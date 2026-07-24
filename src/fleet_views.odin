package main

import game "../packages/game"
import "core:fmt"
import "core:testing"
import rl "zelda_engine:canvas2d"

fleet_compact_notification_pending :: proc(c: ^game.Campaign) -> bool {
	if c.compact.counsel.available do return true
	for call in c.compact.calls[:c.compact.call_count] do if call.status == .Open do return true
	return false
}

// A Passage is commissioned only after the Compact has made a Passage
// undertaking available. Keep Fleet navigation aligned with the same rule the
// game uses when authorizing departure, rather than opening an empty briefing.
fleet_passage_commission_ready :: proc(c: ^game.Campaign) -> bool {
	available: [game.MAX_NEEDS]game.Dark_Contract
	return !c.passage.active && game.dark_available_contracts(c, &available) > 0
}

fleet_opening_council_pending :: proc(c: ^game.Campaign) -> bool {
	// A founding record alone is not enough to route the player into the
	// Compact. Older or incomplete saves can have that record without a call
	// that the Compact can act on, which otherwise leaves the player on an
	// empty docket at startup.
	return c.founding_decision_event != 0 &&
		c.season == 0 &&
		!c.passage.active &&
		fleet_compact_notification_pending(c)
}

open_opening_council :: proc(s: ^Ux_State) {
	// Campaigns saved before opening calls were surfaced can still be at the
	// founding season with a populated need board and an empty Compact docket.
	// Repair that valid, incomplete boundary on entry rather than asking the
	// player to begin again.
	if fleet_opening_council_pending(s.campaign) {
		if game.compact_surface_one_call(s.campaign) do _ = ux_save(s, true)
	}
	for need, i in s.campaign.needs do if need.active && !need.resolved {
		s.selected_need = i
		break
	}
	// Do not present the Compact as a destination unless it has an actionable
	// call or counsel. The Fleet is the useful recovery point if surfacing an
	// old campaign's opening call was not possible.
	s.screen = fleet_compact_notification_pending(s.campaign) ? .Care : .Fleet
}


@(test)
fleet_compact_notification_tracks_calls_and_counsel :: proc(t: ^testing.T) {
	c := new(game.Campaign)
	defer free(c)
	testing.expect(t, !fleet_compact_notification_pending(c))
	c.compact.calls[0] = {
		status = .Open,
	}
	c.compact.call_count = 1
	testing.expect(t, fleet_compact_notification_pending(c))
	c.compact.calls[0].status = .Completed
	testing.expect(t, !fleet_compact_notification_pending(c))
	c.compact.counsel.available = true
	testing.expect(t, fleet_compact_notification_pending(c))
}

@(test)
fleet_only_prompts_for_an_opening_council_after_a_founding_record :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(27174)
	defer game.campaign_destroy_heap(c)
	testing.expect(t, !fleet_opening_council_pending(c))
	c.founding_decision_event = 1
	testing.expect(t, !fleet_opening_council_pending(c))
	c.compact.calls[0] = {
		status = .Open,
	}
	c.compact.call_count = 1
	testing.expect(t, fleet_opening_council_pending(c))
	c.season = 1
	testing.expect(t, !fleet_opening_council_pending(c))
}


fleet_should_prompt_advance :: proc(c: ^game.Campaign) -> bool {
	if c.passage.active || c.council.active || c.council.exception_pending do return false
	if c.current_situation.phase != .None && c.current_situation.phase != .Resolved do return false
	if c.compact.active.status == .Planning || c.compact.active.status == .Operating do return false
	for need in c.needs do if need.active && !need.resolved do return false
	return true
}

Attention_Link :: enum {
	Origin,
	Undertaking,
	Precedent,
	Promise,
}

open_attention_link :: proc(
	s: ^Ux_State,
	event: ^game.Attention_Event,
	link: Attention_Link,
) -> bool {
	sequence: u64
	switch link {
	case .Origin:
		sequence = event.origin_event_id
	case .Undertaking:
		if event.undertaking_id == 0 do return false
		s.screen = .Briefing
		return true
	case .Precedent:
		if event.precedent_id == 0 do return false
		at := game.precedent_index_by_id(s.campaign, game.Precedent_ID(event.precedent_id))
		if at < 0 do return false
		sequence = s.campaign.precedents[at].event_sequence
	case .Promise:
		if event.promise_id == 0 do return false
		index := int(event.promise_id) - 1
		if index < 0 || index >= s.campaign.promise_count do return false
		promise := s.campaign.promises[index]
		for i := s.campaign.event_count - 1; i >= 0; i -= 1 {
			candidate := s.campaign.events[i]
			if candidate.kind == .Promise_Changed && candidate.community == promise.beneficiary {
				sequence = candidate.sequence
				break
			}
		}
	}
	at := game.event_index_by_sequence(s.campaign, sequence)
	if at < 0 do return false
	s.selected_event = at
	open_chronicle_from(s, s.screen)
	return true
}

@(test)
attention_links_open_origin_undertaking_precedent_and_promise_records :: proc(t: ^testing.T) {
	s := Ux_State {
		campaign = game.new_campaign_heap(27177),
	}
	defer game.campaign_destroy_heap(s.campaign)
	origin := s.campaign.events[0].sequence
	s.campaign.precedents[0] = {
		id             = 1,
		event_sequence = origin,
	}
	s.campaign.precedent_count = 1
	s.campaign.promises[0] = {
		beneficiary = s.campaign.events[0].community,
		status      = .Active,
	}
	s.campaign.promise_count = 1
	s.campaign.events[0].kind = .Promise_Changed
	event := game.Attention_Event {
		origin_event_id = origin,
		undertaking_id  = 1,
		precedent_id    = 1,
		promise_id      = 1,
	}
	testing.expect(t, open_attention_link(&s, &event, .Origin))
	testing.expect_value(t, s.screen, Ux_Screen.Chronicle)
	testing.expect(t, open_attention_link(&s, &event, .Undertaking))
	testing.expect_value(t, s.screen, Ux_Screen.Briefing)
	testing.expect(t, open_attention_link(&s, &event, .Precedent))
	testing.expect_value(t, s.screen, Ux_Screen.Chronicle)
	testing.expect(t, open_attention_link(&s, &event, .Promise))
	testing.expect_value(t, s.screen, Ux_Screen.Chronicle)
}

campaign_work_label :: proc(c: ^game.Campaign, work: game.Scheduled_Work) -> string {
	switch work.source {
	case .Council:
		return fmt.tprintf("COUNCIL · %v", c.council.phase)
	case .Project:
		index := int(work.source_id) - 1
		if index >= 0 && index < len(c.projects) {
			return fmt.tprintf("PROJECT · %v", c.projects[index].kind)
		}
		return "FLEET PROJECT"
	case .Repair:
		return "REPAIR"
	case .Settlement:
		return "SETTLEMENT WORK"
	case .Obligation:
		return "OBLIGATION"
	case .Passage:
		return "PASSAGE"
	case .Far_Engagement:
		return "FAR ENGAGEMENT"
	case .Close_Engagement:
		return "CLOSE ENGAGEMENT"
	case .Fleet_Navigation:
		return "FLEET NAVIGATION"
	case .None:
		return "WORK"
	}
	return "WORK"
}

draw_campaign_underway_rail :: proc(s: ^Ux_State, objective: string) {
	c := s.campaign
	pending := game.campaign_pending_attention(c)
	if pending != nil {
		queued := 0
		for event in c.attention_queue do if event.active && (event.level == .Decision || event.level == .Constitutional) do queued += 1
		rl.DrawRectangle(0, 664, UX_W, 56, {5, 5, 4, 252})
		divider(0, 664, UX_W)
		label_caps(fmt.tprintf("ATTENTION · %d QUEUED", queued), 20, 675, UX.warn)
		draw_text_fitted(
			fmt.tprintf("%s → %s", pending.underway_action, pending.changed_fact),
			R(20, 693, 500, 18),
			TYPE_FINE,
			UX.text,
		)
		draw_text_fitted(
			fmt.tprintf(
				"%s · EXPOSED: %s · COST: %s · IRREVERSIBLE: %s · AUTH: %s · DEFAULT: %s%s",
				pending.standing_order,
				pending.affected_summary,
				pending.known_costs == "" ? "none recorded" : pending.known_costs,
				pending.irreversible_effects == "" ? "none recorded" : pending.irreversible_effects,
				pending.authorization_status == "" ? "unconfirmed" : pending.authorization_status,
				pending.no_response_default,
				queued > 1 ? " · Resolving this record may rewrite later defaults; invalidated records remain archived." : "",
			),
			R(530, 680, 470, 28),
			TYPE_FINE,
			UX.dim,
		)
		if pending.affected_ship_count > 0 {
			ship_at := game.ship_index(c, pending.affected_ships[0])
			if ship_at >= 0 && button(R(1006, 674, 70, 36), c.ships[ship_at].name) {
				s.selected_ship = ship_at
				s.screen = .Fleet
			}
		}
		link_x: f32 = 790
		if pending.origin_event_id != 0 {
			if button(R(link_x, 674, 66, 18), "EVENT") do _ = open_attention_link(s, pending, .Origin)
			link_x += 70
		}
		if pending.undertaking_id != 0 {
			if button(R(link_x, 674, 66, 18), "UNDERTAKING") do _ = open_attention_link(s, pending, .Undertaking)
			link_x += 70
		}
		if pending.precedent_id != 0 {
			if button(R(link_x, 674, 66, 18), "LAW") do _ = open_attention_link(s, pending, .Precedent)
			link_x += 70
		}
		if pending.promise_id != 0 {
			if button(R(link_x, 674, 66, 18), "PROMISE") do _ = open_attention_link(s, pending, .Promise)
		}
		if pending.source == .Passage {
			if button(R(1080, 674, 178, 36), "OPEN PASSAGE") {
				s.screen = .Passage
			}
			return
		}
		if pending.source == .Fleet_Navigation {
			if button(R(1080, 674, 178, 36), "OPEN NAVIGATION") {
				_ = game.campaign_resolve_attention(c, pending.id, 0)
				s.screen = .Navigation
			}
			return
		}
		if pending.source == .Far_Engagement {
			if button(R(1080, 674, 178, 36), "OPEN ENGAGEMENT") {
				s.screen = .Far_Engagement
			}
			return
		}
		if pending.source == .Close_Engagement && s.combat_campaign_active {
			if button(R(1080, 674, 178, 36), "OPEN OPERATION") {
				s.screen = .Combat
			}
			return
		}
		if pending.source == .Campaign {
			if button(R(1080, 674, 178, 36), "OPEN DECISION") {
				if s.campaign.material_economy.food_shortage_response_pending {
					s.modal = .Food_Shortage
				} else if s.campaign.economy_loss_decision_pending {
					s.modal = .Economy_Loss
				} else if s.campaign.stranded_outcome_notice_pending {
					s.modal = .Stranded_Outcome
				} else if s.campaign.ending_prompt_pending {
					s.modal = .Conclude
				} else {
					s.screen = .Interaction
				}
			}
			return
		}
		x: f32 = 1010
		for choice in 0 ..< pending.choice_count {
			width := f32(238 / max(pending.choice_count, 1))
			if button(R(x + f32(choice) * width, 674, width - 4, 36), pending.choices[choice]) {
				_ = game.campaign_resolve_attention(c, pending.id, choice)
			}
		}
		return
	}
	rl.DrawRectangle(0, 664, UX_W, 56, {5, 5, 4, 252})
	divider(0, 664, UX_W)
	label_caps("WORK UNDERWAY", 20, 675, UX.info)
	active_work := 0
	for work in c.scheduled_work do if work.active do active_work += 1
	shown := 0
	for work in c.scheduled_work {
		if !work.active || shown >= 2 do continue
		duration := max(i64(work.due_at) - i64(work.started_at), i64(1))
		elapsed := clamp(i64(c.clock.now) - i64(work.started_at), i64(0), duration)
		percent := i32(elapsed * 100 / duration)
		days := max((i64(work.due_at) - i64(c.clock.now)) / game.CAMPAIGN_DAY_SECONDS, i64(0))
		draw_fmt(
			20 + f32(shown) * 285,
			693,
			TYPE_FINE,
			UX.text,
			"%s · %d%% · %dD",
			campaign_work_label(c, work),
			percent,
			days,
		)
		shown += 1
	}
	if shown == 0 do draw_fmt(20, 693, TYPE_FINE, UX.dim, "YEAR %d · NO SCHEDULED WORK · %s", c.year, objective)
	if active_work > shown do draw_fmt(590, 693, TYPE_FINE, UX.dim, "+%d MORE", active_work - shown)
	speeds := [4]game.Campaign_Speed{.Paused, .One, .Ten, .Hundred}
	labels := [4]string{"PAUSE", "1×", "10×", "100×"}
	for speed, i in speeds {
		if button(R(820 + f32(i) * 64, 674, 58, 36), labels[i], true, c.clock.speed == speed) {
			_ = game.campaign_set_speed(c, speed)
		}
	}
	if button(R(1080, 674, 178, 36), "NEXT ATTENTION") {
		_ = game.campaign_advance_to_attention(c)
	}
}

@(test)
advance_prompt_waits_until_player_facing_work_is_clear :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(17)
	defer game.campaign_destroy_heap(c)
	testing.expect(t, fleet_should_prompt_advance(c))
	c.needs[0] = {
		kind   = .Representation,
		active = true,
	}
	testing.expect(t, !fleet_should_prompt_advance(c))
	c.needs[0].resolved = true
	testing.expect(t, fleet_should_prompt_advance(c))
	c.current_situation.phase = .Decision
	testing.expect(t, !fleet_should_prompt_advance(c))
}


draw_fleet :: proc(s: ^Ux_State) {
	top_rail(s)
	label_caps("FLEET COALITIONS", 24, 76)
	draw_fleet_coalitions(s)
	situation_active := draw_fleet_ship_dossier(s)
	if s.campaign.settlement_economies.count > 0 do draw_trade_dependency_record(s, 46, 542, 760, max_rows = 1)
	if s.campaign.economy_loss_decision_pending && s.modal == .None do s.modal = .Economy_Loss
	if s.campaign.stranded_outcome_notice_pending && s.modal == .None do s.modal = .Stranded_Outcome
	if s.campaign.ending_prompt_pending && s.modal == .None do s.modal = .Conclude
	// This rail is for stable places in the record. Situation-specific commands
	// belong to the bottom rail below, where their consequence is stated once.
	if icon_button(R(24, 596, 136, 38), "STORY", ICON_STORY) do s.screen = .Story
	if icon_button(R(168, 596, 136, 38), "GALAXY", ICON_GALAXY) do s.screen = .Galaxy
	if icon_button(R(312, 596, 156, 38), "CHRONICLE", ICON_CHRONICLE) do open_chronicle_from(s, .Fleet)
	if icon_button(R(476, 596, 156, 38), "NAVIGATION", ICON_SURVEY) do s.screen = .Navigation
	commission_ready := fleet_passage_commission_ready(s.campaign)
	opening_council := fleet_opening_council_pending(s.campaign)
	council_notice := fleet_compact_notification_pending(s.campaign)
	shortage_pending := s.campaign.material_economy.food_shortage_response_pending
	objective :=
		opening_council ? "PLACE A FOUNDING CLAIM BEFORE THE COUNCIL" : shortage_pending ? "FOOD CONSUMPTION EXCEEDS SECURE SUPPLY · CHOOSE A STRUCTURAL RESPONSE" : commission_ready ? "PASSAGE UNDERTAKING READY · COMMISSION ITS SECONDED SHIPS" : s.campaign.compact.active.status == .Planning ? "COMPACT UNDERTAKING READY · PLAN ITS AUTHORIZED OPERATION" : council_notice || situation_active ? "COMPACT CALL AWAITS A RESPONSE" : "NO COMPACT INTERVENTION IS PENDING · ADVANCE WHEN READY"
	action :=
		opening_council ? "REVIEW OPENING CLAIMS" : shortage_pending ? "ANSWER FOOD SHORTAGE" : commission_ready ? "OPEN COMMISSION" : s.campaign.compact.active.status == .Planning ? "OPEN COMPACT" : council_notice || situation_active ? "OPEN COMPACT" : ""
	if action != "" && bottom_rail(s, objective, action, true, false, false) {
		if opening_council {
			open_opening_council(s)
		} else if shortage_pending {
			s.modal = .Food_Shortage
		} else if commission_ready {
			prepare_dark_briefing(s)
			s.screen = .Briefing
		} else if council_notice {
			open_opening_council(s)
		} else if situation_active {
			s.screen = .Interaction
		}
	} else if action == "" {
		draw_campaign_underway_rail(s, objective)
	}
}
