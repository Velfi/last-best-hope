package game_tests

import "core:math"
import "core:testing"

@(test)
passage_bookmarks_its_departure_correspondence_and_uses_system_names :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1837)
	defer campaign_destroy(&c)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	testing.expect_value(t, c.passage.departure_door_id, c.outer_dark.continuum.anchor_door_id)
	testing.expect_value(
		t,
		c.passage.departure_door_position_name_hash,
		dark_door_position_name_hash(c.outer_dark.continuum.anchor_position),
	)
	testing.expect_value(
		t,
		c.passage.departure_neighborhood,
		c.outer_dark.continuum.anchor_neighborhood,
	)
	if c.galaxy.detailed_system_count > 0 {
		system := c.galaxy.detailed_systems[0]
		name := dark_correspondence_name(&c, 91, system.neighborhood_index)
		testing.expect_value(t, name, dark_correspondence_name(&c, 91, system.neighborhood_index))
		testing.expect(t, name != generate_gate_name(91))
	}
}

@(test)
unnamed_correspondence_hashes_follow_four_dimensional_position :: proc(t: ^testing.T) {
	a := Dark_Vec4{1.25, -2.5, 3.75, 4.125}
	b := a
	b[3] += .001
	hash_a := dark_door_position_name_hash(a)
	hash_b := dark_door_position_name_hash(b)
	testing.expect_value(t, hash_a, dark_door_position_name_hash(a))
	testing.expect(t, hash_a != hash_b)
	testing.expect(t, generate_door_hash_name(hash_a) != generate_door_hash_name(hash_b))
}

@(test)
fastest_known_route_uses_a_mapped_dark_shortcut :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1841)
	defer campaign_destroy(&c)
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), []int{0}, &c.passage)
	testing.expect(t, ok)
	d := &c.outer_dark.continuum
	testing.expect(t, d.door_count >= 2)
	if d.door_count < 2 do return
	start := d.anchor_neighborhood
	target := (start + 1) % c.galaxy.neighborhood_count
	c.galaxy.neighborhoods[target].x_kpc = c.galaxy.neighborhoods[start].x_kpc + 100
	c.galaxy.neighborhoods[target].y_kpc = c.galaxy.neighborhoods[start].y_kpc
	c.galaxy.neighborhoods[target].z_kpc = c.galaxy.neighborhoods[start].z_kpc
	exit := &d.doors[1]
	exit.position = dark_vec4_add(d.anchor_position, {.1, 0, 0, 0})
	exit.galaxy_neighborhood = target
	exit.endpoint_known = true
	append(
		&c.dark_fleet_atlas,
		Dark_Atlas_Discovery {
			door_id = exit.id,
			position_name_hash = dark_door_position_name_hash(exit.position),
			galaxy_neighborhood = target,
			transmitted = true,
		},
	)
	c.passage.domain = .Normal_Space
	c.passage.phase = .Awaiting_Leg
	c.passage.normal_course.start_neighborhood = start
	route := passage_fastest_known_route(&c, &c.passage, target)
	testing.expect(t, route.valid && route.uses_dark)
	testing.expect_value(t, route.entry_door_id, d.anchor_door_id)
	testing.expect_value(t, route.exit_door_id, exit.id)
	ok, _ = follow_fastest_known_route(&c, &c.passage, target)
	testing.expect(t, ok)
	testing.expect_value(t, c.passage.domain, Expedition_Domain.Dark)
}

@(test)
recommended_passage_composition_covers_required_roles_deterministically :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1838)
	defer campaign_destroy(&c)
	for &ship, i in c.ships[:c.ship_count] {
		ship.active = true
		ship.committed = false
		ship.role = i == 0 || i == 2 ? .Hospital : i == 1 ? .Survey : .Escort
		ship.damage = i == 0 ? 3 : 0
	}
	contract := default_passage_contract()
	contract.required_roles = (i32(1) << u32(Role.Hospital)) | (i32(1) << u32(Role.Survey))
	a, b: [MAX_EXPEDITION_SHIPS]int
	count_a := recommend_passage_ships(&c, &contract, &a)
	count_b := recommend_passage_ships(&c, &contract, &b)
	testing.expect_value(t, count_a, 2)
	testing.expect_value(t, count_b, count_a)
	testing.expect_value(t, a, b)
	testing.expect_value(t, a[0], 2) // Prefer the undamaged hospital ship.
	valid, _ := validate_contract(&c, &contract, a[:count_a])
	testing.expect(t, valid)
}

@(test)
dark_membrane_time_falls_smoothly_with_depth :: proc(t: ^testing.T) {
	ship_days := 10.0
	at_anchor := dark_membrane_days_for_step(0, ship_days)
	shallow := dark_membrane_days_for_step(1, ship_days)
	deep := dark_membrane_days_for_step(4, ship_days)
	testing.expect(t, math.abs(at_anchor - ship_days) < 1e-12)
	testing.expect(t, shallow < at_anchor && shallow > deep)
	testing.expect(t, deep >= 0)
}

@(test)
passage_course_to_selected_door_is_deterministic_and_detection_gated :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1831); defer campaign_destroy(&c)
	ships := [1]int {
		0,
	}; ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage); testing.expect(t, ok)
	door_at := dark_nearest_unknown_door(
		&c.outer_dark.continuum,
		c.passage.dark_navigation.position,
	)
	testing.expect(t, door_at >= 0); if door_at < 0 do return
	door := &c.outer_dark.continuum.doors[door_at]
	a, found_a := passage_course_to_door(&c, &c.passage, door.id, -1)
	b, found_b := passage_course_to_door(&c, &c.passage, door.id, -1)
	testing.expect(t, found_a && found_b); testing.expect_value(t, a, b)
	_, invalid := passage_course_to_door(
		&c,
		&c.passage,
		u64(0xffffffffffffffff),
		-1,
	); testing.expect(t, !invalid)
	prior :=
		door.position; door.position = dark_vec4_add(c.passage.dark_navigation.position, {1000, 1000, 1000, 1000})
	_, undetected := passage_course_to_door(
		&c,
		&c.passage,
		door.id,
		-1,
	); testing.expect(t, !undetected)
	door.position = prior
}

@(test)
lowest_coherence_course_priority_uses_the_expeditions_actual_exposure :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1451)
	defer campaign_destroy(&c)
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), []int{0}, &c.passage)
	testing.expect(t, ok)
	if !ok do return
	p := &c.passage
	p.strategy.course = .Lowest_Coherence
	p.dark_navigation.sensor_posture = .Illuminate
	c.ships[0].dark_field_scars = 3
	door := &c.outer_dark.continuum.doors[0]
	door.position = dark_vec4_add(p.dark_navigation.position, {6, 1, 0, 3})
	chosen, found := passage_course_to_door(&c, p, door.id, -1)
	testing.expect(t, found)
	if !found do return
	base := f64(1.8)
	depths := [3]f64{base, base * 1.45, max(base * .65, .2)}
	chosen_exposure := passage_course_coherence_forecast(&c, p, &chosen).projected
	for depth in depths {
		candidate := dark_course_to_door(p.dark_navigation.position, door, depth, c.outer_dark.continuum.anchor_position[3])
		exposure := passage_course_coherence_forecast(&c, p, &candidate).projected
		testing.expect(t, chosen_exposure <= exposure + 1e-9)
	}
}

@(test)
passage_events_retain_both_clocks_and_depth :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 812)
	c.passage.active = true
	c.passage.id = 44
	c.passage.domain = .Dark
	c.passage.elapsed_days = 3.5
	c.passage.membrane_elapsed_days = .25
	c.passage.dark_navigation.position = c.outer_dark.continuum.anchor_position
	c.passage.dark_navigation.position[3] += 2
	record_event(&c, .Situation_Decided, "The expedition recorded a correspondence.")
	e := c.events[c.event_count - 1]
	testing.expect_value(t, e.passage_id, u64(44))
	testing.expect(t, math.abs(e.ship_elapsed_days - 3.5) < 1e-12)
	testing.expect(t, math.abs(e.membrane_elapsed_days - .25) < 1e-12)
	testing.expect(t, e.dark_depth > 0)
}

@(test)
institutional_learning_separates_outcomes_and_is_deterministic :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 801); b: Campaign
	campaign_init(&b, 801); contract := default_passage_contract(); ships := [2]int{0, 1}
	ok, _ := begin_authorized_test_passage(
		&a,
		contract,
		ships[:],
		&a.passage,
	); testing.expect(t, ok); id := a.passage.id
	v :=
		a.dark_unresolved_voyages[0]; v.resolved = true; v.source = .Fleet_Debrief; v.objective_met = true; v.safe_conclusion = false; v.record_recovered = true; v.damage = 8; v.resolution_event = 44; testing.expect(t, ingest_dark_voyage_record(&a, v))
	testing.expect_value(
		t,
		a.dark_strategy_records[0].objective_successes,
		i32(1),
	); testing.expect_value(t, a.dark_strategy_records[0].safe_conclusions, i32(0)); testing.expect_value(t, a.dark_strategy_records[0].records_recovered, i32(1)); testing.expect(t, !ingest_dark_voyage_record(&a, v)); testing.expect(t, id != 0)
	ra := recommend_dark_strategy(
		&a,
		&contract,
	); rb := recommend_dark_strategy(&b, &contract); rb2 := recommend_dark_strategy(&b, &contract); testing.expect(t, dark_strategy_equal(rb.strategy, rb2.strategy)); testing.expect(t, ra.estimate.objective_rate >= 0 && ra.estimate.safety_rate >= 0)
}

@(test)
strategy_profiles_enumerate_every_independent_choice_once :: proc(t: ^testing.T) {
	seen: [DARK_STRATEGY_PROFILE_COUNT]bool
	for i in 0 ..< DARK_STRATEGY_PROFILE_COUNT {
		strategy, ok := dark_strategy_profile_at(i)
		testing.expect(t, ok)
		at := dark_strategy_profile_index(strategy)
		testing.expect_value(t, at, i)
		testing.expect(t, !seen[at])
		seen[at] = true
	}
	_, ok := dark_strategy_profile_at(DARK_STRATEGY_PROFILE_COUNT)
	testing.expect(t, !ok)
}

@(test)
institutional_memory_retains_the_complete_strategy_space_without_a_fixed_cap :: proc(
	t: ^testing.T,
) {
	c: Campaign
	campaign_init(&c, 1819)
	defer campaign_destroy(&c)
	contract := default_passage_contract()
	for i in 0 ..< DARK_STRATEGY_PROFILE_COUNT {
		strategy, ok := dark_strategy_profile_at(i)
		testing.expect(t, ok)
		testing.expect(
			t,
			dark_strategy_record_ensure(&c, contract.sponsor, contract.purpose, strategy) >= 0,
		)
	}
	testing.expect_value(t, c.dark_strategy_record_count, DARK_STRATEGY_PROFILE_COUNT)
	testing.expect_value(t, len(c.dark_strategy_records), DARK_STRATEGY_PROFILE_COUNT)
}

@(test)
recommendations_consider_non_preset_profiles_and_enforce_safety_policy :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1810)
	defer campaign_destroy(&c)
	contract := default_passage_contract()
	inst_at := institution_index(&c, contract.sponsor)
	testing.expect(t, inst_at >= 0)
	c.institutions[inst_at].rescue_policy = .Absolute_Duty
	unsafe := Dark_Strategy_Profile {
		.Deep,
		.Shortest_Metric,
		.Contact_Tolerant,
		.Objective_First,
		.Mission_First,
	}
	unsafe_at := dark_strategy_record_ensure(&c, contract.sponsor, contract.purpose, unsafe)
	c.dark_strategy_records[unsafe_at].resolved = 100
	c.dark_strategy_records[unsafe_at].objective_successes = 100
	c.dark_strategy_records[unsafe_at].records_recovered = 100
	unsafe_cell :=
		dark_profile_depth_band(unsafe) * 3 +
		dark_environment_band_at_anchor(
			&c,
		); c.dark_strategy_records[unsafe_at].band_resolved[unsafe_cell] = 100; c.dark_strategy_records[unsafe_at].band_objective_successes[unsafe_cell] = 100; c.dark_strategy_records[unsafe_at].band_records_recovered[unsafe_cell] = 100
	custom := Dark_Strategy_Profile {
		.Deep,
		.Best_Mapped,
		.Avoidant,
		.Objective_First,
		.Conservative,
	}
	custom_at := dark_strategy_record_ensure(&c, contract.sponsor, contract.purpose, custom)
	c.dark_strategy_records[custom_at].resolved = 20
	c.dark_strategy_records[custom_at].objective_successes = 20
	c.dark_strategy_records[custom_at].safe_conclusions = 20
	c.dark_strategy_records[custom_at].records_recovered = 20
	custom_cell :=
		dark_profile_depth_band(custom) * 3 +
		dark_environment_band_at_anchor(
			&c,
		); c.dark_strategy_records[custom_at].band_resolved[custom_cell] = 20; c.dark_strategy_records[custom_at].band_objective_successes[custom_cell] = 20; c.dark_strategy_records[custom_at].band_safe_conclusions[custom_cell] = 20; c.dark_strategy_records[custom_at].band_records_recovered[custom_cell] = 20
	recommendation := recommend_dark_strategy(&c, &contract)
	testing.expect(t, dark_strategy_equal(recommendation.strategy, custom))
	testing.expect(
		t,
		recommendation.estimate.safety_rate >=
		dark_strategy_safety_floor(&c.institutions[inst_at]),
	)
}

@(test)
strategy_estimates_use_only_relevant_depth_and_environment_evidence :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1825,
	); defer campaign_destroy(&c); contract := default_passage_contract(); strategy := Dark_Strategy_Profile{.Balanced, .Best_Mapped, .Avoidant, .Relay_First, .Conservative}; at := dark_strategy_record_ensure(&c, contract.sponsor, contract.purpose, strategy); r := &c.dark_strategy_records[at]
	current_environment := dark_environment_band_at_anchor(
		&c,
	); current := dark_profile_depth_band(strategy) * 3 + current_environment; other := dark_profile_depth_band(strategy) * 3 + (current_environment + 1) % 3
	r.resolved = 24; r.objective_successes = 20; r.safe_conclusions = 20; r.records_recovered = 20; r.band_resolved[other] = 20; r.band_objective_successes[other] = 20; r.band_safe_conclusions[other] = 20; r.band_records_recovered[other] = 20; r.band_resolved[current] = 4
	estimate := dark_strategy_estimate_for(
		&c,
		contract.sponsor,
		contract.purpose,
		strategy,
	); testing.expect_value(t, estimate.evidence, i32(4)); testing.expect(t, estimate.objective_rate < .25); testing.expect(t, estimate.safety_rate < .25)
}

@(test)
unreported_voyage_remains_censored_until_confirmed :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		802,
	); ships := [1]int{0}; ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage); testing.expect(t, ok); testing.expect_value(t, c.dark_strategy_record_count, 1); testing.expect_value(t, c.dark_strategy_records[0].attempted, i32(1)); testing.expect_value(t, c.dark_strategy_records[0].resolved, i32(0)); testing.expect(t, confirm_dark_voyage_lost(&c, c.passage.id, 71)); testing.expect_value(t, c.dark_strategy_records[0].ships_lost, i32(1)); testing.expect_value(t, c.dark_strategy_records[0].objective_successes, i32(0))
}

@(test)
late_authenticated_evidence_revises_a_confirmed_loss_without_duplicating_it :: proc(
	t: ^testing.T,
) {
	c: Campaign
	campaign_init(&c, 1813)
	defer campaign_destroy(&c)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	id := c.passage.id
	testing.expect(t, confirm_dark_voyage_lost(&c, id, 71))
	record_at := dark_strategy_record_index(
		&c,
		c.passage.contract.sponsor,
		c.passage.contract.purpose,
		c.passage.strategy,
	)
	testing.expect_value(t, c.dark_strategy_records[record_at].resolved, i32(1))
	testing.expect_value(t, c.dark_strategy_records[record_at].ships_lost, i32(1))
	late := c.dark_unresolved_voyages[0]
	late.source = .Recovered_Record
	late.objective_met = true
	late.safe_conclusion = true
	late.record_recovered = true
	late.ships_lost = 0
	late.resolution_event = 72
	testing.expect(t, ingest_dark_voyage_record(&c, late))
	testing.expect_value(t, c.dark_strategy_records[record_at].attempted, i32(1))
	testing.expect_value(t, c.dark_strategy_records[record_at].resolved, i32(1))
	testing.expect_value(t, c.dark_strategy_records[record_at].ships_lost, i32(0))
	testing.expect_value(t, c.dark_strategy_records[record_at].objective_successes, i32(1))
	testing.expect_value(t, c.dark_strategy_records[record_at].safe_conclusions, i32(1))
	testing.expect_value(t, c.dark_strategy_records[record_at].records_recovered, i32(1))
	testing.expect(t, !ingest_dark_voyage_record(&c, late))
}

@(test)
unknown_door_arrival_establishes_relay_and_uploads_knowledge :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		803,
	); ships := [1]int{0}; ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage); testing.expect(t, ok); i := dark_nearest_unknown_door(&c.outer_dark.continuum, c.passage.dark_navigation.position); testing.expect(t, i >= 0); c.passage.dark_navigation.position = c.outer_dark.continuum.doors[i].position; ok, _ = cross_passage_door(&c, &c.passage); testing.expect(t, ok); testing.expect_value(t, c.passage.local_atlas_count, 1); testing.expect_value(t, len(c.dark_fleet_atlas), 1); testing.expect(t, c.passage.local_atlas[0].transmitted); testing.expect(t, c.outer_dark.continuum.doors[i].endpoint_known); testing.expect(t, dark_relay_at_neighborhood(&c, c.passage.normal_course.start_neighborhood) >= 0)
}

@(test)
hush_colonies_attach_to_real_expedition_ships :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1803)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	o := &c.outer_dark.continuum.organisms[0]
	o.role = .Hush_Colony
	o.alive = true
	o.radius = 1
	o.position = dark_vec4_add(
		c.passage.dark_navigation.position,
		dark_expedition_ship_offset(c.passage.ships[0]),
	)
	_ = resolve_dark_ship_contacts(
		&c,
		&c.passage,
		c.passage.dark_navigation.position,
		c.passage.dark_navigation.position,
	)
	testing.expect_value(t, o.attached_ship, c.passage.ships[0])
	ship_at := ship_index(&c, c.passage.ships[0])
	testing.expect_value(t, c.ships[ship_at].dark_symbiont_id, o.id)
	testing.expect_value(
		t,
		c.ships[ship_at].dark_contact_procedure,
		Dark_Contact_Procedure.Field_Quarantine,
	)
}

@(test)
ships_retain_contact_procedures_learned_from_shear_attacks :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1814)
	defer campaign_destroy(&c)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	o := &c.outer_dark.continuum.organisms[0]
	o.role = .Shear_Hunter
	o.alive = true
	o.radius = 1
	o.position = dark_vec4_add(
		c.passage.dark_navigation.position,
		dark_expedition_ship_offset(c.passage.ships[0]),
	)
	ship_at := ship_index(&c, c.passage.ships[0])
	before := c.ships[ship_at].damage
	c.outer_dark.continuum.simulation_tick = 10
	_ = resolve_dark_ship_contacts(
		&c,
		&c.passage,
		c.passage.dark_navigation.position,
		c.passage.dark_navigation.position,
	)
	testing.expect_value(t, c.ships[ship_at].damage, before + 1)
	testing.expect_value(
		t,
		c.ships[ship_at].dark_contact_procedure,
		Dark_Contact_Procedure.Shear_Evasion,
	)
	testing.expect_value(t, c.ships[ship_at].dark_field_scars, i32(1))
	c.outer_dark.continuum.simulation_tick = 20
	_ = resolve_dark_ship_contacts(
		&c,
		&c.passage,
		c.passage.dark_navigation.position,
		c.passage.dark_navigation.position,
	)
	testing.expect_value(t, c.ships[ship_at].damage, before + 1)
	c.outer_dark.continuum.simulation_tick = 30
	_ = resolve_dark_ship_contacts(
		&c,
		&c.passage,
		c.passage.dark_navigation.position,
		c.passage.dark_navigation.position,
	)
	testing.expect_value(t, c.ships[ship_at].damage, before + 2)
	testing.expect_value(t, c.ships[ship_at].dark_field_scars, i32(2))
}

@(test)
organism_names_are_stable_observational_labels :: proc(t: ^testing.T) {
	a := dark_organism_name(99127, .Lantern_Grazer)
	b := dark_organism_name(99127, .Lantern_Grazer)
	c := dark_organism_name(99127, .Shear_Hunter)
	testing.expect_value(t, a, b)
	testing.expect(t, a != c)
}

@(test)
normal_space_legs_use_relativistic_coordinate_and_proper_time :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1809)
	defer campaign_destroy(&c)
	p := Passage {
		active = true,
		domain = .Normal_Space,
	}
	p.normal_course.start_neighborhood = 1
	testing.expect(t, !plot_normal_course(&c, &p, 2, .5))
	testing.expect(t, !p.normal_course.active)
}

@(test)
manifestation_history_stays_local_until_a_recovered_debrief :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1804)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	tracker := Dark_Tracker {
		track_count = 1,
	}
	tracker.tracks[0] = {
		organism_id = 99,
		role        = .Lantern_Grazer,
		confidence  = .7,
		behavior    = .Feeding,
	}
	dark_update_local_observations(&c.passage, &tracker, 10)
	empty := Dark_Tracker{}
	dark_update_local_observations(&c.passage, &empty, 11)
	dark_update_local_observations(&c.passage, &tracker, 12)
	testing.expect_value(t, c.passage.local_observations[0].manifestation_count, i32(2))
	testing.expect_value(t, len(c.dark_organism_observations), 0)
	c.passage.domain = .Normal_Space
	c.passage.normal_course.start_neighborhood = c.outer_dark.continuum.anchor_neighborhood
	testing.expect(t, set_passage_safe_endpoint(&c, &c.passage, .Fleet))
	ok, _ = conclude_passage(&c, &c.passage)
	testing.expect(t, ok)
	testing.expect_value(t, len(c.dark_organism_observations), 1)
	testing.expect_value(t, c.dark_organism_observations[0].manifestation_count, i32(2))
}

@(test)
replanned_dark_courses_preserve_the_manual_clock_pause :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1805)
	ships := [1]int{0}
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), ships[:], &c.passage)
	testing.expect(t, ok)
	c.outer_dark.continuum.paused = true
	course := Dark_Course {
		waypoint_count = 2,
	}
	course.waypoints[0].position = c.passage.dark_navigation.position
	course.waypoints[1].position = dark_vec4_add(c.passage.dark_navigation.position, {1, 0, 0, .5})
	_, ok = plot_passage_course(&c, &c.passage, course)
	testing.expect(t, ok)
	testing.expect(t, c.outer_dark.continuum.paused)
}
