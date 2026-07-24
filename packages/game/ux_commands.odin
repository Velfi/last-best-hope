package game

import "core:fmt"
import "core:testing"
Manifest_Preview :: struct {
	valid:          bool,
	message:        string,
	pattern:        string,
	ships_selected: int,
	roles_covered:  int,
	return_margin:  i32,
	high_risk:      bool,
}

Setup_Choice_Preview :: struct {
	classification: string,
	effect:         string,
	persistent:     bool,
}

setup_choice_preview :: proc(
	d: ^Civilization_Setup_Draft,
	step: int,
	index: int = -1,
) -> Setup_Choice_Preview {
	r: Setup_Choice_Preview
	switch step {
	case 0:
		r.classification = "OPEN CHRONICLE"
		r.effect = "Seasons continue until the player concludes the record or the traveling fleet dissolves."
	case 1:
		if index < 0 || index >= len(d.choices) do return r
		r.classification =
			index < 2 ? "IDENTITY · STORY + STARTING FLEET" : index < 4 ? "CAPABILITY · STARTING FLEET" : "VALUE · STARTING FLEET + FUTURE TESTS"
		r.effect = setup_attribute_effect(d, index)
		r.persistent = true
	case 2:
		r.classification = "PUBLIC RECORD"
		r.effect = "Sets the fleet's public account of the Loss; later evidence may contest it."
		r.persistent = true
	case 3:
		r.classification = "IMMEDIATE INHERITANCE"
		switch d.preserved_index {
		case 0:
			r.effect = "+10 Sustenance · Seed and Genetic Banks integrity 100"
		case 1:
			r.effect = "+12 Knowledge · Scientific Corpora integrity 100"
		case 2:
			r.effect = "+8 Cohesion · two Cultural Archives integrity 100"
		case 3:
			r.effect = "+10 Industry · Machine Memories integrity 100"
		}
		r.persistent = true
	case 4:
		r.classification = "FOUNDING DECISION"
		a, b :=
			setup_value_kind(d, 0),
			setup_value_kind(d, 1); scenario := founding_value_scenario(a, b)
		r.effect =
			d.founding_choice == 0 ? founding_value_option(a) : d.founding_choice == 1 ? founding_value_option(b) : fmt.tprintf("Refer %s to the first council without enacting a law.", scenario.title)
		r.persistent = true
	}
	return r
}

guidance_advance :: proc(c: ^Campaign, dismiss := false) {
	if dismiss do c.guidance_step = 9
	else do c.guidance_step = min(c.guidance_step + 1, 9)
}

Project_Preview :: struct {
	valid:                                  bool,
	message, target, outcome, cost_summary: string,
	reserve_cost, duration:                 i32,
	resulting_damage:                       i32,
	available_slot:                         int,
}

project_preview :: proc(c: ^Campaign, kind: Project_Kind, ship := Ship_ID(0)) -> Project_Preview {
	r := Project_Preview {
		available_slot = -1,
	}
	switch kind {
	case .Repair:
		r.reserve_cost = 8; r.duration = 1; r.outcome = "Repairs 3 Damage."
	case .Refit:
		r.reserve_cost = 15; r.duration = 1; r.outcome = "Raises ship Power by 2."
	case .Habitat_Expansion:
		r.reserve_cost = 18; r.duration = 1; r.outcome = "Raises Fleet Cohesion by 5."
	case .Analyze_Discovery:
		r.reserve_cost = 6; r.duration = 1; r.outcome = "Raises deployable analysis by 12."
	case .Colony_Package:
		r.reserve_cost = 20; r.duration = 2
		r.outcome = "Prepares authority and equipment for settlement."
	case .Restore_Archive:
		r.reserve_cost = 14; r.duration = 1
		r.outcome = "Raises deployable analysis by 6 and Fleet Cohesion by 4."
	case .Produce_Reserves:
		r.reserve_cost = 10; r.duration = 1; r.outcome = "Produces 18 Expedition Supplies."
	case .Maintenance_Recovery:
		r.reserve_cost = 9; r.duration = 1
		r.outcome = "Pays up to 2 Maintenance Debt without repairing damage."
	case .None:
		r.message = "select a project"; return r
	}
	for project, i in c.projects do if !project.active {r.available_slot = i; break}
	if kind == .Repair || kind == .Refit {
		i := ship_index(c, ship)
		if i < 0 {r.message = "select an available ship"; return r}
		r.target = c.ships[i].name
		r.resulting_damage = kind == .Repair ? max(c.ships[i].damage - 3, 0) : c.ships[i].damage
	} else do r.target = "Fleet"
	if r.available_slot < 0 {r.message = "all three project slots are committed"; return r}
	cost := fleet_project_cost(kind)
	forecast := fleet_spend_forecast(
		c,
		cost,
		.Routine,
	); r.cost_summary = fmt.tprintf("%s · %s · %s · recovery %d seasons", fleet_stock_label(cost), forecast.first, forecast.second, forecast.recovery_seasons)
	ok, _, reason := fleet_stock_spend_preview(
		c,
		cost,
		.Routine,
	); if !ok {r.message = reason; return r}
	r.valid = true
	r.message = "Named fleet stocks are committed immediately."
	return r
}


Dark_Expedition_Preview :: struct {
	valid:          bool,
	message:        string,
	ships_selected: int,
	recommendation: Dark_Strategy_Recommendation,
}
dark_expedition_preview :: proc(
	c: ^Campaign,
	contract: ^Dark_Contract,
	ships: []int,
) -> Dark_Expedition_Preview {r: Dark_Expedition_Preview; r.ships_selected = len(ships)
	r.valid, r.message = validate_contract(c, contract, ships)
	if r.valid do r.recommendation = recommend_dark_strategy(c, contract)
	return r}

Season_Preview :: struct {
	active_situation, expiring_promises, active_commitments, precedent_reviews: int,
	warning:                                                                    string,
	situation_summary, promise_summary, commitment_summary:                     string,
}

season_preview :: proc(c: ^Campaign) -> Season_Preview {
	r: Season_Preview
	if public_question_open(
		&c.public_politics.open,
	) {r.active_situation = 1; r.situation_summary = c.public_politics.open.title}
	if r.active_situation == 0 &&
	   c.current_situation.kind != .None &&
	   c.current_situation.phase != .Resolved {
		r.active_situation = 1
		r.situation_summary = c.current_situation.title
	}
	for promise in c.promises[:c.promise_count] do if promise.status == .Active && promise.deadline <= c.season + 1 {r.expiring_promises += 1; if r.promise_summary == "" do r.promise_summary = promise.detail}
	for commitment in c.capacity_commitments do if commitment.active {r.active_commitments += 1; if r.commitment_summary == "" do r.commitment_summary = commitment.detail}
	for case_record in c.precedent_cases[:c.precedent_case_count] do if case_record.status == .Pending && case_record.review_season <= c.season do r.precedent_reviews += 1
	if r.active_situation > 0 do r.warning = "A fleet situation requires a decision before the season can advance."
	else if r.precedent_reviews > 0 do r.warning = "A constitutional case requires review before the season can advance."
	else if r.expiring_promises > 0 do r.warning = "A promise expires next season."
	else do r.warning = "The fleet is ready to advance."
	return r
}

Game_Command_Kind :: enum {
	Advance_Season,
	Resolve_Food_Shortage,
	Conclude_Chronicle,
	Convert_To_Endless,
	Resolve_Economy_Loss,
	Acknowledge_Stranded_Outcome,
	Acknowledge_Habitable_Discovery,
	Advance_Situation,
	Resolve_Situation,
	Resolve_Precedent_Case,
	Resolve_Need,
	Mitigate_Need,
	Defer_Need,
	Toggle_Compact_Offer,
	Select_Compact_Approach,
	Accept_Compact_Call,
	Resolve_Compact_Counsel,
	Queue_Project,
	Start_Research,
	Suspend_Research,
	Begin_Passage,
	Plot_Dark_Course,
	Cross_Dark_Door,
	Plot_Normal_Course,
	Set_Dark_Strategy,
	Set_Safe_Endpoint,
	Conclude_Passage,
	Found_Settlement,
	Begin_Settlement_Proposal,
	Set_Settlement_Procedure,
	Set_Settlement_Disclosure,
	Set_Settlement_Charter,
	Set_Settlement_Charter_Participation,
	Set_Settlement_Obligation,
	Set_Settlement_Ship,
	Set_Settlement_Community,
	Set_Settlement_Institution,
	Set_Settlement_Archive,
	Open_Settlement_Deliberation,
	Revise_Settlement_Proposal,
	Finalize_Settlement_Proposal,
	Withdraw_Settlement_Proposal,
	Choose_Interaction,
	Resolve_Collision,
}
Game_Command :: struct {
	kind:                              Game_Command_Kind,
	index:                             int,
	target:                            int,
	amount:                            i32,
	project:                           Project_Kind,
	research:                          Research_Kind,
	precedent:                         Precedent_Kind,
	ship:                              Ship_ID,
	contract:                          Dark_Contract,
	ships:                             [MAX_EXPEDITION_SHIPS]int,
	ship_count:                        int,
	dark_course:                       Dark_Course,
	strategy:                          Dark_Strategy_Profile,
	safe_endpoint:                     Dark_Safe_Endpoint,
	relay_id:                          u64,
	distance_kpc, velocity_fraction_c: f64,
	flag:                              bool,
	community:                         Community_ID,
	name:                              string,
	destination:                       string,
	procedure:                         Settlement_Procedure,
	obligation:                        Continuing_Obligation,
	collision_id:                      Collision_ID,
	collision_command_id:              Collision_Command_ID,
}
Game_Command_Result :: struct {
	ok:      bool,
	message: string,
}

execute_command :: proc(c: ^Campaign, command: Game_Command) -> Game_Command_Result {
	r: Game_Command_Result
	switch command.kind {
	case .Advance_Season:
		before := c.season
		advance_season(c)
		r.ok = c.season != before
		if r.ok && !public_question_active(&c.public_politics.open) do _ = surface_interaction(c)
		r.message =
			r.ok ? "season advanced" : c.stranded_outcome_notice_pending ? "acknowledge the relay expedition's decision first" : c.material_economy.food_shortage_response_pending ? "resolve the food shortage first" : "resolve the current situation or Passage first"
	case .Resolve_Food_Shortage:
		r.ok = apply_food_shortage_command(c, Food_Shortage_Command(command.target))
		r.message =
			r.ok ? "food allocation entered the chronicle" : "that food response is unavailable"
	case .Conclude_Chronicle:
		r.ok = conclude_chronicle(c)
		r.message =
			r.ok ? (c.ending == .In_Progress ? "three-season finale begun" : "chronicle concluded") : c.ending_finale.active && c.season < c.ending_finale.ends_season ? "complete all three finale seasons first" : "resolve the current situation or Passage first"
	case .Convert_To_Endless:
		r.ok = convert_chronicle_to_endless(c)
		r.message = r.ok ? "chronicle converted to Endless" : "conversion is unavailable"
	case .Resolve_Economy_Loss:
		r.ok = resolve_economy_loss_decision(c, command.flag)
		r.message =
			r.ok ? "maintenance exposure resolved" : "that preservation response is unavailable"
	case .Acknowledge_Stranded_Outcome:
		r.ok = acknowledge_stranded_outcome(c)
		r.message =
			r.ok ? "the expedition's decision entered the chronicle" : "no relay expedition decision awaits acknowledgment"
	case .Acknowledge_Habitable_Discovery:
		r.ok = acknowledge_candidate_celebration(c)
		r.message =
			r.ok ? "the confirmed world entered the fleet record" : "no confirmed world awaits acknowledgment"
	case .Advance_Situation:
		r.ok = advance_interaction(c)
		r.message = r.ok ? "situation advanced" : "situation cannot advance"
	case .Resolve_Situation:
		r.ok = resolve_interaction(c, command.index)
		r.message = r.ok ? "choice entered the chronicle" : "choice is unavailable"
	case .Resolve_Precedent_Case:
		r.ok = review_precedent_case(
			c,
			Precedent_Case_ID(command.index),
			Precedent_Review(command.target),
			active_precedent_id(c, command.precedent),
			Precedent_Interpretation(command.amount),
		)
		r.message =
			r.ok ? "constitutional review entered the chronicle" : "that review cannot be resolved"
	case .Resolve_Need:
		r.ok = resolve_need(c, command.index)
		r.message = r.ok ? "need resolved" : "need cannot be resolved"
	case .Mitigate_Need:
		r.ok = mitigate_need(c, command.index)
		r.message = r.ok ? "need mitigated" : "need cannot be mitigated"
	case .Defer_Need:
		r.ok = defer_need(c, command.index)
		r.message = r.ok ? "need deferred" : "need cannot be deferred"
	case .Toggle_Compact_Offer:
		r.ok = compact_toggle_offer(c, Compact_Call_ID(command.index), command.target)
		r.message = r.ok ? "secondment selection changed" : "that secondment offer is unavailable"
	case .Select_Compact_Approach:
		r.ok = compact_select_approach(c, Compact_Call_ID(command.index), command.target)
		r.message = r.ok ? "operational approach selected" : "that approach is unavailable"
	case .Accept_Compact_Call:
		r.ok = compact_accept_call(c, Compact_Call_ID(command.index))
		r.message =
			r.ok ? "good-faith undertaking accepted" : "the call or selected contributions cannot support an undertaking"
	case .Resolve_Compact_Counsel:
		r.ok = compact_resolve_counsel(c, command.target)
		r.message =
			r.ok ? "counsel and the sponsor's autonomous response entered the Chronicle" : "that counsel is unavailable"
	case .Queue_Project:
		r.ok = queue_project(c, command.project, command.ship)
		r.message = r.ok ? "project queued" : "project cannot be queued"
	case .Start_Research:
		r.ok = start_research_program(c, command.research, command.ship)
		r.message =
			r.ok ? "research program entered the fleet plan" : "research program cannot begin"
	case .Suspend_Research:
		r.ok = suspend_research_program(c, command.research, command.flag)
		r.message =
			r.ok ? (command.flag ? "research program suspended" : "research program resumed") : "research program cannot be changed"
	case .Begin_Passage:
		selected := command.ships
		r.ok, r.message = begin_passage(
			c,
			command.contract,
			selected[:command.ship_count],
			&c.passage,
		)
	case .Plot_Dark_Course:
		_, r.ok = plot_passage_course(c, &c.passage, command.dark_course)
		r.message = r.ok ? "Dark course accepted" : "Dark course is invalid"
	case .Cross_Dark_Door:
		r.ok, r.message = cross_passage_door(c, &c.passage)
	case .Plot_Normal_Course:
		r.ok = plot_normal_course(c, &c.passage, command.target, command.velocity_fraction_c)
		r.message =
			r.ok ? "Normal-space leg accepted" : "Direct interstellar flight is retired; use mapped Dark correspondences"
	case .Set_Dark_Strategy:
		r.ok, r.message = set_dark_strategy(c, &c.passage, command.strategy)
	case .Set_Safe_Endpoint:
		r.ok = set_passage_safe_endpoint(c, &c.passage, command.safe_endpoint, command.relay_id)
		r.message = r.ok ? "Safe endpoint authenticated" : "No safe endpoint is available"
	case .Conclude_Passage:
		r.ok, r.message = conclude_passage(c, &c.passage)
	case .Found_Settlement:
		r.ok = found_settlement(c, command.community, command.ship, command.name, command.flag)
		r.message = r.ok ? "settlement founded" : "settlement cannot be founded"
	case .Begin_Settlement_Proposal:
		r.ok = begin_settlement_proposal(c, command.name, command.destination)
		r.message = r.ok ? "settlement proposal opened" : "settlement proposal cannot be opened"
	case .Set_Settlement_Procedure:
		r.ok = c.settlement_proposal.phase == .Draft
		if r.ok do c.settlement_proposal.procedure = command.procedure
		r.message = r.ok ? "procedure changed" : "proposal is not editable"
	case .Set_Settlement_Disclosure:
		r.ok = c.settlement_proposal.phase == .Draft
		if r.ok do c.settlement_proposal.disclose_evidence = command.flag
		r.message = r.ok ? "disclosure changed" : "proposal is not editable"
	case .Set_Settlement_Charter:
		r.ok = c.settlement_proposal.phase == .Draft
		if r.ok {c.settlement_proposal.sovereign = command.flag
			c.settlement_proposal.continuing_jurisdiction = !command.flag
			c.settlement_proposal.charter_participation = true}
		r.message = r.ok ? "charter changed" : "proposal is not editable"
	case .Set_Settlement_Charter_Participation:
		r.ok = c.settlement_proposal.phase == .Draft
		if r.ok do c.settlement_proposal.charter_participation = command.flag
		r.message = r.ok ? "charter procedure changed" : "proposal is not editable"
	case .Set_Settlement_Obligation:
		r.ok = c.settlement_proposal.phase == .Draft
		if r.ok do c.settlement_proposal.obligations = continuing_set(c.settlement_proposal.obligations, command.obligation, command.flag)
		r.message = r.ok ? "guarantee changed" : "proposal is not editable"
	case .Set_Settlement_Ship:
		i := ship_index(c, command.ship)
		r.ok = c.settlement_proposal.phase == .Draft && i >= 0 && c.ships[i].active
		if r.ok do c.settlement_proposal.requested_ships[i] = command.flag
		r.message = r.ok ? "ship request changed" : "ship request cannot be changed"
	case .Set_Settlement_Community:
		i := community_index(c, command.community)
		r.ok = c.settlement_proposal.phase == .Draft && i >= 0
		if r.ok do c.settlement_proposal.requested_communities[i] = command.flag
		r.message = r.ok ? "community request changed" : "community request cannot be changed"
	case .Set_Settlement_Institution:
		i := institution_index(c, Institution_ID(command.index))
		r.ok = c.settlement_proposal.phase == .Draft && i >= 0 && c.institutions[i].active
		if r.ok do c.settlement_proposal.transfer_institutions[i] = command.flag
		r.message =
			r.ok ? "institution transfer changed" : "institution transfer cannot be changed"
	case .Set_Settlement_Archive:
		i := archive_index(c, Archive_ID(command.index))
		r.ok = c.settlement_proposal.phase == .Draft && i >= 0 && c.archives[i].preserved
		if r.ok do c.settlement_proposal.transfer_archives[i] = command.flag
		r.message = r.ok ? "archive transfer changed" : "archive transfer cannot be changed"
	case .Open_Settlement_Deliberation:
		r.ok = open_settlement_deliberation(c)
		r.message = r.ok ? "ships published their positions" : "deliberation cannot begin"
	case .Revise_Settlement_Proposal:
		r.ok = revise_settlement_proposal(c)
		r.message = r.ok ? "proposal returned to draft" : "proposal cannot be revised"
	case .Finalize_Settlement_Proposal:
		r.ok = finalize_settlement_proposal(c)
		r.message = r.ok ? "settlement founded" : "proposal cannot be finalized"
	case .Withdraw_Settlement_Proposal:
		r.ok = withdraw_settlement_proposal(c)
		r.message = r.ok ? "proposal withdrawn" : "proposal cannot be withdrawn"
	case .Choose_Interaction:
		r.ok = resolve_interaction(c, command.index)
		r.message = r.ok ? "interaction entered the chronicle" : "that response is unavailable"
	case .Resolve_Collision:
		r.ok, r.message = execute_collision_command(
			c,
			command.collision_id,
			command.collision_command_id,
		)
	}
	if r.ok && command.kind != .Conclude_Chronicle do _ = resolve_fleet_dissolution(c)
	return r
}
