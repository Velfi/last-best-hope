package game

import "core:fmt"

skirmish_hull_cost :: proc(archetype: Ship_Hull_Archetype) -> i64 {
	switch archetype {
	case .Scout:
		return 8
	case .Interceptor:
		return 10
	case .Fighter:
		return 12
	case .Strike_Fighter:
		return 16
	case .Bomber:
		return 20
	case .Assault_Shuttle:
		return 18
	case .Patrol_Boat:
		return 28
	case .Torpedo_Boat:
		return 36
	case .Corvette:
		return 44
	case .Gunship:
		return 58
	case .Picket_Frigate:
		return 72
	case .Combat_Frigate:
		return 95
	case .Support_Frigate:
		return 105
	case .Minelayer_Frigate:
		return 110
	case .Utility_Hull:
		return 80
	case .Transport_Hull:
		return 125
	case .Destroyer:
		return 150
	case .Light_Cruiser:
		return 240
	case .Heavy_Cruiser:
		return 420
	case .Carrier:
		return 560
	case .Battlecruiser:
		return 700
	case .Battleship:
		return 1050
	case .Habitat_Hull:
		return 1250
	case .Dreadnought:
		return 1800
	case .Unspecified:
		return 0
	}
	return 0
}

skirmish_loadout_cost :: proc(setup: ^Skirmish_Setup) -> i64 {
	total: i64
	for entry in setup.loadout do total += skirmish_hull_cost(entry.archetype) * i64(max(entry.ships, 0))
	return total
}

skirmish_loadout_ship_count :: proc(setup: ^Skirmish_Setup) -> int {
	total := 0
	for entry in setup.loadout do total += max(entry.ships, 0)
	return total
}

skirmish_role_for_hull :: proc(hull: Ship_Hull_Archetype) -> Combat_Role {
	switch ship_hull_archetype_family(hull) {
	case .Strike_Craft:
		return hull == .Bomber ? .Bomber : .Fighter
	case .Light_Combatant, .Frigate:
		return .Corvette
	case .Carrier_And_Command:
		return .Carrier
	case .Line_Warship:
		return .Capital
	case .Diaspora:
		return hull == .Utility_Hull ? .Recovery : .Carrier
	case .Unspecified:
		return .Corvette
	}
	return .Corvette
}

skirmish_role_for_hull_operational :: proc(hull: Ship_Hull_Archetype) -> Ship_Operational_Role {
	return ship_operational_role_for_hull(u64(int(hull)) * 0x9e3779b97f4a7c15, .Escort, hull)
}

skirmish_operational_role_for_mission :: proc(
	hull: Ship_Hull_Archetype,
	mission: Skirmish_Mission_Kind,
) -> Ship_Operational_Role {
	if hull == .Utility_Hull {
		#partial switch mission {
		case .Seedship_Recovery,
		     .Disabled_Ship_Rescue,
		     .Convoy_Escort,
		     .Contested_Salvage,
		     .Repair_And_Tow:
			return .Recovery_Tug
		case .Raid_And_Deploy:
			return .Courier
		case:
		}
	}
	return skirmish_role_for_hull_operational(hull)
}

skirmish_archetype_for_mission :: proc(
	hull: Ship_Hull_Archetype,
	mission: Skirmish_Mission_Kind,
) -> Ship_Hull_Archetype {
	if hull == .Interceptor && mission == .Reconnaissance {
		return .Scout
	}
	return hull
}

skirmish_recovery_score :: proc(role: Combat_Role, modules: Ship_Modules) -> int {
	score := 0
	if .Recovery in modules do score += 80
	if .Medical in modules do score += 25
	if .Repair in modules do score += 20
	if role == .Recovery do score += 30
	return score
}

skirmish_recovery_element :: proc(m: ^Combat_Mission) -> int {
	best, best_score := -1, -1
	for u, i in m.units[:m.friendly_count] {
		score := skirmish_recovery_score(u.role, combat_unit_modules(u))
		if score > best_score {best = i; best_score = score}
	}
	return max(best, 0)
}

skirmish_deployment_score :: proc(u: Combat_Unit) -> int {
	modules := combat_unit_modules(u)
	score := 0
	if .Cargo in modules do score += 80
	if .Sensors in modules do score += 20
	if .Command in modules do score += 15
	if u.operational_role == .Courier do score += 30
	return score
}

skirmish_deployment_element :: proc(m: ^Combat_Mission) -> int {
	best, best_score := -1, -1
	best_speed: f32 = -1
	for unit, index in m.units[:m.friendly_count] {
		score := skirmish_deployment_score(unit)
		if score > best_score || score == best_score && unit.speed > best_speed {
			best = index
			best_score = score
			best_speed = unit.speed
		}
	}
	return max(best, 0)
}

skirmish_recovery_loadout_index :: proc(setup: ^Skirmish_Setup) -> int {
	best, best_score := 0, -1
	for entry, i in setup.loadout {
		role := skirmish_role_for_hull(entry.archetype)
		operational := skirmish_operational_role_for_mission(entry.archetype, setup.mission)
		score := skirmish_recovery_score(role, ship_operational_role_modules(operational))
		if score > best_score {best = i; best_score = score}
	}
	return best
}

skirmish_recovery_loadout_rate :: proc(setup: ^Skirmish_Setup) -> f32 {
	index := skirmish_recovery_loadout_index(setup)
	entry := setup.loadout[index]
	role := skirmish_role_for_hull(entry.archetype)
	modules := ship_operational_role_modules(skirmish_role_for_hull_operational(entry.archetype))
	rate: f32 = .35
	if .Recovery in modules do rate += .55
	if .Medical in modules do rate += .15
	if .Repair in modules do rate += .10
	if role == .Recovery do rate += .10
	return min(rate, 1.2)
}

skirmish_citadel_strike_loadout_index :: proc(setup: ^Skirmish_Setup) -> int {
	for entry, i in setup.loadout {
		operational := skirmish_role_for_hull_operational(entry.archetype)
		if .Torpedoes in ship_operational_role_modules(operational) do return i
	}
	return -1
}

skirmish_primary_capability_ready :: proc(setup: ^Skirmish_Setup) -> bool {
	if setup == nil do return false
	if setup.mission == .Citadel_Assault do return skirmish_citadel_strike_loadout_index(setup) >= 0
	if skirmish_is_recovery_operation(setup.mission) {
		index := skirmish_recovery_loadout_index(setup)
		entry := setup.loadout[index]
		role := skirmish_role_for_hull(entry.archetype)
		operational := skirmish_operational_role_for_mission(entry.archetype, setup.mission)
		return skirmish_recovery_score(
			role,
			ship_operational_role_modules(operational),
		) > 0
	}
	return true
}

skirmish_scan_score :: proc(modules: Ship_Modules) -> int {
	score := 0
	if .Sensors in modules do score += 80
	if .Command in modules do score += 20
	if .Electronic_Warfare in modules do score += 15
	return score
}

skirmish_scan_rate_for_modules :: proc(modules: Ship_Modules) -> f32 {
	rate: f32 = .35
	if .Sensors in modules do rate += .65
	if .Command in modules do rate += .15
	if .Electronic_Warfare in modules do rate += .10
	return min(rate, 1.2)
}

skirmish_scan_loadout_index :: proc(setup: ^Skirmish_Setup) -> int {
	best, best_score := 0, -1
	for entry, i in setup.loadout {
		operational := skirmish_role_for_hull_operational(entry.archetype)
		score := skirmish_scan_score(ship_operational_role_modules(operational))
		if score > best_score {best = i; best_score = score}
	}
	return best
}

skirmish_scan_loadout_rate :: proc(setup: ^Skirmish_Setup) -> f32 {
	index := skirmish_scan_loadout_index(setup)
	operational := skirmish_role_for_hull_operational(setup.loadout[index].archetype)
	return skirmish_scan_rate_for_modules(ship_operational_role_modules(operational))
}

skirmish_scan_rate_multiplier :: proc(u: Combat_Unit) -> f32 {
	return skirmish_scan_rate_for_modules(combat_unit_modules(u))
}

skirmish_recovery_rate_multiplier :: proc(m: ^Combat_Mission) -> f32 {
	if !m.skirmish do return 1
	index := clamp(m.recovery_unit, 0, m.friendly_count - 1)
	u := m.units[index]
	modules := combat_unit_modules(u)
	rate: f32 = .35
	if .Recovery in modules do rate += .55
	if .Medical in modules do rate += .15
	if .Repair in modules do rate += .10
	if u.role == .Recovery do rate += .10
	return min(rate, 1.2)
}

skirmish_is_recovery_operation :: proc(mission: Skirmish_Mission_Kind) -> bool {
	#partial switch mission {
	case .Seedship_Recovery, .Disabled_Ship_Rescue, .Contested_Salvage, .Repair_And_Tow:
		return true
	case:
	}
	return false
}

skirmish_recovery_profile :: proc(
	contract_seed: u64,
	mission: Skirmish_Mission_Kind,
) -> Skirmish_Recovery_Profile {
	if !skirmish_is_recovery_operation(mission) do return .None
	roll := combat_mix(
		contract_seed ~ (u64(int(mission) + 1) * 0x94d049bb133111eb),
	) % 100
	if roll < 25 do return .Clear_Approach
	if roll < 55 do return .Picketed_Target
	if roll < 80 do return .Drifting_Target
	return .Heavy_Tow
}

skirmish_recovery_profile_index :: proc(profile: Skirmish_Recovery_Profile) -> int {
	if profile == .None do return -1
	return int(profile) - 1
}

skirmish_recovery_profile_name :: proc(profile: Skirmish_Recovery_Profile) -> string {
	switch profile {
	case .Clear_Approach:
		return "clear"
	case .Picketed_Target:
		return "picketed"
	case .Drifting_Target:
		return "drifting"
	case .Heavy_Tow:
		return "heavy-tow"
	case .None:
		return "none"
	}
	return "none"
}

Skirmish_Recovery_Profile_Budget :: struct {
	approach_seconds,
	interaction_seconds,
	extraction_seconds,
	total_seconds,
	limit_seconds: f32,
	capable,
	viable:        bool,
}

skirmish_recovery_target_position :: proc(m: ^Combat_Mission) -> Combat_Vec3 {
	#partial switch m.skirmish_setup.mission {
	case .Disabled_Ship_Rescue, .Repair_And_Tow:
		target := clamp(m.objective_unit, 0, m.friendly_count - 1)
		return m.units[target].position
	case:
		return m.seedship
	}
}

skirmish_recovery_profile_budget :: proc(
	m: ^Combat_Mission,
	profile: Skirmish_Recovery_Profile,
) -> Skirmish_Recovery_Profile_Budget {
	result: Skirmish_Recovery_Profile_Budget
	if m == nil || !skirmish_is_recovery_operation(m.skirmish_setup.mission) ||
	   m.friendly_count <= 0 {
		return result
	}
	recovery := clamp(m.recovery_unit, 0, m.friendly_count - 1)
	unit := m.units[recovery]
	target := skirmish_recovery_target_position(m)
	speed := max(unit.speed, f32(1))
	result.capable =
		skirmish_recovery_score(unit.role, combat_unit_modules(unit)) > 0 &&
		!unit.disabled
	result.approach_seconds = combat_distance(unit.position, target) / speed
	#partial switch m.skirmish_setup.mission {
	case .Seedship_Recovery, .Contested_Salvage:
		result.interaction_seconds =
			100 / max(COMBAT_RECOVERY_RATE * skirmish_recovery_rate_multiplier(m), f32(.1))
	case .Disabled_Ship_Rescue, .Repair_And_Tow:
		result.interaction_seconds = 20
	case:
	}
	extraction_speed := speed
	if profile == .Heavy_Tow do extraction_speed *= .45
	result.extraction_seconds =
		combat_distance(target, m.extraction) / max(extraction_speed, f32(1))
	switch profile {
	case .Picketed_Target:
		result.interaction_seconds += 120
	case .Drifting_Target:
		result.approach_seconds *= 1.2
		result.interaction_seconds += 30
	case .Clear_Approach, .Heavy_Tow, .None:
	}
	result.total_seconds =
		result.approach_seconds + result.interaction_seconds + result.extraction_seconds
	result.limit_seconds = combat_mission_duration(m) * .75
	result.viable = result.capable && result.total_seconds <= result.limit_seconds
	return result
}

skirmish_recovery_target_secured :: proc(
	m: ^Combat_Mission,
	position: Combat_Vec3,
) -> bool {
	if m == nil || m.skirmish_recovery_profile != .Picketed_Target do return true
	hostiles := 0
	for unit in m.units[m.friendly_count:m.unit_count] do if !unit.disabled &&
	   !unit.extracted &&
	   combat_distance(unit.position, position) < 90 {
		hostiles += 1
	}
	// The screen must be broken, not exterminated. One surviving element can
	// harass the recovery but cannot deny the interaction by itself.
	return hostiles <= 1
}

skirmish_position_tow_interceptors :: proc(m: ^Combat_Mission) {
	if m == nil || m.unit_count <= m.friendly_count do return
	target := skirmish_recovery_target_position(m)
	intercept := Combat_Vec3 {
		(target.x + m.extraction.x) * .5,
		(target.y + m.extraction.y) * .5,
		(target.z + m.extraction.z) * .5,
	}
	group := &m.raider_groups[0]
	group.objective = .Attack
	group.destination = intercept
	group.stance = .Screen
	group.priority = .Threats_To_Objective
	positioned := 0
	for &unit in m.units[m.friendly_count:m.unit_count] {
		if positioned >= 2 do break
		side := positioned == 0 ? f32(-1) : f32(1)
		unit.group = 0
		unit.position = {intercept.x + 45, intercept.y + side * 55, intercept.z + side * 18}
		unit.destination = intercept
		unit.tactical_destination = intercept
		positioned += 1
	}
	if positioned > 0 {
		combat_add_event_at(m, "Hostile elements hold the forecast tow route", intercept)
	}
}

skirmish_apply_recovery_profile :: proc(m: ^Combat_Mission) {
	if m == nil || !skirmish_is_recovery_operation(m.skirmish_setup.mission) do return
	profile := skirmish_recovery_profile(
		m.skirmish_setup.contract_seed,
		m.skirmish_setup.mission,
	)
	if !skirmish_recovery_profile_budget(m, profile).viable {
		profile = .Clear_Approach
		if !skirmish_recovery_profile_budget(m, profile).viable {
			m.skirmish_recovery_profile = .None
			return
		}
	}
	m.skirmish_recovery_profile = profile
	switch profile {
	case .Picketed_Target:
		m.skirmish_objective_pressure = .Picket_Screen
	case .Drifting_Target:
		#partial switch m.skirmish_setup.mission {
		case .Seedship_Recovery, .Contested_Salvage:
			m.seedship_velocity.x *= 140
			m.seedship_velocity.y *= 140
			m.seedship_velocity.z *= 140
		case .Disabled_Ship_Rescue, .Repair_And_Tow:
			identity := combat_mix(
				m.skirmish_setup.contract_seed ~ 0xbf58476d1ce4e5b9,
			)
			side := identity & 1 == 0 ? f32(-1) : f32(1)
			m.recovery_target_velocity = {
				6 + f32((identity >> 8) & 0xff) / 255 * 3,
				side * (2.5 + f32((identity >> 16) & 0xff) / 255 * 2),
				(f32((identity >> 24) & 0xff) / 255 - .5) * 2,
			}
		case:
		}
		combat_add_event_at(
			m,
			"Recovery target is drifting across the engagement volume",
			skirmish_recovery_target_position(m),
		)
	case .Heavy_Tow:
		skirmish_position_tow_interceptors(m)
		combat_add_event_at(
			m,
			"Tow mass will reduce extraction speed after recovery",
			skirmish_recovery_target_position(m),
		)
	case .Clear_Approach, .None:
	}
}

skirmish_apply_heavy_tow :: proc(m: ^Combat_Mission, recovery: int, target: int = -1) {
	if m == nil || m.skirmish_recovery_profile != .Heavy_Tow || m.recovery_tow_slowed do return
	if recovery < 0 || recovery >= m.friendly_count do return
	m.recovery_tow_slowed = true
	m.units[recovery].speed *= .45
	m.units[recovery].max_acceleration *= .62
	if target >= 0 && target < m.friendly_count && target != recovery {
		m.units[target].speed *= .45
		m.units[target].max_acceleration *= .62
	}
	combat_add_event_at(
		m,
		"Recovered mass reduced the tow formation's extraction speed",
		m.units[recovery].position,
	)
}

skirmish_configure_mission :: proc(m: ^Combat_Mission) {
	kind := m.skirmish_setup.mission
	m.objective_unit = skirmish_scan_loadout_index(&m.skirmish_setup)
	switch kind {
	case .Seedship_Recovery, .Fleet_Engagement, .Citadel_Assault:
		return
	case .Rearguard_Withdrawal:
		m.interaction_count = 0
		m.phase = .Extraction
		for &u in m.units[:m.friendly_count] {
			u.order = .Extract
			u.destination = m.extraction
			u.withdrawing = true
		}
		for &group in m.groups {
			group.objective = .Extract
			group.destination = m.extraction
			group.priority = .Threats_To_Objective
		}
	case .Capital_Interception:
		m.interaction_count = 0
		m.fabrication_recovered = true
		m.seedship_found = true
		m.recovery_progress = 45
		m.phase = .Capital_Contact
		for &group in m.groups {
			group.objective = .Attack
			group.priority = .Capital
		}
	case .Reconnaissance, .Silent_Infiltration:
		m.interaction_count = 0
		m.fabrication_recovered = true
		m.seedship_found = true
		m.phase = .Reconnaissance
		scout := clamp(m.objective_unit, 0, m.friendly_count - 1)
		m.units[scout].order = .Control
		m.units[scout].destination = m.anomaly
		if kind == .Silent_Infiltration {
			m.units[scout].silent_running = true
			m.units[scout].silent_running_timer = 45
		}
	case .Disabled_Ship_Rescue, .Repair_And_Tow:
		m.interaction_count = 0
		m.fabrication_recovered = true
		m.seedship_found = true
		m.recovery_unit = skirmish_recovery_element(m)
		target := m.friendly_count > 3 ? 3 : m.friendly_count - 1
		if target == m.recovery_unit do target = target == 0 ? 1 : 0
		m.objective_unit = max(target, 0)
		m.units[m.objective_unit].disabled = true
		m.units[m.objective_unit].hull = 0
		m.units[m.objective_unit].formation_active = max(
			m.units[m.objective_unit].formation_active - 1,
			0,
		)
		_ = combat_add_interaction(
			m,
			{
				kind = .Rescue,
				position = m.units[m.objective_unit].position,
				target = m.objective_unit,
				verb = kind == .Repair_And_Tow ? "REPAIR" : "RESCUE",
				title = kind == .Repair_And_Tow ? "REPAIR DISABLED SHIP" : "RESCUE DISABLED ELEMENT",
				consequence = "A recovery element must reach the disabled ship; both ships withdraw after restoration.",
			},
		)
	case .Relay_Control:
		m.fabrication_recovered = true
		m.seedship_found = true
		m.interaction_count = 2
		m.phase = .Relay_Control
	case .Convoy_Escort:
		m.interaction_count = 0
		m.fabrication_recovered = true
		m.seedship_found = true
		m.objective_unit = skirmish_recovery_element(m)
		convoy := m.objective_unit
		m.units[convoy].order = .Extract
		m.units[convoy].destination = m.extraction
		m.units[convoy].withdrawing = true
		_ = combat_add_interaction(
			m,
			{
				kind = .Escort,
				position = m.units[convoy].position,
				target = convoy,
				verb = "ESCORT",
				title = "ESCORT CONVOY",
				consequence = "Screen the assigned convoy element until it reaches extraction.",
			},
		)
	case .Contested_Salvage:
		m.recovery_unit = skirmish_recovery_element(m)
		m.relay_progress = {100, 100}
		m.relays_synchronized = true
		m.seedship_found = true
		m.phase = .Recovery
		m.interaction_count = 0
		_ = combat_add_interaction(
			m,
			{
				kind = .Salvage,
				position = m.seedship,
				target = -1,
				verb = "SALVAGE",
				title = "RECOVER FABRICATION SALVAGE",
				consequence = "Hold a recovery element beside the wreck until its fabrication core is secured.",
			},
		)
	case .Raid_And_Deploy:
		m.fabrication_recovered = true
		m.seedship_found = true
		m.interaction_count = 1
		m.objective_unit = skirmish_deployment_element(m)
		deployer := m.objective_unit
		m.units[deployer].order = .Control
		m.units[deployer].destination = m.relays[0]
		m.phase = .Relay_Control
		m.interactions[0].kind = .Deploy
		m.interactions[0].verb = "DEPLOY"
		m.interactions[0].title = "DEPLOY FORWARD RELAY"
		m.interactions[0].consequence = "Hold the forward volume until deployment completes, then extract the team."
		origin: Combat_Vec3
		for unit in m.units[:m.friendly_count] {
			origin.x += unit.position.x
			origin.y += unit.position.y
			origin.z += unit.position.z
		}
		count := f32(max(m.friendly_count, 1))
		origin.x /= count
		origin.y /= count
		origin.z /= count
		m.extraction = {
			m.relays[0].x * .7 + origin.x * .3,
			m.relays[0].y * .7 + origin.y * .3,
			m.relays[0].z * .7 + origin.z * .3,
		}
	}
}

Skirmish_Generation_Budget :: struct {
	workload, max_factions: int,
	geometry_scale:         f32,
}

skirmish_generation_budget :: proc(
	mission: Skirmish_Mission_Kind,
) -> Skirmish_Generation_Budget {
	switch mission {
	case .Seedship_Recovery:
		return {3, 2, .40}
	case .Reconnaissance, .Silent_Infiltration:
		return {3, 2, .30}
	case .Relay_Control, .Raid_And_Deploy:
		return {2, 2, .72}
	case .Contested_Salvage:
		return {3, 2, .45}
	case .Disabled_Ship_Rescue,
	     .Repair_And_Tow,
	     .Convoy_Escort,
	     .Capital_Interception:
		return {2, 3, .88}
	case .Fleet_Engagement, .Rearguard_Withdrawal, .Citadel_Assault:
		return {1, 4, 1}
	}
	return {2, 3, .88}
}

skirmish_scale_objective_point :: proc(
	point, origin: Combat_Vec3,
	scale: f32,
) -> Combat_Vec3 {
	return {
		origin.x + (point.x - origin.x) * scale,
		origin.y + (point.y - origin.y) * scale,
		origin.z + (point.z - origin.z) * scale,
	}
}

skirmish_apply_generation_budget :: proc(
	m: ^Combat_Mission,
	budget: Skirmish_Generation_Budget,
) {
	if budget.geometry_scale >= 1 || m.friendly_count <= 0 do return
	origin: Combat_Vec3
	for unit in m.units[:m.friendly_count] {
		origin.x += unit.position.x
		origin.y += unit.position.y
		origin.z += unit.position.z
	}
	denominator := f32(m.friendly_count)
	origin.x /= denominator
	origin.y /= denominator
	origin.z /= denominator
	for &relay in m.relays do relay = skirmish_scale_objective_point(
		relay,
		origin,
		budget.geometry_scale,
	)
	m.seedship = skirmish_scale_objective_point(
		m.seedship,
		origin,
		budget.geometry_scale,
	)
	m.anomaly = skirmish_scale_objective_point(
		m.anomaly,
		origin,
		budget.geometry_scale,
	)
	for &velocity in m.relay_velocity {
		velocity.x *= budget.geometry_scale
		velocity.y *= budget.geometry_scale
		velocity.z *= budget.geometry_scale
	}
	m.seedship_velocity.x *= budget.geometry_scale
	m.seedship_velocity.y *= budget.geometry_scale
	m.seedship_velocity.z *= budget.geometry_scale
}

skirmish_objective_pressure :: proc(
	mission: Skirmish_Mission_Kind,
	contract_seed: u64,
) -> Skirmish_Objective_Pressure {
	#partial switch mission {
	case .Seedship_Recovery, .Contested_Salvage, .Reconnaissance:
		roll := combat_mix(
			contract_seed ~ (u64(int(mission) + 1) * 0xd6e8feb86659fd93),
		)
		if roll % 3 == 0 do return .Picket_Screen
	case:
	}
	return .Open_Approach
}

skirmish_apply_objective_pressure :: proc(m: ^Combat_Mission) {
	if m == nil || m.skirmish_objective_pressure != .Picket_Screen do return
	objective := m.seedship
	if m.skirmish_setup.mission == .Reconnaissance do objective = m.anomaly
	if m.skirmish_setup.mission == .Disabled_Ship_Rescue ||
	   m.skirmish_setup.mission == .Repair_And_Tow {
		objective = m.units[clamp(m.objective_unit, 0, m.friendly_count - 1)].position
	}
	screen_group := 1
	group := &m.raider_groups[screen_group]
	group.objective = .Control
	group.destination = objective
	group.stance = .Screen
	group.priority = .Threats_To_Objective
	screen_index := 0
	for &unit in m.units[m.friendly_count:m.unit_count] {
		if screen_index >= 2 do break
		unit.group = screen_group
		side := screen_index % 2 == 0 ? f32(-1) : f32(1)
		ring := f32(36 + (screen_index / 2) * 20)
		unit.position = {
			objective.x + ring,
			objective.y + side * (28 + f32(screen_index) * 7),
			objective.z + side * 12,
		}
		unit.destination = objective
		unit.tactical_destination = objective
		screen_index += 1
	}
	if screen_index > 0 {
		combat_add_event_at(m, "Hostile pickets hold the objective approach", objective)
	}
}

skirmish_infiltration_cover :: proc(
	contract_seed: u64,
) -> Skirmish_Infiltration_Cover {
	roll := combat_mix(contract_seed ~ 0xa0761d6478bd642f)
	return roll & 1 == 0 ? .Objective_Shroud : .Masked_Corridor
}

skirmish_apply_infiltration_cover :: proc(m: ^Combat_Mission) {
	if m == nil || m.skirmish_setup.mission != .Silent_Infiltration do return
	origin: Combat_Vec3
	for unit in m.units[:m.friendly_count] {
		origin.x += unit.position.x
		origin.y += unit.position.y
		origin.z += unit.position.z
	}
	count := f32(max(m.friendly_count, 1))
	origin.x /= count
	origin.y /= count
	origin.z /= count
	// The ordinary anomaly is a radiation hazard. A covert-scan contract
	// authors a safe observation volume and moves that hazard to a route the
	// commander may choose to avoid.
	m.terrain[2].center = {
		m.anomaly.x,
		m.anomaly.y + 220,
		m.anomaly.z + 35,
	}
	switch m.skirmish_infiltration_cover {
	case .Objective_Shroud:
		m.terrain[0].center = m.anomaly
		m.terrain[0].radius = max(m.terrain[0].radius, f32(150))
		combat_add_event_at(m, "Debris shrouds the anomaly volume", m.anomaly)
	case .Masked_Corridor:
		m.terrain[0].center = {
			(origin.x + m.anomaly.x) * .5,
			(origin.y + m.anomaly.y) * .5,
			(origin.z + m.anomaly.z) * .5,
		}
		m.terrain[0].radius = max(m.terrain[0].radius, f32(175))
		combat_add_event_at(m, "Debris crosses the anomaly approach", m.terrain[0].center)
	case .None:
	}
}

combat_new_skirmish_mission :: proc(
	seed: u64,
	requested_setup: Skirmish_Setup,
	heroism_scale: i32 = 0,
) -> Combat_Mission {
	setup := requested_setup
	// Silent Infiltration remains an enum value for save/replay compatibility,
	// but it is retired from generated missions until its covert-route model is
	// rebuilt. Normalize direct legacy requests to Reconnaissance.
	if setup.mission == .Silent_Infiltration do setup.mission = .Reconnaissance
	budget := skirmish_generation_budget(setup.mission)
	bounded_factions := clamp(
		setup.faction_count,
		SKIRMISH_MIN_FACTIONS,
		min(SKIRMISH_MAX_FACTIONS, budget.max_factions),
	)
	m: Combat_Mission
	if setup.mission == .Citadel_Assault {
		m = combat_new_finale_mission(seed)
	} else {
		m = combat_new_mission(seed, heroism_scale)
	}
	m.skirmish = true
	m.skirmish_setup = setup
	m.skirmish_setup.seed = seed
	m.skirmish_setup.faction_count = bounded_factions
	if m.skirmish_setup.contract_seed == 0 do m.skirmish_setup.contract_seed = seed
	m.skirmish_objectives = skirmish_generate_objectives(
		m.skirmish_setup.contract_seed,
		setup.mission,
	)
	m.skirmish_objective_pressure = skirmish_objective_pressure(
		setup.mission,
		m.skirmish_setup.contract_seed,
	)
	if setup.mission == .Silent_Infiltration {
		m.skirmish_infiltration_cover = skirmish_infiltration_cover(
			m.skirmish_setup.contract_seed,
		)
	}
	if setup.mission == .Citadel_Assault && m.friendly_count > SKIRMISH_LOADOUT_SLOTS {
		old_friendly := m.friendly_count
		hostile_count := m.unit_count - old_friendly
		for offset in 0 ..< hostile_count {
			source := old_friendly + offset
			destination := SKIRMISH_LOADOUT_SLOTS + offset
			m.units[destination] = m.units[source]
			m.wreckage_pending[destination] = m.wreckage_pending[source]
			m.wreckage_pending_tonnage[destination] = m.wreckage_pending_tonnage[source]
			m.wreckage_pending_position[destination] = m.wreckage_pending_position[source]
			m.withdraw_request_made[destination] = m.withdraw_request_made[source]
			for side in 0 ..< 2 do m.contacts[side][destination] = m.contacts[side][source]
		}
		combat_truncate_elements(&m, SKIRMISH_LOADOUT_SLOTS + hostile_count)
		m.friendly_count = SKIRMISH_LOADOUT_SLOTS
	}

	// The seven prepared command elements remain stable for objective and group
	// logic, but every element's hull and formation size comes from the loadout.
	for entry, i in setup.loadout {
		if i >= m.friendly_count do break
		prior := m.units[i]
		archetype := skirmish_archetype_for_mission(entry.archetype, setup.mission)
		role := skirmish_role_for_hull(archetype)
		u := combat_unit(
			fmt.tprintf("Player %s element", ship_hull_archetype_name(archetype)),
			"Player command",
			"Skirmish loadout",
			"Assigned for this skirmish.",
			.Friendly,
			role,
			prior.position,
		)
		operational := skirmish_operational_role_for_mission(archetype, setup.mission)
		combat_configure_archetype(&u, archetype, operational)
		u.group = prior.group
		u.doctrine = prior.doctrine
		u.destination = prior.destination
		u.order = prior.order
		u.guard = prior.guard
		u.formation_ships = max(entry.ships, 1)
		u.formation_active = u.formation_ships
		if setup.mission == .Reconnaissance &&
		   (.Sensors in combat_unit_modules(u) || .Command in combat_unit_modules(u)) {
			u.recon_probes = 1
		}
		if role == .Capital do combat_configure_capital(&u, .Linebreaker)
		m.units[i] = u
	}
	skirmish_apply_generation_budget(&m, budget)
	if setup.mission == .Seedship_Recovery || setup.mission == .Contested_Salvage {
		m.recovery_unit = skirmish_recovery_element(&m)
		for &u in m.units[:m.friendly_count] do if u.order == .Guard do u.guard = m.recovery_unit
	}
	// Each additional opposing faction contributes another contingent. The
	// tactical engine resolves those contingents as hostile to the player.
	for &u in m.units[m.friendly_count:m.unit_count] {
		u.formation_ships *= bounded_factions - 1
		u.formation_active = u.formation_ships
	}
	if setup.mission == .Fleet_Engagement {
		// Fleet Engagement is a direct battle, not the Seedship mission with a
		// different score screen. Remove its contextual objectives and send each
		// prepared element toward an opposing formation. The ordinary command
		// model can replace these opening orders immediately.
		m.interaction_count = 0
		m.phase = .Capital_Contact
		m.complication_triggered = true
		for &group in m.groups {
			group.objective = .Attack
			group.priority = .Capital
		}
		hostile_count := m.unit_count - m.friendly_count
		for &u, i in m.units[:m.friendly_count] {
			target := m.friendly_count + i % max(hostile_count, 1)
			u.order = .Attack
			u.target = target
			u.destination = m.units[target].position
		}
	}
	skirmish_configure_mission(&m)
	skirmish_author_objective_interactions(&m)
	skirmish_apply_recovery_profile(&m)
	skirmish_apply_objective_pressure(&m)
	skirmish_apply_infiltration_cover(&m)
	combat_build_ship_roster(&m)
	combat_add_event(&m, fmt.tprintf("%d factions entered the skirmish area.", bounded_factions))
	return m
}

combat_is_fleet_engagement :: proc(m: ^Combat_Mission) -> bool {
	return m.skirmish && m.skirmish_setup.mission == .Fleet_Engagement
}

combat_is_direct_engagement :: proc(m: ^Combat_Mission) -> bool {
	return(
		m.skirmish &&
		(m.skirmish_setup.mission == .Fleet_Engagement ||
				m.skirmish_setup.mission == .Rearguard_Withdrawal) \
	)
}
