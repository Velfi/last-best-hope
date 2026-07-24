package game_tests

import "core:fmt"
import "core:testing"

@(test)
repeated_attributable_damage_mothballs_and_surfaces_recovery :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c, 921)
	id := c.ships[0].id
	c.ships[0].damage = 2
	record_event(&c, .Ship_Damaged, "First attributable breach.", id, 2)
	c.ships[0].damage = 4
	record_event(&c, .Ship_Damaged, "Second attributable breach.", id, 2)
	cause := c.event_sequence
	testing.expect(t, surface_attributable_severe_setback(&c, id, cause))
	testing.expect(t, !c.ships[0].active)
	ci := ship_continuity_index(&c, id)
	testing.expect_value(t, c.transformations.continuity[ci].lifecycle, Ship_Lifecycle.Mothballed)
	testing.expect(t, c.obligations.count > 0)
	testing.expect_value(t, c.events[c.event_count - 1].kind, Event_Kind.Need_Surfaced)}

@(test)
rare_seeded_cumulative_damage_loss_is_bounded_and_surfaces_substitution :: proc(
	t: ^testing.T,
) {
	selected := 0
	chosen: u64
	for seed in u64(1) ..= u64(100) {
		if severe_damage_loss_selected(seed, 1) {
			selected += 1
			if chosen == 0 do chosen = seed
		}
	}
	testing.expect(t, selected >= 10 && selected <= 25)
	c: Campaign
	campaign_init(&c, chosen)
	id := c.ships[0].id
	for damage := 1; damage <= 3; damage += 1 {c.ships[0].damage = i32(damage + 2); record_event(
			&c,
			.Ship_Damaged,
			fmt.tprintf("Attributable damage %d.", damage),
			id,
			i32(damage),
		)}
	cause := c.event_sequence
	testing.expect(t, surface_attributable_severe_setback(&c, id, cause))
	testing.expect_value(t, c.ships[0].departure, Ship_Departure.Lost)
	testing.expect(t, !c.ships[0].active)
	testing.expect(t, c.obligations.count > 0)
	testing.expect_value(t, c.events[c.event_count - 1].kind, Event_Kind.Need_Surfaced)}

@(test)
seasonal_hazard_damage_enters_attributable_severe_path :: proc(t: ^testing.T) {c: Campaign
	campaign_init(&c, 17)
	id := c.ships[0].id
	c.ships[0].damage = 1
	record_event(&c, .Fleet_Hazard, "First seasonal strike.", id, 1)
	c.ships[0].damage = 3
	record_event(&c, .Fleet_Hazard, "Second seasonal strike.", id, 2)
	cause := c.event_sequence
	selected := severe_damage_loss_selected(c.initial_seed, id)
	testing.expect(t, surface_attributable_severe_setback(&c, id, cause))
	testing.expect(t, !c.ships[0].active)
	testing.expect(
		t,
		(selected && c.ships[0].departure == .Lost) ||
		(!selected && c.ships[0].departure != .Lost),
	)}

@(test)
volatile_seasonal_loss_sample_stays_bounded :: proc(t: ^testing.T) {
	losses := 0
	for seed in u64(1) ..= u64(100) {
		c: Campaign
		campaign_init(&c, seed)
		c.story_tempo = .Volatile
		for _ in 0 ..< 24 do advance_season(&c)
		lost := false
		for ship in c.ships[:c.ship_count] do if ship.departure == .Lost do lost = true
		if lost do losses += 1
	}
	testing.expect(t, losses >= 10 && losses <= 25)
}
