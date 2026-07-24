package main

import "core:math"
import "core:testing"

STELLAR_FLUX_W :: 64
STELLAR_FLUX_H :: 32
STELLAR_FLUX_CELLS :: STELLAR_FLUX_W * STELLAR_FLUX_H
STELLAR_FLUX_HZ :: 4

Stellar_Flux_State :: struct {
	seed:           u64,
	step:           int,
	field, scratch: [STELLAR_FLUX_CELLS]f32,
}

stellar_flux_hash :: proc(v: u64) -> u64 {x := v; x ~= (x >> 30); x *= 0xbf58476d1ce4e5b9; x ~=
		(x >> 27)
	x *= 0x94d049bb133111eb
	x ~= (x >> 31)
	return x}
stellar_flux_unit :: proc(seed: u64, channel: int) -> f32 {return(
		f32(stellar_flux_hash(seed + u64(channel) * 0x9e3779b97f4a7c15) >> 40) /
		f32(1 << 24) \
	)}
stellar_flux_index :: proc(x, y: int) -> int {return(
		clamp(y, 0, STELLAR_FLUX_H - 1) * STELLAR_FLUX_W +
		((x % STELLAR_FLUX_W) + STELLAR_FLUX_W) % STELLAR_FLUX_W \
	)}

stellar_flux_inject_bipole :: proc(s: ^Stellar_Flux_State, event: int) {
	base := s.seed ~ u64(event) * 0xd1b54a32d192ed03
	center_x := stellar_flux_unit(base, 0) * STELLAR_FLUX_W
	lat_sign := stellar_flux_unit(base, 1) < .5 ? f32(-1) : f32(1)
	center_y :=
		f32(STELLAR_FLUX_H) * .5 +
		lat_sign * (.12 + stellar_flux_unit(base, 2) * .22) * STELLAR_FLUX_H
	separation := 1.8 + stellar_flux_unit(base, 3) * 3.4
	tilt := lat_sign * (.12 + stellar_flux_unit(base, 4) * .38)
	strength := .24 + stellar_flux_unit(base, 5) * .58
	sigma := 1.1 + stellar_flux_unit(base, 6) * 1.7
	for y in 0 ..< STELLAR_FLUX_H {for x in 0 ..< STELLAR_FLUX_W {
			dx :=
				f32(x) -
				center_x; if dx > STELLAR_FLUX_W * .5 do dx -= STELLAR_FLUX_W; if dx < -STELLAR_FLUX_W * .5 do dx += STELLAR_FLUX_W
			dy := f32(y) - center_y
			along := dx * f32(math.cos(f64(tilt))) + dy * f32(math.sin(f64(tilt)))
			across := -dx * f32(math.sin(f64(tilt))) + dy * f32(math.cos(f64(tilt)))
			positive := f32(
				math.exp(
					f64(
						-((along - separation * .5) * (along - separation * .5) +
							across * across) /
						(2 * sigma * sigma),
					),
				),
			)
			negative := f32(
				math.exp(
					f64(
						-((along + separation * .5) * (along + separation * .5) +
							across * across) /
						(2 * sigma * sigma),
					),
				),
			)
			s.field[stellar_flux_index(x, y)] += strength * (positive - negative)
		}}
}

stellar_flux_initialize :: proc(s: ^Stellar_Flux_State, seed: u64) {s^ = {
		seed = seed,
	}; for event in 0 ..< 7 do stellar_flux_inject_bipole(s, event)}

stellar_flux_step :: proc(s: ^Stellar_Flux_State) {
	DT: f32 : 1.0 / STELLAR_FLUX_HZ
	for y in 0 ..< STELLAR_FLUX_H {latitude := (f32(y) + .5) / STELLAR_FLUX_H * f32(math.PI) - f32(math.PI) * .5; sin_lat := f32(math.sin(f64(latitude))); omega := .72 - .16 * sin_lat * sin_lat - .08 * sin_lat * sin_lat * sin_lat * sin_lat; meridional := .055 * f32(math.sin(f64(latitude * 2)))
		for x in 0 ..< STELLAR_FLUX_W {source_x := f32(x) - omega * DT; source_y := f32(y) - meridional * DT * STELLAR_FLUX_H; ix := int(math.floor(f64(source_x))); iy := int(math.floor(f64(source_y))); tx := source_x - f32(ix); ty := source_y - f32(iy)
			a :=
				s.field[stellar_flux_index(ix, iy)]; b := s.field[stellar_flux_index(ix + 1, iy)]; c := s.field[stellar_flux_index(ix, iy + 1)]; d := s.field[stellar_flux_index(ix + 1, iy + 1)]; advected := (a + (b - a) * tx) * (1 - ty) + (c + (d - c) * tx) * ty
			lap :=
				s.field[stellar_flux_index(x - 1, y)] +
				s.field[stellar_flux_index(x + 1, y)] +
				s.field[stellar_flux_index(x, y - 1)] +
				s.field[stellar_flux_index(x, y + 1)] -
				4 * s.field[stellar_flux_index(x, y)]
			s.scratch[stellar_flux_index(x, y)] = clamp(advected + lap * .035 * DT, -1, 1)
		}}
	s.field, s.scratch = s.scratch, s.field; s.step += 1
	if s.step % 96 == 0 do stellar_flux_inject_bipole(s, 7 + s.step / 96)
}

stellar_flux_advance_to :: proc(s: ^Stellar_Flux_State, seed: u64, time_seconds: f32) {target :=
		max(0, int(time_seconds * STELLAR_FLUX_HZ))
	if s.seed != seed || target < s.step do stellar_flux_initialize(s, seed)
	for s.step < target do stellar_flux_step(s)}


@(test)
stellar_flux_transport_is_deterministic_and_bounded :: proc(
	t: ^testing.T,
) {a, b: Stellar_Flux_State; stellar_flux_advance_to(&a, 71, 12); stellar_flux_advance_to(
		&b,
		71,
		12,
	)
	testing.expect_value(t, a.field, b.field)
	for v in a.field do testing.expect(t, v >= -1 && v <= 1)}
@(test)
stellar_flux_transport_preserves_both_polarities :: proc(t: ^testing.T) {s: Stellar_Flux_State
	stellar_flux_advance_to(&s, 99, 30)
	low, high := f32(1), f32(-1)
	for i := 0; i < len(s.field); i += 1 {v := s.field[i]; low = min(low, v); high = max(high, v)}
	testing.expect(t, low < -.02 && high > .02)}
