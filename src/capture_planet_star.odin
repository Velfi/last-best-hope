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

planet_kind_from_name :: proc(name: string) -> Planet_Kind {
	switch name {
	case "fertile", "ocean", "earth":
		return .Fertile
	case "ice":
		return .Ice
	case "gas", "gas-giant", "jupiter", "saturn":
		return .Gas_Giant
	case "ice-giant", "uranus", "neptune":
		return .Ice_Giant
	case:
		return .Rocky
	}
}

Planet_Mark_Palette :: struct {
	ground, secondary, cloud, accent: Planet_Mark_Color,
}

surface_component_mark :: proc(component: game.Surface_Component) -> Planet_Mark_Color {
	switch component {
	case .Silicate:
		return .Silicate
	case .Iron_Oxide:
		return .Iron_Oxide
	case .Liquid_Water:
		return .Ocean
	case .Water_Ice:
		return .Water_Ice
	case .Sulfur:
		return .Sulfur_Surface
	case .Carbon:
		return .Carbon
	case .Methane:
		return .Methane_Ice
	case .Ammonia:
		return .Ammonia_Ice
	case .Vegetation:
		return .Vegetation_Surface
	}
	return .Silicate
}

planet_surface_palette :: proc(surface: game.Planet_Surface_Composition) -> Planet_Mark_Palette {
	first, second := 0, 0
	for value, i in surface.fractions {
		if value > surface.fractions[first] {
			second = first
			first = i
		} else if i != first && (second == first || value > surface.fractions[second]) {
			second = i
		}
	}
	ground := surface_component_mark(game.Surface_Component(first))
	secondary := surface_component_mark(game.Surface_Component(second))
	// Some components dominate reflected color without dominating bulk mass.
	// In particular, an iron-oxide coating makes a silicate surface read red.
	if surface.fractions[int(game.Surface_Component.Liquid_Water)] > .40 {
		secondary = .Ocean
		ground =
			surface.fractions[int(game.Surface_Component.Vegetation)] > .04 ? .Vegetation_Surface : .Silicate
	} else if surface.fractions[int(game.Surface_Component.Iron_Oxide)] > .12 {
		ground = .Iron_Oxide
	} else if surface.fractions[int(game.Surface_Component.Sulfur)] > .16 {
		ground = .Sulfur_Surface
	} else if surface.fractions[int(game.Surface_Component.Water_Ice)] > .40 {
		ground = .Water_Ice
	} else if surface.fractions[int(game.Surface_Component.Methane)] > .35 {
		// A methane-dominated visible disk is an atmospheric absorption case;
		// isolated methane ice remains white in the pure-material mapping.
		ground = .Methane_Haze
		secondary =
			surface.fractions[int(game.Surface_Component.Water_Ice)] > .08 ? .Water_Ice : .Ammonia_Ice
	}
	cloud := Planet_Mark_Color.Neutral
	accent := ground
	if surface.fractions[int(game.Surface_Component.Iron_Oxide)] > .12 {
		accent = .Iron_Oxide
	} else if surface.fractions[int(game.Surface_Component.Sulfur)] > .12 {
		accent = .Sulfur_Surface
	}
	return {ground, secondary, cloud, accent}
}

cloud_composition_mark :: proc(clouds: game.Planet_Cloud_Composition) -> Planet_Mark_Color {
	dominant := 0
	for value, i in clouds.fractions do if value > clouds.fractions[dominant] do dominant = i
	switch game.Cloud_Component(dominant) {
	case .Methane:
		return .Cyan
	case .Sulfur:
		return .Yellow
	case .Water, .Ammonia:
		return .Neutral
	}
	return .Neutral
}

cloud_composition_tint_srgb :: proc(clouds: game.Planet_Cloud_Composition) -> [3]f32 {
	colors := [4][3]f32{{.88, .92, .94}, {.96, .94, .86}, {.42, .72, .82}, {.96, .91, .76}}
	total: f64; for value in clouds.fractions do total += value
	if total <= 1e-9 do return {1, 1, 1}
	result: [3]f32
	for value, i in clouds.fractions do for channel in 0 ..< 3 do result[channel] += f32(value / total) * colors[i][channel]
	return result
}

set_cloud_composition :: proc(config: ^Planet_Config, clouds: game.Planet_Cloud_Composition) {
	for value, i in clouds.fractions do config.cloud_composition[i] = f32(value)
	config.cloud_mark = cloud_composition_mark(clouds)
}

surface_component_from_name :: proc(name: string) -> (game.Surface_Component, bool) {
	switch name {
	case "silicate":
		return .Silicate, true
	case "iron-oxide":
		return .Iron_Oxide, true
	case "liquid-water":
		return .Liquid_Water, true
	case "water-ice":
		return .Water_Ice, true
	case "sulfur":
		return .Sulfur, true
	case "carbon":
		return .Carbon, true
	case "methane":
		return .Methane, true
	case "ammonia":
		return .Ammonia, true
	case "vegetation":
		return .Vegetation, true
	}
	return .Silicate, false
}

cloud_component_from_name :: proc(name: string) -> (game.Cloud_Component, bool) {
	switch name {
	case "water":
		return .Water, true
	case "ammonia":
		return .Ammonia, true
	case "methane":
		return .Methane, true
	case "sulfur":
		return .Sulfur, true
	}
	return .Water, false
}

apply_pure_material_calibration :: proc(config: ^Planet_Config, mode, name: string) -> bool {
	config.kind = .Rocky
	config.rings = 0
	config.flattening = 1
	config.body_radius = .82
	config.axial_tilt = .18
	config.banding = 0
	config.rotation_rate = 0
	config.circulation = .35
	config.cloud_altitude = .018
	if mode == "surface" {
		component, ok := surface_component_from_name(name); if !ok do return false
		surface: game.Planet_Surface_Composition
		surface.fractions[int(component)] = 1
		config.geometric_albedo = f32(game.planet_geometric_albedo(.Rocky, surface))
		config.ocean_fraction = component == .Liquid_Water ? 1 : 0
		config.atmosphere = 0
		config.cloud_cover = 0
		mark := surface_component_mark(component)
		apply_planet_mark_palette(config, {mark, mark, .Neutral, mark})
		config.cloud_composition = {}
		return true
	}
	if mode == "atmosphere" {
		component, ok := cloud_component_from_name(name); if !ok do return false
		config.geometric_albedo =
			component == .Water ? .65 : component == .Ammonia ? .58 : component == .Methane ? .42 : .55
		config.ocean_fraction = 0
		config.atmosphere = 1
		config.cloud_cover = 1
		config.humidity = 1
		apply_planet_mark_palette(config, {.Neutral, .Neutral, .Neutral, .Neutral})
		clouds: game.Planet_Cloud_Composition
		clouds.fractions[int(component)] = 1
		set_cloud_composition(config, clouds)
		return true
	}
	return false
}

cloud_composition_for_kind :: proc(
	kind: Planet_Kind,
	seed: u64,
	temperature_kelvin := f64(0),
) -> game.Planet_Cloud_Composition {
	system_kind := game.System_Planet_Kind.Rocky
	switch kind {case .Fertile:
		system_kind = .Ocean; case .Ice:
		system_kind = .Ice; case .Gas_Giant:
		system_kind = .Gas_Giant; case .Ice_Giant:
		system_kind = .Ice_Giant; case .Rocky:
		system_kind = .Rocky}
	return game.planet_cloud_composition(system_kind, temperature_kelvin, seed)
}

solar_planet_surface :: proc(name: string) -> (game.Planet_Surface_Composition, bool) {
	s: game.Planet_Surface_Composition
	set :: proc(
		s: ^game.Planet_Surface_Composition,
		component: game.Surface_Component,
		value: f64,
	) {
		s.fractions[int(component)] = value
	}
	switch name {
	case "mercury":
		set(&s, .Silicate, .92); set(&s, .Carbon, .08)
	case "venus":
		set(&s, .Silicate, .64); set(&s, .Sulfur, .36)
	case "earth":
		set(&s, .Liquid_Water, .70); set(&s, .Silicate, .22); set(&s, .Vegetation, .06)
		set(&s, .Water_Ice, .02)
	case "mars":
		set(&s, .Silicate, .68); set(&s, .Iron_Oxide, .27); set(&s, .Water_Ice, .05)
	case "jupiter":
		set(&s, .Ammonia, .58); set(&s, .Sulfur, .24); set(&s, .Methane, .18)
	case "saturn":
		set(&s, .Ammonia, .68); set(&s, .Sulfur, .17); set(&s, .Methane, .15)
	case "uranus":
		set(&s, .Methane, .62); set(&s, .Ammonia, .23); set(&s, .Water_Ice, .15)
	case "neptune":
		set(&s, .Methane, .70); set(&s, .Ammonia, .18); set(&s, .Water_Ice, .12)
	case:
		return s, false
	}
	return s, true
}

solar_planet_clouds :: proc(name: string) -> (game.Planet_Cloud_Composition, bool) {
	c: game.Planet_Cloud_Composition
	set :: proc(
		c: ^game.Planet_Cloud_Composition,
		component: game.Cloud_Component,
		value: f64,
	) {c.fractions[int(component)] = value}
	switch name {
	case "venus":
		set(&c, .Sulfur, .72); set(&c, .Water, .18); set(&c, .Ammonia, .10)
	case "earth":
		set(&c, .Water, .985); set(&c, .Sulfur, .01); set(&c, .Ammonia, .005)
	case "mars":
		set(&c, .Water, .82); set(&c, .Sulfur, .18)
	case "jupiter":
		set(&c, .Ammonia, .52); set(&c, .Sulfur, .24); set(&c, .Methane, .16); set(&c, .Water, .08)
	case "saturn":
		set(&c, .Ammonia, .61); set(&c, .Sulfur, .17); set(&c, .Methane, .15); set(&c, .Water, .07)
	case "uranus":
		set(&c, .Methane, .61); set(&c, .Ammonia, .24); set(&c, .Water, .15)
	case "neptune":
		set(&c, .Methane, .68); set(&c, .Ammonia, .20); set(&c, .Water, .12)
	case "mercury":
		return c, false
	case:
		return c, false
	}
	return c, true
}

planet_mark_palette :: proc(
	kind: Planet_Kind,
	seed: u64,
	temperature_kelvin := f64(0),
) -> Planet_Mark_Palette {
	switch kind {
	case .Fertile:
		return {.Green, .Blue, .Neutral, .Green}
	case .Ice:
		return {.Cyan, .Blue, .Neutral, .Blue}
	case .Gas_Giant:
		if temperature_kelvin > 700 do return {.Yellow, .Red, .Neutral, .Red}
		return {.Yellow, .Neutral, .Neutral, .Red}
	case .Ice_Giant:
		return {.Cyan, .Blue, .Neutral, .Cyan}
	case .Rocky:
		switch seed % 3 {case 0:
			return {.Neutral, .Neutral, .Neutral, .Neutral}; case 1:
			return {.Red, .Neutral, .Neutral, .Red}; case:
			return {.Yellow, .Neutral, .Neutral, .Red}}
	}
	return {.Neutral, .Neutral, .Neutral, .Neutral}
}

solar_planet_mark_palette :: proc(
	name: string,
	fallback: Planet_Mark_Palette,
) -> Planet_Mark_Palette {
	switch name {
	case "mercury":
		return {.Neutral, .Neutral, .Neutral, .Neutral}
	case "venus":
		return {.Yellow, .Yellow, .Yellow, .Neutral}
	case "earth":
		return {.Green, .Blue, .Neutral, .Green}
	case "mars":
		return {.Red, .Neutral, .Neutral, .Neutral}
	case "jupiter":
		return {.Yellow, .Neutral, .Neutral, .Red}
	case "saturn":
		return {.Yellow, .Neutral, .Neutral, .Neutral}
	case "uranus":
		return {.Cyan, .Cyan, .Neutral, .Cyan}
	case "neptune":
		return {.Blue, .Cyan, .Neutral, .Cyan}
	case "mark-neutral":
		return {.Neutral, .Neutral, .Neutral, .Neutral}
	case "mark-red":
		return {.Red, .Red, .Red, .Red}
	case "mark-green":
		return {.Green, .Green, .Green, .Green}
	case "mark-blue":
		return {.Blue, .Blue, .Blue, .Blue}
	case "mark-yellow":
		return {.Yellow, .Yellow, .Yellow, .Yellow}
	case "mark-cyan":
		return {.Cyan, .Cyan, .Cyan, .Cyan}
	case "mark-magenta":
		return {.Magenta, .Magenta, .Magenta, .Magenta}
	}
	return fallback
}

apply_planet_mark_palette :: proc(config: ^Planet_Config, palette: Planet_Mark_Palette) {
	config.ground_mark =
		palette.ground; config.secondary_mark = palette.secondary; config.cloud_mark = palette.cloud; config.accent_mark = palette.accent
}
