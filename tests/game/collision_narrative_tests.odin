package game_tests

import "core:testing"

@(test)
collision_narrative_preview_is_pure_and_deterministic :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 15001)
	c.ships[3].damage = 3
	record_event(
		&c,
		.Ship_Damaged,
		"Resolute still carries the breach opened at Ilex Gate.",
		c.ships[3].id,
		3,
	)
	testing.expect(t, surface_interaction(&c))
	id := collision_id_for_situation(&c.current_situation)
	before_rng := c.rng_state; before_events := c.event_count
	a := narrative_view_for_collision(&c, id)
	b := narrative_view_for_collision(&c, id)
	testing.expect(t, a.valid && b.valid)
	testing.expect_value(t, a, b)
	testing.expect_value(t, c.rng_state, before_rng)
	testing.expect_value(t, c.event_count, before_events)
	testing.expect(t, a.manifestation.token != "")
	for fact in a.causes[:a.cause_count] do testing.expect(t, fact.token != "" && (fact.event == 0 || event_index_by_sequence(&c, fact.event) >= 0))
}

@(test)
collision_command_revalidates_identity_and_capacity :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 15002)
	c.ships[3].damage = 3
	record_event(&c, .Ship_Damaged, "Resolute carries recorded damage.", c.ships[3].id, 3)
	testing.expect(t, surface_interaction(&c))
	id := collision_id_for_situation(&c.current_situation)
	view := narrative_view_for_collision(&c, id)
	testing.expect(t, view.valid && view.affordance_count > 0)
	ok, _ := execute_collision_command(&c, Collision_ID(u64(id) + 1), view.affordances[0].id)
	testing.expect(t, !ok)
	testing.expect(t, c.current_situation.phase != .Resolved)
}

@(test)
fleet_collision_domains_expose_structured_stakes :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 15003)
	c.ships[3].damage = 3
	record_event(&c, .Ship_Damaged, "A recorded breach reduced repair margin.", c.ships[3].id, 3)
	testing.expect(t, surface_interaction(&c))
	view := narrative_view_for_collision(&c, collision_id_for_situation(&c.current_situation))
	testing.expect_value(t, view.domain, "CAPACITY")
	testing.expect_value(t, view.title, c.current_situation.title)
	testing.expect_value(t, view.stakes, c.current_situation.stakes)
	for affordance in view.affordances[:view.affordance_count] {
		testing.expect(t, affordance.id != 0)
		testing.expect(t, affordance.consequence != "")
		testing.expect(t, affordance.protects != "")
		testing.expect(t, affordance.exposes != "")
		testing.expect(t, affordance.cost != "")
		testing.expect(t, affordance.cause_event != 0)
	}
}

@(test)
collision_preview_names_capacity_shortfalls :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 15004)
	c.current_situation = {
		id           = 1,
		kind         = .Repair_Debt,
		phase        = .Decision,
		initiator    = c.ships[0].id,
		choice_count = 1,
	}
	c.current_situation.choices[0] = {
		label       = "Commit repair crews",
		consequence = "The ship receives a complete repair.",
		compute     = capacity_available(c.capacities.compute) + 2,
		manpower    = capacity_available(c.capacities.manpower) + 1,
	}
	view := narrative_view_for_collision(&c, collision_id_for_situation(&c.current_situation))
	testing.expect(t, !view.affordances[0].available)
	testing.expect_value(
		t,
		view.affordances[0].unavailable_reason,
		"NEEDS 2 MORE COMPUTE · NEEDS 1 MORE CREW",
	)
}
