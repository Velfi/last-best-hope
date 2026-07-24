package main

import game "../packages/game"
import "core:fmt"

draw_research_direction :: proc(s: ^Ux_State) {
	panel(R(620, 360, 598, 240))
	draw_text("RESEARCH DIRECTION", 644, 385, TYPE_SUBHEADING_COMPACT)
	draw_fmt(
		644,
		414,
		TYPE_LABEL,
		UX.info,
		"DEPLOYABLE KNOWLEDGE %d · AVAILABLE MANPOWER %d",
		s.campaign.material_economy.knowledge.deployable_capacity,
		game.capacity_available(s.campaign.capacities.manpower),
	)
	support_ship := game.research_support_ship(s.campaign)
	for kind, i in game.Research_Kind {
		program := s.campaign.material_economy.research[i]
		knowledge, industry, manpower, duration, _ := game.research_terms(kind)
		y := f32(442 + i * 29)
		state :=
			program.completed ? "COMPLETE" : program.active ? (program.suspended ? "SUSPENDED" : fmt.tprintf("%d LEFT", program.remaining)) : fmt.tprintf("K%d G%d M%d · %dS", knowledge, industry, manpower, duration)
		draw_fmt(
			644,
			y + 5,
			TYPE_FINE,
			program.completed ? UX.good : program.suspended ? UX.warn : UX.text,
			"%v · %s",
			kind,
			state,
		)
		if !program.completed && !program.active {
			if button(
				R(1050, y, 140, 24),
				"BEGIN",
				support_ship != 0,
			) {r := execute_command(s, {kind = .Start_Research, research = kind, ship = support_ship}); s.status = r.message}
		} else if program.active {
			if button(
				R(1050, y, 140, 24),
				program.suspended ? "RESUME" : "SUSPEND",
				true,
			) {r := execute_command(s, {kind = .Suspend_Research, research = kind, flag = !program.suspended}); s.status = r.message}
		}
	}
}
