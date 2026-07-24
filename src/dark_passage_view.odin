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

normal_space_advance_elapsed :: proc(p: ^game.Passage) -> f64 {
	return max(p.normal_course.total_days - p.normal_course.elapsed_days, 1)
}

// The Dark view is a map, but it is not an unbounded click surface.  Keeping
// this routing separate from drawing gives every pointer press one owner and
// prevents an illustrated target from reacting beneath a command or record.
Dark_Pointer_Region :: enum {
	Map,
	Status,
	Utility,
	Decision,
	Drawer,
	Modal,
}

dark_pointer_region :: proc(s: ^Ux_State, point: rl.Vector2) -> Dark_Pointer_Region {
	if s.dark_exit_confirm || s.dark_missing_confirm do return .Modal
	if s.dark_contacts_open || s.dark_comms_open do return .Drawer
	if point.y >= 612 do return .Decision
	// The expedition card deliberately owns the left edge, leaving the rest of
	// the frame for the uncertain, selectable Dark.
	if point.x < 382 && point.y < 224 do return .Status
	if point.y < 62 do return .Utility
	return .Map
}

@(test)
passage_advance_finishes_the_current_normal_space_leg :: proc(t: ^testing.T) {
	p := game.Passage {
		domain = .Normal_Space,
	}
	p.normal_course.total_days = 120
	p.normal_course.elapsed_days = 36
	testing.expect_value(t, normal_space_advance_elapsed(&p), f64(84))
}

dark_selected_door :: proc(s: ^Ux_State) -> (^game.Dark_Door, bool) {
	if s.dark_selection_kind != .Door do return nil, false
	d := &s.campaign.outer_dark.continuum
	for &door in d.doors[:d.door_count] do if door.id == s.dark_selection_id do return &door, true
	return nil, false
}

dark_selected_track :: proc(s: ^Ux_State) -> (^game.Dark_Track, bool) {
	if s.dark_selection_kind != .Tracked_Contact do return nil, false
	t := &s.campaign.passage.dark_navigation.tracker
	for &track in t.tracks[:t.track_count] do if track.organism_id == s.dark_selection_id do return &track, true
	return nil, false
}

dark_threat_label :: proc(track: ^game.Dark_Track) -> string {
	threat := game.dark_track_threat(track)
	switch threat.level {
	case .Hold:
		return fmt.tprintf("COURSE HOLD · %.1f INSIDE %.1f", track.distance, threat.hold_distance)
	case .Watch:
		return fmt.tprintf(
			"WATCH%s · %.1f TO HOLD %.1f",
			threat.closing ? " CLOSING" : "",
			track.distance,
			threat.hold_distance,
		)
	case .Clear:
		return "TRACK"
	}
	return "TRACK"
}

dark_select_course_hold_contact :: proc(s: ^Ux_State) {
	p := &s.campaign.passage
	if p.pause_reason != .Dangerous_Contact do return
	if track, ok := dark_selected_track(s); ok && game.dark_track_requires_response(track) do return
	nearest := f64(1e30)
	for &track in p.dark_navigation.tracker.tracks[:p.dark_navigation.tracker.track_count] do if game.dark_track_requires_response(&track) && track.distance < nearest {nearest = track.distance; s.dark_selection_kind = .Tracked_Contact; s.dark_selection_id = track.organism_id}
}

dark_refresh_selected_course :: proc(s: ^Ux_State) -> bool {
	if door, ok := dark_selected_door(s); ok {
		course, found := game.passage_course_to_door(s.campaign, &s.campaign.passage, door.id, -1)
		if found {s.dark_course_draft = course; s.dark_waypoint_z = 0; s.dark_waypoint_w = course.waypoints[1].position[3] - (course.waypoints[0].position[3] + course.waypoints[course.waypoint_count - 1].position[3]) * .5; return true}
	}
	s.dark_course_draft = {}; return false
}

dark_target_world :: proc(observer, point: game.Dark_Vec4) -> game.Combat_Vec3 {
	return {
		f32(point[0] - observer[0]) * 44,
		f32(point[1] - observer[1]) * 44,
		f32(point[2] - observer[2]) * 44,
	}
}

dark_screen_pick_distance :: proc(
	s: ^Ux_State,
	center: game.Combat_Vec3,
	radius: f32,
	pointer: rl.Vector2,
) -> (
	distance, limit: f32,
	visible: bool,
) {
	screen, projected_visible := dark_3d_project_to_ui(
		s,
		center,
	); if !projected_visible do return 0, 0, false
	edge, edge_visible := dark_3d_project_to_ui(s, {center.x + radius, center.y, center.z})
	projected_radius := f32(
		24,
	); if edge_visible {dx, dy := edge.x - screen.x, edge.y - screen.y; projected_radius = max(projected_radius, f32(math.sqrt(f64(dx * dx + dy * dy))))}
	dx, dy := screen.x - pointer.x, screen.y - pointer.y
	return f32(math.sqrt(f64(dx * dx + dy * dy))), clamp(projected_radius, f32(24), f32(140)), true
}

@(test)
dark_target_projection_keeps_w_as_the_section_coordinate :: proc(t: ^testing.T) {
	observer := game.Dark_Vec4{1, 2, 3, 4}
	testing.expect_value(
		t,
		dark_target_world(observer, {2, 4, 6, 40}),
		game.Combat_Vec3{44, 88, 132},
	)
}

dark_pick_targets :: proc(s: ^Ux_State) {
	if dark_pointer_region(s, ux_mouse) != .Map do return
	p := &s.campaign.passage; d := &s.campaign.outer_dark.continuum; observer := p.dark_navigation.position
	best_distance := f32(
		46,
	); best_kind := Dark_Ui_Selection_Kind.None; best_id := u64(0); best_screen := rl.Vector2{}
	for &door in d.doors[:d.door_count] {
		confidence := game.dark_door_detection_confidence(
			d,
			observer,
			&door,
		); if confidence <= 0 do continue
		if screen, visible := dark_3d_project_to_ui(
			s,
			dark_target_world(d.anchor_position, door.position),
		); visible {
			dx, dy :=
				screen.x -
				ux_mouse.x,
				screen.y -
				ux_mouse.y; distance := f32(math.sqrt(f64(dx * dx + dy * dy)))
			if distance <
			   best_distance {best_distance = distance; best_kind = .Door; best_id = door.id; best_screen = screen}
		}
	}
	for &track in p.dark_navigation.tracker.tracks[:p.dark_navigation.tracker.track_count] {
		point := game.dark_vec4_add(
			observer,
			track.relative_bearing,
		); world := dark_target_world(d.anchor_position, point)
		if screen, visible := dark_3d_project_to_ui(s, world); visible {
			dx, dy :=
				screen.x -
				ux_mouse.x,
				screen.y -
				ux_mouse.y; distance := f32(math.sqrt(f64(dx * dx + dy * dy)))
			if distance <
			   best_distance {best_distance = distance; best_kind = .Tracked_Contact; best_id = track.organism_id; best_screen = screen}
		}
		// The creature plate is drawn at this same estimated fix. Its full
		// apparent extent remains selectable even when uncertainty breaks the
		// engraving into sparse fragments.
		pick_radius := max(f32(track.estimated_extent) * 44 * 1.35, 24)
		if distance, limit, visible := dark_screen_pick_distance(s, world, pick_radius, ux_mouse);
		   visible && distance <= limit {
			score := distance / limit * 46
			if score >= best_distance do continue
			best_distance = score; best_kind = .Tracked_Contact; best_id = track.organism_id
			best_screen, _ = dark_3d_project_to_ui(s, world)
		}
	}
	if best_kind != .None {
		ink := best_kind == .Door ? UX.info : UX.warn
		if best_kind ==
		   .Tracked_Contact {for &track in p.dark_navigation.tracker.tracks[:p.dark_navigation.tracker.track_count] do if track.organism_id == best_id && game.dark_track_threat(&track).level == .Hold {ink = UX.bad; break}}
		rl.DrawRectangleRoundedLinesEx(
			R(best_screen.x - 9, best_screen.y - 9, 18, 18),
			0,
			1,
			1,
			ink,
		)
		if rl.IsMouseButtonPressed(
			.LEFT,
		) {s.dark_selection_kind = best_kind; s.dark_selection_id = best_id; s.dark_intent_open = false; s.dark_fine_plot_open = false; if best_kind == .Door do _ = dark_refresh_selected_course(s)}
	} else if rl.IsMouseButtonPressed(.LEFT) &&
	   ux_mouse.y <
		   600 {s.dark_selection_kind = .None; s.dark_selection_id = 0; s.dark_course_draft = {}}
}

dark_draw_task_group_edge :: proc(s: ^Ux_State, x, y: f32) {
	p := &s.campaign.passage; draw_text("TASK GROUP", x, y, TYPE_MICRO, UX.info)
	line_height := readable_text_size(TYPE_MICRO) + 3
	for ship_id, i in p.ships[:p.ship_count] {
		if at := game.ship_index(s.campaign, ship_id);
		   at >=
		   0 {ship := &s.campaign.ships[at]; draw_fmt(x, y + line_height + f32(i) * line_height, TYPE_MICRO, UX.text, "%02d %s · %s  HULL %d/%d  SCARS %d", i + 1, ship.name, game.role_name(ship.role), max(ship.power - ship.damage, 0), ship.power, ship.dark_field_scars)}
	}
}

dark_count_ecology_roles :: proc(mask: u32) -> int {
	count := 0
	for bit in 0 ..< 5 do if mask & (1 << u32(bit)) != 0 do count += 1
	return count
}

dark_expedition_mode_label :: proc(p: ^game.Passage) -> string {
	if p.contract.objective_met do return "OBJECTIVE COMPLETE"
	if p.domain == .Normal_Space do return "RETURN"
	if p.phase == .Underway do return p.systematic_search_active ? "AUTO EXPLORE" : "UNDERWAY"
	switch p.pause_reason {
	case .Course_Arrival:
		return "ARRIVAL"
	case .Dangerous_Contact, .Coherence_Limit, .Material_Obstruction, .Contract_Evidence:
		return "HELD"
	case .Propellant_Reserve:
		return "DEPTH WINDOW"
	case .None, .Unknown_Door:
		return "DESCENT"
	}
	return "PLANNING"
}

dark_draw_expedition_card :: proc(s: ^Ux_State) {
	p := &s.campaign.passage
	panel(R(16, 12, 354, 150))
	draw_text("DARK EXPEDITION", 30, 26, TYPE_MICRO, UX.info)
	draw_text(
		dark_expedition_mode_label(p),
		30,
		46,
		TYPE_BODY_EMPHASIS,
		p.phase == .Underway ? UX.text : UX.info,
	)
	draw_fmt(
		30,
		70,
		TYPE_MICRO,
		UX.text,
		"DIRECTIVE · %s",
		game.deep_exploration_purpose_name(p.contract.purpose),
	)
	draw_text(
		dark_objective_progress_text(s.campaign, p),
		30,
		88,
		TYPE_MICRO,
		p.contract.objective_met ? UX.good : UX.dim,
	)
	dark_draw_expedition_clock(s)
	depth := game.dark_depth_from_anchor(s.campaign.outer_dark.continuum.seed, s.campaign.outer_dark.continuum.anchor_position, p.dark_navigation.position)
	draw_fmt(
		30,
		146,
		TYPE_MICRO,
		depth <= p.field_depth_rating ? UX.dim : UX.warn,
		"FIELD DEPTH %.1f · STABLE %.1f · EMERGENCY %.1f",
		depth,
		p.field_depth_rating,
		p.emergency_depth_limit,
	)
}

dark_objective_progress_text :: proc(c: ^game.Campaign, p: ^game.Passage) -> string {
	if p.contract.objective_met do return "OBJECTIVE MET"
	switch p.contract.purpose {
	case .Map_Unknown_Door:
		return "UNMAPPED CORRESPONDENCE NOT YET CROSSED"
	case .Verify_Correspondence:
		return "NORMAL-SPACE POSITION NOT YET VERIFIED"
	case .Ecological_Survey:
		observed := dark_count_ecology_roles(
			p.observed_ecology_roles & p.contract.required_ecology_roles,
		)
		required := dark_count_ecology_roles(p.contract.required_ecology_roles)
		return fmt.tprintf("ECOLOGICAL ROLES %d / %d", observed, required)
	case .Stabilize_Relay:
		return "AUTHENTICATED RELAY REQUIRED"
	case .Infrastructure_Run:
		if p.domain == .Normal_Space {
			progress := game.passage_contract_progress(c, p)
			if progress.endpoint_resource < p.contract.resource_threshold do return fmt.tprintf("RESOURCE %.0f%% / %.0f%% REQUIRED", progress.endpoint_resource * 100, p.contract.resource_threshold * 100)
			if !progress.relay_available do return "RESOURCE ENDPOINT FOUND · RELAY REQUIRED"
		}
		return "RESOURCE ENDPOINT AND AUTHENTICATED ROUTE REQUIRED"
	case .None:
	}
	return "OBJECTIVE INCOMPLETE"
}

dark_next_action_text :: proc(s: ^Ux_State) -> string {
	c := s.campaign
	p := &s.campaign.passage
	if p.contract.objective_met {
		if p.domain == .Normal_Space {
			if game.passage_dark_return_available(c, p, p.pending_door_id) do return "DISCOVERY RECORDED · RETURN TO THE DARK"
			return "NO ROUTE HOME · TRANSMIT THE RECORD AND REMAIN HERE"
		}
		return "OBJECTIVE MET · RETURN TO FLEET OR CONTINUE"
	}
	if p.pause_reason == .Coherence_Limit do return "NEXT · PATCH AND RESUME OR FULLY STABILIZE"
	if p.pause_reason == .Propellant_Reserve do return "STABLE DEPTH LIMIT · RETURN OR COMMIT TO A DETECTED CORRESPONDENCE"
	if p.pause_reason == .Material_Obstruction do return "NEXT · DETOUR OR WAIT FOR DRIFT"
	if p.pause_reason == .Dangerous_Contact {
		if s.dark_selection_kind == .Tracked_Contact do return "NEXT · KEEP DISTANCE OR ACCEPT CONTACT RISK"
		return "NEXT · SELECT THE DANGEROUS CONTACT"
	}
	if s.dark_selection_kind == .Tracked_Contact {
		if track, ok := dark_selected_track(s); ok && p.contract.purpose == .Ecological_Survey {
			bit :=
				u32(1) <<
				u32(
					track.role,
				); if p.observed_ecology_roles & bit == 0 do return "NEXT · DOCUMENT THIS ROLE OR RESUME THE COURSE"
		}
		return "NEXT · REVIEW CONTACT, THEN CLOSE THE SENSOR CARD"
	}
	if p.phase == .Underway do return "NEXT · HOLD COURSE; PAUSE IF CONDITIONS CHANGE"
	if p.domain == .Normal_Space {
		if game.passage_dark_return_available(c, p, p.pending_door_id) do return "DISCOVERY RECORDED · RETURN TO THE DARK"
		return "NO ROUTE HOME · TRANSMIT THE RECORD AND REMAIN HERE"
	}
	if s.dark_selection_kind == .Door {
		if door, ok := dark_selected_door(s); ok && p.pending_door_id == door.id do return "NEXT · CROSS MEMBRANE"
		return "NEXT · AUTHORIZE COURSE"
	}
	return "NEXT · OPEN CONTACTS AND SELECT AN UNKNOWN CORRESPONDENCE"
}

dark_policy_value :: proc(policy: game.Dark_Expedition_Policy, field: int) -> string {
	switch field {
	case 0:
		switch policy.route {case .Fast:
			return "FAST"; case .Informed:
			return "INFORMED"; case .Low_Exposure:
			return "LOW EXPOSURE"}
	case 1:
		switch policy.contact {case .Avoid:
			return "AVOID"; case .Observe:
			return "OBSERVE"; case .Tolerate:
			return "TOLERATE"}
	case 2:
		switch policy.return_policy {case .Fleet_First:
			return "FLEET FIRST"; case .Balanced_Return:
			return "BALANCED"; case .Objective_First_Return:
			return "OBJECTIVE FIRST"}
	}
	return ""
}

dark_cycle_intent :: proc(s: ^Ux_State, field: int) {
	p := &s.campaign.passage; policy := p.policy
	switch field {
	case 0:
		policy.route = game.Dark_Route_Policy((int(policy.route) + 1) % 3)
	case 1:
		policy.contact = game.Dark_Contact_Policy((int(policy.contact) + 1) % 3)
	case 2:
		policy.return_policy = game.Dark_Return_Policy((int(policy.return_policy) + 1) % 3)
	}
	_, _ = game.set_dark_policy(s.campaign, p, policy)
	s.dark_strategy = p.strategy
	_ = dark_refresh_selected_course(s)
}

dark_draw_contacts_leaf :: proc(s: ^Ux_State) {
	if !s.dark_contacts_open do return
	p := &s.campaign.passage; d := &s.campaign.outer_dark.continuum; observer := p.dark_navigation.position
	panel_rect := R(
		936,
		58,
		320,
		260,
	); rl.DrawRectangleRounded(panel_rect, 0, 1, rl.Color{4, 4, 4, 246}); rl.DrawRectangleRoundedLinesEx(panel_rect, 0, 1, 1, UX.info)
	draw_text("DETECTED TARGETS", 950, 72, TYPE_FINE, UX.info); y := f32(96); shown := 0
	for &door in d.doors[:d.door_count] {
		confidence := game.dark_door_detection_confidence(
			d,
			observer,
			&door,
		); if confidence <= 0 do continue
		if shown >= 5 do break
		course, reachable := game.passage_course_to_door(
			s.campaign,
			p,
			door.id,
			-1,
		); forecast := game.dark_course_forecast(d, &course)
		coherence := game.passage_course_coherence_forecast(s.campaign, p, &course)
		name := game.dark_correspondence_name(
			s.campaign,
			door.id,
			door.endpoint_known ? door.galaxy_neighborhood : -1,
		)
		label :=
			reachable ? fmt.tprintf("%s  R %.1f  H %.0f%%  I %.0f%%", name, forecast.distance, coherence.projected / coherence.limit * 100, forecast.ecological_interception * 100) : fmt.tprintf("%s  NO ROUTE  CONF %.0f%%", name, confidence * 100)
		if button(
			R(950, y, 292, 28),
			label,
			reachable,
			s.dark_selection_kind == .Door && s.dark_selection_id == door.id,
		) {s.dark_selection_kind = .Door; s.dark_selection_id = door.id; s.dark_contacts_open = false; _ = dark_refresh_selected_course(s)}
		y += 32; shown += 1
	}
	for &track in p.dark_navigation.tracker.tracks[:p.dark_navigation.tracker.track_count] {
		if shown >= 7 do break
		threat := game.dark_track_threat(&track); status := "TRACK"
		if threat.level == .Watch do status = threat.closing ? "CLOSING" : "WATCH"
		if threat.level == .Hold do status = "HOLD"
		label :=
			threat.level == .Clear ? fmt.tprintf("%s · TRACK %.1f · %.0f%%", game.dark_organism_name(track.organism_id, track.role), track.distance, track.confidence * 100) : fmt.tprintf("%s · %s %.1f/%.1f · %.0f%%", game.dark_organism_name(track.organism_id, track.role), status, track.distance, threat.hold_distance, track.confidence * 100)
		if button(
			R(950, y, 292, 28),
			label,
			true,
			s.dark_selection_kind == .Tracked_Contact && s.dark_selection_id == track.organism_id,
		) {s.dark_selection_kind = .Tracked_Contact; s.dark_selection_id = track.organism_id; s.dark_contacts_open = false}
		y += 32; shown += 1
	}
	if shown == 0 do draw_text("NO CONTACTS ABOVE SENSOR FLOOR", 950, 104, TYPE_MICRO, UX.dim)
}

dark_draw_comms_leaf :: proc(s: ^Ux_State) {
	if !s.dark_comms_open do return
	r := R(
		1000,
		58,
		256,
		s.dark_missing_confirm ? 280 : 160,
	); rl.DrawRectangleRounded(r, 0, 1, rl.Color{4, 4, 4, 248}); rl.DrawRectangleRoundedLinesEx(r, 0, 1, 1, UX.warn)
	draw_text("COMMS / FLEET REGISTRY", 1014, 72, TYPE_MICRO, UX.info)
	if !s.dark_missing_confirm {
		if button(R(1014, 98, 228, 32), "DECLARE VOYAGE MISSING", true, true) do s.dark_missing_confirm = true
		draw_text_wrapped(
			"Administrative actions are not navigation.",
			R(1014, 140, 228, 50),
			TYPE_SMALL,
			UX.dim,
		)
	} else {
		draw_text_wrapped(
			"List this expedition as overdue and missing. Ships remain recoverable; no loss is presumed.",
			R(1014, 96, 228, 130),
			TYPE_SMALL,
			UX.warn,
		)
		if button(R(1014, 238, 108, 34), "CANCEL") do s.dark_missing_confirm = false
		if button(
			R(1130, 238, 112, 34),
			"CONFIRM",
			true,
			true,
		) {_, s.status = game.declare_passage_missing(s.campaign, &s.campaign.passage); s.screen = s.deep_exploration_active ? .Menu : .Fleet; s.dark_comms_open = false; s.dark_missing_confirm = false}
	}
}

dark_exit_to_menu :: proc(s: ^Ux_State) {
	s.dark_exit_confirm = false
	if !s.deep_exploration_active do s.return_screen = .Passage
	s.screen = .Menu
}

dark_draw_exit_confirmation :: proc(s: ^Ux_State) {
	if !s.dark_exit_confirm do return
	r := R(870, 78, 386, 190)
	rl.DrawRectangleRounded(r, 0, 1, rl.Color{4, 4, 4, 250})
	rl.DrawRectangleRoundedLinesEx(r, 0, 1, 1, UX.warn)
	draw_text("EXIT STANDALONE SESSION", 890, 96, TYPE_LABEL, UX.warn)
	draw_text_wrapped(
		"Return to the main menu and discard this expedition record. The loaded Chronicle will be restored.",
		R(890, 126, 346, 72),
		TYPE_SMALL,
		UX.text,
	)
	if button(R(890, 216, 156, 34), "KEEP EXPLORING") do s.dark_exit_confirm = false
	if button(R(1056, 216, 180, 34), "DISCARD SESSION", true, true) do dark_exit_to_menu(s)
}

@(test)
dark_passage_exit_preserves_continue_target :: proc(t: ^testing.T) {
	s := ux_state_create()
	defer ux_state_destroy(s)
	s.screen = .Passage
	s.return_screen = .Menu
	dark_exit_to_menu(s)
	testing.expect_value(t, s.screen, Ux_Screen.Menu)
	testing.expect_value(t, s.return_screen, Ux_Screen.Passage)
}

dark_draw_intent_tray :: proc(s: ^Ux_State) {
	p := &s.campaign.passage; policy := p.policy
	draw_text("COMMAND INTENT", 20, 624, TYPE_MICRO, UX.info)
	labels := [3]string {
		fmt.tprintf("ROUTE %s", dark_policy_value(policy, 0)),
		fmt.tprintf("CONTACT %s", dark_policy_value(policy, 1)),
		fmt.tprintf("RETURN %s", dark_policy_value(policy, 2)),
	}
	widths := [3]f32{250, 250, 250}; x := f32(20)
	for label, i in labels {if button(R(x, 644, widths[i], 28), label) do dark_cycle_intent(s, i)
		x += widths[i] + 8}
	if button(R(1100, 644, 154, 28), "BACK TO COURSE") do s.dark_intent_open = false
}

dark_draw_fine_plot_tray :: proc(s: ^Ux_State) {
	draw_text("FINE PLOT / MIDPOINT SECTION", 20, 624, TYPE_MICRO, UX.info)
	draw_fmt(
		20,
		648,
		TYPE_FINE,
		UX.text,
		"Z %+.1f   W %+.1f",
		s.dark_waypoint_z,
		s.dark_waypoint_w,
	)
	if button(R(190, 638, 54, 30), "Z−") do dark_shape_course(s, &s.campaign.passage, -.5, 0)
	if button(R(250, 638, 54, 30), "Z+") do dark_shape_course(s, &s.campaign.passage, .5, 0)
	if button(R(318, 638, 54, 30), "W−") do dark_shape_course(s, &s.campaign.passage, 0, -.5)
	if button(R(378, 638, 54, 30), "W+") do dark_shape_course(s, &s.campaign.passage, 0, .5)
	forecast := game.dark_course_forecast(&s.campaign.outer_dark.continuum, &s.dark_course_draft)
	coherence := game.passage_course_coherence_forecast(
		s.campaign,
		&s.campaign.passage,
		&s.dark_course_draft,
	)
	draw_fmt(
		470,
		642,
		TYPE_FINE,
		coherence.crosses_limit ? UX.warn : UX.text,
		"RANGE %.1f  COHERENCE %.0f→%.0f%%  INTERCEPT %.0f%%",
		forecast.distance,
		coherence.current / coherence.limit * 100,
		coherence.projected / coherence.limit * 100,
		forecast.ecological_interception * 100,
	)
	if button(R(1100, 638, 154, 30), "BACK TO COURSE") do s.dark_fine_plot_open = false
}
