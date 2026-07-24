package main

import game "../packages/game"
import "core:testing"

Bot_Action_Family :: enum {
	None,
	Need,
	Emergency,
	Project,
	Passage,
}
Bot_Action_Kind :: enum {
	None,
	Resolve_Need,
	Mitigate_Need,
	Defer_Need,
	Publish_Discovery,
	Use_Reserves,
	Hold_Forum,
	Queue_Project,
}

Bot_Failure_Kind :: enum {
	None,
	Passage_Begin,
	Passage_Conclude,
	Planner_Action,
	No_Progress,
	Iteration_Limit,
}

Bot_Action_Candidate :: struct {
	family:                 Bot_Action_Family,
	kind:                   Bot_Action_Kind,
	target:                 int,
	project:                game.Project_Kind,
	ship:                   game.Ship_ID,
	attention_cost:         i32,
	immediate_cost:         i32,
	legal:                  bool,
	score, projected_delta: i32,
	finale_quality_delta:   i32,
	tie_break:              u64,
}

BOT_MAX_ACTION_CANDIDATES :: 128
BOT_MAX_EVALUATED_CANDIDATES :: 24

bot_record_failure :: proc(
	c: ^game.Campaign,
	result: ^Bot_Run_Result,
	kind: Bot_Failure_Kind,
	family := Bot_Action_Family.None,
	action := Bot_Action_Kind.None,
	target: int = -1,
	blocker: string = "",
) {
	result.invalid_actions += 1
	if result.first_failure_kind != .None do return
	result.first_failure_kind = kind
	result.first_failure_family = family
	result.first_failure_action = action
	result.first_failure_target = target
	result.first_failure_situation_phase = c.current_situation.phase
	result.first_failure_passage_phase = c.passage.phase
	result.first_failure_blocker = blocker
}

bot_active_need_count :: proc(c: ^game.Campaign) -> i32 {n: i32; for need in c.needs do if need.active do n += 1
	return n}
bot_ship_damage_total :: proc(c: ^game.Campaign) -> i32 {n: i32; for ship in c.ships[:c.ship_count] do if ship.active do n += ship.damage
	return n}
bot_exposed_essential_count :: proc(c: ^game.Campaign) -> i32 {game.detect_essential_exposure(c)
	n: i32
	for exposure in c.material_economy.essential do if exposure.exposed && !exposure.acknowledged do n += 1
	return n}

bot_state_score :: proc(c: ^game.Campaign, profile: Bot_Profile) -> i32 {
	w := bot_weights(profile); p := game.strategic_pressure(c); r := game.ending_readiness(c)
	score := p.reserve_coverage * 3 + p.capacity_margin * 5 + p.cohesion * 2
	score -= bot_active_need_count(c) * (w.needs + 8)
	score -= bot_exposed_essential_count(c) * (w.safety + 18)
	score -= bot_ship_damage_total(c) * (w.safety + 3)
	score -= c.material_economy.fleet.maintenance_debt * (w.safety / 2 + 3)
	score -= r.unresolved_hazards * (w.safety + 5) + r.broken_promises * (w.rescue + 8)
	score += r.fleet_food_coverage * (w.safety + 2) + r.viable_settlements * w.settlement
	score += r.passage_objectives * w.exploration + r.transformation_records * w.science
	score += r.sustainable_seasons * (w.projects / 2 + 2)
	if p.emergency do score -= 300
	if c.ending_finale.active {
		// Identity is already locked. The planner grades continuity and never
		// receives credit for changing to a different ending path.
		quality := game.ending_quality(c, c.ending_finale.ending)
		score += i32(quality) * 1000
		#partial switch c.ending_finale.ending {
		case .Nomadic_Fleet:
			score -= c.material_economy.fleet.maintenance_debt * 20
			score += r.sustainable_seasons * 30
		case .New_Home, .Harbor_Network, .Federation:
			score += r.sustainable_settlements * 80
		case .Transformed:
			score += r.completed_undertakings * 50 + r.sustainable_seasons * 30
		case .Fragmented_Survival:
			score += i32(game.active_ship_count(c)) * 15
		case .In_Progress:
		}
	}
	return score
}

bot_apply_candidate :: proc(c: ^game.Campaign, a: Bot_Action_Candidate) -> bool {
	switch a.kind {
	case .Resolve_Need:
		return game.resolve_need(c, a.target)
	case .Mitigate_Need:
		return game.mitigate_need(c, a.target)
	case .Defer_Need:
		return game.defer_need(c, a.target)
	case .Publish_Discovery:
		return game.publish_discovery(c)
	case .Use_Reserves:
		return game.use_contingency_reserves(c)
	case .Hold_Forum:
		return game.hold_community_forum(c)
	case .Queue_Project:
		return game.queue_project(c, a.project, a.ship)
	case .None:
	}
	return false
}

bot_candidate_tie_break :: proc(c: ^game.Campaign, a: Bot_Action_Candidate) -> u64 {
	return(
		c.initial_seed ~
		(u64(c.season + 1) * 0x9e3779b97f4a7c15) ~
		(u64(a.kind) * 0x517cc1b727220a95) ~
		u64(a.target + 1) ~
		(u64(a.project) << 40) ~
		u64(a.ship) \
	)
}

bot_project_immediate_cost :: proc(kind: game.Project_Kind) -> i32 {s := game.fleet_project_cost(
		kind,
	)
	return i32(
		s.raw_materials + s.manufactured_goods + s.equipment + s.propellant + s.supplies + s.services,
	)}

bot_append_candidate :: proc(
	c: ^game.Campaign,
	out: ^[BOT_MAX_ACTION_CANDIDATES]Bot_Action_Candidate,
	count: ^int,
	a_value: Bot_Action_Candidate,
) {
	if count^ >= len(out) do return
	a := a_value; a.tie_break = bot_candidate_tie_break(c, a); out[count^] = a; count^ += 1
}

bot_generate_candidates :: proc(
	c: ^game.Campaign,
	attention: i32,
	allow_emergency, allow_project: bool,
	out: ^[BOT_MAX_ACTION_CANDIDATES]Bot_Action_Candidate,
) -> int {
	count := 0
	for need, i in c.needs {
		if !need.active do continue
		if attention >= 2 do bot_append_candidate(c, out, &count, {family = .Need, kind = .Resolve_Need, target = i, attention_cost = 2})
		if attention >= 1 do bot_append_candidate(c, out, &count, {family = .Need, kind = .Mitigate_Need, target = i, attention_cost = 1})
		if attention >= 1 && (need.kind == .Representation || need.kind == .Settlement_Demand || need.kind == .Settlement_Charter) do bot_append_candidate(c, out, &count, {family = .Need, kind = .Defer_Need, target = i, attention_cost = 1})
	}
	pressure := game.forecast_emergency_pressure(c)
	if allow_emergency && attention >= 1 && pressure.critical {
		bot_append_candidate(
			c,
			out,
			&count,
			{
				family = .Emergency,
				kind = .Publish_Discovery,
				attention_cost = 1,
				immediate_cost = 8,
			},
		)
		bot_append_candidate(
			c,
			out,
			&count,
			{family = .Emergency, kind = .Use_Reserves, attention_cost = 1, immediate_cost = 8},
		)
		bot_append_candidate(
			c,
			out,
			&count,
			{family = .Emergency, kind = .Hold_Forum, attention_cost = 1, immediate_cost = 5},
		)
	}
	if allow_project && attention >= 1 {
		for kind in game.Project_Kind {
			if kind == .None || kind == .Repair do continue
			already_active :=
				false; for project in c.projects do if project.active && project.kind == kind do already_active = true
			if already_active || !game.project_preview(c, kind).valid do continue
			bot_append_candidate(
				c,
				out,
				&count,
				{
					family = .Project,
					kind = .Queue_Project,
					project = kind,
					attention_cost = 1,
					immediate_cost = bot_project_immediate_cost(kind),
				},
			)
		}
		for ship in c.ships[:c.ship_count] do if ship.active && ship.damage > 0 && game.project_preview(c, .Repair, ship.id).valid do bot_append_candidate(c, out, &count, {family = .Project, kind = .Queue_Project, project = .Repair, ship = ship.id, attention_cost = 1, immediate_cost = bot_project_immediate_cost(.Repair)})
	}
	return count
}

bot_forecast_score :: proc(c: ^game.Campaign, profile: Bot_Profile) -> i32 {
	// Candidate selection already applies each action to an isolated snapshot.
	// Advancing a full season here (and again for every candidate) nests the
	// complete simulation inside the planner and makes some valid campaigns
	// appear to hang. The current state is the common, deterministic baseline.
	return bot_state_score(c, profile)
}

bot_evaluate_candidate :: proc(
	c: ^game.Campaign,
	profile: Bot_Profile,
	baseline: i32,
	a: ^Bot_Action_Candidate,
) -> bool {
	s := game.campaign_snapshot(c); defer game.campaign_destroy_heap(s)
	before_quality :=
		c.ending_finale.active ? int(game.ending_quality(c, c.ending_finale.ending)) : 0
	if !bot_apply_candidate(s, a^) do return false
	a.legal = true
	// Delayed projects need completion credit even when one season does not
	// finish them; otherwise every immediate response dominates investment.
	completion_credit := i32(0)
	if a.family ==
	   .Project {completion_credit = 12 + bot_weights(profile).projects * 2; if a.project == .Colony_Package do completion_credit += bot_weights(profile).settlement * 3; if a.project == .Analyze_Discovery || a.project == .Restore_Archive do completion_credit += bot_weights(profile).science * 2; if a.project == .Maintenance_Recovery do completion_credit += c.material_economy.fleet.maintenance_debt * (bot_weights(profile).safety + 12)}
	a.score = bot_state_score(s, profile) + completion_credit - a.immediate_cost
	a.projected_delta = a.score - baseline
	if c.ending_finale.active do a.finale_quality_delta = i32(game.ending_quality(s, c.ending_finale.ending)) - i32(before_quality)
	return true
}

bot_choose_candidate :: proc(
	c: ^game.Campaign,
	profile: Bot_Profile,
	attention: i32,
	allow_emergency, allow_project: bool,
	result: ^Bot_Run_Result,
) -> (
	Bot_Action_Candidate,
	bool,
) {
	items: [BOT_MAX_ACTION_CANDIDATES]Bot_Action_Candidate
	count := bot_generate_candidates(c, attention, allow_emergency, allow_project, &items)
	result.planner_candidates += i64(count)
	baseline := bot_forecast_score(c, profile)
	best, runner := Bot_Action_Candidate {
			score = -0x3fffffff,
		}, Bot_Action_Candidate {
			score = -0x3fffffff,
		}; found := false
	for i in 0 ..< min(count, BOT_MAX_EVALUATED_CANDIDATES) {
		a := &items[i]; if !bot_evaluate_candidate(c, profile, baseline, a) do continue
		better := a.score > best.score || a.score == best.score && a.tie_break < best.tie_break
		if better {runner = best; best = a^; found = true} else if a.score > runner.score || a.score == runner.score && a.tie_break < runner.tie_break do runner = a^
	}
	if !found do return {}, false
	result.planner_chosen_score = best.score; result.planner_runner_up_score = runner.score
	result.planner_projected_delta =
		best.projected_delta; result.planner_finale_quality_delta += best.finale_quality_delta
	if runner.score > -0x3fffffff do result.planner_score_margin_total += i64(best.score - runner.score)
	return best, true
}

bot_plan_discretionary :: proc(
	c: ^game.Campaign,
	profile: Bot_Profile,
	attention: i32,
	result: ^Bot_Run_Result,
	projects_allowed: bool = true,
) {
	allow_emergency, allow_project :=
		true, projects_allowed; acted := false; remaining := attention
	for remaining > 0 {
		candidate, ok := bot_choose_candidate(
			c,
			profile,
			remaining,
			allow_emergency,
			allow_project,
			result,
		)
		if !ok || candidate.projected_delta <= 0 do break
		if !bot_apply_candidate(c, candidate) {
			replacement, replacement_ok := bot_choose_candidate(
				c,
				profile,
				remaining,
				allow_emergency,
				allow_project,
				result,
			)
			if !replacement_ok || replacement.projected_delta <= 0 do break
			if !bot_apply_candidate(c, replacement) {
				bot_record_failure(
					c,
					result,
					.Planner_Action,
					replacement.family,
					replacement.kind,
					replacement.target,
					"live candidate rejected after deterministic replanning",
				)
				break
			}
			candidate = replacement
		}
		acted = true; remaining -= candidate.attention_cost
		result.planner_action_choices[int(candidate.family)] += 1
		if candidate.family == .Emergency do allow_emergency = false
		if candidate.family == .Project do allow_project = false
	}
	if !acted do result.planner_no_positive_seasons += 1
}

bot_memory_observe :: proc(c: ^game.Campaign, memory: ^Bot_Strategy_Memory) {
	food, repair, settlement := false, false, false
	for need in c.needs do if need.active {if need.kind == .Sustenance_Shortfall do food = true; if need.kind == .Ship_Repair do repair = true; if need.kind == .Settlement_Demand || need.kind == .Settlement_Charter do settlement = true}
	if food {memory.sustenance_shortfalls = min(memory.sustenance_shortfalls + 1, 3)} else {memory.sustenance_shortfalls = max(memory.sustenance_shortfalls - 1, 0)}
	if repair {memory.ship_repairs = min(memory.ship_repairs + 1, 3)} else {memory.ship_repairs = max(memory.ship_repairs - 1, 0)}
	if settlement {memory.settlement_demands = min(memory.settlement_demands + 1, 3)} else {memory.settlement_demands = max(memory.settlement_demands - 1, 0)}
	if !game.forecast_emergency_pressure(c).critical do memory.temporary_relief_uses = max(memory.temporary_relief_uses - 1, 0)
}

bot_passage_role_value :: proc(role: game.Role, purpose: game.Dark_Contract_Purpose) -> i32 {
	#partial switch purpose {
	case .Ecological_Survey:
		if role == .Survey || role == .Agriculture || role == .Archive do return 18
	case .Stabilize_Relay:
		if role == .Foundry || role == .Escort || role == .Survey do return 18
	case .Verify_Correspondence:
		if role == .Archive || role == .Survey || role == .Hospital do return 18
	case .Map_Unknown_Door:
		if role == .Survey || role == .Archive || role == .Escort do return 18
	}
	return 3
}

bot_select_passage_crew :: proc(
	c: ^game.Campaign,
	contract: ^game.Dark_Contract,
	out: ^[3]int,
) -> (bool, int) {
	available: [game.MAX_SHIPS]int; count := 0
	for ship, i in c.ships[:c.ship_count] {
		if !ship.active do continue
		if c.compact.active.status == .Planning || c.compact.active.status == .Operating {
			if !game.compact_ship_is_seconded(c, ship.id) do continue
		} else if ship.committed {
			continue
		}
		available[count] = i
		count += 1
	}
	if count <= 0 do return false, 0
	if c.compact.active.status == .Planning || c.compact.active.status == .Operating {
		selected_count := min(count, len(out))
		for i in 0 ..< selected_count do out[i] = available[i]
		preview := game.dark_expedition_preview(c, contract, out[:selected_count])
		return preview.valid, selected_count
	}
	if count < 3 do return false, 0
	best_score := i32(-0x3fffffff); best_key := ~u64(0)
	for a in 0 ..< count - 2 do for b in a + 1 ..< count - 1 do for d in b + 1 ..< count {
		indices := [3]int{available[a], available[b], available[d]}; preview := game.dark_expedition_preview(c, contract, indices[:]); if !preview.valid do continue
		score: i32; roles: u64
		for index in indices {ship := c.ships[index]; score += bot_passage_role_value(ship.role, contract.purpose) + ship.experience * 2 - ship.damage * 14 - ship.dark_field_scars * 12; if ship.scar != .None do score -= 5; bit := u64(1) << u64(ship.role); if roles & bit == 0 do score += 8; roles |= bit
			active_role := 0; for other in c.ships[:c.ship_count] do if other.active && other.role == ship.role do active_role += 1; if active_role == 1 do score -= 22
		}
		key := u64(c.ships[indices[0]].id) << 32 | u64(c.ships[indices[1]].id) << 16 | u64(c.ships[indices[2]].id)
		if score > best_score || score == best_score && key < best_key {best_score = score; best_key = key; out^ = indices}
	}
	return best_score > -0x3fffffff, 3
}

@(test)
planner_candidate_evaluation_is_deterministic_and_does_not_mutate_live_campaign :: proc(
	t: ^testing.T,
) {
	c := game.new_campaign_seeded_heap(6101); defer game.campaign_destroy_heap(c); c.needs[0] = {
		kind     = .Sustenance_Shortfall,
		active   = true,
		cost     = 4,
		deadline = c.season,
		detail   = "Food stocks fell below the seasonal requirement.",
	}
	before_events, before_reserves := c.event_count, game.fleet_supply(c)
	a := Bot_Action_Candidate {
		family         = .Need,
		kind           = .Resolve_Need,
		target         = 0,
		attention_cost = 2,
	}; b := a
	baseline := bot_forecast_score(c, .Strategist)
	testing.expect(
		t,
		bot_evaluate_candidate(c, .Strategist, baseline, &a),
	); testing.expect(t, bot_evaluate_candidate(c, .Strategist, baseline, &b))
	testing.expect_value(
		t,
		a,
		b,
	); testing.expect_value(t, c.event_count, before_events); testing.expect_value(t, game.fleet_supply(c), before_reserves); testing.expect(t, c.needs[0].active)
}

@(test)
planner_memory_tracks_recent_pressure_and_forgets_resolved_work :: proc(t: ^testing.T) {
	c := game.new_campaign_seeded_heap(
		6102,
	); defer game.campaign_destroy_heap(c); memory := Bot_Strategy_Memory {
		sustenance_shortfalls = 2,
		ship_repairs          = 2,
		settlement_demands    = 2,
		temporary_relief_uses = 2,
	}
	bot_memory_observe(
		c,
		&memory,
	); testing.expect_value(t, memory.sustenance_shortfalls, i32(1)); testing.expect_value(t, memory.ship_repairs, i32(1)); testing.expect_value(t, memory.settlement_demands, i32(1)); testing.expect_value(t, memory.temporary_relief_uses, i32(1))
	c.needs[0] = {
		kind   = .Ship_Repair,
		active = true,
		cost   = 4,
	}; bot_memory_observe(
		c,
		&memory,
	); testing.expect_value(t, memory.ship_repairs, i32(2)); testing.expect_value(t, memory.sustenance_shortfalls, i32(0))
}

@(test)
planner_uses_available_attention_when_positive_legal_work_exists :: proc(t: ^testing.T) {
	for profile in Bot_Profile {
		c := game.new_campaign_seeded_heap(6200 + u64(profile)); result := Bot_Run_Result{}
		c.needs[0] = {
			kind     = .Sustenance_Shortfall,
			active   = true,
			cost     = 2,
			deadline = c.season,
			detail   = "Food stocks fell below the seasonal requirement.",
		}
		bot_plan_discretionary(c, profile, 2, &result, false)
		testing.expect(
			t,
			!c.needs[0].active || c.needs[0].response != .Open,
		); testing.expect(t, result.planner_action_choices[int(Bot_Action_Family.Need)] > 0); testing.expect_value(t, result.invalid_actions, i32(0)); game.campaign_destroy_heap(c)
	}
}

@(test)
finale_scoring_uses_locked_identity_quality :: proc(t: ^testing.T) {
	c := game.new_campaign_seeded_heap(
		6104,
	); defer game.campaign_destroy_heap(c); c.ending_finale = {
		active         = true,
		ending         = .Nomadic_Fleet,
		started_season = c.season,
		ends_season    = c.season + 3,
	}; c.material_economy.fleet.maintenance_debt = 10
	base := bot_state_score(
		c,
		.Strategist,
	); c.material_economy.fleet.maintenance_debt = 0; improved := bot_state_score(c, .Strategist)
	testing.expect(
		t,
		improved > base,
	); testing.expect_value(t, c.ending_finale.ending, game.Ending.Nomadic_Fleet)
}

@(test)
passage_crew_selection_uses_objective_roles_and_avoids_damaged_hulls :: proc(t: ^testing.T) {
	c := game.new_campaign_seeded_heap(
		6105,
	); defer game.campaign_destroy_heap(c); for &ship in c.ships[:c.ship_count] do ship.damage = 3
	wanted := [3]game.Role {
		.Survey,
		.Archive,
		.Escort,
	}; for role, i in wanted {for &ship in c.ships[:c.ship_count] do if ship.role == role {ship.damage = 0; ship.experience = i32(4 - i); break}}
	contract := game.default_passage_contract(); contract.purpose = .Map_Unknown_Door; crew: [3]int
	selected, selected_count := bot_select_passage_crew(c, &contract, &crew)
	testing.expect(
		t,
		selected,
	)
	testing.expect_value(t, selected_count, 3)
	for index in crew do testing.expect_value(t, c.ships[index].damage, i32(0))
}
