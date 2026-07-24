package main

import game "../packages/game"
import "core:testing"

@(test)
combat_ai_trial_aggregation_preserves_weighted_metrics :: proc(t: ^testing.T) {
	total: game.Combat_AI_Evaluation
	combat_ai_evaluation_add(
		&total,
		{
			runs = 2,
			wins = 1,
			preserved = 3,
			player_losses = 1,
			mean_time = 100,
			recovery_profile_runs = {2, 0, 0, 0},
			recovery_profile_wins = {1, 0, 0, 0},
		},
	)
	combat_ai_evaluation_add(
		&total,
		{
			runs = 1,
			wins = 1,
			preserved = 1,
			player_losses = 2,
			mean_time = 160,
			recovery_profile_runs = {1, 0, 0, 0},
			recovery_profile_wins = {1, 0, 0, 0},
		},
	)
	testing.expect_value(t, total.runs, 3)
	testing.expect_value(t, total.wins, 2)
	testing.expect_value(t, total.preserved, 4)
	testing.expect_value(t, total.player_losses, 3)
	testing.expect_value(t, total.mean_time, f64(120))
	testing.expect_value(t, total.recovery_profile_runs[0], 3)
	testing.expect_value(t, total.recovery_profile_wins[0], 2)
	testing.expect_value(t, total.score, game.combat_ai_evaluation_score(total))
}

@(test)
combat_ai_trial_equality_checks_all_reported_metrics :: proc(t: ^testing.T) {
	value := game.Combat_AI_Evaluation {
		score = 12,
		runs = 3,
		wins = 2,
		mean_time = 80,
	}
	testing.expect(t, combat_ai_evaluation_equal(value, value))
	changed := value
	changed.mean_time += 1
	testing.expect(t, !combat_ai_evaluation_equal(value, changed))
}

@(test)
combat_ai_parallel_evaluation_matches_single_worker :: proc(t: ^testing.T) {
	parameters := game.combat_ai_default_parameters()
	single :=
		combat_ai_evaluate_parallel(
			parameters,
			73001,
			game.COMBAT_AI_CURRICULUM_RUNS,
			1,
		)
	parallel :=
		combat_ai_evaluate_parallel(
			parameters,
			73001,
			game.COMBAT_AI_CURRICULUM_RUNS,
			8,
		)
	testing.expect(t, combat_ai_evaluation_equal(single, parallel))
}

combat_ai_gate_fixture :: proc() -> game.Combat_AI_Evaluation {
	value := game.Combat_AI_Evaluation {
		score = 48000,
		runs = 48,
		wins = 30,
		preserved = 360,
		player_losses = 40,
		friendly_total = 480,
	}
	for &family in value.families {
		family = {
			score = 16000,
			runs = 16,
			wins = 10,
			preserved = 120,
			player_losses = 13,
			friendly_total = 160,
		}
	}
	return value
}

@(test)
combat_ai_promotion_gate_accepts_balanced_improvement :: proc(t: ^testing.T) {
	incumbent := combat_ai_gate_fixture()
	candidate := incumbent
	candidate.score += 100
	for &family in candidate.families do family.score += 40
	accepted, reason := combat_ai_promotion_gate(incumbent, candidate)
	testing.expect(t, accepted)
	testing.expect_value(t, reason, "accepted")
}

@(test)
combat_ai_promotion_gate_rejects_family_collapse :: proc(t: ^testing.T) {
	incumbent := combat_ai_gate_fixture()
	candidate := incumbent
	candidate.score += 100
	candidate.families[int(game.Combat_AI_Operation_Family.Recovery)].score -= 401
	accepted, reason := combat_ai_promotion_gate(incumbent, candidate)
	testing.expect(t, !accepted)
	testing.expect_value(t, reason, "recovery score regressed")
}

@(test)
combat_ai_promotion_gate_rejects_safety_regressions :: proc(t: ^testing.T) {
	incumbent := combat_ai_gate_fixture()
	candidate := incumbent
	candidate.score += 100
	candidate.player_losses += 25
	accepted, _ := combat_ai_promotion_gate(incumbent, candidate)
	testing.expect(t, !accepted)
	candidate = incumbent
	candidate.score += 100
	candidate.wins -= 1
	accepted, _ = combat_ai_promotion_gate(incumbent, candidate)
	testing.expect(t, !accepted)
}

@(test)
combat_ai_promotion_gate_rejects_recovery_profile_collapse :: proc(t: ^testing.T) {
	incumbent := combat_ai_gate_fixture()
	incumbent.recovery_profile_runs = {4, 4, 4, 4}
	incumbent.recovery_profile_wins = {4, 3, 3, 3}
	candidate := incumbent
	candidate.score += 100
	candidate.recovery_profile_wins[2] -= 2
	accepted, reason := combat_ai_promotion_gate(incumbent, candidate)
	testing.expect(t, !accepted)
	testing.expect_value(t, reason, "drifting recovery profile collapsed")
}
