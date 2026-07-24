package game_tests

import "core:testing"

@(test)
deep_exploration_setup_produces_standalone_contract :: proc(t: ^testing.T) {
	setup := deep_exploration_default_setup()
	setup.purpose = .Ecological_Survey
	contract := deep_exploration_contract(&setup)
	testing.expect_value(t, contract.purpose, Dark_Contract_Purpose.Ecological_Survey)
	testing.expect_value(t, contract.undertaking_id, Compact_Undertaking_ID(0))
	testing.expect_value(t, contract.need_index, -1)
	testing.expect(t, contract.standalone)

	c: Campaign
	campaign_init(&c, 2200)
	defer campaign_destroy(&c)
	ships := [2]int{0, 1}
	ok, _ := begin_passage(&c, contract, ships[:], &c.passage)
	testing.expect(t, ok)
}

deep_exploration_begin_for_test :: proc(c: ^Campaign, purpose: Dark_Contract_Purpose) -> bool {
	setup := deep_exploration_default_setup()
	setup.purpose = purpose
	contract := deep_exploration_contract(&setup)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(c, contract, ships[:], &c.passage)
	return ok
}

@(test)
deep_exploration_auto_explore_starts_with_a_safe_first_leg :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 2200)
	defer campaign_destroy(&c)
	testing.expect(t, deep_exploration_begin_for_test(&c, .Map_Unknown_Door))

	ok, _ := order_systematic_dark_search(&c, &c.passage)
	testing.expect(t, ok)
	testing.expect(t, c.passage.systematic_search_active)
	testing.expect_value(t, c.passage.phase, Dark_Expedition_Phase.Underway)
	testing.expect(t, !passage_course_requires_emergency(&c, &c.passage, &c.passage.dark_navigation.course))
	testing.expect(t, passage_course_within_depth_envelope(&c, &c.passage, &c.passage.dark_navigation.course))
}

deep_exploration_cross_unknown_for_test :: proc(c: ^Campaign) -> bool {
	i := dark_nearest_unknown_door(&c.outer_dark.continuum, c.passage.dark_navigation.position)
	if i < 0 do return false
	c.passage.dark_navigation.position = c.outer_dark.continuum.doors[i].position
	ok, _ := cross_passage_door(c, &c.passage)
	return ok
}

@(test)
auto_explore_crosses_an_unknown_correspondence_before_retargeting :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 2200)
	defer campaign_destroy(&c)
	testing.expect(t, deep_exploration_begin_for_test(&c, .Ecological_Survey))
	first := dark_nearest_unknown_door(&c.outer_dark.continuum, c.passage.dark_navigation.position)
	testing.expect(t, first >= 0)
	first_id := c.outer_dark.continuum.doors[first].id
	c.passage.dark_navigation.position = c.outer_dark.continuum.doors[first].position
	c.passage.systematic_search_active = true

	_ = continue_systematic_dark_search(&c, &c.passage)

	testing.expect(t, dark_fleet_door_known(&c, first_id))
	testing.expect_value(t, c.passage.pending_door_id, first_id)
	testing.expect_value(t, c.passage.domain, Expedition_Domain.Dark)
}

@(test)
deep_exploration_door_objectives_have_playable_completion_paths :: proc(t: ^testing.T) {
	purposes := [2]Dark_Contract_Purpose {
		Dark_Contract_Purpose.Map_Unknown_Door,
		Dark_Contract_Purpose.Verify_Correspondence,
	}
	for purpose in purposes {
		c: Campaign
		campaign_init(&c, 2201 + u64(purpose))
		testing.expect(t, deep_exploration_begin_for_test(&c, purpose))
		testing.expect(t, deep_exploration_cross_unknown_for_test(&c))
		testing.expect(t, c.passage.contract.objective_met)
		campaign_destroy(&c)
	}
}

@(test)
deep_exploration_relay_objectives_have_playable_completion_paths :: proc(t: ^testing.T) {
	purposes := [2]Dark_Contract_Purpose {
		Dark_Contract_Purpose.Stabilize_Relay,
		Dark_Contract_Purpose.Infrastructure_Run,
	}
	for purpose in purposes {
		c: Campaign
		campaign_init(&c, 2211 + u64(purpose))
		testing.expect(t, deep_exploration_begin_for_test(&c, purpose))
		testing.expect(t, deep_exploration_cross_unknown_for_test(&c))
		if purpose == .Infrastructure_Run {
			// Choose a deterministic resource-bearing endpoint; completing the
			// objective must still require authenticating the route there.
			for neighborhood in 0 ..< c.galaxy.neighborhood_count {
				resource, _, valid := dark_endpoint_signals(&c, neighborhood)
				if valid && resource >= c.passage.contract.resource_threshold {
					c.passage.normal_course.start_neighborhood = neighborhood
					break
				}
			}
			testing.expect(t, !c.passage.contract.objective_met)
		}
		_, serviced, _ := service_passage_relay(&c, &c.passage)
		testing.expect(t, serviced)
		testing.expect(t, c.passage.contract.objective_met)
		campaign_destroy(&c)
	}
}

@(test)
deep_exploration_infrastructure_requires_resource_endpoint_and_relay :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 2219)
	defer campaign_destroy(&c)
	testing.expect(t, deep_exploration_begin_for_test(&c, .Infrastructure_Run))
	c.passage.domain = .Normal_Space
	c.passage.phase = .Awaiting_Leg

	low := -1
	high := -1
	for neighborhood in 0 ..< c.galaxy.neighborhood_count {
		resource, _, valid := dark_endpoint_signals(&c, neighborhood)
		if !valid do continue
		if resource < c.passage.contract.resource_threshold && low < 0 do low = neighborhood
		if resource >= c.passage.contract.resource_threshold && high < 0 do high = neighborhood
	}
	testing.expect(t, low >= 0 && high >= 0)
	if low < 0 || high < 0 do return

	c.passage.normal_course.start_neighborhood = low
	_, serviced, _ := service_passage_relay(&c, &c.passage)
	testing.expect(t, serviced)
	testing.expect(t, !c.passage.contract.objective_met)

	c.passage.normal_course.start_neighborhood = high
	_, serviced, _ = service_passage_relay(&c, &c.passage)
	testing.expect(t, serviced)
	testing.expect(t, c.passage.contract.objective_met)
}

@(test)
deep_exploration_ecology_objective_has_playable_completion_path :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 2221)
	defer campaign_destroy(&c)
	testing.expect(t, deep_exploration_begin_for_test(&c, .Ecological_Survey))

	d := &c.outer_dark.continuum
	// Four organism roles have already been recorded through normal tracker
	// contacts. Entering a visible wake field supplies the fifth ecology role.
	c.passage.observed_ecology_roles =
		c.passage.contract.required_ecology_roles &~ (1 << u32(Dark_Ecological_Role.Wake_Film))
	d.field_count = 1
	d.fields[0].position = c.passage.dark_navigation.position
	d.fields[0].radius = 1
	d.fields[0].film = .2
	c.passage.phase = .Underway
	c.passage.dark_navigation.manual_active = true
	c.passage.dark_navigation.manual_velocity = {.01, 0, 0, 0}
	advance_passage(&c, &c.passage, DARK_FIXED_STEP)

	testing.expect_value(
		t,
		c.passage.observed_ecology_roles,
		c.passage.contract.required_ecology_roles,
	)
	testing.expect(t, c.passage.contract.objective_met)
}
