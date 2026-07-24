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
ship_hull_archetype_icon_source :: proc(archetype: game.Ship_Hull_Archetype) -> rl.Rectangle {
	index := clamp(int(archetype) - 1, 0, game.SHIP_HULL_ARCHETYPE_COUNT - 1)
	return R(f32(index % 6) * 256, f32(index / 6) * 256, 256, 256)
}

draw_ship_hull_archetype_icon :: proc(
	archetype: game.Ship_Hull_Archetype,
	destination: rl.Rectangle,
	color := UX.text,
) {
	rl.DrawTexturePro(
		combat_archetype_icon_texture,
		ship_hull_archetype_icon_source(archetype),
		destination,
		color,
	)
}

ship_visual_mix :: proc(value: u64) -> u64 {
	return game.ship_construction_visual_mix(value)
}

ship_role_visual_index :: proc(role: game.Role) -> int {
	switch role {
	case .Habitat:
		return 3 // Enclosed medical pod reads as habitation volume.
	case .Survey:
		return 0
	case .Archive:
		return 1
	case .Foundry:
		return 2
	case .Hospital:
		return 3
	case .Escort:
		return 4
	case .Agriculture:
		return 5
	case .Colony:
		return 5
	}
	return 0
}

ship_role_marking_index :: proc(role: game.Role) -> int {
	switch role {
	case .Survey:
		return 24
	case .Archive:
		return 25
	case .Foundry:
		return 26
	case .Hospital:
		return 27
	case .Escort:
		return 28
	case .Agriculture:
		return 29
	case .Habitat:
		return 18 // Interlinked communities.
	case .Colony:
		return 4 // Outward-pointing fleet insignia.
	}
	return 24
}

ship_trait_marking_index :: proc(trait: game.Passage_Ship_Trait) -> int {
	switch trait {
	case .Curious:
		return 2
	case .Protective:
		return 0
	case .Cautious:
		return 1
	case .Committed:
		return 4
	case .Independent:
		return 3
	case .None:
		return -1
	}
	return -1
}

ship_registry_mark_visible :: proc(ship: game.Ship) -> bool {
	return ship.id != 0
}

ship_damage_visual_row :: proc(ship: game.Ship) -> int {
	if ship.scar != .None do return 5
	// The atlas's row 4 is a repair patch, not a more severe wound. Critical
	// live damage therefore remains a hull breach until a persistent scar exists.
	return clamp(int(ship.damage), 0, 3)
}

ship_damage_visual_column :: proc(ship: game.Ship, construction_seed: u64) -> int {
	if ship.scar != .None do return int(ship.scar) - 1
	return int((construction_seed >> 32) % 6)
}

ship_component_family :: proc(primary, accent: int, seed: u64, bit: uint) -> int {
	return ((seed >> bit) & 1) == 0 ? primary : accent
}

ship_component_layout_code :: proc(ship: game.Ship) -> u64 {
	return game.ship_construction_layout_code(ship)
}

ship_construction_family_pair :: proc(ship: game.Ship) -> (int, int) {
	return game.ship_construction_family_pair(ship)
}

SHIP_YARD_FAMILY_NAMES :: [6]string{"KEEL", "LANTERN", "BRASS", "SLATE", "IVORY", "LATTICE"}
SHIP_PROFILE_GRAMMAR :: "K/W/S/D/E/B/M"

ship_yard_pattern_name :: proc(ship: game.Ship) -> string {
	primary, accent := ship_construction_family_pair(ship)
	names := SHIP_YARD_FAMILY_NAMES
	return fmt.tprintf("%s-%s", names[primary], names[accent])
}

ship_keel_profile_name :: proc(ship: game.Ship) -> string {
	switch game.ship_construction_keel_profile(ship) {
	case 0:
		return "COMPACT KEEL"
	case 2:
		return "LONG KEEL"
	}
	return "STANDARD KEEL"
}

ship_wing_stance_name :: proc(ship: game.Ship) -> string {
	switch game.ship_construction_wing_stance(ship) {
	case 0:
		return "COMPACT WING"
	case 2:
		return "BROAD WING"
	}
	return "BALANCED WING"
}

ship_wing_sweep_name :: proc(ship: game.Ship) -> string {
	switch game.ship_construction_wing_sweep(ship) {
	case 0:
		return "FWD"
	case 2:
		return "AFT"
	}
	return "LVL"
}

ship_drive_layout_name :: proc(ship: game.Ship) -> string {
	switch game.ship_construction_drive_layout(ship) {
	case 0:
		return "INLINE"
	case 2:
		return "OUTBOARD"
	}
	return "TWIN"
}

ship_drive_setback_name :: proc(ship: game.Ship) -> string {
	switch game.ship_construction_drive_setback(ship) {
	case 0:
		return "REC"
	case 2:
		return "EXT"
	}
	return "FLS"
}

ship_bow_profile_name :: proc(ship: game.Ship) -> string {
	switch game.ship_construction_bow_profile(ship) {
	case 0:
		return "BLUNT BOW"
	case 2:
		return "NEEDLE BOW"
	}
	return "STANDARD BOW"
}

ship_construction_profile_label :: proc(ship: game.Ship) -> string {
	return fmt.tprintf(
		"%s · %s/%s · %s/%s · %s · M%d · H%02d",
		ship_keel_profile_name(ship),
		ship_wing_stance_name(ship),
		ship_wing_sweep_name(ship),
		ship_drive_layout_name(ship),
		ship_drive_setback_name(ship),
		ship_bow_profile_name(ship),
		game.ship_construction_mission_profile(ship) + 1,
		game.ship_construction_utility_hardpoint(ship) + 1,
	)
}

ship_structural_profile_code :: proc(ship: game.Ship) -> string {
	return fmt.tprintf(
		"K%d-W%d-S%d-D%d-E%d-B%d-M%d",
		game.ship_construction_keel_profile(ship) + 1,
		game.ship_construction_wing_stance(ship) + 1,
		game.ship_construction_wing_sweep(ship) + 1,
		game.ship_construction_drive_layout(ship) + 1,
		game.ship_construction_drive_setback(ship) + 1,
		game.ship_construction_bow_profile(ship) + 1,
		game.ship_construction_mission_profile(ship) + 1,
	)
}

ship_structural_profile_key :: proc(ship: game.Ship) -> string {
	return fmt.tprintf(
		"%d%d%d%d%d%d%d",
		game.ship_construction_keel_profile(ship) + 1,
		game.ship_construction_wing_stance(ship) + 1,
		game.ship_construction_wing_sweep(ship) + 1,
		game.ship_construction_drive_layout(ship) + 1,
		game.ship_construction_drive_setback(ship) + 1,
		game.ship_construction_bow_profile(ship) + 1,
		game.ship_construction_mission_profile(ship) + 1,
	)
}

ship_variation_board_key :: proc(ship: game.Ship) -> string {
	return fmt.tprintf(
		"%s-H%d",
		ship_structural_profile_key(ship),
		game.ship_construction_utility_hardpoint(ship) + 1,
	)
}

@(test)
construction_profile_labels_are_stable_distinct_and_dossier_bounded :: proc(t: ^testing.T) {
	seen_keels: [3]bool
	seen_wings: [3]bool
	seen_drives: [3]bool
	seen_hardpoints: [9]bool
	for identity in 1 ..= 512 {
		ship := game.Ship {
			id                = game.Ship_ID(identity),
			construction_seed = u64(identity),
		}
		label := ship_construction_profile_label(ship)
		testing.expect(t, label != "" && len(label) <= 80)
		seen_keels[game.ship_construction_keel_profile(ship)] = true
		seen_wings[game.ship_construction_wing_stance(ship)] = true
		seen_drives[game.ship_construction_drive_layout(ship)] = true
		seen_hardpoints[game.ship_construction_utility_hardpoint(ship)] = true
		changed := ship
		changed.role = .Colony
		changed.hull_class = .Capital_Ship
		changed.mass_tonnes = 120000000
		testing.expect_value(t, ship_construction_profile_label(changed), label)
	}
	for present in seen_keels do testing.expect(t, present)
	for present in seen_wings do testing.expect(t, present)
	for present in seen_drives do testing.expect(t, present)
	for present in seen_hardpoints do testing.expect(t, present)
}

@(test)
structural_profile_codes_are_stable_unique_and_compact :: proc(t: ^testing.T) {
	testing.expect_value(t, SHIP_PROFILE_GRAMMAR, "K/W/S/D/E/B/M")
	explicit := game.Ship {
		keel_profile    = 1,
		wing_stance     = 1,
		wing_sweep      = 1,
		drive_layout    = 1,
		drive_setback   = 1,
		bow_profile     = 1,
		mission_profile = 1,
	}
	testing.expect_value(t, ship_structural_profile_code(explicit), "K1-W1-S1-D1-E1-B1-M1")
	testing.expect_value(t, ship_structural_profile_key(explicit), "1111111")
	codes: [2187]string
	for identity in 1 ..= 65536 {
		ship := game.Ship {
			id                = game.Ship_ID(identity),
			construction_seed = u64(identity),
		}
		profile :=
			(((game.ship_construction_structural_profile(ship) * 3 +
									game.ship_construction_bow_profile(ship)) *
								3 +
							game.ship_construction_wing_sweep(ship)) *
						3 +
					game.ship_construction_drive_setback(ship)) *
				3 +
			game.ship_construction_mission_profile(ship)
		code := ship_structural_profile_code(ship)
		testing.expect_value(t, len(code), 20)
		if codes[profile] == "" {
			for prior, index in codes do if index != profile && prior != "" do testing.expect(t, prior != code)
			codes[profile] = code
		} else {
			testing.expect_value(t, code, codes[profile])
		}
	}
	for code in codes do testing.expect(t, code != "")
}

ship_render_recipe :: proc(ship: game.Ship) -> Ship_Render_Recipe {
	construction_identity := ship.construction_seed
	if construction_identity == 0 do construction_identity = u64(ship.id)
	seed := ship_visual_mix(construction_identity)
	individual_seed := ship_visual_mix(construction_identity ~ (u64(ship.id) * 0x9e3779b97f4a7c15))
	// Every construction uses one primary and one accent design family. This
	// keeps panel language, paint balance, and mechanical forms coherent while
	// retaining 900 genuinely mixed five-part recipes before role and markings.
	primary, accent := ship_construction_family_pair(ship)
	layout := ship_component_layout_code(ship)
	core := ship_component_family(primary, accent, layout, 0)
	nose := ship_component_family(primary, accent, layout, 1)
	engine := ship_component_family(primary, accent, layout, 2)
	wing := ship_component_family(primary, accent, layout, 3)
	utility := ship_component_family(primary, accent, layout, 4)
	role := ship_role_visual_index(ship.role)
	community := ship.community != 0 ? (int(ship.community) - 1) % 6 : int(seed % 6)
	damage_row := ship_damage_visual_row(ship)
	if ship.scar == .None && ship.damage == 0 && ship_has_repair_memory(ship) do damage_row = 4
	damage_column := ship_damage_visual_column(ship, seed)
	effect_row := ship.committed ? 2 : 0
	if ship.committed && ship_power_output_scale(ship) >= 1.10 do effect_row = 3
	if ship.damage > 0 do effect_row = 4
	if !ship.active do effect_row = 5
	promise_record := game.ship_promise_record(ship)
	history_column := -1
	switch promise_record {
	case .Broken:
		history_column = int(individual_seed % 2) * 4
	case .Transformed:
		history_column = 3 + int(individual_seed % 2) * 2
	case .Upheld:
		history_column = 1 + int(individual_seed % 2)
	case .None:
	}
	service_rank := ship_service_rank(ship)
	return {
		core = core,
		nose = nose,
		engine = engine,
		wing = wing,
		utility = utility,
		role_module = role,
		wing_stance = game.ship_construction_wing_stance(ship),
		wing_sweep = game.ship_construction_wing_sweep(ship),
		keel_profile = game.ship_construction_keel_profile(ship),
		drive_layout = game.ship_construction_drive_layout(ship),
		drive_setback = game.ship_construction_drive_setback(ship),
		mission_profile = game.ship_construction_mission_profile(ship),
		bow_profile = game.ship_construction_bow_profile(ship),
		damage = damage_row * 6 + damage_column,
		livery = 6 + community,
		community_marking = 18 + community,
		registry_marking = 12 + int((individual_seed >> 16) % 6),
		service_marking = service_rank < 0 ? -1 : 12 + service_rank,
		role_marking = ship_role_marking_index(ship.role),
		trait_marking = ship_trait_marking_index(ship.passage_trait),
		history_marking = history_column < 0 ? -1 : 30 + history_column,
		effect = effect_row * 6 + engine,
	}
}
