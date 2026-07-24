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

ux_save :: proc(s: ^Ux_State, autosave := true) -> bool {
	data := game.campaign_serialize(s.campaign); if data == nil do return false; defer delete(data)
	path, ok := ux_save_path(autosave); if !ok do return false
	return os.write_entire_file(path, data[:]) == nil
}

ux_load :: proc(s: ^Ux_State) -> bool {
	path, path_ok := ux_save_path(
		true,
	); if !path_ok do return false; data, err := os.read_entire_file_from_path(path, context.temp_allocator); if err != nil do return false
	game.campaign_destroy(s.campaign)
	decoded := game.campaign_deserialize(
		data,
		s.campaign,
	); if !decoded.ok {s.status = decoded.message; return false}
	s.has_campaign = true
	s.galaxy_ready = false
	s.screen =
		s.campaign.far_engagement != nil && s.campaign.far_engagement.active && !s.campaign.far_engagement.complete ? .Far_Engagement : s.campaign.passage.active ? .Passage : .Fleet
	s.status = "AUTOSAVE RESTORED"
	return true
}

autosave_before :: proc(s: ^Ux_State) {if s.has_campaign && !ux_save(s, true) do s.status = "AUTOSAVE FAILED"}

execute_command :: proc(s: ^Ux_State, command: game.Game_Command) -> game.Game_Command_Result {
	r := game.execute_command(s.campaign, command)
	if r.ok && !ux_save(s, true) do s.status = "AUTOSAVE FAILED"
	return r
}

draw_stars :: proc() {
	for i in 0 ..< 96 {
		x := f32((i * 97 + 31) % UX_W)
		y := f32((i * 53 + 11) % UX_H)
		a := u8(28 + (i * 19) % 68)
		rl.DrawCircleV(V(x, y), i % 7 == 0 ? 1.2 : .6, {220, 218, 205, a})
		if i % 19 == 0 do rl.DrawLineEx(V(x - 5, y), V(x + 5, y), .5, {220, 218, 205, a})
	}
}

draw_menu_galaxy :: proc(s: ^Ux_State) {
	center := V(872, 350)
	// This is a deliberately small catalogue, but it uses the same seeded
	// morphology, spiral sampling, and projection as the navigable galaxy map.
	// Keep it local: opening the menu should not build the 60,000-mark map.
	g := game.Galaxy {
		seed                 = 0x6c6173745f686f70,
		morphology           = .Spiral,
		disk_radius_kpc      = 18,
		scale_height_kpc     = .42,
		bulge_fraction       = .16,
		spiral_arm_count     = 3,
		spiral_pitch_degrees = 18,
	}
	// The exponential catalogue concentrates most visible marks well inside the
	// formal disk radius. This larger plate scale makes that apparent body fill
	// the same broad menu footprint as the removed hatched background.
	scale := f64(51)
	axis_tilt := f64(-.22)
	tilt_cos, tilt_sin := math.cos(axis_tilt), math.sin(axis_tilt)

	// Keep the camera fixed and rotate the actual three-dimensional catalogue in
	// its own plane. Seeded disk height gives the inclined plate real parallax.
	rotation := s.reduced_motion ? f64(0) : rl.GetTime() * .006
	for i in 0 ..< 9920 {
		radius := galaxy_sample_tapered_exponential_disk(
			&g,
			i,
			g.disk_radius_kpc * .34,
			g.disk_radius_kpc,
		)
		theta := galaxy_sample_spiral_theta(&g, i, radius) + rotation
		x, y := radius * math.cos(theta), radius * math.sin(theta)
		z := galaxy_sample_disk_height(galaxy_star_unit(g.seed, i, 314), g.scale_height_kpc)
		projected_x, projected_y := galaxy_project_world_xyz(&g, x, y, z)
		// Rotate the projected plate as a single object so its long axis echoes the
		// old menu composition without retaining the separate background ellipse.
		tilted_x := projected_x * tilt_cos - projected_y * tilt_sin
		tilted_y := projected_x * tilt_sin + projected_y * tilt_cos
		p := V(center.x + f32(tilted_x * scale), center.y + f32(tilted_y * scale))
		brightness := galaxy_star_unit(g.seed, i, 207)
		alpha := u8(22 + int(brightness * 78))
		size := brightness > .965 ? f32(1.35) : brightness > .78 ? f32(.75) : f32(.42)
		rl.DrawCircleV(p, size, {224, 222, 209, alpha})
		if i % 79 == 0 {
			tangent :=
				galaxy_projected_spiral_tangent_angle(
					&g,
					galaxy_nearest_spiral_arm(&g, radius, theta - rotation),
					radius,
				) +
				rotation +
				axis_tilt
			d := V(f32(math.cos(tangent) * 3), f32(math.sin(tangent) * 3))
			rl.DrawLineEx(
				V(p.x - d.x, p.y - d.y),
				V(p.x + d.x, p.y + d.y),
				.55,
				{224, 222, 209, u8(min(int(alpha) + 18, 255))},
			)
		}
	}
	rl.DrawCircleV(center, 2.4, {232, 228, 210, 128})
}

capacity_indicator :: proc(x: f32, icon: int, label, state: string) {
	rl.DrawIcon(
		icon,
		R(x, 13, 27, 27),
	); draw_text(label, x + 33, 10, TYPE_FINE, UX.dim); draw_text(state, x + 33, 24, TYPE_SMALL, state == "AVAILABLE" ? UX.good : state == "STRAINED" ? UX.warn : UX.bad)
}

top_rail :: proc(s: ^Ux_State) {
	rl.DrawRectangle(0, 0, UX_W, 54, {5, 5, 4, 250}); divider(0, 54, UX_W)
	rl.DrawRectangle(0, 52, UX_W, 2, UX.text)
	if rail_menu_button(R(16, 10, 34, 34)) {
		s.return_screen = s.screen
		s.screen = .Menu
	}
	if s.has_campaign && s.screen != .Fleet {
		if rail_icon_button(R(56, 10, 34, 34), ICON_RETURN, "RETURN TO FLEET", "Return to the fleet overview.") do s.screen = .Fleet
	}
	draw_text("LAST BEST HOPE", 104, 17, TYPE_BODY_EMPHASIS, UX.text)
	mode :=
		s.campaign.passage.active ? "PASSAGE" : "FLEET"; draw_text(mode, 246, 19, TYPE_LABEL, s.campaign.passage.active ? UX.warn : UX.info)
	draw_fmt(310, 19, TYPE_LABEL, UX.dim, "Y%d · S%d", s.campaign.year, s.campaign.season)
	if s.has_campaign {
		stock_labels := [7]string {
			"FOOD",
			"RAW MATERIALS",
			"MANUFACTURED GOODS",
			"EQUIPMENT",
			"PROPELLANT",
			"SUPPLIES",
			"SERVICES",
		}
		stock_icons := [7]int {
			ICON_AGRICULTURE,
			ICON_MATERIALS,
			ICON_CONTAINER,
			ICON_REPAIR,
			ICON_PROPELLANT,
			ICON_CARGO,
			ICON_HOSPITAL,
		}
		x: f32 = 380
		for label, i in stock_labels {
			draw_fleet_resource_cell(s, R(x, 4, 70, 46), i, label, stock_icons[i])
			x += 70
		}
		rl.DrawLineEx(V(x + 4, 8), V(x + 4, 46), 1, UX.line)
		x += 12
		c := s.campaign.capacities
		draw_capacity_cell(R(x, 4, 88, 46), "COMPUTE CAPACITY", ICON_COMPUTE, c.compute); x += 88
		draw_capacity_cell(R(x, 4, 88, 46), "MANPOWER CAPACITY", ICON_COUNCIL, c.manpower); x += 88
		draw_capacity_cell(R(x, 4, 88, 46), "MATERIAL CAPACITY", ICON_MATERIALS, c.raw_materials)
	}
}

bottom_rail :: proc(
	s: ^Ux_State,
	objective: string,
	action: string = "",
	enabled := false,
	automatic_route := true,
	pulse := false,
) -> bool {
	rl.DrawRectangle(
		0,
		664,
		UX_W,
		56,
		{5, 5, 4, 252},
	); divider(0, 664, UX_W); label_caps("CURRENT DIRECTIVE", 20, 675); draw_text(objective, 20, 693, TYPE_BODY)
	action_rect := R(1030, 674, 228, 36)
	activated := action != "" && button(action_rect, action, enabled, true)
	if pulse && action != "" && enabled {
		wave := s.reduced_motion ? f32(1) : f32(.5 + .5 * math.sin(rl.GetTime() * 2.4))
		alpha := u8(90 + 105 * wave)
		color := rl.Color{UX.info.r, UX.info.g, UX.info.b, alpha}
		outer := R(
			action_rect.x - 4,
			action_rect.y - 4,
			action_rect.width + 8,
			action_rect.height + 8,
		)
		rl.DrawRectangleRoundedLinesEx(outer, 0, 1, 1, color)
		// Cropped corner strokes keep the emphasis in the archival plate language.
		rl.DrawLineEx(V(outer.x, outer.y), V(outer.x + 18, outer.y), 2, color)
		rl.DrawLineEx(V(outer.x, outer.y), V(outer.x, outer.y + 10), 2, color)
		rl.DrawLineEx(
			V(outer.x + outer.width - 18, outer.y + outer.height),
			V(outer.x + outer.width, outer.y + outer.height),
			2,
			color,
		)
		rl.DrawLineEx(
			V(outer.x + outer.width, outer.y + outer.height - 10),
			V(outer.x + outer.width, outer.y + outer.height),
			2,
			color,
		)
	}
	if activated && automatic_route do s.modal = s.screen == .Briefing ? .Departure : s.screen == .Fleet ? .Advance : .None
	draw_text(
		"TAB focus  ·  ESC focus back  ·  ENTER confirm",
		620,
		689,
		TYPE_SMALL_EMPHASIS,
		UX.dim,
	)
	return activated
}

draw_menu :: proc(s: ^Ux_State) {
	draw_menu_galaxy(
		s,
	); draw_text("LAST BEST HOPE", 92, 108, TYPE_HERO, UX.text); draw_text("A COMMAND CHRONICLE OF THE DIASPORA", 95, 164, TYPE_BODY, UX.info)
	draw_text(
		"Guide a refugee fleet through generations of irreversible choices.",
		95,
		211,
		TYPE_BODY_EMPHASIS,
		UX.dim,
	)
	items := [10]string {
		"CONTINUE",
		"NEW CHRONICLE",
		"SKIRMISH",
		"FAR ENGAGEMENT",
		"DEEP EXPLORATION",
		"LOAD CHRONICLE",
		"SHIP GUIDEBOOK",
		"SETTINGS",
		"CREDITS",
		"QUIT",
	}
	for item, i in items {enabled := item != "CONTINUE" || s.has_campaign || ux_autosave_exists()
		if button(R(95, 235 + f32(i) * 40, 310, 36), item, enabled, i == 0) {switch i {case 0:
				if s.has_campaign {s.screen = s.return_screen} else {_ = ux_load(s)}; case 1:
				s.setup = game.civilization_setup_generate(
					u64(rl.GetTime() * 1000000) + 1,
					.Standard,
				)
				s.setup_step = 0
				s.screen = .Setup; case 2:
				s.skirmish_setup = game.skirmish_default_setup()
				s.screen = .Skirmish_Setup; case 3:
				launch_standalone_far_engagement(s)
			case 4:
				s.deep_exploration_setup = game.deep_exploration_default_setup()
				s.screen = .Deep_Exploration_Setup; case 5:
				_ = ux_load(s); case 6:
				s.return_screen = .Menu; s.screen = .Guidebook; case 7:
				s.return_screen = .Menu; s.screen = .Settings; case 8:
				s.screen = .Credits; case 9:
				_ = ux_save(s, true); rl.CloseWindow(); os.exit(0)}}}
	if s.has_campaign {
		panel(
			R(790, 105, 390, 490),
		); label_caps("CHRONICLE STATUS", 820, 137); divider(820, 160, 330)
		draw_fmt(
			820,
			190,
			TYPE_BODY,
			UX.dim,
			"%v · YEAR %d · SEASON %d",
			s.campaign.length,
			s.campaign.year,
			s.campaign.season,
		)
		draw_fmt(
			820,
			235,
			TYPE_BODY,
			UX.text,
			"%d SHIPS · %d PEOPLE",
			s.campaign.ship_count,
			game.total_population(s.campaign),
		)
		draw_text(
			s.campaign.passage.active ? "EXPEDITION IN PROGRESS" : "FLEET AWAITING ORDERS",
			820,
			280,
			TYPE_BODY,
			s.campaign.passage.active ? UX.warn : UX.good,
		)
	}
	if s.status != "" do draw_text(s.status, 95, 620, TYPE_SMALL_EMPHASIS, UX.warn)
}

draw_pause_menu :: proc(s: ^Ux_State) {
	draw_stars()
	rl.DrawRectangle(0, 0, UX_W, UX_H, {0, 0, 0, 190})
	panel(R(430, 92, 420, 536), true)
	label_caps("CHRONICLE PAUSED", 470, 126, UX.info)
	draw_text("COMMAND MENU", 470, 158, TYPE_TITLE_LARGE, UX.text)
	divider(470, 202, 340)
	items := [6]string{"RESUME", "OPTIONS", "SAVE", "LOAD", "MAIN MENU", "QUIT"}
	for item, i in items {
		enabled := (i != 2 && i != 3) || (s.has_campaign && !s.deep_exploration_active)
		if button(R(470, 232 + f32(i) * 58, 340, 42), item, enabled, i == 0) {
			switch i {
			case 0:
				s.pause_menu_open = false
				s.combat_last_time = rl.GetTime()
			case 1:
				s.settings_from_pause = true
				s.return_screen = s.pause_return_screen
				s.screen = .Settings
				s.pause_menu_open = false
			case 2:
				s.status = ux_save(s, true) ? "CHRONICLE SAVED" : "SAVE FAILED"
			case 3:
				if ux_load(s) {
					s.pause_menu_open = false
					s.combat_last_time = rl.GetTime()
					s.pause_return_screen = s.screen
				} else {
					s.status = "LOAD FAILED"
				}
			case 4:
				if !s.deep_exploration_active && s.has_campaign && !ux_save(s, true) do s.status = "AUTOSAVE FAILED"
				s.screen = .Menu
				s.return_screen = s.pause_return_screen
				s.pause_menu_open = false
			case 5:
				if !s.deep_exploration_active do _ = ux_save(s, true)
				rl.CloseWindow()
				os.exit(0)
			}
		}
	}
	if s.status != "" do draw_text(s.status, 470, 586, TYPE_SMALL_EMPHASIS, UX.warn)
	draw_text("ESC resume", 708, 602, TYPE_SMALL, UX.dim)
}

setup_step_name :: proc(step: int) -> string {names := [4]string {
		"EXPERIENCE",
		"PEOPLE",
		"FOUNDING",
		"REVIEW",
	}
	return names[clamp(step, 0, 3)]}

found_chronicle :: proc(s: ^Ux_State) -> bool {
	game.campaign_destroy(s.campaign)
	ok, msg := game.civilization_setup_commit(&s.setup, s.campaign)
	s.status = msg
	if !ok do return false
	s.has_campaign = true
	s.galaxy_ready = false
	s.modal = .Opening_Note
	_ = ux_save(s, true)
	s.screen = .Fleet
	return true
}

draw_setup :: proc(s: ^Ux_State) {
	top_rail(
		s,
	); draw_text("FOUND A CHRONICLE", 30, 79, TYPE_TITLE); draw_fmt(30, 117, TYPE_SMALL_EMPHASIS, UX.info, "STEP %d OF 4  ·  %s", s.setup_step + 1, setup_step_name(s.setup_step)); setup_labels := [4]string{"EXPERIENCE", "PEOPLE", "FOUNDING", "REVIEW"}; progress_steps(setup_labels[:], s.setup_step, 650, 92, 560)
	panel(R(28, 151, 1224, 485))
	switch s.setup_step {
	case 0:
		draw_text("What kind of chronicle do you want?", 62, 178, TYPE_HEADING_COMPACT)
		label_caps("CHRONICLE LENGTH", 62, 214, UX.committed)
		length_names := [4]string {
			"SHORT · ~3 HOURS",
			"STANDARD · ~6 HOURS",
			"LONG · ~12 HOURS",
			"ENDLESS · OPEN",
		}
		for name, i in length_names {if radio_button(R(62 + f32(i) * 258, 232, 244, 34), name, int(s.setup.length) == i) do s.setup.length = game.Chronicle_Length(i)}
		label_caps("STORY TEMPO", 62, 284, UX.committed)
		for item, i in game.STORY_TEMPO_NAMES {if radio_button(R(62 + f32(i) * 190, 302, 176, 34), item, int(s.setup.story_tempo) == i) do s.setup.story_tempo = game.Story_Tempo(i)}
		draw_text_fitted(
			game.STORY_TEMPO_DESCRIPTIONS[int(s.setup.story_tempo)],
			R(650, 303, 550, 30),
			TYPE_SMALL,
			UX.dim,
		)
		label_caps("MATERIAL PRESSURE", 62, 358, UX.committed)
		pressure_names := [3]string{"GENTLE", "STANDARD", "SEVERE"}
		for name, i in pressure_names {if radio_button(R(62 + f32(i) * 150, 376, 138, 34), name, int(s.setup.material_pressure) == i) do s.setup.material_pressure = game.Material_Pressure(i)}
		label_caps("CONSEQUENCE SEVERITY", 570, 358, UX.committed)
		for name, i in pressure_names {if radio_button(R(570 + f32(i) * 150, 376, 138, 34), name, int(s.setup.consequence_severity) == i) do s.setup.consequence_severity = game.Consequence_Severity(i)}
		label_caps("CLOSE ENGAGEMENT STYLE", 62, 438, UX.committed)
		for item, i in game.RULESET_PRESET_NAMES {if radio_button(R(62 + f32(i) * 192, 456, 180, 34), item, int(s.setup.ruleset.preset) == i) do game.ruleset_apply_preset(&s.setup, game.Ruleset_Preset(i))}
		label_caps(
			"CUSTOM HEROISM",
			850,
			438,
			UX.dim,
		); draw_fmt(850, 463, TYPE_BODY_EMPHASIS, UX.text, "%d : 1", s.setup.ruleset.heroism_scale)
		if button(R(950, 456, 50, 34), "−10", s.setup.ruleset.heroism_scale > 1) do game.ruleset_set_heroism(&s.setup, s.setup.ruleset.heroism_scale - 10)
		if button(R(1008, 456, 44, 34), "−1", s.setup.ruleset.heroism_scale > 1) do game.ruleset_set_heroism(&s.setup, s.setup.ruleset.heroism_scale - 1)
		if button(R(1060, 456, 44, 34), "+1", s.setup.ruleset.heroism_scale < 1000) do game.ruleset_set_heroism(&s.setup, s.setup.ruleset.heroism_scale + 1)
		if button(R(1112, 456, 50, 34), "+10", s.setup.ruleset.heroism_scale < 1000) do game.ruleset_set_heroism(&s.setup, s.setup.ruleset.heroism_scale + 10)
		preset_index := int(
			s.setup.ruleset.preset,
		); description := fmt.tprintf("One player ship is expected to match about %d equivalent enemy ships.", s.setup.ruleset.heroism_scale); if preset_index >= 0 && preset_index < len(game.RULESET_PRESET_DESCRIPTIONS) do description = game.RULESET_PRESET_DESCRIPTIONS[preset_index]
		draw_text_fitted(description, R(62, 505, 1100, 24), TYPE_SMALL, UX.dim)
		if button(R(750, 574, 300, 36), "REVIEW GENERATED CHRONICLE") do s.setup_step = 3
	case 1:
		for i in 0 ..< 6 {y := 184 + f32(i) * 62; kind := i < 2 ? "IDENTITY" : i < 4 ? "CAPABILITY" : "VALUE"
			label_caps(kind, 62, y)
			choice := s.setup.choices[i]
			tooltip_term(
				game.setup_attribute_name(&s.setup, i),
				game.setup_attribute_description(&s.setup, i),
				190,
				y - 7,
				TYPE_BODY_LARGE,
				UX.text,
			)
			draw_text(game.setup_attribute_effect(&s.setup, i), 190, y + 17, TYPE_SMALL, UX.info)
			if checkbox(R(850, y - 11, 100, 34), "LOCK", s.setup.locked[i]) do s.setup.locked[i] = !s.setup.locked[i]
			if button(R(960, y - 11, 110, 34), "REROLL", !s.setup.locked[i]) do game.civilization_setup_reroll_field(&s.setup, game.Setup_Field(i))}
		if button(R(1090, 173, 120, 36), "ROLL ALL") do game.civilization_setup_reroll(&s.setup)
		label_caps("FOUNDING ATTRIBUTES SHAPE THE GENERATED FLEET", 190, 552, UX.committed)
	case 2:
		draw_text(
			"What happened, what survived, and what rule followed?",
			62,
			178,
			TYPE_HEADING_COMPACT,
		)
		label_caps("PUBLIC ACCOUNT OF THE LOSS", 62, 218, UX.committed)
		for i := 0;
		    i < len(game.LOSS_NAMES);
		    i += 1 {item := game.LOSS_NAMES[i]; if radio_button(R(62, 238 + f32(i) * 47, 340, 36), item, s.setup.loss_index == i) do s.setup.loss_index = i}
		label_caps("PRESERVED INHERITANCE", 454, 218, UX.good)
		for i := 0; i < len(game.PRESERVED_NAMES); i += 1 {item := game.PRESERVED_NAMES[i]
			if radio_button(R(454, 238 + f32(i) * 47, 340, 36), item, s.setup.preserved_index == i) do s.setup.preserved_index = i}
		a, b := game.setup_value_kind(&s.setup, 0), game.setup_value_kind(&s.setup, 1)
		scenario := game.founding_value_scenario(a, b)
		label_caps("FOUNDING TEST", 846, 218, UX.committed)
		draw_text_fitted(scenario.title, R(846, 238, 340, 28), TYPE_BODY_COMPACT, UX.text)
		options := [3]string {
			game.founding_value_option(a),
			game.founding_value_option(b),
			"REFER TO THE FIRST COUNCIL",
		}
		for i := 0;
		    i < len(options);
		    i += 1 {item := options[i]; if radio_button(R(846, 272 + f32(i) * 48, 340, 42), item, s.setup.founding_choice == i) do s.setup.founding_choice = i}
		loss_preview := game.setup_choice_preview(&s.setup, 2)
		inheritance_preview := game.setup_choice_preview(&s.setup, 3)
		precedent_preview := game.setup_choice_preview(&s.setup, 4)
		divider(62, 445, 1124)
		label_caps(loss_preview.classification, 62, 462, UX.committed)
		draw_text_fitted(
			game.LOSS_RECORDS[s.setup.loss_index],
			R(62, 482, 340, 36),
			TYPE_SMALL,
			UX.text,
		)
		label_caps(inheritance_preview.classification, 454, 462, UX.good)
		draw_text_wrapped(inheritance_preview.effect, R(454, 482, 340, 38), TYPE_SMALL, UX.text)
		label_caps(precedent_preview.classification, 846, 462, UX.committed)
		draw_text_wrapped(
			fmt.tprintf("%s %s", scenario.premise, precedent_preview.effect),
			R(846, 482, 340, 54),
			TYPE_SMALL,
			UX.text,
		)
	case 3:
		draw_text("FOUNDING RECORD", 62, 184, TYPE_HEADING_COMPACT)
		for i in 0 ..< 6 {
			choice := s.setup.choices[i]
			class :=
				i < 2 ? game.Attribute_Class.Identity : i < 4 ? game.Attribute_Class.Capability : game.Attribute_Class.Value
			color := i < 2 ? UX.text : i < 4 ? UX.info : UX.committed
			prefix := fmt.tprintf("%v  ·  ", class)
			y := 225 + f32(i) * 32
			draw_text(prefix, 62, y, TYPE_BODY, color)
			tooltip_term(
				game.setup_attribute_name(&s.setup, i),
				game.setup_attribute_description(&s.setup, i),
				62 + measure_text(prefix, TYPE_BODY).x,
				y,
				TYPE_BODY,
				color,
			)
		}
		label_caps(
			"EXPERIENCE",
			650,
			218,
			UX.info,
		); draw_fmt(650, 242, TYPE_BODY_COMPACT, UX.text, "%v · %v TEMPO", s.setup.length, s.setup.story_tempo); draw_fmt(650, 270, TYPE_SMALL, UX.dim, "%v MATERIALS · %v CONSEQUENCES", s.setup.material_pressure, s.setup.consequence_severity); draw_fmt(650, 294, TYPE_SMALL, UX.dim, "COMBAT HEROISM · %d : 1", s.setup.ruleset.heroism_scale)
		label_caps(
			"FOUNDING",
			650,
			340,
			UX.committed,
		); draw_fmt(650, 364, TYPE_BODY_COMPACT, UX.text, "LOSS · %s", game.LOSS_NAMES[s.setup.loss_index]); draw_fmt(650, 392, TYPE_BODY_COMPACT, UX.good, "PRESERVED · %s", game.PRESERVED_NAMES[s.setup.preserved_index]); preview := game.setup_choice_preview(&s.setup, 4); draw_text_wrapped(preview.effect, R(650, 424, 520, 44), TYPE_SMALL_EMPHASIS, UX.text)
		if button(R(650, 500, 150, 34), "EDIT EXPERIENCE") do s.setup_step = 0
		if button(R(810, 500, 130, 34), "EDIT PEOPLE") do s.setup_step = 1
		if button(R(950, 500, 150, 34), "EDIT FOUNDING") do s.setup_step = 2
		if button(R(990, 565, 210, 44), "FOUND CHRONICLE", true, true) {_ = found_chronicle(s)}}
	if s.setup_step > 0 && button(R(50, 582, 120, 36), "BACK") do s.setup_step -= 1
	if s.setup_step < 3 && button(R(1090, 582, 120, 36), "NEXT", true, true) do s.setup_step += 1
}
