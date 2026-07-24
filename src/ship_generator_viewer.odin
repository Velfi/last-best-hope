package main

import game "../packages/game"
import "core:c"
import "core:fmt"
import "core:math"
import "core:testing"
import stbi "vendor:stb/image"
import rl "zelda_engine:canvas2d"

Ship_Generator_Camera :: struct {
	yaw, pitch, zoom: f32,
}
Ship_Project_Point :: struct {
	screen: rl.Vector2,
	depth:  f32,
}
Ship_Project_Face :: struct {
	points:                 [4]rl.Vector2,
	depths:                 [4]f32,
	world:                  [4][3]f32,
	depth:                  f32,
	normal:                 [3]f32,
	material:               game.Ship_Material_Class,
	module_id:              u32,
	surface_id:             u32,
	bounds_min, bounds_max: rl.Vector2,
	bounds_valid:           bool,
}
Ship_View_Span :: struct {
	x, z: f32,
}
ship_detail_capture_module := -1
Ship_Module_Geometry :: enum u8 {
	Angular,
	Open_Truss,
	Armor_Shield,
	Pressure_Cylinder,
	Tank_Barrel,
	Drive_Nozzle,
	Dock_Frame,
	Radiator_Array,
	Mission_Block,
	Antenna_Array,
	Bow_Wedge,
	Habitat_Ring,
}
SHIP_DRIVE_MAX_NOZZLES :: 6
SHIP_DRIVE_SEGMENTS :: 6
SHIP_DRIVE_FACES_PER_SEGMENT :: 4 // outer shell, mouth lip, chamber liner, recessed throat
SHIP_DRIVE_LENGTH_SCALE :: f32(1.42)
SHIP_DRIVE_RADIAL_SCALE :: f32(1.38)
SHIP_PRESSURE_HULL_SEGMENTS :: 10
SHIP_TANK_SEGMENTS :: 6
SHIP_TANK_STRAP_COUNT :: 2
SHIP_HABITAT_RING_SEGMENTS :: 24
SHIP_TRUSS_SEGMENT_COUNT :: 24
SHIP_AXIAL_BAY_SEGMENT_COUNT :: 20
SHIP_ARMOR_SEGMENTS :: 8

ship_module_geometry :: proc(module: game.Procedural_Ship_Module) -> Ship_Module_Geometry {
	switch module {
	case .Truss:
		return .Open_Truss
	case .Armor:
		return .Armor_Shield
	case .Pressure_Hull:
		return .Pressure_Cylinder
	case .Tank:
		return .Tank_Barrel
	case .Drive:
		return .Drive_Nozzle
	case .Dock:
		return .Dock_Frame
	case .Radiator:
		return .Radiator_Array
	case .Mission:
		return .Mission_Block
	case .Antenna:
		return .Antenna_Array
	case .Bow:
		return .Bow_Wedge
	case .Ring_Segment:
		return .Habitat_Ring
	case .Keel:
		return .Angular
	}
	return .Angular
}

ship_geometry_radial_segments :: proc(geometry: Ship_Module_Geometry) -> int {
	switch geometry {
	case .Pressure_Cylinder:
		return SHIP_PRESSURE_HULL_SEGMENTS
	case .Tank_Barrel:
		return SHIP_TANK_SEGMENTS
	case .Drive_Nozzle:
		return SHIP_DRIVE_SEGMENTS
	case .Armor_Shield:
		return SHIP_ARMOR_SEGMENTS
	case .Habitat_Ring:
		return SHIP_HABITAT_RING_SEGMENTS
	case .Angular,
	     .Open_Truss,
	     .Dock_Frame,
	     .Radiator_Array,
	     .Mission_Block,
	     .Antenna_Array,
	     .Bow_Wedge:
		return 0
	}
	return 0
}

ship_generator_default_camera :: proc() -> Ship_Generator_Camera {return {.52, .55, 1}}

ship_rotate_view :: proc(p: [3]f32, camera: Ship_Generator_Camera) -> [3]f32 {
	cy, sy := f32(math.cos(f64(camera.yaw))), f32(math.sin(f64(camera.yaw)))
	cp, sp := f32(math.cos(f64(camera.pitch))), f32(math.sin(f64(camera.pitch)))
	x := p[0] * cy - p[1] * sy; y := p[0] * sy + p[1] * cy; z := p[2]
	return {x, y * cp - z * sp, y * sp + z * cp}
}

ship_project :: proc(
	p: [3]f32,
	camera: Ship_Generator_Camera,
	center: rl.Vector2,
	scale: f32,
) -> Ship_Project_Point {
	v := ship_rotate_view(
		p,
		camera,
	); return {screen = {center.x + v[0] * scale * camera.zoom, center.y - v[2] * scale * camera.zoom}, depth = v[1]}
}

ship_material_hatch :: proc(
	material: game.Ship_Material_Class,
	light: f32,
	surface_id: u32,
) -> rl.Hatch_Config {
	c :=
		LBH_HATCH_ENGRAVING; c.invert = true; c.strength = 1; c.line_width = light > .66 ? 1.08 : .86; c.softness = .82; c.irregularity = .12 + f32(surface_id % 7) * .018
	// Every solid surface carries at least two engraving directions.  Closely
	// spaced upper layers recruit under light, producing a dense etched mass
	// without allowing the small-scale marks to swallow the outer contour.
	c.layer_count = clamp(2 + int(light * 2), 2, 4); c.spacing = 4.2
	switch material {
	case .Armor:
		c.spacing = 5; c.rotation = -.22; c.angles = {-.22, .82, -1.02, .38}; c.irregularity = .2
	case .Truss:
		c.spacing = 6.2; c.layer_count = min(c.layer_count, 3); c.rotation = .72
		c.angles = {.72, -.72, 0, 1.18}
	case .Pressure_Vessel:
		c.spacing = 4; c.rotation = .18; c.angles = {.18, 1.08, -.56, .64}
	case .Radiator:
		c.spacing = 3.2; c.line_width = .72; c.rotation = 1.15; c.angles = {1.15, -.2, .52, -.82}
	case .Drive:
		c.spacing = 3.8; c.rotation = -.62; c.angles = {-.62, .62, 0, 1.25}; c.irregularity = .28
	case .Glass:
		c.spacing = 6.8; c.layer_count = clamp(c.layer_count, 1, 2); c.rotation = .35
		c.angles = {.35, -.55, 0, 0}
	case .Machinery:
		c.spacing = 3.5; c.rotation = .48; c.angles = {.48, -.86, .08, 1.28}
	case .Hull_Plate:
		c.spacing = 4.2; c.rotation = -.48; c.angles = {-.48, .64, -1.04, .18}
	}
	return c
}

ship_material_hatch_for_view :: proc(
	material: game.Ship_Material_Class,
	light: f32,
	surface_id: u32,
	detail: bool,
) -> rl.Hatch_Config {
	c := ship_material_hatch(material, light, surface_id)
	if !detail {
		// Contact-sheet ships need black mass and a few descriptive cuts, not a
		// miniature copy of every close-view engraving layer. Preserve material
		// angles while reducing frequency and visual weight at fleet scale.
		c.layer_count = light > .58 ? 2 : 1
		c.spacing *= 1.48
		c.line_width *= .78
		c.strength *= .88
	}
	return c
}

ship_single_hull_hatch_for_view :: proc(
	material: game.Ship_Material_Class,
	light: f32,
	surface_id: u32,
	detail: bool,
) -> rl.Hatch_Config {
	c := ship_material_hatch_for_view(material, light, surface_id, detail)
	// Monocoque ships reserve dense engraving for exposed working systems. Broad
	// pressure and armor planes retain black rest, making trenches and installed
	// hardware readable instead of distributing identical noise everywhere.
	switch material {
	case .Hull_Plate:
		c.layer_count = 1; c.spacing *= detail ? f32(1.72) : f32(1.34); c.line_width *= .72
		c.strength *= .68
		c.irregularity *= .7
	case .Armor:
		c.layer_count = min(c.layer_count, 2); c.spacing *= 1.28; c.line_width *= .84
		c.strength *= .82
	case .Truss, .Pressure_Vessel, .Radiator, .Drive, .Glass, .Machinery:
	}
	return c
}

ship_material_base_tone :: proc(
	material: game.Ship_Material_Class,
	light: f32,
	detail: bool,
) -> u8 {
	// Solid faces need a quiet charcoal value against space before engraving is
	// applied. Without it, black-filled modules collapse into wireframes and the
	// generated volume is visible only from its perimeter. Material offsets stay
	// deliberately narrow so this remains monochrome rather than shaded plastic.
	base := detail ? 8 : 12; span := detail ? 10 : 14; offset := 0
	switch material {
	case .Armor:
		offset = -2
	case .Radiator:
		offset = -4
	case .Glass:
		offset = 3
	case .Machinery:
		offset = 2
	case .Hull_Plate, .Truss, .Pressure_Vessel, .Drive:
	}
	return u8(clamp(base + int(clamp(light, f32(0), f32(1)) * f32(span)) + offset, 3, 31))
}

ship_face_sort :: proc(faces: []Ship_Project_Face) {for i in 1 ..< len(faces) {v := faces[i]; j :=
			i - 1
		for j >= 0 && faces[j].depth < v.depth {faces[j + 1] = faces[j]; j -= 1}
		faces[j + 1] = v}}

ship_face_camera_facing :: proc(face: Ship_Project_Face) -> bool {
	// Projected depth increases away from the orthographic camera; normals with
	// a negative view-space depth component face the viewer. A small grazing
	// tolerance retains silhouette edges without revealing rear-face seams.
	return face.normal[1] <= .025
}

ship_face_signed_area :: proc(face: Ship_Project_Face) -> f32 {
	area: f32
	for corner in 0 ..< 4 {
		a, b := face.points[corner], face.points[(corner + 1) % 4]
		area += a.x * b.y - b.x * a.y
	}
	return area * .5
}

ship_face_winding_matches_normal :: proc(face: Ship_Project_Face) -> bool {
	// Screen Y is inverted from view-space Z; under this projection the 2D
	// shoelace sign matches the view-depth component of the outward normal.
	// Exactly grazing faces collapse in projection and carry no winding signal.
	if math.abs(face.normal[1]) < .001 do return true
	area := ship_face_signed_area(face)
	return math.abs(area) > 1e-7 && area * face.normal[1] > 0
}

ship_face_canonicalize_winding :: proc(face: ^Ship_Project_Face) {
	if math.abs(face.normal[1]) < .001 do return
	if ship_face_signed_area(face^) * face.normal[1] >= 0 do return
	face.points = {face.points[0], face.points[3], face.points[2], face.points[1]}
	face.depths = {face.depths[0], face.depths[3], face.depths[2], face.depths[1]}
	face.world = {face.world[0], face.world[3], face.world[2], face.world[1]}
}

ship_wireframe_edge_count :: proc(faces: []Ship_Project_Face, camera_facing: bool) -> int {
	count := 0
	for face_index in 0 ..< len(faces) {
		face := faces[face_index]
		if ship_face_camera_facing(face) != camera_facing do continue
		for corner in 0 ..< 4 {
			a, b :=
				face.points[corner], face.points[(corner + 1) % 4]; dx, dy := b.x - a.x, b.y - a.y
			if dx * dx + dy * dy > .2 do count += 1
		}
	}
	return count
}

ship_point_triangle_depth :: proc(p, a, b, c: rl.Vector2, da, db, dc: f32) -> (f32, bool) {
	v0x, v0y :=
		b.x - a.x, b.y - a.y; v1x, v1y := c.x - a.x, c.y - a.y; v2x, v2y := p.x - a.x, p.y - a.y
	denom := v0x * v1y - v1x * v0y
	if math.abs(denom) < 1e-6 do return 0, false
	v := (v2x * v1y - v1x * v2y) / denom; w := (v0x * v2y - v2x * v0y) / denom; u := 1 - v - w
	if u < -.001 || v < -.001 || w < -.001 do return 0, false
	return u * da + v * db + w * dc, true
}

ship_face_depth_at :: proc(face: Ship_Project_Face, p: rl.Vector2) -> (f32, bool) {
	min_x, max_x, min_y, max_y :=
		face.bounds_min.x, face.bounds_max.x, face.bounds_min.y, face.bounds_max.y
	// Generated faces cache this screen-space rejection box once. Hand-authored
	// test faces retain the fallback so small geometry tests stay convenient.
	if !face.bounds_valid {
		min_x, max_x, min_y, max_y =
			face.points[0].x, face.points[0].x, face.points[0].y, face.points[0].y
		for corner in 1 ..< 4 {min_x = min(min_x, face.points[corner].x); max_x = max(max_x, face.points[corner].x); min_y = min(min_y, face.points[corner].y); max_y = max(max_y, face.points[corner].y)}
	}
	if p.x < min_x - .001 || p.x > max_x + .001 || p.y < min_y - .001 || p.y > max_y + .001 do return 0, false
	if depth, inside := ship_point_triangle_depth(p, face.points[0], face.points[1], face.points[2], face.depths[0], face.depths[1], face.depths[2]); inside do return depth, true
	return ship_point_triangle_depth(
		p,
		face.points[0],
		face.points[2],
		face.points[3],
		face.depths[0],
		face.depths[2],
		face.depths[3],
	)
}

ship_wireframe_point_occluded :: proc(
	faces: []Ship_Project_Face,
	owner: int,
	p: rl.Vector2,
	depth: f32,
) -> bool {
	for occluder_index in 0 ..< len(faces) {
		if occluder_index == owner || !ship_face_camera_facing(faces[occluder_index]) do continue
		if surface_depth, inside := ship_face_depth_at(faces[occluder_index], p); inside && surface_depth < depth - .0005 do return true
	}
	return false
}

ship_wireframe_point_occluded_sorted :: proc(
	faces: []Ship_Project_Face,
	occluders: []int,
	owner: int,
	p: rl.Vector2,
	depth: f32,
) -> bool {
	for occluder_index in occluders {
		face := faces[occluder_index]
		if face.bounds_min.x > p.x + .001 do break
		if occluder_index == owner || face.bounds_max.x < p.x - .001 || face.bounds_min.y > p.y + .001 || face.bounds_max.y < p.y - .001 do continue
		if surface_depth, inside := ship_face_depth_at(face, p); inside && surface_depth < depth - .0005 do return true
	}
	return false
}

ship_draw_wireframe_face :: proc(
	faces: []Ship_Project_Face,
	occluders: []int,
	face_index: int,
	detail: bool,
	quiet := false,
) {
	face := faces[face_index]
	if !ship_face_camera_facing(face) do return
	front_width :=
		detail ? f32(.82) : f32(.58); front_ink := detail ? rl.Color{226, 224, 211, 150} : rl.Color{214, 212, 200, 105}
	back_alpha: u8 = 210
	if quiet {front_width *= .78; front_ink.a = detail ? 88 : 68; back_alpha = 155}
	for corner in 0 ..< 4 {
		next :=
			(corner + 1) %
			4; a, b := face.points[corner], face.points[next]; da, db := face.depths[corner], face.depths[next]; dx, dy := b.x - a.x, b.y - a.y
		distance := f32(math.sqrt(f64(dx * dx + dy * dy))); if distance < .45 do continue
		// Hidden-line testing is O(edge samples × candidate faces). Detailed 4K
		// views have wider strokes and can use a coarser cadence without exposing a
		// break; small contact-sheet ships retain the tighter sampling interval.
		cadence := detail ? f64(30) : f64(2.4); segment_cap := detail ? 8 : 96
		segments := clamp(max(1, int(math.ceil(f64(distance) / cadence))), 1, segment_cap)
		visible_run_start := -1
		for segment in 0 ..< segments {
			t0, t1 :=
				f32(segment) /
				f32(segments),
				f32(segment + 1) /
				f32(segments); tm := (t0 + t1) * .5
			mid := rl.Vector2{a.x + dx * tm, a.y + dy * tm}; mid_depth := da + (db - da) * tm
			occluded := ship_wireframe_point_occluded_sorted(
				faces,
				occluders,
				face_index,
				mid,
				mid_depth,
			)
			if !occluded && visible_run_start < 0 do visible_run_start = segment
			if visible_run_start >= 0 && (occluded || segment == segments - 1) {
				// Emit one stroke for a contiguous visible run instead of one quad per
				// 2.4 px depth sample. Besides removing artificial joints, this keeps
				// dense contact sheets inside the fixed canvas vertex budget.
				run_t0 := f32(visible_run_start) / f32(segments)
				run_end := occluded ? segment : segment + 1
				run_t1 := f32(run_end) / f32(segments)
				p0 := rl.Vector2 {
					a.x + dx * run_t0,
					a.y + dy * run_t0,
				}; p1 := rl.Vector2{a.x + dx * run_t1, a.y + dy * run_t1}
				rl.DrawLineEx(
					p0,
					p1,
					front_width + 1,
					{2, 2, 2, back_alpha},
				); rl.DrawLineEx(p0, p1, front_width, front_ink)
				visible_run_start = -1
			}
		}
	}
}

ship_module_basis :: proc(module: game.Procedural_Ship_Placement) -> (axis, side, up: [3]f32) {
	axis, side, up = {1, 0, 0}, {0, 1, 0}, {0, 0, 1}
	if module.module == .Antenna {
		up =
			module.direction; length := f32(math.sqrt(f64(up[0] * up[0] + up[1] * up[1] + up[2] * up[2])))
		if length > .001 {up[0] /= length; up[1] /= length; up[2] /= length} else {up = {0, 0, 1}}
		reference := [3]f32{1, 0, 0}; if math.abs(up[0]) > .9 do reference = {0, 1, 0}
		dot :=
			reference[0] * up[0] +
			reference[1] * up[1] +
			reference[2] *
				up[2]; axis = {reference[0] - up[0] * dot, reference[1] - up[1] * dot, reference[2] - up[2] * dot}
		axis_length := f32(
			math.sqrt(f64(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2])),
		); axis[0] /= axis_length; axis[1] /= axis_length; axis[2] /= axis_length
		side = {
			up[1] * axis[2] - up[2] * axis[1],
			up[2] * axis[0] - up[0] * axis[2],
			up[0] * axis[1] - up[1] * axis[0],
		}
		return
	}
	mounted :=
		module.module == .Truss ||
		module.module == .Armor ||
		module.module == .Pressure_Hull ||
		module.module == .Tank ||
		module.module == .Drive ||
		module.module == .Radiator ||
		module.module == .Mission ||
		module.module == .Dock
	if !mounted do return
	axis =
		module.direction; length := f32(math.sqrt(f64(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2])))
	if length >
	   .001 {axis[0] /= length; axis[1] /= length; axis[2] /= length} else {axis = {1, 0, 0}}
	reference := [3]f32{0, 0, 1}; if math.abs(axis[2]) > .9 do reference = {0, 1, 0}
	side = {
		reference[1] * axis[2] - reference[2] * axis[1],
		reference[2] * axis[0] - reference[0] * axis[2],
		reference[0] * axis[1] - reference[1] * axis[0],
	}
	side_length := f32(
		math.sqrt(f64(side[0] * side[0] + side[1] * side[1] + side[2] * side[2])),
	); side[0] /= side_length; side[1] /= side_length; side[2] /= side_length
	up = {
		axis[1] * side[2] - axis[2] * side[1],
		axis[2] * side[0] - axis[0] * side[2],
		axis[0] * side[1] - axis[1] * side[0],
	}
	return
}

ship_module_render_origin :: proc(module: game.Procedural_Ship_Placement) -> [3]f32 {
	origin := module.position; axis, _, up := ship_module_basis(module)
	// Truss positions are already segment centers. Functional branch sockets are
	// attachment planes, so move their rendered center outward by one half-length.
	if module.module == .Antenna {
		origin[0] +=
			up[0] *
			module.scale[2]; origin[1] += up[1] * module.scale[2]; origin[2] += up[2] * module.scale[2]
	} else if module.module != .Truss &&
	   math.abs(axis[0] - 1) + math.abs(axis[1]) + math.abs(axis[2]) > .001 {
		origin[0] +=
			axis[0] *
			module.scale[0]; origin[1] += axis[1] * module.scale[0]; origin[2] += axis[2] * module.scale[0]
	}
	return origin
}

ship_module_local_point :: proc(module: game.Procedural_Ship_Placement, local: [3]f32) -> [3]f32 {
	origin := ship_module_render_origin(module); axis, side, up := ship_module_basis(module)
	return {
		origin[0] + axis[0] * local[0] + side[0] * local[1] + up[0] * local[2],
		origin[1] + axis[1] * local[0] + side[1] * local[1] + up[1] * local[2],
		origin[2] + axis[2] * local[0] + side[2] * local[1] + up[2] * local[2],
	}
}

ship_module_local_normal :: proc(module: game.Procedural_Ship_Placement, local: [3]f32) -> [3]f32 {
	axis, side, up := ship_module_basis(module)
	return {
		axis[0] * local[0] + side[0] * local[1] + up[0] * local[2],
		axis[1] * local[0] + side[1] * local[1] + up[1] * local[2],
		axis[2] * local[0] + side[2] * local[1] + up[2] * local[2],
	}
}
