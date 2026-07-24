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
dark_draw_course_tray :: proc(s: ^Ux_State, door: ^game.Dark_Door) {
	p := &s.campaign.passage; d := &s.campaign.outer_dark.continuum
	rl.DrawRectangle(
		0,
		612,
		1280,
		108,
		rl.Color{4, 4, 4, 244},
	); rl.DrawLineEx(V(0, 612), V(1280, 612), 1, UX.info)
	if s.dark_intent_open {dark_draw_intent_tray(s); return}
	if s.dark_fine_plot_open {dark_draw_fine_plot_tray(s); return}
	confidence := game.dark_door_detection_confidence(
		d,
		p.dark_navigation.position,
		door,
	); forecast := game.passage_dark_course_forecast(s.campaign, p, &s.dark_course_draft)
	if confidence <=
	   0 {s.dark_selection_kind = .None; s.dark_selection_id = 0; s.dark_course_draft = {}; return}
	draw_fmt(
		20,
		624,
		TYPE_LABEL,
		UX.text,
		"%s",
		game.dark_correspondence_name(
			s.campaign,
			door.id,
			door.endpoint_known ? door.galaxy_neighborhood : -1,
		),
	); draw_fmt(20, 648, TYPE_MICRO, UX.info, "DETECTION %.0f%% · %s · %s", confidence * 100, door.endpoint_known ? "MAPPED" : "UNKNOWN", game.passage_correspondence_reach_name(s.campaign, door))
	reason :=
		p.strategy.course == .Best_Mapped ? "highest mapped confidence" : p.strategy.course == .Lowest_Coherence ? "lowest coherence exposure" : "shortest metric distance"
	draw_fmt(292, 624, TYPE_FINE, UX.text, "RECOMMENDED / %s", reason)
	coherence := game.passage_course_coherence_forecast(s.campaign, p, &s.dark_course_draft)
	timing := game.passage_course_time_forecast(s.campaign, p, &s.dark_course_draft)
	depth := game.passage_depth_forecast(s.campaign, p, &s.dark_course_draft)
	sensor_profile := game.dark_sensor_profile(p.dark_navigation.sensor_posture)
	draw_fmt(
		292,
		648,
		TYPE_FINE,
		coherence.crosses_limit ? UX.warn : UX.dim,
		"RANGE %.1f · SHIP %.1f D · MEMBRANE %.1f D",
		forecast.distance,
		timing.ship_days,
		timing.membrane_days,
	)
	draw_fmt(292, 700, TYPE_MICRO, depth.peak_depth <= depth.safe_limit ? UX.dim : UX.warn, "DEPTH %.1f→%.1f · STABLE %.1f · EMERGENCY %.1f", depth.current_depth, depth.peak_depth, depth.safe_limit, depth.emergency_limit)
	if !s.dark_course_why_open do draw_fmt(292, 682, TYPE_MICRO, coherence.crosses_limit || sensor_profile.emission > 0 ? UX.warn : UX.dim, "COHERENCE %.0f→%.0f%% · INTERCEPT %.0f%% · SENS %s", coherence.current / coherence.limit * 100, coherence.projected / coherence.limit * 100, forecast.ecological_interception * 100, game.dark_sensor_posture_name(p.dark_navigation.sensor_posture))
	if button(R(672, 632, 78, 34), s.dark_course_why_open ? "HIDE WHY" : "WHY") do s.dark_course_why_open = !s.dark_course_why_open
	if s.dark_course_why_open {
		for factor, i in forecast.factors[:min(forecast.factor_count, 2)] do draw_fmt(292, 668 + f32(i) * 15, TYPE_MICRO, factor.evidence == .Unknown ? UX.warn : UX.dim, "%+.2f  %s · %v", factor.contribution, factor.label, factor.evidence)
	}
	if game.passage_course_requires_emergency(s.campaign, p, &s.dark_course_draft) && p.emergency_target_door_id == 0 {
		if button(R(760, 632, 102, 34), "COMMIT DEPTH", depth.emergency_margin >= 0, true) {_, s.status = game.authorize_passage_emergency_descent(s.campaign, p, &s.dark_course_draft)}
	} else if button(R(760, 632, 102, 34), "INTENT") do s.dark_intent_open = true
	if button(R(870, 632, 112, 34), "FINE PLOT") do s.dark_fine_plot_open = true
	if button(
		R(990, 632, 82, 34),
		"CLEAR",
	) {s.dark_selection_kind = .None; s.dark_selection_id = 0; s.dark_course_draft = {}}
	if p.pending_door_id == door.id &&
	   button(
		   R(1080, 614, 174, 30),
		   "CROSS MEMBRANE",
		   true,
		   true,
	   ) {_, s.status = game.cross_passage_door(s.campaign, p)}
	if button(
		R(1080, 652, 174, 40),
		"AUTHORIZE COURSE",
		forecast.valid,
		true,
	) {_, ok := game.plot_passage_course(s.campaign, p, s.dark_course_draft); if ok {s.dark_course_draft = {}; s.dark_selection_kind = .None}}
}

dark_draw_contact_tray :: proc(s: ^Ux_State, track: ^game.Dark_Track) {
	p := &s.campaign.passage
	rl.DrawRectangle(
		0,
		612,
		1280,
		108,
		rl.Color{4, 4, 4, 244},
	); rl.DrawLineEx(V(0, 612), V(1280, 612), 1, UX.warn)
	draw_fmt(
		20,
		624,
		TYPE_LABEL,
		UX.text,
		"%s",
		game.dark_organism_name(track.organism_id, track.role),
	); draw_fmt(20, 648, TYPE_MICRO, UX.warn, "%v · CONFIDENCE %.0f%%", track.behavior, track.confidence * 100)
	fix := track.confidence >= .75 ? "STABLE" : track.confidence >= .45 ? "DEGRADED" : "NOISY"
	draw_fmt(
		350,
		624,
		TYPE_FINE,
		UX.text,
		"RANGE %.2f · EXTENT %.2f · POSITIONAL FIX %s",
		track.distance,
		track.estimated_extent,
		fix,
	)
	threat := game.dark_track_threat(track)
	if button(R(1168, 620, 86, 28), s.dark_contact_why_open ? "HIDE WHY" : "WHY") do s.dark_contact_why_open = !s.dark_contact_why_open
	if s.dark_contact_why_open {
		for factor, i in track.factors[:min(track.factor_count, 3)] do draw_fmt(780, 652 + f32(i) * 14, TYPE_MICRO, factor.evidence == .Unknown ? UX.warn : UX.dim, "%+.2f %s · %v", factor.contribution, factor.label, factor.evidence)
	}
	if threat.level != .Clear && p.pause_reason != .Dangerous_Contact do draw_fmt(350, 648, TYPE_FINE, threat.level == .Hold ? UX.bad : UX.warn, "%s · CLEARANCE %+.2f", dark_threat_label(track), threat.clearance)
	role_secured := p.observed_ecology_roles & (u32(1) << u32(track.role)) != 0
	if p.pause_reason == .Dangerous_Contact {
		avoidance, can_avoid := game.passage_contact_avoidance_course(
			s.campaign,
			p,
			track.organism_id,
		)
		requires_response := game.dark_track_requires_response(
			track,
		); can_avoid = can_avoid && requires_response
		if !requires_response {
			draw_text("THIS TRACK DID NOT TRIGGER THE COURSE HOLD", 350, 648, TYPE_FINE, UX.warn)
		} else if can_avoid {
			evasive := game.dark_course_forecast(&s.campaign.outer_dark.continuum, &avoidance)
			direct := game.Dark_Course {
				waypoint_count = 2,
			}
			direct.waypoints[0].position = p.dark_navigation.position
			direct.waypoints[1].position =
				p.dark_navigation.course.waypoints[p.dark_navigation.course.waypoint_count - 1].position
			held := game.dark_course_forecast(&s.campaign.outer_dark.continuum, &direct)
			coherence := game.passage_course_coherence_forecast(s.campaign, p, &avoidance)
			learners :=
				track.role == .Shear_Hunter ? game.passage_shear_evasion_learners(s.campaign, p) : 0
			if learners > 0 {
				draw_fmt(
					350,
					648,
					TYPE_FINE,
					coherence.crosses_limit ? UX.warn : UX.dim,
					"DOGLEG +%.1f RANGE · COHERENCE %.0f→%.0f%% · TRAINS %d SHIP%s",
					max(evasive.distance - held.distance, 0),
					coherence.current / coherence.limit * 100,
					coherence.projected / coherence.limit * 100,
					learners,
					learners == 1 ? "" : "S",
				)
			} else {
				draw_fmt(
					350,
					648,
					TYPE_FINE,
					coherence.crosses_limit ? UX.warn : UX.dim,
					"EVASIVE DOGLEG +%.1f RANGE · COHERENCE %.0f→%.0f%%",
					max(evasive.distance - held.distance, 0),
					coherence.current / coherence.limit * 100,
					coherence.projected / coherence.limit * 100,
				)
			}
		} else {
			draw_text("NO DESTINATION-PRESERVING EVASIVE COURSE", 350, 648, TYPE_FINE, UX.warn)
		}
		if button(
			R(884, 622, 170, 34),
			"KEEP DISTANCE",
			can_avoid,
		) {_, s.status = game.respond_to_dark_contact(s.campaign, p, false, track.organism_id); s.dark_selection_kind = .None; s.dark_selection_id = 0}
		if button(
			R(1064, 622, 190, 34),
			"ACCEPT CONTACT RISK",
			requires_response,
			true,
		) {_, s.status = game.respond_to_dark_contact(s.campaign, p, true, track.organism_id); s.dark_selection_kind = .None; s.dark_selection_id = 0}
		draw_text(
			"TAKE EVASIVE DOGLEG",
			899,
			660,
			TYPE_MICRO,
			UX.dim,
		); draw_text("RESUME HELD COURSE", 1080, 660, TYPE_MICRO, UX.warn)
	} else if p.contract.purpose == .Ecological_Survey && !role_secured {
		draw_fmt(
			350,
			648,
			TYPE_FINE,
			UX.dim,
			"ENERGY %.2f · CONDITION %.2f · INJURY %.2f · TARGET %04d",
			track.energy_band,
			track.condition_band,
			track.injury,
			track.target_id % 10000,
		)
		required := game.dark_documentation_confidence_required(
			s.campaign,
			p,
		); ready := track.confidence >= required
		draw_fmt(
			740,
			660,
			TYPE_MICRO,
			ready ? UX.dim : UX.warn,
			"COST · 0.25 DAYS · COURSE INTERRUPTED · NEED %.0f%% CONFIDENCE",
			required * 100,
		)
		if button(
			R(1050, 618, 204, 36),
			ready ? "DOCUMENT ROLE" : "CLOSE TO DOCUMENT",
			ready,
			true,
		) {_, s.status = game.document_dark_contact(s.campaign, p, track.organism_id); s.dark_selection_kind = .None; s.dark_selection_id = 0}
	} else if p.contract.purpose == .Ecological_Survey && role_secured {
		draw_fmt(
			350,
			648,
			TYPE_FINE,
			UX.dim,
			"ENERGY %.2f · CONDITION %.2f · INJURY %.2f · TARGET %04d",
			track.energy_band,
			track.condition_band,
			track.injury,
			track.target_id % 10000,
		)
		draw_text("ROLE SECURED IN EXPEDITION RECORD", 960, 642, TYPE_MICRO, UX.good)
	} else {draw_fmt(
			350,
			648,
			TYPE_FINE,
			UX.dim,
			"ENERGY %.2f · CONDITION %.2f · INJURY %.2f · TARGET %04d",
			track.energy_band,
			track.condition_band,
			track.injury,
			track.target_id % 10000,
		)
		if button(
			R(1080, 636, 174, 36),
			"CLOSE SENSOR CARD",
		) {s.dark_selection_kind = .None; s.dark_selection_id = 0}}
}

dark_draw_underway_tray :: proc(s: ^Ux_State) {
	p := &s.campaign.passage; n := &p.dark_navigation; rl.DrawRectangle(0, 612, 1280, 108, rl.Color{4, 4, 4, 244}); rl.DrawLineEx(V(0, 612), V(1280, 612), 1, UX.info)
	if n.manual_active {draw_text("MANUAL HELM ENGAGED", 20, 624, TYPE_CAPTION, UX.text); draw_fmt(20, 648, TYPE_FINE, UX.info, "VELOCITY · X %+.2f · Y %+.2f · Z %+.2f · W %+.2f", n.manual_velocity[0], n.manual_velocity[1], n.manual_velocity[2], n.manual_velocity[3]); draw_text("RELEASE INPUT TO HOLD", 1040, 642, TYPE_MICRO, UX.dim); return}
	draw_text(
		"COURSE UNDERWAY",
		20,
		624,
		TYPE_CAPTION,
		UX.text,
	); draw_fmt(20, 648, TYPE_FINE, UX.info, "LEG %d/%d · PROGRESS %.0f%%", n.segment + 1, max(n.course.waypoint_count - 1, 1), n.segment_progress * 100)
	draw_fmt(
		300,
		624,
		TYPE_FINE,
		UX.text,
		"RANGE %.1f · COURSE LOAD %.2f · CONF %.0f%%",
		n.forecast.distance,
		n.forecast.coherence_cost,
		n.forecast.topology_confidence * 100,
	)
	watch_count, hold_count := 0, 0; nearest_clearance := f64(1e30)
	for &track in n.tracker.tracks[:n.tracker.track_count] {threat := game.dark_track_threat(&track); if threat.level == .Watch do watch_count += 1; if threat.level == .Hold do hold_count += 1; if threat.level != .Clear do nearest_clearance = min(nearest_clearance, threat.clearance)}
	if watch_count + hold_count >
	   0 {draw_fmt(300, 648, TYPE_FINE, hold_count > 0 ? UX.bad : UX.warn, "DANGER · %d WATCH · %d HOLD · CLEARANCE %+.1f", watch_count, hold_count, nearest_clearance)} else {draw_fmt(300, 648, TYPE_FINE, n.tracker.track_count > 0 ? UX.info : UX.dim, "CONTACTS %d · INTERCEPT %.0f%% · CLEAR", n.tracker.track_count, n.forecast.ecological_interception * 100)}
	if p.systematic_search_active {
		next, found := game.passage_course_to_unknown_door(s.campaign, p, -1)
		forecast := game.dark_course_forecast(&s.campaign.outer_dark.continuum, &next)
		draw_fmt(
			760,
			624,
			TYPE_FINE,
			UX.info,
			found ? "SEARCHING UNKNOWN · NEXT %.1f RANGE" : "SEARCHING UNTIL RETURN RESERVE",
			forecast.distance,
		)
		if button(R(1080, 642, 174, 34), "STOP SEARCH") do game.cancel_systematic_dark_search(p)
	} else {
		draw_text(
			rl.GamepadAvailable() ? "LS SCREEN · LB/RB DEPTH · LT/RT W" : "WASD SCREEN · QE DEPTH · RF W",
			1040,
			632,
			TYPE_MICRO,
			UX.info,
		); draw_text(rl.GamepadAvailable() ? "B STOP · START PAUSE" : "SPACE PAUSES CLOCK", 1040, 650, TYPE_MICRO, UX.dim)
	}
}

// The quiet state offers one deliberate departure into the unknown instead
// of scattering expedition-wide commitments across the header.
dark_draw_descent_tray :: proc(s: ^Ux_State) {
	p := &s.campaign.passage
	rl.DrawRectangle(0, 612, 1280, 108, rl.Color{4, 4, 4, 244})
	rl.DrawLineEx(V(0, 612), V(1280, 612), 1, UX.info)
	draw_text("DESCENT", 20, 624, TYPE_CAPTION, UX.info)
	draw_text(dark_next_action_text(s), 20, 648, TYPE_FINE, UX.text)
	depth := game.dark_depth_from_anchor(s.campaign.outer_dark.continuum.seed, s.campaign.outer_dark.continuum.anchor_position, p.dark_navigation.position)
	draw_fmt(
		420,
		624,
		TYPE_FINE,
		depth <= p.field_depth_rating ? UX.dim : UX.warn,
		"FIELD DEPTH %.1f · STABLE %.1f · EMERGENCY %.1f",
		depth,
		p.field_depth_rating,
		p.emergency_depth_limit,
	)
	draw_text("AUTO EXPLORE STOPS BEFORE AN UNCOMMITTED DEPTH DESCENT", 420, 650, TYPE_MICRO, UX.dim)
	if button(R(860, 630, 184, 40), "AUTO EXPLORE", p.phase == .Awaiting_Leg, true) {
		_, s.status = game.order_systematic_dark_search(s.campaign, p)
	}
	if button(R(1060, 630, 194, 40), "RETURN TO FLEET", p.phase == .Awaiting_Leg) {
		game.cancel_systematic_dark_search(p)
		_, s.status = game.follow_fastest_known_route(
			s.campaign,
			p,
			s.campaign.outer_dark.continuum.anchor_neighborhood,
		)
	}
}

dark_draw_coherence_tray :: proc(s: ^Ux_State) -> bool {
	p := &s.campaign.passage; if p.phase != .Awaiting_Leg || p.pause_reason != .Coherence_Limit do return false
	quick := game.passage_coherence_recovery_preview(
		s.campaign,
		p,
		false,
	); full := game.passage_coherence_recovery_preview(s.campaign, p, true); quick_ok := quick.can_resume && !quick.crosses_limit
	rl.DrawRectangle(
		0,
		612,
		1280,
		108,
		rl.Color{4, 4, 4, 244},
	); rl.DrawLineEx(V(0, 612), V(1280, 612), 1, UX.warn)
	draw_text(
		"FIELD COHERENCE LIMIT",
		20,
		624,
		TYPE_CAPTION,
		UX.warn,
	); draw_fmt(20, 650, TYPE_FINE, UX.text, "EXPOSURE %.2f / %.2f", p.coherence_exposure, full.limit)
	if quick.can_resume {draw_fmt(330, 624, TYPE_FINE, quick_ok ? UX.text : UX.warn, "PATCH %.2f DAYS · HELD COURSE %.0f→%.0f%%", quick.ship_days, quick.target_exposure / quick.limit * 100, quick.held_projected / quick.limit * 100)} else {draw_text("HELD COURSE UNAVAILABLE", 330, 624, TYPE_FINE, UX.warn)}
	draw_fmt(
		330,
		650,
		TYPE_FINE,
		UX.dim,
		"FULL %.2f DAYS · RESTORE TO %.0f%% · REPLOT",
		full.ship_days,
		full.target_exposure / full.limit * 100,
	)
	if button(
		R(850, 622, 190, 34),
		"PATCH & RESUME",
		quick_ok,
	) {_, s.status = game.stabilize_passage_coherence(s.campaign, p, false)}
	if button(
		R(1050, 622, 204, 34),
		"FULL STABILIZE",
		true,
		true,
	) {_, s.status = game.stabilize_passage_coherence(s.campaign, p, true)}
	draw_text(
		"KEEP HELD COURSE",
		884,
		662,
		TYPE_MICRO,
		quick_ok ? UX.dim : UX.unavailable,
	); draw_text("RESTORE DEEP BUFFER", 1075, 662, TYPE_MICRO, UX.dim)
	return true
}

dark_draw_obstruction_tray :: proc(s: ^Ux_State) -> bool {
	p := &s.campaign.passage; if p.phase != .Awaiting_Leg || p.pause_reason != .Material_Obstruction do return false
	preview := game.passage_obstruction_response_preview(s.campaign, p)
	rl.DrawRectangle(
		0,
		612,
		1280,
		108,
		rl.Color{4, 4, 4, 244},
	); rl.DrawLineEx(V(0, 612), V(1280, 612), 1, UX.warn)
	draw_text(
		"MATERIAL OBSTRUCTION",
		20,
		624,
		TYPE_CAPTION,
		UX.warn,
	); draw_text(preview.has_held_course ? "HELD COURSE BLOCKED" : "MANUAL HELM BLOCKED", 20, 650, TYPE_FINE, UX.text)
	if preview.can_detour {draw_fmt(330, 624, TYPE_FINE, UX.text, "DETOUR +%.1f RANGE · COHERENCE %.0f%%", preview.detour_added, preview.detour_coherence / preview.limit * 100)} else {draw_text("DETOUR UNAVAILABLE", 330, 624, TYPE_FINE, UX.warn)}
	draw_fmt(
		330,
		650,
		TYPE_FINE,
		preview.can_wait ? UX.dim : UX.warn,
		"WAIT %.2f DAYS · COHERENCE %.0f%%",
		preview.wait_ship_days,
		preview.wait_projected / preview.limit * 100,
	)
	if button(
		R(850, 622, 190, 34),
		"PLOT DETOUR",
		preview.can_detour,
	) {_, s.status = game.respond_to_material_obstruction(s.campaign, p, false)}
	if button(
		R(1050, 622, 204, 34),
		"WAIT FOR DRIFT",
		preview.can_wait,
		true,
	) {_, s.status = game.respond_to_material_obstruction(s.campaign, p, true)}
	draw_text(
		"SPEND RANGE",
		900,
		662,
		TYPE_MICRO,
		UX.dim,
	); draw_text(preview.has_held_course ? "SPEND SHIP TIME" : "CLEAR, THEN REPLOT", preview.has_held_course ? 1090 : 1078, 662, TYPE_MICRO, preview.can_wait ? UX.dim : UX.unavailable)
	return true
}

dark_manual_helm :: proc(s: ^Ux_State) {
	p := &s.campaign.passage
	if s.dark_contacts_open ||
	   s.dark_comms_open ||
	   s.dark_missing_confirm ||
	   s.dark_exit_confirm ||
	   s.dark_intent_open ||
	   s.dark_fine_plot_open {if p.dark_navigation.manual_active do _ = game.set_passage_manual_helm(s.campaign, p, {}); return}
	direction := dark_helm_direction(s)
	s.dark_fleet_power_command = f32(clamp(game.dark_vec4_length(direction), 0, 1))
	if game.dark_vec4_length(direction) > 0 || p.dark_navigation.manual_active do _ = game.set_passage_manual_helm(s.campaign, p, direction)
}

dark_emergence_neighborhood :: proc(s: ^Ux_State) -> int {
	p := &s.campaign.passage
	d := &s.campaign.outer_dark.continuum
	for door in d.doors[:d.door_count] do if door.id == p.pending_door_id && door.galaxy_neighborhood >= 0 do return door.galaxy_neighborhood
	return p.normal_course.start_neighborhood
}

dark_draw_emergence_galaxy :: proc(s: ^Ux_State, rect: rl.Rectangle) {
	g := s.campaign.galaxy
	if g == nil || g.neighborhood_count <= 0 do return
	p := &s.campaign.passage
	start_index := p.departure_neighborhood
	if start_index < 0 || start_index >= g.neighborhood_count do start_index = s.campaign.outer_dark.continuum.anchor_neighborhood
	end_index := dark_emergence_neighborhood(s)
	if start_index < 0 || start_index >= g.neighborhood_count || end_index < 0 || end_index >= g.neighborhood_count do return

	panel(rect)
	draw_text("GALACTIC CORRESPONDENCE FIX", rect.x + 18, rect.y + 14, TYPE_MICRO, UX.info)
	draw_fmt(
		rect.x + rect.width - 148,
		rect.y + 14,
		TYPE_MICRO,
		UX.dim,
		"DOOR %04d",
		p.pending_door_id % 10000,
	)

	center := V(rect.x + rect.width * .5, rect.y + rect.height * .55)
	radius_x := rect.width * .39
	radius_y := rect.height * .32
	previous := V(center.x + radius_x, center.y)
	for segment in 1 ..= 64 {
		angle := f64(segment) * 2 * math.PI / 64
		point := V(
			center.x + f32(math.cos(angle)) * radius_x,
			center.y + f32(math.sin(angle)) * radius_y,
		)
		rl.DrawLineEx(
			previous,
			point,
			segment % 5 == 0 ? f32(.8) : f32(.45),
			segment % 5 == 0 ? UX.line : rl.Color{151, 160, 158, 52},
		)
		previous = point
	}
	for ring in 1 ..= 2 {
		ring_scale := f32(ring) / 3
		previous = V(center.x + radius_x * ring_scale, center.y)
		for segment in 1 ..= 48 {
			angle := f64(segment) * 2 * math.PI / 48
			point := V(
				center.x + f32(math.cos(angle)) * radius_x * ring_scale,
				center.y + f32(math.sin(angle)) * radius_y * ring_scale,
			)
			if segment % 3 != 0 do rl.DrawLineEx(previous, point, .35, rl.Color{151, 160, 158, 34})
			previous = point
		}
	}

	start_n := g.neighborhoods[start_index]
	end_n := g.neighborhoods[end_index]
	start_x, start_y := galaxy_project_world_xyz(g, start_n.x_kpc, start_n.y_kpc, start_n.z_kpc)
	end_x, end_y := galaxy_project_world_xyz(g, end_n.x_kpc, end_n.y_kpc, end_n.z_kpc)
	scale := f64(radius_x) / max(g.disk_radius_kpc, .01)
	start := V(center.x + f32(start_x * scale), center.y + f32(start_y * scale))
	end := V(center.x + f32(end_x * scale), center.y + f32(end_y * scale))
	delta := V(end.x - start.x, end.y - start.y)
	for dash in 0 ..< 12 {
		t0 := f32(dash) / 12
		t1 := min(t0 + f32(.055), f32(1))
		rl.DrawLineEx(
			V(start.x + delta.x * t0, start.y + delta.y * t0),
			V(start.x + delta.x * t1, start.y + delta.y * t1),
			1,
			UX.dim,
		)
	}

	// The square is the known departure anchor; the diamond is the measured emergence fix.
	rl.DrawLineEx(V(start.x - 5, start.y - 5), V(start.x + 5, start.y - 5), 1, UX.text)
	rl.DrawLineEx(V(start.x + 5, start.y - 5), V(start.x + 5, start.y + 5), 1, UX.text)
	rl.DrawLineEx(V(start.x + 5, start.y + 5), V(start.x - 5, start.y + 5), 1, UX.text)
	rl.DrawLineEx(V(start.x - 5, start.y + 5), V(start.x - 5, start.y - 5), 1, UX.text)
	r := f32(7)
	rl.DrawLineEx(V(end.x - r, end.y), V(end.x, end.y - r), 1.5, UX.info)
	rl.DrawLineEx(V(end.x, end.y - r), V(end.x + r, end.y), 1.5, UX.info)
	rl.DrawLineEx(V(end.x + r, end.y), V(end.x, end.y + r), 1.5, UX.info)
	rl.DrawLineEx(V(end.x, end.y + r), V(end.x - r, end.y), 1.5, UX.info)
	departure_door := p.departure_door_id
	if departure_door == 0 do departure_door = s.campaign.outer_dark.continuum.anchor_door_id
	draw_fmt(
		rect.x + 18,
		rect.y + rect.height - 31,
		TYPE_MICRO,
		UX.text,
		"[ ] START · %s",
		game.dark_correspondence_name(
			s.campaign,
			departure_door,
			start_index,
			p.departure_door_position_name_hash,
		),
	)
	draw_fmt(
		rect.x + rect.width - 238,
		rect.y + rect.height - 31,
		TYPE_MICRO,
		UX.info,
		"<> END · %s",
		game.dark_correspondence_name(s.campaign, p.pending_door_id, end_index),
	)
}

dark_draw_expedition_clock :: proc(s: ^Ux_State) {
	p := &s.campaign.passage
	// Time is evidence, not a command.  Showing both clocks avoids a hidden
	// toggle and leaves the map's input surface unambiguous.
	draw_fmt(20, 128, TYPE_MICRO, UX.text, "SHIP %.2f D", p.elapsed_days)
	draw_fmt(172, 128, TYPE_MICRO, UX.info, "MEMBRANE %.2f D", p.membrane_elapsed_days)
}
