package game_tests

import "core:testing"

law_test_enact :: proc(c: ^Campaign, kind: Precedent_Kind) -> Precedent_ID {
	record_event(c, .Situation_Decided, "A material fixture decision entered the record.")
	id, ok := enact_precedent_from_decision(
		c,
		{
			kind = kind,
			source_decision = c.event_sequence,
			detail = "A typed rule followed from the fixture decision.",
		},
	)
	if !ok do return 0
	return id
}

@(test)
all_value_pairs_have_bespoke_loss_aware_founding_scenarios :: proc(t: ^testing.T) {
	seen: [28]bool
	for a in 0 ..< 8 do for b in a + 1 ..< 8 {
		index := value_pair_index(Value_Kind(a), Value_Kind(b)); testing.expect(t, index >= 0 && index < 28); testing.expect(t, !seen[index]); seen[index] = true
		scenario := founding_value_scenario(Value_Kind(a), Value_Kind(b)); testing.expect(t, scenario.title != "" && scenario.premise != ""); testing.expect(t, scenario.first == Value_Kind(a) && scenario.second == Value_Kind(b))
		for loss in Loss_Kind do testing.expect(t, founding_loss_pressure(loss) != "")
	}
	for present in seen do testing.expect(t, present)
}

@(test)
all_28_pairs_commit_under_every_loss_and_three_responses :: proc(t: ^testing.T) {
	seed: u64 = 900
	for a in 0 ..< 8 do for b in a + 1 ..< 8 do for loss in Loss_Kind do for response in 0 ..< 3 {
		d := civilization_setup_generate(seed); seed += 1; d.choices[4] = a; d.choices[5] = b; d.loss_index = int(loss); d.founding_choice = response
		c: Campaign; ok, _ := civilization_setup_commit(&d, &c); testing.expect(t, ok); if !ok do continue
		testing.expect(t, c.values[0].kind == Value_Kind(a) && c.values[1].kind == Value_Kind(b)); testing.expect(t, c.founding_decision_event != 0 && event_reference_exists(&c, c.founding_decision_event))
		if response < 2 do testing.expect(t, c.precedent_count >= 1)
		campaign_destroy(&c)
	}
}

@(test)
every_value_supports_four_response_classes :: proc(t: ^testing.T) {
	for raw in 0 ..< 8 do for action in Precedent_Action {
		if action == .None do continue
		c: Campaign
		campaign_init(&c, u64(1200 + raw * 10 + int(action))); c.values[0].kind = Value_Kind(raw); c.values[1].kind = Value_Kind((raw + 1) % 8)
		id := law_test_enact(&c, value_primary_precedent(Value_Kind(raw))); testing.expect(t, id != 0)
		record_event(&c, .Situation_Decided, "The hard-case response entered the record."); source := c.event_sequence
		application, ok := record_precedent_application(&c, {domain = VALUE_HARD_CASES[raw].domain, source_decision = source, ship = c.ships[0].id, community = c.communities[0].id}, action)
		testing.expect(t, ok); testing.expect(t, application.classification == Precedent_Classification(int(action)))
		if action == .Exception || action == .Depart do testing.expect_value(t, c.precedent_case_count, 1)
		campaign_destroy(&c)
	}
}

@(test)
precedent_review_supports_all_four_resolutions :: proc(t: ^testing.T) {
	for resolution in Precedent_Review {
		c: Campaign
		campaign_init(
			&c,
			u64(1500 + int(resolution)),
		); primary := law_test_enact(&c, .No_One_Left_Behind); secondary := law_test_enact(&c, .Emergency_Command)
		record_event(
			&c,
			.Situation_Decided,
			"A rescue exception entered the record.",
		); _, ok := record_precedent_application(&c, {domain = .Rescue, source_decision = c.event_sequence, secondary_precedent = secondary}, .Exception); testing.expect(t, ok)
		case_record := c.precedent_cases[0]
		switch resolution {case .Affirm:
			ok = review_precedent_case(&c, case_record.id, resolution); case .Narrow:
			ok = review_precedent_case(
				&c,
				case_record.id,
				resolution,
				narrowed = .Attempt_Unless_Fleet_Collapse_Risk,
			); case .Replace:
			ok = review_precedent_case(
				&c,
				case_record.id,
				resolution,
				secondary,
			); case .Leave_Contested:
			ok = review_precedent_case(&c, case_record.id, resolution)}
		testing.expect(
			t,
			ok,
		); testing.expect(t, c.precedent_cases[0].status != .Pending); testing.expect(t, event_reference_exists(&c, c.precedents[precedent_index_by_id(&c, primary)].event_sequence)); campaign_destroy(&c)
	}
}

@(test)
full_case_collection_rejects_atomically :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1600,
	); kinds := [4]Precedent_Kind{.No_One_Left_Behind, .Accountable_Disclosure, .Consent_Of_The_Settled, .Right_Of_Refuge}; domains := [4]Precedent_Domain{.Rescue, .Disclosure, .Settlement_Charter, .Refuge}
	for i in 0 ..< 4 {
		_ = law_test_enact(
			&c,
			kinds[i],
		); record_event(&c, .Situation_Decided, "A contradiction entered the fixture record."); before := c.event_sequence; _, ok := record_precedent_application(&c, {domain = domains[i], source_decision = c.event_sequence}, .Depart)
		if i <
		   3 {testing.expect(t, ok)} else {testing.expect(t, !ok); testing.expect_value(t, c.event_sequence, before)}
	}
	testing.expect_value(t, c.precedent_case_count, MAX_PRECEDENT_CASES)
	old_id :=
		c.precedent_cases[0].id; testing.expect(t, review_precedent_case(&c, old_id, .Affirm))
	record_event(
		&c,
		.Situation_Decided,
		"A later contradiction entered the fixture record.",
	); _, ok := record_precedent_application(&c, {domain = domains[3], source_decision = c.event_sequence}, .Depart)
	testing.expect(
		t,
		ok,
	); testing.expect_value(t, c.precedent_case_count, MAX_PRECEDENT_CASES); testing.expect(t, c.precedent_cases[0].id != old_id); campaign_destroy(&c)
}

@(test)
failed_interaction_law_recording_restores_the_entire_decision :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1650); _ = law_test_enact(&c, .No_One_Left_Behind)
	kinds := [3]Precedent_Kind {
		.Accountable_Disclosure,
		.Consent_Of_The_Settled,
		.Right_Of_Refuge,
	}; domains := [3]Precedent_Domain{.Disclosure, .Settlement_Charter, .Refuge}
	for kind, i in kinds {_ = law_test_enact(&c, kind); record_event(
			&c,
			.Situation_Decided,
			"An unrelated contradiction filled a review slot.",
		)
		_, ok := record_precedent_application(
			&c,
			{domain = domains[i], source_decision = c.event_sequence},
			.Depart,
		)
		testing.expect(t, ok)}
	s, ok := make_value_hard_case(
		&c,
		0,
	); testing.expect(t, ok); record_event(&c, .Situation_Proposed, s.proposal); s.proposal_event = c.event_sequence; s.phase = .Decision; c.current_situation = s
	before_event :=
		c.event_sequence; before_precedents := c.precedent_count; before_cases := c.precedent_case_count
	testing.expect(
		t,
		!resolve_interaction(&c, 3),
	); testing.expect_value(t, c.event_sequence, before_event); testing.expect_value(t, c.precedent_count, before_precedents); testing.expect_value(t, c.precedent_case_count, before_cases); testing.expect_value(t, c.current_situation.phase, Situation_Phase.Decision); campaign_destroy(&c)
}

@(test)
value_status_is_derived_without_erasing_contradictions :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1660); law := law_test_enact(&c, .No_One_Left_Behind)
	record_event(
		&c,
		.Situation_Decided,
		"The rescue claim was followed.",
	); testing.expect(t, record_value_test(&c, .No_One_Left_Behind, true, c.event_sequence, law)); testing.expect_value(t, c.values[0].status, Value_Status.Embodied)
	record_event(
		&c,
		.Situation_Decided,
		"The rescue claim was contradicted.",
	); testing.expect(t, record_value_test(&c, .No_One_Left_Behind, false, c.event_sequence, law)); testing.expect_value(t, c.values[0].status, Value_Status.Compromised)
	record_event(
		&c,
		.Situation_Decided,
		"A later rescue followed the claim.",
	); testing.expect(t, record_value_test(&c, .No_One_Left_Behind, true, c.event_sequence, law)); testing.expect_value(t, c.values[0].status, Value_Status.Compromised)
	record_event(
		&c,
		.Situation_Decided,
		"The civilization renounced the claim.",
	); testing.expect(t, renounce_value(&c, .No_One_Left_Behind, c.event_sequence)); testing.expect_value(t, c.values[0].status, Value_Status.Renounced); campaign_destroy(&c)
}

@(test)
each_value_family_authors_distinct_hard_case_responses :: proc(t: ^testing.T) {
	for definition, i in VALUE_HARD_CASES {testing.expect(
			t,
			definition.choices[0].label != "" &&
			definition.choices[1].label != "" &&
			definition.choices[2].label != "" &&
			definition.choices[3].label != "",
		)
		for prior in VALUE_HARD_CASES[:i] do testing.expect(t, definition.choices[0].label != prior.choices[0].label)}
}

@(test)
rule_matching_is_independent_of_storage_order :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1700,
	); _ = law_test_enact(&c, .Shared_Authority); expected := law_test_enact(&c, .Ship_Sovereignty)
	ctx := Precedent_Context {
		domain          = .Authority,
		source_decision = c.event_sequence,
	}; a := precedent_application(
		&c,
		ctx,
		.Comply,
	); c.precedents[0], c.precedents[1] = c.precedents[1], c.precedents[0]; b := precedent_application(&c, ctx, .Comply)
	testing.expect_value(
		t,
		a.precedent,
		expected,
	); testing.expect_value(t, b.precedent, expected); campaign_destroy(&c)
}

@(test)
actor_specific_scope_precedes_newer_general_scope :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1725,
	); record_event(&c, .Situation_Decided, "A community-specific authority rule entered the record."); specific, _ := enact_precedent_from_decision(&c, {kind = .Shared_Authority, source_decision = c.event_sequence, detail = "The affected community must be represented.", beneficiary = c.communities[0].id})
	c.season += 1; general := law_test_enact(&c, .Ship_Sovereignty); a := precedent_application(&c, {domain = .Authority, community = c.communities[0].id}, .Comply); b := precedent_application(&c, {domain = .Authority, community = c.communities[1].id}, .Comply)
	testing.expect_value(
		t,
		a.precedent,
		specific,
	); testing.expect_value(t, b.precedent, general); campaign_destroy(&c)
}

@(test)
collision_attribution_keeps_the_cited_primary_rule :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1750,
	); primary := law_test_enact(&c, .No_One_Left_Behind); secondary := law_test_enact(&c, .Emergency_Command)
	record_event(&c, .Situation_Decided, "Emergency conservation contradicted the rescue rule.")
	a, ok := record_precedent_application(
		&c,
		{
			domain = .Rescue,
			primary_precedent = primary,
			secondary_precedent = secondary,
			source_decision = c.event_sequence,
		},
		.Exception,
	)
	testing.expect(
		t,
		ok,
	); testing.expect_value(t, a.precedent, primary); testing.expect_value(t, a.secondary, secondary)
	testing.expect_value(
		t,
		c.precedent_cases[0].primary,
		primary,
	); testing.expect_value(t, c.precedent_cases[0].secondary, secondary); campaign_destroy(&c)
}

@(test)
law_state_round_trips_and_version_59_is_rejected :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1800,
	); _ = law_test_enact(&c, .No_One_Left_Behind); record_event(&c, .Situation_Decided, "Emergency conservation entered the record."); _, ok := record_precedent_application(&c, {domain = .Rescue, source_decision = c.event_sequence}, .Exception); testing.expect(t, ok)
	data := campaign_serialize(
		&c,
	); restored: Campaign; result := campaign_deserialize(data[:], &restored); testing.expect(t, result.ok); if result.ok {testing.expect_value(t, restored.precedent_count, c.precedent_count); testing.expect_value(t, restored.precedent_case_count, c.precedent_case_count); campaign_destroy(&restored)}
	data[4] = 59; data[5] = 0; data[6] = 0; data[7] = 0; incompatible: Campaign; result = campaign_deserialize(data[:], &incompatible); testing.expect(t, !result.ok); delete(data); campaign_destroy(&c)
}

@(test)
format_60_rejects_incompatible_interpretations :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1810,
	); id := law_test_enact(&c, .No_One_Left_Behind); at := precedent_index_by_id(&c, id); c.precedents[at].interpretation = .Voluntary_Opt_In
	data := campaign_serialize(
		&c,
	); restored: Campaign; result := campaign_deserialize(data[:], &restored); testing.expect(t, !result.ok); delete(data); campaign_destroy(&c)
}

@(test)
settlement_records_orthogonal_procedural_rules :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1900,
	); record_event(&c, .Settlement_Decided, "A voluntary sovereign founding entered the record."); p := Settlement_Proposal {
		decision_event          = c.event_sequence,
		procedure               = .Voluntary_Opt_In,
		conduct                 = .Engineered_Departure,
		sovereign               = true,
		continuing_jurisdiction = true,
	}
	proposal_enact_precedents(&c, &p)
	testing.expect(
		t,
		has_precedent(&c, .Consent_Of_The_Settled),
	); testing.expect(t, has_precedent(&c, .Right_Of_Departure)); testing.expect(t, has_precedent(&c, .Proportionate_Asset_Division)); testing.expect(t, has_precedent(&c, .Founding_Independence)); testing.expect(t, has_precedent(&c, .Continuing_Fleet_Jurisdiction)); campaign_destroy(&c)
}
