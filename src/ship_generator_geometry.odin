package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:c"
import "core:fmt"
import "core:math"
import "core:testing"
import stbi "vendor:stb/image"

ship_drive_nozzle_count :: proc(
	module: game.Procedural_Ship_Placement,
	family: game.Procedural_Ship_Family,
) -> int {
	base := 3 + int(family)
	return clamp(base + int(module.drive_power_tier), 2, SHIP_DRIVE_MAX_NOZZLES)
}

ship_drive_nozzle_profile :: proc(
	module: game.Procedural_Ship_Placement,
	family: game.Procedural_Ship_Family,
) -> (
	offsets: [SHIP_DRIVE_MAX_NOZZLES][2]f32,
	radii: [SHIP_DRIVE_MAX_NOZZLES]f32,
	count: int,
) {
	count = ship_drive_nozzle_count(module, family); variant := int(module.variant) % 3
	radius := f32(.4) - f32(int(family)) * .045 - f32(count - (3 + int(family))) * .018
	for nozzle in 0 ..< count {
		switch variant {
		case 0:
			// A centered vertical rack grows symmetrically around the thrust axis.
			offsets[nozzle] = {0, (f32(nozzle) - f32(count - 1) * .5) * 1.12}
		case 1:
			// A compact radial cluster adds machinery around its existing center.
			angle := math.PI * 2 * f32(nozzle) / f32(count) - math.PI * .5
			offsets[nozzle] = {f32(math.cos(angle)) * .68, f32(math.sin(angle)) * .68}
		case 2:
			// Two broad banks make power visible across the stern, with odd counts
			// retaining one smaller centerline vernier.
			if count & 1 == 1 && nozzle == count - 1 {
				offsets[nozzle] = {0, 0}; radii[nozzle] = radius * .78
				continue
			}
			pair := nozzle / 2; pairs := count / 2
			offsets[nozzle] = {
				(nozzle & 1 == 0 ? -1 : 1) * (.58 + f32(pair) * .13),
				(f32(pair) - f32(pairs - 1) * .5) * .72,
			}
		}
		radii[nozzle] = radius
	}
	return
}

ship_drive_manifold_envelope :: proc(
	module: game.Procedural_Ship_Placement,
	family: game.Procedural_Ship_Family,
) -> (offset, half_scale: [3]f32) {
	offsets, radii, count := ship_drive_nozzle_profile(module, family)
	sx := module.scale[0] * SHIP_DRIVE_LENGTH_SCALE
	mount_x := -sx - module.scale[0] * .42
	min_y, max_y := f32(1e30), -f32(1e30)
	min_z, max_z := f32(1e30), -f32(1e30)
	for nozzle in 0 ..< count {
		oy := offsets[nozzle][0] * module.scale[1] * SHIP_DRIVE_RADIAL_SCALE
		oz := offsets[nozzle][1] * module.scale[2] * SHIP_DRIVE_RADIAL_SCALE
		throat_y := module.scale[1] * radii[nozzle] * .55 * SHIP_DRIVE_RADIAL_SCALE
		throat_z := module.scale[2] * radii[nozzle] * .55 * SHIP_DRIVE_RADIAL_SCALE
		min_y = min(min_y, oy - throat_y)
		max_y = max(max_y, oy + throat_y)
		min_z = min(min_z, oz - throat_z)
		max_z = max(max_z, oz + throat_z)
	}
	margin_y := max(module.scale[1] * .12, f32(.025))
	margin_z := max(module.scale[2] * .12, f32(.025))
	// The manifold begins at the throat plane. It must not extend aft across the
	// tapered bell surfaces; short per-nozzle collars bridge that transition.
	aft_x := mount_x + module.scale[0] * .035
	forward_x := mount_x - module.scale[0] * .52
	offset = {
		(aft_x + forward_x) * .5,
		(min_y + max_y) * .5,
		(min_z + max_z) * .5,
	}
	half_scale = {
		math.abs(forward_x - aft_x) * .5,
		(max_y - min_y) * .5 + margin_y,
		(max_z - min_z) * .5 + margin_z,
	}
	return
}

ship_append_drive_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	family: game.Procedural_Ship_Family,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// Independently faceted bells expose family-scale propulsion redundancy:
	// three for strike craft, four for fleet hulls, and five for habitats.
	segments :=
		SHIP_DRIVE_SEGMENTS; sx := module.scale[0] * SHIP_DRIVE_LENGTH_SCALE; phase: f32 = math.PI / 6
	offsets, radii, count := ship_drive_nozzle_profile(module, family)
	// The nozzle's narrow forward throat must enter the drive machinery rather
	// than stop at the nominal module envelope. This overlap closes the visible
	// fabrication gap between a faceted bell and its load-bearing mount.
	mount_x := -sx - module.scale[0] * .42
	for nozzle in 0 ..< count {
		oy :=
			offsets[nozzle][0] *
			module.scale[1] *
			SHIP_DRIVE_RADIAL_SCALE; oz := offsets[nozzle][1] * module.scale[2] * SHIP_DRIVE_RADIAL_SCALE
		radius := radii[nozzle]
		for segment in 0 ..< segments {
			a0 :=
				phase +
				math.PI *
					2 *
					f32(segment) /
					f32(
						segments,
					); a1 := phase + math.PI * 2 * f32(segment + 1) / f32(segments); mid := (a0 + a1) * .5; c0, s0 := f32(math.cos(a0)), f32(math.sin(a0)); c1, s1 := f32(math.cos(a1)), f32(math.sin(a1))
			rear_x := sx
			rear0 := ship_module_local_point(
				module,
				{
					rear_x,
					oy + c0 * module.scale[1] * radius * SHIP_DRIVE_RADIAL_SCALE,
					oz + s0 * module.scale[2] * radius * SHIP_DRIVE_RADIAL_SCALE,
				},
			); rear1 := ship_module_local_point(module, {rear_x, oy + c1 * module.scale[1] * radius * SHIP_DRIVE_RADIAL_SCALE, oz + s1 * module.scale[2] * radius * SHIP_DRIVE_RADIAL_SCALE})
			front0 := ship_module_local_point(
				module,
				{
					mount_x,
					oy + c0 * module.scale[1] * radius * .55 * SHIP_DRIVE_RADIAL_SCALE,
					oz + s0 * module.scale[2] * radius * .55 * SHIP_DRIVE_RADIAL_SCALE,
				},
			); front1 := ship_module_local_point(module, {mount_x, oy + c1 * module.scale[1] * radius * .55 * SHIP_DRIVE_RADIAL_SCALE, oz + s1 * module.scale[2] * radius * .55 * SHIP_DRIVE_RADIAL_SCALE})
			base :=
				module.surface_id +
				u32(
					nozzle * segments * SHIP_DRIVE_FACES_PER_SEGMENT +
					segment * SHIP_DRIVE_FACES_PER_SEGMENT,
				)
			ship_append_face(
				faces,
				{rear0, front0, front1, rear1},
				ship_module_local_normal(module, {0, f32(math.cos(mid)), f32(math.sin(mid))}),
				module,
				base,
				camera,
				center,
				scale,
			)
			// A bright annular lip, converging chamber liner, and recessed throat make
			// each nozzle a solid manufactured bell instead of an uncapped frustum.
			inner0 := ship_module_local_point(
				module,
				{
					rear_x,
					oy + c0 * module.scale[1] * radius * .78 * SHIP_DRIVE_RADIAL_SCALE,
					oz + s0 * module.scale[2] * radius * .78 * SHIP_DRIVE_RADIAL_SCALE,
				},
			); inner1 := ship_module_local_point(module, {rear_x, oy + c1 * module.scale[1] * radius * .78 * SHIP_DRIVE_RADIAL_SCALE, oz + s1 * module.scale[2] * radius * .78 * SHIP_DRIVE_RADIAL_SCALE})
			throat_x :=
				rear_x -
				sx *
					.3; throat0 := ship_module_local_point(module, {throat_x, oy + c0 * module.scale[1] * radius * .28 * SHIP_DRIVE_RADIAL_SCALE, oz + s0 * module.scale[2] * radius * .28 * SHIP_DRIVE_RADIAL_SCALE}); throat1 := ship_module_local_point(module, {throat_x, oy + c1 * module.scale[1] * radius * .28 * SHIP_DRIVE_RADIAL_SCALE, oz + s1 * module.scale[2] * radius * .28 * SHIP_DRIVE_RADIAL_SCALE}); throat_center := ship_module_local_point(module, {throat_x, oy, oz})
			ship_append_face(
				faces,
				{rear0, rear1, inner1, inner0},
				ship_module_local_normal(module, {1, 0, 0}),
				module,
				base + 1,
				camera,
				center,
				scale,
			)
			ship_append_face(
				faces,
				{inner0, inner1, throat1, throat0},
				ship_module_local_normal(module, {0, -f32(math.cos(mid)), -f32(math.sin(mid))}),
				module,
				base + 2,
				camera,
				center,
				scale,
			)
			ship_append_face(
				faces,
				{throat_center, throat_center, throat1, throat0},
				ship_module_local_normal(module, {-1, 0, 0}),
				module,
				base + 3,
				camera,
				center,
				scale,
			)
		}
	}
	// Each bell terminates in its own compact collar. These collars provide the
	// small intentional overlap needed for a watertight joint without allowing
	// the cluster-wide enclosure to swallow or intersect the tapered bells.
	for nozzle in 0 ..< count {
		oy := offsets[nozzle][0] * module.scale[1] * SHIP_DRIVE_RADIAL_SCALE
		oz := offsets[nozzle][1] * module.scale[2] * SHIP_DRIVE_RADIAL_SCALE
		collar_aft := -sx * .94
		collar_forward := mount_x - module.scale[0] * .035
		collar := module
		collar.material = .Machinery
		collar.surface_id +=
			u32(
				count * SHIP_DRIVE_SEGMENTS * SHIP_DRIVE_FACES_PER_SEGMENT +
				nozzle * 6,
			)
		collar_radius_y :=
			module.scale[1] * radii[nozzle] * .62 * SHIP_DRIVE_RADIAL_SCALE
		collar_radius_z :=
			module.scale[2] * radii[nozzle] * .62 * SHIP_DRIVE_RADIAL_SCALE
		ship_append_local_box_faces(
			faces,
			collar,
			{(collar_aft + collar_forward) * .5, oy, oz},
			{
				math.abs(collar_forward - collar_aft) * .5,
				collar_radius_y,
				collar_radius_z,
			},
			0,
			camera,
			center,
			scale,
		)
	}
	// One machinery manifold is sized from the complete nozzle cluster. It
	// encloses every throat and carries their combined thrust into the ship,
	// rather than pretending a single-bell-sized box can support the bank.
	manifold := module
	manifold.material = .Machinery
	manifold.surface_id +=
		u32(count * SHIP_DRIVE_SEGMENTS * SHIP_DRIVE_FACES_PER_SEGMENT + count * 6)
	manifold_offset, manifold_scale :=
		ship_drive_manifold_envelope(module, family)
	ship_append_local_box_faces(
		faces,
		manifold,
		manifold_offset,
		manifold_scale,
		0,
		camera,
		center,
		scale,
	)
}

ship_append_delta_distant_drive_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	family: game.Procedural_Ship_Family,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// Contact sheets need the family-specific nozzle count and spacing, not four
	// independently hatched surfaces per bell segment. Four tapered walls, a lip,
	// and a dark recessed throat retain a recognizable bell for one quarter of the
	// detailed topology.
	offsets, radii, count := ship_drive_nozzle_profile(module, family)
	length := module.scale[0] * SHIP_DRIVE_LENGTH_SCALE
	for nozzle in 0 ..< count {
		oy := offsets[nozzle][0] * module.scale[1] * SHIP_DRIVE_RADIAL_SCALE
		oz := offsets[nozzle][1] * module.scale[2] * SHIP_DRIVE_RADIAL_SCALE
		radial_y := module.scale[1] * radii[nozzle] * SHIP_DRIVE_RADIAL_SCALE * .72
		radial_z := module.scale[2] * radii[nozzle] * SHIP_DRIVE_RADIAL_SCALE * .72
		rear_x, front_x := length, -length * .58
		rear, front: [4][3]f32
		for corner in 0 ..< 4 {
			a := math.PI * .25 + math.PI * .5 * f32(corner)
			c, s := f32(math.cos(a)), f32(math.sin(a))
			rear[corner] = ship_module_local_point(
				module,
				{rear_x, oy + c * radial_y, oz + s * radial_z},
			)
			front[corner] = ship_module_local_point(
				module,
				{front_x, oy + c * radial_y * .52, oz + s * radial_z * .52},
			)
		}
		base := u32(nozzle * 8)
		for wall in 0 ..< 4 {
			next := (wall + 1) % 4
			mid := math.PI * .25 + math.PI * .5 * (f32(wall) + .5)
			normal := ship_module_local_normal(module, {0, f32(math.cos(mid)), f32(math.sin(mid))})
			ship_append_face(
				faces,
				{rear[wall], front[wall], front[next], rear[next]},
				normal,
				module,
				module.surface_id + base + u32(wall),
				camera,
				center,
				scale,
			)
		}
		ship_append_face(
			faces,
			{rear[0], rear[1], rear[2], rear[3]},
			ship_module_local_normal(module, {1, 0, 0}),
			module,
			module.surface_id + base + 4,
			camera,
			center,
			scale,
		)
		throat := module
		throat.material = .Glass
		throat_points: [4][3]f32
		for corner in 0 ..< 4 {
			a := math.PI * .25 + math.PI * .5 * f32(corner)
			throat_points[corner] = ship_module_local_point(
				module,
				{
					rear_x - length * .015,
					oy + f32(math.cos(a)) * radial_y * .38,
					oz + f32(math.sin(a)) * radial_z * .38,
				},
			)
		}
		ship_append_face(
			faces,
			throat_points,
			ship_module_local_normal(module, {-1, 0, 0}),
			throat,
			module.surface_id + base + 5,
			camera,
			center,
			scale,
		)
	}
}

@(test)
delta_distant_drives_preserve_family_nozzle_counts_and_recessed_throats :: proc(t: ^testing.T) {
	for family in game.Procedural_Ship_Family {
		module := game.Procedural_Ship_Placement {
			module = .Drive,
			scale  = {1, .8, .8},
		}
		faces := make([dynamic]Ship_Project_Face, 0, 32, context.temp_allocator)
		ship_append_delta_distant_drive_faces(
			&faces,
			module,
			family,
			Ship_Generator_Camera{},
			rl.Vector2{},
			1,
		)
		testing.expect_value(t, len(faces), ship_drive_nozzle_count(module, family) * 6)
		testing.expect(
			t,
			len(faces) <
			ship_drive_nozzle_count(module, family) *
				SHIP_DRIVE_SEGMENTS *
				SHIP_DRIVE_FACES_PER_SEGMENT,
		)
		glass := 0
		for face in faces do if face.material == .Glass do glass += 1
		testing.expect_value(t, glass, ship_drive_nozzle_count(module, family))
	}
}

ship_drive_scatter_segments :: proc(
	module: game.Procedural_Ship_Placement,
	family: game.Procedural_Ship_Family,
	output := f32(1),
) -> (
	result: [SHIP_DRIVE_MAX_NOZZLES][2][3]f32,
	count: int,
) {
	sx := module.scale[0]; rear_x := sx * SHIP_DRIVE_LENGTH_SCALE
	offsets, radii, profile_count := ship_drive_nozzle_profile(
		module,
		family,
	); count = profile_count
	strength := clamp((output - .85) / .3, f32(0), f32(1)); output_length := .65 + strength * .7
	for nozzle in 0 ..< count {
		oy :=
			offsets[nozzle][0] *
			module.scale[1] *
			SHIP_DRIVE_RADIAL_SCALE; oz := offsets[nozzle][1] * module.scale[2] * SHIP_DRIVE_RADIAL_SCALE
		plume_size := ship_drive_plume_size(
			module,
			radii[nozzle],
		); size_length := .78 + plume_size * .55
		length :=
			sx *
			(2.15 + f32((module.surface_id + u32(nozzle) * 3) % 7) * .085) *
			output_length *
			size_length
		result[nozzle] = {
			ship_module_local_point(module, {rear_x, oy, oz}),
			ship_module_local_point(module, {rear_x + length, oy, oz}),
		}
	}
	return
}

ship_drive_plume_size :: proc(module: game.Procedural_Ship_Placement, radius: f32) -> f32 {
	// Nozzle mouth area, rather than whole-ship family, determines morphology.
	// Current generated drives span roughly .12-.27 in this aperture measure.
	aperture := radius * f32(math.sqrt(module.scale[1] * module.scale[2]))
	return clamp((aperture - .12) / .15, f32(0), f32(1))
}

ship_drive_dither_sample :: proc(
	seed: u32,
	index, count: int,
	phase: f32,
) -> (
	along, lateral: f32,
	major: bool,
) {
	// Each mark follows a stable lane through the plume. Only its distance aft
	// advances, so animation resembles matter crawling off an engraved plate
	// rather than television noise being regenerated every frame.
	x :=
		seed ~
		u32(index) *
			0x9e3779b9; x = (x ~ (x >> 16)) * 0x7feb352d; x = (x ~ (x >> 15)) * 0x846ca68b; x = x ~ (x >> 16)
	base := (f32(index) + f32(x & 255) / 256) / f32(count)
	along = f32(math.mod(f64(base + phase * .19), f64(1)))
	spread := along * along
	lateral = (f32((x >> 8) & 1023) / 511.5 - 1) * spread
	major = (x >> 20) & 7 == 0
	return
}

ship_draw_drive_scatter :: proc(
	module: game.Procedural_Ship_Placement,
	family: game.Procedural_Ship_Family,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
	detail: bool,
	phase, output: f32,
) {
	// A narrow ignition scratch breaks into stipple and short dashes as it moves
	// aft. The field is drawn beneath the ship so the bells occlude every root.
	strength := clamp(
		(output - .85) / .3,
		f32(0),
		f32(1),
	); animated_phase := phase * (.63 + strength * .74)
	segments, count := ship_drive_scatter_segments(module, family, output)
	_, radii, _ := ship_drive_nozzle_profile(module, family)
	for segment, nozzle in segments[:count] {
		plume_size := ship_drive_plume_size(module, radii[nozzle])
		a :=
			ship_project(segment[0], camera, center, scale).screen; b := ship_project(segment[1], camera, center, scale).screen
		dx, dy :=
			b.x -
			a.x,
			b.y -
			a.y; length := f32(math.sqrt(dx * dx + dy * dy)); if length < 1 do continue
		ux, uy := dx / length, dy / length; px, py := -uy, ux
		// Two interrupted scratches establish thrust direction before the wake
		// dissolves into discrete ink marks. The black gaps keep the treatment
		// from becoming a smooth sci-fi beam.
		pulses := 2 + int(plume_size * 3)
		for pulse in 0 ..< pulses {
			start :=
				.025 +
				f32(pulse) * (.115 - plume_size * .035); finish := start + .058 + plume_size * .025
			jitter := f32(math.mod(f64(animated_phase * .19 + f32(pulse) * .31), f64(.035)))
			start += jitter; finish += jitter
			p0 := V(
				a.x + dx * start,
				a.y + dy * start,
			); p1 := V(a.x + dx * finish, a.y + dy * finish)
			width :=
				detail ? f32(1.15 + plume_size * .45 - f32(pulse) * .11) : f32(.68 + plume_size * .15)
			rl.DrawLineEx(p0, p1, width, {241, 239, 222, u8(205 - pulse * 35)})
		}
		marks :=
			detail ? 30 + int(strength * 32) + int(plume_size * 20) : 13 + int(strength * 14) + int(plume_size * 8)
		for mark in 0 ..< marks {
			along, lateral, major := ship_drive_dither_sample(
				module.surface_id + u32(nozzle) * 0x45d9f3b,
				mark,
				marks,
				animated_phase,
			)
			// The wake opens quickly after the collimated core, then tapers back
			// toward its axis as its marks lose density in the far field.
			envelope := f32(math.sin(f64(along) * math.PI))
			// Small bells shed a brushy fan; large bells hold a long laminar
			// channel. Both converge to isolated flecks at the wake's end.
			shape := (1 - plume_size) * f32(math.sqrt(envelope)) + plume_size * envelope * envelope
			size_spread := 1.22 - plume_size * .46
			width :=
				(detail ? f32(8.5 + strength * 6) : f32(4.4 + strength * 2.8)) *
				shape *
				(.35 + along * .65) *
				size_spread
			p := V(
				a.x + dx * along + px * lateral * width,
				a.y + dy * along + py * lateral * width,
			)
			alpha := u8(
				clamp(155 + int(strength * 65) - int(along * (110 + strength * 45)), 42, 220),
			); radius := detail ? f32(.7 + strength * .15) : f32(.46 + strength * .08)
			if major {
				dash := (detail ? f32(3.8) : f32(2)) * max(1 - along * .45, f32(.6))
				rl.DrawLineEx(
					V(p.x - ux * dash * .5, p.y - uy * dash * .5),
					V(p.x + ux * dash * .5, p.y + uy * dash * .5),
					radius,
					{231, 229, 213, alpha},
				)
			} else {rl.DrawCircleV(p, radius, {226, 224, 209, alpha})}
		}
	}
}

ship_append_dock_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	// Docking interfaces are open rectangular portals assembled from four beams.
	ty := max(
		module.scale[1] * .22,
		f32(.12),
	); tz := max(module.scale[2] * .22, f32(.12)); vertical_half := max(module.scale[2] - tz * 2, f32(.1))
	centers := [4][3]f32 {
		{0, 0, module.scale[2] - tz},
		{0, 0, -module.scale[2] + tz},
		{0, module.scale[1] - ty, 0},
		{0, -module.scale[1] + ty, 0},
	}
	scales := [4][3]f32 {
		{module.scale[0], module.scale[1], tz},
		{module.scale[0], module.scale[1], tz},
		{module.scale[0], ty, vertical_half},
		{module.scale[0], ty, vertical_half},
	}
	for part in 0 ..< 4 do ship_append_local_box_faces(faces, module, centers[part], scales[part], u32(part * 8), camera, center, scale)
}

ship_dock_guide_local_segments :: proc(module: game.Procedural_Ship_Placement) -> [8][2][3]f32 {
	sx, sy, sz :=
		module.scale[0],
		module.scale[1],
		module.scale[2]; ix := sx; ox := sx * 1.72; iy, iz := sy * .78, sz * .78; oy, oz := sy * 1.15, sz * 1.15
	return {
		{{ix, -iy, -iz}, {ox, -oy, -oz}},
		{{ix, -iy, iz}, {ox, -oy, oz}},
		{{ix, iy, -iz}, {ox, oy, -oz}},
		{{ix, iy, iz}, {ox, oy, oz}},
		{{ox, -oy, -oz}, {ox, oy, -oz}},
		{{ox, oy, -oz}, {ox, oy, oz}},
		{{ox, oy, oz}, {ox, -oy, oz}},
		{{ox, -oy, oz}, {ox, -oy, -oz}},
	}
}

ship_draw_dock_guides :: proc(
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
	detail: bool,
) {
	width :=
		detail ? f32(1.08) : f32(.72); ink := detail ? rl.Color{226, 224, 211, 180} : rl.Color{211, 209, 197, 125}
	for segment in ship_dock_guide_local_segments(module) {
		a :=
			ship_project(ship_module_local_point(module, segment[0]), camera, center, scale).screen; b := ship_project(ship_module_local_point(module, segment[1]), camera, center, scale).screen
		rl.DrawLineEx(a, b, width + 1.15, {2, 2, 2, 225}); rl.DrawLineEx(a, b, width, ink)
	}
}

ship_append_radiator_faces :: proc(
	faces: ^[dynamic]Ship_Project_Face,
	module: game.Procedural_Ship_Placement,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) {
	variant := int(module.variant) % 3
	switch variant {
	case 0:
		// Triptych: three separated leaves on a full-width inboard header.
		panel_half_y :=
			module.scale[1] * .27; panel_x := module.scale[0] * .92; offset := module.scale[1] * .68
		for panel in 0 ..< 3 {
			y := (f32(panel) - 1) * offset
			ship_append_local_box_faces(
				faces,
				module,
				{0, y, 0},
				{panel_x, panel_half_y, module.scale[2]},
				u32(panel * 8),
				camera,
				center,
				scale,
			)
		}
		ship_append_local_box_faces(
			faces,
			module,
			{0, 0, 0},
			{module.scale[0], module.scale[1] * .075, module.scale[2]},
			24,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			module,
			{-module.scale[0] * .88, 0, 0},
			{module.scale[0] * .12, module.scale[1], module.scale[2]},
			32,
			camera,
			center,
			scale,
		)
	case 1:
		// Split wing: two broad leaves preserve a coolant/service corridor down
		// the center, with paired headers resisting deployment hinge torque.
		for side_index in 0 ..< 2 {
			side: f32 = side_index == 0 ? -1 : 1
			ship_append_local_box_faces(
				faces,
				module,
				{module.scale[0] * .06, side * module.scale[1] * .55, 0},
				{module.scale[0] * .9, module.scale[1] * .38, module.scale[2]},
				u32(side_index * 8),
				camera,
				center,
				scale,
			)
		}
		for header in 0 ..< 2 {
			x: f32 = header == 0 ? -module.scale[0] * .88 : module.scale[0] * .72
			ship_append_local_box_faces(
				faces,
				module,
				{x, 0, 0},
				{module.scale[0] * .12, module.scale[1], module.scale[2]},
				16 + u32(header * 8),
				camera,
				center,
				scale,
			)
		}
	case 2:
		// Stepped comb: four narrow vanes stagger axially around a coolant spine.
		for vane in 0 ..< 4 {
			y := (f32(vane) - 1.5) * module.scale[1] * .43
			x := (vane & 1 == 0 ? -.12 : .12) * module.scale[0]
			ship_append_local_box_faces(
				faces,
				module,
				{x, y, 0},
				{module.scale[0] * .76, module.scale[1] * .17, module.scale[2]},
				u32(vane * 8),
				camera,
				center,
				scale,
			)
		}
		ship_append_local_box_faces(
			faces,
			module,
			{-module.scale[0] * .88, 0, 0},
			{module.scale[0] * .12, module.scale[1], module.scale[2]},
			32,
			camera,
			center,
			scale,
		)
		ship_append_local_box_faces(
			faces,
			module,
			{0, 0, 0},
			{module.scale[0], module.scale[1] * .055, module.scale[2]},
			40,
			camera,
			center,
			scale,
		)
	}
}
