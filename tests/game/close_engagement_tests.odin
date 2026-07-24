package game_tests

import "core:testing"

combat_test_distinct_archetypes :: proc(
	m: ^Combat_Mission,
) -> int {seen: [SHIP_HULL_ARCHETYPE_COUNT]bool; for u in m.units[:m.unit_count] {if u.hull_archetype != .Unspecified do seen[int(u.hull_archetype) - 1] = true}
	count := 0
	for value in seen do if value do count += 1
	return count}

@(test)
ordinary_combat_exposes_8_to_12_types_without_scenario_defining_hulls :: proc(t: ^testing.T) {
	for seed in 1 ..= 32 {m := combat_new_mission(u64(seed)); count := combat_test_distinct_archetypes(&m); testing.expect(t, count >= 8 && count <= 12); for u in m.units[:m.unit_count] {testing.expect(t, u.hull_archetype != .Dreadnought); testing.expect(t, u.operational_role != .Generation_Ship && u.operational_role != .Arkship)}; combat_mission_destroy(&m)}
}

@(test)
counter_relationships_are_responses_not_deterministic_outcomes :: proc(t: ^testing.T) {
	interceptor := combat_unit(
		"",
		"",
		"",
		"",
		.Friendly,
		.Fighter,
		{},
	); combat_configure_archetype(&interceptor, .Interceptor, .Interceptor)
	bomber := combat_unit(
		"",
		"",
		"",
		"",
		.Raider,
		.Bomber,
		{},
	); combat_configure_archetype(&bomber, .Bomber, .Bomber)
	bonus := combat_response_multiplier(
		interceptor,
		bomber,
	); testing.expect(t, bonus > 1); testing.expect(t, bonus < 1.5)
	flak := combat_unit(
		"",
		"",
		"",
		"",
		.Friendly,
		.Corvette,
		{},
	); combat_configure_archetype(&flak, .Combat_Frigate, .Flak_Frigate)
	testing.expect(t, combat_response_multiplier(flak, bomber) > bonus)
	gunship := combat_unit(
		"",
		"",
		"",
		"",
		.Friendly,
		.Corvette,
		{},
	); combat_configure_archetype(&gunship, .Gunship, .Gunship)
	torpedo := combat_unit(
		"",
		"",
		"",
		"",
		.Raider,
		.Corvette,
		{},
	); combat_configure_archetype(&torpedo, .Torpedo_Boat, .Torpedo_Boat)
	testing.expect(t, combat_response_multiplier(gunship, torpedo) > 1)
}

@(test)
losing_command_ship_degrades_information_synchronization_and_autonomy :: proc(t: ^testing.T) {
	m := combat_new_mission(
		18,
	); defer combat_mission_destroy(&m); connected := combat_command_state(&m, .Friendly); testing.expect(t, connected.command_ship_active); testing.expect_value(t, connected.report_delay, f32(0)); m.units[5].disabled = true; degraded := combat_command_state(&m, .Friendly); testing.expect(t, !degraded.command_ship_active); testing.expect(t, degraded.report_delay > connected.report_delay); testing.expect(t, degraded.sensor_sharing < connected.sensor_sharing); testing.expect(t, degraded.synchronized_precision < connected.synchronized_precision); testing.expect(t, degraded.captain_autonomy > connected.captain_autonomy)
}
import "core:math"

@(test)
combat_generation_is_deterministic :: proc(t: ^testing.T) {a := combat_new_mission(77)
	defer combat_mission_destroy(&a)
	b := combat_new_mission(77)
	defer combat_mission_destroy(&b)
	testing.expect(t, a.relays == b.relays)
	testing.expect(t, a.seedship == b.seedship)
	testing.expect(t, a.unit_count == b.unit_count)}

@(test)
combat_heroism_scale_adds_ships_without_adding_autonomous_elements :: proc(t: ^testing.T) {
	m := combat_new_mission(77, 8); defer combat_mission_destroy(&m)
	raider_ships := 0
	for u in m.units[m.friendly_count:m.unit_count] do raider_ships += u.formation_ships
	testing.expect_value(t, raider_ships, m.friendly_count * 8)
	testing.expect(t, m.unit_count - m.friendly_count >= 4 && m.unit_count - m.friendly_count <= 5)
}

@(test)
combat_heroism_conserves_enemy_power_across_armada_sizes :: proc(t: ^testing.T) {
	parity := combat_new_mission(77, 1); armada := combat_new_mission(77, 1000)
	defer combat_mission_destroy(&parity); defer combat_mission_destroy(&armada)
	parity_hull, armada_hull, armada_ships: f32
	for u in parity.units[parity.friendly_count:parity.unit_count] do parity_hull += u.max_hull
	for u in armada.units[armada.friendly_count:armada.unit_count] {armada_hull += u.max_hull; armada_ships += f32(u.formation_ships)}
	testing.expect_value(t, int(armada_ships), armada.friendly_count * 1000)
	testing.expect(t, math.abs(parity_hull - armada_hull) < .01)
}

@(test)
combat_stress_generation_is_large_and_deterministic :: proc(t: ^testing.T) {a :=
		combat_new_stress_mission(77)
	defer combat_mission_destroy(&a)
	b := combat_new_stress_mission(77)
	defer combat_mission_destroy(&b)
	testing.expect_value(t, a.unit_count, 56)
	testing.expect_value(t, a.friendly_count, 18)
	testing.expect(t, a.units[17].position == b.units[17].position)
	testing.expect(t, a.units[55].position == b.units[55].position)
	ship_total := 0
	for u in a.units[:a.unit_count] do ship_total += u.formation_ships
	testing.expect_value(t, ship_total, 1000)
	for _ in 0 ..< 20 do combat_tick_fixed(&a, .05)
	testing.expect(t, a.time >= .99)
	testing.expect_value(t, a.unit_count, 56)}

@(test)
combat_separation_spreads_coincident_elements_deterministically :: proc(t: ^testing.T) {
	a := combat_new_mission(91); defer combat_mission_destroy(&a)
	b := combat_new_mission(91); defer combat_mission_destroy(&b)
	missions := [2]^Combat_Mission{&a, &b}
	for mission in missions {
		mission.units[0].position = {}
		mission.units[1].position = {}
		for i in 2 ..< mission.unit_count do mission.units[i].extracted = true
		combat_separate_units(mission, .05)
	}
	testing.expect(t, combat_distance(a.units[0].position, a.units[1].position) > 0)
	testing.expect(t, a.units[0].position == b.units[0].position)
	testing.expect(t, a.units[1].position == b.units[1].position)
	midpoint := Combat_Vec3 {
		(a.units[0].position.x + a.units[1].position.x) * .5,
		(a.units[0].position.y + a.units[1].position.y) * .5,
		(a.units[0].position.z + a.units[1].position.z) * .5,
	}
	testing.expect(t, combat_distance(midpoint, {}) < .0001)
}

@(test)
combat_command_elements_grow_beyond_the_old_fixed_limit :: proc(t: ^testing.T) {
	m := combat_new_finale_mission(77); defer combat_mission_destroy(&m)
	for i in 0 ..< 80 do combat_finale_add_element(&m, .Raider, .Fighter, 1, 0, {f32(i), 0, 0})
	testing.expect(t, m.unit_count > 64)
	testing.expect_value(t, len(m.units), m.unit_count)
	testing.expect_value(t, len(m.withdraw_request_made), m.unit_count)
}

@(test)
combat_finale_composition_is_exact_and_deterministic :: proc(t: ^testing.T) {
	m := combat_new_finale_mission(81); defer combat_mission_destroy(&m)
	testing.expect_value(
		t,
		m.unit_count,
		44,
	); testing.expect_value(t, m.friendly_count, 26); testing.expect_value(t, m.ship_count, 2200)
	friendly_capitals, friendly_strike, enemy_capitals, enemy_strike := 0, 0, 0, 0
	for u, i in m.units[:m.unit_count] {capital := u.role == .Capital || u.role == .Carrier; if i < m.friendly_count {if capital {friendly_capitals += u.formation_ships} else {friendly_strike += u.formation_ships}} else {if capital {enemy_capitals += u.formation_ships} else {enemy_strike += u.formation_ships}}}
	testing.expect_value(
		t,
		friendly_capitals,
		60,
	); testing.expect_value(t, friendly_strike, 1500); testing.expect_value(t, enemy_capitals, 40); testing.expect_value(t, enemy_strike, 600)
	for element in 0 ..< m.unit_count {for member in 0 ..< m.units[element].formation_ships {id := combat_ship_id(m.seed, element, member); for prior_element in 0 ..= element {limit := prior_element == element ? member : m.units[prior_element].formation_ships; for prior in 0 ..< limit do testing.expect(t, id != combat_ship_id(m.seed, prior_element, prior))}}}
}

@(test)
combat_finale_beam_hits_every_intersecting_side_and_role :: proc(t: ^testing.T) {m :=
		combat_new_finale_mission(82)
	defer combat_mission_destroy(&m)
	friendly_fighter := 15
	friendly_capital := 0
	enemy_fighter := 36
	indices := [3]int{friendly_fighter, friendly_capital, enemy_fighter}
	for index in indices do m.units[index].position = {0, 0, 0}
	m.strategic_asset.position = {500, 0, 0}
	m.strategic_asset.beam_aim = {0, 0, 0}
	combat_finale_fire_beam(&m)
	testing.expect_value(t, m.units[friendly_fighter].formation_active, 0)
	testing.expect_value(t, m.units[enemy_fighter].formation_active, 0)
	testing.expect(
		t,
		m.units[friendly_capital].hull > 0 &&
		m.units[friendly_capital].hull < m.units[friendly_capital].max_hull,
	)
	testing.expect(t, m.strategic_asset.ships_hit > 0)}

@(test)
combat_finale_lock_is_deterministic_and_can_be_evaded :: proc(t: ^testing.T) {m :=
		combat_new_finale_mission(83)
	defer combat_mission_destroy(&m)
	target := combat_finale_select_lock(&m)
	testing.expect_value(t, target, combat_finale_select_lock(&m))
	m.strategic_asset.locked = true
	m.strategic_asset.lock_target = target
	m.strategic_asset.beam_aim = m.units[target].position
	before := m.units[target].hull
	m.units[target].position.y += 300
	combat_finale_fire_beam(&m)
	testing.expect_value(t, m.units[target].hull, before)}

@(test)
combat_finale_relays_pause_charge_and_bombers_disable_weapon :: proc(t: ^testing.T) {m :=
		combat_new_finale_mission(84)
	defer combat_mission_destroy(&m)
	m.strategic_asset.charge = 90
	m.relay_progress = {100, 100}
	combat_finale_update(&m, .05)
	testing.expect(t, m.strategic_asset.exposure_remaining > 59)
	testing.expect_value(t, m.strategic_asset.charge, f32(90))
	for i in 23 ..= 25 do m.units[i].position = m.strategic_asset.position
	for _ in 0 ..< 600 do combat_finale_update(&m, .05)
	testing.expect(t, m.strategic_asset.disabled)
	shots := m.strategic_asset.shots_fired
	for _ in 0 ..< 4000 do combat_finale_update(&m, .05)
	testing.expect_value(t, m.strategic_asset.shots_fired, shots)}

@(test)
combat_mission_destroy_is_idempotent :: proc(t: ^testing.T) {m := combat_new_finale_mission(85)
	testing.expect_value(t, len(m.ships), 2200)
	combat_mission_destroy(&m)
	combat_mission_destroy(&m)
	testing.expect(t, m.ships == nil)
	testing.expect_value(t, m.ship_count, 0)}

@(test)
combat_ten_thousand_ships_keep_bounded_tactical_entities :: proc(t: ^testing.T) {
	m := combat_new_scaled_stress_mission(78, 10000)
	defer combat_mission_destroy(&m)
	testing.expect_value(t, m.ship_count, 10000)
	testing.expect_value(t, m.unit_count, 56)
	for _ in 0 ..< 20 do combat_tick_fixed(&m, .05)
	testing.expect_value(t, m.unit_count, 56)
	testing.expect(t, m.groups[0].plan_revision > 0)
}

@(test)
combat_damage_is_attributed_to_exact_ship_records :: proc(t: ^testing.T) {
	m := combat_new_scaled_stress_mission(79, 1000); target := m.friendly_count
	defer combat_mission_destroy(&m)
	before := m.units[target].formation_active
	individual := m.units[target].max_hull / f32(m.units[target].formation_ships)
	combat_apply_damage(&m, target, individual * 1.5)
	disabled := 0
	u := m.units[target]
	for ship in m.ships[u.roster_start:u.roster_start + u.formation_ships] do if ship.hull <= 0 do disabled += 1
	testing.expect_value(t, disabled, 1)
	testing.expect_value(t, m.units[target].formation_active, before - 1)
}

@(test)
combat_large_losses_create_deterministic_wreckage_fields :: proc(t: ^testing.T) {
	a := combat_new_scaled_stress_mission(
		86,
		1000,
	); b := combat_new_scaled_stress_mission(86, 1000)
	defer combat_mission_destroy(&a); defer combat_mission_destroy(&b)
	target :=
		a.friendly_count; individual := a.units[target].max_hull / f32(a.units[target].formation_ships)
	combat_apply_damage(
		&a,
		target,
		individual * 9,
	); combat_apply_damage(&b, target, individual * 9)
	testing.expect_value(
		t,
		a.wreckage_field_count,
		1,
	); testing.expect_value(t, b.wreckage_field_count, 1)
	testing.expect(
		t,
		a.wreckage_fields[0] == b.wreckage_fields[0],
	); testing.expect_value(t, a.wreckage_fields[0].raider_ships, 9)
}

@(test)
combat_small_losses_do_not_create_wreckage_fields :: proc(t: ^testing.T) {
	m := combat_new_scaled_stress_mission(87, 1000); defer combat_mission_destroy(&m)
	target :=
		m.friendly_count; individual := m.units[target].max_hull / f32(m.units[target].formation_ships)
	combat_apply_damage(&m, target, individual * 3)
	testing.expect_value(t, m.wreckage_field_count, 0)
}

@(test)
combat_wreckage_fields_mask_missile_damage :: proc(t: ^testing.T) {
	m := combat_new_scaled_stress_mission(88, 1000); defer combat_mission_destroy(&m)
	target_index := m.friendly_count; target := &m.units[target_index]; attacker := &m.units[2]
	individual :=
		target.max_hull /
		f32(target.formation_ships); combat_apply_damage(&m, target_index, individual * 8)
	target.position =
		m.wreckage_fields[0].center; masked := combat_damage_multiplier(&m, attacker, target)
	target.position = {1000, 1000, 1000}; open := combat_damage_multiplier(&m, attacker, target)
	testing.expect(t, masked < open)
}

@(test)
combat_wreckage_field_radius_is_linear_in_wreck_tonnage :: proc(t: ^testing.T) {
	fighter := Combat_Wreckage_Field{}; carrier := Combat_Wreckage_Field{}
	combat_add_wreckage_to_field(&fighter, .Friendly, 8, 8 * combat_role_tonnage(.Fighter), {})
	combat_add_wreckage_to_field(&carrier, .Friendly, 8, 8 * combat_role_tonnage(.Carrier), {})
	testing.expect_value(t, fighter.radius, combat_wreckage_radius(fighter.tonnage))
	testing.expect_value(
		t,
		carrier.radius / fighter.radius,
		combat_role_tonnage(.Carrier) / combat_role_tonnage(.Fighter),
	)
}

@(test)
combat_result_preserves_exact_ship_totals :: proc(t: ^testing.T) {
	m := combat_new_scaled_stress_mission(80, 1000)
	defer combat_mission_destroy(&m)
	for &u in m.units[:m.friendly_count] do u.extracted = true
	combat_finish(&m)
	testing.expect_value(t, m.result.ships_total, 320)
	testing.expect_value(t, m.result.ships_preserved, 320)
	testing.expect_value(t, m.result.ships_disabled, 0)
}

@(test)
combat_doctrine_changes_withdrawal :: proc(t: ^testing.T) {m := combat_new_mission(2)
	defer combat_mission_destroy(&m)
	m.units[0].hull = 25
	combat_set_doctrine(&m, 0, .Cautious_Screen)
	combat_tick_fixed(&m, .05)
	testing.expect(t, m.units[0].withdrawing)
	n := combat_new_mission(2)
	defer combat_mission_destroy(&n)
	n.units[0].hull = 25
	combat_set_doctrine(&n, 0, .Last_Stand)
	combat_tick_fixed(&n, .05)
	testing.expect(t, !n.units[0].withdrawing)}

@(test)
combat_withdrawing_unit_completes_extraction :: proc(t: ^testing.T) {
	m := combat_new_mission(2); defer combat_mission_destroy(&m)
	u := &m.units[0]; u.position = m.extraction; u.order = .Withdraw; u.withdrawing = true
	combat_tick_fixed(&m, .05)
	testing.expect(t, u.extracted)
}

@(test)
combat_concentrated_fire_pins_and_withdrawal_breaks_pressure :: proc(t: ^testing.T) {
	m := combat_new_mission(2); defer combat_mission_destroy(&m); target := m.friendly_count
	for _ in 0 ..< 10 do combat_apply_weapon_pressure(&m, 0, target)
	testing.expect(
		t,
		m.units[target].pressure >= 65,
	); testing.expect(t, combat_pressure_fire_multiplier(m.units[target]) < 1); testing.expect(t, combat_pressure_mobility_multiplier(m.units[target]) < 1)
	m.units[target].order = .Withdraw; before := m.units[target].pressure; combat_tick_fixed(&m, .05)
	testing.expect(
		t,
		m.units[target].pressure < before,
	); testing.expect(t, combat_pressure_mobility_multiplier(m.units[target]) > 1)
}
