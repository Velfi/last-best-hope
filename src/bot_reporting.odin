package main

import game "../packages/game"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:testing"

bot_is_win :: proc(ending: game.Ending, quality := game.Ending_Quality.Stable) -> bool {
	identity :=
		ending == .New_Home ||
		ending == .Harbor_Network ||
		ending == .Nomadic_Fleet ||
		ending == .Federation ||
		ending == .Transformed
	return identity && quality != .None && quality != .Fragile
}

summary_add :: proc(summary: ^Bot_Summary, result: ^Bot_Run_Result) {
	summary.runs += 1
	summary.profile_counts[int(result.profile)] += 1
	summary.ending_counts[int(result.ending)] += 1
	if bot_is_win(result.ending, result.ending_quality) do summary.wins += 1
	summary.objectives += i64(result.objectives)
	summary.passages += i64(result.passages)
	summary.ships_lost += i64(result.ships_lost)
	if result.ships_lost > 0 do summary.loss_campaigns += 1
	summary.ships_settled += i64(result.ships_settled)
	summary.ships_scarred += i64(result.ships_scarred)
	summary.rescued += i64(result.rescued)
	summary.promises_upheld += i64(result.promises_upheld)
	summary.promises_broken += i64(result.promises_broken)
	summary.settlements += i64(result.settlements)
	summary.charter_changes += i64(result.charter_changes)
	summary.archive_established += i64(result.archive_established)
	summary.archive_charters += i64(result.archive_charters)
	summary.archive_revelations += i64(result.archive_revelations)
	summary.accountability_responses += i64(result.accountability_responses)
	summary.figure_petitions += i64(result.figure_petitions)
	summary.figure_events += i64(result.figure_events)
	summary.captains += i64(result.captains)
	summary.captain_reappearances += i64(result.captain_reappearances)
	summary.captain_petitions += i64(result.captain_petitions)
	summary.tagged_events += i64(result.tagged_events)
	summary.tagged_memories += i64(result.tagged_memories)
	summary.community_memories += i64(result.community_memories)
	summary.community_triggers += i64(result.community_triggers)
	summary.promise_recollections += i64(result.promise_recollections)
	summary.contested_reports += i64(result.contested_reports)
	summary.repair_outcomes += i64(result.repair_outcomes)
	summary.caused_events += i64(
		result.caused_events,
	); summary.multi_cause_events += i64(result.multi_cause_events); summary.multi_season_callbacks += i64(result.multi_season_callbacks); summary.relationship_reversals += i64(result.relationship_reversals); summary.max_causal_depth_total += i64(result.max_causal_depth)
	summary.actions += i64(result.actions)
	summary.emergencies += i64(result.constitutional_emergencies)
	summary.emergency_events += i64(result.emergency_events)
	if result.emergency_events > 0 {
		summary.emergency_first_season_total += i64(result.first_emergency_season)
		summary.emergency_cause_counts[int(result.last_emergency_cause)] += 1
	}
	summary.invalid_actions += i64(result.invalid_actions)
	summary.planner_candidates +=
		result.planner_candidates; summary.planner_score_margin_total += result.planner_score_margin_total; summary.planner_no_positive_seasons += i64(result.planner_no_positive_seasons)
	for count, i in result.planner_action_choices do summary.planner_action_choices[i] += i64(count)
	for kind in game.Situation_Kind {k := int(kind); summary.action_opportunities[k] += i64(result.action_opportunities[k]); for count, i in result.action_choices[k] do summary.action_choices[k][i] += i64(count)}
	for value, i in result.value_tests do summary.value_tests[i] += i64(value); for value, i in result.law_classifications do summary.law_classifications[i] += i64(value); for value, i in result.law_reviews do summary.law_reviews[i] += i64(value)
}

percent :: proc(value, total: i64) -> f64 {if total == 0 do return 0; return(
		f64(value) *
		100.0 /
		f64(total) \
	)}

print_bar :: proc(label: string, value, total: i64) {
	width := 32
	filled := 0
	if total > 0 do filled = int(value * i64(width) / total)
	fmt.printf("  %-23s |", label)
	for i in 0 ..< width {if i < filled {fmt.print("#")} else {fmt.print(" ")}}
	fmt.printf("| %6.2f%% (%d)\n", percent(value, total), value)
}

print_bot_summary :: proc(summary: ^Bot_Summary) {
	fmt.printf("\nBOT SIMULATION SUMMARY — %d runs\n", summary.runs)
	fmt.println("\nVALUE AND LAW COVERAGE")
	for value, i in summary.value_tests do fmt.printf("  %-28s tests:%d\n", game.value_name(game.Value_Kind(i)), value)
	for value, i in summary.law_classifications do if value > 0 do fmt.printf("  classification %-18v %d\n", game.Precedent_Classification(i), value)
	for value, i in summary.law_reviews do if value > 0 do fmt.printf("  review %-26v %d\n", game.Precedent_Review(i), value)
	fmt.printf(
		"Win rate: %.2f%%  Objective completion: %.2f%%  Avg ships lost: %.2f  Avg settled: %.2f  Avg scarred: %.2f\n",
		percent(summary.wins, i64(summary.runs)),
		percent(summary.objectives, summary.passages),
		f64(summary.ships_lost) / f64(max(summary.runs, 1)),
		f64(summary.ships_settled) / f64(max(summary.runs, 1)),
		f64(summary.ships_scarred) / f64(max(summary.runs, 1)),
	)
	fmt.printf(
		"Campaigns with ship loss: %.2f%%\n",
		percent(summary.loss_campaigns, i64(summary.runs)),
	)
	fmt.printf(
		"Rescued: %d  Promises upheld/broken: %d/%d  Promise recollections: %d  Settlements: %d  Charter changes: %d  Archive copies/charters: %d/%d  Revelations/responses: %d/%d  Figure petitions/events: %d/%d  Captains/reappearances/petitions: %d/%d/%d  Community memories/triggers: %d/%d  Contested reports: %d  Funded repairs: %d\n",
		summary.rescued,
		summary.promises_upheld,
		summary.promises_broken,
		summary.promise_recollections,
		summary.settlements,
		summary.charter_changes,
		summary.archive_established,
		summary.archive_charters,
		summary.archive_revelations,
		summary.accountability_responses,
		summary.figure_petitions,
		summary.figure_events,
		summary.captains,
		summary.captain_reappearances,
		summary.captain_petitions,
		summary.community_memories,
		summary.community_triggers,
		summary.contested_reports,
		summary.repair_outcomes,
	)
	fmt.printf(
		"Semantic records — events/memories: %d/%d\n",
		summary.tagged_events,
		summary.tagged_memories,
	)
	fmt.printf(
		"Causal quality — linked %.2f%% · convergent %d · multi-season callbacks %d · reversals %d · avg max depth %.2f\n",
		percent(summary.caused_events, summary.tagged_events),
		summary.multi_cause_events,
		summary.multi_season_callbacks,
		summary.relationship_reversals,
		f64(summary.max_causal_depth_total) / f64(max(summary.runs, 1)),
	)
	avg_first: f64
	if summary.emergencies > 0 do avg_first = f64(summary.emergency_first_season_total) / f64(summary.emergencies)
	fmt.printf(
		"Passages: %d  Actions: %d  Emergency campaigns/events: %d/%d  Avg first season: %.2f  Cohesion crises: %d  Invalid actions: %d\n\nENDING DISTRIBUTION\n",
		summary.passages,
		summary.actions,
		summary.emergencies,
		summary.emergency_events,
		avg_first,
		summary.emergency_cause_counts[int(game.Emergency_Cause.Cohesion)],
		summary.invalid_actions,
	)
	planner_actions: i64; for count in summary.planner_action_choices do planner_actions += count
	fmt.printf(
		"Planner candidates/actions/no-positive-seasons: %d/%d/%d  Avg chosen margin: %.2f\n",
		summary.planner_candidates,
		planner_actions,
		summary.planner_no_positive_seasons,
		f64(summary.planner_score_margin_total) / f64(max(planner_actions, 1)),
	)
	fmt.printf(
		"Balance budgets — experienced wins %.0f–%.0f%%; meaningful setbacks ≥%.0f%%; ship-loss campaigns ≤%.0f%%; emergency campaigns ≤%.0f%%; quiet share is reported by Story Tempo soak.\n",
		EXPERIENCED_WIN_RATE_LOW,
		EXPERIENCED_WIN_RATE_HIGH,
		MEANINGFUL_SETBACK_RATE_LOW,
		SHIP_LOSS_CAMPAIGN_RATE_HIGH,
		EMERGENCY_CAMPAIGN_RATE_HIGH,
	)
	fmt.println("Affordable-choice dominance (gate: investigate >70%):")
	for kind in game.Situation_Kind {k := int(kind); total := summary.action_opportunities[k]; if total <= 0 do continue; best: i64; best_index := -1; for count, i in summary.action_choices[k] do if count > best {best = count; best_index = i}; rate := percent(best, total); fmt.printf("  %-22v choice:%d %.2f%% (%d/%d) %s\n", kind, best_index, rate, best, total, rate > 70 ? "INVESTIGATE" : "PASS")}
	for ending in game.Ending {
		if ending == .In_Progress do continue
		print_bar(
			game.ending_name(ending),
			i64(summary.ending_counts[int(ending)]),
			i64(summary.runs),
		)
	}
}

print_run_csv_header :: proc() {
	fmt.println(
		"profile,game_seed,bot_seed,ending,ending_quality,seasons,passages,objectives,ships_lost,ships_settled,ships_damaged,ships_scarred,rescued,settlements,emergency_campaign,emergency_events,invalid_actions,food,raw,goods,equipment,propellant,supplies,services,maintenance_demand,maintenance_debt,shortage_episodes,sustainable_seasons,eligible_endings,surveys,stars_m,stars_k,stars_g,stars_f,planets,terrestrial,hz,atmosphere,water,long_term,settlement_capable,natural,engineered,unsuitable,survey_supply_cost,founding_waivers,rng_sequence",
	)
}

print_run_csv :: proc(r: ^Bot_Run_Result) {
	fmt.printf(
		"%s,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
		bot_profile_name(r.profile),
		r.game_seed,
		r.bot_seed,
		game.ending_name(r.ending),
		game.ending_quality_name(r.ending_quality),
		r.seasons,
		r.passages,
		r.objectives,
		r.ships_lost,
		r.ships_settled,
		r.ships_damaged,
		r.ships_scarred,
		r.rescued,
		r.settlements,
		r.constitutional_emergencies,
		r.emergency_events,
		r.invalid_actions,
		r.fleet_stock.food,
		r.fleet_stock.raw_materials,
		r.fleet_stock.manufactured_goods,
		r.fleet_stock.equipment,
		r.fleet_stock.propellant,
		r.fleet_stock.supplies,
		r.fleet_stock.services,
		r.maintenance_demand,
		r.maintenance_debt,
		r.food_shortage_episodes,
		r.sustainable_seasons,
		r.eligible_endings,
		r.world_surveys,
		r.stars_surveyed_by_class[0],
		r.stars_surveyed_by_class[1],
		r.stars_surveyed_by_class[2],
		r.stars_surveyed_by_class[3],
		r.survey_funnel.planets,
		r.survey_funnel.terrestrial,
		r.survey_funnel.conservative_hz,
		r.survey_funnel.atmosphere_retained,
		r.survey_funnel.water_bearing,
		r.survey_funnel.long_term,
		r.survey_funnel.settlement_capable,
		r.candidate_classes[int(game.Candidate_World_Class.Naturally_Habitable)],
		r.candidate_classes[int(game.Candidate_World_Class.Engineered_Candidate)],
		r.candidate_classes[int(game.Candidate_World_Class.Surveyed_Unsuitable)],
		r.survey_supply_cost,
		r.founding_waivers,
		r.final_rng_sequence,
	)
}

parse_u64_or :: proc(value: string, fallback: u64) -> u64 {
	parsed, ok := strconv.parse_u64(value)
	if !ok do return fallback
	return parsed
}

parse_int_or :: proc(value: string, fallback: int) -> int {
	parsed, ok := strconv.parse_i64(value)
	if !ok do return fallback
	return int(parsed)
}

run_bot_cli :: proc(args: []string) -> bool {
	if len(args) < 2 do return false
	command := args[1]
	seed_base := u64(0x5eed)

	switch command {
	case "--benchmark-campaigns":
		if len(args) < 5 {fmt.println(
				"usage: --benchmark-campaigns <runs> <profile> <tempo> [seed] [horizon-seasons] [warmup] [repetitions]",
			)
			return true}
		runs := max(parse_int_or(args[2], 100), 1)
		profile, profile_ok := parse_bot_profile(args[3])
		tempo, tempo_ok := parse_story_tempo(args[4])
		if !profile_ok ||
		   !tempo_ok {fmt.println("invalid campaign benchmark profile or tempo"); return true}
		seed := len(args) >= 6 ? parse_u64_or(args[5], seed_base) : seed_base
		horizon := len(args) >= 7 ? i32(max(parse_int_or(args[6], 24), 1)) : 24
		warmup := len(args) >= 8 ? max(parse_int_or(args[7], 3), 0) : 3
		repetitions := len(args) >= 9 ? max(parse_int_or(args[8], 3), 1) : 3
		run_campaign_benchmark(runs, profile, tempo, seed, horizon, warmup, repetitions)
		return true
	case "--simulate":
		if len(args) < 4 {
			fmt.println("usage: --simulate <runs> <profile|all> [--csv] [seed]")
			return true
		}
		runs := max(parse_int_or(args[2], 0), 0)
		csv := len(args) >= 5 && args[4] == "--csv" || len(args) >= 6 && args[5] == "--csv"
		story_report := false
		for arg in args[4:] do if arg == "--story" do story_report = true
		if len(args) >= 5 && args[4] != "--csv" do seed_base = parse_u64_or(args[4], seed_base)
		if len(args) >= 6 && args[5] != "--csv" do seed_base = parse_u64_or(args[5], seed_base)
		if runs <= 0 {
			fmt.println("simulation run count must be positive")
			return true
		}
		profile, profile_ok := parse_bot_profile(args[3])
		all := args[3] == "all"
		if !all && !profile_ok {
			fmt.println("unknown bot profile")
			return true
		}
		if csv do print_run_csv_header()
		summary: Bot_Summary
		for sample in 0 ..< runs {
			if all {
				for selected in Bot_Profile {
					seed := seed_base + u64(sample)
					r := bot_run(
						{
							profile = selected,
							game_seed = seed,
							bot_seed = seed * 0x9e3779b97f4a7c15 ~ (u64(selected) + 1),
						length = bot_preferred_length(selected),
						max_actions = 64,
						story_report = story_report,
						},
					)
					if csv {print_run_csv(&r)} else {summary_add(&summary, &r)}
				}
			} else {
				seed := seed_base + u64(sample)
				r := bot_run(
					{
						profile = profile,
						game_seed = seed,
						bot_seed = seed * 0x9e3779b97f4a7c15 ~ (u64(profile) + 1),
						length = bot_preferred_length(profile),
						max_actions = 64,
						story_report = story_report,
					},
				)
				if csv {print_run_csv(&r)} else {summary_add(&summary, &r)}
			}
		}
		if !csv do print_bot_summary(&summary)
		return true
	case "--soak-seasons", "--soak-years":
		if len(args) < 6 {
			fmt.printf("usage: %s <count> <profile> <tempo> <seed> [--telemetry-csv]\n", command)
			return true
		}
		count := max(parse_int_or(args[2], 0), 0)
		profile, profile_ok := parse_bot_profile(args[3])
		tempo, tempo_ok := parse_story_tempo(args[4])
		seed := parse_u64_or(args[5], seed_base)
		if count <= 0 || !profile_ok || !tempo_ok {
			fmt.println("invalid soak arguments")
			return true
		}
		seasons := i32(count)
		if command == "--soak-years" do seasons = soak_seasons_for_years(i32(count))
		r := bot_run(
			{
				profile = profile,
				game_seed = seed,
				bot_seed = seed ~ 0x517cc1b727220a95,
				length = .Open,
				max_actions = 64,
				horizon = seasons,
				tempo = tempo,
				telemetry_csv = len(args) >= 7 && args[6] == "--telemetry-csv",
			},
		)
		print_soak_report(&r, tempo)
		return true
	case "--compare-tempos":
		if len(args) < 5 do return true
		profile, ok := parse_bot_profile(args[3]); if !ok do return true
		print_matched_tempo_report(
			i32(max(parse_int_or(args[2], 1), 1)),
			profile,
			parse_u64_or(args[4], seed_base),
		)
		return true
	case "--validate-campaigns", "--sample-balance":
		runs := len(args) >= 3 ? max(parse_int_or(args[2], 20), 1) : 20
		seed := len(args) >= 4 ? parse_u64_or(args[3], seed_base) : seed_base
		_ = run_release_validation(runs, seed, command == "--validate-campaigns")
		return true
	case "--validate-long-runs":
		samples := len(args) >= 3 ? max(parse_int_or(args[2], 1), 1) : 1
		seed := len(args) >= 4 ? parse_u64_or(args[3], seed_base) : seed_base
		years := len(args) >= 5 ? i32(max(parse_int_or(args[4], 0), 0)) : 0
		_ = run_long_horizon_validation(samples, seed, years)
		return true
	case "--investigate-actions":
		samples := len(args) >= 3 ? max(parse_int_or(args[2], 1), 1) : 1
		seed := len(args) >= 4 ? parse_u64_or(args[3], seed_base) : seed_base
		horizon := len(args) >= 5 ? i32(max(parse_int_or(args[4], 100), 1)) : 100
		_ = run_action_dominance_investigation(samples, seed, horizon)
		return true
	}
	return false
}

print_soak_report :: proc(r: ^Bot_Run_Result, tempo: game.Story_Tempo) {
	fmt.printf(
		"SOAK profile:%s tempo:%s seed:%d horizon:%d seasons (%d years) ending:%s invalid-actions:%d saturation:%s\n",
		bot_profile_name(r.profile),
		story_tempo_name(tempo),
		r.game_seed,
		r.seasons,
		soak_years_for_seasons(r.seasons),
		game.ending_name(r.ending),
		r.invalid_actions,
		r.first_saturated_collection == "" ? "none" : r.first_saturated_collection,
	)
	fmt.printf(
		"ACTION DOMINANCE kind:%v choice:%d rate:%.1f%% gate:%s\n",
		r.dominant_action_kind,
		r.dominant_action_index,
		r.dominant_action_rate * 100,
		r.dominant_action_rate > .70 ? "INVESTIGATE" : "PASS",
	)
	if r.low_sample_lockin_rate > .7 do fmt.printf("LOW-SAMPLE LOCK-IN kind:%v opportunities:%d rate:%.1f%% (reported; not a dominance gate)\n", r.low_sample_lockin_kind, r.low_sample_lockin_opportunities, r.low_sample_lockin_rate * 100)
	fmt.printf(
		"ECON stocks fleet-food:%d→%d cultivation:%d→%d knowledge:%d→%d population:%d→%d capacity-free compute/manpower/materials:%d/%d/%d→%d/%d/%d\n",
		r.opening_sustenance,
		r.final_sustenance,
		r.opening_food_capacity,
		r.final_food_capacity,
		r.opening_knowledge,
		r.final_knowledge,
		r.opening_population,
		r.final_population,
		r.opening_compute,
		r.opening_manpower,
		r.opening_raw_materials,
		r.final_compute,
		r.final_manpower,
		r.final_raw_materials,
	)
	fmt.printf(
		"ECON fleet food source production/import:%d/%d destination consumption/export/spoilage:%d/%d/%d\n",
		r.fleet_food_production,
		r.fleet_food_imports,
		r.fleet_food_consumption,
		r.fleet_food_exports,
		r.fleet_food_spoilage,
	)
	fmt.printf(
		"ECON settlements produced food/goods/services/ships/people/knowledge:%d/%d/%d/%d/%d/%d consumed:%d/%d/%d/%d/%d/%d\n",
		r.economy_produced.food,
		r.economy_produced.goods,
		r.economy_produced.services,
		r.economy_produced.ships,
		r.economy_produced.people,
		r.economy_produced.knowledge,
		r.economy_consumed.food,
		r.economy_consumed.goods,
		r.economy_consumed.services,
		r.economy_consumed.ships,
		r.economy_consumed.people,
		r.economy_consumed.knowledge,
	)
	fmt.printf(
		"ECON trade source exports:%d/%d/%d/%d/%d/%d destination imports:%d/%d/%d/%d/%d/%d shipped/delivered/lost:%d/%d/%d\n",
		r.economy_exported.food,
		r.economy_exported.goods,
		r.economy_exported.services,
		r.economy_exported.ships,
		r.economy_exported.people,
		r.economy_exported.knowledge,
		r.economy_imported.food,
		r.economy_imported.goods,
		r.economy_imported.services,
		r.economy_imported.ships,
		r.economy_imported.people,
		r.economy_imported.knowledge,
		r.trade_shipments,
		r.trade_deliveries,
		r.trade_losses,
	)
	fmt.printf(
		"ECON allocation projects production/maintenance/settlement/archive:%d/%d/%d/%d migration-records:%d knowledge gained/spent:%d/%d\n",
		r.projects_supply,
		r.projects_repair,
		r.projects_colony,
		r.projects_archive,
		r.migrations,
		r.knowledge_gained,
		r.knowledge_spent,
	)
	fmt.printf(
		"ECON Passage Supplies committed/recovered/rewarded/net:%d/%d/%d/%d · recovery-projects:%d · seasons-below-floor:%v\n",
		r.fleet_committed.supplies,
		r.fleet_recovered.supplies,
		r.fleet_rewarded.supplies,
		r.passage_net_supplies,
		r.maintenance_recovery_projects,
		r.seasons_below_floor,
	)
	fmt.printf(
		"CAUSE food capacity:%d→%d after production projects:%d; settlements:%d→%d after founding records:%d; population:%d→%d after migration records:%d\n",
		r.opening_food_capacity,
		r.final_food_capacity,
		r.projects_supply,
		r.opening_settlements,
		r.settlements,
		r.projects_colony,
		r.opening_population,
		r.final_population,
		r.migrations,
	)
	fmt.printf(
		"CAUSE Knowledge:%d gained - %d spent => deployable %d→%d; active ships:%d→%d after lost/settled:%d/%d\n",
		r.knowledge_gained,
		r.knowledge_spent,
		r.opening_knowledge,
		r.final_knowledge,
		r.opening_active_ships,
		r.final_active_ships,
		r.ships_lost,
		r.ships_settled,
	)
	fmt.printf(
		"CAUSE settlement pipeline candidate-home:%v colony-package:%v\n",
		r.candidate_home_known,
		r.colony_package_ready,
	)
	fmt.printf(
		"POLICY budgets maintenance/emergency/development:%d/%d/%d · validation dangling:%d duplicate-settlements:%d flow-mismatch:%d overdue-essential:%d knowledge-backed:%v regions:%d changed-trade:%d\n",
		r.maintenance_budget,
		r.emergency_budget,
		r.development_budget,
		r.dangling_causal_references,
		r.duplicate_settlement_identities,
		r.economic_flow_mismatches,
		r.overdue_essential_exposures,
		r.knowledge_bounded_or_explained,
		r.productive_regions,
		r.changed_trade_dependencies,
	)
	if r.telemetry_csv {fmt.println("season,major_beats,incoming_needs,unresolved_needs,active_fronts,route_mutations,resource_floors,resource_ceilings,ship_changes,decision_diversity,immediate_relief_uses,structural_recovery_active,structural_recovery_target"); for t in r.telemetry[:r.telemetry_count] do fmt.printf("%d,%d,%d,%d,%d,%d,%d/%d/%d/%d/%d,%d/%d/%d/%d/%d,%d,%d,%d,%v,%d\n", t.season, t.major_beats, t.incoming_needs, t.unresolved_needs, t.active_fronts, t.route_mutations, t.sustenance_min, t.industry_min, t.knowledge_min, t.cohesion_min, t.hope_min, t.sustenance_max, t.industry_max, t.knowledge_max, t.cohesion_max, t.hope_max, t.ship_changes, t.decision_diversity, t.immediate_relief_uses, t.structural_recovery_active, t.structural_recovery_target)}
}

print_matched_tempo_report :: proc(count: i32, profile: Bot_Profile, seed: u64) {
	fmt.printf(
		"MATCHED STORY TEMPO — profile:%s seed:%d horizon:%d seasons (%d years)\n",
		bot_profile_name(profile),
		seed,
		count,
		soak_years_for_seasons(count),
	)
	for tempo in game.Story_Tempo {r := bot_run({profile = profile, game_seed = seed, bot_seed = seed ~ 0x9e3779b97f4a7c15, length = .Open, max_actions = 64, horizon = count, tempo = tempo}); major := i32(0); quiet := i32(0); for t in r.telemetry[:r.telemetry_count] {major += t.major_beats; if t.major_beats == 0 do quiet += 1}; fmt.printf("  %-9s ending:%-20s beats:%d quiet:%.1f%% loss:%d emergency:%d invalid:%d dominance:%v/%d %.1f%% %s saturation:%s\n", story_tempo_name(tempo), game.ending_name(r.ending), major, f64(quiet) * 100 / f64(max(r.telemetry_count, 1)), r.ships_lost, r.emergency_events, r.invalid_actions, r.dominant_action_kind, r.dominant_action_index, r.dominant_action_rate * 100, r.dominant_action_rate > .70 ? "INVESTIGATE" : "PASS", r.first_saturated_collection == "" ? "none" : r.first_saturated_collection)}
}

Validation_Cell :: struct {
	runs,
	wins,
	front_gate,
	revisit_gate,
	invalid,
	saturated,
	stacking,
	setbacks,
	scars,
	ship_loss,
	emergencies,
	quiet_seasons,
	total_seasons,
	dominant_over_70,
	low_sample_lockin,
	passages,
	objectives,
	settlements,
	active_ships,
	broken_promises,
	pending_claims,
	hazards,
	planner_candidates,
	planner_margin,
	planner_no_positive,
	committed_supplies,
	recovered_supplies,
	rewarded_supplies,
	passage_net_supplies,
	recovery_projects: i64,
	max_dominant_rate:                                                                                                                                                                                                                                                                                                                                                                                                                      f64,
	ending_counts:                                                                                                                                                                                                                                                                                                                                                                                                                          [7]i64,
	outcome_counts:                                                                                                                                                                                                                                                                                                                                                                                                                         [28]i64,
	planner_actions:                                                                                                                                                                                                                                                                                                                                                                                                                        [5]i64,
}

