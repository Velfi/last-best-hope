package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"

skirmish_archetype_index :: proc(archetype: game.Ship_Hull_Archetype) -> int {
	for candidate, i in game.SKIRMISH_ARCHETYPES do if candidate == archetype do return i
	return 0
}

skirmish_cycle_archetype :: proc(entry: ^game.Skirmish_Loadout_Entry, delta: int) {
	archetypes := game.SKIRMISH_ARCHETYPES
	count := len(archetypes)
	index := (skirmish_archetype_index(entry.archetype) + delta + count) % count
	entry.archetype = archetypes[index]
}

launch_skirmish :: proc(s: ^Ux_State) {
	seed := s.skirmish_setup.seed
	if seed == 0 {
		seed = u64(rl.GetTime() * 1000000) + 1
		s.skirmish_setup.seed = seed
	}
	if s.skirmish_setup.contract_seed == 0 do s.skirmish_setup.contract_seed = seed
	operation_planning_prepare_skirmish(s)
}

draw_skirmish_setup :: proc(s: ^Ux_State) {
	draw_stars()
	draw_text("SKIRMISH", 32, 26, TYPE_TITLE, UX.text)
	draw_text(
		"Configure the engagement. Loadout cost is recorded, not restricted.",
		32,
		66,
		TYPE_BODY_COMPACT,
		UX.dim,
	)

	panel(R(28, 104, 260, 520), true)
	label_caps("PARTICIPATING FACTIONS", 52, 130, UX.info)
	draw_text_wrapped(
		"One player force and the selected number of opposing contingents.",
		R(52, 158, 210, 48),
		TYPE_SMALL,
		UX.dim,
	)
	for count in game.SKIRMISH_MIN_FACTIONS ..= game.SKIRMISH_MAX_FACTIONS {
		label := fmt.tprintf("%d FACTIONS", count)
		if radio_button(R(52, 218 + f32(count - 2) * 44, 210, 36), label, s.skirmish_setup.faction_count == count) do s.skirmish_setup.faction_count = count
	}
	divider(52, 366, 210)
	label_caps("MISSION", 52, 390, UX.info)
	missions := [?]game.Skirmish_Mission_Kind {
		.Seedship_Recovery,
		.Fleet_Engagement,
		.Citadel_Assault,
		.Rearguard_Withdrawal,
		.Capital_Interception,
		.Reconnaissance,
		.Disabled_Ship_Rescue,
		.Relay_Control,
		.Convoy_Escort,
		.Contested_Salvage,
		.Repair_And_Tow,
		.Raid_And_Deploy,
	}
	for mission, i in missions {
		column := i / 7
		row := i % 7
		x := 36 + f32(column) * 126
		if radio_button(R(x, 420 + f32(row) * 28, 122, 24), game.skirmish_mission_name(mission), s.skirmish_setup.mission == mission) do s.skirmish_setup.mission = mission
	}

	panel(R(306, 104, 610, 520), true)
	label_caps("PLAYER LOADOUT", 330, 130, UX.info)
	draw_text("Cycle any hull and set its formation size.", 330, 158, TYPE_SMALL, UX.dim)
	draw_text("HULL", 414, 194, TYPE_LABEL, UX.dim)
	draw_text("SHIPS", 698, 194, TYPE_LABEL, UX.dim)
	draw_text("COST", 820, 194, TYPE_LABEL, UX.dim)
	contract := game.skirmish_generate_objectives(
		s.skirmish_setup.contract_seed,
		s.skirmish_setup.mission,
	)
	has_scan := false
	for objective in contract.objectives[:contract.count] do if objective.kind == .Scan_Anomaly do has_scan = true
	recovery_slot := game.skirmish_recovery_loadout_index(&s.skirmish_setup)
	strike_slot := game.skirmish_citadel_strike_loadout_index(&s.skirmish_setup)
	scan_slot := game.skirmish_scan_loadout_index(&s.skirmish_setup)
	for &entry, i in s.skirmish_setup.loadout {
		y := 222 + f32(i) * 50
		if button(R(330, y, 38, 34), "‹") do skirmish_cycle_archetype(&entry, -1)
		draw_ship_hull_archetype_icon(entry.archetype, R(376, y, 34, 34), UX.text)
		is_recovery :=
			(s.skirmish_setup.mission == .Seedship_Recovery ||
				s.skirmish_setup.mission == .Contested_Salvage ||
				s.skirmish_setup.mission == .Disabled_Ship_Rescue ||
				s.skirmish_setup.mission == .Repair_And_Tow) &&
			i == recovery_slot
		is_scan := has_scan && i == scan_slot
		if is_recovery || is_scan {
			draw_text_fitted(
				game.ship_hull_archetype_name(entry.archetype),
				R(414, y, 212, 20),
				TYPE_BODY_EMPHASIS,
				UX.text,
			)
			draw_text(
				is_recovery && is_scan ? "RECOVERY · ANOMALY SCAN" : is_recovery ? "RECOVERY ELEMENT" : "ANOMALY SCAN",
				414,
				y + 22,
				TYPE_MICRO,
				UX.info,
			)
		} else if s.skirmish_setup.mission == .Citadel_Assault && i == strike_slot {
			draw_text_fitted(
				game.ship_hull_archetype_name(entry.archetype),
				R(414, y, 212, 20),
				TYPE_BODY_EMPHASIS,
				UX.text,
			)
			draw_text("CITADEL STRIKE", 414, y + 22, TYPE_MICRO, UX.info)
		} else {
			draw_text_fitted(
				game.ship_hull_archetype_name(entry.archetype),
				R(414, y, 212, 34),
				TYPE_BODY_EMPHASIS,
				UX.text,
			)
		}
		if button(R(634, y, 38, 34), "›") do skirmish_cycle_archetype(&entry, 1)
		if button(R(690, y, 32, 34), "−", entry.ships > 1) do entry.ships -= 1
		draw_fmt(730, y + 8, TYPE_BODY, UX.text, "%d", entry.ships)
		if button(R(770, y, 32, 34), "+", entry.ships < 99) do entry.ships += 1
		draw_fmt(
			820,
			y + 8,
			TYPE_BODY,
			UX.info,
			"%d",
			game.skirmish_hull_cost(entry.archetype) * i64(entry.ships),
		)
	}

	panel(R(934, 104, 318, 520), true)
	label_caps("ENGAGEMENT RECORD", 958, 130, UX.info)
	draw_text(
		game.skirmish_mission_name(s.skirmish_setup.mission),
		958,
		166,
		TYPE_HEADING_COMPACT,
		UX.text,
	)
	draw_text_wrapped(
		game.skirmish_mission_description(s.skirmish_setup.mission),
		R(958, 202, 270, 58),
		TYPE_BODY_COMPACT,
		UX.dim,
	)
	divider(958, 276, 270)
	draw_fmt(
		958,
		296,
		TYPE_HEADING_COMPACT,
		UX.text,
		"%d SHIPS",
		game.skirmish_loadout_ship_count(&s.skirmish_setup),
	)
	draw_fmt(
		958,
		326,
		TYPE_BODY_EMPHASIS,
		UX.warn,
		"LOADOUT COST %d",
		game.skirmish_loadout_cost(&s.skirmish_setup),
	)
	if s.skirmish_setup.mission == .Seedship_Recovery ||
	   s.skirmish_setup.mission == .Contested_Salvage ||
	   s.skirmish_setup.mission == .Disabled_Ship_Rescue ||
	   s.skirmish_setup.mission == .Repair_And_Tow {
		if has_scan {
			draw_fmt(
				958,
				348,
				TYPE_MICRO,
				UX.info,
				"RECOVERY %.0f%% · SCAN %.0f%%",
				game.skirmish_recovery_loadout_rate(&s.skirmish_setup) * 100,
				game.skirmish_scan_loadout_rate(&s.skirmish_setup) * 100,
			)
		} else {
			draw_fmt(
				958,
				348,
				TYPE_MICRO,
				UX.info,
				"RECOVERY RATE %.0f%%",
				game.skirmish_recovery_loadout_rate(&s.skirmish_setup) * 100,
			)
		}
	}
	capability_ready := game.skirmish_primary_capability_ready(&s.skirmish_setup)
	if s.skirmish_setup.mission == .Citadel_Assault {
		draw_text(
			capability_ready ? "TORPEDO STRIKE READY" : "ADD A BOMBER OR TORPEDO BOAT",
			958,
			348,
			TYPE_MICRO,
			capability_ready ? UX.info : UX.bad,
		)
	}
	divider(958, 362, 270)
	label_caps("OBJECTIVE CONTRACT", 958, 382, UX.info)
	for objective, i in contract.objectives[:contract.count] {
		role := objective.optional ? "OPTIONAL" : "PRIMARY"
		draw_text_fitted(
			fmt.tprintf("%s · %s", role, game.skirmish_objective_name(objective.kind)),
			R(958, 410 + f32(i) * 31, 270, 24),
			TYPE_MICRO,
			objective.optional ? UX.dim : UX.text,
		)
	}
	draw_fmt(958, 508, TYPE_MICRO, UX.dim, "FIELD SEED    %016X", s.skirmish_setup.seed)
	draw_fmt(958, 520, TYPE_MICRO, UX.dim, "CONTRACT SEED %016X", s.skirmish_setup.contract_seed)
	if button(R(958, 544, 270, 34), "NEW CONTRACT") do game.skirmish_reroll_objectives(&s.skirmish_setup)

	if back_button(R(32, 654, 180, 40), "MAIN MENU") do s.screen = .Menu
	if button(R(1012, 648, 240, 46), "PLAN OPERATION", capability_ready, true) do launch_skirmish(s)
}
