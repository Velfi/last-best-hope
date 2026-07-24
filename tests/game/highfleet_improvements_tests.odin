package game_tests

import "core:testing"

@(test)
passage_sensor_postures_trade_information_for_exposure :: proc(t: ^testing.T) {
	quiet := dark_sensor_profile(.Quiet)
	passive := dark_sensor_profile(.Passive)
	active := dark_sensor_profile(.Active_Sweep)
	illuminate := dark_sensor_profile(.Illuminate)
	testing.expect(t, quiet.range_scale < passive.range_scale)
	testing.expect(t, passive.range_scale < active.range_scale)
	testing.expect(t, active.range_scale < illuminate.range_scale)
	testing.expect(t, quiet.emission == 0 && passive.emission == 0)
	testing.expect(t, active.emission > 0 && illuminate.emission > active.emission)
	testing.expect(t, active.coherence_rate > passive.coherence_rate)
	testing.expect(t, illuminate.coherence_rate > active.coherence_rate)
}

@(test)
passage_sensor_posture_is_deterministic_and_attributable :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 9861)
	b: Campaign
	campaign_init(&b, 9861)
	defer campaign_destroy(&a)
	defer campaign_destroy(&b)
	ok_a, _ := begin_authorized_test_passage(&a, default_passage_contract(), []int{0}, &a.passage)
	ok_b, _ := begin_authorized_test_passage(&b, default_passage_contract(), []int{0}, &b.passage)
	testing.expect(t, ok_a && ok_b)
	testing.expect_value(t, a.passage.dark_navigation.sensor_posture, Dark_Sensor_Posture.Passive)
	changed_a, _ := set_dark_sensor_posture(&a, &a.passage, .Illuminate)
	changed_b, _ := set_dark_sensor_posture(&b, &b.passage, .Illuminate)
	testing.expect(t, changed_a && changed_b)
	testing.expect_value(
		t,
		a.passage.dark_navigation.sensor_posture_event,
		b.passage.dark_navigation.sensor_posture_event,
	)
	testing.expect_value(t, a.event_sequence, b.event_sequence)
	testing.expect(t, a.ships[0].history_record_count > 0)
}

@(test)
course_forecast_reports_observed_inferred_and_unknown_causes :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 9862)
	defer campaign_destroy(&c)
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), []int{0}, &c.passage)
	testing.expect(t, ok)
	c.ships[0].impairments.sensors = 2
	course := Dark_Course {
		waypoint_count = 2,
	}
	course.waypoints[0].position = c.passage.dark_navigation.position
	course.waypoints[1].position = c.passage.dark_navigation.position
	course.waypoints[1].position[3] += 3
	forecast := passage_dark_course_forecast(&c, &c.passage, &course)
	testing.expect(t, forecast.valid)
	testing.expect(t, forecast.factor_count >= 4)
	has_observed, has_inferred, has_unknown := false, false, false
	for factor in forecast.factors[:forecast.factor_count] {
		has_observed = has_observed || factor.evidence == .Observed
		has_inferred = has_inferred || factor.evidence == .Inferred
		has_unknown = has_unknown || factor.evidence == .Unknown
	}
	testing.expect(t, has_observed && has_inferred && has_unknown)
}

@(test)
typed_impairments_change_deployment_and_repairs_preserve_history :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 9863)
	defer campaign_destroy(&c)
	ids := [3]Ship_ID{c.ships[0].id, c.ships[1].id, c.ships[2].id}
	groups := [3]int{0, 1, 2}
	before := combat_deployment_preview(&c, ids[:], groups[:])
	c.ships[0].damage = 2
	c.ships[0].impairments = {
		mobility  = 2,
		strike    = 2,
		endurance = 2,
	}
	after := combat_deployment_preview(&c, ids[:], groups[:])
	testing.expect(t, after.control <= before.control)
	testing.expect(t, after.strike <= before.strike)
	testing.expect(t, after.endurance < before.endurance)
	testing.expect(t, after.factor_count > 0)
	add_ship_history(&c, c.ships[0].id, "The ship kept the record of its wound.")
	history_count := c.ships[0].history_record_count
	ship_clear_one_impairment(&c.ships[0])
	testing.expect(t, ship_impairment_total(c.ships[0].impairments) == 5)
	ship_clear_impairments(&c.ships[0])
	testing.expect_value(t, ship_impairment_total(c.ships[0].impairments), i32(0))
	testing.expect_value(t, c.ships[0].history_record_count, history_count)
}

@(test)
sensor_posture_and_impairments_survive_save_round_trip :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 9864)
	defer campaign_destroy(&c)
	ok, _ := begin_authorized_test_passage(&c, default_passage_contract(), []int{0}, &c.passage)
	testing.expect(t, ok)
	_, _ = set_dark_sensor_posture(&c, &c.passage, .Active_Sweep)
	c.ships[0].impairments = {
		mobility  = 1,
		sensors   = 2,
		endurance = 1,
	}
	data := campaign_serialize(&c)
	defer delete(data)
	restored: Campaign
	defer campaign_destroy(&restored)
	result := campaign_deserialize(data[:], &restored)
	testing.expect(t, result.ok)
	testing.expect_value(
		t,
		restored.passage.dark_navigation.sensor_posture,
		Dark_Sensor_Posture.Active_Sweep,
	)
	testing.expect_value(t, restored.ships[0].impairments, c.ships[0].impairments)
}

@(test)
retired_save_format_is_rejected_without_mutating_destination :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 9865)
	defer campaign_destroy(&c)
	data := campaign_serialize(&c)
	defer delete(data)
	retired_version := u32(68)
	for i in 0 ..< 4 do data[4 + i] = u8(retired_version >> u32(i * 8))
	restored: Campaign
	defer campaign_destroy(&restored)
	restored.initial_seed = 771
	result := campaign_deserialize(data[:], &restored)
	testing.expect(t, !result.ok)
	testing.expect_value(t, restored.initial_seed, u64(771))
}
