package main

import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:os"
import filepath "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"
import rl "zelda_engine:canvas2d"
import ui "zelda_engine:ui"

draw_care :: proc(s: ^Ux_State) {
	top_rail(s)
	if s.campaign.compact.counsel.available {
		counsel := &s.campaign.compact.counsel
		draw_text("FACTUAL REPORT", 28, 78, TYPE_TITLE)
		draw_text(
			"THE COMPACT MAY APPEND ONE EVIDENCE-BACKED COUNSEL",
			28,
			111,
			TYPE_SMALL,
			UX.dim,
		)
		panel(R(28, 140, 1224, 118), true)
		draw_fmt(
			52,
			160,
			TYPE_LABEL,
			UX.info,
			"OPERATION %d · FACTUAL BASIS EVENT %d",
			counsel.aftermath,
			counsel.factual_basis,
		)
		draw_text_wrapped(
			"The operation record is fixed. Counsel can recommend a response; it cannot declare success, rewrite conduct, or enact policy.",
			R(52, 192, 1160, 48),
			TYPE_LABEL,
			UX.text,
		)
		for option, i in counsel.options[:counsel.option_count] {
			y := 282 + f32(i) * 78
			panel(R(28, y, 1224, 62))
			draw_text_wrapped(option, R(52, y + 12, 940, 40), TYPE_LABEL, UX.text)
			if button(R(1030, y + 14, 190, 32), "APPEND COUNSEL") {
				r := execute_command(s, {kind = .Resolve_Compact_Counsel, target = i})
				s.status = r.message
			}
		}
		if button(R(1030, 530, 190, 32), "REPORT ONLY") {
			r := execute_command(s, {kind = .Resolve_Compact_Counsel, target = -1})
			s.status = r.message
		}
		bottom_rail(s, "FACTS PERSIST · AUTONOMOUS ACTORS DECIDE")
		return
	}
	if s.campaign.compact.active.status == .Planning ||
	   s.campaign.compact.active.status == .Operating {
		u := &s.campaign.compact.active
		operation_preview := game.compact_operation_preview(s.campaign)
		draw_text("COMPACT UNDERTAKING", 28, 78, TYPE_TITLE)
		draw_text(
			"INTENT · SECONDMENTS · AUTHORITY · STANDING DOCTRINE",
			28,
			111,
			TYPE_SMALL,
			UX.dim,
		)
		panel(R(28, 140, 1224, 150), true)
		label_caps("GOOD-FAITH INTENT", 52, 160, UX.info)
		draw_text_wrapped(u.intent, R(52, 190, 1120, 48), TYPE_LABEL, UX.text)
		draw_fmt(52, 250, TYPE_FINE, UX.dim, "APPROACH · %v", u.approach)
		draw_fmt(
			300,
			250,
			TYPE_FINE,
			UX.info,
			"ROUTE · %v · OBJECTIVE · %v",
			u.route,
			u.charter.undertaking_intent.objective,
		)
		panel(R(28, 306, 600, 272))
		label_caps("SECONDED SHIPS", 52, 326, UX.info)
		for ship_id, i in u.seconded_ships[:u.seconded_count] {
			at := game.ship_index(s.campaign, ship_id)
			if at < 0 do continue
			ship := s.campaign.ships[at]
			draw_fmt(
				52,
				358 + f32(i) * 28,
				TYPE_LABEL,
				UX.text,
				"%s · %s",
				ship.name,
				game.role_name(ship.role),
			)
		}
		panel(R(644, 306, 608, 272))
		label_caps("STANDING DOCTRINE", 668, 326, UX.info)
		draw_text_wrapped(u.charter.standing_doctrine, R(668, 358, 548, 60), TYPE_LABEL, UX.text)
		draw_fmt(
			668,
			416,
			TYPE_FINE,
			UX.dim,
			"AUTHORITY · %s · EVENT %d",
			u.charter.hard_authority.reviewer_name,
			u.charter.hard_authority.compiled_event,
		)
		draw_fmt(
			668,
			440,
			TYPE_FINE,
			UX.dim,
			"RESCUE %v · EXPOSURE %v",
			u.charter.doctrine.rescue,
			u.charter.doctrine.exposure,
		)
		draw_fmt(
			668,
			462,
			TYPE_FINE,
			UX.dim,
			"WITHDRAWAL %v · DISCLOSURE %v",
			u.charter.doctrine.withdrawal,
			u.charter.doctrine.disclosure,
		)
		if operation_preview.valid {
			draw_fmt(
				668,
				482,
				TYPE_FINE,
				UX.dim,
				"RESERVED · S%d M%d P%d · %d CONTRIBUTOR EXPECTATION(S)",
				operation_preview.exposure.supplies,
				operation_preview.exposure.materials,
				operation_preview.exposure.propellant,
				operation_preview.expectation_count,
			)
		}
		plan_label := u.route == .Passage ? "COMMISSION PASSAGE" : "PLAN OPERATION"
		if u.status == .Planning && button(R(668, 500, 240, 40), plan_label, true, true) {
			if u.route == .Far_Engagement {
				far_engagement_start(s, s.campaign.seed ~ u64(u.id))
			} else {
				if u.route == .Close_Engagement do prepare_combat_campaign_briefing(s)
				else do prepare_dark_briefing(s)
				s.screen = .Briefing
			}
		}
		if u.status == .Planning && button(R(924, 500, 280, 40), "WITHDRAW UNDERTAKING") {
			_ = game.compact_withdraw_undertaking(
				s.campaign,
				"The Compact withdrew before departure.",
			)
		}
		bottom_rail(s, "CONDUCT THE OPERATION · FACTS WILL BE REPORTED AUTOMATICALLY")
		return
	}

	draw_text("EXPEDITIONARY COMPACT", 28, 78, TYPE_TITLE)
	draw_text(
		"EXCEPTIONAL CALLS · CONTRIBUTED SHIPS · ONE UNDERTAKING",
		28,
		111,
		TYPE_SMALL,
		UX.dim,
	)
	for call, i in s.campaign.compact.calls[:s.campaign.compact.call_count] {
		y := 140 + f32(i) * 155
		active := call.status == .Open
		panel(R(28, y, 1224, 152), i == s.selected_need)
		draw_text_fitted(
			fmt.tprintf("CALL %d · %s · DEADLINE %d", call.id, call.title, call.deadline),
			R(52, y + 16, 1140, 16),
			TYPE_LABEL,
			active ? UX.warn : UX.unavailable,
		)
		draw_text_wrapped(
			call.stakes,
			R(52, y + 42, 730, 32),
			TYPE_LABEL,
			active ? UX.text : UX.dim,
		)
		sponsor_name := "Unknown sponsor"
		if sponsor_at := game.institution_index(s.campaign, call.sponsor); sponsor_at >= 0 {
			sponsor_name = s.campaign.institutions[sponsor_at].name
		}
		draw_fmt(
			52,
			y + 73,
			TYPE_FINE,
			UX.dim,
			"SPONSORED BY %s · RECORD %d · %v",
			sponsor_name,
			call.source_event,
			call.escalation,
		)
		if active {
			approaches := call.approaches
			label_caps(
				"CHOOSE AN APPROACH · EACH DESCRIPTION STATES THE KNOWN TRADE-OFF",
				52,
				y + 84,
				UX.dim,
			)
			// Keep the approach row clear of the contribution list. The previous
			// 340px cells reached into the right-hand controls, so a hovered
			// approach could be painted over a ship row.
			for approach, approach_index in approaches[:call.approach_count] {
				approach_x := 52 + f32(approach_index) * 370
				if button(
					R(approach_x, y + 98, 350, 28),
					approach.label,
					true,
					call.selected_approach == approach_index,
				) {
					r := execute_command(
						s,
						{
							kind = .Select_Compact_Approach,
							index = int(call.id),
							target = approach_index,
						},
					)
					s.status = r.message
				}
				// The choice has to be legible before it is selected. This is the
				// player-facing consequence, not a hover-only explanation.
				draw_text_wrapped(
					fmt.tprintf("%s %s", approach.operational_effect, approach.exposure_summary),
					R(approach_x, y + 128, 350, 22),
					TYPE_FINE,
					call.selected_approach == approach_index ? UX.text : UX.dim,
				)
			}
			// Ship names and their conditions are operational information, not
			// abbreviations. Reserve a dedicated right column so each row stays
			// legible and never shares space with an approach control.
			offer_x: f32 = 830
			offer_width: f32 = 370
			offers := call.offers
			for offer, offer_index in offers[:call.offer_count] {
				if offer_index >= 3 do break
				ship_at := game.ship_index(s.campaign, offer.ship)
				name := ship_at >= 0 ? s.campaign.ships[ship_at].name : "Unavailable ship"
				if button(
					R(offer_x, y + 18 + f32(offer_index) * 30, offer_width, 26),
					fmt.tprintf("%s%s · %v", offer.selected ? "✓ " : "", name, offer.condition),
					offer.available,
					offer.selected,
				) {
					r := execute_command(
						s,
						{kind = .Toggle_Compact_Offer, index = int(call.id), target = offer_index},
					)
					s.status = r.message
				}
			}
			selected := false
			for offer in offers[:call.offer_count] do selected = selected || offer.selected
			if button(R(offer_x, y + 112, offer_width, 24), "ACCEPT UNDERTAKING", selected) {
				r := execute_command(s, {kind = .Accept_Compact_Call, index = int(call.id)})
				s.status = r.message
			}
		}
	}
	if s.campaign.compact.call_count == 0 do draw_text("No exceptional calls are presently before the Compact. The world continues under standing institutions.", 52, 170, TYPE_LABEL, UX.dim)
	if s.status != "" do draw_text_fitted(s.status, R(190, 625, 1030, 20), TYPE_FINE, UX.warn)
	bottom_rail(s, "SELECT CONTRIBUTIONS · ACCEPT AN INTENT · CONDUCT THE OPERATION")
	return
}

draw_story :: proc(s: ^Ux_State) {
	top_rail(s)
	label_caps("THE STORY NOW", 28, 78, UX.committed)
	draw_fmt(
		28,
		102,
		TYPE_HEADING_LARGE,
		UX.text,
		"Year %d · Season %d · %d ships · %d people",
		s.campaign.year,
		s.campaign.season,
		s.campaign.ship_count,
		game.total_population(s.campaign),
	)
	panel(R(28, 145, 386, 450), true)
	label_caps("NOW", 52, 170, UX.info)
	situation_active :=
		s.campaign.current_situation.phase != .None &&
		s.campaign.current_situation.phase != .Resolved
	if situation_active {
		draw_text_fitted(
			s.campaign.current_situation.title,
			R(52, 204, 338, 34),
			TYPE_HEADING_COMPACT,
			UX.text,
		)
		draw_text_wrapped(
			s.campaign.current_situation.proposal,
			R(52, 248, 338, 68),
			TYPE_SMALL_EMPHASIS,
			UX.dim,
		)
		draw_text(
			"Institutions will resolve this from their authority and available evidence.",
			52,
			330,
			TYPE_FINE,
			UX.dim,
		)
	} else {
		draw_text("No exceptional situation is open.", 52, 207, TYPE_BODY_EMPHASIS, UX.good)
	}
	active_needs := 0
	for need in s.campaign.needs do if need.active && !need.resolved do active_needs += 1
	draw_fmt(
		52,
		402,
		TYPE_BODY,
		active_needs > 0 ? UX.warn : UX.good,
		"%d NEEDS AWAIT CARE",
		active_needs,
	)
	draw_fmt(
		52,
		432,
		TYPE_BODY,
		UX.info,
		"%d SETTLEMENTS · %d PRECEDENTS",
		s.campaign.settlement_count,
		s.campaign.precedent_count,
	)
	draw_fmt(
		52,
		462,
		TYPE_BODY,
		UX.text,
		"HOPE %d · COHESION %d",
		s.campaign.stability,
		s.campaign.strategic.cohesion,
	)

	panel(R(434, 145, 386, 450))
	label_caps("AUTONOMOUS WORLD", 458, 170, UX.warn)
	y := f32(204)
	q := &s.campaign.public_politics.open
	if game.public_question_active(q) {
		draw_text_wrapped(q.title, R(458, y, 338, 40), TYPE_SMALL_EMPHASIS, UX.text)
		draw_fmt(
			458,
			y + 42,
			TYPE_CAPTION,
			q.urgency == .Acting_Separately ? UX.warn : UX.committed,
			"%v · DUE S%02d",
			q.urgency,
			q.deadline,
		)
		draw_text_wrapped(q.request, R(458, y + 62, 338, 42), TYPE_CAPTION, UX.dim)
		draw_text_wrapped(
			"Visible interests, authority, capacity, and evidence determine the response without a player vote.",
			R(458, y + 112, 338, 50),
			TYPE_FINE,
			UX.info,
		)
		y += 178
	}
	for need, i in s.campaign.needs {
		if !need.active || need.resolved do continue
		draw_text_wrapped(need.detail, R(458, y, 338, 42), TYPE_SMALL, UX.text)
		draw_fmt(
			458,
			y + 44,
			TYPE_CAPTION,
			UX.warn,
			"%s %d · DUE %d",
			need_cost_name(need.kind),
			need.cost,
			need.deadline,
		)
		draw_text("WORLD PROCESS", 700, y + 44, TYPE_FINE, UX.dim)
		y += 92
	}
	if active_needs == 0 && !game.public_question_active(q) do draw_text("Institutions continue ordinary work without Compact intervention.", 458, 207, TYPE_BODY, UX.good)

	panel(R(840, 145, 412, 450))
	label_caps("RECENT RECORD", 864, 170, UX.info)
	// Chronicle details are sentences, not compact control labels. Keep the
	// summary to four taller rows so accessibility text scales can wrap without
	// shrinking the record into an unreadable single line.
	start := max(0, s.campaign.event_count - 4)
	for event, row in s.campaign.events[start:s.campaign.event_count] {
		event_index := start + row
		ey := 202 + f32(row) * 91
		draw_fmt(864, ey, TYPE_CAPTION, UX.dim, "E%03d · %v", event.sequence, event.kind)
		record_rect := R(864, ey + 16, 364, 68)
		if button(record_rect, "") {s.selected_event = event_index; open_chronicle_from(s, .Story)}
		draw_text_wrapped(
			event.detail,
			R(
				record_rect.x + 10,
				record_rect.y + 8,
				record_rect.width - 20,
				record_rect.height - 16,
			),
			TYPE_CAPTION,
			UX.text,
		)
	}
	bottom_rail(s, "SEE WHAT IS HAPPENING · FOLLOW WHAT LED HERE")
}

draw_interaction :: proc(s: ^Ux_State) {
	top_rail(s); q := &s.campaign.current_situation
	view := game.narrative_view_for_collision(s.campaign, game.collision_id_for_situation(q))
	draw_text_fitted(view.title, R(28, 76, 820, 34), TYPE_TITLE, UX.text)
	draw_fmt(
		28,
		112,
		TYPE_SMALL_EMPHASIS,
		UX.committed,
		"COUNCIL RECORD · %s · FROM E%03d",
		view.domain,
		view.origin_event,
	)
	panel(R(80, 145, 1120, 474))
	draw_text_wrapped(view.manifestation.text, R(120, 178, 1040, 48), TYPE_BODY_EMPHASIS, UX.text)
	label_caps("WHAT BROUGHT THIS HERE", 120, 236, UX.info)
	for fact, i in view.causes[:view.cause_count] do draw_fmt(120, 258 + f32(i) * 20, TYPE_SMALL, UX.dim, "E%03d · %s", fact.event, fact.text)
	if view.origin_event != 0 &&
	   button(
		   R(960, 238, 190, 24),
		   "TRACE IN CHRONICLE",
	   ) {at := game.event_index_by_sequence(s.campaign, view.origin_event); if at >= 0 {s.selected_event = at; open_chronicle_from(s, .Interaction)}}
	label_caps("WHAT IS AT STAKE", 120, 286, UX.warn)
	draw_text_wrapped(view.stakes, R(120, 307, 1040, 34), TYPE_SMALL_EMPHASIS, UX.text)
	for position, i in view.positions[:view.position_count] {y := 346 + f32(i) * 30; draw_fmt(120, y, TYPE_LABEL, UX.committed, "%s", position.actor.name); draw_text_wrapped(position.text, R(280, y - 4, 880, 26), TYPE_SMALL, UX.dim)}
	label_caps("THE COUNCIL MUST ISSUE AN ORDER", 120, 408, UX.committed)
	for affordance, i in view.affordances[:view.affordance_count] {
		x := 120 + f32(i % 2) * 520; y := 430 + f32(i / 2) * 82
		if button(
			R(x, y, 225, 34),
			affordance.label,
			affordance.available,
		) {autosave_before(s); r := execute_command(s, {kind = .Resolve_Collision, collision_id = view.id, collision_command_id = affordance.id}); s.status = r.message; if r.ok do s.screen = s.campaign.passage.active ? .Passage : .Fleet}
		draw_text_wrapped(affordance.consequence, R(x + 238, y - 5, 272, 34), TYPE_FINE, UX.text)
		detail :=
			affordance.available ? fmt.tprintf("%s · %s", affordance.cost, affordance.status) : affordance.unavailable_reason
		draw_text_fitted(
			detail,
			R(x + 238, y + 31, 272, 16),
			TYPE_FINE,
			affordance.available ? UX.info : UX.unavailable,
		)
		draw_text_fitted(
			fmt.tprintf("RISKS · %s", affordance.exposes),
			R(x + 238, y + 49, 272, 16),
			TYPE_FINE,
			UX.warn,
		)
	}
	bottom_rail(s, "DECIDE ONLY WHAT THE SHIPS CANNOT SETTLE THEMSELVES")
}
