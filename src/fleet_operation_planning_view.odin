package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:math"

OPERATION_TABS :: [6]string {
	"INTELLIGENCE",
	"FLEET",
	"ORDERS",
	"DOCTRINE",
	"CONTINGENCIES",
	"REVIEW",
}

operation_planning_preview :: proc(s: ^Ux_State) {
	preview :=
		game.combat_new_skirmish_mission(
			s.skirmish_setup.seed,
			s.skirmish_setup,
		)
	copy := s.combat_operation
	copy.draft.validation = game.combat_operation_validate_plan(&copy, &copy.draft)
	copy.draft.committed = true
	copy.draft.immutable = true
	copy.committed_plan = copy.draft
	_ = game.combat_operation_compile_mission(&preview, &copy)
	combat_replace_mission(s, preview)
	s.combat_paused = true
	s.combat_briefing = false
	if s.combat_zoom <= 0 do s.combat_zoom = 1
	q := s.combat_orientation
	if q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w < .1 {
		s.combat_orientation = combat_default_orientation()
	}
	s.combat_last_time = rl.GetTime()
}

operation_planning_prepare_skirmish :: proc(s: ^Ux_State) {
	if s.skirmish_setup.seed == 0 do s.skirmish_setup.seed = u64(rl.GetTime() * 1000000) + 1
	if s.skirmish_setup.contract_seed == 0 do s.skirmish_setup.contract_seed = s.skirmish_setup.seed
	s.combat_operation = game.combat_operation_generate_skirmish(s.skirmish_setup)
	s.combat_planning_tab = 0
	s.combat_planning_group = 0
	s.combat_planning_drag_waypoint = -1
	resize(&s.combat_planning_undo, 0)
	resize(&s.combat_planning_redo, 0)
	operation_planning_preview(s)
	s.screen = .Operation_Planning
}

operation_planning_prepare_campaign :: proc(s: ^Ux_State) {
	seed := s.campaign.combat_deployment_seed
	setup := game.skirmish_default_setup()
	setup.seed = seed
	setup.contract_seed =
		game.combat_mix(seed ~ u64(s.campaign.compact.active.id + 1) * 0x6a09e667f3bcc909)
	setup.mission = game.combat_campaign_mission_kind(s.campaign, seed)
	s.skirmish_setup = setup
	s.combat_operation = game.combat_operation_generate_skirmish(setup)
	s.combat_operation.operation_context = .Campaign
	s.combat_operation.origin_event = s.campaign.event_sequence
	s.combat_operation.draft.assignment_count = 0
	for manifest_index in 0 ..< s.campaign.combat_deployment_count {
		group := clamp(
			s.campaign.combat_deployment_groups[manifest_index],
			0,
			game.COMBAT_GROUP_COUNT - 1,
		)
		s.combat_operation.draft.groups[group].active = true
		s.combat_operation.draft.groups[group].id = u32(group + 1)
		s.combat_operation.draft.groups[group].name = game.combat_plan_default_group_name(group)
		s.combat_operation.draft.assignments[s.combat_operation.draft.assignment_count] = {
			ship = s.campaign.combat_deployment_ships[manifest_index],
			unit_index = group,
			group = group,
			archetype =
				s.campaign.ships[
					game.ship_index(s.campaign, s.campaign.combat_deployment_ships[manifest_index])
				].hull_archetype,
		}
		s.combat_operation.draft.assignment_count += 1
	}
	s.campaign.combat_operation = s.combat_operation
	s.combat_campaign_active = true
	s.combat_planning_tab = 0
	s.combat_planning_group = 0
	resize(&s.combat_planning_undo, 0)
	resize(&s.combat_planning_redo, 0)
	operation_planning_preview(s)
	s.screen = .Operation_Planning
	_ = ux_save(s, true)
}

operation_planning_prepare_linked :: proc(s: ^Ux_State) {
	s.combat_operation = s.campaign.combat_operation
	_ = game.combat_operation_add_reachable_reinforcements(
		&s.combat_operation,
		s.campaign,
	)
	s.campaign.combat_operation = s.combat_operation
	s.combat_campaign_active = true
	s.combat_planning_tab = 0
	s.combat_planning_group = 0
	resize(&s.combat_planning_undo, 0)
	resize(&s.combat_planning_redo, 0)
	operation_planning_preview(s)
	s.screen = .Operation_Planning
	_ = ux_save(s, true)
}

operation_planning_capture_undo :: proc(s: ^Ux_State) {
	if len(s.combat_planning_undo) >= 32 do ordered_remove(&s.combat_planning_undo, 0)
	append(&s.combat_planning_undo, s.combat_operation.draft)
	resize(&s.combat_planning_redo, 0)
}

operation_planning_undo :: proc(s: ^Ux_State) {
	if len(s.combat_planning_undo) == 0 do return
	append(&s.combat_planning_redo, s.combat_operation.draft)
	last := len(s.combat_planning_undo) - 1
	s.combat_operation.draft = s.combat_planning_undo[last]
	resize(&s.combat_planning_undo, last)
	operation_planning_mutated(s)
}

operation_planning_redo :: proc(s: ^Ux_State) {
	if len(s.combat_planning_redo) == 0 do return
	append(&s.combat_planning_undo, s.combat_operation.draft)
	last := len(s.combat_planning_redo) - 1
	s.combat_operation.draft = s.combat_planning_redo[last]
	resize(&s.combat_planning_redo, last)
	operation_planning_mutated(s)
}

operation_planning_mutated :: proc(s: ^Ux_State) {
	s.combat_operation.draft.revision += 1
	s.combat_operation.draft.validation =
		game.combat_operation_validate_plan(&s.combat_operation, &s.combat_operation.draft)
	if s.combat_operation.operation_context == .Campaign ||
	   s.combat_operation.operation_context == .Linked {
		s.campaign.combat_operation = s.combat_operation
		_ = ux_save(s, true)
	}
	operation_planning_preview(s)
}

operation_planning_launch :: proc(s: ^Ux_State) {
	if !game.combat_operation_commit(&s.combat_operation) do return
	if s.combat_operation.operation_context == .Campaign ||
	   s.combat_operation.operation_context == .Linked {
		s.campaign.combat_operation = s.combat_operation
		if s.combat_operation.operation_context == .Linked &&
		   !game.combat_operation_prepare_linked_campaign(
			   &s.combat_operation,
			   s.campaign,
		   ) {
			return
		}
		next := game.combat_new_campaign_mission(s.campaign)
		if !game.combat_operation_compile_mission(&next, &s.combat_operation) {
			game.combat_mission_destroy(&next)
			return
		}
		game.combat_operation_apply_continuity(&next)
		combat_replace_mission(s, next)
		_ = ux_save(s, true)
	} else {
		next := game.combat_new_skirmish_mission(
			s.skirmish_setup.seed,
			s.skirmish_setup,
		)
		if !game.combat_operation_compile_mission(&next, &s.combat_operation) {
			game.combat_mission_destroy(&next)
			return
		}
		combat_replace_mission(s, next)
		s.combat_campaign_active = false
	}
	s.combat_briefing = false
	s.combat_paused = false
	s.combat_speed = 1
	s.combat_last_time = rl.GetTime()
	s.screen = .Combat
}

operation_planning_draw_route :: proc(
	s: ^Ux_State,
	route: game.Combat_Plan_Route,
	color: rl.Color,
	dashed := false,
) {
	if route.count <= 0 do return
	for index in 0 ..< route.count {
		point, visible := combat_3d_project_to_ui(s, route.waypoints[index])
		if !visible do continue
		combat_draw_ring(point, index == 0 || index == route.count - 1 ? 8 : 5, color)
		draw_fmt(point.x + 8, point.y - 8, TYPE_MICRO, color, "%d", index + 1)
		if index > 0 {
			prior, prior_visible := combat_3d_project_to_ui(s, route.waypoints[index - 1])
			if prior_visible {
				if dashed {
					mid := rl.Vector2{(prior.x + point.x) * .5, (prior.y + point.y) * .5}
					rl.DrawLineEx(prior, mid, 1, color)
				} else {
					rl.DrawLineEx(prior, point, 2, color)
				}
			}
		}
	}
}

operation_planning_draw_map :: proc(s: ^Ux_State) {
	rl.BeginScissorMode(COMBAT_VIEWPORT)
	for feature in s.combat_operation.battlespace.features[:s.combat_operation.battlespace.feature_count] {
		p, visible := combat_3d_project_to_ui(s, feature.volume.center)
		if !visible do continue
		color := feature.impassable ? UX.bad : feature.kind == .Open_Lane ? UX.info : UX.dim
		combat_draw_ring(p, clamp(feature.volume.radius * .08, f32(10), f32(34)), color)
		draw_text(fmt.tprintf("%v", feature.kind), p.x + 10, p.y + 8, TYPE_MICRO, color)
	}
	for contact in s.combat_operation.intelligence.contacts[:s.combat_operation.intelligence.contact_count] {
		p, visible := combat_3d_project_to_ui(s, contact.estimate)
		if !visible do continue
		combat_draw_ring(p, clamp(contact.uncertainty_radius * .09, f32(12), f32(32)), UX.warn)
		draw_fmt(p.x + 12, p.y - 8, TYPE_MICRO, UX.warn, "CONTACT %.0f%%", contact.confidence * 100)
	}
	for group, index in s.combat_operation.draft.groups {
		if !group.active do continue
		color := index == s.combat_planning_group ? UX.committed : UX.info
		operation_planning_draw_route(s, group.primary_route, color)
		operation_planning_draw_route(s, group.withdrawal_route, UX.good, true)
		center, visible := combat_3d_project_to_ui(s, group.boundary.center)
		if visible {
			combat_draw_ring(center, clamp(group.boundary.radius * .08, f32(14), f32(40)), color)
		}
	}
	rl.EndScissorMode()
}

operation_planning_camera_input :: proc(s: ^Ux_State) {
	if rl.IsKeyDown(.LEFT) do combat_orbit(s, -.025, 0)
	if rl.IsKeyDown(.RIGHT) do combat_orbit(s, .025, 0)
	if rl.IsKeyDown(.UP) do combat_orbit(s, 0, -.02)
	if rl.IsKeyDown(.DOWN) do combat_orbit(s, 0, .02)
	wheel := rl.GetMouseWheelMove()
	if wheel != 0 do s.combat_zoom = clamp(s.combat_zoom * f32(math.exp(f64(wheel) * .14)), COMBAT_ZOOM_MIN, COMBAT_ZOOM_MAX)
	if s.combat_planning_tab != 2 ||
	   !rl.CheckCollisionPointRec(ux_mouse, COMBAT_VIEWPORT) {
		return
	}
	group := &s.combat_operation.draft.groups[clamp(s.combat_planning_group, 0, game.COMBAT_GROUP_COUNT - 1)]
	route :=
		s.combat_planning_route_kind == 0 ? &group.primary_route : &group.withdrawal_route
	if rl.IsMouseButtonPressed(.LEFT) {
		for index in 0 ..< route.count {
			p, visible := combat_3d_project_to_ui(s, route.waypoints[index])
			dx, dy := ux_mouse.x - p.x, ux_mouse.y - p.y
			if visible && dx * dx + dy * dy <= 12 * 12 {
				operation_planning_capture_undo(s)
				s.combat_planning_drag_waypoint = index
				return
			}
		}
		if route.count < len(route.waypoints) {
			operation_planning_capture_undo(s)
			placed := combat_3d_point_on_plane(s, ux_mouse, s.combat_altitude)
			best_distance: f32 = 65
			for objective in s.combat_operation.battlespace.objective_positions[:s.combat_operation.battlespace.objective_count] {
				distance := game.combat_distance(placed, objective)
				if distance < best_distance {
					placed = objective
					best_distance = distance
				}
			}
			for contact in s.combat_operation.intelligence.contacts[:s.combat_operation.intelligence.contact_count] {
				distance := game.combat_distance(placed, contact.estimate)
				if distance < best_distance {
					placed = contact.estimate
					best_distance = distance
				}
			}
			for &other_group in s.combat_operation.draft.groups do if other_group.active {
				for waypoint in other_group.primary_route.waypoints[:other_group.primary_route.count] {
					distance := game.combat_distance(placed, waypoint)
					if distance < best_distance {
						placed = waypoint
						best_distance = distance
					}
				}
			}
			if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) {
				group.boundary.center = placed
				operation_planning_mutated(s)
				return
			}
			route.waypoints[route.count] = placed
			route.count += 1
			operation_planning_mutated(s)
		}
	}
	if s.combat_planning_drag_waypoint >= 0 {
		if rl.IsMouseButtonDown(.LEFT) {
			route.waypoints[s.combat_planning_drag_waypoint] =
				combat_3d_point_on_plane(s, ux_mouse, s.combat_altitude)
		} else {
			s.combat_planning_drag_waypoint = -1
			operation_planning_mutated(s)
		}
	}
}

operation_planning_draw_groups :: proc(s: ^Ux_State) {
	panel(R(12, 112, 181, 500), true)
	label_caps("TASK GROUPS", 24, 126, UX.info)
	for group, index in s.combat_operation.draft.groups {
		y := 154 + f32(index) * 48
		label := group.active ? game.combat_plan_group_name(&s.combat_operation.draft.groups[index]) : fmt.tprintf("GROUP %d · INACTIVE", index + 1)
		if button(R(22, y, 161, 38), label, true, index == s.combat_planning_group) {
			s.combat_planning_group = index
		}
	}
	selected := &s.combat_operation.draft.groups[s.combat_planning_group]
	if s.combat_planning_renaming {
		keys := [26]rl.KeyboardKey{.A,.B,.C,.D,.E,.F,.G,.H,.I,.J,.K,.L,.M,.N,.O,.P,.Q,.R,.S,.T,.U,.V,.W,.X,.Y,.Z}
		for key, index in keys do if rl.IsKeyPressed(key) &&
		   selected.custom_name_length < len(selected.custom_name) {
			selected.custom_name[selected.custom_name_length] = u8('A' + index)
			selected.custom_name_length += 1
		}
		if rl.IsKeyPressed(.SPACE) &&
		   selected.custom_name_length < len(selected.custom_name) {
			selected.custom_name[selected.custom_name_length] = ' '
			selected.custom_name_length += 1
		}
		if rl.IsKeyPressed(.BACKSPACE) && selected.custom_name_length > 0 {
			selected.custom_name_length -= 1
		}
		if rl.IsKeyPressed(.ENTER) {
			s.combat_planning_renaming = false
			operation_planning_mutated(s)
		}
	}
	if button(R(22, 548, 77, 28), selected.active ? "DISSOLVE" : "CREATE") {
		operation_planning_capture_undo(s)
		selected.active = !selected.active
		if selected.active {
			selected.id = u32(s.combat_planning_group + 1)
			selected.name = game.combat_plan_default_group_name(s.combat_planning_group)
			selected.support_group = -1
			selected.doctrine = game.combat_doctrine_policy(.Balanced)
			s.combat_operation.draft.group_count += 1
		} else {
			s.combat_operation.draft.group_count = max(0, s.combat_operation.draft.group_count - 1)
		}
		operation_planning_mutated(s)
	}
	if button(R(104, 548, 79, 28), "NAME", selected.active) {
		operation_planning_capture_undo(s)
		if selected.custom_name_length == 0 {
			initial := selected.name
			selected.custom_name_length = min(len(initial), len(selected.custom_name))
			for byte, index in transmute([]u8)initial[:selected.custom_name_length] {
				selected.custom_name[index] = byte
			}
		}
		s.combat_planning_renaming = true
	}
}

operation_planning_draw_intel :: proc(s: ^Ux_State) {
	label_caps("EVIDENCE-BASED ESTIMATE", 1026, 126, UX.info)
	draw_fmt(1026, 154, TYPE_BODY_EMPHASIS, UX.text, "QUALITY %.0f%%", s.combat_operation.intelligence.quality * 100)
	draw_text_wrapped(
		"Uncertainty volumes mark the last supported estimate. The hostile plan remains unknown.",
		R(1026, 182, 226, 58),
		TYPE_SMALL,
		UX.dim,
	)
	for contact, index in s.combat_operation.intelligence.contacts[:min(s.combat_operation.intelligence.contact_count, 6)] {
		draw_fmt(
			1026,
			252 + f32(index) * 45,
			TYPE_SMALL_EMPHASIS,
			contact.identified ? UX.warn : UX.dim,
			"%s · %.0f%%",
			contact.identified ? fmt.tprintf("%v", contact.role) : "UNRESOLVED",
			contact.confidence * 100,
		)
		draw_fmt(1026, 270 + f32(index) * 45, TYPE_MICRO, UX.dim, "ERROR RADIUS %.0f", contact.uncertainty_radius)
	}
}

operation_planning_draw_fleet :: proc(s: ^Ux_State) {
	label_caps("ASSIGNMENT", 1026, 126, UX.info)
	draw_text_wrapped("Recommended combined-arms groups remain fully editable.", R(1026, 150, 226, 42), TYPE_SMALL, UX.dim)
	for &assignment, index in s.combat_operation.draft.assignments[:min(s.combat_operation.draft.assignment_count, 9)] {
		y := 204 + f32(index) * 40
		name := fmt.tprintf("ELEMENT %d", assignment.unit_index + 1)
		if assignment.ship != 0 && s.combat_operation.operation_context == .Campaign {
			at := game.ship_index(s.campaign, assignment.ship)
			if at >= 0 do name = s.campaign.ships[at].name
		}
		draw_text_fitted(name, R(1026, y, 118, 28), TYPE_SMALL, UX.text)
		if button(R(1148, y, 62, 28), fmt.tprintf("G%d", assignment.group + 1), !assignment.locked) {
			operation_planning_capture_undo(s)
			assignment.group = (assignment.group + 1) % game.COMBAT_GROUP_COUNT
			s.combat_operation.draft.groups[assignment.group].active = true
			operation_planning_mutated(s)
		}
		if button(R(1214, y, 30, 28), assignment.locked ? "L" : "○") {
			operation_planning_capture_undo(s)
			assignment.locked = !assignment.locked
			operation_planning_mutated(s)
		}
	}
}

operation_planning_draw_orders :: proc(s: ^Ux_State) {
	group := &s.combat_operation.draft.groups[s.combat_planning_group]
	label_caps("SPATIAL ORDERS", 1026, 126, UX.info)
	draw_fmt(1026, 152, TYPE_BODY_EMPHASIS, UX.text, "%s · %v", game.combat_plan_group_name(group), group.order)
	if button(R(1026, 184, 104, 28), "PRIMARY", true, s.combat_planning_route_kind == 0) do s.combat_planning_route_kind = 0
	if button(R(1138, 184, 104, 28), "WITHDRAW", true, s.combat_planning_route_kind == 1) do s.combat_planning_route_kind = 1
	route := s.combat_planning_route_kind == 0 ? &group.primary_route : &group.withdrawal_route
	draw_fmt(1026, 224, TYPE_SMALL, UX.dim, "%d / %d WAYPOINTS", route.count, len(route.waypoints))
	if button(R(1026, 254, 104, 28), "UNDO", len(s.combat_planning_undo) > 0) do operation_planning_undo(s)
	if button(R(1138, 254, 104, 28), "REDO", len(s.combat_planning_redo) > 0) do operation_planning_redo(s)
	if button(R(1026, 294, 104, 28), "ALT −") do s.combat_altitude = max(s.combat_altitude - 25, f32(-180))
	if button(R(1138, 294, 104, 28), "ALT +") do s.combat_altitude = min(s.combat_altitude + 25, f32(180))
	draw_fmt(1026, 330, TYPE_SMALL, UX.info, "EDIT ALTITUDE %.0f", s.combat_altitude)
	if button(R(1026, 358, 216, 26), fmt.tprintf("ORDER · %v", group.order)) {
		operation_planning_capture_undo(s)
		group.order = game.Combat_Order((int(group.order) + 1) % 10)
		operation_planning_mutated(s)
	}
	if button(R(1026, 388, 216, 26), fmt.tprintf("OBJECTIVE · %d", group.objective_index + 1)) {
		operation_planning_capture_undo(s)
		group.objective_index =
			(group.objective_index + 1) % max(s.combat_operation.objectives.count, 1)
		group.boundary.center =
			s.combat_operation.battlespace.objective_positions[group.objective_index]
		operation_planning_mutated(s)
	}
	if button(R(1026, 418, 216, 26), group.support_group < 0 ? "SUPPORT · NONE" : fmt.tprintf("SUPPORT · GROUP %d", group.support_group + 1)) {
		operation_planning_capture_undo(s)
		group.support_group = (group.support_group + 2) % (game.COMBAT_GROUP_COUNT + 1) - 1
		if group.support_group == s.combat_planning_group do group.support_group = (group.support_group + 1) % game.COMBAT_GROUP_COUNT
		operation_planning_mutated(s)
	}
	if button(R(1026, 460, 216, 30), "REMOVE LAST", route.count > 2) {
		operation_planning_capture_undo(s)
		route.count -= 1
		operation_planning_mutated(s)
	}
	draw_fmt(1026, 500, TYPE_SMALL, UX.text, "%v BOUNDARY · R %.0f", group.boundary.kind, group.boundary.radius)
	if button(R(1026, 526, 66, 28), "R −", group.boundary.radius > 80) {
		operation_planning_capture_undo(s)
		group.boundary.radius -= 20
		operation_planning_mutated(s)
	}
	if button(R(1098, 526, 66, 28), "R +") {
		operation_planning_capture_undo(s)
		group.boundary.radius += 20
		operation_planning_mutated(s)
	}
	if button(R(1170, 526, 72, 28), "SHAPE") {
		operation_planning_capture_undo(s)
		group.boundary.kind = group.boundary.kind == .Sphere ? .Cylinder : .Sphere
		operation_planning_mutated(s)
	}
}

operation_planning_draw_doctrine :: proc(s: ^Ux_State) {
	group := &s.combat_operation.draft.groups[s.combat_planning_group]
	label_caps("INDEPENDENT POLICIES", 1026, 126, UX.info)
	presets := [4]game.Combat_Doctrine{.Cautious_Screen, .Balanced, .Hunter_Killer, .Last_Stand}
	for preset, index in presets {
		if radio_button(
			R(1026, 154 + f32(index) * 29, 216, 25),
			fmt.tprintf("%v", preset),
			group.doctrine.preset == preset,
		) {
			operation_planning_capture_undo(s)
			group.doctrine = game.combat_doctrine_policy(preset)
			operation_planning_mutated(s)
		}
	}
	y: f32 = 286
	if button(R(1026, y, 216, 28), fmt.tprintf("OBJECTIVE · %v", group.doctrine.objective)) {
		operation_planning_capture_undo(s)
		group.doctrine.objective = game.Combat_Objective_Priority_Policy((int(group.doctrine.objective) + 1) % 3)
		operation_planning_mutated(s)
	}
	if button(R(1026, y + 34, 216, 28), fmt.tprintf("ENGAGE · %v", group.doctrine.engagement)) {
		operation_planning_capture_undo(s)
		group.doctrine.engagement = game.Combat_Engagement_Policy((int(group.doctrine.engagement) + 1) % 4)
		operation_planning_mutated(s)
	}
	if button(R(1026, y + 68, 216, 28), fmt.tprintf("COHESION · %v", group.doctrine.cohesion)) {
		operation_planning_capture_undo(s)
		group.doctrine.cohesion = game.Combat_Cohesion_Policy((int(group.doctrine.cohesion) + 1) % 4)
		operation_planning_mutated(s)
	}
	if button(R(1026, y + 102, 216, 28), fmt.tprintf("PURSUIT · %v", group.doctrine.pursuit)) {
		operation_planning_capture_undo(s)
		group.doctrine.pursuit = game.Combat_Pursuit_Policy((int(group.doctrine.pursuit) + 1) % 3)
		operation_planning_mutated(s)
	}
	if button(R(1026, y + 136, 216, 28), fmt.tprintf("WITHDRAW · %v", group.doctrine.withdrawal)) {
		operation_planning_capture_undo(s)
		group.doctrine.withdrawal = game.Combat_Withdrawal_Policy((int(group.doctrine.withdrawal) + 1) % 4)
		operation_planning_mutated(s)
	}
	if button(R(1026, y + 170, 216, 28), fmt.tprintf("ORDNANCE · %v", group.doctrine.ordnance)) {
		operation_planning_capture_undo(s)
		group.doctrine.ordnance = game.Combat_Ordnance_Policy((int(group.doctrine.ordnance) + 1) % 3)
		operation_planning_mutated(s)
	}
}

operation_planning_draw_contingencies :: proc(s: ^Ux_State) {
	group := &s.combat_operation.draft.groups[s.combat_planning_group]
	label_caps("ORDERED CONTINGENCIES", 1026, 126, UX.info)
	for &contingency, index in group.contingencies[:group.contingency_count] {
		y := 158 + f32(index) * 64
		if button(R(1026, y, 216, 27), fmt.tprintf("IF · %v", contingency.trigger)) {
			operation_planning_capture_undo(s)
			contingency.trigger = game.Combat_Contingency_Trigger((int(contingency.trigger) % 7) + 1)
			operation_planning_mutated(s)
		}
		if button(R(1026, y + 30, 216, 27), fmt.tprintf("THEN · %v", contingency.action)) {
			operation_planning_capture_undo(s)
			contingency.action = game.Combat_Contingency_Action((int(contingency.action) % 5) + 1)
			operation_planning_mutated(s)
		}
	}
	if button(
		R(1026, 552, 216, 32),
		"ADD CONTINGENCY",
		group.contingency_count < len(group.contingencies),
	) {
		operation_planning_capture_undo(s)
		group.contingencies[group.contingency_count] = {
			trigger = .Extraction_Window,
			action = .Disengage,
			subject_group = s.combat_planning_group,
			target_group = -1,
			threshold = 1080,
			enabled = true,
		}
		group.contingency_count += 1
		operation_planning_mutated(s)
	}
}

operation_planning_draw_review :: proc(s: ^Ux_State) {
	validation := game.combat_operation_validate_plan(&s.combat_operation, &s.combat_operation.draft)
	s.combat_operation.draft.validation = validation
	label_caps("COMMITMENT REVIEW", 1026, 126, UX.info)
	color := validation.valid ? UX.good : UX.bad
	draw_fmt(1026, 154, TYPE_HEADING_COMPACT, color, "%d ERRORS · %d WARNINGS", validation.error_count, validation.warning_count)
	y: f32 = 196
	for issue in validation.errors[:min(validation.error_count, 5)] {
		draw_text_fitted(fmt.tprintf("BLOCK · %v", issue), R(1026, y, 220, 22), TYPE_MICRO, UX.bad)
		y += 24
	}
	for issue in validation.warnings[:min(validation.warning_count, 5)] {
		draw_text_fitted(fmt.tprintf("WARN · %v", issue), R(1026, y, 220, 22), TYPE_MICRO, UX.warn)
		y += 24
	}
	draw_fmt(1026, 442, TYPE_SMALL, UX.text, "FIRE CONTROL · %v", s.combat_operation.draft.fire_control)
	if button(R(1026, 472, 216, 30), "CYCLE FIRE CONTROL") {
		operation_planning_capture_undo(s)
		s.combat_operation.draft.fire_control =
			game.Combat_Fire_Control((int(s.combat_operation.draft.fire_control) + 1) % 3)
		operation_planning_mutated(s)
	}
	if button(R(1026, 532, 216, 46), "COMMIT OPERATION", validation.valid, true) {
		operation_planning_launch(s)
	}
}

draw_operation_planning :: proc(s: ^Ux_State) {
	operation_planning_camera_input(s)
	rl.DrawRectangleRec(R(0, 0, 1280, 76), UX.void)
	rl.DrawRectangleRec(R(0, 612, 1280, 108), UX.void)
	rl.DrawRectangleRec(R(0, 76, 205, 536), UX.void)
	rl.DrawRectangleRec(R(1000, 76, 280, 536), UX.void)
	draw_text("OPERATION PLAN", 18, 15, TYPE_HEADING, UX.text)
	draw_fmt(
		18,
		45,
		TYPE_MICRO,
		UX.dim,
		"%s · FIELD %016X · PLAN R%d",
		game.skirmish_mission_name(s.combat_operation.mission),
		s.combat_operation.seed,
		s.combat_operation.draft.revision,
	)
	for label, index in OPERATION_TABS {
		x := 346 + f32(index) * 108
		if button(R(x, 19, 102, 34), label, true, s.combat_planning_tab == index) {
			s.combat_planning_tab = index
		}
	}
	operation_planning_draw_groups(s)
	panel(R(1010, 112, 258, 500), true)
	operation_planning_draw_map(s)
	switch s.combat_planning_tab {
	case 0:
		operation_planning_draw_intel(s)
	case 1:
		operation_planning_draw_fleet(s)
	case 2:
		operation_planning_draw_orders(s)
	case 3:
		operation_planning_draw_doctrine(s)
	case 4:
		operation_planning_draw_contingencies(s)
	case 5:
		operation_planning_draw_review(s)
	}
	if button(R(220, 626, 92, 26), "ORBIT ←") do combat_orbit(s, -.18, 0)
	if button(R(316, 626, 92, 26), "ORBIT →") do combat_orbit(s, .18, 0)
	if button(R(412, 626, 92, 26), "ORBIT ↑") do combat_orbit(s, 0, -.12)
	if button(R(508, 626, 92, 26), "ORBIT ↓") do combat_orbit(s, 0, .12)
	draw_text("ARROWS ORBIT · WHEEL ZOOMS · ORDERS TAB EDITS ROUTES", 620, 632, TYPE_MICRO, UX.dim)
	if button(R(18, 666, 172, 34), "LEAVE DRAFT") {
		s.screen =
			s.combat_operation.operation_context == .Campaign ? .Care : .Menu
	}
	draw_tooltip()
}
