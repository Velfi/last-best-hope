package main

import game "../packages/game"
import "core:c"
import "core:fmt"
import "core:math"
import "core:testing"
import stbi "vendor:stb/image"
import rl "zelda_engine:canvas2d"
ship_append_local_box_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	local_center, half_scale: [3]f32,
	surface_offset: u32,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	sx, sy, sz :=
		half_scale[0],
		half_scale[1],
		half_scale[2]; cx, cy, cz := local_center[0], local_center[1], local_center[2]
	vertices := [8][3]f32 {
		{cx - sx, cy - sy, cz - sz},
		{cx + sx, cy - sy, cz - sz},
		{cx + sx, cy + sy, cz - sz},
		{cx - sx, cy + sy, cz - sz},
		{cx - sx, cy - sy, cz + sz},
		{cx + sx, cy - sy, cz + sz},
		{cx + sx, cy + sy, cz + sz},
		{cx - sx, cy + sy, cz + sz},
	}
	indices := [6][4]int {
		{0, 1, 2, 3},
		{4, 7, 6, 5},
		{0, 4, 5, 1},
		{3, 2, 6, 7},
		{0, 3, 7, 4},
		{1, 5, 6, 2},
	}
	normals := [6][3]f32{{0, 0, -1}, {0, 0, 1}, {0, -1, 0}, {0, 1, 0}, {-1, 0, 0}, {1, 0, 0}}
	for &v in vertices do v = ship_module_local_point(module, v)
	for face_index in 0 ..< 6 {
		world: [4][3]f32
		for corner in 0 ..< 4 do world[corner] = vertices[indices[face_index][corner]]
		ship_append_face(
			faces,
			world,
			ship_module_local_normal(module, normals[face_index]),
			module,
			module.surface_id + surface_offset + u32(face_index),
			camera,
			center,
			scale,
		)
	}
}

ship_append_box_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	if module.module == .Ring_Segment do return
	half_scale := module.scale; if module.module == .Drive do half_scale[0] *= 1.18
	ship_append_local_box_faces(faces, module, {0, 0, 0}, half_scale, 0, camera, center, scale)
}

ship_append_service_mark_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	if module.service_mark == .None do return
	sx, sy, sz := module.scale[0], module.scale[1], module.scale[2]
	hand: f32 = module.surface_id & 1 == 0 ? -1 : 1
	patch := module; patch.material = .Armor
	// Every mark occupies one seeded side of one existing module. Patch plates
	// overlap like field-cut shingles; a breach gets an external rib cage; Dark
	// exposure grows a sparse offset comb rather than a generic organic blob.
	ship_append_local_box_faces(
		faces,
		patch,
		{-sx * .16, hand * sy * .34, sz * 1.035},
		{sx * .48, sy * .42, max(sz * .045, f32(.035))},
		128,
		camera,
		center,
		scale,
	)
	switch module.service_mark {
	case .Patch_Plate:
		ship_append_local_box_faces(
			faces,
			patch,
			{sx * .36, hand * sy * .5, sz * 1.075},
			{sx * .3, sy * .25, max(sz * .035, f32(.028))},
			136,
			camera,
			center,
			scale,
		)
	case .Breach_Cage:
		brace := module; brace.material = .Truss
		for rib in 0 ..< 3 {
			x := (f32(rib) - 1) * sx * .46
			ship_append_local_box_faces(
				faces,
				brace,
				{x, hand * sy * .54, sz * 1.26},
				{sx * .055, sy * .08, sz * .32},
				144 + u32(rib * 8),
				camera,
				center,
				scale,
			)
		}
		ship_append_local_box_faces(
			faces,
			brace,
			{0, hand * sy * .56, sz * 1.52},
			{sx * .58, sy * .07, sz * .055},
			168,
			camera,
			center,
			scale,
		)
	case .Dark_Scar:
		scar := module; scar.material = .Glass
		for tine in 0 ..< 3 {
			x := (f32(tine) - 1) * sx * .34; lean := f32(tine - 1) * hand
			ship_append_local_box_faces(
				faces,
				scar,
				{x + lean * sx * .08, hand * sy * .45, sz * (1.18 + f32(tine) * .11)},
				{sx * .035, sy * .045, sz * (.2 + f32(tine) * .06)},
				184 + u32(tine * 8),
				camera,
				center,
				scale,
			)
		}
	case .None:
	}
}

ship_truss_local_segments :: proc(
	module: game.Procedural_Ship_Placement,
) -> [SHIP_TRUSS_SEGMENT_COUNT][2][3]f32 {
	sx, sy, sz := module.scale[0], module.scale[1], module.scale[2]
	return {
		{{-sx, -sy, -sz}, {sx, -sy, -sz}},
		{{-sx, -sy, sz}, {sx, -sy, sz}},
		{{-sx, sy, -sz}, {sx, sy, -sz}},
		{{-sx, sy, sz}, {sx, sy, sz}},
		// Root and payload bulkheads distribute four rail loads across a joint
		// face. Their envelope inherits the solver-sized truss thickness.
		{{-sx, -sy, -sz}, {-sx, sy, -sz}},
		{{-sx, sy, -sz}, {-sx, sy, sz}},
		{{-sx, sy, sz}, {-sx, -sy, sz}},
		{{-sx, -sy, sz}, {-sx, -sy, -sz}},
		{{sx, -sy, -sz}, {sx, sy, -sz}},
		{{sx, sy, -sz}, {sx, sy, sz}},
		{{sx, sy, sz}, {sx, -sy, sz}},
		{{sx, -sy, sz}, {sx, -sy, -sz}},
		{{0, -sy, -sz}, {0, sy, -sz}},
		{{0, sy, -sz}, {0, sy, sz}},
		{{0, sy, sz}, {0, -sy, sz}},
		{{0, -sy, sz}, {0, -sy, -sz}},
		{{-sx, -sy, -sz}, {0, sy, -sz}},
		{{0, sy, -sz}, {sx, -sy, -sz}},
		{{-sx, sy, sz}, {0, -sy, sz}},
		{{0, -sy, sz}, {sx, sy, sz}},
		{{-sx, -sy, sz}, {0, -sy, -sz}},
		{{0, -sy, -sz}, {sx, -sy, sz}},
		{{-sx, sy, -sz}, {0, sy, sz}},
		{{0, sy, sz}, {sx, sy, -sz}},
	}
}

ship_draw_truss_structure :: proc(
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
	detail: bool,
) {
	// Projected rails preserve genuine black negative space at a fraction of the
	// face cost of tiny boxes. End and central bulkheads plus alternating
	// diagonals make the load path legible without turning the truss into a slab.
	width :=
		detail ? f32(1.15) : f32(.82); ink := detail ? rl.Color{224, 222, 208, 180} : rl.Color{210, 208, 196, 135}
	for segment in ship_truss_local_segments(module) {
		a :=
			ship_project(ship_module_local_point(module, segment[0]), camera, center, scale).screen
		b :=
			ship_project(ship_module_local_point(module, segment[1]), camera, center, scale).screen
		rl.DrawLineEx(a, b, width + 1.2, {2, 2, 2, 230}); rl.DrawLineEx(a, b, width, ink)
	}
}

ship_axial_bay_segments :: proc(
	r: ^game.Procedural_Ship_Recipe,
	station: int,
) -> [SHIP_AXIAL_BAY_SEGMENT_COUNT][2][3]f32 {
	if station <= 0 || station >= r.frame.station_count do return {}
	a, b := r.modules[station - 1], r.modules[station]
	// Use the smaller adjoining station section so the frame enters both blocks
	// instead of protruding beyond either attachment envelope.
	sy := max(min(a.scale[1], b.scale[1]) * .38, f32(.035))
	sz := max(min(a.scale[2], b.scale[2]) * .38, f32(.035))
	ax, ay, az := a.position[0], a.position[1], a.position[2]
	bx, by, bz := b.position[0], b.position[1], b.position[2]
	return {
		{{ax, ay - sy, az - sz}, {bx, by - sy, bz - sz}},
		{{ax, ay - sy, az + sz}, {bx, by - sy, bz + sz}},
		{{ax, ay + sy, az - sz}, {bx, by + sy, bz - sz}},
		{{ax, ay + sy, az + sz}, {bx, by + sy, bz + sz}},
		{{ax, ay - sy, az - sz}, {ax, ay + sy, az - sz}},
		{{ax, ay + sy, az - sz}, {ax, ay + sy, az + sz}},
		{{ax, ay + sy, az + sz}, {ax, ay - sy, az + sz}},
		{{ax, ay - sy, az + sz}, {ax, ay - sy, az - sz}},
		{{bx, by - sy, bz - sz}, {bx, by + sy, bz - sz}},
		{{bx, by + sy, bz - sz}, {bx, by + sy, bz + sz}},
		{{bx, by + sy, bz + sz}, {bx, by - sy, bz + sz}},
		{{bx, by - sy, bz + sz}, {bx, by - sy, bz - sz}},
		// X-brace all four open planes. Paired diagonals close shear paths in
		// either direction and make the bay resist torsion without adding a skin.
		{{ax, ay - sy, az - sz}, {bx, by + sy, bz - sz}},
		{{ax, ay + sy, az - sz}, {bx, by - sy, bz - sz}},
		{{ax, ay - sy, az + sz}, {bx, by + sy, bz + sz}},
		{{ax, ay + sy, az + sz}, {bx, by - sy, bz + sz}},
		{{ax, ay - sy, az - sz}, {bx, by - sy, bz + sz}},
		{{ax, ay - sy, az + sz}, {bx, by - sy, bz - sz}},
		{{ax, ay + sy, az - sz}, {bx, by + sy, bz + sz}},
		{{ax, ay + sy, az + sz}, {bx, by + sy, bz - sz}},
	}
}

ship_draw_axial_longeron :: proc(
	r: ^game.Procedural_Ship_Recipe,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
	detail: bool,
) {
	// Four longerons, station bulkheads, and open-plane X bracing form a real bay
	// frame beneath the opaque modules. Only fabrication breaks remain exposed,
	// preserving a continuous load path without becoming a solid bar.
	if r.frame.station_count < 2 do return
	width :=
		detail ? f32(1.35) : f32(.9); ink := detail ? rl.Color{218, 216, 203, 160} : rl.Color{204, 202, 190, 120}
	for station in 1 ..< r.frame.station_count {
		for segment in ship_axial_bay_segments(r, station) {
			a := ship_project(segment[0], camera, center, scale).screen
			b := ship_project(segment[1], camera, center, scale).screen
			rl.DrawLineEx(a, b, width + 2.6, {2, 2, 2, 255})
			rl.DrawLineEx(a, b, width, ink)
		}
	}
}

ship_append_armor_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// A narrow chamfered collar flares into a broad octagonal sacrificial plate.
	// Flat corner cuts keep armor in an angular manufactured vocabulary while
	// the taper communicates which face protects the attachment.
	sx, sy, sz := module.scale[0], module.scale[1], module.scale[2]
	iy, iz, oy, oz :=
		sy *
		.38,
		sz *
		.48,
		sy,
		sz *
		.78; icy, icz := iy * .34, iz * .34; ocy, ocz := oy * .28, oz * .28
	inboard := [SHIP_ARMOR_SEGMENTS][2]f32 {
		{-iy, -iz + icz},
		{-iy + icy, -iz},
		{iy - icy, -iz},
		{iy, -iz + icz},
		{iy, iz - icz},
		{iy - icy, iz},
		{-iy + icy, iz},
		{-iy, iz - icz},
	}
	outboard := [SHIP_ARMOR_SEGMENTS][2]f32 {
		{-oy, -oz + ocz},
		{-oy + ocy, -oz},
		{oy - ocy, -oz},
		{oy, -oz + ocz},
		{oy, oz - ocz},
		{oy - ocy, oz},
		{-oy + ocy, oz},
		{-oy, oz - ocz},
	}
	rear_center := ship_module_local_point(
		module,
		{-sx, 0, 0},
	); front_center := ship_module_local_point(module, {sx, 0, 0})
	for segment in 0 ..< SHIP_ARMOR_SEGMENTS {
		next := (segment + 1) % SHIP_ARMOR_SEGMENTS
		r0 := ship_module_local_point(
			module,
			{-sx, inboard[segment][0], inboard[segment][1]},
		); r1 := ship_module_local_point(module, {-sx, inboard[next][0], inboard[next][1]})
		f0 := ship_module_local_point(
			module,
			{sx, outboard[segment][0], outboard[segment][1]},
		); f1 := ship_module_local_point(module, {sx, outboard[next][0], outboard[next][1]})
		ny :=
			(outboard[segment][0] + outboard[next][0]) *
			.5 /
			oy; nz := (outboard[segment][1] + outboard[next][1]) * .5 / oz; normal_length := f32(math.sqrt(f64(ny * ny + nz * nz))); if normal_length > .001 {ny /= normal_length; nz /= normal_length}
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
			module.surface_id + u32(SHIP_ARMOR_SEGMENTS + segment * 2),
			camera,
			center,
			scale,
		)
		ship_append_face(
			faces,
			{front_center, f0, f1, front_center},
			ship_module_local_normal(module, {1, 0, 0}),
			module,
			module.surface_id + u32(SHIP_ARMOR_SEGMENTS + segment * 2 + 1),
			camera,
			center,
			scale,
		)
	}
}

ship_append_face :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	world: [4][3]f32,
	normal: [3]f32,
	module: game.Procedural_Ship_Placement,
	surface: u32,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	e1 := [3]f32 {
		world[1][0] - world[0][0],
		world[1][1] - world[0][1],
		world[1][2] - world[0][2],
	}; e2 := [3]f32{world[2][0] - world[0][0], world[2][1] - world[0][1], world[2][2] - world[0][2]}
	derived := [3]f32 {
		e1[1] * e2[2] - e1[2] * e2[1],
		e1[2] * e2[0] - e1[0] * e2[2],
		e1[0] * e2[1] - e1[1] * e2[0],
	}; length := f32(math.sqrt(f64(derived[0] * derived[0] + derived[1] * derived[1] + derived[2] * derived[2])))
	if length > .0001 {
		for axis in 0 ..< 3 do derived[axis] /= length
		dot := derived[0] * normal[0] + derived[1] * normal[1] + derived[2] * normal[2]
		if dot < 0 do for axis in 0 ..< 3 do derived[axis] *= -1
	} else {derived = normal}
	points: [4]rl.Vector2; depths: [4]f32; depth: f32; for p, i in world {projected := ship_project(p, camera, center, scale); points[i] = projected.screen; depths[i] = projected.depth; depth += projected.depth * .25}; n := ship_rotate_view(derived, camera)
	bounds_min, bounds_max := points[0], points[0]
	for point in points[1:] {bounds_min.x = min(bounds_min.x, point.x); bounds_min.y = min(
			bounds_min.y,
			point.y,
		)
		bounds_max.x = max(bounds_max.x, point.x)
		bounds_max.y = max(bounds_max.y, point.y)}
	face := Ship_Project_Face {
		points       = points,
		depths       = depths,
		world        = world,
		depth        = depth,
		normal       = n,
		material     = module.material,
		module_id    = module.id,
		surface_id   = surface,
		bounds_min   = bounds_min,
		bounds_max   = bounds_max,
		bounds_valid = true,
	}; ship_face_canonicalize_winding(&face); append(faces, face)
}

ship_append_radial_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// Inhabited pressure hulls retain a round pressure-bearing center course, but
	// faceted shoulders narrow both attachment ends into inspectable collars.
	segments := SHIP_PRESSURE_HULL_SEGMENTS; sx := module.scale[0]
	xs := [4]f32{-sx, -sx * .55, sx * .55, sx}; radii := [4]f32{.5, 1, 1, .5}
	phase := f32(module.surface_id % 13) / 13 * math.PI * .25
	for course in 0 ..< 3 do for segment in 0 ..< segments {
		a0 := phase + math.PI * 2 * f32(segment) / f32(segments); a1 := phase + math.PI * 2 * f32(segment + 1) / f32(segments); mid := (a0 + a1) * .5
		c0, s0 := f32(math.cos(a0)), f32(math.sin(a0)); c1, s1 := f32(math.cos(a1)), f32(math.sin(a1)); x0, x1 := xs[course], xs[course + 1]; r0, r1 := radii[course], radii[course + 1]
		p00 := ship_module_local_point(module, {x0, c0 * module.scale[1] * r0, s0 * module.scale[2] * r0}); p01 := ship_module_local_point(module, {x0, c1 * module.scale[1] * r0, s1 * module.scale[2] * r0})
		p10 := ship_module_local_point(module, {x1, c0 * module.scale[1] * r1, s0 * module.scale[2] * r1}); p11 := ship_module_local_point(module, {x1, c1 * module.scale[1] * r1, s1 * module.scale[2] * r1})
		nx: f32 = 0; if course == 0 {nx = -.55} else if course == 2 {nx = .55}
		normal := ship_module_local_normal(module, {nx, f32(math.cos(mid)), f32(math.sin(mid))})
		ship_append_face(faces, {p00, p10, p11, p01}, normal, module, module.surface_id + u32(course * segments + segment), camera, center, scale)
	}
	rear_center := ship_module_local_point(
		module,
		{-sx, 0, 0},
	); front_center := ship_module_local_point(module, {sx, 0, 0}); cap_surface := module.surface_id + u32(segments * 3)
	for segment in 0 ..< segments {
		a0 :=
			phase +
			math.PI *
				2 *
				f32(segment) /
				f32(
					segments,
				); a1 := phase + math.PI * 2 * f32(segment + 1) / f32(segments); c0, s0 := f32(math.cos(a0)), f32(math.sin(a0)); c1, s1 := f32(math.cos(a1)), f32(math.sin(a1))
		rear0 := ship_module_local_point(
			module,
			{-sx, c0 * module.scale[1] * radii[0], s0 * module.scale[2] * radii[0]},
		); rear1 := ship_module_local_point(module, {-sx, c1 * module.scale[1] * radii[0], s1 * module.scale[2] * radii[0]})
		front0 := ship_module_local_point(
			module,
			{sx, c0 * module.scale[1] * radii[3], s0 * module.scale[2] * radii[3]},
		); front1 := ship_module_local_point(module, {sx, c1 * module.scale[1] * radii[3], s1 * module.scale[2] * radii[3]})
		ship_append_face(
			faces,
			{rear_center, rear1, rear0, rear_center},
			ship_module_local_normal(module, {-1, 0, 0}),
			module,
			cap_surface + u32(segment * 2),
			camera,
			center,
			scale,
		)
		ship_append_face(
			faces,
			{front_center, front0, front1, front_center},
			ship_module_local_normal(module, {1, 0, 0}),
			module,
			cap_surface + u32(segment * 2 + 1),
			camera,
			center,
			scale,
		)
	}
}

ship_append_tank_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// Propellant is carried in a straight welded hex vessel, captured by two
	// raised restraint bands and a paired machinery cradle.  The square load
	// path makes this read as mounted cargo rather than another inhabited pod.
	segments :=
		SHIP_TANK_SEGMENTS; phase: f32 = math.PI / 6; sx, sy, sz := module.scale[0], module.scale[1], module.scale[2]; barrel_radius: f32 = .78
	for segment in 0 ..< segments {
		a0 :=
			phase +
			math.PI *
				2 *
				f32(segment) /
				f32(
					segments,
				); a1 := phase + math.PI * 2 * f32(segment + 1) / f32(segments); mid := (a0 + a1) * .5
		c0, s0 :=
			f32(math.cos(a0)), f32(math.sin(a0)); c1, s1 := f32(math.cos(a1)), f32(math.sin(a1))
		rear0 := ship_module_local_point(
			module,
			{-sx, c0 * sy * barrel_radius, s0 * sz * barrel_radius},
		); rear1 := ship_module_local_point(module, {-sx, c1 * sy * barrel_radius, s1 * sz * barrel_radius}); front0 := ship_module_local_point(module, {sx, c0 * sy * barrel_radius, s0 * sz * barrel_radius}); front1 := ship_module_local_point(module, {sx, c1 * sy * barrel_radius, s1 * sz * barrel_radius})
		ship_append_face(
			faces,
			{rear0, front0, front1, rear1},
			ship_module_local_normal(module, {0, f32(math.cos(mid)), f32(math.sin(mid))}),
			module,
			module.surface_id + u32(segment),
			camera,
			center,
			scale,
		)
		rear_center := ship_module_local_point(
			module,
			{-sx, 0, 0},
		); front_center := ship_module_local_point(module, {sx, 0, 0})
		ship_append_face(
			faces,
			{rear_center, rear1, rear0, rear_center},
			ship_module_local_normal(module, {-1, 0, 0}),
			module,
			module.surface_id + u32(segments + segment * 2),
			camera,
			center,
			scale,
		)
		ship_append_face(
			faces,
			{front_center, front0, front1, front_center},
			ship_module_local_normal(module, {1, 0, 0}),
			module,
			module.surface_id + u32(segments + segment * 2 + 1),
			camera,
			center,
			scale,
		)
	}
	strap_half_x := sx * .09
	for strap in 0 ..< SHIP_TANK_STRAP_COUNT {
		x := (f32(strap) * 2 - 1) * sx * .48
		for segment in 0 ..< segments {
			a0 :=
				phase +
				math.PI *
					2 *
					f32(segment) /
					f32(
						segments,
					); a1 := phase + math.PI * 2 * f32(segment + 1) / f32(segments); mid := (a0 + a1) * .5; c0, s0 := f32(math.cos(a0)), f32(math.sin(a0)); c1, s1 := f32(math.cos(a1)), f32(math.sin(a1))
			quad := [4][3]f32 {
				ship_module_local_point(module, {x - strap_half_x, c0 * sy, s0 * sz}),
				ship_module_local_point(module, {x + strap_half_x, c0 * sy, s0 * sz}),
				ship_module_local_point(module, {x + strap_half_x, c1 * sy, s1 * sz}),
				ship_module_local_point(module, {x - strap_half_x, c1 * sy, s1 * sz}),
			}
			ship_append_face(
				faces,
				quad,
				ship_module_local_normal(module, {0, f32(math.cos(mid)), f32(math.sin(mid))}),
				module,
				module.surface_id + u32(segments * 3 + strap * segments + segment),
				camera,
				center,
				scale,
			)
		}
	}
	for rail in 0 ..< 2 {
		y := (f32(rail) * 2 - 1) * sy * .42
		ship_append_local_box_faces(
			faces,
			module,
			{0, y, -sz * .84},
			{sx, sy * .1, sz * .12},
			u32(segments * 5 + rail * 8),
			camera,
			center,
			scale,
		)
	}
}
