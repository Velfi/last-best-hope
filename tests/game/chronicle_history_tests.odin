package game_tests

import "core:testing"

@(test)
hierarchical_archive_remains_bounded_through_ten_thousand_seasons :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 72); first := c.events[0].sequence
	for season in 1 ..= 10000 {c.season = i32(season); for _ in 0 ..< 4 do record_event(&c, .Resource_Changed, "Recorded stores.", value = i32(season))}
	testing.expect_value(
		t,
		c.chronicle_saturation_failures,
		i32(0),
	); testing.expect(t, c.archived_epoch_count > 0); testing.expect(t, c.archived_epoch_count <= MAX_ARCHIVED_EPOCHS); testing.expect(t, c.archived_era_count <= MAX_ARCHIVED_ERAS); testing.expect(t, event_reference_exists(&c, first)); testing.expect(t, event_reference_exists(&c, c.event_sequence))
}

@(test)
chronicle_compaction_preserves_live_references_and_archival_navigation :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		71,
	); protected := c.events[0].sequence; c.pending_accountability_event = protected
	for i in 0 ..< MAX_EVENTS -
		1 {c.season = i32(i / 8) + 3; record_event(&c, .Resource_Changed, "Recorded resource change.", value = i32(i))}
	testing.expect_value(
		t,
		c.event_count,
		MAX_EVENTS,
	); c.season = 100; record_event(&c, .Season_Advanced, "Later season.")
	testing.expect(
		t,
		c.chronicle_compactions > 0,
	); testing.expect_value(t, c.chronicle_saturation_failures, i32(0)); testing.expect(t, event_index_by_sequence(&c, protected) >= 0)
	testing.expect(
		t,
		c.archived_era_count > 0,
	); testing.expect(t, event_reference_exists(&c, c.archived_eras[0].first_sequence)); testing.expect(t, c.archived_eras[0].detail != "")
}
