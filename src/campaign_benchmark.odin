package main

import game "../packages/game"
import "core:fmt"
import "core:time"

CAMPAIGN_BENCHMARK_MAX_RUNS :: 10000
CAMPAIGN_BENCHMARK_P95_BUDGET_MS :: 250.0
CAMPAIGN_BENCHMARK_RELATIVE_TOLERANCE_PERCENT :: 5.0

campaign_benchmark_sort :: proc(values: []f64) {
	for i in 1 ..< len(values) {
		value := values[i]; j := i
		for j > 0 && values[j - 1] > value {values[j] = values[j - 1]; j -= 1}
		values[j] = value
	}
}

campaign_benchmark_percentile :: proc(values: []f64, numerator: int) -> f64 {
	index := clamp((len(values) * numerator + 99) / 100 - 1, 0, len(values) - 1)
	return values[index]
}

run_campaign_benchmark :: proc(
	runs: int,
	profile: Bot_Profile,
	tempo: game.Story_Tempo,
	seed_base: u64,
	horizon: i32,
	warmup: int,
	repetitions: int,
) {
	run_count := clamp(runs, 1, CAMPAIGN_BENCHMARK_MAX_RUNS)
	warmup_count := clamp(warmup, 0, 100)
	repetition_count := clamp(repetitions, 1, 20)
	season_count := clamp(horizon, i32(1), i32(MAX_SOAK_SEASONS))

	for sample in 0 ..< warmup_count {
		seed := seed_base + u64(sample)
		_ = bot_run(
			{
				profile = profile,
				game_seed = seed,
				bot_seed = seed ~ 0x517cc1b727220a95,
				length = .Open,
				max_actions = 64,
				horizon = season_count,
				tempo = tempo,
			},
		)
	}

	values: [CAMPAIGN_BENCHMARK_MAX_RUNS]f64
	repetition_totals: [20]f64
	phase_totals: Bot_Run_Timings
	checksum: u64
	for repetition in 0 ..< repetition_count {
		repetition_started := time.tick_now()
		for sample in 0 ..< run_count {
			seed := seed_base + u64(sample)
			started := time.tick_now()
			result := bot_run(
				{
					profile = profile,
					game_seed = seed,
					bot_seed = seed ~ 0x517cc1b727220a95,
					length = .Open,
					max_actions = 64,
					horizon = season_count,
					tempo = tempo,
					measure_phases = true,
				},
			)
			values[sample] = time.duration_seconds(time.tick_since(started)) * 1000
			phase_totals.initialization_ms += result.timings.initialization_ms
			phase_totals.policy_ms += result.timings.policy_ms
			phase_totals.passage_ms += result.timings.passage_ms
			phase_totals.advance_ms += result.timings.advance_ms
			phase_totals.telemetry_ms += result.timings.telemetry_ms
			phase_totals.finalize_ms += result.timings.finalize_ms
			phase_totals.passage_begin_ms += result.timings.passage_begin_ms
			phase_totals.passage_dark_ms += result.timings.passage_dark_ms
			phase_totals.passage_normal_ms += result.timings.passage_normal_ms
			phase_totals.passage_conclude_ms += result.timings.passage_conclude_ms
			phase_totals.passage_course_planning_ms += result.timings.passage_course_planning_ms
			phase_totals.passage_dark_tick_ms += result.timings.passage_dark_tick_ms
			checksum ~= result.state_signature + result.final_rng_sequence + u64(result.seasons)
		}
		repetition_totals[repetition] =
			time.duration_seconds(time.tick_since(repetition_started)) * 1000
		campaign_benchmark_sort(values[:run_count])
		fmt.eprintf(
			"CAMPAIGN BENCHMARK progress repetition:%d/%d total-ms:%.3f\n",
			repetition + 1,
			repetition_count,
			repetition_totals[repetition],
		)
	}
	campaign_benchmark_sort(repetition_totals[:repetition_count])
	campaign_benchmark_sort(values[:run_count])
	total_campaigns := run_count * repetition_count
	phase_scale := 1.0 / f64(total_campaigns)
	median_total := repetition_totals[repetition_count / 2]
	throughput := f64(run_count) / (median_total / 1000)
	p95 := campaign_benchmark_percentile(values[:run_count], 95)
	fmt.printf(
		"{{\"scenario\":\"campaign-run\",\"profile\":\"%s\",\"tempo\":\"%s\",\"seed_base\":%d,\"horizon_seasons\":%d,\"warmup\":%d,\"runs_per_repetition\":%d,\"repetitions\":%d,",
		bot_profile_name(profile),
		story_tempo_name(tempo),
		seed_base,
		season_count,
		warmup_count,
		run_count,
		repetition_count,
	)
	fmt.printf(
		"\"campaign_last_repetition_ms\":{{\"median\":%.4f,\"p95\":%.4f,\"p99\":%.4f,\"max\":%.4f},",
		values[run_count / 2],
		p95,
		campaign_benchmark_percentile(values[:run_count], 99),
		values[run_count - 1],
	)
	fmt.printf(
		"\"repetition_total_ms\":{{\"median\":%.4f,\"max\":%.4f},\"campaigns_per_second\":%.3f,",
		median_total,
		repetition_totals[repetition_count - 1],
		throughput,
	)
	fmt.printf(
		"\"phase_mean_ms\":{{\"initialization\":%.4f,\"policy\":%.4f,\"passage\":%.4f,\"advance\":%.4f,\"telemetry\":%.4f,\"finalize\":%.4f},",
		phase_totals.initialization_ms * phase_scale,
		phase_totals.policy_ms * phase_scale,
		phase_totals.passage_ms * phase_scale,
		phase_totals.advance_ms * phase_scale,
		phase_totals.telemetry_ms * phase_scale,
		phase_totals.finalize_ms * phase_scale,
	)
	fmt.printf(
		"\"passage_phase_mean_ms\":{{\"begin\":%.4f,\"dark_navigation\":%.4f,\"normal_navigation\":%.4f,\"conclude\":%.4f},",
		phase_totals.passage_begin_ms * phase_scale,
		phase_totals.passage_dark_ms * phase_scale,
		phase_totals.passage_normal_ms * phase_scale,
		phase_totals.passage_conclude_ms * phase_scale,
	)
	fmt.printf(
		"\"dark_navigation_mean_ms\":{{\"course_planning\":%.4f,\"fixed_ticks\":%.4f},",
		phase_totals.passage_course_planning_ms * phase_scale,
		phase_totals.passage_dark_tick_ms * phase_scale,
	)
	fmt.printf(
		"\"p95_budget_ms\":%.1f,\"p95_budget_pass\":%v,\"relative_tolerance_percent\":%.1f,\"checksum\":%d}\n",
		CAMPAIGN_BENCHMARK_P95_BUDGET_MS,
		p95 <= CAMPAIGN_BENCHMARK_P95_BUDGET_MS,
		CAMPAIGN_BENCHMARK_RELATIVE_TOLERANCE_PERCENT,
		checksum,
	)
}
