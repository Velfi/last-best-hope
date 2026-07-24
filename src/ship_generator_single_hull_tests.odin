package main

import game "../packages/game"
import "core:c"
import "core:fmt"
import "core:math"
import "core:testing"
import stbi "vendor:stb/image"
import rl "zelda_engine:canvas2d"
@(test)
single_hull_architecture_closes_the_axial_frame :: proc(t: ^testing.T) {
	r := game.procedural_ship_generate_for_ship(
		game.Ship {
			id = 4,
			construction_seed = 404,
			generator_kind = .Single_Hull,
			hull_archetype = .Heavy_Cruiser,
			operational_role = .Heavy_Cruiser,
		},
	)
	faces := make([dynamic]Ship_Project_Face, 0, 32, context.temp_allocator)
	ship_append_single_hull_faces(&faces, &r, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	testing.expect(t, len(faces) >= 70)
	hull_faces, armor_faces := 0, 0
	for face in faces {if face.material == .Hull_Plate do hull_faces += 1
		if face.material == .Armor do armor_faces += 1}
	testing.expect(t, hull_faces >= 64); testing.expect(t, armor_faces >= 20)
}

@(test)
habitat_single_hulls_express_rotation_districts_as_pressure_shoulders :: proc(t: ^testing.T) {
	for ring_count in 2 ..= 3 {
		beam := [SHIP_SINGLE_HULL_SECTION_COUNT]f32{1, 1, 1, 1, 1, 1, 1}
		height := beam
		ship_single_hull_apply_habitat_districts(&beam, &height, ring_count)
		if ring_count == 2 {
			testing.expect(t, beam[2] > beam[3] * 2)
			testing.expect(t, beam[4] > beam[3] * 2)
			testing.expect(t, height[2] > height[3] * 1.5)
		} else {
			testing.expect(t, beam[1] > beam[2] * 1.9)
			testing.expect(t, beam[3] > beam[2] * 1.9)
			testing.expect(t, beam[5] > beam[4] * 1.9)
		}
	}
}

@(test)
strike_single_hulls_use_a_long_low_pressure_envelope_and_matching_mounts :: proc(t: ^testing.T) {
	fleet := game.Procedural_Ship_Recipe {
		family = .Fleet,
		architecture = .Single_Hull,
		frame = {keel_length = 14, beam = 5.2, height = 3.2},
	}
	strike := fleet
	strike.family = .Strike
	fleet_length, fleet_beam, fleet_height := ship_single_hull_half_extents(&fleet)
	strike_length, strike_beam, strike_height := ship_single_hull_half_extents(&strike)
	testing.expect(t, strike_length / strike_beam > fleet_length / fleet_beam * 1.4)
	testing.expect(t, strike_height < fleet_height * .83)
	radiator := ship_closed_hull_mount_module(&strike, {module = .Radiator, position = {0, 8, 0}})
	testing.expect(t, math.abs(radiator.position[1] - strike_beam * .78) < .001)
	drive := ship_closed_hull_mount_module(&strike, {module = .Drive, scale = {.8, .4, .4}})
	testing.expect(t, math.abs(drive.position[0] + strike_length * .88) < .001)
}

@(test)
single_hull_only_exposes_space_facing_modules :: proc(t: ^testing.T) {
	for module in game.Procedural_Ship_Module {
		expected := module == .Drive || module == .Radiator || module == .Antenna
		testing.expect_value(
			t,
			ship_module_exposed_by_architecture(.Single_Hull, module),
			expected,
		)
		testing.expect(t, ship_module_exposed_by_architecture(.Modular_Frame, module))
	}
}

@(test)
single_hull_internal_warts_follow_installed_inventory :: proc(t: ^testing.T) {
	hull := game.Procedural_Ship_Placement {
		module    = .Keel,
		material  = .Hull_Plate,
		direction = {1, 0, 0},
		scale     = {7, 2.6, 1.85},
	}
	base := game.Procedural_Ship_Recipe {
		seed         = 23,
		architecture = .Single_Hull,
	}
	with_internal := base
	with_internal.module_count = 1
	with_internal.modules[0] = {
		surface_id = 17,
		module     = .Mission,
		position   = {1.5, 4, 2},
	}
	plain_faces := make([dynamic]Ship_Project_Face, 0, context.temp_allocator)
	wart_faces := make([dynamic]Ship_Project_Face, 0, context.temp_allocator)
	ship_append_single_hull_internal_warts(
		&plain_faces,
		&base,
		hull,
		Ship_Generator_Camera{},
		rl.Vector2{},
		1,
		true,
	)
	ship_append_single_hull_internal_warts(
		&wart_faces,
		&with_internal,
		hull,
		Ship_Generator_Camera{},
		rl.Vector2{},
		1,
		true,
	)
	testing.expect_value(t, len(plain_faces), 0)
	testing.expect_value(t, len(wart_faces), 6)
	for face in wart_faces do testing.expect_value(t, face.material, game.Ship_Material_Class.Machinery)
}

@(test)
single_hulls_project_hidden_service_history_onto_the_dorsal_armor_belt :: proc(t: ^testing.T) {
	expected := [3]int{12, 30, 24}
	marks := [3]game.Procedural_Ship_Service_Mark{.Patch_Plate, .Breach_Cage, .Dark_Scar}
	for mark_kind, i in marks {
		plain := game.Procedural_Ship_Recipe {
			seed = 24303,
			family = .Fleet,
			architecture = .Single_Hull,
			frame = {keel_length = 14, beam = 5.2, height = 3.2},
			module_count = 1,
		}
		plain.modules[0] = {
			module     = .Mission,
			surface_id = 117,
		}
		marked := plain
		marked.modules[0].service_mark = mark_kind
		plain_faces := make([dynamic]Ship_Project_Face, 0, 192, context.temp_allocator)
		marked_faces := make([dynamic]Ship_Project_Face, 0, 224, context.temp_allocator)
		ship_append_single_hull_faces(
			&plain_faces,
			&plain,
			Ship_Generator_Camera{},
			rl.Vector2{},
			1,
			false,
		)
		ship_append_single_hull_faces(
			&marked_faces,
			&marked,
			Ship_Generator_Camera{},
			rl.Vector2{},
			1,
			false,
		)
		testing.expect_value(t, len(marked_faces) - len(plain_faces), expected[i])
		history_faces := 0
		for face in marked_faces do if face.surface_id >= 0xf1000800 && face.surface_id < 0xf1000b00 {
			history_faces += 1
			testing.expect(t, face.material != .Hull_Plate)
		}
		testing.expect_value(t, history_faces, expected[i])
	}
}

@(test)
single_hull_carrier_surface_adds_hangar_beyond_bridge_glazing :: proc(t: ^testing.T) {
	base := game.Procedural_Ship_Recipe {
		seed = 17,
		family = .Fleet,
		architecture = .Single_Hull,
		frame = {keel_length = 14, beam = 5.2, height = 3.2},
	}
	carrier := base; carrier.module_count = 1; carrier.modules[0].module = .Dock
	plain_faces := make([dynamic]Ship_Project_Face, 0, 128, context.temp_allocator)
	carrier_faces := make([dynamic]Ship_Project_Face, 0, 160, context.temp_allocator)
	ship_append_single_hull_faces(&plain_faces, &base, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	ship_append_single_hull_faces(
		&carrier_faces,
		&carrier,
		Ship_Generator_Camera{},
		rl.Vector2{},
		1,
	)
	plain_glass, carrier_glass := 0, 0
	plain_armor, carrier_armor := 0, 0
	for face in plain_faces do if face.material == .Glass do plain_glass += 1
	for face in carrier_faces do if face.material == .Glass do carrier_glass += 1
	for face in plain_faces do if face.material == .Armor do plain_armor += 1
	for face in carrier_faces do if face.material == .Armor do carrier_armor += 1
	testing.expect(t, plain_glass >= 48); testing.expect_value(t, carrier_glass - plain_glass, 1)
	testing.expect_value(
		t,
		carrier_armor - plain_armor,
		10,
	); testing.expect_value(t, len(carrier_faces) - len(plain_faces), 17)
}

@(test)
single_hull_fleet_stern_adds_paired_armored_auxiliary_drives :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		seed = 31,
		family = .Fleet,
		architecture = .Single_Hull,
		frame = {keel_length = 14, beam = 5.2, height = 3.2},
	}
	faces := make([dynamic]Ship_Project_Face, 0, 256, context.temp_allocator)
	ship_append_single_hull_faces(&faces, &r, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	drive_faces := 0
	for face in faces do if face.material == .Drive do drive_faces += 1
	testing.expect_value(t, drive_faces, 12)
}

@(test)
single_hull_fleet_weapon_packages_change_external_store_geometry :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		seed = 31,
		family = .Fleet,
		architecture = .Single_Hull,
		weapon_capability_scale = 1,
		frame = {keel_length = 14, beam = 5.2, height = 3.2},
	}
	counts: [3]int
	packages := [3]game.Ship_Weapon_Package{.Railgun_Battery, .Heavy_Torpedoes, .Guided_Missiles}
	for weapon, index in packages {
		r.weapon_package = weapon
		faces := make([dynamic]Ship_Project_Face, 0, 512, context.temp_allocator)
		ship_append_single_hull_faces(&faces, &r, Ship_Generator_Camera{}, rl.Vector2{}, 1, false)
		counts[index] = len(faces)
	}
	testing.expect(t, counts[1] < counts[0])
	testing.expect(t, counts[0] < counts[2])
}

@(test)
single_hull_direct_fire_packages_change_shoulder_battery_geometry :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		seed = 31,
		family = .Fleet,
		architecture = .Single_Hull,
		weapon_capability_scale = 1,
		frame = {keel_length = 14, beam = 5.2, height = 3.2},
	}
	counts: [5]int
	packages := [5]game.Ship_Weapon_Package {
		.Chemical_Autocannon,
		.Coilgun_Battery,
		.Railgun_Battery,
		.Defensive_Laser,
		.Offensive_Laser,
	}
	for weapon, index in packages {
		r.weapon_package = weapon
		faces := make([dynamic]Ship_Project_Face, 0, 512, context.temp_allocator)
		ship_append_single_hull_faces(&faces, &r, Ship_Generator_Camera{}, rl.Vector2{}, 1, false)
		counts[index] = len(faces)
	}
	testing.expect(t, counts[3] < counts[0])
	testing.expect(t, counts[0] < counts[4])
	testing.expect(t, counts[4] < counts[1])
	testing.expect_value(t, counts[1], counts[2])
}

@(test)
single_hull_strike_weapon_packages_generate_distinct_dorsal_installations :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		seed = 31,
		family = .Strike,
		architecture = .Single_Hull,
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
		ship_append_single_hull_faces(&faces, &r, Ship_Generator_Camera{}, rl.Vector2{}, 1, false)
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
single_hull_strike_weapon_mounts_are_seed_stable_but_not_seed_identical :: proc(t: ^testing.T) {
	r := game.Procedural_Ship_Recipe {
		seed = 31,
		family = .Strike,
		architecture = .Single_Hull,
		weapon_package = .Guided_Missiles,
		weapon_capability_scale = 1,
		frame = {keel_length = 14, beam = 5.2, height = 3.2},
	}
	hull := game.Procedural_Ship_Placement {
		surface_id = 0xf0000000,
		module = .Keel,
		material = .Hull_Plate,
		direction = {1, 0, 0},
		scale = {7, 2.6, 1.6},
	}
	first := make([dynamic]Ship_Project_Face, 0, 256, context.temp_allocator)
	repeat := make([dynamic]Ship_Project_Face, 0, 256, context.temp_allocator)
	other := make([dynamic]Ship_Project_Face, 0, 256, context.temp_allocator)
	ship_append_single_hull_strike_weapon_faces(&first, &r, hull, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	ship_append_single_hull_strike_weapon_faces(&repeat, &r, hull, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	r.seed = 32
	ship_append_single_hull_strike_weapon_faces(&other, &r, hull, Ship_Generator_Camera{}, rl.Vector2{}, 1)
	testing.expect_value(t, len(first), len(repeat))
	testing.expect_value(t, len(first), len(other))
	changed := false
	store_min_z, store_max_z := f32(1000), f32(-1000)
	for face, index in first {
		testing.expect_value(t, face.world, repeat[index].world)
		changed = changed || face.world != other[index].world
		if face.surface_id >= 0xe6000100 {
			for point in face.world {
				store_min_z = min(store_min_z, point[2])
				store_max_z = max(store_max_z, point[2])
			}
		}
	}
	testing.expect(t, changed)
	// Launch shoes intersect the dorsal saddle while the rounds themselves clear
	// the pressure-shell contour, preserving both attachment and side readability.
	testing.expect(t, store_min_z < hull.scale[2] * 1.04)
	testing.expect(t, store_max_z > hull.scale[2] * 1.14)
}

draw_procedural_ship :: proc(
	r: ^game.Procedural_Ship_Recipe,
	rect: rl.Rectangle,
	camera: Ship_Generator_Camera,
	detail := true,
	shared_span := Ship_View_Span{},
	clear_background := true,
	exhaust_phase := f32(0),
	exhaust_output := f32(1),
	isolated_strike_weapon := false,
) {
	if clear_background do rl.DrawRectangleRec(rect, {0, 0, 0, 255})
	center, scale := ship_recipe_view_fit(r, camera, rect, shared_span)
	faces := make([dynamic]Ship_Project_Face, 0, r.module_count * 12, context.temp_allocator)
	if ship_architecture_has_closed_hull(r.architecture) {
		ship_append_closed_architecture_faces(&faces, r, camera, center, scale, detail)
	} else {
		for station in 1 ..< r.frame.station_count do ship_append_keel_bridge_faces(&faces, r, station, camera, center, scale)
		ship_append_strike_prow_bridle_faces(&faces, r, camera, center, scale)
		ship_append_modular_fleet_weapon_faces(&faces, r, camera, center, scale)
	}
	greebly_budgets := [5]int{0, 8, 16, 30, 48}
	greebly_budget := detail ? greebly_budgets[clamp(r.greebly_density, 0, 4)] : 0
	if greebly_budget > 0 && ship_architecture_has_closed_hull(r.architecture) {
		greebly_budget -= ship_append_closed_hull_auto_greeblies(
			&faces,
			r,
			r.greebly_density,
			greebly_budget,
			camera,
			center,
			scale,
		)
	}
	if !isolated_strike_weapon {
		for module in r.modules[:r.module_count] {
			if !ship_module_exposed_by_architecture(r.architecture, module.module) do continue
			mounted := ship_closed_hull_mount_module(r, module)
			if !detail && r.architecture == .Delta && mounted.module == .Drive {
				ship_append_delta_distant_drive_faces(
					&faces,
					mounted,
					r.family,
					camera,
					center,
					scale,
				)
			} else {
				ship_append_module_faces(&faces, mounted, r.family, camera, center, scale)
			}
			if greebly_budget > 0 do greebly_budget -= ship_append_auto_greeblies(&faces, mounted, r.greebly_density, greebly_budget, camera, center, scale)
		}
	}
	ship_face_sort(faces[:])
	occluders := make([dynamic]int, 0, len(faces), context.temp_allocator)
	for face, face_index in faces do if ship_face_camera_facing(face) do append(&occluders, face_index)
	for i in 1 ..< len(
		occluders,
	) {value := occluders[i]; j := i; for j > 0 && faces[occluders[j - 1]].bounds_min.x > faces[value].bounds_min.x {occluders[j] = occluders[j - 1]; j -= 1}; occluders[j] = value}
	if !isolated_strike_weapon do for module in r.modules[:r.module_count] do if module.module == .Drive {mounted := ship_closed_hull_mount_module(r, module); ship_draw_drive_scatter(mounted, r.family, camera, center, scale, detail, exhaust_phase, exhaust_output)}
	if !isolated_strike_weapon && r.architecture == .Modular_Frame do for module in r.modules[:r.module_count] do if module.module == .Dock do ship_draw_dock_guides(module, camera, center, scale, detail)
	if !isolated_strike_weapon && r.architecture == .Modular_Frame do ship_draw_axial_longeron(r, camera, center, scale, detail)
	// Open structural rails sit beneath opaque equipment. Drawing this cheap
	// line geometry first lets solid hull faces mask it instead of allowing the
	// truss engraving to bleed across payloads and the axial spine.
	if !isolated_strike_weapon && r.architecture == .Modular_Frame do for module in r.modules[:r.module_count] do if module.module == .Truss do ship_draw_truss_structure(module, camera, center, scale, detail)
	light_dir := [3]f32{-.42, -.36, .83}
	for face_index in 0 ..< len(faces) {
		face := faces[face_index]
		// Orthographic solid modules never expose their rear-facing polygons.
		// Culling them before fill keeps dense contact sheets below the canvas's
		// fixed vertex budget and prevents late cells from losing their edge pass.
		if !ship_face_camera_facing(face) do continue
		// Painter ordering plus an opaque black ground gives the procedural
		// modules solid mass; the second pass cuts light back into that darkness.
		light := clamp(
			face.normal[0] * light_dir[0] +
			face.normal[1] * light_dir[1] +
			face.normal[2] * light_dir[2],
			f32(0),
			f32(1),
		)
		tone := ship_material_base_tone(face.material, light, detail)
		rl.DrawQuadHatched(
			face.points[0],
			face.points[1],
			face.points[2],
			face.points[3],
			{tone, tone, tone, 255},
			rl.HATCH_DISABLED,
		)
		config :=
			ship_architecture_has_closed_hull(r.architecture) ? ship_single_hull_hatch_for_view(face.material, light, face.surface_id, detail) : ship_material_hatch_for_view(face.material, light, face.surface_id, detail)
		if r.architecture == .Delta do config = ship_delta_hatch_for_family_view(config, r.family, detail)
		config.offset = {f32(face.surface_id % 97) * 3.1, f32(face.surface_id % 53) * 2.7}
		alpha := detail ? u8(90 + int(light * 165)) : u8(66 + int(light * 132))
		if ship_architecture_has_closed_hull(
			r.architecture,
		) {if face.material == .Hull_Plate do alpha = u8(int(alpha) * 58 / 100); if face.material == .Armor do alpha = u8(int(alpha) * 78 / 100)}
		rl.DrawQuadHatched(
			face.points[0],
			face.points[1],
			face.points[2],
			face.points[3],
			{231, 229, 211, alpha},
			config,
		)
		ship_draw_wireframe_face(
			faces[:],
			occluders[:],
			face_index,
			detail,
			ship_architecture_has_closed_hull(r.architecture) && face.material == .Hull_Plate,
		)
	}
	// Explicit axes and silhouettes survive when hatch layers fade at distance.
	line :=
		detail ? f32(1.15) : f32(.82); ink := detail ? rl.Color{222, 220, 207, 165} : rl.Color{210, 208, 197, 125}
	for source in r.modules[:r.module_count] {
		if !ship_module_exposed_by_architecture(r.architecture, source.module) do continue
		module := ship_closed_hull_mount_module(r, source)
		mount_p :=
			ship_project(module.position, camera, center, scale).screen; module_center := ship_module_render_origin(module); if module.module == .Ring_Segment do module_center = {module.position[0], 0, 0}; p := ship_project(module_center, camera, center, scale).screen
		if r.architecture ==
		   .Modular_Frame {if socket_index := int(module.socket); socket_index >= 0 && r.sockets[socket_index].parent >= 0 {
				parent :=
					r.modules[int(r.sockets[socket_index].parent)]; parent_p := ship_project(parent.position, camera, center, scale).screen
				if module.module != .Truss &&
				   parent.module !=
					   .Truss {rl.DrawLineEx(parent_p, mount_p, detail ? f32(2.2) : f32(1.4), {8, 8, 7, 255}); rl.DrawLineEx(parent_p, mount_p, detail ? f32(.95) : f32(.7), {218, 216, 203, 155})}
			}}
		if module.module == .Truss do continue
		basis_axis, _, _ := ship_module_basis(
			module,
		); axis := ship_project({module_center[0] + basis_axis[0] * module.scale[0], module_center[1] + basis_axis[1] * module.scale[0], module_center[2] + basis_axis[2] * module.scale[0]}, camera, center, scale).screen
		if module.module ==
		   .Ring_Segment {ship_draw_ring_structure(module, camera, center, scale, detail); continue}
		rl.DrawLineEx(p, axis, line, ink)
		if module.module ==
		   .Antenna {tip := ship_project(ship_module_local_point(module, {0, 0, module.scale[2] * 1.2}), camera, center, scale).screen; rl.DrawLineEx(p, tip, 1, {225, 224, 211, 180})}
	}
}
