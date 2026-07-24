package game_tests

import "core:testing"

@(test)
combat_wreckage_cover_reduces_incoming_pressure :: proc(t: ^testing.T) {
	m := combat_new_scaled_stress_mission(
		89,
		1000,
	); defer combat_mission_destroy(&m); target := m.friendly_count; individual := m.units[target].max_hull / f32(m.units[target].formation_ships)
	combat_apply_damage(
		&m,
		target,
		individual * 8,
	); m.units[target].pressure = 0; m.units[target].position = m.wreckage_fields[0].center; combat_apply_weapon_pressure(&m, 0, target); covered := m.units[target].pressure
	m.units[target].pressure = 0; m.units[target].position = {1000, 1000, 1000}; combat_apply_weapon_pressure(&m, 0, target); testing.expect(t, covered < m.units[target].pressure)
}

@(test)
combat_relays_reveal_seedship :: proc(t: ^testing.T) {m := combat_new_mission(5)
	defer combat_mission_destroy(&m)
	for &u in m.units[m.friendly_count:m.unit_count] do u.disabled = true
	m.units[0].position = m.relays[0]
	m.units[0].order = .Control
	m.units[0].destination = m.relays[0]
	m.units[1].position = m.relays[1]
	m.units[1].order = .Control
	m.units[1].destination = m.relays[1]
	for _ in 0 ..< 3000 do combat_tick_fixed(&m, .05)
	testing.expect(t, m.seedship_found)
	testing.expect(t, m.phase == .Recovery)}

@(test)
combat_seedship_stabilization_completes_in_about_two_hundred_seconds :: proc(t: ^testing.T) {
	m := combat_new_mission(5); defer combat_mission_destroy(&m)
	for &u in m.units[m.friendly_count:m.unit_count] do u.disabled = true
	m.seedship_found =
		true; m.phase = .Recovery; m.capital_arrived = true; m.complication_triggered = true; m.units[4].position = m.seedship; m.units[4].order = .Recover
	for _ in 0 ..< 4020 do combat_tick_fixed(&m, .05)
	testing.expect(t, m.fabrication_recovered)
}

@(test)
combat_raider_fighters_screen_instead_of_mobbing_recovery_ship :: proc(t: ^testing.T) {
	m := combat_new_mission(5); defer combat_mission_destroy(&m)
	m.seedship_found = true; m.recovery_progress = 10
	fighter := -1
	for u, i in m.units[m.friendly_count:m.unit_count] do if u.role == .Fighter {fighter = m.friendly_count + i; break}
	testing.expect(t, fighter >= 0)
	m.units[fighter].position = m.seedship; m.units[4].position = m.seedship
	combat_tick_fixed(&m, .05)
	testing.expect(t, m.units[fighter].target != 4)
}

@(test)
combat_outcome_reports_exact_recovery :: proc(t: ^testing.T) {m := combat_new_mission(9)
	defer combat_mission_destroy(&m)
	m.population_recovered = true
	m.archive_recovered = true
	m.fabrication_recovered = false
	m.units[4].extracted = true
	combat_finish(&m)
	testing.expect_value(t, m.result.population, 18420)
	testing.expect_value(t, m.result.archive, 1)
	testing.expect_value(t, m.result.fabrication, 0)
	testing.expect_value(t, m.result.friendly_preserved, 1)}

@(test)
campaign_combat_uses_persistent_ships_and_applies_results_once :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 91); m := combat_new_campaign_mission(&c); defer combat_mission_destroy(&m)
	available := 0
	for ship in c.ships[:c.ship_count] do if ship.active && ship.departure == .None && !ship.committed do available += 1
	testing.expect_value(
		t,
		m.campaign_ship_count,
		available,
	); testing.expect_value(t, m.units[0].name, c.ships[0].name)
	m.units[0].hull =
		m.units[0].max_hull *
		.4; m.units[0].extracted = true; m.ships[m.campaign_ship_roster_indices[0]].hull = 0
	m.population_recovered =
		true; m.archive_recovered = true; m.fabrication_recovered = true; m.units[4].extracted = true
	combat_finish(
		&m,
	); before_population := total_population(&c); before_knowledge := c.material_economy.knowledge.deployable_capacity
	a := combat_apply_campaign_result(&c, &m)
	testing.expect(
		t,
		a.applied && a.aftermath_opened,
	); testing.expect_value(t, a.population_joined, 18420); testing.expect_value(t, total_population(&c), before_population + 18420); testing.expect_value(t, c.material_economy.knowledge.deployable_capacity, before_knowledge + 4); testing.expect(t, c.ships[0].damage > 0); testing.expect(t, c.ships[0].history_record_count > 0); testing.expect(t, c.front_count > 0); testing.expect_value(t, c.fronts[c.front_count - 1].kind, Front_Kind.Fleet_Authority)
	testing.expect(t, !combat_campaign_available(&c))
	second := combat_apply_campaign_result(
		&c,
		&m,
	); testing.expect(t, !second.applied); testing.expect_value(t, total_population(&c), before_population + 18420)
}

@(test)
campaign_combat_accepts_any_positive_number_of_available_ships :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 93)
	for &ship, i in c.ships[:c.ship_count] do if i > 0 do ship.committed = true
	testing.expect(t, combat_campaign_available(&c))
	m := combat_new_campaign_mission(&c); defer combat_mission_destroy(&m)
	testing.expect_value(t, m.campaign_ship_count, 1)
	testing.expect_value(t, len(m.campaign_ships), 1)
	testing.expect_value(t, m.campaign_ships[0], c.ships[0].id)
	c.ships[0].committed = true
	testing.expect(t, !combat_campaign_available(&c))
}

@(test)
campaign_deployment_commits_selected_ships_and_propellant :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		94,
	); c.material_economy.fleet.stock.propellant = 8; ids := [3]Ship_ID{c.ships[0].id, c.ships[1].id, c.ships[2].id}; groups := [3]int{0, 1, 2}; propellant := fleet_propellant(&c)
	p, ok := begin_authorized_test_combat_deployment(
		&c,
		ids[:],
		groups[:],
	); testing.expect(t, ok && p.valid); testing.expect_value(t, c.combat_deployment_count, 3); testing.expect_value(t, fleet_propellant(&c), propellant); testing.expect(t, c.compact.active.reserved.propellant >= i32(p.propellant_cost)); testing.expect(t, c.combat_deployment_active)
	m := combat_new_campaign_mission(
		&c,
	); defer combat_mission_destroy(&m); testing.expect_value(t, m.campaign_ship_count, 3); testing.expect(t, m.units[0].readiness <= 100)
	_, again := combat_begin_campaign_deployment(
		&c,
		ids[:],
		groups[:],
	); testing.expect(t, !again); testing.expect_value(t, fleet_propellant(&c), propellant)
}

@(test)
campaign_deployment_persists_doctrine_and_exact_ship_damage :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		95,
	); c.material_economy.fleet.stock.propellant = 8; ids := [3]Ship_ID{c.ships[0].id, c.ships[1].id, c.ships[2].id}; groups := [3]int{0, 0, 2}; groups[1] = 1
	_, ok := begin_authorized_test_combat_deployment(
		&c,
		ids[:],
		groups[:],
	); testing.expect(t, ok); testing.expect(t, combat_set_campaign_deployment_doctrine(&c, 1, .Last_Stand)); testing.expect(t, c.combat_deployment_doctrine_deviation)
	testing.expect(
		t,
		combat_set_campaign_deployment_doctrine(&c, 1, c.combat_deployment_authorized_doctrine),
	); testing.expect(t, !c.combat_deployment_doctrine_deviation)
	m := combat_new_campaign_mission(
		&c,
	); defer combat_mission_destroy(&m); for i in 0 ..< m.friendly_count do m.units[i].extracted = true
	first :=
		m.campaign_ship_roster_indices[0]; m.ships[first].hull = 0; combat_finish(&m); a := combat_apply_campaign_result(&c, &m); testing.expect(t, a.applied); testing.expect(t, c.ships[0].damage > 0); testing.expect_value(t, c.ships[1].damage, i32(0))
}

@(test)
combat_secured_population_must_extract_aboard_recovery_ship :: proc(t: ^testing.T) {m :=
		combat_new_mission(10)
	defer combat_mission_destroy(&m)
	m.population_recovered = true
	m.units[0].extracted = true
	combat_finish(&m)
	testing.expect(t, m.result.population_secured)
	testing.expect_value(t, m.result.population, 0)
	testing.expect(
		t,
		m.result.consequence ==
		"Common Hearth did not reach extraction. The secured population remains in the operational area.",
	)}

@(test)
combat_relay_capture_then_withdrawal_is_a_partial_success :: proc(t: ^testing.T) {
	m := combat_new_mission(11); defer combat_mission_destroy(&m)
	m.relay_progress = {100, 100}
	for i in 0 ..< m.friendly_count do m.units[i].extracted = true
	combat_finish(&m)
	testing.expect(t, m.result.sensor_data)
	testing.expect_value(t, combat_result_outcome(&m), Combat_Outcome.Partial_Success)
	testing.expect(
		t,
		m.result.consequence ==
		"The relay fix returned with the fleet. The seedship remains in the operational area for a later recovery attempt.",
	)
}

@(test)
combat_disabling_recovery_ship_reassigns_recovery_duty :: proc(t: ^testing.T) {
	m := combat_new_mission(10); defer combat_mission_destroy(&m)
	previous := m.recovery_unit
	m.units[4].disabled = true; m.units[4].hull = 0; m.units[4].formation_active = 0
	combat_tick_fixed(&m, .05)
	testing.expect(t, !m.complete)
	testing.expect(t, m.recovery_unit != previous)
	testing.expect(t, !m.units[m.recovery_unit].disabled)
	testing.expect(t, m.result.population == 0)
}

@(test)
combat_operation_runs_from_relays_through_extraction :: proc(t: ^testing.T) {
	m := combat_new_mission(0x5eed)
	defer combat_mission_destroy(&m)
	for &u in m.units[m.friendly_count:m.unit_count] do u.disabled = true
	m.units[0].position =
		m.relays[0]; m.units[0].order = .Control; m.units[0].destination = m.relays[0]
	m.units[1].position =
		m.relays[1]; m.units[1].order = .Control; m.units[1].destination = m.relays[1]
	for _ in 0 ..< 3000 do combat_tick_fixed(&m, .05)
	testing.expect(t, m.seedship_found)
	m.units[4].position =
		m.seedship; m.units[4].order = .Recover; m.units[4].hull = 100000; m.units[4].max_hull = 100000
	for _ in 0 ..< 5100 do combat_tick_fixed(&m, .05)
	testing.expect(t, m.fabrication_recovered); testing.expect(t, m.capital_arrived)
	for i in 0 ..< m.friendly_count {m.units[i].position = m.extraction; combat_issue_order(&m, i, .Extract, m.extraction)}
	combat_tick_fixed(&m, .05)
	testing.expect(
		t,
		m.complete,
	); testing.expect_value(t, m.result.friendly_preserved, 7); testing.expect_value(t, m.result.population, 18420)
}

@(test)
combat_terrain_masks_missiles :: proc(t: ^testing.T) {m := combat_new_mission(3)
	defer combat_mission_destroy(&m)
	attacker := &m.units[2]
	target := &m.units[m.friendly_count]
	target.position = m.terrain[0].center
	masked := combat_damage_multiplier(&m, attacker, target)
	target.position = {500, 500, 0}
	open := combat_damage_multiplier(&m, attacker, target)
	testing.expect(t, masked < open)}

@(test)
combat_request_defaults_follow_doctrine :: proc(t: ^testing.T) {m := combat_new_mission(4)
	defer combat_mission_destroy(&m)
	m.units[0].doctrine = .Hunter_Killer
	combat_surface_request(&m, .Commit_Screen, 0, "test", "test")
	m.request_timer = .05
	combat_tick_fixed(&m, .05)
	testing.expect(t, !m.request_pending)
	testing.expect(t, m.groups[0].objective != .Guard)
	n := combat_new_mission(4)
	defer combat_mission_destroy(&n)
	n.units[0].doctrine = .Balanced
	combat_surface_request(&n, .Commit_Screen, 0, "test", "test")
	n.request_timer = .05
	combat_tick_fixed(&n, .05)
	testing.expect(t, n.groups[0].objective == .Guard)}

@(test)
combat_stance_changes_do_not_cancel_actions :: proc(t: ^testing.T) {
	m := combat_new_mission(17)
	defer combat_mission_destroy(&m)
	index := 0
	destination := Combat_Vec3{317, -82, 41}
	combat_issue_order(&m, index, .Move, destination)
	order := m.units[index].order
	target := m.units[index].target
	combat_set_stance(&m, index, .Evade)
	testing.expect_value(t, m.units[index].stance, Combat_Stance.Evade)
	testing.expect_value(t, m.units[index].order, order)
	testing.expect_value(t, m.units[index].destination, destination)
	testing.expect_value(t, m.units[index].target, target)
}

@(test)
combat_contextual_interactions_map_to_existing_deterministic_actions :: proc(t: ^testing.T) {
	m := combat_new_mission(19)
	defer combat_mission_destroy(&m)
	combat_issue_interaction(&m, 0, .Capture, m.relays[0])
	testing.expect_value(t, m.units[0].order, Combat_Order.Control)
	testing.expect_value(t, m.units[0].destination, m.relays[0])
	combat_issue_interaction(&m, 4, .Recover, m.seedship)
	testing.expect_value(t, m.units[4].order, Combat_Order.Recover)
	testing.expect_value(t, m.units[4].destination, m.seedship)
}

@(test)
combat_missions_publish_data_driven_interactions :: proc(t: ^testing.T) {
	m := combat_new_mission(23)
	defer combat_mission_destroy(&m)
	testing.expect_value(t, m.interaction_count, 3)
	testing.expect(t, combat_interaction_available(&m, 0))
	testing.expect(t, combat_interaction_available(&m, 1))
	testing.expect(t, !combat_interaction_available(&m, 2))
	m.seedship_found = true
	testing.expect(t, combat_interaction_available(&m, 2))
	m.fabrication_recovered = true
	testing.expect(t, !combat_interaction_available(&m, 2))
}

@(test)
combat_new_interaction_kinds_use_the_general_act_path :: proc(t: ^testing.T) {
	m := combat_new_mission(29)
	defer combat_mission_destroy(&m)
	index := combat_add_interaction(
		&m,
		{
			kind = .Scan,
			position = {220, -40, 18},
			target = -1,
			verb = "SCAN",
			title = "SCAN ANOMALY",
			consequence = "Hold the survey volume.",
		},
	)
	testing.expect(t, index >= 0 && combat_interaction_available(&m, index))
	combat_issue_interaction(&m, 0, .Scan, m.interactions[index].position)
	testing.expect_value(t, combat_command_action(m.units[0].order), Combat_Command_Action.Act)
	testing.expect_value(t, m.units[0].destination, m.interactions[index].position)
}
