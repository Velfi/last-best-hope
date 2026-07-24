package game_tests

import "core:math"
import "core:testing"

@(test)
combat_local_tracks_require_an_actual_network_transmission_to_relay :: proc(t: ^testing.T) {
	m := combat_new_mission(8810); defer combat_mission_destroy(&m)
	target := m.friendly_count
	for &u, index in m.units[:m.unit_count] {
		if u.side == .Friendly && index != 0 && index != 1 do u.extracted = true
	}
	m.units[0].group = 0; m.units[0].position = {0, 0, 0}; m.units[0].communication = .Local; m.units[0].network_burst_timer = 0
	m.units[1].group = 1; m.units[1].position = {-4000, 0, 0}; m.units[1].communication = .Local
	m.units[target].position = {100, 0, 0}
	combat_update_contacts(&m, .05)
	testing.expect(t, combat_group_contact_targetable(&m, .Friendly, 0, target))
	testing.expect(t, !combat_group_contact_targetable(&m, .Friendly, 1, target))
	m.units[0].network_burst_timer = 1
	combat_update_contacts(&m, .05)
	relayed := combat_group_contact_trace(&m, .Friendly, 1, target)
	testing.expect(t, combat_group_contact_targetable(&m, .Friendly, 1, target))
	testing.expect(t, relayed.relayed)
}

@(test)
combat_burst_policy_is_quiet_between_transmission_windows :: proc(t: ^testing.T) {
	m := combat_new_mission(8811); defer combat_mission_destroy(&m); u := &m.units[0]
	u.position = {
		900,
		900,
		0,
	}; u.communication = .Burst; u.network_burst_timer = 0; u.active_sensors = false; u.exposure = 0
	combat_update_signature(&m, u, .05); between := u.signature
	u.network_burst_timer = 1
	combat_update_signature(&m, u, .05); transmitting := u.signature
	testing.expect(t, transmitting > between)
}

@(test)
combat_planner_ignores_authoritative_state_hidden_behind_the_same_trace :: proc(t: ^testing.T) {
	a := combat_new_mission(
		8812,
	); b := combat_new_mission(8812); defer combat_mission_destroy(&a); defer combat_mission_destroy(&b)
	target := a.friendly_count
	trace := Combat_Contact_Trace {
		position         = {220, 30, 0},
		velocity         = {-10, 0, 0},
		confidence       = .7,
		error_radius     = 35,
		solution_quality = .52,
		liveness         = .Fresh,
		identity         = .Classification,
	}
	a.group_contacts[0][0][target] = trace; b.group_contacts[0][0][target] = trace
	a.units[target].position = {220, 30, 0}; b.units[target].position = {900, -700, 300}
	a.units[target].range = 40; b.units[target].range = 900
	combat_plan_group(&a, .Friendly, 0); combat_plan_group(&b, .Friendly, 0)
	testing.expect_value(t, a.groups[0].maneuver, b.groups[0].maneuver)
	testing.expect_value(t, a.groups[0].maneuver_reason, b.groups[0].maneuver_reason)
	testing.expect_value(t, a.groups[0].planned_displacement, b.groups[0].planned_displacement)
}

@(test)
combat_after_firing_displacement_uses_a_fire_event_not_signature :: proc(t: ^testing.T) {
	m := combat_new_mission(8813); defer combat_mission_destroy(&m); target := m.friendly_count
	combat_apply_group_doctrine(&m.groups[0], .Hunter_Killer)
	m.groups[0].plan_revision = 1; m.groups[0].maneuver = .Skirmish_Pass; m.groups[0].maneuver_timer = 0
	m.time = 20
	m.group_contacts[0][0][target] = Combat_Contact_Trace {
		position         = {160, 0, 0},
		confidence       = .9,
		error_radius     = 15,
		solution_quality = .8,
		liveness         = .Fresh,
		identity         = .Classification,
	}
	for &u in m.units[:m.friendly_count] do if u.group == 0 {u.signature = u.base_signature * 2; u.pressure = 0}
	combat_plan_group(&m, .Friendly, 0)
	testing.expect(t, m.groups[0].maneuver != .Fire_And_Displace)
	m.groups[0].maneuver_timer = 0; m.groups[0].last_fired_time = 19
	combat_plan_group(&m, .Friendly, 0)
	testing.expect_value(t, m.groups[0].maneuver, Combat_Maneuver.Fire_And_Displace)
}

@(test)
combat_threat_envelope_accounts_for_observed_closing_motion :: proc(t: ^testing.T) {
	inbound := combat_new_mission(
		8814,
	); outbound := combat_new_mission(8814); defer combat_mission_destroy(&inbound); defer combat_mission_destroy(&outbound)
	target := inbound.friendly_count
	base := Combat_Contact_Trace {
		position         = {240, 0, 0},
		confidence       = .8,
		error_radius     = 20,
		solution_quality = .55,
		liveness         = .Fresh,
		identity         = .Classification,
	}
	approaching :=
		base; approaching.velocity = {-40, 0, 0}; departing := base; departing.velocity = {40, 0, 0}
	inbound.group_contacts[0][0][target] =
		approaching; outbound.group_contacts[0][0][target] = departing
	inbound.groups[0].destination = {0, 0, 0}; outbound.groups[0].destination = {0, 0, 0}
	combat_plan_group(&inbound, .Friendly, 0); combat_plan_group(&outbound, .Friendly, 0)
	testing.expect(t, inbound.groups[0].escape_margin < outbound.groups[0].escape_margin)
}

@(test)
combat_doctrine_maps_to_distinct_survival_and_maneuver_policies :: proc(t: ^testing.T) {
	concealment, passive, ambush, tracked := combat_doctrine_policies(.Cautious_Screen)
	testing.expect_value(
		t,
		concealment,
		Combat_Survival_Method.Concealment,
	); testing.expect_value(t, passive, Combat_Emission_Policy.Passive_First); testing.expect_value(t, ambush, Combat_Attack_Rhythm.Ambush); testing.expect_value(t, tracked, Combat_Displacement_Trigger.When_Tracked)
	mobility, continuous, passes, after := combat_doctrine_policies(.Hunter_Killer)
	testing.expect_value(
		t,
		mobility,
		Combat_Survival_Method.Mobility,
	); testing.expect_value(t, continuous, Combat_Emission_Policy.Continuous); testing.expect_value(t, passes, Combat_Attack_Rhythm.Repeated_Passes); testing.expect_value(t, after, Combat_Displacement_Trigger.After_Firing)
}

@(test)
combat_signature_accounts_for_silence_sensors_burn_and_masking :: proc(t: ^testing.T) {
	m := combat_new_mission(8801); defer combat_mission_destroy(&m); u := &m.units[0]
	u.position = {
		900,
		900,
		0,
	}; u.silent_running = true; u.combat_burn = false; u.communication = .Local; u.exposure = 0; combat_update_signature(&m, u, .05); quiet := u.signature
	u.silent_running =
		false; u.combat_burn = true; u.communication = .Continuous; u.active_sensors = true; combat_update_signature(&m, u, .05); loud := u.signature
	testing.expect(t, loud > quiet * 2)
	u.position =
		m.terrain[0].center; u.combat_burn = false; u.communication = .Local; u.active_sensors = false; combat_update_signature(&m, u, .05); testing.expect(t, u.signature < loud)
}

@(test)
combat_burn_trades_readiness_and_heat_for_acceleration :: proc(t: ^testing.T) {
	u := combat_unit("Test", "Test", "", "", .Friendly, .Fighter, {})
	quiet := u; quiet.combat_burn = false; combat_move_toward(&quiet, {500, 0, 0}, 1)
	burning := u; burning.combat_burn = true; combat_move_toward(&burning, {500, 0, 0}, 1)
	testing.expect(
		t,
		burning.velocity.x > quiet.velocity.x,
	); testing.expect(t, burning.burn_heat > 0); testing.expect(t, burning.readiness < quiet.readiness)
}

@(test)
combat_acceleration_follows_physical_role_thrust :: proc(t: ^testing.T) {
	fighter := combat_unit("Fighter", "Test", "", "", .Friendly, .Fighter, {})
	capital := combat_unit("Capital", "Test", "", "", .Friendly, .Capital, {})
	testing.expect(t, fighter.engine_power < capital.engine_power)
	testing.expect(t, fighter.max_acceleration > capital.max_acceleration)
	testing.expect(t, math.abs(fighter.drive_acceleration_g - .2) < .001)
	testing.expect(t, math.abs(capital.drive_acceleration_g - .04) < .001)
	testing.expect(t, math.abs(fighter.max_acceleration - combat_acceleration_units_per_minute2(.2)) < .000001)
	testing.expect(t, math.abs(capital.max_acceleration - combat_acceleration_units_per_minute2(.04)) < .000001)
}

@(test)
combat_arrival_requires_braking_instead_of_an_instant_stop :: proc(t: ^testing.T) {
	u := combat_unit("Fighter", "Test", "", "", .Friendly, .Fighter, {})
	u.position = {9.9, 0, 0}; u.velocity = {40, 0, 0}
	combat_move_toward(&u, {10, 0, 0}, .05)
	testing.expect(t, u.velocity.x > 0)
	testing.expect(t, u.position.x > 10)
}

@(test)
combat_silent_running_degrades_the_opposing_track :: proc(t: ^testing.T) {
	m := combat_new_mission(
		8802,
	); defer combat_mission_destroy(&m); index := 0; enemy_view := combat_contact_trace(&m, .Raider, index); enemy_view.solution_quality = .9; enemy_view.error_radius = 12; enemy_view.confidence = .9
	m.units[index].hull_archetype = .Scout; m.units[index].ability_charges = 1
	testing.expect(
		t,
		combat_activate_ship_ability(&m, index),
	); testing.expect(t, m.units[index].silent_running); testing.expect(t, !m.units[index].active_sensors); testing.expect(t, enemy_view.solution_quality < .9); testing.expect(t, enemy_view.error_radius > 12)
}

@(test)
combat_maneuver_planner_is_deterministic_and_side_visible :: proc(t: ^testing.T) {
	a := combat_new_mission(
		8803,
	); b := combat_new_mission(8803); defer combat_mission_destroy(&a); defer combat_mission_destroy(&b)
	for _ in 0 ..< 80 {combat_tick(&a, .05); combat_tick(&b, .05)}
	for group in 0 ..< COMBAT_GROUP_COUNT {testing.expect_value(t, a.groups[group].maneuver, b.groups[group].maneuver); testing.expect_value(t, a.groups[group].maneuver_reason, b.groups[group].maneuver_reason); testing.expect_value(t, a.raider_groups[group].maneuver, b.raider_groups[group].maneuver)}
}

@(test)
combat_weapon_and_defense_packages_are_persistent_and_role_bounded :: proc(t: ^testing.T) {
	for id in Ship_ID(1) ..= Ship_ID(32) {a := ship_weapon_package_for(id, .Combat_Frigate, .Missile_Frigate); b := ship_weapon_package_for(id, .Combat_Frigate, .Missile_Frigate); testing.expect_value(t, a, Ship_Weapon_Package.Guided_Missiles); testing.expect_value(t, a, b); testing.expect(t, ship_defense_packages_for(id, .Combat_Frigate, .Shield_Frigate) != {})}
}

@(test)
combat_emergency_defense_spends_stores_and_disrupts_inbound_salvo :: proc(t: ^testing.T) {
	m := combat_new_mission(
		600,
	); defer combat_mission_destroy(&m); target := 0; source := m.friendly_count
	m.units[target].chaff = 2; m.units[target].flares = 2; m.units[target].decoys = 2; m.units[target].defense_cooldown = 0
	combat_update_contacts(
		&m,
		.05,
	); combat_launch_salvo(&m, source, target, .Guided_Missile, 12); m.salvos[0].guidance = 1; before := m.salvos[0].guidance; stores := m.units[target].chaff + m.units[target].flares + m.units[target].decoys
	testing.expect(
		t,
		combat_emergency_defense(&m, target),
	); testing.expect(t, m.salvos[0].guidance < before); testing.expect_value(t, m.units[target].chaff + m.units[target].flares + m.units[target].decoys, stores - 1); testing.expect(t, m.units[target].readiness < 100); testing.expect(t, m.units[target].exposure > 0); testing.expect(t, m.units[target].defense_cooldown > 0)
}

@(test)
combat_active_defense_role_provides_real_defensive_layers :: proc(t: ^testing.T) {
	modules := ship_operational_role_modules(
		.Shield_Frigate,
	); testing.expect(t, .Active_Defense in modules); testing.expect(t, .Electronic_Warfare in modules); testing.expect(t, .Flak in modules)
}


@(test)
combat_torpedo_request_controls_reserve :: proc(t: ^testing.T) {m := combat_new_mission(6)
	defer combat_mission_destroy(&m)
	combat_surface_request(&m, .Release_Torpedoes, 2, "test", "test")
	combat_resolve_request(&m, true)
	testing.expect(t, m.units[2].costly_shot_authorized)
	n := combat_new_mission(6)
	defer combat_mission_destroy(&n)
	combat_surface_request(&n, .Release_Torpedoes, 2, "test", "test")
	combat_resolve_request(&n, false)
	testing.expect(t, !n.units[2].costly_shot_authorized)}

@(test)
combat_fire_control_modes_pause_only_when_required :: proc(t: ^testing.T) {
	m := combat_new_mission(601); defer combat_mission_destroy(&m); target := m.friendly_count
	m.units[0].position = {
		0,
		0,
		0,
	}; m.units[target].position = {40, 0, 0}; combat_update_contacts(&m, .05)
	m.fire_control = .Automatic; testing.expect(t, !combat_fire_request_needed(&m, 0, target, false)); testing.expect(t, !combat_fire_request_needed(&m, 0, target, true))
	m.fire_control = .Confirm_Costly; testing.expect(t, !combat_fire_request_needed(&m, 0, target, false)); testing.expect(t, combat_fire_request_needed(&m, 0, target, true))
	m.fire_control = .Confirm_Engagements; testing.expect(t, combat_fire_request_needed(&m, 0, target, false)); combat_request_fire(&m, 0, target, true); before := m.time; combat_tick_fixed(&m, .05); testing.expect_value(t, m.time, before); combat_resolve_request(&m, true); testing.expect_value(t, m.units[0].engagement_target, target); testing.expect(t, m.units[0].costly_shot_authorized)
}

@(test)
combat_exposure_and_salvos_are_deterministic :: proc(t: ^testing.T) {
	a := combat_new_mission(
		602,
	); defer combat_mission_destroy(&a); b := combat_new_mission(602); defer combat_mission_destroy(&b); target := a.friendly_count
	a.units[0].position = {
		0,
		0,
		0,
	}; a.units[target].position = {145, 0, 0}; combat_update_contacts(&a, .05); combat_launch_salvo(&a, 0, target, .Guided_Missile, 12); testing.expect(t, a.units[0].exposure > 0); for _ in 0 ..< 40 do combat_update_salvos(&a, .05)
	b.units[0].position = {
		0,
		0,
		0,
	}; b.units[target].position = {145, 0, 0}; combat_update_contacts(&b, .05); combat_launch_salvo(&b, 0, target, .Guided_Missile, 12); for _ in 0 ..< 40 do combat_update_salvos(&b, .05)
	testing.expect_value(
		t,
		a.units[target].hull,
		b.units[target].hull,
	); testing.expect(t, len(a.salvos) > 0); testing.expect_value(t, len(a.salvos), len(b.salvos)); for salvo, i in a.salvos do testing.expect_value(t, salvo, b.salvos[i])
}

@(test)
combat_salvos_can_strike_friendly_formations_in_their_flight_path :: proc(t: ^testing.T) {
	m := combat_new_mission(93); defer combat_mission_destroy(&m)
	target := m.friendly_count
	for &unit, index in m.units[:m.unit_count] do unit.extracted = index != 0 && index != 1 && index != target
	m.units[0].position = {0, 0, 0}
	m.units[1].position = {60, 0, 0}
	m.units[target].position = {145, 0, 0}
	combat_update_contacts(&m, .05)
	friendly_hull := m.units[1].hull
	target_hull := m.units[target].hull
	combat_launch_salvo(&m, 0, target, .Guided_Missile, 12)
	for _ in 0 ..< 700 do combat_update_salvos(&m, .05)
	testing.expect(t, m.units[1].hull < friendly_hull)
	testing.expect_value(t, m.units[target].hull, target_hull)
	testing.expect_value(t, len(m.salvos), 0)
}

@(test)
combat_doctrine_controls_friendly_fire_risk_tolerance :: proc(t: ^testing.T) {
	m := combat_new_mission(94); defer combat_mission_destroy(&m)
	target := m.friendly_count
	for &unit, index in m.units[:m.unit_count] do unit.extracted = index != 0 && index != 1 && index != target
	m.units[0].position = {0, 0, 0}
	m.units[1].position = {60, 0, 0}
	m.units[target].position = {145, 0, 0}
	combat_update_contacts(&m, .05)
	combat_contact_trace(&m, .Friendly, target).solution_quality = 1
	risk := combat_friendly_fire_risk(&m, 0, target, .Guided_Missile)
	testing.expect(t, risk > .9)
	combat_set_doctrine(&m, 0, .Cautious_Screen)
	testing.expect(t, !combat_has_firing_solution(&m, 0, target, .Guided_Missile))
	combat_set_doctrine(&m, 0, .Balanced)
	testing.expect(t, !combat_has_firing_solution(&m, 0, target, .Guided_Missile))
	combat_set_doctrine(&m, 0, .Hunter_Killer)
	testing.expect(t, !combat_has_firing_solution(&m, 0, target, .Guided_Missile))
	combat_set_doctrine(&m, 0, .Last_Stand)
	testing.expect(t, combat_has_firing_solution(&m, 0, target, .Guided_Missile))
	m.units[1].position = {60, 80, 0}
	combat_set_doctrine(&m, 0, .Cautious_Screen)
	testing.expect_value(t, combat_friendly_fire_risk(&m, 0, target, .Guided_Missile), f32(0))
	testing.expect(t, combat_has_firing_solution(&m, 0, target, .Guided_Missile))
}

@(test)
combat_captain_personality_modifies_doctrine_friendly_fire_tolerance :: proc(t: ^testing.T) {
	m := combat_new_mission(95); defer combat_mission_destroy(&m)
	target := m.friendly_count
	for &unit, index in m.units[:m.unit_count] do unit.extracted = index != 0 && index != 1 && index != target
	m.units[0].position = {0, 0, 0}
	m.units[1].position = {60, 6, 0}
	m.units[target].position = {145, 0, 0}
	m.units[0].doctrine = .Balanced
	combat_update_contacts(&m, .05)
	combat_contact_trace(&m, .Friendly, target).solution_quality = 1
	risk := combat_friendly_fire_risk(&m, 0, target, .Guided_Missile)
	testing.expect(t, risk > combat_doctrine_friendly_fire_tolerance(.Balanced))
	testing.expect(
		t,
		risk <
		combat_doctrine_friendly_fire_tolerance(.Balanced) +
			combat_captain_recklessness_modifier(.Committed),
	)
	m.units[0].captain_trait = .Protective
	testing.expect(t, !combat_has_firing_solution(&m, 0, target, .Guided_Missile))
	m.units[0].captain_trait = .Committed
	testing.expect(t, combat_has_firing_solution(&m, 0, target, .Guided_Missile))
}

@(test)
combat_confirmed_disabled_contacts_cannot_be_targeted :: proc(t: ^testing.T) {
	m := combat_new_mission(606)
	defer combat_mission_destroy(&m)
	target := m.friendly_count
	m.units[0].position = {0, 0, 0}
	for i in m.friendly_count ..< m.unit_count do m.units[i].position = {1000, 0, 0}
	m.units[target].position = {40, 0, 0}
	combat_update_contacts(&m, .05)
	testing.expect(t, combat_contact_targetable(&m, .Friendly, target))
	trace := combat_contact_trace(&m, .Friendly, target)
	trace.assessment = .Confirmed_Disabled
	testing.expect(t, !combat_contact_targetable(&m, .Friendly, target))
	testing.expect_value(t, combat_best_enemy(&m, 0, 100, .Threats_To_Objective), -1)
}

@(test)
combat_sensor_fusion_improves_solution :: proc(t: ^testing.T) {
	m := combat_new_mission(
		603,
	); defer combat_mission_destroy(&m); target := m.friendly_count; m.units[target].position = {180, 0, 0}; for i in 0 ..< m.friendly_count do m.units[i].position = {-1000, 0, 0}; m.units[0].position = {0, 0, 0}; combat_update_contacts(&m, .05); single := combat_contact_trace(&m, .Friendly, target).solution_quality; m.units[1].position = {80, 0, 0}; combat_update_contacts(&m, .05); testing.expect(t, combat_contact_trace(&m, .Friendly, target).observer_count >= 2); testing.expect(t, combat_contact_trace(&m, .Friendly, target).solution_quality > single)
}

@(test)
combat_every_hull_has_a_distinct_active_ability :: proc(t: ^testing.T) {
	seen: [25]bool
	for value in 1 ..= SHIP_HULL_ARCHETYPE_COUNT {
		u := combat_unit("test", "", "", "", .Friendly, .Fighter, {})
		u.hull_archetype = Ship_Hull_Archetype(value)
		ability := combat_ship_ability(u)
		testing.expect(t, ability != .None)
		testing.expect(t, combat_ship_ability_name(ability) != "NO ABILITY")
		testing.expect(t, !seen[int(ability)])
		seen[int(ability)] = true
	}
}

@(test)
combat_special_abilities_have_an_immediate_effect_at_full_readiness :: proc(t: ^testing.T) {
	m := combat_new_mission(15)
	defer combat_mission_destroy(&m)

	// These elements begin at full readiness and cohesion. Their abilities must
	// still change combat state instead of only spending a charge on capped stats.
	m.units[0].hull_archetype = .Scout
	testing.expect(t, combat_activate_ship_ability(&m, 0))
	testing.expect(t, m.units[0].silent_running)
	testing.expect(t, !m.units[0].active_sensors)

	m.units[2].hull_archetype = .Assault_Shuttle
	bomber_torpedoes := m.units[2].torpedoes
	testing.expect(t, combat_activate_ship_ability(&m, 2))
	testing.expect(t, m.units[2].torpedoes > bomber_torpedoes)

	carrier_decoys := m.units[5].decoys
	testing.expect(t, combat_activate_ship_ability(&m, 5))
	testing.expect(t, m.units[5].decoys > carrier_decoys)

	m.units[6].hull_archetype = .Light_Cruiser
	cruiser_torpedoes := m.units[6].torpedoes
	testing.expect(t, combat_activate_ship_ability(&m, 6))
	testing.expect(t, m.units[6].torpedoes > cruiser_torpedoes)
}

@(test)
combat_capital_stern_is_vulnerable :: proc(t: ^testing.T) {target := combat_unit(
		"target",
		"",
		"",
		"",
		.Raider,
		.Capital,
		{0, 0, 0},
	)
	target.facing = 0
	rear := combat_unit("rear", "", "", "", .Friendly, .Capital, {-100, 0, 0})
	front := rear
	front.position = {100, 0, 0}
	testing.expect(
		t,
		combat_capital_arc_multiplier(rear, target) > combat_capital_arc_multiplier(front, target),
	)}

@(test)
combat_linebreaker_salvo_is_delayed_limited_and_deterministic :: proc(t: ^testing.T) {
	m := combat_new_mission(
		12,
	); capital := &m.units[6]; capital.position = {0, 0, 0}; target := m.friendly_count; m.units[target].position = {250, 0, 0}; m.units[target].speed = 0; start := m.units[target].hull
	defer combat_mission_destroy(&m)
	testing.expect(
		t,
		combat_activate_capital_ability(&m, 6, {250, 0, 0}),
	); testing.expect_value(t, capital.ability_charges, 1); testing.expect_value(t, m.units[target].hull, start)
	for _ in 0 ..< 69 do combat_tick_fixed(&m, .05)
	testing.expect_value(t, m.units[target].hull, start)
	m.ability_timer = .05; combat_tick_fixed(&m, .05); testing.expect(t, m.units[target].hull < start); testing.expect(t, !combat_capital_ability_ready(&m, 6))
}

@(test)
combat_linebreaker_salvo_has_minimum_range_and_friendly_fire :: proc(t: ^testing.T) {
	m := combat_new_mission(
		13,
	); m.units[6].position = {0, 0, 0}; m.units[0].position = {250, 0, 0}; m.units[0].speed = 0; friendly_start := m.units[0].hull
	defer combat_mission_destroy(&m)
	testing.expect(
		t,
		!combat_activate_capital_ability(&m, 6, {49, 0, 0}),
	); testing.expect(t, combat_activate_capital_ability(&m, 6, {250, 0, 0})); m.ability_timer = .05; combat_tick_fixed(&m, .05); testing.expect(t, m.units[0].hull < friendly_start)
}

@(test)
combat_ranged_ability_projects_distance_based_time_to_impact :: proc(t: ^testing.T) {
	m := combat_new_mission(16); defer combat_mission_destroy(&m); m.units[6].position = {0, 0, 0}
	near, near_valid := combat_ship_ability_time_to_impact(&m, 6, {120, 0, 0})
	far, far_valid := combat_ship_ability_time_to_impact(&m, 6, {480, 0, 0})
	_, too_close := combat_ship_ability_time_to_impact(&m, 6, {49, 0, 0})
	testing.expect(
		t,
		near_valid,
	); testing.expect(t, far_valid); testing.expect(t, !too_close); testing.expect(t, far > near)
	testing.expect(t, combat_activate_ship_ability(&m, 6, {480, 0, 0}))
	testing.expect_value(t, m.ability_timer, far)
}

@(test)
combat_generated_objectives_avoid_fatal_terrain :: proc(t: ^testing.T) {for seed in 1 ..= 100 {m :=
			combat_new_mission(u64(seed))
		for relay in m.relays do testing.expect(t, combat_distance(relay, m.terrain[2].center) > m.terrain[2].radius + 20)
		testing.expect(
			t,
			combat_distance(m.seedship, m.terrain[2].center) > m.terrain[2].radius + 20,
		)
		testing.expect(t, combat_distance(m.relays[0], m.relays[1]) > 250)
		combat_mission_destroy(&m)}}

@(test)
combat_battlefield_requires_meaningful_redeployment :: proc(t: ^testing.T) {for seed in 1 ..= 100 {m :=
			combat_new_mission(u64(seed))
		testing.expect(t, combat_distance(m.relays[0], m.relays[1]) > 400)
		testing.expect(t, combat_distance(m.extraction, m.anomaly) > 800)
		combat_mission_destroy(&m)}}

@(test)
combat_opening_is_split_across_both_relay_approaches :: proc(t: ^testing.T) {
	m := combat_new_mission(23); defer combat_mission_destroy(&m)
	testing.expect(
		t,
		m.units[0].destination == m.relays[0],
	); testing.expect(t, m.units[1].destination == m.relays[0])
	testing.expect(
		t,
		m.units[2].destination == m.relays[1],
	); testing.expect(t, m.units[3].destination == m.relays[1])
	testing.expect_value(
		t,
		m.units[5].order,
		Combat_Order.Guard,
	); testing.expect_value(t, m.units[5].guard, 4)
	testing.expect_value(
		t,
		m.units[6].order,
		Combat_Order.Move,
	); testing.expect(t, m.units[6].destination == m.terrain[1].center)
	for enemy, i in m.units[m.friendly_count:m.unit_count] {
		assigned := (i % 2)
		other := 1 - assigned
		testing.expect(
			t,
			combat_distance(enemy.position, m.relays[assigned]) <
			combat_distance(enemy.position, m.relays[other]),
		)
	}
}

@(test)
combat_abandoned_seedship_relay_can_be_jammed_after_capture :: proc(t: ^testing.T) {
	m := combat_new_mission(24); defer combat_mission_destroy(&m)
	for &u in m.units[:m.friendly_count] do u.position = {-10000, 0, 0}
	for &u in m.units[m.friendly_count:m.unit_count] do u.position = {10000, 0, 0}
	m.relay_progress[0] = 100; m.units[m.friendly_count].position = m.relays[0]
	combat_tick_fixed(&m, .05)
	testing.expect(t, m.relay_progress[0] < 100)
}

@(test)
combat_engagement_grid_uses_military_sector_addresses_and_depth_planes :: proc(t: ^testing.T) {
	grid := Combat_Engagement_Grid {
		min_x       = -600,
		max_x       = 600,
		min_y       = -600,
		max_y       = 600,
		low_ceiling = -50,
		high_floor  = 50,
	}
	testing.expect(t, combat_sector_label(grid, {-500, -500, 0}) == "A1")
	testing.expect(t, combat_sector_label(grid, {500, 500, 0}) == "F6")
	testing.expect(t, combat_location_label(grid, {-300, -300, 80}) == "B2 HIGH")
	testing.expect(t, combat_location_label(grid, {0, 0, 0}) == "D4 PLANE")
	testing.expect(t, combat_location_label(grid, {300, 300, -80}) == "E5 LOW")
}

@(test)
combat_spatial_event_records_sector_and_depth_plane :: proc(t: ^testing.T) {
	m := combat_new_mission(14); defer combat_mission_destroy(&m)
	combat_add_event_at(&m, "Contact disabled", {-750, -750, 80})
	testing.expect(t, m.event_text[0] == "Contact disabled in Sector A1 High.")
}

@(test)
combat_guided_missile_hits_report_once_per_burst :: proc(t: ^testing.T) {
	m := combat_new_mission(14); defer combat_mission_destroy(&m)
	initial_events := m.event_count
	salvo := Combat_Salvo {
		source = m.friendly_count,
		target = 0,
		weapon = .Guided_Missile,
	}
	m.time = 10
	combat_report_guided_hit(&m, salvo, "Guided-missile burst hit; damage unassessed", {0, 0, 0})
	m.time = 10.7
	combat_report_guided_hit(&m, salvo, "Guided-missile burst hit; damage unassessed", {0, 0, 0})
	testing.expect_value(t, m.event_count, initial_events + 1)
	m.time = 11.6
	combat_report_guided_hit(&m, salvo, "Guided-missile burst hit; damage unassessed", {0, 0, 0})
	testing.expect_value(t, m.event_count, initial_events + 2)
}

@(test)
combat_salvo_warnings_require_a_command_window :: proc(t: ^testing.T) {
	missile := Combat_Salvo {
		weapon         = .Guided_Missile,
		time_remaining = 2.4,
		active         = true,
	}
	testing.expect(t, !combat_salvo_warning_actionable(missile))
	missile.time_remaining = 2.5
	testing.expect(t, combat_salvo_warning_actionable(missile))
	torpedo := Combat_Salvo {
		weapon         = .Heavy_Torpedo,
		time_remaining = 1,
		active         = true,
	}
	testing.expect(t, combat_salvo_warning_actionable(torpedo))
	torpedo.active = false
	testing.expect(t, !combat_salvo_warning_actionable(torpedo))
}

@(test)
combat_contact_traces_age_extrapolate_and_expire :: proc(t: ^testing.T) {
	m := combat_new_mission(81); defer combat_mission_destroy(&m); enemy := m.friendly_count
	for &u in m.units[:m.friendly_count] do u.position = {-10000, 0, 0}
	m.units[0].position = {
		0,
		0,
		0,
	}; m.units[enemy].position = {80, 0, 0}; m.units[enemy].velocity = {10, 2, 0}
	combat_update_contacts(&m, .05); trace := combat_contact_trace(&m, .Friendly, enemy)
	testing.expect_value(
		t,
		trace.liveness,
		Combat_Contact_Liveness.Fresh,
	); testing.expect(t, trace.detected); testing.expect(t, trace.identity != .Unknown)
	m.units[0].position = {-10000, 0, 0}; combat_update_contacts(&m, 4)
	testing.expect_value(
		t,
		trace.liveness,
		Combat_Contact_Liveness.Aging,
	); predicted, visible := combat_contact_position(&m, .Friendly, enemy); testing.expect(t, visible); testing.expect_value(t, predicted.x, f32(120)); testing.expect_value(t, predicted.y, f32(8))
	combat_update_contacts(
		&m,
		9,
	); testing.expect_value(t, trace.liveness, Combat_Contact_Liveness.Stale); testing.expect(t, !combat_contact_targetable(&m, .Friendly, enemy))
	combat_update_contacts(
		&m,
		18,
	); testing.expect_value(t, trace.liveness, Combat_Contact_Liveness.Lost); _, visible = combat_contact_position(&m, .Friendly, enemy); testing.expect(t, !visible)
}

@(test)
combat_contact_picture_is_deterministic_and_side_specific :: proc(t: ^testing.T) {
	a := combat_new_mission(
		82,
	); defer combat_mission_destroy(&a); b := combat_new_mission(82); defer combat_mission_destroy(&b)
	for _ in 0 ..< 80 {combat_tick_fixed(&a, .05); combat_tick_fixed(&b, .05)}
	for i in 0 ..< a.unit_count {testing.expect(t, a.contacts[0][i] == b.contacts[0][i]); testing.expect(t, a.contacts[1][i] == b.contacts[1][i])}
	enemy :=
		a.friendly_count; friendly_view := combat_contact_trace(&a, .Friendly, enemy); enemy_view := combat_contact_trace(&a, .Raider, enemy)
	testing.expect_value(
		t,
		enemy_view.identity,
		Combat_Contact_Identity.Identified,
	); testing.expect(t, friendly_view^ != enemy_view^)
}

@(test)
combat_autoplay_is_deterministic :: proc(t: ^testing.T) {a := combat_autoplay(41); b :=
		combat_autoplay(41)
	testing.expect(t, a == b)}
