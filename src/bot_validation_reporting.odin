package main

import game "../packages/game"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:testing"
run_release_validation :: proc(total_runs: int, seed_base: u64, production: bool = true) -> bool {
	requested :=
		production ? max(total_runs, 10000) : max(total_runs, 20); per_cell := (requested + 14) / 15; actual := per_cell * 15
	progress_interval := max(actual / 50, 1)
	cells: [5][3]Validation_Cell; signatures: [5][64]u64; signature_counts: [5]int
	for profile in Bot_Profile do for tempo in game.Story_Tempo do for sample in 0 ..< per_cell {
		seed := seed_base + u64(sample); r := bot_run({profile = profile, game_seed = seed, bot_seed = seed * 0x9e3779b97f4a7c15 ~ (u64(profile) + 1), length = .Standard, max_actions = 64, horizon = 24, tempo = tempo}); cell := &cells[int(profile)][int(tempo)]; cell.runs += 1
		cell.ending_counts[int(r.ending)] += 1
		cell.outcome_counts[int(r.ending) * 4 + int(r.ending_quality)] += 1
		cell.passages += i64(r.passages); cell.objectives += i64(r.objectives); cell.settlements += i64(r.settlements); cell.active_ships += i64(r.final_active_ships); cell.broken_promises += i64(r.final_broken_promises); cell.pending_claims += i64(r.final_pending_claims); cell.hazards += i64(r.final_hazards)
		cell.committed_supplies += r.fleet_committed.supplies; cell.recovered_supplies += r.fleet_recovered.supplies; cell.rewarded_supplies += r.fleet_rewarded.supplies; cell.passage_net_supplies += i64(r.passage_net_supplies); cell.recovery_projects += i64(r.maintenance_recovery_projects)
		cell.planner_candidates += r.planner_candidates; cell.planner_margin += r.planner_score_margin_total; cell.planner_no_positive += i64(r.planner_no_positive_seasons); for count, i in r.planner_action_choices do cell.planner_actions[i] += i64(count)
		if bot_is_win(r.ending, r.ending_quality) do cell.wins += 1; if r.qualifying_fronts >= 2 do cell.front_gate += 1; if r.region_revisit_mutated do cell.revisit_gate += 1; cell.invalid += i64(r.invalid_actions); if r.first_saturated_collection != "" do cell.saturated += 1; cell.stacking += i64(r.tempo_stack_violations); if r.ships_damaged > 0 || r.ships_scarred > 0 || r.emergency_events > 0 do cell.setbacks += 1; if r.ships_scarred > 0 do cell.scars += 1; if r.ships_lost > 0 do cell.ship_loss += 1; if r.emergency_events > 0 do cell.emergencies += 1
		for t in r.telemetry[:r.telemetry_count] {cell.total_seasons += 1; if t.major_beats == 0 do cell.quiet_seasons += 1}
		if r.dominant_action_rate > .7 {cell.dominant_over_70 += 1; cell.max_dominant_rate = max(cell.max_dominant_rate, r.dominant_action_rate)}
		if r.low_sample_lockin_rate > .7 do cell.low_sample_lockin += 1
		known := false; for value in signatures[int(profile)][:signature_counts[int(profile)]] do if value == r.state_signature do known = true; if !known && signature_counts[int(profile)] < len(signatures[int(profile)]) {signatures[int(profile)][signature_counts[int(profile)]] = r.state_signature; signature_counts[int(profile)] += 1}
		if sample == per_cell - 1 do fmt.eprintf("BALANCE progress profile:%s tempo:%s runs:%d\n", bot_profile_name(profile), story_tempo_name(tempo), cell.runs)
		completed := (int(profile) * 3 + int(tempo)) * per_cell + sample + 1; if completed % progress_interval == 0 || completed == actual {fmt.print("{"); fmt.printf("\"type\":\"validation_progress\",\"completed\":%d,\"total\":%d,\"percent\":%.1f,\"profile\":\"%s\",\"tempo\":\"%s\"}\n", completed, actual, f64(completed) * 100 / f64(actual), bot_profile_name(profile), story_tempo_name(tempo))}
	}
	fmt.println("{\"type\":\"validation_progress\",\"phase\":\"event-preservation\"}")
	preserved :=
		true; for profile in Bot_Profile do for tempo in game.Story_Tempo {seed := seed_base + 0x100000 + u64(profile) * 17 + u64(tempo); r := bot_run({profile = profile, game_seed = seed, bot_seed = seed ~ 0x517cc1b727220a95, length = .Open, max_actions = 64, horizon = 100, tempo = tempo}); if !r.preserved_over_512 || r.invalid_actions > 0 || r.first_saturated_collection != "" do preserved = false}
	profile_win_gate :=
		true; tempo_win_gate := true; state_gate := true; front_gate := true; revisit_gate := true; tempo_gate := true; clean_gate := true; total_wins, total_campaigns, total_setbacks, total_scars, total_losses, total_emergencies: i64; all_outcomes: [28]i64; profile_outcomes: [5][28]i64
	for profile in Bot_Profile {wins, runs: i64; for tempo in game.Story_Tempo {cell := cells[int(profile)][int(tempo)]; wins += cell.wins; runs += cell.runs; rate := f64(cell.wins) * 100 / f64(cell.runs); if tempo == .Measured && (rate < 70 || rate > 80) do tempo_win_gate = false; if tempo == .Spacious && (rate < 85 || rate > 94) do tempo_win_gate = false; if tempo == .Volatile && (rate < 20 || rate > 60) do tempo_win_gate = false; if f64(cell.front_gate) / f64(cell.runs) < .8 do front_gate = false; if cell.revisit_gate == 0 do revisit_gate = false; if tempo != .Volatile && cell.stacking > 0 do tempo_gate = false; if cell.invalid > 0 || cell.saturated > 0 do clean_gate = false}; if f64(wins) / f64(runs) >= .95 do profile_win_gate = false; if signature_counts[int(profile)] < 3 do state_gate = false}
	for profile in Bot_Profile do for tempo in game.Story_Tempo {cell := cells[int(profile)][int(tempo)]; total_wins += cell.wins; total_campaigns += cell.runs; total_setbacks += cell.setbacks; total_scars += cell.scars; total_losses += cell.ship_loss; total_emergencies += cell.emergencies; for count, i in cell.outcome_counts {all_outcomes[i] += count; profile_outcomes[int(profile)][i] += count}}
	rate_ok :=
		percent(total_wins, total_campaigns) >= EXPERIENCED_WIN_RATE_LOW &&
		percent(total_wins, total_campaigns) <=
			EXPERIENCED_WIN_RATE_HIGH; setback_ok := percent(total_setbacks, total_campaigns) >= MEANINGFUL_SETBACK_RATE_LOW && percent(total_setbacks, total_campaigns) <= MEANINGFUL_SETBACK_RATE_HIGH; scar_ok := percent(total_scars, total_campaigns) >= SCAR_CAMPAIGN_RATE_LOW && percent(total_scars, total_campaigns) <= SCAR_CAMPAIGN_RATE_HIGH; loss_ok := percent(total_losses, total_campaigns) >= SHIP_LOSS_CAMPAIGN_RATE_LOW && percent(total_losses, total_campaigns) <= SHIP_LOSS_CAMPAIGN_RATE_HIGH; emergency_ok := percent(total_emergencies, total_campaigns) >= EMERGENCY_CAMPAIGN_RATE_LOW && percent(total_emergencies, total_campaigns) <= EMERGENCY_CAMPAIGN_RATE_HIGH
	ending_kinds := 0; ending_peak: i64; for count, i in all_outcomes {ending := i / 4; quality := i % 4; if ending > 0 && ending < int(game.Ending.Fragmented_Survival) && quality > 0 && count > 0 do ending_kinds += 1; if i > 0 do ending_peak = max(ending_peak, count)}; ending_ok := ending_kinds >= 4 && percent(ending_peak, total_campaigns) <= 55; profile_diversity := true; for profile in Bot_Profile {kinds := 0; for count, i in profile_outcomes[int(profile)] do if i / 4 > 0 && i % 4 > 0 && count > 0 do kinds += 1; if kinds < 2 do profile_diversity = false}
	passed :=
		tempo_win_gate &&
		setback_ok &&
		scar_ok &&
		loss_ok &&
		emergency_ok &&
		ending_ok &&
		profile_diversity &&
		profile_win_gate &&
		state_gate &&
		front_gate &&
		revisit_gate &&
		preserved &&
		tempo_gate &&
		clean_gate
	fmt.print(
		"{",
	); fmt.printf("\"type\":\"%s\",\"requested_runs\":%d,\"matched_runs\":%d,\"seed_base\":%d,\"passed\":%v,\"win_rate\":%.4f,\"setback_rate\":%.4f,\"scar_rate\":%.4f,\"loss_rate\":%.4f,\"emergency_rate\":%.4f,\"gates\":", production ? "release_validation" : "balance_sample", requested, actual, seed_base, passed, percent(total_wins, total_campaigns) / 100, percent(total_setbacks, total_campaigns) / 100, percent(total_scars, total_campaigns) / 100, percent(total_losses, total_campaigns) / 100, percent(total_emergencies, total_campaigns) / 100); fmt.print("{"); fmt.printf("\"tempo_win_targets\":%v,\"overall_win_70_80_diagnostic\":%v,\"setbacks_35_55\":%v,\"scars_15_30\":%v,\"losses_3_10\":%v,\"emergencies_15_30\":%v,\"ending_diversity\":%v,\"profile_ending_diversity\":%v,\"profile_win_below_95\":%v,\"three_states_by_24\":%v,\"fronts_80pct\":%v,\"region_revisit_mutation\":%v,\"event_preservation_over_512\":%v,\"tempo_no_stacking\":%v,\"no_invalid_or_saturation\":%v", tempo_win_gate, rate_ok, setback_ok, scar_ok, loss_ok, emergency_ok, ending_ok, profile_diversity, profile_win_gate, state_gate, front_gate, revisit_gate, preserved, tempo_gate, clean_gate); fmt.println("}}")
	for profile in Bot_Profile do for tempo in game.Story_Tempo {c := cells[int(profile)][int(tempo)]; fmt.print("{"); fmt.printf("\"type\":\"cell\",\"profile\":\"%s\",\"tempo\":\"%s\",\"runs\":%d,\"win_rate\":%.4f,\"distinct_profile_states\":%d,\"front_gate_rate\":%.4f,\"revisit_rate\":%.4f,\"setback_rate\":%.4f,\"ship_loss_rate\":%.4f,\"emergency_rate\":%.4f,\"quiet_share\":%.4f,\"invalid_actions\":%d,\"saturated_runs\":%d,\"stacking_violations\":%d,\"dominant_over_70_runs\":%d,\"low_sample_lockin_runs\":%d,\"max_dominant_rate\":%.4f,\"avg_passages\":%.2f,\"avg_objectives\":%.2f,\"avg_settlements\":%.2f,\"avg_active_ships\":%.2f,\"avg_broken_promises\":%.2f,\"avg_pending_claims\":%.2f,\"avg_hazards\":%.2f,\"passage_committed_supplies\":%d,\"passage_recovered_supplies\":%d,\"passage_rewarded_supplies\":%d,\"passage_net_supplies\":%d,\"maintenance_recovery_projects\":%d,\"endings\":[", bot_profile_name(profile), story_tempo_name(tempo), c.runs, f64(c.wins) / f64(c.runs), signature_counts[int(profile)], f64(c.front_gate) / f64(c.runs), f64(c.revisit_gate) / f64(c.runs), f64(c.setbacks) / f64(c.runs), f64(c.ship_loss) / f64(c.runs), f64(c.emergencies) / f64(c.runs), f64(c.quiet_seasons) / f64(max(c.total_seasons, 1)), c.invalid, c.saturated, c.stacking, c.dominant_over_70, c.low_sample_lockin, c.max_dominant_rate, f64(c.passages) / f64(c.runs), f64(c.objectives) / f64(c.runs), f64(c.settlements) / f64(c.runs), f64(c.active_ships) / f64(c.runs), f64(c.broken_promises) / f64(c.runs), f64(c.pending_claims) / f64(c.runs), f64(c.hazards) / f64(c.runs), c.committed_supplies, c.recovered_supplies, c.rewarded_supplies, c.passage_net_supplies, c.recovery_projects); for count, i in c.ending_counts {if i > 0 do fmt.print(","); fmt.print(count)}; fmt.println("]}")}
	for profile in Bot_Profile do for tempo in game.Story_Tempo {c := cells[int(profile)][int(tempo)]; actions: i64; for count in c.planner_actions do actions += count; fmt.print("{"); fmt.printf("\"type\":\"planner_cell\",\"profile\":\"%s\",\"tempo\":\"%s\",\"candidates\":%d,\"actions\":%d,\"avg_margin\":%.3f,\"no_positive_seasons\":%d,\"families\":[%d,%d,%d,%d,%d]}\n", bot_profile_name(profile), story_tempo_name(tempo), c.planner_candidates, actions, f64(c.planner_margin) / f64(max(actions, 1)), c.planner_no_positive, c.planner_actions[0], c.planner_actions[1], c.planner_actions[2], c.planner_actions[3], c.planner_actions[4])}
	return passed
}

run_long_horizon_validation :: proc(samples: int, seed_base: u64, only_years: i32 = 0) -> bool {
	horizons := [3]i32{100, 300, 1000}; passed := true; applicable, regional_success: i64
	for years in horizons {if only_years > 0 && years != only_years do continue; for profile in Bot_Profile do for tempo in game.Story_Tempo do for sample in 0 ..< max(samples, 1) {
			seed := seed_base + u64(sample) + u64(years) * 1009 + u64(profile) * 31 + u64(tempo) * 7
			seasons := soak_seasons_for_years(years)
			r := bot_run({profile = profile, game_seed = seed, bot_seed = seed ~ 0x517cc1b727220a95, length = .Open, max_actions = 64, horizon = seasons, tempo = tempo})
			clean := r.seasons == seasons && r.invalid_actions == 0 && r.first_saturated_collection == "" && r.dangling_causal_references == 0 && r.duplicate_settlement_identities == 0 && r.economic_flow_mismatches == 0 && r.overdue_essential_exposures == 0 && r.knowledge_bounded_or_explained && r.integer_bounds_clean
			if years == 1000 && r.settlements >= 2 {applicable += 1; if r.productive_regions >= 2 && r.changed_trade_dependencies >= 1 do regional_success += 1}
			if !clean do passed = false
			fmt.printf("LONG years:%d seasons:%d profile:%s tempo:%s sample:%d seed:%d replay:%d/%d clean:%v ending:%s invalid:%d saturation:%s dangling:%d duplicate:%d flow:%d bounds:%v overdue-essential:%d knowledge-backed:%v productive-regions:%d changed-trade:%d\n", years, seasons, bot_profile_name(profile), story_tempo_name(tempo), sample, seed, r.game_seed, r.bot_seed, clean, game.ending_name(r.ending), r.invalid_actions, r.first_saturated_collection == "" ? "none" : r.first_saturated_collection, r.dangling_causal_references, r.duplicate_settlement_identities, r.economic_flow_mismatches, r.integer_bounds_clean, r.overdue_essential_exposures, r.knowledge_bounded_or_explained, r.productive_regions, r.changed_trade_dependencies)
		}}
	regional_gate :=
		applicable > 0 &&
		f64(regional_success) / f64(applicable) >=
			.8; if !regional_gate do passed = false; fmt.printf("LONG regional-gate applicable:%d success:%d rate:%.2f%% pass:%v\n", applicable, regional_success, applicable > 0 ? f64(regional_success) * 100 / f64(applicable) : 0, regional_gate)
	return passed
}

run_action_dominance_investigation :: proc(
	samples_per_cell: int,
	seed_base: u64,
	horizon: i32 = 100,
) -> bool {
	summary: Bot_Summary; samples := max(samples_per_cell, 1)
	for profile in Bot_Profile do for tempo in game.Story_Tempo do for sample in 0 ..< samples {
		seed := seed_base + u64(sample) + u64(profile) * 100003 + u64(tempo) * 1009
		r := bot_run({profile = profile, game_seed = seed, bot_seed = seed ~ 0x517cc1b727220a95, length = .Open, max_actions = 64, horizon = horizon, tempo = tempo}); summary_add(&summary, &r)
	}
	passed :=
		true; fmt.printf("ACTION INVESTIGATION matched-runs:%d samples-per-cell:%d horizon:%d-seasons/%d-years seed-base:%d\n", summary.runs, samples, horizon, soak_years_for_seasons(horizon), seed_base)
	for kind in game.Situation_Kind {k := int(kind); total := summary.action_opportunities[k]; if total <= 0 do continue; best: i64; best_index := -1; for count, i in summary.action_choices[k] do if count > best {best = count; best_index = i}; rate := percent(best, total); if rate > 70 do passed = false; fmt.printf("  kind:%v affordable-opportunities:%d dominant-choice:%d rate:%.2f%% result:%s\n", kind, total, best_index, rate, rate > 70 ? "INVESTIGATE" : "PASS")}
	return passed
}

@(test)
bot_run_is_reproducible :: proc(t: ^testing.T) {
	config := Bot_Run_Config {
		profile     = .Strategist,
		game_seed   = 77,
		bot_seed    = 991,
		length      = .Short,
		max_actions = 64,
	}
	a := bot_run(config)
	b := bot_run(config)
	testing.expect_value(t, a, b)
}

// Regression: the CLI-equivalent Strategist campaign for this seed currently
// fails to reach an ending. Keep the exact seed and bot stream so a repair
// must prove that the campaign completes rather than only avoiding a crash.
@(test)
strategist_seed_30001_reaches_an_ending :: proc(t: ^testing.T) {
	r := bot_run(
		{
			profile     = .Strategist,
			game_seed   = 30001,
			bot_seed    = 11763423866481236228,
			length      = .Standard,
			max_actions = 64,
		},
	)
	testing.expectf(
		t,
		r.ending != .In_Progress,
		"seed 30001 did not reach an ending; failure=%v blocker=%s",
		r.first_failure_kind,
		r.first_failure_blocker,
	)
}

@(test)
player_story_bots_finish_without_invalid_actions :: proc(t: ^testing.T) {
	for profile in Bot_Profile {
		for seed in u64(1) ..= u64(12) {
			result := bot_run(
				{
					profile = profile,
					game_seed = seed,
					bot_seed = seed * 101 + u64(profile),
					length = .Short,
					max_actions = 64,
				},
			)
			testing.expect_value(t, result.seasons, game.chronicle_length_seasons(.Short) + 3)
			testing.expect(t, result.passages <= result.seasons)
			testing.expectf(
				t,
				result.invalid_actions == 0,
				"profile=%v seed=%d failure=%v blocker=%s compact=%v passage=%v",
				profile,
				seed,
				result.first_failure_kind,
				result.first_failure_blocker,
				result.first_failure_family,
				result.first_failure_passage_phase,
			)
			testing.expect(t, result.ending != .In_Progress)
		}
	}
}

@(test)
compact_bot_completes_all_operation_routes_without_stalling :: proc(t: ^testing.T) {
	for seed in u64(1) ..= u64(5) {
		result := bot_run({
			profile = .Strategist,
			game_seed = seed,
			bot_seed = seed * 101 + 3,
			length = .Short,
			max_actions = 64,
		})
		testing.expectf(
			t,
			result.invalid_actions == 0,
			"seed=%d failure=%v blocker=%s phase=%v seasons=%d",
			seed,
			result.first_failure_kind,
			result.first_failure_blocker,
			result.first_failure_passage_phase,
			result.seasons,
		)
	}
}

@(test)
profiles_choose_distinct_dark_objectives_and_public_responses :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(41); defer game.campaign_destroy_heap(c)
	testing.expect_value(
		t,
		bot_objective(c, .Strategist),
		game.Dark_Contract_Purpose.Map_Unknown_Door,
	)
	testing.expect_value(t, bot_objective(c, .Steward), game.Dark_Contract_Purpose.Stabilize_Relay)
	testing.expect_value(
		t,
		bot_objective(c, .Explorer),
		game.Dark_Contract_Purpose.Ecological_Survey,
	)
	c.season = 1; testing.expect_value(t, bot_objective(c, .Explorer), game.Dark_Contract_Purpose.Map_Unknown_Door); c.season = 0
	testing.expect_value(
		t,
		bot_objective(c, .Risk_Manager),
		game.Dark_Contract_Purpose.Verify_Correspondence,
	)
	testing.expect_value(
		t,
		bot_objective(c, .World_Builder),
		game.Dark_Contract_Purpose.Map_Unknown_Door,
	)
	c.current_situation = {
		kind         = .Settlement,
		choice_count = 4,
	}
	testing.expect_value(t, bot_interaction_choice(c, .Explorer), 2)
	testing.expect_value(t, bot_interaction_choice(c, .Steward), 0)
}

@(test)
player_story_weights_create_distinct_behavior :: proc(t: ^testing.T) {
	steward, risk, world :=
		bot_weights(.Steward), bot_weights(.Risk_Manager), bot_weights(.World_Builder)
	testing.expect(t, steward.rescue > risk.rescue)
	testing.expect(t, world.settlement > risk.settlement)
	// Verify those authored differences survive into an actual decision path;
	// rare astronomical outcomes are deliberately not used as a style oracle.
	c := game.new_campaign_seeded_heap(
		9912,
	); defer game.campaign_destroy_heap(c); c.material_economy.essential[0].exposed = true; memory: Bot_Strategy_Memory
	testing.expect_value(
		t,
		bot_marginal_choice(c, .Risk_Manager, &memory),
		Bot_Marginal_Choice.Trade,
	)
	testing.expect(
		t,
		bot_marginal_choice(c, .World_Builder, &memory) !=
		bot_marginal_choice(c, .Risk_Manager, &memory),
	)
}

@(test)
experienced_strategy_tracks_passage_completion_target :: proc(t: ^testing.T) {
	completed: i64; passages: i64; triumphs, successes, partials, disasters, lost: i64
	// Keep routine tests representative but fast. Distribution confidence belongs
	// to the dedicated validation matrix, not every `make test` invocation.
	for seed in u64(1) ..= u64(20) {result := bot_run({profile = .Strategist, game_seed = seed, bot_seed = seed * 31337, length = .Short, max_actions = 64}); completed += i64(result.objectives); passages += i64(result.passages); triumphs += i64(result.triumphs); successes += i64(result.successes); partials += i64(result.partials); disasters += i64(result.disasters); lost += i64(result.lost_passages)}
	rate := f64(completed) / f64(passages)
	fmt.printf(
		"strategist passage completion-rate: %.3f (%d/%d), outcomes %d/%d/%d/%d/%d\n",
		rate,
		completed,
		passages,
		triumphs,
		successes,
		partials,
		disasters,
		lost,
	)
	// Compact-authorized operations count every accepted undertaking, including
	// recoverable withdrawals and incomplete contracts. The matched 20-seed
	// baseline is 0.553; keep this passage-level signal separate from the 75%
	// experienced-player campaign-win target.
	testing.expect(t, rate >= 0.50 && rate <= 0.60)
}

@(test)
too_few_ships_skips_commission_without_an_invalid_action :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(
		41,
	); defer game.campaign_destroy_heap(c); for i in 2 ..< game.MAX_SHIPS do c.ships[i].active = false
	config := Bot_Run_Config {
		profile     = .Risk_Manager,
		game_seed   = 41,
		bot_seed    = 7,
		length      = .Short,
		max_actions = 64,
	}; rng := Bot_Rng{7}; result: Bot_Run_Result; bot_play_passage(c, &config, &rng, &result)
	testing.expect_value(
		t,
		result.invalid_actions,
		i32(0),
	); testing.expect_value(t, result.passages, i32(0))
}

@(test)
soak_regressions_are_deterministic_at_24_50_and_100_seasons :: proc(t: ^testing.T) {
	horizons := [3]i32{24, 50, 100}; for horizon in horizons {config := Bot_Run_Config {
			profile     = .Risk_Manager,
			game_seed   = u64(horizon),
			bot_seed    = 9001,
			length      = .Open,
			max_actions = 64,
			horizon     = horizon,
			tempo       = .Measured,
		}; a := bot_run(
			config,
		); b := bot_run(config); testing.expect_value(t, a, b); testing.expect_value(t, a.seasons, horizon + 3); testing.expect_value(t, a.invalid_actions, i32(0)); testing.expect_value(t, a.first_saturated_collection, "")}
}

@(test)
year_horizons_convert_to_three_year_seasons_and_preserve_replay :: proc(t: ^testing.T) {
	years := [3]i32{100, 300, 1000}; expected := [3]i32{34, 100, 334}
	for value, i in years {seasons := soak_seasons_for_years(value); testing.expect_value(t, seasons, expected[i]); config := Bot_Run_Config {
			profile     = .Strategist,
			game_seed   = u64(value),
			bot_seed    = 0x9001,
			length      = .Open,
			max_actions = 64,
			horizon     = seasons,
			tempo       = .Measured,
		}; a := bot_run(
			config,
		); b := bot_run(config); testing.expect_value(t, a, b); testing.expect(t, a.seasons > 0 && a.seasons <= seasons + 3); testing.expect_value(t, a.invalid_actions, i32(0))}
}

@(test)
adaptive_settlement_choice_changes_with_route_and_prior_outcomes :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(44); defer game.campaign_destroy_heap(c); c.current_situation = {
		kind         = .Settlement,
		choice_count = 4,
	}; c.current_situation.choices[0] = {
		effect = .Found_Settlement,
	}; c.current_situation.choices[1] = {
		effect = .Amend_Settlement,
	}; c.current_situation.choices[2] = {
		effect = .Delay,
	}; c.current_situation.choices[3] = {
		effect = .Decline,
	}; c.settlement_proposal.charter_participation =
		true; c.settlement_proposal.disclose_evidence = true
	memory: Bot_Strategy_Memory
	first := bot_adaptive_interaction_choice(
		c,
		.Strategist,
		&memory,
	); c.hazard_count = 3; memory.settlement_demands = 2
	second := bot_adaptive_interaction_choice(
		c,
		.Strategist,
		&memory,
	); testing.expect_value(t, c.current_situation.choices[first].effect, game.Situation_Choice_Effect.Found_Settlement); testing.expect(t, first != second); testing.expect(t, c.current_situation.choices[second].effect == .Amend_Settlement || c.current_situation.choices[second].effect == .Delay)
}

@(test)
marginal_policy_compares_repairs_with_structural_alternatives :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(
		144,
	); defer game.campaign_destroy_heap(c); memory: Bot_Strategy_Memory; c.ships[0].damage = 2
	testing.expect_value(
		t,
		bot_marginal_choice(c, .Strategist, &memory),
		Bot_Marginal_Choice.Repair,
	)
	c.material_economy.food_shortage_response_pending = true
	testing.expect_value(
		t,
		bot_marginal_choice(c, .Strategist, &memory),
		Bot_Marginal_Choice.Productive_Investment,
	)
	c.material_economy.food_shortage_response_pending =
		false; ag := game.ship_index(c, 8); c.ships[ag].active = false; c.ships[ag].departure = .Lost
	testing.expect_value(
		t,
		bot_marginal_choice(c, .Strategist, &memory),
		Bot_Marginal_Choice.Replacement,
	)
	testing.expect_value(
		t,
		bot_marginal_choice(c, .Risk_Manager, &memory),
		Bot_Marginal_Choice.Trade,
	)
}

@(test)
soak_result_contains_conserved_economic_flow_diagnostics :: proc(t: ^testing.T) {
	r := bot_run(
		{
			profile = .Strategist,
			game_seed = 244,
			bot_seed = 4242,
			length = .Open,
			max_actions = 64,
			horizon = 24,
			tempo = .Measured,
		},
	)
	testing.expect_value(t, r.trade_shipments, r.trade_deliveries + r.trade_losses)
	testing.expect(t, r.knowledge_gained >= 0 && r.knowledge_spent >= 0)
	testing.expect(
		t,
		r.opening_active_ships > 0 && r.opening_food_capacity > 0 && r.final_food_capacity > 0,
	)
}

@(test)
adaptive_policy_separates_budgets_and_preserves_explicit_targets :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(
		45,
	); defer game.campaign_destroy_heap(c); c.material_economy.fleet.stock.supplies = 40; b := bot_budget_buckets(c, .Strategist); targets := bot_policy_targets(.Strategist)
	testing.expect(
		t,
		b.maintenance > 0 && b.emergency_reserve > 0 && b.development > 0,
	); testing.expect(t, b.development <= game.fleet_supply(c))
	testing.expect(
		t,
		targets.food_reserve_seasons >= 3 &&
		targets.free_industrial_capacity >= 4 &&
		targets.essential_role_redundancy >= 2 &&
		targets.route_redundancy >= 2 &&
		targets.obligation_margin >= 2,
	)
}

@(test)
essential_loss_produces_import_or_deliberate_contraction_by_profile :: proc(t: ^testing.T) {
	risk := game.new_campaign_heap(
		46,
	); defer game.campaign_destroy_heap(risk); for &ship in risk.ships[:risk.ship_count] do if ship.role == .Agriculture do ship.active = false
	memory: Bot_Strategy_Memory; testing.expect(t, bot_answer_essential_exposure(risk, .Risk_Manager, &memory)); testing.expect_value(t, risk.material_economy.essential[int(game.Role.Agriculture)].chosen, game.Capability_Response.Import_Service)
	world := game.new_campaign_heap(
		47,
	); defer game.campaign_destroy_heap(world); for &ship in world.ships[:world.ship_count] do if ship.role == .Foundry do ship.active = false
	testing.expect(
		t,
		bot_answer_essential_exposure(world, .World_Builder, &memory),
	); testing.expect_value(t, world.material_economy.population_policy, game.Population_Policy.Planned_Contraction)
}

@(test)
bots_answer_pre_emergency_warning_with_structural_policy :: proc(t: ^testing.T) {
	for profile in Bot_Profile {c := game.new_campaign_heap(48 + u64(profile)); c.emergency_structural_response_pending = true; c.material_economy.fleet.stock.supplies = 40; rng := Bot_Rng{9}; result: Bot_Run_Result; memory: Bot_Strategy_Memory; config := Bot_Run_Config {
			profile = profile,
		}; bot_manage_season(
			c,
			&config,
			&rng,
			&result,
			&memory,
		); testing.expect(t, !c.emergency_structural_response_pending); testing.expect(t, c.emergency_preparedness > 0); testing.expect(t, memory.structural_investments > 0); game.campaign_destroy_heap(c)}
}

@(test)
tempo_telemetry_groups_major_roots_by_recorded_season :: proc(t: ^testing.T) {
	events := [6]game.Campaign_Event {
		{sequence = 1, season = 4, kind = .Situation_Proposed},
		{sequence = 2, season = 5, kind = .Fleet_Hazard, value = 1},
		{sequence = 3, season = 5, kind = .Season_Advanced},
		{sequence = 4, season = 6, kind = .Front_Advanced},
		{sequence = 5, season = 5, kind = .Fleet_Hazard, value = 1, cause_count = 1},
		{sequence = 6, season = 5, kind = .Situation_Proposed, cause_count = 1},
	}
	testing.expect_value(
		t,
		bot_major_roots_in_season(events[:], 4),
		i32(1),
	); testing.expect_value(t, bot_major_roots_in_season(events[:], 5), i32(1)); testing.expect_value(t, bot_major_roots_in_season(events[:], 6), i32(1)); testing.expect_value(t, bot_major_roots_in_season(events[:], 5, 2), i32(0))
}

@(test)
matched_bot_telemetry_reports_no_measured_or_spacious_stacking :: proc(t: ^testing.T) {
	tempos := [2]game.Story_Tempo {
		game.Story_Tempo.Measured,
		game.Story_Tempo.Spacious,
	}; for profile in Bot_Profile do for tempo in tempos do for seed in u64(1) ..= u64(2) {r := bot_run({profile = profile, game_seed = seed, bot_seed = seed * 31337, length = .Open, max_actions = 64, horizon = 24, tempo = tempo}); testing.expect_value(t, r.tempo_stack_violations, i32(0))}
}

@(test)
sampled_validator_strategist_measured_cell_has_no_stacking :: proc(t: ^testing.T) {
	// The validation CLI owns exhaustive cells; this test protects their exact
	// seed/configuration path with a deterministic smoke sample.
	for sample in 0 ..< 4 {seed := u64(1 + sample * 53); r := bot_run({profile = .Strategist, game_seed = seed, bot_seed = seed * 0x9e3779b97f4a7c15 ~ (u64(Bot_Profile.Strategist) + 1), length = .Open, max_actions = 64, horizon = 24, tempo = .Measured}); testing.expectf(t, r.tempo_stack_violations == 0, "seed %d stacked in season %d with %v", seed, r.first_tempo_stack_season, r.first_tempo_stack_kinds[:r.first_tempo_stack_kind_count])}
}

@(test)
action_dominance_only_counts_decisions_with_two_affordable_options :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(901); defer game.campaign_destroy_heap(c); r: Bot_Run_Result
	c.current_situation = {
		kind         = .Repair_Debt,
		phase        = .Decision,
		choice_count = 3,
	}; c.current_situation.choices[0] = {
		raw_materials = 2,
	}; c.current_situation.choices[1] = {
		raw_materials = 1,
	}; c.current_situation.choices[2] = {
		raw_materials = 99,
	}
	for _ in 0 ..< 8 do record_action_choice(c, &r, 0)
	for _ in 0 ..< 2 do record_action_choice(c, &r, 1)
	finalize_action_dominance(
		&r,
	); testing.expect_value(t, r.action_opportunities[int(game.Situation_Kind.Repair_Debt)], i32(10)); testing.expect_value(t, r.dominant_action_kind, game.Situation_Kind.Repair_Debt); testing.expect_value(t, r.dominant_action_index, i32(0)); testing.expect(t, r.dominant_action_rate > .70)
	c.capacities.raw_materials.reserved = 11; before := r.action_opportunities[int(game.Situation_Kind.Repair_Debt)]; record_action_choice(c, &r, 1); testing.expect_value(t, r.action_opportunities[int(game.Situation_Kind.Repair_Debt)], before)
}

@(test)
dominance_gate_requires_five_comparable_opportunities :: proc(t: ^testing.T) {
	r: Bot_Run_Result; r.action_opportunities[int(game.Situation_Kind.Repair_Debt)] = 4; r.action_choices[int(game.Situation_Kind.Repair_Debt)][1] = 4; finalize_action_dominance(&r)
	testing.expect_value(
		t,
		r.dominant_action_rate,
		f64(0),
	); testing.expect_value(t, r.low_sample_lockin_opportunities, i32(4)); testing.expect_value(t, r.low_sample_lockin_rate, f64(1))
}

@(test)
bot_retries_suspended_essential_role_training :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(
		904,
	); defer game.campaign_destroy_heap(c); ag := game.ship_index(c, 8); c.ships[ag].active = false; c.ships[ag].departure = .Lost
	game.detect_essential_exposure(c)
	p := &c.material_economy.research[int(game.Research_Kind.Ship_Role_Training)]
	p^ = {
		kind                 = .Ship_Role_Training,
		active               = true,
		suspended            = true,
		remaining            = 3,
		knowledge_per_season = 3,
		industry_per_season  = 1,
		manpower             = 3,
		ship                 = c.ships[0].id,
	}
	memory: Bot_Strategy_Memory
	testing.expect(t, bot_answer_essential_exposure(c, .Steward, &memory))
	testing.expect(t, !p.suspended)
}

@(test)
bots_leave_overloaded_obligations_to_autonomous_world_resolution :: proc(
	t: ^testing.T,
) {
	for tempo in game.Story_Tempo {c := game.new_campaign_heap(902); c.story_tempo = tempo; c.season = 15; game.advance_obligations(c); testing.expect(t, c.obligations.underfunded_count > 0); before := c.event_sequence; rng := Bot_Rng{77}; result: Bot_Run_Result; config := Bot_Run_Config {
			profile   = .Strategist,
			game_seed = 902,
			bot_seed  = 77,
			tempo     = tempo,
		}; bot_manage_season(
			c,
			&config,
			&rng,
			&result,
		); testing.expect(t, !game.public_question_active(&c.public_politics.open)); testing.expect(t, c.event_sequence >= before); game.campaign_destroy_heap(c)}
}

@(test)
passage_bot_uses_current_allocation_and_feasible_rescue_plans :: proc(t: ^testing.T) {
	for profile in Bot_Profile do for tempo in game.Story_Tempo {
		seed := u64(77) + u64(profile) * 17 + u64(tempo)
		r := bot_run({profile = profile, game_seed = seed, bot_seed = seed * 0x9e3779b97f4a7c15 ~ (u64(profile) + 1), length = .Open, max_actions = 64, horizon = 24, tempo = tempo})
		testing.expectf(
			t,
			r.invalid_actions == 0,
			"profile=%v tempo=%v seed=%d failure=%v family=%v action=%v target=%d situation=%v passage=%v blocker=%s",
			profile,
			tempo,
			seed,
			r.first_failure_kind,
			r.first_failure_family,
			r.first_failure_action,
			r.first_failure_target,
			r.first_failure_situation_phase,
			r.first_failure_passage_phase,
			r.first_failure_blocker,
		)
	}
}

@(test)
world_builder_long_horizon_is_not_an_automatic_settlement_win :: proc(t: ^testing.T) {
	// A dozen matched seeds catches an automatic-win regression. Population
	// estimates remain the responsibility of the dedicated balance matrix.
	runs := 4; seed_base := u64(0x5eed)
	for tempo in game.Story_Tempo {settlement_wins := 0; for sample in 0 ..< runs {seed := seed_base + u64(sample); r := bot_run({profile = .World_Builder, game_seed = seed, bot_seed = seed * 0x9e3779b97f4a7c15 ~ (u64(Bot_Profile.World_Builder) + 1), length = .Open, max_actions = 64, horizon = 24, tempo = tempo}); if r.ending == .New_Home || r.ending == .Harbor_Network || r.ending == .Federation do settlement_wins += 1; testing.expect_value(t, r.invalid_actions, i32(0))}; rate := f64(settlement_wins) / f64(runs); fmt.printf("world-builder tempo:%s settlement-win-rate:%.3f\n", story_tempo_name(tempo), rate); testing.expect(t, rate < .95)}
}

@(test)
bot_reserves_essential_replacement_before_discretionary_projects :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(
		1902,
	); defer game.campaign_destroy_heap(c); ag := game.ship_index(c, 8); c.ships[ag].active = false; c.ships[ag].departure = .Lost; c.ships[0].damage = 3; _, _ = game.discover_candidate_home(c, 1902); c.material_economy.fleet.stock.supplies = 50
	rng := Bot_Rng{17}; result: Bot_Run_Result; config := Bot_Run_Config {
		profile   = .Explorer,
		game_seed = 1902,
		bot_seed  = 17,
	}; bot_manage_season(c, &config, &rng, &result)
	testing.expect(
		t,
		c.material_economy.research[int(game.Research_Kind.Ship_Role_Training)].active,
	)
	for project in c.projects do testing.expect(t, !project.active)
}
