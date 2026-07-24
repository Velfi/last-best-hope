package game

import "core:fmt"
import "core:math"
combat_update_contacts :: proc(m: ^Combat_Mission, dt: f32) {
	for &u in m.units[:m.unit_count] {
		if u.disabled || u.extracted do continue
		if u.sensor_mode == .Silent {
			u.active_sensors = false
		} else if u.sensor_mode == .Passive_Watch || u.sensor_mode == .Relay {
			u.active_sensors = combat_doctrine_active_sensors(u)
		} else {
			u.active_sensors = u.sensor_mode == .Active_Search || u.sensor_mode == .Illuminate || u.sensor_mode == .Deceive
		}
		if u.active_sensors {
			u.exposure = min(100, u.exposure + dt * 1.6)
		}
		combat_update_signature(m, &u, dt)
	}
	for observing_side in Combat_Side {
		side_index := combat_side_index(observing_side)
		for receiving_group in 0 ..< COMBAT_GROUP_COUNT {
			for &trace, target_index in m.group_contacts[side_index][receiving_group] {
				target := m.units[target_index]
				if target.side ==
				   observing_side {trace.position = target.position; trace.velocity = target.velocity; trace.observed_acceleration = target.acceleration; trace.last_seen = m.time; trace.age = 0; trace.confidence = 1; trace.error_radius = 0; trace.prediction_uncertainty = 0; trace.identity_confidence = 1; trace.solution_quality = 1; trace.assessment_confidence = 1; trace.last_network_update = m.time; trace.relayed = false; trace.liveness = .Fresh; trace.identity = .Identified; trace.detected = true; continue}
				if target.extracted {trace.detected = false; trace.liveness = .Lost; trace.confidence = 0; continue}
				detected :=
					false; best_margin: f32 = -10000; best_distance: f32 = 100000; identified := false; combined_power: f32 = 0; observers := 0; illuminated := false; local_observer := false; continuous_relay := false
				for observer in m.units[:m.unit_count] {
					if observer.side != observing_side || observer.disabled || observer.extracted do continue
					local := observer.group == receiving_group
					bursting := observer.network_burst_timer > 0
					continuous := observer.communication == .Continuous
					if !local && !bursting && !continuous do continue
					power := combat_sensor_power(observer)
					sharing := local ? f32(.82) : continuous ? f32(1) : f32(.9)
					range :=
						combat_sensor_range(observer) *
						combat_contact_signature(target) *
						sharing *
						power
					if target.exposure > 0 do range *= 1 + target.exposure / 125
					if combat_inside(target.position, m.terrain[0]) do range *= .62
					if combat_inside(target.position, m.terrain[2]) do range *= .78
					for field in m.wreckage_fields[:m.wreckage_field_count] do if combat_distance(target.position, field.center) < field.radius {range *= .7; break}
					distance := combat_distance(
						observer.position,
						target.position,
					); margin := range - distance
					if margin >=
					   0 {detected = true; observers += 1; local_observer = local_observer || local; continuous_relay = continuous_relay || (!local && continuous); combined_power += power * clamp(1 - distance / max(range, f32(1)), .04, 1); illuminated = illuminated || observer.active_sensors; if margin > best_margin do best_margin = margin; best_distance = min(best_distance, distance); if distance < min(range * .48, f32(2000)) || (.Sensors in combat_unit_modules(observer) && distance < min(range * .72, f32(2600))) do identified = true}
				}
				trace.detected = detected
				if detected {
					prior_velocity :=
						trace.velocity; trace.velocity = target.velocity; sample_dt := max(m.time - trace.last_seen, f32(.05)); trace.observed_acceleration = {(target.velocity.x - prior_velocity.x) / sample_dt, (target.velocity.y - prior_velocity.y) / sample_dt, (target.velocity.z - prior_velocity.z) / sample_dt}; accel := math.sqrt(trace.observed_acceleration.x * trace.observed_acceleration.x + trace.observed_acceleration.y * trace.observed_acceleration.y + trace.observed_acceleration.z * trace.observed_acceleration.z); relay_delay := local_observer ? f32(0) : continuous_relay ? f32(.1) : f32(.5); trace.age = relay_delay + combat_light_delay_minutes(best_distance); trace.position = {target.position.x - target.velocity.x * trace.age, target.position.y - target.velocity.y * trace.age, target.position.z - target.velocity.z * trace.age}; trace.last_seen = m.time - trace.age; trace.confidence = clamp(.24 + combined_power * .2 + best_margin / 6000, 0, 1); trace.prediction_uncertainty = clamp(accel * trace.age * .35 / (1 + f32(observers) * .35 + (illuminated ? .8 : 0)), 0, 180); range_error := clamp(best_distance / 18, f32(8), f32(240)); trace.error_radius = clamp(range_error / (combined_power + .35) + trace.prediction_uncertainty, 4, 300); precision := local_observer ? f32(.9) : continuous_relay ? f32(1) : f32(.96); range_precision := clamp(1 - best_distance / 3600, f32(.08), f32(1)); trace.solution_quality = clamp(trace.confidence * (1 - trace.error_radius / 340) * precision * range_precision, 0, 1); trace.identity_confidence = clamp(trace.identity_confidence + dt * combined_power * (illuminated ? .018 : .008), 0, 1); trace.assessment_confidence = clamp(trace.assessment_confidence + dt * combined_power * .006, 0, 1); trace.observer_count = observers; trace.illuminated = illuminated; trace.relayed = !local_observer; trace.last_network_update = m.time; trace.liveness = trace.age <= COMBAT_CONTACT_FRESH_TIME ? .Fresh : .Aging
					if identified ||
					   trace.identity_confidence >=
						   .7 {trace.identity = .Identified} else if trace.identity == .Unknown {trace.identity = .Classification}
					if target.disabled && trace.assessment_confidence >= .65 {
						trace.assessment = .Confirmed_Disabled
					} else if target.hull / target.max_hull < .75 &&
					   trace.assessment_confidence >= .35 {
						trace.assessment = .Apparently_Damaged
					}
				} else if trace.liveness != .Unknown && trace.liveness != .Lost {
					trace.age +=
						dt; trace.confidence = max(0, trace.confidence - dt / COMBAT_CONTACT_LOST_TIME); accel := math.sqrt(trace.observed_acceleration.x * trace.observed_acceleration.x + trace.observed_acceleration.y * trace.observed_acceleration.y + trace.observed_acceleration.z * trace.observed_acceleration.z); trace.prediction_uncertainty = min(260, trace.prediction_uncertainty + dt * (4 + accel * .25)); trace.error_radius = min(300, trace.error_radius + dt * (4 + accel * .25)); trace.solution_quality = max(0, trace.solution_quality - dt * .08); trace.illuminated = false; trace.observer_count = 0; trace.relayed = true
					trace.liveness =
						trace.age <= COMBAT_CONTACT_FRESH_TIME ? .Fresh : trace.age <= COMBAT_CONTACT_STALE_TIME ? .Aging : trace.age <= COMBAT_CONTACT_LOST_TIME ? .Stale : .Lost
				}
			}
		}
		for target_index in 0 ..< m.unit_count {
			best := Combat_Contact_Trace{}
			for group in 0 ..< COMBAT_GROUP_COUNT {
				candidate := m.group_contacts[side_index][group][target_index]
				if candidate.liveness != .Unknown && (best.liveness == .Unknown || candidate.solution_quality > best.solution_quality || candidate.solution_quality == best.solution_quality && candidate.confidence > best.confidence) do best = candidate
			}
			m.contacts[side_index][target_index] = best
		}
	}
	for &u in m.units[:m.unit_count] {if u.engagement_target >= 0 {trace := combat_contact_trace(m, u.side, u.engagement_target); if trace == nil || trace.liveness == .Lost || trace.assessment == .Confirmed_Disabled do u.engagement_target = -1}; if u.denied_target >= 0 {trace := combat_contact_trace(m, u.side, u.denied_target); if trace == nil || trace.liveness == .Lost do u.denied_target = -1}; if u.costly_denied_target >= 0 {trace := combat_contact_trace(m, u.side, u.costly_denied_target); if trace == nil || trace.liveness == .Lost do u.costly_denied_target = -1}}
}

combat_nearest_enemy :: proc(m: ^Combat_Mission, index: int, max_range: f32) -> int {best := -1
	distance := max_range
	u := m.units[index]
	for other, i in m.units[:m.unit_count] {if other.side == u.side || !combat_contact_targetable(m, u.side, i) do continue
		position, _ := combat_contact_position(m, u.side, i)
		d := combat_distance(u.position, position)
		if d < distance {distance = d; best = i}}
	return best}
combat_command_state :: proc(
	m: ^Combat_Mission,
	side: Combat_Side,
) -> Combat_Command_State {active, continuous, burst := false, false, false; for u in m.units[:m.unit_count] do if u.side == side && !u.disabled && !u.extracted {if .Command in combat_unit_modules(u) do active = true; if u.communication == .Continuous do continuous = true; if u.network_burst_timer > 0 do burst = true}
	if active {if continuous do return {report_delay = 0, sensor_sharing = 1, synchronized_precision = 1, captain_autonomy = .25, command_ship_active = true}
		if burst do return {report_delay = .25, sensor_sharing = .9, synchronized_precision = .96, captain_autonomy = .32, command_ship_active = true}
		return{
			report_delay = 0,
			sensor_sharing = .82,
			synchronized_precision = .9,
			captain_autonomy = .45,
			command_ship_active = true,
		}}
	return{
		report_delay = 4,
		sensor_sharing = .72,
		synchronized_precision = .86,
		captain_autonomy = .75,
		command_ship_active = false,
	}}
combat_target_score :: proc(
	m: ^Combat_Mission,
	attacker, target: int,
	priority: Combat_Target_Priority,
) -> f32 {a := m.units[attacker]; t := m.units[target]; perceived, _ :=
		combat_group_contact_position(m, a.side, a.group, target)
	score := 500 - combat_distance(a.position, perceived)
	trace := combat_group_contact_trace(m, a.side, a.group, target)
	identified := trace != nil && trace.identity == .Identified
	// Fighter screens should contest opposing strike craft before committing to
	// slow support hulls. Support remains a fallback when no other track exists.
	if identified && a.role == .Fighter && (t.role == .Recovery || t.role == .Carrier) do score -= 420
	switch
	priority {
	case .Strike_Craft:
		if identified && (t.role == .Fighter || t.role == .Bomber) {score += 900}
		else if identified {score -= 500}
	case .Support:
		if identified && (t.role == .Recovery || t.role == .Carrier) do score += 280
	case .Capital:
		if identified && t.role == .Capital do score += 300
	case .Threats_To_Objective:
		if combat_distance(perceived, m.seedship) < 150 do score += 320
	}
	return score}
combat_best_enemy :: proc(
	m: ^Combat_Mission,
	index: int,
	max_range: f32,
	priority: Combat_Target_Priority,
) -> int {best := -1; best_score: f32 = -10000; side := m.units[index].side; for other, i in m.units[:m.unit_count] {if other.side == side || m.units[index].denied_target == i || !combat_group_contact_targetable(m, side, m.units[index].group, i) do continue
		if priority == .Strike_Craft && m.units[index].role == .Fighter && (other.role == .Recovery || other.role == .Carrier) do continue
		position, _ := combat_group_contact_position(m, side, m.units[index].group, i)
		if combat_distance(m.units[index].position, position) > max_range do continue
		score := combat_target_score(m, index, i, priority)
		trace := combat_group_contact_trace(m, side, m.units[index].group, i)
		score *= trace.confidence
		if score > best_score {best_score = score; best = i}}
	return best}
combat_inside :: proc(p: Combat_Vec3, t: Combat_Terrain) -> bool {return(
		combat_distance(p, t.center) <
		t.radius \
	)}
combat_pressure_state :: proc(u: Combat_Unit) -> string {if u.pressure >= 65 do return "PINNED"
	if u.pressure >= 35 do return "PRESSURED"
	return "STEADY"}
combat_pressure_fire_multiplier :: proc(u: Combat_Unit) -> f32 {if u.pressure >= 65 do return .62
	if u.pressure >= 35 do return .82
	return 1}
combat_pressure_mobility_multiplier :: proc(u: Combat_Unit) -> f32 {
	// A deliberate withdrawal breaks contact instead of trapping a pinned ship.
	if u.order == .Withdraw || u.order == .Extract do return 1.12
	if u.pressure >= 65 do return .52
	if u.pressure >= 35 do return .78
	return 1
}

combat_weapon_class :: proc(u: Combat_Unit, costly: bool) -> Combat_Weapon_Class {
	if costly do return .Heavy_Torpedo
	if .Missiles in combat_unit_modules(u) do return .Guided_Missile
	weapon_package := combat_unit_primary_weapon(u)
	switch weapon_package {case .Guided_Missiles:
		return .Guided_Missile; case .Heavy_Torpedoes:
		return .Heavy_Torpedo; case .Defensive_Laser:
		return .Defensive_Laser; case .Offensive_Laser:
		return .Laser; case .Chemical_Autocannon:
		if .Flak in combat_unit_modules(u) || u.role == .Fighter do return .Defensive_Gun
		return .Kinetic; case .Coilgun_Battery, .Railgun_Battery:
		return .Kinetic; case .Unspecified:
		return .Kinetic}
	return .Kinetic
}

combat_weapon_effectiveness :: proc(
	weapon: Combat_Weapon_Class,
	distance, range: f32,
	target: Combat_Unit,
) -> f32 {
	#partial switch weapon {case .Laser:
		return clamp(1.3 - distance / max(range, f32(1)) * .75, .4, 1.15); case .Kinetic:
		if target.role == .Capital || target.role == .Carrier do return 1.18
		return 1; case .Defensive_Gun, .Defensive_Laser:
		if target.role == .Fighter || target.role == .Bomber do return 1.2; return .72; case:}
	return 1
}

combat_fire_request_needed :: proc(
	m: ^Combat_Mission,
	attacker, target: int,
	costly: bool,
) -> bool {
	if attacker < 0 || attacker >= m.friendly_count do return false
	u := &m.units[attacker]
	if costly && !u.costly_shot_authorized && m.fire_control != .Automatic do return true
	if m.fire_control == .Confirm_Engagements && u.engagement_target != target do return true
	return false
}

combat_request_fire :: proc(m: ^Combat_Mission, attacker, target: int, costly: bool) {
	if m.request_pending do return
	trace := combat_contact_trace(
		m,
		.Friendly,
		target,
	); weapon := combat_weapon_class(m.units[attacker], costly)
	m.request_kind = .Authorize_Fire; m.request_unit = attacker; m.request_target = target; m.request_costly = costly; m.request_timer = 0; m.request_pending = true
	m.request_text = fmt.tprintf(
		"Authorize %s against %s?",
		costly ? "limited ordnance" : "engagement",
		combat_contact_display_name(trace^),
	)
	risk := combat_friendly_fire_risk(m, attacker, target, weapon)
	m.request_consequence = fmt.tprintf(
		"%v · error %.0f · solution %.0f%% · friendly-fire risk %.0f%% · exposure +%.0f",
		weapon,
		trace.error_radius,
		trace.solution_quality * 100,
		risk * 100,
		costly ? 34 : 14,
	)
}

combat_record_group_fire :: proc(m: ^Combat_Mission, source: int) {
	if source < 0 || source >= m.unit_count do return
	u := m.units[source]
	g := combat_group_state(m, u.side, u.group)
	g.last_fired_time = m.time
}

combat_launch_salvo :: proc(
	m: ^Combat_Mission,
	source, target: int,
	weapon: Combat_Weapon_Class,
	strength: f32,
) {
	trace := combat_group_contact_trace(
		m,
		m.units[source].side,
		m.units[source].group,
		target,
	); position, _ := combat_group_contact_position(m, m.units[source].side, m.units[source].group, target); distance := combat_distance(m.units[source].position, position); profile := combat_weapon_profile(weapon); speed := combat_km_to_units(profile.projectile_speed_km_s * COMBAT_SECONDS_PER_TIME_UNIT)
	origin :=
		m.units[source].position; dx := position.x - origin.x; dy := position.y - origin.y; dz := position.z - origin.z; direction_scale := distance > 0 ? speed / distance : f32(0)
	seeker := weapon == .Kinetic || weapon == .Spinal_Kinetic ? Combat_Seeker.None : Combat_Seeker(
		1 +
		int(
			combat_mix(
				m.seed ~ u64(source + 1) * 31 ~ u64(target + 1) * 131 ~ u64(m.event_serial),
			) %
			3,
		),
	)
	value := Combat_Salvo {
		source         = source,
		target         = target,
		side           = m.units[source].side,
		weapon         = weapon,
		seeker         = seeker,
		position       = origin,
		velocity       = {dx * direction_scale, dy * direction_scale, dz * direction_scale},
		target_volume  = position,
		time_remaining = max(.5, combat_weapon_flight_minutes(weapon, distance)),
		speed          = speed,
		strength       = strength * clamp(m.units[source].subsystems.weapons / 100, f32(.2), f32(1)),
		guidance       = trace.solution_quality,
		last_guidance  = m.time,
		phase          = .Boost,
		weapons_launched = weapon == .Heavy_Torpedo ? 2 : weapon == .Kinetic ? 12 : 8,
		weapons_surviving = weapon == .Heavy_Torpedo ? 2 : weapon == .Kinetic ? 12 : 8,
		delta_v_remaining_km_s = weapon == .Heavy_Torpedo ? 18 : 9,
		launch_time = m.time,
		arrival_earliest = m.time + max(.5, combat_weapon_flight_minutes(weapon, distance) * .9),
		arrival_latest = m.time + max(.5, combat_weapon_flight_minutes(weapon, distance) * 1.1),
		active         = true,
	}; reused :=
		false; for &salvo in m.salvos do if !salvo.active {salvo = value; reused = true; break}; if !reused {if len(m.salvos) >= COMBAT_MAX_SALVOS do return; append(&m.salvos, value)}; m.salvo_count = len(m.salvos)
	m.units[source].exposure = min(
		100,
		m.units[source].exposure + (weapon == .Heavy_Torpedo ? 34 : 18),
	); m.units[source].weapon_heat = min(100, m.units[source].weapon_heat + profile.heat_per_shot); m.units[source].weapon_flash = .5
	combat_record_group_fire(m, source)
}

combat_update_salvos :: proc(m: ^Combat_Mission, dt: f32) {
	for &salvo in m.salvos {if !salvo.active do continue
		salvo.time_remaining = max(
			0,
			salvo.time_remaining - dt,
		); total_window := max(salvo.arrival_latest - salvo.launch_time, f32(.5)); elapsed := m.time - salvo.launch_time; fraction := clamp(elapsed / total_window, 0, 1); salvo.phase = fraction < .08 ? .Boost : fraction < .72 ? .Cruise : fraction < .9 ? .Search : .Terminal; trace := combat_contact_trace(m, salvo.side, salvo.target)
		if trace != nil &&
		   combat_contact_targetable(
			   m,
			   salvo.side,
			   salvo.target,
		   ) {position, _ := combat_contact_position(m, salvo.side, salvo.target); salvo.target_volume = position; salvo.guidance = max(salvo.guidance, trace.solution_quality); salvo.last_guidance = m.time} else {salvo.guidance = max(.12, salvo.guidance - dt * .09)}
		before :=
			salvo.position; dx := salvo.target_volume.x - before.x; dy := salvo.target_volume.y - before.y; dz := salvo.target_volume.z - before.z; distance := math.sqrt(dx * dx + dy * dy + dz * dz)
		step := min(
			salvo.speed * dt,
			distance,
		); if distance > .001 {salvo.velocity = {dx / distance * salvo.speed, dy / distance * salvo.speed, dz / distance * salvo.speed}; salvo.position = {before.x + dx / distance * step, before.y + dy / distance * step, before.z + dz / distance * step}}
		hit_index := -1; hit_fraction: f32 = 2
		for unit, index in m.units[:m.unit_count] {if index == salvo.source || unit.disabled || unit.extracted do continue
			radius :=
				combat_element_separation_radius(unit) *
				.7; segment := Combat_Vec3{salvo.position.x - before.x, salvo.position.y - before.y, salvo.position.z - before.z}; to_unit := Combat_Vec3{unit.position.x - before.x, unit.position.y - before.y, unit.position.z - before.z}; denom := segment.x * segment.x + segment.y * segment.y + segment.z * segment.z
			fraction: f32 = 0; if denom > .0001 do fraction = clamp((to_unit.x * segment.x + to_unit.y * segment.y + to_unit.z * segment.z) / denom, 0, 1)
			closest := Combat_Vec3 {
				before.x + segment.x * fraction,
				before.y + segment.y * fraction,
				before.z + segment.z * fraction,
			}
			if combat_distance(closest, unit.position) <= radius &&
			   fraction < hit_fraction {hit_index = index; hit_fraction = fraction}
		}
		if hit_index >=
		   0 {target := &m.units[hit_index]; salvo.position = {before.x + (salvo.position.x - before.x) * hit_fraction, before.y + (salvo.position.y - before.y) * hit_fraction, before.z + (salvo.position.z - before.z) * hit_fraction}
			threshold: f32 = .62; switch target.doctrine {case .Cautious_Screen:
				threshold = .32; case .Balanced:
				threshold = .48; case .Hunter_Killer:
				threshold = .72; case .Last_Stand:
				threshold = .82}
			if salvo.guidance >= threshold &&
			   target.defense_cooldown <=
				   0 {if salvo.seeker == .Radar && target.chaff > 0 && .Chaff in target.defense_packages {target.chaff -= 1; salvo.soft_kill += .42; target.defense_response = "Chaff broke radar lock"} else if salvo.seeker == .Infrared && target.flares > 0 && .Thermal_Flares in target.defense_packages {target.flares -= 1; salvo.soft_kill += .38; target.defense_response = "Thermal flares displaced the seeker"} else if target.decoys > 0 && .Active_Decoys in target.defense_packages {target.decoys -= 1; salvo.soft_kill += .32; target.defense_response = "Active decoy drew the seeker"}; target.defense_cooldown = 4}
			if .ECM in target.defense_packages ||
			   combat_nearby_module(m, target.side, target.position, .Electronic_Warfare, 150) ||
			   combat_nearby_module(
				   m,
				   target.side,
				   target.position,
				   .Active_Defense,
				   130,
			   ) {salvo.soft_kill += .18; target.defense_response = "ECM displaced the track"}
			for defender in m.units[:m.unit_count] do if defender.side == target.side && !defender.disabled && !defender.extracted && combat_distance(defender.position, target.position) < 120 {if .Defensive_Lasers in defender.defense_packages {salvo.hard_kill += .22} else if .Defensive_Guns in defender.defense_packages || .Flak in combat_unit_modules(defender) {salvo.hard_kill += .16}; if defender.role == .Fighter do salvo.hard_kill += .08}
			salvo.hard_kill = clamp(
				salvo.hard_kill,
				0,
				.72,
			); salvo.evasion += clamp(target.speed / 180 * (target.readiness / 100), .04, .3); mask: f32 = 1; if combat_inside(target.position, m.terrain[0]) do mask = .65
			survival_fraction := (1 - clamp(salvo.soft_kill, 0, .8)) * (1 - salvo.hard_kill)
			salvo.weapons_surviving = clamp(
				int(math.ceil(f64(f32(salvo.weapons_launched) * survival_fraction))),
				0,
				salvo.weapons_launched,
			)
			effective :=
				salvo.guidance *
				mask *
				(1 - clamp(salvo.soft_kill, 0, .8)) *
				(1 - salvo.hard_kill) *
				(1 -
						clamp(
							salvo.evasion,
							0,
							.65,
						)); wave_fraction := f32(salvo.weapons_surviving) / f32(max(salvo.weapons_launched, 1)); damage := salvo.strength * wave_fraction * clamp(effective, .04, 1)
			if effective <
			   .1 {salvo.active = false; if salvo.weapon != .Guided_Missile do combat_add_event_at(m, target.defense_response != "" ? target.defense_response : "Terminal evasion cleared the intercept volume", salvo.position); continue}
			was_active := !target.disabled; combat_apply_damage(m, hit_index, damage); target.impact_flash = .45; target.defense_response = "Terminal evasion failed"; salvo.active = false
			if target.side ==
			   salvo.side {combat_add_event_at(m, "Friendly formation struck by an allied salvo", salvo.position)} else if salvo.weapon == .Guided_Missile {combat_report_guided_hit(m, salvo, was_active && target.disabled ? "Guided-missile burst disabled a contact; assessment pending" : "Guided-missile burst hit; damage unassessed", salvo.position)} else if was_active && target.disabled {combat_add_event_at(m, "Contact disabled; assessment pending", salvo.position)} else {combat_add_event_at(m, "Salvo impact observed; damage unassessed", salvo.position)}
		} else if distance <= step + .001 ||
		   salvo.time_remaining <=
			   0 {salvo.active = false; if salvo.weapon != .Guided_Missile do combat_add_event_at(m, "Salvo missed its tracked volume", salvo.target_volume)}
	}
	// Keep the aggregate list proportional to the salvos still in flight. Stable
	// compaction preserves deterministic presentation order while preventing
	// resolved salvos from turning every later simulation tick into a scan of
	// historical projectiles.
	write_index := 0
	for read_index in 0 ..< len(m.salvos) {
		if !m.salvos[read_index].active do continue
		if write_index != read_index do m.salvos[write_index] = m.salvos[read_index]
		write_index += 1
	}
	resize(&m.salvos, write_index)
	m.salvo_count = write_index
}
combat_apply_weapon_pressure :: proc(m: ^Combat_Mission, attacker, target: int, weight: f32 = 1) {
	if attacker < 0 || attacker >= m.unit_count || target < 0 || target >= m.unit_count do return
	a := m.units[attacker]; t := &m.units[target]; if t.disabled || t.extracted do return
	// Rapid screens disrupt firing solutions; heavy hulls impose shock. Debris
	// and wreckage provide the close-engagement equivalent of directional cover.
	gain: f32 = 7 * weight
	#partial switch a.role {case .Fighter:
		gain *= 1.35; case .Corvette:
		gain *= 1.18; case .Capital:
		gain *= 1.45; case .Bomber:
		gain *= .8; case:}
	masked := combat_inside(
		t.position,
		m.terrain[0],
	); if !masked {for field in m.wreckage_fields[:m.wreckage_field_count] do if combat_distance(t.position, field.center) < field.radius {masked = true; break}}
	if masked do gain *= .58
	t.pressure = clamp(t.pressure + gain, 0, 100)
}
combat_nearby_module :: proc(
	m: ^Combat_Mission,
	side: Combat_Side,
	position: Combat_Vec3,
	module: Ship_Module,
	radius: f32,
) -> bool {for u in m.units[:m.unit_count] {if u.side != side || u.disabled || u.extracted || combat_distance(u.position, position) > radius do continue
		if module in combat_unit_modules(u) do return true}
	return false}

combat_repair_element :: proc(m: ^Combat_Mission, element: int, amount: f32) {
	if element < 0 || element >= m.unit_count || amount <= 0 do return; u := &m.units[element]; if u.disabled || u.hull >= u.max_hull do return
	remaining := min(
		amount,
		u.max_hull - u.hull,
	); start := u.roster_start; end := start + u.formation_ships
	for &ship in m.ships[start:end] {if remaining <= 0 do break; if ship.hull <= 0 do continue; individual_max := u.max_hull / f32(max(u.formation_ships, 1)); repair := min(individual_max - ship.hull, remaining); if repair > 0 {ship.hull += repair; u.hull += repair; remaining -= repair}}
}

combat_apply_specialist_support :: proc(m: ^Combat_Mission) {
	for &support, support_index in m.units[:m.unit_count] {if support.disabled || support.extracted do continue
		if .Repair in
		   combat_unit_modules(
			   support,
		   ) {best := -1; missing: f32 = 0; for ally, i in m.units[:m.unit_count] {if ally.side != support.side || ally.disabled || ally.extracted || combat_distance(ally.position, support.position) > 95 do continue; gap := ally.max_hull - ally.hull; if gap > missing {missing = gap; best = i}}; if best >= 0 {combat_repair_element(m, best, .7); m.units[best].readiness = min(100, m.units[best].readiness + .25)}}
		if .Mines in
		   combat_unit_modules(
			   support,
		   ) {target := -1; for enemy, i in m.units[:m.unit_count] do if enemy.side != support.side && !enemy.disabled && !enemy.extracted && combat_distance(enemy.position, support.position) < 72 {target = i; break}; if target >= 0 do combat_apply_damage(m, target, 1.1)}
		_ = support_index
	}
}
combat_response_multiplier :: proc(attacker, target: Combat_Unit) -> f32 {
	mult: f32 = 1
	// Soft response bonuses implement the roster's counter relationships. They
	// are intentionally smaller than attack-run, terrain, and flanking effects.
	switch attacker.operational_role {
	case .Interceptor:
		if target.operational_role == .Scout || target.operational_role == .Bomber || target.operational_role == .Assault_Shuttle do mult *= 1.22
	case .Fighter:
		if target.hull_archetype == .Bomber || target.hull_archetype == .Assault_Shuttle do mult *= 1.16
	case .Flak_Frigate:
		if ship_hull_archetype_family(target.hull_archetype) == .Strike_Craft do mult *= 1.24
	case .Corvette:
		if ship_hull_archetype_family(target.hull_archetype) == .Strike_Craft do mult *= 1.14
	case .Gunship:
		if target.hull_archetype == .Corvette || target.hull_archetype == .Torpedo_Boat do mult *= 1.2
	case .Strike_Fighter:
		if ship_hull_archetype_family(target.hull_archetype) == .Light_Combatant || ship_hull_archetype_family(target.hull_archetype) == .Frigate do mult *= 1.15
	case .Destroyer:
		if ship_hull_archetype_family(target.hull_archetype) == .Frigate do mult *= 1.2
	case .Bomber, .Torpedo_Boat:
		if ship_hull_archetype_family(target.hull_archetype) == .Line_Warship || target.hull_archetype == .Carrier do mult *= 1.2
	case .Battlecruiser, .Battleship:
		if target.hull_archetype == .Light_Cruiser || target.hull_archetype == .Heavy_Cruiser || target.hull_archetype == .Destroyer do mult *= 1.15
	case .Patrol_Boat,
	     .Picket_Ship,
	     .Missile_Frigate,
	     .Electronic_Warfare_Frigate,
	     .Shield_Frigate,
	     .Support_Frigate,
	     .Minelayer_Frigate,
	     .Light_Cruiser,
	     .Heavy_Cruiser,
	     .Dreadnought,
	     .Escort_Carrier,
	     .Fleet_Carrier,
	     .Command_Ship,
	     .Courier,
	     .Freighter,
	     .Tanker,
	     .Fabricator_Ship,
	     .Recovery_Tug,
	     .Hospital_Ship,
	     .Habitat_Ship,
	     .Colony_Transport,
	     .Seedship,
	     .Generation_Ship,
	     .Arkship,
	     .Assault_Shuttle,
	     .Scout,
	     .Unspecified:
	}
	return mult
}
combat_damage_multiplier :: proc(
	m: ^Combat_Mission,
	attacker, target: ^Combat_Unit,
) -> f32 {command := combat_command_state(m, attacker.side); mult :=
		combat_response_multiplier(attacker^, target^) *
		command.synchronized_precision *
		combat_pressure_fire_multiplier(attacker^)
	if combat_nearby_module(m, target.side, target.position, .Active_Defense, 115) do mult *= .84
	if combat_nearby_module(m, target.side, target.position, .Electronic_Warfare, 150) do mult *= .9
	masked := combat_inside(target.position, m.terrain[0])
	if !masked {for field in m.wreckage_fields[:m.wreckage_field_count] do if combat_distance(target.position, field.center) < field.radius {masked = true; break}}
	if masked {if attacker.role == .Bomber {mult *= .55}
		else {mult *= .78}}
	if combat_inside(attacker.position, m.terrain[1]) && attacker.role == .Capital do mult *= 1.22
	return mult}
