package game_tests

import "core:math"
import "core:testing"

far_test_run :: proc(e: ^Far_Engagement, max_steps := 100000) {
	if e.briefing_pending do _ = far_commit_briefing(e)
	for step in 0 ..< max_steps {
		if e.complete do break
		far_tick(e, .02)
		if e.decision.pending do _ = far_resolve_default(e)
	}
}

@(test)
far_physics_light_delay_uses_distance :: proc(t: ^testing.T) {
	delay := far_light_delay_seconds({0, 0}, {FAR_C_KM_S * 12, 0})
	testing.expect(t, math.abs(delay - 12) < 1.0e-9)
}

@(test)
far_physics_reachable_volume_is_bounded_by_delta_v :: proc(t: ^testing.T) {
	radius := far_reachable_radius_km(10, 1, 20)
	testing.expect(t, math.abs(radius - 150) < 1.0e-9)
}

@(test)
far_physics_intercept_fixture_matches_stationary_target :: proc(t: ^testing.T) {
	seconds, ok := far_intercept_time_seconds({1000, 0}, {0, 0}, 10)
	testing.expect(t, ok)
	testing.expect(t, math.abs(seconds - 100) < 1.0e-9)
}

@(test)
far_physics_kinetic_energy_uses_relative_velocity :: proc(t: ^testing.T) {
	energy := far_kinetic_energy_j(2, 3)
	testing.expect(t, math.abs(energy - 9.0e6) < 1)
}

@(test)
far_physics_catastrophic_overmatch_short_circuits_detail :: proc(t: ^testing.T) {
	outcome := far_ship_physics_from_hull(1, .Corvette, 80)
	far_apply_physical_impact(&outcome, .Kinetic, outcome.structure_j * 9, .1, 40, 1)
	testing.expect_value(t, outcome.state, Far_Ship_State.Destroyed)
	testing.expect_value(t, outcome.crew_surviving, 0)
	testing.expect(t, outcome.cause != "")
}

@(test)
far_physics_marginal_hit_records_a_physical_cause :: proc(t: ^testing.T) {
	outcome := far_ship_physics_from_hull(1, .Battleship, 900)
	resistance := far_armor_resistance_j(outcome.armor_areal_density_kg_m2, .12)
	far_apply_physical_impact(
		&outcome,
		.Kinetic,
		resistance + outcome.structure_j * .08,
		.12,
		41,
		2,
	)
	testing.expect(t, outcome.state != .Destroyed)
	testing.expect(t, outcome.last_coupled_energy_j > 0)
	testing.expect(t, outcome.cause != "")
}

@(test)
far_generator_covers_all_objective_families :: proc(t: ^testing.T) {
	for family in Far_Objective_Family {
		spec := far_default_spec(100 + u64(family))
		spec.objective_family = family
		e := far_generate_encounter(spec)
		testing.expect_value(t, e.spec.objective_family, family)
		testing.expect(t, e.task_group_count >= 3)
		testing.expect(t, e.truth_contact_count >= 1)
		testing.expect(t, far_validate(&e))
	}
}

@(test)
far_all_objective_families_reach_a_physical_terminal_state :: proc(t: ^testing.T) {
	for family in Far_Objective_Family {
		spec := far_default_spec(700 + u64(family))
		spec.objective_family = family
		e := far_generate_encounter(spec)
		far_set_authority(&e, .Report_Only)
		far_test_run(&e, 3000)
		testing.expect(t, e.complete)
		testing.expect(t, e.objective_complete || e.objective_failed)
		testing.expect(t, far_validate(&e))
	}
}

@(test)
far_generated_standard_operations_have_a_delegated_win_path :: proc(t: ^testing.T) {
	for family in Far_Objective_Family {
		for complication in Far_Complication {
			spec := far_default_spec(9000 + u64(family) * 32 + u64(complication))
			spec.objective_family = family
			spec.complication = complication
			e := far_generate_encounter(spec)
			far_set_authority(&e, .Report_Only)
			far_test_run(&e, 3000)

			testing.expect(t, e.complete)
			testing.expect(t, e.objective_complete)
			testing.expect(t, e.result.deadline_kept)
		}
	}
}

@(test)
far_next_decision_requires_an_in_flight_process :: proc(t: ^testing.T) {
	e := far_generate_encounter(far_default_spec(9182))
	commit := far_commit_briefing(&e)
	testing.expect(t, commit.ok)

	// Suppress the regular commitment prompts to exercise the no-decision path.
	e.authority = .Report_Only
	e.opening_commitment_resolved = true
	e.first_track_decision = true
	e.first_fire_decision = true
	e.first_defense_decision = true
	e.first_recovery_decision = true
	e.next_ai_plan_seconds = e.deadline_seconds + 3600
	e.next_observation_seconds = e.deadline_seconds + 3600

	far_advance_to_decision(&e)

	testing.expect(t, !e.complete)
	testing.expect(t, !far_can_advance_to_decision(&e))
	testing.expect_value(t, e.elapsed_seconds, f64(0))
}

@(test)
far_next_decision_stops_after_the_next_in_flight_event :: proc(t: ^testing.T) {
	e := far_generate_encounter(far_default_spec(9183))
	commit := far_commit_briefing(&e)
	testing.expect(t, commit.ok)
	e.authority = .Report_Only
	e.opening_commitment_resolved = true
	e.first_track_decision = true
	e.first_fire_decision = true
	e.first_defense_decision = true
	e.first_recovery_decision = true
	e.next_ai_plan_seconds = e.deadline_seconds + 3600
	e.next_observation_seconds = e.deadline_seconds + 3600
	e.transmission_count = 1
	e.transmissions[0] = {kind = .Observation, active = true, arrives_at_seconds = 60}

	testing.expect(t, far_can_advance_to_decision(&e))
	far_advance_to_decision(&e)

	testing.expect(t, !e.complete)
	testing.expect(t, e.transmissions[0].delivered)
	testing.expect(t, !e.transmissions[0].active)
	testing.expect(t, e.elapsed_seconds < e.deadline_seconds)
}

@(test)
far_reconnaissance_can_complete_from_a_confirmed_standoff_track :: proc(t: ^testing.T) {
	spec := far_default_spec(702)
	spec.objective_family = .Reconnaissance
	e := far_generate_encounter(spec)
	e.beliefs[0].identified = true
	e.stage_contact = true
	e.task_groups[2].position = {0, 0}
	e.truth_contacts[0].group.position = {20.0e6, 0}

	far_update_objective_state(&e)

	testing.expect(t, e.objective_complete)
	testing.expect(t, e.complete)
	testing.expect(t, e.result.passage_reached)
}

@(test)
far_reconnaissance_requires_a_close_track_before_standoff_completion :: proc(t: ^testing.T) {
	spec := far_default_spec(702)
	spec.objective_family = .Reconnaissance
	e := far_generate_encounter(spec)
	e.beliefs[0].identified = true
	e.task_groups[2].position = {0, 0}
	e.truth_contacts[0].group.position = {20.0e6, 0}

	far_update_objective_state(&e)

	testing.expect(t, !e.objective_complete)
	testing.expect(t, !e.complete)
}

@(test)
far_reconnaissance_default_plan_can_complete_before_the_deadline :: proc(t: ^testing.T) {
	spec := far_default_spec(702)
	spec.objective_family = .Reconnaissance
	e := far_generate_encounter(spec)
	far_set_authority(&e, .Report_Only)

	far_test_run(&e, 3000)

	testing.expect(t, e.complete)
	testing.expect(t, e.objective_complete)
	testing.expect(t, e.result.deadline_kept)
}

@(test)
far_withdrawal_default_plan_can_reach_the_return_corridor :: proc(t: ^testing.T) {
	spec := far_default_spec(703)
	spec.objective_family = .Withdrawal_Recovery
	e := far_generate_encounter(spec)
	far_set_authority(&e, .Report_Only)

	far_test_run(&e, 3000)

	testing.expect(t, e.complete)
	testing.expect(t, e.objective_complete)
	testing.expect(t, e.result.deadline_kept)
}

@(test)
far_deteriorating_deadline_updates_task_group_orders :: proc(t: ^testing.T) {
	spec := far_default_spec(704)
	spec.complication = .Deteriorating_Deadline
	e := far_generate_encounter(spec)

	for group in e.task_groups[:e.task_group_count] {
		testing.expect_value(t, group.order.deadline_seconds, e.deadline_seconds)
		testing.expect_value(t, group.received_order.deadline_seconds, e.deadline_seconds)
	}
}

@(test)
far_withdrawal_forecast_uses_the_slowest_returning_group :: proc(t: ^testing.T) {
	spec := far_default_spec(705)
	spec.objective_family = .Withdrawal_Recovery
	e := far_generate_encounter(spec)
	eta, ok := far_objective_eta_seconds(&e)

	testing.expect(t, ok)
	for i in 0 ..< e.task_group_count {
		group_eta, group_ok := far_projected_arrival_seconds(&e, i)
		testing.expect(t, group_ok)
		testing.expect(t, eta >= group_eta)
	}
}

@(test)
far_briefing_supports_manifest_and_doctrine_changes :: proc(t: ^testing.T) {
	e := far_default_engagement(4401)
	before := e.task_groups[0].member_count
	result := far_transfer_last_member(&e, 0, 1)
	testing.expect(t, result.ok)
	testing.expect_value(t, e.task_groups[0].member_count, before - 1)
	testing.expect(t, far_set_task_group_doctrine(&e, 1, .Complete_At_Cost).ok)
	testing.expect(t, far_commit_briefing(&e).ok)
	testing.expect(t, !far_transfer_last_member(&e, 1, 2).ok)
}

@(test)
far_opening_commitment_gives_a_proactive_plan :: proc(t: ^testing.T) {
	e := far_default_engagement(4414)
	_ = far_commit_briefing(&e)
	far_tick(&e, .02)
	testing.expect(t, e.decision.pending)
	testing.expect_value(t, e.decision.kind, Far_Decision_Kind.Opening_Commitment)
	testing.expect_value(t, e.decision.commands[0], Far_Command.Hold_Protected_Course)
	testing.expect_value(t, e.decision.commands[1], Far_Command.Shift_Intercept)
	testing.expect_value(t, e.decision.commands[2], Far_Command.Branch_Formation)
	decoys_before := e.decoys
	testing.expect(t, far_resolve_decision(&e, .Branch_Formation))
	testing.expect_value(t, e.opening_commitment, Far_Command.Branch_Formation)
	testing.expect(t, e.false_branch)
	testing.expect_value(t, e.decoys, decoys_before - 1)
}

@(test)
far_choice_projection_compares_branches_without_mutating_the_operation :: proc(t: ^testing.T) {
	e := far_default_engagement(4418)
	_ = far_commit_briefing(&e)
	far_tick(&e, .02)
	before := e

	hold := far_project_choice(&e, .Hold_Protected_Course)
	shift := far_project_choice(&e, .Shift_Intercept)

	testing.expect(t, hold.valid)
	testing.expect(t, shift.valid)
	testing.expect(t, hold.task_positions[0] != shift.task_positions[0])
	testing.expect_value(t, e, before)
}

@(test)
far_shift_intercept_delays_the_hostile_launch_window_on_receipt :: proc(t: ^testing.T) {
	e := far_default_engagement(4417)
	_ = far_commit_briefing(&e)
	e.opening_commitment = .Shift_Intercept
	order := e.task_groups[0].received_order
	order.destination.y += 3.0e6
	before := e.next_enemy_launch_seconds
	testing.expect(t, far_transmit_order(&e, e.task_groups[0].position, 0, order).ok)
	far_deliver_transmissions(&e)
	testing.expect(t, e.intercept_pressure_applied)
	testing.expect_value(t, e.next_enemy_launch_seconds, before + 1800)
}

@(test)
far_command_transmission_arrives_after_light_delay :: proc(t: ^testing.T) {
	e := far_default_engagement(4402)
	_ = far_commit_briefing(&e)
	if e.decision.pending do testing.expect(t, far_resolve_default(&e))
	order := e.task_groups[2].order
	before_verb := e.task_groups[2].received_order.verb
	order.verb = before_verb == .Observe ? .Intercept : .Observe
	result := far_transmit_order(&e, e.task_groups[0].position, 2, order)
	testing.expect(t, result.ok)
	arrival := e.transmissions[e.transmission_count - 1].arrives_at_seconds
	testing.expect(t, arrival > e.elapsed_seconds)
	far_step_physical(&e, arrival - e.elapsed_seconds - .01)
	testing.expect_value(t, e.task_groups[2].received_order.verb, before_verb)
	if e.decision.pending do testing.expect(t, far_resolve_default(&e))
	far_step_physical(&e, .02)
	testing.expect_value(t, e.task_groups[2].received_order.verb, order.verb)
}

@(test)
far_formation_changes_only_when_the_order_arrives :: proc(t: ^testing.T) {
	e := far_default_engagement(4412)
	_ = far_commit_briefing(&e)
	order := e.task_groups[1].received_order
	order.formation = .Dispersed
	formation_before := e.groups[1].formation
	cohesion_before := e.groups[1].cohesion
	result := far_transmit_order(&e, e.task_groups[0].position, 1, order)
	testing.expect(t, result.ok)
	arrival := e.transmissions[0].arrives_at_seconds
	testing.expect(t, arrival > e.elapsed_seconds)
	e.elapsed_seconds = arrival - .01
	far_deliver_transmissions(&e)
	testing.expect_value(t, e.groups[1].formation, formation_before)
	testing.expect_value(t, e.groups[1].cohesion, cohesion_before)
	e.elapsed_seconds = arrival
	far_deliver_transmissions(&e)
	testing.expect_value(t, e.groups[1].formation, Far_Formation.Dispersed)
	testing.expect_value(t, e.groups[1].cohesion, cohesion_before - 12)
}

@(test)
far_maintain_screen_transmits_instead_of_applying_immediately :: proc(t: ^testing.T) {
	e := far_default_engagement(4413)
	_ = far_commit_briefing(&e)
	initial := e.groups[0].formation
	far_raise_decision(
		&e,
		.Defensive_Shaping,
		"SCREEN",
		"Inbound",
		"Hold formation",
		{.Maintain_Screen},
		{"SCREEN"},
		{"Transmit screen orders."},
	)
	testing.expect(t, far_resolve_decision(&e, .Maintain_Screen))
	testing.expect_value(t, e.groups[0].formation, initial)
	testing.expect(t, e.transmission_count >= e.task_group_count)
}

@(test)
far_expose_screen_changes_the_received_physical_course :: proc(t: ^testing.T) {
	e := far_default_engagement(4419)
	_ = far_commit_briefing(&e)
	before := e.task_groups[1].received_order.destination
	far_raise_decision(
		&e,
		.Constraint_Conflict,
		"SCREEN",
		"Crossing",
		"Expose the screen.",
		{.Expose_Screen},
		{"EXPOSE"},
		{"Cross under active illumination."},
	)

	testing.expect(t, far_resolve_decision(&e, .Expose_Screen))
	testing.expect(t, e.transmission_count > 0)
	arrival := e.transmissions[e.transmission_count - 1].arrives_at_seconds
	e.elapsed_seconds = arrival
	far_deliver_transmissions(&e)
	testing.expect(t, e.task_groups[1].received_order.destination.y < before.y)
}

@(test)
far_unaffordable_decision_remains_pending :: proc(t: ^testing.T) {
	e := far_default_engagement(4403)
	_ = far_commit_briefing(&e)
	e.heavy_ordnance = 0
	far_raise_decision(
		&e,
		.Launch_Authorization,
		"FIRE",
		"Track",
		"No reserve",
		{.Launch_Full_Salvo, .Hold_Ordnance},
		{"FULL", "HOLD"},
		{"Spend five.", "Preserve."},
		1,
	)
	testing.expect(t, !far_resolve_decision(&e, .Launch_Full_Salvo))
	testing.expect(t, e.decision.pending)
	testing.expect(t, far_resolve_decision(&e, .Hold_Ordnance))
}

@(test)
far_decision_previews_expose_each_option_cost :: proc(t: ^testing.T) {
	e := far_default_engagement(4411)
	e.selected_belief = 0
	e.beliefs[0].confidence = .9
	kinetic := far_preview_command(&e, .Launch_Shaping_Salvo)
	missiles := far_preview_command(&e, .Launch_Full_Salvo)
	disperse := far_preview_command(&e, .Disperse_Fleet)
	decoys := far_preview_command(&e, .Deploy_Decoys)
	testing.expect_value(t, kinetic.ordnance_cost, 2)
	testing.expect_value(t, missiles.ordnance_cost, 5)
	testing.expect(t, disperse.delta_v_cost_km_s > 0)
	testing.expect_value(t, decoys.decoy_cost, 2)
	testing.expect(t, kinetic.weapon_flight_seconds > missiles.weapon_flight_seconds)
	testing.expect(t, kinetic.target_uncertainty_at_arrival_km > 0)
}

@(test)
far_authority_levels_expose_distinct_boundaries :: proc(t: ^testing.T) {
	e := far_default_engagement(4409)
	far_set_authority(&e, .Report_Only)
	testing.expect(t, !far_decision_required(&e, true, true))
	far_set_authority(&e, .Confirm_Commitments)
	testing.expect(t, far_decision_required(&e, true, false))
	testing.expect(t, !far_decision_required(&e, false, true))
	far_set_authority(&e, .Confirm_Engagements)
	testing.expect(t, far_decision_required(&e, false, true))
	testing.expect(t, !far_decision_required(&e, false, false))
	far_set_authority(&e, .Direct_Command)
	testing.expect(t, far_decision_required(&e, false, false))
}

@(test)
far_laser_diffraction_grows_with_range :: proc(t: ^testing.T) {
	near := far_laser_spot_radius_m(1.06e-6, 18, 1.0e6, 1.5e-8)
	far := far_laser_spot_radius_m(1.06e-6, 18, 10.0e6, 1.5e-8)
	testing.expect(t, far > near * 9.9)
}

@(test)
far_guided_weapon_expends_finite_propellant :: proc(t: ^testing.T) {
	e := far_default_engagement(4410)
	_ = far_commit_briefing(&e)
	for &belief in e.beliefs[:e.belief_count] do belief.confidence = .9
	result := far_launch_physical_weapon(&e, true, 1, 0, .Guided_Missile, 2)
	testing.expect(t, result.ok)
	before := e.weapon_flights[0].propellant_seconds
	far_update_weapon_flights(&e, 30)
	testing.expect_value(t, e.weapon_flights[0].propellant_seconds, before - 30)
}

@(test)
far_branched_course_can_draw_hostile_fire_from_the_passage_group :: proc(t: ^testing.T) {
	e := far_default_engagement(4414)
	_ = far_commit_briefing(&e)
	e.false_branch = true
	e.groups[0].formation = .Branched
	expected := e.task_groups[0].stable_id
	if far_mix(e.seed ~ u64(e.weapon_flight_count)) % 2 == 0 do expected = e.task_groups[1].stable_id
	result := far_launch_physical_weapon(&e, false, 0, 0, .Guided_Missile, 2)
	testing.expect(t, result.ok)
	testing.expect_value(t, e.weapon_flights[0].target_group_id, expected)
	if expected == e.task_groups[1].stable_id do testing.expect_value(t, e.hostile_flights_diverted, 1)
}

@(test)
far_terminal_defense_exposes_a_cohesion_tradeoff :: proc(t: ^testing.T) {
	e := far_default_engagement(4415)
	e.groups[1].formation = .Dispersed
	e.groups[1].cohesion = 100
	high, _ := far_inbound_defense_profile(&e, 1)
	e.groups[1].cohesion = 40
	low, _ := far_inbound_defense_profile(&e, 1)
	testing.expect(t, high > low)
}

@(test)
far_disabled_screen_ship_raises_a_recovery_dilemma :: proc(t: ^testing.T) {
	e := far_default_engagement(4416)
	_ = far_commit_briefing(&e)
	e.opening_commitment_resolved = true
	ship_id := e.task_groups[1].member_ids[0]
	for &outcome in e.ship_outcomes[:e.ship_outcome_count] do if outcome.friendly && outcome.ship_id == ship_id do outcome.state = .Mission_Killed
	far_evaluate_physical_events(&e)
	testing.expect_value(t, e.decision.kind, Far_Decision_Kind.Recovery_Commitment)
	testing.expect(t, far_resolve_decision(&e, .Dispatch_Recovery))
	testing.expect(t, e.recovery_committed)
	testing.expect(t, e.transmission_count > 0)
}

@(test)
far_same_seed_and_commands_are_deterministic :: proc(t: ^testing.T) {
	a := far_default_engagement(4404)
	b := far_default_engagement(4404)
	_ = far_commit_briefing(&a)
	_ = far_commit_briefing(&b)
	for step in 0 ..< 6000 {
		far_tick(&a, .02)
		far_tick(&b, .02)
		if a.decision.pending {
			testing.expect(t, b.decision.pending)
			command := a.decision.commands[a.decision.default_option]
			testing.expect(t, far_resolve_decision(&a, command))
			testing.expect(t, far_resolve_decision(&b, command))
		}
		if a.complete do break
	}
	testing.expect_value(t, a, b)
}

@(test)
far_different_seeds_change_hidden_truth :: proc(t: ^testing.T) {
	a := far_default_engagement(4405)
	b := far_default_engagement(4406)
	testing.expect(
		t,
		a.truth_contacts[0].group.position != b.truth_contacts[0].group.position ||
		a.spec.complication != b.spec.complication,
	)
}

@(test)
far_active_physical_state_round_trips :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 4407)
	defer campaign_destroy(&c)
	c.far_engagement^ = far_generate_campaign_encounter(&c, 4407)
	_ = far_commit_briefing(c.far_engagement)
	far_tick(c.far_engagement, .5)
	data := campaign_serialize(&c)
	defer delete(data)
	restored: Campaign
	defer campaign_destroy(&restored)
	result := campaign_deserialize(data[:], &restored)
	testing.expect(t, result.ok)
	testing.expect_value(
		t,
		restored.far_engagement.elapsed_seconds,
		c.far_engagement.elapsed_seconds,
	)
	testing.expect_value(
		t,
		restored.far_engagement.task_groups[0],
		c.far_engagement.task_groups[0],
	)
	testing.expect_value(t, restored.far_engagement.beliefs[0], c.far_engagement.beliefs[0])
	testing.expect_value(
		t,
		restored.far_engagement.transmission_count,
		c.far_engagement.transmission_count,
	)
}

@(test)
far_aftermath_applies_to_exact_persistent_ship_once :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 4408)
	defer campaign_destroy(&c)
	c.far_engagement^ = far_generate_campaign_encounter(&c, 4408)
	target_id := c.far_engagement.ship_outcomes[1].ship_id
	target_index := ship_index(&c, target_id)
	c.far_engagement.ship_outcomes[1].state = .Mission_Killed
	c.far_engagement.ship_outcomes[1].cause = "Drive destroyed by a penetrative kinetic impact."
	c.far_engagement.complete = true
	c.far_engagement.active = false
	c.far_engagement.result.ships_disabled = 1
	before_damage := c.ships[target_index].damage
	testing.expect(t, far_apply_campaign_result(&c))
	testing.expect_value(t, c.ships[target_index].damage, before_damage + 3)
	testing.expect(t, c.ships[target_index].history_note != "")
	testing.expect(t, !far_apply_campaign_result(&c))
}
