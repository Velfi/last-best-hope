package main

import "core:fmt"
import "core:math"
import "core:testing"
import rl "zelda_engine:canvas2d"

Propellant_Range_Layout :: struct {
	track:                              rl.Rectangle,
	fill_width, needle_x:               f32,
	propellant_fraction, exit_fraction: f32,
	exit_known, at_return_limit:        bool,
}

propellant_range_layout :: proc(
	rect: rl.Rectangle,
	capacity, remaining, exit_cost: f64,
	exit_known: bool,
) -> Propellant_Range_Layout {
	track := R(rect.x, rect.y + 13, rect.width, 7)
	valid_capacity := max(capacity, 0)
	propellant_fraction := valid_capacity > 0 ? f32(clamp(remaining / valid_capacity, 0, 1)) : 0
	exit_fraction :=
		valid_capacity > 0 && exit_known ? f32(clamp(exit_cost / valid_capacity, 0, 1)) : 0
	return {
		track = track,
		fill_width = track.width * propellant_fraction,
		needle_x = track.x + track.width * exit_fraction,
		propellant_fraction = propellant_fraction,
		exit_fraction = exit_fraction,
		exit_known = exit_known,
		at_return_limit = exit_known && remaining <= exit_cost + 1e-6,
	}
}

propellant_range_hatch :: proc(rect: rl.Rectangle, color: rl.Color) {
	if rect.width <= 0 || rect.height <= 0 do return
	step := f32(7)
	x := rect.x - rect.height
	for x < rect.x + rect.width {
		start_x := max(x, rect.x)
		end_x := min(x + rect.height, rect.x + rect.width)
		start_y := rect.y + (start_x - x)
		end_y := rect.y + (end_x - x)
		rl.DrawLineEx(V(start_x, start_y), V(end_x, end_y), 1, color)
		x += step
	}
}

propellant_range_instrument :: proc(
	rect: rl.Rectangle,
	capacity, remaining, exit_cost: f64,
	exit_known: bool,
) {
	layout := propellant_range_layout(rect, capacity, remaining, exit_cost, exit_known)
	margin := remaining - exit_cost
	ink :=
		!exit_known ? UX.warn : layout.at_return_limit ? UX.bad : margin <= max(capacity * .25, .25) ? UX.warn : UX.good

	if exit_known {
		draw_fmt(
			rect.x,
			rect.y,
			TYPE_MICRO,
			layout.at_return_limit ? UX.bad : UX.dim,
			"EXIT %.2f",
			max(exit_cost, 0),
		)
	} else {
		draw_text("EXIT UNRESOLVED", rect.x, rect.y, TYPE_MICRO, UX.warn)
	}
	draw_fmt(
		rect.x + rect.width - 112,
		rect.y,
		TYPE_MICRO,
		ink,
		"PROPELLANT %.2f / %.2f",
		max(remaining, 0),
		max(capacity, 0),
	)

	rl.DrawRectangleRec(layout.track, rl.Color{4, 4, 4, 235})
	if layout.fill_width > 0 {
		rl.DrawRectangleRec(
			R(layout.track.x, layout.track.y, layout.fill_width, layout.track.height),
			rl.Color{ink.r, ink.g, ink.b, 92},
		)
		rl.DrawLineEx(
			V(layout.track.x, layout.track.y + layout.track.height - 1),
			V(layout.track.x + layout.fill_width, layout.track.y + layout.track.height - 1),
			2,
			ink,
		)
	}

	reserve_width := exit_known ? layout.track.width * layout.exit_fraction : layout.track.width
	propellant_range_hatch(
		R(layout.track.x, layout.track.y, reserve_width, layout.track.height),
		exit_known ? rl.Color{UX.text.r, UX.text.g, UX.text.b, 82} : rl.Color{UX.warn.r, UX.warn.g, UX.warn.b, 92},
	)
	rl.DrawRectangleRoundedLinesEx(layout.track, 0, 1, 1, UX.line)

	if exit_known {
		needle_x := clamp(
			layout.needle_x,
			layout.track.x + 1,
			layout.track.x + layout.track.width - 1,
		)
		needle_ink := layout.at_return_limit ? UX.bad : UX.text
		rl.DrawLineEx(
			V(needle_x, layout.track.y - 5),
			V(needle_x, layout.track.y + layout.track.height + 2),
			1.5,
			needle_ink,
		)
		rl.DrawLineEx(
			V(needle_x - 4, layout.track.y - 5),
			V(needle_x, layout.track.y - 1),
			1.5,
			needle_ink,
		)
		rl.DrawLineEx(
			V(needle_x + 4, layout.track.y - 5),
			V(needle_x, layout.track.y - 1),
			1.5,
			needle_ink,
		)
		rl.DrawLineEx(
			V(needle_x - 4, layout.track.y - 5),
			V(needle_x + 4, layout.track.y - 5),
			1.5,
			needle_ink,
		)
	}

	if rl.CheckCollisionPointRec(ux_mouse, rect) {
		ux_tooltip = {
			visible = true,
			anchor  = rect,
			title   = "PROPELLANT RANGE",
			body    = "The needle marks fuel needed for the nearest mapped fleet exit; systematic search stops at that reserve.",
		}
	}
}

@(test)
propellant_range_layout_clamps_empty_full_and_over_capacity :: proc(t: ^testing.T) {
	rect := R(10, 20, 200, 24)
	empty := propellant_range_layout(rect, 10, 0, 2, true)
	full := propellant_range_layout(rect, 10, 10, 2, true)
	over := propellant_range_layout(rect, 10, 14, 2, true)
	testing.expect_value(t, empty.fill_width, f32(0))
	testing.expect_value(t, full.fill_width, f32(200))
	testing.expect_value(t, over.fill_width, f32(200))
	testing.expect(t, empty.at_return_limit)
	testing.expect(t, !full.at_return_limit)
}

@(test)
propellant_range_layout_handles_zero_capacity_and_unresolved_exit :: proc(t: ^testing.T) {
	rect := R(10, 20, 200, 24)
	zero := propellant_range_layout(rect, 0, 4, 3, true)
	unknown := propellant_range_layout(rect, 10, 7, 0, false)
	testing.expect_value(t, zero.fill_width, f32(0))
	testing.expect_value(t, zero.needle_x, rect.x)
	testing.expect(t, !unknown.exit_known)
	testing.expect(t, !unknown.at_return_limit)
}

@(test)
propellant_range_layout_needle_marks_the_search_stop_boundary :: proc(t: ^testing.T) {
	rect := R(10, 20, 200, 24)
	margin := propellant_range_layout(rect, 10, 6, 4, true)
	boundary := propellant_range_layout(rect, 10, 4, 4, true)
	testing.expect_value(t, margin.needle_x, f32(90))
	testing.expect(t, math.abs(margin.fill_width - 120) < .001)
	testing.expect_value(t, boundary.fill_width, boundary.needle_x - rect.x)
	testing.expect(t, boundary.at_return_limit)
}
