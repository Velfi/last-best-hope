package game_tests

import "core:testing"

@(test)
narrative_selection_is_seeded_and_order_independent :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 14001)
	b: Campaign
	campaign_init(&b, 14001)
	candidates := [3]Narrative_Candidate {
		{domain = .Public_Question, priority = .Developing, stable_id = 11, urgency = 10},
		{domain = .Public_Question, priority = .Developing, stable_id = 22, urgency = 10},
		{domain = .Public_Question, priority = .Developing, stable_id = 33, urgency = 10},
	}
	reversed := [3]Narrative_Candidate{candidates[2], candidates[1], candidates[0]}
	left, left_ok := narrative_select_candidate(&a, candidates[:])
	right, right_ok := narrative_select_candidate(&b, reversed[:])
	testing.expect(t, left_ok && right_ok)
	testing.expect_value(t, left.stable_id, right.stable_id)
	testing.expect_value(t, a.rng_state, b.rng_state)
}

@(test)
narrative_priority_overrides_seeded_ties :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 14002)
	candidates := [2]Narrative_Candidate {
		{domain = .Historical_Front, priority = .Developing, stable_id = 1, urgency = 100},
		{domain = .Public_Question, priority = .Mandatory, stable_id = 2, urgency = 1},
	}
	selected, ok := narrative_select_candidate(&c, candidates[:])
	testing.expect(t, ok)
	testing.expect_value(t, selected.stable_id, u64(2))
}

@(test)
narrative_ties_vary_across_campaign_seeds_without_consuming_rng :: proc(t: ^testing.T) {
	candidates := [3]Narrative_Candidate {
		{domain = .Public_Question, priority = .Developing, stable_id = 101, urgency = 10},
		{domain = .Public_Question, priority = .Developing, stable_id = 202, urgency = 10},
		{domain = .Public_Question, priority = .Developing, stable_id = 303, urgency = 10},
	}
	seen: [3]bool
	for seed in u64(1) ..= u64(32) {
		c: Campaign
		campaign_init(&c, seed); before_state, before_sequence := c.rng_state, c.rng_sequence
		selected, ok := narrative_select_candidate(&c, candidates[:]); testing.expect(t, ok)
		for value, i in candidates do if value.stable_id == selected.stable_id do seen[i] = true
		testing.expect_value(
			t,
			c.rng_state,
			before_state,
		); testing.expect_value(t, c.rng_sequence, before_sequence)
	}
	count := 0; for value in seen do if value do count += 1
	testing.expect(t, count >= 2)
}

@(test)
narrative_director_round_trip_preserves_next_selection :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 14003)
	c.season = 4; c.last_major_beat_season = -3
	c.needs[0] = {
		active       = true,
		kind         = .Ship_Repair,
		ship         = c.ships[0].id,
		community    = c.communities[0].id,
		deadline     = 5,
		source_event = c.event_sequence,
		detail       = "Repair alpha.",
	}
	c.needs[1] = {
		active       = true,
		kind         = .Representation,
		ship         = c.ships[1].id,
		community    = c.communities[1].id,
		deadline     = 5,
		source_event = c.event_sequence,
		detail       = "Hear beta.",
	}
	data := campaign_serialize(&c); defer delete(data)
	restored: Campaign; defer campaign_destroy(&restored); result := campaign_deserialize(data[:], &restored); testing.expect(t, result.ok)
	left: [MAX_NARRATIVE_CANDIDATES]Narrative_Candidate; right: [MAX_NARRATIVE_CANDIDATES]Narrative_Candidate
	left_count := collect_public_question_candidates(
		&c,
		left[:],
	); right_count := collect_public_question_candidates(&restored, right[:])
	a, a_ok := narrative_select_candidate(
		&c,
		left[:left_count],
	); b, b_ok := narrative_select_candidate(&restored, right[:right_count])
	testing.expect(t, a_ok && b_ok); testing.expect_value(t, a.stable_id, b.stable_id)
}

@(test)
legacy_narrative_rules_save_is_rejected_cleanly :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 14004); data := campaign_serialize(&c); defer delete(data)
	data[4] = 63; data[5] = 0; data[6] = 0; data[7] = 0
	restored: Campaign; result := campaign_deserialize(data[:], &restored)
	testing.expect(t, !result.ok)
	testing.expect_value(
		t,
		result.message,
		"This campaign predates centralized narrative scheduling; begin a new chronicle.",
	)
}
