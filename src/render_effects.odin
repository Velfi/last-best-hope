package main

import rl "zelda_engine:canvas2d"
import "core:math"

LBH_EFFECT_VOLUME :: u32(1)
LBH_EFFECT_PLANET :: u32(2)
LBH_EFFECT_STAR :: u32(3)
LBH_EFFECT_GRAPH :: u32(4)
LBH_EFFECT_GAUSSIAN :: u32(5)

Sdf_Volume_Kind :: enum {
	Debris,
	Nebula,
	Radiation,
}
Sdf_Volume_Config :: struct {
	kind:           Sdf_Volume_Kind,
	density:        f32,
	seed:           f32,
	noise_scale:    f32,
	cell_smoothing: f32,
	edge_softness:  f32,
	depth:          f32,
}

Planet_Kind :: enum {
	Rocky,
	Fertile,
	Ice,
	Gas_Giant,
	Ice_Giant,
}
Planet_Mark_Color :: enum u8 {
	Neutral = 1,
	Red,
	Green,
	Blue,
	Yellow,
	Cyan,
	Magenta,
	Silicate,
	Iron_Oxide,
	Ocean,
	Water_Ice,
	Sulfur_Surface,
	Carbon,
	Methane_Ice,
	Ammonia_Ice,
	Vegetation_Surface,
	Methane_Haze,
}
Planet_Config :: struct {
	kind:              Planet_Kind,
	seed:              f32,
	phase:             f32,
	axial_tilt:        f32,
	ocean_fraction:    f32,
	atmosphere:        f32,
	cloud_cover:       f32,
	banding:           f32,
	rings:             f32,
	flattening:        f32,
	body_radius:       f32,
	ring_inner:        f32,
	ring_outer:        f32,
	ring_density:      f32,
	ring_structure:    f32,
	atmosphere_time:   f32,
	rotation_rate:     f32,
	humidity:          f32,
	circulation:       f32,
	cloud_altitude:    f32,
	cloud_lerp:        f32,
	geometric_albedo:  f32,
	cloud_composition: [4]f32,
	ground_mark:       Planet_Mark_Color,
	secondary_mark:    Planet_Mark_Color,
	cloud_mark:        Planet_Mark_Color,
	accent_mark:       Planet_Mark_Color,
}

Star_Kind :: enum {
	Main_Sequence,
	Red_Giant,
	Blue_Giant,
	White_Dwarf,
	Neutron,
	Black_Hole,
	Stripped_Star,
	Protostar,
}
Star_Config :: struct {
	kind:               Star_Kind,
	seed:               f32,
	phase:              f32,
	activity:           f32,
	spots:               f32,
	granulation:         f32,
	corona:              f32,
	rotation:            f32,
	body_radius:         f32,
	temperature_kelvin:  f32,
	luminosity_solar:    f32,
	mass_solar:          f32,
	radius_solar:        f32,
	time_seconds:        f32,
	rotation_rate:       f32,
	reduced_motion:      bool,
}

GRAPH_SAMPLE_CAPACITY :: 16
Graph_Kind :: enum {
	Sparkline,
	Line,
	Area,
	Bars,
	Step,
	Lollipop,
}
Graph_Config :: struct {
	kind:             Graph_Kind,
	values:           [GRAPH_SAMPLE_CAPACITY]f32,
	count:            int,
	minimum, maximum: f32,
	baseline:         f32,
	line_width:       f32,
	fill_alpha:       f32,
	grid_lines:       int,
}

DrawPlanet :: proc(
	bounds: rl.Rectangle,
	color: rl.Color,
	config: Planet_Config,
	atmosphere_atlas := rl.Texture{},
) {
	payload := config
	effect := rl.EffectPayload(LBH_EFFECT_PLANET, &payload)
	rl.DrawEffectQuad(bounds, color, effect, atmosphere_atlas)
}

DrawStar :: proc(
	bounds: rl.Rectangle,
	color: rl.Color,
	config: Star_Config,
	magnetic_flux_atlas := rl.Texture{},
) {
	payload := config
	effect := rl.EffectPayload(LBH_EFFECT_STAR, &payload, true)
	rl.DrawEffectQuad(bounds, color, effect, magnetic_flux_atlas)
}

DrawGraph :: proc(bounds: rl.Rectangle, color: rl.Color, config: Graph_Config) {
	if config.count <= 0 do return
	graph := config
	graph.count = clamp(graph.count, 1, GRAPH_SAMPLE_CAPACITY)
	if graph.line_width <= 0 do graph.line_width = 1
	effect := rl.EffectPayload(LBH_EFFECT_GRAPH, &graph)
	rl.DrawEffectQuad(bounds, color, effect)
}

DrawBarGraph :: proc(
	bounds: rl.Rectangle,
	values: []f32,
	color: rl.Color,
	baseline: f32 = 0,
	grid_lines: int = 0,
) {
	config := Graph_Config {
		kind = .Bars,
		count = min(len(values), GRAPH_SAMPLE_CAPACITY),
		baseline = baseline,
		line_width = 1,
		grid_lines = clamp(grid_lines, 0, 8),
	}
	for value, index in values[:config.count] do config.values[index] = value
	DrawGraph(bounds, color, config)
}

DrawSdfVolume :: proc(bounds: rl.Rectangle, color: rl.Color, config: Sdf_Volume_Config) {
	if config.density <= 0 do return
	payload := config
	effect := rl.EffectPayload(LBH_EFFECT_VOLUME, &payload)
	rl.DrawEffectQuad(bounds, color, effect)
}

DrawSdfVolumeEllipse :: proc(
	center: rl.Vector2,
	radius_x, radius_y, rotation: f32,
	color: rl.Color,
	config: Sdf_Volume_Config,
) {
	if radius_x <= 0 || radius_y <= 0 || config.density <= 0 do return
	cr, sr := f32(math.cos(f64(rotation))), f32(math.sin(f64(rotation)))
	corner := proc(center: rl.Vector2, x, y, c, s: f32) -> rl.Vector2 {
		return {center.x + x * c - y * s, center.y + x * s + y * c}
	}
	payload := config
	effect := rl.EffectPayload(LBH_EFFECT_VOLUME, &payload)
	rl.DrawEffectQuadPoints(
		corner(center, -radius_x, -radius_y, cr, sr),
		corner(center, radius_x, -radius_y, cr, sr),
		corner(center, radius_x, radius_y, cr, sr),
		corner(center, -radius_x, radius_y, cr, sr),
		color,
		effect,
	)
}

DrawGaussianSplat :: proc(
	center: rl.Vector2,
	sigma_major, sigma_minor, rotation: f32,
	color: rl.Color,
) {
	if sigma_major <= 0 || sigma_minor <= 0 || color.a == 0 do return
	dummy: u8
	effect := rl.EffectPayload(LBH_EFFECT_GAUSSIAN, &dummy)
	extent_x, extent_y := sigma_major * 3, sigma_minor * 3
	cr, sr := f32(math.cos(f64(rotation))), f32(math.sin(f64(rotation)))
	rl.DrawEffectQuadPoints(
		{center.x - extent_x * cr + extent_y * sr, center.y - extent_x * sr - extent_y * cr},
		{center.x + extent_x * cr + extent_y * sr, center.y + extent_x * sr - extent_y * cr},
		{center.x + extent_x * cr - extent_y * sr, center.y + extent_x * sr + extent_y * cr},
		{center.x - extent_x * cr - extent_y * sr, center.y - extent_x * sr + extent_y * cr},
		color,
		effect,
	)
}
