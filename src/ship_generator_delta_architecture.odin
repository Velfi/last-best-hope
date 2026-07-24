package main

import game "../packages/game"
import "core:math"
import "core:testing"
import rl "zelda_engine:canvas2d"

ship_delta_half_extents :: proc(r: ^game.Procedural_Ship_Recipe) -> (sx, sy, sz: f32) {
	sx = r.frame.keel_length * .50
	sy = r.frame.beam * .50
	// A lifting body still needs enough pressure depth to read as a ship in side
	// elevation. Family depth is structural: strike hulls remain knife-like,
	// fleet hulls carry a credible central volume, and habitats become deep
	// inhabited wedges rather than merely broader wings.
	sz = r.frame.height * .28
	switch r.family {
	case .Strike:
		sz *= .82
	case .Fleet:
	case .Habitat:
		// Habitat deltas are heavy lifting bodies: broad inhabited shoulders and
		// a deeper pressure volume take precedence over interceptor directionality.
		sx *= .88
		sy *= 1.25
		sz *= 1.22
	}
	return
}

ship_append_delta_hull_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
	detail := true,
) {
	sx, sy, sz := ship_delta_half_extents(r)
	plan := ship_delta_planform(r.seed, sx, sy, r.family)
	hull := game.Procedural_Ship_Placement {
		surface_id = 0xf3000000,
		module     = .Keel,
		material   = .Hull_Plate,
		direction  = {1, 0, 0},
		scale      = {sx, sy, sz},
	}
	top_center := [3]f32{-sx * .05, 0, sz * 1.22}
	bottom_center := [3]f32{-sx * .12, 0, -sz}
	for i in 0 ..< len(plan) {
		next := (i + 1) % len(plan)
		top_a, bottom_a := ship_delta_edge_vertical(r.seed, plan[i][0], i, sx, sz)
		top_b, bottom_b := ship_delta_edge_vertical(r.seed, plan[next][0], next, sx, sz)
		a := [3]f32{plan[i][0], plan[i][1], top_a}
		b := [3]f32{plan[next][0], plan[next][1], top_b}
		la := [3]f32{plan[i][0], plan[i][1], bottom_a}
		lb := [3]f32{plan[next][0], plan[next][1], bottom_b}
		dx, dy := plan[next][0] - plan[i][0], plan[next][1] - plan[i][1]
		length := max(f32(math.sqrt(f64(dx * dx + dy * dy))), f32(.001))
		normal := [3]f32{dy / length, -dx / length, 0}
		surface := hull.surface_id + u32(i * 3)
		ship_append_face(
			faces,
			{top_center, a, b, top_center},
			{0, 0, 1},
			hull,
			surface,
			camera,
			center,
			scale,
		)
		ship_append_face(
			faces,
			{bottom_center, lb, la, bottom_center},
			{0, 0, -1},
			hull,
			surface + 1,
			camera,
			center,
			scale,
		)
		ship_append_face(faces, {a, la, lb, b}, normal, hull, surface + 2, camera, center, scale)
	}
	spine := hull; spine.material = .Armor
	ship_append_delta_keel_ridge_faces(
		faces,
		spine,
		r.seed,
		r.family,
		sx,
		sy,
		sz,
		camera,
		center,
		scale,
	)
	ship_append_delta_elevon_faces(
		faces,
		spine,
		r.seed,
		r.family,
		sx,
		sy,
		sz,
		camera,
		center,
		scale,
	)
	ship_append_delta_citadel_faces(
		faces,
		spine,
		r.seed,
		r.family,
		sx,
		sy,
		sz,
		camera,
		center,
		scale,
	)
	// Paired root fairings make the wide trailing edge look structurally loaded.
	for side_index in 0 ..< 2 {
		side: f32 = side_index == 0 ? -1 : 1
		ship_append_local_box_faces(
			faces,
			spine,
			{-sx * .48, side * sy * .54, sz * .72},
			{sx * .18, sy * .11, sz * .10},
			u32(0x1c0 + side_index * 8),
			camera,
			center,
			scale,
		)
	}
	ship_append_delta_weapon_faces(faces, r, hull, sx, sy, sz, camera, center, scale)
	ship_append_delta_mount_fairings(faces, r, hull, sx, sy, sz, camera, center, scale, detail)
	ship_append_delta_history_faces(faces, r, hull, sx, sy, sz, camera, center, scale, detail)
	ship_append_single_hull_internal_warts(faces, r, hull, camera, center, scale, detail)
}

ship_append_delta_weapon_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	hull: game.Procedural_Ship_Placement,
	sx, sy, sz: f32,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	weapon_scale := r.weapon_capability_scale
	if weapon_scale <= 0 do weapon_scale = 1
	for side_index in 0 ..< 2 {
		side: f32 = side_index == 0 ? -1 : 1
		if r.weapon_package == .Guided_Missiles {
			for store_index in 0 ..< 2 {
				x := sx * (-.08 + f32(store_index) * .27)
				y := side * sy * (store_index == 0 ? f32(.55) : f32(.45))
				store := hull
				store.position = {
					x,
					y,
					ship_delta_surface_z(r.seed, sx, sy, sz, x, y, true, r.family) + sz * .05,
				}
				store.scale = {
					sx * .135 * weapon_scale,
					sy * .045 * weapon_scale,
					sz * .095 * weapon_scale,
				}
				store.material = .Machinery
				store.surface_id = 0xf3001000 + u32(side_index * 0x100 + store_index * 0x40)
				// A narrow launch shoe keeps each round mechanically tied to the
				// wing root while leaving black clearance around its exhaust.
				ship_append_local_box_faces(
					faces,
					store,
					{-store.scale[0] * .16, 0, -store.scale[2] * 1.28},
					{store.scale[0] * .82, store.scale[1] * .72, store.scale[2] * .16},
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
				ship_append_weapon_nose_faces(
					faces,
					store,
					store.scale[0] * .42,
					.82,
					camera,
					center,
					scale,
				)
				// Paired tail planes distinguish guided rounds from smooth tanks
				// even in the common top view used by tactical UI.
				store.material = .Machinery
				for fin_index in 0 ..< 2 {
					fin_side: f32 = fin_index == 0 ? -1 : 1
					ship_append_local_box_faces(
						faces,
						store,
						{-store.scale[0] * .7, fin_side * store.scale[1] * 1.22, 0},
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
			x, y := sx * .04, side * sy * .5
			store := hull
			store.position = {
				x,
				y,
				ship_delta_surface_z(r.seed, sx, sy, sz, x, y, true, r.family) + sz * .07,
			}
			store.scale = {
				sx * .25 * weapon_scale,
				sy * .07 * weapon_scale,
				sz * .12 * weapon_scale,
			}
			store.material = .Machinery
			store.surface_id = 0xf3001400 + u32(side_index * 0x80)
			// Heavy weapons ride in two continuous cradle rails rather than the
			// missiles' compact launch shoes.
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
			ship_append_weapon_nose_faces(
				faces,
				store,
				store.scale[0] * .18,
				.96,
				camera,
				center,
				scale,
			)
			store.material = .Machinery
			ship_append_local_box_faces(
				faces,
				store,
				{-store.scale[0] * .88, 0, 0},
				{store.scale[0] * .08, store.scale[1] * 1.2, store.scale[2] * 1.2},
				0x38,
				camera,
				center,
				scale,
			)
			ship_append_local_box_faces(
				faces,
				store,
				{store.scale[0] * .38, 0, 0},
				{store.scale[0] * .055, store.scale[1] * 1.16, store.scale[2] * 1.16},
				0x48,
				camera,
				center,
				scale,
			)
			continue
		}
		x, y := sx * .08, side * sy * .48
		z := ship_delta_surface_z(r.seed, sx, sy, sz, x, y, true, r.family) + sz * .07
		mount := hull
		mount.position = {x, y, z}
		mount.scale = {sx * .075, sy * .075, sz * .11}
		mount.material = .Armor
		mount.surface_id = 0xf3001800 + u32(side_index * 0x100)
		ship_append_local_box_faces(faces, mount, {}, mount.scale, 0, camera, center, scale)
		barrel := mount
		barrel.position[0] += sx * .13
		barrel.scale = {
			sx * (r.weapon_package == .Defensive_Laser ? f32(.07) : f32(.12)),
			sy * .018,
			sz * .035,
		}
		barrel.material = .Machinery
		barrel_count := r.weapon_package == .Chemical_Autocannon ? 2 : 1
		for barrel_index in 0 ..< barrel_count {
			barrel_side: f32 = barrel_count == 1 ? 0 : (barrel_index == 0 ? f32(-1) : f32(1))
			ship_append_local_box_faces(
				faces,
				barrel,
				{0, barrel_side * sy * .025, 0},
				barrel.scale,
				u32(0x10 + barrel_index * 8),
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
				{barrel.scale[0] * .08, sy * .035, sz * .065},
				u32(0x40 + collar_index * 8),
				camera,
				center,
				scale,
			)
		}
		if r.weapon_package == .Railgun_Battery {
			for fork_index in 0 ..< 2 {
				fork_side: f32 = fork_index == 0 ? -1 : 1
				ship_append_local_box_faces(
					faces,
					barrel,
					{barrel.scale[0] * .92, fork_side * sy * .035, 0},
					{barrel.scale[0] * .18, sy * .012, sz * .045},
					u32(0x70 + fork_index * 8),
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
			ship_append_local_box_faces(
				faces,
				mount,
				{-mount.scale[0] * .2, side * sy * .08, 0},
				{sx * .04, sy * .05, sz * .07},
				0xa0,
				camera,
				center,
				scale,
			)
		}
	}
}

ship_delta_edge_vertical :: proc(
	seed: u64,
	x: f32,
	index: int,
	sx, sz: f32,
) -> (
	top, bottom: f32,
) {
	// The forward third converges vertically as well as laterally. This makes the
	// side silhouette agree with the pointed planform while leaving the stern deep
	// enough to carry the recessed drive court and persistent service damage.
	shape := game.ship_construction_visual_mix(seed ~ 0x6c8e9cf570932bd5)
	forward := clamp((x / sx - .05) / .95, f32(0), f32(1))
	upper_rake := .32 + f32(shape % 4) * .035
	lower_rake := .43 + f32((shape >> 8) % 4) * .04
	top_factor := .72 + f32(index & 1) * .12 - forward * upper_rake
	bottom_factor := -1 + forward * lower_rake
	return sz * top_factor, sz * bottom_factor
}

ship_append_delta_mount_fairings :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	hull: game.Procedural_Ship_Placement,
	sx, sy, sz: f32,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
	detail := true,
) {
	// Closed deltas still carry exposed heat rejection and sensing hardware. Low,
	// armored roots make their load path into the pressure hull visible instead of
	// leaving the equipment apparently suspended just beyond the wing surface.
	budget := detail ? 8 : (r.family == .Habitat ? 0 : 1)
	for source, index in r.modules[:r.module_count] {
		if source.module != .Radiator && source.module != .Antenna do continue
		if budget <= 0 do break
		mounted := ship_closed_hull_mount_module(r, source)
		fairing := hull
		fairing.material = .Armor
		fairing.surface_id = 0xf3000400 + u32(index * 8)
		fairing.direction = {1, 0, 0}
		#partial switch source.module {
		case .Radiator:
			side: f32 = mounted.position[1] < 0 ? -1 : 1
			fairing.position = {
				mounted.position[0],
				mounted.position[1] - side * sy * .055,
				mounted.position[2],
			}
			fairing.scale = {
				max(source.scale[0] * .42, sx * .035),
				sy * .075,
				max(source.scale[2] * 1.4, sz * .11),
			}
		case .Antenna:
			vertical_side: f32 = mounted.direction[2] < 0 ? -1 : 1
			fairing.position = {
				mounted.position[0],
				mounted.position[1],
				mounted.position[2] - vertical_side * sz * .055,
			}
			fairing.scale = {
				max(source.scale[0] * .7, sx * .025),
				max(source.scale[1] * .7, sy * .025),
				sz * .075,
			}
		}
		ship_append_local_box_faces(faces, fairing, {}, fairing.scale, 0, camera, center, scale)
		budget -= 1
	}
}

ship_append_delta_history_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	hull: game.Procedural_Ship_Placement,
	sx, sy, sz: f32,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
	detail := true,
) {
	// Internal rooms disappear inside a delta's closed pressure body, but their
	// recorded damage must remain part of the ship's visible biography. Project a
	// bounded number of marks onto seeded dorsal wing stations, clear of the keel
	// and exposed-system roots.
	budget := detail ? 2 : 1
	mark_index := 0
	for source in r.modules[:r.module_count] {
		if budget <= 0 do break
		if source.service_mark == .None do continue
		shape := game.ship_construction_visual_mix(
			r.seed ~ u64(source.surface_id) ~ 0xd672b412cc31a91b,
		)
		x := -sx * .38 + sx * f32(shape % 1000) / 1000 * .70
		beam, _, _ := ship_delta_section_at_x(r.seed, sx, sy, sz, x, r.family)
		side: f32 = (shape >> 16) & 1 == 0 ? -1 : 1
		y := side * beam * (.42 + f32((shape >> 24) % 4) * .065)
		surface_z := ship_delta_surface_z(r.seed, sx, sy, sz, x, y, true, r.family)
		mark_scale := [3]f32{sx * .095, sy * .075, sz * .105}
		// The shared mark builder places its first plate one local half-height
		// above the module origin. Sink that virtual module so the plate intersects
		// the sampled armor surface instead of hovering over it.
		parity: u32 = side > 0 ? 0 : 1
		mark := hull
		mark.surface_id = 0xf3000600 + u32(mark_index) * 0x100 + parity
		mark.material = .Hull_Plate
		mark.service_mark = source.service_mark
		mark.position = {x, y, surface_z - mark_scale[2] * 1.01}
		mark.direction = {1, 0, 0}
		mark.scale = mark_scale
		ship_append_service_mark_faces(faces, mark, camera, center, scale)
		mark_index += 1; budget -= 1
	}
}

ship_delta_keel_ridge_rise :: proc(family: game.Procedural_Ship_Family, sz: f32) -> f32 {
	switch family {
	case .Strike:
		return sz * .09
	case .Fleet:
		return sz * .15
	case .Habitat:
		return sz * .22
	}
	return sz * .15
}

ship_append_delta_keel_ridge_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	seed: u64,
	family: game.Procedural_Ship_Family,
	sx, sy, sz: f32,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// The ridge makes the axial load path explicit in plan and side views. Each
	// lower corner samples the actual faceted wing, so changing family sweep or
	// seed cannot detach this structure from the pressure body.
	shape := game.ship_construction_visual_mix(seed ~ 0x291af75c63de084b)
	rear_x := -sx * (.62 + f32(shape % 4) * .025)
	front_x := sx * (.54 + f32((shape >> 8) % 4) * .025)
	rear_width := sy * (.050 + f32((shape >> 16) % 3) * .008)
	front_width := rear_width * (.42 + f32((shape >> 20) % 3) * .08)
	rise := ship_delta_keel_ridge_rise(family, sz)
	bottom := [4]f32 {
		ship_delta_surface_z(seed, sx, sy, sz, rear_x, -rear_width, true, family),
		ship_delta_surface_z(seed, sx, sy, sz, front_x, -front_width, true, family),
		ship_delta_surface_z(seed, sx, sy, sz, front_x, front_width, true, family),
		ship_delta_surface_z(seed, sx, sy, sz, rear_x, rear_width, true, family),
	}
	v := [8][3]f32 {
		{rear_x, -rear_width, bottom[0]},
		{front_x, -front_width, bottom[1]},
		{front_x, front_width, bottom[2]},
		{rear_x, rear_width, bottom[3]},
		{rear_x, -rear_width, bottom[0] + rise},
		{front_x, -front_width, bottom[1] + rise * .58},
		{front_x, front_width, bottom[2] + rise * .58},
		{rear_x, rear_width, bottom[3] + rise},
	}
	indices := [6][4]int {
		{0, 1, 2, 3},
		{4, 7, 6, 5},
		{0, 4, 5, 1},
		{3, 2, 6, 7},
		{0, 3, 7, 4},
		{1, 5, 6, 2},
	}
	normals := [6][3]f32 {
		{0, 0, -1},
		{.08, 0, 1},
		{0, -1, .12},
		{0, 1, .12},
		{-1, 0, .08},
		{1, 0, .12},
	}
	for face_index in 0 ..< 6 {
		quad: [4][3]f32
		for corner in 0 ..< 4 do quad[corner] = v[indices[face_index][corner]]
		ship_append_face(
			faces,
			quad,
			normals[face_index],
			module,
			module.surface_id + 0x300 + u32(face_index),
			camera,
			center,
			scale,
		)
	}
}

ship_append_delta_elevon_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	seed: u64,
	family: game.Procedural_Ship_Family,
	sx, sy, sz: f32,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// Paired elevons follow the swept aft wing rather than sitting in world-flat
	// space. One quad per side is enough to communicate a functional control seam
	// without spending the face budget on decorative boxes.
	shape := game.ship_construction_visual_mix(seed ~ 0xb5b93f5174e8cd21)
	rear_x := -sx * (.74 + f32(shape % 3) * .025)
	front_x := -sx * (.27 + f32((shape >> 8) % 3) * .025)
	rear_beam, _, _ := ship_delta_section_at_x(seed, sx, sy, sz, rear_x, family)
	front_beam, _, _ := ship_delta_section_at_x(seed, sx, sy, sz, front_x, family)
	lift := sz * .012
	panel := module; panel.material = .Machinery
	for side_index in 0 ..< 2 {
		side: f32 = side_index == 0 ? -1 : 1
		xy := [4][2]f32 {
			{rear_x, side * rear_beam * .46},
			{front_x, side * front_beam * .58},
			{front_x, side * front_beam * .82},
			{rear_x, side * rear_beam * .76},
		}
		quad: [4][3]f32
		for point, index in xy {
			quad[index] = {
				point[0],
				point[1],
				ship_delta_surface_z(seed, sx, sy, sz, point[0], point[1], true, family) + lift,
			}
		}
		ship_append_face(
			faces,
			quad,
			{0, 0, 1},
			panel,
			module.surface_id + 0x340 + u32(side_index),
			camera,
			center,
			scale,
		)
	}
}

ship_append_delta_citadel_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	seed: u64,
	family: game.Procedural_Ship_Family,
	sx, sy, sz: f32,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// The dorsal command/utility citadel establishes a second, readable side-view
	// mass instead of hiding a rectangular spine inside the hull crown. Its sloped
	// roof preserves the delta's forward motion and avoids a generic box-on-wing.
	shape := game.ship_construction_visual_mix(seed ~ 0x4dbf8f54aa35c9d7)
	length_factor, width_factor, height_factor := ship_delta_citadel_family_profile(family)
	rear_x := -sx * (.48 + f32(shape % 3) * .055) * length_factor
	front_x := sx * (.24 + f32((shape >> 8) % 3) * .045) * length_factor
	rear_half_width := sy * (.10 + f32((shape >> 16) % 3) * .018) * width_factor
	front_half_width := rear_half_width * (.52 + f32((shape >> 20) % 3) * .10)
	roof_inset := .62 + f32((shape >> 22) % 4) * .045
	rear_roof_width := rear_half_width * roof_inset
	front_roof_width := front_half_width * roof_inset
	rear_top := sz * (1 + (.42 + f32((shape >> 24) % 4) * .10) * height_factor)
	front_top := rear_top - sz * (.18 + f32((shape >> 32) % 3) * .07) * height_factor
	bottom := sz * .88
	v := [8][3]f32 {
		{rear_x, -rear_half_width, bottom},
		{front_x, -front_half_width, bottom},
		{front_x, front_half_width, bottom},
		{rear_x, rear_half_width, bottom},
		{rear_x, -rear_roof_width, rear_top},
		{front_x, -front_roof_width, front_top},
		{front_x, front_roof_width, front_top},
		{rear_x, rear_roof_width, rear_top},
	}
	indices := [6][4]int {
		{0, 1, 2, 3},
		{4, 7, 6, 5},
		{0, 4, 5, 1},
		{3, 2, 6, 7},
		{0, 3, 7, 4},
		{1, 5, 6, 2},
	}
	normals := [6][3]f32 {
		{0, 0, -1},
		{.25, 0, 1},
		{0, -1, .24},
		{0, 1, .24},
		{-1, 0, .1},
		{1, 0, .18},
	}
	for face_index in 0 ..< 6 {
		quad: [4][3]f32
		for corner in 0 ..< 4 do quad[corner] = v[indices[face_index][corner]]
		ship_append_face(
			faces,
			quad,
			normals[face_index],
			module,
			module.surface_id + 0x180 + u32(face_index),
			camera,
			center,
			scale,
		)
	}
}

ship_delta_citadel_family_profile :: proc(
	family: game.Procedural_Ship_Family,
) -> (
	length, width, height: f32,
) {
	switch family {
	case .Strike:
		return .76, .72, .68
	case .Fleet:
		return 1, 1, 1
	case .Habitat:
		return 1.18, 1.52, 1.42
	}
	return 1, 1, 1
}

ship_delta_planform :: proc(
	seed: u64,
	sx, sy: f32,
	family := game.Procedural_Ship_Family.Fleet,
) -> [9][2]f32 {
	// A recessed engine court breaks the otherwise rectangular trailing edge and
	// leaves the drive bank visibly seated inside the pressure boundary. Shoulder,
	// chine, and court proportions vary in separate seed domains so related delta
	// hulls keep their shared vocabulary without collapsing to one silhouette.
	// Diffusion is essential here: contact sheets intentionally use consecutive
	// construction seeds, whose undecorrelated high bits would otherwise remain
	// identical across an entire lineage row.
	shape := game.ship_construction_visual_mix(seed ~ 0x8f3f73b5cf1c9ade)
	shoulder := .34 + f32(shape % 7) * .065
	waist := .50 + f32((shape >> 8) % 6) * .07
	stern_half := .24 + f32((shape >> 16) % 5) * .045
	court_depth := .68 + f32((shape >> 24) % 4) * .055
	switch family {
	case .Strike:
		shoulder = min(shoulder * 1.12, f32(.86)); waist *= .82; stern_half *= .74
		court_depth = min(court_depth * 1.08, f32(.92))
	case .Fleet:
	case .Habitat:
		shoulder *= .82; waist = min(waist * 1.16, f32(.94))
		stern_half = min(stern_half * 1.28, f32(.58))
		court_depth *= .94
	}
	court_x := -sx * court_depth
	return {
		{-sx, -sy * stern_half},
		{-sx * shoulder, -sy},
		{sx * .12, -sy * waist},
		{sx, 0},
		{sx * .12, sy * waist},
		{-sx * shoulder, sy},
		{-sx, sy * stern_half},
		{court_x, sy * .14},
		{court_x, -sy * .14},
	}
}

ship_append_closed_architecture_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	r: ^game.Procedural_Ship_Recipe,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
	detail := true,
) {
	switch r.architecture {
	case .Single_Hull:
		ship_append_single_hull_faces(faces, r, camera, center, scale, detail)
	case .Saucer:
		// Legacy saves are normally normalized while building their recipe.
		// Treat any direct legacy recipe as a delta rather than drawing a saucer.
		ship_append_delta_hull_faces(faces, r, camera, center, scale, detail)
	case .Delta:
		ship_append_delta_hull_faces(faces, r, camera, center, scale, detail)
	case .Modular_Frame:
	}
}
