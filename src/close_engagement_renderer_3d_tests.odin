package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:math"
import "core:mem"
import "core:testing"
import "core:time"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"

@(test)
combat_3d_projection_round_trip :: proc(t: ^testing.T) {
	s := new(
		Ux_State,
	); defer ux_state_destroy(s); s.combat_zoom = 1; s.combat_orientation = combat_default_orientation()
	points := [3]game.Combat_Vec3{{0, 0, 0}, {-420, 180, -80}, {360, -240, 90}}
	for expected_index := 0; expected_index < len(points); expected_index += 1 {expected := points[expected_index]; screen, visible := combat_3d_project_to_ui(s, expected)
		testing.expect(t, visible)
		actual, ok := combat_3d_unproject_to_plane(s, screen, expected.z)
		testing.expect(t, ok)
		testing.expect(t, math.abs(f64(actual.x - expected.x)) < .01)
		testing.expect(t, math.abs(f64(actual.y - expected.y)) < .01)}
}

@(test)
combat_3d_viewport_edge_rays_round_trip :: proc(t: ^testing.T) {s := ux_state_create(); defer ux_state_destroy(s)
	s.combat_zoom = 1
	s.combat_orientation = combat_default_orientation()
	screens := [4]rl.Vector2 {
		{COMBAT_VIEWPORT.x + 1, COMBAT_VIEWPORT.y + 1},
		{COMBAT_VIEWPORT.x + COMBAT_VIEWPORT.width - 1, COMBAT_VIEWPORT.y + 1},
		{COMBAT_VIEWPORT.x + 1, COMBAT_VIEWPORT.y + COMBAT_VIEWPORT.height - 1},
		{
			COMBAT_VIEWPORT.x + COMBAT_VIEWPORT.width - 1,
			COMBAT_VIEWPORT.y + COMBAT_VIEWPORT.height - 1,
		},
	}
	for expected_index := 0; expected_index < len(screens); expected_index += 1 {expected := screens[expected_index]
		world, ok := combat_3d_unproject_to_plane(s, expected, 0)
		testing.expect(t, ok)
		actual, visible := combat_3d_project_to_ui(s, world)
		testing.expect(t, visible)
		testing.expect(t, math.abs(f64(actual.x - expected.x)) < .01)
		testing.expect(t, math.abs(f64(actual.y - expected.y)) < .01)}}

@(test)
combat_3d_close_zoom_projection_round_trip :: proc(t: ^testing.T) {s := ux_state_create(); defer ux_state_destroy(s)
	s.combat_zoom = COMBAT_ZOOM_MAX
	s.combat_orientation = combat_default_orientation()
	expected := game.Combat_Vec3{80, -45, 30}
	screen, visible := combat_3d_project_to_ui(s, expected)
	testing.expect(t, visible)
	actual, ok := combat_3d_unproject_to_plane(s, screen, expected.z)
	testing.expect(t, ok)
	testing.expect(t, math.abs(f64(actual.x - expected.x)) < .01)
	testing.expect(t, math.abs(f64(actual.y - expected.y)) < .01)}

@(test)
combat_3d_orbit_keeps_command_plane_facing_camera :: proc(t: ^testing.T) {
	s := ux_state_create(); defer ux_state_destroy(s); s.combat_orientation = combat_default_orientation()
	for _ in 0 ..< 1000 do combat_orbit(s, .07, .07)
	normal := combat_quat_rotate(s.combat_orientation, {0, 0, 1})
	testing.expect(t, normal.z >= COMBAT_MIN_PLANE_FACING)
	_, visible := combat_3d_project_to_ui(s, {0, 0, COMBAT_GRID_Z}); testing.expect(t, visible)
}

@(test)
combat_3d_ray_sphere_picking_handles_near_far_and_miss :: proc(t: ^testing.T) {origin :=
		game.Combat_Vec3{0, 0, -100}
	direction := game.Combat_Vec3{0, 0, 1}
	near, near_hit := combat_3d_ray_sphere_distance(origin, direction, {0, 0, 0}, 12)
	far, far_hit := combat_3d_ray_sphere_distance(origin, direction, {0, 0, 900}, 20)
	_, miss := combat_3d_ray_sphere_distance(origin, direction, {30, 0, 0}, 12)
	testing.expect(t, near_hit && far_hit && !miss)
	testing.expect(t, near < far)}

combat_3d_role_index :: proc(role: game.Combat_Role) -> int {switch role {case .Fighter:
		return 0; case .Bomber:
		return 1; case .Corvette:
		return 2; case .Recovery:
		return 3; case .Carrier:
		return 4; case .Capital:
		return 5}; return 0}

combat_3d_glyph_line :: proc(
	vertices: ^[dynamic]Combat_3D_Glyph_Vertex,
	x0, y0, x1, y1: f32,
) {append(vertices, Combat_3D_Glyph_Vertex{{x0, y0}}, Combat_3D_Glyph_Vertex{{x1, y1}})}

combat_3d_build_glyph_meshes :: proc() -> [dynamic]Combat_3D_Glyph_Vertex {
	vertices := make([dynamic]Combat_3D_Glyph_Vertex, 0, 96)
	for role in 0 ..< 6 {
		combat_3d.glyph_first[role] = u32(len(vertices))
		switch role {
		case 0:
			combat_3d_glyph_line(&vertices, -1, -.65, 1, 0); combat_3d_glyph_line(
				&vertices,
				1,
				0,
				-1,
				.65,
			)
			combat_3d_glyph_line(&vertices, -1, .65, -1, -.65)
		case 1:
			combat_3d_glyph_line(&vertices, -1, 0, 0, -.75); combat_3d_glyph_line(
				&vertices,
				0,
				-.75,
				1,
				0,
			)
			combat_3d_glyph_line(&vertices, 1, 0, 0, .75)
			combat_3d_glyph_line(&vertices, 0, .75, -1, 0)
			combat_3d_glyph_line(&vertices, -.3, -.45, .3, .45)
		case 2:
			combat_3d_glyph_line(&vertices, -1, -.55, .45, -.55); combat_3d_glyph_line(
				&vertices,
				.45,
				-.55,
				1,
				0,
			)
			combat_3d_glyph_line(&vertices, 1, 0, .45, .55)
			combat_3d_glyph_line(&vertices, .45, .55, -1, .55)
			combat_3d_glyph_line(&vertices, -1, .55, -1, -.55)
		case 3:
			for segment in 0 ..< 20 {
				a := f32(segment) / 20 * 2 * math.PI
				b := f32(segment + 1) / 20 * 2 * math.PI
				combat_3d_glyph_line(
					&vertices,
					f32(math.cos(f64(a))),
					f32(math.sin(f64(a))),
					f32(math.cos(f64(b))),
					f32(math.sin(f64(b))),
				)}
			combat_3d_glyph_line(&vertices, -.55, 0, .55, 0)
			combat_3d_glyph_line(&vertices, 0, -.55, 0, .55)
		case 4:
			combat_3d_glyph_line(&vertices, -1, -.5, 1, -.5); combat_3d_glyph_line(
				&vertices,
				1,
				-.5,
				1,
				.5,
			)
			combat_3d_glyph_line(&vertices, 1, .5, -1, .5)
			combat_3d_glyph_line(&vertices, -1, .5, -1, -.5)
			combat_3d_glyph_line(&vertices, -.55, 0, .65, 0)
		case 5:
			combat_3d_glyph_line(&vertices, -1, -.45, .7, -.45); combat_3d_glyph_line(
				&vertices,
				.7,
				-.45,
				1,
				0,
			)
			combat_3d_glyph_line(&vertices, 1, 0, .7, .45)
			combat_3d_glyph_line(&vertices, .7, .45, -1, .45)
			combat_3d_glyph_line(&vertices, -1, .45, -1, -.45)
			combat_3d_glyph_line(&vertices, -.65, -.18, .6, -.18)
			combat_3d_glyph_line(&vertices, -.65, .18, .6, .18)
		}
		combat_3d.glyph_count[role] = u32(len(vertices)) - combat_3d.glyph_first[role]
	}
	return vertices
}

combat_3d_append_line :: proc(a, b: [3]f32, color: [4]f32) {if len(combat_3d.vertices) + len(combat_3d.glow_vertices) + 2 > COMBAT_3D_MAX_VERTICES / 2 do return
	line := Combat_3D_Line_Instance{start_position=a,end_position=b,color=color}
	if !combat_3d.glow_only do append(&combat_3d.vertices, line)
	if combat_3d.capture_glow do append(&combat_3d.glow_vertices, line)}

combat_3d_append_dark_course_line :: proc(
	a, b: [3]f32,
	color: [4]f32,
	depth_a, depth_b, u_a, u_b: f32,
) {
	if len(combat_3d.vertices)+len(combat_3d.glow_vertices)+2>COMBAT_3D_MAX_VERTICES/2 do return
	line:=Combat_3D_Line_Instance{
		start_position=a,end_position=b,color=color,
		dark_course={depth_a,depth_b,u_a,u_b},
	}
	if !combat_3d.glow_only do append(&combat_3d.vertices,line)
	if combat_3d.capture_glow do append(&combat_3d.glow_vertices,line)
}

combat_3d_append_ring :: proc(
	center: game.Combat_Vec3,
	radius: f32,
	color: [4]f32,
	segments := 32,
) {
	for segment in 0 ..< segments {
		a := f32(segment) / f32(segments) * 2 * math.PI
		b :=
			f32(segment + 1) / f32(segments) * 2 * math.PI
		combat_3d_append_line(
			{
				center.x + f32(math.cos(f64(a))) * radius,
				center.y + f32(math.sin(f64(a))) * radius,
				center.z,
			},
			{
				center.x + f32(math.cos(f64(b))) * radius,
				center.y + f32(math.sin(f64(b))) * radius,
				center.z,
			},
			color,
		)}}

combat_3d_append_orbit :: proc(
	center: game.Combat_Vec3,
	radius: f32,
	color: [4]f32,
	plane: int,
	segments := 32,
) {
	for segment in 0 ..< segments {
		a :=
			f32(segment) /
			f32(segments) *
			2 *
			math.PI; b := f32(segment + 1) / f32(segments) * 2 * math.PI
		ca :=
			f32(math.cos(f64(a))) *
			radius; sa := f32(math.sin(f64(a))) * radius; cb := f32(math.cos(f64(b))) * radius; sb := f32(math.sin(f64(b))) * radius
		p0, p1: game.Combat_Vec3
		switch plane {
		case 0:
			p0 = {center.x + ca, center.y + sa, center.z}
			p1 = {center.x + cb, center.y + sb, center.z}
		case 1:
			p0 = {center.x + ca, center.y, center.z + sa}
			p1 = {center.x + cb, center.y, center.z + sb}
		case 2:
			p0 = {center.x, center.y + ca, center.z + sa}
			p1 = {center.x, center.y + cb, center.z + sb}
		}
		combat_3d_append_line({p0.x, p0.y, p0.z}, {p1.x, p1.y, p1.z}, color)
	}
}

combat_3d_append_volume :: proc(
	center: game.Combat_Vec3,
	radius, half_height: f32,
	color: [4]f32,
) {
	for layer in -1 ..= 1 {
		p := center
		p.z += f32(layer) * half_height
		combat_3d_append_ring(
			p,
			radius * (layer == 0 ? 1 : .72),
			color,
			36,
		)}
	for spoke in 0 ..< 8 {
		angle := f32(spoke) / 8 * 2 * math.PI
		x :=
			center.x + f32(math.cos(f64(angle))) * radius * .72
		y := center.y + f32(math.sin(f64(angle))) * radius * .72
		combat_3d_append_line(
			{x, y, center.z - half_height},
			{x, y, center.z + half_height},
			color,
		)}}

combat_3d_append_sphere :: proc(
	center: game.Combat_Vec3,
	radius: f32,
	color: [4]f32,
) {combat_3d_append_orbit(center, radius, color, 0, 40); combat_3d_append_orbit(
		center,
		radius,
		color,
		1,
		40,
	)
	combat_3d_append_orbit(center, radius, color, 2, 40)}

combat_3d_build_terrain_meshes :: proc(
) -> (
	vertices: [dynamic]Combat_3D_Terrain_Mesh_Vertex,
	indices: [dynamic]u32,
) {
	vertices = make(
		[dynamic]Combat_3D_Terrain_Mesh_Vertex,
		0,
		256,
	); indices = make([dynamic]u32, 0, 1024); latitudes := 6; longitudes := 24
	for latitude in 0 ..= latitudes {lat := -f32(math.PI) * .5 + f32(latitude) / f32(latitudes) * f32(math.PI); cos_lat := f32(math.cos(f64(lat))); for longitude in 0 ..= longitudes {lon := f32(longitude) / f32(longitudes) * 2 * math.PI; append(&vertices, Combat_3D_Terrain_Mesh_Vertex{{cos_lat * f32(math.cos(f64(lon))), cos_lat * f32(math.sin(f64(lon))), f32(math.sin(f64(lat)))}})}}
	combat_3d.terrain_sphere_first = u32(
		len(indices),
	); for latitude in 0 ..< latitudes do for longitude in 0 ..< longitudes {a := u32(latitude * (longitudes + 1) + longitude); b := a + 1; c := u32((latitude + 1) * (longitudes + 1) + longitude + 1); d := c - 1; append(&indices, a, b, c, a, c, d)}; combat_3d.terrain_sphere_count = u32(len(indices)) - combat_3d.terrain_sphere_first
	lane_vertex := u32(
		len(vertices),
	); append(&vertices, Combat_3D_Terrain_Mesh_Vertex{{0, 0, 0}}); segments := 48; for segment in 0 ..< segments {angle := f32(segment) / f32(segments) * 2 * math.PI; append(&vertices, Combat_3D_Terrain_Mesh_Vertex{{f32(math.cos(f64(angle))), f32(math.sin(f64(angle))), 0}})}; combat_3d.terrain_lane_first = u32(len(indices)); for segment in 0 ..< segments {append(&indices, lane_vertex, lane_vertex + 1 + u32(segment), lane_vertex + 1 + u32((segment + 1) % segments))}; combat_3d.terrain_lane_count = u32(len(indices)) - combat_3d.terrain_lane_first; return
}

combat_3d_append_terrain_volume :: proc(
	center: game.Combat_Vec3,
	radius, half_height: f32,
	kind, seed, noise, density: f32,
	color: [4]f32,
	sensor_confidence: f32 = 1,
) {if len(combat_3d.terrain_instances) >= COMBAT_3D_MAX_TERRAIN_INSTANCES do return; append(
		&combat_3d.terrain_instances,
		Combat_3D_Terrain_Instance {
			{center.x, center.y, center.z},
			{radius, half_height, kind, seed},
			{noise, density, color[3], sensor_confidence},
			{color[0], color[1], color[2]},
		},
	)}

combat_3d_append_lane_decal :: proc(
	center: game.Combat_Vec3,
	radius, seed: f32,
	color: [4]f32,
) {if len(combat_3d.terrain_instances) >= COMBAT_3D_MAX_TERRAIN_INSTANCES do return; append(
		&combat_3d.terrain_instances,
		Combat_3D_Terrain_Instance {
			{center.x, center.y, center.z},
			{radius, 0, 2, seed},
			{2.2, .5, color[3], 0},
			{color[0], color[1], color[2]},
		},
	)}

combat_3d_sort_terrain_volumes :: proc(s: ^Ux_State) {
	for i in 1 ..< int(combat_3d.terrain_volume_count) {
		value := combat_3d.terrain_instances[i]
		value_depth :=
			combat_quat_rotate(s.combat_orientation, {value.center[0], value.center[1], value.center[2]}).z
		j := i
		for j > 0 {other := combat_3d.terrain_instances[j - 1]; other_depth :=
				combat_quat_rotate(s.combat_orientation, {other.center[0], other.center[1], other.center[2]}).z
			if other_depth >= value_depth do break
			combat_3d.terrain_instances[j] = other
			j -= 1}
		combat_3d.terrain_instances[j] = value}}

combat_3d_unit_line :: proc(u: ^game.Combat_Unit, x0, y0, x1, y1: f32, color: [4]f32) {c := f32(
		math.cos(f64(u.facing)),
	)
	s := f32(math.sin(f64(u.facing)))
	a := [3]f32{u.position.x + x0 * c - y0 * s, u.position.y + x0 * s + y0 * c, u.position.z}
	b := [3]f32{u.position.x + x1 * c - y1 * s, u.position.y + x1 * s + y1 * c, u.position.z}
	combat_3d_append_line(a, b, color)}

combat_3d_append_hull_volume :: proc(u: ^game.Combat_Unit, size: f32, color: [4]f32) {
	c := f32(math.cos(f64(u.facing))); s := f32(math.sin(f64(u.facing)))
	point := proc(u: ^game.Combat_Unit, c, s, x, y, z: f32) -> [3]f32 {return{
			u.position.x + x * c - y * s,
			u.position.y + x * s + y * c,
			u.position.z + z,
		}}
	nose := point(
		u,
		c,
		s,
		size * 1.15,
		0,
		0,
	); tail := point(u, c, s, -size * .9, 0, 0); port := point(u, c, s, -size * .18, -size * .7, 0); starboard := point(u, c, s, -size * .18, size * .7, 0)
	crest := point(
		u,
		c,
		s,
		-size * .05,
		0,
		size * .8,
	); keel := point(u, c, s, -size * .05, 0, -size * .42); hull_color := [4]f32{color[0], color[1], color[2], .76}
	corners := [4][3]f32 {
		nose,
		tail,
		port,
		starboard,
	}; for corner in corners {combat_3d_append_line(corner, crest, hull_color); combat_3d_append_line(corner, keel, {hull_color[0], hull_color[1], hull_color[2], .48})}
	combat_3d_append_line(
		nose,
		port,
		hull_color,
	); combat_3d_append_line(port, tail, hull_color); combat_3d_append_line(tail, starboard, hull_color); combat_3d_append_line(starboard, nose, hull_color)
}
