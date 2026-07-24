package main

import rl "zelda_engine:canvas2d"
import render2d "zelda_engine:render2d"
import "core:mem"
import "core:testing"


lbh_encode_canvas_batch :: proc(destination: []u8, batch_data, user_data: rawptr) -> bool {
	if len(destination) != size_of(rl.Push) || batch_data == nil do return false
	push := cast(^rl.Push)raw_data(destination)
	batch := cast(^rl.Batch)batch_data
	h := batch.hatch
	push.texture_hatch = {
		batch.texture >= 0 ? 1 : 0,
		h.enabled ? 1 : 0,
		h.filter == .Anti_Aliased ? 1 : 0,
		h.invert ? 1 : 0,
	}
	push.hatch_shape = {h.spacing * rl.HatchSpacingScale, h.line_width, h.softness, h.strength}
	push.hatch_tone = {h.contrast, h.brightness, h.rotation, f32(h.layer_count)}
	push.hatch_offset = {h.offset.x, h.offset.y, h.edge_softness, h.irregularity}
	push.hatch_angles = h.angles
	push.hatch_levels = h.thresholds
	switch batch.effect.kind {
	case LBH_EFFECT_VOLUME:
		if batch.effect.size != size_of(Sdf_Volume_Config) do return false
		v := cast(^Sdf_Volume_Config)raw_data(batch.effect.bytes[:])
		push.texture_hatch = {-1, f32(v.kind), v.density, v.seed}
		push.hatch_shape = {v.noise_scale, v.edge_softness, v.depth, v.cell_smoothing}
	case LBH_EFFECT_PLANET:
		if batch.effect.size != size_of(Planet_Config) do return false
		p := cast(^Planet_Config)raw_data(batch.effect.bytes[:])
		push.texture_hatch = {-2, f32(p.kind), p.seed, p.phase}
		push.hatch_shape = {p.axial_tilt, p.atmosphere, p.cloud_cover, p.banding}
		push.hatch_tone = {p.ocean_fraction, p.rings, p.flattening, p.body_radius}
		push.hatch_offset = {p.ring_inner, p.ring_outer, p.ring_density, p.ring_structure}
		push.hatch_angles = {batch.texture >= 0 ? 1 : 0, p.cloud_lerp, p.cloud_altitude, p.atmosphere_time * p.rotation_rate}
		push.hatch_levels = {f32(p.ground_mark), f32(p.secondary_mark), f32(p.cloud_mark), f32(p.accent_mark) + clamp(p.geometric_albedo, 0, .999) * .1}
	case LBH_EFFECT_STAR:
		if batch.effect.size != size_of(Star_Config) do return false
		s := cast(^Star_Config)raw_data(batch.effect.bytes[:])
		push.texture_hatch = {-3, f32(s.kind), s.seed, s.phase}
		push.hatch_shape = {s.activity, s.spots, s.granulation, s.corona}
		push.hatch_tone = {s.rotation, s.body_radius, s.temperature_kelvin, s.luminosity_solar}
		push.hatch_offset = {s.mass_solar, s.radius_solar, s.reduced_motion ? 0 : s.time_seconds, s.rotation_rate}
		push.hatch_angles[0] = batch.texture >= 0 ? 1 : 0
	case LBH_EFFECT_GRAPH:
		if batch.effect.size != size_of(Graph_Config) do return false
		g := cast(^Graph_Config)raw_data(batch.effect.bytes[:])
		push.texture_hatch = {-4, f32(g.kind), f32(g.count), g.line_width}
		push.hatch_shape = {g.values[0], g.values[1], g.values[2], g.values[3]}
		push.hatch_tone = {g.values[4], g.values[5], g.values[6], g.values[7]}
		push.hatch_offset = {g.values[8], g.values[9], g.values[10], g.values[11]}
		push.hatch_levels = {g.values[12], g.values[13], g.values[14], g.values[15]}
		push.hatch_angles = {g.minimum, g.maximum, g.baseline, f32(g.grid_lines) + clamp(g.fill_alpha, 0, .99)}
	case LBH_EFFECT_GAUSSIAN:
		push.texture_hatch = {-5, 0, 0, 0}
	}
	return true
}

LBH_RENDERER_DESCRIPTOR :: render2d.Renderer_Descriptor {
	pipeline = {
		vertex = {"assets/shaders/ui.vert", .Vertex, "main", "shaders/ui.vert"},
		fragment = {"assets/shaders/ui.frag", .Fragment, "main", "shaders/ui.frag"},
		post_vertex = {"assets/shaders/ui-post.vert", .Vertex, "main", "shaders/ui-post.vert"},
		post_fragment = {"assets/shaders/ui-post.frag", .Fragment, "main", "shaders/ui-post.frag"},
		push_constant_size = size_of(rl.Push),
		post_process_enabled = true,
	},
	encode_batch_payload = lbh_encode_canvas_batch,
}

LBH_HATCH_ENGRAVING :: rl.Hatch_Config {
	enabled       = true,
	filter        = .Anti_Aliased,
	spacing       = 8,
	line_width    = 1.1,
	softness      = 1,
	strength      = .9,
	contrast      = 1.15,
	edge_softness = .1,
	irregularity  = .12,
	layer_count   = 4,
	angles        = {-.7853982, .7853982, 0, 1.5707963},
	thresholds    = {.18, .38, .58, .78},
}

LBH_HATCH_OUTER_DARK :: rl.Hatch_Config {
	enabled       = true,
	filter        = .Anti_Aliased,
	spacing       = 6,
	line_width    = 1.2,
	softness      = .8,
	strength      = 1,
	contrast      = 1.45,
	brightness    = -.06,
	edge_softness = .14,
	irregularity  = .42,
	layer_count   = 4,
	angles        = {-1.012291, .4712389, -.2094395, 1.186824},
	thresholds    = {.12, .3, .52, .76},
}

@(test)
lbh_canvas_payload_encoding_remains_consumer_owned :: proc(t: ^testing.T) {
	planet := Planet_Config {
		kind = .Gas_Giant,
		seed = .25,
		phase = .75,
		atmosphere = .5,
		ground_mark = .Methane_Haze,
	}
	batch := rl.Batch {
		texture = 2,
		effect = rl.EffectPayload(LBH_EFFECT_PLANET, &planet),
	}
	push: rl.Push
	bytes := mem.slice_ptr(cast([^]u8)&push, size_of(push))
	testing.expect(t, lbh_encode_canvas_batch(bytes, &batch, nil))
	testing.expect_value(t, push.texture_hatch[0], f32(-2))
	testing.expect_value(t, push.texture_hatch[1], f32(Planet_Kind.Gas_Giant))
	testing.expect_value(t, push.hatch_shape[1], f32(.5))
}
