package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"

draw_skirmish_objective_record :: proc(s: ^Ux_State) {
	if !s.combat.skirmish do return
	label_caps("OBJECTIVE CONTRACT", 700, 202, UX.info)
	for objective, i in s.combat.skirmish_objectives.objectives[:s.combat.skirmish_objectives.count] {
		met := game.skirmish_objective_met(&s.combat, objective.kind)
		role := objective.optional ? "OPTIONAL" : "PRIMARY"
		status := met ? "MET" : "UNMET"
		color := met ? UX.good : objective.optional ? UX.dim : UX.bad
		draw_text_fitted(
			fmt.tprintf(
				"%s · %s · %s",
				role,
				game.skirmish_objective_name(objective.kind),
				status,
			),
			R(700, 226 + f32(i) * 28, 285, 22),
			TYPE_MICRO,
			color,
		)
	}
}

draw_combat_result :: proc(s: ^Ux_State) {r := s.combat.result; rl.DrawRectangleRec(
		R(0, 0, 1280, 720),
		rl.Color{0, 0, 0, 220},
	)
	panel(R(245, 80, 790, 560), true)
	draw_text("OPERATION RECORD", 285, 112, TYPE_TITLE_LARGE, UX.text)
	draw_fmt(
		285,
		158,
		TYPE_BODY_COMPACT,
		UX.info,
		"DURATION %02d:%02d",
		int(r.mission_time) / 60,
		int(r.mission_time) % 60,
	)
	divider(285, 188, 710)
	draw_skirmish_objective_record(s)
	outcome := game.combat_result_outcome(&s.combat)
	outcome_text :=
		outcome == .Victory ? "VICTORY" : outcome == .Partial_Success ? "PARTIAL SUCCESS" : "DEFEAT"
	outcome_color := outcome == .Victory ? UX.good : outcome == .Partial_Success ? UX.warn : UX.bad
	draw_fmt(760, 158, TYPE_BODY_COMPACT, outcome_color, "%s", outcome_text)
	if s.combat.scenario == .Finale {
		draw_fmt(
			285,
			216,
			TYPE_BODY_EMPHASIS,
			r.strategic_asset_disabled ? UX.good : UX.bad,
			"CITADEL WEAPON       %s",
			r.strategic_asset_disabled ? "PERMANENTLY DISABLED" : "STILL OPERATIONAL",
		)
		draw_fmt(
			285,
			254,
			TYPE_BODY,
			r.player_ships_lost > 0 ? UX.warn : UX.text,
			"COALITION LOSSES     %d / 1,560 SHIPS",
			r.player_ships_lost,
		)
		draw_fmt(
			285,
			286,
			TYPE_BODY,
			UX.text,
			"DEFENDER LOSSES      %d / 640 SHIPS",
			r.enemy_ships_lost,
		)
		draw_fmt(
			285,
			324,
			TYPE_BODY_COMPACT,
			r.beam_shots > 0 ? UX.warn : UX.dim,
			"BEAM SHOTS %d · INDIVIDUAL SHIPS HIT %d",
			r.beam_shots,
			r.beam_ships_hit,
		)
		draw_fmt(
			285,
			360,
			TYPE_BODY,
			UX.text,
			"COMMAND ELEMENTS PRESERVED  %d / %d",
			r.friendly_preserved,
			r.friendly_total,
		)
		draw_fmt(
			285,
			396,
			TYPE_SMALL_EMPHASIS,
			r.ships_preserved < r.ships_total ? UX.warn : UX.text,
			"COALITION SHIPS ACTIVE %d / %d · DISABLED ELEMENTS %d",
			r.ships_preserved,
			r.ships_total,
			r.ships_disabled,
		)
		draw_text_wrapped(r.consequence, R(285, 456, 680, 66), TYPE_BODY_COMPACT, UX.text)
	}
	else if s.combat.skirmish &&
	   s.combat.skirmish_setup.mission != .Seedship_Recovery &&
	   s.combat.skirmish_setup.mission != .Contested_Salvage {
		draw_fmt(
			285,
			216,
			TYPE_BODY_EMPHASIS,
			r.ships_preserved > 0 ? UX.good : UX.bad,
			"PLAYER SHIPS ACTIVE       %d / %d",
			r.ships_preserved,
			r.ships_total,
		)
		draw_fmt(
			285,
			258,
			TYPE_BODY,
			r.player_ships_lost > 0 ? UX.warn : UX.text,
			"PLAYER SHIPS LOST         %d",
			r.player_ships_lost,
		)
		draw_fmt(
			285,
			300,
			TYPE_BODY,
			r.enemy_ships_lost > 0 ? UX.good : UX.text,
			"OPPOSING SHIPS LOST       %d",
			r.enemy_ships_lost,
		)
		draw_fmt(
			285,
			342,
			TYPE_BODY,
			UX.text,
			"COMMAND ELEMENTS PRESERVED  %d / %d",
			r.friendly_preserved,
			r.friendly_total,
		)
		draw_fmt(
			285,
			384,
			TYPE_SMALL_EMPHASIS,
			UX.info,
			"FACTIONS %d · ORDNANCE %d",
			s.combat.skirmish_setup.faction_count,
			r.heavy_ammunition,
		)
		draw_text_wrapped(r.consequence, R(285, 450, 680, 70), TYPE_BODY_COMPACT, UX.text)
	}
	else {
		population_status :=
			r.population > 0 ? "DELIVERED" : r.population_secured ? "SECURED · LEFT BEHIND" : "NOT SECURED"; archive_status := r.archive > 0 ? "DELIVERED" : r.archive_secured ? "SECURED · LEFT BEHIND" : "LEFT BEHIND"; fabrication_status := r.fabrication > 0 ? "DELIVERED" : r.fabrication_secured ? "SECURED · LEFT BEHIND" : "LEFT BEHIND"; draw_fmt(285, 216, TYPE_BODY_EMPHASIS, r.population > 0 ? UX.good : UX.bad, "POPULATION            %s", population_status); draw_fmt(285, 248, TYPE_BODY, r.archive > 0 ? UX.good : UX.dim, "GENETIC ARCHIVE       %s", archive_status); draw_fmt(285, 278, TYPE_BODY, r.fabrication > 0 ? UX.good : UX.dim, "FABRICATION CORE      %s", fabrication_status); draw_fmt(285, 310, TYPE_SMALL_EMPHASIS, r.sensor_data ? UX.good : UX.dim, "SENSOR FIX %s · ANOMALY DATA %s", r.sensor_data ? "RECOVERED" : "INCOMPLETE", r.anomaly_data ? "RECOVERED" : "INCOMPLETE"); draw_fmt(285, 340, TYPE_BODY, UX.text, "COMMAND ELEMENTS PRESERVED  %d / %d", r.friendly_preserved, r.friendly_total); draw_fmt(285, 370, TYPE_SMALL_EMPHASIS, r.ships_preserved < r.ships_total ? UX.warn : UX.text, "SHIPS EXTRACTED %d / %d · DISABLED %d", r.ships_preserved, r.ships_total, r.ships_disabled); draw_fmt(285, 400, TYPE_BODY, r.enemy_capital_disabled ? UX.good : UX.warn, "RAIDER CAPITAL              %s", r.enemy_capital_disabled ? "DISABLED" : "SURVIVING THREAT"); draw_fmt(285, 430, TYPE_BODY, UX.text, "OPTIONAL OBJECTIVES %d / 5 · ORDNANCE %d", r.optional_completed, r.heavy_ammunition); draw_fmt(
			720,
			430,
			TYPE_SMALL_EMPHASIS,
			r.casualties > 0 ? UX.warn : UX.text,
			"CASUALTIES %d",
			r.casualties,
		)
		draw_text_wrapped(r.consequence, R(285, 470, 680, 52), TYPE_BODY_COMPACT, UX.text)
	}
	if s.combat_campaign_active {
		if s.campaign.combat_operation.chain.active &&
		   button(R(285, 552, 190, 38), "PLAN FOLLOW-UP", true, true) {
			operation_planning_prepare_linked(s)
			return
		}
		if button(R(495, 552, 250, 38), "RETURN TO FLEET", true, true) {
			s.combat_campaign_active = false
			s.screen = .Fleet
		}
		if back_button(R(765, 552, 190, 38), "CHRONICLE") {
			s.combat_campaign_active = false
			open_chronicle_from(s, .Fleet)
		}
		return
	}
	if button(R(285, 552, 190, 38), "REPLAY OPERATION") {seed := s.combat.seed; heroism :=
			s.combat.heroism_scale
		skirmish := s.combat.skirmish
		skirmish_setup := s.combat.skirmish_setup
		scenario := s.combat.scenario
		next :=
			skirmish ? game.combat_new_skirmish_mission(seed, skirmish_setup) : scenario == .Finale ? game.combat_new_finale_mission(seed) : scenario == .Stress ? game.combat_new_stress_mission(seed) : game.combat_new_mission(seed, heroism)
		combat_replace_mission(s, next)
		s.combat.units[0].selected = true
		s.combat_selected = 0
		s.combat_briefing = true
		s.combat_last_time = rl.GetTime()}
	if button(R(495, 552, 190, 38), "NEW OPERATION") {seed := u64(rl.GetTime() * 1000000) + 1
		heroism := s.combat.heroism_scale
		skirmish := s.combat.skirmish
		skirmish_setup := s.combat.skirmish_setup
		scenario := s.combat.scenario
		if skirmish {
			s.skirmish_setup = game.skirmish_prepare_next_setup(skirmish_setup, seed)
			s.screen = .Skirmish_Setup
			return
		}
		next :=
			skirmish ? game.combat_new_skirmish_mission(seed, skirmish_setup) : scenario == .Finale ? game.combat_new_finale_mission(seed) : scenario == .Stress ? game.combat_new_stress_mission(seed) : game.combat_new_mission(seed, heroism)
		combat_replace_mission(s, next)
		s.combat.units[0].selected = true
		s.combat_selected = 0
		s.combat_briefing = true
		s.combat_last_time = rl.GetTime()}
	if back_button(R(705, 552, 190, 38), "RETURN TO MENU") do s.screen = .Menu
}
