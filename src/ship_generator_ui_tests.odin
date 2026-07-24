package main

import game "../packages/game"
import "core:c"
import "core:fmt"
import "core:math"
import "core:testing"
import stbi "vendor:stb/image"
import rl "zelda_engine:canvas2d"

@(test)
ship_service_marks_add_distinct_local_patch_breach_and_dark_geometry :: proc(t: ^testing.T) {
	expected := [3]int{12, 30, 24}
	marks := [3]game.Procedural_Ship_Service_Mark{.Patch_Plate, .Breach_Cage, .Dark_Scar}
	for mark, i in marks {
		faces := make([dynamic]Ship_Project_Face, 0, 32, context.temp_allocator)
		module := game.Procedural_Ship_Placement {
			module       = .Mission,
			material     = .Machinery,
			service_mark = mark,
			surface_id   = 19,
			scale        = {1, .7, .8},
			direction    = {1, 0, 0},
		}
		ship_append_service_mark_faces(&faces, module, Ship_Generator_Camera{}, rl.Vector2{}, 1)
		testing.expect_value(t, len(faces), expected[i])
		for face in faces do testing.expect(t, face.material != .Machinery)
	}
}

@(test)
ship_greebly_selection_is_deterministic_and_preserves_open_trusses :: proc(t: ^testing.T) {
	modules := [12]game.Procedural_Ship_Module {
		.Keel,
		.Pressure_Hull,
		.Tank,
		.Radiator,
		.Drive,
		.Mission,
		.Dock,
		.Antenna,
		.Bow,
		.Armor,
		.Ring_Segment,
		.Truss,
	}
	seen: [12]bool
	for module_kind, i in modules {
		module := game.Procedural_Ship_Placement {
			id         = u32(i + 1),
			surface_id = u32(101 + i * 7919),
			module     = module_kind,
			material   = .Hull_Plate,
			scale      = {1, .7, .8},
			direction  = {1, 0, 0},
		}
		first := ship_greebly_for_module(module); second := ship_greebly_for_module(module)
		testing.expect_value(t, first, second); seen[int(first)] = true
		faces := make([dynamic]Ship_Project_Face, 0, 32, context.temp_allocator)
		ship_append_greebly_faces(&faces, module, Ship_Generator_Camera{}, rl.Vector2{}, 1)
		if module_kind ==
		   .Truss {testing.expect_value(t, len(faces), 0)} else {testing.expect(t, len(faces) >= 12); for face in faces do testing.expect(t, face.material != .Hull_Plate)}
	}
	kinds_seen := 0; for present in seen do if present do kinds_seen += 1
	testing.expect(t, kinds_seen >= 7)
}

@(test)
every_ship_greebly_builds_a_small_distinct_functional_assembly :: proc(t: ^testing.T) {
	expected_faces := [12]int{12, 24, 12, 12, 12, 12, 18, 12, 12, 12, 18, 12}
	module := game.Procedural_Ship_Placement {
		id         = 17,
		surface_id = 991,
		module     = .Mission,
		material   = .Hull_Plate,
		scale      = {1, .7, .8},
		direction  = {1, 0, 0},
	}
	for kind in Ship_Greebly {
		faces := make([dynamic]Ship_Project_Face, 0, 24, context.temp_allocator)
		ship_append_greebly_kind_faces(
			&faces,
			module,
			kind,
			Ship_Generator_Camera{},
			rl.Vector2{},
			1,
		)
		testing.expect_value(t, len(faces), expected_faces[int(kind)])
		material_changed := false
		for face in faces {
			testing.expect(t, face.material != .Hull_Plate)
			if face.material != .Machinery do material_changed = true
			for point in face.points {
				testing.expect(t, math.abs(point.x) < 4)
				testing.expect(t, math.abs(point.y) < 4)
			}
		}
		// Assemblies with lenses, armor, exhaust, or lifting structure must retain
		// that material cue instead of collapsing into undifferentiated machinery.
		if kind == .Inspection_Hatch || kind == .Attitude_Jet || kind == .Sensor_Blister || kind == .Lifting_Lugs || kind == .Junction_Box || kind == .Work_Light || kind == .Docking_Cleat || kind == .Micrometeor_Shield do testing.expect(t, material_changed)
	}
}

@(test)
greebly_density_autoplaces_monotonically_with_seeded_rules_and_a_budget :: proc(t: ^testing.T) {
	modules := [6]game.Procedural_Ship_Module {
		.Keel,
		.Pressure_Hull,
		.Tank,
		.Mission,
		.Dock,
		.Armor,
	}
	counts: [5]int
	for density in 0 ..< 5 {
		for module_kind, i in modules {
			module := game.Procedural_Ship_Placement {
				id         = u32(i + 31),
				surface_id = u32(7001 + i * 104729),
				module     = module_kind,
				material   = .Hull_Plate,
				scale      = {1, .7, .8},
				direction  = {1, 0, 0},
			}
			first := ship_greebly_slot_count(
				module,
				density,
			); repeat := ship_greebly_slot_count(module, density)
			testing.expect_value(
				t,
				first,
				repeat,
			); testing.expect(t, first >= 0 && first <= 3); counts[density] += first
		}
	}
	testing.expect_value(t, counts[0], 0)
	for density in 1 ..< 5 do testing.expect(t, counts[density] >= counts[density - 1])
	faces := make([dynamic]Ship_Project_Face, 0, 64, context.temp_allocator)
	module := game.Procedural_Ship_Placement {
		id         = 91,
		surface_id = 8191,
		module     = .Mission,
		material   = .Hull_Plate,
		scale      = {1, .7, .8},
		direction  = {1, 0, 0},
	}
	placed := ship_append_auto_greeblies(
		&faces,
		module,
		4,
		2,
		Ship_Generator_Camera{},
		rl.Vector2{},
		1,
	)
	testing.expect(t, placed <= 2); testing.expect(t, len(faces) >= placed * 12)
}

@(test)
every_closed_hull_architecture_accepts_deterministic_surface_greeblies :: proc(t: ^testing.T) {
	architectures := [2]game.Ship_Generator_Kind{.Single_Hull, .Delta}
	for architecture in architectures {
		r := game.Procedural_Ship_Recipe {
			seed = 24301,
			family = .Fleet,
			architecture = architecture,
			greebly_density = 4,
			frame = {keel_length = 14, beam = 5.2, height = 3.2},
		}
		first := make([dynamic]Ship_Project_Face, 0, 128, context.temp_allocator)
		repeat := make([dynamic]Ship_Project_Face, 0, 128, context.temp_allocator)
		first_count := ship_append_closed_hull_auto_greeblies(
			&first,
			&r,
			4,
			12,
			Ship_Generator_Camera{},
			rl.Vector2{},
			1,
		)
		repeat_count := ship_append_closed_hull_auto_greeblies(
			&repeat,
			&r,
			4,
			12,
			Ship_Generator_Camera{},
			rl.Vector2{},
			1,
		)
		testing.expect(t, first_count > 0 && first_count <= 12)
		testing.expect_value(t, repeat_count, first_count)
		testing.expect_value(t, len(repeat), len(first))
		for face, i in first {
			testing.expect_value(t, repeat[i].surface_id, face.surface_id)
			testing.expect_value(t, repeat[i].world, face.world)
		}
		other := r
		other.seed += 1
		other_faces := make([dynamic]Ship_Project_Face, 0, 128, context.temp_allocator)
		other_count := ship_append_closed_hull_auto_greeblies(
			&other_faces,
			&other,
			4,
			12,
			Ship_Generator_Camera{},
			rl.Vector2{},
			1,
		)
		testing.expect(t, other_count > 0)
		varied := other_count != first_count || len(other_faces) != len(first)
		for face, i in other_faces {
			if i >= len(first) {
				varied = true
				break
			}
			if face.surface_id != first[i].surface_id || face.world != first[i].world {
				varied = true
				break
			}
		}
		testing.expect(t, varied)
	}
}

@(test)
retired_saucer_architecture_normalizes_to_delta :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		game.ship_generator_kind_supported(.Saucer),
		game.Ship_Generator_Kind.Delta,
	)
	testing.expect_value(t, game.ship_generator_kind_name(.Saucer), "DELTA")
}

@(test)
strike_frame_prow_bridle_is_paired_open_and_bow_convergent :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		family = .Strike,
		architecture = .Modular_Frame,
		frame = {keel_length = 12, beam = 3.2, height = 1.4},
	}
	faces := make([dynamic]Ship_Project_Face, 0, 12, context.temp_allocator)
	ship_append_strike_prow_bridle_faces(&faces, &r, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	testing.expect_value(t, len(faces), 48)
	rear_beam, forward_beam := f32(0), f32(1000)
	for face in faces {
		for point in face.world {
			if point[0] < 0 {
				rear_beam = max(rear_beam, math.abs(point[1]))
			} else {
				forward_beam = min(forward_beam, math.abs(point[1]))
			}
		}
	}
	testing.expect(t, rear_beam > r.frame.beam * .25)
	testing.expect(t, forward_beam < r.frame.beam * .1)
}

@(test)
strike_weapon_packages_generate_distinct_installed_geometry :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		family = .Strike,
		architecture = .Modular_Frame,
		weapon_capability_scale = 1,
		frame = {keel_length = 12, beam = 3.2, height = 1.4},
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
		faces := make([dynamic]Ship_Project_Face, 0, 192, context.temp_allocator)
		ship_append_strike_prow_bridle_faces(&faces, &r, Ship_Generator_Camera{}, rl.Vector2{}, 1)
		counts[index] = len(faces)
	}
	testing.expect_value(t, counts[0], 42)
	testing.expect_value(t, counts[1], 48)
	testing.expect_value(t, counts[2], 48)
	testing.expect_value(t, counts[3], 34)
	testing.expect_value(t, counts[4], 46)
	testing.expect_value(t, counts[5], 264)
	testing.expect_value(t, counts[6], 126)
}

@(test)
missile_engine_bells_open_toward_local_aft :: proc(t: ^testing.T) {
	module := game.Procedural_Ship_Placement {
		surface_id = 0xe7000000,
		module     = .Tank,
		material   = .Drive,
		direction  = {1, 0, 0},
		scale      = {1, .2, .2},
	}
	faces := make([dynamic]Ship_Project_Face, 0, 8, context.temp_allocator)
	ship_append_weapon_engine_faces(
		&faces,
		module,
		.25,
		1.08,
		Ship_Generator_Camera{},
		rl.Vector2{},
		1,
	)
	testing.expect_value(t, len(faces), 5)
	aft_exit_faces := 0
	for face in faces {
		for point in face.world do testing.expect(t, point[0] <= -.96)
		exit_plane := true
		for point in face.world do exit_plane = exit_plane && point[0] < -1.24
		if exit_plane {
			aft_exit_faces += 1
			testing.expect(t, face.normal[0] < 0)
		}
	}
	testing.expect_value(t, aft_exit_faces, 1)
}

@(test)
torpedo_engine_bells_remain_compact_relative_to_missile_bells :: proc(t: ^testing.T) {
	module := game.Procedural_Ship_Placement {
		surface_id = 0xe7000100,
		module     = .Tank,
		material   = .Drive,
		direction  = {1, 0, 0},
		scale      = {1, .2, .2},
	}
	missile := make([dynamic]Ship_Project_Face, 0, 8, context.temp_allocator)
	torpedo := make([dynamic]Ship_Project_Face, 0, 8, context.temp_allocator)
	ship_append_weapon_engine_faces(
		&missile,
		module,
		.22,
		1.08,
		Ship_Generator_Camera{},
		rl.Vector2{},
		1,
	)
	ship_append_weapon_engine_faces(
		&torpedo,
		module,
		.14,
		.86,
		Ship_Generator_Camera{},
		rl.Vector2{},
		1,
	)
	missile_min_x, torpedo_min_x := f32(1000), f32(1000)
	missile_radius, torpedo_radius := f32(0), f32(0)
	for face in missile do for point in face.world {
		missile_min_x = min(missile_min_x, point[0])
		missile_radius = max(missile_radius, math.abs(point[1]))
	}
	for face in torpedo do for point in face.world {
		torpedo_min_x = min(torpedo_min_x, point[0])
		torpedo_radius = max(torpedo_radius, math.abs(point[1]))
	}
	testing.expect(t, torpedo_min_x > missile_min_x)
	testing.expect(t, torpedo_radius < missile_radius)
}

@(test)
modular_fleet_weapon_packages_generate_distinct_transverse_batteries :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		family = .Fleet,
		architecture = .Modular_Frame,
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
		faces := make([dynamic]Ship_Project_Face, 0, 256, context.temp_allocator)
		ship_append_modular_fleet_weapon_faces(
			&faces,
			&r,
			Ship_Generator_Camera{},
			rl.Vector2{},
			1,
		)
		counts[index] = len(faces)
	}
	testing.expect(t, counts[3] < counts[0])
	testing.expect(t, counts[0] < counts[4])
	testing.expect(t, counts[4] < counts[1])
	testing.expect_value(t, counts[1], counts[2])
	testing.expect(t, counts[2] < counts[6])
	testing.expect(t, counts[6] < counts[5])
	testing.expect(t, counts[5] - counts[6] >= 32)
	testing.expect(t, counts[6] - counts[2] >= 24)
}

@(test)
generated_open_frames_keep_center_of_mass_near_the_thrust_axis :: proc(t: ^testing.T) {
	families := [3]game.Procedural_Ship_Family{.Strike, .Fleet, .Habitat}
	for family in families {
		for row in 0 ..< 4 {
			for seed in u64(24301) ..< 24317 {
				ship := ship_generator_contact_identity(seed, seed, family, row)
				ship.generator_kind = .Modular_Frame
				r := game.procedural_ship_generate_for_ship(ship)
				offset := game.procedural_ship_transverse_mass_offset(&r)
				allowance := max(r.frame.beam * .10, f32(.08))
				testing.expectf(
					t,
					offset <= allowance,
					"family=%v row=%d seed=%d transverse_com=%.3f allowance=%.3f",
					family,
					row,
					seed,
					offset,
					allowance,
				)
			}
		}
	}
}

@(test)
every_surviving_architecture_keeps_rendered_mass_near_its_thrust_axis :: proc(t: ^testing.T) {
	families := [3]game.Procedural_Ship_Family{.Strike, .Fleet, .Habitat}
	architectures := [3]game.Ship_Generator_Kind{.Modular_Frame, .Single_Hull, .Delta}
	for architecture in architectures {
		for family in families {
			for row in 0 ..< 4 {
				for seed in u64(24301) ..< 24317 {
					ship := ship_generator_contact_identity(seed, seed, family, row)
					ship.generator_kind = architecture
					r := game.procedural_ship_generate_for_ship(ship)
					offset := ship_rendered_transverse_mass_offset(&r)
					allowance := max(r.frame.beam * .05, f32(.05))
					testing.expectf(
						t,
						offset <= allowance,
						"architecture=%v family=%v row=%d seed=%d rendered_com=%.3f allowance=%.3f",
						architecture,
						family,
						row,
						seed,
						offset,
						allowance,
					)
				}
			}
		}
	}
}

@(test)
off_axis_payloads_size_their_support_from_the_supported_envelope :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		family = .Strike,
		frame = {beam = 3.2},
		socket_count = 2,
		module_count = 2,
		sockets = {0 = {parent = -1}, 1 = {parent = 0}},
		modules = {
			0 = {module = .Truss, scale = {1.4, .04, .04}, mass = .01},
			1 = {module = .Mission, position = {0, 1.5, 0}, scale = {.8, 1.2, .7}, mass = 2},
		},
		mass = 2.01,
	}
	game.procedural_ship_reinforce_payload_support(&r, 1)
	testing.expect(t, r.modules[0].scale[1] >= r.modules[1].scale[1] * .18)
	testing.expect(t, r.modules[0].scale[2] >= r.modules[1].scale[2] * .18)
	testing.expect(t, r.modules[0].mass > .01)
}

@(test)
transformed_structural_connectors_span_parent_to_payload :: proc(t: ^testing.T) {
	for family in game.Procedural_Ship_Family do for row in 0 ..< 12 {
		ship := ship_generator_contact_identity(28101 + u64(row), 28101, family, row)
		r := game.procedural_ship_generate_for_ship(ship)
		checked := 0
		for connector, connector_index in r.modules[:r.module_count] {
			if connector.module != .Truss do continue
			parent_index := int(r.sockets[connector_index].parent)
			if parent_index < 0 do continue
			child_index := -1
			for socket, index in r.sockets[:r.socket_count] {
				if int(socket.parent) == connector_index {
					child_index = index
					break
				}
			}
			if child_index < 0 do continue
			endpoints := [2]int{parent_index, child_index}
			for endpoint in endpoints {
				delta := [3]f32{r.modules[endpoint].position[0] - connector.position[0], r.modules[endpoint].position[1] - connector.position[1], r.modules[endpoint].position[2] - connector.position[2]}
				along := delta[0] * connector.direction[0] + delta[1] * connector.direction[1] + delta[2] * connector.direction[2]
				perpendicular := [3]f32{delta[0] - connector.direction[0] * along, delta[1] - connector.direction[1] * along, delta[2] - connector.direction[2] * along}
				perpendicular_distance := f32(math.sqrt(f64(perpendicular[0] * perpendicular[0] + perpendicular[1] * perpendicular[1] + perpendicular[2] * perpendicular[2])))
				testing.expect(t, math.abs(along) <= connector.scale[0] + .001)
				testing.expect(t, perpendicular_distance < .001)
			}
			checked += 1
		}
		testing.expect(t, checked > 0)
	}
}

@(test)
drive_aperture_tracks_final_frame_while_visual_masses_preserve_ship_total :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		family = .Habitat,
		frame = {beam = 6.4, height = 3.2},
		module_count = 2,
		modules = {
			0 = {module = .Drive, scale = {.8, .2, .2}, mass = 1},
			1 = {module = .Mission, scale = {1, 1.5, 1}, mass = 9},
		},
		mass = 10,
	}
	game.procedural_ship_fit_drive_to_frame(&r)
	game.procedural_ship_normalize_visual_mass_distribution(&r, 10)
	testing.expect(t, r.modules[0].scale[1] >= r.frame.beam * .16)
	testing.expect(t, r.modules[0].scale[2] >= r.frame.height * .22)
	testing.expect(t, math.abs(r.mass - 10) < .0001)
	testing.expect(t, math.abs(r.modules[0].mass + r.modules[1].mass - 10) < .0001)
	testing.expect(t, r.modules[1].mass > r.modules[0].mass)
}

@(test)
fleet_and_habitat_radiator_area_tracks_hull_section_and_drive_output :: proc(t: ^testing.T) {
	families := [2]game.Procedural_Ship_Family{.Fleet, .Habitat}
	for family in families {
		r := game.Procedural_Ship_Recipe {
			family = family,
			drive_capability_scale = 1.2,
			frame = {keel_length = 18, beam = 6},
			module_count = 3,
			modules = {
				0 = {module = .Drive, scale = {.8, 1, .8}},
				1 = {module = .Radiator, scale = {.2, .3, .04}},
				2 = {module = .Radiator, scale = {.2, .3, .04}},
			},
		}
		before := game.procedural_ship_radiator_area(&r)
		game.procedural_ship_fit_radiators_to_power(&r)
		after := game.procedural_ship_radiator_area(&r)
		testing.expect(t, after > before)
		testing.expect(t, after + .0001 >= game.procedural_ship_required_radiator_area(&r))
		testing.expect_value(t, r.modules[1].scale, r.modules[2].scale)
		testing.expect(t, after > game.procedural_ship_drive_aperture_area(&r) * 10)
	}
}

@(test)
ship_truss_is_an_open_rail_bulkhead_and_cross_braced_frame :: proc(t: ^testing.T) {
	module := game.Procedural_Ship_Placement {
		module    = .Truss,
		material  = .Truss,
		position  = {0, 0, 0},
		scale     = {1, .2, .2},
		direction = {0, 1, 0},
	}
	segments := ship_truss_local_segments(module)
	testing.expect_value(t, len(segments), SHIP_TRUSS_SEGMENT_COUNT)
	for segment in segments[:4] {
		testing.expect_value(t, segment[0][0], -module.scale[0])
		testing.expect_value(t, segment[1][0], module.scale[0])
	}
	for segment in segments[4:8] {
		for point in segment do testing.expect_value(t, point[0], -module.scale[0])
	}
	for segment in segments[8:12] {
		for point in segment do testing.expect_value(t, point[0], module.scale[0])
	}
	for segment in segments[12:16] {
		for point in segment do testing.expect_value(t, point[0], f32(0))
	}
	for segment in segments[16:] {
		testing.expect(
			t,
			math.abs(math.abs(segment[1][0] - segment[0][0]) - module.scale[0]) < .0001,
		)
		testing.expect(t, segment[0][1] != segment[1][1] || segment[0][2] != segment[1][2])
	}
}

@(test)
ship_axial_bays_are_four_longeron_frames_bounded_by_station_sections :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		family = .Fleet,
		frame = {station_count = 2},
		module_count = 2,
		modules = {
			0 = {position = {-2, 0, 0}, scale = {.8, .6, .4}},
			1 = {position = {2, 0, 0}, scale = {.8, .4, .3}},
		},
	}
	segments := ship_axial_bay_segments(&r, 1)
	testing.expect_value(t, len(segments), SHIP_AXIAL_BAY_SEGMENT_COUNT)
	for segment in segments[:4] {
		testing.expect_value(t, segment[0][0], f32(-2))
		testing.expect_value(t, segment[1][0], f32(2))
	}
	for segment in segments[12:] {
		testing.expect_value(t, segment[0][0], f32(-2))
		testing.expect_value(t, segment[1][0], f32(2))
		testing.expect(t, segment[0][1] != segment[1][1] || segment[0][2] != segment[1][2])
	}
	expected_y := r.modules[1].scale[1] * .38
	expected_z := r.modules[1].scale[2] * .38
	for segment in segments {
		for point in segment {
			testing.expect(t, math.abs(point[1]) <= expected_y + .0001)
			testing.expect(t, math.abs(point[2]) <= expected_z + .0001)
		}
	}
}

@(test)
ship_armor_is_a_chamfered_plate_flared_from_its_mounting_plane :: proc(t: ^testing.T) {
	face_count := SHIP_ARMOR_SEGMENTS * 3
	faces := make([dynamic]Ship_Project_Face, 0, face_count, context.temp_allocator)
	module := game.Procedural_Ship_Placement {
		module    = .Armor,
		material  = .Armor,
		position  = {2, 3, 4},
		scale     = {.75, .5, .25},
		direction = {0, 1, 0},
	}
	ship_append_armor_faces(&faces, module, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	testing.expect_value(t, len(faces), face_count)
	inboard := ship_module_local_point(module, {-module.scale[0], 0, 0})
	for coordinate in 0 ..< 3 do testing.expect(t, math.abs(inboard[coordinate] - module.position[coordinate]) < .0001)
}

@(test)
ship_antenna_uses_a_mast_and_paired_receiver_head :: proc(t: ^testing.T) {
	faces := make([dynamic]Ship_Project_Face, 0, 18, context.temp_allocator)
	module := game.Procedural_Ship_Placement {
		module    = .Antenna,
		material  = .Glass,
		position  = {2, 3, 4},
		scale     = {.3, .3, 1.2},
		direction = {0, 1, 0},
	}
	ship_append_antenna_faces(&faces, module, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	testing.expect_value(t, len(faces), 18)
	mast_base := ship_module_local_point(module, {0, 0, -module.scale[2]})
	for coordinate in 0 ..< 3 do testing.expect(t, math.abs(mast_base[coordinate] - module.position[coordinate]) < .0001)
}

@(test)
ship_drive_redundancy_scales_from_strike_to_fleet_to_habitat :: proc(t: ^testing.T) {
	module := game.Procedural_Ship_Placement {
		module   = .Drive,
		material = .Drive,
		position = {0, 0, 0},
		scale    = {1, 1, 1},
	}
	expected := [3]int{3, 4, 5}
	for family in game.Procedural_Ship_Family {
		faces := make(
			[dynamic]Ship_Project_Face,
			0,
			SHIP_DRIVE_MAX_NOZZLES * SHIP_DRIVE_SEGMENTS * SHIP_DRIVE_FACES_PER_SEGMENT,
			context.temp_allocator,
		)
		ship_append_drive_faces(&faces, module, family, Ship_Generator_Camera{}, rl.Vector2{}, 1)
		testing.expect_value(
			t,
			ship_drive_nozzle_count(module, family),
			expected[int(family)],
		); testing.expect_value(t, len(faces), expected[int(family)] * (SHIP_DRIVE_SEGMENTS * SHIP_DRIVE_FACES_PER_SEGMENT + 6) + 6)
		for nozzle in 0 ..< expected[int(family)] {
			first := nozzle * SHIP_DRIVE_SEGMENTS * SHIP_DRIVE_FACES_PER_SEGMENT
			// Each segment contributes an outer facet, lip, liner, and throat face.
			for segment in 0 ..< SHIP_DRIVE_SEGMENTS do for part in 0 ..< SHIP_DRIVE_FACES_PER_SEGMENT do testing.expect_value(t, faces[first + segment * SHIP_DRIVE_FACES_PER_SEGMENT + part].material, game.Ship_Material_Class.Drive)
		}
	}
}

@(test)
ship_drive_nozzles_overlap_their_forward_mount :: proc(t: ^testing.T) {
	module := game.Procedural_Ship_Placement {
		module    = .Drive,
		material  = .Drive,
		direction = {1, 0, 0},
		scale     = {1, 1, 1},
	}
	faces := make([dynamic]Ship_Project_Face, context.temp_allocator)
	ship_append_drive_faces(&faces, module, .Strike, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	forward := f32(1e30)
	for face in faces do for point in face.world do forward = min(forward, point[0])
	testing.expect(t, forward < -module.scale[0] * SHIP_DRIVE_LENGTH_SCALE)
}

@(test)
ship_drive_manifold_encloses_the_complete_bell_cluster :: proc(t: ^testing.T) {
	module := game.Procedural_Ship_Placement {
		module  = .Drive,
		scale   = {1, 1, 1},
		variant = 0,
	}
	offsets, radii, count := ship_drive_nozzle_profile(module, .Strike)
	center, enclosure := ship_drive_manifold_envelope(module, .Strike)
	for nozzle in 0 ..< count {
		oy := offsets[nozzle][0] * module.scale[1] * SHIP_DRIVE_RADIAL_SCALE
		oz := offsets[nozzle][1] * module.scale[2] * SHIP_DRIVE_RADIAL_SCALE
		radius_y := module.scale[1] * radii[nozzle] * .55 * SHIP_DRIVE_RADIAL_SCALE
		radius_z := module.scale[2] * radii[nozzle] * .55 * SHIP_DRIVE_RADIAL_SCALE
		testing.expect(t, oy - radius_y >= center[1] - enclosure[1])
		testing.expect(t, oy + radius_y <= center[1] + enclosure[1])
		testing.expect(t, oz - radius_z >= center[2] - enclosure[2])
		testing.expect(t, oz + radius_z <= center[2] + enclosure[2])
	}
}

@(test)
ship_drive_identity_variants_have_distinct_bank_envelopes :: proc(t: ^testing.T) {
	inline_drive := game.Procedural_Ship_Placement {
		module  = .Drive,
		variant = 0,
	}; clustered :=
		inline_drive; clustered.variant = 1; outboard := inline_drive; outboard.variant = 2
	i, _, _ := ship_drive_nozzle_profile(
		inline_drive,
		.Strike,
	); c, _, _ := ship_drive_nozzle_profile(clustered, .Strike); o, r, _ := ship_drive_nozzle_profile(outboard, .Strike)
	testing.expect_value(t, i[0][0], f32(0)); testing.expect(t, c[0][0] != 0)
	testing.expect(
		t,
		math.abs(o[0][0]) > math.abs(c[0][0]),
	); testing.expect(t, r[2] < r[0] && r[2] < r[1])
}

@(test)
ship_drive_power_adds_centered_bells :: proc(t: ^testing.T) {
	low := game.Procedural_Ship_Placement {
		module           = .Drive,
		drive_power_tier = -1,
	}
	nominal := low; nominal.drive_power_tier = 0
	high := low; high.drive_power_tier = 1
	for family in game.Procedural_Ship_Family {
		low_offsets, _, low_count := ship_drive_nozzle_profile(low, family)
		nominal_offsets, _, nominal_count := ship_drive_nozzle_profile(nominal, family)
		high_offsets, _, high_count := ship_drive_nozzle_profile(high, family)
		testing.expect_value(t, nominal_count - low_count, 1)
		testing.expect_value(t, high_count - nominal_count, 1)
		profiles := [3]struct {
			values: [SHIP_DRIVE_MAX_NOZZLES][2]f32,
			count:  int,
		} {
			{values = low_offsets, count = low_count},
			{values = nominal_offsets, count = nominal_count},
			{values = high_offsets, count = high_count},
		}
		for offsets in profiles {
			center: f32
			for i in 0 ..< offsets.count do center += offsets.values[i][1]
			testing.expect(t, math.abs(center) < .0001)
		}
	}
}

@(test)
ship_bow_identity_variants_are_angular_and_topologically_distinct :: proc(t: ^testing.T) {
	blunt_beam, blunt_height, bumper := ship_bow_tip_profile(
		0,
	); standard_beam, standard_height, _ := ship_bow_tip_profile(1); needle_beam, needle_height, _ := ship_bow_tip_profile(2)
	testing.expect(t, bumper && blunt_beam > standard_beam && standard_beam > needle_beam)
	testing.expect(t, blunt_height > standard_height && standard_height > needle_height)
	for family in game.Procedural_Ship_Family do for variant in 0 ..< 3 {
		faces := make([dynamic]Ship_Project_Face, 0, 32, context.temp_allocator)
		module := game.Procedural_Ship_Placement {
			module   = .Bow,
			material = .Hull_Plate,
			scale    = {1, 1, 1},
			variant  = u8(variant),
		}
		ship_append_bow_faces(&faces, module, family, Ship_Generator_Camera{}, rl.Vector2{}, 1)
		expected := 24 + (variant == 0 ? 6 : 0) + ship_bow_family_subassembly_count(family) * 6
		testing.expect_value(t, len(faces), expected)
		if family != .Strike {distinct_material := 0; for face in faces do if face.material != .Hull_Plate do distinct_material += 1; testing.expect_value(t, distinct_material, ship_bow_family_subassembly_count(family) * 6)}
	}
	strike_side, strike_deck := ship_bow_chine_profile(
		.Strike,
	); fleet_side, fleet_deck := ship_bow_chine_profile(.Fleet); habitat_side, habitat_deck := ship_bow_chine_profile(.Habitat)
	testing.expect(t, strike_side < fleet_side && strike_deck < fleet_deck)
	testing.expect(t, habitat_deck > fleet_deck && habitat_side != fleet_side)
}

@(test)
ship_drive_scatter_has_one_aft_anchored_channel_per_nozzle :: proc(t: ^testing.T) {
	module := game.Procedural_Ship_Placement {
		module     = .Drive,
		material   = .Drive,
		position   = {2, 3, 4},
		scale      = {1, .8, .7},
		surface_id = 23,
	}
	segments, count := ship_drive_scatter_segments(
		module,
		.Habitat,
	); rear_x := module.position[0] + module.scale[0] * SHIP_DRIVE_LENGTH_SCALE
	low, _ := ship_drive_scatter_segments(
		module,
		.Habitat,
		.85,
	); high, _ := ship_drive_scatter_segments(module, .Habitat, 1.15)
	small := module; small.scale = {.58, .45, .41}; large := module; large.scale = {.96, .75, .67}
	small_segments, _ := ship_drive_scatter_segments(
		small,
		.Strike,
	); large_segments, _ := ship_drive_scatter_segments(large, .Habitat)
	testing.expect_value(t, count, 5)
	testing.expect(t, high[0][1][0] - high[0][0][0] > low[0][1][0] - low[0][0][0])
	testing.expect(
		t,
		large_segments[0][1][0] - large_segments[0][0][0] >
		small_segments[0][1][0] - small_segments[0][0][0],
	)
	for segment, i in segments[:count] {
		testing.expect(t, math.abs(segment[0][0] - rear_x) < .0001)
		testing.expect(t, segment[1][0] > segment[0][0])
		testing.expect_value(
			t,
			segment[0][1],
			segment[1][1],
		); testing.expect_value(t, segment[0][2], segment[1][2])
		if i > 0 do testing.expect(t, segment[0][1] != segments[0][0][1] || segment[0][2] != segments[0][0][2])
	}
}

@(test)
ship_drive_bells_and_scatter_follow_the_module_axis :: proc(t: ^testing.T) {
	module := game.Procedural_Ship_Placement {
		module     = .Drive,
		material   = .Drive,
		position   = {2, 3, 4},
		scale      = {1, .8, .7},
		direction  = {0, 1, 0},
		surface_id = 23,
	}
	faces := make(
		[dynamic]Ship_Project_Face,
		0,
		SHIP_DRIVE_MAX_NOZZLES * SHIP_DRIVE_SEGMENTS * SHIP_DRIVE_FACES_PER_SEGMENT,
		context.temp_allocator,
	)
	ship_append_drive_faces(&faces, module, .Strike, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	expected_rear := ship_module_local_point(
		module,
		{module.scale[0] * SHIP_DRIVE_LENGTH_SCALE, 0, 0},
	)
	testing.expect(t, math.abs(faces[0].world[0][1] - expected_rear[1]) < .0001)
	testing.expect(t, math.abs(faces[0].world[0][0] - module.position[0]) > module.scale[0] * .1)
	segments, count := ship_drive_scatter_segments(module, .Strike)
	testing.expect_value(t, count, 3)
	for segment in segments[:count] {
		dx, dy, dz :=
			segment[1][0] -
			segment[0][0],
			segment[1][1] -
			segment[0][1],
			segment[1][2] -
			segment[0][2]
		testing.expect(t, math.abs(dx) < .0001 && dy > 0 && math.abs(dz) < .0001)
	}
}

@(test)
ship_drive_bells_flare_toward_the_module_aft_axis :: proc(t: ^testing.T) {
	module := game.Procedural_Ship_Placement {
		module    = .Drive,
		material  = .Drive,
		direction = {-1, 0, 0},
		scale     = {1, .8, .7},
	}
	faces := make([dynamic]Ship_Project_Face, 0, 128, context.temp_allocator)
	ship_append_drive_faces(&faces, module, .Strike, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	outer := faces[0]
	rear_chord := f32(
		math.sqrt(
			f64(
				(outer.world[3][1] - outer.world[0][1]) * (outer.world[3][1] - outer.world[0][1]) +
				(outer.world[3][2] - outer.world[0][2]) * (outer.world[3][2] - outer.world[0][2]),
			),
		),
	)
	throat_chord := f32(
		math.sqrt(
			f64(
				(outer.world[2][1] - outer.world[1][1]) * (outer.world[2][1] - outer.world[1][1]) +
				(outer.world[2][2] - outer.world[1][2]) * (outer.world[2][2] - outer.world[1][2]),
			),
		),
	)
	testing.expect(t, rear_chord > throat_chord * 1.7)
	// With an aft axis of -X, the wide exit must be farther left than the throat.
	testing.expect(t, outer.world[0][0] < outer.world[1][0])
	segments, count := ship_drive_scatter_segments(module, .Strike)
	testing.expect_value(t, count, 3)
	for segment in segments[:count] do testing.expect(t, segment[1][0] < segment[0][0])
}

@(test)
generated_modular_drive_bells_open_away_from_the_hull :: proc(t: ^testing.T) {
	// The construction keel advances toward +X, while the first socket is the
	// stern drive. Its axis must point aft so the wide bell exit never projects
	// into an ordinary modular ship's bow.
	for family in game.Procedural_Ship_Family {
		r := game.procedural_ship_generate(24301, family)
		drive := r.modules[0]
		testing.expect_value(t, drive.module, game.Procedural_Ship_Module.Drive)
		testing.expect(t, drive.direction[0] < 0)
		faces := make([dynamic]Ship_Project_Face, 0, 128, context.temp_allocator)
		ship_append_drive_faces(&faces, drive, family, Ship_Generator_Camera{}, rl.Vector2{}, 1)
		exit_x := f32(1e30)
		for point in faces[0].world do exit_x = min(exit_x, point[0])
		testing.expect(t, exit_x < drive.position[0] - drive.scale[0])
	}
}

@(test)
ship_pressure_hull_has_three_courses_and_two_end_caps :: proc(t: ^testing.T) {
	face_count := SHIP_PRESSURE_HULL_SEGMENTS * 3 + SHIP_PRESSURE_HULL_SEGMENTS * 2
	faces := make([dynamic]Ship_Project_Face, 0, face_count, context.temp_allocator)
	module := game.Procedural_Ship_Placement {
		module   = .Pressure_Hull,
		material = .Pressure_Vessel,
		position = {0, 0, 0},
		scale    = {1, 1, 1},
	}
	ship_append_radial_faces(&faces, module, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	testing.expect_value(t, len(faces), face_count)
}

@(test)
ship_tank_has_a_capped_barrel_two_restraint_bands_and_a_paired_cradle :: proc(t: ^testing.T) {
	// Barrel: six walls and twelve cap wedges. Bands: twelve walls. Cradle:
	// two six-faced longitudinal rails.
	face_count := SHIP_TANK_SEGMENTS * 5 + 12
	faces := make([dynamic]Ship_Project_Face, 0, face_count, context.temp_allocator)
	module := game.Procedural_Ship_Placement {
		module    = .Tank,
		material  = .Pressure_Vessel,
		position  = {2, 3, 4},
		scale     = {1.2, .7, .7},
		direction = {0, 1, 0},
	}
	ship_append_tank_faces(&faces, module, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	testing.expect_value(t, len(faces), face_count)
	// Like every branch payload, the inboard tank end still begins exactly at
	// its socket even though its visible load path now includes cradle rails.
	inboard := ship_module_local_point(module, {-module.scale[0], 0, 0})
	for coordinate in 0 ..< 3 do testing.expect(t, math.abs(inboard[coordinate] - module.position[coordinate]) < .0001)
}

@(test)
ship_radiator_panels_share_a_socket_anchored_deployment_frame :: proc(t: ^testing.T) {
	part_count := 3 + 2
	faces := make([dynamic]Ship_Project_Face, 0, part_count * 6, context.temp_allocator)
	module := game.Procedural_Ship_Placement {
		module    = .Radiator,
		material  = .Radiator,
		position  = {2, 3, 4},
		scale     = {.8, 1.2, .08},
		direction = {0, 1, 0},
	}
	ship_append_radiator_faces(&faces, module, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	testing.expect_value(t, len(faces), part_count * 6)
	boom_base := ship_module_local_point(module, {-module.scale[0], 0, 0})
	for coordinate in 0 ..< 3 do testing.expect(t, math.abs(boom_base[coordinate] - module.position[coordinate]) < .0001)
}

@(test)
ship_radiator_variants_form_triptych_split_wing_and_stepped_comb :: proc(t: ^testing.T) {
	expected_faces := [3]int{30, 24, 36}
	for variant in 0 ..< 3 {
		faces := make([dynamic]Ship_Project_Face, context.temp_allocator)
		module := game.Procedural_Ship_Placement {
			module    = .Radiator,
			material  = .Radiator,
			scale     = {.8, 1.2, .08},
			direction = {1, 0, 0},
			variant   = u8(variant),
		}
		ship_append_radiator_faces(&faces, module, Ship_Generator_Camera{}, rl.Vector2{}, 1)
		testing.expect_value(t, len(faces), expected_faces[variant])
		for face in faces do for point in face.world {
			testing.expect(t, math.abs(point[0]) <= module.scale[0] + .001)
			testing.expect(t, math.abs(point[1]) <= module.scale[1] + .001)
			testing.expect(t, math.abs(point[2]) <= module.scale[2] + .001)
		}
	}
}

@(test)
radiator_keepouts_clear_modules_after_thermal_growth :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		family = .Fleet,
		frame = {beam = 5},
		module_count = 2,
		socket_count = 2,
		sockets = {0 = {parent = -1}, 1 = {parent = -1}},
		modules = {
			0 = {module = .Radiator, position = {}, direction = {0, 1, 0}, scale = {.8, 1.2, .08}},
			1 = {
				module = .Mission,
				position = {0, .5, 0},
				direction = {1, 0, 0},
				scale = {.7, .7, .7},
			},
		},
	}
	testing.expect(t, game.procedural_ship_modules_overlap_aabb(r.modules[0], r.modules[1]))
	game.procedural_ship_resolve_radiator_keepouts(&r)
	testing.expect(t, !game.procedural_ship_modules_overlap_aabb(r.modules[0], r.modules[1]))
	testing.expect(t, r.modules[0].position[1] > 0)
	testing.expect_value(t, r.sockets[0].position, r.modules[0].position)
}

@(test)
generated_radiators_preserve_keepout_clearance_across_families :: proc(t: ^testing.T) {
	families := [2]game.Procedural_Ship_Family{.Fleet, .Habitat}
	for family in families do for row in 0 ..< 16 {
		ship := ship_generator_contact_identity(29101 + u64(row), 29101, family, row)
		r := game.procedural_ship_generate_for_ship(ship)
		for radiator, radiator_index in r.modules[:r.module_count] {
			if radiator.module != .Radiator do continue
			parent_index := int(r.sockets[radiator_index].parent)
			for other, other_index in r.modules[:r.module_count] {
				if other_index == radiator_index || other_index == parent_index do continue
				testing.expectf(t, !game.procedural_ship_modules_overlap_aabb(radiator, other), "family=%v row=%d radiator=%d overlaps module=%d (%v)", family, row, radiator_index, other_index, other.module)
			}
		}
	}
}

@(test)
ship_dock_has_four_flared_guide_rails_and_an_outer_capture_frame :: proc(t: ^testing.T) {
	module := game.Procedural_Ship_Placement {
		module    = .Dock,
		material  = .Machinery,
		position  = {2, 3, 4},
		scale     = {.5, .8, .8},
		direction = {0, 1, 0},
	}
	segments := ship_dock_guide_local_segments(module)
	testing.expect_value(t, len(segments), 8)
	for segment, i in segments {
		if i < 4 {
			testing.expect_value(
				t,
				segment[0][0],
				module.scale[0],
			); testing.expect_value(t, segment[1][0], module.scale[0] * 1.72)
			testing.expect(
				t,
				math.abs(segment[1][1]) > math.abs(segment[0][1]),
			); testing.expect(t, math.abs(segment[1][2]) > math.abs(segment[0][2]))
		} else {
			testing.expect_value(
				t,
				segment[0][0],
				module.scale[0] * 1.72,
			); testing.expect_value(t, segment[1][0], module.scale[0] * 1.72)
		}
	}
	inner_world := ship_module_local_point(
		module,
		segments[0][0],
	); outer_world := ship_module_local_point(module, segments[0][1])
	testing.expect(t, outer_world[1] > inner_world[1])
}

@(test)
ship_mission_deck_has_a_sloped_housing_and_seeded_service_side :: proc(t: ^testing.T) {
	faces := make([dynamic]Ship_Project_Face, 0, 18, context.temp_allocator)
	module := game.Procedural_Ship_Placement {
		module     = .Mission,
		material   = .Machinery,
		position   = {2, 3, 4},
		scale      = {.9, .7, 1},
		direction  = {0, 1, 0},
		surface_id = 18,
		variant    = 1,
	}
	ship_append_mission_faces(&faces, module, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	testing.expect_value(t, len(faces), 18)
	testing.expect_value(t, ship_mission_service_side(18), f32(-1))
	testing.expect_value(t, ship_mission_service_side(19), f32(1))
	inboard := ship_module_local_point(module, {-module.scale[0], 0, 0})
	for coordinate in 0 ..< 3 do testing.expect(t, math.abs(inboard[coordinate] - module.position[coordinate]) < .0001)
}

@(test)
ship_mission_identity_variants_change_deck_topology :: proc(t: ^testing.T) {
	expected := [3]int{12, 18, 30}
	for variant in 0 ..< 3 {
		faces := make([dynamic]Ship_Project_Face, 0, expected[variant], context.temp_allocator)
		module := game.Procedural_Ship_Placement {
			module     = .Mission,
			material   = .Machinery,
			scale      = {.9, .7, 1},
			direction  = {0, 1, 0},
			surface_id = 19,
			variant    = u8(variant),
		}
		ship_append_mission_faces(&faces, module, Ship_Generator_Camera{}, rl.Vector2{}, 1)
		testing.expect_value(t, len(faces), expected[variant])
	}
}

@(test)
ship_mission_utility_hardpoints_cover_a_three_by_three_mount_grid :: proc(t: ^testing.T) {
	module := game.Procedural_Ship_Placement {
		module = .Mission,
		scale  = {1, 1, 1},
	}
	seen: [9]bool
	for slot in 0 ..< 9 {
		module.mount_variant = u8(slot); mount := ship_mission_mount_local(module)
		column := int(math.round(f64(mount[1] / .78))) + 1
		if slot % 3 == 1 do column = 1
		row := int(math.round(f64(mount[0] / .42))) + 1
		testing.expect(
			t,
			column >= 0 && column < 3 && row >= 0 && row < 3,
		); seen[row * 3 + column] = true
	}
	for present in seen do testing.expect(t, present)
	module.mount_variant = 1; port_center := ship_mission_mount_local(module); module.mount_variant = 10; starboard_center := ship_mission_mount_local(module)
	testing.expect(t, port_center[1] < 0 && starboard_center[1] > 0)
}

@(test)
ship_habitat_ring_is_a_continuous_smooth_pressure_frame :: proc(t: ^testing.T) {
	testing.expect_value(t, SHIP_HABITAT_RING_SEGMENTS, 24)
	face_count := SHIP_HABITAT_RING_SEGMENTS * 4
	faces := make([dynamic]Ship_Project_Face, 0, face_count, context.temp_allocator)
	module := game.Procedural_Ship_Placement {
		module     = .Ring_Segment,
		material   = .Pressure_Vessel,
		position   = {2, 3, 4},
		scale      = {.6, 2.4, 2.4},
		surface_id = 19,
	}
	ship_append_ring_faces(&faces, module, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	testing.expect_value(t, len(faces), face_count)
	base := module.surface_id * 64
	seen: [SHIP_HABITAT_RING_SEGMENTS]bool
	for face in faces do seen[int((face.surface_id - base) / 4)] = true
	for present in seen do testing.expect(t, present)
}

@(test)
ship_branch_payloads_begin_at_their_mounting_socket :: proc(t: ^testing.T) {
	kinds := [6]game.Procedural_Ship_Module {
		game.Procedural_Ship_Module.Armor,
		game.Procedural_Ship_Module.Pressure_Hull,
		game.Procedural_Ship_Module.Tank,
		game.Procedural_Ship_Module.Radiator,
		game.Procedural_Ship_Module.Mission,
		game.Procedural_Ship_Module.Dock,
	}
	for kind in kinds {
		module := game.Procedural_Ship_Placement {
			module    = kind,
			position  = {2, 3, 4},
			scale     = {.75, .5, .25},
			direction = {0, 1, 0},
		}
		axis, side, up := ship_module_basis(
			module,
		); origin := ship_module_render_origin(module); inboard := ship_module_local_point(module, {-module.scale[0], 0, 0})
		testing.expect_value(t, axis, [3]f32{0, 1, 0}); testing.expect(t, side != up)
		testing.expect_value(
			t,
			origin,
			[3]f32{2, 3.75, 4},
		); testing.expect_value(t, inboard, module.position)
	}
	antenna := game.Procedural_Ship_Placement {
		module    = .Antenna,
		position  = {2, 3, 4},
		scale     = {.2, .2, 1},
		direction = {0, 1, 0},
	}
	_, _, mast_up := ship_module_basis(
		antenna,
	); mast_base := ship_module_local_point(antenna, {0, 0, -antenna.scale[2]})
	testing.expect_value(
		t,
		mast_up,
		[3]f32{0, 1, 0},
	); testing.expect_value(t, mast_base, antenna.position)
}

@(test)
ship_visible_face_pass_keeps_front_and_grazing_faces_only :: proc(t: ^testing.T) {
	front := Ship_Project_Face {
		normal = {0, -1, 0},
	}; back := Ship_Project_Face {
		normal = {0, 1, 0},
	}; grazing := Ship_Project_Face {
		normal = {1, 0, 0},
	}
	testing.expect(
		t,
		ship_face_camera_facing(front),
	); testing.expect(t, ship_face_camera_facing(grazing)); testing.expect(t, !ship_face_camera_facing(back))
}

@(test)
ship_wireframe_classification_distinguishes_occluded_rear_edges :: proc(t: ^testing.T) {
	quad := [4]rl.Vector2{{0, 0}, {8, 0}, {8, 8}, {0, 8}}
	faces := [2]Ship_Project_Face {
		{points = quad, normal = {0, -1, 0}},
		{points = quad, normal = {0, 1, 0}},
	}
	testing.expect_value(t, ship_wireframe_edge_count(faces[:], true), 4)
	testing.expect_value(t, ship_wireframe_edge_count(faces[:], false), 4)
	faces[1].points[2] = faces[1].points[1]
	testing.expect_value(t, ship_wireframe_edge_count(faces[:], false), 3)
}

@(test)
ship_wireframe_depth_test_uses_per_pixel_face_depth :: proc(t: ^testing.T) {
	quad := [4]rl.Vector2{{0, 0}, {8, 0}, {8, 8}, {0, 8}}
	faces := [2]Ship_Project_Face {
		{points = quad, depths = {2, 2, 2, 2}, normal = {0, -1, 0}},
		{points = quad, depths = {1, 1, 1, 1}, normal = {0, -1, 0}},
	}
	testing.expect(t, ship_wireframe_point_occluded(faces[:], 0, {4, 4}, 2))
	testing.expect(t, !ship_wireframe_point_occluded(faces[:], 1, {4, 4}, 1))
	testing.expect(t, !ship_wireframe_point_occluded(faces[:], 0, {10, 4}, 2))
}

@(test)
ship_rendered_face_module_hit_uses_nearest_visible_surface :: proc(t: ^testing.T) {
	quad := [4]rl.Vector2{{0, 0}, {8, 0}, {8, 8}, {0, 8}}
	faces := [2]Ship_Project_Face {
		{points = quad, depths = {2, 2, 2, 2}, normal = {0, -1, 0}, module_id = 17},
		{points = quad, depths = {1, 1, 1, 1}, normal = {0, -1, 0}, module_id = 0},
	}
	testing.expect_value(t, ship_rendered_face_module_at(faces[:], {4, 4}), u32(0))
	testing.expect_value(t, ship_rendered_face_module_at(faces[:], {12, 4}), ~u32(0))
}

@(test)
ship_generated_faces_wind_consistently_with_view_space_normals :: proc(t: ^testing.T) {
	views := [4]Ship_Generator_Camera {
		{.52, .55, 1},
		{0, math.PI * .5, 1},
		{0, 0, 1},
		{math.PI * .5, 0, 1},
	}
	checked := 0
	for family in game.Procedural_Ship_Family do for row in 0 ..< 4 {
		ship := ship_generator_contact_identity(24301 + u64(row), 24301, family, row)
		r := game.procedural_ship_generate_for_ship(ship)
		for camera in views {
			faces := make([dynamic]Ship_Project_Face, 0, r.module_count * 24, context.temp_allocator)
			for station in 1 ..< r.frame.station_count do ship_append_keel_bridge_faces(&faces, &r, station, camera, rl.Vector2{}, 1)
			for module in r.modules[:r.module_count] do ship_append_module_faces(&faces, module, r.family, camera, rl.Vector2{}, 1)
			for face in faces {
				if math.abs(face.normal[1]) < .01 do continue
				checked += 1
				testing.expectf(t, ship_face_winding_matches_normal(face), "family=%v row=%d surface=%d normal_depth=%.4f signed_area=%.4f", family, row, face.surface_id, face.normal[1], ship_face_signed_area(face))
			}
		}
	}
	testing.expect(t, checked > 1000)
}

@(test)
ship_system_graph_is_deterministic_complete_and_physical :: proc(t: ^testing.T) {
	for family in game.Procedural_Ship_Family do for row in 0 ..< 4 {
		ship := ship_generator_contact_identity(27101 + u64(row), 27101, family, row)
		a := game.procedural_ship_generate_for_ship(ship)
		b := game.procedural_ship_generate_for_ship(ship)
		testing.expect_value(t, a.systems.fingerprint, b.systems.fingerprint)
		testing.expect_value(t, a.systems.node_count, b.systems.node_count)
		testing.expect_value(t, a.systems.link_count, b.systems.link_count)
		testing.expect(t, a.systems.complete)
		testing.expect(t, a.systems.balanced)
		testing.expect(t, game.procedural_ship_system_find(&a.systems, .Structure) >= 0)
		testing.expect(t, game.procedural_ship_system_find(&a.systems, .Drive) >= 0)
		testing.expect(t, game.procedural_ship_system_find(&a.systems, .Power) >= 0)
		testing.expect(t, game.procedural_ship_system_find(&a.systems, .Water) >= 0)
		if family == .Strike {
			testing.expect(t, game.procedural_ship_system_find(&a.systems, .Weapon) >= 0)
			testing.expect(t, game.procedural_ship_system_find(&a.systems, .Heat_Sink) >= 0)
		} else {
			first := game.procedural_ship_system_find(&a.systems, .Heat_Rejection, 0)
			second := game.procedural_ship_system_find(&a.systems, .Heat_Rejection, 1)
			testing.expect(t, first >= 0 && second >= 0)
			testing.expect(t, a.systems.nodes[first].position[1] * a.systems.nodes[second].position[1] < 0)
		}
		for node, index in a.systems.nodes[:a.systems.node_count] {
			if node.kind == .Structure do continue
			load_bearing := false
			for link in a.systems.links[:a.systems.link_count] {
				if link.kind == .Load && int(link.target) == index {
					load_bearing = true
					break
				}
			}
			testing.expectf(t, load_bearing, "family=%v system=%v lacks a structural load path", family, node.kind)
		}
	}
}
