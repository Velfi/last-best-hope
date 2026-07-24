package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:c"
import "core:fmt"
import "core:math"
import "core:testing"
import stbi "vendor:stb/image"
ship_mission_service_side :: proc(surface_id: u32) -> f32 {
	return surface_id & 1 == 0 ? -1 : 1
}

ship_mission_mount_local :: proc(module: game.Procedural_Ship_Placement) -> [3]f32 {
	encoded := int(
		module.mount_variant,
	); slot := encoded % 9; column := slot % 3 - 1; row := slot / 3 - 1
	side: f32
	if column == 0 {side = encoded >= 9 ? f32(1) : -1} else {side = f32(column)}
	lateral := column == 0 ? f32(.28) : f32(.78)
	return {
		f32(row) * module.scale[0] * .42,
		side * module.scale[1] * lateral,
		module.scale[2] * (.16 + f32(row) * .08),
	}
}

ship_append_mission_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// Mission profiles change actual deck topology. Compact installations keep
	// everything inside the sloped housing; standard decks add one replaceable
	// service pod; expanded decks carry paired pods and an offset sensor room.
	// Seeded handedness keeps the latter two from becoming sterile mirror forms.
	sx, sy, sz := module.scale[0], module.scale[1], module.scale[2]
	ship_append_local_box_faces(
		faces,
		module,
		{-sx * .25, 0, -sz * .28},
		{sx * .75, sy, sz * .46},
		0,
		camera,
		center,
		scale,
	)
	x0, x1 :=
		-sx *
		.08,
		sx *
		.94; y0, y1 := -sy * .62, sy * .62; bottom, rear_top, front_top := sz * .08, sz * .9, sz * .6
	local := [8][3]f32 {
		{x0, y0, bottom},
		{x1, y0, bottom},
		{x1, y1, bottom},
		{x0, y1, bottom},
		{x0, y0, rear_top},
		{x1, y0, front_top},
		{x1, y1, front_top},
		{x0, y1, rear_top},
	}
	indices := [6][4]int {
		{0, 1, 2, 3},
		{4, 7, 6, 5},
		{0, 4, 5, 1},
		{3, 2, 6, 7},
		{0, 3, 7, 4},
		{1, 5, 6, 2},
	}
	normals := [6][3]f32{{0, 0, -1}, {.28, 0, 1}, {0, -1, 0}, {0, 1, 0}, {-1, 0, 0}, {1, 0, .18}}
	world: [8][3]f32; for point, i in local do world[i] = ship_module_local_point(module, point)
	for face_index in 0 ..< 6 {quad: [4][3]f32; for corner in 0 ..< 4 do quad[corner] = world[indices[face_index][corner]]; ship_append_face(faces, quad, ship_module_local_normal(module, normals[face_index]), module, module.surface_id + 8 + u32(face_index), camera, center, scale)}
	if module.variant == 0 do return
	mount := ship_mission_mount_local(module); service_side := mount[1] < 0 ? f32(-1) : 1
	ship_append_local_box_faces(
		faces,
		module,
		mount,
		{sx * .3, sy * .2, sz * .22},
		16,
		camera,
		center,
		scale,
	)
	if module.variant >= 2 {
		ship_append_local_box_faces(
			faces,
			module,
			{-mount[0] * .5, -service_side * sy * .78, sz * .12},
			{sx * .38, sy * .2, sz * .28},
			24,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			module,
			{sx * .22, service_side * sy * .28, sz * .86},
			{sx * .28, sy * .3, sz * .14},
			32,
			camera,
			center,
			scale,
		)
	}
}

ship_append_antenna_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// A narrow socket-anchored mast carries two separated receiver plates. The
	// paired head reads as communications hardware from top and side views while
	// remaining inside the former rectangular antenna envelope.
	sx, sy, sz := module.scale[0], module.scale[1], module.scale[2]
	ship_append_local_box_faces(
		faces,
		module,
		{0, 0, 0},
		{sx * .18, sy * .18, sz},
		0,
		camera,
		center,
		scale,
	)
	ship_append_local_box_faces(
		faces,
		module,
		{-sx * .62, 0, sz * .58},
		{sx * .3, sy, sz * .27},
		8,
		camera,
		center,
		scale,
	)
	ship_append_local_box_faces(
		faces,
		module,
		{sx * .62, 0, sz * .58},
		{sx * .3, sy, sz * .27},
		16,
		camera,
		center,
		scale,
	)
}

ship_bow_tip_profile :: proc(variant: u8) -> (beam, height: f32, bumper: bool) {
	switch int(variant) % 3 {
	case 0:
		return .62, .72, true // blunt protected work bow
	case 1:
		return .16, .42, false // standard clipped wedge
	case 2:
		return .035, .11, false // narrow needle with a square inspection tip
	}
	return .16, .42, false
}

ship_bow_family_subassembly_count :: proc(family: game.Procedural_Ship_Family) -> int {
	switch family {case .Strike:
		return 0; case .Fleet:
		return 2; case .Habitat:
		return 3}
	return 0
}

ship_bow_chine_profile :: proc(family: game.Procedural_Ship_Family) -> (side_cut, deck_cut: f32) {
	switch family {
	case .Strike:
		return .55, .25
	case .Fleet:
		return .72, .42
	case .Habitat:
		return .62, .56
	}
	return .6, .4
}

ship_append_bow_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	family: game.Procedural_Ship_Family,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// Three yard architectures share an angular pressure boundary: a broad bow
	// with a replaceable impact bumper, the standard clipped wedge, and a long
	// needle terminating in a tiny square inspection face. None uses a radial cap.
	sx, sy, sz :=
		module.scale[0],
		module.scale[1],
		module.scale[2]; beam, height, bumper := ship_bow_tip_profile(module.variant); fy, fz := sy * beam, sz * height; x0, x1 := module.position[0] - sx, module.position[0] + sx; y, z := module.position[1], module.position[2]
	side_cut, deck_cut := ship_bow_chine_profile(family)
	rear := [8][2]f32 {
		{-sy, -sz * deck_cut},
		{-sy * side_cut, -sz},
		{sy * side_cut, -sz},
		{sy, -sz * deck_cut},
		{sy, sz * deck_cut},
		{sy * side_cut, sz},
		{-sy * side_cut, sz},
		{-sy, sz * deck_cut},
	}
	front: [8][2]f32
	for point, i in rear do front[i] = {point[0] * beam, point[1] * height}
	rear_center := [3]f32{x0, y, z}; front_center := [3]f32{x1, y, z}
	for segment in 0 ..< 8 {
		next := (segment + 1) % 8
		r0 := [3]f32 {
			x0,
			y + rear[segment][0],
			z + rear[segment][1],
		}; r1 := [3]f32{x0, y + rear[next][0], z + rear[next][1]}; f0 := [3]f32{x1, y + front[segment][0], z + front[segment][1]}; f1 := [3]f32{x1, y + front[next][0], z + front[next][1]}
		ny :=
			(rear[segment][0] + rear[next][0]) *
			.5 /
			max(
				sy,
				f32(.001),
			); nz := (rear[segment][1] + rear[next][1]) * .5 / max(sz, f32(.001)); length := f32(math.sqrt(f64(ny * ny + nz * nz))); if length > .001 {ny /= length; nz /= length}
		ship_append_face(
			faces,
			{r0, f0, f1, r1},
			{0, ny, nz},
			module,
			module.surface_id + u32(segment),
			camera,
			center,
			scale,
		)
		ship_append_face(
			faces,
			{rear_center, r1, r0, rear_center},
			{-1, 0, 0},
			module,
			module.surface_id + 8 + u32(segment * 2),
			camera,
			center,
			scale,
		)
		ship_append_face(
			faces,
			{front_center, f0, f1, front_center},
			{1, 0, 0},
			module,
			module.surface_id + 8 + u32(segment * 2 + 1),
			camera,
			center,
			scale,
		)
	}
	if bumper do ship_append_local_box_faces(faces, module, {sx * .82, 0, 0}, {sx * .12, sy * .74, sz * .8}, 32, camera, center, scale)
	// Family construction remains legible even when two yards choose the same
	// seeded tip profile. Fleet prows carry replaceable armor cheeks; habitat bows
	// expose a dorsal service deck and paired capture jaws for slow docking work.
	switch family {
	case .Strike:
	case .Fleet:
		cheek := module; cheek.material = .Armor
		ship_append_local_box_faces(
			faces,
			cheek,
			{-sx * .28, -sy * 1.2, -sz * .08},
			{sx * .68, sy * .25, sz * .68},
			48,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			cheek,
			{-sx * .28, sy * 1.2, -sz * .08},
			{sx * .68, sy * .25, sz * .68},
			56,
			camera,
			center,
			scale,
		)
	case .Habitat:
		service := module; service.material = .Machinery
		ship_append_local_box_faces(
			faces,
			service,
			{-sx * .18, 0, sz * 1.25},
			{sx * .56, sy * .64, sz * .18},
			64,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			service,
			{sx * .42, -sy * 1.22, 0},
			{sx * .38, sy * .22, sz * .55},
			72,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			service,
			{sx * .42, sy * 1.22, 0},
			{sx * .38, sy * .22, sz * .55},
			80,
			camera,
			center,
			scale,
		)
	}
}

ship_append_ring_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// Ring modules snap back to the axial keel instead of inheriting a branch's
	// lateral socket position. A continuous run of narrow pressure-bearing
	// sectors keeps the inhabited volume intact while retaining inspectable panel
	// divisions and a smooth silhouette.
	segments :=
		SHIP_HABITAT_RING_SEGMENTS; inner := module.scale[1] * .66; outer := module.scale[1]; half_x := module.scale[0] * .62; phase := f32(module.surface_id % 17) / 17 * math.PI * 2; base_surface := module.surface_id * 64
	for segment in 0 ..< segments {
		a0 :=
			phase +
			math.PI *
				2 *
				f32(segment) /
				f32(
					segments,
				); a1 := phase + math.PI * 2 * f32(segment + 1) / f32(segments); c0, s0 := f32(math.cos(a0)), f32(math.sin(a0)); c1, s1 := f32(math.cos(a1)), f32(math.sin(a1)); x := module.position[0]
		front := [4][3]f32 {
			{x + half_x, c0 * inner, s0 * inner},
			{x + half_x, c0 * outer, s0 * outer},
			{x + half_x, c1 * outer, s1 * outer},
			{x + half_x, c1 * inner, s1 * inner},
		}
		back := [4][3]f32 {
			{x - half_x, c1 * inner, s1 * inner},
			{x - half_x, c1 * outer, s1 * outer},
			{x - half_x, c0 * outer, s0 * outer},
			{x - half_x, c0 * inner, s0 * inner},
		}
		outer_wall := [4][3]f32 {
			{x - half_x, c0 * outer, s0 * outer},
			{x - half_x, c1 * outer, s1 * outer},
			{x + half_x, c1 * outer, s1 * outer},
			{x + half_x, c0 * outer, s0 * outer},
		}
		inner_wall := [4][3]f32 {
			{x + half_x, c0 * inner, s0 * inner},
			{x + half_x, c1 * inner, s1 * inner},
			{x - half_x, c1 * inner, s1 * inner},
			{x - half_x, c0 * inner, s0 * inner},
		}
		mid :=
			(a0 + a1) *
			.5; radial := [3]f32{0, f32(math.cos(mid)), f32(math.sin(mid))}; surface := base_surface + u32(segment * 4); ship_append_face(faces, front, {1, 0, 0}, module, surface, camera, center, scale); ship_append_face(faces, back, {-1, 0, 0}, module, surface + 1, camera, center, scale); ship_append_face(faces, outer_wall, radial, module, surface + 2, camera, center, scale); ship_append_face(faces, inner_wall, {0, -radial[1], -radial[2]}, module, surface + 3, camera, center, scale)
	}
}

ship_draw_ring_structure :: proc(
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
	detail: bool,
) {
	segments :=
		SHIP_HABITAT_RING_SEGMENTS; inner := module.scale[1] * .66; outer := module.scale[1]; x := module.position[0] + module.scale[0] * .64; phase := f32(module.surface_id % 17) / 17 * math.PI * 2; line := detail ? f32(1.25) : f32(.9)
	ink :=
		detail ? rl.Color{232, 229, 213, 205} : rl.Color{220, 217, 203, 170}; under := rl.Color{3, 3, 3, 255}
	for segment in 0 ..< segments {
		a0 :=
			phase +
			math.PI *
				2 *
				f32(segment) /
				f32(segments); a1 := phase + math.PI * 2 * f32(segment + 1) / f32(segments)
		radii := [2]f32{inner, outer}
		for radius in radii {
			p0 :=
				ship_project({x, f32(math.cos(a0)) * radius, f32(math.sin(a0)) * radius}, camera, center, scale).screen; p1 := ship_project({x, f32(math.cos(a1)) * radius, f32(math.sin(a1)) * radius}, camera, center, scale).screen
			dx, dy := p1.x - p0.x, p1.y - p0.y
			if dx * dx + dy * dy >
			   .25 {rl.DrawLineEx(p0, p1, line + 1.2, under); rl.DrawLineEx(p0, p1, line, ink)}
		}
	}
	hub := ship_project({x, 0, 0}, camera, center, scale).screen
	for spoke in 0 ..< 4 {
		a :=
			phase +
			math.PI *
				.5 *
				f32(
					spoke,
				); rim := ship_project({x, f32(math.cos(a)) * inner, f32(math.sin(a)) * inner}, camera, center, scale).screen
		dx, dy := rim.x - hub.x, rim.y - hub.y
		if dx * dx + dy * dy >
		   .25 {rl.DrawLineEx(hub, rim, line + 1, under); rl.DrawLineEx(hub, rim, line * .62, {216, 213, 200, 145})}
	}
}

ship_recipe_view_bounds :: proc(
	r: ^game.Procedural_Ship_Recipe,
	camera: Ship_Generator_Camera,
) -> (
	min_x, min_z, max_x, max_z: f32,
) {
	min_x, min_z = 1e30, 1e30; max_x, max_z = -1e30, -1e30
	if ship_architecture_has_closed_hull(r.architecture) {
		// The closed loft replaces most inventory geometry, so its own envelope
		// must drive camera fitting rather than the now-hidden outrigger sockets.
		half_length := r.frame.keel_length * .5
		half_beam := r.frame.beam * .5
		half_height := r.frame.height * .58
		for corner in 0 ..< 8 {
			x: f32 = corner & 1 == 0 ? -half_length : half_length
			y: f32 = corner & 2 == 0 ? -half_beam : half_beam
			z: f32 = corner & 4 == 0 ? -half_height : half_height
			p := ship_rotate_view({x, y, z}, camera)
			min_x = min(
				min_x,
				p[0],
			); max_x = max(max_x, p[0]); min_z = min(min_z, p[2]); max_z = max(max_z, p[2])
		}
	}
	for source in r.modules[:r.module_count] {
		if !ship_module_exposed_by_architecture(r.architecture, source.module) do continue
		module := ship_closed_hull_mount_module(r, source)
		// Rings are centered on the keel even though their placement socket is
		// offset. Their scale is already the outer radial envelope.
		origin := ship_module_render_origin(module)
		if module.module == .Ring_Segment do origin = {module.position[0], 0, 0}
		axis, side, up := ship_module_basis(module); sx := module.scale[0]
		sy, sz := module.scale[1], module.scale[2]
		if module.module == .Drive {sx *= 3.0; sy *= 1.55; sz *= 1.55}
		if module.module == .Dock {sx *= 1.72; sy *= 1.15; sz *= 1.15}
		if module.module ==
		   .Bow {if r.family == .Fleet {sy *= 1.48; sz *= 1.18} else if r.family == .Habitat {sy *= 1.52; sz *= 1.48}}
		if module.service_mark == .Breach_Cage ||
		   module.service_mark == .Dark_Scar {sy *= 1.18; sz *= 1.65}
		for corner in 0 ..< 8 {
			sign_x: f32 =
				corner & 1 == 0 ? -1 : 1; sign_y: f32 = corner & 2 == 0 ? -1 : 1; sign_z: f32 = corner & 4 == 0 ? -1 : 1
			local := [3]f32{sign_x * sx, sign_y * sy, sign_z * sz}
			world := [3]f32 {
				origin[0] + axis[0] * local[0] + side[0] * local[1] + up[0] * local[2],
				origin[1] + axis[1] * local[0] + side[1] * local[1] + up[1] * local[2],
				origin[2] + axis[2] * local[0] + side[2] * local[1] + up[2] * local[2],
			}
			p := ship_rotate_view(world, camera)
			min_x = min(
				min_x,
				p[0],
			); max_x = max(max_x, p[0]); min_z = min(min_z, p[2]); max_z = max(max_z, p[2])
		}
	}
	return
}

ship_recipe_view_span :: proc(
	r: ^game.Procedural_Ship_Recipe,
	camera: Ship_Generator_Camera,
) -> Ship_View_Span {
	min_x, min_z, max_x, max_z := ship_recipe_view_bounds(r, camera)
	return {max(max_x - min_x, f32(.01)), max(max_z - min_z, f32(.01))}
}

ship_recipe_view_fit :: proc(
	r: ^game.Procedural_Ship_Recipe,
	camera: Ship_Generator_Camera,
	rect: rl.Rectangle,
	shared_span := Ship_View_Span{},
) -> (
	rl.Vector2,
	f32,
) {
	min_x, min_z, max_x, max_z := ship_recipe_view_bounds(r, camera)
	local := Ship_View_Span{max(max_x - min_x, f32(.01)), max(max_z - min_z, f32(.01))}
	span_x :=
		shared_span.x > 0 ? shared_span.x : local.x; span_z := shared_span.z > 0 ? shared_span.z : local.z
	scale := min(rect.width * .86 / span_x, rect.height * .78 / span_z) * camera.zoom
	center := V(
		rect.x + rect.width * .5 - (min_x + max_x) * .5 * scale,
		rect.y + rect.height * .5 + (min_z + max_z) * .5 * scale,
	)
	return center, scale / camera.zoom
}

ship_delta_hatch_for_family_view :: proc(
	config: rl.Hatch_Config,
	family: game.Procedural_Ship_Family,
	detail: bool,
) -> rl.Hatch_Config {
	result := config
	if !detail && family == .Habitat {
		// Taller 4:3 habitat sheets project broad faces across more scan lines than
		// fleet or strike hulls. One sparse layer preserves engraved material while
		// preventing hatch vertices from displacing later labels and cells.
		result.layer_count = min(result.layer_count, 1)
		result.spacing *= 1.55
		result.line_width *= .9
	}
	return result
}

@(test)
habitat_delta_distant_hatching_is_sparse_without_changing_close_views :: proc(t: ^testing.T) {
	base := LBH_HATCH_ENGRAVING
	distant := ship_delta_hatch_for_family_view(base, .Habitat, false)
	close := ship_delta_hatch_for_family_view(base, .Habitat, true)
	fleet := ship_delta_hatch_for_family_view(base, .Fleet, false)
	testing.expect_value(t, distant.layer_count, 1)
	testing.expect(t, distant.spacing > base.spacing)
	testing.expect_value(t, close, base)
	testing.expect_value(t, fleet, base)
}
