package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:testing"

COMBAT_LABEL_ZONE_CAP :: 256
COMBAT_LABEL_RECT_CAP :: 256

Combat_Label_Zone :: struct {
	rect:   rl.Rectangle,
	weight: f32,
}
Combat_Label_Layout :: struct {
	zones:       [COMBAT_LABEL_ZONE_CAP]Combat_Label_Zone,
	zone_count:  int,
	labels:      [COMBAT_LABEL_RECT_CAP]rl.Rectangle,
	label_count: int,
}

combat_label_add_zone :: proc(
	layout: ^Combat_Label_Layout,
	center: rl.Vector2,
	radius, weight: f32,
) {
	if layout.zone_count >= COMBAT_LABEL_ZONE_CAP do return
	layout.zones[layout.zone_count] = {
		{center.x - radius, center.y - radius, radius * 2, radius * 2},
		weight,
	}
	layout.zone_count += 1
}

combat_rect_overlap_area :: proc(a, b: rl.Rectangle, padding: f32 = 0) -> f32 {
	x := max(0, min(a.x + a.width, b.x + b.width + padding) - max(a.x, b.x - padding))
	y := max(0, min(a.y + a.height, b.y + b.height + padding) - max(a.y, b.y - padding))
	return x * y
}

combat_label_candidate_score :: proc(
	layout: ^Combat_Label_Layout,
	rect: rl.Rectangle,
	anchor: rl.Vector2,
) -> f32 {
	score: f32
	for zone in layout.zones[:layout.zone_count] do score += combat_rect_overlap_area(rect, zone.rect, 10) * zone.weight
	// Labels are harder obstacles than action zones: action may sit beneath a
	// leader, but two archival readouts must never be composed as one block.
	for placed in layout.labels[:layout.label_count] do score += combat_rect_overlap_area(rect, placed, 12) * 1000
	cx := rect.x + rect.width * .5; cy := rect.y + rect.height * .5
	dx := cx - anchor.x; dy := cy - anchor.y
	// Down-screen placement obscures the direction of travel and the weapons
	// beneath a contact. Treat it as a fallback, while making longer lateral
	// leaders cheap enough for a dense group to fan out.
	below_penalty := cy > anchor.y ? (cy - anchor.y) * 45 : 0
	return score + (dx * dx + dy * dy) * .0008 + below_penalty
}

combat_place_label :: proc(
	layout: ^Combat_Label_Layout,
	anchor: rl.Vector2,
	w, h: f32,
	salt: int = 0,
) -> rl.Rectangle {
	// Search the upper fan first and at several lateral distances. Lower choices
	// exist only for anchors already pressed against the top of the viewport.
	// Salt prevents stacked anchors choosing the same spoke in lockstep.
	offsets := [12]rl.Vector2 {
		{32, -h - 26},
		{-w - 32, -h - 26},
		{-w * .5, -h - 42},
		{72, -h - 34},
		{-w - 72, -h - 34},
		{-w * .5 + 72, -h - 58},
		{-w * .5 - 72, -h - 58},
		{118, -h - 44},
		{-w - 118, -h - 44},
		{38, 24},
		{-w - 38, 24},
		{-w * .5, 34},
	}
	best := rl.Rectangle{}; best_score := f32(1e30)
	for step in 0 ..< len(offsets) {
		offset := offsets[(step + salt) % len(offsets)]
		candidate := R(anchor.x + offset.x, anchor.y + offset.y, w, h)
		candidate.x = clamp(
			candidate.x,
			COMBAT_VIEWPORT.x + 5,
			COMBAT_VIEWPORT.x + COMBAT_VIEWPORT.width - w - 5,
		)
		candidate.y = clamp(
			candidate.y,
			COMBAT_VIEWPORT.y + 27,
			COMBAT_VIEWPORT.y + COMBAT_VIEWPORT.height - h - 5,
		)
		score := combat_label_candidate_score(layout, candidate, anchor)
		if score < best_score {best = candidate; best_score = score}
	}
	if layout.label_count <
	   COMBAT_LABEL_RECT_CAP {layout.labels[layout.label_count] = best; layout.label_count += 1}
	return best
}

combat_label_connection :: proc(rect: rl.Rectangle, pin: rl.Vector2) -> rl.Vector2 {
	inset := min(f32(4), min(rect.width, rect.height) * .25)
	candidates := [4]rl.Vector2 {
		{rect.x, clamp(pin.y, rect.y + inset, rect.y + rect.height - inset)},
		{rect.x + rect.width, clamp(pin.y, rect.y + inset, rect.y + rect.height - inset)},
		{clamp(pin.x, rect.x + inset, rect.x + rect.width - inset), rect.y},
		{clamp(pin.x, rect.x + inset, rect.x + rect.width - inset), rect.y + rect.height},
	}
	best := candidates[0]
	best_distance := (best.x - pin.x) * (best.x - pin.x) + (best.y - pin.y) * (best.y - pin.y)
	for candidate in candidates[1:] {
		distance :=
			(candidate.x - pin.x) * (candidate.x - pin.x) +
			(candidate.y - pin.y) * (candidate.y - pin.y)
		if distance < best_distance {best = candidate; best_distance = distance}
	}
	return best
}

combat_label_rule_connection :: proc(rect: rl.Rectangle, pin: rl.Vector2) -> rl.Vector2 {
	left := rl.Vector2{rect.x, rect.y}
	right := rl.Vector2{rect.x + rect.width, rect.y}
	left_distance :=
		(left.x - pin.x) * (left.x - pin.x) +
		(left.y - pin.y) * (left.y - pin.y)
	right_distance :=
		(right.x - pin.x) * (right.x - pin.x) +
		(right.y - pin.y) * (right.y - pin.y)
	return left_distance <= right_distance ? left : right
}

combat_leader_pin_point :: proc(pin, connection: rl.Vector2, radius: f32 = 10) -> rl.Vector2 {
	dx := connection.x - pin.x; dy := connection.y - pin.y
	distance := f32(math.sqrt(f64(dx * dx + dy * dy)))
	if distance <= .001 do return pin
	step := min(radius, distance)
	return {pin.x + dx / distance * step, pin.y + dy / distance * step}
}

combat_build_label_layout :: proc(s: ^Ux_State) -> Combat_Label_Layout {
	layout: Combat_Label_Layout
	// Sample the complete battle deterministically when stress battles exceed the
	// overlay budget. Salvos and impacts are added separately at higher weight.
	stride := max(1, (s.combat.unit_count + 191) / 192)
	for i := 0; i < s.combat.unit_count; i += stride {
		u := s.combat.units[i]; if u.extracted do continue
		position := u.position
		if u.side ==
		   .Raider {contact, known := game.combat_contact_position(&s.combat, .Friendly, i); if !known do continue; position = contact}
		p, visible := combat_3d_project_to_ui(
			s,
			position,
		); if visible do combat_label_add_zone(&layout, p, u.action == .Attack_Run ? 30 : 22, u.action == .Attack_Run ? 3 : 1.5)
	}
	for salvo in s.combat.salvos {if salvo.active {p, visible := combat_3d_project_to_ui(s, salvo.position); if visible do combat_label_add_zone(&layout, p, 34, 5)}}
	if s.combat.ability_pending {p, visible := combat_3d_project_to_ui(s, s.combat.ability_target); if visible do combat_label_add_zone(&layout, p, 48, 7)}
	return layout
}

combat_draw_viewport_instrument :: proc() {
	// A restrained etched reticle makes the map read as a projected command
	// instrument instead of a window onto ordinary space.
	view :=
		COMBAT_VIEWPORT; rule := rl.Color{147, 173, 176, 72}; faint := rl.Color{147, 173, 176, 34}
	for x := view.x + 20;
	    x < view.x + view.width;
	    x += 40 {major := int(x - view.x) % 200 == 20; length: f32 = major ? 9 : 4; rl.DrawLineEx({x, view.y}, {x, view.y + length}, 1, major ? rule : faint); rl.DrawLineEx({x, view.y + view.height - length}, {x, view.y + view.height}, 1, major ? rule : faint)}
	for y := view.y + 20;
	    y < view.y + view.height;
	    y += 40 {major := int(y - view.y) % 200 == 20; length: f32 = major ? 9 : 4; rl.DrawLineEx({view.x, y}, {view.x + length, y}, 1, major ? rule : faint); rl.DrawLineEx({view.x + view.width - length, y}, {view.x + view.width, y}, 1, major ? rule : faint)}
	cx := view.x + view.width * .5; cy := view.y + view.height * .5
	rl.DrawLineEx(
		{cx - 18, cy},
		{cx - 5, cy},
		1,
		faint,
	); rl.DrawLineEx({cx + 5, cy}, {cx + 18, cy}, 1, faint); rl.DrawLineEx({cx, cy - 18}, {cx, cy - 5}, 1, faint); rl.DrawLineEx({cx, cy + 5}, {cx, cy + 18}, 1, faint)
	draw_text(
		"HOLOGRAPHIC TACTICAL VOLUME",
		view.x + 12,
		view.y + 10,
		TYPE_MICRO,
		rule,
	); draw_text("LIVE · RANGE UNCORRECTED", view.x + view.width - 160, view.y + 10, TYPE_MICRO, rule)
}

combat_draw_ring :: proc(p: rl.Vector2, r: f32, color: rl.Color) {rl.DrawCircleV(p, r, color)
	rl.DrawCircleV(p, max(r - 2, 0), UX.void)}

combat_depth_plane_icon_index :: proc(plane: game.Combat_Depth_Plane) -> int {switch
	plane {case .High:
		return 0; case .Plane:
		return 1; case .Low:
		return 2}
	return 1}
combat_draw_depth_plane_icon :: proc(
	plane: game.Combat_Depth_Plane,
	destination: rl.Rectangle,
	color: rl.Color,
) {source := R(f32(combat_depth_plane_icon_index(plane)) * 128, 0, 128, 128); rl.DrawTexturePro(
		combat_depth_plane_texture,
		source,
		destination,
		color,
	)}

combat_draw_sector_labels :: proc(s: ^Ux_State) {
	grid :=
		s.combat.grid; cell_x := (grid.max_x - grid.min_x) / f32(game.COMBAT_SECTOR_ROWS); cell_y := (grid.max_y - grid.min_y) / f32(game.COMBAT_SECTOR_COLUMNS); letters := [game.COMBAT_SECTOR_COLUMNS]string{"A", "B", "C", "D", "E", "F"}
	for column in 0 ..< game.COMBAT_SECTOR_COLUMNS {world := game.Combat_Vec3{grid.min_x - 18, grid.min_y + (f32(column) + .5) * cell_y, COMBAT_GRID_Z}; p, visible := combat_3d_project_to_ui(s, world); if visible do draw_text(letters[column], p.x - 3, p.y - 4, TYPE_MICRO, UX.info)}
	for row in 0 ..< game.COMBAT_SECTOR_ROWS {world := game.Combat_Vec3{grid.min_x + (f32(row) + .5) * cell_x, grid.min_y - 18, COMBAT_GRID_Z}; p, visible := combat_3d_project_to_ui(s, world); if visible do draw_fmt(p.x - 3, p.y - 4, TYPE_MICRO, UX.info, "%d", row + 1)}
}


combat_control_destination :: proc(
	s: ^Ux_State,
	pointer: rl.Vector2,
	fallback: game.Combat_Vec3,
) -> game.Combat_Vec3 {
	best := fallback; best_distance: f32 = 90
	for relay in s.combat.relays {
		projected, visible := combat_3d_project_to_ui(s, relay); if !visible do continue
		dx :=
			pointer.x -
			projected.x; dy := pointer.y - projected.y; distance := f32(math.sqrt(f64(dx * dx + dy * dy)))
		if distance < best_distance {best = relay; best_distance = distance}
	}
	return best
}

combat_draw_order_preview :: proc(s: ^Ux_State) {if !s.combat_order_armed || !s.combat_order_drag_active && !rl.CheckCollisionPointRec(ux_mouse, COMBAT_VIEWPORT) do return
	destination :=
		s.combat_order_drag_active ? s.combat_order_drag_world : combat_3d_point_on_plane(s, ux_mouse, s.combat_altitude)
	if s.combat_order_drag_active do destination.z = s.combat_altitude
	if s.combat_order_kind == .Control do destination = combat_control_destination(s, ux_mouse, destination)
	p, visible := combat_3d_project_to_ui(s, destination)
	if !visible do return
	plane := game.combat_depth_plane(s.combat.grid, destination.z)
	combat_draw_depth_plane_icon(plane, R(p.x + 15, p.y - 10, 20, 20), UX.info)
	draw_text(
		game.combat_location_label(s.combat.grid, destination),
		p.x + 38,
		p.y - 5,
		TYPE_FINE,
		UX.info,
	)}

combat_draw_objective :: proc(
	s: ^Ux_State,
	layout: ^Combat_Label_Layout,
	label: string,
	world: game.Combat_Vec3,
	progress: f32,
	color: rl.Color,
) {
	p, visible := combat_3d_project_to_ui(s, world); if !visible do return
	display_label := fmt.tprintf(
		"%s · %s",
		label,
		game.combat_location_label(s.combat.grid, world),
	); label_w := max(f32(len(display_label)) * 7 + 14, 54); placed := combat_place_label(layout, p, label_w, 18, int(p.x + p.y)); label_x := placed.x; label_y := placed.y
	rl.DrawRectangleRec(
		R(label_x, label_y, label_w, 18),
		rl.Color{5, 6, 6, 220},
	); rl.DrawLineEx({label_x, label_y}, {label_x + label_w, label_y}, 1, rl.Color{color.r, color.g, color.b, 145}); connection := combat_label_rule_connection(placed, p); pin_edge := combat_leader_pin_point(p, connection, 16); rl.DrawLineEx(pin_edge, connection, 1, rl.Color{color.r, color.g, color.b, 90}); draw_text(display_label, label_x + 6, label_y + 4, TYPE_FINE, color)
	if progress >
	   0 {rl.DrawRectangleRec(R(label_x, label_y + 15, label_w, 3), UX.unavailable); rl.DrawRectangleRec(R(label_x, label_y + 15, label_w * progress / 100, 3), color)}
}


combat_draw_unit_caption :: proc(
	layout: ^Combat_Label_Layout,
	grid: game.Combat_Engagement_Grid,
	u: ^game.Combat_Unit,
	index: int,
	p: rl.Vector2,
	color: rl.Color,
) {
	// Only selected ships receive a caption, so every visible label can retain
	// the complete, legible archival readout.
	w: f32 = 142
	h: f32 = 34
	placed := combat_place_label(layout, p, w, h, index); x := placed.x; y := placed.y
	anchor := combat_label_connection(placed, p)
	pin_edge := combat_leader_pin_point(p, anchor)
	leader := rl.Color{color.r, color.g, color.b, 92}
	rl.DrawLineEx(p, pin_edge, 1, leader)
	rl.DrawLineEx(pin_edge, anchor, 1, leader)
	rl.DrawRectangleRec(R(x, y, w, h), rl.Color{5, 6, 6, 228})
	rl.DrawLineEx({x, y}, {x + w, y}, 1, color)
	rl.DrawLineEx({x, y}, {x, y + 5}, 1, color)
	rl.DrawLineEx({x + w, y}, {x + w, y + 5}, 1, color)
	draw_text_fitted(u.name, R(x + 6, y + 4, w - 12, 12), TYPE_CAPTION, color)
	plane := game.combat_depth_plane(grid, u.position.z)
	combat_draw_depth_plane_icon(plane, R(x + 5, y + 17, 15, 15), UX.dim)
	pressure_color := u.pressure >= 65 ? UX.bad : u.pressure >= 35 ? UX.warn : UX.dim
	draw_fmt(
		x + 22,
		y + 20,
		TYPE_MICRO_TIGHT,
		pressure_color,
		"%s · %s · T%d",
		game.combat_pressure_state(u^),
		game.combat_location_label(grid, u.position),
		game.ship_tonnage_band(u.tonnage_each),
	)
}

combat_draw_unit_caption_overlay :: proc(
	s: ^Ux_State,
	layout: ^Combat_Label_Layout,
	index: int,
) {source := &s.combat.units[index]
	if source.extracted || !source.selected do return
	u := source^
	position := u.position
	if u.side ==
	   .Raider {contact, known := game.combat_contact_position(&s.combat, .Friendly, index)
		if !known do return
		position = contact
		trace := game.combat_contact_trace(&s.combat, .Friendly, index)
		u.position = position
		u.name = game.combat_contact_display_name(trace^)
		if trace.identity == .Identified do u.name = fmt.tprintf("%s · %v", u.name, u.operational_role)
		if trace.assessment != .Confirmed_Disabled do u.disabled = false
		p, _ := combat_3d_project_to_ui(s, position)
		screen_radius := clamp(trace.error_radius * .16, 7, 42)
		combat_draw_ring(p, screen_radius, rl.Color{UX.bad.r, UX.bad.g, UX.bad.b, 90})}
	color := u.side == .Friendly ? UX.info : UX.bad
	if u.disabled do color = UX.unavailable
	p, visible := combat_3d_project_to_ui(s, position)
	if visible do combat_draw_unit_caption(layout, s.combat.grid, &u, index, p, color)}


@(test)
combat_label_placement_is_bounded_stable_and_avoids_prior_labels :: proc(t: ^testing.T) {
	layout: Combat_Label_Layout
	combat_label_add_zone(&layout, {420, 280}, 38, 6)
	first := combat_place_label(&layout, {420, 280}, 142, 34, 3)
	second := combat_place_label(&layout, {420, 280}, 142, 34, 3)
	testing.expect(t, first.x >= COMBAT_VIEWPORT.x + 5)
	testing.expect(t, first.y >= COMBAT_VIEWPORT.y + 27)
	testing.expect(t, first.x + first.width <= COMBAT_VIEWPORT.x + COMBAT_VIEWPORT.width - 5)
	testing.expect(t, first.y + first.height <= COMBAT_VIEWPORT.y + COMBAT_VIEWPORT.height - 5)
	testing.expect(t, combat_rect_overlap_area(first, second, 12) == 0)
	replay: Combat_Label_Layout
	combat_label_add_zone(&replay, {420, 280}, 38, 6)
	testing.expect_value(t, combat_place_label(&replay, {420, 280}, 142, 34, 3), first)
}

@(test)
combat_label_leaders_join_nearest_edges :: proc(t: ^testing.T) {
	rect := rl.Rectangle{300, 200, 100, 40}
	right := combat_label_connection(rect, {500, 220})
	testing.expect_value(t, right.x, f32(400))
	testing.expect(t, right.y >= rect.y && right.y <= rect.y + rect.height)
	pin := combat_leader_pin_point({500, 220}, right, 10)
	testing.expect(t, pin.x < 500 && pin.x > right.x)
}

@(test)
combat_objective_leaders_join_visible_rule_endpoints :: proc(t: ^testing.T) {
	rect := rl.Rectangle{300, 200, 100, 18}
	left := combat_label_rule_connection(rect, {220, 260})
	right := combat_label_rule_connection(rect, {500, 260})
	testing.expect_value(t, left, rl.Vector2{rect.x, rect.y})
	testing.expect_value(t, right, rl.Vector2{rect.x + rect.width, rect.y})
}

@(test)
combat_dense_label_layout_remains_within_capacity :: proc(t: ^testing.T) {
	layout: Combat_Label_Layout
	for i in 0 ..< 96 {
		anchor := rl.Vector2{420 + f32(i % 8) * 9, 260 + f32(i / 8) * 7}
		placed := combat_place_label(&layout, anchor, 92, 18, i)
		testing.expect(t, placed.x >= COMBAT_VIEWPORT.x + 5)
		testing.expect(t, placed.y >= COMBAT_VIEWPORT.y + 27)
	}
	testing.expect_value(t, layout.label_count, 96)
}
