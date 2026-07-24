package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:math"

combat_draw_frame_shell :: proc(s: ^Ux_State) {
	// The Vulkan world pass already cleared the tactical viewport. Preserve it
	// while the immediate canvas supplies the surrounding archival interface.
	rl.DrawRectangleRec(
		R(0, 0, 1280, 72),
		UX.void,
	); rl.DrawRectangleRec(R(0, 620, 1280, 100), UX.void); rl.DrawRectangleRec(R(0, 72, 205, 548), UX.void); rl.DrawRectangleRec(R(1000, 72, 280, 548), UX.void)
	for i in 0 ..< 120 {x := f32((i * 107 + int(s.combat.seed % 97)) % 1280); y := f32((i * 61 + 13) % 720); rl.DrawRectangleRec(R(x, y, 1, 1), rl.Color{95, 95, 90, u8(35 + i % 45)})}
	// Terrain volumes live in the depth-tested world pass; names remain crisp
	// archival annotations in the canvas pass.
	rl.BeginScissorMode(COMBAT_VIEWPORT)
	debris, _ := combat_3d_project_to_ui(
		s,
		s.combat.terrain[0].center,
	); lane, _ := combat_3d_project_to_ui(s, s.combat.terrain[1].center); radiation, _ := combat_3d_project_to_ui(s, s.combat.terrain[2].center)
	draw_text(
		"DEBRIS · MISSILE MASK",
		debris.x - 65,
		debris.y - 5,
		TYPE_FINE,
		UX.dim,
	); draw_text("OPEN FIRE LANE", lane.x - 45, lane.y - 5, TYPE_FINE, UX.info); draw_text("RADIATION", radiation.x - 30, radiation.y - 5, TYPE_FINE, UX.bad)
	for field in s.combat.wreckage_fields[:s.combat.wreckage_field_count] {p, _ := combat_3d_project_to_ui(s, field.center); draw_fmt(p.x - field.radius * .12, p.y + field.radius * .08, TYPE_MICRO, UX.dim, "WRECKAGE · %d HULLS", field.friendly_ships + field.raider_ships)}
	combat_draw_sector_labels(s)
	combat_draw_viewport_instrument()
	rl.EndScissorMode()
	panel(R(12, 72, 181, 548)); panel(R(1010, 72, 258, 548)); divider(0, 58, 1280)
	title := game.combat_mission_title(
		&s.combat,
	); draw_text(title, 20, 18, TYPE_HEADING_COMPACT, UX.text)
	combat_draw_mission_clock(s)
}

combat_draw_battlefield_overlays :: proc(s: ^Ux_State) {
	rl.BeginScissorMode(COMBAT_VIEWPORT)
	label_layout := combat_build_label_layout(s)
	if !game.combat_is_direct_engagement(&s.combat) {
		combat_draw_objective(
			s,
			&label_layout,
			"RELAY A",
			s.combat.relays[0],
			s.combat.relay_progress[0],
			UX.info,
		)
		combat_draw_objective(
			s,
			&label_layout,
			"RELAY B",
			s.combat.relays[1],
			s.combat.relay_progress[1],
			UX.info,
		)
		if s.combat.seedship_found do combat_draw_objective(s, &label_layout, "SEEDSHIP", s.combat.seedship, s.combat.recovery_progress, UX.warn)
	}
	combat_draw_objective(s, &label_layout, "EXTRACTION", s.combat.extraction, 0, UX.good)
	if !game.combat_is_direct_engagement(&s.combat) &&
	   (!s.combat.skirmish ||
			   game.skirmish_has_objective(&s.combat, .Scan_Anomaly) ||
			   game.skirmish_has_objective(&s.combat, .Complete_Reconnaissance) ||
			   game.skirmish_has_objective(&s.combat, .Complete_Covert_Scan)) {
		combat_draw_objective(
			s,
			&label_layout,
			"ANOMALY",
			s.combat.anomaly,
			s.combat.anomaly_progress,
			UX.committed,
		)
	}
	if s.combat.scenario ==
	   .Finale {asset := &s.combat.strategic_asset; ap, _ := combat_3d_project_to_ui(s, asset.position); asset_color := asset.disabled ? UX.unavailable : asset.exposure_remaining > 0 ? UX.committed : UX.bad; draw_text(asset.disabled ? "CITADEL DISABLED" : "CITADEL WEAPON", ap.x - 48, ap.y - 38, TYPE_FINE, asset_color); if asset.locked && asset.beam_flash <= 0 {target, _ := combat_3d_project_to_ui(s, asset.beam_aim); draw_text("FIRING CORRIDOR", target.x + 15, target.y - 5, TYPE_MICRO, UX.warn)}}
	if s.combat.ability_pending {target, _ := combat_3d_project_to_ui(s, s.combat.ability_target); draw_fmt(target.x - 42, target.y - 60, TYPE_SMALL, UX.warn, "IMPACT %.1f", s.combat.ability_timer)}
	if s.combat_ability_armed {
		target := combat_3d_point_on_plane(
			s,
			ux_mouse,
			s.combat_altitude,
		); p, _ := combat_3d_project_to_ui(s, target)
		source := clamp(
			s.combat_selected,
			0,
			s.combat.friendly_count - 1,
		); source_p, source_visible := combat_3d_project_to_ui(s, s.combat.units[source].position)
		impact_time, valid := game.combat_ship_ability_time_to_impact(&s.combat, source, target)
		if source_visible do rl.DrawLineEx(source_p, p, 1, valid ? UX.warn : UX.unavailable)
		draw_text(
			"DESIGNATE ABILITY TARGET",
			p.x - 62,
			p.y - 66,
			TYPE_CAPTION,
			valid ? UX.warn : UX.unavailable,
		)
		if valid {draw_text(fmt.tprintf("IMPACT IN %s", game.combat_format_duration(impact_time)), p.x - 45, p.y - 50, TYPE_CAPTION, UX.info)} else {draw_text("OUT OF RANGE", p.x - 38, p.y - 50, TYPE_CAPTION, UX.unavailable)}
	}
	for salvo, salvo_index in s.combat.salvos {if !salvo.active do continue; p, visible := combat_3d_project_to_ui(s, salvo.position); if visible {color := salvo.side == .Friendly ? UX.warn : UX.bad; combat_draw_ring(p, 10, color); text := fmt.tprintf("%v · %v · %d/%d · %s · G%.0f%%", salvo.weapon, salvo.phase, salvo.weapons_surviving, salvo.weapons_launched, game.combat_format_duration(salvo.time_remaining), salvo.guidance * 100); w := max(measure_text(text, TYPE_FINE).x + 8, 70); placed := combat_place_label(&label_layout, p, w, 17, salvo_index); draw_text(text, placed.x + 4, placed.y + 3, TYPE_FINE, color); connection := combat_label_connection(placed, p); edge := combat_leader_pin_point(p, connection); rl.DrawLineEx(edge, connection, 1, rl.Color{color.r, color.g, color.b, 90})}}
	for i in 0 ..< s.combat.unit_count do combat_draw_unit_caption_overlay(s, &label_layout, i)
	combat_draw_order_preview(s)
	rl.EndScissorMode()
}

combat_draw_camera_toolbar :: proc(s: ^Ux_State) {
	if button(R(365, 626, 92, 24), "ORBIT LEFT") do combat_orbit(s, -.18, 0)
	if button(R(462, 626, 92, 24), "ORBIT RIGHT") do combat_orbit(s, .18, 0)
	if button(R(559, 626, 72, 24), "ORBIT UP") do combat_orbit(s, 0, -.12)
	if button(R(636, 626, 72, 24), "ORBIT DOWN") do combat_orbit(s, 0, .12)
	if button(R(713, 626, 92, 24), "GALACTIC UP") do s.combat_orientation = combat_default_orientation()
	ability_unit := &s.combat.units[clamp(s.combat_selected, 0, s.combat.friendly_count - 1)]; ability := game.combat_ship_ability(ability_unit^); ability_ready := ability_unit.selected && game.combat_ship_ability_ready(&s.combat, s.combat_selected); ability_label := s.combat_ability_armed ? "CANCEL TARGET" : ability_unit.ability_charges <= 0 ? "ABILITY EXPENDED" : ability_unit.ability_cooldown > 0 ? fmt.tprintf("RECYCLE %.0fs", ability_unit.ability_cooldown) : fmt.tprintf("Q · %s", game.combat_ship_ability_name(ability)); if button(R(820, 626, 180, 24), ability_label, ability_ready || s.combat_ability_armed, s.combat_ability_armed) {if s.combat_ability_armed {s.combat_ability_armed = false} else do combat_use_selected_ability(s, s.combat_selected)}
	draw_fmt(
		820,
		654,
		TYPE_FINE,
		ability_unit.selected ? UX.dim : UX.unavailable,
		"%s · %d CHARGES",
		ability_unit.name,
		ability_unit.ability_charges,
	)
	if s.combat_drag_active {x := min(s.combat_drag_start.x, ux_mouse.x); y := min(s.combat_drag_start.y, ux_mouse.y); w := math.abs(ux_mouse.x - s.combat_drag_start.x); h := math.abs(ux_mouse.y - s.combat_drag_start.y); rl.DrawRectangleRoundedLinesEx(R(x, y, w, h), 0, 0, 1, UX.info)}
}

combat_draw_request_overlay :: proc(s: ^Ux_State) {
	if s.combat.request_pending {panel(R(350, 76, 560, 112), true); requester := s.combat.units[clamp(s.combat.request_unit, 0, s.combat.friendly_count - 1)]; fire_request := s.combat.request_kind == .Authorize_Fire; if fire_request {draw_fmt(370, 88, TYPE_LABEL, UX.warn, "%s · FIRE AUTHORITY", requester.name)} else {draw_fmt(370, 88, TYPE_LABEL, UX.warn, "%s · %v · %.0fs", requester.name, s.combat.request_kind, s.combat.request_timer)}; draw_text_wrapped(s.combat.request_text, R(370, 110, 350, 26), TYPE_SMALL, UX.text); draw_text_wrapped(s.combat.request_consequence, R(370, 137, 350, 38), TYPE_SMALL, UX.dim); if !fire_request do draw_fmt(370, 168, TYPE_SMALL, UX.info, "NO RESPONSE · %s", game.combat_request_default(&s.combat) ? "APPROVE BY DOCTRINE" : "DENY BY DOCTRINE"); if button(R(744, 101, 68, 34), fire_request ? "AUTHORIZE" : "APPROVE") do game.combat_resolve_request(&s.combat, true); if button(R(818, 101, 68, 34), fire_request ? "WITHHOLD" : "DENY") do game.combat_resolve_request(&s.combat, false)}
}

combat_draw_chatter_overlay :: proc(s: ^Ux_State) {
	if s.combat_chatter_timer > 0 &&
	   !s.combat.request_pending {panel(R(405, 560, 400, 54), true); draw_fmt(421, 568, TYPE_SMALL, UX.info, "%s · COMMS", s.combat_chatter_source); draw_text_fitted(s.combat_chatter_text, R(421, 588, 368, 20), TYPE_SMALL, UX.text)}
}

draw_combat :: proc(s: ^Ux_State) {
	if s.combat_briefing {
		combat_draw_briefing(s)
		return
	}
	combat_controls(s)
	combat_update_chatter(s)
	combat_draw_frame_shell(s)
	combat_draw_battlefield_overlays(s)
	combat_draw_camera_toolbar(s)
	combat_battlefield_input(s)
	combat_draw_left_command_panel(s)
	combat_draw_status_panel(s)
	combat_draw_request_overlay(s)
	combat_draw_chatter_overlay(s)
	if s.combat.complete {
		if s.combat_campaign_active && !s.combat.campaign_result_applied {
			if s.combat.operation.committed_plan.committed &&
			   !game.skirmish_primary_objective_met(&s.combat) {
				s.campaign.combat_operation =
					game.combat_operation_linked_draft(&s.combat)
			}
			_ = game.combat_apply_campaign_result(s.campaign, &s.combat)
			_ = ux_save(s, true)
		}
		draw_combat_result(s)
	}
	draw_tooltip()
}
