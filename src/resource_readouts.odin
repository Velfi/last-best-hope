package main

import game "../packages/game"
import "core:fmt"
import rl "zelda_engine:canvas2d"

// Quantities use a number followed by its monochrome unit glyph. Returning the
// painted width lets dense ledgers compose several resources without padded
// text columns or repeating resource names.
draw_resource_amount :: proc(
	x, y: f32,
	value: $T,
	icon: int,
	color := UX.text,
	size := f32(TYPE_LABEL),
) -> f32 {
	value_text := fmt.tprintf("%d", value)
	value_width := measure_text(value_text, size).x
	draw_text(value_text, x, y, size, color)
	icon_size := size
	rl.DrawIcon(icon, R(x + value_width + 3, y, icon_size, icon_size), color)
	return value_width + 3 + icon_size
}

draw_resource_ratio :: proc(
	x, y: f32,
	value, available: $T,
	icon: int,
	color := UX.text,
	size := f32(TYPE_LABEL),
) -> f32 {
	value_text := fmt.tprintf("%d/%d", value, available)
	value_width := measure_text(value_text, size).x
	draw_text(value_text, x, y, size, color)
	rl.DrawIcon(icon, R(x + value_width + 3, y, size, size), color)
	return value_width + 3 + size
}

fleet_stock_value :: proc(stock: game.Fleet_Stock, index: int) -> i64 {
	switch index {
	case 0:
		return stock.food
	case 1:
		return stock.raw_materials
	case 2:
		return stock.manufactured_goods
	case 3:
		return stock.equipment
	case 4:
		return stock.propellant
	case 5:
		return stock.supplies
	case 6:
		return stock.services
	}
	return 0
}

// The rail stays icon-first and glanceable. Pointer hover opens the season
// ledger, using the graph primitive for sources above zero and drains below
// it—the same hierarchy as a grand-strategy top bar without importing its
// ornamental treatment.
draw_fleet_resource_cell :: proc(
	s: ^Ux_State,
	rect: rl.Rectangle,
	index: int,
	label: string,
	icon: int,
) {
	e := s.campaign.material_economy.fleet
	value := fleet_stock_value(e.stock, index)
	produced := fleet_stock_value(e.season.produced, index)
	imported := fleet_stock_value(e.season.imported, index)
	consumed := fleet_stock_value(e.season.consumed, index)
	exported := fleet_stock_value(e.season.exported, index)
	lost := fleet_stock_value(e.season.lost, index)
	delta := produced + imported - consumed - exported - lost
	color := value <= 0 ? UX.bad : (delta < 0 ? UX.warn : UX.text)

	rl.DrawIcon(icon, R(rect.x + 7, rect.y + 9, 20, 20), color)
	draw_fmt(rect.x + 31, rect.y + 9, TYPE_BODY_COMPACT, color, "%d", value)
	if delta != 0 do draw_fmt(rect.x + 31, rect.y + 27, TYPE_FINE, delta > 0 ? UX.good : UX.warn, "%+d", delta)

	if tooltip_hover_target(rect, label, "") {
		ux_tooltip.body = fmt.tprintf("%d held · net %+d this season", value, delta)
		ux_tooltip.graph_visible = true
		ux_tooltip.graph_value_count = 5
		ux_tooltip.graph_values = {
			f32(produced),
			f32(imported),
			-f32(consumed),
			-f32(exported),
			-f32(lost),
		}
	}
}

draw_capacity_cell :: proc(rect: rl.Rectangle, label: string, icon: int, capacity: game.Capacity) {
	available := game.capacity_available(capacity)
	state := game.capacity_state(capacity)
	color := state == "AVAILABLE" ? UX.good : (state == "STRAINED" ? UX.warn : UX.bad)
	rl.DrawIcon(icon, R(rect.x + 7, rect.y + 9, 20, 20), color)
	draw_fmt(rect.x + 31, rect.y + 9, TYPE_BODY_COMPACT, UX.text, "%d", available)
	draw_text(state, rect.x + 31, rect.y + 27, TYPE_FINE, color)
	_ = tooltip_hover_target(
		rect,
		label,
		fmt.tprintf(
			"%d available · %d reserved · %d damaged · %d total",
			available,
			capacity.reserved,
			capacity.damaged,
			capacity.total,
		),
	)
}
