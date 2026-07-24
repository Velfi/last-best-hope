package game_tests

import "core:testing"

@(test)
combat_ai_parameters_are_bounded_and_side_specific :: proc(t: ^testing.T) {
	m := combat_new_mission(91)
	defer combat_mission_destroy(&m)
	defaults := combat_ai_default_parameters()
	testing.expect(t, combat_ai_parameters_valid(defaults))
	invalid := defaults
	invalid.travel_cost = 1.51
	testing.expect(t, !combat_ai_parameters_valid(invalid))
	testing.expect(t, !combat_ai_set_parameters(&m, .Raider, invalid))
	trained := defaults
	trained.objective_value = 1.25
	testing.expect(t, combat_ai_set_parameters(&m, .Raider, trained))
	testing.expect_value(t, combat_ai_parameters_for(&m, .Raider), trained)
	testing.expect_value(t, combat_ai_parameters_for(&m, .Friendly), defaults)
}

@(test)
combat_ai_evaluation_is_deterministic_and_aggregates_a_seed_batch :: proc(t: ^testing.T) {
	parameters := combat_ai_default_parameters()
	first := combat_ai_evaluate(parameters, 4401, 2)
	second := combat_ai_evaluate(parameters, 4401, 2)
	testing.expect_value(t, first, second)
	testing.expect_value(t, first.runs, 2)
	testing.expect(t, first.wins >= 0 && first.wins <= first.runs)
	testing.expect(t, first.partials >= 0 && first.partials <= first.runs)
	testing.expect(t, first.mean_time > 0)

	invalid := parameters
	invalid.sensor_value = 0
	testing.expect_value(t, combat_ai_evaluate(invalid, 4401, 2), Combat_AI_Evaluation{})
	testing.expect_value(t, combat_ai_evaluate(parameters, 4401, 0), Combat_AI_Evaluation{})
}

@(test)
combat_ai_league_covers_distinct_bounded_opponents_and_is_deterministic :: proc(t: ^testing.T) {
	for index in 0 ..< 4 {
		opponent := combat_ai_league_parameters(index)
		testing.expect(t, combat_ai_parameters_valid(opponent))
		testing.expect_value(t, combat_ai_league_doctrine(index), Combat_Doctrine(index))
	}
	parameters := combat_ai_default_parameters()
	first := combat_ai_evaluate_league(parameters, 8800, 4)
	second := combat_ai_evaluate_league(parameters, 8800, 4)
	testing.expect_value(t, first, second)
	testing.expect_value(t, first.runs, 4)
}

@(test)
combat_ai_curriculum_covers_each_ordinary_operation_and_opponent_once :: proc(t: ^testing.T) {
	seen: [COMBAT_AI_CURRICULUM_OPERATIONS][COMBAT_AI_CURRICULUM_OPPONENTS]bool
	for index in 0 ..< COMBAT_AI_CURRICULUM_RUNS {
		sample := combat_ai_curriculum_sample(24301, index)
		operation := index % COMBAT_AI_CURRICULUM_OPERATIONS
		testing.expect(t, sample.operation != .Citadel_Assault)
		testing.expect(t, sample.operation != .Silent_Infiltration)
		testing.expect_value(t, sample.operation, combat_ai_curriculum_operation(operation))
		testing.expect_value(t, sample.opponent_index, index / COMBAT_AI_CURRICULUM_OPERATIONS)
		testing.expect(t, sample.faction_count >= 2 && sample.faction_count <= 4)
		testing.expect(
			t,
			sample.faction_count <= skirmish_generation_budget(sample.operation).max_factions,
		)
		testing.expect(t, !seen[operation][sample.opponent_index])
		seen[operation][sample.opponent_index] = true
	}
	for operations in seen do for covered in operations do testing.expect(t, covered)
}

@(test)
combat_ai_curriculum_identity_is_deterministic_and_varies_by_batch :: proc(t: ^testing.T) {
	for index in 0 ..< COMBAT_AI_CURRICULUM_RUNS {
		first := combat_ai_curriculum_sample(24301, index)
		repeat := combat_ai_curriculum_sample(24301, index)
		neighbor := combat_ai_curriculum_sample(24302, index)
		testing.expect_value(t, first, repeat)
		testing.expect(
			t,
			first.mission_seed != neighbor.mission_seed ||
			first.contract_seed != neighbor.contract_seed,
		)
	}
}
