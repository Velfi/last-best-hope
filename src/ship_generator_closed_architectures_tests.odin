package main

import game "../packages/game"
import "core:math"
import "core:testing"
import rl "zelda_engine:canvas2d"

@(test)
delta_architecture_generates_closed_faces :: proc(t: ^testing.T) {
	architectures := [1]game.Ship_Generator_Kind{.Delta}
	for architecture in architectures {r := game.Procedural_Ship_Recipe {
			seed = 81,
			family = .Fleet,
			architecture = architecture,
			frame = {keel_length = 14, beam = 5.2, height = 3.2},
		}; faces := make(
			[dynamic]Ship_Project_Face,
			0,
			128,
			context.temp_allocator,
		); ship_append_closed_architecture_faces(&faces, &r, Ship_Generator_Camera{}, rl.Vector2{}, 1); testing.expectf(t, len(faces) >= 30, "architecture %v emitted only %d faces", architecture, len(faces))}
}

@(test)
delta_weapon_packages_generate_distinct_wing_root_installations :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		seed = 81,
		family = .Fleet,
		architecture = .Delta,
		weapon_capability_scale = 1,
		frame = {keel_length = 14, beam = 5.2, height = 3.2},
	}
	counts: [7]int
	packages := [7]game.Ship_Weapon_Package {
		.Chemical_Autocannon,
		.Coilgun_Battery,
		.Railgun_Battery,
		.Defensive_Laser,
		.Offensive_Laser,
		.Guided_Missiles,
		.Heavy_Torpedoes,
	}
	for weapon, index in packages {
		r.weapon_package = weapon
		faces := make([dynamic]Ship_Project_Face, 0, 512, context.temp_allocator)
		ship_append_delta_hull_faces(&faces, &r, Ship_Generator_Camera{}, rl.Vector2{}, 1, false)
		counts[index] = len(faces)
	}
	testing.expect(t, counts[3] < counts[0])
	testing.expect(t, counts[0] < counts[4])
	testing.expect(t, counts[4] < counts[1])
	testing.expect_value(t, counts[1], counts[2])
	testing.expect(t, counts[2] < counts[6])
	testing.expect(t, counts[6] < counts[5])
	// The guided package carries four launch shoes and paired control fins,
	// while the two heavy rounds use twin continuous cradle rails and restraint
	// bands. Keep enough structural separation that both installations remain
	// readable rather than degenerating into differently sized bare tanks.
	testing.expect(t, counts[5] - counts[6] >= 32)
	testing.expect(t, counts[6] - counts[2] >= 24)
}

@(test)
delta_planforms_keep_a_mirrored_recessed_stern_and_seeded_proportions :: proc(t: ^testing.T) {
	first := ship_delta_planform(
		1,
		7,
		3,
	); testing.expect_value(t, first[0][0], f32(-7)); testing.expect(t, first[7][0] > first[0][0]); left := [4]int{0, 1, 2, 7}; right := [4]int{6, 5, 4, 8}
	for i in 0 ..< len(
		left,
	) {testing.expect_value(t, first[left[i]][0], first[right[i]][0]); testing.expect_value(t, first[left[i]][1], -first[right[i]][1])}
	testing.expect_value(t, first[3][1], f32(0)); changed := false
	for seed in u64(
		2,
	) ..= 32 {candidate := ship_delta_planform(seed, 7, 3); changed = changed || candidate[1] != first[1] || candidate[2] != first[2] || candidate[7] != first[7]}; testing.expect(t, changed)
	for seed in u64(
		24301,
	) ..< 24304 {a := ship_delta_planform(seed, 7, 3); b := ship_delta_planform(seed + 1, 7, 3); testing.expect(t, a[1] != b[1] || a[2] != b[2] || a[7] != b[7])}
}

@(test)
delta_planform_silhouette_communicates_ship_family :: proc(t: ^testing.T) {
	strike := ship_delta_planform(
		24301,
		7,
		3,
		.Strike,
	); fleet := ship_delta_planform(24301, 7, 3, .Fleet); habitat := ship_delta_planform(24301, 7, 3, .Habitat)
	testing.expect(
		t,
		strike[1][0] < fleet[1][0] && fleet[1][0] < habitat[1][0],
	); testing.expect(t, math.abs(strike[2][1]) < math.abs(fleet[2][1]) && math.abs(fleet[2][1]) < math.abs(habitat[2][1])); testing.expect(t, math.abs(strike[0][1]) < math.abs(fleet[0][1]) && math.abs(fleet[0][1]) < math.abs(habitat[0][1])); testing.expect(t, strike[7][0] < fleet[7][0] && fleet[7][0] < habitat[7][0])
	plans := [3][9][2]f32 {
		strike,
		fleet,
		habitat,
	}; pairs := [4][2]int{{0, 6}, {1, 5}, {2, 4}, {7, 8}}
	for plan in plans do for pair in pairs {testing.expect_value(t, plan[pair[0]][0], plan[pair[1]][0]); testing.expect_value(t, plan[pair[0]][1], -plan[pair[1]][1])}
}

@(test)
habitat_delta_uses_a_broad_deep_envelope_and_matching_surface_mounts :: proc(t: ^testing.T) {
	fleet := game.Procedural_Ship_Recipe {
		seed = 24301,
		family = .Fleet,
		architecture = .Delta,
		frame = {keel_length = 14, beam = 5.2, height = 3.2},
	}
	habitat := fleet
	habitat.family = .Habitat
	fleet_x, fleet_y, fleet_z := ship_delta_half_extents(&fleet)
	habitat_x, habitat_y, habitat_z := ship_delta_half_extents(&habitat)
	testing.expect(t, habitat_x / habitat_y < fleet_x / fleet_y * .72)
	testing.expect(t, habitat_z > fleet_z * 1.14)
	radiator := ship_closed_hull_mount_module(&habitat, {module = .Radiator, position = {0, 8, 0}})
	expected_beam, _, _ := ship_delta_section_at_x(
		habitat.seed,
		habitat_x,
		habitat_y,
		habitat_z,
		radiator.position[0],
		.Habitat,
	)
	testing.expect(t, math.abs(radiator.position[1] - expected_beam) < .001)
}

@(test)
delta_pressure_depth_is_family_specific_and_side_readable :: proc(t: ^testing.T) {
	fleet := game.Procedural_Ship_Recipe {
		seed = 24301,
		family = .Fleet,
		architecture = .Delta,
		frame = {keel_length = 14, beam = 5.2, height = 3.2},
	}
	strike := fleet
	strike.family = .Strike
	habitat := fleet
	habitat.family = .Habitat
	_, _, strike_z := ship_delta_half_extents(&strike)
	_, _, fleet_z := ship_delta_half_extents(&fleet)
	_, _, habitat_z := ship_delta_half_extents(&habitat)
	testing.expect(t, strike_z < fleet_z && fleet_z < habitat_z)
	testing.expect(t, fleet_z >= fleet.frame.height * .27)
}

@(test)
delta_vertical_profile_thins_the_bow_without_weakening_the_stern :: proc(t: ^testing.T) {
	stern_top, stern_bottom := ship_delta_edge_vertical(
		24301,
		-7,
		0,
		7,
		1,
	); bow_top, bow_bottom := ship_delta_edge_vertical(24301, 7, 3, 7, 1)
	testing.expect(
		t,
		bow_top - bow_bottom < (stern_top - stern_bottom) * .68,
	); testing.expect(t, stern_top > .7 && stern_bottom == f32(-1)); testing.expect(t, bow_top > 0 && bow_bottom < 0)
	same_top, same_bottom := ship_delta_edge_vertical(
		24301,
		7,
		3,
		7,
		1,
	); testing.expect_value(t, bow_top, same_top); testing.expect_value(t, bow_bottom, same_bottom); other_top, other_bottom := ship_delta_edge_vertical(24302, 7, 3, 7, 1); testing.expect(t, other_top != bow_top || other_bottom != bow_bottom)
}

@(test)
delta_citadel_rises_above_the_hull_and_varies_by_construction_seed :: proc(t: ^testing.T) {
	append_for_seed := proc(seed: u64) -> [dynamic]Ship_Project_Face {faces := make(
			[dynamic]Ship_Project_Face,
			0,
			8,
			context.temp_allocator,
		)
		module := game.Procedural_Ship_Placement {
			surface_id = 0xf3000000,
			module     = .Keel,
			material   = .Armor,
		}
		ship_append_delta_citadel_faces(
			&faces,
			module,
			seed,
			.Fleet,
			7,
			3,
			1,
			Ship_Generator_Camera{},
			rl.Vector2{},
			1,
		)
		return faces}
	a, b :=
		append_for_seed(24301),
		append_for_seed(
			24302,
		); testing.expect_value(t, len(a), 6); testing.expect(t, math.abs(a[0].world[1][1]) < math.abs(a[0].world[0][1])); testing.expect(t, math.abs(a[1].world[0][1]) < math.abs(a[0].world[0][1])); max_a, max_b := f32(0), f32(0); for face in a do for point in face.world do max_a = max(max_a, point[2]); for face in b do for point in face.world do max_b = max(max_b, point[2]); testing.expect(t, max_a > 1.4 && max_b > 1.4); testing.expect(t, max_a != max_b || a[0].world != b[0].world)
}

@(test)
delta_citadel_mass_communicates_ship_family :: proc(t: ^testing.T) {
	module := game.Procedural_Ship_Placement {
		surface_id = 0xf3000000,
		module     = .Keel,
		material   = .Armor,
	}; extents := [3][2]f32{}
	for family in game.Procedural_Ship_Family {faces := make([dynamic]Ship_Project_Face, 0, 8, context.temp_allocator); ship_append_delta_citadel_faces(&faces, module, 24301, family, 7, 3, 1, Ship_Generator_Camera{}, rl.Vector2{}, 1); max_y, max_z := f32(0), f32(0); for face in faces do for point in face.world {max_y = max(max_y, math.abs(point[1])); max_z = max(max_z, point[2])}; extents[int(family)] = {max_y, max_z}}
	strike, fleet, habitat :=
		extents[int(game.Procedural_Ship_Family.Strike)],
		extents[int(game.Procedural_Ship_Family.Fleet)],
		extents[int(game.Procedural_Ship_Family.Habitat)]; testing.expect(t, strike[0] < fleet[0] && fleet[0] < habitat[0]); testing.expect(t, strike[1] < fleet[1] && fleet[1] < habitat[1])
}

@(test)
delta_axial_keel_ridge_is_surface_fitted_and_family_scaled :: proc(t: ^testing.T) {
	seed := u64(
		24301,
	); sx, sy, sz := f32(7), f32(3), f32(.88); module := game.Procedural_Ship_Placement {
		surface_id = 0xf3000000,
		module     = .Keel,
		material   = .Armor,
	}
	for family in game.Procedural_Ship_Family {faces := make([dynamic]Ship_Project_Face, 0, 6, context.temp_allocator); ship_append_delta_keel_ridge_faces(&faces, module, seed, family, sx, sy, sz, Ship_Generator_Camera{}, rl.Vector2{}, 1); testing.expect_value(t, len(faces), 6); testing.expect_value(t, faces[0].material, game.Ship_Material_Class.Armor); for root in faces[0].world {expected := ship_delta_surface_z(seed, sx, sy, sz, root[0], root[1], true, family); testing.expect(t, math.abs(root[2] - expected) < .001)}}
	strike := ship_delta_keel_ridge_rise(
		.Strike,
		sz,
	); fleet := ship_delta_keel_ridge_rise(.Fleet, sz); habitat := ship_delta_keel_ridge_rise(.Habitat, sz); testing.expect(t, strike < fleet && fleet < habitat)
}

@(test)
delta_exposed_systems_receive_armored_hull_roots :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		architecture = .Delta,
		frame = {keel_length = 14, beam = 6, height = 4},
		module_count = 3,
	}; r.modules[0] = {
		module   = .Radiator,
		position = {1, -8, 3},
		scale    = {.8, 1.4, .12},
	}; r.modules[1] = {
		module   = .Antenna,
		position = {2, 7, 4},
		scale    = {.3, .4, .9},
	}; r.modules[2] = {
		module   = .Mission,
		position = {0, 0, 0},
		scale    = {1, 1, 1},
	}
	faces := make(
		[dynamic]Ship_Project_Face,
		0,
		16,
		context.temp_allocator,
	); hull := game.Procedural_Ship_Placement {
		surface_id = 0xf3000000,
		module     = .Keel,
		material   = .Hull_Plate,
	}; ship_append_delta_mount_fairings(
		&faces,
		&r,
		hull,
		7,
		3,
		.88,
		Ship_Generator_Camera{},
		rl.Vector2{},
		1,
		true,
	); testing.expect_value(t, len(faces), 12); for face in faces do testing.expect_value(t, face.material, game.Ship_Material_Class.Armor)
}

@(test)
delta_hulls_project_bounded_service_history_onto_the_dorsal_wing :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		seed = 24301,
		family = .Fleet,
		architecture = .Delta,
		frame = {keel_length = 14, beam = 6, height = 4},
		module_count = 3,
	}; r.modules[0] = {
		module       = .Mission,
		surface_id   = 11,
		service_mark = .Patch_Plate,
	}; r.modules[1] = {
		module       = .Tank,
		surface_id   = 12,
		service_mark = .Breach_Cage,
	}; r.modules[2] = {
		module       = .Armor,
		surface_id   = 13,
		service_mark = .Dark_Scar,
	}; hull := game.Procedural_Ship_Placement {
		surface_id = 0xf3000000,
		module     = .Keel,
		material   = .Hull_Plate,
		direction  = {1, 0, 0},
		scale      = {7, 3, .88},
	}
	close_faces := make(
		[dynamic]Ship_Project_Face,
		0,
		48,
		context.temp_allocator,
	); distant_faces := make([dynamic]Ship_Project_Face, 0, 16, context.temp_allocator); ship_append_delta_history_faces(&close_faces, &r, hull, 7, 3, .88, Ship_Generator_Camera{}, rl.Vector2{}, 1, true); ship_append_delta_history_faces(&distant_faces, &r, hull, 7, 3, .88, Ship_Generator_Camera{}, rl.Vector2{}, 1, false); testing.expect_value(t, len(close_faces), 42); testing.expect_value(t, len(distant_faces), 12); for face in close_faces {testing.expect(t, face.surface_id >= 0xf3000680 && face.surface_id < 0xf3000800); testing.expect(t, face.material == .Armor || face.material == .Truss)}
}

@(test)
delta_exposed_modules_mount_on_the_local_hull_surface :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		seed = 24301,
		architecture = .Delta,
		frame = {keel_length = 14, beam = 6, height = 4},
	}; radiator_source := game.Procedural_Ship_Placement {
		module   = .Radiator,
		position = {3, -8, 5},
		scale    = {.8, 1.4, .12},
	}; radiator := ship_closed_hull_mount_module(
		&r,
		radiator_source,
	); half_beam, _, _ := ship_delta_section_at_x(r.seed, 7, 3, .88, radiator.position[0], r.family); testing.expect(t, math.abs(math.abs(radiator.position[1]) - half_beam) < .001); testing.expect_value(t, radiator.direction, [3]f32{0, -1, 0})
	dorsal_source := game.Procedural_Ship_Placement {
		module   = .Antenna,
		position = {2, 8, 5},
		scale    = {.3, .4, .9},
	}; dorsal := ship_closed_hull_mount_module(
		&r,
		dorsal_source,
	); sx, sy, sz := ship_delta_half_extents(&r); expected_top := ship_delta_surface_z(r.seed, sx, sy, sz, dorsal.position[0], dorsal.position[1], true, r.family); testing.expect(t, math.abs(dorsal.position[2] - expected_top) < .001); testing.expect_value(t, dorsal.direction, [3]f32{0, 0, 1}); testing.expect(t, dorsal.scale[0] <= sx * .045 + .001 && dorsal.scale[1] <= sy * .075 + .001 && dorsal.scale[2] <= sz * 1.25 + .001); dorsal_root := ship_module_local_point(dorsal, {0, 0, -dorsal.scale[2]}); testing.expect(t, math.abs(dorsal_root[2] - dorsal.position[2]) < .001)
	ventral_source :=
		dorsal_source; ventral_source.position[2] = -5; ventral := ship_closed_hull_mount_module(&r, ventral_source); expected_bottom := ship_delta_surface_z(r.seed, sx, sy, sz, ventral.position[0], ventral.position[1], false, r.family); testing.expect(t, math.abs(ventral.position[2] - expected_bottom) < .001); testing.expect_value(t, ventral.direction, [3]f32{0, 0, -1})
}

@(test)
delta_surface_sampler_matches_the_rendered_triangle_fan :: proc(t: ^testing.T) {
	seed := u64(
		24301,
	); sx, sy, sz := f32(7), f32(3), f32(.88); plan := ship_delta_planform(seed, sx, sy); top, bottom := ship_delta_edge_vertical(seed, plan[1][0], 1, sx, sz); testing.expect(t, math.abs(ship_delta_surface_z(seed, sx, sy, sz, plan[1][0], plan[1][1], true) - top) < .001); testing.expect(t, math.abs(ship_delta_surface_z(seed, sx, sy, sz, plan[1][0], plan[1][1], false) - bottom) < .001); testing.expect(t, math.abs(ship_delta_surface_z(seed, sx, sy, sz, -sx * .05, 0, true) - sz * 1.22) < .001); testing.expect(t, math.abs(ship_delta_surface_z(seed, sx, sy, sz, -sx * .12, 0, false) + sz) < .001); mid_x := (-sx * .05 + plan[1][0]) * .5; mid_y := plan[1][1] * .5; expected := (sz * 1.22 + top) * .5; testing.expect(t, math.abs(ship_delta_surface_z(seed, sx, sy, sz, mid_x, mid_y, true) - expected) < .001)
}

@(test)
legacy_saucer_mounts_normalize_to_the_delta_hull_envelope :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		seed = 24301,
		architecture = .Saucer,
		frame = {keel_length = 14, beam = 5.2, height = 3.2},
	}; drive_source := game.Procedural_Ship_Placement {
		module   = .Drive,
		position = {-20, 8, 5},
		scale    = {.7, .5, .5},
	}; drive := ship_closed_hull_mount_module(
		&r,
		drive_source,
	); radiator := ship_closed_hull_mount_module(&r, {module = .Radiator, position = {2, -8, 5}}); antenna := ship_closed_hull_mount_module(&r, {module = .Antenna, position = {3, 8, 5}}); sx, _, _ := ship_delta_half_extents(&r); testing.expect(t, math.abs(drive.position[0] + sx * .88) < .001 && math.abs(drive.position[1]) < r.frame.beam * .2); testing.expect(t, radiator.position[1] < 0 && math.abs(radiator.position[1]) <= r.frame.beam * .5); testing.expect(t, antenna.position[1] > 0 && antenna.position[2] <= r.frame.height * .5)
}
