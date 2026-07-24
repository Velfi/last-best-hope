package main

import game "../packages/game"
import rl "zelda_engine:canvas2d"
import ui "zelda_engine:ui"
import "core:testing"

// The first-operation guide is deliberately small and state-driven. It teaches
// the commitment loop once, then leaves the expedition's actual decisions to
// the player instead of narrating every control in the Dark.
first_season_guide_is_available :: proc(s: ^Ux_State) -> bool {
	return s.has_campaign && !s.deep_exploration_active
}

@(test)
first_season_guide_is_singleplayer_only :: proc(t: ^testing.T) {
	s := ux_state_create()
	defer ux_state_destroy(s)
	s.has_campaign = true
	testing.expect(t, first_season_guide_is_available(s))
	s.deep_exploration_active = true
	testing.expect(t, !first_season_guide_is_available(s))
}

draw_first_season_guide :: proc(s: ^Ux_State) {
	if !first_season_guide_is_available(s) || s.guide_dismissed || s.campaign.season > 0 || s.campaign.guidance_step >= 9 || s.modal != .None do return
	if s.campaign.guidance_step >= 5 && !s.campaign.passage.active do return
	if s.screen != .Fleet && s.screen != .Care && s.screen != .Briefing && s.screen != .Passage do return

	// These transitions are consequences of play, not clicks on the guide.
	if s.campaign.guidance_step == 2 && fleet_passage_commission_ready(s.campaign) {
		game.guidance_advance(s.campaign)
		_ = ux_save(s, true)
	}
	if s.campaign.guidance_step == 3 && s.screen == .Briefing {
		game.guidance_advance(s.campaign)
		_ = ux_save(s, true)
	}

	step := clamp(int(s.campaign.guidance_step), 0, 5)
	titles := [6]string {
		"READ THE FLEET",
		"INSPECT A SHIP",
		"OPEN THE COMPACT",
		"REVIEW THE UNDERTAKING",
		"COMMISSION THE PASSAGE",
		"THE PASSAGE IS UNDER WAY",
	}
	messages := [6][2]string {
		{
			"Resources are shared across the fleet.",
			"Ships carry their damage and history forward.",
		},
		{
			"Select a ship to read its condition and record.",
			"A ship sent away is unavailable until it returns.",
		},
		{
			"A Compact call sets the purpose and contributors.",
			"Accept only the undertaking you are prepared to conduct.",
		},
		{
			"Check the route, objective, contributors, and exposure.",
			"Commissioning assigns the seconded ships to that record.",
		},
		{
			"Choose ships and examine the known forecast.",
			"Authorization commits the ships, supplies, and public contract.",
		},
		{
			"The fleet waits while the task group acts.",
			"Use the objective, reserves, and return margin to choose each leg.",
		},
	}
	prompts := [6]string {
		"BEGIN",
		"SELECT A SHIP",
		"OPEN COMPACT · ACCEPT A PASSAGE UNDERTAKING",
		"COMMISSION PASSAGE",
		"AUTHORIZE DEPARTURE",
		"TAKE COMMAND",
	}

	foci: [ui.GUI_SPOTLIGHT_MAX_FOCI]rl.Rectangle
	focus_count := 1
	card := R(28, 112, 402, 144)
	switch step {
	case 0:
		foci[0] = R(684, 0, 492, 54)
	case 1:
		foci[0] = R(28, 82, 792, 486)
		foci[1] = R(850, 72, 406, 500)
		focus_count = 2
		card = R(28, 505, 402, 144)
	case 2:
		if s.screen == .Care {
			foci[0] = R(28, 140, 1224, 480)
			card = R(688, 84, 402, 144)
		} else {
			foci[0] = R(581, 596, 130, 38)
		}
	case 3:
		if s.screen == .Care {
			foci[0] = R(644, 306, 608, 272)
			card = R(208, 84, 402, 144)
		} else {
			foci[0] = R(428, 596, 145, 38)
		}
	case 4:
		foci[0] = R(28, 130, 1224, 500)
		foci[1] = R(470, 520, 280, 44)
		focus_count = 2
		card = R(804, 84, 402, 144)
	case 5:
		foci[0] = R(20, 72, 972, 400)
		foci[1] = R(14, 574, 970, 76)
		focus_count = 2
		card = R(654, 430, 402, 144)
	}

	_ = spotlight(foci[:focus_count], 196, 7)
	decision_panel(card, step < 2 ? "FIRST COMMAND" : "FIRST PASSAGE", titles[step], UX.committed)
	for line, line_index in messages[step] do draw_text(line, card.x + 22, card.y + 75 + f32(line_index) * 15, MIN_BODY_TEXT_SIZE, UX.text)
	if button(R(card.x + 22, card.y + card.height - 28, 104, 22), "SKIP GUIDE") {
		game.guidance_advance(s.campaign, true)
		_ = ux_save(s, true)
	}
	if step == 0 || step == 5 {
		label := step == 0 ? "BEGIN" : "TAKE COMMAND"
		if button(
			R(card.x + card.width - 118, card.y + card.height - 28, 96, 22),
			label,
			true,
			true,
		) {
			if step == 0 do game.guidance_advance(s.campaign)
			else do game.guidance_advance(s.campaign, true)
			_ = ux_save(s, true)
		}
	} else {
		draw_text_fitted(
			prompts[step],
			R(card.x + 146, card.y + card.height - 27, card.width - 168, 20),
			TYPE_CAPTION,
			UX.info,
		)
	}
}
