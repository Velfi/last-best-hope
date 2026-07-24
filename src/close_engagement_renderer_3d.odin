package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:math"
import "core:mem"
import "core:testing"
import "core:time"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"

Combat_3D_Line_Vertex :: struct {
	parameter: [2]f32,
}
Combat_3D_Line_Instance :: struct {
	start_position: [3]f32,
	end_position:   [3]f32,
	color:          [4]f32,
	// Dark-only presentation payload: anchor depth at each endpoint and
	// normalized accumulated course distance. Ordinary combat lines leave this
	// zeroed and retain the original shader path.
	dark_course:    [4]f32,
}
#assert(size_of(Combat_3D_Line_Instance) == 56)
#assert(offset_of(Combat_3D_Line_Instance,dark_course) == 40)
Combat_3D_Glyph_Vertex :: struct {
	position: [2]f32,
}
Combat_3D_Instance :: struct {
	position:     [3]f32,
	facing_scale: [4]f32,
	color:        [4]f32,
}
Combat_3D_Terrain_Mesh_Vertex :: struct {
	local_position: [3]f32,
}
Combat_3D_Terrain_Instance :: struct {
	center: [3]f32,
	shape:  [4]f32,
	style:  [4]f32,
	color:  [3]f32,
}
Combat_3D_Nebula_Instance :: struct {
	center:        [3]f32,
	radii_density: [4]f32,
	style:         [4]f32,
	color:         [3]f32,
}
#assert(size_of(Combat_3D_Nebula_Instance) == 56)
Combat_3D_Creature_GPU_Gene :: struct {
	meta:     [4]f32,
	center:   [4]f32,
	radius:   [4]f32,
	rotation_a: [4]f32,
	rotation_b: [4]f32,
	motion_a: [4]f32,
	motion_b: [4]f32,
}
Combat_3D_Creature_Cache_Entry :: struct {
	valid: bool,
	id: u64,
	genome: game.Sdf_Creature_Genome,
}
Combat_3D_Push :: struct {
	view_projection: [16]f32,
	viewport_seed:   [4]f32,
	glow:            [4]f32,
	camera_position: [4]f32,
	dark_light_position: [4]f32,
}
Dark_Render_Globals :: struct {
	// xyz are world-space positions in the renderer's 44-unit Dark scale.
	anchor_band:       [4]f32, // anchor xyz, band spacing
	fleet_depth:       [4]f32, // fleet xyz, current metric anchor depth
	environment:       [4]f32, // topology confidence, coherence, law, weather
	presentation:      [4]f32, // visual time, reduced motion, Dark enabled, crossing pulse
}
#assert(size_of(Dark_Render_Globals) == 64)
Combat_3D_State :: struct {
	initialized:                                                                    bool,
	ctx:                                                                            ^engine.Vk_Context,
	pipeline_layout:                                                                vk.PipelineLayout,
	pipeline:                                                                       [2]vk.Pipeline,
	contact_pipeline:                                                               [2]vk.Pipeline,
	terrain_pipeline:                                                               [2]vk.Pipeline,
	terrain_survey_pipeline:                                                        [2]vk.Pipeline,
	nebula_pipeline:                                                                [2]vk.Pipeline,
	glow_pipeline:                                                                  [2]vk.Pipeline,
	background_pipeline:                                                            [2]vk.Pipeline,
	vertex:                                                                         [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	glow_vertex:                                                                    [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	line_vertex:                                                                    engine.Vk_Buffer,
	glyph_vertex:                                                                   engine.Vk_Buffer,
	glyph_index:                                                                    engine.Vk_Buffer,
	instance:                                                                       [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	terrain_mesh_vertex:                                                            engine.Vk_Buffer,
	terrain_mesh_index:                                                             engine.Vk_Buffer,
	terrain_instance:                                                               [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	nebula_instance:                                                               [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	creature_gene:                                                                  [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	dark_globals:                                                                   [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
	creature_descriptor_layout:                                                     vk.DescriptorSetLayout,
	creature_descriptor_pool:                                                       vk.DescriptorPool,
	creature_descriptors:                                                           [engine.MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
	vertices:                                                                       [dynamic]Combat_3D_Line_Instance,
	glow_vertices:                                                                  [dynamic]Combat_3D_Line_Instance,
	instances:                                                                      [dynamic]Combat_3D_Instance,
	terrain_instances:                                                              [dynamic]Combat_3D_Terrain_Instance,
	nebula_instances:                                                              [dynamic]Combat_3D_Nebula_Instance,
	creature_genes:                                                                 [COMBAT_3D_MAX_CREATURE_GENES]Combat_3D_Creature_GPU_Gene,
	creature_gene_count:                                                            int,
	creature_cache:                                                                 [game.MAX_DARK_ORGANISMS]Combat_3D_Creature_Cache_Entry,
	creature_cache_uploads, creature_visible_count:                                 int,
	terrain_sphere_first, terrain_sphere_count:                                     u32,
	terrain_lane_first, terrain_lane_count:                                         u32,
	terrain_volume_count, terrain_lane_instance_first, terrain_lane_instance_count: u32,
	terrain_survey_instance_first, terrain_survey_instance_count:                   u32,
	glyph_first:                                                                    [6]u32,
	glyph_count:                                                                    [6]u32,
	instance_first:                                                                 [6]u32,
	instance_count:                                                                 [6]u32,
	capture_glow:                                                                   bool,
	glow_only:                                                                      bool,
}
combat_3d: Combat_3D_State
combat_3d_last_cpu_ms: f64
COMBAT_3D_MAX_VERTICES :: 32768
COMBAT_3D_MAX_INSTANCES :: 64
COMBAT_3D_MAX_TERRAIN_INSTANCES :: 48
COMBAT_3D_MAX_NEBULA_INSTANCES :: 12
COMBAT_3D_MAX_CREATURES :: 16
COMBAT_3D_MAX_CREATURE_GENES :: COMBAT_3D_MAX_CREATURES * game.SDF_CREATURE_MAX_GENES

// Presentation-only implicit volume kinds. Keep these synchronized with the
// constants in close_engagement_3d.slang; simulation and persistence never store
// them.
DARK_VOLUME_MEMBRANE :: f32(3)
DARK_VOLUME_WAKE_FILM :: f32(4)
DARK_VOLUME_LANTERN_GRAZER :: f32(5)
DARK_VOLUME_HUSH_COLONY :: f32(6)
DARK_VOLUME_SHEAR_HUNTER :: f32(7)
DARK_VOLUME_GRAVE_REEF :: f32(8)
DARK_VOLUME_EXPEDITION :: f32(9)
DARK_VOLUME_DOOR_ALIGNMENT :: f32(10)
DARK_VOLUME_MEMBRANE_SURVEY :: f32(11)
DARK_VOLUME_GENERATED_CREATURE :: f32(12)

// Matrices are column-major and multiply column vectors. Combat_Vec3 remains
// the simulation's right-handed world coordinate; Vulkan NDC uses Z in [0,1].
combat_3d_mat_mul :: proc(a, b: [16]f32) -> (r: [16]f32) {for c in 0 ..< 4 do for row in 0 ..< 4 {sum: f32 = 0; for k in 0 ..< 4 do sum += a[k * 4 + row] * b[c * 4 + k]; r[c * 4 + row] = sum}
	return}

combat_3d_view_projection :: proc(s: ^Ux_State, aspect: f32) -> [16]f32 {
	q :=
		s.combat_orientation; if q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w < .1 do q = combat_default_orientation()
	rx := combat_quat_rotate(
		q,
		{1, 0, 0},
	); ry := combat_quat_rotate(q, {0, 1, 0}); rz := combat_quat_rotate(q, {0, 0, 1})
	view := [16]f32 {
		rx.x,
		rx.y,
		rx.z,
		0,
		ry.x,
		ry.y,
		ry.z,
		0,
		rz.x,
		rz.y,
		rz.z,
		0,
		s.combat_pan_x / COMBAT_VIEW_SCALE,
		s.combat_pan_y / COMBAT_VIEW_SCALE,
		1800,
		1,
	}
	fov :=
		f32(math.PI / 3.27) /
		clamp(
			s.combat_zoom,
			COMBAT_ZOOM_MIN,
			COMBAT_ZOOM_MAX,
		); ys := f32(1 / math.tan(f64(fov * .5))); xs := ys / max(aspect, .01); near: f32 = 40; far: f32 = 5000
	projection := [16]f32 {
		xs,
		0,
		0,
		0,
		0,
		ys,
		0,
		0,
		0,
		0,
		far / (far - near),
		1,
		0,
		0,
		-near * far / (far - near),
		0,
	}
	return combat_3d_mat_mul(projection, view)
}

dark_3d_view_projection :: proc(s: ^Ux_State, aspect: f32) -> [16]f32 {
	q := s.dark_orientation; if q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w<.1 do q=combat_default_orientation()
	rx := combat_quat_rotate(q, {1, 0, 0}); ry := combat_quat_rotate(q, {0, 1, 0}); rz := combat_quat_rotate(q, {0, 0, 1})
	navigation:=s.campaign.passage.dark_navigation.position;entry:=s.campaign.outer_dark.continuum.anchor_position
	focus:=game.Combat_Vec3{f32(navigation[0]-entry[0])*44,f32(navigation[1]-entry[1])*44,f32(navigation[2]-entry[2])*44};rotated_focus:=combat_quat_rotate(q,focus)
	wide_fit: f32 = aspect > 2 ? .72 : 1.0
	// Leave enough negative space to read the full cross-section silhouette at
	// the default setting; wheel zoom still reaches the engraved close view.
	zoom := f32(clamp(s.dark_zoom, .65, 8.0)) * f32(1.35) * wide_fit
	// Navigation, orbit, and zoom share the fleet as their stable focus. World
	// geography retains entry-relative coordinates and moves past the centered
	// expedition instead of dragging the camera away from it.
	view := [16]f32{rx.x,rx.y,rx.z,0, ry.x,ry.y,ry.z,0, rz.x,rz.y,rz.z,0, -rotated_focus.x,-rotated_focus.y,1800-rotated_focus.z,1}
	fov := f32(math.PI / 3.27) / zoom; ys := 1 / math.tan(f32(fov * .5)); xs := ys / max(aspect, .01); near:f32=40; far:f32=5000
	projection := [16]f32{xs,0,0,0, 0,ys,0,0, 0,0,far/(far-near),1, 0,0,-near*far/(far-near),0}
	return combat_3d_mat_mul(projection, view)
}

dark_3d_camera_position :: proc(s: ^Ux_State) -> game.Combat_Vec3 {
	q := s.dark_orientation; if q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w<.1 do q=combat_default_orientation()
	navigation:=s.campaign.passage.dark_navigation.position;entry:=s.campaign.outer_dark.continuum.anchor_position
	focus:=game.Combat_Vec3{f32(navigation[0]-entry[0])*44,f32(navigation[1]-entry[1])*44,f32(navigation[2]-entry[2])*44};rotated_focus:=combat_quat_rotate(q,focus)
	translation := game.Combat_Vec3{-rotated_focus.x,-rotated_focus.y,1800-rotated_focus.z}
	return combat_quat_inverse_rotate(q, {-translation.x,-translation.y,-translation.z})
}

dark_3d_orbit :: proc(s:^Ux_State,dx,dy:f32) {
	q:=s.dark_orientation; if q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w<.1 do q=combat_default_orientation()
	yaw:=combat_quat_axis({0,0,1},dx); pitch:=combat_quat_axis({1,0,0},dy)
	candidate:=combat_quat_normalize(combat_quat_mul(pitch,combat_quat_mul(q,yaw)))
	// Keep enough face-on component for depth and pointer interpretation while
	// still permitting a severe oblique inspection of the 4D section.
	normal:=combat_quat_rotate(candidate,{0,0,1}); if normal.z>=.12 do s.dark_orientation=candidate
}

combat_3d_camera_position :: proc(s: ^Ux_State) -> game.Combat_Vec3 {
	q:=s.combat_orientation; if q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w<.1 do q=combat_default_orientation()
	translation:=game.Combat_Vec3{s.combat_pan_x/COMBAT_VIEW_SCALE,s.combat_pan_y/COMBAT_VIEW_SCALE,1800}
	return combat_quat_inverse_rotate(q,{-translation.x,-translation.y,-translation.z})
}

combat_3d_inverse_view_projection :: proc(s: ^Ux_State, aspect: f32) -> [16]f32 {
	q :=
		s.combat_orientation; if q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w < .1 do q = combat_default_orientation(); fov := f32(math.PI / 3.27) / clamp(s.combat_zoom, COMBAT_ZOOM_MIN, COMBAT_ZOOM_MAX); ys := f32(1 / math.tan(f64(fov * .5))); xs := ys / max(aspect, .01); near: f32 = 40; far: f32 = 5000; a := far / (far - near); b := -near * far / (far - near)
	inverse_projection := [16]f32 {
		1 / xs,
		0,
		0,
		0,
		0,
		1 / ys,
		0,
		0,
		0,
		0,
		0,
		1 / b,
		0,
		0,
		1,
		-a / b,
	}
	ix := combat_quat_inverse_rotate(
		q,
		{1, 0, 0},
	); iy := combat_quat_inverse_rotate(q, {0, 1, 0}); iz := combat_quat_inverse_rotate(q, {0, 0, 1}); translation := game.Combat_Vec3{s.combat_pan_x / COMBAT_VIEW_SCALE, s.combat_pan_y / COMBAT_VIEW_SCALE, 1800}; origin := combat_quat_inverse_rotate(q, {-translation.x, -translation.y, -translation.z}); inverse_view := [16]f32{ix.x, ix.y, ix.z, 0, iy.x, iy.y, iy.z, 0, iz.x, iz.y, iz.z, 0, origin.x, origin.y, origin.z, 1}; return combat_3d_mat_mul(inverse_view, inverse_projection)
}

combat_3d_transform_homogeneous :: proc(m: [16]f32, p: [4]f32) -> game.Combat_Vec3 {x :=
		m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12] * p[3]
	y := m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13] * p[3]
	z := m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14] * p[3]
	w := m[3] * p[0] + m[7] * p[1] + m[11] * p[2] + m[15] * p[3]
	return{x / w, y / w, z / w}}

combat_3d_project_to_ui :: proc(
	s: ^Ux_State,
	p: game.Combat_Vec3,
) -> (
	screen: rl.Vector2,
	visible: bool,
) {
	m := combat_3d_view_projection(
		s,
		COMBAT_VIEWPORT.width / COMBAT_VIEWPORT.height,
	); x := m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12]; y := m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13]; w := m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15]; if w <= .001 do return {}, false
	nx :=
		x /
		w; ny := y / w; screen = {COMBAT_VIEWPORT.x + (nx + 1) * .5 * COMBAT_VIEWPORT.width, COMBAT_VIEWPORT.y + (ny + 1) * .5 * COMBAT_VIEWPORT.height}; visible = nx >= -1.2 && nx <= 1.2 && ny >= -1.2 && ny <= 1.2; return
}

dark_3d_project_to_ui :: proc(s: ^Ux_State, p: game.Combat_Vec3) -> (screen: rl.Vector2, visible: bool) {
	m := dark_3d_view_projection(s, CONTINUOUS_DARK_VIEW.width / CONTINUOUS_DARK_VIEW.height)
	x := m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12]
	y := m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13]
	w := m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15]
	if w <= .001 do return {}, false
	nx, ny := x / w, y / w
	screen = {
		CONTINUOUS_DARK_VIEW.x + (nx + 1) * .5 * CONTINUOUS_DARK_VIEW.width,
		CONTINUOUS_DARK_VIEW.y + (ny + 1) * .5 * CONTINUOUS_DARK_VIEW.height,
	}
	visible = nx >= -1 && nx <= 1 && ny >= -1 && ny <= 1
	return
}

dark_camera_tracks_the_fleet_at_view_center :: proc(t:^testing.T) {
	s:=ux_state_create();defer ux_state_destroy(s);s.dark_zoom=1;s.dark_orientation=combat_default_orientation()
	s.campaign.outer_dark.continuum.anchor_position={1,2,3,4};s.campaign.passage.dark_navigation.position={3,1,6,9}
	focus:=dark_target_world(s.campaign.outer_dark.continuum.anchor_position,s.campaign.passage.dark_navigation.position)
	screen,visible:=dark_3d_project_to_ui(s,focus);testing.expect(t,visible)
	testing.expect(t,math.abs(f64(screen.x-640))<.01&&math.abs(f64(screen.y-360))<.01)
}

combat_3d_pointer_ray :: proc(
	s: ^Ux_State,
	screen: rl.Vector2,
) -> (
	origin, direction: game.Combat_Vec3,
) {
	nx :=
		(screen.x - COMBAT_VIEWPORT.x) / COMBAT_VIEWPORT.width * 2 -
		1; ny := (screen.y - COMBAT_VIEWPORT.y) / COMBAT_VIEWPORT.height * 2 - 1
	inverse := combat_3d_inverse_view_projection(
		s,
		COMBAT_VIEWPORT.width / COMBAT_VIEWPORT.height,
	); origin = combat_3d_transform_homogeneous(inverse, {nx, ny, 0, 1}); far := combat_3d_transform_homogeneous(inverse, {nx, ny, 1, 1}); direction = {far.x - origin.x, far.y - origin.y, far.z - origin.z}
	length := f32(
		math.sqrt(
			f64(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z),
		),
	); if length > .0001 {direction.x /= length; direction.y /= length; direction.z /= length}; return
}

combat_3d_ray_sphere_distance :: proc(
	origin, direction, center: game.Combat_Vec3,
	radius: f32,
) -> (
	distance: f32,
	hit: bool,
) {offset := game.Combat_Vec3{center.x - origin.x, center.y - origin.y, center.z - origin.z}
	distance = offset.x * direction.x + offset.y * direction.y + offset.z * direction.z
	if distance < 0 do return distance, false
	dx := offset.x - direction.x * distance
	dy := offset.y - direction.y * distance
	dz := offset.z - direction.z * distance
	return distance, dx * dx + dy * dy + dz * dz <= radius * radius}

combat_3d_unproject_to_plane :: proc(
	s: ^Ux_State,
	screen: rl.Vector2,
	z: f32,
) -> (
	point: game.Combat_Vec3,
	ok: bool,
) {
	origin, direction := combat_3d_pointer_ray(
		s,
		screen,
	); if math.abs(direction.z) < .0001 do return {}, false; t := (z - origin.z) / direction.z; if t < 0 do return {}, false; return {origin.x + direction.x * t, origin.y + direction.y * t, z}, true
}
combat_3d_point_on_plane :: proc(
	s: ^Ux_State,
	screen: rl.Vector2,
	z: f32,
) -> game.Combat_Vec3 {point, ok := combat_3d_unproject_to_plane(s, screen, z); if !ok do return {0, 0, z}
	return point}
