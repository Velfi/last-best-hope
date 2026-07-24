package main

import game "../packages/game"
import "core:testing"

// This file translates simulation-owned ship history into atlas-facing mark
// indices. It deliberately contains no progression thresholds or mutations.
ship_service_score :: proc(ship: game.Ship) -> int {
	return game.ship_service_score(ship)
}

ship_service_rank :: proc(ship: game.Ship) -> int {
	return int(game.ship_service_tier(ship)) - 1
}

ship_service_mark_visible :: proc(ship: game.Ship) -> bool {
	return game.ship_service_tier(ship) != .None
}

ship_history_mark_visible :: proc(ship: game.Ship) -> bool {
	return game.ship_promise_record(ship) != .None
}

ship_has_repair_memory :: proc(ship: game.Ship) -> bool {
	for i in 0 ..< ship.memory_count do if ship.memories[i].kind == .Ship_Repaired do return true
	return game.semantic_has(ship.archived_memory_tags, .Repair)
}

ship_damage_mark_visible :: proc(ship: game.Ship) -> bool {
	return ship.damage > 0 || ship.scar != .None || ship_has_repair_memory(ship)
}

@(test)
growth_mark_indices_are_absent_until_the_record_earns_them :: proc(t: ^testing.T) {
	ship := game.Ship {
		id                = 4,
		construction_seed = 44,
	}
	recipe := ship_render_recipe(ship)
	testing.expect_value(t, recipe.service_marking, -1)
	testing.expect_value(t, recipe.history_marking, -1)
	ship.experience = 1
	ship.promises_upheld = 1
	recipe = ship_render_recipe(ship)
	testing.expect(t, recipe.service_marking >= 12)
	testing.expect(t, recipe.history_marking >= 30)
}

@(test)
growth_mark_uses_latest_explicit_promise_outcome :: proc(t: ^testing.T) {
	ship := game.Ship {
		id                  = 9,
		construction_seed   = 99,
		promises_upheld     = 1,
		promises_broken     = 1,
		last_promise_event  = 23,
		last_promise_status = .Upheld,
	}
	upheld := ship_render_recipe(ship).history_marking
	upheld_attachment := ship_history_attachment_component(ship, ship_render_recipe(ship))
	ship.last_promise_event = 24
	ship.last_promise_status = .Broken
	broken := ship_render_recipe(ship).history_marking
	broken_attachment := ship_history_attachment_component(ship, ship_render_recipe(ship))
	testing.expect(t, upheld != broken)
	testing.expect(t, upheld_attachment != broken_attachment)
}
