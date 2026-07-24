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

atlas_cell :: proc(index: int) -> rl.Rectangle {
	cell: f32 = 209
	return R(f32(index % 6) * cell, f32(index / 6) * cell, cell, cell)
}

atlas_cell_crop :: proc(index: int, crop: rl.Rectangle) -> rl.Rectangle {
	cell := atlas_cell(index)
	return R(cell.x + crop.x, cell.y + crop.y, crop.width, crop.height)
}

draw_ship_atlas_cell :: proc(
	texture: rl.Texture,
	index: int,
	destination: rl.Rectangle,
	tint := rl.Color{255, 255, 255, 255},
	hatch := rl.HATCH_DISABLED,
) {
	if !texture.ready do return
	if hatch.enabled {
		rl.DrawTextureProHatched(texture, atlas_cell(index), destination, hatch, tint)
	} else {
		rl.DrawTexturePro(texture, atlas_cell(index), destination, tint)
	}
}

draw_ship_atlas_crop :: proc(
	texture: rl.Texture,
	index: int,
	crop, destination: rl.Rectangle,
	tint := rl.Color{255, 255, 255, 255},
	hatch := rl.HATCH_DISABLED,
) {
	if !texture.ready do return
	if hatch.enabled {
		rl.DrawTextureProHatched(texture, atlas_cell_crop(index, crop), destination, hatch, tint)
	} else {
		rl.DrawTexturePro(texture, atlas_cell_crop(index, crop), destination, tint)
	}
}

draw_ship_effect_cell :: proc(
	texture: rl.Texture,
	index: int,
	destination: rl.Rectangle,
	tint := rl.Color{255, 255, 255, 255},
) {
	if !texture.ready do return
	// Engine-effect cells reserve generous transparent margins so their glow does
	// not bleed into neighboring atlas cells. Remove that padding before scaling;
	// otherwise a marker-sized plume collapses into a nearly invisible speck.
	row := index / 6
	crop := row == 0 ? R(58, 42, 93, 92) : R(54, 0, 101, 188)
	rl.DrawTexturePro(texture, atlas_cell_crop(index, crop), destination, tint)
}

ship_hull_width_scale :: proc(hull: game.Hull_Class) -> f32 {
	switch hull {
	case .Strike_Craft:
		return .76
	case .Corvette:
		return .86
	case .Fleet_Ship, .Unspecified:
		return 1
	case .Cruiser:
		return 1.08
	case .Capital_Ship:
		return 1.16
	}
	return 1
}

ship_hull_length_scale :: proc(hull: game.Hull_Class) -> f32 {
	switch hull {
	case .Strike_Craft:
		return .78
	case .Corvette:
		return .88
	case .Fleet_Ship, .Unspecified:
		return 1
	case .Cruiser:
		return 1.08
	case .Capital_Ship:
		return 1.15
	}
	return 1
}

// Role owns the first read of a ship. These large proportions remain legible
// after the component art and markings have collapsed at constellation scale.
// Construction profiles still vary the frame inside each role grammar.
ship_role_silhouette_scale :: proc(role: game.Role) -> (width, length: f32) {
	switch role {
	case .Habitat:
		return 1.05, .92 // broad inhabited drum
	case .Agriculture:
		return 1.06, .96 // wide growing and radiator volume
	case .Foundry:
		return 1.02, 1.02 // dense industrial frame
	case .Archive:
		return .86, 1.16 // protected vault spine
	case .Hospital:
		return 1.03, 1.00 // accessible lateral docking
	case .Survey:
		return .78, 1.24 // long sensor baseline
	case .Escort:
		return .82, 1.14 // narrow armored wedge
	case .Colony:
		return 1.06, 1.06 // detachable settlement mass
	}
	return 1, 1
}

ship_role_massing_scale :: proc(role: game.Role) -> (bow, core, wing, drive: f32) {
	switch role {
	case .Habitat:
		return .92, 1.12, 1.12, .88
	case .Agriculture:
		return .90, 1.06, 1.22, .86
	case .Foundry:
		return .94, 1.08, .92, 1.18
	case .Archive:
		return .86, 1.14, .82, .92
	case .Hospital:
		return 1.02, 1.04, 1.16, .90
	case .Survey:
		return .76, .88, .80, 1.04
	case .Escort:
		return .82, .94, .88, 1.20
	case .Colony:
		return 1.12, 1.16, 1.08, 1.02
	}
	return 1, 1, 1, 1
}

ship_keel_profile_scale :: proc(profile: int) -> (width_scale, length_scale: f32) {
	switch clamp(profile, 0, 2) {
	case 0:
		return 1.06, .92 // compact, broad-beamed
	case 2:
		return .94, 1.08 // long-range, slender
	}
	return 1, 1
}

ship_bow_profile_scale :: proc(profile: int) -> (width_scale, length_scale: f32) {
	switch clamp(profile, 0, 2) {
	case 0:
		return 1.14, .86 // blunt / broad crown
	case 2:
		return .86, 1.14 // needle / long crown
	}
	return 1, 1
}

ship_drive_layout_scale :: proc(layout: int) -> f32 {
	switch clamp(layout, 0, 2) {
	case 0:
		return .88
	case 2:
		return 1.12
	}
	return 1
}

ship_wing_fraction :: proc(hull: game.Hull_Class) -> f32 {
	switch hull {
	case .Strike_Craft:
		return .43
	case .Corvette:
		return .405
	case .Fleet_Ship, .Unspecified:
		return .38
	case .Cruiser:
		return .36
	case .Capital_Ship:
		return .34
	}
	return .38
}

ship_core_fraction :: proc(hull: game.Hull_Class) -> f32 {
	switch hull {
	case .Strike_Craft:
		return .42
	case .Corvette:
		return .48
	case .Fleet_Ship, .Unspecified:
		return .54
	case .Cruiser:
		return .60
	case .Capital_Ship:
		return .66
	}
	return .54
}

ship_nose_fraction :: proc(hull: game.Hull_Class) -> f32 {
	switch hull {
	case .Strike_Craft:
		return .54
	case .Corvette:
		return .61
	case .Fleet_Ship, .Unspecified:
		return .68
	case .Cruiser:
		return .72
	case .Capital_Ship:
		return .76
	}
	return .68
}

ship_wing_vertical_profile :: proc(hull: game.Hull_Class) -> (f32, f32) {
	switch hull {
	case .Strike_Craft:
		return .10, .82
	case .Corvette:
		return .14, .77
	case .Fleet_Ship, .Unspecified:
		return .18, .72
	case .Cruiser:
		return .21, .68
	case .Capital_Ship:
		return .24, .64
	}
	return .18, .72
}

ship_engine_volume_scale :: proc(hull: game.Hull_Class) -> f32 {
	switch hull {
	case .Strike_Craft:
		return .86
	case .Corvette:
		return .93
	case .Fleet_Ship, .Unspecified:
		return 1
	case .Cruiser:
		return 1.08
	case .Capital_Ship:
		return 1.16
	}
	return 1
}

ship_role_engine_scale :: proc(role: game.Role) -> f32 {
	switch role {
	case .Escort:
		return 1.10
	case .Foundry:
		return 1.07
	case .Survey:
		return 1.03
	case .Colony:
		return 1.02
	case .Archive:
		return .98
	case .Hospital:
		return .96
	case .Agriculture:
		return .94
	case .Habitat:
		return .92
	}
	return 1
}

ship_role_utility_scale :: proc(role: game.Role) -> f32 {
	switch role {
	case .Colony:
		return 1.18
	case .Habitat:
		return 1.16
	case .Agriculture:
		return 1.12
	case .Hospital:
		return 1.08
	case .Foundry:
		return 1.05
	case .Archive:
		return 1
	case .Escort:
		return .91
	case .Survey:
		return .88
	}
	return 1
}

ship_mass_percentile :: proc(ship: game.Ship) -> f32 {
	if ship.mass_tonnes <= 0 do return .5
	low, high := game.ship_hull_mass_range(ship.hull_class)
	if high <= low do return .5
	mass := clamp(ship.mass_tonnes, low, high)
	return f32(mass - low) / f32(high - low)
}

ship_mass_bulk_scale :: proc(ship: game.Ship) -> f32 {
	return .94 + ship_mass_percentile(ship) * .12
}

ship_mass_nose_scale :: proc(ship: game.Ship) -> f32 {
	return .97 + ship_mass_percentile(ship) * .06
}

ship_mass_engine_scale :: proc(ship: game.Ship) -> f32 {
	return .96 + ship_mass_percentile(ship) * .08
}

ship_power_output_scale :: proc(ship: game.Ship) -> f32 {
	if ship.power <= 0 do return 1
	baseline := max(game.ship_hull_class_power(ship.role, ship.hull_class), 1)
	ratio := clamp(f32(ship.power) / f32(baseline), f32(.5), f32(1.5))
	return .85 + (ratio - .5) * .30
}

ship_crew_occupancy_scale :: proc(ship: game.Ship) -> f32 {
	if ship.crew <= 0 do return 1
	baseline := max(game.ship_hull_class_crew(ship.role, ship.hull_class), 1)
	ratio := clamp(f32(ship.crew) / f32(baseline), f32(.5), f32(1.5))
	return .90 + (ratio - .5) * .20
}

ship_mission_deck_scale :: proc(ship: game.Ship) -> f32 {
	switch game.ship_construction_mission_profile(ship) {
	case 0:
		return .88
	case 2:
		return 1.12
	}
	return 1
}

ship_mission_module_scale :: proc(ship: game.Ship) -> f32 {
	return clamp(
		ship_crew_occupancy_scale(ship) * ship_mission_deck_scale(ship),
		f32(.88),
		f32(1.12),
	)
}


