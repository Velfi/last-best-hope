package game_tests

import "core:testing"

@(test)
manual_helm_moves_directly_without_creating_micro_courses :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1901,
	); defer campaign_destroy(&c); ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), []int{0}, &c.passage); testing.expect(t, ok)
	for &organism in c.outer_dark.continuum.organisms[:c.outer_dark.continuum.organism_count] do organism.alive = false
	start := c.passage.dark_navigation.position
	testing.expect(
		t,
		set_passage_manual_helm(&c, &c.passage, {1, 0, 0, .5}),
	); advance_passage(&c, &c.passage, .5)
	testing.expect(
		t,
		c.passage.dark_navigation.position[0] > start[0],
	); testing.expect(t, c.passage.dark_navigation.position[3] > start[3])
	testing.expect_value(
		t,
		c.passage.dark_navigation.course.waypoint_count,
		0,
	); testing.expect(t, c.passage.dark_navigation.manual_active)
	_ = set_passage_manual_helm(
		&c,
		&c.passage,
		{},
	); stopped := c.passage.dark_navigation.position; advance_passage(&c, &c.passage, .5)
	testing.expect_value(
		t,
		c.passage.dark_navigation.position,
		stopped,
	); testing.expect(t, !c.passage.dark_navigation.manual_active)
}

@(test)
dangerous_contact_response_owns_the_replan_or_exposure_tradeoff :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1902,
	); defer campaign_destroy(&c); c.ships[1].dark_contact_procedure = .Field_Quarantine; ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), []int{0, 1}, &c.passage); testing.expect(t, ok)
	course := Dark_Course {
		waypoint_count = 2,
	}; course.waypoints[0].position =
		c.passage.dark_navigation.position; course.waypoints[1].position = dark_vec4_add(course.waypoints[0].position, {4, 0, 0, 0}); _, ok = plot_passage_course(&c, &c.passage, course); testing.expect(t, ok)
	c.passage.dark_navigation.tracker = {
		track_count = 2,
	}; c.passage.dark_navigation.tracker.tracks[0] = {
		organism_id      = 91,
		role             = .Shear_Hunter,
		relative_bearing = {1, 0, 0, 0},
		distance         = 1.8,
		estimated_extent = .8,
		confidence       = .9,
	}; c.passage.dark_navigation.tracker.tracks[1] = {
		organism_id      = 92,
		role             = .Lantern_Grazer,
		relative_bearing = {0, 1, 0, 0},
		distance         = 1,
		estimated_extent = .5,
		confidence       = .9,
	}
	c.passage.phase = .Awaiting_Leg; c.passage.pause_reason = .Dangerous_Contact; c.passage.dark_navigation.autopilot_active = false
	direct := dark_course_forecast(
		&c.outer_dark.continuum,
		&course,
	); strategy_before := c.passage.strategy
	ok, _ = respond_to_dark_contact(
		&c,
		&c.passage,
		false,
		92,
	); testing.expect(t, !ok); testing.expect_value(t, c.passage.phase, Dark_Expedition_Phase.Awaiting_Leg)
	testing.expect_value(
		t,
		passage_shear_evasion_learners(&c, &c.passage),
		1,
	); events_before := c.event_count
	ok, _ = respond_to_dark_contact(
		&c,
		&c.passage,
		false,
		91,
	); testing.expect(t, ok); testing.expect(t, dark_strategy_equal(c.passage.strategy, strategy_before)); testing.expect_value(t, c.passage.phase, Dark_Expedition_Phase.Underway); testing.expect(t, c.passage.dark_navigation.autopilot_active); testing.expect_value(t, c.passage.cleared_contact_id, u64(91)); testing.expect_value(t, c.ships[0].dark_contact_procedure, Dark_Contact_Procedure.Shear_Evasion); testing.expect_value(t, c.ships[1].dark_contact_procedure, Dark_Contact_Procedure.Field_Quarantine); testing.expect_value(t, c.ships[0].history_record_count, 1); testing.expect(t, c.event_count > events_before); testing.expect_value(t, passage_shear_evasion_learners(&c, &c.passage), 0)
	evasive :=
		c.passage.dark_navigation.course; testing.expect_value(t, evasive.waypoint_count, 3); testing.expect_value(t, evasive.waypoints[2].position, course.waypoints[1].position); testing.expect(t, dark_course_forecast(&c.outer_dark.continuum, &evasive).distance > direct.distance)
	data := campaign_serialize(
		&c,
	); defer delete(data); restored: Campaign; defer campaign_destroy(&restored); testing.expect(t, campaign_deserialize(data[:], &restored).ok); testing.expect_value(t, restored.passage.cleared_contact_id, u64(91)); testing.expect_value(t, restored.passage.dark_navigation.course.waypoints[2].position, course.waypoints[1].position); testing.expect_value(t, restored.ships[0].dark_contact_procedure, Dark_Contact_Procedure.Shear_Evasion); testing.expect_value(t, restored.ships[0].history_record_count, 1)
	second_threat :=
		c.passage.dark_navigation.tracker; second_threat.track_count = 3; second_threat.tracks[2] = {
		organism_id      = 93,
		role             = .Shear_Hunter,
		distance         = 2,
		estimated_extent = .7,
	}; testing.expect(t, dark_contact_pause_required(&c.passage, &second_threat))
	testing.expect(
		t,
		!dark_contact_pause_required(&c.passage, &c.passage.dark_navigation.tracker, true),
	); c.passage.dark_navigation.tracker.tracks[0].distance = 3.3; testing.expect(t, dark_contact_pause_required(&c.passage, &c.passage.dark_navigation.tracker, true)); testing.expect_value(t, c.passage.cleared_contact_id, u64(0)); c.passage.dark_navigation.tracker.tracks[0].distance = 1.8; testing.expect(t, dark_contact_pause_required(&c.passage, &c.passage.dark_navigation.tracker))
	_, ok = plot_passage_course(
		&c,
		&c.passage,
		course,
	); testing.expect(t, ok); c.passage.phase = .Awaiting_Leg; c.passage.pause_reason = .Dangerous_Contact; c.passage.dark_navigation.autopilot_active = false; c.ships[0].dark_contact_procedure = .Unspecified; history_before := c.ships[0].history_record_count
	ok, _ = respond_to_dark_contact(
		&c,
		&c.passage,
		true,
		91,
	); testing.expect(t, ok); testing.expect(t, dark_strategy_equal(c.passage.strategy, strategy_before)); testing.expect_value(t, c.passage.phase, Dark_Expedition_Phase.Underway); testing.expect(t, c.passage.dark_navigation.autopilot_active); testing.expect_value(t, c.passage.cleared_contact_id, u64(91)); testing.expect_value(t, c.passage.dark_navigation.course.waypoints[1].position, course.waypoints[1].position); testing.expect_value(t, c.ships[0].dark_contact_procedure, Dark_Contact_Procedure.Unspecified); testing.expect_value(t, c.ships[0].history_record_count, history_before)
	testing.expect(
		t,
		!dark_contact_pause_required(&c.passage, &c.passage.dark_navigation.tracker, true),
	); c.passage.dark_navigation.tracker.tracks[0].distance = 3.3; testing.expect(t, dark_contact_pause_required(&c.passage, &c.passage.dark_navigation.tracker, true)); c.passage.dark_navigation.tracker.tracks[0].distance = 1.8; testing.expect(t, dark_contact_pause_required(&c.passage, &c.passage.dark_navigation.tracker))
}

@(test)
dark_threat_assessment_exposes_warning_and_hold_clearance :: proc(t: ^testing.T) {
	hunter := Dark_Track {
		role             = .Shear_Hunter,
		distance         = 3.0,
		relative_bearing = {3, 0, 0, 0},
		velocity         = {-.1, 0, 0, 0},
	}
	warning := dark_track_threat(
		&hunter,
	); testing.expect_value(t, warning.level, Dark_Track_Threat_Level.Watch); testing.expect(t, warning.closing); testing.expect_value(t, warning.hold_distance, f64(2.5)); testing.expect_value(t, warning.warning_distance, f64(3.2)); testing.expect_value(t, warning.clearance, f64(.5))
	hunter.distance = 2.4; testing.expect_value(t, dark_track_threat(&hunter).level, Dark_Track_Threat_Level.Hold)
	reef := Dark_Track {
		role             = .Grave_Reef,
		distance         = 2.6,
		estimated_extent = 1,
	}; testing.expect_value(
		t,
		dark_track_threat(&reef).level,
		Dark_Track_Threat_Level.Watch,
	); reef.distance = 2; testing.expect_value(t, dark_track_threat(&reef).level, Dark_Track_Threat_Level.Hold)
	grazer := Dark_Track {
		role     = .Lantern_Grazer,
		distance = .2,
	}; testing.expect_value(t, dark_track_threat(&grazer).level, Dark_Track_Threat_Level.Clear)
}

@(test)
coherence_stabilization_turns_the_limit_into_a_costly_recovery :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1903,
	); defer campaign_destroy(&c); ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), []int{0, 1}, &c.passage); testing.expect(t, ok)
	p := &c.passage; course := Dark_Course {
		waypoint_count = 2,
	}; course.waypoints[0].position =
		p.dark_navigation.position; course.waypoints[1].position = dark_vec4_add(course.waypoints[0].position, {.4, 0, 0, 0}); _, ok = plot_passage_course(&c, p, course); testing.expect(t, ok); p.phase = .Awaiting_Leg; p.pause_reason = .Coherence_Limit; p.dark_navigation.autopilot_active = false; p.coherence_exposure = passage_coherence_limit(p) + .2
	quick := passage_coherence_recovery_preview(
		&c,
		p,
		false,
	); full := passage_coherence_recovery_preview(&c, p, true); testing.expect(t, quick.can_resume && !quick.crosses_limit); testing.expect(t, quick.ship_days < full.ship_days); testing.expect(t, quick.target_exposure > full.target_exposure)
	prior_days :=
		p.elapsed_days; ok, _ = stabilize_passage_coherence(&c, p, false); testing.expect(t, ok); testing.expect_value(t, p.phase, Dark_Expedition_Phase.Underway); testing.expect(t, p.dark_navigation.autopilot_active); testing.expect_value(t, p.dark_navigation.course.waypoints[1].position, course.waypoints[1].position); testing.expect_value(t, p.coherence_exposure, quick.target_exposure); testing.expect_value(t, p.elapsed_days, prior_days + quick.ship_days)
	p.phase = .Awaiting_Leg; p.pause_reason = .Coherence_Limit; p.dark_navigation.autopilot_active = false; p.coherence_exposure = passage_coherence_limit(p) + .2
	prior_days = p.elapsed_days; prior_cost, prior_events := p.course_cost, c.event_count
	ok, _ = stabilize_passage_coherence(
		&c,
		p,
		true,
	); testing.expect(t, ok); testing.expect_value(t, p.coherence_exposure, full.target_exposure); testing.expect(t, p.elapsed_days > prior_days); testing.expect(t, p.course_cost > prior_cost); testing.expect_value(t, p.phase, Dark_Expedition_Phase.Awaiting_Leg); testing.expect_value(t, p.pause_reason, Dark_Pause_Reason.None); testing.expect(t, !p.dark_navigation.autopilot_active); testing.expect_value(t, c.event_count, prior_events + 1)
}

@(test)
coherence_patch_is_unavailable_when_the_held_course_exceeds_its_buffer :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1906,
	); defer campaign_destroy(&c); ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), []int{0}, &c.passage); testing.expect(t, ok); p := &c.passage
	course := Dark_Course {
		waypoint_count = 8,
	}; course.waypoints[0].position =
		p.dark_navigation.position
	for waypoint in 1 ..< course.waypoint_count do course.waypoints[waypoint].position = waypoint % 2 == 0 ? course.waypoints[0].position : dark_vec4_add(course.waypoints[0].position, {4, 0, 0, 0})
	_, ok = plot_passage_course(&c, p, course); testing.expect(t, ok); p.phase = .Awaiting_Leg; p.pause_reason = .Coherence_Limit; p.dark_navigation.autopilot_active = false; p.coherence_exposure = passage_coherence_limit(p) + .1
	preview := passage_coherence_recovery_preview(
		&c,
		p,
		false,
	); testing.expect(t, preview.can_resume && preview.crosses_limit); before_days := p.elapsed_days; ok, _ = stabilize_passage_coherence(&c, p, false); testing.expect(t, !ok); testing.expect_value(t, p.elapsed_days, before_days); testing.expect_value(t, p.phase, Dark_Expedition_Phase.Awaiting_Leg); testing.expect_value(t, p.pause_reason, Dark_Pause_Reason.Coherence_Limit)
}

@(test)
material_obstruction_offers_destination_preserving_time_or_distance :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1907,
	); defer campaign_destroy(&c); ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), []int{0, 1}, &c.passage); testing.expect(t, ok); p := &c.passage
	original := Dark_Course {
		waypoint_count = 2,
	}; original.waypoints[0].position =
		p.dark_navigation.position; original.waypoints[1].position = dark_vec4_add(original.waypoints[0].position, {5, 0, 0, 1}); _, ok = plot_passage_course(&c, p, original); testing.expect(t, ok); p.phase = .Awaiting_Leg; p.pause_reason = .Material_Obstruction; p.dark_navigation.autopilot_active = false; p.dark_navigation.paused_for_replan = true
	preview := passage_obstruction_response_preview(
		&c,
		p,
	); testing.expect(t, preview.can_detour && preview.detour_added > 0); testing.expect(t, preview.can_wait && preview.wait_ship_days > 0)
	ok, _ = respond_to_material_obstruction(
		&c,
		p,
		false,
	); testing.expect(t, ok); testing.expect_value(t, p.phase, Dark_Expedition_Phase.Underway); testing.expect(t, p.dark_navigation.autopilot_active && !p.dark_navigation.paused_for_replan); testing.expect_value(t, p.dark_navigation.course.waypoints[p.dark_navigation.course.waypoint_count - 1].position, original.waypoints[1].position)
	_, ok = plot_passage_course(
		&c,
		p,
		original,
	); testing.expect(t, ok); p.phase = .Awaiting_Leg; p.pause_reason = .Material_Obstruction; p.dark_navigation.autopilot_active = false; p.dark_navigation.paused_for_replan = true; tick_before := c.outer_dark.continuum.simulation_tick; days_before := p.elapsed_days
	ok, _ = respond_to_material_obstruction(
		&c,
		p,
		true,
	); testing.expect(t, ok); testing.expect_value(t, p.phase, Dark_Expedition_Phase.Underway); testing.expect(t, p.dark_navigation.autopilot_active && !p.dark_navigation.paused_for_replan); testing.expect_value(t, p.dark_navigation.course.waypoints[1].position, original.waypoints[1].position); testing.expect(t, p.elapsed_days > days_before); testing.expect(t, c.outer_dark.continuum.simulation_tick > tick_before)
}

@(test)
manual_helm_obstruction_can_drift_clear_without_a_held_destination :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1908,
	); defer campaign_destroy(&c); ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), []int{0}, &c.passage); testing.expect(t, ok); p := &c.passage; p.dark_navigation.course = {}; p.dark_navigation.paused_for_replan = true; p.dark_navigation.autopilot_active = false; p.phase = .Awaiting_Leg; p.pause_reason = .Material_Obstruction
	preview := passage_obstruction_response_preview(
		&c,
		p,
	); testing.expect(t, !preview.can_detour && !preview.has_held_course && preview.can_wait); ok, _ = respond_to_material_obstruction(&c, p, true); testing.expect(t, ok); testing.expect_value(t, p.phase, Dark_Expedition_Phase.Awaiting_Leg); testing.expect_value(t, p.pause_reason, Dark_Pause_Reason.None); testing.expect(t, !p.dark_navigation.autopilot_active && !p.dark_navigation.paused_for_replan)
}

@(test)
ecological_roles_require_a_costly_documentation_commitment :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1904,
	); defer campaign_destroy(&c); c.ships[0].role = .Hospital; contract := default_passage_contract(); contract.purpose = .Ecological_Survey; contract.required_ecology_roles = u32(1) << u32(Dark_Ecological_Role.Lantern_Grazer); ok, _ := begin_authorized_test_passage(&c, contract, []int{0}, &c.passage); testing.expect(t, ok)
	p := &c.passage; p.dark_navigation.tracker = {
		track_count = 1,
	}; p.dark_navigation.tracker.tracks[0] = {
		organism_id = 91,
		role        = .Lantern_Grazer,
		confidence  = .4,
	}; dark_update_local_observations(p, &p.dark_navigation.tracker, 1)
	testing.expect_value(
		t,
		p.observed_ecology_roles,
		u32(0),
	); prior_days, prior_coherence, prior_events := p.elapsed_days, p.coherence_exposure, c.event_count
	ok, _ = document_dark_contact(&c, p, 91); testing.expect(t, !ok)
	ship_at := ship_index(&c, p.ships[0]); c.ships[ship_at].role = .Survey
	ok, _ = document_dark_contact(
		&c,
		p,
		91,
	); testing.expect(t, ok); testing.expect_value(t, p.observed_ecology_roles, p.contract.required_ecology_roles); testing.expect(t, p.contract.objective_met); testing.expect(t, p.elapsed_days > prior_days); testing.expect(t, p.coherence_exposure > prior_coherence); testing.expect_value(t, p.phase, Dark_Expedition_Phase.Awaiting_Leg); testing.expect_value(t, p.pause_reason, Dark_Pause_Reason.Contract_Evidence); testing.expect_value(t, c.event_count, prior_events + 1); testing.expect(t, p.local_observations[0].confidence >= .9)
}

@(test)
passage_course_time_forecast_tracks_expedition_speed_and_depth :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1910)
	defer campaign_destroy(&c)
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), []int{0}, &c.passage)
	testing.expect(t, ok)
	if !ok do return
	p := &c.passage
	course := Dark_Course{waypoint_count = 2}
	course.waypoints[0].position = p.dark_navigation.position
	course.waypoints[1].position = dark_vec4_add(course.waypoints[0].position, {2, 0, 0, 3})
	baseline := passage_course_time_forecast(&c, p, &course)
	p.dark_navigation.speed *= .5
	slower := passage_course_time_forecast(&c, p, &course)
	testing.expect(t, slower.ship_days > baseline.ship_days)
	testing.expect(t, slower.membrane_days > baseline.membrane_days)
	shallow := course
	shallow.waypoints[1].position[3] = course.waypoints[0].position[3]
	shallow_time := passage_course_time_forecast(&c, p, &shallow)
	testing.expect(t, shallow_time.membrane_days > slower.membrane_days)
	tiny := Dark_Course{waypoint_count = 2}
	tiny.waypoints[0].position = p.dark_navigation.position
	tiny.waypoints[1].position = dark_vec4_add(tiny.waypoints[0].position, {.001, 0, 0, 0})
	tiny_time := passage_course_time_forecast(&c, p, &tiny)
	testing.expect_value(t, tiny_time.ship_days, DARK_FIXED_STEP * .72)
	for &organism in c.outer_dark.continuum.organisms[:c.outer_dark.continuum.organism_count] do organism.alive = false
	before_ship_days, before_membrane_days := p.elapsed_days, p.membrane_elapsed_days
	_, plotted := plot_passage_course(&c, p, tiny)
	testing.expect(t, plotted)
	advance_passage(&c, p, DARK_FIXED_STEP)
	testing.expect_value(t, p.elapsed_days - before_ship_days, tiny_time.ship_days)
	testing.expect_value(t, p.membrane_elapsed_days - before_membrane_days, tiny_time.membrane_days)
}

@(test)
course_forecast_exposes_coherence_threshold_and_ship_history :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1905,
	); defer campaign_destroy(&c); ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), []int{0}, &c.passage); testing.expect(t, ok); p := &c.passage
	shallow := Dark_Course {
		waypoint_count = 2,
	}; shallow.waypoints[0].position =
		p.dark_navigation.position; shallow.waypoints[1].position = dark_vec4_add(shallow.waypoints[0].position, {2, 0, 0, 0})
	deep :=
		shallow; deep.waypoint_count = 3; deep.waypoints[1].position = dark_vec4_add(shallow.waypoints[0].position, {1, 0, 0, 4}); deep.waypoints[2].position = shallow.waypoints[1].position
	a := passage_course_coherence_forecast(
		&c,
		p,
		&shallow,
	); b := passage_course_coherence_forecast(&c, p, &deep); testing.expect(t, b.added > a.added); testing.expect_value(t, b.projected, b.current + b.added); testing.expect_value(t, b.limit, passage_coherence_limit(p))
	ship_at := ship_index(
		&c,
		p.ships[0],
	); c.ships[ship_at].dark_field_scars = 6; scarred := passage_course_coherence_forecast(&c, p, &shallow); testing.expect(t, scarred.added > a.added)
	p.coherence_exposure =
		passage_coherence_limit(p) -
		a.added *
			.5; near_limit := passage_course_coherence_forecast(&c, p, &shallow); testing.expect(t, near_limit.crosses_limit)
}
