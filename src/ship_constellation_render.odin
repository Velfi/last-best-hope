package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:os"
import filepath "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"
import ui "zelda_engine:ui"

draw_ship_constellation_marker :: proc(
	ship: game.Ship,
	x, y: f32,
	selected := false,
	presentation_scale := f32(1),
	structural_hatch := rl.HATCH_DISABLED,
) {
	rect := ship_marker_rect(ship, x, y, selected, presentation_scale)
	if selected {
		// Selection is an archival registration mark, not a colored spotlight.
		// Keeping its center black preserves the ship's engraved silhouette and
		// makes cyan-grey carry information without becoming the composition.
		radius := max(rect.width, rect.height) * .62
		outer := rl.Color{104, 181, 198, 190}
		inner := rl.Color{104, 181, 198, 82}
		ring_radii := [2]f32{radius, radius - 4}
		for ring_radius, ring_index in ring_radii {
			ring_color := ring_index == 0 ? outer : inner
			for segment in 0 ..< 24 {
				a := f32(segment) * math.TAU / 24
				b := f32(segment + 1) * math.TAU / 24
				rl.DrawLineEx(
					V(
						x + f32(math.cos(f64(a))) * ring_radius,
						y + f32(math.sin(f64(a))) * ring_radius,
					),
					V(
						x + f32(math.cos(f64(b))) * ring_radius,
						y + f32(math.sin(f64(b))) * ring_radius,
					),
					1,
					ring_color,
				)
			}
		}
		tick := f32(7)
		gap := f32(3)
		directions := [4]rl.Vector2{V(1, 0), V(0, 1), V(-1, 0), V(0, -1)}
		for direction in directions {
			start := V(x + direction.x * (radius + gap), y + direction.y * (radius + gap))
			end := V(start.x + direction.x * tick, start.y + direction.y * tick)
			rl.DrawLineEx(start, end, 2, outer)
		}
	}
	// The live fleet no longer composites the legacy 2D component atlases. A
	// near-end-on procedural camera preserves the compact vertical marker while
	// keeping construction identity, damage, and service history on one renderer.
	recipe := game.procedural_ship_generate_for_ship(ship)
	marker_camera := Ship_Generator_Camera{math.PI * .5, 1.12, 1}
	draw_procedural_ship(
		&recipe,
		rect,
		marker_camera,
		false,
		{},
		false,
		0,
		ship_power_output_scale(ship),
	)
	if !ship.active do rl.DrawRectangleRec(rect, {3, 3, 3, 118})
}

@(test)
role_silhouettes_have_distinct_dominant_proportions :: proc(t: ^testing.T) {
	survey := ship_marker_rect(game.Ship{role = .Survey, hull_class = .Fleet_Ship}, 100, 100)
	agriculture := ship_marker_rect(
		game.Ship{role = .Agriculture, hull_class = .Fleet_Ship},
		100,
		100,
	)
	escort := ship_marker_rect(game.Ship{role = .Escort, hull_class = .Fleet_Ship}, 100, 100)
	colony := ship_marker_rect(game.Ship{role = .Colony, hull_class = .Fleet_Ship}, 100, 100)
	testing.expect(t, survey.height / survey.width > agriculture.height / agriculture.width)
	testing.expect(t, escort.height / escort.width > colony.height / colony.width)
	testing.expect(t, agriculture.width > survey.width)
}

@(test)
history_attachment_is_stable_asymmetric_and_history_gated :: proc(t: ^testing.T) {
	ship := game.Ship {
		id                = 7,
		construction_seed = 0x7719,
		role              = .Foundry,
		hull_class        = .Fleet_Ship,
	}
	hull := ship_marker_rect(ship, 100, 100)
	testing.expect(t, !ship_history_attachment_visible(ship))
	ship.history_count = 1
	testing.expect(t, ship_history_attachment_visible(ship))
	first, second :=
		ship_history_attachment_rect(hull, ship), ship_history_attachment_rect(hull, ship)
	testing.expect_value(t, first, second)
	center := first.x + first.width / 2
	testing.expect(t, math.abs(f64(center - (hull.x + hull.width / 2))) > f64(hull.width * .20))
	// Every utility-family cell keeps its opaque body within approximately
	// 31%-69% of the cell. That conservative envelope must cross the hull edge.
	testing.expect(t, first.x + first.width * .69 > hull.x)
	testing.expect(t, first.x + first.width * .31 < hull.x + hull.width)
	changed := ship
	changed.damage = 3
	changed.power = 99
	testing.expect_value(t, ship_history_attachment_rect(hull, changed), first)
	recipe := ship_render_recipe(ship)
	upheld, broken, transformed, scarred := ship, ship, ship, ship
	upheld.promises_upheld = 1
	broken.promises_broken = 1
	transformed.promises_transformed = 1
	scarred.scar = .Hull_Breach
	components := [4]int {
		ship_history_attachment_component(upheld, recipe),
		ship_history_attachment_component(broken, recipe),
		ship_history_attachment_component(transformed, recipe),
		ship_history_attachment_component(scarred, recipe),
	}
	for component, i in components do for prior in components[:i] do testing.expect(t, component != prior)
}

@(test)
ship_constellation_markers_scale_with_class_and_selection :: proc(t: ^testing.T) {
	strike := game.Ship {
		hull_class = .Strike_Craft,
	}
	capital := game.Ship {
		hull_class = .Capital_Ship,
	}
	strike_rect := ship_marker_rect(strike, 100, 100)
	capital_rect := ship_marker_rect(capital, 100, 100)
	selected := ship_marker_rect(capital, 100, 100, true)
	board_scaled := ship_marker_rect(capital, 100, 100, false, 1.55)
	testing.expect(
		t,
		capital_rect.width > strike_rect.width && capital_rect.height > strike_rect.height,
	)
	testing.expect(t, selected.width > capital_rect.width && selected.height > capital_rect.height)
	testing.expect(t, selected.x >= 75 && selected.x + selected.width <= 125)
	testing.expect(t, board_scaled.width < 216 && board_scaled.height < 72)
}

@(test)
ship_role_modules_have_distinct_bounded_silhouette_profiles :: proc(t: ^testing.T) {
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
	hull := R(20, 30, 100, 160)
	rects: [8]rl.Rectangle
	for role, i in roles {
		rects[i] = ship_role_module_rect(hull, role)
		testing.expect(t, rects[i].x >= hull.x && rects[i].y >= hull.y)
		testing.expect(t, rects[i].x + rects[i].width <= hull.x + hull.width)
		testing.expect(t, rects[i].y + rects[i].height <= hull.y + hull.height)
		for prior in rects[:i] do testing.expect(t, prior != rects[i])
	}
	testing.expect(t, rects[7].width * rects[7].height > rects[5].width * rects[5].height)
	testing.expect(t, rects[0].width * rects[0].height > rects[6].width * rects[6].height)
	testing.expect(t, rects[5].y < rects[2].y)
}

@(test)
utility_hardpoints_cover_nine_stable_bounded_mounts :: proc(t: ^testing.T) {
	seen: [9]bool
	for identity in 1 ..= 512 {
		ship := game.Ship {
			id                = game.Ship_ID(identity),
			construction_seed = u64(identity),
			role              = .Colony,
			hull_class        = .Capital_Ship,
			mass_tonnes       = 120000000,
		}
		mount := ship_utility_mount_offset(ship)
		x_slot := int(math.round(f64(mount.x / .09))) + 1
		y_slot := int(math.round(f64(mount.y / .035))) + 1
		testing.expect(t, x_slot >= 0 && x_slot < 3 && y_slot >= 0 && y_slot < 3)
		if x_slot >= 0 && x_slot < 3 && y_slot >= 0 && y_slot < 3 do seen[y_slot * 3 + x_slot] = true
		hull := R(20, 30, 100, 160)
		rect := ship_marker_utility_rect(
			hull,
			ship_utility_volume_scale(ship) * ship_role_utility_scale(ship.role),
			mount,
		)
		testing.expect(t, rect.x >= hull.x && rect.y >= hull.y)
		testing.expect(t, rect.x + rect.width <= hull.x + hull.width)
		testing.expect(t, rect.y + rect.height <= hull.y + hull.height)
		changed := ship
		changed.role = .Survey
		changed.mass_tonnes = 4000000
		testing.expect_value(t, ship_utility_mount_offset(changed), mount)
	}
	for present in seen do testing.expect(t, present)
	center_sides: [2]bool
	for identity in 1 ..= 64 {
		center_ship := game.Ship {
			id                = game.Ship_ID(identity),
			construction_seed = u64(identity),
			utility_hardpoint = 5,
		}
		mount := ship_superstructure_mount_offset(center_ship)
		center_sides[mount.x > 0 ? 1 : 0] = true
		testing.expect(t, math.abs(f64(mount.x)) > .07)
	}
	for present in center_sides do testing.expect(t, present)
}

@(test)
superstructures_counterbalance_every_hardpoint_with_safe_bounds :: proc(t: ^testing.T) {
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
	classes := [5]game.Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	seen: [9]bool
	for identity in 1 ..= 512 {
		ship := game.Ship {
			id                = game.Ship_ID(identity),
			construction_seed = u64(identity),
		}
		slot := game.ship_construction_utility_hardpoint(ship)
		if seen[slot] do continue
		seen[slot] = true
		utility := ship_utility_mount_offset(ship)
		module_mount := ship_superstructure_mount_offset(ship)
		testing.expect(t, utility.x * module_mount.x <= 0 && utility.y * module_mount.y <= 0)
		if math.abs(utility.x) < .0001 {
			testing.expect(t, math.abs(f64(module_mount.x)) > .07)
		} else {
			testing.expect(t, math.abs(f64(module_mount.x + utility.x * .8)) < .0001)
		}
		changed := ship
		changed.role = .Colony
		changed.hull_class = .Capital_Ship
		changed.mass_tonnes = 120000000
		testing.expect_value(t, ship_superstructure_mount_offset(changed), module_mount)
		for role in roles do for hull_class in classes {
			hull := ship_marker_rect(game.Ship{hull_class = hull_class}, 100, 100)
			module := scale_rect_about_center(ship_role_module_rect(hull, role, module_mount), 1.1)
			testing.expect(t, module.x >= hull.x && module.y >= hull.y)
			testing.expect(t, module.x + module.width <= hull.x + hull.width)
			testing.expect(t, module.y + module.height <= hull.y + hull.height)
		}
	}
	for present in seen do testing.expect(t, present)
}

@(test)
ship_constellation_construction_layers_stay_inside_marker :: proc(t: ^testing.T) {
	ships := [3]game.Ship {
		{hull_class = .Strike_Craft, mass_tonnes = 18000},
		{hull_class = .Fleet_Ship, mass_tonnes = 45000},
		{hull_class = .Capital_Ship, mass_tonnes = 70000},
	}
	for ship in ships do for bow_profile in 0 ..< 3 {
		hull := ship_marker_rect(ship, 100, 100)
		layers := [13]rl.Rectangle{ship_marker_nose_rect(hull, ship.hull_class, ship_mass_nose_scale(ship), bow_profile), ship_marker_core_rect(hull, ship.hull_class, ship_mass_bulk_scale(ship)), ship_marker_wing_rect(hull, ship.hull_class, false), ship_marker_wing_rect(hull, ship.hull_class, true), ship_marker_engine_rect(hull, ship_engine_volume_scale(ship.hull_class) * ship_mass_engine_scale(ship)), ship_marker_livery_rect(hull), ship_marker_damage_rect(hull), ship_marker_utility_rect(hull, ship_utility_volume_scale(ship)), ship_role_module_rect(hull, ship.role), ship_marker_trait_rect(hull), ship_marker_registry_rect(hull), ship_marker_service_rect(hull), ship_marker_history_rect(hull)}
		for layer in layers {
			testing.expect(t, layer.x >= hull.x && layer.y >= hull.y)
			testing.expect(t, layer.x + layer.width <= hull.x + hull.width)
			testing.expect(t, layer.y + layer.height <= hull.y + hull.height)
		}
		compact := ship_marker_wing_rect(hull, ship.hull_class, false, 0)
		balanced := ship_marker_wing_rect(hull, ship.hull_class, false, 1)
		broad := ship_marker_wing_rect(hull, ship.hull_class, false, 2)
		testing.expect(t, compact.width < balanced.width && balanced.width < broad.width)
		testing.expect(t, compact.y > balanced.y && balanced.y > broad.y)
		for stance in 0 ..< 3 do for side in 0 ..< 2 {
			right := side == 1
			wing := ship_marker_wing_rect(hull, ship.hull_class, right, stance)
			testing.expect(t, wing.x >= hull.x && wing.y >= hull.y)
			testing.expect(t, wing.x + wing.width <= hull.x + hull.width)
			testing.expect(t, wing.y + wing.height <= hull.y + hull.height)
		}
	}
}

@(test)
founding_memory_earns_a_stable_service_mark_without_rebuilding_the_ship :: proc(t: ^testing.T) {
	ship := game.Ship {
		id                = 7,
		construction_seed = 0x7719,
		role              = .Archive,
		hull_class        = .Corvette,
	}
	baseline := ship_render_recipe(ship)
	testing.expect(t, !ship_service_mark_visible(ship))
	ship.memory_count = 1
	witness := ship_render_recipe(ship)
	testing.expect(t, ship_service_mark_visible(ship))
	testing.expect_value(t, witness.registry_marking, baseline.registry_marking)
	testing.expect_value(t, witness.core, baseline.core)
	testing.expect_value(t, witness.nose, baseline.nose)
	ship.experience = 2
	ship.memory_count = 0
	testing.expect(t, ship_service_mark_visible(ship))
	testing.expect_value(t, ship_render_recipe(ship).registry_marking, baseline.registry_marking)
	ship.promises_upheld = 1
	testing.expect(t, ship_history_mark_visible(ship))
	testing.expect_value(t, ship_render_recipe(ship).registry_marking, baseline.registry_marking)
}

ship_variation_board_ship :: proc(
	role: game.Role,
	hull_class: game.Hull_Class,
	cell, variant: int,
) -> game.Ship {
	target := clamp(variant, 0, 2)
	seen: [3]int
	unique := 0
	fallback: game.Ship
	for candidate in 0 ..< 64 {
		config := game.default_ship_generator_config(cell * 3 + unique)
		config.role = role
		config.role_locked = true
		config.hull_class = hull_class
		config.mass_percent = 100
		config.variation_percent = 12
		seed := 0x51a7 + u64(cell) * 0x9e3779b97f4a7c15 + u64(candidate) * 0xbf58476d1ce4e5b9
		ship := game.generate_ship(seed, config)
		fallback = ship
		fingerprint := ship_recipe_fingerprint(ship_render_recipe(ship))
		duplicate := false
		for prior in seen[:unique] do if prior == fingerprint {duplicate = true; break}
		if duplicate do continue
		if unique == target do return ship
		seen[unique] = fingerprint
		unique += 1
	}
	return fallback
}

ship_recipe_fingerprint :: proc(recipe: Ship_Render_Recipe) -> int {
	return(
		recipe.core +
		recipe.nose * 6 +
		recipe.engine * 36 +
		recipe.wing * 216 +
		recipe.utility * 1296 +
		recipe.wing_stance * 7776 +
		recipe.keel_profile * 23328 +
		recipe.drive_layout * 69984 +
		recipe.bow_profile * 209952 +
		recipe.wing_sweep * 629856 +
		recipe.drive_setback * 1889568 +
		recipe.mission_profile * 5668704 \
	)
}

@(test)
ship_variation_board_exposes_structural_variation_in_every_role_class_cell :: proc(t: ^testing.T) {
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
	families: [6]bool
	stances: [3]bool
	sweeps: [3]bool
	profiles: [3]bool
	drives: [3]bool
	setbacks: [3]bool
	mission_profiles: [3]bool
	bows: [3]bool
	hardpoints: [9]bool
	structural_profiles: [27]bool
	complete_recipes: [8 * 5 * 3]u64
	complete_recipe_count := 0
	for role, row in roles {
		for hull_class, column in classes {
			cell := row * len(classes) + column
			fingerprints: [3]int
			for variant in 0 ..< 3 {
				ship := ship_variation_board_ship(role, hull_class, cell, variant)
				testing.expect_value(t, ship.role, role)
				testing.expect_value(t, ship.hull_class, hull_class)
				recipe := ship_render_recipe(ship)
				fingerprints[variant] = ship_recipe_fingerprint(recipe)
				families[recipe.core] = true
				families[recipe.nose] = true
				families[recipe.engine] = true
				families[recipe.wing] = true
				families[recipe.utility] = true
				stances[recipe.wing_stance] = true
				sweeps[recipe.wing_sweep] = true
				profiles[recipe.keel_profile] = true
				drives[recipe.drive_layout] = true
				setbacks[recipe.drive_setback] = true
				mission_profiles[recipe.mission_profile] = true
				bows[recipe.bow_profile] = true
				hardpoints[game.ship_construction_utility_hardpoint(ship)] = true
				structural_profiles[game.ship_construction_structural_profile(ship)] = true
				complete := game.ship_construction_recipe_fingerprint(ship)
				for prior in complete_recipes[:complete_recipe_count] do testing.expect(t, prior != complete)
				complete_recipes[complete_recipe_count] = complete
				complete_recipe_count += 1
			}
			testing.expect(t, fingerprints[0] != fingerprints[1])
			testing.expect(t, fingerprints[0] != fingerprints[2])
			testing.expect(t, fingerprints[1] != fingerprints[2])
		}
	}
	for present in families do testing.expect(t, present)
	for present in stances do testing.expect(t, present)
	for present in sweeps do testing.expect(t, present)
	for present in profiles do testing.expect(t, present)
	for present in drives do testing.expect(t, present)
	for present in setbacks do testing.expect(t, present)
	for present in mission_profiles do testing.expect(t, present)
	for present in bows do testing.expect(t, present)
	for present in hardpoints do testing.expect(t, present)
	for present in structural_profiles do testing.expect(t, present)
	testing.expect_value(t, complete_recipe_count, len(complete_recipes))
}
