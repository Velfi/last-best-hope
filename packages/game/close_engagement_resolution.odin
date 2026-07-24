package game

import "core:fmt"
import "core:math"

combat_angle_delta :: proc(a, b: f32) -> f32 {d := b - a; for d > 3.14159 do d -= 6.28318; for d < -3.14159 do d += 6.28318
	return d}
combat_capital_arc_multiplier :: proc(attacker, target: Combat_Unit) -> f32 {bearing := f32(
		math.atan2(
			f64(attacker.position.y - target.position.y),
			f64(attacker.position.x - target.position.x),
		),
	)
	return math.abs(combat_angle_delta(target.facing + math.PI, bearing)) < .7 ? 1.7 : 1}
combat_move_toward :: proc(
	u: ^Combat_Unit,
	p: Combat_Vec3,
	dt: f32,
	target_velocity: Combat_Vec3 = {},
) {dx := p.x - u.position.x
	dy := p.y - u.position.y
	dz := p.z - u.position.z
	d := math.sqrt(dx * dx + dy * dy + dz * dz)
	desired := f32(math.atan2(f64(dy), f64(dx)))
	burn_factor: f32 = 1
	if u.combat_burn && !u.silent_running && u.burn_heat < 100 && u.readiness > 8 do burn_factor = 1.65
	turn := clamp(
		combat_angle_delta(u.facing, desired),
		-u.turn_rate * u.turn_authority * burn_factor * dt,
		u.turn_rate * u.turn_authority * burn_factor * dt,
	)
	u.facing += turn
	speed := u.speed * combat_pressure_mobility_multiplier(u^) * burn_factor
	if u.silent_running do speed = min(speed, u.speed * .55)
	// Brake before the destination instead of stopping or reversing velocity
	// instantaneously. The drive's thrust-to-mass acceleration sets the
	// reachable arrival speed.
	acceleration_limit :=
		u.max_acceleration * burn_factor * clamp(u.subsystems.engines / 100, f32(.2), f32(1))
	arrival_speed := f32(math.sqrt(f64(max(2 * acceleration_limit * d, 0))))
	speed = min(speed, arrival_speed)
	if d < .01 do speed = 0
	desired_velocity := target_velocity
	if d >= .01 {
		desired_velocity.x += dx / d * speed
		desired_velocity.y += dy / d * speed
		desired_velocity.z += dz / d * speed
	}
	dvx, dvy, dvz :=
		desired_velocity.x -
		u.velocity.x,
		desired_velocity.y -
		u.velocity.y,
		desired_velocity.z -
		u.velocity.z
	dv := math.sqrt(dvx * dvx + dvy * dvy + dvz * dvz); limit := acceleration_limit * dt
	if dv > limit && dv > 0 {scale := limit / dv; dvx *= scale; dvy *= scale; dvz *= scale}
	u.acceleration = {dvx / max(dt, f32(.001)), dvy / max(dt, f32(.001)), dvz / max(dt, f32(.001))}
	u.velocity.x += dvx; u.velocity.y += dvy; u.velocity.z += dvz
	step_x, step_y, step_z := u.velocity.x * dt, u.velocity.y * dt, u.velocity.z * dt
	step := math.sqrt(step_x * step_x + step_y * step_y + step_z * step_z)
	u.position.x += step_x; u.position.y += step_y; u.position.z += step_z
	if burn_factor >
	   1 {u.burn_heat = min(100, u.burn_heat + dt * 18); u.readiness = max(0, u.readiness - dt * .7)} else {u.burn_heat = max(0, u.burn_heat - dt * 11)}
}

combat_element_separation_radius :: proc(u: Combat_Unit) -> f32 {
	// Command elements stand in for whole formations. Give larger formations
	// more room, while bounding the radius so mass battles remain maneuverable.
	return clamp(math.sqrt(f32(max(u.formation_active, 1))) * 2, 12, 40)
}

combat_separate_units :: proc(m: ^Combat_Mission, dt: f32) {
	// Movement orders often send several elements to the exact same objective.
	// Resolve those overlaps symmetrically after steering so neither element
	// gets privileged and the simulation remains deterministic for a seed.
	for left in 0 ..< m.unit_count {
		a := &m.units[left]
		if a.disabled || a.extracted do continue
		for right in left + 1 ..< m.unit_count {
			b := &m.units[right]
			if b.disabled || b.extracted do continue
			dx := b.position.x - a.position.x
			dy := b.position.y - a.position.y
			dz := b.position.z - a.position.z
			distance := math.sqrt(dx * dx + dy * dy + dz * dz)
			clearance :=
				combat_element_separation_radius(a^) + combat_element_separation_radius(b^)
			if distance >= clearance do continue
			if distance < .001 {
				// Stable pair-derived direction prevents coincident elements from
				// choosing a random escape vector or always separating on one axis.
				pair_seed := combat_mix(m.seed ~ (u64(left + 1) << 32) ~ u64(right + 1))
				azimuth := f64(pair_seed & 0xffff) / 65535 * math.PI * 2
				z := f32((pair_seed >> 16) & 0xffff) / 65535 * 2 - 1
				planar := f32(math.sqrt(f64(max(1 - z * z, 0))))
				dx = f32(math.cos(azimuth)) * planar
				dy = f32(math.sin(azimuth)) * planar
				dz = z
				distance = 1
			}
			push := min((clearance - distance) * dt * 4, f32(3)) * .5
			nx, ny, nz := dx / distance, dy / distance, dz / distance
			a.position.x -= nx * push
			a.position.y -= ny * push
			a.position.z -= nz * push
			b.position.x += nx * push
			b.position.y += ny * push
			b.position.z += nz * push
		}
	}
}

combat_ship_world_position :: proc(m: ^Combat_Mission, element, member: int) -> Combat_Vec3 {
	u :=
		m.units[element]; id := combat_ship_id(m.seed, element, member); angle := f32(id & 0xffff) / 65535 * 6.283185; layer := f32((id >> 16) & 0xffff) / 65535 * 2 - 1
	radius :=
		math.sqrt(f32(max(u.formation_ships, 1))) *
		3.2 *
		(.45 + f32((id >> 32) & 0xffff) / 65535 * .55) *
		(u.cohesion / 100 * .55 + .45)
	return {
		u.position.x + f32(math.cos(f64(angle))) * radius,
		u.position.y + f32(math.sin(f64(angle))) * radius,
		u.position.z + layer * radius * .55,
	}
}

combat_point_segment_distance :: proc(p, a, b: Combat_Vec3) -> f32 {ab := Combat_Vec3 {
		b.x - a.x,
		b.y - a.y,
		b.z - a.z,
	}
	ap := Combat_Vec3{p.x - a.x, p.y - a.y, p.z - a.z}
	denom := ab.x * ab.x + ab.y * ab.y + ab.z * ab.z
	if denom <= .0001 do return combat_distance(p, a)
	t := clamp((ap.x * ab.x + ap.y * ab.y + ap.z * ab.z) / denom, 0, 1)
	return combat_distance(p, {a.x + ab.x * t, a.y + ab.y * t, a.z + ab.z * t})}

combat_reconcile_element :: proc(m: ^Combat_Mission, element: int) {u := &m.units[element]
	hull: f32
	active := 0
	for ship in m.ships[u.roster_start:u.roster_start + u.formation_ships] {hull += ship.hull; if ship.hull > 0 do active += 1}
	u.hull = hull
	u.formation_active = active
	u.disabled = active == 0
	if u.disabled do u.cohesion = 0}

combat_finale_select_lock :: proc(m: ^Combat_Mission) -> int {best := -1; best_score: f32 = -1; for u, i in m.units[:m.friendly_count] {if u.disabled || u.extracted do continue
		weight: f32 = 1
		#partial switch
		u.role {case .Capital:
			weight = 8; case .Carrier:
			weight = 6; case .Bomber:
			weight = 2; case:}
		score := f32(u.formation_active) * weight + u.readiness * .01
		if score > best_score {best_score = score; best = i}}
	return best}

combat_finale_fire_beam :: proc(m: ^Combat_Mission) {asset := &m.strategic_asset
	if asset.disabled do return
	start := asset.position
	dx := asset.beam_aim.x - start.x
	dy := asset.beam_aim.y - start.y
	dz := asset.beam_aim.z - start.z
	length := math.sqrt(dx * dx + dy * dy + dz * dz)
	if length < 1 do return
	finish := Combat_Vec3 {
		asset.beam_aim.x + dx / length * 500,
		asset.beam_aim.y + dy / length * 500,
		asset.beam_aim.z + dz / length * 500,
	}
	hit := 0
	for &u, element in m.units[:m.unit_count] {if u.disabled || u.extracted do continue; active_before := u.formation_active
		loss_position := u.position
		individual_max := u.max_hull / f32(max(u.formation_ships, 1))
		changed := false
		for &ship, member in m.ships[u.roster_start:u.roster_start + u.formation_ships] {if ship.hull <= 0 do continue; p := combat_ship_world_position(m, element, member)
			if combat_point_segment_distance(p, start, finish) > 45 do continue
			damage := individual_max * .7
			if u.role == .Fighter || u.role == .Bomber do damage = individual_max
			ship.hull = max(0, ship.hull - damage)
			hit += 1
			changed = true}
		if changed {combat_reconcile_element(m, element); combat_record_wreckage(m, element, max(active_before - u.formation_active, 0), loss_position)
			u.cohesion = max(0, u.cohesion - 22)
			u.readiness = max(0, u.readiness - 15)
			u.impact_flash = 1}}
	asset.shots_fired += 1
	asset.ships_hit += hit
	asset.beam_flash = 1.2
	asset.locked = false
	asset.lock_target = -1
	combat_add_event(m, "Citadel beam crossed every hull remaining in its firing corridor.")
}

combat_finale_update :: proc(m: ^Combat_Mission, dt: f32) {asset := &m.strategic_asset
	if asset.beam_flash > 0 do asset.beam_flash = max(0, asset.beam_flash - dt)
	if !asset.disabled &&
	   asset.exposure_remaining <= 0 &&
	   m.relay_progress[0] >= 100 &&
	   m.relay_progress[1] >=
		   100 {m.relays_synchronized = true; asset.exposure_remaining = 60; m.relay_progress = {}
		m.finale_phase = .Exposed_Strike
		combat_add_event(
			m,
			"Both targeting relays are under coalition control. The weapon shield opened.",
		)}
	if asset.exposure_remaining >
	   0 {asset.exposure_remaining = max(0, asset.exposure_remaining - dt)
		strike_elements := 0
		for u in m.units[:m.friendly_count] do if !u.disabled && !u.extracted && (u.role == .Bomber || .Torpedoes in combat_unit_modules(u)) && combat_distance(u.position, asset.position) < 160 do strike_elements += 1
		if strike_elements >
		   0 {asset.disable_progress = min(100, asset.disable_progress + dt * f32(strike_elements) * 1.4)
			if asset.disable_progress >= 100 && !asset.disabled {asset.disabled = true
				asset.locked = false
				combat_add_event_at(
					m,
					"Strike formations disabled the Citadel weapon",
					asset.position,
				)}}} else if !asset.disabled {asset.charge += dt; if !asset.locked && asset.charge >= COMBAT_FINALE_BEAM_CYCLE - COMBAT_FINALE_BEAM_LOCK {target := combat_finale_select_lock(m)
			if target >=
			   0 {asset.locked = true; asset.lock_target = target; asset.beam_aim = m.units[target].position
				combat_add_event_at(
					m,
					"Citadel firing corridor locked on a coalition formation",
					asset.beam_aim,
				)}}
		if asset.charge >= COMBAT_FINALE_BEAM_CYCLE {asset.charge -= COMBAT_FINALE_BEAM_CYCLE
			combat_finale_fire_beam(m)}}
	if m.time >=
	   COMBAT_FINALE_WITHDRAWAL {m.finale_phase = .Withdrawal} else if asset.exposure_remaining > 0 {m.finale_phase = .Exposed_Strike} else if m.time >= 240 {m.finale_phase = .Relay_Assault} else if m.time >= 60 {m.finale_phase = .Line_Engagement} else {m.finale_phase = .Approach}
}

combat_reassign_recovery_element :: proc(m: ^Combat_Mission) -> bool {
	previous := clamp(m.recovery_unit, 0, m.friendly_count - 1)
	best, best_score := -1, -1
	for unit, index in m.units[:m.friendly_count] {
		if unit.disabled || unit.extracted || index == previous do continue
		score :=
			skirmish_recovery_score(unit.role, combat_unit_modules(unit)) * 1000 +
			int(unit.hull / max(unit.max_hull, f32(1)) * 100) * 10 +
			unit.formation_active
		if score > best_score {
			best = index
			best_score = score
		}
	}
	if best < 0 do return false
	m.recovery_unit = best
	for &unit in m.units[:m.friendly_count] do if unit.guard == previous do unit.guard = best
	combat_add_event_at(
		m,
		fmt.tprintf("%s assumed recovery duty after %s was disabled", m.units[best].name, m.units[previous].name),
		m.units[best].position,
	)
	return true
}

combat_launch_recon_probe :: proc(
	m: ^Combat_Mission,
	launcher: int,
	destination: Combat_Vec3,
) -> bool {
	if m == nil ||
	   !m.skirmish ||
	   m.skirmish_setup.mission != .Reconnaissance ||
	   launcher < 0 ||
	   launcher >= m.friendly_count {
		return false
	}
	u := &m.units[launcher]
	if u.disabled ||
	   u.extracted ||
	   u.recon_probes <= 0 ||
	   m.recon_probe.status == .In_Flight ||
	   m.recon_probe.status == .Scanning {
		return false
	}
	u.recon_probes -= 1
	m.recon_probes_launched += 1
	m.recon_probe = {
		status      = .In_Flight,
		launcher    = launcher,
		position    = u.position,
		destination = destination,
		hull        = 18,
		max_hull    = 18,
		speed       = 180,
		scan_rate   = 8,
	}
	combat_add_event_at(
		m,
		fmt.tprintf("%s launched a reconnaissance probe", u.name),
		u.position,
	)
	return true
}

combat_update_recon_probe :: proc(m: ^Combat_Mission, dt: f32) {
	if m == nil ||
	   (m.recon_probe.status != .In_Flight && m.recon_probe.status != .Scanning) {
		return
	}
	probe := &m.recon_probe
	if probe.status == .In_Flight {
		dx := probe.destination.x - probe.position.x
		dy := probe.destination.y - probe.position.y
		dz := probe.destination.z - probe.position.z
		distance := math.sqrt(dx * dx + dy * dy + dz * dz)
		if distance <= 60 {
			probe.status = .Scanning
		} else if distance > 0 {
			step := min(probe.speed * dt, distance)
			probe.position.x += dx / distance * step
			probe.position.y += dy / distance * step
			probe.position.z += dz / distance * step
		}
	}
	threat: f32
	probe.detected = false
	for unit in m.units[m.friendly_count:m.unit_count] do if !unit.disabled &&
	   !unit.extracted {
		distance := combat_distance(unit.position, probe.position)
		if distance < 220 do probe.detected = true
		if distance < 130 do threat += max(unit.damage, f32(1)) * .12
	}
	if probe.detected && threat > 0 {
		probe.hull = max(0, probe.hull - threat * dt)
		if probe.hull <= 0 {
			probe.status = .Destroyed
			m.recon_probes_lost += 1
			combat_add_event_at(m, "Hostile fire destroyed the reconnaissance probe", probe.position)
			return
		}
	}
	if probe.status == .Scanning {
		m.anomaly_progress = min(
			100,
			m.anomaly_progress + dt * COMBAT_ANOMALY_RATE * probe.scan_rate,
		)
		if m.anomaly_progress >= 100 {
			probe.status = .Complete
			m.recon_probes_completed += 1
			combat_add_event_at(m, "Reconnaissance probe completed the anomaly scan", probe.position)
		}
	}
}

combat_tick_fixed :: proc(m: ^Combat_Mission, dt: f32) {
	if m.complete || (m.request_pending && m.request_kind == .Authorize_Fire) do return; m.time += dt
	if m.scenario != .Finale {
		m.seedship.x += m.seedship_velocity.x * dt
		m.seedship.y += m.seedship_velocity.y * dt
		m.seedship.z += m.seedship_velocity.z * dt
		for &relay, i in m.relays {
			relay.x += m.relay_velocity[i].x * dt
			relay.y += m.relay_velocity[i].y * dt
			relay.z += m.relay_velocity[i].z * dt
			if i < m.interaction_count do m.interactions[i].position = relay
		}
		if m.interaction_count > 2 do m.interactions[2].position = m.seedship
		if m.skirmish_recovery_profile == .Drifting_Target &&
		   (m.skirmish_setup.mission == .Disabled_Ship_Rescue ||
			   m.skirmish_setup.mission == .Repair_And_Tow) {
			target := clamp(m.objective_unit, 0, m.friendly_count - 1)
			if m.units[target].disabled {
				m.units[target].position.x += m.recovery_target_velocity.x * dt
				m.units[target].position.y += m.recovery_target_velocity.y * dt
				m.units[target].position.z += m.recovery_target_velocity.z * dt
				for &interaction in m.interactions[:m.interaction_count] do if interaction.target == target {
					interaction.position = m.units[target].position
				}
			}
		}
	}
	combat_update_contacts(m, dt)
	combat_update_salvos(m, dt)
	combat_update_recon_probe(m, dt)
	m.planning_accumulator += dt
	if m.planning_accumulator >=
	   1 {m.planning_accumulator -= 1; combat_plan_groups(m); combat_operation_execute_contingencies(m); combat_operation_advance_routes(m); combat_operation_propose_ability(m); combat_apply_specialist_support(m); for &u in m.units[:m.unit_count] do if !u.disabled && !u.extracted && ship_hull_archetype_family(u.hull_archetype) == .Strike_Craft && !combat_nearby_module(m, u.side, u.position, .Flight_Deck, 520) do u.readiness = max(0, u.readiness - .35)}
	if m.ability_flash > 0 do m.ability_flash = max(0, m.ability_flash - dt)
	if m.ability_pending {m.ability_timer = max(0, m.ability_timer - dt); if m.ability_timer == 0 do combat_resolve_capital_ability(m)}
	withdrawal_time :=
		m.scenario == .Finale ? COMBAT_FINALE_WITHDRAWAL : f32(1260); duration := combat_mission_duration(m)
	if m.time >= withdrawal_time &&
	   !m.extraction_mandatory {m.extraction_mandatory = true; m.phase = .Extraction; combat_add_event(m, "Navigation window closing. Extraction is mandatory.")}
	if m.time >=
	   duration -
		   60 {for &u, i in m.units[:m.unit_count] do if !u.disabled && !u.extracted do combat_apply_damage(m, i, dt * (m.time - (duration - 60)) * .035)}
	for i in 0 ..< m.unit_count {u := &m.units[i]; if u.disabled || u.extracted do continue
		if u.ability_cooldown > 0 do u.ability_cooldown = max(0, u.ability_cooldown - dt)
		if u.defense_cooldown > 0 do u.defense_cooldown = max(0, u.defense_cooldown - dt)
		if u.weapon_cooldown > 0 do u.weapon_cooldown = max(0, u.weapon_cooldown - dt)
		u.weapon_heat = max(
			0,
			u.weapon_heat - dt * 1.5 * clamp(u.subsystems.radiators / 100, f32(.15), f32(1)),
		)
		if u.weapon_flash > 0 do u.weapon_flash = max(0, u.weapon_flash - dt); if u.impact_flash > 0 do u.impact_flash = max(0, u.impact_flash - dt)
		pressure_decay: f32 = 4; if combat_inside(u.position, m.terrain[0]) do pressure_decay = 8; for field in m.wreckage_fields[:m.wreckage_field_count] do if combat_distance(u.position, field.center) < field.radius {pressure_decay = 8; break}; if u.order == .Withdraw || u.order == .Extract do pressure_decay = 18; u.pressure = max(0, u.pressure - pressure_decay * dt)
		if combat_inside(
			u.position,
			m.terrain[2],
		) {was_active := !u.disabled; combat_apply_damage(m, i, dt * (m.complication == .Radiation_Surge ? 2.2 : .7)); if was_active && u.disabled {combat_add_event_at(m, "Radiation disabled a command element", u.position); continue}}
		if u.side == .Friendly {
			g := combat_group_state(m, u.side, u.group)
			threshold, pursuit, priority := combat_doctrine_rules(u.doctrine)
			if u.stance == .Screen ||
			   u.order == .Intercept {priority = .Strike_Craft; pursuit = min(pursuit, 180)}
			if u.stance == .Evade do pursuit = 0
			if u.hull / u.max_hull * 100 < threshold &&
			   u.order !=
				   .Recover {u.withdrawing = true; u.order = .Withdraw; u.destination = m.extraction}
			if m.extraction_mandatory &&
			   u.order != .Extract &&
			   u.doctrine !=
				   .Last_Stand {u.order = .Extract; u.destination = m.extraction; u.action = .Extracting}
			switch u.order {
			case .Move, .Control, .Intercept, .Withdraw, .Extract:
				combat_move_toward(u, u.destination, dt)
				u.action =
					u.order == .Control ? .Capturing : u.order == .Intercept ? .Screening : u.order == .Extract ? .Extracting : u.order == .Withdraw ? .Disengaging : .Navigating
			case .Guard:
				if u.guard >=
				   0 {guard_position := m.units[u.guard].position; offset := f32((i % 3) - 1) * 42; guard_position.y += offset; combat_move_toward(u, guard_position, dt); u.action = .Screening}
			case .Recover:
				u.action = .Repairing
				if u.target >= 0 &&
				   u.target < m.friendly_count &&
				   m.units[u.target].disabled {
					combat_move_toward(
						u,
						m.units[u.target].position,
						dt,
						m.recovery_target_velocity,
					)
					if combat_distance(u.position, m.units[u.target].position) < 24 &&
					   skirmish_recovery_target_secured(m, m.units[u.target].position) {
						target := u.target
						rescued := &m.units[target]
						combat_restore_element(m, target, rescued.max_hull * .25)
						rescued.order = .Withdraw
						rescued.destination = m.extraction
						m.disabled_rescued += 1
						u.target = -1
						skirmish_apply_heavy_tow(m, i, target)
						combat_add_event_at(
							m,
							"Disabled command element recovered; both ships are withdrawing",
							rescued.position,
						)
					}
				} else {
					combat_move_toward(u, m.seedship, dt, m.seedship_velocity)
				}
			case .Hold, .Attack:
			}
			if u.order != .Control && u.order != .Recover && u.order != .Extract && u.order != .Withdraw && (g.maneuver == .Break_Contact || g.maneuver == .Fire_And_Displace || g.maneuver == .Decline_Engagement || g.maneuver == .Reform) do combat_move_toward(u, u.tactical_destination, dt)
			if (u.order == .Extract || u.order == .Withdraw) &&
			   combat_distance(u.position, m.extraction) <
				   42 {u.extracted = true; m.last_extraction_time = m.time; m.last_extraction_role = u.role; continue}
			permit_engage :=
				g.allow_fire &&
				!u.silent_running &&
				u.stance != .Evade &&
				u.order != .Recover &&
				u.order != .Extract &&
				u.order != .Withdraw
			target :=
				u.target; if target < 0 || target >= m.unit_count || !combat_group_contact_targetable(m, u.side, u.group, target) do target = combat_best_enemy(m, i, pursuit, priority)
			if u.order ==
			   .Control {if combat_distance(u.position, u.destination) > 70 {permit_engage = false; target = -1} else if target >= 0 && combat_distance(m.units[target].position, u.destination) > 110 {target = -1}}
			if u.order == .Guard && target >= 0 && u.guard >= 0 && combat_distance(m.units[target].position, m.units[u.guard].position) > 150 do target = -1
			if !permit_engage do target = -1
			if target >= 0 {
				enemy := &m.units[target]; contact_position, _ := combat_group_contact_position(m, u.side, u.group, target); d := combat_distance(u.position, contact_position)
				if u.role == .Bomber &&
				   u.attack_run_timer >
					   0 {u.attack_run_timer = max(0, u.attack_run_timer - dt); u.action = .Disengaging; escape := u.position; escape.x -= 120; combat_move_toward(u, escape, dt)} else {
					if d > u.range * g.preferred_range &&
					   u.order != .Guard &&
					   u.order !=
						   .Recover {approach := contact_position; if g.maneuver == .Establish_Cross_Bearing || g.maneuver == .Skirmish_Pass do approach = u.tactical_destination; combat_move_toward(u, approach, dt); u.action = u.role == .Bomber ? .Attack_Run : .Repositioning}
					identified :=
						combat_group_contact_trace(m, u.side, u.group, target).identity ==
						.Identified
					wants_torpedo :=
						u.role == .Bomber &&
						u.torpedoes > 0 &&
						u.costly_denied_target != target &&
						(g.ordnance_policy == .Liberal && identified ||
								g.ordnance_policy == .Confirmed_Priority &&
									identified &&
									(enemy.role == .Capital || enemy.role == .Corvette) ||
								g.ordnance_policy == .Conserve && u.costly_shot_authorized)
					weapon := combat_weapon_class(u^, wants_torpedo)
					if d >= combat_weapon_minimum_range(weapon) &&
					   d <= combat_weapon_range(u^, weapon) &&
					   u.weapon_cooldown <= 0 &&
					   combat_has_firing_solution(m, i, target, weapon) {
						if combat_fire_request_needed(
							m,
							i,
							target,
							wants_torpedo,
						) {combat_request_fire(m, i, target, wants_torpedo); continue}
						u.weapon_heat = min(
							100,
							u.weapon_heat + combat_weapon_profile(weapon).heat_per_shot,
						)
						if wants_torpedo {u.torpedoes -= 1; u.costly_shot_authorized = false; u.attack_run_timer = 4; u.action = .Attack_Run; combat_launch_salvo(m, i, target, .Heavy_Torpedo, u.damage * 2.3)} else if weapon == .Guided_Missile || weapon == .Kinetic {combat_launch_salvo(m, i, target, weapon, u.damage)} else {bonus: f32 = 1; if u.role == .Fighter && identified && enemy.role == .Bomber do bonus = 1.65; if u.role == .Capital do bonus *= combat_capital_arc_multiplier(u^, enemy^); was_active := !enemy.disabled; combat_apply_damage(m, target, u.damage * clamp(u.subsystems.weapons / 100, f32(.2), f32(1)) * bonus * combat_weapon_effectiveness(weapon, d, u.range, enemy^) * combat_damage_multiplier(m, u, enemy)); enemy.impact_flash = .32; if was_active && enemy.disabled do u.kills += 1; defensive := weapon == .Defensive_Gun || weapon == .Defensive_Laser; u.exposure = min(100, u.exposure + (defensive ? 5 : weapon == .Laser ? 22 : 14)); u.weapon_flash = .35; combat_record_group_fire(m, i)}
						combat_apply_weapon_pressure(
							m,
							i,
							target,
							wants_torpedo ? 1.4 : 1,
						); u.engagement_target = target; u.weapon_cooldown = u.role == .Capital ? 1.6 : u.role == .Bomber ? 2.2 : .7
					}
				}
			}
		} else {
			// Hostile elements use the same side-visible group plan. Scenario goals
			// shape their doctrine and destination, not privileged target knowledge.
			g := combat_group_state(m, u.side, u.group)
			if u.hull / u.max_hull <
			   .2 {u.action = .Disengaging; combat_move_toward(u, {520, u.position.y, u.position.z}, dt); continue}
			priority := g.priority
			if u.role == .Fighter do priority = .Strike_Craft
			target := combat_best_enemy(m, i, g.pursuit_limit, priority)
			if target >= 0 && !combat_group_contact_targetable(m, u.side, u.group, target) do target = -1
			if target >=
			   0 {u.target = target; enemy := &m.units[target]; contact_position, _ := combat_group_contact_position(m, u.side, u.group, target); d := combat_distance(u.position, contact_position); if g.maneuver == .Break_Contact || g.maneuver == .Fire_And_Displace || g.maneuver == .Decline_Engagement {combat_move_toward(u, u.tactical_destination, dt); u.action = .Disengaging} else if d > u.range * g.preferred_range {approach := contact_position; if g.maneuver == .Establish_Cross_Bearing || g.maneuver == .Skirmish_Pass do approach = u.tactical_destination; combat_move_toward(u, approach, dt); u.action = .Repositioning}; costly := u.role == .Bomber && u.torpedoes > 0; weapon := combat_weapon_class(u^, costly); if g.allow_fire && !u.silent_running && d >= combat_weapon_minimum_range(weapon) && d <= combat_weapon_range(u^, weapon) && u.weapon_cooldown <= 0 && combat_has_firing_solution(m, i, target, weapon) {if costly {u.torpedoes -= 1; u.attack_run_timer = 4; combat_launch_salvo(m, i, target, .Heavy_Torpedo, u.damage * 1.8 * .32)} else if weapon == .Guided_Missile || weapon == .Kinetic {combat_launch_salvo(m, i, target, weapon, u.damage * .32)} else {was_active := !enemy.disabled; combat_apply_damage(m, target, u.damage * combat_weapon_effectiveness(weapon, d, u.range, enemy^) * combat_damage_multiplier(m, u, enemy) * .32); enemy.impact_flash = .32; defensive := weapon == .Defensive_Gun || weapon == .Defensive_Laser; u.exposure = min(100, u.exposure + (defensive ? 5 : weapon == .Laser ? 22 : 14)); u.weapon_flash = .35; combat_record_group_fire(m, i); if was_active && enemy.disabled do combat_add_event_at(m, "A friendly command element was disabled and can be recovered", enemy.position)}; combat_apply_weapon_pressure(m, i, target, costly ? 1.25 : 1); u.weapon_cooldown = u.role == .Capital ? 1.7 : .85}} else {combat_move_toward(u, u.tactical_destination, dt); u.action = g.maneuver == .Masked_Approach ? .Repositioning : .Screening}
		}
	}
	combat_separate_units(m, dt)
	recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1)
	if m.scenario != .Finale &&
	   !combat_is_direct_engagement(m) &&
	   m.units[recovery].disabled {
		_ = combat_reassign_recovery_element(m)
		recovery = clamp(m.recovery_unit, 0, m.friendly_count - 1)
	}
	for &u in m.units[:m.unit_count] {if u.role == .Fighter || u.role == .Bomber || u.role == .Corvette {if u.disabled {u.craft = 0} else {u.craft = clamp(int(math.ceil(f64(max(u.hull, 0) / u.max_hull * f32(u.max_craft)))), 1, u.max_craft)}}}
	for relay, i in m.relays {occupiers := 0; hostiles := 0; sensor_support := false; for u in m.units[:m.unit_count] {if u.disabled || u.extracted do continue; if u.side == .Friendly && combat_distance(u.position, relay) < 150 && .Sensors in combat_unit_modules(u) do sensor_support = true; if combat_distance(u.position, relay) < 90 {if u.side == .Friendly {occupiers += 1} else {hostiles += 1}}}; if occupiers > hostiles {advantage := min(occupiers - hostiles, 4); rate := COMBAT_RELAY_CAPTURE_RATE + f32(advantage - 1) * .15; if sensor_support do rate *= 1.12; m.relay_progress[i] = min(100, m.relay_progress[i] + dt * rate)} else if hostiles > occupiers && (m.scenario == .Seedship || m.relay_progress[i] < 100) {m.relay_progress[i] = max(0, m.relay_progress[i] - dt * COMBAT_RELAY_DECAY_RATE)}}
	if m.scenario == .Finale do combat_finale_update(m, dt)
	if m.scenario != .Finale && !combat_is_direct_engagement(m) {
		if m.skirmish && m.skirmish_setup.mission == .Silent_Infiltration {
			scout := clamp(m.objective_unit, 0, m.friendly_count - 1)
			trace := combat_contact_trace(m, .Raider, scout)
			if trace != nil && trace.identity == .Identified do m.objective_failed = true
		}
		if m.phase == .Reconnaissance && (m.relay_progress[0] > 0 || m.relay_progress[1] > 0) do m.phase = .Relay_Control
		if !m.seedship_found &&
		   m.relay_progress[0] >= 100 &&
		   m.relay_progress[1] >=
			   100 {m.relays_synchronized = true; m.seedship_found = true; m.phase = .Recovery; combat_add_event_at(m, "Relay fixes agree; seedship position confirmed", m.seedship)}
		if m.seedship_found && !m.fabrication_recovered {
			r := &m.units[recovery]
			relative_velocity := Combat_Vec3 {
				r.velocity.x - m.seedship_velocity.x,
				r.velocity.y - m.seedship_velocity.y,
				r.velocity.z - m.seedship_velocity.z,
			}
			match_speed := combat_distance(relative_velocity, {})
			if !r.disabled &&
			   !r.extracted &&
			   combat_distance(r.position, m.seedship) < 12 &&
			   match_speed < .1 &&
			   skirmish_recovery_target_secured(m, m.seedship) {
				m.recovery_progress = min(
					100,
					m.recovery_progress +
						dt * COMBAT_RECOVERY_RATE * skirmish_recovery_rate_multiplier(m),
				)
				if m.recovery_progress >= 35 do m.population_recovered = true
				if m.recovery_progress >= 67 do m.archive_recovered = true
				if m.recovery_progress >= 100 {
					m.fabrication_recovered = true
					skirmish_apply_heavy_tow(m, recovery)
					combat_add_event_at(
						m,
						fmt.tprintf(
							"Seedship stabilization complete; fabrication core secured aboard %s",
							r.name,
						),
						m.seedship,
					)
				}
			}
		}
		if !m.skirmish ||
		   skirmish_has_objective(m, .Scan_Anomaly) ||
		   skirmish_has_objective(m, .Complete_Reconnaissance) ||
		   skirmish_has_objective(m, .Complete_Covert_Scan) {
			if m.skirmish {
				best_rate: f32
				for u in m.units[:m.friendly_count] do if !u.disabled && !u.extracted && combat_distance(u.position, m.anomaly) < 70 do best_rate = max(best_rate, skirmish_scan_rate_multiplier(u))
				m.anomaly_progress = min(
					100,
					m.anomaly_progress + dt * COMBAT_ANOMALY_RATE * best_rate,
				)
			} else {
				for u in m.units[:m.friendly_count] do if !u.disabled && !u.extracted && combat_distance(u.position, m.anomaly) < 70 do m.anomaly_progress = min(100, m.anomaly_progress + dt * COMBAT_ANOMALY_RATE)
			}
		}
		if !m.complication_triggered &&
		   (m.relay_progress[0] >= 100 ||
				   m.relay_progress[1] >= 100 ||
				   m.time >=
					   360) {m.complication_triggered = true; open_relay := m.relay_progress[0] >= 100 ? 1 : 0; switch m.complication {
			case .Radiation_Surge:
				combat_add_event_at(m, "Radiation surge expanded around the anomaly", m.anomaly)
			case .Relay_Drift:
				m.relays[open_relay].z += 65
				combat_add_event_at(
					m,
					fmt.tprintf(
						"Relay %s drifted above the original command plane",
						open_relay == 0 ? "A" : "B",
					),
					m.relays[open_relay],
				)
			case .Raider_Reinforcements:
				p := m.relays[open_relay]; p.x += 420; p.z -= 90
				u := combat_unit(
					"Carrion Reserve",
					"Unknown",
					"Objective raider",
					"Entered after the relay warning.",
					.Raider,
					.Bomber,
					p,
				)
				u.formation_ships = max(int(m.heroism_scale), 1)
				combat_apply_heroism(&u, f32(max(m.heroism_scale, 1)))
				index := combat_add_element(m, u)
				combat_append_element_roster(m, index)
				combat_add_event_at(
					m,
					"Raider torpedo reserve entered on the unsecured relay approach",
					u.position,
				)
			case .None:
			}}
		if m.recovery_progress >= 45 &&
		   !m.capital_arrived {m.capital_arrived = true; m.phase = .Capital_Contact; p := combat_map_position({430, 220, 70}); u := combat_unit("Ravager Ascendant", "Raider Primus", "Exposed engines", "Its drive plume identifies an unarmored stern quarter.", .Raider, .Capital, p); u.formation_ships = max(int(m.heroism_scale), 1); combat_apply_heroism(&u, f32(max(m.heroism_scale, 1))); index := combat_add_element(m, u); combat_append_element_roster(m, index); combat_add_event_at(m, "Enemy capital ship translated into the open lane", p); combat_surface_request(m, .Commit_Screen, 1, "Recovery vessel exposed. Commit the screen?", "Screen leaves its relay boundary.")}
		if m.request_cooldown > 0 do m.request_cooldown = max(0, m.request_cooldown - dt)
		if !m.request_pending &&
		   m.request_cooldown <=
			   0 {for &friendly, i in m.units[:m.friendly_count] do if !friendly.disabled && !friendly.extracted && !m.withdraw_request_made[i] && friendly.hull / friendly.max_hull < .42 {m.withdraw_request_made[i] = true; combat_surface_request(m, .Damaged_Withdrawal, i, "Hull margin is failing. Permission to withdraw?", "Preserves the element but leaves its objective exposed."); break}}
		if !m.request_pending &&
		   m.request_cooldown <= 0 &&
		   !m.pursuit_request_made {for friendly, i in m.units[:m.friendly_count] {if friendly.disabled || friendly.extracted || friendly.doctrine == .Hunter_Killer || friendly.doctrine == .Last_Stand do continue; _, limit, _ := combat_doctrine_rules(friendly.doctrine); for enemy, j in m.units[m.friendly_count:m.unit_count] {distance := combat_distance(friendly.position, enemy.position); if !enemy.disabled && enemy.hull / enemy.max_hull < .45 && distance > limit && distance < limit + 150 {m.pursuit_request_made = true; combat_surface_request(m, .Pursuit, i, "Damaged contact is leaving the engagement boundary. Pursue?", "May finish the contact but separates this element from its objective.", m.friendly_count + j); break}}; if m.pursuit_request_made do break}}
		if m.request_timer >
		   0 {m.request_timer = max(0, m.request_timer - dt); if m.request_timer == 0 && m.request_pending do combat_resolve_request(m, combat_request_default(m))}
	}
	friend_active := 0; for u in m.units[:m.friendly_count] do if !u.disabled && !u.extracted do friend_active += 1
	if friend_active == 0 || m.time >= duration {combat_finish(m)}
}

// dt is simulated minutes. Presentation chooses how many simulated minutes
// pass per real second; every path drains the same fixed-step accumulator.
combat_tick :: proc(m: ^Combat_Mission, dt: f32) {m.accumulator += max(dt, 0)
	for m.accumulator >=
	    .049999 {combat_tick_fixed(m, .05); m.accumulator = max(0, m.accumulator - .05)}}

combat_finish :: proc(m: ^Combat_Mission) {if m.complete do return; m.complete = true
	m.phase = .Complete
	m.finale_phase = .Complete
	r := &m.result
	recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1)
	cargo_delivered := m.units[recovery].extracted
	r.population_secured = m.population_recovered
	r.archive_secured = m.archive_recovered
	r.fabrication_secured = m.fabrication_recovered
	r.population = m.population_recovered && cargo_delivered ? 18420 : 0
	r.archive = m.archive_recovered && cargo_delivered ? 1 : 0
	r.fabrication = m.fabrication_recovered && cargo_delivered ? 1 : 0
	r.sensor_data =
		m.relays_synchronized || (m.relay_progress[0] >= 100 && m.relay_progress[1] >= 100)
	r.anomaly_data = m.anomaly_progress >= 100
	r.mission_time = m.time
	r.friendly_total = m.friendly_count
	for u in m.units[:m.friendly_count] {
		if u.extracted {r.friendly_preserved += 1} else if u.disabled {r.abandoned += 1; r.casualties += u.role == .Fighter || u.role == .Bomber ? u.max_craft * 6 : 28} else {r.abandoned += 1}
		r.casualties +=
			(u.max_craft - u.craft) *
			6; r.heavy_ammunition += u.torpedoes; r.ships_total += u.formation_ships
		for ship in m.ships[u.roster_start:u.roster_start + u.formation_ships] {if ship.hull <= 0 {r.ships_disabled += 1} else if u.extracted {r.ships_preserved += 1}}
	}
	if m.capital_arrived {for u in m.units[m.friendly_count:m.unit_count] do if u.role == .Capital && u.disabled do r.enemy_capital_disabled = true}
	for u, i in m.units[:m.unit_count] do for ship in m.ships[u.roster_start:u.roster_start + u.formation_ships] do if ship.hull <= 0 {if i < m.friendly_count {r.player_ships_lost += 1} else {r.enemy_ships_lost += 1}}
	r.strategic_asset_disabled = m.strategic_asset.disabled
	r.beam_ships_hit = m.strategic_asset.ships_hit
	r.beam_shots = m.strategic_asset.shots_fired
	r.rescued = m.disabled_rescued
	r.optional_completed =
		r.archive +
		r.fabrication +
		r.rescued +
		(r.enemy_capital_disabled ? 1 : 0) +
		(r.anomaly_data ? 1 : 0)
	if m.skirmish do r.optional_completed = skirmish_optional_objectives_met(m)
	if m.scenario ==
	   .Finale {r.consequence = r.strategic_asset_disabled ? "The Citadel weapon ceased firing. Surviving formations withdrew from the operational volume." : "The Citadel weapon remained operational when the navigation window closed."} else if combat_is_direct_engagement(m) {
		if r.ships_preserved <= 0 {
			r.consequence = "No player formation reached the withdrawal corridor."
		} else if r.enemy_ships_lost > r.player_ships_lost {
			r.consequence = "The player fleet inflicted the greater loss and withdrew from the operational volume."
		} else if r.enemy_ships_lost == r.player_ships_lost {
			r.consequence = "The fleets traded equal losses; player formations reached the withdrawal corridor."
		} else {
			r.consequence = "The player fleet withdrew after taking the greater loss."
		}
	} else if m.skirmish &&
	   m.skirmish_setup.mission != .Seedship_Recovery &&
	   m.skirmish_setup.mission != .Contested_Salvage {
		if skirmish_primary_objective_met(m) {
			r.consequence = fmt.tprintf(
				"The primary objective for %s was completed; surviving formations left the operational volume.",
				skirmish_mission_name(m.skirmish_setup.mission),
			)
		} else if r.ships_preserved > 0 {
			r.consequence = fmt.tprintf(
				"The primary objective for %s remained incomplete; surviving formations withdrew.",
				skirmish_mission_name(m.skirmish_setup.mission),
			)
		} else {
			r.consequence = fmt.tprintf(
				"No player formation returned from %s.",
				skirmish_mission_name(m.skirmish_setup.mission),
			)
		}
	} else if r.population > 0 &&
	   r.fabrication > 0 &&
	   r.friendly_preserved >=
		   5 {r.consequence = "The recovered population can found a supplied settlement; the veteran screen remains intact."} else if r.population > 0 {r.consequence = "The population joins an orbital refugee fleet; missing capacity must be replaced."} else if r.population_secured {r.consequence = fmt.tprintf("%s did not reach extraction. The secured population remains in the operational area.", m.units[recovery].name)} else if m.units[recovery].disabled {r.consequence = fmt.tprintf("%s was disabled before the population could be recovered. The seedship remains in the operational area.", m.units[recovery].name)} else if r.sensor_data {r.consequence = "The relay fix returned with the fleet. The seedship remains in the operational area for a later recovery attempt."} else {r.consequence = "The seedship remains a salvage site. No population reached the fleet."}
}

Combat_Autoplay_Phase :: enum {
	Assign,
	Pursue,
	Extract,
	Complete,
	Aborted,
}

Combat_Autoplay_Controller :: struct {
	phase:                                                                    Combat_Autoplay_Phase,
	objective_units:                                                          [2]int,
	objective_unit_count:                                                     int,
	recovery_staged,
	recovery_ordered,
	recovery_extraction_ordered:           bool,
	screen_released,
	anomaly_ordered,
	capital_ordered,
	extraction_ordered:    bool,
	primary_order_active,
	interaction_complete,
	extraction_complete,
	aborted: bool,
}

combat_autoplay_interaction :: proc(
	m: ^Combat_Mission,
	kind: Combat_Interaction_Kind,
	target := -2,
) -> (
	Combat_Interaction,
	bool,
) {
	for interaction in m.interactions[:m.interaction_count] {
		if !interaction.active || interaction.kind != kind do continue
		if target != -2 && interaction.target != target do continue
		return interaction, true
	}
	return {}, false
}

combat_autoplay_assign :: proc(c: ^Combat_Autoplay_Controller, units: ..int) {
	c.objective_unit_count = min(len(units), len(c.objective_units))
	for unit, index in units do if index < len(c.objective_units) do c.objective_units[index] = unit
	c.phase = .Pursue
	c.primary_order_active = true
}

combat_autoplay_extract :: proc(m: ^Combat_Mission, c: ^Combat_Autoplay_Controller, units: ..int) {
	c.phase = .Extract
	c.interaction_complete = true
	for unit in units do if unit >= 0 && unit < m.friendly_count && !m.units[unit].disabled && !m.units[unit].extracted {
		combat_issue_order(m, unit, .Extract, m.extraction)
	}
}

combat_autoplay_extract_all :: proc(m: ^Combat_Mission, c: ^Combat_Autoplay_Controller) {
	c.phase = .Extract
	c.extraction_ordered = true
	for i in 0 ..< m.friendly_count do if !m.units[i].disabled && !m.units[i].extracted {
		combat_issue_order(m, i, .Extract, m.extraction)
	}
}

combat_autoplay_extraction_satisfied :: proc(
	m: ^Combat_Mission,
	c: ^Combat_Autoplay_Controller,
) -> bool {
	if m == nil || c == nil || (!c.extraction_ordered && c.phase != .Extract && c.phase != .Complete) {
		return false
	}
	if c.objective_unit_count > 0 {
		for unit in c.objective_units[:c.objective_unit_count] do if unit >= 0 &&
		   unit < m.friendly_count &&
		   !m.units[unit].disabled &&
		   !m.units[unit].extracted {
			return false
		}
		return true
	}
	for unit in m.units[:m.friendly_count] do if !unit.disabled && !unit.extracted do return false
	return true
}

combat_autoplay_screen :: proc(m: ^Combat_Mission, objective: int) {
	if objective < 0 || objective >= m.friendly_count do return
	for &unit, index in m.units[:m.friendly_count] do if index != objective &&
	   !unit.disabled &&
	   !unit.extracted &&
	   unit.order != .Withdraw &&
	   unit.order != .Extract {
		combat_issue_order(m, index, .Attack, m.units[objective].position)
	}
}

combat_autoplay_scanner :: proc(m: ^Combat_Mission) -> int {
	best := -1
	best_score: f32 = -1
	for unit, index in m.units[:m.friendly_count] do if !unit.disabled &&
	   !unit.extracted &&
	   .Sensors in combat_unit_modules(unit) {
		score := unit.speed * 4 + unit.max_hull
		if unit.operational_role == .Scout do score += 1000
		if score <= best_score do continue
		best = index
		best_score = score
	}
	return best
}

combat_autoplay_probe_launcher :: proc(m: ^Combat_Mission) -> int {
	best := -1
	best_hull: f32 = -1
	for unit, index in m.units[:m.friendly_count] do if !unit.disabled &&
	   !unit.extracted &&
	   unit.recon_probes > 0 &&
	   (.Sensors in combat_unit_modules(unit) || .Command in combat_unit_modules(unit)) &&
	   unit.max_hull > best_hull {
		best = index
		best_hull = unit.max_hull
	}
	return best
}

combat_autoplay_durable_element :: proc(m: ^Combat_Mission) -> int {
	best := -1
	best_hull: f32 = -1
	for unit, index in m.units[:m.friendly_count] do if !unit.disabled &&
	   !unit.extracted &&
	   unit.max_hull > best_hull {
		best = index
		best_hull = unit.max_hull
	}
	return best
}

combat_autoplay_objective_step :: proc(m: ^Combat_Mission, c: ^Combat_Autoplay_Controller) {
	kind := m.skirmish_setup.mission
	switch kind {
	case .Seedship_Recovery, .Contested_Salvage:
		if c.phase == .Assign &&
		   (m.recovery_unit < 0 ||
			   m.recovery_unit >= m.friendly_count ||
			   m.units[m.recovery_unit].disabled ||
			   m.units[m.recovery_unit].extracted) {
			_ = combat_reassign_recovery_element(m)
		}
		recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1)
		if c.phase == .Assign do combat_autoplay_assign(c, recovery)
		if m.units[recovery].disabled && !m.fabrication_recovered {
			c.aborted = true
			c.phase = .Aborted
		}
		if !m.seedship_found {
			relay := m.relay_progress[0] < 100 ? 0 : 1
			scanner := combat_autoplay_scanner(m)
			scan_active := skirmish_has_objective(m, .Scan_Anomaly) &&
			               m.anomaly_progress < 100 &&
			               scanner >= 0
			screen_count := 0
			for &unit, index in m.units[:m.friendly_count] do if !unit.disabled &&
			   !unit.extracted {
				if index == recovery {
					safe := m.extraction
					safe.x += 90
					unit.stance = .Evade
					combat_issue_order(m, index, .Move, safe)
					continue
				}
				unit.combat_burn = true
				if scan_active && index == scanner {
					unit.stance = .Evade
					combat_issue_interaction(m, index, .Scan, m.anomaly)
					continue
				}
				if scan_active && screen_count < 2 {
					combat_issue_order(m, index, .Attack, m.units[scanner].position)
					screen_count += 1
					continue
				}
				combat_issue_interaction(m, index, .Capture, m.relays[relay], relay)
			}
		} else if m.fabrication_recovered {
			c.interaction_complete = true
			combat_autoplay_extract_all(m, c)
		} else if !m.units[recovery].disabled {
			m.units[recovery].combat_burn = true
			m.units[recovery].stance = .Evade
			interaction_kind :=
				kind == .Contested_Salvage ? Combat_Interaction_Kind.Salvage : Combat_Interaction_Kind.Recover
			if interaction, ok := combat_autoplay_interaction(m, interaction_kind); ok {
				combat_issue_interaction(
					m,
					recovery,
					interaction.kind,
					interaction.position,
					interaction.target,
				)
			} else if m.seedship_found {
				combat_issue_order(m, recovery, .Recover, m.seedship)
			}
			combat_autoplay_screen(m, recovery)
		}
	case .Disabled_Ship_Rescue, .Repair_And_Tow:
		recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1)
		target := clamp(m.objective_unit, 0, m.friendly_count - 1)
		if c.phase == .Assign do combat_autoplay_assign(c, recovery, target)
		if m.units[recovery].disabled && m.disabled_rescued == 0 {
			c.aborted = true
			c.phase = .Aborted
		}
		if m.disabled_rescued > 0 || !m.units[target].disabled {
			c.interaction_complete = true
			combat_autoplay_extract_all(m, c)
		} else if !m.units[recovery].disabled {
			m.units[recovery].combat_burn = true
			m.units[recovery].stance = .Evade
			if interaction, ok := combat_autoplay_interaction(m, .Rescue, target); ok {
				combat_issue_interaction(
					m,
					recovery,
					interaction.kind,
					interaction.position,
					interaction.target,
					)
				}
				combat_autoplay_screen(m, recovery)
			}
	case .Reconnaissance, .Silent_Infiltration:
		if c.phase == .Assign {
			m.objective_unit = combat_autoplay_scanner(m)
			combat_autoplay_assign(c, m.objective_unit)
		}
		scout := clamp(m.objective_unit, 0, m.friendly_count - 1)
		if m.units[scout].disabled && m.anomaly_progress < 100 {
			replacement := combat_autoplay_scanner(m)
			if replacement >= 0 {
				m.objective_unit = replacement
				c.objective_units[0] = replacement
				scout = replacement
			} else {
				c.aborted = true
				c.phase = .Aborted
			}
		}
		if kind == .Reconnaissance &&
		   m.anomaly_progress < 100 &&
		   m.recon_probe.status != .In_Flight &&
		   m.recon_probe.status != .Scanning {
			if launcher := combat_autoplay_probe_launcher(m); launcher >= 0 &&
			   combat_launch_recon_probe(m, launcher, m.anomaly) {
				m.objective_unit = launcher
				c.objective_units[0] = launcher
				scout = launcher
			}
		}
		probe_active :=
			kind == .Reconnaissance &&
			(m.recon_probe.status == .In_Flight || m.recon_probe.status == .Scanning)
		if m.anomaly_progress >= 100 {
			c.interaction_complete = true
			combat_autoplay_extract_all(m, c)
		} else if probe_active {
			if !m.units[scout].disabled && !m.units[scout].extracted {
				m.units[scout].stance = .Evade
				m.units[scout].silent_running = true
				m.units[scout].silent_running_timer = max(
					m.units[scout].silent_running_timer,
					f32(2),
				)
				combat_issue_order(m, scout, .Hold, m.units[scout].position)
			}
			combat_autoplay_screen(m, scout)
		} else if !m.units[scout].disabled {
			m.units[scout].stance = .Evade
			if kind == .Reconnaissance {
				trace := combat_contact_trace(m, .Raider, scout)
				detected := trace != nil && trace.detected
				m.units[scout].silent_running = !detected
				if !detected {
					m.units[scout].silent_running_timer = max(
						m.units[scout].silent_running_timer,
						f32(2),
					)
				} else {
					m.units[scout].combat_burn = true
				}
			}
			if interaction, ok := combat_autoplay_interaction(m, .Scan); ok {
				combat_issue_interaction(
					m,
					scout,
					interaction.kind,
					interaction.position,
					interaction.target,
				)
			} else {
				combat_issue_order(m, scout, .Control, m.anomaly)
			}
			if kind == .Silent_Infiltration {
				m.units[scout].silent_running = true
				m.units[scout].silent_running_timer = max(
					m.units[scout].silent_running_timer,
					f32(2),
					)
				}
			combat_autoplay_screen(m, scout)
		}
	case .Relay_Control:
		left := clamp(m.objective_unit, 0, m.friendly_count - 1)
		right := left == 0 ? 1 : 0
		if c.phase == .Assign do combat_autoplay_assign(c, left, right)
		if m.relay_progress[0] >= 100 && m.relay_progress[1] >= 100 {
			c.interaction_complete = true
			combat_autoplay_extract_all(m, c)
		} else {
			for &unit, index in m.units[:m.friendly_count] do if !unit.disabled &&
			   !unit.extracted &&
			   unit.order != .Withdraw {
				unit.combat_burn = true
				relay := index % 2
				if interaction, ok := combat_autoplay_interaction(m, .Capture, relay); ok {
					combat_issue_interaction(m, index, interaction.kind, interaction.position, interaction.target)
				}
			}
		}
	case .Raid_And_Deploy:
		deployer := clamp(m.objective_unit, 0, m.friendly_count - 1)
		if c.phase == .Assign do combat_autoplay_assign(c, deployer)
		if m.units[deployer].disabled && m.relay_progress[0] < 100 {
			replacement := combat_autoplay_durable_element(m)
			if replacement >= 0 {
				m.objective_unit = replacement
				m.recovery_unit = replacement
				c.objective_units[0] = replacement
				deployer = replacement
			} else {
				c.aborted = true
				c.phase = .Aborted
			}
		}
		if m.relay_progress[0] >= 100 && c.phase != .Extract {
			c.interaction_complete = true
			m.units[deployer].combat_burn = true
			combat_autoplay_extract(m, c, deployer)
		} else if c.phase == .Extract {
			m.units[deployer].combat_burn = true
		} else if !m.units[deployer].disabled {
			m.units[deployer].combat_burn = true
			m.units[deployer].stance = .Evade
			if interaction, ok := combat_autoplay_interaction(m, .Deploy, 0); ok {
				combat_issue_interaction(
					m,
					deployer,
					interaction.kind,
					interaction.position,
					interaction.target,
					)
				}
				combat_autoplay_screen(m, deployer)
			}
	case .Convoy_Escort:
		convoy := clamp(m.objective_unit, 0, m.friendly_count - 1)
		escort := convoy == 0 ? 1 : 0
		if c.phase == .Assign do combat_autoplay_assign(c, convoy, escort)
		if m.units[convoy].disabled {
			c.aborted = true
			c.phase = .Aborted
		}
		if m.units[convoy].extracted || m.units[convoy].disabled {
			c.interaction_complete = m.units[convoy].extracted
			combat_autoplay_extract_all(m, c)
		} else {
			m.units[convoy].combat_burn = true
			m.units[convoy].stance = .Evade
			combat_issue_order(m, convoy, .Extract, m.extraction)
			_ = escort
			combat_autoplay_screen(m, convoy)
		}
	case .Rearguard_Withdrawal:
		if c.phase == .Assign do combat_autoplay_assign(c)
	// Mission authoring assigns every element to the withdrawal corridor.
	// Preserve those orders instead of replacing one with casualty recovery.
	case .Fleet_Engagement:
		if c.phase == .Assign do combat_autoplay_assign(c)
		enemy_active := 0
		for enemy in m.units[m.friendly_count:m.unit_count] do if !enemy.disabled do enemy_active += 1
		if enemy_active == 0 || m.time >= 900 {
			combat_autoplay_extract_all(m, c)
		} else {
			for &u, i in m.units[:m.friendly_count] do if !u.disabled && !u.extracted && u.order != .Withdraw {
				combat_issue_order(m, i, .Attack, u.destination)
			}
		}
	case .Capital_Interception:
		if c.phase == .Assign do combat_autoplay_assign(c)
		capital := -1
		for enemy, offset in m.units[m.friendly_count:m.unit_count] do if enemy.role == .Capital {
			capital = m.friendly_count + offset
			break
		}
		if capital >= 0 && m.units[capital].disabled {
			combat_autoplay_extract_all(m, c)
		} else if capital >= 0 {
			for &u, i in m.units[:m.friendly_count] do if !u.disabled && !u.extracted && u.order != .Withdraw {
				combat_issue_order(m, i, .Attack, m.units[capital].position, capital)
			}
		}
	case .Citadel_Assault:
	}
	if c.phase == .Extract {
		c.extraction_complete = combat_autoplay_extraction_satisfied(m, c)
		if c.extraction_complete do c.phase = .Complete
	}
}

combat_autoplay_step :: proc(m: ^Combat_Mission, c: ^Combat_Autoplay_Controller) {
	if m.request_pending {approve := combat_request_default(m); switch m.request_kind {
		case .Commit_Screen,
		     .Release_Torpedoes,
		     .Authorize_Fire,
		     .Authorize_Ability,
		     .Authorize_Emergency_Defense:
			approve = true
		case .Damaged_Withdrawal:
			approve = m.fabrication_recovered
		case .Pursuit:
			approve = false
		case .None:
		}; combat_resolve_request(m, approve)}
	if m.skirmish {
		combat_autoplay_objective_step(m, c)
		return
	}
	recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1)
	if !m.seedship_found && !c.recovery_staged {
		c.recovery_staged = true
		staging := Combat_Vec3 {
			(m.relays[0].x + m.relays[1].x) * .5,
			(m.relays[0].y + m.relays[1].y) * .5,
			(m.relays[0].z + m.relays[1].z) * .5,
		}
		combat_issue_order(m, recovery, .Move, staging)
		for &u, i in m.units[:m.friendly_count] do if u.group == 2 && i != recovery {
			combat_issue_order(m, i, .Extract, m.extraction)
		}
	}
	if m.seedship_found &&
	   !c.recovery_ordered {c.recovery_ordered = true; recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1); combat_issue_order(m, recovery, .Recover, m.seedship); for _, i in m.units[:m.friendly_count] do if i != recovery {combat_issue_order(m, i, .Extract, m.extraction)}}
	if m.capital_arrived &&
	   !c.capital_ordered {c.capital_ordered = true; capital := -1; for u, i in m.units[m.friendly_count:m.unit_count] do if u.role == .Capital {capital = m.friendly_count + i; break}; if capital >= 0 {for &u, i in m.units[:m.friendly_count] do if u.group == 1 && u.order != .Extract && u.order != .Withdraw do combat_issue_order(m, i, .Attack, m.units[capital].position, capital)}}
	if m.fabrication_recovered &&
	   !c.anomaly_ordered {c.anomaly_ordered = true; combat_issue_order(m, 0, .Control, m.anomaly)}
	if m.population_recovered && !c.screen_released {
		c.screen_released = true
		for &u, i in m.units[:m.friendly_count] do if i != recovery && u.order == .Guard {
			combat_issue_order(m, i, .Extract, m.extraction)
		}
	}
	if m.fabrication_recovered && !c.recovery_extraction_ordered {
		c.recovery_extraction_ordered = true
		combat_issue_order(m, recovery, .Extract, m.extraction)
	}
	if !c.extraction_ordered &&
	   m.fabrication_recovered &&
	   m.time >=
		   960 {c.extraction_ordered = true; for i in 0 ..< m.friendly_count do combat_issue_order(m, i, .Extract, m.extraction)}
	if m.seedship_found && !m.fabrication_recovered && !m.units[recovery].disabled {
		// The seedship is moving. Refresh the objective every command step and
		// do not let casualty recovery silently replace the primary mission.
		combat_issue_order(m, recovery, .Recover, m.seedship)
	} else if !c.recovery_extraction_ordered && !m.units[recovery].disabled {
		for u, i in m.units[:m.friendly_count] do if u.disabled {
			combat_issue_order(m, recovery, .Recover, u.position, i)
			break
		}
	}
}
combat_autoplay_mission :: proc(seed: u64, stop_at: f32) -> Combat_Mission {m :=
		combat_new_mission(seed)
	controller: Combat_Autoplay_Controller
	for !m.complete && m.time < stop_at {combat_autoplay_step(&m, &controller); combat_tick_fixed(
			&m,
			.05,
		)}
	return m}

combat_resolve_abandoned_campaign_deployment :: proc(c: ^Campaign) -> Combat_Campaign_Application {
	if !c.combat_deployment_active do return {}
	m := combat_new_campaign_mission(
		c,
	); defer combat_mission_destroy(&m); controller: Combat_Autoplay_Controller
	for !m.complete {combat_autoplay_step(&m, &controller); combat_tick_fixed(&m, .05)}
	return combat_apply_campaign_result(c, &m)
}

// A deterministic, intentionally competent command policy used for balance
// tests. It issues objectives only; the same unit autonomy executes them.
combat_autoplay :: proc(seed: u64) -> Combat_Autoplay_Report {
	m := combat_autoplay_mission(seed, COMBAT_DURATION + .1); defer combat_mission_destroy(&m)
	recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1)
	recovery_unit := &m.units[recovery]
	relative_velocity := Combat_Vec3 {
		recovery_unit.velocity.x - m.seedship_velocity.x,
		recovery_unit.velocity.y - m.seedship_velocity.y,
		recovery_unit.velocity.z - m.seedship_velocity.z,
	}
	friendly_unextracted := 0
	first_unextracted_role: Combat_Role
	for unit in m.units[:m.friendly_count] do if !unit.disabled && !unit.extracted {
		if friendly_unextracted == 0 do first_unextracted_role = unit.role
		friendly_unextracted += 1
	}
	return {
		seed = seed,
		completed = m.complete,
		population = m.result.population > 0,
		archive = m.result.archive > 0,
		fabrication = m.result.fabrication > 0,
		anomaly = m.result.anomaly_data,
		capital_disabled = m.result.enemy_capital_disabled,
		preserved = m.result.friendly_preserved,
		casualties = m.result.casualties,
		time = m.result.mission_time,
		relay_progress = m.relay_progress,
		recovery_progress = m.recovery_progress,
		recovery_distance = combat_distance(recovery_unit.position, m.seedship),
		recovery_match_speed = combat_distance(relative_velocity, {}),
		recovery_disabled = recovery_unit.disabled,
		recovery_extracted = recovery_unit.extracted,
		friendly_unextracted = friendly_unextracted,
		first_unextracted_role = first_unextracted_role,
		last_extraction_role = m.last_extraction_role,
		last_extraction_time = m.last_extraction_time,
	}
}
