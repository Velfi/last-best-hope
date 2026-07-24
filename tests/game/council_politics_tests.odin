package game_tests

import "core:fmt"
import "core:testing"

@(test)
council_is_deterministic_for_seed_and_direction :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 7101); b: Campaign
	campaign_init(
		&b,
		7101,
	); seed_front_families(&a); seed_front_families(&b); _ = activate_front_proposal(&a, 0); _ = activate_front_proposal(&b, 0)
	testing.expect(
		t,
		choose_political_direction(&a, .Front, 0, 1),
	); testing.expect(t, choose_political_direction(&b, .Front, 0, 1))
	for _ in 0 ..< 5 {advance_council_enactment(&a); advance_council_enactment(&b); testing.expect_value(t, a.council.phase, b.council.phase); testing.expect_value(t, a.council.last_outcome, b.council.last_outcome); testing.expect_value(t, a.council.momentum, b.council.momentum); testing.expect_value(t, a.council.setbacks, b.council.setbacks)}
}

@(test)
council_checkpoints_cover_phases_momentum_failure_and_cooldown :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		7102,
	); seed_front_families(&c); _ = activate_front_proposal(&c, 0); testing.expect(t, choose_political_direction(&c, .Front, 0, 0))
	resolve_council_checkpoint(
		&c,
		.Advance,
	); testing.expect_value(t, c.council.momentum, i32(10)); resolve_council_checkpoint(&c, .Success); testing.expect_value(t, c.council.phase, Council_Phase.Deliberation); resolve_council_checkpoint(&c, .Success); testing.expect_value(t, c.council.phase, Council_Phase.Ratification)
	resolve_council_checkpoint(
		&c,
		.Stall,
	); resolve_council_checkpoint(&c, .Stall); resolve_council_checkpoint(&c, .Stall); testing.expect_value(t, c.council.phase, Council_Phase.Failed); testing.expect(t, !choose_political_direction(&c, .Front, 0, 0)); c.season = c.council.cooldown_until; testing.expect(t, choose_political_direction(&c, .Front, 0, 1))
}

@(test)
cancelling_council_direction_spends_cohesion_and_cools_source :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		7106,
	); seed_front_families(&c); _ = activate_front_proposal(&c, 0); testing.expect(t, choose_political_direction(&c, .Front, 0, 0)); cohesion := c.strategic.cohesion; testing.expect(t, cancel_political_direction(&c)); testing.expect_value(t, c.council.phase, Council_Phase.Cancelled); testing.expect_value(t, c.strategic.cohesion, cohesion - 1); testing.expect_value(t, c.council.cooldown_until, c.season + 1); testing.expect(t, !choose_political_direction(&c, .Front, 0, 1)); c.season = c.council.cooldown_until; testing.expect(t, choose_political_direction(&c, .Front, 0, 1))
}

@(test)
council_only_interrupts_unsupported_doctrine_deviations :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		7103,
	); seed_front_families(&c); _ = activate_front_proposal(&c, 0); testing.expect(t, choose_political_direction(&c, .Front, 0, 2)); resolve_council_checkpoint(&c, .Debate); testing.expect(t, c.council.exception_pending); testing.expect(t, resolve_political_exception(&c, 0))
	d: Campaign
	campaign_init(
		&d,
		7103,
	); seed_front_families(&d); _ = activate_front_proposal(&d, 0); d.fronts[0].pressure = 7; testing.expect(t, choose_political_direction(&d, .Front, 0, 2)); resolve_council_checkpoint(&d, .Debate); testing.expect(t, !d.council.exception_pending); testing.expect(t, d.council.last_event > d.council.started_event); testing.expect_value(t, d.events[d.event_count - 1].detail, fmt.tprintf("Authorized deviation: %s pressure 7.", d.fronts[0].name))
}

@(test)
active_council_checkpoint_state_is_persisted :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		7104,
	); seed_front_families(&c); _ = activate_front_proposal(&c, 0); testing.expect(t, choose_political_direction(&c, .Front, 0, 0)); resolve_council_checkpoint(&c, .Advance)
	data := campaign_serialize(
		&c,
	); defer delete(data); restored: Campaign; defer campaign_destroy(&restored); result := campaign_deserialize(data[:], &restored)
	testing.expect(
		t,
		result.ok,
	); testing.expect_value(t, restored.council.phase, c.council.phase); testing.expect_value(t, restored.council.position_count, c.council.position_count); testing.expect(t, restored.council.active)
}

@(test)
institutional_and_community_support_improves_enactment_odds :: proc(t: ^testing.T) {
	strong: Campaign
	campaign_init(&strong, 7105); weak: Campaign
	campaign_init(
		&weak,
		7105,
	); seed_front_families(&strong); seed_front_families(&weak); _ = activate_front_proposal(&strong, 0); _ = activate_front_proposal(&weak, 0); _ = choose_political_direction(&strong, .Front, 0, 0); _ = choose_political_direction(&weak, .Front, 0, 0)
	for &institution in strong.institutions {institution.authority_policy = .Shared_Authority; institution.legitimacy = 90}
	for &community in strong.communities[:strong.community_count] {community.trust = 80; community.grievance = 3}
	for &institution in weak.institutions {institution.authority_policy = .Central_Command; institution.legitimacy = 90}
	for &community in weak.communities[:weak.community_count] {community.trust = 20; community.grievance = 0}
	council_refresh_support(
		&strong,
		&strong.council,
	); council_refresh_support(&weak, &weak.council)
	testing.expect(
		t,
		strong.council.success_chance > weak.council.success_chance,
	); testing.expect(t, strong.council.stall_chance < weak.council.stall_chance)
}

@(test)
council_direction_preview_is_read_only_and_exposes_doctrine_risk :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		7106,
	); seed_front_families(&c); _ = activate_front_proposal(&c, 0); options, count := council_direction_options(&c, .Front, 0); testing.expect_value(t, count, 3); before_events := c.event_count; before_council := c.council
	shared := council_direction_preview(
		&c,
		options[0],
	); revision := council_direction_preview(&c, options[2]); testing.expect_value(t, c.event_count, before_events); testing.expect_value(t, c.council, before_council); testing.expect(t, !shared.doctrine_conflict); testing.expect(t, revision.doctrine_conflict); testing.expect(t, revision.success_chance > 0 && revision.stall_chance > 0); testing.expect(t, revision.strongest_supporter != "" && revision.strongest_opponent != "")
}
