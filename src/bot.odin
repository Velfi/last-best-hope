package main

import game "../packages/game"

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"

Bot_Profile :: enum {
	Strategist,
	Steward,
	Explorer,
	Risk_Manager,
	World_Builder,
}
Bot_Weights :: struct {
	objective,
	safety,
	reward,
	rescue,
	science,
	settlement,
	exploration,
	command,
	needs,
	projects: i32,
}

Bot_Rng :: struct {
	state: u64,
}

Bot_Run_Config :: struct {
	profile:        Bot_Profile,
	game_seed:      u64,
	bot_seed:       u64,
	length:         game.Chronicle_Length,
	trace:          bool,
	max_actions:    int,
	horizon:        i32,
	tempo:          game.Story_Tempo,
	story_report:   bool,
	telemetry_csv:  bool,
	measure_phases: bool,
}

Bot_Run_Timings :: struct {
	initialization_ms, policy_ms, passage_ms, advance_ms, telemetry_ms, finalize_ms: f64,
	passage_begin_ms, passage_dark_ms, passage_normal_ms, passage_conclude_ms:       f64,
	passage_course_planning_ms, passage_dark_tick_ms:                                f64,
}

MAX_SOAK_SEASONS :: 1000
BOT_SITUATION_KIND_COUNT :: int(game.Situation_Kind.Value_Every_Home_Is_Free) + 1
YEARS_PER_SEASON :: 3
soak_seasons_for_years :: proc(years: i32) -> i32 {return(
		(years + YEARS_PER_SEASON - 1) /
		YEARS_PER_SEASON \
	)}
soak_years_for_seasons :: proc(seasons: i32) -> i32 {return seasons * YEARS_PER_SEASON}

bot_preferred_length :: proc(profile: Bot_Profile) -> game.Chronicle_Length {
	switch profile {case .Explorer, .Risk_Manager:
		return .Short; case .World_Builder:
		return .Long; case .Strategist, .Steward:
		return .Standard}
	return .Standard
}

Bot_Strategy_Memory :: struct {
	sustenance_shortfalls, ship_repairs, settlement_demands: i32,
	temporary_relief_uses, structural_investments:           i32,
}
Bot_Policy_Targets :: struct {
	food_reserve_seasons,
	free_industrial_capacity,
	essential_role_redundancy,
	settlement_self_sufficiency,
	route_redundancy,
	obligation_margin: i32,
}
Bot_Budget_Buckets :: struct {
	maintenance, emergency_reserve, development: i32,
}

Bot_Marginal_Choice :: enum {
	Repair,
	Replacement,
	Productive_Investment,
	Settlement_Support,
	Trade,
	Migration,
	Contraction,
}

bot_marginal_choice :: proc(
	c: ^game.Campaign,
	profile: Bot_Profile,
	memory: ^Bot_Strategy_Memory,
) -> Bot_Marginal_Choice {
	game.detect_essential_exposure(c)
	for exposure in c.material_economy.essential do if exposure.exposed && !exposure.acknowledged {
		if profile == .Risk_Manager do return .Trade
		if profile == .World_Builder || memory.sustenance_shortfalls >= 2 do return .Contraction
		return .Replacement
	}
	if c.material_economy.food_shortage_response_pending || memory.sustenance_shortfalls >= 2 do return .Productive_Investment
	for economy in c.settlement_economies.economies[:c.settlement_economies.count] {
		if !economy.active do continue
		if economy.shortage_seasons >= 2 || economy.infrastructure < 55 do return .Settlement_Support
		if economy.population > economy.housing do return .Migration
	}
	for flow in c.settlement_economies.flows[:c.settlement_economies.flow_count] do if flow.active && (flow.condition == .Closed || flow.reliability < 60) do return .Trade
	best_repair: i32
	for ship in c.ships[:c.ship_count] do if ship.active && ship.damage > 0 {
		value := ship.damage * 3
		if ship.role == .Agriculture || ship.role == .Hospital || ship.role == .Foundry do value += 4
		best_repair = max(best_repair, value)
	}
	food_target :=
		bot_policy_targets(profile).food_reserve_seasons * max(game.total_population(c) / 5500, 4)
	development_value :=
		max(food_target - i32(c.material_economy.fleet.stock.food), 0) +
		memory.temporary_relief_uses * 3
	if development_value > best_repair do return .Productive_Investment
	return .Repair
}

bot_policy_targets :: proc(profile: Bot_Profile) -> Bot_Policy_Targets {
	r := Bot_Policy_Targets {
		food_reserve_seasons        = 3,
		free_industrial_capacity    = 4,
		essential_role_redundancy   = 2,
		settlement_self_sufficiency = 60,
		route_redundancy            = 2,
		obligation_margin           = 2,
	}
	if profile ==
	   .Risk_Manager {r.food_reserve_seasons = 4; r.free_industrial_capacity = 6; r.obligation_margin = 3}
	if profile == .World_Builder {r.settlement_self_sufficiency = 70; r.route_redundancy = 3}
	return r
}

bot_budget_buckets :: proc(c: ^game.Campaign, profile: Bot_Profile) -> Bot_Budget_Buckets {
	stock :=
		c.material_economy.fleet.stock; floor := game.fleet_operating_floor(c).stock; available := i32(max(stock.supplies - floor.supplies, 0)); maintenance := i32(max(stock.manufactured_goods - floor.manufactured_goods, 0) + max(stock.services - floor.services, 0)); r := Bot_Budget_Buckets {
		maintenance       = maintenance,
		emergency_reserve = i32(floor.supplies),
	}; r.development = available
	if profile ==
	   .Risk_Manager {r.emergency_reserve += r.development / 4; r.development -= r.development / 4}
	return r
}

bot_project_affordable :: proc(c: ^game.Campaign, kind: game.Project_Kind) -> bool {
	cost := game.fleet_project_cost(kind)
	// Typed project costs and the policy buckets are now the authoritative
	// constraint. The former scalar maintenance buffer double-counted unrelated
	// stocks and made valid development projects unreachable.
	ok, _, _ := game.fleet_stock_spend_preview(c, cost, .Routine)
	return ok
}

bot_answer_essential_exposure :: proc(
	c: ^game.Campaign,
	profile: Bot_Profile,
	memory: ^Bot_Strategy_Memory,
) -> bool {
	game.detect_essential_exposure(c)
	for role in game.Role {
		e := &c.material_economy.essential[int(role)]; if !e.exposed do continue
		if profile == .Risk_Manager && game.resolve_essential_exposure(c, role, .Import_Service) do return true
		if (profile == .World_Builder || memory.sustenance_shortfalls >= 2) && game.resolve_essential_exposure(c, role, .Contract_Demand) do return true
		training := &c.material_economy.research[int(game.Research_Kind.Ship_Role_Training)]
		if training.active && training.suspended do _ = game.suspend_research_program(c, .Ship_Role_Training, false)
		return game.reserve_essential_replacement(c)
	}
	return false
}
Season_Telemetry :: struct {
	season,
	major_beats,
	incoming_needs,
	unresolved_needs,
	active_fronts,
	route_mutations,
	ship_changes,
	decision_diversity:                  i32,
	compact_open_calls,
	compact_available_offers,
	compact_selected_offers,
	compact_callbacks_resolved:          i32,
	compact_family:                      game.Compact_Call_Family,
	compact_route:                       game.Compact_Operation_Route,
	compact_active:                      bool,
	compact_quiet_beat:                  bool,
	immediate_relief_uses,
	structural_recovery_target:                                                                                        i32,
	structural_recovery_active:                                                                                                               bool,
	sustenance_min,
	sustenance_max,
	industry_min,
	industry_max,
	knowledge_min,
	knowledge_max,
	cohesion_min,
	cohesion_max,
	hope_min,
	hope_max: i32,
}

Bot_Run_Result :: struct {
	profile:                                                                                                                                                                                                                                                                                                                                                                                                          Bot_Profile,
	game_seed,
	bot_seed:                                                                                                                                                                                                                                                                                                                                                                                              u64,
	ending:                                                                                                                                                                                                                                                                                                                                                                                                           game.Ending,
	ending_quality:                                                                                                                                                                                                                                                                                                                                                                                                   game.Ending_Quality,
	seasons,
	passages,
	objectives,
	triumphs,
	successes,
	partials,
	disasters,
	lost_passages:                                                                                                                                                                                                                                                                                                                           i32,
	ships_lost,
	ships_settled,
	ships_damaged,
	ships_scarred,
	rescued,
	promises_upheld,
	promises_broken:                                                                                                                                                                                                                                                                                                               i32,
	settlements,
	charter_changes,
	archive_established,
	archive_charters,
	archive_revelations,
	accountability_responses,
	figure_petitions,
	figure_events,
	captains,
	captain_reappearances,
	captain_petitions,
	tagged_events,
	tagged_memories,
	community_memories,
	community_triggers,
	promise_recollections,
	contested_reports,
	repair_outcomes,
	constitutional_emergencies,
	invalid_actions,
	safety_returns,
	actions: i32,
	caused_events,
	multi_cause_events,
	multi_season_callbacks,
	relationship_reversals,
	max_causal_depth:                                                                                                                                                                                                                                                                                                              i32,
	emergency_events,
	first_emergency_season:                                                                                                                                                                                                                                                                                                                                                                         i32,
	last_emergency_cause:                                                                                                                                                                                                                                                                                                                                                                                             game.Emergency_Cause,
	final_compute,
	final_manpower,
	final_raw_materials:                                                                                                                                                                                                                                                                                                                                                               i32,
	opening_sustenance,
	opening_industry,
	opening_knowledge,
	opening_population,
	opening_settlements:                                                                                                                                                                                                                                                                                                                 i32,
	opening_food_capacity,
	final_food_capacity,
	knowledge_gained,
	knowledge_spent:                                                                                                                                                                                                                                                                                                                                    i32,
	opening_compute,
	opening_manpower,
	opening_raw_materials:                                                                                                                                                                                                                                                                                                                                                         i32,
	final_sustenance,
	final_industry,
	final_knowledge,
	final_population:                                                                                                                                                                                                                                                                                                                                              i32,
	final_active_ships,
	final_broken_promises,
	final_pending_claims,
	final_hazards:                                                                                                                                                                                                                                                                                                                                   i32,
	projects_repair,
	projects_supply,
	projects_colony,
	projects_archive,
	migrations:                                                                                                                                                                                                                                                                                                                                  i32,
	economy_produced,
	economy_consumed,
	economy_imported,
	economy_exported,
	economy_lost:                                                                                                                                                                                                                                                                                                                             game.Economy_Stock,
	trade_shipments,
	trade_deliveries,
	trade_losses:                                                                                                                                                                                                                                                                                                                                                                  i64,
	fleet_food_production,
	fleet_food_consumption,
	fleet_food_imports,
	fleet_food_exports,
	fleet_food_spoilage:                                                                                                                                                                                                                                                                                                       i64,
	fleet_stock:                                                                                                                                                                                                                                                                                                                                                                                                      game.Fleet_Stock,
	fleet_season:                                                                                                                                                                                                                                                                                                                                                                                                     game.Fleet_Flow_Ledger,
	fleet_committed,
	fleet_recovered,
	fleet_rewarded:                                                                                                                                                                                                                                                                                                                                                                 game.Fleet_Stock,
	seasons_below_floor:                                                                                                                                                                                                                                                                                                                                                                                              [7]i32,
	passage_net_supplies,
	maintenance_recovery_projects:                                                                                                                                                                                                                                                                                                                                                              i32,
	maintenance_demand,
	maintenance_debt,
	food_shortage_episodes,
	sustainable_seasons,
	economy_damage_episodes:                                                                                                                                                                                                                                                                                                       i32,
	stars_surveyed_by_class:                                                                                                                                                                                                                                                                                                                                                                                          [4]i32,
	survey_funnel:                                                                                                                                                                                                                                                                                                                                                                                                    game.World_Survey_Funnel,
	candidate_classes:                                                                                                                                                                                                                                                                                                                                                                                                [3]i32,
	world_surveys,
	survey_supply_cost,
	founding_waivers:                                                                                                                                                                                                                                                                                                                                                              i32,
	eligible_endings:                                                                                                                                                                                                                                                                                                                                                                                                 u32,
	unmet_ending_requirements:                                                                                                                                                                                                                                                                                                                                                                                        string,
	opening_active_ships:                                                                                                                                                                                                                                                                                                                                                                                             i32,
	maintenance_budget,
	emergency_budget,
	development_budget:                                                                                                                                                                                                                                                                                                                                                         i32,
	final_rng_sequence:                                                                                                                                                                                                                                                                                                                                                                                               u64,
	telemetry:                                                                                                                                                                                                                                                                                                                                                                                                        [MAX_SOAK_SEASONS]Season_Telemetry,
	telemetry_count:                                                                                                                                                                                                                                                                                                                                                                                                  int,
	first_saturated_collection:                                                                                                                                                                                                                                                                                                                                                                                       string,
	first_failure_kind:                                                                                                                                                                                                                                                                                                                                                                                               Bot_Failure_Kind,
	first_failure_family:                                                                                                                                                                                                                                                                                                                                                                                             Bot_Action_Family,
	first_failure_action:                                                                                                                                                                                                                                                                                                                                                                                             Bot_Action_Kind,
	first_failure_target:                                                                                                                                                                                                                                                                                                                                                                                             int,
	first_failure_situation_phase:                                                                                                                                                                                                                                                                                                                                                                                    game.Situation_Phase,
	first_failure_passage_phase:                                                                                                                                                                                                                                                                                                                                                                                      game.Dark_Expedition_Phase,
	first_failure_blocker:                                                                                                                                                                                                                                                                                                                                                                                            string,
	action_opportunities:                                                                                                                                                                                                                                                                                                                                                                                             [BOT_SITUATION_KIND_COUNT]i32,
	action_choices:                                                                                                                                                                                                                                                                                                                                                                                                   [BOT_SITUATION_KIND_COUNT][game.MAX_SITUATION_CHOICES]i32,
	dominant_action_kind:                                                                                                                                                                                                                                                                                                                                                                                             game.Situation_Kind,
	dominant_action_index:                                                                                                                                                                                                                                                                                                                                                                                            i32,
	dominant_action_rate:                                                                                                                                                                                                                                                                                                                                                                                             f64,
	low_sample_lockin_kind:                                                                                                                                                                                                                                                                                                                                                                                           game.Situation_Kind,
	low_sample_lockin_rate:                                                                                                                                                                                                                                                                                                                                                                                           f64,
	low_sample_lockin_opportunities:                                                                                                                                                                                                                                                                                                                                                                                  i32,
	planner_candidates,
	planner_score_margin_total:                                                                                                                                                                                                                                                                                                                                                                   i64,
	planner_chosen_score,
	planner_runner_up_score,
	planner_projected_delta,
	planner_finale_quality_delta,
	planner_no_positive_seasons:                                                                                                                                                                                                                                                                                i32,
	planner_action_choices:                                                                                                                                                                                                                                                                                                                                                                                           [5]i32,
	selected_value_pair:                                                                                                                                                                                                                                                                                                                                                                                              int,
	value_tests:                                                                                                                                                                                                                                                                                                                                                                                                      [8]i32,
	law_classifications:                                                                                                                                                                                                                                                                                                                                                                                              [6]i32,
	law_reviews:                                                                                                                                                                                                                                                                                                                                                                                                      [4]i32,
	state_signature:                                                                                                                                                                                                                                                                                                                                                                                                  u64,
	qualifying_fronts:                                                                                                                                                                                                                                                                                                                                                                                                i32,
	region_revisit_mutated:                                                                                                                                                                                                                                                                                                                                                                                           bool,
	preserved_over_512:                                                                                                                                                                                                                                                                                                                                                                                               bool,
	tempo_stack_violations:                                                                                                                                                                                                                                                                                                                                                                                           i32,
	first_tempo_stack_season:                                                                                                                                                                                                                                                                                                                                                                                         i32,
	first_tempo_stack_kinds:                                                                                                                                                                                                                                                                                                                                                                                          [4]game.Event_Kind,
	first_tempo_stack_kind_count:                                                                                                                                                                                                                                                                                                                                                                                     int,
	telemetry_csv:                                                                                                                                                                                                                                                                                                                                                                                                    bool,
	dangling_causal_references,
	duplicate_settlement_identities,
	economic_flow_mismatches,
	overdue_essential_exposures:                                                                                                                                                                                                                                                                                               i32,
	productive_regions,
	changed_trade_dependencies:                                                                                                                                                                                                                                                                                                                                                                   i32,
	knowledge_bounded_or_explained,
	integer_bounds_clean,
	candidate_home_known,
	colony_package_ready:                                                                                                                                                                                                                                                                                                                 bool,
	timings:                                                                                                                                                                                                                                                                                                                                                                                                          Bot_Run_Timings,
}

Bot_Summary :: struct {
	runs:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               int,
	wins,
	objectives,
	passages,
	loss_campaigns,
	ships_lost,
	ships_settled,
	ships_scarred,
	rescued,
	promises_upheld,
	promises_broken,
	settlements,
	charter_changes,
	archive_established,
	archive_charters,
	archive_revelations,
	accountability_responses,
	figure_petitions,
	figure_events,
	captains,
	captain_reappearances,
	captain_petitions,
	tagged_events,
	tagged_memories,
	community_memories,
	community_triggers,
	promise_recollections,
	contested_reports,
	repair_outcomes,
	actions,
	emergencies,
	emergency_events,
	emergency_first_season_total,
	invalid_actions: i64,
	caused_events,
	multi_cause_events,
	multi_season_callbacks,
	relationship_reversals,
	max_causal_depth_total:                                                                                                                                                                                                                                                                                                                                                                                                                                                          i64,
	emergency_cause_counts:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             [4]i64,
	ending_counts:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      [7]int,
	profile_counts:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     [5]int,
	action_opportunities:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               [BOT_SITUATION_KIND_COUNT]i64,
	action_choices:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     [BOT_SITUATION_KIND_COUNT][game.MAX_SITUATION_CHOICES]i64,
	value_tests:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        [8]i64,
	law_classifications:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                [6]i64,
	law_reviews:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        [4]i64,
	planner_candidates,
	planner_score_margin_total,
	planner_no_positive_seasons:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        i64,
	planner_action_choices:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             [5]i64,
}

// Balance budgets are report thresholds, not hidden difficulty modifiers.
EXPERIENCED_WIN_RATE_LOW :: 70.0
EXPERIENCED_WIN_RATE_HIGH :: 80.0
MEANINGFUL_SETBACK_RATE_LOW :: 35.0
MEANINGFUL_SETBACK_RATE_HIGH :: 55.0
SCAR_CAMPAIGN_RATE_LOW :: 15.0
SCAR_CAMPAIGN_RATE_HIGH :: 30.0
SHIP_LOSS_CAMPAIGN_RATE_LOW :: 3.0
SHIP_LOSS_CAMPAIGN_RATE_HIGH :: 10.0
EMERGENCY_CAMPAIGN_RATE_LOW :: 15.0
EMERGENCY_CAMPAIGN_RATE_HIGH :: 30.0

bot_profile_name :: proc(profile: Bot_Profile) -> string {
	switch profile {
	case .Strategist:
		return "strategist"
	case .Steward:
		return "steward"
	case .Explorer:
		return "explorer"
	case .Risk_Manager:
		return "risk-manager"
	case .World_Builder:
		return "world-builder"
	}
	return "strategist"
}

parse_bot_profile :: proc(value: string) -> (Bot_Profile, bool) {
	switch value {
	case "strategist":
		return .Strategist, true
	case "steward":
		return .Steward, true
	case "explorer":
		return .Explorer, true
	case "risk-manager", "risk_manager":
		return .Risk_Manager, true
	case "world-builder", "world_builder":
		return .World_Builder, true
	}
	return .Strategist, false
}

story_tempo_name :: proc(tempo: game.Story_Tempo) -> string {switch tempo {case .Spacious:
		return "spacious"; case .Volatile:
		return "volatile"; case .Measured:
		return "measured"}; return "measured"}
parse_story_tempo :: proc(value: string) -> (game.Story_Tempo, bool) {switch
	value {case "spacious":
		return .Spacious, true; case "measured":
		return .Measured, true; case "volatile":
		return .Volatile, true}
	return .Measured, false}

bot_event_is_unrelated_major_root :: proc(event: game.Campaign_Event) -> bool {
	// Constitutional emergency is an immediate consequence of the player's
	// accumulated resource state. It is attributable, not a new director root.
	if event.kind == .Situation_Proposed && strings.has_prefix(event.detail, "The council began considering ") do return false
	// Political measures surfaced from recorded needs and fronts carry their
	// source event as a causal edge. They are callbacks to existing pressure,
	// not fresh director beats.
	if event.kind == .Situation_Proposed && event.cause_count > 0 do return false
	if event.kind == .Fleet_Hazard && event.value <= 0 do return false
	// Recurring hazard pressure records a causal edge to the hazard it extends;
	// it is an escalation callback, not another unrelated beat.
	if event.kind == .Fleet_Hazard && event.cause_count > 0 do return false
	#partial switch event.kind {case .Fleet_Hazard, .Situation_Proposed, .Front_Proposed, .Front_Advanced, .Front_Returned:
		return true; case:}
	return false
}

bot_major_roots_in_season :: proc(
	events: []game.Campaign_Event,
	season: i32,
	after_sequence: u64 = 0,
) -> i32 {count: i32; for event in events do if event.sequence > after_sequence && event.season == season && bot_event_is_unrelated_major_root(event) do count += 1
	return count}

bot_weights :: proc(profile: Bot_Profile) -> Bot_Weights {
	switch profile {
	case .Strategist:
		return {14, 10, 10, 6, 7, 5, 5, 9, 12, 11}
	case .Steward:
		return {8, 10, 3, 20, 4, 8, 3, 7, 18, 9}
	case .Explorer:
		return {8, 4, 9, 5, 17, 8, 20, 11, 5, 7}
	case .Risk_Manager:
		return {10, 20, 4, 7, 5, 3, 2, 5, 14, 9}
	case .World_Builder:
		return {9, 8, 5, 12, 10, 22, 9, 7, 15, 16}
	}
	return {}
}


bot_rng_next :: proc(rng: ^Bot_Rng) -> u64 {
	x := rng.state
	if x == 0 do x = 0x9e3779b97f4a7c15
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	if x == 0 do x = 1
	rng.state = x
	return x
}

bot_objective :: proc(c: ^game.Campaign, profile: Bot_Profile) -> game.Dark_Contract_Purpose {
	#partial switch profile {
	case .Explorer:
		// A full five-role ecology census is intentionally demanding. Explorers
		// revisit it periodically while using intervening voyages to map doors,
		// rather than repeating an unmet census forever.
		return c.season % 3 == 0 ? .Ecological_Survey : .Map_Unknown_Door
	case .Steward:
		return .Stabilize_Relay
	case .Risk_Manager:
		return .Verify_Correspondence
	case:
		return .Map_Unknown_Door
	}
}

bot_reach_unknown_door :: proc(
	c: ^game.Campaign,
	config: ^Bot_Run_Config,
	result: ^Bot_Run_Result,
	depth: f64,
) -> bool {
	steps := 0
	for c.passage.active && c.passage.domain == .Dark && steps < config.max_actions {
		if c.passage.phase == .Awaiting_Leg {
			if c.passage.pause_reason ==
			   .Coherence_Limit {preview := game.passage_coherence_recovery_preview(c, &c.passage, false); rapid := preview.can_resume && !preview.crosses_limit && preview.held_projected < preview.limit * .92; ok, _ := game.stabilize_passage_coherence(c, &c.passage, !rapid); if !ok do return false; if rapid do continue}
			if c.passage.pause_reason ==
			   .Dangerous_Contact {contact_id: u64; nearest := f64(1e30); for &track in c.passage.dark_navigation.tracker.tracks[:c.passage.dark_navigation.tracker.track_count] do if game.dark_track_requires_response(&track) && track.distance < nearest {nearest = track.distance; contact_id = track.organism_id}; ok, _ := game.respond_to_dark_contact(c, &c.passage, false, contact_id); if !ok do return false; continue}
			if c.passage.pause_reason ==
			   .Material_Obstruction {preview := game.passage_obstruction_response_preview(c, &c.passage); wait := preview.can_wait && (!preview.can_detour || preview.detour_added > 2); ok, _ := game.respond_to_material_obstruction(c, &c.passage, wait); if !ok do return false; continue}
			if c.passage.pause_reason == .Course_Arrival &&
			   game.dark_door_at_position(
				   &c.outer_dark.continuum,
				   c.passage.dark_navigation.position,
			   ) >=
				   0 {
				ok, _ := game.cross_passage_door(c, &c.passage)
				if ok do return true
			}
			phase_started := time.tick_now()
			course, found := game.passage_course_to_unknown_door(c, &c.passage, depth)
			if config.measure_phases do result.timings.passage_course_planning_ms += time.duration_seconds(time.tick_since(phase_started)) * 1000
			if !found do return false
			_, plotted := game.plot_passage_course(c, &c.passage, course)
			if !plotted do return false
		}
		if c.passage.phase == .Underway {
			if c.passage.contract.purpose ==
			   .Ecological_Survey {documented := false; for track in c.passage.dark_navigation.tracker.tracks[:c.passage.dark_navigation.tracker.track_count] {bit := u32(1) << u32(track.role); if c.passage.observed_ecology_roles & bit == 0 {ok, _ := game.document_dark_contact(c, &c.passage, track.organism_id); if ok {result.actions += 1; documented = true}; break}}; if documented do continue}
			phase_started := time.tick_now()
			game.advance_passage(c, &c.passage, .5)
			if config.measure_phases do result.timings.passage_dark_tick_ms += time.duration_seconds(time.tick_since(phase_started)) * 1000
			steps += 1
			result.actions += 1
		}
	}
	return c.passage.domain == .Normal_Space
}

bot_play_passage :: proc(
	c: ^game.Campaign,
	config: ^Bot_Run_Config,
	rng: ^Bot_Rng,
	result: ^Bot_Run_Result,
) {
	if c.passage.active do return
	contract := game.default_passage_contract(
		
	); contract.purpose = bot_objective(c, config.profile)
	// Scenario resources belong to accepted undertakings. Operations keep their
	// factual debrief return without inventing a repeatable reward loop.
	_ = game.apply_active_charter_to_passage_contract(c, &contract)
	ships: [3]int
	crew_ok, ship_count := bot_select_passage_crew(c, &contract, &ships)
	if !crew_ok do return
	crew_field_scars, crew_damage: i32; for index in ships[:ship_count] {crew_field_scars += c.ships[index].dark_field_scars; crew_damage += c.ships[index].damage}
	// Repeated field damage is a forecastable coherence cost. Wait for a crew
	// with a viable exposure history instead of commissioning a likely loss.
	if (crew_field_scars > 3 || crew_damage > 2) && config.horizon <= 24 do return
	phase_started := time.tick_now()
	if contract.undertaking_id == 0 do return
	ok, begin_message := game.begin_passage(c, contract, ships[:ship_count], &c.passage)
	if config.measure_phases do result.timings.passage_begin_ms += time.duration_seconds(time.tick_since(phase_started)) * 1000
	if !ok {
		bot_record_failure(c, result, .Passage_Begin, .Passage, blocker = begin_message)
		return
	}
	result.passages += 1
	recommended := game.recommend_dark_strategy(
		c,
		&contract,
	); _, _ = game.set_dark_strategy(c, &c.passage, recommended.strategy)
	phase_started = time.tick_now()
	depth := f64(2.5); if config.profile == .Risk_Manager do depth = .5
	passage_config := config^; if config.profile == .Strategist do passage_config.max_actions = max(passage_config.max_actions, 80)
	ok = bot_reach_unknown_door(c, &passage_config, result, depth)
	if config.measure_phases do result.timings.passage_dark_ms += time.duration_seconds(time.tick_since(phase_started)) * 1000
	if !ok {_, _ = game.declare_passage_missing(c, &c.passage); return}
	phase_started = time.tick_now()
	if c.passage.domain == .Normal_Space {
		if c.passage.relay_advised ||
		   c.passage.contract.purpose ==
			   .Stabilize_Relay {_, _, _ = game.service_passage_relay(c, &c.passage)}
		entered, _ := game.enter_passage_dark(c, &c.passage, c.passage.pending_door_id)
		if entered {
			for route_step in 0 ..< 64 {
				if c.passage.domain == .Normal_Space do break
				ok, _ := game.follow_fastest_known_route(
					c,
					&c.passage,
					c.outer_dark.continuum.anchor_neighborhood,
				)
				if !ok do break
				if c.passage.phase == .Underway {
					// A blocked known-route leg can remain Underway without consuming a
					// decision boundary. Bound bot fast-forwarding so a malformed or
					// stalled route cannot hang an entire campaign simulation.
					underway_steps := 0
					for c.passage.phase == .Underway && underway_steps < 256 {
						game.advance_passage(c, &c.passage, .5)
						underway_steps += 1
					}
					if c.passage.phase == .Underway do break
				}
				result.actions += 1
			}
		}
	}
	if config.measure_phases do result.timings.passage_normal_ms += time.duration_seconds(time.tick_since(phase_started)) * 1000
	if c.passage.contract.objective_met do result.objectives += 1
	phase_started = time.tick_now()
	if !game.set_passage_safe_endpoint(
		c,
		&c.passage,
		.Fleet,
	) {_, _ = game.declare_passage_missing(c, &c.passage); return}
	conclude_message: string
	ok, conclude_message = game.conclude_passage(c, &c.passage)
	if !ok do bot_record_failure(c, result, .Passage_Conclude, .Passage, blocker = conclude_message)
	if config.measure_phases do result.timings.passage_conclude_ms += time.duration_seconds(time.tick_since(phase_started)) * 1000
}
