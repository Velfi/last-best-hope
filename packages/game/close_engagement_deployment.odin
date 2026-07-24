package game

import "core:fmt"
import "core:math"
combat_deployment_preview :: proc(
	c: ^Campaign,
	ships: []Ship_ID,
	groups: []int,
) -> Combat_Deployment_Preview {
	p: Combat_Deployment_Preview
	if len(ships) != len(groups) ||
	   len(ships) == 0 ||
	   len(ships) > MAX_SHIPS {p.warning = "Select at least one available ship."; return p}
	seen: [MAX_SHIPS]bool
	for id, i in ships {
		at := ship_index(
			c,
			id,
		); if at < 0 || at >= c.ship_count || seen[at] {p.warning = "The deployment manifest contains an unavailable ship."; return p}
		ship :=
			c.ships[at]; if !ship.active || ship.departure != .None || !compact_operation_ship_available(c, ship.id) {p.warning = fmt.tprintf("%s is not seconded and available for this undertaking.", ship.name); return p}
		group :=
			groups[i]; if group < 0 || group >= COMBAT_GROUP_COUNT {p.warning = "Every ship needs a task group."; return p}; seen[at] = true; p.group_ships[group] += 1
		mods := ship_operational_role_modules(ship.operational_role)
		base_endurance :=
			max(1, i32(ship.mass_tonnes / 10000)) + max(ship.power / 3, 1) - ship.damage
		p.endurance += max(base_endurance - ship.impairments.endurance, 0)
		if .Sensors in mods do p.recon += max(3 - ship.impairments.sensors, 0)
		if .Command in mods do p.control += max(3 - ship.impairments.mobility, 0)
		if .Recovery in mods || .Medical in mods || .Repair in mods do p.support += max(3 - ship.impairments.support, 0)
		switch ship_hull_archetype_family(ship.hull_archetype) {case .Strike_Craft:
			p.strike += max(2 - ship.impairments.strike, 0); case .Light_Combatant, .Frigate:
			p.control += max(2 - ship.impairments.mobility, 0)
			p.strike += max(1 - ship.impairments.strike, 0); case .Line_Warship:
			p.control += max(2 - ship.impairments.mobility, 0)
			p.strike += max(3 - ship.impairments.strike, 0); case .Carrier_And_Command:
			p.support += max(2 - ship.impairments.support, 0)
			p.strike += max(2 - ship.impairments.strike, 0); case .Diaspora:
			p.support += 2; case .Unspecified:}
		if ship_impairment_total(ship.impairments) > 0 {
			forecast_add_factor(
				&p.factors,
				&p.factor_count,
				fmt.tprintf("%s carries capability damage", ship.name),
				-f64(ship_impairment_total(ship.impairments)),
				1,
				.Observed,
				ship.id,
				latest_ship_event(c, ship.id),
			)
		}
	}
	p.ship_count = len(ships); p.propellant_cost = max(1, (len(ships) + 3) / 4)
	if fleet_propellant(c) <
	   i32(
		   p.propellant_cost,
	   ) {p.warning = fmt.tprintf("Deployment requires %d Propellant; %d is available.", p.propellant_cost, max(fleet_propellant(c), 0)); return p}
	if p.group_ships[0] == 0 ||
	   p.group_ships[1] == 0 ||
	   p.group_ships[2] ==
		   0 {p.warning = "Screen, Strike, and Recovery each require a ship."; return p}
	p.valid = true
	if p.support < 3 {p.warning = "Recovery support is thin."; p.shortfall_count += 1}
	if p.recon <
	   3 {if p.shortfall_count == 0 do p.warning = "Sensor coverage is thin."; p.shortfall_count += 1}
	if p.strike <
	   5 {if p.shortfall_count == 0 do p.warning = "Strike capability is thin."; p.shortfall_count += 1}
	if p.shortfall_count == 0 do p.warning = "The deployment covers all required task groups."
	forecast_add_factor(
		&p.factors,
		&p.factor_count,
		"recon coverage",
		f64(p.recon - 3),
		1,
		.Observed,
	)
	forecast_add_factor(
		&p.factors,
		&p.factor_count,
		"strike coverage",
		f64(p.strike - 5),
		1,
		.Observed,
	)
	forecast_add_factor(
		&p.factors,
		&p.factor_count,
		"recovery coverage",
		f64(p.support - 3),
		1,
		.Observed,
	)
	return p
}

combat_begin_campaign_deployment :: proc(
	c: ^Campaign,
	ships: []Ship_ID,
	groups: []int,
) -> (
	Combat_Deployment_Preview,
	bool,
) {
	if c.combat_deployment_active {return {warning = "An operation is already deployed."}, false}
	p := combat_deployment_preview(c, ships, groups); if !p.valid do return p, false
	if c.compact.active.status != .Planning ||
	   c.compact.active.operation != .Combat ||
	   c.compact.active.route != .Close_Engagement ||
	   !c.compact.active.charter.valid {
		p.warning = "Combat deployment requires an active Compact charter."
		return p, false
	}
	authorized :=
		Combat_Doctrine.Balanced; if has_precedent(c, .No_One_Left_Behind) do authorized = .Cautious_Screen; if has_precedent(c, .Emergency_Command) do authorized = .Hunter_Killer
	switch c.compact.active.charter.doctrine.exposure {
	case .Conservative:
		authorized = .Cautious_Screen
	case .Proportional:
		authorized = .Balanced
	case .Mission_Critical:
		authorized = .Hunter_Killer
	}
	if c.compact.active.reserved.propellant < i32(p.propellant_cost) {
		p.warning = "The selected secondments did not offer enough Propellant."
		return p, false
	}
	c.combat_deployment_active =
		true; c.combat_deployment_authorized_doctrine = authorized; for &d in c.combat_deployment_doctrines do d = authorized; c.combat_deployment_doctrine_deviation = false; c.combat_deployment_seed = c.initial_seed ~ (u64(c.season + 1) * 0x9e3779b97f4a7c15); c.combat_deployment_count = len(ships); c.combat_deployment_propellant_cost = i32(p.propellant_cost)
	mission_kind := combat_campaign_mission_kind(
		c,
		c.initial_seed ~ (u64(c.season + 1) * 0x9e3779b97f4a7c15),
	)
	for id, i in ships {c.combat_deployment_ships[i] = id
		c.combat_deployment_groups[i] = groups[i]
		at := ship_index(c, id)
		if at >= 0 do c.ships[at].current_commitment = fmt.tprintf("Assigned to %s for %s.", c.combat_deployment_groups[i] == 0 ? "Screen" : c.combat_deployment_groups[i] == 1 ? "Strike" : "Support", skirmish_mission_name(mission_kind))}
	c.compact.active.status = .Operating
	record_event(
		c,
		.Capacity_Committed,
		fmt.tprintf("%d ships deployed with %d Propellant.", len(ships), p.propellant_cost),
		value = i32(p.propellant_cost),
		cause_sequence = c.compact.active.charter.intent_event,
	)
	return p, true
}

combat_set_campaign_deployment_doctrine :: proc(
	c: ^Campaign,
	group: int,
	doctrine: Combat_Doctrine,
) -> bool {
	if !c.combat_deployment_active || group < 0 || group >= COMBAT_GROUP_COUNT do return false
	c.combat_deployment_doctrines[group] = doctrine; c.combat_deployment_doctrine_deviation = false
	for current in c.combat_deployment_doctrines do if current != c.combat_deployment_authorized_doctrine {c.combat_deployment_doctrine_deviation = true; break}
	return true
}

combat_clear_campaign_deployment :: proc(c: ^Campaign) {
	for id in c.combat_deployment_ships[:c.combat_deployment_count] {at := ship_index(c, id); if at >= 0 do c.ships[at].current_commitment = ""}
	c.combat_deployment_active =
		false; c.combat_deployment_count = 0; c.combat_deployment_propellant_cost = 0; c.combat_deployment_doctrine_deviation = false; c.combat_deployment_authorized_doctrine = .Balanced
}

COMBAT_CAMPAIGN_EVENT :: "The fleet completed a combat operation."

combat_subsystem_impairment :: proc(value: f32) -> i32 {
	if value < 35 do return 2
	if value < 70 do return 1
	return 0
}

combat_campaign_impairments :: proc(unit: Combat_Unit) -> Ship_Impairments {
	return {
		mobility = combat_subsystem_impairment(unit.subsystems.engines),
		sensors = combat_subsystem_impairment(unit.subsystems.sensors),
		strike = max(
			combat_subsystem_impairment(unit.subsystems.weapons),
			combat_subsystem_impairment(unit.subsystems.flight_deck),
		),
		support = max(
			combat_subsystem_impairment(unit.subsystems.command),
			combat_subsystem_impairment(unit.subsystems.life_support),
		),
		endurance = combat_subsystem_impairment(unit.subsystems.radiators),
	}
}

combat_campaign_available :: proc(c: ^Campaign) -> bool {
	if c.combat_deployment_active do return true
	if c.passage.active do return false
	authorized_by_compact :=
		c.compact.active.operation == .Combat &&
		(c.compact.active.status == .Planning || c.compact.active.status == .Operating)
	last_operation: u64
	for event in c.events[:c.event_count] do if event.kind == .Fleet_Hazard && event.detail == COMBAT_CAMPAIGN_EVENT do last_operation = event.sequence
	if last_operation > 0 && !authorized_by_compact do return false
	available := 0; for ship in c.ships[:c.ship_count] do if ship.active && ship.departure == .None && !ship.committed do available += 1
	return available > 0
}

// Apply once, after combat_finish. Tactical defeat creates repair history and
// scars; it does not silently delete one of the chronicle's named ships.
combat_apply_campaign_result :: proc(
	c: ^Campaign,
	m: ^Combat_Mission,
) -> Combat_Campaign_Application {
	a: Combat_Campaign_Application
	if !m.complete || m.campaign_result_applied || !combat_campaign_available(c) do return a
	m.campaign_result_applied = true; a.applied = true
	a.ships_deployed = m.campaign_ship_count
	record_event(
		c,
		.Fleet_Hazard,
		COMBAT_CAMPAIGN_EVENT,
		value = i32(combat_result_outcome(m)),
		cause_sequence = m.campaign_origin_event,
	)
	operation_event := c.event_sequence
	if m.campaign_doctrine_deviation {c.strategic.cohesion = max(c.strategic.cohesion - 1, 0); record_event(c, .Institution_Changed, "Fleet command departed from standing battle authority.", value = -1, cause_sequence = operation_event)}
	for id, i in m.campaign_ships[:m.campaign_ship_count] {
		at := ship_index(c, id); if at < 0 do continue
		ship := &c.ships[at]; unit := m.units[m.campaign_ship_elements[i]]; roster := m.ships[m.campaign_ship_roster_indices[i]]
		individual_max :=
			unit.max_hull /
			f32(max(unit.formation_ships, 1)); loss := 1 - roster.hull / max(individual_max, .001)
		damage := loss >= .55 || roster.hull <= 0 || !unit.extracted ? 2 : loss >= .18 ? 1 : 0
		ship.experience += 1
		derived_impairments := combat_campaign_impairments(unit)
		ship.impairments.mobility = min(
			ship.impairments.mobility + derived_impairments.mobility,
			3,
		)
		ship.impairments.sensors = min(ship.impairments.sensors + derived_impairments.sensors, 3)
		ship.impairments.strike = min(ship.impairments.strike + derived_impairments.strike, 3)
		ship.impairments.support = min(ship.impairments.support + derived_impairments.support, 3)
		ship.impairments.endurance = min(
			ship.impairments.endurance + derived_impairments.endurance,
			3,
		)
		mission_name := skirmish_mission_name(m.skirmish_setup.mission)
		if damage ==
		   0 {add_ship_history(c, id, fmt.tprintf("Returned from %s.", mission_name)); continue}
		ship.damage = min(ship.damage + i32(damage), 4); a.ships_damaged += 1
		detail := fmt.tprintf(
			"%s returned from %s with %d damage.",
			ship.name,
			mission_name,
			damage,
		)
		add_ship_history(
			c,
			id,
			detail,
		); record_event(c, .Ship_Damaged, detail, id, i32(damage), cause_sequence = operation_event)
		if ship_impairment_total(derived_impairments) > 0 do record_event(c, .Resource_Changed, fmt.tprintf("%s's combat damage impaired mobility %d, sensors %d, strike %d, support %d, and endurance %d.", ship.name, derived_impairments.mobility, derived_impairments.sensors, derived_impairments.strike, derived_impairments.support, derived_impairments.endurance), id, ship_impairment_total(derived_impairments), cause_sequence = c.event_sequence)
		if ship.damage >= 4 &&
		   ship.scar ==
			   .None {ship.scar = .Hull_Breach; a.new_scars += 1; scar_detail := fmt.tprintf("%s still carries the breach opened during %s.", ship.name, mission_name); add_ship_history(c, id, scar_detail); record_event(c, .Ship_Scarred, scar_detail, id, i32(ship.scar), cause_sequence = operation_event)}
	}
	if m.result.population > 0 &&
	   c.community_count >
		   0 {community := &c.communities[min(3, c.community_count - 1)]; community.population += i32(m.result.population); a.population_joined = m.result.population; record_event(c, .Community_Joined, "The seedship survivors joined the traveling fleet.", value = i32(m.result.population), community = community.id, cause_sequence = operation_event)}
	if m.result.archive >
	   0 {a.knowledge_gained = 4; record_knowledge_gain(c, 4, .Archives); record_event(c, .Resource_Changed, "The recovered archive entered fleet custody.", value = 4, cause_sequence = operation_event)}
	if m.result.fabrication >
	   0 {a.industry_gained = 4; fleet_stock_gain(c, {supplies = 4}, .Reward, operation_event); record_event(c, .Resource_Changed, "The recovered fabrication core entered service.", value = 4, cause_sequence = operation_event)}
	objective_met := skirmish_primary_objective_met(m)
	_ = apply_operation_return(
		c,
		.Close_Engagement,
		c.combat_deployment_seed,
		objective_met,
		m.campaign_ships[:m.campaign_ship_count],
		i64(combat_mission_duration(m) * 60),
		withdrawals = i32(
			max(m.result.ships_total - m.result.ships_preserved - m.result.player_ships_lost, 0),
		),
		protected_exposure = i32(m.result.player_ships_lost),
		deviations = m.campaign_doctrine_deviation ? 1 : 0,
		evidence = m.result.archive > 0 ? 1 : 0,
	)
	front_index := surface_council_front(c, .Fleet_Authority, operation_event)
	if front_index >=
	   0 {c.fronts[front_index].last_public_record = m.result.consequence; a.aftermath_opened = true}
	combat_clear_campaign_deployment(c)
	detect_essential_exposure(c, operation_event)
	return a
}

// combat_new_stress_mission keeps the authored Seedship objective but surrounds
// it with fleet-scale formations. The first seven friendly indices remain the
// original persistent command elements so recovery and command requests retain
// their ordinary semantics.
combat_new_scaled_stress_mission :: proc(seed: u64, total_ships: int) -> Combat_Mission {
	m := combat_new_mission(seed)
	m.scenario = .Stress
	bounded_ships := clamp(total_ships, 56, COMBAT_MAX_SHIPS)
	initial_enemies: [8]Combat_Unit
	initial_enemy_count := m.unit_count - m.friendly_count
	for enemy, i in m.units[m.friendly_count:m.unit_count] do initial_enemies[i] = enemy
	combat_truncate_elements(&m, m.friendly_count)

	friendly_names := [11]string {
		"Peregrine Flight",
		"Harrow Flight",
		"Vigil Flight",
		"Northstar Bombers",
		"Redoubt Bombers",
		"Bastion",
		"Mercy of Dawn",
		"Long Measure",
		"Far Lantern",
		"Covenant",
		"Last Horizon",
	}
	friendly_roles := [11]Combat_Role {
		.Fighter,
		.Fighter,
		.Fighter,
		.Bomber,
		.Bomber,
		.Corvette,
		.Corvette,
		.Carrier,
		.Carrier,
		.Capital,
		.Capital,
	}
	for name, i in friendly_names {
		row := i / 4; column := i % 4
		p := Combat_Vec3{-690 + f32(column) * 88, -360 + f32(row) * 155, f32((i % 3) - 1) * 72}
		u := combat_unit(
			name,
			"Fleet command",
			"Line formation",
			"Committed to the fleet engagement.",
			.Friendly,
			friendly_roles[i],
			p,
		)
		combat_configure_roster_archetype(&u, i)
		u.group = i < 3 ? 0 : i < 7 ? 1 : 2; u.doctrine = m.groups[u.group].doctrine
		if u.role == .Capital do combat_configure_capital(&u, .Linebreaker)
		combat_add_element(&m, u)
	}
	m.friendly_count = m.unit_count
	for enemy in initial_enemies[:initial_enemy_count] do combat_add_element(&m, enemy)

	enemy_roles := [6]Combat_Role{.Fighter, .Fighter, .Bomber, .Corvette, .Carrier, .Capital}
	for i in 0 ..< 34 {
		row := i / 7; column := i % 7
		p := Combat_Vec3{420 + f32(column) * 82, -430 + f32(row) * 185, f32((i % 5) - 2) * 64}
		role := enemy_roles[i % len(enemy_roles)]
		u := combat_unit(
			"Raider Fleet Element",
			"Unknown",
			"Battle line",
			"Entered with the massed raider formation.",
			.Raider,
			role,
			p,
		)
		combat_configure_roster_archetype(&u, i + 1)
		if role == .Capital {u.hull *= 1.2; u.max_hull = u.hull}
		combat_add_element(&m, u)
	}
	friendly_ships := max(bounded_ships * 32 / 100, m.friendly_count)
	hostile_ships := bounded_ships - friendly_ships
	for &u, i in m.units[:m.friendly_count] do u.formation_ships = friendly_ships / m.friendly_count + (i < friendly_ships % m.friendly_count ? 1 : 0)
	hostile_count := m.unit_count - m.friendly_count
	for &u, i in m.units[m.friendly_count:m.unit_count] do u.formation_ships = hostile_ships / hostile_count + (i < hostile_ships % hostile_count ? 1 : 0)
	combat_build_ship_roster(&m)
	combat_plan_groups(&m)
	combat_add_event(&m, "Massing contacts resolved into a fleet engagement.")
	return m
}

combat_new_stress_mission :: proc(
	seed: u64,
) -> Combat_Mission {return combat_new_scaled_stress_mission(seed, 1000)}

combat_finale_add_element :: proc(
	m: ^Combat_Mission,
	side: Combat_Side,
	role: Combat_Role,
	count, group: int,
	p: Combat_Vec3,
) {
	name :=
		side == .Friendly ? "Coalition Formation" : "Citadel Formation"; commander := side == .Friendly ? "Fleet command" : "Unknown"
	u := combat_unit(
		name,
		commander,
		"Battle line",
		"Committed to the fleet engagement.",
		side,
		role,
		p,
	)
	combat_configure_roster_archetype(&u, m.unit_count + (side == .Raider ? 3 : 0))
	u.formation_ships =
		count; u.formation_active = count; u.group = clamp(group, 0, COMBAT_GROUP_COUNT - 1); u.doctrine = m.groups[u.group].doctrine
	if role == .Capital do combat_configure_capital(&u, .Linebreaker)
	combat_add_element(m, u)
}

combat_new_finale_mission :: proc(seed: u64) -> Combat_Mission {
	m := Combat_Mission {
		seed           = seed,
		rng            = combat_mix(seed),
		scenario       = .Finale,
		phase          = .Reconnaissance,
		finale_phase   = .Approach,
		recovery_unit  = -1,
		request_unit   = -1,
		request_target = -1,
	}
	m.grid = {
		min_x       = -1050,
		max_x       = 1050,
		min_y       = -660,
		max_y       = 660,
		low_ceiling = -75,
		high_floor  = 75,
	}
	m.relays[0] = {
		180,
		-420,
		-80,
	}; m.relays[1] = {210, 410, 95}; m.extraction = {-940, 0, 0}; m.seedship = {720, 0, 80}; m.anomaly = {0, 0, -220}
	_ = combat_add_interaction(
		&m,
		{
			kind = .Capture,
			position = m.relays[0],
			target = 0,
			verb = "CAPTURE",
			title = "CAPTURE RELAY A",
			consequence = "Hold the relay control volume and interrupt the weapon cycle.",
		},
	)
	_ = combat_add_interaction(
		&m,
		{
			kind = .Capture,
			position = m.relays[1],
			target = 1,
			verb = "CAPTURE",
			title = "CAPTURE RELAY B",
			consequence = "Hold the relay control volume and interrupt the weapon cycle.",
		},
	)
	m.terrain[0] = {
		.Debris,
		{-80, -260, -40},
		190,
	}; m.terrain[1] = {.Open_Lane, {280, 0, 40}, 240}; m.terrain[2] = {.Radiation, {650, 0, 80}, 115}
	m.groups[0] = {
		name               = "SCREEN",
		objective          = .Intercept,
		doctrine           = .Cautious_Screen,
		destination        = m.relays[0],
		target             = -1,
		guard              = -1,
		pursuit_limit      = 240,
		withdraw_threshold = 55,
		priority           = .Strike_Craft,
	}
	m.groups[1] = {
		name               = "LINE",
		objective          = .Attack,
		doctrine           = .Balanced,
		destination        = {180, 0, 20},
		target             = -1,
		guard              = -1,
		pursuit_limit      = 360,
		withdraw_threshold = 30,
		priority           = .Capital,
	}
	m.groups[2] = {
		name               = "ASSAULT",
		objective          = .Control,
		doctrine           = .Hunter_Killer,
		destination        = m.relays[1],
		target             = -1,
		guard              = -1,
		pursuit_limit      = 480,
		withdraw_threshold = 20,
		priority           = .Support,
	}
	for &group in m.groups do combat_apply_group_doctrine(&group, group.doctrine)
	for i in 0 ..< 12 do combat_finale_add_element(&m, .Friendly, .Capital, 4, 1, {-820 + f32(i % 4) * 72, -360 + f32(i / 4) * 280, f32((i % 3) - 1) * 70})
	for i in 0 ..< 3 do combat_finale_add_element(&m, .Friendly, .Carrier, 4, 0, {-900, -300 + f32(i) * 300, f32(i - 1) * 90})
	for i in 0 ..< 8 do combat_finale_add_element(&m, .Friendly, .Fighter, 150, 0, {-680 + f32(i % 4) * 65, -520 + f32(i / 4) * 1040, f32((i % 4) - 2) * 48})
	for i in 0 ..< 3 do combat_finale_add_element(&m, .Friendly, .Bomber, 100, 2, {-760, -230 + f32(i) * 230, f32(i - 1) * 62})
	m.friendly_count = m.unit_count
	for i in 0 ..< 8 do combat_finale_add_element(&m, .Raider, .Capital, 4, 1, {420 + f32(i % 4) * 80, -390 + f32(i / 4) * 780, f32((i % 3) - 1) * 78})
	for i in 0 ..< 2 do combat_finale_add_element(&m, .Raider, .Carrier, 4, 0, {590, -250 + f32(i) * 500, f32(i * 2 - 1) * 85})
	for i in 0 ..< 6 do combat_finale_add_element(&m, .Raider, .Fighter, 80, 0, {260 + f32(i % 3) * 70, -560 + f32(i / 3) * 1120, f32((i % 3) - 1) * 55})
	for i in 0 ..< 2 do combat_finale_add_element(&m, .Raider, .Bomber, 60, 2, {500, -140 + f32(i) * 280, f32(i * 2 - 1) * 70})
	m.strategic_asset = {
		position    = {880, 0, 120},
		lock_target = -1,
	}
	combat_build_ship_roster(
		&m,
	); combat_plan_groups(&m); combat_issue_group_order(&m, 0, .Control, m.relays[0]); combat_issue_group_order(&m, 1, .Move, {80, 0, 20}); combat_issue_group_order(&m, 2, .Control, m.relays[1]); combat_add_event(&m, "Citadel weapon charge detected beyond the defending line.")
	return m
}
