package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"

combat_draw_briefing :: proc(s: ^Ux_State) {
	rl.DrawRectangleRec(R(0, 0, 1280, 720), UX.void)
	for i in 0 ..< 90 {x := f32((i * 107 + int(s.combat.seed % 97)) % 1280); y := f32((i * 61 + 13) % 720); rl.DrawRectangleRec(R(x, y, 1, 1), rl.Color{95, 95, 90, u8(35 + i % 45)})}
	panel(R(105, 70, 1070, 580), true)
	label_caps("PRE-BATTLE ORDERS", 145, 105, UX.info)
	draw_text(game.combat_mission_title(&s.combat), 145, 136, TYPE_TITLE, UX.text)
	draw_text_wrapped(
		"Set each task group's standing doctrine. These orders govern withdrawal limits, target priority, and unanswered command requests once contact begins.",
		R(145, 180, 990, 55),
		TYPE_BODY_COMPACT,
		UX.dim,
	)
	divider(145, 244, 990)
	combat_group_list(s, R(145, 275, 250, 150), 48, &s.combat_briefing_group_scroll)
	if s.combat.skirmish {
		label_caps("OBJECTIVE CONTRACT", 145, 414)
		for objective, i in s.combat.skirmish_objectives.objectives[:s.combat.skirmish_objectives.count] {
			role := objective.optional ? "OPTIONAL" : "PRIMARY"
			draw_text_fitted(
				fmt.tprintf("%s · %s", role, game.skirmish_objective_name(objective.kind)),
				R(145, 440 + f32(i) * 25, 250, 20),
				TYPE_MICRO,
				objective.optional ? UX.dim : UX.info,
			)
		}
	}
	u := &s.combat.units[clamp(s.combat_selected, 0, s.combat.friendly_count - 1)]
	draw_text_fitted(u.name, R(440, 275, 300, 31), TYPE_HEADING, UX.text)
	draw_fmt(
		440,
		316,
		TYPE_SMALL_EMPHASIS,
		UX.info,
		"%s · %v",
		s.combat.groups[u.group].name,
		u.doctrine,
	)
	draw_text_wrapped(u.history, R(440, 344, 300, 50), TYPE_SMALL, UX.dim)
	label_caps("FLEET FIRE CONTROL", 440, 414)
	modes := [3]game.Combat_Fire_Control {
		.Automatic,
		.Confirm_Costly,
		.Confirm_Engagements,
	}; labels := [3]string{"NO CONFIRM", "CONFIRM BIG", "CONFIRM ALL"}
	for mode, i in modes {if radio_button(R(440, 438 + f32(i) * 25, 300, 21), labels[i], s.combat.fire_control == mode) {s.combat.fire_control = mode; s.combat_fire_control_preference = mode; if s.combat_campaign_active {s.campaign.combat_fire_control_preference = mode; _ = ux_save(s, true)}}}
	label_caps("STANDING DOCTRINE", 790, 275)
	doctrines := [4]game.Combat_Doctrine{.Cautious_Screen, .Balanced, .Hunter_Killer, .Last_Stand}
	for d, i in doctrines {all_match := true; for ship in s.combat.units[:s.combat.friendly_count] do if combat_group_selected(s, ship.group) && ship.doctrine != d {all_match = false; break}
		if radio_button(
			R(790, 306 + f32(i) * 48, 300, 38),
			fmt.tprintf(
				"%v · FF ≤ %.0f%%",
				d,
				game.combat_doctrine_friendly_fire_tolerance(d) * 100,
			),
			all_match,
		) {for group in 0 ..< game.COMBAT_GROUP_COUNT do if combat_group_selected(s, group) {for ship, j in s.combat.units[:s.combat.friendly_count] do if ship.group == group do game.combat_set_doctrine(&s.combat, j, d)}}}
	divider(145, 520, 990)
	draw_text(
		"Doctrine sets intent. Fire control sets command authority.",
		145,
		548,
		TYPE_SMALL_EMPHASIS,
		UX.warn,
	)
	if button(
		R(790, 548, 300, 46),
		"BEGIN ENGAGEMENT",
		true,
		true,
	) {s.combat_briefing = false; s.combat_last_time = rl.GetTime()}
}
