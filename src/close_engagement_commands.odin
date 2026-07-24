package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:testing"

combat_set_chatter :: proc(s: ^Ux_State, source, text: string) {s.combat_chatter_source = source
	s.combat_chatter_text = text
	s.combat_chatter_timer = 3.5}
combat_replace_mission :: proc(
	s: ^Ux_State,
	next: game.Combat_Mission,
) {game.combat_mission_destroy(&s.combat); s.combat = next
	if s.combat_campaign_active {s.combat_fire_control_preference = s.combat.fire_control} else {s.combat.fire_control = s.combat_fire_control_preference}
	delete(s.combat_last_actions)
	s.combat_last_actions = make([dynamic]game.Combat_Action, s.combat.friendly_count)}
combat_issue_selected :: proc(
	s: ^Ux_State,
	order: game.Combat_Order,
	destination: game.Combat_Vec3,
	target := -1,
) {
	// Once an operation is committed, autonomy owns all routine maneuver.
	// Withdrawal uses the dedicated irreversible operation interface below.
	if s.combat.operation.committed_plan.committed do return
	count := 0; first := -1; for u, i in s.combat.units[:s.combat.friendly_count] do if u.selected {count += 1; if first < 0 do first = i}
	slot := 0
	for &u, i in s.combat.units[:s.combat.friendly_count] do if u.selected {placed := destination; if target < 0 && count > 1 {placed.x += f32(slot - (count - 1) / 2) * 32; placed.z += f32((slot % 2) * 2 - 1) * 10}; game.combat_issue_order(&s.combat, i, order, placed, target); slot += 1}
	if first >= 0 {line := "Order received."; switch order {
		case .Move:
			line = "Course plotted."
		case .Guard:
			line = "Screen established."
		case .Control:
			line = "Control volume marked."
		case .Intercept:
			line = "Interception solution set."
		case .Recover:
			line = "Recovery approach begun."
		case .Withdraw:
			line = "Disengaging."
		case .Extract:
			line = "Extraction course set."
		case .Attack:
			line = "Beginning attack run."
		case .Hold:
			line = "Holding position."
		}; combat_set_chatter(s, s.combat.units[first].name, line)}}

Combat_Context_Interaction :: struct {
	kind:                      game.Combat_Interaction_Kind,
	destination:               game.Combat_Vec3,
	target:                    int,
	label, title, explanation: string,
	enabled:                   bool,
}

combat_context_interaction :: proc(s: ^Ux_State) -> Combat_Context_Interaction {
	selected := -1
	for unit, index in s.combat.units[:s.combat.friendly_count] do if unit.selected {selected = index; break}
	if selected < 0 do return {label = "ACT", title = "NO ACTION TARGET", explanation = "Select a task group before assigning a mission action."}

	// Disabled formations are actionable only when the recovery group is part of
	// the selection. Other groups retain their current work instead of being
	// silently redirected by an unrelated casualty.
	if combat_group_selected(s, 2) {
		for unit, index in s.combat.units[:s.combat.friendly_count] do if unit.disabled {
			return {kind = .Rescue, destination = unit.position, target = index, label = "RESCUE", title = "RESCUE DISABLED ELEMENT", explanation = "Restore the disabled formation and escort it toward extraction.", enabled = true}
		}
	}
	best := -1
	best_distance: f32 = 1e30
	for interaction, index in s.combat.interactions[:s.combat.interaction_count] {
		if !game.combat_interaction_available(&s.combat, index) do continue
		dx := interaction.position.x - s.combat.units[selected].position.x
		dy := interaction.position.y - s.combat.units[selected].position.y
		dz := interaction.position.z - s.combat.units[selected].position.z
		distance := dx * dx + dy * dy + dz * dz
		if distance < best_distance {best = index; best_distance = distance}
	}
	if best >= 0 {
		interaction := &s.combat.interactions[best]
		return {
			kind = interaction.kind,
			destination = interaction.position,
			target = interaction.target,
			label = interaction.verb,
			title = interaction.title,
			explanation = interaction.consequence,
			enabled = true,
		}
	}
	return {
		label = "ACT",
		title = "NO ACTIVE OBJECTIVE",
		explanation = "No mission interaction is currently available for the selected formation.",
	}
}

combat_issue_selected_interaction :: proc(s: ^Ux_State, interaction: Combat_Context_Interaction) {
	if s.combat.operation.committed_plan.committed do return
	if !interaction.enabled do return
	first := -1
	for unit, index in s.combat.units[:s.combat.friendly_count] do if unit.selected {
		if first < 0 do first = index
		game.combat_issue_interaction(&s.combat, index, interaction.kind, interaction.destination, interaction.target)
	}
	if first >= 0 do combat_set_chatter(s, s.combat.units[first].name, fmt.tprintf("%s action committed.", interaction.label))
}

combat_update_chatter :: proc(s: ^Ux_State) {if s.combat_chatter_timer > 0 do s.combat_chatter_timer = max(0, s.combat_chatter_timer - .016)
	if s.combat_chatter_timer > 0 do return
	for i := 0; i < s.combat.friendly_count; i += 1 {u := &s.combat.units[i]
		if u.action == s.combat_last_actions[i] do continue
		s.combat_last_actions[i] = u.action
		line := ""
		#partial switch
		u.action {
		case .Attack_Run:
			line = "Bombers beginning their run."
		case .Disengaging:
			line = "Disengaging under doctrine limits."
		case .Capturing:
			line = "Relay scan underway."
		case .Repairing:
			line = "Recovery cradles deployed."
		case .Extracting:
			line = "Proceeding to extraction."
		}
		if line != "" {combat_set_chatter(s, u.name, line); break}}}


combat_unit_at_pointer :: proc(s: ^Ux_State) -> int {closest := -1; best_t: f32 = 100000
	origin, direction := combat_3d_pointer_ray(s, ux_mouse)
	fov := f32(math.PI / 3.27) / clamp(s.combat_zoom, COMBAT_ZOOM_MIN, COMBAT_ZOOM_MAX)
	for u, i in s.combat.units[:s.combat.unit_count] {if u.extracted do continue; position := u.position; if u.side == .Raider {contact, known := game.combat_contact_position(&s.combat, .Friendly, i); if !known do continue; position = contact}; offset := game.Combat_Vec3{position.x - origin.x, position.y - origin.y, position.z - origin.z}; approx_t := offset.x * direction.x + offset.y * direction.y + offset.z * direction.z; if approx_t < 0 || approx_t >= best_t do continue; screen_floor := approx_t * 2 * f32(math.tan(f64(fov * .5))) / COMBAT_VIEWPORT.height * 8; radius := max(max(f32(20), game.ship_tonnage_visual_scale(u.tonnage_each) * 1.4), screen_floor); if hit_t, hit := combat_3d_ray_sphere_distance(origin, direction, position, radius); hit && hit_t < best_t {best_t = hit_t; closest = i}}
	return closest
}

combat_battlefield_input :: proc(s: ^Ux_State) {if !rl.CheckCollisionPointRec(ux_mouse, COMBAT_VIEWPORT) do return
	// UI buttons consume their own clicks outside the tactical viewport.
	if rl.IsMouseButtonPressed(.RIGHT) {s.combat_orbit_drag_active = true
		s.combat_orbit_drag_moved = false
		s.combat_orbit_drag_start = ux_mouse
		return}
	if !rl.IsMouseButtonPressed(.LEFT) do return
	if s.combat_ability_armed {source := clamp(s.combat_selected, 0, s.combat.friendly_count - 1)
		target := combat_3d_point_on_plane(s, ux_mouse, s.combat_altitude)
		activated := false
		if s.combat.operation.committed_plan.committed {
			activated = game.combat_request_ship_ability(&s.combat, source, target)
		} else {
			activated = game.combat_activate_ship_ability(&s.combat, source, target)
		}
		if activated {combat_set_chatter(s, s.combat.units[source].name, s.combat.operation.committed_plan.committed ? "Ability authorization requested." : "Ability committed.")
			s.combat_ability_armed = false}
		return}
	closest := combat_unit_at_pointer(s)
	if closest >= 0 {if closest < s.combat.friendly_count {add :=
				rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
			combat_select_unit(s, closest, add)}
		else {contact, _ := game.combat_contact_position(&s.combat, .Friendly, closest)
			combat_issue_selected(s, .Attack, contact, closest)}
		return}
	if s.combat_order_armed {s.combat_order_drag_active = true; s.combat_order_drag_start =
			ux_mouse
		s.combat_order_drag_altitude = s.combat_altitude
		s.combat_order_drag_world = combat_3d_point_on_plane(s, ux_mouse, s.combat_altitude)
		return}
	s.combat_drag_start = ux_mouse
	s.combat_drag_active = true
}


combat_use_selected_ability :: proc(s: ^Ux_State, source: int) {
	if !s.combat.units[source].selected || !game.combat_ship_ability_ready(&s.combat, source) do return
	ability := game.combat_ship_ability(s.combat.units[source])
	if game.combat_ship_ability_requires_target(ability) {
		s.combat_ability_armed = !s.combat_ability_armed
	} else {
		activated := false
		if s.combat.operation.committed_plan.committed {
			activated = game.combat_request_ship_ability(&s.combat, source)
		} else {
			activated = game.combat_activate_ship_ability(&s.combat, source)
		}
		if activated do combat_set_chatter(
			s,
			s.combat.units[source].name,
			s.combat.operation.committed_plan.committed ? "Ability authorization requested." : "Ability executed.",
		)
	}
}


combat_controls :: proc(s: ^Ux_State) {
	if rl.IsKeyPressed(.SPACE) do combat_toggle_pause(s)
	if rl.IsKeyPressed(.I) {
		game.combat_advance_to_next_decision(&s.combat)
		s.combat_paused = true
	}
	has_selection := false
	for unit in s.combat.units[:s.combat.friendly_count] do if unit.selected {has_selection = true; break}
	ability_source := clamp(
		s.combat_selected,
		0,
		s.combat.friendly_count - 1,
	); if !s.combat.units[ability_source].selected do s.combat_ability_armed = false
	if s.combat_zoom <= 0 do s.combat_zoom = 1
	q :=
		s.combat_orientation; if q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w < .1 do s.combat_orientation = combat_default_orientation()
	pan_speed :=
		4.0 /
		s.combat_zoom; if rl.IsKeyDown(.A) do s.combat_pan_x += pan_speed; if rl.IsKeyDown(.D) do s.combat_pan_x -= pan_speed; if rl.IsKeyDown(.W) do s.combat_pan_y += pan_speed; if rl.IsKeyDown(.S) do s.combat_pan_y -= pan_speed
	if rl.IsKeyDown(.LEFT) do combat_orbit(s, -COMBAT_KEY_ORBIT_SPEED, 0)
	if rl.IsKeyDown(.RIGHT) do combat_orbit(s, COMBAT_KEY_ORBIT_SPEED, 0)
	if rl.IsKeyDown(.UP) do combat_orbit(s, 0, -COMBAT_KEY_ORBIT_SPEED)
	if rl.IsKeyDown(.DOWN) do combat_orbit(s, 0, COMBAT_KEY_ORBIT_SPEED)
	viewport := COMBAT_VIEWPORT; over_view := rl.CheckCollisionPointRec(ux_mouse, viewport)
	wheel := rl.GetMouseWheelMove(
		
	); pinch := rl.GetMousePinchScale(); zoom_factor := f32(1); if wheel != 0 do zoom_factor *= f32(math.exp(f64(wheel) * .14)); if pinch > 0 && math.abs(pinch - 1) > .001 do zoom_factor *= pinch; if zoom_factor != 1 && over_view {anchor, anchor_ok := combat_3d_unproject_to_plane(s, ux_mouse, s.combat_altitude); s.combat_zoom = clamp(s.combat_zoom * zoom_factor, COMBAT_ZOOM_MIN, COMBAT_ZOOM_MAX); if anchor_ok && combat_zoom_anchor_safe(s, anchor) {after, after_ok := combat_3d_unproject_to_plane(s, ux_mouse, s.combat_altitude); if after_ok && combat_zoom_anchor_safe(s, after) {delta := game.Combat_Vec3{anchor.x - after.x, anchor.y - after.y, anchor.z - after.z}; view_delta := combat_quat_rotate(s.combat_orientation, delta); s.combat_pan_x += view_delta.x * COMBAT_VIEW_SCALE; s.combat_pan_y += view_delta.y * COMBAT_VIEW_SCALE}}}
	if s.combat_orbit_drag_active {if rl.IsMouseButtonDown(.RIGHT) {distance := math.abs(ux_mouse.x - s.combat_orbit_drag_start.x) + math.abs(ux_mouse.y - s.combat_orbit_drag_start.y); if distance > 4 do s.combat_orbit_drag_moved = true; if s.combat_orbit_drag_moved {delta := rl.GetMouseDelta(); combat_orbit(s, delta.x * .006, delta.y * .006)}} else {if !s.combat_orbit_drag_moved && over_view && !s.combat.operation.committed_plan.committed {closest := combat_unit_at_pointer(s); if closest >= s.combat.friendly_count {contact, _ := game.combat_contact_position(&s.combat, .Friendly, closest); combat_issue_selected(s, .Attack, contact, closest)} else {combat_issue_selected(s, .Move, combat_3d_point_on_plane(s, ux_mouse, s.combat_altitude))}; s.combat_order_drag_active = false; s.combat_order_armed = false}; s.combat_orbit_drag_active = false}}
	if rl.IsMouseButtonPressed(.MIDDLE) && over_view do s.combat_pan_active = true
	if s.combat_pan_active {if rl.IsMouseButtonDown(.MIDDLE) {delta := rl.GetMouseDelta(); s.combat_pan_x += delta.x / (ux_zoom * s.combat_zoom); s.combat_pan_y += delta.y / (ux_zoom * s.combat_zoom)} else {s.combat_pan_active = false}}
	if s.combat_order_drag_active {s.combat_altitude = clamp(s.combat_order_drag_altitude + (s.combat_order_drag_start.y - ux_mouse.y) * 1.2, -120, 120); if !rl.IsMouseButtonDown(.LEFT) {destination := s.combat_order_drag_world; destination.z = s.combat_altitude; if s.combat_order_kind == .Control do destination = combat_control_destination(s, ux_mouse, destination); combat_issue_selected(s, s.combat_order_kind, destination); s.combat_order_drag_active = false; s.combat_order_armed = false}}
	group := -1; if rl.IsKeyPressed(.ONE) do group = 0; if rl.IsKeyPressed(.TWO) do group = 1; if rl.IsKeyPressed(.THREE) do group = 2
	locked_plan := s.combat.operation.committed_plan.committed
	if has_selection && rl.IsKeyPressed(.Q) do combat_use_selected_ability(s, ability_source)
	if has_selection && rl.IsKeyPressed(.R) {
		if locked_plan {
			_ = game.combat_request_emergency_defense(&s.combat, ability_source)
		} else {
			_ = game.combat_emergency_defense(&s.combat, ability_source)
		}
	}
	if has_selection && !locked_plan && rl.IsKeyPressed(.G) {
		for &unit, index in s.combat.units[:s.combat.friendly_count] do if unit.selected {
			next := game.Combat_Sensor_Mode((int(unit.sensor_mode) + 1) % 6)
			game.combat_set_sensor_mode(&s.combat, index, next)
		}
	}
	if has_selection && !locked_plan && rl.IsKeyPressed(.E) do combat_issue_selected(s, .Hold, {})
	if has_selection && !locked_plan &&
	   rl.IsKeyPressed(.M) {s.combat_order_armed = true; s.combat_order_kind = .Move}
	if has_selection && rl.IsKeyPressed(.X) {
		if locked_plan &&
		   (rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)) {
			_ = game.combat_operation_withdraw_fleet(&s.combat)
		} else {
			for unit in s.combat.units[:s.combat.friendly_count] do if unit.selected {
				if locked_plan {
				_ = game.combat_operation_withdraw_group(&s.combat, unit.group)
				} else {
					combat_issue_selected(s, .Withdraw, s.combat.extraction)
				}
				break
			}
		}
	}
	if has_selection && !locked_plan && rl.IsKeyPressed(.C) do combat_issue_selected_interaction(s, combat_context_interaction(s))
	if group >= 0 do combat_select_group(s, group, rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT))
	if rl.IsKeyPressed(
		.F,
	) {u := s.combat.units[clamp(s.combat_selected, 0, s.combat.friendly_count - 1)]; view := combat_quat_rotate(s.combat_orientation, u.position); s.combat_pan_x = -view.x * COMBAT_VIEW_SCALE; s.combat_pan_y = -view.y * COMBAT_VIEW_SCALE}
	combat_clamp_pan(s)
	if s.combat_drag_active &&
	   !rl.IsMouseButtonDown(
			   .LEFT,
		   ) {s.combat_drag_active = false; x0 := min(s.combat_drag_start.x, ux_mouse.x); x1 := max(s.combat_drag_start.x, ux_mouse.x); y0 := min(s.combat_drag_start.y, ux_mouse.y); y1 := max(s.combat_drag_start.y, ux_mouse.y); add := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT); if x1 - x0 > 6 || y1 - y0 > 6 {if !add do for &u in s.combat.units[:s.combat.friendly_count] do u.selected = false; for &u, i in s.combat.units[:s.combat.friendly_count] {p, visible := combat_3d_project_to_ui(s, u.position); if visible && p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1 {u.selected = true; s.combat_selected = i}}} else if !add {for &u in s.combat.units[:s.combat.friendly_count] do u.selected = false}}
}


@(test)
combat_context_action_requires_a_selection :: proc(t: ^testing.T) {
	s := ux_state_create()
	defer ux_state_destroy(s)
	interaction := combat_context_interaction(s)
	testing.expect(t, !interaction.enabled)
	testing.expect_value(t, interaction.label, "ACT")
}

@(test)
combat_context_action_prioritizes_rescue_for_the_recovery_group :: proc(t: ^testing.T) {
	s := ux_state_create()
	defer ux_state_destroy(s)
	s.combat.units = make([dynamic]game.Combat_Unit, 2)
	defer delete(s.combat.units)
	s.combat.friendly_count = 2
	s.combat.unit_count = 2
	s.combat.units[0] = {
		name     = "Recovery",
		group    = 2,
		selected = true,
	}
	s.combat.units[1] = {
		name     = "Disabled",
		disabled = true,
		position = {30, 40, 5},
	}
	interaction := combat_context_interaction(s)
	testing.expect(t, interaction.enabled)
	testing.expect_value(t, interaction.kind, game.Combat_Interaction_Kind.Rescue)
	testing.expect_value(t, interaction.target, 1)
	testing.expect_value(t, interaction.destination, s.combat.units[1].position)
}

@(test)
combat_context_action_chooses_the_nearest_available_objective :: proc(t: ^testing.T) {
	s := ux_state_create()
	defer ux_state_destroy(s)
	s.combat.units = make([dynamic]game.Combat_Unit, 1)
	defer delete(s.combat.units)
	s.combat.friendly_count = 1
	s.combat.unit_count = 1
	s.combat.units[0] = {
		selected = true,
		position = {0, 0, 0},
	}
	s.combat.interaction_count = 2
	s.combat.interactions[0] = {
		kind     = .Deploy,
		position = {100, 0, 0},
		verb     = "FAR",
		active   = true,
	}
	s.combat.interactions[1] = {
		kind     = .Deploy,
		position = {10, 0, 0},
		verb     = "NEAR",
		active   = true,
	}
	interaction := combat_context_interaction(s)
	testing.expect(t, interaction.enabled)
	testing.expect_value(t, interaction.label, "NEAR")
	testing.expect_value(t, interaction.destination, game.Combat_Vec3{10, 0, 0})
}

@(test)
combat_multi_selection_orders_keep_deterministic_formation_offsets :: proc(t: ^testing.T) {
	s := ux_state_create()
	defer ux_state_destroy(s)
	s.combat.units = make([dynamic]game.Combat_Unit, 2)
	defer delete(s.combat.units)
	s.combat.friendly_count = 2
	s.combat.unit_count = 2
	s.combat.units[0] = {
		name     = "First",
		selected = true,
	}
	s.combat.units[1] = {
		name     = "Second",
		selected = true,
	}
	combat_issue_selected(s, .Move, {100, 200, 30})
	testing.expect_value(t, s.combat.units[0].destination, game.Combat_Vec3{100, 200, 20})
	testing.expect_value(t, s.combat.units[1].destination, game.Combat_Vec3{132, 200, 40})
	testing.expect_value(t, s.combat_chatter_source, "First")
	testing.expect_value(t, s.combat_chatter_text, "Course plotted.")
}

@(test)
combat_chatter_reports_new_unit_actions_once :: proc(t: ^testing.T) {
	s := ux_state_create()
	defer ux_state_destroy(s)
	s.combat.units = make([dynamic]game.Combat_Unit, 1)
	defer delete(s.combat.units)
	s.combat.friendly_count = 1
	s.combat.unit_count = 1
	s.combat.units[0] = {
		name   = "Wing",
		action = .Attack_Run,
	}
	delete(s.combat_last_actions)
	s.combat_last_actions = make([dynamic]game.Combat_Action, 1)
	defer delete(s.combat_last_actions)
	s.combat_chatter_timer = 0
	combat_update_chatter(s)
	testing.expect_value(t, s.combat_chatter_source, "Wing")
	testing.expect_value(t, s.combat_chatter_text, "Bombers beginning their run.")
	previous_timer := s.combat_chatter_timer
	combat_update_chatter(s)
	testing.expect(t, s.combat_chatter_timer < previous_timer)
}
