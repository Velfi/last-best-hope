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

UX_W :: 1280
UX_H :: 720
FONT_SCALE :: 2
MAX_FONT_PAINT_SIZE :: 256

// Shared typography tokens. Text call sites use these names instead of local
// paint-size literals so the hierarchy can be tuned without hunting through
// every view. Variants preserve the established layouts while keeping each
// size attached to a semantic tier.
TYPE_MICRO_TIGHT :: 7
TYPE_MICRO :: 8
TYPE_FINE :: 9
TYPE_CAPTION :: 10
TYPE_LABEL :: 11
TYPE_SMALL :: 12
TYPE_SMALL_EMPHASIS :: 13
TYPE_BODY_COMPACT :: 14
TYPE_BODY :: 15
TYPE_BODY_EMPHASIS :: 16
TYPE_BODY_LARGE :: 17
TYPE_SUBHEADING_COMPACT :: 18
TYPE_SUBHEADING :: 19
TYPE_HEADING_COMPACT :: 20
TYPE_HEADING :: 21
TYPE_HEADING_LARGE :: 24
TYPE_TITLE_COMPACT :: 25
TYPE_TITLE :: 27
TYPE_TITLE_LARGE :: 28
TYPE_DISPLAY_COMPACT :: 30
TYPE_DISPLAY :: 32
TYPE_DISPLAY_LARGE :: 34
TYPE_HERO_COMPACT :: 38
TYPE_HERO :: 42
TYPE_HERO_LARGE :: 46
TYPE_HERO_MAX :: 52

MIN_BODY_TEXT_SIZE :: TYPE_SMALL

// Row-major meanings in assets/icons/ui-icon-atlas-garden.png. Keep UI call
// sites semantic: sharing a glyph should be a deliberate visual relationship.
ICON_SEED :: 0
ICON_MATERIALS :: 1
ICON_CHRONICLE :: 2
ICON_FLEET :: 3
ICON_STORY :: 4
ICON_COUNCIL :: 5
ICON_PROPELLANT :: 6
ICON_CARGO :: 7
ICON_SECURE :: 8
ICON_COMPUTE :: 9
ICON_RANK :: 10
ICON_CONTAINER :: 11
ICON_HOME :: 12
ICON_GALAXY :: 13
ICON_COMMISSION :: 14
ICON_DEPART :: 15
ICON_RETURN :: 16
ICON_ESCAPE :: 17
ICON_SURVEY :: 18
ICON_ARCHIVE :: 19
ICON_REPAIR :: 20
ICON_HOSPITAL :: 21
ICON_ESCORT :: 22
ICON_AGRICULTURE :: 23
ICON_DIALOGUE :: 24
ICON_LIFE_SUPPORT :: 25
ICON_SCANNER :: 26
ICON_WORLD_SEARCH :: 27
ICON_SETTLEMENT :: 28
ICON_HARBOR :: 29
ICON_ACCORD :: 30
ICON_INSTITUTION :: 31
ICON_MEMORY :: 32
ICON_DAMAGE :: 33
ICON_WARNING :: 34
ICON_LOCKED :: 35

Ux_Screen :: enum {
	Menu,
	Skirmish_Setup,
	Operation_Planning,
	Deep_Exploration_Setup,
	Setup,
	Fleet,
	Navigation,
	Story,
	Care,
	Galaxy,
	Chronicle,
	Build,
	Briefing,
	Passage,
	Debrief,
	Settlement_Proposal,
	Interaction,
	Guidebook,
	Settings,
	Credits,
	Ending,
	Combat,
	Far_Engagement,
	Ship_Generator,
}

hatch_density_spacing_scale :: proc(density: f32) -> f32 {
	return 1 / clamp(density, f32(.5), f32(2))
}

@(test)
hatch_density_range_maps_to_inverse_spacing :: proc(t: ^testing.T) {
	testing.expect_value(t, hatch_density_spacing_scale(.5), f32(2))
	testing.expect_value(t, hatch_density_spacing_scale(1), f32(1))
	testing.expect_value(t, hatch_density_spacing_scale(2), f32(.5))
}
Ux_Modal :: enum {
	None,
	Body_Detail,
	Ship_Detail,
	Food_Shortage,
	Economy_Loss,
	Stranded_Outcome,
	Habitable_Discovery,
	Opening_Note,
	Advance,
	Conclude,
	Departure,
	Return,
	Extraction,
	Settlement,
	Abandon_Cargo,
	Project,
	Result,
}

Dark_Ui_Selection_Kind :: enum {
	None,
	Door,
	Tracked_Contact,
}

Ux_State :: struct {
	screen:                                                      Ux_Screen,
	return_screen:                                               Ux_Screen,
	// Keep an in-campaign detail route separate from the main-menu return
	// target, so a Chronicle link can return to the page that opened it.
	navigation_return_screen:                                    Ux_Screen,
	pause_return_screen:                                         Ux_Screen,
	pause_menu_open, settings_from_pause:                        bool,
	modal:                                                       Ux_Modal,
	campaign:                                                    ^game.Campaign,
	setup:                                                       game.Civilization_Setup_Draft,
	skirmish_setup:                                              game.Skirmish_Setup,
	combat_operation:                                            game.Combat_Operation,
	combat_planning_undo, combat_planning_redo:                  [dynamic]game.Combat_Operation_Plan,
	combat_planning_tab, combat_planning_group:                  int,
	combat_planning_route_kind:                                  int,
	combat_planning_drag_waypoint:                               int,
	combat_planning_confirm_regenerate:                          bool,
	combat_planning_renaming:                                    bool,
	deep_exploration_setup:                                      game.Deep_Exploration_Setup,
	deep_exploration_story_campaign:                             ^game.Campaign,
	deep_exploration_active, deep_exploration_story_loaded:      bool,
	deep_exploration_story_available:                            bool,
	far_engagement_story_campaign:                               ^game.Campaign,
	far_engagement_standalone, far_engagement_story_available:   bool,
	contract:                                                    game.Dark_Contract,
	dark_strategy:                                               game.Dark_Strategy_Profile,
	setup_step:                                                  int,
	selected_ship, selected_node, selected_need, selected_event: int,
	fleet_scroll:                                                f32,
	fleet_scroll_dragging:                                       bool,
	guide_family:                                                game.Ship_Family,
	guide_role:                                                  game.Ship_Operational_Role,
	guide_tactics:                                               bool,
	passage_ships:                                               [game.MAX_SHIPS]bool,
	combat_deployment_groups:                                    [game.MAX_SHIPS]int,
	show_details:                                                bool,
	guide_dismissed:                                             bool,
	opening_note_ready:                                          bool,
	opening_note_population:                                     i32,
	opening_note_habitable_worlds, opening_note_planet_systems:  f64,
	last_action:                                                 string,
	pending_project:                                             game.Project_Kind,
	ui_scale:                                                    f32,
	hatch_density:                                               f32,
	reduced_motion:                                              bool,
	screen_effect:                                               rl.Screen_Effect,
	status:                                                      string,
	ship_generator_seed:                                         u64,
	ship_generator_family:                                       game.Procedural_Ship_Family,
	ship_generator_recipe:                                       game.Procedural_Ship_Recipe,
	ship_generator_camera:                                       Ship_Generator_Camera,
	ship_detail_camera:                                          Ship_Generator_Camera,
	ship_generator_ready:                                        bool,
	has_campaign:                                                bool,
	galaxy:                                                      game.Galaxy,
	galaxy_ready:                                                bool,
	galaxy_star_cache_seed:                                      u64,
	galaxy_star_cache_count:                                     int,
	galaxy_star_cache:                                           [dynamic]Galaxy_Render_Star,
	galaxy_zoom:                                                 f64,
	galaxy_pan_x, galaxy_pan_y:                                  f64,
	dark_zoom:                                                   f64,
	dark_pan_u, dark_pan_v:                                      f64,
	dark_last_time:                                              f64,
	campaign_last_time:                                          f64,
	dark_orientation:                                            Combat_Quat,
	dark_fleet_facing, dark_fleet_pitch:                         f32,
	dark_fleet_heading_time:                                     f64,
	dark_fleet_heading_ready:                                    bool,
	dark_fleet_power, dark_fleet_power_command:                  f32,
	dark_fleet_power_time:                                       f64,
	dark_waypoint_z, dark_waypoint_w:                            f64,
	dark_course_draft:                                           game.Dark_Course,
	dark_selection_kind:                                         Dark_Ui_Selection_Kind,
	dark_selection_id:                                           u64,
	dark_contacts_open, dark_comms_open, dark_missing_confirm:   bool,
	dark_show_membrane_time:                                     bool,
	dark_exit_confirm:                                           bool,
	dark_intent_open, dark_fine_plot_open:                       bool,
	dark_course_why_open, dark_contact_why_open:                 bool,
	combat_deployment_why_open:                                  bool,
	selected_neighborhood:                                       int,
	galaxy_contact_page:                                         int,
	selected_system_detail:                                      int,
	selected_body:                                               game.Celestial_Body_Ref,
	navigation_target:                                           game.Celestial_Body_Ref,
	navigation_arrival_days:                                     f64,
	navigation_harvest_fraction:                                 f64,
	navigation_harvest_deadline_days:                            f64,
	chronicle_filter:                                            int,
	chronicle_view:                                              int,
	combat:                                                      game.Combat_Mission,
	combat_campaign_active:                                      bool,
	combat_fire_control_preference:                              game.Combat_Fire_Control,
	combat_selected:                                             int,
	combat_altitude:                                             f32,
	combat_group_scroll, combat_briefing_group_scroll:           f32,
	combat_order_armed, combat_paused, combat_briefing:          bool,
	combat_show_mission_time:                                    bool,
	combat_ability_armed:                                        bool,
	combat_order_drag_active:                                    bool,
	combat_order_kind:                                           game.Combat_Order,
	combat_order_drag_world:                                     game.Combat_Vec3,
	combat_order_drag_start:                                     rl.Vector2,
	combat_order_drag_altitude:                                  f32,
	combat_speed:                                                f32,
	combat_last_time:                                            f64,
	combat_pan_x, combat_pan_y, combat_zoom:                     f32,
	combat_orientation:                                          Combat_Quat,
	combat_drag_start:                                           rl.Vector2,
	combat_drag_active:                                          bool,
	combat_pan_active:                                           bool,
	combat_orbit_drag_start:                                     rl.Vector2,
	combat_orbit_drag_active, combat_orbit_drag_moved:           bool,
	combat_chatter_source, combat_chatter_text:                  string,
	combat_chatter_timer:                                        f32,
	combat_last_actions:                                         [dynamic]game.Combat_Action,
	far_speed:                                                   f64,
	far_last_time:                                               f64,
	far_selected_group, far_selected_contact:                    int,
	far_last_saved_record_count:                                 int,
	far_paused:                                                  bool,
	far_plot_pan_x, far_plot_pan_y, far_plot_zoom:               f32,
}

navigation_return_label :: proc(screen: Ux_Screen) -> string {
	#partial switch screen {
	case .Care:
		return "← COMPACT"
	case .Interaction:
		return "← DECISION"
	case .Navigation:
		return "← NAVIGATION"
	case .Passage:
		return "← PASSAGE"
	case .Ending:
		return "← ENDING"
	case:
		return "← FLEET"
	}
}

open_chronicle_from :: proc(s: ^Ux_State, origin: Ux_Screen) {
	s.navigation_return_screen = origin
	s.screen = .Chronicle
}

close_chronicle :: proc(s: ^Ux_State) {
	destination := s.navigation_return_screen
	if destination == .Chronicle || destination == .Menu do destination = .Fleet
	s.screen = destination
	s.navigation_return_screen = .Fleet
}

@(test)
chronicle_returns_to_its_opening_context :: proc(t: ^testing.T) {
	s := Ux_State{screen = .Interaction, navigation_return_screen = .Fleet}
	open_chronicle_from(&s, s.screen)
	testing.expect_value(t, s.screen, Ux_Screen.Chronicle)
	testing.expect_value(t, s.navigation_return_screen, Ux_Screen.Interaction)
	close_chronicle(&s)
	testing.expect_value(t, s.screen, Ux_Screen.Interaction)
	testing.expect_value(t, s.navigation_return_screen, Ux_Screen.Fleet)
}

// Campaign owns several intentionally heap-backed collections of its own, but
// the outer value is also large. Keep both live UI campaigns behind pointers
// so adding bounded simulation state cannot silently inflate every Ux_State.
ux_state_create :: proc() -> ^Ux_State {
	s := new(Ux_State)
	s.campaign = new(game.Campaign)
	return s
}

ux_state_destroy :: proc(s: ^Ux_State) {
	if s == nil do return
	game.campaign_destroy_heap(s.campaign)
	game.campaign_destroy_heap(s.deep_exploration_story_campaign)
	game.campaign_destroy_heap(s.far_engagement_story_campaign)
	delete(s.combat_planning_undo)
	delete(s.combat_planning_redo)
	free(s)
}

UX_STATE_SIZE_LIMIT :: 256 * 1024

@(test)
ux_state_keeps_campaigns_out_of_line :: proc(t: ^testing.T) {
	live: ^game.Campaign = Ux_State{}.campaign
	parked: ^game.Campaign = Ux_State{}.deep_exploration_story_campaign
	_ = live
	_ = parked
	testing.expect(t, size_of(Ux_State) < UX_STATE_SIZE_LIMIT)
}

Ux_Colors :: struct {
	void, panel, raised, line, text, dim, info, good, warn, bad, committed, unavailable: rl.Color,
}
UX := Ux_Colors {
	void        = {3, 3, 3, 255},
	panel       = {9, 9, 8, 246},
	raised      = {18, 18, 16, 255},
	line        = {72, 72, 67, 255},
	text        = {226, 224, 212, 255},
	dim         = {139, 138, 130, 255},
	info        = {126, 190, 198, 255},
	good        = {136, 190, 123, 255},
	warn        = {224, 176, 67, 255},
	bad         = {211, 91, 68, 255},
	committed   = {183, 132, 207, 255},
	unavailable = {69, 69, 65, 255},
}

ux_linear_channel :: proc(channel: u8) -> f64 {
	value := f64(channel) / 255
	return value <= .04045 ? value / 12.92 : math.pow((value + .055) / 1.055, 2.4)
}

ux_relative_luminance :: proc(color: rl.Color) -> f64 {
	return(
		.2126 * ux_linear_channel(color.r) +
		.7152 * ux_linear_channel(color.g) +
		.0722 * ux_linear_channel(color.b) \
	)
}

ux_contrast_ratio :: proc(foreground, background: rl.Color) -> f64 {
	foreground_luminance := ux_relative_luminance(foreground)
	background_luminance := ux_relative_luminance(background)
	return(
		(max(foreground_luminance, background_luminance) + .05) /
		(min(foreground_luminance, background_luminance) + .05) \
	)
}

@(test)
enabled_text_palette_meets_normal_text_contrast :: proc(t: ^testing.T) {
	backgrounds := [3]rl.Color{UX.void, UX.panel, UX.raised}
	foregrounds := [7]rl.Color{UX.text, UX.dim, UX.info, UX.good, UX.warn, UX.bad, UX.committed}
	for background in backgrounds do for foreground in foregrounds do testing.expect(t, ux_contrast_ratio(foreground, background) >= 4.5)
}

ux_fonts: [MAX_FONT_PAINT_SIZE + 1]rl.Font
ux_fonts_loaded: [MAX_FONT_PAINT_SIZE + 1]bool
ux_mouse: rl.Vector2
ux_origin: rl.Vector2
ux_zoom: f32
ux_text_scale: f32 = 1
ux_button_cursor: int
ux_focus_back_requested: bool
// A modal is rendered after its parent screen, but it owns pointer input for
// the whole frame so clicks cannot activate controls visible behind it.
ux_pointer_input_blocked: bool

Ship_Render_Recipe :: struct {
	core,
	nose,
	engine,
	wing,
	utility,
	role_module,
	wing_stance,
	wing_sweep,
	keel_profile,
	drive_layout,
	drive_setback,
	bow_profile,
	mission_profile: int,
	damage,
	livery,
	community_marking,
	registry_marking,
	service_marking,
	role_marking,
	trait_marking,
	history_marking,
	effect:                       int,
}

ship_component_texture, ship_map_component_texture, ship_damage_texture, ship_effect_texture, ship_marking_texture, combat_archetype_icon_texture, combat_depth_plane_texture: rl.Texture
