package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"

draw_food_shortage_modal :: proc(s: ^Ux_State) {
	m := &s.campaign.material_economy; episode := m.food_shortage_episode
	rl.DrawRectangle(0, 0, UX_W, UX_H, {0, 0, 0, 205}); panel(R(150, 82, 980, 556), true)
	label_caps(fmt.tprintf("FOOD ALLOCATION · EPISODE %d", episode.id), 184, 112, UX.warn)
	draw_text("SECURE SUPPLY HAS FAILED", 184, 137, TYPE_TITLE_COMPACT, UX.text)
	draw_fmt(
		184,
		178,
		TYPE_BODY_COMPACT,
		UX.warn,
		"PRODUCTION %d + IMPORTS %d − CONSUMPTION %d = DEFICIT %d",
		episode.production,
		episode.imports,
		episode.consumption,
		episode.deficit,
	)
	draw_text_wrapped(
		"The season cannot advance until the fleet adopts a persistent response. Costs are applied immediately.",
		R(184, 207, 900, 42),
		TYPE_SMALL_EMPHASIS,
		UX.dim,
	)
	commands := [6]game.Food_Shortage_Command {
		.Invest_Capacity,
		.Import_Route,
		.Change_Diet,
		.Ration,
		.Reduce_Growth,
		.Contract_Habitat,
	}
	for command, i in commands {
		terms := game.food_shortage_response_terms(command)
		column := i % 2; row := i / 2; x := f32(184 + column * 452); y := f32(252 + row * 104)
		available := game.food_shortage_command_legal(s.campaign, command)
		panel(R(x, y, 440, 94), available)
		if button(R(x + 12, y + 12, 142, 68), terms.label, available) {
			autosave_before(
				s,
			); r := execute_command(s, {kind = .Resolve_Food_Shortage, target = int(command)}); s.status = r.message
			if r.ok do s.modal = .None
		}
		draw_fmt(
			x + 168,
			y + 10,
			TYPE_LABEL,
			available ? UX.info : UX.unavailable,
			"COST · %s",
			terms.cost,
		)
		draw_text_wrapped(terms.effect, R(x + 168, y + 28, 254, 30), TYPE_SMALL, UX.text)
		draw_text_wrapped(terms.tradeoff, R(x + 168, y + 59, 254, 28), TYPE_FINE, UX.dim)
	}
	if !game.food_shortage_command_legal(s.campaign, .Import_Route) do draw_text("IMPORTS REQUIRE A KNOWN ROUTE OR SETTLEMENT.", 184, 574, TYPE_CAPTION, UX.warn)
	draw_text(
		"COMMUNITY MIGRATION IS PLANNED FROM A SETTLEMENT'S POPULATION LEDGER.",
		184,
		596,
		TYPE_FINE,
		UX.dim,
	)
	if button(R(938, 594, 158, 30), "REVIEW FLEET") do s.modal = .None
}
