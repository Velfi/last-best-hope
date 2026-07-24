package main

import game "../packages/game"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import jsonlines "zelda_engine:jsonlines"

Agent_Request :: struct {
	command, action:                                                                   string,
	seed:                                                                              u64,
	target:                                                                            int,
	depth, velocity_fraction_c:                                                        f64,
	relay_id:                                                                          u64,
	door_id:                                                                           u64,
	ships:                                                                             [game.MAX_EXPEDITION_SHIPS]int,
	ship_count:                                                                        int,
	strategy_index:                                                                    int,
	has_strategy:                                                                      bool,
	route_policy, contact_policy, return_policy:                                       int,
	has_policy:                                                                        bool,
	depth_posture, course_priority, ecology_posture, relay_posture, withdrawal_margin: int,
	waypoints:                                                                         [game.MAX_DARK_COURSE_WAYPOINTS]game.Dark_Vec4,
	waypoint_count:                                                                    int,
	// A campaign request delegates every player-facing campaign decision to one
	// of the deterministic policies used by the headless playtest runner.
	campaign_profile, campaign_length, campaign_tempo, campaign_horizon:               int,
}

Agent_State :: struct {
	active:                                                                   bool,
	phase, domain, purpose, sponsor, pause_reason:                            string,
	objective_met:                                                            bool,
	elapsed_days, membrane_elapsed_days, course_cost:                         f64,
	local_discoveries, tracks:                                                int,
	recommendation, selected_strategy, recommended_strategy, selected_policy: string,
	strategy_differences, strategy_evidence:                                  int,
	known_failure_mode:                                                       string,
	normal_position:                                                          [3]f64,
	fleet_stock, protected_stock, spendable_stock:                            game.Fleet_Stock,
	manifest:                                                                 game.Passage_Manifest,
	principal_exposure:                                                       string,
}

Agent_Response :: struct {
	type:             string,
	ok:               bool,
	message:          string,
	protocol_version: int,
	state:            Agent_State,
	campaign:         Agent_Campaign_Result,
}

// Keep the full-campaign result compact enough for an interactive agent while
// retaining the outcomes needed to decide whether to replay, change policy, or
// inspect a seed in the graphical Chronicle.
Agent_Campaign_Result :: struct {
	played:                                                            bool,
	profile, ending, ending_quality:                                   string,
	seed:                                                              u64,
	seasons, passages, objectives, actions, invalid_actions:           i32,
	ships_lost, ships_settled, settlements, rescued, emergency_events: i32,
	final_stock:                                                       game.Fleet_Stock,
}

agent_campaign_result :: proc(result: Bot_Run_Result) -> Agent_Campaign_Result {
	return {
		played = true,
		profile = bot_profile_name(result.profile),
		ending = game.ending_name(result.ending),
		ending_quality = game.ending_quality_name(result.ending_quality),
		seed = result.game_seed,
		seasons = result.seasons,
		passages = result.passages,
		objectives = result.objectives,
		actions = result.actions,
		invalid_actions = result.invalid_actions,
		ships_lost = result.ships_lost,
		ships_settled = result.ships_settled,
		settlements = result.settlements,
		rescued = result.rescued,
		emergency_events = result.emergency_events,
		final_stock = result.fleet_stock,
	}
}

agent_run_campaign :: proc(req: ^Agent_Request) -> (Agent_Campaign_Result, string, bool) {
	if req.campaign_profile < 0 || req.campaign_profile > int(Bot_Profile.World_Builder) do return {}, "invalid campaign profile", false
	if req.campaign_length < 0 || req.campaign_length > int(game.Chronicle_Length.Open) do return {}, "invalid campaign length", false
	if req.campaign_tempo < 0 || req.campaign_tempo > int(game.Story_Tempo.Volatile) do return {}, "invalid campaign tempo", false
	seed := req.seed; if seed == 0 do seed = 0x5eed
	profile := Bot_Profile(req.campaign_profile)
	horizon := i32(clamp(req.campaign_horizon, 0, MAX_SOAK_SEASONS))
	result := bot_run(
		{
			profile = profile,
			game_seed = seed,
			bot_seed = seed ~ (u64(profile) + 1) * 0x9e3779b97f4a7c15,
			length = game.Chronicle_Length(req.campaign_length),
			tempo = game.Story_Tempo(req.campaign_tempo),
			horizon = horizon,
			max_actions = 256,
		},
	)
	return agent_campaign_result(result), "campaign completed", true
}

agent_strategy_text :: proc(s: game.Dark_Strategy_Profile) -> string {
	return fmt.tprintf(
		"depth=%v course=%v ecology=%v relay=%v withdrawal=%v",
		s.depth,
		s.course,
		s.ecology,
		s.relay,
		s.withdrawal,
	)
}

agent_policy_text :: proc(policy: game.Dark_Expedition_Policy) -> string {
	return fmt.tprintf(
		"route=%v contact=%v return=%v",
		policy.route,
		policy.contact,
		policy.return_policy,
	)
}

agent_requested_policy :: proc(req: ^Agent_Request) -> (game.Dark_Expedition_Policy, bool) {
	if req.route_policy < 0 || req.route_policy > 2 || req.contact_policy < 0 || req.contact_policy > 2 || req.return_policy < 0 || req.return_policy > 2 do return {}, false
	return {
			route = game.Dark_Route_Policy(req.route_policy),
			contact = game.Dark_Contact_Policy(req.contact_policy),
			return_policy = game.Dark_Return_Policy(req.return_policy),
		},
		true
}

agent_requested_strategy :: proc(
	req: ^Agent_Request,
	term: game.Operation_Conduct,
) -> (
	game.Dark_Strategy_Profile,
	bool,
) {
	if !req.has_strategy {
		return game.dark_strategy_profile_at(
			clamp(req.strategy_index, 0, game.DARK_STRATEGY_PROFILE_COUNT - 1),
		)
	}
	if req.depth_posture < 0 || req.depth_posture > 2 || req.course_priority < 0 || req.course_priority > 2 || req.ecology_posture < 0 || req.ecology_posture > 2 || req.relay_posture < 0 || req.relay_posture > 1 || req.withdrawal_margin < 0 || req.withdrawal_margin > 2 do return {}, false
	return {
			depth = game.Dark_Depth_Posture(req.depth_posture),
			course = game.Dark_Course_Priority(req.course_priority),
			ecology = game.Dark_Ecology_Posture(req.ecology_posture),
			relay = game.Dark_Relay_Posture(req.relay_posture),
			withdrawal = game.Dark_Withdrawal_Margin(req.withdrawal_margin),
		},
		true
}

agent_state :: proc(c: ^game.Campaign) -> Agent_State {
	p := &c.passage
	floor := game.fleet_operating_floor(
		c,
	); spendable := game.fleet_stock_min_zero(game.fleet_stock_sub(c.material_economy.fleet.stock, floor.stock))
	r := Agent_State {
		active                = p.active,
		phase                 = fmt.tprintf("%v", p.phase),
		domain                = fmt.tprintf("%v", p.domain),
		purpose               = fmt.tprintf("%v", p.contract.purpose),
		sponsor               = game.institution_name(c, p.contract.sponsor),
		pause_reason          = fmt.tprintf("%v", p.pause_reason),
		objective_met         = p.contract.objective_met,
		elapsed_days          = p.elapsed_days,
		membrane_elapsed_days = p.membrane_elapsed_days,
		course_cost           = p.course_cost,
		local_discoveries     = p.local_atlas_count,
		tracks                = p.dark_navigation.tracker.track_count,
		fleet_stock           = c.material_economy.fleet.stock,
		protected_stock       = floor.stock,
		spendable_stock       = spendable,
		manifest              = p.manifest,
		principal_exposure    = floor.principal,
	}
	r.normal_position = p.normal_course.current_position
	if p.active {
		rec := game.recommend_dark_strategy(c, &p.contract)
		comparison := game.compare_dark_strategy(c, &p.contract, p.strategy)
		r.recommendation = rec.reason
		r.selected_strategy = agent_strategy_text(p.strategy)
		r.recommended_strategy = agent_strategy_text(rec.strategy)
		r.selected_policy = agent_policy_text(p.policy)
		r.strategy_differences = comparison.difference_count
		r.strategy_evidence = int(comparison.selected_estimate.evidence)
		r.known_failure_mode = comparison.failure_mode
	}
	return r
}

agent_write :: proc(r: Agent_Response) {
	if !jsonlines.write(r) do fmt.println("{\"type\":\"error\",\"ok\":false}")
}

run_agent_interface :: proc() {
	c := new(game.Campaign)
	defer free(c)
	started := false
	fmt.println("{\"type\":\"hello\",\"ok\":true,\"protocol_version\":5}")
	for {
		bytes, available := jsonlines.read(); if !available {delete(bytes); break}
		line := strings.trim_space(string(bytes[:]))
		req: Agent_Request
		err := json.unmarshal(transmute([]u8)line, &req); delete(bytes)
		if err !=
		   nil {agent_write({type = "error", message = "invalid request", protocol_version = 5}); continue}
		if req.command == "campaign" {
			result, msg, ok := agent_run_campaign(&req)
			agent_write(
				{
					type = "campaign_result",
					ok = ok,
					message = msg,
					protocol_version = 5,
					campaign = result,
				},
			)
			continue
		}
		if req.command == "start" {
			if started {agent_write({type = "error", message = "campaign already active", protocol_version = 5}); continue}
			seed := req.seed; if seed == 0 do seed = 0x5eed
			game.campaign_init(c, seed)
			contract := game.default_passage_contract()
			// The line protocol begins a self-contained expedition rather than
			// driving the Chronicle's Compact-negotiation UI. Marking the contract
			// standalone preserves that public protocol while keeping campaign
			// Passage reserved for a formally accepted undertaking.
			contract.standalone = true
			ships := req.ships; count := req.ship_count; if count <= 0 {ships[0] = 0; count = 1}
			ok, msg := game.begin_passage(c, contract, ships[:count], &c.passage)
			if ok {
				if req.has_policy {
					policy, valid := agent_requested_policy(&req)
					if !valid {msg = "invalid expedition policy"; ok = false} else {ok, msg = game.set_dark_policy(c, &c.passage, policy)}
				} else {
					strategy, valid := agent_requested_strategy(&req, c.passage.contract.term)
					if !valid {msg = "invalid strategy profile"; ok = false} else {ok, msg = game.set_dark_strategy(c, &c.passage, strategy)}
				}
			}
			started =
				ok; agent_write({type = "state", ok = ok, message = msg, protocol_version = 5, state = agent_state(c)}); continue
		}
		if !started {agent_write({type = "error", message = "start a campaign first", protocol_version = 5}); continue}
		ok := false; msg := "unknown command"
		switch req.action {
		case "set_strategy":
			strategy, valid := agent_requested_strategy(&req, c.passage.contract.term)
			if valid do ok, msg = game.set_dark_strategy(c, &c.passage, strategy)
			msg = ok ? "strategy recorded" : "strategy rejected"
		case "set_policy":
			policy, valid := agent_requested_policy(&req)
			if valid do ok, msg = game.set_dark_policy(c, &c.passage, policy)
			msg = ok ? "policy recorded" : "policy rejected"
		case "custom_course":
			course := game.Dark_Course {
				waypoint_count = clamp(req.waypoint_count, 0, game.MAX_DARK_COURSE_WAYPOINTS),
			}; for point, i in req.waypoints[:course.waypoint_count] do course.waypoints[i].position = point; _, ok = game.plot_passage_course(c, &c.passage, course); msg = ok ? "course accepted" : "course rejected"
		case "course_to_door":
			course, found := game.passage_course_to_unknown_door(c, &c.passage, req.depth)
			if found {_, ok = game.plot_passage_course(c, &c.passage, course)}
			msg = ok ? "course accepted" : "no course available"
		case "cross_door":
			ok, msg = game.cross_passage_door(c, &c.passage)
		case "enter_dark":
			ok, msg = game.enter_passage_dark(c, &c.passage, req.door_id)
		case "normal_course":
			ok = game.plot_normal_course(c, &c.passage, req.target, req.velocity_fraction_c)
			msg =
				ok ? "course accepted" : "direct interstellar flight is retired; use mapped Dark correspondences"
		case "advance":
			step :=
				c.passage.domain == .Normal_Space ? max(c.passage.normal_course.total_days - c.passage.normal_course.elapsed_days, 1) : 1
			game.advance_passage(c, &c.passage, step)
			ok = true
			msg = "expedition advanced"
		case "service_relay":
			_, ok, msg = game.service_passage_relay(c, &c.passage)
		case "fleet_endpoint":
			ok = game.set_passage_safe_endpoint(c, &c.passage, .Fleet)
			msg = ok ? "fleet endpoint set" : "endpoint unavailable"
		case "relay_endpoint":
			ok = game.set_passage_safe_endpoint(c, &c.passage, .Authenticated_Relay, req.relay_id)
			msg = ok ? "relay authenticated" : "relay unavailable"
		case "conclude":
			ok, msg = game.conclude_passage(c, &c.passage)
		case "declare_missing":
			ok, msg = game.declare_passage_missing(c, &c.passage)
		case "observe":
			ok = true; msg = "observation"
		case:
		}
		agent_write(
			{
				type = "result",
				ok = ok,
				message = msg,
				protocol_version = 5,
				state = agent_state(c),
			},
		)
	}
	if started do game.campaign_destroy(c)
}
