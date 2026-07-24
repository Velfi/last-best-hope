package main

import game "../packages/game"
import "core:math"
import rl "zelda_engine:canvas2d"

// Greeblies are presentation-only service hardware. They never enter the
// procedural recipe, so adding close-view detail cannot perturb mass, sockets,
// solver backtracking, or the construction fingerprint.
Ship_Greebly :: enum u8 {
	Inspection_Hatch,
	Valve_Manifold,
	Cable_Trunk,
	Attitude_Jet,
	Sensor_Blister,
	Lifting_Lugs,
	Coolant_Pump,
	Junction_Box,
	Work_Light,
	Docking_Cleat,
	Pipe_Bridge,
	Micrometeor_Shield,
}

ship_greebly_for_module :: proc(module: game.Procedural_Ship_Placement) -> Ship_Greebly {
	choice :=
		int(
			(u64(module.surface_id) * 0x9e3779b97f4a7c15 ~ u64(module.id) * 0xbf58476d1ce4e5b9) >>
			32,
		) %
		3
	options: [3]Ship_Greebly
	switch module.module {
	case .Keel, .Bow, .Armor:
		options = {.Inspection_Hatch, .Lifting_Lugs, .Micrometeor_Shield}
	case .Pressure_Hull, .Ring_Segment:
		options = {.Inspection_Hatch, .Valve_Manifold, .Work_Light}
	case .Tank:
		options = {.Valve_Manifold, .Coolant_Pump, .Pipe_Bridge}
	case .Radiator, .Drive:
		options = {.Coolant_Pump, .Pipe_Bridge, .Junction_Box}
	case .Mission:
		options = {.Cable_Trunk, .Junction_Box, .Sensor_Blister}
	case .Dock:
		options = {.Work_Light, .Docking_Cleat, .Junction_Box}
	case .Antenna:
		options = {.Cable_Trunk, .Sensor_Blister, .Attitude_Jet}
	case .Truss:
		options = {.Cable_Trunk, .Lifting_Lugs, .Junction_Box}
	}
	return options[choice]
}

ship_append_greebly_kind_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	kind: Ship_Greebly,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	sx, sy, sz := module.scale[0], module.scale[1], module.scale[2]
	// Clamp the hardware to a close-view scale. Large habitat modules should not
	// turn the same valve or lamp into a silhouette-defining installation.
	gx := min(
		max(sx * .13, f32(.045)),
		f32(.22),
	); gy := min(max(sy * .12, f32(.035)), f32(.16)); gz := min(max(sz * .10, f32(.03)), f32(.14))
	hand: f32 = module.surface_id & 1 == 0 ? -1 : 1; base := u32(0x600 + int(kind) * 0x40)
	part := module; part.material = .Machinery
	switch kind {
	case .Inspection_Hatch:
		part.material = .Armor
		ship_append_local_box_faces(
			faces,
			part,
			{0, hand * sy * .34, sz + gz * .3},
			{gx * 1.45, gy * 1.3, gz * .3},
			base,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			part,
			{gx * .85, hand * sy * .34, sz + gz * .66},
			{gx * .12, gy * .82, gz * .12},
			base + 8,
			camera,
			center,
			scale,
		)
	case .Valve_Manifold:
		ship_append_local_box_faces(
			faces,
			part,
			{-gx * .35, hand * (sy + gy * .34), sz * .45},
			{gx * .78, gy * .34, gz * .62},
			base,
			camera,
			center,
			scale,
		)
		for valve in 0 ..< 3 do ship_append_local_box_faces(faces, part, {(-.78 + f32(valve) * .78) * gx, hand * (sy + gy * .76), sz * .62}, {gx * .12, gy * .28, gz * .12}, base + 8 + u32(valve * 8), camera, center, scale)
	case .Cable_Trunk:
		ship_append_local_box_faces(
			faces,
			part,
			{0, hand * (sy + gy * .2), sz * .58},
			{gx * 1.8, gy * .22, gz * .24},
			base,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			part,
			{gx * 1.42, hand * (sy + gy * .2), sz * .82},
			{gx * .24, gy * .22, gz * .48},
			base + 8,
			camera,
			center,
			scale,
		)
	case .Attitude_Jet:
		ship_append_local_box_faces(
			faces,
			part,
			{gx * .4, hand * (sy + gy * .5), sz * .62},
			{gx * .62, gy * .5, gz * .52},
			base,
			camera,
			center,
			scale,
		)
		part.material = .Drive
		ship_append_local_box_faces(
			faces,
			part,
			{gx * .4, hand * (sy + gy * 1.05), sz * .62},
			{gx * .34, gy * .28, gz * .3},
			base + 8,
			camera,
			center,
			scale,
		)
	case .Sensor_Blister:
		part.material = .Glass
		ship_append_local_box_faces(
			faces,
			part,
			{gx * .25, hand * sy * .28, sz + gz * .45},
			{gx * .72, gy * .72, gz * .45},
			base,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			part,
			{-gx * .52, hand * sy * .28, sz + gz * .2},
			{gx * .12, gy * .9, gz * .12},
			base + 8,
			camera,
			center,
			scale,
		)
	case .Lifting_Lugs:
		part.material = .Truss
		for lug in 0 ..< 2 do ship_append_local_box_faces(faces, part, {(f32(lug) * 2 - 1) * gx * .78, hand * sy * .42, sz + gz * .72}, {gx * .16, gy * .28, gz * .72}, base + u32(lug * 8), camera, center, scale)
	case .Coolant_Pump:
		ship_append_local_box_faces(
			faces,
			part,
			{0, hand * (sy + gy * .38), sz * .3},
			{gx, gy * .38, gz * .72},
			base,
			camera,
			center,
			scale,
		)
		for pipe in 0 ..< 2 do ship_append_local_box_faces(faces, part, {(f32(pipe) * 2 - 1) * gx * .72, hand * (sy + gy * .14), sz * .3}, {gx * .3, gy * .14, gz * .18}, base + 8 + u32(pipe * 8), camera, center, scale)
	case .Junction_Box:
		ship_append_local_box_faces(
			faces,
			part,
			{gx * .15, hand * (sy + gy * .3), sz * .5},
			{gx, gy * .3, gz * .82},
			base,
			camera,
			center,
			scale,
		)
		part.material = .Glass
		ship_append_local_box_faces(
			faces,
			part,
			{gx * .15, hand * (sy + gy * .62), sz * .7},
			{gx * .18, gy * .08, gz * .16},
			base + 8,
			camera,
			center,
			scale,
		)
	case .Work_Light:
		ship_append_local_box_faces(
			faces,
			part,
			{0, hand * (sy + gy * .24), sz * .72},
			{gx * .34, gy * .24, gz * .52},
			base,
			camera,
			center,
			scale,
		)
		part.material = .Glass
		ship_append_local_box_faces(
			faces,
			part,
			{0, hand * (sy + gy * .52), sz * .82},
			{gx * .24, gy * .12, gz * .3},
			base + 8,
			camera,
			center,
			scale,
		)
	case .Docking_Cleat:
		part.material = .Truss
		ship_append_local_box_faces(
			faces,
			part,
			{0, hand * (sy + gy * .5), sz * .38},
			{gx * .25, gy * .5, gz * .72},
			base,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			part,
			{0, hand * (sy + gy * .92), sz * .38},
			{gx, gy * .16, gz * .2},
			base + 8,
			camera,
			center,
			scale,
		)
	case .Pipe_Bridge:
		for pipe in 0 ..< 2 do ship_append_local_box_faces(faces, part, {0, hand * (sy + gy * (.28 + f32(pipe) * .38)), sz * .45}, {gx * 1.45, gy * .12, gz * .14}, base + u32(pipe * 8), camera, center, scale)
		ship_append_local_box_faces(
			faces,
			part,
			{gx * 1.2, hand * (sy + gy * .47), sz * .62},
			{gx * .14, gy * .32, gz * .32},
			base + 16,
			camera,
			center,
			scale,
		)
	case .Micrometeor_Shield:
		part.material = .Armor
		ship_append_local_box_faces(
			faces,
			part,
			{gx * .18, hand * (sy + gy * .48), sz * .55},
			{gx * 1.42, gy * .16, gz},
			base,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			part,
			{-gx * .92, hand * (sy + gy * .25), sz * .55},
			{gx * .12, gy * .32, gz * .7},
			base + 8,
			camera,
			center,
			scale,
		)
	}
}

ship_append_greebly_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	if module.module == .Truss do return // Preserve the negative space of open frames.
	ship_append_greebly_kind_faces(
		faces,
		module,
		ship_greebly_for_module(module),
		camera,
		center,
		scale,
	)
}

ship_greebly_slot_count :: proc(module: game.Procedural_Ship_Placement, density: int) -> int {
	if density <= 0 || module.module == .Truss do return 0
	hash := game.ship_construction_visual_mix(
		u64(module.surface_id) ~ u64(module.id) * 0x9e3779b97f4a7c15,
	)
	thresholds := [5]u64{0, 24, 48, 72, 92}
	level := clamp(density, 0, 4)
	if hash % 100 >= thresholds[level] do return 0
	if level <= 2 || module.module == .Antenna || module.module == .Drive do return 1
	if level == 3 do return 1 + int((hash >> 16) % 4 == 0)
	return 2 + int((hash >> 16) & 1)
}

ship_append_auto_greeblies :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	density, max_count: int,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) -> int {
	count := min(ship_greebly_slot_count(module, density), max_count)
	if count <= 0 do return 0
	axis, _, _ := ship_module_basis(module)
	for slot in 0 ..< count {
		decorated := module
		decorated.id ~= u32((slot + 1) * 0x45d9f3b)
		decorated.surface_id ~= u32((slot + 1) * 0x9e3779b9)
		lane := (f32(slot) - f32(count - 1) * .5) * min(module.scale[0] * .62, f32(.42))
		for coordinate in 0 ..< 3 do decorated.position[coordinate] += axis[coordinate] * lane
		ship_append_greebly_kind_faces(
			faces,
			decorated,
			ship_greebly_for_module(decorated),
			camera,
			center,
			scale,
		)
	}
	return count
}

ship_append_closed_hull_auto_greeblies :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	density, max_count: int,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) -> int {
	if !ship_architecture_has_closed_hull(r.architecture) || density <= 0 || max_count <= 0 {
		return 0
	}
	placed := 0
	host_modules := [4]game.Procedural_Ship_Module{.Armor, .Pressure_Hull, .Mission, .Armor}
	for slot in 0 ..< 4 {
		host_mix := game.ship_construction_visual_mix(
			r.seed ~ u64(slot + 1) * 0x9e3779b97f4a7c15 ~ u64(r.architecture) * 0xbf58476d1ce4e5b9,
		)
		host := game.Procedural_Ship_Placement {
			id         = 0xe1000000 | (u32(host_mix) & 0x00fffff0) | u32(slot),
			surface_id = 0xe2000000 | (u32(host_mix >> 32) &
					0x00ffff00) | u32(r.architecture) * 0x10 | u32(slot),
			module     = host_modules[slot],
			material   = .Hull_Plate,
			direction  = {1, 0, 0},
		}
		side: f32 = 1
		if game.ship_construction_visual_mix(r.seed ~ u64(slot) * 0x9e3779b97f4a7c15) & 1 == 0 {
			side = -1
		}
		switch r.architecture {
		case .Single_Hull:
			hx, hy, hz := ship_single_hull_half_extents(r)
			if slot < 2 {
				host.position = {hx * (-.32 + f32(slot) * .18), side * hy * .10, hz * 1.12}
			} else {
				host.position = {hx * (.09 + f32(slot - 2) * .15), side * hy * .08, hz * 1.05}
			}
			host.scale = {hx * .07, hy * .10, hz * .025}
			host.position[2] -= host.scale[2]
		case .Saucer, .Delta:
			sx, sy, sz := ship_delta_half_extents(r)
			x := sx * (-.42 + f32(slot) * .23)
			beam, _, _ := ship_delta_section_at_x(r.seed, sx, sy, sz, x, r.family)
			y := side * beam * (.34 + f32(slot % 2) * .12)
			top := ship_delta_surface_z(r.seed, sx, sy, sz, x, y, true, r.family)
			host.position = {x, y, top}
			host.scale = {sx * .045, sy * .055, sz * .035}
			host.position[2] -= host.scale[2]
		case .Modular_Frame:
		}
		placed += ship_append_auto_greeblies(
			faces,
			host,
			density,
			max_count - placed,
			camera,
			center,
			scale,
		)
		if placed >= max_count do break
	}
	return placed
}

ship_keel_subassembly_count :: proc(family: game.Procedural_Ship_Family) -> int {
	switch family {case .Strike:
		return 1; case .Fleet:
		return 4; case .Habitat:
		return 4}
	return 1
}

ship_append_keel_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	family: game.Procedural_Ship_Family,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// Keel stations are family-specific manufactured subassemblies, not beads on
	// a wire. Every added volume remains orthogonal and separated by a reveal so
	// the axial silhouette gains mass without returning to rounded hull caps.
	sx, sy, sz := module.scale[0], module.scale[1], module.scale[2]
	ship_append_local_box_faces(faces, module, {0, 0, 0}, {sx, sy, sz}, 0, camera, center, scale)
	switch family {
	case .Strike:
		return
	case .Fleet:
		armor := module; armor.material = .Armor
		ship_append_local_box_faces(
			faces,
			armor,
			{0, -sy * 1.38, -sz * .08},
			{sx * .82, sy * .30, sz * .68},
			8,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			armor,
			{0, sy * 1.38, -sz * .08},
			{sx * .82, sy * .30, sz * .68},
			16,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			armor,
			{0, 0, sz * 1.30},
			{sx * .62, sy * .58, sz * .18},
			24,
			camera,
			center,
			scale,
		)
	case .Habitat:
		service := module; service.material = .Machinery
		ship_append_local_box_faces(
			faces,
			service,
			{0, -sy * 1.20, -sz * .16},
			{sx * .86, sy * .15, sz * .22},
			8,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			service,
			{0, sy * 1.20, -sz * .16},
			{sx * .86, sy * .15, sz * .22},
			16,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			service,
			{0, 0, sz * 1.25},
			{sx * .56, sy * .52, sz * .17},
			24,
			camera,
			center,
			scale,
		)
	}
}

ship_keel_bridge_enabled :: proc(r: ^game.Procedural_Ship_Recipe, station: int) -> bool {
	if station <= 0 || station >= r.frame.station_count || r.family == .Strike do return false
	mid := (r.modules[station - 1].position[0] + r.modules[station].position[0]) * .5
	half_length := max(r.frame.keel_length * .5, f32(.001))
	if r.family == .Fleet do return math.abs(mid / half_length) < .58
	// Habitat service trunks stop outside the ring districts, preserving long
	// exposed keel runs between inhabited neighborhoods.
	for module in r.modules[:r.module_count] do if module.module == .Ring_Segment && math.abs(mid - module.position[0]) < 2.25 do return true
	return false
}

ship_append_keel_bridge_core_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	family: game.Procedural_Ship_Family,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// Capital armor uses a broad chamfered octagon; civilian service trunks use
	// a simpler hexagonal extrusion. These are clipped structural sections, not
	// radial pressure vessels, so their long planar faces remain dominant.
	sy, sz := module.scale[1], module.scale[2]
	section: [8][2]f32; count := 8
	if family == .Fleet {
		section = {
			{-sy, -sz * .58},
			{-sy * .58, -sz},
			{sy * .58, -sz},
			{sy, -sz * .58},
			{sy, sz * .58},
			{sy * .58, sz},
			{-sy * .58, sz},
			{-sy, sz * .58},
		}
	} else {
		count = 6; section = {{-sy, 0}, {-sy * .5, -sz}, {sy * .5, -sz}, {sy, 0}, {sy * .5, sz}, {-sy * .5, sz}, {0, 0}, {0, 0}}
	}
	rear_center := ship_module_local_point(
		module,
		{-module.scale[0], 0, 0},
	); front_center := ship_module_local_point(module, {module.scale[0], 0, 0})
	for segment in 0 ..< count {
		next := (segment + 1) % count
		r0 := ship_module_local_point(
			module,
			{-module.scale[0], section[segment][0], section[segment][1]},
		); r1 := ship_module_local_point(module, {-module.scale[0], section[next][0], section[next][1]})
		f0 := ship_module_local_point(
			module,
			{module.scale[0], section[segment][0], section[segment][1]},
		); f1 := ship_module_local_point(module, {module.scale[0], section[next][0], section[next][1]})
		ny :=
			(section[segment][0] + section[next][0]) *
			.5 /
			max(
				sy,
				f32(.001),
			); nz := (section[segment][1] + section[next][1]) * .5 / max(sz, f32(.001)); length := f32(math.sqrt(f64(ny * ny + nz * nz))); if length > .001 {ny /= length; nz /= length}
		ship_append_face(
			faces,
			{r0, f0, f1, r1},
			ship_module_local_normal(module, {0, ny, nz}),
			module,
			module.surface_id + u32(segment),
			camera,
			center,
			scale,
		)
		ship_append_face(
			faces,
			{rear_center, r1, r0, rear_center},
			ship_module_local_normal(module, {-1, 0, 0}),
			module,
			module.surface_id + u32(count + segment * 2),
			camera,
			center,
			scale,
		)
		ship_append_face(
			faces,
			{front_center, f0, f1, front_center},
			ship_module_local_normal(module, {1, 0, 0}),
			module,
			module.surface_id + u32(count + segment * 2 + 1),
			camera,
			center,
			scale,
		)
	}
}

ship_append_keel_bridge_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	station: int,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	if !ship_keel_bridge_enabled(r, station) do return
	a, b := r.modules[station - 1], r.modules[station]
	bridge :=
		a; bridge.position = {(a.position[0] + b.position[0]) * .5, (a.position[1] + b.position[1]) * .5, (a.position[2] + b.position[2]) * .5}; bridge.direction = {1, 0, 0}
	distance := math.abs(
		b.position[0] - a.position[0],
	); sy := min(a.scale[1], b.scale[1]); sz := min(a.scale[2], b.scale[2])
	bridge.scale = {
		distance * .54,
		sy * (r.family == .Fleet ? .72 : .48),
		sz * (r.family == .Fleet ? .66 : .42),
	}
	bridge.material = r.family == .Fleet ? .Armor : .Machinery
	bridge.surface_id = 0x70000000 + u32(station) * 64 + u32(r.family) * 4096
	// The narrow outer courses leave a visible seam at each fabrication bay.
	ship_append_keel_bridge_core_faces(faces, bridge, r.family, camera, center, scale)
	shoulder := bridge.scale
	shoulder[0] *= .86; shoulder[1] *= 1.22; shoulder[2] *= .28
	ship_append_local_box_faces(
		faces,
		bridge,
		{0, 0, bridge.scale[2] * .86},
		shoulder,
		8,
		camera,
		center,
		scale,
	)
	if r.family == .Fleet {
		cheek := bridge.scale; cheek[0] *= .9; cheek[1] *= .24; cheek[2] *= .78
		ship_append_local_box_faces(
			faces,
			bridge,
			{0, -bridge.scale[1] * .92, 0},
			cheek,
			16,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			bridge,
			{0, bridge.scale[1] * .92, 0},
			cheek,
			24,
			camera,
			center,
			scale,
		)
	}
}

ship_append_weapon_nose_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	length, radius_scale: f32,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	base_x := module.scale[0] * .96
	tip := ship_module_local_point(module, {module.scale[0] + length, 0, 0})
	base := [4][3]f32 {
		ship_module_local_point(module, {base_x, module.scale[1] * radius_scale, 0}),
		ship_module_local_point(module, {base_x, 0, module.scale[2] * radius_scale}),
		ship_module_local_point(module, {base_x, -module.scale[1] * radius_scale, 0}),
		ship_module_local_point(module, {base_x, 0, -module.scale[2] * radius_scale}),
	}
	normals := [4][3]f32{{1, 1, 1}, {1, -1, 1}, {1, -1, -1}, {1, 1, -1}}
	for face_index in 0 ..< 4 {
		next := (face_index + 1) % 4
		ship_append_face(
			faces,
			{base[face_index], tip, tip, base[next]},
			ship_module_local_normal(module, normals[face_index]),
			module,
			module.surface_id + 0x18 + u32(face_index),
			camera,
			center,
			scale,
		)
	}
}

ship_append_weapon_engine_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	length, exit_radius_scale: f32,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// Weapon rounds travel toward local +X. Their motor bell therefore opens
	// toward local -X, behind the control fins. A flared exit makes propulsion
	// direction readable even when the cylindrical store itself is symmetric.
	throat_x := -module.scale[0] * .96
	exit_x := -module.scale[0] - length
	throat_radius := exit_radius_scale * .52
	throat := [4][3]f32 {
		ship_module_local_point(module, {throat_x, module.scale[1] * throat_radius, 0}),
		ship_module_local_point(module, {throat_x, 0, module.scale[2] * throat_radius}),
		ship_module_local_point(module, {throat_x, -module.scale[1] * throat_radius, 0}),
		ship_module_local_point(module, {throat_x, 0, -module.scale[2] * throat_radius}),
	}
	exit_ring := [4][3]f32 {
		ship_module_local_point(module, {exit_x, module.scale[1] * exit_radius_scale, 0}),
		ship_module_local_point(module, {exit_x, 0, module.scale[2] * exit_radius_scale}),
		ship_module_local_point(module, {exit_x, -module.scale[1] * exit_radius_scale, 0}),
		ship_module_local_point(module, {exit_x, 0, -module.scale[2] * exit_radius_scale}),
	}
	normals := [4][3]f32{{-1, 1, 1}, {-1, -1, 1}, {-1, -1, -1}, {-1, 1, -1}}
	for face_index in 0 ..< 4 {
		next := (face_index + 1) % 4
		ship_append_face(
			faces,
			{throat[face_index], exit_ring[face_index], exit_ring[next], throat[next]},
			ship_module_local_normal(module, normals[face_index]),
			module,
			module.surface_id + 0x60 + u32(face_index),
			camera,
			center,
			scale,
		)
	}
	// Close the exit with the Drive material's near-black tone, creating a
	// recessed exhaust aperture instead of another bright pointed cap.
	ship_append_face(
		faces,
		{exit_ring[0], exit_ring[1], exit_ring[2], exit_ring[3]},
		ship_module_local_normal(module, {-1, 0, 0}),
		module,
		module.surface_id + 0x68,
		camera,
		center,
		scale,
	)
}

ship_append_strike_prow_bridle_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	if r.architecture != .Modular_Frame || r.family != .Strike do return
	// Two narrow armor rails converge on the bow socket. They give even a sparse
	// strike recipe an unmistakable axial weapon-craft silhouette while retaining
	// open negative space and leaving the individual payload layout asymmetric.
	half_length := r.frame.keel_length * .5
	root_x, tip_x := -half_length * .08, half_length * .91
	root_y, tip_y := r.frame.beam * .31, r.frame.beam * .055
	half_width := max(r.frame.beam * .026, f32(.035))
	half_height := max(r.frame.height * .045, f32(.025))
	z := r.frame.height * .08
	module := game.Procedural_Ship_Placement {
		id         = 0xe3000000,
		surface_id = 0xe3000000,
		module     = .Armor,
		material   = .Armor,
		direction  = {1, 0, 0},
	}
	for side_index in 0 ..< 2 {
		side: f32 = side_index == 0 ? -1 : 1
		root := [2]f32{root_x, side * root_y}
		tip := [2]f32{tip_x, side * tip_y}
		dx, dy := tip[0] - root[0], tip[1] - root[1]
		length := max(f32(math.sqrt(f64(dx * dx + dy * dy))), f32(.001))
		dir := [2]f32{dx / length, dy / length}
		normal := [2]f32{-dir[1], dir[0]}
		v := [8][3]f32 {
			{root[0] - normal[0] * half_width, root[1] - normal[1] * half_width, z - half_height},
			{tip[0] - normal[0] * half_width, tip[1] - normal[1] * half_width, z - half_height},
			{tip[0] + normal[0] * half_width, tip[1] + normal[1] * half_width, z - half_height},
			{root[0] + normal[0] * half_width, root[1] + normal[1] * half_width, z - half_height},
			{root[0] - normal[0] * half_width, root[1] - normal[1] * half_width, z + half_height},
			{tip[0] - normal[0] * half_width, tip[1] - normal[1] * half_width, z + half_height},
			{tip[0] + normal[0] * half_width, tip[1] + normal[1] * half_width, z + half_height},
			{root[0] + normal[0] * half_width, root[1] + normal[1] * half_width, z + half_height},
		}
		indices := [6][4]int {
			{0, 3, 2, 1},
			{4, 5, 6, 7},
			{0, 1, 5, 4},
			{3, 7, 6, 2},
			{0, 4, 7, 3},
			{1, 2, 6, 5},
		}
		normals := [6][3]f32 {
			{0, 0, -1},
			{0, 0, 1},
			{-normal[0], -normal[1], 0},
			{normal[0], normal[1], 0},
			{-dir[0], -dir[1], 0},
			{dir[0], dir[1], 0},
		}
		for face_index in 0 ..< 6 {
			quad: [4][3]f32
			for corner in 0 ..< 4 do quad[corner] = v[indices[face_index][corner]]
			ship_append_face(
				faces,
				quad,
				normals[face_index],
				module,
				module.surface_id + u32(side_index * 8 + face_index),
				camera,
				center,
				scale,
			)
		}
	}
	// The cradle exists to carry a centerline weapon, not as decorative wings.
	// Its long breech-to-muzzle machinery shares the drive axis, so firing recoil
	// and thrust loads close through the same primary structure.
	gun := module
	gun.surface_id = 0xe3000100
	gun.material = .Machinery
	// The graph optimizer places the weapon system; the renderer turns that
	// functional station into a continuous breech-to-muzzle load path.
	weapon_x := half_length * .72
	if weapon_index := game.procedural_ship_system_find(&r.systems, .Weapon); weapon_index >= 0 {
		weapon_x = r.systems.nodes[weapon_index].position[0]
	}
	breech_x := weapon_x - half_length * .28
	muzzle_x := half_length * .98
	weapon_scale := r.weapon_capability_scale
	if weapon_scale <= 0 do weapon_scale = 1
	caliber := clamp(weapon_scale, f32(.72), f32(1.32))
	if r.weapon_package == .Guided_Missiles {
		// Four narrow launch coffins share the prow cradle. Open lanes between
		// them preserve the individual rounds at contact-sheet scale.
		for row in 0 ..< 2 do for side_index in 0 ..< 2 {
			side: f32 = side_index == 0 ? -1 : 1
			cell_x := breech_x + half_length * (.16 + f32(row) * .25)
			gun.position = {cell_x, side * r.frame.beam * .075, z + (f32(row) - .5) * r.frame.height * .09}
			gun.scale = {half_length * .105, max(r.frame.beam * .025 * caliber, f32(.032)), max(r.frame.height * .038 * caliber, f32(.026))}
			gun.surface_id = 0xe3000200 + u32(row * 0x40 + side_index * 0x20)
			ship_append_tank_faces(faces, gun, camera, center, scale)
			gun.material = .Drive
			ship_append_weapon_engine_faces(faces, gun, gun.scale[0] * .22, 1.08, camera, center, scale)
			gun.material = .Armor
			ship_append_weapon_nose_faces(faces, gun, gun.scale[0] * .42, .82, camera, center, scale)
			for fin_side_index in 0 ..< 2 {
				fin_side: f32 = fin_side_index == 0 ? -1 : 1
				ship_append_local_box_faces(faces, gun, {-gun.scale[0] * .72, fin_side * gun.scale[1] * 1.22, 0}, {gun.scale[0] * .18, gun.scale[1] * .72, gun.scale[2] * .12}, u32(0x30 + fin_side_index * 8), camera, center, scale)
			}
			gun.material = .Machinery
		}
		return
	}
	if r.weapon_package == .Heavy_Torpedoes {
		// Torpedoes are ship-scale stores: two long armored cradles with broad
		// restraint bands, visibly heavier than the missile launch coffins.
		for side_index in 0 ..< 2 {
			side: f32 = side_index == 0 ? -1 : 1
			gun.position = {(breech_x + muzzle_x) * .5, side * r.frame.beam * .085, z}
			gun.scale = {
				(muzzle_x - breech_x) * .43,
				max(r.frame.beam * .043 * caliber, f32(.052)),
				max(r.frame.height * .058 * caliber, f32(.04)),
			}
			gun.surface_id = 0xe3000400 + u32(side_index * 0x40)
			ship_append_tank_faces(faces, gun, camera, center, scale)
			gun.material = .Drive
			ship_append_weapon_engine_faces(faces, gun, gun.scale[0] * .14, .86, camera, center, scale)
			gun.material = .Armor
			ship_append_weapon_nose_faces(
				faces,
				gun,
				gun.scale[0] * .18,
				.96,
				camera,
				center,
				scale,
			)
			gun.material = .Machinery
			ship_append_local_box_faces(
				faces,
				gun,
				{-gun.scale[0] * .88, 0, 0},
				{gun.scale[0] * .08, gun.scale[1] * 1.2, gun.scale[2] * 1.2},
				0x38,
				camera,
				center,
				scale,
			)
		}
		return
	}
	breech_length := half_length * (.18 + .04 * caliber)
	breech_center := breech_x + breech_length * .5
	barrel_root := breech_x + breech_length * .82
	barrel_end := muzzle_x
	if r.weapon_package == .Chemical_Autocannon do barrel_end = barrel_root + (muzzle_x - barrel_root) * .72
	if r.weapon_package == .Defensive_Laser do barrel_end = barrel_root + (muzzle_x - barrel_root) * .58
	gun.position = {(breech_x + muzzle_x) * .5, 0, z}
	gun.scale = {
		(barrel_end - barrel_root) * .5,
		max(r.frame.beam * .018 * caliber, f32(.028)),
		max(r.frame.height * .029 * caliber, f32(.022)),
	}
	gun.position[0] = (barrel_root + barrel_end) * .5
	barrel_count := r.weapon_package == .Chemical_Autocannon ? 2 : 1
	for barrel_index in 0 ..< barrel_count {
		barrel_side: f32 = barrel_count == 1 ? 0 : (barrel_index == 0 ? -1 : 1)
		ship_append_local_box_faces(
			faces,
			gun,
			{0, barrel_side * gun.scale[1] * 1.45, 0},
			gun.scale,
			u32(barrel_index * 8),
			camera,
			center,
			scale,
		)
	}
	// The common armored breech closes recoil and thermal loads into the prow
	// cradle; package-specific barrels and emitters remain visibly replaceable.
	gun.material = .Armor
	ship_append_local_box_faces(
		faces,
		gun,
		{breech_center - gun.position[0], 0, 0},
		{
			breech_length * .5,
			max(r.frame.beam * .058 * caliber, f32(.06)),
			max(r.frame.height * .085 * caliber, f32(.05)),
		},
		16,
		camera,
		center,
		scale,
	)
	gun.material = .Machinery
	collar_count := 2
	switch r.weapon_package {
	case .Chemical_Autocannon, .Defensive_Laser:
		collar_count = 1
	case .Coilgun_Battery:
		collar_count = 4
	case .Offensive_Laser:
		collar_count = 3
	case .Railgun_Battery, .Unspecified:
		collar_count = 2
	case .Guided_Missiles, .Heavy_Torpedoes:
	}
	for collar_index in 0 ..< collar_count {
		collar_t := f32(collar_index + 1) / f32(collar_count + 1)
		collar_x := barrel_root + (barrel_end - barrel_root) * collar_t
		ship_append_local_box_faces(
			faces,
			gun,
			{collar_x - gun.position[0], 0, 0},
			{
				half_length * .018,
				max(r.frame.beam * .044 * caliber, f32(.04)),
				max(r.frame.height * .055 * caliber, f32(.032)),
			},
			u32(24 + collar_index * 8),
			camera,
			center,
			scale,
		)
	}
	if r.weapon_package == .Railgun_Battery || r.weapon_package == .Unspecified {
		gun.material = .Armor
		for side_index in 0 ..< 2 {
			side: f32 = side_index == 0 ? -1 : 1
			ship_append_local_box_faces(
				faces,
				gun,
				{barrel_end - gun.position[0] - half_length * .035, side * gun.scale[1] * 1.75, 0},
				{half_length * .045, gun.scale[1] * .48, gun.scale[2] * 1.22},
				u32(48 + side_index * 8),
				camera,
				center,
				scale,
			)
		}
	}
	if r.weapon_package == .Defensive_Laser || r.weapon_package == .Offensive_Laser {
		emitter := gun
		emitter.material = .Glass
		ship_append_weapon_nose_faces(
			faces,
			emitter,
			gun.scale[0] * (r.weapon_package == .Offensive_Laser ? f32(.34) : f32(.22)),
			1.5,
			camera,
			center,
			scale,
		)
	}
	if r.weapon_package == .Chemical_Autocannon {
		gun.material = .Machinery
		ship_append_local_box_faces(
			faces,
			gun,
			{breech_center - gun.position[0] - breech_length * .18, gun.scale[1] * 3.2, 0},
			{breech_length * .2, gun.scale[1] * 1.7, gun.scale[2] * 1.6},
			0x58,
			camera,
			center,
			scale,
		)
	}
}

ship_append_modular_fleet_weapon_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	if r.architecture != .Modular_Frame || r.family != .Fleet do return
	half_length := r.frame.keel_length * .5
	beam := r.frame.beam
	height := r.frame.height
	weapon_scale := r.weapon_capability_scale
	if weapon_scale <= 0 do weapon_scale = 1
	for side_index in 0 ..< 2 {
		side: f32 = side_index == 0 ? -1 : 1
		x := half_length * .22
		y := side * beam * .37
		z := height * .1
		mount := game.Procedural_Ship_Placement {
			id         = 0xe5000000 + u32(side_index) * 0x100,
			surface_id = 0xe5000000 + u32(side_index) * 0x100,
			module     = .Armor,
			material   = .Armor,
			position   = {x, y, z},
			direction  = {1, 0, 0},
			scale      = {half_length * .075, beam * .075, height * .11},
		}
		// A transverse recoil bridge closes the battery load path into the axial
		// frame and remains visible between the open truss and weapon housing.
		ship_append_local_box_faces(
			faces,
			mount,
			{-mount.scale[0] * .3, -side * beam * .16, -height * .08},
			{half_length * .055, beam * .18, height * .035},
			0x08,
			camera,
			center,
			scale,
		)
		if r.weapon_package == .Guided_Missiles {
			for store_index in 0 ..< 2 {
				store := mount
				store.position[0] += half_length * (-.08 + f32(store_index) * .25)
				store.position[1] += side * beam * .045
				store.scale = {
					half_length * .13 * weapon_scale,
					beam * .032 * weapon_scale,
					height * .055 * weapon_scale,
				}
				store.material = .Machinery
				store.surface_id += 0x20 + u32(store_index) * 0x40
				ship_append_local_box_faces(
					faces,
					store,
					{-store.scale[0] * .15, 0, -store.scale[2] * 1.25},
					{store.scale[0] * .82, store.scale[1] * .7, store.scale[2] * .16},
					0x08,
					camera,
					center,
					scale,
				)
				ship_append_tank_faces(faces, store, camera, center, scale)
				store.material = .Drive
				ship_append_weapon_engine_faces(
					faces,
					store,
					store.scale[0] * .22,
					1.08,
					camera,
					center,
					scale,
				)
				store.material = .Armor
				ship_append_weapon_nose_faces(faces, store, store.scale[0] * .42, .82, camera, center, scale)
				store.material = .Machinery
				for fin_index in 0 ..< 2 {
					fin_side: f32 = fin_index == 0 ? -1 : 1
					ship_append_local_box_faces(
						faces,
						store,
						{-store.scale[0] * .7, fin_side * store.scale[1] * 1.2, 0},
						{store.scale[0] * .17, store.scale[1] * .68, store.scale[2] * .13},
						u32(0x30 + fin_index * 8),
						camera,
						center,
						scale,
					)
				}
			}
			continue
		}
		if r.weapon_package == .Heavy_Torpedoes {
			store := mount
			store.position[0] += half_length * .04
			store.position[1] += side * beam * .04
			store.scale = {
				half_length * .31 * weapon_scale,
				beam * .052 * weapon_scale,
				height * .082 * weapon_scale,
			}
			store.material = .Machinery
			store.surface_id += 0xa0
			for rail_index in 0 ..< 2 {
				rail_side: f32 = rail_index == 0 ? -1 : 1
				ship_append_local_box_faces(
					faces,
					store,
					{-store.scale[0] * .12, rail_side * store.scale[1] * .72, -store.scale[2] * 1.22},
					{store.scale[0] * .9, store.scale[1] * .13, store.scale[2] * .18},
					u32(0x08 + rail_index * 8),
					camera,
					center,
					scale,
				)
			}
			ship_append_tank_faces(faces, store, camera, center, scale)
			store.material = .Drive
			ship_append_weapon_engine_faces(
				faces,
				store,
				store.scale[0] * .14,
				.86,
				camera,
				center,
				scale,
			)
			store.material = .Armor
			ship_append_weapon_nose_faces(faces, store, store.scale[0] * .18, .96, camera, center, scale)
			store.material = .Machinery
			for band_index in 0 ..< 2 {
				band_x := band_index == 0 ? f32(-.72) : f32(.38)
				ship_append_local_box_faces(
					faces,
					store,
					{store.scale[0] * band_x, 0, 0},
					{store.scale[0] * .055, store.scale[1] * 1.16, store.scale[2] * 1.16},
					u32(0x38 + band_index * 0x10),
					camera,
					center,
					scale,
				)
			}
			continue
		}
		ship_append_local_box_faces(faces, mount, {}, mount.scale, 0x18, camera, center, scale)
		barrel := mount
		barrel.position[0] += half_length * .19
		barrel.scale = {
			half_length * (r.weapon_package == .Defensive_Laser ? f32(.09) : f32(.16)),
			beam * .018,
			height * .03,
		}
		barrel.material = .Machinery
		barrel_count := r.weapon_package == .Chemical_Autocannon ? 2 : 1
		for barrel_index in 0 ..< barrel_count {
			barrel_side: f32 = barrel_count == 1 ? 0 : (barrel_index == 0 ? -1 : 1)
			ship_append_local_box_faces(
				faces,
				barrel,
				{0, barrel_side * beam * .025, 0},
				barrel.scale,
				u32(0x20 + barrel_index * 8),
				camera,
				center,
				scale,
			)
		}
		collar_count := 0
		switch r.weapon_package {
		case .Chemical_Autocannon, .Defensive_Laser:
			collar_count = 1
		case .Coilgun_Battery:
			collar_count = 4
		case .Railgun_Battery:
			collar_count = 2
		case .Offensive_Laser:
			collar_count = 3
		case .Unspecified, .Guided_Missiles, .Heavy_Torpedoes:
		}
		for collar_index in 0 ..< collar_count {
			t := f32(collar_index + 1) / f32(collar_count + 1)
			ship_append_local_box_faces(
				faces,
				barrel,
				{-barrel.scale[0] + barrel.scale[0] * 2 * t, 0, 0},
				{barrel.scale[0] * .08, beam * .035, height * .06},
				u32(0x40 + collar_index * 8),
				camera,
				center,
				scale,
			)
		}
		if r.weapon_package == .Coilgun_Battery {
			// Coilguns carry their pulsed field hardware around the barrel. The
			// paired capacitor drums are deliberately broad in plan view: they make
			// an induction weapon read as a contained machine, not a slender rail.
			for drum_index in 0 ..< 2 {
				drum_side: f32 = drum_index == 0 ? -1 : 1
				ship_append_local_box_faces(
					faces,
					barrel,
					{-barrel.scale[0] * .18, drum_side * beam * .075, height * .012},
					{barrel.scale[0] * .22, beam * .045, height * .078},
					0x70 + u32(drum_index * 8),
					camera,
					center,
					scale,
				)
			}
		}
		if r.weapon_package == .Railgun_Battery {
			// Unlike a coilgun's contained field rings, railgun conductors remain
			// visibly open along both sides of the projectile path. Extend the
			// paired rails from breech to muzzle so their architecture survives
			// contact-sheet scale and explains the forward forks below.
			for rail_index in 0 ..< 2 {
				rail_side: f32 = rail_index == 0 ? -1 : 1
				ship_append_local_box_faces(
					faces,
					barrel,
					{barrel.scale[0] * .04, rail_side * beam * .048, height * .012},
					{barrel.scale[0] * 1.05, beam * .012, height * .022},
					0x80 + u32(rail_index * 8),
					camera,
					center,
					scale,
				)
			}
			for fork_index in 0 ..< 2 {
				fork_side: f32 = fork_index == 0 ? -1 : 1
				ship_append_local_box_faces(
					faces,
					barrel,
					{barrel.scale[0] * .92, fork_side * beam * .035, 0},
					{barrel.scale[0] * .18, beam * .012, height * .042},
					u32(0x70 + fork_index * 8),
					camera,
					center,
					scale,
				)
			}
		}
		if r.weapon_package == .Defensive_Laser {
			// Point defense belongs close to its tracking hardware. A raised
			// heat-sink / sensor collar makes this a compact traversing turret,
			// rather than a reduced version of the main-beam installation.
			ship_append_local_box_faces(
				faces,
				mount,
				{-mount.scale[0] * .12, 0, height * .12},
				{mount.scale[0] * .42, beam * .048, height * .055},
				0x90,
				camera,
				center,
				scale,
			)
		}
		if r.weapon_package == .Offensive_Laser {
			// A primary laser needs substantial, visibly separate feed trunks.
			// Keep them low and parallel to the barrel so the open frame still
			// reads first, while the weapon claims a longer powered load path.
			for feed_index in 0 ..< 2 {
				feed_side: f32 = feed_index == 0 ? -1 : 1
				ship_append_local_box_faces(
					faces,
					barrel,
					{-barrel.scale[0] * .18, feed_side * beam * .068, -height * .045},
					{barrel.scale[0] * .94, beam * .018, height * .038},
					0x90 + u32(feed_index * 8),
					camera,
					center,
					scale,
				)
			}
		}
		if r.weapon_package == .Defensive_Laser || r.weapon_package == .Offensive_Laser {
			emitter := barrel
			emitter.material = .Glass
			ship_append_weapon_nose_faces(
				faces,
				emitter,
				barrel.scale[0] * (r.weapon_package == .Offensive_Laser ? f32(.34) : f32(.22)),
				1.5,
				camera,
				center,
				scale,
			)
		}
		if r.weapon_package == .Chemical_Autocannon {
			// The twin barrels share a broad, replaceable ammunition cassette at
			// the breech. It gives the short-range gun a physical supply path and
			// makes it distinct from the otherwise similarly sized laser turret.
			ship_append_local_box_faces(
				faces,
				barrel,
				{-barrel.scale[0] * .56, 0, -height * .055},
				{barrel.scale[0] * .30, beam * .082, height * .062},
				0xa0,
				camera,
				center,
				scale,
			)
			ship_append_local_box_faces(
				faces,
				mount,
				{-mount.scale[0] * .25, side * beam * .1, 0},
				{half_length * .045, beam * .05, height * .07},
				0xb0,
				camera,
				center,
				scale,
			)
		}
	}
}
