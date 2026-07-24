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
selection_control :: proc(
	rect: rl.Rectangle,
	label: string,
	selected: bool,
	enabled: bool,
	radio: bool,
) -> bool {
	index := ux_button_cursor
	ux_button_cursor += 1
	interaction := rl.ButtonBehavior(index, rect, enabled && !ux_pointer_input_blocked)
	active := interaction.hovered || interaction.focused
	fill := active && enabled ? rl.Color{27, 29, 28, 255} : rl.Color{12, 13, 12, 255}
	rl.DrawRectangleRec(rect, fill)
	if active {
		rl.DrawRectangleRoundedLinesEx(rect, 0, 1, 1, UX.line)
		rl.DrawRectangle(i32(rect.x), i32(rect.y), 3, i32(rect.height), UX.info)
	}

	mark_size := int(min(f32(16), rect.height - 10))
	mark_x := int(math.round(f64(rect.x + 10)))
	mark_y := int(math.round(f64(rect.y + (rect.height - f32(mark_size)) / 2)))
	mark_color := enabled ? (selected ? UX.info : UX.dim) : UX.unavailable
	draw_selection_mark(mark_x, mark_y, mark_size, selected, radio, mark_color)

	draw_text_fitted(
		label,
		R(f32(mark_x + mark_size + 10), rect.y, rect.width - f32(mark_size) - 30, rect.height),
		TYPE_BODY_COMPACT,
		enabled ? UX.text : UX.unavailable,
	)
	return interaction.activated
}

radio_button :: proc(rect: rl.Rectangle, label: string, selected: bool, enabled := true) -> bool {
	return selection_control(rect, label, selected, enabled, true)
}

checkbox :: proc(rect: rl.Rectangle, label: string, checked: bool, enabled := true) -> bool {
	return selection_control(rect, label, checked, enabled, false)
}

tab :: proc(rect: rl.Rectangle, label: string, selected: bool, enabled := true) -> bool {
	index := ux_button_cursor
	ux_button_cursor += 1
	interaction := rl.ButtonBehavior(index, rect, enabled && !ux_pointer_input_blocked)
	active := interaction.hovered || interaction.focused
	fill := selected ? UX.raised : active && enabled ? rl.Color{24, 25, 23, 255} : UX.panel
	rl.DrawRectangleRec(rect, fill)
	if active do rl.DrawRectangleRoundedLinesEx(rect, 0, 1, 1, UX.text)
	if selected && enabled {
		rl.DrawRectangle(i32(rect.x), i32(rect.y + rect.height - 3), i32(rect.width), 3, UX.info)
	}
	draw_text_fitted(
		label,
		R(rect.x + 8, rect.y, rect.width - 16, rect.height - 3),
		TYPE_SMALL_EMPHASIS,
		enabled ? (selected ? UX.text : UX.dim) : UX.unavailable,
	)
	return interaction.activated
}

tab_group :: proc(rect: rl.Rectangle, labels: []string, selected: int, enabled := true) -> int {
	if len(labels) == 0 do return selected
	current := clamp(selected, 0, len(labels) - 1)
	for label, i in labels {
		cell := ui.gui_tab_rect({rect.x, rect.y, rect.width, rect.height}, len(labels), i)
		tab_rect := R(cell.x, cell.y, cell.w, cell.h)
		if tab(tab_rect, label, current == i, enabled) do current = i
		if i > 0 do rl.DrawLineEx(V(tab_rect.x, rect.y + 5), V(tab_rect.x, rect.y + rect.height - 5), 1, UX.line)
	}
	rl.DrawRectangleRoundedLinesEx(rect, 0, 1, 1, UX.line)
	return current
}

progress_bar :: proc(rect: rl.Rectangle, label: string, value: f32, color := UX.info) {
	progress := clamp(value, 0, 1)
	fill := ui.gui_progress_fill_rect({rect.x, rect.y, rect.width, rect.height}, progress)
	draw_text(label, rect.x, rect.y - 22, TYPE_LABEL, UX.dim)
	draw_fmt(rect.x + rect.width - 42, rect.y - 22, TYPE_LABEL, color, "%3.0f%%", progress * 100)
	rl.DrawRectangleRec(rect, rl.Color{5, 5, 5, 255})
	rl.DrawRectangleRec(R(fill.x, fill.y, fill.w, fill.h), rl.Color{color.r, color.g, color.b, 80})
	rl.DrawLineEx(V(fill.x, fill.y + fill.h), V(fill.x + fill.w, fill.y + fill.h), 3, color)
	rl.DrawRectangleRoundedLinesEx(rect, 0, 1, 1, UX.line)
}

loading_indicator :: proc(rect: rl.Rectangle, label: string, phase: f32 = 0) {
	draw_text(label, rect.x, rect.y - 22, TYPE_LABEL, UX.dim)
	rl.DrawRectangleRec(rect, rl.Color{5, 5, 5, 255})
	rl.DrawRectangleRoundedLinesEx(rect, 0, 1, 1, UX.line)
	segment := ui.gui_loading_segment_rect({rect.x, rect.y, rect.width, rect.height}, phase)
	if segment.w > 0 {
		rl.DrawRectangleRec(
			R(segment.x, segment.y, segment.w, segment.h),
			rl.Color{UX.info.r, UX.info.g, UX.info.b, 64},
		)
		rl.DrawLineEx(
			V(segment.x, segment.y + segment.h),
			V(segment.x + segment.w, segment.y + segment.h),
			3,
			UX.info,
		)
	}
}

draw_ui_knollboard :: proc() {
	rl.ClearBackground(UX.void)
	manga_backdrop()
	draw_text("INTERFACE KNOLLBOARD", 42, 34, TYPE_TITLE_LARGE, UX.text)
	draw_text("ARCHIVAL CONTROLS · REFERENCE STATES", 44, 72, TYPE_SMALL, UX.info)
	divider(42, 101, 1196)

	panel_w: f32 = 382
	panel_h: f32 = 244
	xs := [3]f32{42, 449, 856}
	ys := [2]f32{124, 390}

	panel(R(xs[0], ys[0], panel_w, panel_h), true)
	label_caps("TYPE SYSTEM", xs[0] + 22, ys[0] + 26, UX.info)
	draw_text("DISPLAY / 28", xs[0] + 22, ys[0] + 51, TYPE_TITLE_LARGE, UX.text)
	draw_text("HEADING / 20", xs[0] + 22, ys[0] + 91, TYPE_HEADING_COMPACT, UX.text)
	draw_text("BODY / 15 · Operational record", xs[0] + 22, ys[0] + 124, TYPE_BODY, UX.text)
	draw_text("LABEL / 12 · ARCHIVAL INDEX", xs[0] + 22, ys[0] + 154, TYPE_SMALL, UX.info)
	draw_text("CAPTION / 10 · RENDERS AT MIN 12", xs[0] + 22, ys[0] + 181, TYPE_CAPTION, UX.dim)
	draw_text("CAUTION · COMMITMENT · LOSS", xs[0] + 22, ys[0] + 207, TYPE_LABEL, UX.warn)

	panel(R(xs[1], ys[0], panel_w, panel_h), true)
	label_caps("ACTIONS", xs[1] + 22, ys[0] + 26, UX.info)
	draw_text("BUTTONS", xs[1] + 22, ys[0] + 51, TYPE_HEADING_COMPACT, UX.text)
	_ = button(R(xs[1] + 22, ys[0] + 91, 158, 38), "STANDARD")
	_ = button(R(xs[1] + 194, ys[0] + 91, 158, 38), "PRIMARY", true, true)
	_ = button(R(xs[1] + 22, ys[0] + 143, 158, 38), "UNAVAILABLE", false)
	draw_text(
		"Immediate command · accent marks priority.",
		xs[1] + 22,
		ys[0] + 207,
		TYPE_CAPTION,
		UX.dim,
	)

	panel(R(xs[2], ys[0], panel_w, panel_h), true)
	label_caps("NAVIGATION", xs[2] + 22, ys[0] + 26, UX.info)
	draw_text("TAB GROUP", xs[2] + 22, ys[0] + 51, TYPE_HEADING_COMPACT, UX.text)
	tab_labels := [3]string{"CURRENT", "ERAS", "INDEX"}
	_ = tab_group(R(xs[2] + 22, ys[0] + 91, 338, 36), tab_labels[:], 1)
	draw_text(
		"Exchanges the visible page in one context.",
		xs[2] + 22,
		ys[0] + 151,
		TYPE_CAPTION,
		UX.dim,
	)
	_ = tab_group(R(xs[2] + 22, ys[0] + 190, 338, 28), tab_labels[:], 0, false)

	panel(R(xs[0], ys[1], panel_w, panel_h), true)
	label_caps("SINGLE CHOICE", xs[0] + 22, ys[1] + 26, UX.info)
	draw_text("RADIO GROUP", xs[0] + 22, ys[1] + 51, TYPE_HEADING_COMPACT, UX.text)
	_ = radio_button(R(xs[0] + 22, ys[1] + 88, 338, 34), "BALANCED DOCTRINE", true)
	_ = radio_button(R(xs[0] + 22, ys[1] + 128, 338, 34), "CAUTIOUS SCREEN", false)
	_ = radio_button(R(xs[0] + 22, ys[1] + 168, 338, 34), "LAST STAND", false, false)
	draw_text("Exactly one option applies.", xs[0] + 22, ys[1] + 214, TYPE_CAPTION, UX.dim)

	panel(R(xs[1], ys[1], panel_w, panel_h), true)
	label_caps("MULTIPLE CHOICE", xs[1] + 22, ys[1] + 26, UX.info)
	draw_text("CHECKBOX GROUP", xs[1] + 22, ys[1] + 51, TYPE_HEADING_COMPACT, UX.text)
	_ = checkbox(R(xs[1] + 22, ys[1] + 88, 338, 34), "COMMON HEARTH", true)
	_ = checkbox(R(xs[1] + 22, ys[1] + 128, 338, 34), "RESOLUTE", false)
	_ = checkbox(R(xs[1] + 22, ys[1] + 168, 338, 34), "SHIP COMMITTED", false, false)
	draw_text(
		"Available rows select independently.",
		xs[1] + 22,
		ys[1] + 214,
		TYPE_CAPTION,
		UX.dim,
	)

	panel(R(xs[2], ys[1], panel_w, panel_h), true)
	label_caps("SYSTEM STATUS", xs[2] + 22, ys[1] + 26, UX.info)
	draw_text("PROGRESS / LOADERS", xs[2] + 22, ys[1] + 51, TYPE_HEADING_COMPACT, UX.text)
	progress_bar(R(xs[2] + 22, ys[1] + 109, 338, 12), "ARCHIVE RECONSTRUCTION", .62)
	progress_bar(R(xs[2] + 22, ys[1] + 157, 338, 12), "COHERENCE RESERVE", .28, UX.warn)
	loading_indicator(R(xs[2] + 22, ys[1] + 205, 338, 10), "READING FLEET RECORD", .58)

	// Renderer-boundary characterization strip. Keep each carrier visibly
	// distinct so a baseline diff identifies which generic draw path changed.
	strip := R(42, 652, 1196, 42)
	rl.BeginScissorMode(strip)
	rl.DrawRectangleRec(strip, rl.Color{4, 4, 4, 255})
	rl.DrawLineEx(V(42, 652), V(1238, 652), 1, UX.line)
	rl.DrawCircleV(V(65, 673), 10, UX.info)
	rl.DrawEllipseHatched(V(101, 673), 16, 9, UX.dim, LBH_HATCH_ENGRAVING, 24)
	rl.DrawQuadHatched(V(132, 660), V(216, 660), V(216, 686), V(132, 686), UX.text)
	graph_values := [?]f32{.12, .58, .31, .86, .43, .72}
	DrawBarGraph(R(235, 659, 180, 28), graph_values[:], UX.info, 0, 1)
	rl.DrawTexturePro(ship_component_texture, atlas_cell(0), R(438, 655, 34, 34), UX.text)
	draw_text("CLIPPED · HATCH · GRAPH · TEXTURE", 494, 664, TYPE_CAPTION, UX.dim)
	// Deliberately extends past the clip to make scissor regressions obvious.
	rl.DrawLineEx(V(1160, 673), V(1270, 673), 3, UX.warn)
	rl.EndScissorMode()
}

draw_ui_accents_knollboard :: proc() {
	rl.ClearBackground(UX.void)
	manga_backdrop()
	draw_text("INTERFACE KNOLLBOARD / II", 42, 34, TYPE_TITLE_LARGE, UX.text)
	draw_text("SEMANTIC INKS · SUPPORTING COMPONENTS", 44, 72, TYPE_SMALL, UX.info)
	divider(42, 101, 1196)

	panel(R(42, 124, 1196, 130), true)
	label_caps("SEMANTIC ACCENTS", 64, 150, UX.info)
	accent_names := [5]string{"INFORMATION", "FAVORABLE", "CAUTION", "DESTRUCTIVE", "COMMITMENT"}
	accent_notes := [5]string{"SELECTED", "SECURED", "AT RISK", "HULL LOSS", "IRREVERSIBLE"}
	accent_colors := [5]rl.Color{UX.info, UX.good, UX.warn, UX.bad, UX.committed}
	for color, i in accent_colors {
		x := 64 + f32(i) * 230
		rl.DrawRectangle(i32(x), 174, 5, 54, color)
		rl.DrawLineEx(V(x + 14, 180), V(x + 202, 180), 2, color)
		draw_text(accent_names[i], x + 14, 188, TYPE_SMALL, color)
		draw_text(accent_notes[i], x + 14, 210, TYPE_FINE, color)
	}

	panel_w: f32 = 382
	y: f32 = 280
	panel_h: f32 = 350
	xs := [3]f32{42, 449, 856}
	panel(R(xs[0], y, panel_w, panel_h), true)
	label_caps("SEQUENCE", xs[0] + 22, y + 26, UX.info)
	draw_text("PROGRESS STEPS", xs[0] + 22, y + 51, TYPE_HEADING_COMPACT, UX.text)
	steps := [4]string{"CHART", "CREW", "LOAD", "DEPART"}
	progress_steps(steps[:], 2, xs[0] + 22, y + 92, 338)
	divider(xs[0] + 22, y + 138, 338)
	label_caps("RESOURCE DELTAS", xs[0] + 22, y + 163, UX.dim)
	resource_delta(xs[0] + 22, y + 181, "PROPELLANT", 18, 12, icon = ICON_PROPELLANT)
	resource_delta(xs[0] + 22, y + 219, "SURVIVORS", 304, 327)
	resource_delta(xs[0] + 22, y + 257, "ARCHIVES", 7, 7)

	panel(R(xs[1], y, panel_w, panel_h), true)
	label_caps("DECISION", xs[1] + 22, y + 26, UX.committed)
	draw_text("CONSEQUENCE PREVIEW", xs[1] + 22, y + 51, TYPE_HEADING_COMPACT, UX.text)
	setup_preview_panel_resource_effect(
		R(xs[1] + 22, y + 86, 338, 132),
		"OPEN THE CORRESPONDENCE",
		"SPENDS",
		6,
		ICON_PROPELLANT,
		"· ADDS A PERMANENT ROUTE",
		UX.committed,
	)
	_ = button(R(xs[1] + 22, y + 240, 160, 40), "COMMIT", true, true)
	_ = button(R(xs[1] + 200, y + 240, 160, 40), "RETURN")
	draw_text("Violet marks a persistent precedent.", xs[1] + 22, y + 304, TYPE_CAPTION, UX.dim)

	panel(R(xs[2], y, panel_w, panel_h), true)
	label_caps("COMPOUND CONTROLS", xs[2] + 22, y + 26, UX.info)
	draw_text("ICONS / DISCLOSURE", xs[2] + 22, y + 51, TYPE_HEADING_COMPACT, UX.text)
	_ = icon_button(R(xs[2] + 22, y + 88, 158, 40), "ARCHIVE", ICON_ARCHIVE)
	_ = icon_button(R(xs[2] + 194, y + 88, 166, 40), "REPAIR", ICON_REPAIR, true, true)
	_ = icon_button(R(xs[2] + 22, y + 142, 158, 40), "LOCKED", ICON_LOCKED, false)
	warning_line(xs[2] + 22, y + 205, "SUPPLY MARGIN BELOW 20%")
	warning_line(xs[2] + 22, y + 233, "PRESSURE HULL BREACHED", true)
	_ = button(R(xs[2] + 22, y + 278, 188, 38), "INSPECT TERM")
	ux_tooltip = {
		visible = true,
		anchor  = R(xs[2] + 22, y + 278, 188, 38),
		title   = "CORRESPONDENCE",
		body    = "A verified route between two permanent fleet positions.",
	}
	draw_tooltip()
}

back_button :: proc(rect: rl.Rectangle, label: string, enabled := true, accent := false) -> bool {
	if ux_focus_back_requested && enabled {
		rl.FocusButton(ux_button_cursor)
		ux_focus_back_requested = false
	}
	return button(rect, label, enabled, accent)
}

// Context returns name their actual destination. Fleet navigation lives in the
// persistent top rail, so a page-local return should never silently claim it.
page_back_button :: proc(label: string) -> bool {
	return back_button(R(1152, 76, 100, 34), label)
}

// Persistent rail controls use the icon atlas directly, with a short hover
// record preserving the destination that their compact form omits.
rail_icon_button :: proc(rect: rl.Rectangle, icon: int, title, description: string, accent := false) -> bool {
	activated := button(rect, "", true, accent)
	size := min(rect.width - 12, rect.height - 12)
	rl.DrawIcon(icon, R(rect.x + (rect.width - size) / 2, rect.y + (rect.height - size) / 2, size, size), UX.text)
	if contains(rect) do ux_tooltip = {
		visible = true,
		anchor  = rect,
		title   = title,
		body    = description,
	}
	return activated
}

rail_menu_button :: proc(rect: rl.Rectangle) -> bool {
	activated := button(rect, "")
	center_x := rect.x + rect.width / 2
	center_y := rect.y + rect.height / 2
	rl.DrawLineEx(V(center_x - 8, center_y - 6), V(center_x + 8, center_y - 6), 2, UX.text)
	rl.DrawLineEx(V(center_x - 8, center_y), V(center_x + 8, center_y), 2, UX.text)
	rl.DrawLineEx(V(center_x - 8, center_y + 6), V(center_x + 8, center_y + 6), 2, UX.text)
	if contains(rect) do ux_tooltip = {
		visible = true,
		anchor  = rect,
		title   = "MENU",
		body    = "Open the campaign menu.",
	}
	return activated
}

icon_button :: proc(
	rect: rl.Rectangle,
	label: string,
	icon: int,
	enabled := true,
	accent := false,
) -> bool {
	activated := button(rect, "", enabled, accent)
	size := min(rect.height - 8, f32(24))
	rl.DrawIcon(
		icon,
		R(rect.x + 6, rect.y + (rect.height - size) / 2, size, size),
		enabled ? rl.Color{255, 255, 255, 255} : rl.Color{110, 120, 125, 180},
	)
	text_x := rect.x + size + 10
	draw_text_fitted(
		label,
		R(text_x, rect.y, rect.width - size - 16, rect.height),
		TYPE_BODY_EMPHASIS,
		enabled ? UX.text : UX.unavailable,
	)
	return activated
}

label_caps :: proc(text: string, x, y: f32, color := UX.dim) {
	rl.DrawLineEx(V(x, y - 4), V(x + 20, y - 4), 2, color)
	draw_text(text, x, y, TYPE_SMALL_EMPHASIS, color)
}
divider :: proc(x, y, w: f32) {rl.DrawLineEx(V(x, y), V(x + w, y), 1, UX.line)}

progress_steps :: proc(labels: []string, current: int, x, y, width: f32) {
	step_width := width / f32(len(labels))
	for label, i in labels {
		color := i < current ? UX.good : i == current ? UX.info : UX.unavailable
		rl.DrawRectangle(i32(x + f32(i) * step_width), i32(y), i32(step_width - 6), 3, color)
		draw_text(label, x + f32(i) * step_width, y + 10, TYPE_CAPTION, color)
	}
}

decision_panel :: proc(rect: rl.Rectangle, eyebrow, title: string, color := UX.info) {
	panel(rect, true)
	rl.DrawRectangle(i32(rect.x), i32(rect.y + 18), 4, i32(rect.height - 36), color)
	label_caps(
		eyebrow,
		rect.x + 22,
		rect.y + 18,
		color,
	); draw_text(title, rect.x + 22, rect.y + 43, TYPE_HEADING, UX.text); divider(rect.x + 22, rect.y + 76, rect.width - 44)
}

setup_preview_panel :: proc(rect: rl.Rectangle, title, effect: string, color := UX.info) {
	decision_panel(rect, "WHAT THIS CHANGES", title, color)
	draw_text_wrapped(
		effect,
		R(rect.x + 22, rect.y + 88, rect.width - 44, rect.height - 100),
		TYPE_BODY_COMPACT,
		color,
	)
}

setup_preview_panel_resource_effect :: proc(
	rect: rl.Rectangle,
	title, verb: string,
	amount, icon: int,
	remainder: string,
	color := UX.info,
) {
	decision_panel(rect, "WHAT THIS CHANGES", title, color)
	amount_text := fmt.tprintf("%s %d", verb, amount)
	paint_size := f32(TYPE_BODY_COMPACT); icon_gap: f32 = 5
	available := rect.width - 44
	amount_width := measure_text(amount_text, paint_size).x
	remainder_width := measure_text(remainder, paint_size).x
	total_width := amount_width + paint_size + icon_gap * 2 + remainder_width
	if total_width > available {
		paint_size = max(paint_size * available / total_width, f32(MIN_BODY_TEXT_SIZE))
		amount_width = measure_text(amount_text, paint_size).x
	}
	text_y := rect.y + 88 + (22 - paint_size) / 2
	x := rect.x + 22
	draw_text(amount_text, x, text_y, paint_size, color)
	x += amount_width + icon_gap
	rl.DrawIcon(icon, R(x, rect.y + 88 + (22 - paint_size) / 2, paint_size, paint_size), color)
	x += paint_size + icon_gap; draw_text(remainder, x, text_y, paint_size, color)
}

resource_delta :: proc(
	x, y: f32,
	label: string,
	before, after: i32,
	width := f32(270),
	icon := -1,
) {
	color := after < before ? UX.warn : after > before ? UX.good : UX.dim
	before_text := fmt.tprintf("%d", before)
	after_text := fmt.tprintf("%d", after)
	delta_text := after == before ? "—" : fmt.tprintf("%+d", after - before)
	before_width := measure_text(before_text, TYPE_SMALL).x
	after_width := measure_text(after_text, TYPE_SMALL).x
	delta_width := measure_text(delta_text, TYPE_LABEL).x
	icon_size: f32 = 14
	icon_gap := icon >= 0 ? icon_size + 4 : f32(0)
	before_x := icon >= 0 ? x + 12 : x + 102
	rail_start := before_x + before_width + icon_gap + 6
	rail_end := rail_start + 22
	after_x := rail_end + 6
	delta_x := after_x + after_width + icon_gap + 14
	content_width := delta_x + delta_width + 10 - x
	rect := R(x, y, min(width, max(content_width, icon >= 0 ? f32(138) : f32(210))), 32)
	rl.DrawRectangleRec(rect, {5, 5, 5, 255})
	rl.DrawRectangleRoundedLinesEx(rect, 0, 1, 1, UX.line)
	rl.DrawRectangle(i32(x), i32(y), 3, i32(rect.height), color)
	if icon < 0 do draw_text_fitted(label, R(x + 12, y, 82, rect.height), TYPE_LABEL, UX.text)
	draw_text(before_text, before_x, y + 9, TYPE_SMALL, UX.dim)
	draw_text(after_text, after_x, y + 9, TYPE_SMALL, color)
	if icon >= 0 {
		rl.DrawIcon(icon, R(before_x + before_width + 3, y + 9, icon_size, icon_size), UX.dim)
		rl.DrawIcon(icon, R(after_x + after_width + 3, y + 9, icon_size, icon_size), color)
	}
	rl.DrawLineEx(
		V(after_x, y + rect.height - 4),
		V(after_x + after_width + icon_gap, y + rect.height - 4),
		2,
		color,
	)

	rail_y := y + rect.height / 2
	rl.DrawLineEx(V(rail_start, rail_y), V(rail_end, rail_y), 1, color)
	if after == before {
		center_x := (rail_start + rail_end) / 2
		rl.DrawLineEx(V(center_x - 4, rail_y - 3), V(center_x + 4, rail_y - 3), 2, color)
		rl.DrawLineEx(V(center_x - 4, rail_y + 3), V(center_x + 4, rail_y + 3), 2, color)
	} else {
		rl.DrawLineEx(V(rail_end - 6, rail_y - 5), V(rail_end, rail_y), 2, color)
		rl.DrawLineEx(V(rail_end - 6, rail_y + 5), V(rail_end, rail_y), 2, color)
	}

	draw_text(delta_text, delta_x, y + 10, TYPE_LABEL, color)
}

warning_line :: proc(x, y: f32, text: string, severe := false) {
	rl.DrawCircleV(
		V(x + 5, y + 7),
		4,
		severe ? UX.bad : UX.warn,
	); draw_text(text, x + 16, y, TYPE_SMALL_EMPHASIS, severe ? UX.bad : UX.warn)
}

ux_save_path :: proc(
	autosave := true,
	allocator := context.temp_allocator,
) -> (
	string,
	bool,
) {base, err := os.user_data_dir(allocator); if err != nil do return "", false
	directory, join_err := os.join_path([]string{base, "Last Best Hope"}, allocator)
	if join_err != nil || os.make_directory_all(directory) != nil do return "", false
	path, path_err := os.join_path(
		[]string{directory, autosave ? "autosave.lbh" : "chronicle.lbh"},
		allocator,
	)
	return path, path_err == nil}

ux_autosave_exists :: proc() -> bool {path, ok := ux_save_path(true); return(
		ok &&
		os.is_file(path) \
	)}
