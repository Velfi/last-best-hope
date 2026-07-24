package main

import rl "zelda_engine:canvas2d"
import "core:fmt"
import "core:math"
import "core:sync"
import "core:testing"
import "core:time"
import benchmark "zelda_engine:benchmark"

ATM_FACE_SIZE :: 32
ATM_FACE_CELLS :: ATM_FACE_SIZE * ATM_FACE_SIZE
ATM_CELL_COUNT :: ATM_FACE_CELLS * 6
ATM_STEP_SECONDS :: f32(0.5)
ATM_SPINUP_STEPS :: 48
ATM_CACHE_SIZE :: 4
ATM_EPOCH_STEPS :: i64(240)

Atmosphere_Params :: struct {
	kind:                                    Planet_Kind,
	seed:                                    u64,
	atmosphere, cloud_cover, ocean_fraction: f32,
	rotation_rate, humidity, circulation:    f32,
	cloud_composition:                       [4]f32,
}

Atmosphere_Field :: struct {
	pressure, vapor, cloud, temperature, vorticity: [ATM_CELL_COUNT]f32,
	wind:                                           [ATM_CELL_COUNT][3]f32,
	composition:                                    [4][ATM_CELL_COUNT]f32,
}

Atmosphere_State :: struct {
	ready:          bool,
	params:         Atmosphere_Params,
	step:           i64,
	previous_cloud: [ATM_CELL_COUNT]f32,
	field, scratch: Atmosphere_Field,
}

Atmosphere_Cache_Entry :: struct {
	state:         Atmosphere_State,
	texture:       rl.Texture,
	uploaded_step: i64,
	stamp:         u64,
}
when ODIN_TEST {
	// Odin executes tests concurrently. Keep presentation cache fixtures local
	// to their runner thread so cache eviction and atlas packing cannot alias
	// another atmosphere test. The production renderer remains single-threaded.
	@(thread_local)
	atmosphere_cache: [ATM_CACHE_SIZE]Atmosphere_Cache_Entry
	@(thread_local)
	atmosphere_stamp: u64
	@(thread_local)
	atmosphere_pixels: [ATM_CELL_COUNT * 8]u8
} else {
	atmosphere_cache: [ATM_CACHE_SIZE]Atmosphere_Cache_Entry
	atmosphere_stamp: u64
	atmosphere_pixels: [ATM_CELL_COUNT * 8]u8
}
atmosphere_topology_once: sync.Once
atmosphere_directions, atmosphere_east, atmosphere_north: [ATM_CELL_COUNT][3]f32
atmosphere_neighbors: [ATM_CELL_COUNT][4]int
atmosphere_sun, atmosphere_jet_terrestrial, atmosphere_jet_gas, atmosphere_jet_ice: [ATM_CELL_COUNT]f32

atm_hash :: proc(x: u64) -> u64 {
	v := x + 0x9e3779b97f4a7c15
	v = (v ~ (v >> 30)) * 0xbf58476d1ce4e5b9
	v = (v ~ (v >> 27)) * 0x94d049bb133111eb
	return v ~ (v >> 31)
}
atm_unit :: proc(seed: u64, index, lane: int) -> f32 {
	v := atm_hash(seed ~ u64(index) * 0x632be59bd9b4e019 ~ u64(lane) * 0x9e3779b97f4a7c15)
	return f32(v >> 40) / f32(1 << 24)
}
atm_normalize :: proc(v: [3]f32) -> [3]f32 {
	l := f32(math.sqrt(f64(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])))
	if l < 1e-6 do return {0, 1, 0}
	return {v[0] / l, v[1] / l, v[2] / l}
}
atm_dot :: proc(a, b: [3]f32) -> f32 {return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]}
atm_cross :: proc(a, b: [3]f32) -> [3]f32 {return{
		a[1] * b[2] - a[2] * b[1],
		a[2] * b[0] - a[0] * b[2],
		a[0] * b[1] - a[1] * b[0],
	}}
atm_dir :: proc(face, x, y: int) -> [3]f32 {
	u :=
		(f32(x) + .5) / f32(ATM_FACE_SIZE) * 2 - 1; v := (f32(y) + .5) / f32(ATM_FACE_SIZE) * 2 - 1
	switch face {
	case 0:
		return atm_normalize({1, -v, -u})
	case 1:
		return atm_normalize({-1, -v, u})
	case 2:
		return atm_normalize({u, 1, v})
	case 3:
		return atm_normalize({u, -1, -v})
	case 4:
		return atm_normalize({u, -v, 1})
	case:
		return atm_normalize({-u, -v, -1})
	}
}
atm_index_from_dir :: proc(d: [3]f32) -> int {
	ax, ay, az := abs(d[0]), abs(d[1]), abs(d[2]); face := 0; u, v: f32
	if ax >= ay &&
	   ax >=
		   az {if d[0] >= 0 {face = 0; u = -d[2] / ax; v = -d[1] / ax} else {face = 1; u = d[2] / ax; v = -d[1] / ax}} else if ay >= az {if d[1] >= 0 {face = 2; u = d[0] / ay; v = d[2] / ay} else {face = 3; u = d[0] / ay; v = -d[2] / ay}} else {if d[2] >= 0 {face = 4; u = d[0] / az; v = -d[1] / az} else {face = 5; u = -d[0] / az; v = -d[1] / az}}
	x := clamp(int((u * .5 + .5) * f32(ATM_FACE_SIZE)), 0, ATM_FACE_SIZE - 1)
	y := clamp(int((v * .5 + .5) * f32(ATM_FACE_SIZE)), 0, ATM_FACE_SIZE - 1)
	return face * ATM_FACE_CELLS + y * ATM_FACE_SIZE + x
}
atm_sample :: proc(values: ^[ATM_CELL_COUNT]f32, d: [3]f32) -> f32 {return(
		values[atm_index_from_dir(d)] \
	)}
atm_sample_wind :: proc(values: ^[ATM_CELL_COUNT][3]f32, d: [3]f32) -> [3]f32 {return(
		values[atm_index_from_dir(d)] \
	)}
atm_backtrace :: proc(d, w: [3]f32, sign: f32) -> [3]f32 {
	return {d[0] + w[0] * sign * .021, d[1] + w[1] * sign * .021, d[2] + w[2] * sign * .021}
}

atmosphere_initialize_topology :: proc() {
	for face in 0 ..< 6 {for y in 0 ..< ATM_FACE_SIZE {for x in 0 ..< ATM_FACE_SIZE {
				i :=
					face * ATM_FACE_CELLS +
					y * ATM_FACE_SIZE +
					x; d := atm_dir(face, x, y); east := atm_normalize(atm_cross({0, 1, 0}, d)); north := atm_normalize(atm_cross(d, east)); epsilon := f32(.032)
				atmosphere_directions[i] =
					d; atmosphere_east[i] = east; atmosphere_north[i] = north
				atmosphere_sun[i] = clamp(atm_dot(d, atm_normalize({-.68, -.36, .64})), 0, 1)
				atmosphere_jet_terrestrial[i] = f32(math.sin(f64(d[1] * 5)))
				atmosphere_jet_gas[i] = f32(math.sin(f64(d[1] * 17)))
				atmosphere_jet_ice[i] = f32(math.sin(f64(d[1] * 8)))
				atmosphere_neighbors[i][0] = atm_index_from_dir(
					{d[0] + east[0] * epsilon, d[1] + east[1] * epsilon, d[2] + east[2] * epsilon},
				)
				atmosphere_neighbors[i][1] = atm_index_from_dir(
					{d[0] - east[0] * epsilon, d[1] - east[1] * epsilon, d[2] - east[2] * epsilon},
				)
				atmosphere_neighbors[i][2] = atm_index_from_dir(
					{
						d[0] + north[0] * epsilon,
						d[1] + north[1] * epsilon,
						d[2] + north[2] * epsilon,
					},
				)
				atmosphere_neighbors[i][3] = atm_index_from_dir(
					{
						d[0] - north[0] * epsilon,
						d[1] - north[1] * epsilon,
						d[2] - north[2] * epsilon,
					},
				)
			}}}
}
atmosphere_prepare_topology :: proc() {sync.once_do(
		&atmosphere_topology_once,
		atmosphere_initialize_topology,
	)}

atmosphere_defaults :: proc(config: Planet_Config, seed: u64) -> Atmosphere_Params {
	p := Atmosphere_Params {
		kind           = config.kind,
		seed           = seed,
		atmosphere     = config.atmosphere,
		cloud_cover    = config.cloud_cover,
		ocean_fraction = config.ocean_fraction,
	}
	p.cloud_composition = config.cloud_composition
	total: f32; for value in p.cloud_composition do total += value
	if total <=
	   1e-6 {p.cloud_composition = {1, 0, 0, 0}} else {for &value in p.cloud_composition do value = max(value, 0) / total}
	p.rotation_rate =
		config.rotation_rate; if p.rotation_rate <= 0 do p.rotation_rate = config.kind == .Gas_Giant ? 1.45 : config.kind == .Ice_Giant ? .92 : 1
	p.humidity =
		config.humidity; if p.humidity <= 0 do p.humidity = config.kind == .Fertile ? .72 : config.kind == .Gas_Giant ? .9 : config.kind == .Ice_Giant ? .55 : config.kind == .Ice ? .24 : .12
	p.circulation =
		config.circulation; if p.circulation <= 0 do p.circulation = config.kind == .Gas_Giant ? 1 : config.kind == .Ice_Giant ? .68 : config.kind == .Fertile ? .52 : .28
	return p
}

atmosphere_initialize :: proc(state: ^Atmosphere_State, params: Atmosphere_Params) {
	state^ = {}; state.ready = params.atmosphere > .01; state.params = params
	if !state.ready do return
	atmosphere_prepare_topology()
	for face in 0 ..< 6 {for y in 0 ..< ATM_FACE_SIZE {for x in 0 ..< ATM_FACE_SIZE {
				i :=
					face * ATM_FACE_CELLS +
					y * ATM_FACE_SIZE +
					x; d := atmosphere_directions[i]; lat := d[1]
				n0 :=
					atm_unit(params.seed, i, 0) * 2 - 1; n1 := atm_unit(params.seed, i, 1) * 2 - 1
				state.field.pressure[i] = 1 + n0 * .025
				state.field.temperature[i] = clamp(.88 - abs(lat) * .5 + n1 * .05, .08, 1)
				source := params.humidity * (.42 + .58 * atm_unit(params.seed, i, 2))
				if params.kind ==
				   .Fertile {ocean := atm_unit(params.seed, i, 7) < params.ocean_fraction; if ocean {source *= 1.22} else {source *= .7}}
				state.field.vapor[i] = clamp(source, 0, 1)
				state.field.cloud[i] =
					clamp((source - (.34 + state.field.temperature[i] * .34)) * 1.8, 0, 1) *
					params.cloud_cover
				composition_total: f32
				for species in 0 ..< 4 {
					regional := .72 + atm_unit(params.seed, i, 20 + species) * .56
					switch species {
					case 0:
						regional *= .78 + (1 - state.field.temperature[i]) * .34
					case 1:
						regional *= .7 + abs(lat) * .48 + (1 - state.field.temperature[i]) * .22
					case 2:
						regional *= .82 + abs(lat) * .22 + abs(n0) * .12
					case 3:
						regional *=
							.68 +
							state.field.temperature[i] * .55 +
							max(state.field.pressure[i] - 1, 0) * 3
					}
					state.field.composition[species][i] =
						params.cloud_composition[species] * regional
					composition_total += state.field.composition[species][i]
				}
				if composition_total > 1e-6 do for species in 0 ..< 4 do state.field.composition[species][i] /= composition_total
				zonal :=
					params.circulation *
					(params.kind == .Gas_Giant ? f32(math.sin(f64(lat * 35))) : f32(math.sin(f64(lat * 9))))
				east := atm_normalize(
					atm_cross({0, 1, 0}, d),
				); state.field.wind[i] = {east[0] * zonal + n0 * .015, east[1] * zonal + n0 * .015, east[2] * zonal + n0 * .015}
			}}}
	state.previous_cloud = state.field.cloud
	for _ in 0 ..< ATM_SPINUP_STEPS do atmosphere_step(state)
	// Spin-up establishes balanced circulation but is not presentation time.
	state.step = 0; state.previous_cloud = state.field.cloud
}

atmosphere_step :: proc(state: ^Atmosphere_State) {
	if !state.ready do return
	state.previous_cloud = state.field.cloud; p := state.params
	axis := [3]f32 {
		f32(math.sin(f64(p.rotation_rate * .07))),
		f32(math.cos(f64(p.rotation_rate * .07))),
		0,
	}
	for face in 0 ..< 6 {for y in 0 ..< ATM_FACE_SIZE {for x in 0 ..< ATM_FACE_SIZE {
				i :=
					face * ATM_FACE_CELLS +
					y * ATM_FACE_SIZE +
					x; d := atmosphere_directions[i]; w := state.field.wind[i]; east := atmosphere_east[i]; north := atmosphere_north[i]; epsilon := f32(.032); neighbors := atmosphere_neighbors[i]
				grad_e :=
					(state.field.pressure[neighbors[0]] - state.field.pressure[neighbors[1]]) /
					(2 * epsilon)
				grad_n :=
					(state.field.pressure[neighbors[2]] - state.field.pressure[neighbors[3]]) /
					(2 * epsilon)
				wep :=
					state.field.wind[neighbors[0]]; wem := state.field.wind[neighbors[1]]; wnp := state.field.wind[neighbors[2]]; wnm := state.field.wind[neighbors[3]]
				divergence :=
					(atm_dot(wep, east) -
						atm_dot(wem, east) +
						atm_dot(wnp, north) -
						atm_dot(wnm, north)) /
					(2 * epsilon)
				back := atm_backtrace(d, w, -1); forward := atm_backtrace(back, w, 1)
				// Every advected field follows the same characteristic. Resolve the
				// cubed-sphere cells once instead of repeating the face projection for
				// pressure, vapor, cloud, and each condensate species.
				back_index := atm_index_from_dir(back)
				forward_index := atm_index_from_dir(forward)
				adv_p := state.field.pressure[back_index]
				rev_p := state.field.pressure[forward_index]
				adv_v := state.field.vapor[back_index]
				rev_v := state.field.vapor[forward_index]
				adv_c := state.field.cloud[back_index]
				rev_c := state.field.cloud[forward_index]
				// MacCormack predictor/corrector, bounded to prevent negative moisture.
				pressure := clamp(
					adv_p + (state.field.pressure[i] - rev_p) * .5 - divergence * .008,
					.82,
					1.18,
				)
				vapor := clamp(adv_v + (state.field.vapor[i] - rev_v) * .5, 0, 1)
				cloud := clamp(adv_c + (state.field.cloud[i] - rev_c) * .5, 0, 1)
				sun :=
					atmosphere_sun[i]; equilibrium := clamp(.2 + sun * .7 - abs(d[1]) * .16, .05, 1)
				temperature :=
					state.field.temperature[i] + (equilibrium - state.field.temperature[i]) * .006
				saturation := clamp(
					.2 + temperature * .55,
					0,
					1,
				); condense := max(vapor - saturation, 0) * .12; evaporate := max(saturation - vapor, 0) * min(cloud, .025)
				precipitation := max(cloud - .78, 0) * .018
				if p.kind == .Fertile && atm_unit(p.seed, i, 7) < p.ocean_fraction do vapor += .0015 * p.humidity
				vapor = clamp(
					vapor - condense + evaporate,
					0,
					1,
				); cloud = clamp((cloud + condense - evaporate - precipitation) * (1 - .0015 * (1 - p.cloud_cover)), 0, 1)
				coriolis := atm_cross(
					axis,
					w,
				); jet_shape := p.kind == .Gas_Giant ? atmosphere_jet_gas[i] : p.kind == .Ice_Giant ? atmosphere_jet_ice[i] : atmosphere_jet_terrestrial[i]
				jet := jet_shape * p.circulation
				wind := atm_normalize(
					{
						w[0] +
						coriolis[0] * .012 +
						east[0] * (jet * .004 - grad_e * .002) -
						north[0] * grad_n * .002,
						w[1] +
						coriolis[1] * .012 +
						east[1] * (jet * .004 - grad_e * .002) -
						north[1] * grad_n * .002,
						w[2] +
						coriolis[2] * .012 +
						east[2] * (jet * .004 - grad_e * .002) -
						north[2] * grad_n * .002,
					},
				)
				speed := min(
					.04 + p.circulation * .13,
					f32(math.sqrt(f64(w[0] * w[0] + w[1] * w[1] + w[2] * w[2]))) * .995 + .002,
				)
				wind = {
					wind[0] * speed,
					wind[1] * speed,
					wind[2] * speed,
				}; vort := atm_dot(d, atm_cross(w, wind)) / .02
				composition_total: f32
				for species in 0 ..< 4 {
					value := clamp(state.field.composition[species][back_index], 0, 1)
					// Condensates separate gently by the local weather regime while the
					// shared backtrace keeps their regional history attached to cloud flow.
					switch species {
					case 0:
						value *= .995 + (1 - temperature) * .004
					case 1:
						value *= .995 + abs(d[1]) * .004
					case 2:
						value *= .997 + abs(vort) * .002
					case 3:
						value *= .995 + temperature * .004
					}
					state.scratch.composition[species][i] = value; composition_total += value
				}
				if composition_total > 1e-6 do for species in 0 ..< 4 do state.scratch.composition[species][i] /= composition_total
				state.scratch.pressure[i] =
					pressure; state.scratch.vapor[i] = vapor; state.scratch.cloud[i] = cloud; state.scratch.temperature[i] = temperature; state.scratch.wind[i] = wind; state.scratch.vorticity[i] = clamp(vort, -1, 1)
			}}}
	state.field, state.scratch = state.scratch, state.field; state.step += 1
}

atmosphere_reconstruct :: proc(
	state: ^Atmosphere_State,
	params: Atmosphere_Params,
	target_step: i64,
) {
	// Deterministic epochs bound cold reconstruction work. Each epoch starts
	// from a seed-derived balanced atmosphere and advances at most 239 steps.
	epoch := max(target_step, 0) / ATM_EPOCH_STEPS; epoch_start := epoch * ATM_EPOCH_STEPS
	epoch_params :=
		params; if epoch > 0 do epoch_params.seed = atm_hash(params.seed ~ u64(epoch) * 0xd1b54a32d192ed03)
	atmosphere_initialize(state, epoch_params); state.params = params; state.step = epoch_start
	for state.step < target_step do atmosphere_step(state)
}

atmosphere_get :: proc(
	params: Atmosphere_Params,
	time_seconds: f32,
	freeze := false,
) -> ^Atmosphere_Cache_Entry {
	target := i64(max(time_seconds, 0) / ATM_STEP_SECONDS); atmosphere_stamp += 1
	oldest := 0
	for i in 0 ..< ATM_CACHE_SIZE {
		e := &atmosphere_cache[i]
		if e.state.ready &&
		   e.state.params ==
			   params {if !freeze {if e.state.step > target do atmosphere_reconstruct(&e.state, params, target); for e.state.step < target do atmosphere_step(&e.state)}; e.stamp = atmosphere_stamp; return e}
		if e.stamp < atmosphere_cache[oldest].stamp do oldest = i
	}
	e := &atmosphere_cache[oldest]; atmosphere_reconstruct(&e.state, params, freeze ? 0 : target); e.uploaded_step = -1; e.stamp = atmosphere_stamp; return e
}

atmosphere_atlas :: proc(state: ^Atmosphere_State) -> []u8 {
	atlas_width := ATM_FACE_SIZE * 6
	for i in 0 ..< ATM_CELL_COUNT {
		face :=
			i /
			ATM_FACE_CELLS; local := i % ATM_FACE_CELLS; x := local % ATM_FACE_SIZE; y := local / ATM_FACE_SIZE
		atlas_x :=
			(face % 3) * ATM_FACE_SIZE +
			x; atlas_y := (face / 3) * ATM_FACE_SIZE + y; pixel := (atlas_y * atlas_width + atlas_x) * 4
		atmosphere_pixels[pixel + 0] = u8(clamp(state.previous_cloud[i] * 255, 0, 255))
		atmosphere_pixels[pixel + 1] = u8(clamp(state.field.cloud[i] * 255, 0, 255))
		atmosphere_pixels[pixel + 2] = u8(
			clamp((state.field.pressure[i] - .82) / .36 * 255, 0, 255),
		)
		atmosphere_pixels[pixel + 3] = u8(
			clamp((state.field.vorticity[i] * .5 + .5) * 255, 0, 255),
		)
		composition_pixel := (atlas_y * atlas_width + atlas_x + ATM_FACE_SIZE * 3) * 4
		for species in 0 ..< 4 do atmosphere_pixels[composition_pixel + species] = u8(clamp(state.field.composition[species][i] * 255, 0, 255))
	}
	return atmosphere_pixels[:]
}

atmosphere_texture_for :: proc(
	config: ^Planet_Config,
	seed: u64,
	time_seconds: f32,
	reduced_motion := false,
) -> rl.Texture {
	if config.atmosphere <= .01 do return {}
	params := atmosphere_defaults(
		config^,
		seed,
	); entry := atmosphere_get(params, time_seconds, reduced_motion); state := &entry.state
	config.cloud_lerp =
		reduced_motion ? f32(0) : f32(math.mod(f64(time_seconds), f64(ATM_STEP_SECONDS)) / f64(ATM_STEP_SECONDS))
	if !entry.texture.ready {entry.texture = rl.CreateDynamicTextureRGBA(ATM_FACE_SIZE * 6, ATM_FACE_SIZE * 2, atmosphere_atlas(state)); entry.uploaded_step = state.step} else if entry.uploaded_step != state.step {if rl.UpdateDynamicTextureRGBA(entry.texture, atmosphere_atlas(state)) do entry.uploaded_step = state.step}
	return entry.texture
}

atmosphere_benchmark :: proc() {
	params := [4]Atmosphere_Params {
		{
			kind = .Fertile,
			seed = 11,
			atmosphere = .7,
			cloud_cover = .58,
			ocean_fraction = .71,
			rotation_rate = 1,
			humidity = .72,
			circulation = .52,
		},
		{
			kind = .Rocky,
			seed = 12,
			atmosphere = .3,
			cloud_cover = .18,
			rotation_rate = .8,
			humidity = .12,
			circulation = .28,
		},
		{
			kind = .Gas_Giant,
			seed = 13,
			atmosphere = .8,
			cloud_cover = .8,
			rotation_rate = 1.45,
			humidity = .9,
			circulation = 1,
		},
		{
			kind = .Ice_Giant,
			seed = 14,
			atmosphere = .6,
			cloud_cover = .4,
			rotation_rate = .92,
			humidity = .55,
			circulation = .68,
		},
	}
	states: [4]^Atmosphere_State; for i in 0 ..< 4 {states[i] = new(Atmosphere_State); defer free(states[i]); atmosphere_initialize(states[i], params[i])}
	values: [120]f64
	for i in 0 ..< len(values) {started := time.tick_now(); atmosphere_step(states[i % 4]); values[i] = time.duration_seconds(time.tick_since(started)) * 1000}
	benchmark.sort_samples(values[:]); p95 := values[113]
	fmt.printf(
		"{{\"scenario\":\"planet-atmosphere-c32\",\"samples\":120,\"cached_atmospheres\":4,\"tick_p95_ms\":%.4f,\"tick_max_ms\":%.4f,\"tick_interval_ms\":500,\"frame_uploads_per_tick\":1,\"budget_ms\":1.0,\"budget_pass\":%v}}\n",
		p95,
		values[len(values) - 1],
		p95 <= 1,
	)
}

@(test)
atmosphere_is_deterministic_and_bounded :: proc(t: ^testing.T) {
	p := Atmosphere_Params {
		kind           = .Fertile,
		seed           = 77,
		atmosphere     = .7,
		cloud_cover    = .58,
		ocean_fraction = .71,
		rotation_rate  = 1,
		humidity       = .72,
		circulation    = .52,
	}
	a, b :=
		new(Atmosphere_State),
		new(
			Atmosphere_State,
		); defer free(a); defer free(b); atmosphere_reconstruct(a, p, 7); atmosphere_reconstruct(b, p, 7)
	for i in 0 ..< ATM_CELL_COUNT {testing.expect_value(t, a.field.cloud[i], b.field.cloud[i]); testing.expect(t, a.field.cloud[i] >= 0 && a.field.cloud[i] <= 1); testing.expect(t, a.field.vapor[i] >= 0 && a.field.vapor[i] <= 1); testing.expect(t, a.field.pressure[i] >= .82 && a.field.pressure[i] <= 1.18)}
}

@(test)
atmosphere_time_uses_fixed_steps :: proc(t: ^testing.T) {
	p := Atmosphere_Params {
		kind          = .Gas_Giant,
		seed          = 9,
		atmosphere    = .8,
		cloud_cover   = .8,
		rotation_rate = 1.4,
		humidity      = .9,
		circulation   = 1,
	}
	a, b :=
		new(Atmosphere_State),
		new(
			Atmosphere_State,
		); defer free(a); defer free(b); atmosphere_reconstruct(a, p, 3); atmosphere_reconstruct(b, p, 3); testing.expect_value(t, a.step, b.step); testing.expect_value(t, a.field.cloud, b.field.cloud)
}

@(test)
atmosphere_reconstruction_matches_continuous_advance :: proc(t: ^testing.T) {
	p := Atmosphere_Params {
		kind          = .Ice,
		seed          = 91,
		atmosphere    = .3,
		cloud_cover   = .2,
		rotation_rate = .8,
		humidity      = .24,
		circulation   = .3,
	}
	a, b := new(Atmosphere_State), new(Atmosphere_State); defer free(a); defer free(b)
	atmosphere_initialize(
		a,
		p,
	); for _ in 0 ..< 12 do atmosphere_step(a); atmosphere_reconstruct(b, p, 12)
	testing.expect_value(
		t,
		a.field.cloud,
		b.field.cloud,
	); testing.expect_value(t, a.field.wind, b.field.wind)
}

@(test)
atmosphere_cubed_sphere_edges_reproject_continuously :: proc(t: ^testing.T) {
	for face in 0 ..< 6 {for edge in 0 ..< ATM_FACE_SIZE {
			directions := [4][3]f32 {
				atm_dir(face, 0, edge),
				atm_dir(face, ATM_FACE_SIZE - 1, edge),
				atm_dir(face, edge, 0),
				atm_dir(face, edge, ATM_FACE_SIZE - 1),
			}
			for d in directions {i := atm_index_from_dir(d); other_face := i / ATM_FACE_CELLS
				local := i % ATM_FACE_CELLS
				roundtrip := atm_dir(other_face, local % ATM_FACE_SIZE, local / ATM_FACE_SIZE)
				testing.expect(t, atm_dot(d, roundtrip) > .998)}
		}}
}

@(test)
atmosphere_airless_world_bypasses_simulation :: proc(t: ^testing.T) {s := new(Atmosphere_State)
	defer free(s)
	atmosphere_initialize(s, {seed = 1})
	testing.expect(t, !s.ready)}

@(test)
atmosphere_reduced_motion_freezes_cached_step :: proc(t: ^testing.T) {
	p := Atmosphere_Params {
		kind          = .Fertile,
		seed          = 0xf001,
		atmosphere    = .7,
		cloud_cover   = .5,
		rotation_rate = 1,
		humidity      = .7,
		circulation   = .5,
	}
	e := atmosphere_get(p, 5, false); step := e.state.step; frozen := atmosphere_get(p, 500, true)
	testing.expect(t, e == frozen); testing.expect_value(t, frozen.state.step, step)
}

@(test)
atmosphere_large_time_reconstruction_is_epoch_bounded :: proc(t: ^testing.T) {
	p := Atmosphere_Params {
		kind          = .Ice_Giant,
		seed          = 0xe001,
		atmosphere    = .6,
		cloud_cover   = .4,
		rotation_rate = .9,
		humidity      = .5,
		circulation   = .6,
	}
	s := new(
		Atmosphere_State,
	); defer free(s); target := i64(1_000_123); atmosphere_reconstruct(s, p, target)
	testing.expect_value(t, s.step, target); testing.expect_value(t, s.params, p)
}

@(test)
atmosphere_regional_composition_is_deterministic_normalized_and_advected :: proc(t: ^testing.T) {
	p := Atmosphere_Params {
		kind              = .Gas_Giant,
		seed              = 0xc10d,
		atmosphere        = .8,
		cloud_cover       = .82,
		rotation_rate     = 1.4,
		humidity          = .9,
		circulation       = 1,
		cloud_composition = {.08, .52, .16, .24},
	}
	a, b := new(Atmosphere_State), new(Atmosphere_State); defer free(a); defer free(b)
	atmosphere_initialize(
		a,
		p,
	); atmosphere_initialize(b, p); testing.expect_value(t, a.field.composition, b.field.composition)
	before :=
		a.field.composition; atmosphere_step(a); testing.expect(t, a.field.composition != before)
	for i in 0 ..< ATM_CELL_COUNT {
		total: f32
		for species in 0 ..< 4 {value := a.field.composition[species][i]; testing.expect(t, value >= 0 && value <= 1); total += value}
		if a.field.cloud[i] > 1e-6 do testing.expect(t, abs(total - 1) < 1e-4)
	}
}

@(test)
atmosphere_atlas_packs_weather_and_composition_face_sets :: proc(t: ^testing.T) {
	s := new(Atmosphere_State); defer free(s); s.ready = true
	i := ATM_FACE_CELLS + 7 * ATM_FACE_SIZE + 11
	s.previous_cloud[i] = .25; s.field.cloud[i] = .75; s.field.pressure[i] = 1; s.field.vorticity[i] = 0
	s.field.composition[0][i] = .1; s.field.composition[1][i] = .2; s.field.composition[2][i] = .3; s.field.composition[3][i] = .4
	pixels := atmosphere_atlas(s); testing.expect_value(t, len(pixels), ATM_CELL_COUNT * 8)
	atlas_x :=
		ATM_FACE_SIZE +
		11; atlas_y := 7; weather := (atlas_y * ATM_FACE_SIZE * 6 + atlas_x) * 4; composition := (atlas_y * ATM_FACE_SIZE * 6 + atlas_x + ATM_FACE_SIZE * 3) * 4
	testing.expect(
		t,
		pixels[weather] < pixels[weather + 1],
	); testing.expect_value(t, pixels[composition], u8(25)); testing.expect_value(t, pixels[composition + 3], u8(102))
}

@(test)
atmosphere_reduced_motion_preserves_regional_composition :: proc(t: ^testing.T) {
	p := Atmosphere_Params {
		kind              = .Ice_Giant,
		seed              = 0xf12e,
		atmosphere        = .6,
		cloud_cover       = .4,
		rotation_rate     = .9,
		humidity          = .55,
		circulation       = .68,
		cloud_composition = {.15, .24, .61, 0},
	}
	e := atmosphere_get(
		p,
		5,
		false,
	); before := e.state.field.composition; frozen := atmosphere_get(p, 500, true)
	testing.expect(t, e == frozen); testing.expect_value(t, frozen.state.field.composition, before)
}
