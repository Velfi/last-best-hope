package main

import game "../packages/game"
import "core:os"
import jobs "zelda_engine:jobs"

COMBAT_AI_MAX_WORKERS :: 64

Combat_AI_Evaluation_Jobs :: struct {
	parameters: game.Combat_AI_Parameters,
	seed_base: u64,
	sample_offset: int,
	results: []game.Combat_AI_Evaluation,
}

combat_ai_default_workers :: proc() -> int {
	return clamp(os.get_processor_core_count(), 1, 8)
}

combat_ai_evaluation_worker :: proc(index: int, data: rawptr) {
	work := cast(^Combat_AI_Evaluation_Jobs)data
	work.results[index] =
		game.combat_ai_evaluate_curriculum_sample(
			work.parameters,
			work.seed_base,
			work.sample_offset + index,
		)
}

combat_ai_evaluate_parallel :: proc(
	parameters: game.Combat_AI_Parameters,
	seed_base: u64,
	runs, worker_count: int,
	sample_offset: int = 0,
) -> game.Combat_AI_Evaluation {
	if runs <= 0 do return {}
	workers := clamp(worker_count, 1, min(runs, COMBAT_AI_MAX_WORKERS))
	results := make([]game.Combat_AI_Evaluation, runs)
	defer delete(results)
	work := Combat_AI_Evaluation_Jobs {
		parameters = parameters,
		seed_base = seed_base,
		sample_offset = sample_offset,
		results = results,
	}
	jobs.run_indexed(runs, workers, combat_ai_evaluation_worker, &work)
	result: game.Combat_AI_Evaluation
	for evaluation in results do game.combat_ai_evaluation_merge(&result, evaluation)
	return result
}
