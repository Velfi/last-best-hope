package main

import game "../packages/game"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:time"

Combat_AI_Trial_Block :: struct {
	index:                                                   int,
	seed:                                                    u64,
	runs:                                                    int,
	baseline, candidate:                                     game.Combat_AI_Evaluation,
	score_delta_per_run, win_rate_delta, loss_delta_per_run: f64,
	regression:                                              bool,
}

Combat_AI_Trial_Report :: struct {
	version:                                               int,
	curriculum_version:                                    int,
	controller_revision, evaluation_revision:              int,
	matrix_runs:                                           int,
	operation_names:                                       [game.COMBAT_AI_CURRICULUM_OPERATIONS]string,
	checkpoint_generation:                                 int,
	checkpoint_seed, holdout_seed:                         u64,
	runs_per_block, block_count, total_runs, worker_count: int,
	deterministic:                                         bool,
	baseline, candidate:                                   game.Combat_AI_Evaluation,
	score_delta_per_run, win_rate_delta:                   f64,
	win_rate_delta_ci95_low, win_rate_delta_ci95_high:     f64,
	preservation_delta_per_run, loss_delta_per_run:        f64,
	positive_blocks, regressing_blocks:                    int,
	promotion_recommended:                                 bool,
	verdict:                                               string,
	blocks:                                                [dynamic]Combat_AI_Trial_Block,
}

combat_ai_evaluation_add :: proc(
	total: ^game.Combat_AI_Evaluation,
	value: game.Combat_AI_Evaluation,
) {
	game.combat_ai_evaluation_merge(total, value)
}

combat_ai_evaluation_equal :: proc(a, b: game.Combat_AI_Evaluation) -> bool {
	equal :=
		a.score == b.score &&
		a.runs == b.runs &&
		a.wins == b.wins &&
		a.partials == b.partials &&
		a.objectives == b.objectives &&
		a.primary_failures == b.primary_failures &&
		a.objective_orders == b.objective_orders &&
		a.interaction_completions == b.interaction_completions &&
		a.extraction_completions == b.extraction_completions &&
		a.objective_aborts == b.objective_aborts &&
		a.probe_launches == b.probe_launches &&
		a.probe_completions == b.probe_completions &&
		a.probe_losses == b.probe_losses &&
		a.screened_runs == b.screened_runs &&
		a.recovery_profile_runs == b.recovery_profile_runs &&
		a.recovery_profile_wins == b.recovery_profile_wins &&
		a.preserved == b.preserved &&
		a.disabled == b.disabled &&
		a.enemy_losses == b.enemy_losses &&
		a.player_losses == b.player_losses &&
		a.ordnance_remaining == b.ordnance_remaining &&
		a.mean_time == b.mean_time &&
		a.initial_ordnance == b.initial_ordnance &&
		a.friendly_total == b.friendly_total &&
		a.enemy_total == b.enemy_total &&
		a.operations == b.operations &&
		a.families == b.families
	return equal
}

combat_ai_trial_report_write :: proc(path: string, report: ^Combat_AI_Trial_Report) -> bool {
	data, err := json.marshal(report^)
	if err != nil {
		fmt.eprintf("could not serialize trial report %s: %v\n", path, err)
		return false
	}
	defer delete(data)
	return combat_ai_write_file_atomically(path, data[:])
}

combat_ai_run_trials :: proc(
	checkpoint_path, report_path: string,
	runs_per_block, block_count: int,
	holdout_seed: u64,
	workers: int,
) -> bool {
	if runs_per_block < game.COMBAT_AI_CURRICULUM_RUNS ||
	   runs_per_block % game.COMBAT_AI_CURRICULUM_RUNS != 0 {
		fmt.eprintf(
			"trial runs per block must be a positive multiple of %d\n",
			game.COMBAT_AI_CURRICULUM_RUNS,
		)
		return false
	}
	checkpoint, ok, _ := combat_ai_checkpoint_read(checkpoint_path)
	if !ok {
		fmt.eprintln("checkpoint is missing or invalid")
		return false
	}
	report := Combat_AI_Trial_Report {
		version               = 2,
		curriculum_version    = game.COMBAT_AI_CURRICULUM_VERSION,
		controller_revision   = game.COMBAT_AI_CONTROLLER_REVISION,
		evaluation_revision   = game.COMBAT_AI_EVALUATION_REVISION,
		matrix_runs           = game.COMBAT_AI_CURRICULUM_RUNS,
		operation_names       = combat_ai_operation_names(),
		checkpoint_generation = checkpoint.generation,
		checkpoint_seed       = checkpoint.seed,
		holdout_seed          = holdout_seed,
		runs_per_block        = runs_per_block,
		block_count           = block_count,
		worker_count          = workers,
	}
	defer delete(report.blocks)
	baseline_parameters := game.combat_ai_default_parameters()
	started := time.tick_now()
	total_planned := runs_per_block * block_count
	progress_interval := max(1, runs_per_block / 10)
	fmt.printf(
		"starting paired combat AI trials: %d battles in %d blocks with %d workers; report=%s\n",
		total_planned,
		block_count,
		workers,
		report_path,
	)
	for block_index in 0 ..< block_count {
		block_seed := holdout_seed + u64(block_index * runs_per_block)
		baseline, candidate: game.Combat_AI_Evaluation
		for batch_start := 0; batch_start < runs_per_block; batch_start += workers {
			batch_runs := min(workers, runs_per_block - batch_start)
			combat_ai_evaluation_add(
				&baseline,
				combat_ai_evaluate_parallel(
					baseline_parameters,
					block_seed,
					batch_runs,
					workers,
					batch_start,
				),
			)
			combat_ai_evaluation_add(
				&candidate,
				combat_ai_evaluate_parallel(
					checkpoint.champion,
					block_seed,
					batch_runs,
					workers,
					batch_start,
				),
			)
			block_completed := batch_start + batch_runs
			completed := block_index * runs_per_block + block_completed
			if block_completed / progress_interval != batch_start / progress_interval ||
			   block_completed == runs_per_block {
				elapsed := time.duration_seconds(time.tick_since(started))
				eta := elapsed / f64(completed) * f64(total_planned - completed)
				score_delta := (candidate.score - baseline.score) / f64(block_completed)
				win_delta := f64(candidate.wins - baseline.wins) / f64(block_completed)
				fmt.printf(
					"trial progress %d/%d (%.1f%%) block=%d/%d sample=%d/%d elapsed=%.0fs eta=%.0fs score=%+.2f/run wins=%+.1f%%\n",
					completed,
					total_planned,
					f64(completed) * 100 / f64(total_planned),
					block_index + 1,
					block_count,
					block_completed,
					runs_per_block,
					elapsed,
					eta,
					score_delta,
					win_delta * 100,
				)
			}
		}
		block := Combat_AI_Trial_Block {
			index               = block_index,
			seed                = block_seed,
			runs                = runs_per_block,
			baseline            = baseline,
			candidate           = candidate,
			score_delta_per_run = (candidate.score - baseline.score) / f64(runs_per_block),
			win_rate_delta      = f64(candidate.wins - baseline.wins) / f64(runs_per_block),
			loss_delta_per_run  = combat_ai_rate(
				candidate.player_losses,
				candidate.friendly_total,
			) - combat_ai_rate(baseline.player_losses, baseline.friendly_total),
		}
		// A block regression is material if it loses wins or gives away at
		// least a quarter of a player ship per mission without compensating.
		block.regression =
			candidate.wins < baseline.wins ||
			(block.loss_delta_per_run > .05 && block.score_delta_per_run <= 0)
		if block.score_delta_per_run > 0 do report.positive_blocks += 1
		if block.regression do report.regressing_blocks += 1
		append(&report.blocks, block)
		combat_ai_evaluation_add(&report.baseline, baseline)
		combat_ai_evaluation_add(&report.candidate, candidate)
		report.total_runs = report.baseline.runs
		report.verdict = "running"
		fmt.printf(
			"trial block %d/%d seed=%d score=%+.2f/run wins=%+.1f%% losses=%+.2f/run regression=%v\n",
			block_index + 1,
			block_count,
			block_seed,
			block.score_delta_per_run,
			block.win_rate_delta * 100,
			block.loss_delta_per_run,
			block.regression,
		)
		if !combat_ai_trial_report_write(report_path, &report) {
			fmt.eprintf("could not write partial trial report %s\n", report_path)
			return false
		}
	}
	report.total_runs = report.baseline.runs
	report.score_delta_per_run =
		(report.candidate.score - report.baseline.score) / f64(report.total_runs)
	report.win_rate_delta =
		f64(report.candidate.wins - report.baseline.wins) / f64(report.total_runs)
	report.preservation_delta_per_run =
		combat_ai_rate(report.candidate.preserved, report.candidate.friendly_total) -
		combat_ai_rate(report.baseline.preserved, report.baseline.friendly_total)
	report.loss_delta_per_run =
		combat_ai_rate(report.candidate.player_losses, report.candidate.friendly_total) -
		combat_ai_rate(report.baseline.player_losses, report.baseline.friendly_total)
	baseline_win_rate := f64(report.baseline.wins) / f64(report.total_runs)
	candidate_win_rate := f64(report.candidate.wins) / f64(report.total_runs)
	standard_error := math.sqrt(
		baseline_win_rate * (1 - baseline_win_rate) / f64(report.total_runs) +
		candidate_win_rate * (1 - candidate_win_rate) / f64(report.total_runs),
	)
	report.win_rate_delta_ci95_low = report.win_rate_delta - 1.96 * standard_error
	report.win_rate_delta_ci95_high = report.win_rate_delta + 1.96 * standard_error
	replay_runs := game.COMBAT_AI_CURRICULUM_RUNS
	first_replay := combat_ai_evaluate_parallel(
		checkpoint.champion,
		holdout_seed,
		replay_runs,
		workers,
	)
	second_replay := combat_ai_evaluate_parallel(
		checkpoint.champion,
		holdout_seed,
		replay_runs,
		workers,
	)
	report.deterministic = combat_ai_evaluation_equal(first_replay, second_replay)
	score_gate := report.score_delta_per_run >= 25
	win_gate := report.candidate.wins >= report.baseline.wins
	balanced_gate, balanced_reason := combat_ai_promotion_gate(report.baseline, report.candidate)
	resilience_gate :=
		report.loss_delta_per_run <= .05 &&
		report.preservation_delta_per_run >= -.05 &&
		report.regressing_blocks == 0 &&
		report.positive_blocks > block_count / 2
	report.promotion_recommended =
		report.deterministic && score_gate && win_gate && balanced_gate && resilience_gate
	if report.promotion_recommended {
		report.verdict = "promote"
	} else if !report.deterministic {
		report.verdict = "reject: nondeterministic replay"
	} else if !score_gate || !win_gate {
		report.verdict = "reject: improvement not demonstrated"
	} else if !balanced_gate {
		report.verdict = fmt.tprintf("reject: %s", balanced_reason)
	} else {
		report.verdict = "reject: holdout regression"
	}
	fmt.printf(
		"trial verdict=%s score=%+.2f/run wins=%+.1f%% CI95=[%+.1f%%,%+.1f%%] preserved=%+.2f/run losses=%+.2f/run blocks=%d/%d positive regressions=%d deterministic=%v\n",
		report.verdict,
		report.score_delta_per_run,
		report.win_rate_delta * 100,
		report.win_rate_delta_ci95_low * 100,
		report.win_rate_delta_ci95_high * 100,
		report.preservation_delta_per_run,
		report.loss_delta_per_run,
		report.positive_blocks,
		report.block_count,
		report.regressing_blocks,
		report.deterministic,
	)
	if !combat_ai_trial_report_write(report_path, &report) {
		fmt.eprintf("could not write trial report %s\n", report_path)
		return false
	}
	fmt.printf("wrote trial report to %s\n", report_path)
	return true
}
