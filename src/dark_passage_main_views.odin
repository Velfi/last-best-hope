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
draw_dark_passage_compact :: proc(s: ^Ux_State) {
	p := &s.campaign.passage; d := &s.campaign.outer_dark.continuum
	now := rl.GetTime(
		
	); elapsed := s.dark_last_time > 0 ? clamp(now - s.dark_last_time, f64(0), f64(.1)) : f64(0); s.dark_last_time = now
	dark_discrete_controls(s)
	dark_manual_helm(s)
	if !d.paused &&
	   !s.campaign.clock.paused_for_attention &&
	   elapsed >
		   0 {if p.phase == .Underway {game.advance_passage(s.campaign, p, elapsed)} else {game.advance_dark_continuum(d, elapsed)}}
	game.campaign_sync_passage(s.campaign, p)
	dark_select_course_hold_contact(s)
	if rl.IsKeyPressed(.SPACE) do d.paused = !d.paused
	draw_continuous_dark_3d_overlay(s); dark_pick_targets(s); dark_draw_navigation_feedback(s)
	if rl.IsKeyPressed(
		.ESCAPE,
	) {s.dark_contacts_open = false; s.dark_comms_open = false; s.dark_missing_confirm = false; s.dark_exit_confirm = false; s.dark_intent_open = false; s.dark_fine_plot_open = false}
	dark_draw_expedition_card(s)
	// Route commitments live in the contextual decision tray, leaving the
	// upper edge quiet enough for the map to carry the expedition's mood.
	if button(
		R(392, 16, 178, 30),
		fmt.tprintf("SENS · %s", game.dark_sensor_posture_name(p.dark_navigation.sensor_posture)),
	) {
		next := game.Dark_Sensor_Posture((int(p.dark_navigation.sensor_posture) + 1) % 4)
		_, s.status = game.set_dark_sensor_posture(s.campaign, p, next)
	}
	if button(R(578, 16, 128, 30), "POLICY") do s.dark_intent_open = !s.dark_intent_open
	if button(
		R(918, 16, 104, 30),
		"TARGETS",
	) {s.dark_contacts_open = !s.dark_contacts_open; s.dark_comms_open = false}
	if button(
		R(1030, 16, 104, 30),
		"RECORDS",
	) {s.dark_comms_open = !s.dark_comms_open; s.dark_contacts_open = false; s.dark_missing_confirm = false}
	if button(R(1142, 16, 54, 30), d.paused ? "RUN" : "PAUSE", true, d.paused) do d.paused = !d.paused
	if button(
		R(1202, 16, 54, 30),
		"EXIT",
	) {s.dark_exit_confirm = true; s.dark_contacts_open = false; s.dark_comms_open = false}
	arrival_door := game.dark_door_at_position(d, p.dark_navigation.position)
	selected_door, has_selected_door := dark_selected_door(s)
	selected_alternate_door :=
		has_selected_door &&
		p.phase == .Awaiting_Leg &&
		p.pause_reason == .Course_Arrival &&
		arrival_door >= 0 &&
		selected_door.id != d.doors[arrival_door].id
	if s.dark_intent_open {
		dark_draw_intent_tray(s)
	} else if dark_draw_coherence_tray(
		s,
	) {} else if dark_draw_obstruction_tray(s) {} else if track, ok := dark_selected_track(s); ok {dark_draw_contact_tray(s, track)} else if p.phase == .Underway {dark_draw_underway_tray(s)} else if selected_alternate_door {dark_draw_course_tray(s, selected_door)} else if dark_draw_arrival_tray(s) {} else if has_selected_door {dark_draw_course_tray(s, selected_door)} else {
		dark_draw_descent_tray(s)
	}
	dark_draw_contacts_leaf(s); dark_draw_comms_leaf(s)
	dark_draw_exit_confirmation(s)
}

draw_passage :: proc(s: ^Ux_State) {
	p := &s.campaign.passage
	if p.domain == .Dark {draw_dark_passage_compact(s); return}
	top_rail(s)
	draw_text(
		"CONTINUOUS DARK EXPEDITION",
		28,
		78,
		TYPE_TITLE,
	); panel(R(28, 130, 1224, 500)); draw_fmt(58, 160, TYPE_BODY_EMPHASIS, UX.text, "PHASE %v · DOMAIN %v", p.phase, p.domain); draw_fmt(58, 192, TYPE_BODY_COMPACT, UX.info, "PURPOSE %v · EVIDENCE %d", p.contract.purpose, p.contract.evidence_count); draw_fmt(58, 220, TYPE_SMALL_EMPHASIS, UX.dim, "SHIP %.2f D · MEMBRANE %.2f D · COST %.2f", p.elapsed_days, p.membrane_elapsed_days, p.course_cost)
	if p.domain == .Normal_Space do draw_fmt(650, 220, TYPE_LABEL, UX.dim, "GALAXY POSITION  %.2f  %.2f  %.2f KPC", p.normal_course.current_position[0], p.normal_course.current_position[1], p.normal_course.current_position[2])
	y := f32(285)
	if p.phase == .Awaiting_Leg && p.domain == .Dark {
		draw_fmt(
			58,
			y - 38,
			TYPE_CAPTION,
			UX.dim,
			"DRAFT %d POINTS · Z %+.1f · IN/OUT %+.1f",
			s.dark_course_draft.waypoint_count,
			s.dark_waypoint_z,
			s.dark_waypoint_w,
		)
		if button(R(58, y, 54, 34), "Z−") do s.dark_waypoint_z -= .5
		if button(R(118, y, 54, 34), "Z+") do s.dark_waypoint_z += .5
		if button(R(178, y, 54, 34), "OUT") do s.dark_waypoint_w -= .5
		if button(R(238, y, 54, 34), "IN") do s.dark_waypoint_w += .5
		if button(
			R(58, y + 44, 174, 34),
			"PLOT DRAFT",
			s.dark_course_draft.waypoint_count >= 2,
		) {_, ok := game.plot_passage_course(s.campaign, p, s.dark_course_draft); if ok do s.dark_course_draft = {}}
		if button(R(238, y + 44, 70, 34), "CLEAR") do s.dark_course_draft = {}
		y += 92
	}
	if p.phase == .Awaiting_Leg &&
	   p.domain ==
		   .Dark {if button(R(58, y, 280, 38), "SUGGEST UNKNOWN CORRESPONDENCE") {course, found := game.passage_course_to_unknown_door(s.campaign, p, -1); if found {s.dark_course_draft = course} else {s.status = "No unknown correspondence is currently reachable."}}}
	if p.phase ==
	   .Underway {if button(R(58, y, 280, 42), "ADVANCE EXPEDITION") do game.advance_passage(s.campaign, p, normal_space_advance_elapsed(p))}
	if p.phase == .Awaiting_Leg &&
	   p.domain ==
		   .Dark {if button(R(360, y, 240, 42), "CROSS CORRESPONDENCE") {_, s.status = game.cross_passage_door(s.campaign, p)}}
	if p.phase == .Awaiting_Leg &&
	   p.domain ==
		   .Dark {if button(R(360, y + 50, 240, 34), "DECLARE VOYAGE MISSING") {_, s.status = game.declare_passage_missing(s.campaign, p); s.screen = s.deep_exploration_active ? .Menu : .Fleet}}
	if p.phase == .Awaiting_Leg && p.domain == .Normal_Space {
		return_available := game.passage_dark_return_available(s.campaign, p, p.pending_door_id)
		if button(
			R(58, y, 300, 42),
			"RETURN TO THE DARK",
			return_available,
			return_available,
		) {_, s.status = game.enter_passage_dark(s.campaign, p, p.pending_door_id)}
	}
	if p.phase != .Underway && p.domain == .Normal_Space {
		at_fleet :=
			p.normal_course.start_neighborhood ==
			s.campaign.outer_dark.continuum.anchor_neighborhood
		if at_fleet &&
		   button(
			   R(58, y + 98, 300, 42),
			   "END MISSION AND RETURN HOME",
		   ) {if game.set_passage_safe_endpoint(s.campaign, p, .Fleet) {_, s.status = game.conclude_passage(s.campaign, p); s.screen = .Debrief} else do s.status = "The expedition has not reached the fleet."}
		relay_at := game.dark_relay_at_neighborhood(s.campaign, p.normal_course.start_neighborhood)
		return_available := game.passage_dark_return_available(s.campaign, p, p.pending_door_id)
		if !at_fleet &&
		   !return_available &&
		   button(
			   R(58, y + 98, 400, 42),
			   "TRANSMIT AND TRY TO LIVE HERE",
			   relay_at >= 0,
		   ) {relay := s.campaign.dark_relays[relay_at]; if game.set_passage_safe_endpoint(s.campaign, p, .Authenticated_Relay, relay.id) {_, s.status = game.conclude_passage(s.campaign, p); s.screen = .Debrief}}
	}
	if p.domain == .Normal_Space {
		dark_draw_emergence_galaxy(s, R(650, 252, 540, 190))
		draw_text_wrapped(s.status, R(650, 458, 540, 44), TYPE_BODY_COMPACT, UX.text)
		if s.campaign.settlement_economies.count > 0 do draw_trade_dependency_record(s, 650, 510, 500, max_rows = 1)
	} else {
		draw_text_wrapped(s.status, R(650, 285, 500, 90), TYPE_BODY_COMPACT, UX.text)
		if s.campaign.settlement_economies.count > 0 do draw_trade_dependency_record(s, 650, 390, 500, max_rows = 2)
	}
	bottom_rail(s, "THE DARK HOLDS UNCERTAINTY; THE CONTRACT HOLDS ACCOUNTABILITY")
}

draw_debrief :: proc(s: ^Ux_State) {
	if s.deep_exploration_active {
		p := &s.campaign.passage
		draw_stars(); panel(R(245, 80, 790, 560), true)
		draw_text("EXPEDITION RECORD", 285, 116, TYPE_TITLE_LARGE, UX.text)
		draw_fmt(
			285,
			162,
			TYPE_BODY_EMPHASIS,
			UX.text,
			"%s",
			game.deep_exploration_purpose_name(p.contract.purpose),
		)
		draw_text(
			dark_objective_progress_text(s.campaign, p),
			285,
			186,
			TYPE_SMALL_EMPHASIS,
			p.contract.objective_met ? UX.good : UX.warn,
		)
		draw_fmt(285, 224, TYPE_BODY, UX.text, "SHIP TIME              %.2f DAYS", p.elapsed_days)
		draw_fmt(
			285,
			260,
			TYPE_BODY,
			UX.text,
			"MEMBRANE TIME          %.2f DAYS",
			p.membrane_elapsed_days,
		)
		draw_fmt(285, 296, TYPE_BODY, UX.text, "COURSE COST            %.2f", p.course_cost)
		draw_fmt(
			285,
			332,
			TYPE_BODY,
			p.coherence_incidents > 0 ? UX.warn : UX.text,
			"COHERENCE INCIDENTS    %d",
			p.coherence_incidents,
		)
		draw_fmt(285, 368, TYPE_BODY, UX.info, "CORRESPONDENCES MAPPED %d", p.local_atlas_count)
		draw_fmt(
			285,
			404,
			TYPE_BODY,
			UX.info,
			"ECOLOGICAL RECORDS     %d",
			p.local_observation_count,
		)
		draw_text_wrapped(
			"This standalone record will be discarded when you return to the main menu.",
			R(285, 448, 680, 52),
			TYPE_BODY_COMPACT,
			UX.dim,
		)
		if button(R(285, 552, 230, 40), "RETURN TO MENU", true, true) do s.screen = .Menu
		return
	}
	top_rail(s)
	draw_text("FACTUAL DEBRIEF", 28, 78, TYPE_TITLE)
	panel(R(28, 130, 1224, 500))
	aftermath := &s.campaign.pending_aftermath
	if aftermath.id != 0 {
		draw_fmt(
			58,
			165,
			TYPE_BODY_EMPHASIS,
			UX.text,
			"OPERATION %d · UNDERTAKING %d",
			aftermath.id,
			aftermath.undertaking_id,
		)
		draw_fmt(58, 198, TYPE_BODY_COMPACT, UX.text, "OBJECTIVE STATE · %v", aftermath.objective)
		draw_fmt(
			58,
			230,
			TYPE_BODY_COMPACT,
			UX.text,
			"PARTICIPANTS %d · LOSSES %d · WITHDRAWALS %d",
			aftermath.ship_count,
			aftermath.losses,
			aftermath.withdrawals,
		)
		draw_fmt(
			58,
			262,
			TYPE_BODY_COMPACT,
			UX.text,
			"EVIDENCE %d · DEVIATIONS %d · OBSERVATIONS %d",
			aftermath.evidence_recovered,
			aftermath.deviations,
			aftermath.observation_count,
		)
	} else {
		draw_text(
			"The factual expedition record has entered the Chronicle.",
			58,
			170,
			TYPE_BODY,
			UX.text,
		)
	}
	if button(R(58, 500, 220, 42), "RETURN TO FLEET") do s.screen = .Fleet
	bottom_rail(s, "FACTS · EVIDENCE · AUTONOMOUS RESPONSE")
}

guidebook_mass_range_label :: proc(low, high: i64) -> string {
	if low >= 1000000 do return fmt.tprintf("%.1f–%.1f Mt", f64(low) / 1000000, f64(high) / 1000000)
	if low >= 1000 do return fmt.tprintf("%.0f–%.0f kt", f64(low) / 1000, f64(high) / 1000)
	return fmt.tprintf("%d–%d t", low, high)
}

draw_guidebook :: proc(s: ^Ux_State) {
	draw_stars(
		
	); draw_text("SHIP GUIDEBOOK", 54, 44, TYPE_DISPLAY_COMPACT, UX.text); draw_text("PRODUCTION HULLS · OPERATIONAL CONFIGURATIONS · FIELD RESPONSES", 54, 82, TYPE_SMALL, UX.info)
	if s.guide_family == .Unspecified do s.guide_family = .Strike_Craft
	families := [6]game.Ship_Family {
		.Strike_Craft,
		.Light_Combatant,
		.Frigate,
		.Line_Warship,
		.Carrier_And_Command,
		.Diaspora,
	}
	panel(R(42, 116, 206, 500)); label_caps("FAMILIES", 62, 138)
	for family, i in families do if radio_button(R(60, 168 + f32(i) * 48, 170, 38), game.ship_family_name(family), !s.guide_tactics && s.guide_family == family) {s.guide_family = family; s.guide_role = .Unspecified; s.guide_tactics = false}
	divider(60, 470, 170)
	if radio_button(R(60, 492, 170, 42), "COMBAT BASICS", s.guide_tactics) do s.guide_tactics = true
	if s.guide_tactics {
		panel(R(264, 116, 974, 500), true)
		draw_text("SPACE COMBAT, IN PLAIN TERMS", 292, 142, TYPE_HEADING_LARGE, UX.text)
		draw_text(
			"WIN THE OBJECTIVE. KEEP THE FLEET ABLE TO COME HOME.",
			292,
			178,
			TYPE_SMALL,
			UX.info,
		)
		divider(292, 204, 918)
		label_caps("1 · DO THE JOB", 292, 224)
		draw_text_wrapped(
			"You rarely need to destroy everything. Take the relays, protect the recovery ship, secure the objective, and reach extraction.",
			R(292, 250, 278, 76),
			TYPE_BODY_COMPACT,
			UX.text,
		)
		label_caps("2 · KEEP A SCREEN", 292, 350)
		draw_text_wrapped(
			"Put fighters, interceptors, corvettes, or flak between bombers and the ships you cannot afford to lose. Guard orders keep the screen close.",
			R(292, 376, 278, 88),
			TYPE_BODY_COMPACT,
			UX.text,
		)
		label_caps("3 · MATCH THE THREAT", 610, 224)
		draw_text_wrapped(
			"Fighters catch bombers. Flak breaks up strike craft. Bombers and torpedo boats threaten capital ships. These are advantages, not automatic wins.",
			R(610, 250, 278, 88),
			TYPE_BODY_COMPACT,
			UX.text,
		)
		label_caps("4 · USE THE MAP", 610, 350)
		draw_text_wrapped(
			"Debris and wreckage reduce incoming fire, especially bomber attacks. Open lanes help capital guns. A shot into a capital ship's rear quarter hits much harder.",
			R(610, 376, 278, 96),
			TYPE_BODY_COMPACT,
			UX.text,
		)
		label_caps("5 · STAY IN SUPPORT", 928, 224)
		draw_text_wrapped(
			"Defensive fire, jamming, and repair protect nearby allies. Sensors help relay control. Strike craft lose readiness when they range too far from a flight deck.",
			R(928, 250, 278, 88),
			TYPE_BODY_COMPACT,
			UX.text,
		)
		label_caps("6 · LEAVE IN TIME", 928, 350)
		draw_text_wrapped(
			"Withdraw damaged ships before they are cut off. Recovery vessels can restore disabled elements, but both ships still need a safe route to extraction.",
			R(928, 376, 278, 88),
			TYPE_BODY_COMPACT,
			UX.text,
		)
		divider(292, 492, 914)
		label_caps("A SIMPLE PLAN", 292, 510)
		draw_text_wrapped(
			"Screen the vulnerable ships · move sensors toward the relays · keep support close · send the right attacker at the right target · withdraw before the route closes.",
			R(292, 536, 914, 60),
			TYPE_SMALL_EMPHASIS,
			UX.warn,
		)
		if back_button(R(42, 646, 160, 38), "BACK") do s.screen = s.return_screen
		return
	}
	panel(R(264, 116, 284, 500)); label_caps(game.ship_family_name(s.guide_family), 284, 138)
	first := game.Ship_Operational_Role.Unspecified; row := 0
	for value in 1 ..= game.SHIP_OPERATIONAL_ROLE_COUNT {role := game.Ship_Operational_Role(value); if game.ship_operational_role_family(role) != s.guide_family do continue; if first == .Unspecified do first = role; if radio_button(R(282, 166 + f32(row) * 36, 248, 30), game.ship_operational_role_name(role), s.guide_role == role) do s.guide_role = role; row += 1}
	if s.guide_role == .Unspecified || game.ship_operational_role_family(s.guide_role) != s.guide_family do s.guide_role = first
	role :=
		s.guide_role; hull := game.ship_operational_role_hull(role); profile := game.ship_operational_profile(role)
	panel(R(564, 116, 674, 500), true)
	draw_ship_hull_archetype_icon(hull, R(590, 140, 126, 126), UX.text)
	draw_text(
		game.ship_operational_role_name(role),
		744,
		148,
		TYPE_TITLE_COMPACT,
		UX.text,
	); draw_fmt(744, 184, TYPE_SMALL, UX.info, "%s · %s", game.ship_hull_archetype_name(hull), game.ship_family_name(s.guide_family)); guide_weapon := game.ship_weapon_package_for(1, hull, role); draw_fmt(744, 208, TYPE_LABEL, UX.dim, "ARMAMENT %s · MODULES %v", game.ship_weapon_package_name(guide_weapon), game.ship_operational_role_modules(role))
	low_mass, high_mass := game.ship_hull_archetype_mass_range(
		hull,
	); tonnage_band := game.ship_tonnage_band(game.ship_hull_archetype_nominal_mass(hull)); draw_fmt(744, 232, TYPE_LABEL, UX.text, "DISPLACEMENT %s · TONNAGE %d/5", guidebook_mass_range_label(low_mass, high_mass), tonnage_band)
	for mark in 0 ..< 5 {color := UX.unavailable; if mark < tonnage_band do color = UX.info; rl.DrawRectangleRec(R(744 + f32(mark) * 34, 254, 28, 5), color)}
	divider(
		590,
		278,
		620,
	); label_caps("FUNCTION", 590, 296); draw_text_wrapped(game.ship_operational_role_function(role), R(590, 320, 610, 50), TYPE_BODY, UX.text)
	label_caps(
		"FIELD RESPONSE",
		590,
		382,
	); draw_text_wrapped(game.ship_operational_role_response(role), R(590, 406, 610, 58), TYPE_BODY_COMPACT, UX.warn)
	divider(590, 477, 620); label_caps("CAPABILITY RECORD", 590, 494)
	draw_fmt(
		590,
		520,
		TYPE_LABEL,
		UX.text,
		"RECON %d · STEALTH %d · INTERCEPT %d · ANTI-SHIP %d · POINT DEFENSE %d",
		profile.recon,
		profile.stealth,
		profile.interception,
		profile.anti_ship,
		profile.point_defense,
	)
	draw_fmt(
		590,
		542,
		TYPE_LABEL,
		UX.text,
		"BOARD %d · CAPTURE %d · EW %d · ACTIVE DEF %d · RANGE %d · DENIAL %d",
		profile.boarding,
		profile.capture,
		profile.electronic_warfare,
		profile.shield,
		profile.long_range,
		profile.area_denial,
	)
	capability_x: f32 = 590
	capability_values := [4]i32 {
		profile.repair,
		profile.recovery,
		profile.command,
		profile.flight_support,
	}; capability_icons := [4]int{ICON_REPAIR, ICON_RETURN, ICON_COUNCIL, ICON_FLEET}
	for value, i in capability_values {capability_x +=
			draw_resource_amount(
				capability_x,
				564,
				value,
				capability_icons[i],
				UX.text,
				TYPE_LABEL,
			) +
			12}
	manifest_x: f32 = 590
	manifest_values := [7]i32 {
		profile.cargo,
		profile.propellant,
		profile.fabrication,
		profile.medical,
		profile.population,
		profile.colony,
		profile.archive,
	}; manifest_icons := [7]int{ICON_CARGO, ICON_PROPELLANT, ICON_REPAIR, ICON_HOSPITAL, ICON_HOME, ICON_SETTLEMENT, ICON_ARCHIVE}
	for value, i in manifest_values {manifest_x +=
			draw_resource_amount(manifest_x, 586, value, manifest_icons[i], UX.text, TYPE_LABEL) +
			12}
	if back_button(R(42, 646, 160, 38), "BACK") do s.screen = s.return_screen
}
