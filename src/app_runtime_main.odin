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
graphical_prepare_initial_state :: proc(
	s: ^Ux_State,
	capture_campaign_seed: u64,
	capture_mode: bool,
) {
	mode := len(os.args) >= 2 ? os.args[1] : ""
	switch mode {
	case "--combat", "--combat-stress", "--combat-finale":
		graphical_prepare_combat(s, u64(0x5eed), mode, true)
	case "--far-engagement":
		game.campaign_init(s.campaign, capture_campaign_seed)
		s.has_campaign = true
		far_engagement_start(s, capture_campaign_seed)
	}
	if !capture_mode do return
	game.campaign_init(s.campaign, capture_campaign_seed)
	s.has_campaign = true
	switch mode {
	case "--benchmark-combat-render",
	     "--capture-combat",
	     "--capture-combat-stress",
	     "--capture-combat-finale",
	     "--capture-combat-late",
	     "--capture-combat-result",
	     "--capture-combat-resize":
		graphical_prepare_combat(s, capture_campaign_seed, mode)
	case "--capture-far-engagement":
		far_engagement_start(s, capture_campaign_seed)
	case "--capture-passage",
	     "--capture-passage-stress",
	     "--capture-passage-deep",
	     "--benchmark-passage-render":
		graphical_prepare_passage(s, mode)
	case "--capture-galaxy",
	     "--capture-body-detail",
	     "--benchmark-galaxy",
	     "--benchmark-planet-detail",
	     "--benchmark-star-detail":
		s.screen = .Galaxy
	case "--capture-interaction":
		s.campaign.ships[3].damage = 3
		game.record_event(
			s.campaign,
			.Ship_Damaged,
			"Resolute still carries the breach opened at Ilex Gate.",
			s.campaign.ships[3].id,
			3,
		)
		_ = game.surface_public_question(s.campaign)
		s.screen = .Interaction
	case "--capture-ship-detail":
		graphical_prepare_ship_detail(s)
	case "--capture-generated-fleet":
		graphical_prepare_generated_fleet(s, true)
		if len(os.args) >= 4 {
			if selected, ok := strconv.parse_int(os.args[3]); ok {
				for &ship in s.campaign.ships[:s.campaign.ship_count] do ship.committed = false
				s.selected_ship = clamp(selected, 0, s.campaign.ship_count - 1)
				s.campaign.ships[s.selected_ship].committed = true
			}
		}
		if len(os.args) >= 5 && os.args[4] == "two-column" {
			for &ship, i in s.campaign.ships[:s.campaign.ship_count] do ship.role = i < 8 ? .Habitat : .Archive
		} else if len(os.args) >= 5 && os.args[4] == "overflow" {
			for &ship in s.campaign.ships[:s.campaign.ship_count] do ship.role = .Habitat
			if len(os.args) >= 6 {
				if scroll, ok := strconv.parse_int(os.args[5]); ok do s.fleet_scroll = f32(max(scroll, 0))
			}
		} else if len(os.args) >= 5 {
			if scroll, ok := strconv.parse_int(os.args[4]); ok do s.fleet_scroll = f32(max(scroll, 0))
		}
	case "--capture-ship-lineage-board":
		graphical_prepare_generated_fleet(s, false)
	case:
		graphical_prepare_fleet_fixture(s)
	}
}


run_graphical :: proc() {
	benchmark_galaxy := len(os.args) >= 2 && os.args[1] == "--benchmark-galaxy"
	benchmark_ship_gen := len(os.args) >= 2 && os.args[1] == "--benchmark-ship-gen"
	benchmark_ship_hatching := len(os.args) >= 2 && os.args[1] == "--benchmark-ship-hatching"
	benchmark_planet_detail := len(os.args) >= 2 && os.args[1] == "--benchmark-planet-detail"
	benchmark_star_detail := len(os.args) >= 2 && os.args[1] == "--benchmark-star-detail"
	benchmark_combat_render := len(os.args) >= 2 && os.args[1] == "--benchmark-combat-render"
	benchmark_passage_render := len(os.args) >= 2 && os.args[1] == "--benchmark-passage-render"
	benchmark_samples := 180
	if (benchmark_galaxy ||
		   benchmark_ship_gen ||
		   benchmark_ship_hatching ||
		   benchmark_planet_detail ||
		   benchmark_star_detail ||
		   benchmark_combat_render ||
		   benchmark_passage_render) &&
	   len(os.args) >= 3 {
		if parsed, ok := strconv.parse_int(os.args[2]); ok do benchmark_samples = clamp(parsed, 60, 900)
	}
	capture_galaxy := len(os.args) >= 5 && os.args[1] == "--capture-galaxy"
	capture_body_detail := len(os.args) >= 3 && os.args[1] == "--capture-body-detail"
	capture_planet := len(os.args) >= 3 && os.args[1] == "--capture-planet"
	preview_planet := len(os.args) >= 2 && os.args[1] == "--planet-preview"
	capture_star := len(os.args) >= 3 && os.args[1] == "--capture-star"
	preview_star := len(os.args) >= 2 && os.args[1] == "--star-preview"
	capture_ship_contact := len(os.args) >= 5 && os.args[1] == "--capture-ship-contact-sheet"
	ship_contact_path := ""
	ship_contact_seed := u64(0x5eed)
	ship_contact_family := game.Procedural_Ship_Family.Fleet
	ship_contact_width, ship_contact_height := i32(1000), i32(800)
	ship_contact_target_width, ship_contact_target_height := i32(3000), i32(2400)
	ship_contact_capture_architecture = .Modular_Frame
	if capture_ship_contact {
		ship_contact_path =
			os.args[2]; if !filepath.is_abs(ship_contact_path) {cwd, _ := os.get_working_directory(context.allocator); ship_contact_path, _ = filepath.join([]string{cwd, ship_contact_path})}
		ship_contact_seed = parse_u64_or(
			os.args[3],
			ship_contact_seed,
		); ship_contact_family = game.procedural_ship_family_from_name(os.args[4])
		if len(os.args) >=
		   7 {if parsed, ok := strconv.parse_int(os.args[5]); ok do ship_contact_target_width = i32(max(parsed, 1280)); if parsed, ok := strconv.parse_int(os.args[6]); ok do ship_contact_target_height = i32(max(parsed, 720))}
		if len(os.args) >= 8 {switch os.args[7] {case "single":
				ship_contact_capture_architecture = .Single_Hull; case "delta":
				ship_contact_capture_architecture = .Delta; case:}}
	}
	planet_capture_path := ""
	planet_capture_width, planet_capture_height := i32(UX_W), i32(UX_H)
	if capture_planet {
		planet_capture_path = os.args[2]
		if !filepath.is_abs(planet_capture_path) {
			cwd, _ := os.get_working_directory(context.allocator)
			planet_capture_path, _ = filepath.join([]string{cwd, planet_capture_path})
		}
		size_arg := 5
		if len(os.args) > size_arg && os.args[size_arg] == "rings" do size_arg += 1
		if len(os.args) > size_arg + 1 {
			if parsed, ok := strconv.parse_int(os.args[size_arg]); ok do planet_capture_width = i32(max(parsed, UX_W))
			if parsed, ok := strconv.parse_int(os.args[size_arg + 1]); ok do planet_capture_height = i32(max(parsed, UX_H))
		}
	}
	star_capture_path := ""
	if capture_star {star_capture_path = os.args[2]; if !filepath.is_abs(star_capture_path) {cwd, _ := os.get_working_directory(context.allocator); star_capture_path, _ = filepath.join([]string{cwd, star_capture_path})}}
	capture_passage := len(os.args) >= 3 && os.args[1] == "--capture-passage"
	capture_passage_stress := len(os.args) >= 3 && os.args[1] == "--capture-passage-stress"
	capture_passage_deep := len(os.args) >= 4 && os.args[1] == "--capture-passage-deep"
	capture_fleet := len(os.args) >= 3 && os.args[1] == "--capture-fleet"
	capture_ship_detail := len(os.args) >= 3 && os.args[1] == "--capture-ship-detail"
	capture_generated_fleet := len(os.args) >= 3 && os.args[1] == "--capture-generated-fleet"
	capture_ui_knollboard := len(os.args) >= 3 && os.args[1] == "--capture-ui-knollboard"
	capture_ui_accents_knollboard :=
		len(os.args) >= 3 && os.args[1] == "--capture-ui-accents-knollboard"
	capture_ship_board := len(os.args) >= 3 && os.args[1] == "--capture-ship-board"
	capture_effect_board := len(os.args) >= 3 && os.args[1] == "--capture-ship-effects-board"
	capture_drive_board := len(os.args) >= 3 && os.args[1] == "--capture-ship-drive-board"
	capture_wing_board := len(os.args) >= 3 && os.args[1] == "--capture-ship-wing-board"
	capture_hull_board := len(os.args) >= 3 && os.args[1] == "--capture-ship-hull-board"
	capture_mission_board := len(os.args) >= 3 && os.args[1] == "--capture-ship-mission-board"
	capture_damage_board := len(os.args) >= 3 && os.args[1] == "--capture-ship-damage-board"
	capture_service_board := len(os.args) >= 3 && os.args[1] == "--capture-ship-service-board"
	capture_lineage_board := len(os.args) >= 3 && os.args[1] == "--capture-ship-lineage-board"
	capture_seed_board := len(os.args) >= 3 && os.args[1] == "--capture-ship-seed-board"
	capture_hardpoint_board := len(os.args) >= 3 && os.args[1] == "--capture-ship-hardpoint-board"
	capture_weapon_board := len(os.args) >= 3 && os.args[1] == "--capture-ship-weapon-board"
	capture_direct_fire_board :=
		len(os.args) >= 3 && os.args[1] == "--capture-ship-direct-fire-board"
	capture_single_hull_weapon_board :=
		len(os.args) >= 3 && os.args[1] == "--capture-single-hull-weapon-board"
	capture_single_hull_direct_fire_board :=
		len(os.args) >= 3 && os.args[1] == "--capture-single-hull-direct-fire-board"
	capture_delta_weapon_board := len(os.args) >= 3 && os.args[1] == "--capture-delta-weapon-board"
	capture_modular_fleet_weapon_board :=
		len(os.args) >= 3 && os.args[1] == "--capture-modular-fleet-weapon-board"
	capture_single_hull_strike_weapon_board :=
		len(os.args) >= 3 && os.args[1] == "--capture-single-hull-strike-weapon-board"
	capture_strike_weapon_lineage_board :=
		len(os.args) >= 3 && os.args[1] == "--capture-strike-weapon-lineage-board"
	capture_strike_ordnance_multiview_board :=
		len(os.args) >= 3 && os.args[1] == "--capture-strike-ordnance-multiview-board"
	capture_interaction := len(os.args) >= 3 && os.args[1] == "--capture-interaction"
	capture_combat := len(os.args) >= 3 && os.args[1] == "--capture-combat"
	capture_combat_stress := len(os.args) >= 3 && os.args[1] == "--capture-combat-stress"
	capture_combat_finale := len(os.args) >= 3 && os.args[1] == "--capture-combat-finale"
	capture_combat_late := len(os.args) >= 3 && os.args[1] == "--capture-combat-late"
	capture_combat_result := len(os.args) >= 3 && os.args[1] == "--capture-combat-result"
	capture_combat_resize := len(os.args) >= 5 && os.args[1] == "--capture-combat-resize"
	capture_far_engagement := len(os.args) >= 3 && os.args[1] == "--capture-far-engagement"
	combat_resize_width, combat_resize_height :=
		i32(1600),
		i32(
			900,
		); if capture_combat_resize {if parsed, ok := strconv.parse_int(os.args[3]); ok do combat_resize_width = i32(max(parsed, UX_W)); if parsed, ok := strconv.parse_int(os.args[4]); ok do combat_resize_height = i32(max(parsed, UX_H))}
	capture_campaign_seed := u64(0x5eed)
	ship_benchmark_family := game.Procedural_Ship_Family.Fleet
	if benchmark_ship_gen && len(os.args) >= 4 do capture_campaign_seed = parse_u64_or(os.args[3], capture_campaign_seed)
	if benchmark_ship_gen && len(os.args) >= 5 do ship_benchmark_family = game.procedural_ship_family_from_name(os.args[4])
	if capture_galaxy && len(os.args) >= 6 do capture_campaign_seed = parse_u64_or(os.args[5], capture_campaign_seed)
	if benchmark_galaxy && len(os.args) >= 4 do capture_campaign_seed = parse_u64_or(os.args[3], capture_campaign_seed)
	if benchmark_planet_detail && len(os.args) >= 4 do capture_campaign_seed = parse_u64_or(os.args[3], capture_campaign_seed)
	if benchmark_star_detail && len(os.args) >= 4 do capture_campaign_seed = parse_u64_or(os.args[3], capture_campaign_seed)
	if benchmark_combat_render && len(os.args) >= 4 do capture_campaign_seed = parse_u64_or(os.args[3], capture_campaign_seed)
	if benchmark_passage_render && len(os.args) >= 4 do capture_campaign_seed = parse_u64_or(os.args[3], capture_campaign_seed)
	ship_benchmark_recipe := game.procedural_ship_generate(
		capture_campaign_seed,
		ship_benchmark_family,
	)
	capture_mode :=
		benchmark_galaxy ||
		benchmark_ship_gen ||
		benchmark_ship_hatching ||
		benchmark_planet_detail ||
		benchmark_star_detail ||
		benchmark_combat_render ||
		benchmark_passage_render ||
		capture_galaxy ||
		capture_body_detail ||
		capture_planet ||
		capture_star ||
		capture_ship_contact ||
		capture_passage ||
		capture_passage_stress ||
		capture_passage_deep ||
		capture_fleet ||
		capture_ship_detail ||
		capture_generated_fleet ||
		capture_ui_knollboard ||
		capture_ui_accents_knollboard ||
		capture_ship_board ||
		capture_effect_board ||
		capture_drive_board ||
		capture_wing_board ||
		capture_hull_board ||
		capture_mission_board ||
		capture_damage_board ||
		capture_service_board ||
		capture_lineage_board ||
		capture_seed_board ||
		capture_hardpoint_board ||
		capture_weapon_board ||
		capture_direct_fire_board ||
		capture_single_hull_weapon_board ||
		capture_single_hull_direct_fire_board ||
		capture_delta_weapon_board ||
		capture_modular_fleet_weapon_board ||
		capture_single_hull_strike_weapon_board ||
		capture_strike_weapon_lineage_board ||
		capture_strike_ordnance_multiview_board ||
		capture_interaction ||
		capture_combat ||
		capture_combat_stress ||
		capture_combat_finale ||
		capture_combat_late ||
		capture_combat_result ||
		capture_combat_resize ||
		capture_far_engagement
	// The star-detail benchmark owns an exact 4K framebuffer. Disabling the
	// platform HiDPI multiplier keeps 3840x2160 from becoming an accidental 8K
	// workload on Retina displays.
	window_flags := rl.ConfigFlags{.WINDOW_RESIZABLE, .VSYNC_HINT}
	if !benchmark_star_detail && !benchmark_ship_gen && !benchmark_ship_hatching && !benchmark_passage_render do window_flags += {.WINDOW_HIGHDPI}
	if capture_mode do window_flags += {.WINDOW_NOT_FOCUSABLE}
	assert(rl.SetRendererDescriptor(LBH_RENDERER_DESCRIPTOR))
	rl.SetConfigFlags(window_flags)
	initial_width :=
		benchmark_passage_render ? i32(1920) : (benchmark_star_detail || benchmark_ship_gen || benchmark_ship_hatching) ? i32(3840) : i32(UX_W)
	initial_height :=
		benchmark_passage_render ? i32(1080) : (benchmark_star_detail || benchmark_ship_gen || benchmark_ship_hatching) ? i32(2160) : i32(UX_H)
	rl.InitWindow(
		initial_width,
		initial_height,
		"Last Best Hope",
	); defer rl.CloseWindow(); rl.SetWindowMinSize(UX_W, UX_H); rl.SetTargetFPS(60)
	defer unload_fonts()
	ship_component_texture = rl.LoadTexture("assets/ships/ship-components-engraved.png")
	ship_map_component_texture = rl.LoadTexture("assets/ships/ship-components-map.png")
	ship_damage_texture = rl.LoadTexture("assets/ships/ship-damage-atlas.png")
	ship_effect_texture = rl.LoadTexture("assets/ships/ship-engine-effects-atlas.png")
	ship_marking_texture = rl.LoadTexture("assets/ships/ship-markings-atlas.png")
	combat_archetype_icon_texture = rl.LoadTexture(
		"assets/ships/combat-archetype-icons-atlas-v1.png",
	)
	combat_depth_plane_texture = rl.LoadTexture("assets/icons/depth-planes-strip.png")
	s := ux_state_create(); defer ux_state_destroy(s); s^ = Ux_State {
		campaign      = s.campaign,
		screen        = .Menu,
		return_screen = .Fleet,
		navigation_return_screen = .Fleet,
		selected_ship = 0,
		selected_node = 0,
		ui_scale      = 1,
		hatch_density = 1,
	}
	defer game.combat_mission_destroy(&s.combat)
	defer delete(s.combat_last_actions)
	defer combat_3d_shutdown(); defer rl.SetWorldPass(nil)
	s.galaxy_star_cache = make([dynamic]Galaxy_Render_Star, MAX_GALAXY_RENDER_STARS)
	defer delete(s.galaxy_star_cache)
	s.has_campaign = ux_autosave_exists()
	graphical_prepare_initial_state(s, capture_campaign_seed, capture_mode)
	if capture_mode {
		capture_scale_buffer: [16]u8
		switch os.get_env_buf(capture_scale_buffer[:], "LBH_CAPTURE_UI_SCALE") {
		case "1.25":
			s.ui_scale = 1.25
		case "1.5":
			s.ui_scale = 1.5
		}
		capture_effect_buffer: [64]u8
		if os.get_env_buf(capture_effect_buffer[:], "LBH_CAPTURE_SCREEN_EFFECT") == "trinitron" {
			s.screen_effect = .Trinitron
		}
	}
	combat_sidebar_hover_capture := len(os.args) >= 4 && os.args[3] == "sidebar-hover"
	combat_no_selection_capture := len(os.args) >= 4 && os.args[3] == "no-selection"
	if combat_no_selection_capture && (capture_combat || capture_combat_late) {
		for &unit in s.combat.units[:s.combat.friendly_count] do unit.selected = false
		s.combat_order_armed = false
		s.combat_ability_armed = false
	}
	capture_frame := 0
	combat_capture_mode :=
		capture_combat ||
		capture_combat_stress ||
		capture_combat_finale ||
		capture_combat_late ||
		capture_combat_result
	// Combat uses the renderer-owned asynchronous readback directly. The
	// generic harness currently marks itself complete without invoking its
	// screenshot callback for these fixtures, so keep the scene alive through
	// delivery just as the Passage stress capture does.
	shared_capture_mode :=
		capture_mode &&
		!combat_capture_mode &&
		!capture_weapon_board &&
		!capture_direct_fire_board &&
		!capture_single_hull_weapon_board &&
		!capture_single_hull_direct_fire_board &&
		!capture_delta_weapon_board &&
		!capture_modular_fleet_weapon_board &&
		!capture_single_hull_strike_weapon_board &&
		!capture_strike_weapon_lineage_board &&
		!capture_strike_ordnance_multiview_board
	shared_capture: capture.Harness
	shared_capture_data := Capture_Frame_Data {
		state                      = s,
		ship_contact_path          = ship_contact_path,
		ship_contact_target_width  = ship_contact_target_width,
		ship_contact_target_height = ship_contact_target_height,
		planet_capture_path        = planet_capture_path,
		star_capture_path          = star_capture_path,
	}
	if shared_capture_mode {
		shared_config := capture.Config {
			viewport       = {initial_width, initial_height},
			frame_horizon  = graphical_capture_horizon(),
			timeout_frames = max(graphical_capture_horizon() + 120, 240),
			output_path    = len(os.args) >= 3 ? os.args[2] : "capture.png",
			focus_policy   = .Background,
			reduced_motion = s.reduced_motion,
			resize_frame   = -1,
		}
		if !capture.start(
			&shared_capture,
			shared_config,
			{
				user_data = &shared_capture_data,
				initialize = capture_initialize,
				frame = capture_frame_tick,
				resize = capture_resize,
				screenshot = capture_screenshot,
				teardown = capture_teardown,
			},
		) {
			fmt.eprintf("capture initialization failed: %v\n", shared_capture.error)
			return
		}
		defer capture.finish(&shared_capture)
	}
	BENCHMARK_WARMUP :: 20
	benchmark_phase, benchmark_phase_frame := 0, 0
	benchmark_zooms := [3]f64{1, 8, 40}
	benchmark_cpu: [3][900]f64
	benchmark_gpu: [3][900]f64
	benchmark_gpu_counts: [3]int
	planet_benchmark_frame := 0
	planet_benchmark_ready := false
	planet_benchmark_cpu, planet_benchmark_wall, planet_benchmark_atmosphere, planet_benchmark_gpu: [900]f64
	planet_benchmark_gpu_count := 0
	combat_benchmark_phase, combat_benchmark_frame := 0, 0
	combat_benchmark_cpu: [2][900]f64
	combat_benchmark_gpu: [2][900]f64
	combat_benchmark_gpu_counts: [2]int
	passage_benchmark_frame := 0
	passage_benchmark_cpu, passage_benchmark_wall, passage_benchmark_gpu: [900]f64
	passage_benchmark_gpu_count := 0
	combat_metric_draws, combat_metric_batches, combat_metric_uploads: [2]u64
	passage_metric_draws, passage_metric_batches, passage_metric_uploads: u64
	fleet_metric_draws, fleet_metric_batches, fleet_metric_uploads: u64
	fleet_screenshot_latency_ms: f64
	ship_benchmark_frame := 0
	ship_benchmark_cpu, ship_benchmark_wall, ship_benchmark_gpu: [900]f64
	ship_benchmark_gpu_count := 0
	hatch_benchmark_phase, hatch_benchmark_frame := 0, 0
	hatch_benchmark_cpu, hatch_benchmark_wall, hatch_benchmark_gpu: [4][900]f64
	hatch_benchmark_gpu_counts: [4]int
	for !rl.WindowShouldClose() {
		rl.SetScreenEffect(
			s.screen_effect,
			s.reduced_motion,
		); if capture_planet && capture_frame == 1 do rl.SetWindowSize(planet_capture_width, planet_capture_height); if capture_ship_contact && capture_frame == 1 do rl.SetWindowSize(ship_contact_width, ship_contact_height); if capture_combat_resize && capture_frame == 1 do rl.SetWindowSize(combat_resize_width, combat_resize_height); w := f32(rl.GetScreenWidth()); h := f32(rl.GetScreenHeight()); ux_zoom = min(w / f32(UX_W), h / f32(UX_H)); ux_origin = V((w - f32(UX_W) * ux_zoom) / 2, (h - f32(UX_H) * ux_zoom) / 2); if capture_ship_contact {ux_zoom = 1; ux_origin = {0, 0}}; mouse := rl.GetMousePosition(); ux_mouse = V((mouse.x - ux_origin.x) / ux_zoom, (mouse.y - ux_origin.y) / ux_zoom); if capture_fleet do ux_mouse = fleet_capture_hover_point(s); if combat_sidebar_hover_capture && (capture_combat || capture_combat_late) do ux_mouse = V(92, 235); if rl.IsKeyPressed(.ESCAPE) {if s.pause_menu_open {s.pause_menu_open = false; s.combat_last_time = rl.GetTime()} else if s.modal != .None {s.modal = .None} else if s.screen != .Menu && s.screen != .Settings {s.pause_return_screen = s.screen; s.pause_menu_open = true} else {ux_focus_back_requested = true}}
		// Keep the canvas world hook absent outside combat so every other screen
		// follows the ordinary depth-free presentation path.
		if s.screen == .Combat || s.screen == .Passage do rl.SetWorldPass(combat_3d_world_pass, s)
		else do rl.SetWorldPass(nil)
		cpu_draw_start := time.tick_now()
		rl.BeginDrawing(); rl.ClearBackground(UX.void); camera := rl.Camera2D {
			offset   = ux_origin,
			target   = {0, 0},
			rotation = 0,
			zoom     = ux_zoom,
		}; rl.BeginMode2D(camera)
		if benchmark_galaxy && s.galaxy_ready {
			s.galaxy_zoom = benchmark_zooms[benchmark_phase]
			if benchmark_phase == 0 {
				s.galaxy_pan_x, s.galaxy_pan_y = 0, 0
			} else {
				selected :=
					s.galaxy.detailed_system_count > 0 ? s.galaxy.detailed_systems[0].neighborhood_index : 0
				n := s.galaxy.neighborhoods[selected]
				s.galaxy_pan_x, s.galaxy_pan_y = n.x_kpc, n.y_kpc
			}
		}
		if capture_galaxy && s.galaxy_ready && (capture_frame == 3 || capture_frame == 5) {
			selected :=
				s.galaxy.detailed_system_count > 0 ? s.galaxy.detailed_systems[0].neighborhood_index : 0
			s.selected_neighborhood = selected
			n := s.galaxy.neighborhoods[selected]
			s.galaxy_pan_x, s.galaxy_pan_y = n.x_kpc, n.y_kpc
			s.galaxy_zoom = capture_frame == 3 ? 8 : 40
		}
		if capture_body_detail && s.galaxy_ready && capture_frame == 1 {
			s.selected_system_detail = 0
			s.selected_body = {
				kind  = .Planet,
				index = min(2, s.galaxy.detailed_systems[0].system.planet_count - 1),
			}
			body_kind := len(os.args) >= 4 ? os.args[3] : "planet"
			if body_kind == "central-black-hole" {
				s.galaxy.central_black_hole_occupied = true
				if s.galaxy.central_black_hole_mass_solar <= 0 do s.galaxy.central_black_hole_mass_solar = 4.3e6
				s.selected_body = {
					kind = .Central_Black_Hole,
				}
			} else if strings.has_prefix(body_kind, "black-hole") {
				s.galaxy.detailed_system_count = max(s.galaxy.detailed_system_count, 1)
				s.galaxy.detailed_systems[0].system = black_hole_capture_fixture(body_kind)
				s.selected_body = {
					kind  = .Star,
					index = 0,
				}
			} else {
				s.selected_body =
					body_kind == "star" ? game.Celestial_Body_Ref{kind = .Star, index = 0} : game.Celestial_Body_Ref{kind = .Planet, index = 0}
			}
			s.modal = .Body_Detail
		}
		if (benchmark_planet_detail || benchmark_star_detail) &&
		   s.galaxy_ready &&
		   !planet_benchmark_ready {
			s.selected_system_detail = 0; s.selected_body = benchmark_star_detail ? game.Celestial_Body_Ref{kind = .Star, index = 0} : game.Celestial_Body_Ref{kind = .Planet, index = 0}
			found := false
			for offset in u64(0) ..< 64 {
				fixture := game.generate_solar_system(capture_campaign_seed + offset)
				for i in 0 ..< fixture.planet_count {kind := fixture.planets[i].kind; if kind == .Gas_Giant || kind == .Ice_Giant || kind == .Ocean {planet_detail_benchmark_system = fixture; s.selected_body = {
							kind  = .Planet,
							index = i,
						}; found = true; break}}
				if found do break
			}
			if !found {fixture := game.generate_solar_system(capture_campaign_seed); if fixture.planet_count > 0 {fixture.planets[0].kind = .Gas_Giant; fixture.planets[0].clouds = game.planet_cloud_composition(.Gas_Giant, fixture.planets[0].body.surface_temperature_k, fixture.planets[0].body.seed); planet_detail_benchmark_system = fixture; s.selected_body = {
						kind  = .Planet,
						index = 0,
					}}}
			s.modal = .Body_Detail
			planet_benchmark_ready = planet_detail_benchmark_system.planet_count > 0
		}
		if (benchmark_planet_detail || benchmark_star_detail) && planet_benchmark_ready do planet_detail_benchmark_time = f32(planet_benchmark_frame) / 60
		if capture_ship_contact &&
		   capture_frame >= 1 {ship_contact_width = i32(w); ship_contact_height = i32(h)}
		if benchmark_ship_gen do draw_procedural_ship(&ship_benchmark_recipe, R(0, 0, w, h), ship_generator_default_camera(), true)
		if benchmark_ship_hatching do draw_ship_hatch_benchmark(hatch_benchmark_phase, w, h)
		if !benchmark_ship_gen && !benchmark_ship_hatching {
			if capture_ship_contact {draw_ship_contact_sheet(ship_contact_seed, ship_contact_family, ship_contact_width, ship_contact_height)} else if capture_star {seed := u64(0x5eed); if len(os.args) >= 4 do seed = parse_u64_or(os.args[3], seed); name := len(os.args) >= 5 ? os.args[4] : "main"; draw_star_plate(seed, star_kind_from_name(name))} else if preview_star {seed := u64(0x5eed); if len(os.args) >= 3 do seed = parse_u64_or(os.args[2], seed); name := len(os.args) >= 4 ? os.args[3] : "main"; draw_star_plate(seed, star_kind_from_name(name), f32(rl.GetTime()) * .012)} else if capture_planet {seed := u64(0x5eed); if len(os.args) >= 4 do seed = parse_u64_or(os.args[3], seed); kind_name := len(os.args) >= 5 ? os.args[4] : "rocky"; kind := planet_kind_from_name(kind_name); force_rings := len(os.args) >= 6 && os.args[5] == "rings"; draw_planet_plate(seed, kind, force_rings, 0, kind_name)} else if preview_planet {seed := u64(0x5eed); if len(os.args) >= 3 do seed = parse_u64_or(os.args[2], seed); kind_name := len(os.args) >= 4 ? os.args[3] : "fertile"; kind := planet_kind_from_name(kind_name); force_rings := len(os.args) >= 5 && os.args[4] == "rings"; now := f32(rl.GetTime()); draw_planet_plate(seed, kind, force_rings, now * .018, kind_name, now, s.reduced_motion)} else if capture_ui_knollboard {draw_ui_knollboard()} else if capture_ui_accents_knollboard {draw_ui_accents_knollboard()} else if capture_ship_board {draw_ship_variation_board()} else if capture_effect_board {draw_ship_effect_board()} else if capture_drive_board {draw_ship_drive_board()} else if capture_wing_board {draw_ship_wing_board()} else if capture_hull_board {draw_ship_hull_board()} else if capture_mission_board {draw_ship_mission_board()} else if capture_damage_board {draw_ship_damage_board()} else if capture_service_board {draw_ship_service_board()} else if capture_lineage_board {draw_ship_lineage_board(s.campaign)} else if capture_seed_board {draw_ship_seed_comparison_board()} else if capture_hardpoint_board {draw_ship_hardpoint_board()} else if capture_weapon_board {draw_ship_weapon_board()} else if capture_direct_fire_board {draw_ship_direct_fire_board()} else if capture_single_hull_weapon_board {draw_ship_single_hull_weapon_board()} else if capture_single_hull_direct_fire_board {draw_ship_single_hull_direct_fire_board()} else if capture_delta_weapon_board {draw_ship_delta_weapon_board()} else if capture_modular_fleet_weapon_board {draw_ship_modular_fleet_weapon_board()} else if capture_single_hull_strike_weapon_board {draw_ship_single_hull_strike_weapon_board()} else if capture_strike_weapon_lineage_board {draw_ship_strike_weapon_lineage_board()} else if capture_strike_ordnance_multiview_board {draw_ship_strike_ordnance_multiview_board()} else {draw_app(s)}
		}
		rl.EndMode2D()
		cpu_draw_ms := time.duration_seconds(time.tick_since(cpu_draw_start)) * 1000
		rl.EndDrawing()
		render_metrics := rl.GetRenderMetrics()
		if benchmark_combat_render &&
		   combat_benchmark_phase < 2 &&
		   combat_benchmark_frame >= BENCHMARK_WARMUP {
			combat_metric_draws[combat_benchmark_phase] = render_metrics.draw_calls
			combat_metric_batches[combat_benchmark_phase] = render_metrics.batches
			combat_metric_uploads[combat_benchmark_phase] = render_metrics.upload_bytes
		}
		if benchmark_passage_render && passage_benchmark_frame >= BENCHMARK_WARMUP {
			passage_metric_draws = render_metrics.draw_calls
			passage_metric_batches = render_metrics.batches
			passage_metric_uploads = render_metrics.upload_bytes
		}
		if capture_fleet {
			fleet_metric_draws = render_metrics.draw_calls
			fleet_metric_batches = render_metrics.batches
			fleet_metric_uploads = render_metrics.upload_bytes
			fleet_screenshot_latency_ms = max(
				fleet_screenshot_latency_ms,
				render_metrics.screenshot_latency_ms,
			)
		}
		if shared_capture_mode {
			status := capture.step(&shared_capture)
			if status == .Complete do break
			if status == .Failed {
				fmt.eprintf("capture failed: %v\n", shared_capture.error)
				break
			}
		}
		if combat_capture_mode {
			if capture_frame == 2 do rl.TakeScreenshot(fmt.ctprintf("%s", os.args[2]))
			if capture_frame >= 14 do break
		}
		if capture_weapon_board {
			if capture_frame == 2 do rl.TakeScreenshot(fmt.ctprintf("%s", os.args[2]))
			if capture_frame >= 14 do break
		}
		if capture_direct_fire_board {
			if capture_frame == 2 do rl.TakeScreenshot(fmt.ctprintf("%s", os.args[2]))
			if capture_frame >= 14 do break
		}
		if capture_single_hull_weapon_board {
			if capture_frame == 2 do rl.TakeScreenshot(fmt.ctprintf("%s", os.args[2]))
			if capture_frame >= 14 do break
		}
		if capture_single_hull_direct_fire_board {
			if capture_frame == 2 do rl.TakeScreenshot(fmt.ctprintf("%s", os.args[2]))
			if capture_frame >= 14 do break
		}
		if capture_delta_weapon_board {
			if capture_frame == 2 do rl.TakeScreenshot(fmt.ctprintf("%s", os.args[2]))
			if capture_frame >= 14 do break
		}
		if capture_modular_fleet_weapon_board {
			if capture_frame == 2 do rl.TakeScreenshot(fmt.ctprintf("%s", os.args[2]))
			if capture_frame >= 14 do break
		}
		if capture_single_hull_strike_weapon_board {
			if capture_frame == 2 do rl.TakeScreenshot(fmt.ctprintf("%s", os.args[2]))
			if capture_frame >= 14 do break
		}
		if capture_strike_weapon_lineage_board {
			if capture_frame == 2 do rl.TakeScreenshot(fmt.ctprintf("%s", os.args[2]))
			if capture_frame >= 14 do break
		}
		if capture_strike_ordnance_multiview_board {
			if capture_frame == 2 do rl.TakeScreenshot(fmt.ctprintf("%s", os.args[2]))
			if capture_frame >= 14 do break
		}
		// Keep the legacy deterministic Passage fixture independently usable
		// while the shared capture harness is being adopted. Vulkan readback is
		// asynchronous, so request on frame two and retain twelve more presents.
		if capture_passage_stress {
			if capture_frame == 2 do rl.TakeScreenshot(fmt.ctprintf("%s", os.args[2]))
			if capture_frame >= 14 do break
		}
		wall_frame_ms := time.duration_seconds(time.tick_since(cpu_draw_start)) * 1000
		if benchmark_galaxy {
			if benchmark_phase_frame >= BENCHMARK_WARMUP {
				sample_index := benchmark_phase_frame - BENCHMARK_WARMUP
				benchmark_cpu[benchmark_phase][sample_index] = cpu_draw_ms
				if gpu_ms, available := rl.GetGpuFrameTimeMs(); available {
					gpu_index := benchmark_gpu_counts[benchmark_phase]
					benchmark_gpu[benchmark_phase][gpu_index] = gpu_ms
					benchmark_gpu_counts[benchmark_phase] += 1
				}
			}
			benchmark_phase_frame += 1
			if benchmark_phase_frame >= BENCHMARK_WARMUP + benchmark_samples {
				benchmark_phase += 1
				benchmark_phase_frame = 0
				if benchmark_phase >= len(benchmark_zooms) do break
			}
		}
		if benchmark_combat_render {
			if combat_benchmark_frame >=
			   BENCHMARK_WARMUP {sample := combat_benchmark_frame - BENCHMARK_WARMUP; combat_benchmark_cpu[combat_benchmark_phase][sample] = cpu_draw_ms + combat_3d_last_cpu_ms; if gpu_ms, available := rl.GetGpuFrameTimeMs(); available {gpu_index := combat_benchmark_gpu_counts[combat_benchmark_phase]; combat_benchmark_gpu[combat_benchmark_phase][gpu_index] = gpu_ms; combat_benchmark_gpu_counts[combat_benchmark_phase] += 1}}
			combat_benchmark_frame += 1
			if combat_benchmark_frame >=
			   BENCHMARK_WARMUP +
				   benchmark_samples {combat_benchmark_phase += 1; combat_benchmark_frame = 0; if combat_benchmark_phase >= 2 {break} else {next := game.combat_new_stress_mission(capture_campaign_seed); combat_replace_mission(s, next); s.combat.units[0].selected = true; s.combat_selected = 0; s.combat_paused = true; s.combat_last_time = rl.GetTime()}}
		}
		if benchmark_passage_render {
			if passage_benchmark_frame >=
			   BENCHMARK_WARMUP {sample := passage_benchmark_frame - BENCHMARK_WARMUP; passage_benchmark_cpu[sample] = cpu_draw_ms + combat_3d_last_cpu_ms; passage_benchmark_wall[sample] = wall_frame_ms; if gpu_ms, available := rl.GetGpuFrameTimeMs(); available {passage_benchmark_gpu[passage_benchmark_gpu_count] = gpu_ms; passage_benchmark_gpu_count += 1}}
			passage_benchmark_frame += 1
			if passage_benchmark_frame >= BENCHMARK_WARMUP + benchmark_samples do break
		}
		if benchmark_ship_gen {
			if ship_benchmark_frame >= BENCHMARK_WARMUP {
				sample := ship_benchmark_frame - BENCHMARK_WARMUP
				ship_benchmark_cpu[sample] = cpu_draw_ms
				ship_benchmark_wall[sample] = wall_frame_ms
				if gpu_ms, available := rl.GetGpuFrameTimeMs();
				   available {ship_benchmark_gpu[ship_benchmark_gpu_count] = gpu_ms; ship_benchmark_gpu_count += 1}
			}
			ship_benchmark_frame += 1
			if ship_benchmark_frame >= BENCHMARK_WARMUP + benchmark_samples do break
		}
		if benchmark_ship_hatching {
			if hatch_benchmark_frame >=
			   BENCHMARK_WARMUP {sample := hatch_benchmark_frame - BENCHMARK_WARMUP; hatch_benchmark_cpu[hatch_benchmark_phase][sample] = cpu_draw_ms; hatch_benchmark_wall[hatch_benchmark_phase][sample] = wall_frame_ms; if gpu_ms, available := rl.GetGpuFrameTimeMs(); available {index := hatch_benchmark_gpu_counts[hatch_benchmark_phase]; hatch_benchmark_gpu[hatch_benchmark_phase][index] = gpu_ms; hatch_benchmark_gpu_counts[hatch_benchmark_phase] += 1}}
			hatch_benchmark_frame += 1
			if hatch_benchmark_frame >=
			   BENCHMARK_WARMUP +
				   benchmark_samples {hatch_benchmark_phase += 1; hatch_benchmark_frame = 0; if hatch_benchmark_phase >= 4 do break}
		}
		if (benchmark_planet_detail || benchmark_star_detail) && planet_benchmark_ready {
			if planet_benchmark_frame >=
			   BENCHMARK_WARMUP {sample := planet_benchmark_frame - BENCHMARK_WARMUP; planet_benchmark_cpu[sample] = cpu_draw_ms; planet_benchmark_wall[sample] = wall_frame_ms; planet_benchmark_atmosphere[sample] = planet_detail_atmosphere_cpu_ms; if gpu_ms, available := rl.GetGpuFrameTimeMs(); available {planet_benchmark_gpu[planet_benchmark_gpu_count] = gpu_ms; planet_benchmark_gpu_count += 1}}
			planet_benchmark_frame += 1
			if planet_benchmark_frame >= BENCHMARK_WARMUP + benchmark_samples do break
		}
		capture_frame += 1
		// Vulkan screenshot delivery completes after presentation. Keep capture
		// fixtures alive long enough for the asynchronous readback to flush on
		// slower drivers instead of closing one frame after TakeScreenshot.
	}
	if benchmark_galaxy {
		fmt.print("{\"campaign_seed\":")
		fmt.printf(
			"%d,\"galaxy_seed\":%d,\"morphology\":\"%v\",\"rendered_stars\":%d",
			capture_campaign_seed,
			s.galaxy.seed,
			s.galaxy.morphology,
			galaxy_render_star_count(&s.galaxy),
		)
		fmt.println("}")
		labels := [3]string{"galaxy-wide", "galaxy-mid", "galaxy-close"}
		for phase in 0 ..< len(benchmark_zooms) {
			galaxy_benchmark_report(
				labels[phase],
				benchmark_zooms[phase],
				benchmark_cpu[phase][:benchmark_samples],
				benchmark_gpu[phase][:benchmark_gpu_counts[phase]],
			)
		}
	}
	if benchmark_combat_render {labels := [2]string{"combat-normal", "combat-stress-1000-ships"}; for phase in 0 ..< 2 do combat_render_benchmark_report(labels[phase], capture_campaign_seed, combat_benchmark_cpu[phase][:benchmark_samples], combat_benchmark_gpu[phase][:combat_benchmark_gpu_counts[phase]])}
	if benchmark_passage_render do passage_render_benchmark_report(capture_campaign_seed, passage_benchmark_cpu[:benchmark_samples], passage_benchmark_wall[:benchmark_samples], passage_benchmark_gpu[:passage_benchmark_gpu_count])
	if benchmark_combat_render {for phase in 0 ..< 2 {fmt.print("{\"scenario\":\"render2d-metrics-combat-"); fmt.printf("%d\",\"draw_calls\":%d,\"batches\":%d,\"upload_bytes\":%d", phase, combat_metric_draws[phase], combat_metric_batches[phase], combat_metric_uploads[phase]); fmt.println("}")}}
	if benchmark_passage_render {fmt.print("{\"scenario\":\"render2d-metrics-passage\","); fmt.printf("\"draw_calls\":%d,\"batches\":%d,\"upload_bytes\":%d", passage_metric_draws, passage_metric_batches, passage_metric_uploads); fmt.println("}")}
	if capture_fleet {fmt.print("{\"scenario\":\"render2d-metrics-fleet\","); fmt.printf("\"draw_calls\":%d,\"batches\":%d,\"upload_bytes\":%d,\"screenshot_latency_ms\":%.4f", fleet_metric_draws, fleet_metric_batches, fleet_metric_uploads, fleet_screenshot_latency_ms); fmt.println("}")}
	if benchmark_ship_gen do ship_generator_benchmark_report(capture_campaign_seed, ship_benchmark_family, ship_benchmark_cpu[:benchmark_samples], ship_benchmark_wall[:benchmark_samples], ship_benchmark_gpu[:ship_benchmark_gpu_count])
	if benchmark_ship_hatching {for phase in 0 ..< 4 do ship_hatch_benchmark_report(phase, ship_hatch_benchmark_label(phase), ship_hatch_benchmark_quad_count(), hatch_benchmark_cpu[phase][:benchmark_samples], hatch_benchmark_wall[phase][:benchmark_samples], hatch_benchmark_gpu[phase][:hatch_benchmark_gpu_counts[phase]])}
	if benchmark_planet_detail {planet := planet_detail_benchmark_system.planets[s.selected_body.index]; planet_detail_benchmark_report(capture_campaign_seed, planet.kind, planet_benchmark_cpu[:benchmark_samples], planet_benchmark_atmosphere[:benchmark_samples], planet_benchmark_gpu[:planet_benchmark_gpu_count]); planet_detail_benchmark_time = -1; planet_detail_benchmark_system = {}}
	if benchmark_star_detail {star_detail_benchmark_report(capture_campaign_seed, planet_detail_benchmark_system.stars[0].class, planet_benchmark_cpu[:benchmark_samples], planet_benchmark_wall[:benchmark_samples], planet_benchmark_gpu[:planet_benchmark_gpu_count]); planet_detail_benchmark_time = -1; planet_detail_benchmark_system = {}}
}
