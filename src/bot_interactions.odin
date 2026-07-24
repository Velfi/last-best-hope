package main

import game "../packages/game"

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"
bot_interaction_choice :: proc(c: ^game.Campaign, profile: Bot_Profile) -> int {
	s := &c.current_situation
	if s.kind >= .Value_No_One_Left_Behind && s.kind <= .Value_Every_Home_Is_Free {
		switch profile {case .Steward, .World_Builder:
			return 0; case .Strategist:
			return game.capacity_available(c.capacities.manpower) >= 3 ? 0 : 1; case .Explorer:
			return 1; case .Risk_Manager:
			return game.has_precedent(c, .Emergency_Command) ? 2 : 1}
	}
	switch profile {
	case .Strategist:
		#partial switch s.kind {
		case .Repair_Debt:
			return 1
		case .Settlement:
			return c.hazard_count >= 3 ? 0 : 3
		case .Rescue:
			return 1
		case .Contested_Evidence:
			return 0
		case .Combat_Aftermath:
			return 1
		case .Value_No_One_Left_Behind,
		     .Value_Truth_Before_Comfort,
		     .Value_Consent_To_Settle,
		     .Value_Shelter_Is_Sacred,
		     .Value_Shared_Authority,
		     .Value_Open_Archives,
		     .Value_The_Fleet_Endures,
		     .Value_Every_Home_Is_Free:
			return 0
		case .None:
			return 0
		}
	case .Steward:
		return 0
	case .Explorer:
		#partial switch s.kind {
		case .Repair_Debt:
			return 1
		case .Settlement:
			return 2
		case .Rescue:
			return c.story_tempo == .Measured ? 0 : 1
		case .Contested_Evidence:
			return 1
		case .Combat_Aftermath:
			return 1
		case .Value_No_One_Left_Behind,
		     .Value_Truth_Before_Comfort,
		     .Value_Consent_To_Settle,
		     .Value_Shelter_Is_Sacred,
		     .Value_Shared_Authority,
		     .Value_Open_Archives,
		     .Value_The_Fleet_Endures,
		     .Value_Every_Home_Is_Free:
			return 0
		case .None:
			return 0
		}
	case .Risk_Manager:
		#partial switch s.kind {
		case .Repair_Debt:
			return 1
		case .Settlement:
			if c.hazard_count >= 3 do return 0
			if game.fleet_supply(c) >= 50 && game.capacity_available(c.capacities.manpower) >= 8 do return 1
			return 3
		case .Rescue:
			return 1
		case .Contested_Evidence:
			return 1
		case .Combat_Aftermath:
			return 0
		case .Value_No_One_Left_Behind,
		     .Value_Truth_Before_Comfort,
		     .Value_Consent_To_Settle,
		     .Value_Shelter_Is_Sacred,
		     .Value_Shared_Authority,
		     .Value_Open_Archives,
		     .Value_The_Fleet_Endures,
		     .Value_Every_Home_Is_Free:
			return 0
		case .None:
			return 0
		}
	case .World_Builder:
		#partial switch s.kind {
		case .Repair_Debt:
			return 1
		case .Settlement:
			hazard_limit := c.story_tempo == .Volatile ? i32(4) : i32(1)
			// Affordability is not a mandate. A minority of otherwise viable
			// proposals retain the fleet when accumulated ecology, route exposure,
			// and prior founding history do not support another departure.
			return(
				c.hazard_count < hazard_limit && game.capacity_available(c.capacities.manpower) >= 4 ? 1 : 0 \
			)
		case .Rescue:
			return 0
		case .Contested_Evidence:
			return 0
		case .Combat_Aftermath:
			return 2
		case .Value_No_One_Left_Behind,
		     .Value_Truth_Before_Comfort,
		     .Value_Consent_To_Settle,
		     .Value_Shelter_Is_Sacred,
		     .Value_Shared_Authority,
		     .Value_Open_Archives,
		     .Value_The_Fleet_Endures,
		     .Value_Every_Home_Is_Free:
			return 0
		case .None:
			return 0
		}
	}
	return 0
}

bot_adaptive_interaction_choice :: proc(
	c: ^game.Campaign,
	profile: Bot_Profile,
	memory: ^Bot_Strategy_Memory,
) -> int {
	s := &c.current_situation
	if s.kind == .Repair_Debt {
		switch profile {
		case .Steward:
			return 0
		case .Strategist:
			return (c.season + memory.ship_repairs) % 3 == 0 ? 0 : 1
		case .Explorer:
			return c.season % 2 == 0 ? 0 : 1
		case .Risk_Manager:
			return game.capacity_available(c.capacities.raw_materials) < 6 ? 2 : 1
		case .World_Builder:
			return c.settlement_count > 0 ? 0 : 1
		}
	}
	if s.kind != .Settlement do return bot_interaction_choice(c, profile)
	if c.story_tempo != .Spacious && c.settlement_count == 0 && profile != .Strategist do return 0
	if profile == .Explorer && c.story_tempo != .Spacious do return 0
	if profile != .Strategist && profile != .World_Builder do return bot_interaction_choice(c, profile)
	best, best_score := 0, i32(-0x3fffffff)
	// Settlement policy is evaluated from the recorded charter process, the
	// ecology and route ledgers, remaining fleet capability, and prior outcomes.
	charter_ready :=
		c.settlement_proposal.charter_participation && c.settlement_proposal.disclose_evidence
	ecology: i32 = 70; active_economies := i32(0)
	for economy in c.settlement_economies.economies[:c.settlement_economies.count] do if economy.active {ecology += economy.ecology; active_economies += 1}
	if active_economies > 0 do ecology /= active_economies + 1
	route_risk := c.hazard_count
	for flow in c.settlement_economies.flows[:c.settlement_economies.flow_count] do if flow.active && (flow.condition == .Closed || flow.condition == .Degrading) do route_risk += 1
	active_ships := game.active_ship_count(c); poor_outcomes: i32
	for settlement in c.settlements[:c.settlement_count] do if settlement.active && settlement.reported && settlement.viability < 60 do poor_outcomes += 1
	for choice, i in s.choices[:s.choice_count] {
		if !interaction_choice_affordable(c, choice) do continue
		score := i32(20) - choice.compute * 2 - choice.manpower * 3 - choice.raw_materials * 2
		#partial switch choice.effect {
		case .Found_Settlement:
			if charter_ready {score += 8} else {score -= 12}
			if ecology >= 65 {score += 6} else {score -= 8}
			if route_risk >= 3 do score -= 12
			if active_ships <= 6 do score -= 14
			score -= poor_outcomes * 6
		case .Amend_Settlement:
			score += poor_outcomes * 5 + (charter_ready ? i32(3) : i32(9))
			if ecology < 65 || route_risk >= 2 do score += 7
		case .Delay:
			if ecology < 55 || route_risk >= 3 || active_ships <= 6 do score += 12
		case .Decline:
			if poor_outcomes >= 2 || active_ships <= 5 do score += 16
		case:
			score += i32((i + int(c.settlement_count) + int(c.hazard_count)) % s.choice_count) * 2
		}
		if game.fleet_supply(c) < 45 do score -= choice.manpower * 4
		if c.hazard_count >= 3 do score -= choice.raw_materials * 2
		if game.capacity_available(c.capacities.manpower) >= 8 do score += choice.manpower
		if profile == .Strategist && memory.settlement_demands > 0 do score += i32((i + int(memory.settlement_demands)) % s.choice_count) * 3
		if score > best_score {best_score = score; best = i}
	}
	return best
}

interaction_choice_affordable :: proc(c: ^game.Campaign, choice: game.Situation_Choice) -> bool {
	return(
		choice.compute <= game.capacity_available(c.capacities.compute) &&
		choice.manpower <= game.capacity_available(c.capacities.manpower) &&
		choice.raw_materials <= game.capacity_available(c.capacities.raw_materials) \
	)
}

record_action_choice :: proc(c: ^game.Campaign, result: ^Bot_Run_Result, choice_index: int) {
	s := &c.current_situation; if s.kind == .None || choice_index < 0 || choice_index >= s.choice_count do return
	affordable := 0; for choice in s.choices[:s.choice_count] do if interaction_choice_affordable(c, choice) do affordable += 1
	// Surfaced choices already carry implemented consequences; with two affordable
	// options they are both strategically plausible and enter dominance analysis.
	if affordable < 2 || !interaction_choice_affordable(c, s.choices[choice_index]) do return
	k := int(
		s.kind,
	); result.action_opportunities[k] += 1; result.action_choices[k][choice_index] += 1
}

finalize_action_dominance :: proc(result: ^Bot_Run_Result) {
	for kind in game.Situation_Kind {k := int(kind); total := result.action_opportunities[k]; if total <= 0 do continue; for count, index in result.action_choices[k] {rate := f64(count) / f64(total); if total >= 5 {if rate > result.dominant_action_rate {result.dominant_action_rate = rate; result.dominant_action_kind = kind; result.dominant_action_index = i32(index)}} else if rate > .7 && rate > result.low_sample_lockin_rate {result.low_sample_lockin_rate = rate; result.low_sample_lockin_kind = kind; result.low_sample_lockin_opportunities = total}}}
}

bot_answer_food_shortage :: proc(
	c: ^game.Campaign,
	profile: Bot_Profile,
	memory: ^Bot_Strategy_Memory,
) -> bool {
	if !c.material_economy.food_shortage_response_pending do return false
	preferred := game.Food_Shortage_Command.Invest_Capacity
	switch profile {
	case .Steward:
		preferred = .Ration
	case .Explorer, .Risk_Manager:
		preferred = .Import_Route
	case .Strategist, .World_Builder:
		preferred = .Invest_Capacity
	}
	if game.apply_food_shortage_command(
		c,
		preferred,
	) {memory.structural_investments += 1; return true}
	fallbacks := [3]game.Food_Shortage_Command{.Invest_Capacity, .Import_Route, .Ration}
	for fallback in fallbacks {
		if game.apply_food_shortage_command(
			c,
			fallback,
		) {memory.structural_investments += 1; return true}
	}
	return false
}

bot_manage_compact :: proc(c: ^game.Campaign, profile: Bot_Profile) -> bool {
	if c.compact.counsel.available {
		option := 0
		if profile == .Explorer do option = 2
		if profile == .Risk_Manager do option = 1
		return game.compact_resolve_counsel(c, option)
	}
	if c.compact.active.status == .Planning || c.compact.active.status == .Operating do return false
	best := -1
	best_score := i32(-1000)
	for call, i in c.compact.calls[:c.compact.call_count] {
		if call.status != .Open do continue
		score := i32(10)
		switch profile {
		case .Explorer:
			if call.family == .Survey_Verify do score += 20
		case .Steward:
			if call.family == .Rescue_Recover || call.family == .Escort_Evacuate do score += 20
		case .Risk_Manager:
			if call.family == .Stabilize_Build do score += 20
			score += max(call.deadline - c.season, 0)
		case .Strategist:
			if call.family == .Defend_Intercept do score += 20
		case .World_Builder:
			if call.family == .Stabilize_Build || call.family == .Escort_Evacuate do score += 20
		}
		score += max(6 - (call.deadline - c.season), 0)
		if score > best_score {
			best = i
			best_score = score
		}
	}
	if best < 0 do return false
	call := &c.compact.calls[best]
	approach := 0
	if profile == .Explorer || profile == .Strategist do approach = min(1, call.approach_count - 1)
	_ = game.compact_select_approach(c, call.id, approach)
	selected := 0
	used: [game.MAX_COMPACT_OFFERS]bool
	for selected < min(3, call.offer_count) {
		best_offer, best_offer_score := -1, i32(-1000)
		for offer, i in call.offers[:call.offer_count] {
			if used[i] || !offer.available do continue
			score := offer.supplies + offer.materials + offer.propellant
			switch profile {
			case .Risk_Manager:
				if offer.condition == .Prefer_Withdrawal || offer.condition == .Protect_Ship {
					score += 12
				}
			case .Steward:
				if offer.condition == .Rescue_When_Possible do score += 12
			case .Explorer:
				if offer.condition == .Disclose_Findings do score += 12
			case .Strategist:
				if offer.condition == .Protect_Ship do score -= 4
				score += offer.propellant
			case .World_Builder:
				score += offer.materials
			}
			if score > best_offer_score {
				best_offer, best_offer_score = i, score
			}
		}
		if best_offer < 0 do break
		used[best_offer] = true
		if game.compact_toggle_offer(c, call.id, best_offer) {
			selected += 1
		}
	}
	if selected == 0 do return false
	return game.compact_accept_call(c, call.id)
}

bot_play_compact_combat :: proc(c: ^game.Campaign, profile: Bot_Profile) -> bool {
	u := &c.compact.active
	if u.status != .Planning || (u.route != .Close_Engagement && u.route != .Far_Engagement) {
		return false
	}
	u.status = .Operating
	ships: [game.MAX_COMPACT_OFFERS]game.Ship_ID
	for ship, i in u.seconded_ships[:u.seconded_count] do ships[i] = ship
	layer := u.route == .Far_Engagement ? game.Operation_Layer.Far_Engagement : .Close_Engagement
	objective_met := profile != .Risk_Manager || u.approach == .Close_Defense
	return game.apply_operation_return(
		c,
		layer,
		u64(u.id) << 16 ~ u64(c.season + 1),
		objective_met,
		ships[:u.seconded_count],
		game.CAMPAIGN_DAY_SECONDS,
		withdrawals = objective_met ? 0 : 1,
		protected_exposure = objective_met ? 0 : 1,
		evidence = u.route == .Far_Engagement ? 2 : 1,
	)
}

bot_manage_season :: proc(
	c: ^game.Campaign,
	config: ^Bot_Run_Config,
	rng: ^Bot_Rng,
	result: ^Bot_Run_Result,
	memory: ^Bot_Strategy_Memory = nil,
	allow_new_undertaking := true,
) {
	local_memory: Bot_Strategy_Memory; strategy_memory := memory; if strategy_memory == nil do strategy_memory = &local_memory
	if c.council.exception_pending do _ = game.resolve_political_exception(c, 0)
	if c.current_situation.phase != .None && c.current_situation.phase != .Resolved {
		interaction_steps := 0
		for (c.current_situation.phase == .Proposal || c.current_situation.phase == .Responses) &&
		    interaction_steps < 8 {
			if !game.advance_interaction(c) do break
			interaction_steps += 1
		}
		choice := bot_adaptive_interaction_choice(c, config.profile, strategy_memory)
		if c.current_situation.phase == .Decision {
			resolved := game.resolve_interaction(c, choice)
			if !resolved {
				for fallback in 0 ..< c.current_situation.choice_count {
					if fallback == choice do continue
					if game.resolve_interaction(c, fallback) {
						choice = fallback
						resolved = true
						break
					}
				}
			}
			if resolved do record_action_choice(c, result, choice)
		}
	}
	for case_record in c.precedent_cases[:c.precedent_case_count] {
		if case_record.status != .Pending || case_record.review_season > c.season do continue
		pi := game.precedent_index_by_id(
			c,
			case_record.primary,
		); if pi < 0 do continue; p := c.precedents[pi]
		if config.profile ==
		   .Risk_Manager {narrow := game.precedent_narrow_interpretation(p.kind); if narrow != .Default && game.review_precedent_case(c, case_record.id, .Narrow, narrowed = narrow) do break}
		if config.profile == .Strategist &&
		   case_record.secondary !=
			   0 {if game.review_precedent_case(c, case_record.id, .Replace, case_record.secondary) do break}
		if config.profile ==
		   .Explorer {if game.review_precedent_case(c, case_record.id, .Leave_Contested) do break}
		_ = game.review_precedent_case(c, case_record.id, .Affirm); break
	}
	if allow_new_undertaking || c.compact.counsel.available {
		_ = bot_manage_compact(c, config.profile)
	}
	if c.season >= 1 && !c.candidate_home_known && c.world_survey_count < c.galaxy.detailed_system_count do _ = bot_survey_candidate_home(c)
	if c.colony_package_ready do _ = bot_found_ready_settlement(c)
	if config.horizon > 24 do _ = bot_sponsor_productive_daughter(c)
	_ = bot_answer_food_shortage(c, config.profile, strategy_memory)
	w := bot_weights(config.profile)
	targets := bot_policy_targets(config.profile); buckets := bot_budget_buckets(c, config.profile)
	result.maintenance_budget =
		buckets.maintenance; result.emergency_budget = buckets.emergency_reserve; result.development_budget = buckets.development
	game.initialize_obligations(c)
	if c.emergency_structural_response_pending {
		response := game.Emergency_Structural_Response.Protect_Development
		if config.profile == .Steward || config.profile == .World_Builder do response = .Institutional_Recovery
		if !game.apply_emergency_structural_response(c, response) {
			if !game.apply_emergency_structural_response(c, .Protect_Development) &&
			   !game.apply_emergency_structural_response(c, .Institutional_Recovery) {
				_ = game.apply_emergency_structural_response(c, .Contract_Obligations)
			}
		}
		strategy_memory.structural_investments += 1
	}
	// World Builders protect the obligation margin needed by the Federation
	// fallback instead of allowing due public promises to fail silently.
	protect_measured_promises :=
		c.story_tempo == .Measured &&
		(config.profile == .Strategist || config.profile == .Explorer)
	if config.profile == .World_Builder ||
	   protect_measured_promises {for promise, i in c.promises[:c.promise_count] do if promise.status == .Active {if game.honor_promise(c, i) do break}}
	bot_memory_observe(c, strategy_memory)
	replacement_reserved := bot_answer_essential_exposure(c, config.profile, strategy_memory)
	planner_budget := i32(
		3,
	); if config.profile == .Explorer do planner_budget = 2; if config.profile == .Risk_Manager do planner_budget = 4
	if c.obligations.attention_total - c.obligations.attention_reserved <= 1 do planner_budget = max(planner_budget - 2, 1)
	bot_plan_discretionary(c, config.profile, planner_budget, result, !replacement_reserved)
	// Settlement is resolved only through the surfaced interaction. This keeps
	// review, consent, capacity, and the eventual founding decision in one path.
}

bot_run_blocker :: proc(c: ^game.Campaign) -> string {
	if c.stranded_outcome_notice_pending do return "stranded outcome notice"
	if c.economy_loss_decision_pending do return "economy loss decision"
	if c.passage.active do return "active passage"
	if c.current_situation.phase != .None && c.current_situation.phase != .Resolved do return "fleet situation"
	if c.council.exception_pending do return "council exception"
	for case_record in c.precedent_cases[:c.precedent_case_count] do if case_record.status == .Pending && case_record.review_season <= c.season do return "precedent review"
	if c.material_economy.food_shortage_response_pending do return "food shortage response"
	if c.emergency_structural_response_pending do return "structural emergency response"
	if c.compact.counsel.available do return "Compact counsel"
	if c.ending_prompt_pending do return "ending prompt"
	if pending := game.campaign_pending_attention(c); pending != nil {
		return fmt.tprintf("attention source=%v id=%d", pending.source, pending.source_id)
	}
	if c.ending_finale.active {
		return fmt.tprintf(
			"finale stalled season=%d end=%d",
			c.season,
			c.ending_finale.ends_season,
		)
	}
	return "campaign made no observable progress"
}

bot_run_progress_signature :: proc(c: ^game.Campaign) -> u64 {
	signature :=
		u64(c.season + 1) * 0x9e3779b97f4a7c15 ~
		c.event_sequence * 0x517cc1b727220a95 ~
		u64(c.current_situation.phase) << 8 ~
		u64(c.passage.phase) << 16 ~
		u64(c.compact.active.status) << 24 ~
		u64(c.public_politics.open.status) << 32
	if c.passage.active do signature ~= u64(1) << 40
	if c.ending_prompt_pending do signature ~= u64(1) << 41
	if c.ending_finale.active do signature ~= u64(1) << 42
	if c.council.exception_pending do signature ~= u64(1) << 43
	if c.material_economy.food_shortage_response_pending do signature ~= u64(1) << 44
	signature ~= u64(c.passage.dark_navigation.sensor_posture) << 45
	for ship in c.ships[:c.ship_count] do signature ~= u64(game.ship_impairment_total(ship.impairments) & 15) * 0x94d049bb133111eb
	return signature
}

bot_manage_navigation :: proc(c: ^game.Campaign) {
	for &event in c.attention_queue {
		if event.active && event.source == .Fleet_Navigation {
			_ = game.campaign_resolve_attention(c, event.id, 0)
			// Resolving an arrival boundary is one bot action. Do not
			// immediately advance the clock and surface the same navigation
			// boundary again before the campaign loop can observe progress.
			return
		}
	}
	if !c.fleet_navigation.initialized do return
	if c.fleet_navigation.phase != .Holding {
		_ = game.campaign_advance_to_attention(c)
		return
	}
	capacity := game.fleet_propellant_capacity(c)
	remaining := game.fleet_propellant_remaining(c)
	if capacity <= 0 do return
	if game.fleet_deposit_index(c, c.fleet_navigation.current_body) >= 0 &&
	   remaining < capacity * .72 {
		deadline := game.campaign_time_add(c.clock.now, 120 * game.CAMPAIGN_DAY_SECONDS)
		if ok, _ := game.fleet_navigation_commit_harvest(c, capacity * .82, deadline); ok {
			_ = game.campaign_advance_to_attention(c)
			return
		}
	}
	best := game.Fleet_Transfer_Forecast{}
	best_score := f64(1e30)
	arrival_options := [3]i64{120, 240, 480}
	for deposit in c.fleet_navigation.deposits[:c.fleet_navigation.deposit_count] {
		if deposit.remaining_propellant_kt <= 0 || deposit.body == c.fleet_navigation.current_body do continue
		for days in arrival_options {
			arrival := game.campaign_time_add(c.clock.now, days * game.CAMPAIGN_DAY_SECONDS)
			forecast := game.fleet_transfer_forecast(c, deposit.body, arrival)
			if !forecast.valid || !forecast.feasible do continue
			score :=
				forecast.propellant_cost_kt +
				forecast.duration_days * .002 -
				min(deposit.remaining_propellant_kt, capacity) * .001
			if score < best_score {best = forecast; best_score = score}
		}
	}
	if best.valid {
		if ok, _ := game.fleet_navigation_commit_transfer(c, best); ok do _ = game.campaign_advance_to_attention(c)
	}
}

bot_run :: proc(config: Bot_Run_Config) -> Bot_Run_Result {
	initialization_started := time.tick_now()
	run_config := config
	setup := game.civilization_setup_generate(
		config.game_seed,
		config.length,
	); setup.story_tempo = config.tempo; setup.founding_choice = int(config.profile) % 3
	c := new(
		game.Campaign,
	); founded, _ := game.civilization_setup_commit(&setup, c); if !founded do game.campaign_init(c, config.game_seed, config.length)
	defer game.campaign_destroy_heap(c)
	actual_bot_seed := config.bot_seed
	if actual_bot_seed == 0 do actual_bot_seed = config.game_seed ~ (u64(config.profile) + 1) * 0x9e3779b97f4a7c15
	rng := Bot_Rng{actual_bot_seed}
	result := Bot_Run_Result {
		profile              = config.profile,
		game_seed            = config.game_seed,
		bot_seed             = actual_bot_seed,
		integer_bounds_clean = true,
	}
	if config.measure_phases do result.timings.initialization_ms = time.duration_seconds(time.tick_since(initialization_started)) * 1000
	result.telemetry_csv = config.telemetry_csv
	result.opening_sustenance = i32(
		c.material_economy.fleet.stock.food,
	); result.opening_industry = i32(c.material_economy.fleet.stock.manufactured_goods); result.opening_knowledge = c.material_economy.knowledge.deployable_capacity; result.opening_population = game.total_population(c); result.opening_settlements = i32(c.settlement_count); result.opening_active_ships = i32(game.active_ship_count(c)); result.opening_food_capacity = c.material_economy.agriculture.cultivation; result.opening_compute = game.capacity_available(c.capacities.compute); result.opening_manpower = game.capacity_available(c.capacities.manpower); result.opening_raw_materials = game.capacity_available(c.capacities.raw_materials)
	strategy_memory: Bot_Strategy_Memory
	last_passage_season := i32(-1)
	// Bots choose a finite reporting horizon even though the campaign itself is
	// open-ended. Reaching it is a player-policy decision, not a world rule.
	horizon := game.chronicle_length_seasons(config.length)
	if config.length == .Open do horizon = 24
	if config.horizon > 0 do horizon = config.horizon
	run_config.horizon = horizon
	run_iterations: i32
	max_run_iterations := max(horizon * 2 + 16, 64)
	last_progress_signature := ~u64(0)
	stalled_iterations: i32
	for c.ending == .In_Progress {
		run_iterations += 1
		progress_signature := bot_run_progress_signature(c)
		if progress_signature == last_progress_signature {
			stalled_iterations += 1
		} else {
			last_progress_signature = progress_signature
			stalled_iterations = 0
		}
		if stalled_iterations >= 3 {
			bot_record_failure(c, &result, .No_Progress, blocker = bot_run_blocker(c))
			result.first_saturated_collection = result.first_failure_blocker
			break
		}
		if run_iterations > max_run_iterations {
			bot_record_failure(c, &result, .Iteration_Limit, blocker = bot_run_blocker(c))
			result.first_saturated_collection = result.first_failure_blocker
			break
		}
		if c.stranded_outcome_notice_pending do _ = game.acknowledge_stranded_outcome(c)
		if c.economy_loss_decision_pending {
			if !game.resolve_economy_loss_decision(c, true) do _ = game.resolve_economy_loss_decision(c, false)
		}
		if c.ending_prompt_pending {
			// The horizon prompt does not erase decisions surfaced by the final
			// season. Account for returned undertakings and pending structural work
			// before choosing the same Conclude action available to the player.
			bot_manage_season(
				c,
				&run_config,
				&rng,
				&result,
				&strategy_memory,
				allow_new_undertaking = false,
			)
			if !bot_play_compact_combat(c, run_config.profile) &&
			   c.compact.active.status == .Planning &&
			   c.compact.active.route == .Passage {
				bot_play_passage(c, &run_config, &rng, &result)
			}
			if c.compact.counsel.available do _ = game.compact_resolve_counsel(c, -1)
			_ = game.conclude_chronicle(c)
			if c.ending != .In_Progress do break
			continue
		}
		before_needs := 0; before_ship_changes := i32(0); before_routes := i32(0)
		before_relief :=
			c.emergency_response_uses[0] +
			c.emergency_response_uses[1] +
			c.emergency_response_uses[2]
		for need in c.needs do if need.active do before_needs += 1
		for ship in c.ships[:c.ship_count] do before_ship_changes += ship.damage + ship.experience + i32(ship.departure)
		before_routes = i32(c.dark_strategy_record_count)
		phase_started := time.tick_now()
		bot_manage_season(c, &run_config, &rng, &result, &strategy_memory)
		bot_manage_navigation(c)
		if config.measure_phases do result.timings.policy_ms += time.duration_seconds(time.tick_since(phase_started)) * 1000
		if c.season >= horizon && !c.ending_finale.active {
			_ = game.conclude_chronicle(c)
			if c.ending != .In_Progress do break
			continue
		}
		if last_passage_season != c.season &&
		   (c.current_situation.phase == .None || c.current_situation.phase == .Resolved) {
			phase_started = time.tick_now()
			if !bot_play_compact_combat(c, run_config.profile) {
				bot_play_passage(c, &run_config, &rng, &result)
			}
			if config.measure_phases do result.timings.passage_ms += time.duration_seconds(time.tick_since(phase_started)) * 1000
			last_passage_season = c.season
		}
		// Telemetry's tempo gate covers autonomous seasonal direction. Passage
		// actions are bot/player initiated and must not be counted as a second
		// unrelated director beat in the same season.
		before_advance_events := c.event_sequence
		phase_started = time.tick_now()
		game.advance_season(c)
		if !game.public_question_active(&c.public_politics.open) do _ = game.surface_interaction(c)
		if config.measure_phases do result.timings.advance_ms += time.duration_seconds(time.tick_since(phase_started)) * 1000
		if result.telemetry_count < MAX_SOAK_SEASONS {
			phase_started = time.tick_now()
			t := &result.telemetry[result.telemetry_count]; t.season = c.season
			unresolved := 0; for need in c.needs do if need.active do unresolved += 1
			t.unresolved_needs = i32(
				unresolved,
			); t.incoming_needs = max(i32(unresolved - before_needs), 0); t.active_fronts = i32(c.front_count)
			for call_index in 0 ..< c.compact.call_count do if c.compact.calls[call_index].status == .Open {
				call := &c.compact.calls[call_index]
				t.compact_open_calls += 1
				t.compact_family = call.family
				for offer_index in 0 ..< call.offer_count {
					offer := &call.offers[offer_index]
					if offer.available do t.compact_available_offers += 1
					if offer.selected do t.compact_selected_offers += 1
				}
			}
			for callback in c.compact.callbacks[:c.compact.callback_count] do if callback.stage == .Resolved {
				t.compact_callbacks_resolved += 1
			}
			t.compact_active =
				c.compact.active.status == .Planning || c.compact.active.status == .Operating
			t.compact_route = c.compact.active.route
			t.compact_quiet_beat = c.season < c.compact.quiet_until_season
			t.major_beats = bot_major_roots_in_season(
				c.events[:c.event_count],
				c.season,
				before_advance_events,
			)
			if t.major_beats > 1 && result.first_tempo_stack_season == 0 {
				result.first_tempo_stack_season = c.season
				for event in c.events[:c.event_count] do if event.sequence > before_advance_events && event.season == c.season && bot_event_is_unrelated_major_root(event) && result.first_tempo_stack_kind_count < len(result.first_tempo_stack_kinds) {
					result.first_tempo_stack_kinds[result.first_tempo_stack_kind_count] = event.kind; result.first_tempo_stack_kind_count += 1
				}
			}
			after_changes := i32(
				0,
			); for ship in c.ships[:c.ship_count] do after_changes += ship.damage + ship.experience + i32(ship.departure); t.ship_changes = abs(after_changes - before_ship_changes)
			after_routes := i32(
				c.dark_strategy_record_count,
			); t.route_mutations = abs(after_routes - before_routes)
			t.sustenance_min = i32(
				c.material_economy.fleet.stock.food,
			); t.sustenance_max = t.sustenance_min; t.industry_min = i32(c.material_economy.fleet.stock.manufactured_goods); t.industry_max = t.industry_min; t.knowledge_min = c.material_economy.knowledge.deployable_capacity; t.knowledge_max = c.material_economy.knowledge.deployable_capacity; t.cohesion_min = c.strategic.cohesion; t.cohesion_max = c.strategic.cohesion; t.hope_min = c.strategic.cohesion; t.hope_max = c.strategic.cohesion
			t.decision_diversity = i32(
				c.current_situation.selected_choice + 1,
			); result.telemetry_count += 1
			t.immediate_relief_uses =
				c.emergency_response_uses[0] +
				c.emergency_response_uses[1] +
				c.emergency_response_uses[2] -
				before_relief; t.structural_recovery_active = c.emergency_recovery_active; t.structural_recovery_target = c.emergency_recovery_target
			if config.measure_phases do result.timings.telemetry_ms += time.duration_seconds(time.tick_since(phase_started)) * 1000
		}
	}
	finalize_started := time.tick_now()
	if c.chronicle_saturation_failures >
	   0 {result.first_saturated_collection = "chronicle events/archived eras"} else if c.promise_count >= game.MAX_PROMISES {all_active := true; for promise in c.promises[:c.promise_count] do if promise.status != .Active do all_active = false; if all_active do result.first_saturated_collection = "active promises"} else if c.historical_figure_count >= game.MAX_HISTORICAL_FIGURES {all_active := true; for figure in c.historical_figures[:c.historical_figure_count] do if !figure.active do all_active = false; if all_active do result.first_saturated_collection = "active historical figures"}
	if c.emergency_count > 0 do result.constitutional_emergencies = 1
	result.emergency_events = c.emergency_count
	result.first_emergency_season = c.first_emergency_season
	result.last_emergency_cause = c.last_emergency_cause
	result.ending = c.ending
	result.selected_value_pair = game.value_pair_index(
		c.values[0].kind,
		c.values[1].kind,
	); for value in c.values do result.value_tests[int(value.kind)] += value.tests
	result.ending_quality = c.ending_quality
	result.seasons = c.season
	result.final_active_ships = i32(
		game.active_ship_count(c),
	); result.final_hazards = c.hazard_count
	for promise in c.promises[:c.promise_count] do if promise.status == .Broken do result.final_broken_promises += 1
	for ship in c.ships[:c.ship_count] do if ship.pending_claim != "" do result.final_pending_claims += 1
	for ship in c.ships {
		if ship.departure == .Lost do result.ships_lost += 1
		if ship.departure == .Settlement do result.ships_settled += 1
		if ship.damage > 0 do result.ships_damaged += 1
		if ship.scar != .None do result.ships_scarred += 1
	}
	for ship in c.ships[:c.ship_count] do for memory_index in 0 ..< ship.memory_count do if ship.memories[memory_index].semantic_tags != game.Semantic_Tags(0) do result.tagged_memories += 1
	for figure in c.historical_figures[:c.historical_figure_count] {if figure.passage_actions <= 0 do continue; result.captains += 1; result.captain_reappearances += max(figure.passage_actions - 1, 0)}
	result.settlements = i32(c.settlement_count)
	causal_depth: [game.MAX_EVENTS]i32
	for &event, event_at in c.events[:c.event_count] {
		if event.cause_count >
		   0 {result.caused_events += 1; depth: i32 = 1; for cause in event.causes[:event.cause_count] {cause_at := game.event_index_by_sequence(c, cause.sequence); if cause_at >= 0 {depth = max(depth, causal_depth[cause_at] + 1); if c.events[cause_at].season < event.season do result.multi_season_callbacks += 1} else if !game.event_reference_exists(c, cause.sequence) {result.dangling_causal_references += 1}}; causal_depth[event_at] = depth; result.max_causal_depth = max(result.max_causal_depth, depth)}
		if event.cause_count > 1 do result.multi_cause_events += 1
		if event.kind == .Political_Relationship_Changed && event.value > 0 do result.relationship_reversals += 1
		if event.semantic_tags != game.Semantic_Tags(0) do result.tagged_events += 1
		if event.kind == .Settlement_Charter_Changed do result.charter_changes += 1
		if event.kind == .Archive_Established do result.archive_established += 1
		if event.kind == .Archive_Revelation do result.archive_revelations += 1
		if event.kind == .Need_Resolved &&
		   event.cause_sequence >
			   0 {cause_at := game.event_index_by_sequence(c, event.cause_sequence); if cause_at >= 0 && c.events[cause_at].kind == .Archive_Revelation do result.accountability_responses += 1}
		if event.kind == .Settlement_Charter_Changed && event.archive_id != 0 do result.archive_charters += 1
		if event.kind == .Need_Surfaced &&
		   event.figure_id !=
			   0 {result.figure_petitions += 1; figure_at := game.historical_figure_index(c, event.figure_id); if figure_at >= 0 && c.historical_figures[figure_at].passage_actions > 0 do result.captain_petitions += 1}
		if event.kind == .Historical_Figure_Changed do result.figure_events += 1
		if event.kind == .Precedent_Applied ||
		   event.kind ==
			   .Precedent_Contradicted {classification := int(event.value); if classification >= 0 && classification < len(result.law_classifications) do result.law_classifications[classification] += 1}
		if event.kind ==
		   .Precedent_Reviewed {review := int(event.value); if review >= 0 && review < len(result.law_reviews) do result.law_reviews[review] += 1}
		if event.kind == .Community_Memory_Changed do result.community_memories += 1
		if event.kind == .Autonomy_Triggered && event.community != 0 do result.community_triggers += 1
		if event.kind == .Autonomy_Triggered &&
		   event.cause_sequence >
			   0 {cause_at := game.event_index_by_sequence(c, event.cause_sequence); if cause_at >= 0 && c.events[cause_at].kind == .Promise_Changed do result.promise_recollections += 1}
		if event.account_status != .Uncontested do result.contested_reports += 1
		if event.kind == .Ship_Repaired {result.repair_outcomes += 1; result.projects_repair += 1}
		if event.kind ==
		   .Project_Completed {result.projects_supply += 1; if event.value == i32(game.Project_Kind.Maintenance_Recovery) do result.maintenance_recovery_projects += 1}
		if event.kind == .Settlement_Founded do result.projects_colony += 1
		if event.kind == .Archive_Established do result.projects_archive += 1
		if event.kind == .Local_Settlement || event.kind == .Community_Joined do result.migrations += 1
	}
	result.final_compute = game.capacity_available(c.capacities.compute)
	result.final_manpower = game.capacity_available(c.capacities.manpower)
	result.final_raw_materials = game.capacity_available(c.capacities.raw_materials)
	result.final_sustenance = i32(
		c.material_economy.fleet.stock.food,
	); result.final_industry = i32(c.material_economy.fleet.stock.manufactured_goods); result.final_knowledge = c.material_economy.knowledge.deployable_capacity; result.final_population = game.total_population(c)
	result.fleet_stock =
		c.material_economy.fleet.stock; result.fleet_season = c.material_economy.fleet.season; result.fleet_committed = c.material_economy.fleet.committed; result.fleet_recovered = c.material_economy.fleet.recovered; result.fleet_rewarded = c.material_economy.fleet.rewarded; result.seasons_below_floor = c.material_economy.fleet.seasons_below_floor; result.passage_net_supplies = i32(result.fleet_rewarded.supplies + result.fleet_recovered.supplies - result.fleet_committed.supplies)
	result.maintenance_demand =
		c.material_economy.fleet.maintenance_demand; result.maintenance_debt = c.material_economy.fleet.maintenance_debt; result.food_shortage_episodes = c.material_economy.food_shortage_response_count; result.sustainable_seasons = c.sustainable_seasons; result.economy_damage_episodes = c.economy_damage_episodes
	readiness := game.ending_readiness(
		c,
	); for eligible, i in readiness.eligible do if eligible do result.eligible_endings |= u32(1) << u32(i); result.unmet_ending_requirements = readiness.unmet_summary
	result.candidate_home_known =
		c.candidate_home_known; result.colony_package_ready = c.colony_package_ready
	result.world_surveys = i32(c.world_survey_count)
	for survey in c.world_surveys[:c.world_survey_count] {
		if survey.system_index >= 0 &&
		   int(survey.system_index) <
			   int(
				   c.galaxy.detailed_system_count,
			   ) {system := c.galaxy.detailed_systems[int(survey.system_index)].system; for star in system.stars[:system.star_count] do result.stars_surveyed_by_class[int(star.class)] += 1}
		result.survey_funnel.systems +=
			survey.funnel.systems; result.survey_funnel.stars += survey.funnel.stars; result.survey_funnel.planets += survey.funnel.planets; result.survey_funnel.terrestrial += survey.funnel.terrestrial; result.survey_funnel.conservative_hz += survey.funnel.conservative_hz; result.survey_funnel.stable += survey.funnel.stable; result.survey_funnel.atmosphere_retained += survey.funnel.atmosphere_retained; result.survey_funnel.water_bearing += survey.funnel.water_bearing; result.survey_funnel.long_term += survey.funnel.long_term; result.survey_funnel.settlement_capable += survey.funnel.settlement_capable
		result.survey_supply_cost += i32(
			survey.survey_cost.supplies,
		); result.candidate_classes[int(survey.profile.classification)] += 1
	}
	for settlement in c.settlements[:c.settlement_count] do if settlement.waived_founding_requirements != 0 do result.founding_waivers += 1
	result.final_food_capacity = c.material_economy.agriculture.cultivation
	for value in c.material_economy.knowledge.total_gained_by_source do result.knowledge_gained += value
	for value in c.material_economy.knowledge.total_spent_by_use do result.knowledge_spent += value
	for economy in c.settlement_economies.economies[:c.settlement_economies.count] do if economy.active {
		stock_values := [6]i64{economy.stock.food, economy.stock.goods, economy.stock.services, economy.stock.ships, economy.stock.people, economy.stock.knowledge}; for value in stock_values do if value < 0 || value > 1_000_000_000_000 do result.integer_bounds_clean = false
		result.economy_produced.food += economy.produced.food; result.economy_produced.goods += economy.produced.goods; result.economy_produced.services += economy.produced.services; result.economy_produced.ships += economy.produced.ships; result.economy_produced.people += economy.produced.people; result.economy_produced.knowledge += economy.produced.knowledge
		result.economy_consumed.food += economy.consumed.food; result.economy_consumed.goods += economy.consumed.goods; result.economy_consumed.services += economy.consumed.services; result.economy_consumed.ships += economy.consumed.ships; result.economy_consumed.people += economy.consumed.people; result.economy_consumed.knowledge += economy.consumed.knowledge
		result.economy_imported.food += economy.imports.food; result.economy_imported.goods += economy.imports.goods; result.economy_imported.services += economy.imports.services; result.economy_imported.ships += economy.imports.ships; result.economy_imported.people += economy.imports.people; result.economy_imported.knowledge += economy.imports.knowledge
		result.economy_exported.food += economy.exports.food; result.economy_exported.goods += economy.exports.goods; result.economy_exported.services += economy.exports.services; result.economy_exported.ships += economy.exports.ships; result.economy_exported.people += economy.exports.people; result.economy_exported.knowledge += economy.exports.knowledge
		result.economy_lost.food += economy.route_losses.food; result.economy_lost.goods += economy.route_losses.goods; result.economy_lost.services += economy.route_losses.services; result.economy_lost.ships += economy.route_losses.ships; result.economy_lost.people += economy.route_losses.people; result.economy_lost.knowledge += economy.route_losses.knowledge
	}
	result.trade_shipments = game.economy_stock_total(
		result.economy_exported,
	); result.trade_deliveries = game.economy_stock_total(result.economy_imported); result.trade_losses = game.economy_stock_total(result.economy_lost)
	a :=
		c.material_economy.agriculture; result.fleet_food_production = i64(a.last_production); result.fleet_food_consumption = i64(a.last_consumption); result.fleet_food_imports = i64(a.last_imports); result.fleet_food_exports = i64(a.last_exports); result.fleet_food_spoilage = i64(a.last_spoilage)
	result.final_rng_sequence = c.rng_sequence
	for settlement, i in c.settlements[:c.settlement_count] do for other in c.settlements[i + 1:c.settlement_count] do if settlement.id == other.id || settlement.name == other.name do result.duplicate_settlement_identities += 1
	for flow in c.settlement_economies.flows[:c.settlement_economies.flow_count] do if flow.shipped != flow.delivered + flow.lost do result.economic_flow_mismatches += 1
	result.productive_regions, result.changed_trade_dependencies =
		bot_regional_economy_diagnostics(c)
	for exposure in c.material_economy.essential do if exposure.exposed && !exposure.acknowledged do result.overdue_essential_exposures += 1
	active_knowledge_backing :=
		false; for commitment in c.material_economy.commitments do if commitment.active && !commitment.suspended do active_knowledge_backing = true
	result.knowledge_bounded_or_explained =
		c.material_economy.knowledge.deployable_capacity <= 40 || active_knowledge_backing
	signature :=
		u64(game.fleet_supply(c) & 255) |
		u64(game.fleet_materials(c) & 255) << 8 |
		u64(c.material_economy.knowledge.deployable_capacity & 255) << 16 |
		u64(c.strategic.cohesion & 127) << 24 |
		u64(c.strategic.cohesion & 127) << 31 |
		u64(c.front_count & 7) << 38 |
		u64(c.settlement_count & 7) << 41
	for ship in c.ships[:c.ship_count] do signature = (signature ~ (u64(ship.damage + 1) * 0x9e3779b97f4a7c15)) + (u64(ship.departure) << 3) ~ u64(game.ship_impairment_total(ship.impairments) & 15) * 0x94d049bb133111eb
	result.state_signature = signature
	for front in c.fronts[:c.front_count] do if !front.dormant || front.transformation != .None do result.qualifying_fronts += 1
	for record in c.dark_strategy_records[:c.dark_strategy_record_count] do if record.resolved >= 2 && record.last_event != 0 do result.region_revisit_mutated = true
	result.preserved_over_512 =
		c.event_sequence > 512 &&
		c.archived_era_count > 0 &&
		c.event_count > 0 &&
		c.events[c.event_count - 1].sequence == c.event_sequence
	if c.story_tempo != .Volatile do for t in result.telemetry[:result.telemetry_count] do if t.major_beats > 1 do result.tempo_stack_violations += 1
	if config.story_report {
		fmt.printf(
			"STORY events:%d archived-eras:%d settlements:%d ships-lost:%d emergencies:%d\n",
			c.event_sequence,
			c.archived_era_count,
			c.settlement_count,
			result.ships_lost,
			c.emergency_count,
		)
		for event in c.events[:c.event_count] do fmt.printf("STORY E%03d S%02d %v %s\n", event.sequence, event.season, event.kind, event.detail)
	}
	finalize_action_dominance(&result)
	if config.measure_phases do result.timings.finalize_ms = time.duration_seconds(time.tick_since(finalize_started)) * 1000
	return result
}
