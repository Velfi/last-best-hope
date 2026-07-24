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

draw_ship_variation_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("PROCEDURAL SHIP MATRIX", 28, 20, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		fmt.tprintf(
			"8 ROLES  x  5 HULL CLASSES  x  3 CONSTRUCTIONS  |  KEY %s + HARDPOINT  |  FIXED SEED",
			SHIP_PROFILE_GRAMMAR,
		),
		29,
		52,
		TYPE_LABEL,
		UX.dim,
	)
	classes := [5]game.Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	roles := [8]game.Role {
		.Habitat,
		.Agriculture,
		.Foundry,
		.Archive,
		.Hospital,
		.Survey,
		.Escort,
		.Colony,
	}
	grid_x: f32 = 160
	grid_y: f32 = 112
	cell_w: f32 = 216
	cell_h: f32 = 72
	for hull_class, column in classes {
		name := game.ship_hull_class_name(hull_class)
		draw_text(name, grid_x + f32(column) * cell_w + 18, 82, TYPE_SMALL, UX.info)
	}
	for role, row in roles {
		y := grid_y + f32(row) * cell_h
		draw_text(game.role_name(role), 24, y + 26, TYPE_SMALL, UX.text)
		for hull_class, column in classes {
			x := grid_x + f32(column) * cell_w
			rl.DrawLineEx(V(x, y), V(x + cell_w - 8, y), 1, UX.line)
			cell := row * len(classes) + column
			for variant in 0 ..< 3 {
				ship := ship_variation_board_ship(role, hull_class, cell, variant)
				ship_x := x + cell_w * (f32(variant) + .5) / 3
				draw_ship_constellation_marker(ship, ship_x, y + 31, false, 1.12)
				draw_text_fitted(
					ship_variation_board_key(ship),
					R(ship_x - 31, y + 49, 62, 10),
					TYPE_MICRO_TIGHT,
					UX.dim,
				)
			}
		}
	}
}

draw_ship_lineage_board :: proc(c: ^game.Campaign) {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("CONSTRUCTION LINEAGES", 38, 24, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"SHARED DESIGN FAMILIES + KEEL + WING SWEEP  |  BALANCED YARD-DOCTRINE BOWS",
		39,
		55,
		TYPE_LABEL,
		UX.dim,
	)
	for relationship, row in c.ship_relationships[:c.ship_relationship_count] {
		if relationship.kind != .Construction_Siblings do continue
		first_at := game.ship_index(c, relationship.ship_a)
		second_at := game.ship_index(c, relationship.ship_b)
		if first_at < 0 || second_at < 0 do continue
		first, second := c.ships[first_at], c.ships[second_at]
		y := f32(170 + row * 190)
		x1, x2 := f32(390), f32(890)
		rl.DrawLineEx(V(x1 + 75, y), V(x2 - 75, y), 1, UX.line)
		draw_fmt(602, y - 12, TYPE_CAPTION, UX.committed, "LINEAGE %02d", row + 1)
		draw_ship_constellation_marker(first, x1, y, false, 2.2)
		draw_ship_constellation_marker(second, x2, y, false, 2.2)
		draw_text_fitted(first.name, R(x1 - 145, y + 66, 290, 20), TYPE_BODY, UX.text)
		draw_text_fitted(second.name, R(x2 - 145, y + 66, 290, 20), TYPE_BODY, UX.text)
		draw_text_fitted(
			fmt.tprintf("%v · %s", first.role, game.ship_hull_class_name(first.hull_class)),
			R(x1 - 145, y + 88, 290, 18),
			TYPE_LABEL,
			UX.info,
		)
		draw_text_fitted(
			fmt.tprintf("%v · %s", second.role, game.ship_hull_class_name(second.hull_class)),
			R(x2 - 145, y + 88, 290, 18),
			TYPE_LABEL,
			UX.info,
		)
		primary, accent := ship_construction_family_pair(first)
		draw_text_fitted(
			ship_yard_pattern_name(first),
			R(555, y + 10, 170, 18),
			TYPE_LABEL,
			UX.committed,
		)
		draw_text_fitted(
			ship_keel_profile_name(first),
			R(555, y + 29, 170, 14),
			TYPE_MICRO,
			UX.info,
		)
		draw_text_fitted(
			fmt.tprintf(
				"F%02d/F%02d · S%d · B%d/B%d",
				primary + 1,
				accent + 1,
				game.ship_construction_wing_sweep(first) + 1,
				game.ship_construction_bow_profile(first) + 1,
				game.ship_construction_bow_profile(second) + 1,
			),
			R(555, y + 45, 170, 13),
			TYPE_MICRO,
			UX.dim,
		)
	}
}

draw_ship_seed_comparison_board :: proc() {
	first := game.new_campaign_heap(0x5eed)
	second := game.new_campaign_heap(0x5eee)
	defer game.campaign_destroy_heap(first)
	defer game.campaign_destroy_heap(second)
	game.apply_generated_fleet(first, game.balanced_fleet_goals(), "FCS")
	game.apply_generated_fleet(second, game.balanced_fleet_goals(), "FCS")
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("NEIGHBORING SEED FLEETS", 38, 24, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		fmt.tprintf(
			"COMPLETE CONSTRUCTION AVALANCHE  |  FAMILY + COMPONENTS + %s + HARDPOINT",
			SHIP_PROFILE_GRAMMAR,
		),
		39,
		55,
		TYPE_LABEL,
		UX.dim,
	)
	rl.DrawLineEx(V(640, 94), V(640, 674), 1, UX.line)
	seeds := [2]u64{0x5eed, 0x5eee}
	fleets := [2]^game.Campaign{first, second}
	for fleet, panel in fleets {
		panel_x := f32(panel * 640)
		draw_fmt(
			panel_x + 250,
			91,
			TYPE_SMALL_EMPHASIS,
			UX.committed,
			"CAMPAIGN SEED 0x%04x",
			seeds[panel],
		)
		for ship, i in fleet.ships[:fleet.ship_count] {
			column, row := i % 4, i / 4
			x := panel_x + 80 + f32(column) * 155
			y := f32(170 + row * 165)
			draw_ship_constellation_marker(ship, x, y, false, 1.8)
			draw_text_fitted(ship.name, R(x - 67, y + 43, 134, 15), TYPE_CAPTION, UX.text)
			draw_text_fitted(
				ship_structural_profile_code(ship),
				R(x - 67, y + 59, 134, 12),
				TYPE_MICRO_TIGHT,
				UX.info,
			)
		}
	}
	overlap := 0
	for a in first.ships[:first.ship_count] do for b in second.ships[:second.ship_count] do if game.ship_construction_recipe_fingerprint(a) == game.ship_construction_recipe_fingerprint(b) do overlap += 1
	draw_fmt(528, 686, TYPE_FINE, UX.dim, "EXACT RECIPE OVERLAP  %d / %d", overlap, game.MAX_SHIPS)
}

draw_ship_effect_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("ENGINE EFFECT MATRIX", 38, 22, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"6 ENGINE FAMILIES  x  6 OPERATING STATES  |  CROPPED ATLAS REGRESSION",
		39,
		53,
		TYPE_LABEL,
		UX.dim,
	)
	row_names := [6]string{"IDLE", "MANEUVER", "COMMITTED", "OVERDRIVE", "FAILING", "DISABLED"}
	grid_x, grid_y := f32(150), f32(112)
	cell_w, cell_h := f32(176), f32(92)
	for column in 0 ..< 6 do draw_fmt(grid_x + f32(column) * cell_w + 66, 84, TYPE_CAPTION, UX.info, "F%02d", column + 1)
	for row in 0 ..< 6 {
		y := grid_y + f32(row) * cell_h
		draw_text(row_names[row], 34, y + 36, TYPE_CAPTION, UX.text)
		for column in 0 ..< 6 {
			x := grid_x + f32(column) * cell_w
			panel(R(x, y, cell_w - 10, cell_h - 8))
			draw_ship_effect_cell(ship_effect_texture, row * 6 + column, R(x + 57, y + 7, 52, 70))
		}
	}
}

ship_drive_board_ship :: proc(layout, setback: int) -> game.Ship {
	config := game.default_ship_generator_config(0)
	config.role = .Escort
	config.role_locked = true
	config.hull_class = .Cruiser
	config.variation_percent = 0
	for seed in 1 ..= 4096 {
		ship := game.generate_ship(u64(seed), config)
		if game.ship_construction_keel_profile(ship) != 1 || game.ship_construction_wing_stance(ship) != 1 || game.ship_construction_wing_sweep(ship) != 1 || game.ship_construction_bow_profile(ship) != 1 do continue
		ship.drive_layout = u8(clamp(layout, 0, 2) + 1)
		ship.drive_setback = u8(clamp(setback, 0, 2) + 1)
		ship.committed = true
		ship.active = true
		return ship
	}
	return game.generate_ship(1, config)
}

@(test)
drive_comparison_board_finds_each_layout_under_matched_conditions :: proc(t: ^testing.T) {
	baseline := ship_drive_board_ship(0, 0)
	for setback in 0 ..< 3 do for layout in 0 ..< 3 {
		ship := ship_drive_board_ship(layout, setback)
		testing.expect_value(t, game.ship_construction_drive_layout(ship), layout)
		testing.expect_value(t, game.ship_construction_drive_setback(ship), setback)
		testing.expect_value(t, ship.role, game.Role.Escort)
		testing.expect_value(t, ship.hull_class, game.Hull_Class.Cruiser)
		testing.expect_value(t, game.ship_construction_keel_profile(ship), 1)
		testing.expect_value(t, game.ship_construction_wing_stance(ship), 1)
		testing.expect_value(t, game.ship_construction_wing_sweep(ship), 1)
		testing.expect_value(t, game.ship_construction_bow_profile(ship), 1)
		testing.expect_value(t, ship.construction_seed, baseline.construction_seed)
		testing.expect_value(t, game.ship_construction_visual_fingerprint(ship), game.ship_construction_visual_fingerprint(baseline))
		testing.expect(t, ship.committed && ship.active)
	}
}

draw_ship_drive_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("PROPULSION ARCHITECTURES", 38, 24, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"3 DRIVE LAYOUTS  x  3 SETBACKS  |  ENGINE BANK + COUPLED EXHAUST ORIGIN",
		39,
		55,
		TYPE_LABEL,
		UX.dim,
	)
	names := [3]string{"INLINE DRIVE", "TWIN DRIVE", "OUTBOARD DRIVE"}
	setback_names := [3]string{"RECESSED", "FLUSH", "EXTENDED"}
	for layout in 0 ..< 3 do draw_text_fitted(names[layout], R(f32(190 + layout * 360), 90, 300, 24), TYPE_BODY, UX.info)
	for setback in 0 ..< 3 {
		y := f32(190 + setback * 190)
		draw_text(setback_names[setback], 35, y, TYPE_SMALL, UX.committed)
		for layout in 0 ..< 3 {
			x := f32(340 + layout * 360)
			ship := ship_drive_board_ship(layout, setback)
			draw_ship_constellation_marker(ship, x, y, false, 2.45)
			draw_text_fitted(
				ship_structural_profile_code(ship),
				R(x - 100, y + 67, 200, 16),
				TYPE_MICRO,
				UX.dim,
			)
			if layout < 2 do rl.DrawLineEx(V(x + 180, y - 65), V(x + 180, y + 85), 1, UX.line)
		}
		if setback < 2 do rl.DrawLineEx(V(175, y + 94), V(1195, y + 94), 1, UX.line)
	}
}

ship_wing_board_ship :: proc(stance, sweep: int) -> game.Ship {
	config := game.default_ship_generator_config(0)
	config.role = .Survey
	config.role_locked = true
	config.hull_class = .Cruiser
	config.variation_percent = 0
	for seed in 1 ..= 4096 {
		ship := game.generate_ship(u64(seed), config)
		if game.ship_construction_keel_profile(ship) != 1 || game.ship_construction_bow_profile(ship) != 1 || game.ship_construction_drive_layout(ship) != 1 || game.ship_construction_drive_setback(ship) != 1 do continue
		ship.wing_stance = u8(clamp(stance, 0, 2) + 1)
		ship.wing_sweep = u8(clamp(sweep, 0, 2) + 1)
		ship.active = true
		return ship
	}
	return game.generate_ship(1, config)
}

@(test)
wing_comparison_board_is_identical_except_stance_and_sweep :: proc(t: ^testing.T) {
	baseline := ship_wing_board_ship(0, 0)
	for sweep in 0 ..< 3 do for stance in 0 ..< 3 {
		ship := ship_wing_board_ship(stance, sweep)
		testing.expect_value(t, game.ship_construction_wing_stance(ship), stance)
		testing.expect_value(t, game.ship_construction_wing_sweep(ship), sweep)
		testing.expect_value(t, ship.construction_seed, baseline.construction_seed)
		testing.expect_value(t, game.ship_construction_visual_fingerprint(ship), game.ship_construction_visual_fingerprint(baseline))
		testing.expect_value(t, game.ship_construction_keel_profile(ship), 1)
		testing.expect_value(t, game.ship_construction_bow_profile(ship), 1)
		testing.expect_value(t, game.ship_construction_drive_layout(ship), 1)
		testing.expect_value(t, game.ship_construction_drive_setback(ship), 1)
	}
}

draw_ship_wing_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("WING ARCHITECTURES", 38, 24, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"3 STANCES  x  3 SWEEPS  |  IDENTICAL SURVEY CRUISER CONSTRUCTION",
		39,
		55,
		TYPE_LABEL,
		UX.dim,
	)
	stance_names := [3]string{"COMPACT WING", "BALANCED WING", "BROAD WING"}
	sweep_names := [3]string{"FORWARD", "LEVEL", "AFT"}
	for stance in 0 ..< 3 do draw_text_fitted(stance_names[stance], R(f32(190 + stance * 360), 90, 300, 24), TYPE_BODY, UX.info)
	for sweep in 0 ..< 3 {
		y := f32(190 + sweep * 190)
		draw_text(sweep_names[sweep], 35, y, TYPE_SMALL, UX.committed)
		for stance in 0 ..< 3 {
			x := f32(340 + stance * 360)
			ship := ship_wing_board_ship(stance, sweep)
			draw_ship_constellation_marker(ship, x, y, false, 3.05)
			draw_text_fitted(
				ship_structural_profile_code(ship),
				R(x - 100, y + 67, 200, 16),
				TYPE_MICRO,
				UX.dim,
			)
			if stance < 2 do rl.DrawLineEx(V(x + 180, y - 65), V(x + 180, y + 85), 1, UX.line)
		}
		if sweep < 2 do rl.DrawLineEx(V(175, y + 94), V(1195, y + 94), 1, UX.line)
	}
}

ship_hull_board_ship :: proc(keel, bow: int) -> game.Ship {
	config := game.default_ship_generator_config(0)
	config.role = .Escort
	config.role_locked = true
	config.hull_class = .Cruiser
	config.variation_percent = 0
	for seed in 1 ..= 4096 {
		ship := game.generate_ship(u64(seed), config)
		if game.ship_construction_wing_stance(ship) != 1 || game.ship_construction_wing_sweep(ship) != 1 || game.ship_construction_drive_layout(ship) != 1 || game.ship_construction_drive_setback(ship) != 1 do continue
		ship.keel_profile = u8(clamp(keel, 0, 2) + 1)
		ship.bow_profile = u8(clamp(bow, 0, 2) + 1)
		ship.active = true
		return ship
	}
	return game.generate_ship(1, config)
}

@(test)
hull_comparison_board_is_identical_except_keel_and_bow :: proc(t: ^testing.T) {
	baseline := ship_hull_board_ship(0, 0)
	for bow in 0 ..< 3 do for keel in 0 ..< 3 {
		ship := ship_hull_board_ship(keel, bow)
		testing.expect_value(t, game.ship_construction_keel_profile(ship), keel)
		testing.expect_value(t, game.ship_construction_bow_profile(ship), bow)
		testing.expect_value(t, ship.construction_seed, baseline.construction_seed)
		testing.expect_value(t, game.ship_construction_visual_fingerprint(ship), game.ship_construction_visual_fingerprint(baseline))
		testing.expect_value(t, game.ship_construction_wing_stance(ship), 1)
		testing.expect_value(t, game.ship_construction_wing_sweep(ship), 1)
		testing.expect_value(t, game.ship_construction_drive_layout(ship), 1)
		testing.expect_value(t, game.ship_construction_drive_setback(ship), 1)
	}
}

draw_ship_hull_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("HULL ARCHITECTURES", 38, 24, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"3 KEEL PROFILES  x  3 BOWS  |  IDENTICAL ESCORT CRUISER CONSTRUCTION",
		39,
		55,
		TYPE_LABEL,
		UX.dim,
	)
	keel_names := [3]string{"COMPACT KEEL", "STANDARD KEEL", "LONG KEEL"}
	bow_names := [3]string{"BLUNT BOW", "STANDARD BOW", "NEEDLE BOW"}
	for keel in 0 ..< 3 do draw_text_fitted(keel_names[keel], R(f32(190 + keel * 360), 90, 300, 24), TYPE_BODY, UX.info)
	for bow in 0 ..< 3 {
		y := f32(190 + bow * 190)
		draw_text(bow_names[bow], 35, y, TYPE_SMALL, UX.committed)
		for keel in 0 ..< 3 {
			x := f32(340 + keel * 360)
			ship := ship_hull_board_ship(keel, bow)
			draw_ship_constellation_marker(ship, x, y, false, 3.0)
			draw_text_fitted(
				ship_structural_profile_code(ship),
				R(x - 100, y + 67, 200, 16),
				TYPE_MICRO,
				UX.dim,
			)
			if keel < 2 do rl.DrawLineEx(V(x + 180, y - 65), V(x + 180, y + 85), 1, UX.line)
		}
		if bow < 2 do rl.DrawLineEx(V(175, y + 94), V(1195, y + 94), 1, UX.line)
	}
}

ship_mission_board_ship :: proc(role: game.Role, profile: int) -> game.Ship {
	config := game.default_ship_generator_config(int(role))
	config.role = role
	config.role_locked = true
	config.hull_class = .Cruiser
	config.variation_percent = 0
	for seed in 1 ..= 4096 {
		ship := game.generate_ship(u64(seed), config)
		if game.ship_construction_keel_profile(ship) != 1 || game.ship_construction_wing_stance(ship) != 1 || game.ship_construction_wing_sweep(ship) != 1 || game.ship_construction_drive_layout(ship) != 1 || game.ship_construction_drive_setback(ship) != 1 do continue
		ship.mission_profile = u8(clamp(profile, 0, 2) + 1)
		ship.active = true
		return ship
	}
	return game.generate_ship(1, config)
}

@(test)
mission_deck_profiles_are_matched_distinct_and_bounded :: proc(t: ^testing.T) {
	roles := [3]game.Role{.Survey, .Habitat, .Colony}
	classes := [5]game.Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	for role in roles {
		baseline := ship_mission_board_ship(role, 0)
		areas: [3]f32
		for profile in 0 ..< 3 {
			ship := ship_mission_board_ship(role, profile)
			testing.expect_value(t, game.ship_construction_mission_profile(ship), profile)
			testing.expect_value(t, ship.construction_seed, baseline.construction_seed)
			testing.expect_value(
				t,
				game.ship_construction_visual_fingerprint(ship),
				game.ship_construction_visual_fingerprint(baseline),
			)
			hull := ship_marker_rect(ship, 100, 100, false, 3)
			module := scale_rect_about_center(
				ship_role_module_rect(hull, role, ship_superstructure_mount_offset(ship)),
				ship_mission_module_scale(ship),
			)
			areas[profile] = module.width * module.height
		}
		testing.expect(t, areas[0] < areas[1] && areas[1] < areas[2])
	}
	all_roles := [8]game.Role {
		.Habitat,
		.Agriculture,
		.Foundry,
		.Archive,
		.Hospital,
		.Survey,
		.Escort,
		.Colony,
	}
	for role in all_roles do for hull_class in classes do for profile in 0 ..< 3 do for hardpoint in 0 ..< 9 {
		ship := game.Ship {
			role              = role,
			hull_class        = hull_class,
			crew              = game.ship_hull_class_crew(role, hull_class) * 3 / 2,
			mission_profile   = u8(profile + 1),
			utility_hardpoint = u8(hardpoint + 1),
		}
		hull := ship_marker_rect(ship, 100, 100, false, 3)
		module := scale_rect_about_center(ship_role_module_rect(hull, role, ship_superstructure_mount_offset(ship)), ship_mission_module_scale(ship))
		testing.expect(t, module.x >= hull.x && module.y >= hull.y)
		testing.expect(t, module.x + module.width <= hull.x + hull.width)
		testing.expect(t, module.y + module.height <= hull.y + hull.height)
	}
}

draw_ship_mission_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("MISSION DECK ARCHITECTURES", 38, 24, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"3 ROLES  x  3 DECK PROFILES  |  MATCHED WITHIN EACH ROLE",
		39,
		55,
		TYPE_LABEL,
		UX.dim,
	)
	profile_names := [3]string{"COMPACT DECK", "STANDARD DECK", "EXPANDED DECK"}
	roles := [3]game.Role{.Survey, .Habitat, .Colony}
	for profile in 0 ..< 3 do draw_text_fitted(profile_names[profile], R(f32(190 + profile * 360), 90, 300, 24), TYPE_BODY, UX.info)
	for role, row in roles {
		y := f32(190 + row * 190)
		draw_text(game.role_name(role), 35, y, TYPE_SMALL, UX.committed)
		for profile in 0 ..< 3 {
			x := f32(340 + profile * 360)
			ship := ship_mission_board_ship(role, profile)
			draw_ship_constellation_marker(ship, x, y, false, 3.05)
			draw_text_fitted(
				ship_structural_profile_code(ship),
				R(x - 100, y + 67, 200, 16),
				TYPE_MICRO,
				UX.dim,
			)
			if profile < 2 do rl.DrawLineEx(V(x + 180, y - 65), V(x + 180, y + 85), 1, UX.line)
		}
		if row < 2 do rl.DrawLineEx(V(175, y + 94), V(1195, y + 94), 1, UX.line)
	}
}

ship_hardpoint_name :: proc(slot: int) -> string {
	row_names := [3]string{"FORE", "MID", "AFT"}
	column_names := [3]string{"PORT", "CENTER", "STARBOARD"}
	bounded := clamp(slot, 0, 8)
	return fmt.tprintf("%s-%s", row_names[bounded / 3], column_names[bounded % 3])
}

ship_hardpoint_board_ship :: proc(slot: int) -> game.Ship {
	config := game.default_ship_generator_config(0)
	config.role = .Survey
	config.role_locked = true
	config.hull_class = .Cruiser
	config.variation_percent = 0
	for seed in 1 ..= 8192 {
		ship := game.generate_ship(u64(seed), config)
		ship.bow_profile = 2 // standard bow, held constant across the matrix
		if game.ship_construction_keel_profile(ship) != 1 || game.ship_construction_wing_stance(ship) != 1 || game.ship_construction_drive_layout(ship) != 1 do continue
		ship.utility_hardpoint = u8(clamp(slot, 0, 8) + 1)
		return ship
	}
	ship := game.generate_ship(1, config)
	ship.utility_hardpoint = u8(clamp(slot, 0, 8) + 1)
	return ship
}

@(test)
hardpoint_board_finds_nine_matched_counterbalanced_constructions :: proc(t: ^testing.T) {
	baseline := ship_hardpoint_board_ship(0)
	for slot in 0 ..< 9 {
		ship := ship_hardpoint_board_ship(slot)
		testing.expect_value(t, game.ship_construction_utility_hardpoint(ship), slot)
		testing.expect_value(t, game.ship_construction_keel_profile(ship), 1)
		testing.expect_value(t, game.ship_construction_wing_stance(ship), 1)
		testing.expect_value(t, game.ship_construction_drive_layout(ship), 1)
		testing.expect_value(t, game.ship_construction_bow_profile(ship), 1)
		testing.expect_value(t, ship.construction_seed, baseline.construction_seed)
		testing.expect_value(
			t,
			game.ship_construction_visual_fingerprint(ship),
			game.ship_construction_visual_fingerprint(baseline),
		)
		utility := ship_utility_mount_offset(ship)
		module := ship_superstructure_mount_offset(ship)
		testing.expect(t, utility.x * module.x <= 0 && utility.y * module.y <= 0)
	}
}

draw_ship_hardpoint_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("HARDPOINT ARCHITECTURES", 38, 22, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"MATCHED SURVEY CRUISERS  |  UTILITY POD + COUNTERBALANCED MISSION SUPERSTRUCTURE",
		39,
		53,
		TYPE_LABEL,
		UX.dim,
	)
	for slot in 0 ..< 9 {
		column, row := slot % 3, slot / 3
		x := f32(270 + column * 370)
		y := f32(172 + row * 178)
		ship := ship_hardpoint_board_ship(slot)
		draw_ship_constellation_marker(ship, x, y, false, 3.0)
		draw_fmt(x - 23, y + 66, TYPE_SMALL, UX.committed, "H%02d", slot + 1)
		draw_text_fitted(
			ship_hardpoint_name(slot),
			R(x - 105, y + 85, 210, 17),
			TYPE_CAPTION,
			UX.info,
		)
		if column < 2 do rl.DrawLineEx(V(x + 185, y - 68), V(x + 185, y + 105), 1, UX.line)
		if row < 2 do rl.DrawLineEx(V(x - 160, y + 108), V(x + 160, y + 108), 1, UX.line)
	}
}

draw_ship_weapon_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("STRIKE WEAPON MODULES", 38, 22, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"MATCHED LINEAGE  |  KINETIC RECOIL ASSEMBLY · GUIDED MISSILE COFFINS · HEAVY TORPEDO CRADLES",
		39,
		53,
		TYPE_LABEL,
		UX.dim,
	)
	packages := [3]game.Ship_Weapon_Package{.Railgun_Battery, .Guided_Missiles, .Heavy_Torpedoes}
	names := [3]string{"KINETIC BATTERY", "GUIDED MISSILES", "HEAVY TORPEDOES"}
	notes := [3]string {
		"BREECH · RECOIL COLLARS · FORKED MUZZLE",
		"4 FACETED NOSES · CONTROL FINS",
		"2 SEEKER HEADS · PROPULSION COLLARS",
	}
	camera := Ship_Generator_Camera{0, math.PI * .5, 1}
	for column in 0 ..< 3 {
		x := f32(28 + column * 410)
		ship := ship_generator_contact_identity(24301, 24301, .Strike, 0)
		ship.weapon_package = packages[column]
		recipe := game.procedural_ship_generate_for_ship(ship)
		// Isolate the prow installation so this board remains a fast visual
		// regression fixture instead of redrawing the whole ship three times.
		half_length := recipe.frame.keel_length * .5
		recipe.module_count = 1
		recipe.frame.station_count = 1
		recipe.modules[0] = {
			id         = 0xe3000800,
			surface_id = 0xe3000800,
			module     = .Truss,
			material   = .Truss,
			position   = {half_length * .45, 0, recipe.frame.height * .08},
			scale      = {half_length * .58, recipe.frame.beam * .4, recipe.frame.height * .2},
			direction  = {1, 0, 0},
		}
		panel(R(x, 92, 390, 558))
		draw_procedural_ship(
			&recipe,
			R(x + 12, 128, 366, 410),
			camera,
			false,
			{},
			true,
			0,
			1,
			true,
		)
		draw_text(names[column], x + 18, 558, TYPE_HEADING, UX.text)
		draw_text(notes[column], x + 18, 590, TYPE_CAPTION, UX.info)
		draw_fmt(
			x + 18,
			616,
			TYPE_FINE,
			UX.dim,
			"PACKAGE %s · SCALE %.2f",
			game.ship_weapon_package_name(packages[column]),
			recipe.weapon_capability_scale,
		)
	}
}

draw_ship_direct_fire_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("DIRECT-FIRE WEAPON MODULES", 38, 22, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"MATCHED LINEAGE  |  PACKAGE-SPECIFIC BREECH, BARREL, COIL, MUZZLE, AND EMITTER ARCHITECTURE",
		39,
		53,
		TYPE_LABEL,
		UX.dim,
	)
	packages := [5]game.Ship_Weapon_Package {
		.Chemical_Autocannon,
		.Coilgun_Battery,
		.Railgun_Battery,
		.Defensive_Laser,
		.Offensive_Laser,
	}
	names := [5]string {
		"CHEMICAL AUTOCANNON",
		"COILGUN BATTERY",
		"RAILGUN BATTERY",
		"DEFENSIVE LASER",
		"OFFENSIVE LASER",
	}
	notes := [5]string {
		"TWIN SHORT BARRELS · AMMUNITION BOX",
		"4 FIELD COILS · SINGLE BORE",
		"2 RECOIL COLLARS · FORKED MUZZLE",
		"SHORT EMITTER · COMPACT OPTIC",
		"LONG EMITTER · 3 FOCUSING COLLARS",
	}
	camera := Ship_Generator_Camera{0, math.PI * .5, 1}
	for weapon, index in packages {
		column, row := index % 3, index / 3
		x, y := f32(28 + column * 410), f32(88 + row * 304)
		ship := ship_generator_contact_identity(24301, 24301, .Strike, 0)
		ship.weapon_package = weapon
		recipe := game.procedural_ship_generate_for_ship(ship)
		half_length := recipe.frame.keel_length * .5
		recipe.module_count = 1
		recipe.frame.station_count = 1
		recipe.modules[0] = {
			id         = 0xe3000800,
			surface_id = 0xe3000800,
			module     = .Truss,
			material   = .Truss,
			position   = {half_length * .45, 0, recipe.frame.height * .08},
			scale      = {half_length * .58, recipe.frame.beam * .4, recipe.frame.height * .2},
			direction  = {1, 0, 0},
		}
		panel(R(x, y, 390, 286))
		draw_procedural_ship(
			&recipe,
			R(x + 12, y + 12, 366, 178),
			camera,
			false,
			{},
			true,
			0,
			1,
			true,
		)
		draw_text(names[index], x + 18, y + 204, TYPE_HEADING, UX.text)
		draw_text(notes[index], x + 18, y + 238, TYPE_CAPTION, UX.info)
		draw_fmt(
			x + 18,
			y + 264,
			TYPE_FINE,
			UX.dim,
			"PACKAGE %s · SCALE %.2f",
			game.ship_weapon_package_name(weapon),
			recipe.weapon_capability_scale,
		)
	}
}

draw_ship_single_hull_weapon_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("SINGLE-HULL WEAPON INTEGRATION", 38, 22, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"MATCHED FLEET HULL  |  SHOULDER LOAD PATHS · SERVICE ACCESS · PACKAGE-SPECIFIC EXTERNAL STORES",
		39,
		53,
		TYPE_LABEL,
		UX.dim,
	)
	packages := [3]game.Ship_Weapon_Package{.Railgun_Battery, .Guided_Missiles, .Heavy_Torpedoes}
	names := [3]string{"DISTRIBUTED BATTERY", "GUIDED MISSILE RACKS", "HEAVY TORPEDO CRADLES"}
	notes := [3]string {
		"4 STAGGERED SHOULDER TURRETS",
		"4 FINNED STORES · PAIRED SHOULDERS",
		"2 SHIP-SCALE STORES · DEEP LOAD PATH",
	}
	camera := Ship_Generator_Camera{0, math.PI * .5, 1}
	for weapon, column in packages {
		x := f32(28 + column * 410)
		ship := ship_generator_contact_identity(24301, 24301, .Fleet, 0)
		ship.generator_kind = .Single_Hull
		ship.construction_style = .Machine_Partnership
		ship.weapon_package = weapon
		recipe := game.procedural_ship_generate_for_ship(ship)
		panel(R(x, 92, 390, 558))
		draw_procedural_ship(&recipe, R(x + 12, 126, 366, 408), camera, false)
		draw_text(names[column], x + 18, 558, TYPE_HEADING, UX.text)
		draw_text(notes[column], x + 18, 590, TYPE_CAPTION, UX.info)
		draw_fmt(
			x + 18,
			616,
			TYPE_FINE,
			UX.dim,
			"PACKAGE %s · SCALE %.2f",
			game.ship_weapon_package_name(weapon),
			recipe.weapon_capability_scale,
		)
	}
}

draw_ship_single_hull_direct_fire_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("SINGLE-HULL DIRECT-FIRE INTEGRATION", 38, 22, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"MATCHED FLEET HULL  |  FIVE REPLACEABLE SHOULDER-BATTERY ARCHITECTURES",
		39,
		53,
		TYPE_LABEL,
		UX.dim,
	)
	packages := [5]game.Ship_Weapon_Package {
		.Chemical_Autocannon,
		.Coilgun_Battery,
		.Railgun_Battery,
		.Defensive_Laser,
		.Offensive_Laser,
	}
	names := [5]string {
		"CHEMICAL AUTOCANNON",
		"COILGUN BATTERY",
		"RAILGUN BATTERY",
		"DEFENSIVE LASER",
		"OFFENSIVE LASER",
	}
	camera := Ship_Generator_Camera{0, math.PI * .5, 1}
	for weapon, index in packages {
		column, row := index % 3, index / 3
		x, y := f32(28 + column * 410), f32(88 + row * 304)
		ship := ship_generator_contact_identity(24301, 24301, .Fleet, 0)
		ship.generator_kind = .Single_Hull
		ship.construction_style = .Machine_Partnership
		ship.weapon_package = weapon
		recipe := game.procedural_ship_generate_for_ship(ship)
		panel(R(x, y, 390, 286))
		draw_procedural_ship(&recipe, R(x + 12, y + 12, 366, 178), camera, false)
		draw_text(names[index], x + 18, y + 204, TYPE_HEADING, UX.text)
		draw_fmt(
			x + 18,
			y + 238,
			TYPE_CAPTION,
			UX.info,
			"%s · SCALE %.2f",
			game.ship_weapon_package_name(weapon),
			recipe.weapon_capability_scale,
		)
	}
}

draw_ship_delta_weapon_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("DELTA WEAPON INTEGRATION", 38, 22, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"MATCHED FLEET LIFTING BODY  |  SEVEN WING-ROOT INSTALLATIONS · COMMON TOP VIEW",
		39,
		53,
		TYPE_LABEL,
		UX.dim,
	)
	packages := [7]game.Ship_Weapon_Package {
		.Chemical_Autocannon,
		.Coilgun_Battery,
		.Railgun_Battery,
		.Defensive_Laser,
		.Offensive_Laser,
		.Guided_Missiles,
		.Heavy_Torpedoes,
	}
	names := [7]string {
		"AUTOCANNON",
		"COILGUN",
		"RAILGUN",
		"DEFENSIVE LASER",
		"OFFENSIVE LASER",
		"GUIDED MISSILES",
		"HEAVY TORPEDOES",
	}
	camera := Ship_Generator_Camera{0, math.PI * .5, 1}
	for weapon, index in packages {
		column, row := index % 4, index / 4
		x, y := f32(24 + column * 307), f32(88 + row * 304)
		ship := ship_generator_contact_identity(24301, 24301, .Fleet, 0)
		ship.generator_kind = .Delta
		ship.construction_style = .Machine_Partnership
		ship.weapon_package = weapon
		recipe := game.procedural_ship_generate_for_ship(ship)
		panel(R(x, y, 291, 286))
		draw_procedural_ship(&recipe, R(x + 8, y + 10, 275, 178), camera, false)
		draw_text(names[index], x + 14, y + 204, TYPE_HEADING, UX.text)
		draw_fmt(
			x + 14,
			y + 240,
			TYPE_FINE,
			UX.info,
			"%s · %.2f",
			game.ship_weapon_package_name(weapon),
			recipe.weapon_capability_scale,
		)
	}
}

draw_ship_modular_fleet_weapon_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("FRAME FLEET WEAPON INTEGRATION", 38, 22, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"MATCHED OPEN FLEET FRAME  |  SEVEN TRANSVERSE BATTERIES · COMMON TOP VIEW",
		39,
		53,
		TYPE_LABEL,
		UX.dim,
	)
	packages := [7]game.Ship_Weapon_Package {
		.Chemical_Autocannon,
		.Coilgun_Battery,
		.Railgun_Battery,
		.Defensive_Laser,
		.Offensive_Laser,
		.Guided_Missiles,
		.Heavy_Torpedoes,
	}
	names := [7]string {
		"AUTOCANNON",
		"COILGUN",
		"RAILGUN",
		"DEFENSIVE LASER",
		"OFFENSIVE LASER",
		"GUIDED MISSILES",
		"HEAVY TORPEDOES",
	}
	camera := Ship_Generator_Camera{0, math.PI * .5, 1}
	for weapon, index in packages {
		column, row := index % 4, index / 4
		x, y := f32(24 + column * 307), f32(88 + row * 304)
		ship := ship_generator_contact_identity(24301, 24301, .Fleet, 0)
		ship.generator_kind = .Modular_Frame
		ship.construction_style = .Machine_Partnership
		ship.weapon_package = weapon
		recipe := game.procedural_ship_generate_for_ship(ship)
		panel(R(x, y, 291, 286))
		draw_procedural_ship(&recipe, R(x + 8, y + 10, 275, 178), camera, false)
		draw_text(names[index], x + 14, y + 204, TYPE_HEADING, UX.text)
		draw_fmt(
			x + 14,
			y + 240,
			TYPE_FINE,
			UX.info,
			"%s · %.2f",
			game.ship_weapon_package_name(weapon),
			recipe.weapon_capability_scale,
		)
	}
}

draw_ship_single_hull_strike_weapon_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("STRIKE HULL WEAPON INTEGRATION", 38, 22, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"MATCHED INTERCEPTOR PRESSURE SHELL  |  SEVEN DORSAL INSTALLATIONS · COMMON TOP VIEW",
		39,
		53,
		TYPE_LABEL,
		UX.dim,
	)
	packages := [7]game.Ship_Weapon_Package {
		.Chemical_Autocannon,
		.Coilgun_Battery,
		.Railgun_Battery,
		.Defensive_Laser,
		.Offensive_Laser,
		.Guided_Missiles,
		.Heavy_Torpedoes,
	}
	names := [7]string {
		"AUTOCANNON",
		"COILGUN",
		"RAILGUN",
		"DEFENSIVE LASER",
		"OFFENSIVE LASER",
		"GUIDED MISSILES",
		"HEAVY TORPEDOES",
	}
	camera := Ship_Generator_Camera{0, math.PI * .5, 1}
	for weapon, index in packages {
		column, row := index % 4, index / 4
		x, y := f32(24 + column * 307), f32(88 + row * 304)
		ship := ship_generator_contact_identity(24301, 24301, .Strike, 0)
		ship.generator_kind = .Single_Hull
		ship.construction_style = .Machine_Partnership
		ship.weapon_package = weapon
		recipe := game.procedural_ship_generate_for_ship(ship)
		panel(R(x, y, 291, 286))
		draw_procedural_ship(&recipe, R(x + 8, y + 10, 275, 178), camera, false)
		draw_text(names[index], x + 14, y + 204, TYPE_HEADING, UX.text)
		draw_fmt(
			x + 14,
			y + 240,
			TYPE_FINE,
			UX.info,
			"%s · %.2f",
			game.ship_weapon_package_name(weapon),
			recipe.weapon_capability_scale,
		)
	}
}

draw_ship_strike_weapon_lineage_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("STRIKE WEAPON LINEAGE", 38, 22, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"THREE CONSTRUCTION SEEDS  |  GUIDED RACKS ABOVE · HEAVY CRADLES BELOW",
		39,
		53,
		TYPE_LABEL,
		UX.dim,
	)
	camera := Ship_Generator_Camera{0, math.PI * .5, 1}
	// Sample both service-side bits and a later rack phase rather than using
	// consecutive seeds which can legitimately land in the same variation bin.
	seeds := [3]u64{24301, 24309, 24429}
	for row in 0 ..< 2 do for seed, column in seeds {
		weapon :=
			row == 0 ? game.Ship_Weapon_Package.Guided_Missiles : game.Ship_Weapon_Package.Heavy_Torpedoes
		x, y := f32(24 + column * 410), f32(88 + row * 304)
		ship := ship_generator_contact_identity(seed, seed, .Strike, 0)
		ship.generator_kind = .Single_Hull
		ship.construction_style = .Machine_Partnership
		ship.weapon_package = weapon
		recipe := game.procedural_ship_generate_for_ship(ship)
		panel(R(x, y, 390, 286))
		draw_procedural_ship(&recipe, R(x + 12, y + 10, 366, 178), camera, false)
		draw_fmt(x + 18, y + 204, TYPE_HEADING, UX.text, "SEED %d", seed)
		draw_fmt(
			x + 18,
			y + 240,
			TYPE_CAPTION,
			UX.info,
			"%s · SERVICE SIDE %s",
			game.ship_weapon_package_name(weapon),
			(seed >> 3) & 1 == 0 ? "PORT" : "STARBOARD",
		)
	}
}

draw_ship_strike_ordnance_multiview_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("STRIKE ORDNANCE INSTALLATION AUDIT", 38, 22, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"MATCHED HULL AND SEED  |  TOP · SIDE · THREE-QUARTER",
		39,
		53,
		TYPE_LABEL,
		UX.dim,
	)
	cameras := [3]Ship_Generator_Camera {
		{0, math.PI * .5, 1},
		{0, 0, 1},
		{.52, .55, 1},
	}
	view_names := [3]string{"TOP", "SIDE", "THREE-QUARTER"}
	for row in 0 ..< 2 do for camera, column in cameras {
		weapon :=
			row == 0 ? game.Ship_Weapon_Package.Guided_Missiles : game.Ship_Weapon_Package.Heavy_Torpedoes
		x, y := f32(24 + column * 410), f32(88 + row * 304)
		ship := ship_generator_contact_identity(24309, 24309, .Strike, 0)
		ship.generator_kind = .Single_Hull
		ship.construction_style = .Machine_Partnership
		ship.weapon_package = weapon
		recipe := game.procedural_ship_generate_for_ship(ship)
		panel(R(x, y, 390, 286))
		draw_procedural_ship(&recipe, R(x + 12, y + 10, 366, 178), camera, false)
		draw_text(view_names[column], x + 18, y + 204, TYPE_HEADING, UX.text)
		draw_fmt(
			x + 18,
			y + 240,
			TYPE_CAPTION,
			UX.info,
			"%s · SEED %d",
			game.ship_weapon_package_name(weapon),
			recipe.seed,
		)
	}
}

draw_ship_damage_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("HULL HISTORY MATRIX", 38, 22, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"6 VARIANTS  x  6 DAMAGE / REPAIR STATES  |  ASSEMBLED-HULL REGRESSION",
		39,
		53,
		TYPE_LABEL,
		UX.dim,
	)
	row_names := [6]string{"SCRAPES", "BURNS", "PUNCTURES", "BREACHES", "REPAIRS", "SCARS"}
	grid_x, grid_y := f32(150), f32(112)
	cell_w, cell_h := f32(176), f32(92)
	config := game.default_ship_generator_config(0)
	config.role = .Escort
	config.role_locked = true
	config.hull_class = .Fleet_Ship
	ship := game.generate_ship(0x5ca7, config)
	for column in 0 ..< 6 do draw_fmt(grid_x + f32(column) * cell_w + 66, 84, TYPE_CAPTION, UX.info, "V%02d", column + 1)
	for row in 0 ..< 6 {
		y := grid_y + f32(row) * cell_h
		draw_text(row_names[row], 34, y + 36, TYPE_CAPTION, UX.text)
		for column in 0 ..< 6 {
			x := grid_x + f32(column) * cell_w
			panel(R(x, y, cell_w - 10, cell_h - 8))
			center_x, center_y := x + (cell_w - 10) / 2, y + 40
			draw_ship_constellation_marker(ship, center_x, center_y, false, 1.45)
			hull := ship_marker_rect(ship, center_x, center_y, false, 1.45)
			draw_ship_atlas_cell(
				ship_damage_texture,
				row * 6 + column,
				ship_marker_damage_rect(hull),
				rl.Color{255, 255, 255, 235},
			)
		}
	}
}

draw_ship_service_board :: proc() {
	rl.DrawRectangle(0, 0, UX_W, UX_H, UX.void)
	draw_text("SHIP SERVICE HERALDRY", 38, 28, TYPE_HEADING_LARGE, UX.text)
	draw_text(
		"STABLE REGISTRY  |  SIX PERSISTENT SERVICE RANKS  |  CONSTRUCTION UNCHANGED",
		39,
		59,
		TYPE_LABEL,
		UX.dim,
	)
	scores := [6]i32{1, 3, 6, 9, 13, 18}
	config := game.default_ship_generator_config(0)
	config.role = .Survey
	config.role_locked = true
	config.hull_class = .Fleet_Ship
	base := game.generate_ship(0x5e7a, config)
	for score, rank in scores {
		x := f32(135 + rank * 202)
		ship := base
		ship.experience = score
		panel(R(x - 82, 158, 164, 382), true)
		draw_fmt(x - 34, 184, TYPE_LABEL, UX.info, "RANK %d", rank + 1)
		draw_ship_constellation_marker(ship, x, 325, false, 3.1)
		recipe := ship_render_recipe(ship)
		draw_ship_atlas_cell(ship_marking_texture, recipe.service_marking, R(x - 24, 390, 48, 48))
		draw_fmt(x - 52, 462, TYPE_FINE, UX.text, "SERVICE %02d", score)
		draw_fmt(x - 49, 486, TYPE_MICRO, UX.dim, "MARK %02d", recipe.service_marking - 11)
	}
}
