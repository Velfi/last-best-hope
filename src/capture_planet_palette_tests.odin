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
planet_mark_palettes_are_deterministic_and_solar_specific :: proc(t: ^testing.T) {
	a := planet_mark_palette(
		.Rocky,
		41,
	); b := planet_mark_palette(.Rocky, 41); testing.expect_value(t, a, b)
	testing.expect_value(
		t,
		solar_planet_mark_palette("mercury", a).ground,
		Planet_Mark_Color.Neutral,
	)
	testing.expect_value(
		t,
		solar_planet_mark_palette("venus", a).cloud,
		Planet_Mark_Color.Yellow,
	)
	earth := solar_planet_mark_palette(
		"earth",
		a,
	); testing.expect_value(t, earth.ground, Planet_Mark_Color.Green); testing.expect_value(t, earth.secondary, Planet_Mark_Color.Blue)
	testing.expect_value(t, solar_planet_mark_palette("mars", a).ground, Planet_Mark_Color.Red)
	testing.expect_value(
		t,
		solar_planet_mark_palette("jupiter", a).accent,
		Planet_Mark_Color.Red,
	)
	testing.expect_value(
		t,
		solar_planet_mark_palette("saturn", a).ground,
		Planet_Mark_Color.Yellow,
	)
	testing.expect_value(
		t,
		solar_planet_mark_palette("uranus", a).ground,
		Planet_Mark_Color.Cyan,
	)
	neptune := solar_planet_mark_palette(
		"neptune",
		a,
	); testing.expect_value(t, neptune.ground, Planet_Mark_Color.Blue); testing.expect_value(t, neptune.secondary, Planet_Mark_Color.Cyan)
}

@(test)
surface_components_determine_planet_marks :: proc(t: ^testing.T) {
	mars := game.Planet_Surface_Composition{}
	mars.fractions[int(game.Surface_Component.Silicate)] = .68
	mars.fractions[int(game.Surface_Component.Iron_Oxide)] = .24
	mars.fractions[int(game.Surface_Component.Water_Ice)] = .08
	p := planet_surface_palette(mars)
	testing.expect_value(t, p.ground, Planet_Mark_Color.Iron_Oxide)
	testing.expect_value(t, p.secondary, Planet_Mark_Color.Iron_Oxide)
	testing.expect_value(t, p.accent, Planet_Mark_Color.Iron_Oxide)
	ocean := game.Planet_Surface_Composition{}
	ocean.fractions[int(game.Surface_Component.Liquid_Water)] = .72
	ocean.fractions[int(game.Surface_Component.Silicate)] = .28
	testing.expect_value(t, planet_surface_palette(ocean).ground, Planet_Mark_Color.Silicate)
	testing.expect_value(t, planet_surface_palette(ocean).secondary, Planet_Mark_Color.Ocean)
}

@(test)
cloud_composition_palette_handles_pure_mixed_and_empty_inputs :: proc(t: ^testing.T) {
	water := game.Planet_Cloud_Composition {
		fractions = {1, 0, 0, 0},
	}
	methane := game.Planet_Cloud_Composition {
		fractions = {0, 0, 1, 0},
	}
	mixed := game.Planet_Cloud_Composition {
		fractions = {.5, 0, .5, 0},
	}
	testing.expect_value(t, cloud_composition_tint_srgb(water), [3]f32{.88, .92, .94})
	testing.expect_value(t, cloud_composition_tint_srgb(methane), [3]f32{.42, .72, .82})
	mixed_tint := cloud_composition_tint_srgb(mixed)
	testing.expect(t, abs(mixed_tint[0] - .65) < 1e-5)
	testing.expect(t, abs(mixed_tint[1] - .82) < 1e-5)
	testing.expect(t, abs(mixed_tint[2] - .88) < 1e-5)
	testing.expect_value(t, cloud_composition_tint_srgb({}), [3]f32{1, 1, 1})
	testing.expect_value(t, cloud_composition_mark(methane), Planet_Mark_Color.Cyan)
}

star_kind_from_name :: proc(name: string) -> Star_Kind {
	switch name {case "red", "red-giant":
		return .Red_Giant; case "blue", "blue-giant":
		return .Blue_Giant; case "white-dwarf", "dwarf":
		return .White_Dwarf; case "neutron", "pulsar":
		return .Neutron; case "black-hole", "black":
		return .Black_Hole; case "stripped", "stripped-star", "wolf-rayet":
		return .Stripped_Star; case "protostar", "proto":
		return .Protostar; case:
		return .Main_Sequence}
}

@(test)
stellar_capture_names_cover_compact_remnants :: proc(t: ^testing.T) {
	testing.expect_value(t, star_kind_from_name("neutron"), Star_Kind.Neutron)
	testing.expect_value(t, star_kind_from_name("black-hole"), Star_Kind.Black_Hole)
	testing.expect_value(t, star_kind_from_name("stripped"), Star_Kind.Stripped_Star)
	testing.expect_value(t, star_kind_from_name("protostar"), Star_Kind.Protostar)
}

draw_star_plate :: proc(
	seed: u64,
	kind: Star_Kind,
	rotation_offset := f32(0),
	plasma_time := f32(0),
	reduced_motion := false,
) {
	rl.DrawRectangle(0, 0, UX_W, UX_H, {0, 0, 0, 255})
	for i in 0 ..< 54 {x := f32(galaxy_star_unit(seed, i, 451)) * f32(UX_W); y := f32(galaxy_star_unit(seed, i, 452)) * f32(UX_H); if math.abs(x - 640) < 350 && math.abs(y - 360) < 330 do continue; rl.DrawCircleV(V(x, y), i % 13 == 0 ? f32(.85) : f32(.4), {213, 214, 202, u8(45 + int(galaxy_star_unit(seed, i, 453) * 75))})}
	state := seed ~ 0xd1b54a32d192ed03
	unit :: proc(s: ^u64) -> f32 {s^ = s^ ~ (s^ >> 12); s^ = s^ ~ (s^ << 25); s^ = s^ ~ (s^ >> 27)
		return f32((s^ * 0x2545f4914f6cdd1d) >> 40) / f32(1 << 24)}
	config := Star_Config {
		kind               = kind,
		seed               = f32(seed % 1000003),
		phase              = unit(&state) * f32(math.PI) * 2 + rotation_offset,
		activity           = .34 + unit(&state) * .58,
		spots              = .28 + unit(&state) * .62,
		granulation        = .55 + unit(&state) * .4,
		corona             = .38 + unit(&state) * .54,
		rotation           = (unit(&state) - .5) * .6,
		body_radius        = .68,
		temperature_kelvin = 5772,
		luminosity_solar   = 1,
		mass_solar         = 1,
		radius_solar       = 1,
		time_seconds       = plasma_time + rotation_offset * 40,
		rotation_rate      = .012,
		reduced_motion     = reduced_motion,
	}
	if kind ==
	   .Red_Giant {config.granulation = .92; config.spots = .72; config.body_radius = .72; config.temperature_kelvin = 3900; config.luminosity_solar = 900; config.mass_solar = 1.3; config.radius_solar = 55; config.rotation_rate = .002}
	if kind ==
	   .Blue_Giant {config.activity = .7; config.corona = .64; config.body_radius = .7; config.temperature_kelvin = 18000; config.luminosity_solar = 18000; config.mass_solar = 12; config.radius_solar = 7; config.rotation_rate = .02}
	if kind ==
	   .White_Dwarf {config.granulation = .08; config.spots = .04; config.corona = .12; config.body_radius = .42; config.temperature_kelvin = 10000; config.luminosity_solar = .01; config.mass_solar = .62; config.radius_solar = .012; config.rotation_rate = .006}
	if kind ==
	   .Neutron {config.granulation = 0; config.spots = 1; config.activity = 1; config.corona = .88; config.body_radius = .12; config.temperature_kelvin = 600000; config.luminosity_solar = .001; config.mass_solar = 1.4; config.radius_solar = .00002; config.rotation_rate = 1.8}
	if kind ==
	   .Black_Hole {config.granulation = 0; config.spots = 0; config.activity = .8; config.corona = .6; config.body_radius = .18; config.temperature_kelvin = 1000; config.luminosity_solar = .000001; config.mass_solar = 8; config.radius_solar = .00004; config.rotation_rate = .2}
	if kind ==
	   .Stripped_Star {config.granulation = .12; config.spots = .08; config.activity = .88; config.corona = .92; config.body_radius = .48; config.temperature_kelvin = 52000; config.luminosity_solar = 85000; config.mass_solar = 7.5; config.radius_solar = 1.2; config.rotation_rate = .08}
	if kind ==
	   .Protostar {config.granulation = .78; config.spots = .86; config.activity = .92; config.corona = .72; config.body_radius = .62; config.temperature_kelvin = 3400; config.luminosity_solar = 4.2; config.mass_solar = .8; config.radius_solar = 3.1; config.rotation_rate = .035}
	DrawStar(R(350, 70, 580, 580), {231, 229, 211, 255}, config)
}

apply_solar_planet_preset :: proc(name: string, config: ^Planet_Config) -> bool {
	switch name {
	case "mercury":
		config.kind = .Rocky
		config.geometric_albedo = .106
		config.axial_tilt = .0006
		config.ocean_fraction = 0
		config.atmosphere = 0
		config.cloud_cover = 0
		config.banding = 0
		config.rings = 0
		config.flattening = 1
		config.body_radius = .82
	case "venus":
		config.kind = .Rocky
		config.geometric_albedo = .65
		config.axial_tilt = 3.096
		config.ocean_fraction = 0
		config.atmosphere = 1
		config.cloud_cover = .99
		config.banding = .04
		config.rings = 0
		config.flattening = 1
		config.body_radius = .82
	case "earth":
		config.kind = .Fertile
		config.geometric_albedo = .367
		config.axial_tilt = .4091
		config.ocean_fraction = .71
		config.atmosphere = .68
		config.cloud_cover = .57
		config.banding = .06
		config.rings = 0
		config.flattening = .9966
		config.body_radius = .82
	case "mars":
		config.kind = .Rocky
		config.geometric_albedo = .150
		config.axial_tilt = .4396
		config.ocean_fraction = 0
		config.atmosphere = .13
		config.cloud_cover = .035
		config.banding = .03
		config.rings = 0
		config.flattening = .994
		config.body_radius = .82
	case "jupiter":
		config.kind = .Gas_Giant
		config.geometric_albedo = .52
		config.axial_tilt = .0546
		config.ocean_fraction = 0
		config.atmosphere = .5
		config.cloud_cover = .76
		config.banding = 1
		config.rings = 0
		config.flattening = .935
		config.body_radius = .82
	case "saturn":
		config.kind = .Gas_Giant
		config.geometric_albedo = .47
		config.axial_tilt = .4665
		config.ocean_fraction = 0
		config.atmosphere = .42
		config.cloud_cover = .58
		config.banding = .82
		config.rings = .96
		config.flattening = .902
		config.body_radius = .431
		config.ring_inner = 1.11
		config.ring_outer = 2.32
		config.ring_density = .9
		config.ring_structure = .82
	case "uranus":
		config.kind = .Ice_Giant
		config.geometric_albedo = .51
		config.axial_tilt = 1.706
		config.ocean_fraction = 0
		config.atmosphere = .55
		config.cloud_cover = .2
		config.banding = .18
		config.rings = .14
		config.flattening = .977
		config.body_radius = .5
		config.ring_inner = 1.64
		config.ring_outer = 1.98
		config.ring_density = .2
		config.ring_structure = .72
	case "neptune":
		config.kind = .Ice_Giant
		config.geometric_albedo = .41
		config.axial_tilt = .4943
		config.ocean_fraction = 0
		config.atmosphere = .58
		config.cloud_cover = .3
		config.banding = .56
		config.rings = 0
		config.flattening = .983
		config.body_radius = .82
	case:
		return false
	}
	return true
}

draw_planet_plate :: proc(
	seed: u64,
	kind: Planet_Kind,
	force_rings := false,
	rotation_offset := f32(0),
	preset_name := "",
	atmosphere_time := f32(0),
	reduced_motion := false,
) {
	// Asset plates use actual black negative space. The operational interface's
	// charcoal ground is intentionally not inherited by illustration captures.
	rl.DrawRectangle(0, 0, UX_W, UX_H, {0, 0, 0, 255})
	// Sparse pinpricks keep the plate archival and leave enough black rest for
	// the planet's silhouette. Their positions share the generator seed.
	for i in 0 ..< 72 {
		x := f32(galaxy_star_unit(seed, i, 401)) * f32(UX_W)
		y := f32(galaxy_star_unit(seed, i, 402)) * f32(UX_H)
		r := i % 11 == 0 ? f32(.9) : f32(.45)
		rl.DrawCircleV(
			V(x, y),
			r,
			{213, 214, 202, u8(55 + int(galaxy_star_unit(seed, i, 403) * 80))},
		)
	}
	state := seed ~ 0x9e3779b97f4a7c15
	unit :: proc(s: ^u64) -> f32 {s^ = s^ ~ (s^ >> 12); s^ = s^ ~ (s^ << 25); s^ = s^ ~ (s^ >> 27)
		return f32((s^ * 0x2545f4914f6cdd1d) >> 40) / f32(1 << 24)}
	config := Planet_Config {
		kind             = kind,
		seed             = f32(seed % 1000003),
		phase            = unit(&state) * f32(math.PI) * 2 + rotation_offset,
		axial_tilt       = (unit(&state) - .5) * .72,
		ocean_fraction   = kind == .Fertile ? .66 : kind == .Rocky ? .04 : .08,
		atmosphere       = kind == .Fertile ? .72 : kind == .Ice ? .28 : kind == .Rocky ? .08 : .52,
		cloud_cover      = kind == .Fertile ? .58 : kind == .Rocky ? .04 : kind == .Ice ? .14 : .34,
		banding          = (kind == .Gas_Giant || kind == .Ice_Giant) ? .82 : .08,
		rings            = force_rings ? .78 : (kind == .Gas_Giant || kind == .Ice_Giant) && unit(&state) > .55 ? .65 : 0,
		flattening       = kind == .Gas_Giant || kind == .Ice_Giant ? .94 : 1,
		body_radius      = .82,
		geometric_albedo = kind == .Rocky ? .14 : kind == .Fertile ? .36 : kind == .Ice ? .58 : kind == .Gas_Giant ? .48 : .46,
		atmosphere_time  = atmosphere_time,
	}
	_ = apply_solar_planet_preset(preset_name, &config)
	// Atmosphere controls are explicit on generated and Solar presets so a
	// capture can be reconstructed from config + seed without hidden globals.
	switch config.kind {
	case .Fertile:
		config.rotation_rate = 1; config.humidity = .72; config.circulation = .52
		config.cloud_altitude = .018
	case .Ice:
		config.rotation_rate = .82; config.humidity = .24; config.circulation = .3
		config.cloud_altitude = .014
	case .Gas_Giant:
		config.rotation_rate = 1.45; config.humidity = .9; config.circulation = 1
		config.cloud_altitude = .028
	case .Ice_Giant:
		config.rotation_rate = .92; config.humidity = .55; config.circulation = .68
		config.cloud_altitude = .024
	case .Rocky:
		config.rotation_rate = .75; config.humidity = .12; config.circulation = .28
		config.cloud_altitude = .012
	}
	switch preset_name {
	case "venus":
		config.rotation_rate = .04; config.humidity = .98; config.circulation = .42
		config.cloud_altitude = .032
	case "earth":
		config.rotation_rate = 1; config.humidity = .72; config.circulation = .52
		config.cloud_altitude = .018
	case "mars":
		config.rotation_rate = .97; config.humidity = .035; config.circulation = .18
		config.cloud_altitude = .01
	case "jupiter":
		config.rotation_rate = 1.45; config.humidity = .92; config.circulation = 1
		config.cloud_altitude = .03
	case "saturn":
		config.rotation_rate = 1.38; config.humidity = .8; config.circulation = .9
		config.cloud_altitude = .027
	case "uranus":
		config.rotation_rate = .72; config.humidity = .36; config.circulation = .36
		config.cloud_altitude = .021
	case "neptune":
		config.rotation_rate = .91; config.humidity = .58; config.circulation = .72
		config.cloud_altitude = .025
	}
	palette := solar_planet_mark_palette(preset_name, planet_mark_palette(config.kind, seed))
	if surface, ok := solar_planet_surface(preset_name); ok do palette = planet_surface_palette(surface)
	apply_planet_mark_palette(&config, palette)
	clouds := cloud_composition_for_kind(config.kind, seed)
	if solar_clouds, ok := solar_planet_clouds(preset_name); ok do clouds = solar_clouds
	set_cloud_composition(&config, clouds)
	switch preset_name {
	case "material-surface-silicate":
		_ = apply_pure_material_calibration(&config, "surface", "silicate")
	case "material-surface-iron-oxide":
		_ = apply_pure_material_calibration(&config, "surface", "iron-oxide")
	case "material-surface-liquid-water":
		_ = apply_pure_material_calibration(&config, "surface", "liquid-water")
	case "material-surface-water-ice":
		_ = apply_pure_material_calibration(&config, "surface", "water-ice")
	case "material-surface-sulfur":
		_ = apply_pure_material_calibration(&config, "surface", "sulfur")
	case "material-surface-carbon":
		_ = apply_pure_material_calibration(&config, "surface", "carbon")
	case "material-surface-methane":
		_ = apply_pure_material_calibration(&config, "surface", "methane")
	case "material-surface-ammonia":
		_ = apply_pure_material_calibration(&config, "surface", "ammonia")
	case "material-surface-vegetation":
		_ = apply_pure_material_calibration(&config, "surface", "vegetation")
	case "material-atmosphere-water":
		_ = apply_pure_material_calibration(&config, "atmosphere", "water")
	case "material-atmosphere-ammonia":
		_ = apply_pure_material_calibration(&config, "atmosphere", "ammonia")
	case "material-atmosphere-methane":
		_ = apply_pure_material_calibration(&config, "atmosphere", "methane")
	case "material-atmosphere-sulfur":
		_ = apply_pure_material_calibration(&config, "atmosphere", "sulfur")
	}
	if force_rings do config.rings = .78
	// Procedural systems use plausible Roche-zone proportions. The generated
	// profile is stored in planetary radii, and the globe is scaled so even a
	// broad system remains inside the illustration plate.
	if config.rings > 0 && config.ring_outer <= config.ring_inner {
		config.ring_inner = 1.08 + unit(&state) * .42
		config.ring_outer = 1.72 + unit(&state) * .86
		config.ring_outer = max(config.ring_outer, config.ring_inner + .38)
		config.ring_density = .28 + unit(&state) * .68
		config.ring_structure = .2 + unit(&state) * .8
		config.body_radius = min(config.body_radius, .97 / config.ring_outer)
	}
	atlas := atmosphere_texture_for(&config, seed, atmosphere_time, reduced_motion)
	DrawPlanet(R(350, 70, 580, 580), {231, 229, 211, 255}, config, atlas)
}
