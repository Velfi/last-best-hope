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
scale_rect_about_center :: proc(rect: rl.Rectangle, scale: f32) -> rl.Rectangle {
	width, height := rect.width * scale, rect.height * scale
	return R(rect.x + (rect.width - width) / 2, rect.y + (rect.height - height) / 2, width, height)
}

ship_drive_setback_offset :: proc(setback: int) -> f32 {
	switch clamp(setback, 0, 2) {
	case 0:
		return -.035
	case 2:
		return .035
	}
	return 0
}

ship_preview_effect_rect :: proc(
	ship: game.Ship,
	effect_row: int,
	center_x: f32,
	drive_scale := f32(1),
	drive_setback := 1,
) -> rl.Rectangle {
	power_scale := ship_power_output_scale(ship)
	width, height, top := f32(30), f32(30), f32(200)
	switch effect_row {
	case 0:
		width, height, top = 30, 30, 200
	case 1:
		width, height, top = 34, 48, 204
	case 2:
		width, height, top = 38, 68, 204
	case 3:
		width, height, top = 42, 76, 202
	case 4:
		width, height, top = 40, 58, 202
	case 5:
		width, height, top = 34, 46, 202
	}
	width *= power_scale * drive_scale
	height *= power_scale
	top += ship_drive_setback_offset(drive_setback) * 154
	return R(center_x - width / 2, top, width, height)
}

ship_utility_volume_scale :: proc(ship: game.Ship) -> f32 {
	return .82 + ship_mass_percentile(ship) * .36
}

scale_ship_rect :: proc(
	rect: rl.Rectangle,
	center_x, center_y, width_scale, length_scale: f32,
) -> rl.Rectangle {
	return R(
		center_x + (rect.x - center_x) * width_scale,
		center_y + (rect.y - center_y) * length_scale,
		rect.width * width_scale,
		rect.height * length_scale,
	)
}

ship_drive_pair_rects :: proc(rect: rl.Rectangle, layout: int) -> [2]rl.Rectangle {
	gap_fraction := layout == 1 ? f32(.03) : f32(.14)
	pod_width := rect.width * (1 - gap_fraction) / 2
	return [2]rl.Rectangle {
		R(rect.x, rect.y, pod_width, rect.height),
		R(rect.x + rect.width - pod_width, rect.y, pod_width, rect.height),
	}
}

Ship_Preview_Context :: struct {
	ship:                                              game.Ship,
	recipe:                                            Ship_Render_Recipe,
	tint:                                              rl.Color,
	width_scale, length_scale:                         f32,
	center_x, center_y:                                f32,
	preview_hull, left_wing, right_wing:               rl.Rectangle,
	nose_rect, engine_rect, core_rect, preview_effect: rl.Rectangle,
}

draw_ship_preview_propulsion :: proc(ctx: ^Ship_Preview_Context) {
	if ctx.recipe.drive_layout > 0 {
		for plume in ship_drive_pair_rects(ctx.preview_effect, ctx.recipe.drive_layout) do draw_ship_effect_cell(ship_effect_texture, ctx.recipe.effect, scale_ship_rect(plume, ctx.center_x, ctx.center_y, ctx.width_scale, ctx.length_scale), ctx.tint)
	} else {
		draw_ship_effect_cell(
			ship_effect_texture,
			ctx.recipe.effect,
			scale_ship_rect(
				ctx.preview_effect,
				ctx.center_x,
				ctx.center_y,
				ctx.width_scale,
				ctx.length_scale,
			),
			ctx.tint,
		)
	}
}

draw_ship_preview_hull :: proc(ctx: ^Ship_Preview_Context) {
	draw_ship_atlas_crop(
		ship_component_texture,
		18 + ctx.recipe.wing,
		R(0, 18, 78, 181),
		scale_ship_rect(
			ctx.left_wing,
			ctx.center_x,
			ctx.center_y,
			ctx.width_scale,
			ctx.length_scale,
		),
		ctx.tint,
	)
	draw_ship_atlas_crop(
		ship_component_texture,
		18 + ctx.recipe.wing,
		R(131, 18, 78, 181),
		scale_ship_rect(
			ctx.right_wing,
			ctx.center_x,
			ctx.center_y,
			ctx.width_scale,
			ctx.length_scale,
		),
		ctx.tint,
	)
	// The source nose cells include their own lower hull. Crop to the cockpit crown
	// and bury its lower edge beneath the core so no detached fragment can appear.
	draw_ship_atlas_crop(
		ship_component_texture,
		6 + ctx.recipe.nose,
		R(35, 101, 139, 90),
		scale_ship_rect(
			ctx.nose_rect,
			ctx.center_x,
			ctx.center_y,
			ctx.width_scale,
			ctx.length_scale,
		),
		ctx.tint,
	)
	if ctx.recipe.drive_layout > 0 {
		engine_pods := ship_drive_pair_rects(ctx.engine_rect, ctx.recipe.drive_layout)
		draw_ship_atlas_crop(
			ship_component_texture,
			12 + ctx.recipe.engine,
			R(18, 54, 86.5, 128),
			scale_ship_rect(
				engine_pods[0],
				ctx.center_x,
				ctx.center_y,
				ctx.width_scale,
				ctx.length_scale,
			),
			ctx.tint,
		)
		draw_ship_atlas_crop(
			ship_component_texture,
			12 + ctx.recipe.engine,
			R(104.5, 54, 86.5, 128),
			scale_ship_rect(
				engine_pods[1],
				ctx.center_x,
				ctx.center_y,
				ctx.width_scale,
				ctx.length_scale,
			),
			ctx.tint,
		)
	} else {
		draw_ship_atlas_crop(
			ship_component_texture,
			12 + ctx.recipe.engine,
			R(18, 54, 173, 128),
			scale_ship_rect(
				ctx.engine_rect,
				ctx.center_x,
				ctx.center_y,
				ctx.width_scale,
				ctx.length_scale,
			),
			ctx.tint,
		)
	}
	draw_ship_atlas_crop(
		ship_component_texture,
		ctx.recipe.core,
		R(42, 12, 125, 185),
		scale_ship_rect(
			ctx.core_rect,
			ctx.center_x,
			ctx.center_y,
			ctx.width_scale,
			ctx.length_scale,
		),
		ctx.tint,
	)
}

draw_ship_preview_modules :: proc(ctx: ^Ship_Preview_Context, utility_scale: f32) -> rl.Rectangle {
	livery_tint := ctx.ship.active ? rl.Color{255, 255, 255, 145} : ctx.tint
	draw_ship_atlas_cell(
		ship_marking_texture,
		ctx.recipe.livery,
		scale_ship_rect(
			R(ctx.center_x - 34, 124, 68, 88),
			ctx.center_x,
			ctx.center_y,
			ctx.width_scale,
			ctx.length_scale,
		),
		livery_tint,
	)
	utility_rect := ship_marker_utility_rect(
		ctx.preview_hull,
		utility_scale,
		ship_utility_mount_offset(ctx.ship),
	)
	draw_ship_atlas_cell(
		ship_component_texture,
		24 + ctx.recipe.utility,
		scale_ship_rect(
			utility_rect,
			ctx.center_x,
			ctx.center_y,
			ctx.width_scale,
			ctx.length_scale,
		),
		ctx.tint,
	)
	role_rect := scale_rect_about_center(
		ship_role_module_rect(
			ctx.preview_hull,
			ctx.ship.role,
			ship_superstructure_mount_offset(ctx.ship),
		),
		ship_mission_module_scale(ctx.ship),
	)
	draw_ship_atlas_cell(
		ship_component_texture,
		30 + ctx.recipe.role_module,
		scale_ship_rect(role_rect, ctx.center_x, ctx.center_y, ctx.width_scale, ctx.length_scale),
		ctx.tint,
	)
	marking_rect := R(
		role_rect.x + role_rect.width * .11,
		role_rect.y + role_rect.height * .05,
		role_rect.width * .78,
		role_rect.height * .79,
	)
	draw_ship_atlas_cell(
		ship_marking_texture,
		ctx.recipe.role_marking,
		scale_ship_rect(
			marking_rect,
			ctx.center_x,
			ctx.center_y,
			ctx.width_scale,
			ctx.length_scale,
		),
		ctx.tint,
	)
	return role_rect
}

draw_ship_preview_identity :: proc(ctx: ^Ship_Preview_Context) {
	draw_ship_atlas_cell(
		ship_marking_texture,
		ctx.recipe.community_marking,
		R(ctx.center_x - 14, 158, 28, 32),
		ctx.tint,
	)
	if ctx.recipe.trait_marking >= 0 do draw_ship_atlas_cell(ship_marking_texture, ctx.recipe.trait_marking, R(ctx.center_x - 35, 177, 19, 21), ctx.tint)
	if ship_registry_mark_visible(ctx.ship) do draw_ship_atlas_cell(ship_marking_texture, ctx.recipe.registry_marking, R(ctx.center_x - 11, 181, 22, 24), ctx.tint)
	if ctx.recipe.service_marking >= 0 do draw_ship_atlas_cell(ship_marking_texture, ctx.recipe.service_marking, R(ctx.center_x + 34, 165, 18, 20), ctx.tint)
	if ctx.recipe.history_marking >= 0 do draw_ship_atlas_cell(ship_marking_texture, ctx.recipe.history_marking, R(ctx.center_x + 13, 176, 22, 25), ctx.tint)
	if ship_damage_mark_visible(ctx.ship) do draw_ship_atlas_cell(ship_damage_texture, ctx.recipe.damage, scale_ship_rect(R(ctx.center_x - 38, 101, 76, 94), ctx.center_x, ctx.center_y, ctx.width_scale, ctx.length_scale), ctx.tint)
	if ship_history_attachment_visible(ctx.ship) {
		attachment := ship_history_attachment_rect(
			scale_ship_rect(
				ctx.core_rect,
				ctx.center_x,
				ctx.center_y,
				ctx.width_scale,
				ctx.length_scale,
			),
			ctx.ship,
		)
		draw_ship_atlas_cell(
			ship_component_texture,
			ship_history_attachment_component(ctx.ship, ctx.recipe),
			attachment,
			ctx.tint,
		)
	}
}

@(test)
ship_render_recipes_are_stable_and_role_specific :: proc(t: ^testing.T) {
	ship := game.Ship {
		id         = 7,
		role       = .Survey,
		hull_class = .Corvette,
	}
	a, b := ship_render_recipe(ship), ship_render_recipe(ship)
	testing.expect_value(t, a, b)
	ship.role = .Hospital
	c := ship_render_recipe(ship)
	testing.expect(t, c.role_module != a.role_module)
	testing.expect(
		t,
		a.core >= 0 && a.core < 6 && a.nose >= 0 && a.nose < 6 && a.effect >= 0 && a.effect < 36,
	)
}

@(test)
ship_render_recipe_uses_persistent_construction_identity_with_legacy_fallback :: proc(
	t: ^testing.T,
) {
	ship := game.Ship {
		id                = 7,
		construction_seed = 0,
		role              = .Survey,
	}
	legacy_a := ship_render_recipe(ship)
	legacy_b := ship_render_recipe(ship)
	testing.expect_value(t, legacy_a, legacy_b)

	ship.construction_seed = 0x12345678
	seeded := ship_render_recipe(ship)
	ship.id = 99
	same_construction := ship_render_recipe(ship)
	testing.expect_value(t, seeded.core, same_construction.core)
	testing.expect_value(t, seeded.nose, same_construction.nose)
	testing.expect_value(t, seeded.engine, same_construction.engine)
	testing.expect_value(t, seeded.wing, same_construction.wing)
	testing.expect_value(t, seeded.utility, same_construction.utility)
	testing.expect_value(t, seeded.wing_stance, same_construction.wing_stance)
	testing.expect_value(t, seeded.wing_sweep, same_construction.wing_sweep)
	testing.expect_value(t, seeded.keel_profile, same_construction.keel_profile)
	testing.expect_value(t, seeded.drive_setback, same_construction.drive_setback)
	testing.expect_value(t, seeded.mission_profile, same_construction.mission_profile)
	testing.expect(
		t,
		seeded.core != legacy_a.core ||
		seeded.nose != legacy_a.nose ||
		seeded.engine != legacy_a.engine ||
		seeded.wing != legacy_a.wing ||
		seeded.utility != legacy_a.utility,
	)
}
