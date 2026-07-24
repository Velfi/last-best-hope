package game_tests

import "core:testing"

@(test)
operation_generation_is_deterministic :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.seed = 41021
	setup.contract_seed = 992
	a := combat_operation_generate_skirmish(setup)
	b := combat_operation_generate_skirmish(setup)
	testing.expect_value(t, a.geography_seed, b.geography_seed)
	testing.expect_value(t, a.battlespace, b.battlespace)
	testing.expect_value(t, a.intelligence, b.intelligence)
	testing.expect_value(t, a.enemy_plan, b.enemy_plan)
	testing.expect_value(t, a.draft, b.draft)
}

@(test)
enemy_plan_is_independent_of_player_edits :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.seed = 41022
	operation := combat_operation_generate_skirmish(setup)
	enemy := operation.enemy_plan
	operation.draft.groups[0].primary_route.waypoints[1].z += 250
	operation.draft.groups[0].doctrine = combat_doctrine_policy(.Last_Stand)
	testing.expect_value(t, operation.enemy_plan, enemy)
}

@(test)
operation_commit_is_validated_and_immutable :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.seed = 41023
	operation := combat_operation_generate_skirmish(setup)
	testing.expect(t, operation.draft.validation.valid)
	testing.expect(t, combat_operation_commit(&operation))
	testing.expect(t, operation.committed_plan.committed)
	testing.expect(t, operation.committed_plan.immutable)
	testing.expect(t, !combat_operation_commit(&operation))
}

@(test)
operation_rejects_missing_withdrawal_and_reserve_trigger :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.seed = 41024
	operation := combat_operation_generate_skirmish(setup)
	operation.draft.groups[0].withdrawal_route.count = 0
	operation.draft.groups[1].reserve = true
	operation.draft.groups[1].contingency_count = 0
	result := combat_operation_validate_plan(&operation, &operation.draft)
	testing.expect(t, !result.valid)
	found_withdrawal, found_reserve := false, false
	for issue in result.errors[:result.error_count] {
		if issue == .Withdrawal_Missing do found_withdrawal = true
		if issue == .Reserve_Without_Trigger do found_reserve = true
	}
	testing.expect(t, found_withdrawal)
	testing.expect(t, found_reserve)
}

@(test)
operation_group_withdrawal_is_irreversible :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.seed = 41025
	operation := combat_operation_generate_skirmish(setup)
	testing.expect(t, combat_operation_commit(&operation))
	mission := combat_new_skirmish_mission(setup.seed, setup)
	defer combat_mission_destroy(&mission)
	testing.expect(t, combat_operation_compile_mission(&mission, &operation))
	testing.expect(t, combat_operation_withdraw_group(&mission, 0))
	testing.expect(t, !combat_operation_withdraw_group(&mission, 0))
}

@(test)
operation_withdrawal_does_not_mutate_committed_orders :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.seed = 41026
	operation := combat_operation_generate_skirmish(setup)
	testing.expect(t, combat_operation_commit(&operation))
	mission := combat_new_skirmish_mission(setup.seed, setup)
	defer combat_mission_destroy(&mission)
	testing.expect(t, combat_operation_compile_mission(&mission, &operation))
	orders := mission.operation.committed_plan
	testing.expect(t, combat_operation_withdraw_group(&mission, 0))
	testing.expect_value(t, mission.operation.committed_plan, orders)
}

@(test)
route_validation_checks_segments_not_only_waypoints :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.seed = 41027
	operation := combat_operation_generate_skirmish(setup)
	feature := &operation.battlespace.features[0]
	feature.impassable = true
	feature.volume = {
		kind   = .Sphere,
		center = {0, 0, 0},
		radius = 60,
	}
	route: Combat_Plan_Route
	route.waypoints[0] = {-100, 0, 0}
	route.waypoints[1] = {100, 0, 0}
	route.count = 2
	inside, passable := combat_plan_route_valid(&operation, route)
	testing.expect(t, inside)
	testing.expect(t, !passable)
}

@(test)
generated_operations_have_safe_dual_approaches :: proc(t: ^testing.T) {
	for seed in u64(1) ..= 256 {
		setup := skirmish_default_setup()
		setup.seed = seed
		setup.contract_seed = seed * 17 + 3
		operation := combat_operation_generate_skirmish(setup)
		testing.expect(t, operation.draft.validation.valid)
		for objective_index in 0 ..< operation.battlespace.objective_count {
			objective_node := 2 + objective_index * 3
			testing.expect(t, operation.battlespace.nodes[objective_node].neighbor_count >= 3)
		}
	}
}

@(test)
committed_ability_uses_approval_request :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.seed = 41028
	operation := combat_operation_generate_skirmish(setup)
	testing.expect(t, combat_operation_commit(&operation))
	mission := combat_new_skirmish_mission(setup.seed, setup)
	defer combat_mission_destroy(&mission)
	testing.expect(t, combat_operation_compile_mission(&mission, &operation))
	mission.units[0].hull_archetype = .Scout
	mission.units[0].ability_charges = 1
	before := mission.units[0].ability_charges
	testing.expect(t, combat_request_ship_ability(&mission, 0))
	testing.expect_value(t, mission.request_kind, Combat_Request_Kind.Authorize_Ability)
	testing.expect_value(t, mission.units[0].ability_charges, before)
	combat_resolve_request(&mission, true)
	testing.expect_value(t, mission.units[0].ability_charges, before - 1)
}

@(test)
campaign_mission_preserves_eight_group_identities :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 41029)
	defer campaign_destroy(&c)
	testing.expect(t, c.ship_count >= COMBAT_GROUP_COUNT)
	c.combat_deployment_active = true
	c.combat_deployment_seed = 41029
	c.combat_deployment_count = COMBAT_GROUP_COUNT
	for index in 0 ..< COMBAT_GROUP_COUNT {
		c.combat_deployment_ships[index] = c.ships[index].id
		c.combat_deployment_groups[index] = index
	}
	mission := combat_new_campaign_mission(&c)
	defer combat_mission_destroy(&mission)
	testing.expect(t, mission.friendly_count >= COMBAT_GROUP_COUNT)
	for index in 0 ..< COMBAT_GROUP_COUNT do testing.expect_value(t, mission.campaign_ship_elements[index], index)
}

@(test)
linked_draft_carries_tactical_continuity :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.seed = 41030
	operation := combat_operation_generate_skirmish(setup)
	testing.expect(t, combat_operation_commit(&operation))
	mission := combat_new_skirmish_mission(setup.seed, setup)
	defer combat_mission_destroy(&mission)
	testing.expect(t, combat_operation_compile_mission(&mission, &operation))
	mission.time = 120
	mission.units[0].position = {17, 23, -9}
	mission.units[0].torpedoes = 1
	linked := combat_operation_linked_draft(&mission)
	testing.expect(t, linked.chain.active)
	testing.expect_value(t, linked.chain.elapsed_time, f32(120))
	testing.expect_value(t, linked.chain.ships[0].position, Combat_Vec3{17, 23, -9})
	testing.expect(t, !linked.draft.committed && !linked.draft.immutable)
}

@(test)
independent_doctrine_policies_change_autonomy :: proc(t: ^testing.T) {
	base: Combat_Group
	base.cohesion = 45
	base.readiness = 55
	base.strength = .8
	base.escape_margin = 80
	parameters := combat_ai_default_parameters()

	preserve := base
	preserve.objective_policy = .Preserve_Force
	complete := base
	complete.objective_policy = .Complete_At_Cost
	preserve_score := combat_maneuver_utility(
		.Ambush,
		preserve,
		parameters,
		true,
		.8,
		150,
		20,
		.4,
		.2,
		1,
		.8,
		false,
	)
	complete_score := combat_maneuver_utility(
		.Ambush,
		complete,
		parameters,
		true,
		.8,
		150,
		20,
		.4,
		.2,
		1,
		.8,
		false,
	)
	testing.expect(t, complete_score > preserve_score)

	avoid := base
	avoid.engagement_policy = .Avoid
	seek := base
	seek.engagement_policy = .Seek_Battle
	avoid_score := combat_maneuver_utility(
		.Skirmish_Pass,
		avoid,
		parameters,
		true,
		.8,
		150,
		20,
		.4,
		.2,
		1,
		.5,
		false,
	)
	seek_score := combat_maneuver_utility(
		.Skirmish_Pass,
		seek,
		parameters,
		true,
		.8,
		150,
		20,
		.4,
		.2,
		1,
		.5,
		false,
	)
	testing.expect(t, seek_score > avoid_score)

	tight := base
	tight.cohesion_policy = .Tight
	independent := base
	independent.cohesion_policy = .Independent
	tight_score := combat_maneuver_utility(
		.Reform,
		tight,
		parameters,
		false,
		0,
		0,
		10,
		.2,
		.2,
		1,
		.5,
		false,
	)
	independent_score := combat_maneuver_utility(
		.Reform,
		independent,
		parameters,
		false,
		0,
		0,
		10,
		.2,
		.2,
		1,
		.5,
		false,
	)
	testing.expect(t, tight_score > independent_score)

	conserve := base
	conserve.ordnance_policy = .Conserve
	liberal := base
	liberal.ordnance_policy = .Liberal
	conserve_score := combat_maneuver_utility(
		.Ambush,
		conserve,
		parameters,
		true,
		.8,
		150,
		20,
		.4,
		.2,
		1,
		.5,
		false,
	)
	liberal_score := combat_maneuver_utility(
		.Ambush,
		liberal,
		parameters,
		true,
		.8,
		150,
		20,
		.4,
		.2,
		1,
		.5,
		false,
	)
	testing.expect(t, liberal_score > conserve_score)

	policy := combat_doctrine_policy(.Balanced)
	policy.emissions = .Silent
	policy.targets = .Capitals
	policy.pursuit = .None
	policy.withdrawal = .Early
	policy.rescue = .Leave_Disabled
	applied: Combat_Group
	combat_apply_doctrine_policy(&applied, policy)
	testing.expect_value(t, applied.emission_policy, Combat_Emission_Policy.Silent)
	testing.expect_value(t, applied.priority, Combat_Target_Priority.Capital)
	testing.expect_value(t, applied.pursuit_limit, f32(0))
	testing.expect_value(t, applied.withdraw_threshold, f32(72))
	testing.expect_value(t, applied.rescue_policy, Combat_Rescue_Policy.Leave_Disabled)
}

@(test)
operation_plan_json_round_trip_is_validated :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.seed = 41031
	operation := combat_operation_generate_skirmish(setup)
	data, ok := combat_operation_plan_export_json(&operation.draft)
	testing.expect(t, ok)
	defer delete(data)
	imported := combat_operation_generate_skirmish(setup)
	imported.draft.groups[0].name = "Changed"
	testing.expect(t, combat_operation_plan_import_json(&imported, data))
	testing.expect(t, imported.draft.validation.valid)

	broken := operation.draft
	broken.groups[0].primary_route.count = 0
	broken_data, broken_ok := combat_operation_plan_export_json(&broken)
	testing.expect(t, broken_ok)
	defer delete(broken_data)
	testing.expect(t, !combat_operation_plan_import_json(&imported, broken_data))
}

@(test)
invalid_committed_operation_is_rejected_on_load_validation :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.seed = 41032
	operation := combat_operation_generate_skirmish(setup)
	testing.expect(t, combat_operation_commit(&operation))
	testing.expect(t, combat_operation_validate_loaded(&operation))
	operation.committed_plan.groups[0].withdrawal_route.count = 0
	testing.expect(t, !combat_operation_validate_loaded(&operation))
}
