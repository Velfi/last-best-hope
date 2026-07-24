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

@(test)
ship_role_profiles_create_semantic_silhouettes :: proc(t: ^testing.T) {
	testing.expect(t, ship_role_utility_scale(.Colony) > ship_role_utility_scale(.Archive))
	testing.expect(t, ship_role_utility_scale(.Habitat) > ship_role_utility_scale(.Survey))
	testing.expect(t, ship_role_utility_scale(.Agriculture) > ship_role_utility_scale(.Escort))
	testing.expect(t, ship_role_engine_scale(.Escort) > ship_role_engine_scale(.Habitat))
	testing.expect(t, ship_role_engine_scale(.Foundry) > ship_role_engine_scale(.Hospital))
}

@(test)
ship_role_volume_profiles_stay_inside_every_marker_hull :: proc(t: ^testing.T) {
	classes := [5]game.Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	for hull_class in classes {
		low, high := game.ship_hull_mass_range(hull_class)
		for role_value in 0 ..< 8 {
			role := game.Role(role_value)
			hull := ship_marker_rect(game.Ship{hull_class = hull_class}, 100, 100)
			engine_ship := game.Ship {
				hull_class  = hull_class,
				mass_tonnes = high,
			}
			engine := ship_marker_engine_rect(
				hull,
				ship_engine_volume_scale(hull_class) *
				ship_role_engine_scale(role) *
				ship_mass_engine_scale(engine_ship),
			)
			utility := ship_marker_utility_rect(
				hull,
				ship_utility_volume_scale(game.Ship{hull_class = hull_class, mass_tonnes = high}) *
				ship_role_utility_scale(role),
			)
			testing.expect(t, engine.x >= hull.x && engine.x + engine.width <= hull.x + hull.width)
			testing.expect(
				t,
				utility.x >= hull.x && utility.x + utility.width <= hull.x + hull.width,
			)
			testing.expect(
				t,
				utility.y >= hull.y && utility.y + utility.height <= hull.y + hull.height,
			)
			minimum := ship_marker_utility_rect(
				hull,
				ship_utility_volume_scale(game.Ship{hull_class = hull_class, mass_tonnes = low}) *
				ship_role_utility_scale(role),
			)
			testing.expect(t, utility.width > minimum.width && utility.height > minimum.height)
		}
	}
}

@(test)
drive_layouts_scale_engines_and_exhausts_monotonically_with_safe_bounds :: proc(t: ^testing.T) {
	hull := R(20, 30, 100, 160)
	engine_widths, effect_widths: [3]f32
	for layout in 0 ..< 3 {
		drive_scale := ship_drive_layout_scale(layout)
		engine := ship_marker_engine_rect(hull, 1, drive_scale)
		effect := ship_marker_effect_rect(hull, 1, 2, drive_scale)
		engine_widths[layout] = engine.width
		effect_widths[layout] = effect.width
		testing.expect(t, engine.x >= hull.x && engine.x + engine.width <= hull.x + hull.width)
		testing.expect(t, effect.x >= hull.x && effect.x + effect.width <= hull.x + hull.width)
	}
	testing.expect(t, engine_widths[0] < engine_widths[1] && engine_widths[1] < engine_widths[2])
	testing.expect(t, effect_widths[0] < effect_widths[1] && effect_widths[1] < effect_widths[2])
	twin_engine_pair := ship_drive_pair_rects(
		ship_marker_engine_rect(hull, 1, ship_drive_layout_scale(1)),
		1,
	)
	outboard_engine_pair := ship_drive_pair_rects(
		ship_marker_engine_rect(hull, 1, ship_drive_layout_scale(2)),
		2,
	)
	twin_effect_pair := ship_drive_pair_rects(
		ship_marker_effect_rect(hull, 1, 2, ship_drive_layout_scale(1)),
		1,
	)
	outboard_effect_pair := ship_drive_pair_rects(
		ship_marker_effect_rect(hull, 1, 2, ship_drive_layout_scale(2)),
		2,
	)
	pairs := [4][2]rl.Rectangle {
		twin_engine_pair,
		outboard_engine_pair,
		twin_effect_pair,
		outboard_effect_pair,
	}
	for pair in pairs {
		testing.expect_value(t, pair[0].width, pair[1].width)
		testing.expect_value(t, pair[0].height, pair[1].height)
		testing.expect(t, pair[0].x + pair[0].width < pair[1].x)
		left_margin := pair[0].x - hull.x
		right_margin := hull.x + hull.width - (pair[1].x + pair[1].width)
		testing.expect(t, math.abs(f64(left_margin - right_margin)) < .001)
	}
	twin_engine_gap := twin_engine_pair[1].x - (twin_engine_pair[0].x + twin_engine_pair[0].width)
	outboard_engine_gap :=
		outboard_engine_pair[1].x - (outboard_engine_pair[0].x + outboard_engine_pair[0].width)
	twin_effect_gap := twin_effect_pair[1].x - (twin_effect_pair[0].x + twin_effect_pair[0].width)
	outboard_effect_gap :=
		outboard_effect_pair[1].x - (outboard_effect_pair[0].x + outboard_effect_pair[0].width)
	testing.expect(t, twin_engine_gap < outboard_engine_gap)
	testing.expect(t, twin_effect_gap < outboard_effect_gap)
	classes := [5]game.Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	for hull_class in classes do for role_value in 0 ..< 8 {
		_, high := game.ship_hull_mass_range(hull_class)
		ship := game.Ship {
			role        = game.Role(role_value),
			hull_class  = hull_class,
			mass_tonnes = high,
		}
		marker := ship_marker_rect(ship, 100, 100)
		outboard := ship_marker_engine_rect(marker, ship_engine_volume_scale(hull_class) * ship_role_engine_scale(ship.role) * ship_mass_engine_scale(ship), ship_drive_layout_scale(2))
		testing.expect(t, outboard.x >= marker.x && outboard.x + outboard.width <= marker.x + marker.width)
	}
}

@(test)
within_class_mass_profiles_are_monotonic_bounded_and_centered :: proc(t: ^testing.T) {
	classes := [5]game.Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	for hull_class in classes {
		low, high := game.ship_hull_mass_range(hull_class)
		light := game.Ship {
			hull_class  = hull_class,
			mass_tonnes = low,
		}
		heavy := game.Ship {
			hull_class  = hull_class,
			mass_tonnes = high,
		}
		hull := ship_marker_rect(heavy, 100, 100)
		light_core := ship_marker_core_rect(hull, hull_class, ship_mass_bulk_scale(light))
		heavy_core := ship_marker_core_rect(hull, hull_class, ship_mass_bulk_scale(heavy))
		light_nose := ship_marker_nose_rect(hull, hull_class, ship_mass_nose_scale(light))
		heavy_nose := ship_marker_nose_rect(hull, hull_class, ship_mass_nose_scale(heavy))
		light_engine := ship_marker_engine_rect(
			hull,
			ship_engine_volume_scale(hull_class) * ship_mass_engine_scale(light),
		)
		heavy_engine := ship_marker_engine_rect(
			hull,
			ship_engine_volume_scale(hull_class) * ship_mass_engine_scale(heavy),
		)
		testing.expect(t, light_core.width < heavy_core.width)
		testing.expect(t, light_nose.width < heavy_nose.width)
		testing.expect(t, light_engine.width < heavy_engine.width)
		heavy_layers := [3]rl.Rectangle{heavy_core, heavy_nose, heavy_engine}
		for rect in heavy_layers {
			testing.expect(t, rect.x >= hull.x && rect.x + rect.width <= hull.x + hull.width)
		}
		testing.expect(t, math.abs(f64((light_core.x + light_core.width / 2) - 100)) < .001)
		testing.expect(t, math.abs(f64((heavy_core.x + heavy_core.width / 2) - 100)) < .001)
	}
	legacy := game.Ship {
		hull_class = .Fleet_Ship,
	}
	testing.expect(t, math.abs(f64(ship_mass_percentile(legacy) - .5)) < .001)
	testing.expect(t, math.abs(f64(ship_mass_bulk_scale(legacy) - 1)) < .001)
}

@(test)
power_output_profile_is_normalized_bounded_and_construction_neutral :: proc(t: ^testing.T) {
	base_ship := game.Ship {
		id                = 4,
		construction_seed = 0x9173,
		role              = .Escort,
		hull_class        = .Fleet_Ship,
		power             = 10,
		active            = true,
	}
	low_ship, high_ship := base_ship, base_ship
	low_ship.power = 5
	high_ship.power = 15
	low := ship_power_output_scale(low_ship)
	neutral := ship_power_output_scale(base_ship)
	high := ship_power_output_scale(high_ship)
	testing.expect(t, math.abs(f64(low - .85)) < .001)
	testing.expect(t, math.abs(f64(neutral - 1)) < .001)
	testing.expect(t, math.abs(f64(high - 1.15)) < .001)
	testing.expect(t, low < neutral && neutral < high)
	testing.expect(
		t,
		math.abs(
			f64(ship_power_output_scale(game.Ship{role = .Escort, hull_class = .Fleet_Ship}) - 1),
		) <
		.001,
	)
	hull := ship_marker_rect(base_ship, 100, 100)
	scales := [3]f32{low, neutral, high}
	for scale in scales {
		effect := ship_marker_effect_rect(hull, scale)
		testing.expect(t, effect.y < hull.y + hull.height)
		testing.expect(t, effect.y + effect.height <= hull.y + hull.height * 1.76)
		testing.expect(t, effect.x >= hull.x && effect.x + effect.width <= hull.x + hull.width)
	}
	base_recipe := ship_render_recipe(base_ship)
	variants := [2]game.Ship{low_ship, high_ship}
	for variant in variants {
		recipe := ship_render_recipe(variant)
		testing.expect_value(t, recipe.core, base_recipe.core)
		testing.expect_value(t, recipe.engine, base_recipe.engine)
		testing.expect_value(t, recipe.effect, base_recipe.effect)
	}
}

@(test)
crew_occupancy_profile_is_normalized_bounded_and_construction_neutral :: proc(t: ^testing.T) {
	baseline_crew := game.ship_hull_class_crew(.Escort, .Fleet_Ship)
	base_ship := game.Ship {
		id                = 6,
		construction_seed = 0x8173,
		role              = .Escort,
		hull_class        = .Fleet_Ship,
		crew              = baseline_crew,
		active            = true,
	}
	low_ship, high_ship := base_ship, base_ship
	low_ship.crew = max(baseline_crew / 2, 1)
	high_ship.crew = baseline_crew * 3 / 2
	low := ship_crew_occupancy_scale(low_ship)
	neutral := ship_crew_occupancy_scale(base_ship)
	high := ship_crew_occupancy_scale(high_ship)
	testing.expect(t, math.abs(f64(low - .90)) < .011)
	testing.expect(t, math.abs(f64(neutral - 1)) < .001)
	testing.expect(t, math.abs(f64(high - 1.10)) < .001)
	testing.expect(t, low < neutral && neutral < high)
	testing.expect(
		t,
		math.abs(
			f64(
				ship_crew_occupancy_scale(game.Ship{role = .Escort, hull_class = .Fleet_Ship}) - 1,
			),
		) <
		.001,
	)
	base_recipe := ship_render_recipe(base_ship)
	variants := [2]game.Ship{low_ship, high_ship}
	for variant in variants {
		recipe := ship_render_recipe(variant)
		testing.expect_value(t, recipe.core, base_recipe.core)
		testing.expect_value(t, recipe.role_module, base_recipe.role_module)
	}
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
	hull := R(20, 30, 100, 160)
	for role in roles do for hull_class in classes {
		ship := game.Ship {
			role       = role,
			hull_class = hull_class,
			crew       = game.ship_hull_class_crew(role, hull_class) * 3 / 2,
		}
		module := scale_rect_about_center(ship_role_module_rect(hull, role), ship_crew_occupancy_scale(ship))
		testing.expect(t, module.x >= hull.x && module.y >= hull.y)
		testing.expect(t, module.x + module.width <= hull.x + hull.width)
		testing.expect(t, module.y + module.height <= hull.y + hull.height)
	}
}

ship_marker_rect :: proc(
	ship: game.Ship,
	x, y: f32,
	selected := false,
	presentation_scale := f32(1),
) -> rl.Rectangle {
	base_width: f32 = (selected ? 38 : 29) * presentation_scale
	base_height: f32 = (selected ? 44 : 34) * presentation_scale
	keel_width, keel_length := ship_keel_profile_scale(game.ship_construction_keel_profile(ship))
	role_width, role_length := ship_role_silhouette_scale(ship.role)
	width := base_width * ship_hull_width_scale(ship.hull_class) * keel_width * role_width
	height := base_height * ship_hull_length_scale(ship.hull_class) * keel_length * role_length
	return R(x - width / 2, y - height / 2, width, height)
}

ship_history_attachment_visible :: proc(ship: game.Ship) -> bool {
	return(
		ship.scar != .None ||
		ship.history_count > 0 ||
		ship.history_record_count > 0 ||
		ship.promises_upheld > 0 ||
		ship.promises_broken > 0 ||
		ship.promises_transformed > 0 \
	)
}

// History changes the outline instead of becoming another decal. The side and
// station are stable for a ship, so a repaired or politically changed vessel
// remains recognizable in later records.
ship_history_attachment_rect :: proc(hull: rl.Rectangle, ship: game.Ship) -> rl.Rectangle {
	identity := ship.construction_seed
	if identity == 0 do identity = u64(max(int(ship.id), 1))
	mixed := game.ship_construction_visual_mix(identity ~ 0x452821e638d01377)
	right := (mixed & 1) != 0
	width := hull.width * .34
	height := hull.height * .25
	// Utility cells keep roughly one sixth of their width as transparent atlas
	// padding. Overlap the destination far enough that the opaque machinery,
	// not merely its rectangle, visibly meets the hull socket.
	x := right ? hull.x + hull.width - width * .70 : hull.x - width * .30
	y := hull.y + hull.height * (.30 + f32((mixed >> 8) % 3) * .12)
	return R(x, y, width, height)
}

ship_history_attachment_component :: proc(ship: game.Ship, recipe: Ship_Render_Recipe) -> int {
	if ship.scar != .None do return 12 + recipe.engine
	switch game.ship_promise_record(ship) {
	case .Broken:
		return 24 + (recipe.utility + 3) % 6
	case .Transformed:
		return 30 + recipe.role_module
	case .None, .Upheld:
	}
	return 24 + recipe.utility
}

ship_marker_engine_rect :: proc(
	hull: rl.Rectangle,
	volume_scale := f32(1),
	drive_scale := f32(1),
	drive_setback := 1,
) -> rl.Rectangle {
	width := hull.width * .74 * min(volume_scale * drive_scale, f32(1.32))
	return R(
		hull.x + (hull.width - width) / 2,
		hull.y + hull.height * (.37 + ship_drive_setback_offset(drive_setback)),
		width,
		hull.height * .45,
	)
}

@(test)
drive_setbacks_move_engine_and_exhaust_together_with_safe_hull_bounds :: proc(t: ^testing.T) {
	classes := [5]game.Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	for hull_class in classes {
		hull := ship_marker_rect(game.Ship{hull_class = hull_class}, 100, 100, false, 2)
		engines: [3]rl.Rectangle
		effects: [3]rl.Rectangle
		for setback in 0 ..< 3 {
			engines[setback] = ship_marker_engine_rect(hull, 1, 1, setback)
			effects[setback] = ship_marker_effect_rect(hull, 1, 2, 1, setback)
			engine := engines[setback]
			testing.expect(t, engine.x >= hull.x && engine.y >= hull.y)
			testing.expect(t, engine.x + engine.width <= hull.x + hull.width)
			testing.expect(t, engine.y + engine.height <= hull.y + hull.height)
			testing.expect(t, effects[setback].y < engine.y + engine.height)
		}
		testing.expect(t, engines[0].y < engines[1].y && engines[1].y < engines[2].y)
		testing.expect(t, effects[0].y < effects[1].y && effects[1].y < effects[2].y)
		for setback in 0 ..< 3 do testing.expect(t, math.abs(f64((effects[setback].y - effects[1].y) - (engines[setback].y - engines[1].y))) < .001)
	}
}

ship_wing_stance_profile :: proc(stance: int) -> (width_scale, top_offset, height_scale: f32) {
	switch clamp(stance, 0, 2) {
	case 0:
		return .82, .035, .90
	case 2:
		return 1.18, -.035, 1.08
	}
	return 1, 0, 1
}

ship_wing_sweep_offset :: proc(sweep: int) -> f32 {
	switch clamp(sweep, 0, 2) {
	case 0:
		return -.025
	case 2:
		return .025
	}
	return 0
}

ship_marker_nose_rect :: proc(
	hull: rl.Rectangle,
	hull_class: game.Hull_Class = .Fleet_Ship,
	mass_scale := f32(1),
	bow_profile := 1,
	role: game.Role = .Habitat,
) -> rl.Rectangle {
	bow_width, bow_length := ship_bow_profile_scale(bow_profile)
	role_bow, _, _, _ := ship_role_massing_scale(role)
	width := hull.width * ship_nose_fraction(hull_class) * mass_scale * bow_width * role_bow
	height := hull.height * .46 * bow_length
	// Keep the longest needle crown inside the hull while retaining a common
	// shoulder line where every bow disappears beneath the core.
	bottom := hull.y + hull.height * .54
	return R(hull.x + (hull.width - width) / 2, bottom - height, width, height)
}

ship_marker_core_rect :: proc(
	hull: rl.Rectangle,
	hull_class: game.Hull_Class,
	mass_scale := f32(1),
	role: game.Role = .Habitat,
) -> rl.Rectangle {
	_, role_core, _, _ := ship_role_massing_scale(role)
	width := hull.width * ship_core_fraction(hull_class) * mass_scale * role_core
	return R(hull.x + (hull.width - width) / 2, hull.y, width, hull.height)
}

ship_marker_wing_rect :: proc(
	hull: rl.Rectangle,
	hull_class: game.Hull_Class,
	right: bool,
	stance := 1,
	sweep := 1,
	role: game.Role = .Habitat,
) -> rl.Rectangle {
	width_scale, stance_offset, height_scale := ship_wing_stance_profile(stance)
	_, _, role_wing, _ := ship_role_massing_scale(role)
	width := hull.width * ship_wing_fraction(hull_class) * width_scale * role_wing
	top, height := ship_wing_vertical_profile(hull_class)
	return R(
		right ? hull.x + hull.width - width : hull.x,
		hull.y + hull.height * (top + stance_offset + ship_wing_sweep_offset(sweep)),
		width,
		hull.height * height * height_scale,
	)
}

@(test)
wing_sweep_profiles_are_visibly_distinct_and_bounded_for_every_frame :: proc(t: ^testing.T) {
	classes := [5]game.Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	for hull_class in classes do for stance in 0 ..< 3 {
		hull := R(20, 30, 100, 160)
		forward := ship_marker_wing_rect(hull, hull_class, false, stance, 0)
		level := ship_marker_wing_rect(hull, hull_class, false, stance, 1)
		aft := ship_marker_wing_rect(hull, hull_class, false, stance, 2)
		testing.expect(t, forward.y < level.y && level.y < aft.y)
		rects := [3]rl.Rectangle{forward, level, aft}
		for rect in rects {
			testing.expect(t, rect.x >= hull.x && rect.y >= hull.y)
			testing.expect(t, rect.x + rect.width <= hull.x + hull.width)
			testing.expect(t, rect.y + rect.height <= hull.y + hull.height)
		}
	}
}

ship_marker_livery_rect :: proc(hull: rl.Rectangle) -> rl.Rectangle {
	return R(
		hull.x + hull.width * .31,
		hull.y + hull.height * .28,
		hull.width * .38,
		hull.height * .48,
	)
}

ship_marker_damage_rect :: proc(hull: rl.Rectangle) -> rl.Rectangle {
	return R(
		hull.x + hull.width * .1,
		hull.y + hull.height * .14,
		hull.width * .8,
		hull.height * .68,
	)
}

ship_utility_mount_offset :: proc(ship: game.Ship) -> rl.Vector2 {
	slot := game.ship_construction_utility_hardpoint(ship)
	horizontal := f32(slot % 3 - 1) * .09
	vertical := f32(slot / 3 - 1) * .035
	return V(horizontal, vertical)
}

ship_superstructure_mount_offset :: proc(ship: game.Ship) -> rl.Vector2 {
	utility := ship_utility_mount_offset(ship)
	// Large inhabited/mission volumes counterbalance the utility pod, revealing
	// both layers instead of stacking every construction on the centerline.
	horizontal := -utility.x * .80
	if math.abs(horizontal) < .0001 {
		horizontal = game.ship_construction_centerline_bias(ship) == 0 ? f32(-.072) : f32(.072)
	}
	return V(horizontal, -utility.y * .50)
}

ship_marker_utility_rect :: proc(
	hull: rl.Rectangle,
	volume_scale: f32,
	mount := rl.Vector2{},
) -> rl.Rectangle {
	width := hull.width * .34 * volume_scale
	height := hull.height * .34 * volume_scale
	return R(
		hull.x + (hull.width - width) / 2 + hull.width * mount.x,
		hull.y + hull.height * (.22 + mount.y),
		width,
		height,
	)
}

ship_role_module_rect :: proc(
	hull: rl.Rectangle,
	role: game.Role,
	mount := rl.Vector2{},
) -> rl.Rectangle {
	width, height, top := f32(.38), f32(.42), f32(.18)
	switch role {
	case .Habitat:
		width, height, top = .48, .52, .18
	case .Agriculture:
		width, height, top = .46, .50, .20
	case .Foundry:
		width, height, top = .40, .44, .28
	case .Archive:
		width, height, top = .32, .52, .14
	case .Hospital:
		width, height, top = .42, .46, .18
	case .Survey:
		width, height, top = .30, .36, .10
	case .Escort:
		width, height, top = .28, .32, .23
	case .Colony:
		width, height, top = .50, .55, .17
	}
	return R(
		hull.x + (hull.width - hull.width * width) / 2 + hull.width * mount.x,
		hull.y + hull.height * (top + mount.y),
		hull.width * width,
		hull.height * height,
	)
}

ship_marker_trait_rect :: proc(hull: rl.Rectangle) -> rl.Rectangle {
	size := min(hull.width * .27, f32(10))
	return R(hull.x + hull.width * .07, hull.y + hull.height * .58, size, size)
}

ship_marker_registry_rect :: proc(hull: rl.Rectangle) -> rl.Rectangle {
	size := min(hull.width * .20, f32(7))
	return R(hull.x + hull.width * .40, hull.y + hull.height * .70, size, size)
}

ship_marker_service_rect :: proc(hull: rl.Rectangle) -> rl.Rectangle {
	size := min(hull.width * .22, f32(8))
	return R(hull.x + hull.width * .74, hull.y + hull.height * .48, size, size)
}

ship_marker_history_rect :: proc(hull: rl.Rectangle) -> rl.Rectangle {
	size := min(hull.width * .20, f32(7))
	return R(hull.x + hull.width * .68, hull.y + hull.height * .66, size, size)
}

ship_marker_effect_visible :: proc(ship: game.Ship) -> bool {
	return ship.committed || ship.damage > 0 || !ship.active
}

ship_marker_effect_rect :: proc(
	hull: rl.Rectangle,
	power_scale: f32,
	effect_row := 2,
	drive_scale := f32(1),
	drive_setback := 1,
) -> rl.Rectangle {
	width_fraction, height_fraction, top_fraction := f32(.30), f32(.90), f32(.72)
	switch effect_row {
	case 0:
		width_fraction, height_fraction, top_fraction = .24, .34, .72
	case 1:
		width_fraction, height_fraction, top_fraction = .27, .64, .72
	case 2:
		width_fraction, height_fraction, top_fraction = .30, .90, .72
	case 3:
		width_fraction, height_fraction, top_fraction = .34, 1.02, .70
	case 4:
		width_fraction, height_fraction, top_fraction = .34, .72, .72
	case 5:
		width_fraction, height_fraction, top_fraction = .28, .56, .72
	}
	width := hull.width * width_fraction * power_scale * drive_scale
	return R(
		hull.x + (hull.width - width) / 2,
		hull.y + hull.height * (top_fraction + ship_drive_setback_offset(drive_setback)),
		width,
		hull.height * height_fraction * power_scale,
	)
}
