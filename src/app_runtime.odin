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
import capture "zelda_engine:capture"
import ui "zelda_engine:ui"

capture_initialize :: proc(data: rawptr, config: ^capture.Config) -> bool {return true}
capture_resize :: proc(data: rawptr, viewport: capture.Viewport) -> bool {
	rl.SetWindowSize(viewport.width, viewport.height)
	return true
}
capture_screenshot :: proc(data: rawptr, output_path: string) -> bool {
	rl.TakeScreenshot(fmt.ctprintf("%s", output_path))
	return true
}
capture_teardown :: proc(data: rawptr) {}

Capture_Frame_Data :: struct {
	state:                                                 ^Ux_State,
	ship_contact_path:                                     string,
	ship_contact_target_width, ship_contact_target_height: i32,
	planet_capture_path, star_capture_path:                string,
}

graphical_capture_frame :: proc(
	s: ^Ux_State,
	frame: int,
	ship_contact_path: string,
	ship_contact_target_width, ship_contact_target_height: i32,
	planet_capture_path, star_capture_path: string,
) -> capture.Screenshot_Request {
	if len(os.args) < 2 do return {}
	mode := os.args[1]
	path := proc(index: int) -> string {
		return os.args[index]
	}
	switch mode {
	case "--capture-ship-contact-sheet":
		if frame == 2 do return {true, ship_contact_path}
		// Screenshot delivery is asynchronous on Vulkan. Give it an additional
		// presented frame before loading and resizing the finished PNG.
		if frame == 4 do _ = ship_contact_resize_png(ship_contact_path, ship_contact_target_width, ship_contact_target_height)
	case "--capture-planet":
		if frame == 2 do return {true, planet_capture_path}
	case "--capture-star":
		if frame == 2 do return {true, star_capture_path}
	case "--capture-body-detail":
		// The body modal is installed on frame one. Waiting through several complete
		// presents avoids reading a partially populated Vulkan backbuffer on capture.
		if frame == 4 do return {true, path(2)}
	case "--capture-galaxy":
		switch frame {case 2:
			return {true, path(2)}; case 4:
			return {true, path(3)}; case 6:
			return {true, path(4)}}
	case "--capture-passage":
		if len(os.args) >= 5 {
			switch frame {case 2:
				return {true, path(2)}; case 4:
				return {true, path(3)}; case 6:
				return {true, path(4)}; case 8:
				if len(os.args) >= 6 do return {true, path(5)}}
		} else if frame == 2 {return {true, path(2)}}
	case "--capture-passage-stress":
		if frame == 2 do return {true, path(2)}
	case "--capture-passage-deep":
		if frame == 2 do return {true, path(2)}
		if frame == 3 {
			s.campaign.passage.dark_navigation.position[3] = 6
			_ = game.dark_ensure_chunk_loaded(
				&s.campaign.outer_dark.continuum,
				game.dark_chunk_coord_at(s.campaign.passage.dark_navigation.position),
			)
		}
		if frame == 8 do return {true, path(3)}
	case "--benchmark-passage-render":
		if len(os.args) >= 5 && frame == 24 do return {true, path(4)}
	case "--capture-combat-resize":
		if frame == 4 do return {true, path(2)}
	case "--capture-far-engagement":
		if frame == 2 do return {true, path(2)}
	case "--capture-combat-late":
		if frame == 1 {
			s.combat_paused = true
			sel := clamp(s.combat_selected, 0, s.combat.friendly_count - 1)
			if s.combat.unit_count > s.combat.friendly_count {
				target := s.combat.friendly_count
				s.combat.units[sel].target = target
				s.combat.units[sel].engagement_target = target
				s.combat.units[sel].action = .Attack_Run
				s.combat.units[sel].weapon_cooldown = .8
				s.combat.units[sel].ability_cooldown = 12
				s.combat.units[sel].defense_response = "Chaff broke radar lock"
				s.combat.units[sel].defense_cooldown = 4
				s.combat.units[sel].chaff = 1
			}
		}
		if frame == 2 do return {true, path(2)}
	case "--capture-fleet",
	     "--capture-ship-detail",
	     "--capture-generated-fleet",
	     "--capture-ui-knollboard",
	     "--capture-ui-accents-knollboard",
	     "--capture-ship-board",
	     "--capture-ship-effects-board",
	     "--capture-ship-drive-board",
	     "--capture-ship-wing-board",
	     "--capture-ship-hull-board",
	     "--capture-ship-mission-board",
	     "--capture-ship-damage-board",
	     "--capture-ship-service-board",
	     "--capture-ship-lineage-board",
	     "--capture-ship-seed-board",
	     "--capture-ship-hardpoint-board",
	     "--capture-ship-weapon-board",
	     "--capture-ship-direct-fire-board",
	     "--capture-single-hull-weapon-board",
	     "--capture-single-hull-direct-fire-board",
	     "--capture-delta-weapon-board",
	     "--capture-modular-fleet-weapon-board",
	     "--capture-single-hull-strike-weapon-board",
	     "--capture-strike-weapon-lineage-board",
	     "--capture-strike-ordnance-multiview-board",
	     "--capture-interaction",
	     "--capture-combat",
	     "--capture-combat-stress",
	     "--capture-combat-finale",
	     "--capture-combat-result":
		if frame == 2 do return {true, path(2)}
	}
	return {}
}

capture_frame_tick :: proc(
	data: rawptr,
	frame: int,
	config: ^capture.Config,
) -> capture.Screenshot_Request {
	value := cast(^Capture_Frame_Data)data
	return graphical_capture_frame(
		value.state,
		frame,
		value.ship_contact_path,
		value.ship_contact_target_width,
		value.ship_contact_target_height,
		value.planet_capture_path,
		value.star_capture_path,
	)
}

graphical_capture_horizon :: proc() -> int {
	frame := 0
	for !graphical_capture_complete(frame + 1) && frame < 1000 do frame += 1
	return frame
}

graphical_capture_complete :: proc(frame: int) -> bool {
	if len(os.args) < 2 do return false
	switch os.args[1] {
	case "--capture-galaxy":
		return frame > 7
	case "--capture-body-detail":
		return frame > 6
	case "--capture-planet", "--capture-star":
		return frame > 3
	case "--capture-ship-contact-sheet":
		return frame > 4
	case "--capture-passage":
		return frame > (len(os.args) >= 6 ? 20 : len(os.args) >= 5 ? 18 : 14)
	case "--capture-passage-stress":
		return frame > 14
	case "--capture-passage-deep":
		return frame > 22
	case "--capture-combat-resize":
		return frame > 5
	case "--capture-far-engagement":
		// Keep the fixture alive through asynchronous Vulkan readback on slower
		// drivers; operational charts do not otherwise need these extra frames.
		return frame > 14
	case "--capture-fleet",
	     "--capture-ship-detail",
	     "--capture-generated-fleet",
	     "--capture-ui-knollboard",
	     "--capture-ui-accents-knollboard",
	     "--capture-ship-board",
	     "--capture-ship-effects-board",
	     "--capture-ship-drive-board",
	     "--capture-ship-wing-board",
	     "--capture-ship-hull-board",
	     "--capture-ship-mission-board",
	     "--capture-ship-damage-board",
	     "--capture-ship-service-board",
	     "--capture-ship-lineage-board",
	     "--capture-ship-seed-board",
	     "--capture-ship-hardpoint-board",
	     "--capture-ship-weapon-board",
	     "--capture-ship-direct-fire-board",
	     "--capture-single-hull-weapon-board",
	     "--capture-single-hull-direct-fire-board",
	     "--capture-delta-weapon-board",
	     "--capture-modular-fleet-weapon-board",
	     "--capture-single-hull-strike-weapon-board",
	     "--capture-strike-weapon-lineage-board",
	     "--capture-strike-ordnance-multiview-board",
	     "--capture-interaction",
	     "--capture-combat",
	     "--capture-combat-stress",
	     "--capture-combat-finale",
	     "--capture-combat-late",
	     "--capture-combat-result":
		return frame > 3
	}
	return false
}


graphical_prepare_combat :: proc(s: ^Ux_State, seed: u64, mode: string, direct_start := false) {
	if direct_start {
		switch mode {
		case "--combat-finale":
			combat_replace_mission(s, game.combat_new_finale_mission(seed))
		case "--combat-stress":
			combat_replace_mission(s, game.combat_new_stress_mission(seed))
		case:
			combat_replace_mission(s, game.combat_new_mission(seed))
		}
		s.combat_briefing = true
	} else {
		switch mode {
		case "--capture-combat-finale":
			combat_replace_mission(s, game.combat_new_finale_mission(seed))
		case "--capture-combat-stress":
			combat_replace_mission(s, game.combat_new_stress_mission(seed))
		case "--capture-combat-result":
			combat_replace_mission(
				s,
				game.combat_autoplay_mission(seed, game.COMBAT_DURATION + .1),
			)
		case "--capture-combat-late":
			combat_replace_mission(s, game.combat_autoplay_mission(seed, 420))
		case "--capture-combat":
			combat_replace_mission(s, game.combat_new_campaign_mission(s.campaign))
		case:
			combat_replace_mission(s, game.combat_new_mission(seed))
		}
	}
	s.combat.units[0].selected = true
	s.combat_selected = 0
	if mode == "--capture-combat" && s.combat.friendly_count > 1 do s.combat.units[1].selected = true
	combat_ai_apply_graphical_checkpoint(&s.combat, os.args)
	if mode == "--capture-combat-stress" {
		s.combat.time = 84
		game.combat_add_event(&s.combat, "Three missile tracks acquired.")
		s.combat.time = 90
		game.combat_add_event(&s.combat, "Railguns opened on command contact.")
		s.combat.time = 95
		game.combat_add_event(&s.combat, "Countermeasure screen established.")
		element := &s.combat.units[0]
		if element.formation_ships > 1 &&
		   element.roster_start >= 0 &&
		   element.roster_start < len(s.combat.ships) {
			ship := &s.combat.ships[element.roster_start]
			individual_max := element.max_hull / f32(element.formation_ships)
			previous := ship.hull
			ship.hull = min(ship.hull, individual_max * .28)
			element.hull = max(0, element.hull - (previous - ship.hull))
		}
	}
	// Dense-state captures focus the most endangered surviving command element so
	// threat telemetry and target causality are exercised by visual regression.
	if mode == "--capture-combat-late" {
		s.combat_paused = true
		threatened := -1
		for salvo in s.combat.salvos do if salvo.active && salvo.side == .Raider && salvo.target >= 0 && salvo.target < s.combat.friendly_count && !s.combat.units[salvo.target].disabled {
			threatened = salvo.target
			break
		}
		if threatened < 0 {
			for hostile in s.combat.units[s.combat.friendly_count:s.combat.unit_count] {
				candidate :=
					hostile.engagement_target >= 0 ? hostile.engagement_target : hostile.target
				if !hostile.disabled &&
				   candidate >= 0 &&
				   candidate < s.combat.friendly_count &&
				   !s.combat.units[candidate].disabled {threatened = candidate; break}
			}
		}
		if threatened < 0 {
			for element, index in s.combat.units[:s.combat.friendly_count] do if !element.disabled && !element.extracted {threatened = index; break}
			if threatened >= 0 {
				for hostile, offset in s.combat.units[s.combat.friendly_count:s.combat.unit_count] do if !hostile.disabled && !hostile.extracted {
					source := s.combat.friendly_count + offset
					game.combat_launch_salvo(&s.combat, source, threatened, .Guided_Missile, 1)
					for &salvo in s.combat.salvos do if salvo.active && salvo.source == source && salvo.target == threatened {
						salvo.speed = 5
						salvo.time_remaining = 4
						salvo.guidance = 1
					}
					break
				}
			}
		}
		if threatened >= 0 {
			has_visual_salvo := false
			for salvo in s.combat.salvos do if salvo.active && salvo.side == .Raider && salvo.target == threatened {has_visual_salvo = true; break}
			if !has_visual_salvo {
				for hostile, offset in s.combat.units[s.combat.friendly_count:s.combat.unit_count] do if !hostile.disabled && !hostile.extracted {
					source := s.combat.friendly_count + offset
					game.combat_launch_salvo(&s.combat, source, threatened, .Guided_Missile, 1)
					for &salvo in s.combat.salvos do if salvo.active && salvo.source == source && salvo.target == threatened {
						salvo.speed = 5; salvo.time_remaining = 4; salvo.guidance = 1
					}
					break
				}
			}
		}
		if threatened >= 0 {
			forced_source := min(s.combat.friendly_count, s.combat.unit_count - 1)
			forced := game.Combat_Salvo {
				source         = forced_source,
				target         = threatened,
				side           = .Raider,
				weapon         = .Guided_Missile,
				position       = s.combat.units[forced_source].position,
				target_volume  = s.combat.units[threatened].position,
				time_remaining = 4,
				speed          = 5,
				strength       = 1,
				guidance       = 1,
				active         = true,
			}
			if len(s.combat.salvos) >
			   0 {s.combat.salvos[0] = forced} else do append(&s.combat.salvos, forced)
			for hostile, index in s.combat.units[s.combat.friendly_count:s.combat.unit_count] do if !hostile.disabled && !hostile.extracted {
				s.combat.units[threatened].target = s.combat.friendly_count + index
				s.combat.units[threatened].engagement_target = s.combat.friendly_count + index
				s.combat.units[threatened].action = .Attack_Run
				break
			}
			for &element in s.combat.units[:s.combat.friendly_count] do element.selected = false
			s.combat.units[threatened].selected = true
			s.combat.units[threatened].readiness = 42
			s.combat.units[threatened].cohesion = 58
			// Keep one live impact in the paused dense-state fixture so HDR flash
			// shape, bloom, occlusion, and map-scale readability are screenshot-tested.
			s.combat.units[threatened].impact_flash = .45
			if s.combat.units[threatened].max_craft > 2 do s.combat.units[threatened].craft = s.combat.units[threatened].max_craft - 2
			s.combat_selected = threatened
		}
		// Preserve one damaged surviving ship in a different formation so dense
		// UI captures exercise per-ship hull segmentation rather than only full
		// aggregate bars. Keep the command element and exact roster record aligned.
		damaged := -1
		for element, index in s.combat.units[:s.combat.friendly_count] do if index != threatened && !element.disabled && !element.extracted && element.formation_ships > 0 && element.roster_start >= 0 && element.roster_start < len(s.combat.ships) {
			damaged = index
			if element.formation_ships > 1 do break
		}
		if damaged >= 0 {
			element := &s.combat.units[damaged]
			ship := &s.combat.ships[element.roster_start]
			individual_max := element.max_hull / f32(max(element.formation_ships, 1))
			previous := ship.hull
			ship.hull = min(ship.hull, individual_max * .28)
			element.hull = max(0, element.hull - (previous - ship.hull))
		}
	}
	s.combat_speed = 1
	if mode == "--capture-combat-late" do s.combat_speed = 0
	s.combat_last_time = rl.GetTime()
	s.screen = .Combat
	if mode == "--capture-combat" {
		s.combat_zoom = COMBAT_ZOOM_MAX
		s.combat_orientation = combat_default_orientation()
		view := combat_quat_rotate(s.combat_orientation, s.combat.units[0].position)
		s.combat_pan_x = -view.x * COMBAT_VIEW_SCALE
		s.combat_pan_y = -view.y * COMBAT_VIEW_SCALE
	}
	if mode == "--benchmark-combat-render" do s.combat_paused = true
}

graphical_prepare_passage :: proc(s: ^Ux_State, mode: string) {
	capture_ships := [2]int{0, 1}
	_, _ = game.begin_passage(
		s.campaign,
		game.default_passage_contract(),
		capture_ships[:],
		&s.campaign.passage,
	)
	s.screen = .Passage
	s.dark_zoom = 1
	s.guide_dismissed = true
	if mode == "--benchmark-passage-render" {
		s.campaign.passage.dark_navigation.position[3] = 0
		s.dark_orientation = combat_quat_mul(
			combat_quat_axis({1, 0, 0}, -.18),
			combat_quat_mul(combat_default_orientation(), combat_quat_axis({0, 0, 1}, .31)),
		)
		d := &s.campaign.outer_dark.continuum
		d.field_count = 0
		origin := s.campaign.passage.dark_navigation.position
		for i in 0 ..< COMBAT_3D_MAX_CREATURES {
			if i >= d.organism_count {d.organism_count = i + 1; d.organisms[i] = {}}
			o := &d.organisms[i]; o.id = u64(0x4d000 + i); o.role = game.Dark_Ecological_Role(i % 5); o.alive = true
			o.radius = .62 + f64(i % 4) * .08; o.energy = .8; o.condition = .9
			column := i % 4; row := i / 4
			o.position =
				origin; o.position[0] += (f64(column) - 1.5) * 1.55; o.position[1] += (f64(row) - 1.5) * 1.08; o.position[2] += (f64((i * 7) % 5) - 2) * .12; o.position[3] += (f64(i % 3) - 1) * .14
			o.genome = game.generate_sdf_creature(combat_3d_creature_seed(d.seed, o.id, o.role))
		}
	}
	if mode == "--capture-passage-deep" {
		// Begin at the canonical shallow section. The capture loop moves
		// to deep W only after recording the baseline frame.
		s.campaign.passage.dark_navigation.position[3] = 0
	} else if mode == "--capture-passage-stress" {
		s.dark_orientation = combat_quat_mul(
			combat_quat_axis({1, 0, 0}, -.18),
			combat_quat_mul(combat_default_orientation(), combat_quat_axis({0, 0, 1}, .31)),
		)
		ui_fixture := len(os.args) >= 4 ? os.args[3] : "door"
		if course, found := game.passage_course_to_unknown_door(
			s.campaign,
			&s.campaign.passage,
			-1,
		); found {
			s.dark_course_draft = course
			s.dark_waypoint_w =
				course.waypoints[1].position[3] -
				(course.waypoints[0].position[3] +
						course.waypoints[course.waypoint_count - 1].position[3]) *
					.5
			door_at := game.dark_nearest_unknown_door(
				&s.campaign.outer_dark.continuum,
				s.campaign.passage.dark_navigation.position,
			)
			if door_at >= 0 &&
			   ui_fixture !=
				   "idle" {s.dark_selection_kind = .Door; s.dark_selection_id = s.campaign.outer_dark.continuum.doors[door_at].id}
			if ui_fixture == "underway" do _, _ = game.plot_passage_course(s.campaign, &s.campaign.passage, course)
		}
		if ui_fixture == "contact" || ui_fixture == "survey" {
			role :=
				ui_fixture == "contact" ? game.Dark_Ecological_Role.Shear_Hunter : .Lantern_Grazer
			behavior := ui_fixture == "contact" ? game.Dark_Behavior.Hunting : .Feeding
			track := game.Dark_Track {
				organism_id      = 0xc047ac7,
				role             = role,
				relative_bearing = {1.8, .4, .2, .35},
				velocity         = {-.12, .03, 0, -.02},
				distance         = 1.9,
				estimated_extent = .8,
				energy_band      = .75,
				condition_band   = .75,
				preferred_depth  = 2.4,
				behavior         = behavior,
				target_id        = u64(s.campaign.passage.ships[0]),
				confidence       = .72,
			}
			s.campaign.passage.dark_navigation.tracker = {
				track_count = 1,
			}; s.campaign.passage.dark_navigation.tracker.tracks[0] = track
			s.dark_selection_kind = .Tracked_Contact; s.dark_selection_id = track.organism_id
			if s.dark_course_draft.waypoint_count >=
			   2 {_, _ = game.plot_passage_course(s.campaign, &s.campaign.passage, s.dark_course_draft); s.dark_course_draft = {}}
			if ui_fixture ==
			   "contact" {s.campaign.passage.phase = .Awaiting_Leg; s.campaign.passage.pause_reason = .Dangerous_Contact}
			if ui_fixture ==
			   "survey" {s.campaign.passage.contract.purpose = .Ecological_Survey; s.campaign.passage.contract.required_ecology_roles = u32(1) << u32(role)}
		}
		if ui_fixture == "approach" || ui_fixture == "intersect" || ui_fixture == "withdraw" {
			w :=
				ui_fixture == "intersect" ? f64(0) : ui_fixture == "approach" ? f64(.62) : f64(-.62)
			vw := ui_fixture == "withdraw" ? f64(-.08) : f64(.08)
			track := game.Dark_Track {
				organism_id      = 0xc047ac8,
				role             = .Lantern_Grazer,
				relative_bearing = {1.6, .35, .18, w},
				velocity         = {-.08, .02, 0, vw},
				distance         = 1.7,
				estimated_extent = .85,
				energy_band      = .75,
				condition_band   = .82,
				preferred_depth  = 2.2,
				behavior         = .Migrating,
				confidence       = .68,
			}
			s.campaign.passage.dark_navigation.tracker = {
				track_count = 1,
			}
			s.campaign.passage.dark_navigation.tracker.tracks[0] = track
			s.dark_selection_kind = .Tracked_Contact; s.dark_selection_id = track.organism_id
		}
		if ui_fixture == "deep-route" && s.dark_course_draft.waypoint_count >= 3 {
			s.dark_course_draft.waypoints[1].position[3] += 4.5
			s.dark_course_draft.waypoints[2].position[3] += 2.25
		}
		if ui_fixture == "uncertain" {
			if s.dark_course_draft.waypoint_count >=
			   2 {_, _ = game.plot_passage_course(s.campaign, &s.campaign.passage, s.dark_course_draft); s.dark_course_draft = {}}
			s.campaign.passage.dark_navigation.forecast.topology_confidence = .38
		}
		if ui_fixture == "reduced" do s.reduced_motion = true
		if ui_fixture == "coherence" {
			if s.dark_course_draft.waypoint_count >=
			   2 {_, _ = game.plot_passage_course(s.campaign, &s.campaign.passage, s.dark_course_draft); s.dark_course_draft = {}}
			s.campaign.passage.phase = .Awaiting_Leg; s.campaign.passage.pause_reason = .Coherence_Limit; s.campaign.passage.dark_navigation.autopilot_active = false; s.campaign.passage.coherence_exposure = game.passage_coherence_limit(&s.campaign.passage) + .08; s.dark_selection_kind = .None; s.dark_selection_id = 0
		}
		if ui_fixture == "obstruction" {
			if s.dark_course_draft.waypoint_count >=
			   2 {_, _ = game.plot_passage_course(s.campaign, &s.campaign.passage, s.dark_course_draft); s.dark_course_draft = {}}
			s.campaign.passage.phase = .Awaiting_Leg; s.campaign.passage.pause_reason = .Material_Obstruction; s.campaign.passage.dark_navigation.autopilot_active = false; s.campaign.passage.dark_navigation.paused_for_replan = true; s.dark_selection_kind = .None; s.dark_selection_id = 0
		}
		if ui_fixture == "propellant-mid" || ui_fixture == "propellant-boundary" {
			p := &s.campaign.passage
			p.dark_navigation.position[0] += 1.25
			exit_cost, known := game.passage_propellant_to_fleet_exit(s.campaign, p)
			if known do p.course_cost = ui_fixture == "propellant-boundary" ? max(game.passage_propellant_capacity(p) - exit_cost, 0) : game.passage_propellant_capacity(p) * .25
			s.dark_selection_kind = .None; s.dark_selection_id = 0; s.dark_course_draft = {}
		}
		if ui_fixture == "propellant-unresolved" {
			s.campaign.outer_dark.continuum.anchor_door_id = 0
			s.dark_selection_kind = .None; s.dark_selection_id = 0; s.dark_course_draft = {}
		}
		s.dark_comms_open = ui_fixture == "comms"; s.dark_missing_confirm = ui_fixture == "comms"
		s.dark_intent_open = ui_fixture == "intent"; s.dark_fine_plot_open = ui_fixture == "fine"
		s.dark_contacts_open = ui_fixture == "contacts"
		if ui_fixture == "idle" do s.dark_course_draft = {}
		// Advance presentation time so the fixture exercises both fresh and
		// dried historical wakes instead of rendering every scar at age zero.
		s.campaign.season = 8
		s.campaign.year = 24
		for axis in 0 ..< 4 {coord := game.Dark_Chunk_Coord{}; coord[axis] = 1; _ = game.dark_ensure_chunk_loaded(&s.campaign.outer_dark.continuum, coord)}
	}
}

graphical_prepare_ship_detail :: proc(s: ^Ux_State) {
	s.selected_ship = min(8, s.campaign.ship_count - 1)
	if len(os.args) >= 5 && os.args[4] == "single" {
		s.campaign.ships[s.selected_ship].generator_kind = .Single_Hull
		s.campaign.ships[s.selected_ship].construction_style = .Living_Hullcraft
	}
	if len(os.args) >= 6 && os.args[5] == "carrier" {
		s.campaign.ships[s.selected_ship].role = .Foundry
		s.campaign.ships[s.selected_ship].operational_role = .Fleet_Carrier
		s.campaign.ships[s.selected_ship].hull_archetype = game.ship_operational_role_hull(
			.Fleet_Carrier,
		)
	}
	s.ship_detail_camera = ship_generator_default_camera()
	if len(os.args) >= 7 && os.args[6] == "stern" do s.ship_detail_camera = {1.28, .18, 1}
	s.screen = .Fleet
	s.modal = .Ship_Detail
	ship_detail_capture_module = len(os.args) >= 4 ? int(parse_u64_or(os.args[3], 0)) : 0
}

graphical_prepare_generated_fleet :: proc(s: ^Ux_State, capture_generated_fleet: bool) {
	draft := game.civilization_setup_generate(0x5eed, .Short)
	_, _ = game.civilization_setup_commit(&draft, s.campaign)
	selected_memory := false
	for ship, i in s.campaign.ships[:s.campaign.ship_count] {
		for memory_index in 0 ..< ship.memory_count do if ship.memories[memory_index].kind == .Precedent_Enacted && game.ship_bond_description(s.campaign, ship.id) != "" {s.selected_ship = i; selected_memory = true; break}
		if selected_memory do break
	}
	for ship, i in s.campaign.ships[:s.campaign.ship_count] {
		if !selected_memory &&
		   ship.memory_count > 0 &&
		   game.ship_bond_description(s.campaign, ship.id) !=
			   "" {s.selected_ship = i; selected_memory = true; break}
	}
	if !selected_memory do for ship, i in s.campaign.ships[:s.campaign.ship_count] do if ship.memory_count > 0 {s.selected_ship = i; selected_memory = true; break}
	if s.campaign.ship_relationship_count > 0 {
		if !selected_memory do s.selected_ship = game.ship_index(s.campaign, s.campaign.ship_relationships[0].ship_a)
	}
	if capture_generated_fleet && s.selected_ship >= 0 && s.selected_ship < s.campaign.ship_count do s.campaign.ships[s.selected_ship].committed = true
	s.guide_dismissed = true
	s.screen = .Fleet
}

fleet_capture_hover_point :: proc(s: ^Ux_State) -> rl.Vector2 {
	if s.campaign.ship_count <= 0 do return V(-100, -100)
	index := min(4, s.campaign.ship_count - 1)
	if index == s.selected_ship && s.campaign.ship_count > 1 {
		index = (index + 1) % s.campaign.ship_count
	}
	return fleet_coalition_ship_point(s.campaign, index)
}

graphical_prepare_fleet_fixture :: proc(s: ^Ux_State) {
	// Keep the fleet regression capture representative of every marker state.
	capture_classes := [5]game.Hull_Class {
		.Strike_Craft,
		.Corvette,
		.Fleet_Ship,
		.Cruiser,
		.Capital_Ship,
	}
	capture_masses := [5]i64{24, 6000, 72000, 900000, 18000000}
	for i in 0 ..< game.MAX_SHIPS {
		class_index := i % len(capture_classes)
		s.campaign.ships[i].hull_class = capture_classes[class_index]
		s.campaign.ships[i].mass_tonnes = capture_masses[class_index]
	}
	s.campaign.ships[0].committed = true
	s.campaign.ships[1].damage = 2
	s.campaign.ships[2].active = false
	s.campaign.ships[2].departure = .Lost
	s.campaign.ships[3].scar = .Hull_Breach
	s.campaign.ships[4].memory_count = 1
	s.campaign.ships[4].memories[0].kind = .Ship_Repaired
	stress_ship := min(8, s.campaign.ship_count - 1) // Habitat exercises the seventh role mapping.
	s.selected_ship = stress_ship
	// Keep the selected dossier dense enough to expose collisions between
	// service history, present commitments, and the bottom action affordance.
	game.record_ship_autonomy(
		s.campaign,
		"The captain held the survey margin without waiting for a fleet order.",
		s.campaign.ships[stress_ship].id,
		1,
	)
	if captain_at := game.historical_figure_index(
		s.campaign,
		s.campaign.ships[stress_ship].captain,
	); captain_at >= 0 {
		profile := &s.campaign.historical_figures[captain_at].captain_profile
		profile.facets[int(game.Captain_Facet.Life_Preservation)] = 4
		profile.facets[int(game.Captain_Facet.Risk_Tolerance)] = 4
		game.captain_refresh_convictions(profile)
	}
	s.campaign.ships[stress_ship].memory_count = 2
	s.campaign.ships[stress_ship].memories[0].kind = .Chronicle_Started
	s.campaign.ships[stress_ship].memories[0].event_sequence = 4
	s.campaign.ships[stress_ship].memories[1].kind = .Resource_Changed
	s.campaign.ships[stress_ship].memories[1].event_sequence = 5
	s.campaign.ships[stress_ship].current_position = "Hold the survey margin until the missing tender reports."
	s.campaign.ships[stress_ship].current_commitment = "Keep one berth open for the Ilex Gate survivors."
	s.campaign.ships[stress_ship].pending_claim = "Requests first salvage rights at the abandoned relay."
	s.campaign.ships[stress_ship].experience = 6
	s.campaign.ships[stress_ship].discoveries = 2
	s.campaign.ships[stress_ship].promises_upheld = 3
	s.campaign.ships[stress_ship].promises_broken = 1
	s.campaign.ships[stress_ship].promises_transformed = 2
	s.campaign.ships[stress_ship].scar = .Hull_Breach
	s.campaign.ships[stress_ship].passage_trait = .Cautious
	if community_at := game.community_index(s.campaign, s.campaign.ships[stress_ship].community);
	   community_at >= 0 {
		s.campaign.communities[community_at].position = .Aggrieved
		s.campaign.communities[community_at].grievance = 4
		s.campaign.promises[0] = {
			beneficiary = s.campaign.communities[community_at].id,
			deadline    = s.campaign.season + 1,
			status      = .Active,
			detail      = "Keep one berth open for the Ilex Gate survivors.",
		}
		s.campaign.promise_count = max(s.campaign.promise_count, 1)
	}
	if s.campaign.ships[stress_ship].captain != 0 {
		s.campaign.captain_obligations[0] = {
			id               = 1,
			captain          = s.campaign.ships[stress_ship].captain,
			ship             = s.campaign.ships[stress_ship].id,
			decision_context = .Withdrawal,
			status           = .Active,
			issued_event     = 4,
			issuer           = s.campaign.institutions[0].id,
			stakes           = 3,
		}
		s.campaign.captain_obligation_count = max(s.campaign.captain_obligation_count, 1)
	}
	s.campaign.current_situation.kind = .Repair_Debt
	s.campaign.current_situation.phase = .Proposal
	s.campaign.current_situation.initiator = s.campaign.ships[stress_ship].id
	if len(os.args) >= 4 {
		if selected, ok := strconv.parse_int(os.args[3]); ok {
			s.selected_ship = clamp(selected, 0, s.campaign.ship_count - 1)
		}
	}
	if len(os.args) >= 5 {
		fixture := os.args[4]
		ship := &s.campaign.ships[s.selected_ship]
		switch fixture {
		case "empty":
			ship.current_position = ""
			ship.current_commitment = ""
			ship.pending_claim = ""
			ship.memory_count = 0
			ship.captain = 0
			ship.community = 0
			ship.damage = 0
			ship.scar = .None
		case "ordinary":
			ship.current_position = "Available for fleet assignment."
			ship.current_commitment = ""
			ship.pending_claim = ""
			ship.memory_count = min(ship.memory_count, 1)
			ship.damage = 0
			ship.scar = .None
		case "damaged":
			ship.damage = max(ship.damage, 4)
			ship.scar = .Hull_Breach
			s.campaign.projects[0] = {
				kind      = .Repair,
				ship      = ship.id,
				remaining = 2,
				active    = true,
			}
		case "departed":
			ship.active = false
			ship.departure = .Settlement
			ship.committed = false
			ship.current_position = "Transferred to the settlement record."
		case "lost":
			ship.active = false
			ship.departure = .Lost
			ship.committed = false
			ship.current_position = "Lost during recorded fleet service."
		case "connected":
		// The default stress fixture already carries simultaneous claims,
		// captain tension, promises, memories, and a pivotal situation.
		case:
		}
	}
	s.guide_dismissed = true
	s.screen = .Fleet

}
