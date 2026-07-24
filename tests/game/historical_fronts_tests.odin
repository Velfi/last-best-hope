package game_tests

import "core:testing"

@(test)
historical_front_can_escalate_dormant_return_and_transform :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c, 91)
	seed_front_families(&c)
	testing.expect(t, activate_front_proposal(&c, 0))
	id := c.fronts[0].id
	source := c.fronts[0].last_change_event
	c.season += 1
	testing.expect(t, advance_historical_fronts(&c))
	testing.expect(t, set_front_dormant(&c, id, source))
	c.season += 2
	testing.expect(t, advance_historical_fronts(&c))
	testing.expect(t, !c.fronts[0].dormant)
	testing.expect_value(t, c.events[c.event_count - 1].kind, Event_Kind.Front_Returned)
	testing.expect(t, transform_front(&c, id, .Changed_Authority, c.fronts[0].last_change_event))
	testing.expect_value(t, c.fronts[0].transformation, Front_Transformation.Changed_Authority)
	other: Campaign
	campaign_init(&other, 91)
	seed_front_families(&other)
	_ = activate_front_proposal(&other, 0)
	testing.expect(
		t,
		transform_front(
			&other,
			other.fronts[0].id,
			.Constrained_Route,
			other.fronts[0].last_change_event,
		),
	)
	testing.expect(t, other.fronts[0].transformation != c.fronts[0].transformation)}

@(test)
front_content_coverage_meets_family_and_role_gates :: proc(t: ^testing.T) {
	for kind in Front_Kind {
		coverage := front_family_coverage(kind)
		testing.expect(t, coverage.stage_count >= 3)
		testing.expect(t, coverage.transformation_count >= 3)
		testing.expect(t, coverage.dormant_callback)
		testing.expect(t, coverage.passage_interaction_count >= 1)
		values := front_family_transformations(kind)
		testing.expect(
			t,
			values[0] != values[1] && values[0] != values[2] && values[1] != values[2],
		)
	}
	roles := [8]Role {
		.Habitat,
		.Agriculture,
		.Foundry,
		.Archive,
		.Hospital,
		.Survey,
		.Escort,
		.Colony,
	}
	for role_index := 0; role_index < len(roles); role_index += 1 {role := roles[role_index]
		families := 0
		for kind in Front_Kind do if front_role_solution(kind, role) != .None do families += 1
		testing.expect(t, families >= 2)}}

@(test)
front_transformations_change_distinct_state :: proc(t: ^testing.T) {a: Campaign
	campaign_init(&a, 19)
	seed_front_families(&a)
	_ = activate_front_proposal(&a, 0)
	industry := fleet_supply(&a)
	_ = transform_front(&a, a.fronts[0].id, .Distributed_Cost, a.fronts[0].last_change_event)
	testing.expect(t, fleet_supply(&a) < industry)
	b: Campaign
	campaign_init(&b, 19)
	seed_front_families(&b)
	_ = activate_front_proposal(&b, 0)
	trust := b.communities[0].trust
	_ = transform_front(&b, b.fronts[0].id, .Broadened_Constituency, b.fronts[0].last_change_event)
	testing.expect(t, b.communities[0].trust > trust)
	c: Campaign
	campaign_init(&c, 19)
	seed_front_families(&c)
	_ = activate_front_proposal(&c, 0)
	cohesion := c.strategic.cohesion
	testing.expect(
		t,
		transform_front(&c, c.fronts[0].id, .Constrained_Route, c.fronts[0].last_change_event),
	)
	testing.expect(t, c.strategic.cohesion < cohesion)}

@(test)
low_pressure_front_persists_as_dormant_transformed_history :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c, 920)
	c.season = 4
	c.last_major_beat_season = -10
	testing.expect(t, advance_historical_fronts(&c))
	testing.expect(t, c.front_count >= 2)
	qualifying := 0
	for f in c.fronts[:c.front_count] do if !f.dormant || f.transformation != .None do qualifying += 1
	testing.expect(t, qualifying >= 2)
	testing.expect(t, c.fronts[1].dormant && c.fronts[1].transformation != .None)
	testing.expect(t, c.fronts[1].last_change_event != 0)}

@(test)
tempo_window_prevents_obligation_and_front_beats_from_stacking :: proc(t: ^testing.T) {tempos :=
		[2]Story_Tempo{Story_Tempo.Measured, Story_Tempo.Spacious}
	for tempo_index := 0; tempo_index < len(tempos); tempo_index += 1 {tempo := tempos[tempo_index]
		c: Campaign
		campaign_init(&c, 601)
		c.story_tempo = tempo
		c.season = 13
		c.last_major_beat_season = -3
		seed_front_families(&c)
		start := c.event_count
		advance_obligations(&c)
		_ = advance_historical_fronts(&c)
		major := 0
		for event in c.events[start:c.event_count] do if event.kind == .Need_Surfaced || event.kind == .Front_Proposed || event.kind == .Front_Advanced || event.kind == .Front_Returned do major += 1
		testing.expect(t, major <= 1)}}
