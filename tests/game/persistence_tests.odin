package game_tests

import "core:encoding/json"
import "core:testing"

@(test)
compact_v8_round_trip_rejects_all_legacy_campaign_formats :: proc(t: ^testing.T) {
	c := new_campaign_seeded_heap(24309)
	defer campaign_destroy_heap(c)
	original_count := len(c.habitable_contacts)
	data := campaign_serialize(c)
	defer delete(data)
	restored := new(Campaign)
	defer free(restored)
	defer campaign_destroy(restored)
	result := campaign_deserialize(data[:], restored)
	testing.expect(t, result.ok)
	testing.expect_value(t, len(restored.habitable_contacts), len(c.habitable_contacts))
	for contact, i in c.habitable_contacts do testing.expect_value(t, restored.habitable_contacts[i], contact)

	c.format_version = 2
	legacy := campaign_serialize(c)
	defer delete(legacy)
	migrated := new(Campaign)
	defer free(migrated)
	defer campaign_destroy(migrated)
	migration := campaign_deserialize(legacy[:], migrated)
	testing.expect(t, !migration.ok)
	testing.expect(t, len(migration.message) > 0)

	candidate := install_test_candidate_home(c)
	testing.expect(t, candidate.valid)
	c.candidate_celebration_cursor = 0
	c.format_version = 3
	v3 := campaign_serialize(c)
	defer delete(v3)
	migrated_v3 := new(Campaign)
	defer free(migrated_v3)
	defer campaign_destroy(migrated_v3)
	migration_v3 := campaign_deserialize(v3[:], migrated_v3)
	testing.expect(t, !migration_v3.ok)
	c.format_version = 7
	v7 := campaign_serialize(c)
	defer delete(v7)
	rejected_v7 := new(Campaign)
	defer free(rejected_v7)
	defer campaign_destroy(rejected_v7)
	v7_result := campaign_deserialize(v7[:], rejected_v7)
	testing.expect(t, !v7_result.ok)
	testing.expect(t, v7_result.message == "This chronicle predates the complete Expeditionary Compact v8 campaign format and cannot be continued; begin a new chronicle.")
	_ = original_count
}
@(test)
campaign_save_round_trip_preserves_fleet_history :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 0xcafe)
	defer campaign_destroy(&c)
	c.guidance_step = 3
	c.communities[0].position = .Aggrieved; c.communities[0].grievance = 4; c.communities[0].petitions_neglected = 2; c.communities[0].last_memory_event = 7
	home := install_test_candidate_home(&c); testing.expect(t, home.valid)
	c.settlements[0] = {
		id                   = 1,
		name                 = "Harbor One",
		population           = 2500,
		viability            = 62,
		active               = true,
		founding_community   = 2,
		founder_ship         = 12,
		founding_event       = 4,
		last_report_event    = 9,
		report_count         = 2,
		archive_id           = 2,
		archive_origin_event = 6,
		celestial            = home,
	}; c.settlement_count = 1
	c.ship_relationships[0] = {
		ship_a          = 1,
		ship_b          = 2,
		strength        = 2,
		shared_passages = 2,
		origin_event    = 3,
		last_event      = 8,
	}; c.ship_relationship_count = 1
	append(
		&c.dark_strategy_records,
		Dark_Strategy_Statistics {
			sponsor = 2,
			purpose = .Map_Unknown_Door,
			strategy = dark_default_strategy(.Open_Record),
			attempted = 2,
			resolved = 2,
			objective_successes = 1,
			safe_conclusions = 2,
			records_recovered = 2,
		},
	); c.dark_strategy_record_count = 1
	add_ship_history(&c, 1, "Opened the first route through the Tithe Gate.")
	c.ships[0].promises_broken = 1; c.ships[0].last_promise_status = .Broken; c.ships[0].last_promise_event = 8
	hook_index := create_broken_procession_hook(
		&c,
		800,
		1,
	); c.history_hooks[hook_index].stage = .Obligation
	c.historical_figures[0].age_years = 47; c.historical_figures[0].institution = 1
	record_ship_autonomy(
		&c,
		"Wayward Light pursued a signal without waiting for orders.",
		1,
		1,
	); captain_id := c.ships[0].captain
	record_event(
		&c,
		.History_Continued,
		"The Broken Procession requested a council voice.",
		1,
		800,
		c.history_hooks[hook_index].community,
		c.history_hooks[hook_index].origin_event,
	)
	c.history_hooks[hook_index].obligation_event = c.event_sequence
	advance_season(&c)
	_ = enact_precedent_fixture(&c, .Shared_Authority, "Every community receives a council voice.")
	record_event(
		&c,
		.Expedition_Returned,
		"The expedition reported no viable settlement.",
		authoritative_detail = "Pale Harbor was viable with adaptation.",
		account_status = .Contradicted,
	)
	contested_event := c.event_sequence
	c.events[c.event_count - 1].account_exposed =
		true; c.pending_accountability_event = contested_event
	data := campaign_serialize(&c)
	defer delete(data)
	restored: Campaign
	defer campaign_destroy(&restored)
	decoded := campaign_deserialize(data[:], &restored)
	testing.expect(t, decoded.ok)
	testing.expect_value(t, restored.rng_state, c.rng_state)
	testing.expect_value(t, restored.guidance_step, c.guidance_step)
	testing.expect_value(t, restored.event_count, c.event_count)
	testing.expect_value(t, restored.precedent_count, c.precedent_count)
	testing.expect_value(t, restored.precedents[0].event_sequence, c.precedents[0].event_sequence)
	testing.expect_value(t, restored.institutions[0].id, Institution_ID(1))
	testing.expect_value(t, restored.relationship_count, c.relationship_count)
	testing.expect_value(t, restored.communities[0].position, Community_Position.Aggrieved)
	testing.expect_value(t, restored.communities[0].grievance, i32(4))
	testing.expect_value(t, restored.settlements[0].id, Settlement_ID(1))
	testing.expect_value(t, restored.archives[1].id, Archive_ID(2))
	testing.expect_value(t, restored.settlements[0].archive_id, Archive_ID(2))
	testing.expect_value(
		t,
		restored.settlements[0].last_report_event,
		c.settlements[0].last_report_event,
	)
	testing.expect_value(t, restored.ship_relationships[0], c.ship_relationships[0])
	testing.expect_value(t, restored.relationships[0], c.relationships[0])
	testing.expect_value(t, restored.historical_figure_count, c.historical_figure_count)
	testing.expect_value(t, restored.historical_figures[0].name, "Tala Venn")
	testing.expect_value(
		t,
		restored.historical_figures[0].origin_event,
		c.historical_figures[0].origin_event,
	)
	testing.expect_value(
		t,
		restored.historical_figures[0].age_years,
		c.historical_figures[0].age_years,
	)
	testing.expect_value(t, restored.historical_figures[0].institution, Institution_ID(1))
	testing.expect_value(t, restored.ships[0].name, c.ships[0].name)
	testing.expect_value(t, restored.ships[0].history_records[0], c.ships[0].history_records[0])
	testing.expect_value(
		t,
		restored.ships[0].memory_count,
		c.ships[0].memory_count,
	); testing.expect_value(t, restored.ships[0].memories[restored.ships[0].memory_count - 1], c.ships[0].memories[c.ships[0].memory_count - 1])
	testing.expect_value(
		t,
		restored.ships[0].captain,
		captain_id,
	); captain_at := historical_figure_index(&restored, captain_id); testing.expect(t, captain_at >= 0); testing.expect_value(t, restored.historical_figures[captain_at].passage_actions, i32(1))
	testing.expect_value(
		t,
		restored.ships[0].promises_broken,
		i32(1),
	); testing.expect_value(t, restored.ships[0].last_promise_status, Passage_Promise_Status.Broken); testing.expect_value(t, restored.ships[0].last_promise_event, u64(8))
	testing.expect_value(t, restored.history_hooks[0].population, i32(800))
	testing.expect_value(
		t,
		restored.history_hooks[0].origin_event,
		c.history_hooks[0].origin_event,
	)
	testing.expect_value(
		t,
		restored.history_hooks[0].obligation_event,
		c.history_hooks[0].obligation_event,
	)
	testing.expect_value(t, restored.communities[4].name, "Broken Procession")
	testing.expect_value(
		t,
		restored.dark_strategy_record_count,
		1,
	); testing.expect_value(t, restored.dark_strategy_records[0], c.dark_strategy_records[0])
	testing.expect_value(t, restored.events[0].detail, c.events[0].detail)
	contested_at := event_index_by_sequence(
		&restored,
		contested_event,
	); testing.expect(t, contested_at >= 0)
	testing.expect_value(
		t,
		restored.events[contested_at].account_status,
		Account_Status.Contradicted,
	)
	testing.expect_value(
		t,
		restored.events[contested_at].authoritative_detail,
		"Pale Harbor was viable with adaptation.",
	)
	testing.expect(
		t,
		restored.events[contested_at].account_exposed,
	); testing.expect_value(t, restored.pending_accountability_event, contested_event)
	// Prove decoded strings own content rather than retaining pointers into data.
	for i in SAVE_HEADER_SIZE ..< len(data) do data[i] = 0
	testing.expect_value(t, restored.ships[0].name, "Wayward Light")
}

@(test)
campaign_save_round_trip_preserves_world_survey_evidence :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		8842,
	); defer campaign_destroy(&c); _, _ = discover_candidate_home(&c, 3); testing.expect_value(t, c.world_survey_count, 1)
	data := campaign_serialize(
		&c,
	); defer delete(data); restored: Campaign; defer campaign_destroy(&restored); decoded := campaign_deserialize(data[:], &restored)
	testing.expect(
		t,
		decoded.ok,
	); testing.expect_value(t, restored.world_survey_count, c.world_survey_count); testing.expect_value(t, restored.world_surveys[0], c.world_surveys[0]); testing.expect_value(t, restored.surveyed_system_mask, c.surveyed_system_mask)
}

@(test)
campaign_save_round_trip_preserves_pending_food_shortage :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1710,
	); c.material_economy.fleet.stock.food = 0; c.material_economy.agriculture.damage = 100
	advance_material_economy(&c); advance_material_economy(&c)
	data := campaign_serialize(&c); defer delete(data)
	restored: Campaign; defer campaign_destroy(&restored); decoded := campaign_deserialize(data[:], &restored)
	testing.expect(
		t,
		decoded.ok,
	); testing.expect(t, restored.material_economy.food_shortage_response_pending)
	testing.expect_value(
		t,
		restored.material_economy.food_shortage_episode.id,
		c.material_economy.food_shortage_episode.id,
	)
	testing.expect_value(
		t,
		restored.material_economy.food_shortage_episode.origin_event,
		c.material_economy.food_shortage_episode.origin_event,
	)
}

@(test)
campaign_save_round_trip_preserves_stranded_relay_search :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1845,
	); defer campaign_destroy(&c); ships := [1]int{0}; ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage); testing.expect(t, ok)
	c.passage.domain = .Normal_Space; c.passage.phase = .Awaiting_Leg; c.passage.normal_course.start_neighborhood = 9
	relay, serviced, _ := service_passage_relay(
		&c,
		&c.passage,
	); testing.expect(t, serviced); testing.expect(t, set_passage_safe_endpoint(&c, &c.passage, .Authenticated_Relay, relay)); ok, _ = conclude_passage(&c, &c.passage); testing.expect(t, ok)
	c.season += 1; advance_stranded_passage_groups(&c)
	data := campaign_serialize(
		&c,
	); defer delete(data); restored: Campaign; defer campaign_destroy(&restored); decoded := campaign_deserialize(data[:], &restored)
	testing.expect(
		t,
		decoded.ok,
	); testing.expect_value(t, restored.stranded_passage_group_count, 1); testing.expect(t, restored.stranded_passage_groups[0].active); testing.expect_value(t, restored.stranded_passage_groups[0].route_progress, c.stranded_passage_groups[0].route_progress)
}

@(test)
campaign_save_rejects_other_rules :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c)
	data := campaign_serialize(&c)
	defer delete(data)
	data[8] ~= 0xff
	restored: Campaign
	decoded := campaign_deserialize(data[:], &restored)
	testing.expect(t, !decoded.ok)
}

@(test)
campaign_save_bytes_are_deterministic :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 24301)
	defer campaign_destroy(&a)
	b: Campaign
	campaign_init(&b, 24301)
	defer campaign_destroy(&b)
	first := campaign_serialize(&a)
	defer delete(first)
	second := campaign_serialize(&b)
	defer delete(second)
	testing.expect(t, len(first) == len(second))
	for value, i in first do testing.expect_value(t, value, second[i])
}

@(test)
campaign_save_rejects_truncated_and_malformed_payloads_without_mutating_destination :: proc(
	t: ^testing.T,
) {
	c: Campaign
	campaign_init(&c, 24302)
	defer campaign_destroy(&c)
	data := campaign_serialize(&c)
	defer delete(data)
	restored: Campaign
	restored.initial_seed = 771
	truncated := campaign_deserialize(data[:SAVE_HEADER_SIZE], &restored)
	testing.expect(t, !truncated.ok)
	testing.expect_value(t, restored.initial_seed, u64(771))
	malformed := make([]u8, len(data))
	defer delete(malformed)
	copy(malformed, data[:])
	malformed[SAVE_HEADER_SIZE] = '{'
	for i in SAVE_HEADER_SIZE + 1 ..< len(malformed) do malformed[i] = 0
	decoded := campaign_deserialize(malformed, &restored)
	testing.expect(t, !decoded.ok)
	testing.expect_value(t, restored.initial_seed, u64(771))
}

@(test)
campaign_save_round_trip_preserves_compacted_chronicle_identity :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 404)
	for i in 0 ..< MAX_EVENTS {c.season = i32(i / 8) + 3; record_event(&c, .Resource_Changed, "Measured stores.", value = i32(i))}
	c.season = 100; record_event(&c, .Season_Advanced, "Later season.")
	testing.expect(
		t,
		c.archived_era_count > 0,
	); archived_sequence := c.archived_eras[0].first_sequence; rng := c.rng_state; sequence := c.event_sequence
	data := campaign_serialize(
		&c,
	); defer delete(data); restored: Campaign; defer campaign_destroy(&restored); decoded := campaign_deserialize(data[:], &restored)
	testing.expect(
		t,
		decoded.ok,
	); testing.expect_value(t, restored.rng_state, rng); testing.expect_value(t, restored.event_sequence, sequence); testing.expect(t, event_reference_exists(&restored, archived_sequence)); testing.expect_value(t, restored.archived_eras[0], c.archived_eras[0])
}

@(test)
campaign_save_round_trip_preserves_hierarchical_epoch_identity :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 405)
	for season in 1 ..= 10000 {c.season = i32(season); for _ in 0 ..< 4 do record_event(&c, .Resource_Changed, "Measured stores.", value = i32(season))}
	testing.expect(
		t,
		c.archived_epoch_count > 0,
	); archived_sequence := c.archived_epochs[0].first_sequence; rng := c.rng_state; sequence := c.event_sequence
	data := campaign_serialize(
		&c,
	); defer delete(data); restored: Campaign; defer campaign_destroy(&restored); decoded := campaign_deserialize(data[:], &restored)
	testing.expect(
		t,
		decoded.ok,
	); testing.expect_value(t, restored.rng_state, rng); testing.expect_value(t, restored.event_sequence, sequence); testing.expect_value(t, restored.archived_epoch_count, c.archived_epoch_count); testing.expect(t, event_reference_exists(&restored, archived_sequence)); testing.expect_value(t, restored.archived_epochs[0], c.archived_epochs[0])
}

@(test)
campaign_save_round_trip_preserves_combat_manifest_and_doctrine :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		406,
	); c.combat_fire_control_preference = .Confirm_Engagements; c.material_economy.fleet.stock.propellant = 8; ids := [3]Ship_ID{c.ships[0].id, c.ships[1].id, c.ships[2].id}; groups := [3]int{0, 1, 2}; _, ok := begin_authorized_test_combat_deployment(&c, ids[:], groups[:]); testing.expect(t, ok); testing.expect(t, combat_set_campaign_deployment_doctrine(&c, 1, .Last_Stand))
	data := campaign_serialize(
		&c,
	); defer delete(data); restored: Campaign; defer campaign_destroy(&restored); decoded := campaign_deserialize(data[:], &restored)
	testing.expect(
		t,
		decoded.ok,
	); testing.expect(t, restored.combat_deployment_active); testing.expect_value(t, restored.combat_deployment_count, 3); testing.expect_value(t, restored.combat_deployment_ships[1], ids[1]); testing.expect_value(t, restored.combat_deployment_doctrines[1], Combat_Doctrine.Last_Stand); testing.expect_value(t, restored.combat_fire_control_preference, Combat_Fire_Control.Confirm_Engagements); testing.expect(t, restored.combat_deployment_doctrine_deviation)
}

@(test)
campaign_save_preserves_unbounded_dark_chunk_deltas_and_fleet_atlas :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 407)
	defer campaign_destroy(&c)
	d := &c.outer_dark.continuum
	door_id := d.doors[0].id
	d.doors[0].traffic = 23
	_ = dark_fleet_record_discovery(
		&c,
		{
			door_id = door_id,
			galaxy_neighborhood = d.doors[0].galaxy_neighborhood,
			discovered_tick = 9,
		},
	)
	for i in 1 ..= INITIAL_DARK_ARCHIVED_CHUNKS + MAX_DARK_LOADED_CHUNKS + 2 do testing.expect(t, dark_ensure_chunk_loaded(d, {i32(i), 0, 0, 0}))
	testing.expect(t, d.archived_chunk_count > INITIAL_DARK_ARCHIVED_CHUNKS)
	data := campaign_serialize(&c)
	defer delete(data)
	restored: Campaign
	defer campaign_destroy(&restored)
	decoded := campaign_deserialize(data[:], &restored)
	testing.expect(t, decoded.ok)
	testing.expect_value(t, len(restored.dark_fleet_atlas), 1)
	testing.expect(
		t,
		dark_ensure_correspondence_loaded(
			&restored.outer_dark.continuum,
			door_id,
			restored.dark_fleet_atlas[0].galaxy_neighborhood,
		),
	)
	found := false
	for door in restored.outer_dark.continuum.doors[:restored.outer_dark.continuum.door_count] do if door.id == door_id {found = true; testing.expect_value(t, door.traffic, i32(23))}
	testing.expect(t, found)
}
