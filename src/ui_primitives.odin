package main

import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:os"
import filepath "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"
import rl "zelda_engine:canvas2d"
import ui "zelda_engine:ui"

Tooltip_State :: struct {
	visible:           bool,
	anchor:            rl.Rectangle,
	title, body:       string,
	body_height:       f32,
	graph_visible:     bool,
	graph_values:      [5]f32,
	graph_value_count: int,
}
ux_tooltip: Tooltip_State

R :: proc(x, y, w, h: f32) -> rl.Rectangle {return {x, y, w, h}}
V :: proc(x, y: f32) -> rl.Vector2 {return {x, y}}

spotlight :: proc(focuses: []rl.Rectangle, dim_alpha: u8 = 190, padding: f32 = 8) -> int {
	engine_foci: [ui.GUI_SPOTLIGHT_MAX_FOCI]ui.Rect
	for focus, i in focuses[:min(len(focuses), ui.GUI_SPOTLIGHT_MAX_FOCI)] do engine_foci[i] = {focus.x, focus.y, focus.width, focus.height}
	engine_cells: [ui.GUI_SPOTLIGHT_MAX_CELLS]ui.Rect
	count := ui.gui_spotlight_layout(
		engine_foci[:min(len(focuses), ui.GUI_SPOTLIGHT_MAX_FOCI)],
		{0, 0, UX_W, UX_H},
		padding,
		&engine_cells,
	)
	for cell in engine_cells[:count] do rl.DrawRectangleRec(R(cell.x, cell.y, cell.w, cell.h), {3, 3, 3, dim_alpha})
	for focus in focuses[:min(len(focuses), ui.GUI_SPOTLIGHT_MAX_FOCI)] {
		box := R(
			clamp(focus.x - padding, 0, UX_W),
			clamp(focus.y - padding, 0, UX_H),
			min(focus.width + padding * 2, UX_W),
			min(focus.height + padding * 2, UX_H),
		)
		rl.DrawRectangleRoundedLinesEx(box, .04, 4, 2, UX.info)
	}
	return count
}

font_for_size :: proc(size: f32) -> rl.Font {
	// Cache by final on-screen size; the atlas itself is rasterized at 2x.
	index := clamp(int(math.round(f64(size * ux_zoom))), 1, MAX_FONT_PAINT_SIZE)
	if !ux_fonts_loaded[index] {
		ux_fonts[index] = rl.LoadFontEx(
			"assets/fonts/Iosevka-Regular.ttf",
			i32(index * FONT_SCALE),
			nil,
			0,
		)
		ux_fonts_loaded[index] = true
	}
	return ux_fonts[index]
}

unload_fonts :: proc() {for loaded, index in ux_fonts_loaded do if loaded do rl.UnloadFont(ux_fonts[index])}

readable_text_size_at_scale :: proc(size, scale: f32) -> f32 {
	return max(size, f32(MIN_BODY_TEXT_SIZE)) * scale
}

readable_text_size :: proc(size: f32) -> f32 {return readable_text_size_at_scale(
		size,
		ux_text_scale,
	)}

@(test)
typography_never_paints_below_the_body_minimum :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		readable_text_size_at_scale(TYPE_MICRO_TIGHT, 1),
		f32(MIN_BODY_TEXT_SIZE),
	)
	testing.expect_value(
		t,
		readable_text_size_at_scale(TYPE_FINE, 1.25),
		f32(MIN_BODY_TEXT_SIZE) * 1.25,
	)
	testing.expect_value(t, readable_text_size_at_scale(TYPE_BODY, 1.5), f32(TYPE_BODY) * 1.5)
}

draw_text :: proc(text: string, x, y, size: f32, color := UX.text) {paint_size :=
		readable_text_size(size)
	rl.DrawTextEx(
		font_for_size(paint_size),
		fmt.ctprintf("%s", text),
		V(x, y),
		paint_size,
		1,
		color,
	)}
draw_fmt :: proc(x, y, size: f32, color: rl.Color, format: string, args: ..any) {paint_size :=
		readable_text_size(size)
	rl.DrawTextEx(
		font_for_size(paint_size),
		fmt.ctprintf(format, ..args),
		V(x, y),
		paint_size,
		1,
		color,
	)}
draw_text_fitted :: proc(text: string, rect: rl.Rectangle, size: f32, color := UX.text) {
	minimum_size := readable_text_size(MIN_BODY_TEXT_SIZE)
	paint_size := readable_text_size(size)
	display_text := text
	measure := rl.MeasureTextEx(
		font_for_size(paint_size),
		fmt.ctprintf("%s", display_text),
		paint_size,
		1,
	)
	available := max(rect.width, f32(1))
	if measure.x > available {
		glyph_count := 0
		for _ in text do glyph_count += 1
		fit := ui.gui_monospace_text_fit(
			max(glyph_count, 1),
			available,
			paint_size,
			minimum_size,
			rl.FontAdvanceEm(),
			1,
		)
		paint_size = fit.paint_size
		measure = rl.MeasureTextEx(
			font_for_size(paint_size),
			fmt.ctprintf("%s", display_text),
			paint_size,
			1,
		)
	}
	if measure.x > available {
		max_glyphs := max(int((available + 1) / (paint_size * rl.FontAdvanceEm() + 1)), 1)
		if max_glyphs > 3 {
			display_text = fmt.tprintf("%s...", strings.cut(text, 0, max_glyphs - 3))
		} else {
			display_text = strings.cut("...", 0, max_glyphs)
		}
		measure = rl.MeasureTextEx(
			font_for_size(paint_size),
			fmt.ctprintf("%s", display_text),
			paint_size,
			1,
		)
	}
	rl.DrawTextEx(
		font_for_size(paint_size),
		fmt.ctprintf("%s", display_text),
		V(rect.x, rect.y + (rect.height - paint_size) / 2),
		paint_size,
		1,
		color,
	)
}

draw_text_wrapped :: proc(text: string, rect: rl.Rectangle, size: f32, color := UX.text) -> f32 {
	y := rect.y
	line_height := readable_text_size(size) + 6
	remaining_lines := text
	// Treat explicit line feeds as layout instructions. Apart from allowing
	// callers to separate paragraphs, this keeps font rendering from turning
	// a newline glyph into a visible fallback character.
	for paragraph in strings.split_lines_iterator(&remaining_lines) {
		if paragraph == "" {
			y += line_height
			continue
		}
		line := ""
		remaining_words := paragraph
		for word in strings.split_by_byte_iterator(&remaining_words, ' ') {
			if word == "" do continue
			candidate := word
			if line != "" do candidate = fmt.tprintf("%s %s", line, word)
			if line != "" && measure_text(candidate, size).x > rect.width {
				draw_text(line, rect.x, y, size, color)
				y += line_height
				line = word
			} else {
				line = candidate
			}
		}
		if line != "" {
			draw_text(line, rect.x, y, size, color)
			y += line_height
		}
	}
	return y
}

measure_text :: proc(text: string, size: f32) -> rl.Vector2 {
	paint_size := readable_text_size(size)
	return rl.MeasureTextEx(font_for_size(paint_size), fmt.ctprintf("%s", text), paint_size, 1)
}

// Annotated terms use ordinary GUI focus behavior, making their explanations
// available to keyboard users as well as pointer users. The overlay is drawn
// once, after the screen, so it cannot be covered by later screen content.
tooltip_term :: proc(text, explanation: string, x, y, size: f32, color := UX.text) {
	measure := measure_text(text, size)
	rect := R(x - 3, y - 3, measure.x + 6, measure.y + 6)
	index := ux_button_cursor
	ux_button_cursor += 1
	interaction := rl.ButtonBehavior(index, rect, true)
	active := interaction.hovered || interaction.focused
	draw_text(text, x, y, size, color)
	underline_color := active ? UX.text : rl.Color{color.r, color.g, color.b, 150}
	// MeasureTextEx includes the font's line box, whose trailing descent leaves
	// decorative rules visibly detached from these terminal-style glyphs.
	underline_y := y + readable_text_size(size) - 1
	segment_width: f32 = 4
	for segment_x := x; segment_x < x + measure.x; segment_x += segment_width * 2 {
		rl.DrawLineEx(
			V(segment_x, underline_y),
			V(min(segment_x + segment_width, x + measure.x), underline_y),
			1,
			underline_color,
		)
	}
	if active do ux_tooltip = {
		visible = true,
		anchor  = rect,
		title   = text,
		body    = explanation,
	}
}

tooltip_target :: proc(rect: rl.Rectangle, title, explanation: string) -> bool {
	index := ux_button_cursor
	ux_button_cursor += 1
	interaction := rl.ButtonBehavior(index, rect, true)
	active := interaction.hovered || interaction.focused
	if active {
		rl.DrawRectangleRoundedLinesEx(rect, .12, 5, 1, UX.info)
		ux_tooltip = {
			visible = true,
			anchor  = rect,
			title   = title,
			body    = explanation,
		}
	}
	return active
}

// Passive readouts should explain themselves while pointed at, but must not
// retain a tooltip after a click has moved keyboard focus elsewhere.
tooltip_hover_target :: proc(rect: rl.Rectangle, title, explanation: string) -> bool {
	ux_button_cursor += 1
	if !contains(rect) do return false
	rl.DrawRectangleRoundedLinesEx(rect, .12, 5, 1, UX.info)
	ux_tooltip = {
		visible = true,
		anchor  = rect,
		title   = title,
		body    = explanation,
	}
	return true
}

draw_tooltip :: proc() {
	if !ux_tooltip.visible do return
	width: f32 = 430
	body_height := max(f32(50), ux_tooltip.body_height)
	height: f32 = ux_tooltip.graph_visible ? 194 : 54 + body_height
	margin: f32 = 14
	x := clamp(ux_tooltip.anchor.x, margin, f32(UX_W) - width - margin)
	y := ux_tooltip.anchor.y + ux_tooltip.anchor.height + 10
	if y + height > f32(UX_H) - margin do y = ux_tooltip.anchor.y - height - 10
	y = clamp(y, margin, f32(UX_H) - height - margin)
	rect := R(x, y, width, height)
	rl.DrawRectangleRounded(rect, 0, 1, rl.Color{6, 6, 5, 252})
	rl.DrawRectangleRoundedLinesEx(rect, 0, 1, 2, UX.info)
	rl.DrawLineEx(V(x, y + 7), V(x + 54, y + 7), 3, UX.info)
	label_caps(ux_tooltip.title, x + 16, y + 12, UX.info)
	draw_text_wrapped(
		ux_tooltip.body,
		R(x + 16, y + 38, width - 32, body_height),
		TYPE_SMALL,
		UX.text,
	)
	if ux_tooltip.graph_visible {
		graph_rect := R(x + 16, y + 96, width - 32, 48)
		DrawBarGraph(
			graph_rect,
			ux_tooltip.graph_values[:ux_tooltip.graph_value_count],
			UX.info,
			0,
			1,
		)
		rl.DrawLineEx(
			V(graph_rect.x, graph_rect.y + graph_rect.height / 2),
			V(graph_rect.x + graph_rect.width, graph_rect.y + graph_rect.height / 2),
			1,
			UX.line,
		)
		legend_labels := [5]string{"PRODUCED", "IMPORTED", "USED", "EXPORTED", "LOST"}
		legend_colors := [5]rl.Color{UX.good, UX.info, UX.warn, UX.dim, UX.bad}
		for legend, i in legend_labels {
			// Each label shares its bar's center; a packed legend drifts labels
			// left while the graph distributes bars across its full width.
			label_width := measure_text(legend, TYPE_FINE).x
			bar_center := graph_rect.x + graph_rect.width * (f32(i) + .5) / f32(len(legend_labels))
			draw_text(legend, bar_center - label_width / 2, y + 154, TYPE_FINE, legend_colors[i])
		}
	}
}

manga_corner_marks :: proc(rect: rl.Rectangle, color := UX.text) {
	length := min(f32(15), min(rect.width, rect.height) * .18)
	for x_side in 0 ..< 2 {
		for y_side in 0 ..< 2 {
			x := x_side == 0 ? rect.x : rect.x + rect.width
			y := y_side == 0 ? rect.y : rect.y + rect.height
			dx: f32 = x_side == 0 ? 1 : -1
			dy: f32 = y_side == 0 ? 1 : -1
			rl.DrawLineEx(V(x, y), V(x + dx * length, y), 2, color)
			rl.DrawLineEx(V(x, y), V(x, y + dy * length), 2, color)
		}
	}
}

manga_backdrop :: proc() {
	// Sparse screen-tone bands establish the page without competing with maps.
	tone := rl.Color{226, 224, 212, 12}
	for i in 0 ..< 18 {
		offset := f32(i * 18)
		rl.DrawLineEx(V(UX_W - 320 + offset, 0), V(UX_W, 320 - offset), 1, tone)
		rl.DrawLineEx(V(0, UX_H - 210 + offset), V(210 - offset, UX_H), 1, tone)
	}
	// Slightly imperfect parallel rules read like a printed page edge.
	rl.DrawLineEx(V(12, 0), V(12, UX_H), 1, {226, 224, 212, 18})
	rl.DrawLineEx(V(15, 0), V(15, UX_H), .5, {226, 224, 212, 10})
}

panel :: proc(rect: rl.Rectangle, raised := false) {
	// Offset ink shadow and double-rule edge give panels the weight of manga
	// narration boxes while retaining a rectangular hit area.
	rl.DrawRectangleRounded(
		R(rect.x + 4, rect.y + 4, rect.width, rect.height),
		0,
		1,
		{0, 0, 0, 165},
	)
	rl.DrawRectangleRounded(rect, 0, 1, raised ? UX.raised : UX.panel)
	rl.DrawRectangleRoundedLinesEx(rect, 0, 1, 1, UX.line)
	manga_corner_marks(rect, raised ? UX.text : UX.dim)
	if raised {
		rl.DrawLineEx(V(rect.x + 18, rect.y + 7), V(rect.x + 72, rect.y + 7), 3, UX.text)
		rl.DrawLineEx(V(rect.x + 76, rect.y + 7), V(rect.x + 91, rect.y + 7), 3, UX.info)
	}
}
contains :: proc(rect: rl.Rectangle) -> bool {return rl.CheckCollisionPointRec(ux_mouse, rect)}

button :: proc(rect: rl.Rectangle, label: string, enabled := true, accent := false) -> bool {
	index := ux_button_cursor
	ux_button_cursor += 1
	interaction := rl.ButtonBehavior(index, rect, enabled && !ux_pointer_input_blocked)
	hover, focused := interaction.hovered, interaction.focused
	fill := enabled ? (hover ? rl.Color{32, 32, 29, 255} : UX.raised) : rl.Color{11, 11, 10, 255}
	rl.DrawRectangleRounded(rect, 0, 1, fill)
	border := hover || focused ? UX.text : (enabled ? UX.line : UX.unavailable)
	rl.DrawRectangleRoundedLinesEx(rect, 0, 1, hover || focused ? 2 : 1, border)
	if hover || focused {
		for i in 0 ..< 3 {
			x := rect.x + rect.width - 18 + f32(i * 5)
			rl.DrawLineEx(V(x - 10, rect.y + rect.height), V(x + 10, rect.y), 1, UX.dim)
		}
	}
	if accent && enabled {
		accent_color := hover ? UX.text : UX.info
		rl.DrawRectangle(i32(rect.x), i32(rect.y), 5, i32(rect.height), accent_color)
		rl.DrawLineEx(
			V(rect.x + 9, rect.y + 5),
			V(rect.x + 9, rect.y + rect.height - 5),
			1,
			accent_color,
		)
	}
	minimum_size := readable_text_size(MIN_BODY_TEXT_SIZE)
	paint_size := readable_text_size(TYPE_BODY_EMPHASIS)
	measure := rl.MeasureTextEx(
		font_for_size(paint_size),
		fmt.ctprintf("%s", label),
		paint_size,
		1,
	)
	available := max(rect.width - 10, f32(1))
	if measure.x > available {
		paint_size = max(paint_size * available / measure.x, minimum_size)
		measure = rl.MeasureTextEx(
			font_for_size(paint_size),
			fmt.ctprintf("%s", label),
			paint_size,
			1,
		)
	}
	rl.DrawTextEx(
		font_for_size(paint_size),
		fmt.ctprintf("%s", label),
		V(
			rect.x + (rect.width - min(measure.x, available)) / 2,
			rect.y + (rect.height - paint_size) / 2,
		),
		paint_size,
		1,
		enabled ? UX.text : UX.unavailable,
	)
	return interaction.activated
}

draw_selection_mark :: proc(x, y, size: int, selected, radio: bool, color: rl.Color) {
	// Rasterize the mark directly onto the logical-pixel grid. These controls
	// deliberately use hard, monochrome pixels rather than antialiased vector
	// strokes; text and the illustrated icon atlas keep their normal filtering.
	n := clamp(size, 6, 16)
	if radio {
		for py in 0 ..< n {
			for px in 0 ..< n {
				if ui.gui_selection_mark_pixel(px, py, n, selected, true) do rl.DrawRectangle(i32(x + px), i32(y + py), 1, 1, color)
			}
		}
		return
	}

	// The box and check share one ink color. The stepped check is intentionally
	// asymmetric so it remains recognizable even in the six-pixel compact form.
	for py in 0 ..< n {
		for px in 0 ..< n {
			if ui.gui_selection_mark_pixel(px, py, n, selected, false) do rl.DrawRectangle(i32(x + px), i32(y + py), 1, 1, color)
		}
	}
}
