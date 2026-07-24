package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:testing"

deep_exploration_restore_story :: proc(s: ^Ux_State) {
	if !s.deep_exploration_active do return
	game.campaign_destroy_heap(s.campaign)
	if s.deep_exploration_story_loaded {
		s.campaign = s.deep_exploration_story_campaign
	} else {
		game.campaign_destroy_heap(s.deep_exploration_story_campaign)
		s.campaign = new(game.Campaign)
	}
	s.deep_exploration_story_campaign = nil
	s.has_campaign = s.deep_exploration_story_available
	// The standalone session is entered from the main menu, so its inherited
	// return target may itself be the menu. Point Continue at the restored
	// Chronicle instead of routing straight back to the same menu.
	if s.deep_exploration_story_loaded {
		s.return_screen = s.campaign.passage.active ? .Passage : .Fleet
	}
	s.deep_exploration_active = false
	s.deep_exploration_story_loaded = false
	s.deep_exploration_story_available = false
	s.dark_course_draft = {}
	s.dark_selection_kind = .None
	s.status = ""
}

@(test)
deep_exploration_restore_story_restores_continue_target :: proc(t: ^testing.T) {
	s := ux_state_create()
	defer ux_state_destroy(s)
	s^ = Ux_State {
		campaign                         = s.campaign,
		return_screen                    = .Menu,
		deep_exploration_active          = true,
		deep_exploration_story_loaded    = true,
		deep_exploration_story_available = true,
	}
	s.deep_exploration_story_campaign = new(game.Campaign)
	game.campaign_init(s.deep_exploration_story_campaign, 41)
	deep_exploration_restore_story(s)
	testing.expect_value(t, s.has_campaign, true)
	testing.expect_value(t, s.return_screen, Ux_Screen.Fleet)
}

@(test)
deep_exploration_restore_story_discards_empty_parked_campaign :: proc(t: ^testing.T) {
	s := ux_state_create()
	defer ux_state_destroy(s)
	game.campaign_destroy_heap(s.campaign)
	s.campaign = game.new_campaign_seeded_heap(42)
	s.deep_exploration_story_campaign = new(game.Campaign)
	s.deep_exploration_active = true
	deep_exploration_restore_story(s)
	testing.expect(t, s.campaign != nil)
	testing.expect(t, s.deep_exploration_story_campaign == nil)
	testing.expect_value(t, s.has_campaign, false)
}

launch_deep_exploration :: proc(s: ^Ux_State) {
	seed := u64(rl.GetTime() * 1000000) + 1
	s.deep_exploration_story_campaign = s.campaign
	s.deep_exploration_story_loaded = s.has_campaign
	s.deep_exploration_story_available = s.has_campaign
	s.campaign = new(game.Campaign)
	game.campaign_init(s.campaign, seed)
	s.has_campaign = false
	s.deep_exploration_active = true
	contract := game.deep_exploration_contract(&s.deep_exploration_setup)
	indices: [game.MAX_EXPEDITION_SHIPS]int
	count := clamp(s.deep_exploration_setup.ship_count, 1, game.MAX_EXPEDITION_SHIPS)
	for i in 0 ..< count do indices[i] = i
	ok, message := game.begin_passage(s.campaign, contract, indices[:count], &s.campaign.passage)
	if !ok {
		deep_exploration_restore_story(s)
		s.status = message
		return
	}
	_, _ = game.set_dark_strategy(
		s.campaign,
		&s.campaign.passage,
		s.deep_exploration_setup.strategy,
	)
	s.dark_strategy = s.deep_exploration_setup.strategy
	s.dark_zoom = 1
	s.dark_pan_u, s.dark_pan_v = 0, 0
	s.dark_orientation = combat_default_orientation()
	s.dark_course_draft = {}
	s.dark_selection_kind = .None
	s.dark_contacts_open = false
	s.dark_comms_open = false
	s.dark_exit_confirm = false
	s.dark_intent_open = false
	s.dark_fine_plot_open = false
	s.dark_last_time = rl.GetTime()
	s.status = "Standalone expedition entered the Dark."
	s.screen = .Passage
}

@(test)
launch_deep_exploration_enters_standalone_passage :: proc(t: ^testing.T) {
	s := ux_state_create()
	defer ux_state_destroy(s)
	s.deep_exploration_setup = game.deep_exploration_default_setup()

	launch_deep_exploration(s)

	testing.expect(t, s.deep_exploration_active)
	testing.expect(t, s.campaign.passage.active)
	testing.expect_value(t, s.screen, Ux_Screen.Passage)
}

deep_exploration_setting_row :: proc(label, value: string, y: f32) {
	draw_text(label, 494, y + 8, TYPE_LABEL, UX.dim)
	draw_text_fitted(value, R(660, y, 260, 34), TYPE_BODY_EMPHASIS, UX.text)
}

deep_exploration_strategy_value :: proc(
	strategy: ^game.Dark_Strategy_Profile,
	row: int,
) -> string {
	switch row {
	case 0:
		switch strategy.depth {case .Shallow:
			return "SHALLOW"; case .Balanced:
			return "BALANCED"; case .Deep:
			return "DEEP"}
	case 1:
		switch strategy.course {case .Shortest_Metric:
			return "SHORTEST ROUTE"; case .Best_Mapped:
			return "BEST MAPPED"; case .Lowest_Coherence:
			return "LOWEST COHERENCE"}
	case 2:
		switch strategy.ecology {case .Avoidant:
			return "AVOID CONTACT"; case .Balanced:
			return "BALANCED"; case .Contact_Tolerant:
			return "TOLERATE CONTACT"}
	case 3:
		switch strategy.relay {case .Relay_First:
			return "RELAY FIRST"; case .Objective_First:
			return "OBJECTIVE FIRST"}
	case 4:
		switch strategy.withdrawal {case .Conservative:
			return "CONSERVATIVE"; case .Balanced:
			return "BALANCED"; case .Mission_First:
			return "MISSION FIRST"}
	}
	return ""
}

deep_exploration_strategy_effect :: proc(
	strategy: ^game.Dark_Strategy_Profile,
	row: int,
) -> string {
	switch row {
	case 0:
		switch strategy.depth {case .Shallow:
			return "Lower exposure; fewer deep shortcuts."; case .Balanced:
			return "Moderate depth and exposure."; case .Deep:
			return "More shortcuts; greater coherence exposure."}
	case 1:
		switch strategy.course {case .Shortest_Metric:
			return "Minimizes distance."; case .Best_Mapped:
			return "Favors topology confidence."; case .Lowest_Coherence:
			return "Favors lower coherence cost."}
	case 2:
		switch strategy.ecology {case .Avoidant:
			return "Stops when dangerous contacts appear."; case .Balanced:
			return "Stops for dangerous contacts."; case .Contact_Tolerant:
			return "Continues through dangerous contacts."}
	case 3:
		switch strategy.relay {case .Relay_First:
			return "Advises relay work after crossing."; case .Objective_First:
			return "Keeps attention on the objective."}
	case 4:
		switch strategy.withdrawal {case .Conservative:
			return "Stops at lower coherence exposure."; case .Balanced:
			return "Uses the standard exposure limit."; case .Mission_First:
			return "Permits greater coherence exposure."}
	}
	return ""
}

draw_deep_exploration_setup :: proc(s: ^Ux_State) {
	draw_stars()
	draw_text("DEEP EXPLORATION", 32, 26, TYPE_TITLE, UX.text)
	draw_text(
		"A standalone expedition. Its discoveries and damage do not enter the Chronicle.",
		32,
		66,
		TYPE_BODY_COMPACT,
		UX.dim,
	)

	panel(R(28, 104, 420, 520), true)
	label_caps("OBJECTIVE", 52, 130, UX.info)
	for purpose, i in game.DEEP_EXPLORATION_PURPOSES {
		if radio_button(R(52, 164 + f32(i) * 46, 372, 38), game.deep_exploration_purpose_name(purpose), s.deep_exploration_setup.purpose == purpose) do s.deep_exploration_setup.purpose = purpose
	}
	draw_text_wrapped(
		game.deep_exploration_purpose_description(s.deep_exploration_setup.purpose),
		R(52, 410, 360, 74),
		TYPE_BODY_COMPACT,
		UX.dim,
	)
	divider(52, 500, 372)
	label_caps("EXPEDITION", 52, 526, UX.info)
	if button(R(52, 554, 42, 36), "−", s.deep_exploration_setup.ship_count > 1) do s.deep_exploration_setup.ship_count -= 1
	draw_fmt(
		112,
		562,
		TYPE_BODY_EMPHASIS,
		UX.text,
		"%d SHIPS",
		s.deep_exploration_setup.ship_count,
	)
	if button(R(224, 554, 42, 36), "+", s.deep_exploration_setup.ship_count < game.MAX_EXPEDITION_SHIPS) do s.deep_exploration_setup.ship_count += 1
	draw_text("More ships add capability and exposure.", 282, 563, TYPE_SMALL, UX.dim)

	panel(R(466, 104, 480, 520), true)
	label_caps("COMMAND INTENT", 490, 130, UX.info)
	draw_text("These settings remain adjustable between legs.", 490, 158, TYPE_SMALL, UX.dim)
	strategy := &s.deep_exploration_setup.strategy
	rows := [5]string{"DEPTH", "ROUTE", "ECOLOGY", "RELAY", "WITHDRAWAL"}
	for label, i in rows {
		y := 210 + f32(i) * 68
		value := deep_exploration_strategy_value(strategy, i)
		deep_exploration_setting_row(label, value, y)
		draw_text(deep_exploration_strategy_effect(strategy, i), 660, y + 34, TYPE_MICRO, UX.dim)
		if button(R(842, y, 34, 34), "‹") {
			switch i {case 0:
				strategy.depth = game.Dark_Depth_Posture((int(strategy.depth) + 2) % 3); case 1:
				strategy.course = game.Dark_Course_Priority(
					(int(strategy.course) + 2) % 3,
				); case 2:
				strategy.ecology = game.Dark_Ecology_Posture(
					(int(strategy.ecology) + 2) % 3,
				); case 3:
				strategy.relay = game.Dark_Relay_Posture((int(strategy.relay) + 1) % 2); case 4:
				strategy.withdrawal = game.Dark_Withdrawal_Margin(
					(int(strategy.withdrawal) + 2) % 3,
				)}
		}
		if button(R(886, y, 34, 34), "›") {
			switch i {case 0:
				strategy.depth = game.Dark_Depth_Posture((int(strategy.depth) + 1) % 3); case 1:
				strategy.course = game.Dark_Course_Priority(
					(int(strategy.course) + 1) % 3,
				); case 2:
				strategy.ecology = game.Dark_Ecology_Posture(
					(int(strategy.ecology) + 1) % 3,
				); case 3:
				strategy.relay = game.Dark_Relay_Posture((int(strategy.relay) + 1) % 2); case 4:
				strategy.withdrawal = game.Dark_Withdrawal_Margin(
					(int(strategy.withdrawal) + 1) % 3,
				)}
		}
	}

	panel(R(964, 104, 288, 520), true)
	label_caps("SESSION RULES", 988, 130, UX.info)
	draw_text_wrapped(
		"The mode uses the full Dark simulation: continuous four-dimensional navigation, correspondence crossings, ecological contacts, coherence damage, relays, and return travel.",
		R(988, 170, 240, 180),
		TYPE_BODY_COMPACT,
		UX.text,
	)
	divider(988, 370, 240)
	draw_text_wrapped(
		"Returning to the main menu discards this session and restores the loaded Chronicle.",
		R(988, 398, 240, 100),
		TYPE_SMALL,
		UX.warn,
	)

	if back_button(R(32, 654, 180, 40), "MAIN MENU") do s.screen = .Menu
	if button(R(1012, 648, 240, 46), "BEGIN EXPEDITION", true, true) do launch_deep_exploration(s)
}
