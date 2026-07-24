package main

import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:testing"
import rl "zelda_engine:canvas2d"

FAR_PLOT :: rl.Rectangle{235, 92, 760, 468}

far_engagement_return_destination :: proc(origin: Ux_Screen) -> Ux_Screen {
	return origin == .Menu ? .Menu : .Fleet
}

@(test)
far_engagement_menu_launch_returns_to_menu :: proc(t: ^testing.T) {
	testing.expect_value(t, far_engagement_return_destination(.Menu), Ux_Screen.Menu)
	testing.expect_value(t, far_engagement_return_destination(.Fleet), Ux_Screen.Fleet)
}

far_engagement_restore_story :: proc(s: ^Ux_State) {
	if !s.far_engagement_standalone do return
	game.campaign_destroy_heap(s.campaign)
	if s.far_engagement_story_available {
		s.campaign = s.far_engagement_story_campaign
	} else {
		game.campaign_destroy_heap(s.far_engagement_story_campaign)
		s.campaign = new(game.Campaign)
	}
	s.far_engagement_story_campaign = nil
	s.has_campaign = s.far_engagement_story_available
	s.far_engagement_standalone = false
	s.far_engagement_story_available = false
	s.status = ""
}

launch_standalone_far_engagement :: proc(s: ^Ux_State) {
	seed := u64(rl.GetTime() * 1000000) + 1
	s.far_engagement_story_campaign = s.campaign
	s.far_engagement_story_available = s.has_campaign
	s.campaign = new(game.Campaign)
	game.campaign_init(s.campaign, seed)
	s.has_campaign = false
	s.far_engagement_standalone = true
	s.return_screen = .Menu
	far_engagement_start(s, seed ~ 0x666172)
}

@(test)
standalone_far_engagement_restores_the_parked_chronicle :: proc(t: ^testing.T) {
	s := ux_state_create()
	defer ux_state_destroy(s)
	game.campaign_init(s.campaign, 41)
	s.has_campaign = true
	parked := s.campaign
	event_count := parked.event_count

	launch_standalone_far_engagement(s)

	testing.expect(t, s.far_engagement_standalone)
	testing.expect_value(t, s.has_campaign, false)
	testing.expect(t, s.campaign != parked)
	far_engagement_restore_story(s)
	testing.expect(t, s.campaign == parked)
	testing.expect_value(t, s.has_campaign, true)
	testing.expect_value(t, s.campaign.event_count, event_count)
}

far_engagement_start :: proc(s: ^Ux_State, seed: u64) {
	if s.campaign.far_engagement == nil {
		s.campaign.far_engagement = new(game.Far_Engagement)
	}
	s.campaign.far_engagement^ = game.far_generate_campaign_encounter(
		s.campaign,
		seed,
		game.Far_Objective_Family(game.far_mix(seed) % 5),
	)
	s.far_speed = 60
	s.far_paused = false
	s.far_last_time = rl.GetTime()
	s.far_selected_group = 0
	s.far_selected_contact = 0
	s.far_last_saved_record_count = 0
	s.far_plot_pan_x = 0
	s.far_plot_pan_y = 0
	s.far_plot_zoom = 1
	s.screen = .Far_Engagement
}

far_plot_point :: proc(s: ^Ux_State, p: game.Far_Vec2) -> rl.Vector2 {
	zoom := max(s.far_plot_zoom, .25)
	x_normal := (f32(p.x / 40.0) - .5) * zoom + .5 + s.far_plot_pan_x
	y_normal := f32(p.y / 12.0) * zoom + s.far_plot_pan_y
	return V(
		FAR_PLOT.x + x_normal * FAR_PLOT.width,
		FAR_PLOT.y + FAR_PLOT.height * .5 - y_normal * FAR_PLOT.height * .45,
	)
}

far_draw_meter :: proc(x, y, w: f32, label: string, value: f64, color: rl.Color) {
	draw_fmt(x, y, TYPE_FINE, UX.dim, "%s %.0f", label, value)
	rl.DrawRectangleRec(R(x, y + 13, w, 5), UX.raised)
	rl.DrawRectangleRec(R(x, y + 13, w * f32(clamp(value / 100, 0, 1)), 5), color)
}

far_preview_summary :: proc(preview: game.Far_Decision_Preview) -> string {
	parts: [7]string
	count := 0
	if preview.command_delay_seconds > 0 {
		parts[count] = fmt.tprintf("ORDER +%.0fs", preview.command_delay_seconds)
		count += 1
	}
	if preview.delta_v_cost_km_s > 0 {
		parts[count] = fmt.tprintf("ΔV −%.0f", preview.delta_v_cost_km_s)
		count += 1
	}
	if preview.arrival_change_seconds != 0 {
		parts[count] = fmt.tprintf("ETA %+.1fh", preview.arrival_change_seconds / 3600)
		count += 1
	}
	if preview.ordnance_cost > 0 {
		parts[count] = fmt.tprintf("ORD −%d", preview.ordnance_cost)
		count += 1
	}
	if preview.decoy_cost > 0 {
		parts[count] = fmt.tprintf("DECOYS −%d", preview.decoy_cost)
		count += 1
	}
	if preview.uncertainty_change_km != 0 {
		parts[count] = fmt.tprintf("TRACK %+.0fkm", preview.uncertainty_change_km)
		count += 1
	}
	if preview.weapon_flight_seconds > 0 {
		parts[count] = fmt.tprintf(
			"FLIGHT %s",
			game.far_format_time(preview.weapon_flight_seconds / 3600),
		)
		count += 1
		parts[count] = fmt.tprintf(
			"ARRIVAL ±%.1fMkm",
			preview.target_uncertainty_at_arrival_km / 1.0e6,
		)
		count += 1
	}
	if count == 0 do return "NO IMMEDIATE RESOURCE COST"
	result := parts[0]
	for i in 1 ..< count do result = fmt.tprintf("%s · %s", result, parts[i])
	return result
}

far_draw_motion_vector :: proc(
	start, finish: rl.Vector2,
	color: rl.Color,
	speed_km_s: f64,
	label: string,
) {
	dx, dy := finish.x - start.x, finish.y - start.y
	length := math.sqrt(f64(dx * dx + dy * dy))
	if length < 4 do return
	unit_x, unit_y := f32(f64(dx) / length), f32(f64(dy) / length)
	perp_x, perp_y := -unit_y, unit_x
	rl.DrawLineEx(start, finish, 2, rl.Color{color.r, color.g, color.b, 150})
	arrow_base := V(finish.x - unit_x * 8, finish.y - unit_y * 8)
	rl.DrawLineEx(finish, V(arrow_base.x + perp_x * 4, arrow_base.y + perp_y * 4), 2, color)
	rl.DrawLineEx(finish, V(arrow_base.x - perp_x * 4, arrow_base.y - perp_y * 4), 2, color)
	draw_fmt(finish.x + 5, finish.y + 5, TYPE_MICRO, color, "%s · %.0f km/s", label, speed_km_s)
}

far_operational_question :: proc(e: ^game.Far_Engagement) -> string {
	if e.recovery_committed && !e.recovery_completed do return "Can Far Lantern reach the disabled screen ship before the route pressure closes?"
	if e.recovery_completed do return "Recovery completed. Both screen groups are returning to the route."
	switch e.phase {
	case .Find:
		return "Can the fleet make this track actionable before the corridor closes?"
	case .Fix:
		return "Which observation risk improves the next report enough to act?"
	case .Shape:
		return "Spend ordnance now, or preserve it for a clearer approach?"
	case .Commit:
		return "Which formation accepts the inbound acquisition risk?"
	case .Interpret:
		return "Does the result preserve the route, or require recovery or withdrawal?"
	case .Complete:
		return "The operation is complete."
	case .Dormant:
		return "Commit standing orders and establish the operational picture."
	}
	return "Establish the operational picture."
}

far_opening_commitment_label :: proc(command: game.Far_Command) -> string {
	#partial switch command {
	case .Hold_Protected_Course:
		return "HOLD PASSAGE"
	case .Shift_Intercept:
		return "SHIFT INTERCEPT"
	case .Branch_Formation:
		return "BRANCH COURSE"
	}
	return "UNSET"
}

far_draw_plot :: proc(s: ^Ux_State, e: ^game.Far_Engagement) {
	panel(FAR_PLOT)
	mouse := rl.GetMousePosition()
	if rl.CheckCollisionPointRec(mouse, FAR_PLOT) {
		wheel := rl.GetMouseWheelMove()
		if wheel != 0 do s.far_plot_zoom = clamp(s.far_plot_zoom * (1 + wheel * .12), .6, 4)
		if rl.IsMouseButtonDown(.RIGHT) {
			delta := rl.GetMouseDelta()
			s.far_plot_pan_x += delta.x / FAR_PLOT.width
			s.far_plot_pan_y -= delta.y / (FAR_PLOT.height * .45)
		}
	}
	rl.BeginScissorMode(FAR_PLOT)
	for i in 0 ..= 6 {
		x := FAR_PLOT.x + f32(i) * FAR_PLOT.width / 6
		rl.DrawLineEx(
			V(x, FAR_PLOT.y),
			V(x, FAR_PLOT.y + FAR_PLOT.height),
			1,
			rl.Color{UX.line.r, UX.line.g, UX.line.b, 75},
		)
		draw_fmt(
			x + 4,
			FAR_PLOT.y + FAR_PLOT.height - 16,
			TYPE_MICRO,
			UX.dim,
			"%.0f Mkm",
			f32(i) * 40.0 / 6.0,
		)
	}
	for i in -3 ..= 3 {
		y := FAR_PLOT.y + FAR_PLOT.height * .5 + f32(i) * FAR_PLOT.height / 7
		rl.DrawLineEx(
			V(FAR_PLOT.x, y),
			V(FAR_PLOT.x + FAR_PLOT.width, y),
			1,
			rl.Color{UX.line.r, UX.line.g, UX.line.b, 55},
		)
	}
	passage := far_plot_point(s, e.protected_course)
	rl.DrawCircleV(passage, 17, rl.Color{UX.good.r, UX.good.g, UX.good.b, 28})
	combat_draw_ring(passage, 17, UX.good)
	draw_text("PASSAGE WINDOW", passage.x - 45, passage.y + 23, TYPE_FINE, UX.good)

	// The viable-course envelope is the operational terrain: all projected
	// courses reaching the Passage before the deadline remain inside the wedge.
	fleet := far_plot_point(s, e.groups[0].position)
	remaining_seconds := max(0, e.deadline_seconds - e.elapsed_seconds)
	reachable_km := game.far_reachable_radius_km(
		e.task_groups[0].delta_v_remaining_km_s,
		e.task_groups[0].max_acceleration_km_s2,
		remaining_seconds,
	)
	margin := f32(clamp(reachable_km / 1.0e6 / 12.0 * f64(FAR_PLOT.height) * .45, 8, 150))
	rl.DrawLineEx(
		fleet,
		V(passage.x, passage.y - margin),
		1,
		rl.Color{UX.info.r, UX.info.g, UX.info.b, 100},
	)
	rl.DrawLineEx(
		fleet,
		V(passage.x, passage.y + margin),
		1,
		rl.Color{UX.info.r, UX.info.g, UX.info.b, 100},
	)
	rl.DrawLineEx(
		V(passage.x, passage.y - margin),
		V(passage.x, passage.y + margin),
		1,
		rl.Color{UX.info.r, UX.info.g, UX.info.b, 60},
	)

	for contact, contact_index in e.contacts[:e.contact_count] {
		if !contact.active do continue
		p := far_plot_point(s, contact.estimated_position)
		radius := f32(clamp(contact.uncertainty_mkm / 390 * f64(FAR_PLOT.width), 8, 90))
		rl.DrawCircleV(p, radius, rl.Color{UX.bad.r, UX.bad.g, UX.bad.b, 18})
		combat_draw_ring(p, radius, rl.Color{UX.bad.r, UX.bad.g, UX.bad.b, 130})
		rl.DrawLineEx(V(p.x - 7, p.y), V(p.x + 7, p.y), 2, UX.bad)
		rl.DrawLineEx(V(p.x, p.y - 7), V(p.x, p.y + 7), 2, UX.bad)
		draw_fmt(p.x + 11, p.y - 18, TYPE_FINE, UX.bad, "%s · %v", contact.name, contact.identity)
		draw_fmt(
			p.x + 11,
			p.y - 5,
			TYPE_MICRO,
			UX.dim,
			"CONF %.0f%% · ±%.0f Mkm",
			contact.confidence * 100,
			contact.uncertainty_mkm,
		)
		end := far_plot_point(
			s,
			{
				contact.estimated_position.x + contact.estimated_velocity.x * 4,
				contact.estimated_position.y + contact.estimated_velocity.y * 4,
			},
		)
		far_draw_motion_vector(
			p,
			end,
			UX.bad,
			game.far_vec_length(contact.estimated_velocity) * 1.0e6 / 3600,
			"4H VECTOR",
		)
		pointer := rl.GetMousePosition()
		if (pointer.x - p.x) * (pointer.x - p.x) + (pointer.y - p.y) * (pointer.y - p.y) <=
			   radius * radius &&
		   rl.IsMouseButtonPressed(.LEFT) {
			s.far_selected_contact = contact_index
			_ = game.far_set_selected_belief(e, contact_index)
		}
	}

	group_colors := [3]rl.Color{UX.good, UX.warn, UX.info}
	for group, i in e.groups[:e.group_count] {
		p := far_plot_point(s, group.position)
		color := group_colors[min(i, 2)]
		if group.state == .Disabled || group.state == .Lost do color = UX.bad
		rl.DrawCircleV(p, 7, color)
		combat_draw_ring(p, 13, rl.Color{color.r, color.g, color.b, 100})
		reach_one_hour := game.far_reachable_radius_km(
			e.task_groups[i].delta_v_remaining_km_s,
			e.task_groups[i].max_acceleration_km_s2,
			3600,
		)
		reach_pixels := f32(clamp(reach_one_hour / 40.0e6 * f64(FAR_PLOT.width), 4, 72))
		combat_draw_ring(p, reach_pixels, rl.Color{color.r, color.g, color.b, 42})
		end := far_plot_point(
			s,
			{group.position.x + group.velocity.x * 4, group.position.y + group.velocity.y * 4},
		)
		far_draw_motion_vector(
			p,
			end,
			color,
			game.far_vec_length(group.velocity) * 1.0e6 / 3600,
			"4H VECTOR",
		)
		draw_fmt(p.x + 12, p.y + 7, TYPE_FINE, color, "%s · %v", group.name, group.state)
		pointer := rl.GetMousePosition()
		dx, dy := pointer.x - p.x, pointer.y - p.y
		if dx * dx + dy * dy <= 15 * 15 && rl.IsMouseButtonPressed(.LEFT) {
			s.far_selected_group = i
		}
	}

	for flight in e.weapon_flights[:e.weapon_flight_count] {
		if !flight.active || !flight.detected do continue
		p := far_plot_point(s, {flight.position.x / 1.0e6, flight.position.y / 1.0e6})
		color := flight.friendly ? UX.warn : UX.bad
		remaining_seconds := max(0, flight.predicted_arrival_seconds - e.elapsed_seconds)
		vector_seconds := min(remaining_seconds, 4 * 3600)
		end := far_plot_point(
			s,
			{
				(flight.position.x + flight.velocity.x * vector_seconds) / 1.0e6,
				(flight.position.y + flight.velocity.y * vector_seconds) / 1.0e6,
			},
		)
		far_draw_motion_vector(
			p,
			end,
			color,
			game.far_vec_length(flight.velocity),
			flight.friendly ? "OUTBOUND" : "INBOUND",
		)
		combat_draw_ring(p, 9, color)
		target_label := "HOSTILE TRACK"
		if !flight.friendly {
			for group, group_index in e.task_groups[:e.task_group_count] do if group.stable_id == flight.target_group_id {
				target_label = e.groups[group_index].name
				break
			}
		}
		draw_fmt(
			p.x + 11,
			p.y - 5,
			TYPE_MICRO,
			color,
			"%v → %s · %s",
			flight.weapon_type,
			target_label,
			game.far_format_time(
				max(0, flight.predicted_arrival_seconds - e.elapsed_seconds) / 3600,
			),
		)
	}
	for transmission in e.transmissions[:e.transmission_count] {
		if !transmission.active do continue
		a := far_plot_point(
			s,
			{transmission.origin_position.x / 1.0e6, transmission.origin_position.y / 1.0e6},
		)
		b := far_plot_point(
			s,
			{
				transmission.receiver_position_at_send.x / 1.0e6,
				transmission.receiver_position_at_send.y / 1.0e6,
			},
		)
		rl.DrawLineEx(a, b, 1, rl.Color{UX.info.r, UX.info.g, UX.info.b, 70})
	}
	rl.EndScissorMode()
}

far_draw_groups :: proc(e: ^game.Far_Engagement) {
	panel(R(12, 92, 210, 568))
	label_caps("COMMAND ELEMENTS", 26, 108)
	for group, i in e.groups[:e.group_count] {
		y := f32(140 + i * 142)
		color := i == 0 ? UX.good : i == 1 ? UX.warn : UX.info
		draw_fmt(26, y, TYPE_SMALL_EMPHASIS, color, "%s", group.name)
		draw_fmt(26, y + 19, TYPE_FINE, UX.dim, "%s · %d SHIPS", group.commander, group.ships)
		draw_fmt(
			26,
			y + 35,
			TYPE_FINE,
			UX.text,
			"%s · %s",
			game.far_formation_name(group.formation),
			game.far_emission_name(group.emission),
		)
		far_draw_meter(26, y + 54, 172, "MANEUVER", group.maneuver_reserve, UX.info)
		far_draw_meter(26, y + 77, 172, "SIGNATURE", group.signature_reserve, UX.committed)
		far_draw_meter(26, y + 100, 172, "DEFENSE", group.defensive_reserve, UX.good)
	}
}

far_draw_intelligence :: proc(s: ^Ux_State, e: ^game.Far_Engagement) {
	panel(R(1008, 92, 260, 568))
	label_caps("COMMAND FORECAST", 1024, 108)
	arrival_hour := e.arrival_hour
	has_objective_eta := false
	if projected_seconds, ok := game.far_objective_eta_seconds(e); ok {
		arrival_hour = projected_seconds / 3600
		has_objective_eta = true
	}
	draw_fmt(1024, 136, TYPE_SMALL_EMPHASIS, UX.text, "%s", game.far_phase_name(e.phase))
	draw_fmt(
		1024,
		119,
		TYPE_MICRO,
		UX.info,
		"%v · %v",
		e.spec.objective_family,
		e.spec.complication,
	)
	draw_fmt(
		1024,
		158,
		TYPE_FINE,
		UX.dim,
		"SIMULATION %s / %s",
		game.far_format_time(e.hour),
		game.far_format_time(e.duration_hours),
	)
	if has_objective_eta {
		draw_fmt(
			1024,
			176,
			TYPE_FINE,
			arrival_hour <= e.deadline_hour ? UX.good : UX.bad,
			"OBJECTIVE ETA %s · DEADLINE %s",
			game.far_format_time(arrival_hour),
			game.far_format_time(e.deadline_hour),
		)
	} else {
		draw_fmt(
			1024,
			176,
			TYPE_FINE,
			UX.warn,
			"CONTACT-BOUND OBJECTIVE · DEADLINE %s",
			game.far_format_time(e.deadline_hour),
		)
	}
	divider(1024, 200, 228)
	label_caps("RESERVES", 1024, 216)
	draw_fmt(1024, 240, TYPE_SMALL, UX.text, "HEAVY ORDNANCE  %d", e.heavy_ordnance)
	draw_fmt(1024, 260, TYPE_SMALL, UX.text, "DECOY TRAINS     %d", e.decoys)
	margin_hours := has_objective_eta ? e.deadline_hour - arrival_hour : 0
	if has_objective_eta {
		draw_fmt(
			1024,
			280,
			TYPE_SMALL,
			margin_hours >= 0 ? UX.good : UX.warn,
			"OBJECTIVE MARGIN %s",
			game.far_format_time(max(0, margin_hours)),
		)
	} else {
		draw_text("OBJECTIVE MARGIN · CONTACT-BOUND", 1024, 280, TYPE_SMALL, UX.warn)
	}
	best_track: f64
	for belief in e.beliefs[:e.belief_count] do best_track = max(best_track, belief.confidence)
	screen_index := min(1, e.group_count - 1)
	draw_fmt(
		1024,
		298,
		TYPE_MICRO,
		UX.info,
		"TRACK %.0f%% · SCREEN %.0f%% · INTERCEPT %+.1fh",
		best_track * 100,
		e.groups[screen_index].cohesion,
		e.intercept_margin_hours,
	)
	draw_text_wrapped(far_operational_question(e), R(1024, 312, 228, 30), TYPE_MICRO, UX.text)
	if e.recovery_committed && !e.recovery_completed {
		draw_text("RECOVERY · ORDER IN FLIGHT", 1024, 338, TYPE_MICRO, UX.warn)
	} else if e.recovery_completed {
		draw_text("RECOVERY · SCREEN SHIP RECOVERED", 1024, 338, TYPE_MICRO, UX.good)
	} else if e.opening_commitment != .Accept_Standing_Orders do draw_fmt(1024, 338, TYPE_MICRO, UX.committed, "OPENING · %s", far_opening_commitment_label(e.opening_commitment))
	divider(1024, 348, 228)
	label_caps("AUTHORITY", 1024, 362)
	authorities := [4]game.Far_Authority {
		.Report_Only,
		.Confirm_Commitments,
		.Confirm_Engagements,
		.Direct_Command,
	}
	authority_labels := [4]string{"REPORT", "COMMIT", "ENGAGE", "DIRECT"}
	for authority, i in authorities {
		if button(R(1024 + f32(i % 2) * 112, 384 + f32(i / 2) * 27, 106, 24), authority_labels[i], true, e.authority == authority) do game.far_set_authority(e, authority)
	}
	divider(1024, 444, 228)
	label_caps("CAUSE LEDGER", 1024, 460)
	y: f32 = 482
	// A ledger entry has its own timestamp line so the time never competes with
	// the record copy.  The body is clipped to this section: long operational
	// records must not escape the command panel or overlap later entries.
	ledger_bottom: f32 = 640
	ledger_clip := R(1024, y, 228, ledger_bottom - y)
	rl.BeginScissorMode(ledger_clip)
	for offset in 0 ..< min(e.record_count, 3) {
		if y >= ledger_bottom do break
		i := e.record_count - 1 - offset
		record := e.records[i]
		color := record.consequence ? UX.warn : UX.dim
		stamp := game.far_format_time(record.hour)
		draw_text(stamp, 1248 - measure_text(stamp, TYPE_MICRO).x, y, TYPE_MICRO, color)
		body_start := y + readable_text_size(TYPE_MICRO) + 3
		body_end := draw_text_wrapped(
			record.text,
			R(1037, body_start, 211, ledger_bottom - body_start),
			TYPE_MICRO,
			record.consequence ? UX.text : UX.dim,
		)
		if offset == 0 {
			rl.DrawRectangleRec(
				R(1028, body_start, 2, max(body_end - body_start - 2, f32(8))),
				UX.info,
			)
		} else {
			rl.DrawRectangleRec(R(1028, body_start + 4, 2, 2), UX.dim)
		}
		y = body_end + 7
	}
	rl.EndScissorMode()
}

far_draw_choice_projection :: proc(
	s: ^Ux_State,
	e: ^game.Far_Engagement,
	projection: game.Far_Choice_Projection,
) {
	if !projection.valid do return
	rl.BeginScissorMode(FAR_PLOT)
	for i in 0 ..< min(e.task_group_count, projection.task_count) {
		start := far_plot_point(s, e.task_groups[i].position)
		finish := far_plot_point(s, projection.task_positions[i])
		color := i == 0 ? UX.info : UX.committed
		ghost := rl.Color{color.r, color.g, color.b, 180}
		rl.DrawLineEx(start, finish, 2, ghost)
		rl.DrawCircleV(finish, 4, ghost)
	}
	rl.EndScissorMode()
	draw_fmt(
		FAR_PLOT.x + 12,
		FAR_PLOT.y + 12,
		TYPE_MICRO,
		UX.info,
		"BRANCH FORECAST · +%s · TRACK %.0f%% · DISABLED %d · LOST %d",
		game.far_format_time(projection.horizon_seconds / 3600),
		projection.track_confidence * 100,
		projection.ships_disabled,
		projection.ships_lost,
	)
}

far_draw_decision :: proc(s: ^Ux_State, e: ^game.Far_Engagement) {
	if !e.decision.pending do return
	// Decisions deliberately occupy the command rail instead of masking the
	// plot. Course geometry, weapon flights, and the cause ledger remain in
	// view while the player compares commitments.
	panel(R(235, 568, 760, 96), true)
	draw_fmt(
		249,
		578,
		TYPE_LABEL,
		UX.warn,
		"%s · %s",
		game.far_format_time(e.hour),
		e.decision.title,
	)
	draw_text_wrapped(e.decision.forecast, R(475, 578, 506, 17), TYPE_MICRO, UX.dim)
	option_count := max(e.decision.option_count, 1)
	option_width := (732 - f32(option_count - 1) * 8) / f32(option_count)
	for i in 0 ..< e.decision.option_count {
		x := f32(249) + f32(i) * (option_width + 8)
		selected := i == e.decision.default_option
		enabled := e.decision.option_enabled[i]
		option_rect := R(x, 608, option_width, 25)
		if button(option_rect, e.decision.labels[i], enabled, selected) do _ = game.far_resolve_decision(e, e.decision.commands[i])
		preview := game.far_preview_command(e, e.decision.commands[i])
		summary := enabled ? far_preview_summary(preview) : e.decision.unavailable_reasons[i]
		draw_text_wrapped(
			summary,
			R(x, 640, option_width, 18),
			TYPE_MICRO,
			enabled ? UX.info : UX.dim,
		)
		if contains(option_rect) {
			projection := game.far_project_choice(e, e.decision.commands[i])
			projection_summary :=
				projection.valid ? fmt.tprintf("Two-hour branch forecast: track %.0f%%; %d disabled; %d lost.", projection.track_confidence * 100, projection.ships_disabled, projection.ships_lost) : "No branch forecast is available for this command."
			detail :=
				enabled ? fmt.tprintf("%s\n%s\n%s", e.decision.consequences[i], far_preview_summary(preview), projection_summary) : fmt.tprintf("%s\nUnavailable: %s", e.decision.consequences[i], e.decision.unavailable_reasons[i])
			ux_tooltip = {
				visible     = true,
				anchor      = option_rect,
				title       = e.decision.labels[i],
				body        = detail,
				body_height = 110,
			}
			far_draw_choice_projection(s, e, projection)
		}
	}
	draw_fmt(249, 593, TYPE_MICRO, UX.dim, "STANDING DEFAULT · %s", e.decision.default_text)
}

far_draw_briefing :: proc(e: ^game.Far_Engagement) {
	if !e.briefing_pending do return
	rl.DrawRectangleRec(R(0, 0, UX_W, UX_H), rl.Color{0, 0, 0, 185})
	panel(R(118, 70, 1044, 580), true)
	label_caps("OPERATIONAL BRIEFING", 150, 96, UX.info)
	draw_fmt(150, 126, TYPE_HEADING_COMPACT, UX.text, "%v", e.spec.objective_family)
	draw_fmt(150, 158, TYPE_BODY, UX.warn, "COMPLICATION · %v", e.spec.complication)
	draw_text_wrapped(
		"Tracks are delayed beliefs. Once committed, orders and reports propagate at light speed; captains continue their last received intent.",
		R(150, 190, 950, 48),
		TYPE_SMALL,
		UX.dim,
	)
	doctrine_names := [3]string{"PRESERVE", "BALANCED", "AT COST"}
	for group, i in e.task_groups[:e.task_group_count] {
		x := f32(150 + i * 330)
		panel(R(x, 260, 300, 250))
		draw_fmt(x + 18, 278, TYPE_BODY_EMPHASIS, UX.text, "%s", e.groups[i].name)
		draw_fmt(x + 18, 307, TYPE_SMALL, UX.dim, "%d PERSISTENT SHIPS", group.member_count)
		draw_fmt(x + 18, 331, TYPE_SMALL, UX.info, "%s", game.far_command_name(group.order.verb))
		draw_fmt(
			x + 18,
			353,
			TYPE_FINE,
			UX.dim,
			"ΔV %.0f km/s · %.3f km/s²",
			group.delta_v_remaining_km_s,
			group.max_acceleration_km_s2,
		)
		for doctrine_index in 0 ..< 3 {
			if button(
				R(x + 18, 386 + f32(doctrine_index) * 30, 126, 25),
				doctrine_names[doctrine_index],
				true,
				int(group.doctrine) == doctrine_index,
			) {
				_ = game.far_set_task_group_doctrine(e, i, game.Far_Doctrine(doctrine_index))
			}
		}
		to := (i + 1) % e.task_group_count
		if button(R(x + 158, 386, 124, 56), "TRANSFER →", group.member_count > 1) {
			_ = game.far_transfer_last_member(e, i, to)
		}
	}
	draw_fmt(
		150,
		538,
		TYPE_SMALL,
		UX.dim,
		"DEADLINE %s · DESTINATION %.1f million km",
		game.far_format_time(e.deadline_seconds / 3600),
		e.spec.route_destination.x / 1.0e6,
	)
	if button(R(842, 572, 270, 46), "COMMIT STANDING ORDERS", true, true) {
		_ = game.far_commit_briefing(e)
	}
}

far_draw_result :: proc(s: ^Ux_State, e: ^game.Far_Engagement) {
	rl.DrawRectangleRec(R(0, 0, UX_W, UX_H), rl.Color{0, 0, 0, 170})
	panel(R(280, 130, 720, 430), true)
	label_caps("FAR ENGAGEMENT RECORD", 312, 160)
	draw_text_wrapped(e.result.ending, R(312, 196, 656, 48), TYPE_HEADING_COMPACT, UX.text)
	draw_fmt(
		312,
		264,
		TYPE_BODY,
		e.result.passage_reached ? UX.good : UX.warn,
		"OBJECTIVE · %s",
		e.result.passage_reached ? "PASSAGE REACHED" : "PASSAGE NOT REACHED",
	)
	draw_fmt(
		312,
		296,
		TYPE_BODY,
		e.result.deadline_kept ? UX.good : UX.warn,
		"DEADLINE · %s",
		e.result.deadline_kept ? "KEPT" : "MISSED",
	)
	draw_fmt(
		312,
		328,
		TYPE_BODY,
		UX.text,
		"SHIPS RECOVERABLE %d / %d",
		e.result.ships_arrived,
		e.result.friendly_ships,
	)
	draw_fmt(
		312,
		360,
		TYPE_BODY,
		UX.warn,
		"DISABLED %d · LOST %d · RECOVERED %d",
		e.result.ships_disabled,
		e.result.ships_lost,
		e.result.ships_recovered,
	)
	draw_fmt(
		312,
		392,
		TYPE_BODY,
		UX.dim,
		"HEAVY ORDNANCE %d · DECOYS %d",
		e.result.heavy_ordnance_spent,
		e.result.decoys_spent,
	)
	return_screen := far_engagement_return_destination(s.return_screen)
	return_label := return_screen == .Menu ? "RETURN TO MENU" : "RETURN TO FLEET"
	if button(R(312, 486, 210, 38), return_label) {
		if !s.far_engagement_standalone {
			if !e.outcome_applied do _ = game.far_apply_campaign_result(s.campaign)
			_ = ux_save(s, true)
		}
		s.screen = return_screen
	}
	if button(R(540, 486, 210, 38), "REPLAY SCENARIO") do far_engagement_start(s, e.seed)
}

draw_far_engagement :: proc(s: ^Ux_State) {
	e := s.campaign.far_engagement
	if e == nil {
		far_engagement_start(s, s.campaign.seed ~ 0x666172)
		e = s.campaign.far_engagement
	}
	now := rl.GetTime()
	dt := max(0, now - s.far_last_time)
	s.far_last_time = now
	if !s.far_paused &&
	   !e.decision.pending &&
	   !e.complete &&
	   !s.campaign.clock.paused_for_attention {
		// One wall-clock second advances far_speed simulated minutes.
		game.far_tick(e, dt * s.far_speed / 60)
	}
	game.campaign_sync_far_engagement(s.campaign, e)
	if !s.far_engagement_standalone &&
	   (e.decision.pending || e.complete) &&
	   e.record_count != s.far_last_saved_record_count {
		_ = ux_save(s, true)
		s.far_last_saved_record_count = e.record_count
	}
	rl.DrawRectangleRec(R(0, 0, UX_W, 72), UX.void)
	rl.DrawRectangleRec(R(0, 672, UX_W, 48), UX.void)
	divider(0, 72, UX_W)
	draw_text("FAR ENGAGEMENT", 18, 18, TYPE_HEADING, UX.text)
	draw_fmt(
		238,
		24,
		TYPE_LABEL,
		UX.info,
		"OPEN-SPACE INTERCEPTION · %s",
		game.far_phase_name(e.phase),
	)
	far_draw_plot(s, e)
	far_draw_groups(e)
	far_draw_intelligence(s, e)
	if !e.decision.pending {
		if button(R(235, 576, 68, 30), s.far_paused ? "RESUME" : "PAUSE", true, s.far_paused) do s.far_paused = !s.far_paused
		speeds := [4]f64{1, 10, 100, 1000}
		for speed, i in speeds {
			label := fmt.tprintf("%.0f×", speed)
			if button(R(310 + f32(i) * 62, 576, 56, 30), label, true, s.far_speed == speed) {
				s.far_speed = speed
				s.far_paused = false
			}
		}
		if button(R(566, 576, 144, 30), "NEXT DECISION", game.far_can_advance_to_decision(e)) do game.far_advance_to_decision(e)
		if button(R(718, 576, 120, 30), "SAVE RECORD") && !s.far_engagement_standalone {
			_ = ux_save(s, true)
		}
		return_screen := far_engagement_return_destination(s.return_screen)
		return_label := return_screen == .Menu ? "RETURN TO MENU" : "RETURN TO FLEET"
		if button(R(846, 576, 149, 30), return_label) {
			if !s.far_engagement_standalone do _ = ux_save(s, true)
			s.screen = return_screen
		}
	}
	if !e.decision.pending do draw_text("AI EXECUTES STANDING INTENT · COMMAND INTERRUPTS AT COMMITMENT BOUNDARIES", 235, 632, TYPE_FINE, UX.dim)
	far_draw_decision(s, e)
	far_draw_briefing(e)
	if e.complete do far_draw_result(s, e)
	draw_tooltip()
}
