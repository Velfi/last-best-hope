package game_tests

import "core:math"
import "core:testing"

@(test)
passage_ecology_and_navigation_share_one_deterministic_fixed_step :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 1815)
	b: Campaign
	campaign_init(&b, 1815)
	defer campaign_destroy(&a)
	defer campaign_destroy(&b)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&a, default_passage_contract(), ships[:], &a.passage)
	testing.expect(t, ok)
	ok, _ = begin_authorized_test_passage(&b, default_passage_contract(), ships[:], &b.passage)
	testing.expect(t, ok)
	for &organism in a.outer_dark.continuum.organisms[:a.outer_dark.continuum.organism_count] do organism.alive = false
	for &organism in b.outer_dark.continuum.organisms[:b.outer_dark.continuum.organism_count] do organism.alive = false
	course := Dark_Course {
		waypoint_count = 2,
	}
	course.waypoints[0].position = a.passage.dark_navigation.position
	course.waypoints[1].position = dark_vec4_add(course.waypoints[0].position, {2, 1, .5, 1})
	_, ok = plot_passage_course(&a, &a.passage, course)
	testing.expect(t, ok)
	_, ok = plot_passage_course(&b, &b.passage, course)
	testing.expect(t, ok)
	advance_passage(&a, &a.passage, .5)
	for _ in 0 ..< 5 do advance_passage(&b, &b.passage, .1)
	testing.expect_value(
		t,
		a.outer_dark.continuum.simulation_tick,
		b.outer_dark.continuum.simulation_tick,
	)
	testing.expect_value(t, a.passage.dark_navigation.position, b.passage.dark_navigation.position)
	testing.expect_value(t, a.passage.elapsed_days, b.passage.elapsed_days)
	testing.expect_value(t, a.passage.course_cost, b.passage.course_cost)
	for field, i in a.outer_dark.continuum.fields[:a.outer_dark.continuum.field_count] do testing.expect_value(t, field, b.outer_dark.continuum.fields[i])
}

@(test)
material_contact_pauses_before_later_requested_steps_advance :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1816)
	defer campaign_destroy(&c)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	for &organism in c.outer_dark.continuum.organisms[:c.outer_dark.continuum.organism_count] do organism.alive = false
	hunter := &c.outer_dark.continuum.organisms[0]
	hunter.alive = true
	hunter.role = .Shear_Hunter
	hunter.radius = 3
	hunter.position = c.passage.dark_navigation.position
	course := Dark_Course {
		waypoint_count = 2,
	}
	course.waypoints[0].position = c.passage.dark_navigation.position
	course.waypoints[1].position = dark_vec4_add(course.waypoints[0].position, {2, 0, 0, 0})
	_, ok = plot_passage_course(&c, &c.passage, course)
	testing.expect(t, ok)
	advance_passage(&c, &c.passage, 1)
	testing.expect_value(t, c.outer_dark.continuum.simulation_tick, u64(1))
	testing.expect_value(t, c.passage.phase, Dark_Expedition_Phase.Awaiting_Leg)
	// Starting inside a hunter is a genuine biological contact. The fixed step
	// still stops immediately, but reports the more specific danger reason.
	testing.expect_value(t, c.passage.pause_reason, Dark_Pause_Reason.Dangerous_Contact)
}

@(test)
missing_voyage_stays_censored_and_releases_the_active_expedition_slot :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1817); defer campaign_destroy(&c); ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(
		&c,
		default_passage_contract(),
		ships[:],
		&c.passage,
	); testing.expect(t, ok)
	id :=
		c.passage.id; record_at := dark_strategy_record_index(&c, c.passage.contract.sponsor, c.passage.contract.purpose, c.passage.strategy)
	ok, _ = declare_passage_missing(
		&c,
		&c.passage,
	); testing.expect(t, ok); testing.expect(t, !c.passage.active); testing.expect(t, c.ships[0].committed)
	testing.expect_value(
		t,
		c.dark_strategy_records[record_at].attempted,
		i32(1),
	); testing.expect_value(t, c.dark_strategy_records[record_at].resolved, i32(0))
	found :=
		false; for voyage in c.dark_unresolved_voyages do if voyage.id == id {found = true; testing.expect(t, !voyage.resolved)}; testing.expect(t, found)
}

@(test)
confirmed_missing_voyage_updates_the_original_ships_and_record :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1822,
	); defer campaign_destroy(&c); ships := [1]int{0}; ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage); testing.expect(t, ok); id := c.passage.id; _, _ = declare_passage_missing(&c, &c.passage)
	testing.expect(
		t,
		confirm_dark_voyage_lost(&c, id, 91),
	); testing.expect(t, !c.ships[0].active); testing.expect(t, !c.ships[0].committed); testing.expect_value(t, c.ships[0].departure, Ship_Departure.Lost)
	resolved := 0; for voyage in c.dark_unresolved_voyages do if voyage.id == id && voyage.resolved do resolved += 1; testing.expect_value(t, resolved, 1)
}

@(test)
generic_mapping_has_no_resource_gate_and_surveys_receive_a_complete_role_scope :: proc(
	t: ^testing.T,
) {
	c: Campaign
	campaign_init(&c, 1818); defer campaign_destroy(&c); ships := [1]int{0}
	mapping := default_passage_contract(
		
	); testing.expect_value(t, mapping.resource_threshold, f64(0)); ok, _ := begin_authorized_test_passage(&c, mapping, ships[:], &c.passage); testing.expect(t, ok); _, _ = declare_passage_missing(&c, &c.passage)
	// Use another available ship because a missing vessel remains correctly committed.
	survey := default_passage_contract(
		
	); survey.purpose = .Ecological_Survey; survey.required_ecology_roles = 0
	ok, _ = begin_authorized_test_passage(
		&c,
		survey,
		[]int{1},
		&c.passage,
	); testing.expect(t, ok); testing.expect_value(t, c.passage.contract.required_ecology_roles, u32((1 << 5) - 1))
}

@(test)
normal_space_legs_retain_continuous_three_dimensional_position :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1819,
	); defer campaign_destroy(&c); ships := [1]int{0}; ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage); testing.expect(t, ok)
	c.passage.domain = .Normal_Space; c.passage.phase = .Awaiting_Leg; c.passage.normal_course.start_neighborhood = c.outer_dark.continuum.anchor_neighborhood
	destination := (c.outer_dark.continuum.anchor_neighborhood + 1) % c.galaxy.neighborhood_count
	testing.expect(t, !plot_normal_course(&c, &c.passage, destination, .2))
	testing.expect(t, !c.passage.normal_course.active)
}

@(test)
active_four_dimensional_voyage_replays_across_save_and_reload :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 1827); defer campaign_destroy(&a)
	// Keep the generated ecology out of this short course without producing an
	// invalid body/chunk combination that no ordinary simulation step can create.
	for &organism in a.outer_dark.continuum.organisms[:a.outer_dark.continuum.organism_count] {
		organism.position = dark_vec4_add(a.outer_dark.continuum.anchor_position, {3, 3, 3, 3})
		organism.chunk = dark_chunk_coord_at(organism.position)
	}
	ok, _ := begin_authorized_test_passage(
		&a,
		default_passage_contract(),
		[]int{0},
		&a.passage,
	); testing.expect(t, ok); course := Dark_Course {
		waypoint_count = 2,
	}; course.waypoints[0].position =
		a.passage.dark_navigation.position; course.waypoints[1].position = dark_vec4_add(course.waypoints[0].position, {.4, .3, .2, .5}); _, ok = plot_passage_course(&a, &a.passage, course); testing.expect(t, ok); advance_passage(&a, &a.passage, .2)
	data := campaign_serialize(
		&a,
	); defer delete(data); b: Campaign; decoded := campaign_deserialize(data[:], &b); testing.expect(t, decoded.ok); defer campaign_destroy(&b)
	testing.expect_value(
		t,
		b.passage.phase,
		a.passage.phase,
	); testing.expect_value(t, b.passage.domain, a.passage.domain); testing.expect_value(t, b.passage.dark_navigation.segment, a.passage.dark_navigation.segment); testing.expect_value(t, b.outer_dark.continuum.simulation_tick, a.outer_dark.continuum.simulation_tick)
	advance_passage(&a, &a.passage, .5); advance_passage(&b, &b.passage, .5)
	// Odin's JSON writer emits 16 significant digits, so persisted f64 values may
	// differ by one final bit. Replay must preserve every discrete decision and
	// remain numerically identical at simulation precision.
	testing.expect_value(
		t,
		b.passage.phase,
		a.passage.phase,
	); testing.expect_value(t, b.passage.dark_navigation.segment, a.passage.dark_navigation.segment); testing.expect_value(t, b.outer_dark.continuum.simulation_tick, a.outer_dark.continuum.simulation_tick); testing.expect_value(t, b.outer_dark.continuum.organism_count, a.outer_dark.continuum.organism_count); testing.expect_value(t, b.outer_dark.continuum.field_count, a.outer_dark.continuum.field_count)
	for axis in 0 ..< 4 do testing.expect(t, math.abs(b.passage.dark_navigation.position[axis] - a.passage.dark_navigation.position[axis]) < 1e-12)
	for i in 0 ..< a.outer_dark.continuum.organism_count {left := a.outer_dark.continuum.organisms[i]; right := b.outer_dark.continuum.organisms[i]; testing.expect_value(t, right.id, left.id); testing.expect_value(t, right.alive, left.alive); for axis in 0 ..< 4 {testing.expect(t, math.abs(right.position[axis] - left.position[axis]) < 1e-12); testing.expect(t, math.abs(right.velocity[axis] - left.velocity[axis]) < 1e-12)}; testing.expect(t, math.abs(right.energy - left.energy) < 1e-12); testing.expect(t, math.abs(right.condition - left.condition) < 1e-12)}
	for i in 0 ..< a.outer_dark.continuum.field_count {left := a.outer_dark.continuum.fields[i]; right := b.outer_dark.continuum.fields[i]; testing.expect_value(t, right.id, left.id); testing.expect(t, math.abs(right.film - left.film) < 1e-12); testing.expect(t, math.abs(right.weather_intensity - left.weather_intensity) < 1e-12)}
}

@(test)
remote_relay_conclusion_is_one_way :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		804,
	); ships := [1]int{0}; id := c.ships[0].id; ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage); testing.expect(t, ok); c.passage.domain = .Normal_Space; c.passage.normal_course.start_neighborhood = 4; relay, serviced, _ := service_passage_relay(&c, &c.passage); testing.expect(t, serviced); testing.expect(t, set_passage_safe_endpoint(&c, &c.passage, .Authenticated_Relay, relay)); ok, _ = conclude_passage(&c, &c.passage); testing.expect(t, ok); at := ship_index(&c, id); testing.expect(t, !c.ships[at].active); testing.expect_value(t, c.ships[at].departure, Ship_Departure.Dark_Voyage)
}

@(test)
strategy_override_moves_the_censored_attempt :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 806)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	prior := c.passage.strategy
	override := Dark_Strategy_Profile {
		.Deep,
		.Shortest_Metric,
		.Contact_Tolerant,
		.Objective_First,
		.Mission_First,
	}
	if dark_strategy_equal(prior, override) do override = {.Shallow, .Best_Mapped, .Avoidant, .Relay_First, .Conservative}
	ok, _ = set_dark_strategy(&c, &c.passage, override)
	testing.expect(t, ok)
	prior_at := dark_strategy_record_index(
		&c,
		c.passage.contract.sponsor,
		c.passage.contract.purpose,
		prior,
	)
	override_at := dark_strategy_record_index(
		&c,
		c.passage.contract.sponsor,
		c.passage.contract.purpose,
		override,
	)
	testing.expect(t, prior_at >= 0 && override_at >= 0)
	testing.expect_value(t, c.dark_strategy_records[prior_at].attempted, i32(0))
	testing.expect_value(t, c.dark_strategy_records[override_at].attempted, i32(1))
	testing.expect(t, dark_strategy_equal(c.dark_unresolved_voyages[0].strategy, override))
}

@(test)
conclusion_derives_missing_ships_and_preserve_lives_failure :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 807)
	contract := default_passage_contract()
	contract.term = .Preserve_Lives
	ships := [2]int{0, 1}
	ok, _ := begin_authorized_test_passage(&c, contract, ships[:], &c.passage)
	testing.expect(t, ok)
	c.ships[1].active = false
	c.ships[1].departure = .Lost
	c.passage.domain = .Normal_Space
	c.passage.normal_course.start_neighborhood = c.outer_dark.continuum.anchor_neighborhood
	testing.expect(t, set_passage_safe_endpoint(&c, &c.passage, .Fleet))
	ok, _ = conclude_passage(&c, &c.passage)
	testing.expect(t, ok)
	at := dark_strategy_record_index(&c, contract.sponsor, contract.purpose, c.passage.strategy)
	testing.expect(t, at >= 0)
	testing.expect_value(t, c.dark_strategy_records[at].ships_lost, i32(1))
	testing.expect_value(t, c.dark_strategy_records[at].safe_conclusions, i32(0))
}

@(test)
relay_contract_requires_real_authenticated_infrastructure :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 808)
	contract := default_passage_contract()
	contract.purpose = .Stabilize_Relay
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, contract, ships[:], &c.passage)
	testing.expect(t, ok)
	c.passage.domain = .Normal_Space
	c.passage.normal_course.start_neighborhood = 6
	testing.expect(t, !set_passage_safe_endpoint(&c, &c.passage, .Authenticated_Relay, 999))
	relay, serviced, _ := service_passage_relay(&c, &c.passage)
	testing.expect(t, serviced)
	testing.expect(t, relay != 0)
	testing.expect(t, c.passage.contract.objective_met)
	progress := passage_contract_progress(&c, &c.passage)
	testing.expect(t, progress.relay_available)
	testing.expect(t, set_passage_safe_endpoint(&c, &c.passage, .Authenticated_Relay, relay))
}

@(test)
normal_space_arrival_establishes_communications_automatically :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1817)
	defer campaign_destroy(&c)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	c.passage.strategy.relay = .Relay_First
	i := dark_nearest_unknown_door(&c.outer_dark.continuum, c.passage.dark_navigation.position)
	testing.expect(t, i >= 0)
	c.passage.dark_navigation.position = c.outer_dark.continuum.doors[i].position
	ok, _ = cross_passage_door(&c, &c.passage)
	testing.expect(t, ok)
	testing.expect(t, !c.passage.relay_advised)
	testing.expect(
		t,
		dark_relay_at_neighborhood(&c, c.passage.normal_course.start_neighborhood) >= 0,
	)
}

@(test)
authenticated_relay_uploads_incremental_knowledge_before_voyage_resolution :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1818)
	defer campaign_destroy(&c)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	i := dark_nearest_unknown_door(&c.outer_dark.continuum, c.passage.dark_navigation.position)
	testing.expect(t, i >= 0)
	c.passage.dark_navigation.position = c.outer_dark.continuum.doors[i].position
	ok, _ = cross_passage_door(&c, &c.passage)
	testing.expect(t, ok)
	tracker := Dark_Tracker {
		track_count = 1,
	}
	tracker.tracks[0] = {
		organism_id = 818,
		role        = .Lantern_Grazer,
		confidence  = .7,
	}
	dark_update_local_observations(&c.passage, &tracker, 1)
	relay, serviced, _ := service_passage_relay(&c, &c.passage)
	testing.expect(t, serviced && relay != 0)
	testing.expect(t, c.passage.active)
	testing.expect(t, !c.dark_unresolved_voyages[0].resolved)
	testing.expect_value(t, len(c.dark_fleet_atlas), 1)
	testing.expect_value(t, len(c.dark_organism_observations), 1)
	testing.expect_value(t, c.dark_organism_observations[0].manifestation_count, i32(1))
	empty := Dark_Tracker{}
	dark_update_local_observations(&c.passage, &empty, 2)
	dark_update_local_observations(&c.passage, &tracker, 3)
	_, serviced, _ = service_passage_relay(&c, &c.passage)
	testing.expect(t, serviced)
	testing.expect_value(t, len(c.dark_fleet_atlas), 1)
	testing.expect_value(t, c.dark_organism_observations[0].manifestation_count, i32(2))
}

@(test)
local_door_knowledge_allows_mixed_domain_return_without_retracing :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 809)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	i := dark_nearest_unknown_door(&c.outer_dark.continuum, c.passage.dark_navigation.position)
	testing.expect(t, i >= 0)
	c.passage.dark_navigation.position = c.outer_dark.continuum.doors[i].position
	ok, _ = cross_passage_door(&c, &c.passage)
	testing.expect(t, ok)
	testing.expect(t, c.outer_dark.continuum.doors[i].endpoint_known)
	ok, _ = enter_passage_dark(&c, &c.passage, c.outer_dark.continuum.doors[i].id)
	testing.expect(t, ok)
	testing.expect_value(t, c.passage.domain, Expedition_Domain.Dark)
	c.passage.domain = .Normal_Space
	c.passage.normal_course.start_neighborhood =
		c.outer_dark.continuum.doors[i].galaxy_neighborhood
	testing.expect(t, !plot_normal_course_to_fleet(&c, &c.passage))
	testing.expect(t, !set_passage_safe_endpoint(&c, &c.passage, .Fleet))
}

@(test)
inaccessible_correspondence_blocks_return_from_remote_relay :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1842)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	i := dark_nearest_unknown_door(&c.outer_dark.continuum, c.passage.dark_navigation.position)
	testing.expect(t, i >= 0)
	c.passage.dark_navigation.position = c.outer_dark.continuum.doors[i].position
	ok, _ = cross_passage_door(&c, &c.passage)
	testing.expect(t, ok)
	door_id := c.outer_dark.continuum.doors[i].id
	testing.expect(t, passage_dark_return_available(&c, &c.passage, door_id))
	c.outer_dark.continuum.doors[i].access = 0
	testing.expect(t, !passage_dark_return_available(&c, &c.passage, door_id))
	ok, _ = enter_passage_dark(&c, &c.passage, door_id)
	testing.expect(t, !ok)
}

@(test)
stranded_relay_expedition_decides_to_return_as_same_ships :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1843)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	c.passage.domain = .Normal_Space
	c.passage.phase = .Awaiting_Leg
	c.passage.normal_course.start_neighborhood = 7
	relay, serviced, _ := service_passage_relay(&c, &c.passage)
	testing.expect(t, serviced)
	testing.expect(t, set_passage_safe_endpoint(&c, &c.passage, .Authenticated_Relay, relay))
	ship_id := c.passage.ships[0]
	c.ships[ship_index(&c, ship_id)].passage_trait = .Committed
	c.ships[ship_index(&c, ship_id)].promises_upheld = 3
	ok, _ = conclude_passage(&c, &c.passage)
	testing.expect(t, ok)
	ship_at := ship_index(&c, ship_id)
	testing.expect(t, ship_at >= 0 && !c.ships[ship_at].active)
	testing.expect(t, stranded_passage_active(&c))
	for !c.stranded_outcome_notice_pending && c.season < 8 {
		c.season += 1
		advance_stranded_passage_groups(&c)
	}
	testing.expect(t, c.stranded_outcome_notice_pending)
	testing.expect(t, c.season >= 2 && c.season <= 5)
	testing.expect(t, c.ships[ship_at].active)
	testing.expect_value(t, c.ships[ship_at].departure, Ship_Departure.None)
	testing.expect(t, c.ships[ship_at].history_record_count > 0)
	testing.expect(t, !stranded_passage_active(&c))
	testing.expect(t, acknowledge_stranded_outcome(&c))
}

@(test)
stranded_relay_expedition_can_choose_independent_community :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1844)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	c.passage.domain = .Normal_Space
	c.passage.phase = .Awaiting_Leg
	c.passage.normal_course.start_neighborhood = 8
	relay, serviced, _ := service_passage_relay(&c, &c.passage)
	testing.expect(t, serviced)
	testing.expect(t, set_passage_safe_endpoint(&c, &c.passage, .Authenticated_Relay, relay))
	ship_id := c.passage.ships[0]
	ship_at := ship_index(&c, ship_id)
	c.ships[ship_at].role = .Habitat
	c.ships[ship_at].passage_trait = .Independent
	ok, _ = conclude_passage(&c, &c.passage)
	testing.expect(t, ok)
	for !c.stranded_outcome_notice_pending {
		c.season += 1
		advance_stranded_passage_groups(&c)
	}
	testing.expect(t, ship_at >= 0 && !c.ships[ship_at].active)
	testing.expect_value(t, c.ships[ship_at].departure, Ship_Departure.Dark_Voyage)
	testing.expect(t, !stranded_passage_active(&c))
	relay_at := dark_relay_index(&c, relay)
	testing.expect(t, relay_at >= 0 && c.dark_relays[relay_at].condition == 1)
	testing.expect(t, acknowledge_stranded_outcome(&c))
}

@(test)
successful_passage_debrief_returns_scenario_specific_materials_once :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1831); defer campaign_destroy(&c)
	p := Passage {
		contract = {scenario = .Passage_Recover_Reserves, objective_met = true, sponsor = 2},
		ship_count = 1,
		departure_event = c.event_sequence,
		safe_endpoint = .Fleet,
	}
	p.ships[0] = c.ships[0].id
	before := c.material_economy.fleet.stock
	reward := apply_passage_debrief_reward(&c, &p, true)
	testing.expect_value(
		t,
		reward.supplies,
		i64(18),
	); testing.expect_value(t, reward.raw_materials, i64(4))
	testing.expect_value(
		t,
		reward.manufactured_goods,
		i64(2),
	); testing.expect_value(t, reward.services, i64(4))
	testing.expect_value(t, c.material_economy.fleet.stock.supplies, before.supplies + 18)
	testing.expect_value(t, c.material_economy.fleet.stock.raw_materials, before.raw_materials + 4)
	testing.expect_value(t, c.material_economy.fleet.rewarded.supplies, i64(18))
	failed_before := c.material_economy.fleet.stock
	p.contract.objective_met = false
	_ = apply_passage_debrief_reward(&c, &p, true)
	testing.expect_value(t, c.material_economy.fleet.stock, failed_before)
	p.contract.objective_met = true; p.safe_endpoint = .Authenticated_Relay
	_ = apply_passage_debrief_reward(&c, &p, true)
	testing.expect_value(t, c.material_economy.fleet.stock, failed_before)
}

@(test)
passage_manifest_recovers_unused_propellant_once_and_loses_relay_stock :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1850,
	); before := c.material_economy.fleet.stock.propellant; testing.expect(t, fleet_stock_transfer(&c, {propellant = 10}, c.event_sequence))
	p := Passage {
		ship_count = 1,
		departure_event = c.event_sequence,
		safe_endpoint = .Fleet,
		course_cost = 2.2,
		manifest = {allocated = {propellant = 10}},
	}; p.ships[0] = c.ships[0].id
	testing.expect(
		t,
		settle_passage_manifest(&c, &p),
	); testing.expect_value(t, p.manifest.consumed.propellant, i64(0)); testing.expect_value(t, p.manifest.recovered.propellant, i64(10)); testing.expect_value(t, c.material_economy.fleet.stock.propellant, before); testing.expect(t, !settle_passage_manifest(&c, &p))
	relay_before :=
		c.material_economy.fleet.stock.propellant; testing.expect(t, fleet_stock_transfer(&c, {propellant = 5}, c.event_sequence)); relay := Passage {
		ship_count = 1,
		departure_event = c.event_sequence,
		safe_endpoint = .Authenticated_Relay,
		course_cost = .2,
		manifest = {allocated = {propellant = 5}},
	}; relay.ships[0] = c.ships[0].id
	testing.expect(
		t,
		settle_passage_manifest(&c, &relay),
	); testing.expect_value(t, relay.manifest.consumed.propellant, i64(0)); testing.expect_value(t, relay.manifest.lost.propellant, i64(5)); testing.expect_value(t, c.material_economy.fleet.stock.propellant, relay_before - 5)
}

@(test)
passage_depth_envelope_requires_a_detected_door_commitment :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1851)
	defer campaign_destroy(&c)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	door := &c.outer_dark.continuum.doors[1]
	door.position = dark_vec4_add(c.passage.dark_navigation.position, {4.8, 0, 0, 0})
	door.radius = 1
	door.access = 1
	course := Dark_Course{waypoint_count = 2}
	course.waypoints[0].position = c.passage.dark_navigation.position
	course.waypoints[1].position = door.position
	testing.expect(t, passage_course_requires_emergency(&c, &c.passage, &course))
	_, plotted := plot_passage_course(&c, &c.passage, course)
	testing.expect(t, !plotted)
	ok, _ = authorize_passage_emergency_descent(&c, &c.passage, &course)
	testing.expect(t, ok)
	other := &c.outer_dark.continuum.doors[2]
	other.position = dark_vec4_add(c.passage.dark_navigation.position, {5.2, 0, 0, 0})
	other.radius = 1
	other.access = 1
	wrong := course
	wrong.waypoints[1].position = other.position
	_, plotted = plot_passage_course(&c, &c.passage, wrong)
	testing.expect(t, !plotted)
	_, plotted = plot_passage_course(&c, &c.passage, course)
	testing.expect(t, plotted)
}

@(test)
passage_depth_state_survives_save_load_with_a_rebuilt_destination_order :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1852)
	defer campaign_destroy(&c)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	data := campaign_serialize(&c)
	defer delete(data)
	restored: Campaign
	defer campaign_destroy(&restored)
	decoded := campaign_deserialize(data[:], &restored)
	testing.expect(t, decoded.ok)
	testing.expect_value(t, restored.passage.field_depth_rating, 4.0)
	testing.expect_value(t, restored.passage.emergency_depth_limit, 6.5)
	testing.expect_value(t, restored.outer_dark.continuum.neighborhood_by_anchor_distance[0], restored.outer_dark.continuum.anchor_neighborhood)
}

@(test)
successful_without_undertaking_passage_still_returns_maintenance_capacity :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1832); defer campaign_destroy(&c)
	p := Passage {
		contract = {purpose = .Map_Unknown_Door, objective_met = true, sponsor = 2},
		ship_count = 1,
		departure_event = c.event_sequence,
		safe_endpoint = .Fleet,
	}
	p.ships[0] = c.ships[0].id
	before := c.material_economy.fleet.stock
	reward := apply_passage_debrief_reward(&c, &p, true)
	testing.expect_value(
		t,
		reward.manufactured_goods,
		i64(2),
	); testing.expect_value(t, reward.services, i64(4))
	testing.expect_value(
		t,
		c.material_economy.fleet.stock.manufactured_goods,
		before.manufactured_goods + 2,
	)
	testing.expect_value(t, c.material_economy.fleet.stock.services, before.services + 4)
}
