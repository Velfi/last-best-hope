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
draw_settings :: proc(s: ^Ux_State) {draw_stars(); draw_text(
		"SETTINGS",
		80,
		72,
		TYPE_DISPLAY_COMPACT,
	)
	panel(R(80, 125, 1120, 490))
	draw_text("INTERFACE SCALE", 115, 170, TYPE_BODY, UX.dim)
	scales := [3]f32{1, 1.25, 1.5}
	for i := 0; i < len(scales); i += 1 {value := scales[i]; if radio_button(R(115 + f32(i) * 135, 205, 120, 40), fmt.tprintf("%.0f%%", value * 100), s.ui_scale == value) do s.ui_scale = value}
	draw_text("MOTION", 115, 285, TYPE_BODY, UX.dim)
	if checkbox(R(115, 320, 260, 40), "REDUCED MOTION", s.reduced_motion) do s.reduced_motion = !s.reduced_motion
	draw_text("DISPLAY", 570, 170, TYPE_BODY, UX.dim)
	displays := [2]rl.Screen_Effect{.None, .Trinitron}
	display_labels := [2]string{"CLEAN", "TRINITRON"}
	for i := 0; i < len(displays); i += 1 {effect := displays[i]
		if radio_button(R(570 + f32(i) * 180, 205, 165, 40), display_labels[i], s.screen_effect == effect) do s.screen_effect = effect
	}
	draw_text("Aperture grille · scanlines · curved glass", 570, 255, TYPE_LABEL, UX.dim)
	draw_text("HATCH DENSITY", 115, 390, TYPE_BODY, UX.dim)
	slider := R(115, 425, 360, 34)
	track_y := slider.y + slider.height * .5
	rl.DrawRectangleRec(R(slider.x, track_y - 1, slider.width, 2), UX.line)
	for stop := 0; stop < 4; stop += 1 {
		stop_x := slider.x + f32(stop) * slider.width / 3
		rl.DrawRectangleRec(R(stop_x - 1, track_y - 6, 2, 12), UX.dim)
	}
	if rl.CheckCollisionPointRec(
		   ux_mouse,
		   R(slider.x - 12, slider.y, slider.width + 24, slider.height),
	   ) &&
	   rl.IsMouseButtonDown(.LEFT) {
		t := clamp((ux_mouse.x - slider.x) / slider.width, f32(0), f32(1))
		s.hatch_density = .5 + t * 1.5
	}
	knob_x := slider.x + (s.hatch_density - .5) / 1.5 * slider.width
	rl.DrawCircleV(V(knob_x, track_y), 9, UX.text)
	rl.DrawCircleV(V(knob_x, track_y), 5, UX.void)
	draw_text("50%", slider.x, 468, TYPE_LABEL, UX.dim)
	draw_text("200%", slider.x + slider.width - 34, 468, TYPE_LABEL, UX.dim)
	draw_text(fmt.tprintf("%.0f%%", s.hatch_density * 100), knob_x - 18, 397, TYPE_LABEL, UX.text)

	// Update immediately so the adjacent swatch responds during the drag frame.
	rl.SetHatchDensity(hatch_density_spacing_scale(s.hatch_density))
	rl.SetScreenEffect(s.screen_effect, s.reduced_motion)
	draw_text("EXAMPLE", 570, 390, TYPE_BODY, UX.dim)
	preview := R(570, 425, 540, 62)
	preview_hatch := LBH_HATCH_ENGRAVING
	preview_hatch.invert = true
	preview_hatch.spacing = 7
	preview_hatch.layer_count = 2
	preview_hatch.rotation = .12
	preview_hatch.irregularity = .24
	rl.DrawQuadHatched(
		V(preview.x, preview.y),
		V(preview.x + preview.width, preview.y),
		V(preview.x + preview.width, preview.y + preview.height),
		V(preview.x, preview.y + preview.height),
		{196, 198, 187, 145},
		preview_hatch,
	)
	rl.DrawRectangleRoundedLinesEx(preview, 0, 0, 1, UX.line)
	draw_text(
		"All danger states use labels and shapes in addition to color.",
		115,
		500,
		TYPE_BODY,
		UX.info,
	)
	draw_text(
		"Keyboard: TAB focus · ENTER confirm · ESC focus back · 1–8 select.",
		115,
		535,
		TYPE_BODY,
		UX.dim,
	)
	if back_button(R(80, 640, 150, 38), "BACK") {
		s.screen = s.return_screen
		if s.settings_from_pause {
			s.settings_from_pause = false
			s.pause_return_screen = s.screen
			s.pause_menu_open = true
		}
	}}

draw_credits :: proc(s: ^Ux_State) {draw_stars(); draw_text("LAST BEST HOPE", 80, 90, TYPE_DISPLAY)
	draw_text("DESIGN & ENGINEERING", 80, 155, TYPE_BODY_COMPACT, UX.info)
	draw_text(
		"A deterministic fleet chronicle built with Odin and zelda-engine.",
		80,
		190,
		TYPE_BODY_EMPHASIS,
	)
	draw_text(
		"Ships are persistent characters. History is the progression system.",
		80,
		230,
		TYPE_BODY_EMPHASIS,
		UX.dim,
	)
	if back_button(R(80, 640, 150, 38), "BACK") do s.screen = .Menu}

draw_modal :: proc(s: ^Ux_State) {
	if s.modal == .None && game.candidate_celebration_pending(s.campaign) {
		s.modal = .Habitable_Discovery
	}
	switch s.modal {
	case .None:
		return
	case .Body_Detail:
		draw_celestial_body_modal(s)
		return
	case .Ship_Detail:
		draw_ship_detail_modal(s)
		return
	case .Food_Shortage:
		draw_food_shortage_modal(s)
		return
	case .Economy_Loss:
		rl.DrawRectangle(0, 0, UX_W, UX_H, {0, 0, 0, 205}); panel(R(300, 190, 680, 300), true)
		draw_text("A SHIP CANNOT BE MAINTAINED", 340, 225, TYPE_HEADING_COMPACT, UX.warn)
		draw_text_wrapped(
			"Commit 2 Equipment and 2 Services to preserve the ship. Abandonment permanently loses it, removes its hull from maintenance demand, and recovers 4 Raw Materials and 2 Equipment.",
			R(340, 275, 600, 78),
			TYPE_BODY_COMPACT,
			UX.text,
		)
		cost := game.Fleet_Stock {
			equipment = 2,
			services  = 2,
		}; can_preserve := game.fleet_stock_can_spend(
			s.campaign.material_economy.fleet.stock,
			cost,
		)
		if button(
			R(340, 390, 250, 42),
			"PRESERVE SHIP",
			can_preserve,
			true,
		) {r := execute_command(s, {kind = .Resolve_Economy_Loss, flag = true}); s.status = r.message; if r.ok do s.modal = .None}
		if button(
			R(650, 390, 250, 42),
			"RECORD ABANDONMENT",
			true,
		) {r := execute_command(s, {kind = .Resolve_Economy_Loss, flag = false}); s.status = r.message; if r.ok do s.modal = .None}
		return
	case .Stranded_Outcome:
		rl.DrawRectangle(0, 0, UX_W, UX_H, {0, 0, 0, 205}); panel(R(280, 170, 720, 340), true)
		draw_text("A ROUTE HOME", 320, 205, TYPE_HEADING_COMPACT, UX.good)
		candidate := s.campaign.stranded_outcome_candidate
		if candidate >= 0 && candidate < s.campaign.stranded_passage_group_count {
			group := &s.campaign.stranded_passage_groups[candidate]
			years := (s.campaign.season - group.stranded_season) * 3
			returned := group.outcome == .Returned_Home
			basis := game.stranded_choice_basis(s.campaign, group, returned)
			message :=
				returned ? fmt.tprintf("After %d years, the relay expedition accepted the fleet's standing invitation and returned home. %s", years, basis) : fmt.tprintf("After %d years, the relay expedition reported that it would remain with the independent community it established. %s", years, basis)
			draw_text_wrapped(message, R(320, 255, 640, 82), TYPE_BODY_COMPACT, UX.text)
		}
		if button(
			R(550, 410, 180, 42),
			"ACKNOWLEDGE",
			true,
			true,
		) {r := execute_command(s, {kind = .Acknowledge_Stranded_Outcome}); s.status = r.message; if r.ok do s.modal = .None}
		return
	case .Habitable_Discovery:
		candidate, ok := game.candidate_celebration(s.campaign)
		if !ok {s.modal = .None; return}
		rl.DrawRectangle(0, 0, UX_W, UX_H, {0, 0, 0, 205})
		panel(R(250, 135, 780, 430), true)
		natural := candidate.profile.classification == .Naturally_Habitable
		confirmation :=
			natural ? "The survey has confirmed %s in the %s system as naturally habitable." : "The survey has confirmed %s in the %s system as settlement-capable with engineered support."
		draw_text(
			natural ? "A HABITABLE WORLD" : "A WORLD WITHIN REACH",
			300,
			180,
			TYPE_DISPLAY_COMPACT,
			UX.good,
		)
		draw_text_wrapped(
			fmt.tprintf(
				confirmation,
				candidate.reference.planet_name,
				candidate.reference.system_name,
			),
			R(300, 245, 680, 70),
			TYPE_BODY_LARGE,
			UX.text,
		)
		draw_text_wrapped(
			fmt.tprintf(
				"For one watch, ships repeated the name %s across open channels. The confirmed ephemeris is now part of the fleet record.",
				candidate.reference.planet_name,
			),
			R(300, 330, 680, 75),
			TYPE_BODY_COMPACT,
			UX.dim,
		)
		draw_text(
			"Settlement still requires an approved proposal and a prepared colony package.",
			300,
			430,
			TYPE_FINE,
			UX.info,
		)
		if button(R(510, 490, 260, 42), "RECORD THE WORLD", true, true) {
			r := execute_command(s, {kind = .Acknowledge_Habitable_Discovery})
			s.status = r.message
			if r.ok do s.modal = .None
		}
		return
	case .Opening_Note:
		if !s.opening_note_ready {
			report := game.estimate_galaxy_habitability(
				s.campaign.galaxy,
				.Evidence_Centered,
				8192,
			)
			s.opening_note_population = game.total_population(s.campaign)
			s.opening_note_habitable_worlds =
				report.tiers[int(game.Habitability_Tier.Long_Term_Habitable)].median
			s.opening_note_planet_systems =
				report.tiers[int(game.Habitability_Tier.Any_Planet)].median
			s.opening_note_ready = true
		}
		ratio := 0.0
		if s.opening_note_planet_systems > 0 do ratio = 100 * s.opening_note_habitable_worlds / s.opening_note_planet_systems
		rl.DrawRectangle(0, 0, UX_W, UX_H, {0, 0, 0, 215})
		panel(R(272, 132, 736, 456), true)
		label_caps("OPENING RECORD", 322, 176, UX.info)
		draw_text("THE SEARCH", 322, 214, TYPE_DISPLAY_COMPACT, UX.text)
		draw_text_wrapped(
			fmt.tprintf(
				"Forced to take to the stars, your people number %d.",
				s.opening_note_population,
			),
			R(322, 290, 636, 44),
			TYPE_BODY_LARGE,
			UX.text,
		)
		draw_text_wrapped(
			fmt.tprintf(
				"There are approximately %.0f long-term habitable worlds in this galaxy.",
				s.opening_note_habitable_worlds,
			),
			R(322, 352, 636, 48),
			TYPE_BODY_LARGE,
			UX.text,
		)
		draw_text_wrapped(
			fmt.tprintf("That is %.3f%% of all planet-hosting systems.", ratio),
			R(322, 414, 636, 44),
			TYPE_BODY_LARGE,
			UX.text,
		)
		draw_text("Find them.", 322, 484, TYPE_HEADING_COMPACT, UX.committed)
		if button(R(526, 526, 228, 40), "BEGIN THE SEARCH", true, true) {
			s.modal = .None
			open_opening_council(s)
		}
		return
	case .Advance, .Conclude:
		rl.DrawRectangle(0, 0, UX_W, UX_H, {0, 0, 0, 180})
		panel(R(360, 220, 560, 250))
		title := s.modal == .Advance ? "ADVANCE THE SEASON" : "CONCLUDE THE CHRONICLE"
		message :=
			s.modal == .Advance ? "Advance fleet time and resolve the next season." : !s.campaign.ending_finale.active ? fmt.tprintf("Lock %s as the fleet's ending, then play three final seasons.", game.ending_name(game.ending_identity(s.campaign))) : "Record the ending and its condition after the three-season finale."
		confirm :=
			s.modal == .Advance ? "ADVANCE" : !s.campaign.ending_finale.active ? "BEGIN FINALE" : "RECORD ENDING"
		draw_text(title, 395, 255, TYPE_HEADING_COMPACT)
		draw_text_wrapped(message, R(395, 300, 490, 55), TYPE_BODY_COMPACT, UX.text)
		if s.modal == .Conclude &&
		   s.campaign.ending_prompt_pending &&
		   !s.campaign.ending_finale.active {
			if button(
				R(395, 390, 220, 40),
				"CONTINUE ENDLESS",
			) {r := execute_command(s, {kind = .Convert_To_Endless}); s.status = r.message; if r.ok do s.modal = .None}
		} else if button(R(395, 390, 180, 40), "CANCEL") do s.modal = .None
		if button(R(690, 390, 180, 40), confirm, true, true) {
			modal := s.modal
			s.modal = .None
			if modal == .Advance {
				_ = execute_command(s, {kind = .Advance_Season})
			} else if modal == .Conclude {
				r := execute_command(s, {kind = .Conclude_Chronicle}); s.status = r.message
				if s.campaign.ending != .In_Progress do s.screen = .Ending
			}
		}
	case .Departure, .Return, .Extraction, .Settlement, .Abandon_Cargo, .Project, .Result:
		// These retired modal states must never borrow another modal's copy or
		// action. Keeping them explicit makes new modal work compiler-visible.
		rl.DrawRectangle(0, 0, UX_W, UX_H, {0, 0, 0, 180})
		panel(R(360, 220, 560, 210))
		draw_text("ACTION UNAVAILABLE", 395, 255, TYPE_HEADING_COMPACT, UX.warn)
		draw_text_wrapped(
			"This action is unavailable. No campaign action was taken.",
			R(395, 300, 490, 45),
			TYPE_BODY_COMPACT,
			UX.text,
		)
		if button(R(550, 365, 180, 40), "CLOSE", true, true) do s.modal = .None
	}
}

draw_ending :: proc(s: ^Ux_State) {draw_stars(); draw_text(
		"CHRONICLE CONCLUDED",
		80,
		80,
		TYPE_DISPLAY_LARGE,
	)
	draw_fmt(80, 145, TYPE_TITLE_COMPACT, UX.good, "%s", game.ending_name(s.campaign.ending))
	draw_fmt(
		80,
		180,
		TYPE_HEADING_COMPACT,
		s.campaign.ending_quality == .Fragile ? UX.warn : UX.good,
		"%s",
		game.ending_quality_name(s.campaign.ending_quality),
	)
	draw_text("Recorded after a three-season finale.", 80, 220, TYPE_BODY_LARGE, UX.dim)
	panel(R(80, 255, 1120, 300))
	draw_fmt(
		115,
		292,
		TYPE_BODY_EMPHASIS,
		UX.text,
		"POPULATION %d · SHIPS ACTIVE %d",
		game.total_population(s.campaign),
		s.campaign.ship_count,
	)
	draw_fmt(
		115,
		330,
		TYPE_BODY_EMPHASIS,
		UX.text,
		"PRECEDENTS %d · SETTLEMENTS %d · EVENTS %d",
		s.campaign.precedent_count,
		s.campaign.settlement_count,
		s.campaign.event_count,
	)
	label_caps("RECORDED CONSEQUENCES", 115, 375)
	for evidence, i in s.campaign.ending_evidence[:s.campaign.ending_evidence_count] do draw_text(evidence, 115, 405 + f32(i) * 34, TYPE_BODY, UX.dim)
	if button(R(80, 620, 220, 40), "REVIEW CHRONICLE") do open_chronicle_from(s, .Ending)
	if button(R(320, 620, 220, 40), "MAIN MENU") do s.screen = .Menu}

draw_app :: proc(s: ^Ux_State) {ux_text_scale = s.ui_scale; ux_button_cursor = 0; ux_tooltip = {}
	// Keep the screen visible behind a modal without letting it share the
	// modal's pointer press.
	ux_pointer_input_blocked = s.modal != .None
	now_campaign := rl.GetTime()
	campaign_dt :=
		s.campaign_last_time > 0 ? clamp(now_campaign - s.campaign_last_time, f64(0), f64(.25)) : f64(0)
	s.campaign_last_time = now_campaign
	campaign_view :=
		s.screen == .Fleet ||
		s.screen == .Navigation ||
		s.screen == .Story ||
		s.screen == .Care ||
		s.screen == .Galaxy ||
		s.screen == .Chronicle ||
		s.screen == .Build ||
		s.screen == .Briefing ||
		s.screen == .Settlement_Proposal ||
		s.screen == .Interaction
	// Routine dossiers and management panels do not stop fleet work. Pivotal
	// modals already raise shared attention, which pauses authoritatively.
	if campaign_view && !s.pause_menu_open {
		_ = game.campaign_tick(s.campaign, campaign_dt)
	}
	rl.SetHatchDensity(hatch_density_spacing_scale(s.hatch_density))
	manga_backdrop()
	if s.pause_menu_open {
		draw_pause_menu(s)
		ux_focus_back_requested = false
		return
	}
	if s.deep_exploration_active && s.screen == .Menu do deep_exploration_restore_story(s)
	if s.far_engagement_standalone && s.screen == .Menu do far_engagement_restore_story(s)
	#partial switch s.screen {case .Menu:
		draw_menu(s); case .Skirmish_Setup:
		draw_skirmish_setup(s); case .Deep_Exploration_Setup:
		draw_deep_exploration_setup(s); case .Operation_Planning:
		draw_operation_planning(s); case .Setup:
		draw_setup(s); case .Fleet:
		draw_fleet(s); case .Navigation:
		draw_navigation(s); case .Story:
		draw_story(s); case .Care:
		draw_care(s); case .Galaxy:
		// The celestial survey is an opaque archival plate. Rebuilding the full
		// animated galaxy behind it cannot affect the visible result and used to
		// dominate planet-detail frame construction.
		if s.modal != .Body_Detail do draw_galaxy_map(s)
	case .Chronicle:
		draw_chronicle(s); case .Build:
		draw_build(s); case .Briefing:
		draw_briefing(s); case .Passage:
		draw_passage(s); case .Debrief:
		draw_debrief(s); case .Settlement_Proposal:
		draw_settlement_proposal(s); case .Interaction:
		draw_interaction(s); case .Guidebook:
		draw_guidebook(s); case .Settings:
		draw_settings(s); case .Credits:
		draw_credits(s); case .Ending:
		draw_ending(s); case .Combat:
		now := rl.GetTime(); dt := f32(now - s.combat_last_time); s.combat_last_time = now
		if !s.combat_briefing &&
		   !s.combat_paused &&
		   !s.combat.complete &&
		   !s.campaign.clock.paused_for_attention {
			game.combat_tick(&s.combat, dt * s.combat_speed)
		}
		if s.combat_campaign_active {
			s.campaign.combat_runtime = &s.combat
			game.campaign_sync_close_engagement(s.campaign, &s.combat)
		}
		draw_combat(s)
	case .Ship_Generator:
		draw_ship_generator(s)
	case .Far_Engagement:
		draw_far_engagement(s)}
	if s.screen == .Fleet || s.screen == .Care || s.screen == .Briefing || s.screen == .Passage do draw_first_season_guide(s)
	if s.modal == .None do draw_tooltip()
	ux_pointer_input_blocked = false
	draw_modal(s)
	// An Escape press is intentionally frame-local. Screens without a Back
	// control ignore it instead of carrying the request into a later screen.
	ux_focus_back_requested = false
}
