package main

import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:testing"
import rl "zelda_engine:canvas2d"

dark_gamepad_axis :: proc(axis: rl.Gamepad_Axis) -> f64 {
	v := f64(rl.GetGamepadAxis(axis)); deadzone := f64(.18); if math.abs(v) <= deadzone do return 0
	return (math.abs(v) - deadzone) / (1 - deadzone) * (v < 0 ? -1 : 1)
}

dark_camera_relative_helm_direction :: proc(
	orientation: Combat_Quat,
	screen_x, screen_y, view_depth, w: f64,
) -> game.Dark_Vec4 {
	q := orientation
	if q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w < .1 do q = combat_default_orientation()
	world := combat_quat_inverse_rotate(q, {f32(screen_x), f32(screen_y), f32(view_depth)})
	return {f64(world.x), f64(world.y), f64(world.z), w}
}

dark_helm_direction :: proc(s: ^Ux_State) -> game.Dark_Vec4 {
	screen_x, screen_y, view_depth, w := f64(0), f64(0), f64(0), f64(0)
	if rl.IsKeyDown(.A) do screen_x -= 1; if rl.IsKeyDown(.D) do screen_x += 1
	if rl.IsKeyDown(.W) do screen_y += 1; if rl.IsKeyDown(.S) do screen_y -= 1
	if rl.IsKeyDown(.Q) do view_depth -= 1; if rl.IsKeyDown(.E) do view_depth += 1
	if rl.IsKeyDown(.R) do w += 1; if rl.IsKeyDown(.F) do w -= 1
	if rl.GamepadAvailable() {
		screen_x += dark_gamepad_axis(.Left_X); screen_y -= dark_gamepad_axis(.Left_Y)
		if rl.IsGamepadButtonDown(.Left_Shoulder) do view_depth -= 1; if rl.IsGamepadButtonDown(.Right_Shoulder) do view_depth += 1
		w += max(dark_gamepad_axis(.Right_Trigger), 0) - max(dark_gamepad_axis(.Left_Trigger), 0)
	}
	return dark_camera_relative_helm_direction(
		s.dark_orientation,
		screen_x,
		screen_y,
		view_depth,
		w,
	)
}

@(test)
dark_helm_identity_camera_preserves_screen_axes :: proc(t: ^testing.T) {
	d := dark_camera_relative_helm_direction({0, 0, 0, 1}, 1, -2, .5, 3)
	testing.expect(
		t,
		math.abs(d[0] - 1) < 1e-6 && math.abs(d[1] + 2) < 1e-6 && math.abs(d[2] - .5) < 1e-6,
	)
	testing.expect_value(t, d[3], f64(3))
}

@(test)
dark_helm_orbit_rotates_screen_and_depth_axes_together :: proc(t: ^testing.T) {
	q := combat_quat_mul(combat_quat_axis({1, 0, 0}, -.6), combat_quat_axis({0, 0, 1}, .8))
	right := dark_camera_relative_helm_direction(q, 1, 0, 0, 0)
	depth := dark_camera_relative_helm_direction(q, 0, 0, 1, 0)
	visible_right := combat_quat_rotate(q, {f32(right[0]), f32(right[1]), f32(right[2])})
	visible_depth := combat_quat_rotate(q, {f32(depth[0]), f32(depth[1]), f32(depth[2])})
	testing.expect(
		t,
		math.abs(visible_right.x - 1) < 1e-5 &&
		math.abs(visible_right.y) < 1e-5 &&
		math.abs(visible_right.z) < 1e-5,
	)
	testing.expect(
		t,
		math.abs(visible_depth.x) < 1e-5 &&
		math.abs(visible_depth.y) < 1e-5 &&
		math.abs(visible_depth.z - 1) < 1e-5,
	)
}

@(test)
dark_helm_fourth_axis_is_camera_independent :: proc(t: ^testing.T) {
	a := dark_camera_relative_helm_direction({0, 0, 0, 1}, 0, 0, 0, 1)
	b := dark_camera_relative_helm_direction(combat_quat_axis({0, 1, 0}, 1.2), 0, 0, 0, 1)
	testing.expect_value(t, a, game.Dark_Vec4{0, 0, 0, 1})
	testing.expect_value(t, b, game.Dark_Vec4{0, 0, 0, 1})
}

dark_cycle_target :: proc(s: ^Ux_State, step: int) {
	p := &s.campaign.passage; d := &s.campaign.outer_dark.continuum; ids: [game.MAX_DARK_DOORS + game.MAX_DARK_TRACKS]u64; kinds: [len(ids)]Dark_Ui_Selection_Kind; count := 0
	for &door in d.doors[:d.door_count] {if game.dark_door_detection_confidence(d, p.dark_navigation.position, &door) <= 0 do continue; ids[count] = door.id; kinds[count] = .Door; count += 1}
	for &track in p.dark_navigation.tracker.tracks[:p.dark_navigation.tracker.track_count] {ids[count] = track.organism_id; kinds[count] = .Tracked_Contact; count += 1}
	if count == 0 do return
	current := -1; for i in 0 ..< count do if ids[i] == s.dark_selection_id && kinds[i] == s.dark_selection_kind {current = i; break}
	next := current + step; if next < 0 do next = count - 1; if next >= count do next = 0
	s.dark_selection_id =
		ids[next]; s.dark_selection_kind = kinds[next]; s.dark_contacts_open = false; s.dark_intent_open = false; s.dark_fine_plot_open = false
	if s.dark_selection_kind == .Door do _ = dark_refresh_selected_course(s)
}

dark_discrete_controls :: proc(s: ^Ux_State) {
	p := &s.campaign.passage; d := &s.campaign.outer_dark.continuum
	next :=
		rl.IsKeyPressed(.TAB) ||
		rl.IsGamepadButtonPressed(.Dpad_Right) ||
		rl.IsGamepadButtonPressed(.Dpad_Down)
	prior := rl.IsGamepadButtonPressed(.Dpad_Left) || rl.IsGamepadButtonPressed(.Dpad_Up)
	if next {dark_cycle_target(s, 1)} else if prior {dark_cycle_target(s, -1)}
	accept := rl.IsKeyPressed(.ENTER)
	if rl.GamepadAvailable() {
		rx, ry :=
			dark_gamepad_axis(.Right_X),
			dark_gamepad_axis(
				.Right_Y,
			); if math.abs(rx) > 0 || math.abs(ry) > 0 do dark_3d_orbit(s, f32(rx * .035), f32(ry * .035))
		if rl.IsGamepadButtonPressed(.North) do s.dark_contacts_open = !s.dark_contacts_open
		if rl.IsGamepadButtonPressed(.West) && s.dark_selection_kind == .Door do s.dark_fine_plot_open = !s.dark_fine_plot_open
		if rl.IsGamepadButtonPressed(.Start) do d.paused = !d.paused
		if rl.IsGamepadButtonPressed(.East) {
			if p.dark_navigation.manual_active do _ = game.set_passage_manual_helm(s.campaign, p, {})
			p.dark_navigation.autopilot_active =
				false; if p.phase == .Underway {p.phase = .Awaiting_Leg; p.pause_reason = .None}
			s.dark_selection_kind = .None; s.dark_selection_id = 0; s.dark_course_draft = {}
		}
		accept = accept || rl.IsGamepadButtonPressed(.South)
	}
	if accept {
		if at := game.dark_door_at_position(d, p.dark_navigation.position);
		   at >=
		   0 {_, s.status = game.cross_passage_door(s.campaign, p)} else if s.dark_selection_kind == .Door && s.dark_course_draft.waypoint_count >= 2 {_, _ = game.plot_passage_course(s.campaign, p, s.dark_course_draft)}
	}
}

dark_course_remaining :: proc(
	d: ^game.Dark_Continuum,
	n: ^game.Dark_Expedition_Navigation,
) -> f64 {
	if n.course.waypoint_count < 2 || n.segment >= n.course.waypoint_count - 1 do return 0
	r := game.dark_metric_distance(d.seed, n.position, n.course.waypoints[n.segment + 1].position)
	for i in n.segment + 2 ..< n.course.waypoint_count do r += game.dark_metric_distance(d.seed, n.course.waypoints[i - 1].position, n.course.waypoints[i].position)
	return r
}

dark_draw_w_profile :: proc(
	d: ^game.Dark_Continuum,
	course: ^game.Dark_Course,
	r: rl.Rectangle,
	current_w: f64,
) {
	if course.waypoint_count < 2 do return
	min_w, max_w :=
		current_w,
		current_w; for point in course.waypoints[:course.waypoint_count] {min_w = min(min_w, point.position[3]); max_w = max(max_w, point.position[3])}; span := max(max_w - min_w, .25)
	map_point := proc(
		point: game.Dark_Vec4,
		index, count: int,
		min_w, span: f64,
		r: rl.Rectangle,
	) -> rl.Vector2 {return{
			r.x + f32(index) / f32(max(count - 1, 1)) * r.width,
			r.y + r.height - f32((point[3] - min_w) / span) * r.height,
		}}
	for i in 1 ..< course.waypoint_count {a := map_point(course.waypoints[i - 1].position, i - 1, course.waypoint_count, min_w, span, r); b := map_point(course.waypoints[i].position, i, course.waypoint_count, min_w, span, r); rl.DrawLineEx(a, b, 1.5, UX.info)}
	entry_y :=
		r.y +
		r.height -
		f32((d.anchor_position[3] - min_w) / span) *
			r.height; rl.DrawLineEx({r.x, entry_y}, {r.x + r.width, entry_y}, 1, UX.dim)
}

dark_draw_navigation_feedback :: proc(s: ^Ux_State) {
	p := &s.campaign.passage; d := &s.campaign.outer_dark.continuum; course := p.dark_navigation.course; preview := false
	if s.dark_course_draft.waypoint_count >=
	   2 {course = s.dark_course_draft; preview = true} else if course.waypoint_count < 2 do return
	if p.dark_navigation.manual_active && !preview do return
	destination :=
		course.waypoints[course.waypoint_count - 1].position
	remaining := preview ? game.dark_course_forecast(d, &course).distance : dark_course_remaining(d, &p.dark_navigation)
	timing_course := course
	if !preview {
		if remaining_course, ok := game.passage_remaining_course(p); ok do timing_course = remaining_course
	}
	timing := game.passage_course_time_forecast(s.campaign, p, &timing_course)
	state :=
		preview ? "COURSE PREVIEW" : p.phase == .Awaiting_Leg ? (p.pause_reason == .Course_Arrival ? "ARRIVAL" : "COURSE HELD") : "COURSE UNDERWAY"
	feedback_y := f32(132)
	rl.DrawRectangleRec(
		{18, feedback_y, 354, 78},
		rl.Color{4, 4, 4, 218},
	); draw_fmt(28, feedback_y + 8, TYPE_MICRO, preview ? UX.info : UX.text, "%s · RANGE %.2f · SHIP %.1f D · MEMBRANE %.1f D", state, remaining, timing.ship_days, timing.membrane_days)
	dark_draw_w_profile(
		d,
		&course,
		{28, feedback_y + 32, 330, 32},
		p.dark_navigation.position[3],
	); draw_fmt(28, feedback_y + 66, TYPE_MICRO, UX.dim, "W NOW %+.2f · TARGET %+.2f", p.dark_navigation.position[3] - d.anchor_position[3], destination[3] - d.anchor_position[3])
	world := dark_target_world(
		d.anchor_position,
		destination,
	); screen, visible := dark_3d_project_to_ui(s, world); screen.x = clamp(screen.x, f32(28), f32(1252)); screen.y = clamp(screen.y, f32(82), f32(590)); ink := preview ? UX.info : UX.good
	rl.DrawRectangleRoundedLinesEx(
		{screen.x - 10, screen.y - 10, 20, 20},
		0,
		1,
		1.5,
		ink,
	); draw_text(preview ? "COURSE TARGET" : fmt.tprintf("TARGET · %.1f", remaining), screen.x + 15, screen.y - 6, TYPE_MICRO, ink)
	if !visible do draw_text("OFF-SCREEN", screen.x + 15, screen.y + 10, TYPE_MICRO, UX.dim)
}

dark_draw_arrival_tray :: proc(s: ^Ux_State) -> bool {
	p := &s.campaign.passage; if p.phase != .Awaiting_Leg || p.pause_reason != .Course_Arrival do return false; d := &s.campaign.outer_dark.continuum; at := game.dark_door_at_position(d, p.dark_navigation.position); if at < 0 do return false
	door := &d.doors[at]; rl.DrawRectangle(0, 612, 1280, 108, rl.Color{4, 4, 4, 244}); rl.DrawLineEx({0, 612}, {1280, 612}, 1, UX.good)
	draw_fmt(
		20,
		624,
		TYPE_CAPTION,
		UX.good,
		"OPENING %04d IN RANGE",
		door.id % 10000,
	); draw_text("Arrival complete. The fleet is holding position.", 20, 652, TYPE_FINE, UX.text)
	if button({816, 632, 210, 42}, "CHANGE COURSE", true, true) {
		s.dark_selection_kind = .None
		s.dark_selection_id = 0
		s.dark_course_draft = {}
		s.status = "Select an opening to plot a new course."
	}
	if button(
		{1044, 632, 210, 42},
		"CROSS OPENING",
		true,
		true,
	) {_, s.status = game.cross_passage_door(s.campaign, p)}
	return true
}
