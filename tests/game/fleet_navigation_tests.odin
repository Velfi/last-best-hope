package game_tests

import game "../../packages/game"
import "core:math"
import "core:testing"

navigation_test_forecast :: proc(c: ^game.Campaign) -> (game.Fleet_Transfer_Forecast, bool) {
	options := [6]i64{60, 120, 240, 480, 720, 1200}
	for deposit in c.fleet_navigation.deposits[:c.fleet_navigation.deposit_count] {
		if deposit.body == c.fleet_navigation.current_body do continue
		for days in options {
			arrival := game.campaign_time_add(c.clock.now, days * game.CAMPAIGN_DAY_SECONDS)
			forecast := game.fleet_transfer_forecast(c, deposit.body, arrival)
			if forecast.valid && forecast.feasible do return forecast, true
		}
	}
	return {}, false
}

@(test)
long_term_navigation_goal_tracks_charted_dark_progress_to_a_habitable_contact :: proc(
	t: ^testing.T,
) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	target := (c.outer_dark.continuum.anchor_neighborhood + 1) % c.galaxy.neighborhood_count
	contact := game.Habitable_World_Contact {
		id                 = 0x48414231,
		neighborhood_index = target,
	}
	append(&c.habitable_contacts, contact)
	testing.expect_value(
		t,
		game.habitable_contact_intel(c, contact),
		game.Habitable_Contact_Intel.Signature,
	)
	ok, _ := game.long_term_navigation_goal_set(c, contact.id)
	testing.expect(t, ok)
	initial := game.long_term_navigation_goal_progress(c)
	testing.expect(t, initial.valid)
	testing.expect_value(t, initial.progress, 0.0)
	testing.expect_value(t, initial.stage, game.Long_Term_Navigation_Stage.Charting)
	append(
		&c.dark_fleet_atlas,
		game.Dark_Atlas_Discovery{door_id = 0x444f4f52, galaxy_neighborhood = target},
	)
	advanced := game.long_term_navigation_goal_progress(c)
	testing.expect(t, advanced.progress > initial.progress)
	testing.expect_value(t, advanced.closest_mapped_neighborhood, target)
	append(
		&c.dark_relays,
		game.Dark_Relay_Record {
			id = 0x52454c41,
			galaxy_neighborhood = target,
			authenticated = true,
		},
	)
	reached := game.long_term_navigation_goal_progress(c)
	testing.expect_value(t, reached.stage, game.Long_Term_Navigation_Stage.Reached)
	testing.expect_value(
		t,
		game.habitable_contact_intel(c, contact),
		game.Habitable_Contact_Intel.Local_Survey,
	)
}

@(test)
habitable_contact_intelligence_reveals_at_sensor_resolution_thresholds :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		game.habitable_contact_intel_from_sensor_resolution(false, false, .Charting, 1),
		game.Habitable_Contact_Intel.Signature,
	)
	testing.expect_value(
		t,
		game.habitable_contact_intel_from_sensor_resolution(true, false, .Charting, 50001),
		game.Habitable_Contact_Intel.Signature,
	)
	testing.expect_value(
		t,
		game.habitable_contact_intel_from_sensor_resolution(true, false, .Charting, 50000),
		game.Habitable_Contact_Intel.Orbital,
	)
	testing.expect_value(
		t,
		game.habitable_contact_intel_from_sensor_resolution(true, false, .Charting, 10000),
		game.Habitable_Contact_Intel.Climate,
	)
	testing.expect_value(
		t,
		game.habitable_contact_intel_from_sensor_resolution(true, false, .Reached, 100000),
		game.Habitable_Contact_Intel.Local_Survey,
	)
	testing.expect_value(
		t,
		game.habitable_contact_intel_from_sensor_resolution(true, true, .Charting, 100000),
		game.Habitable_Contact_Intel.Surveyed,
	)
}

@(test)
long_term_navigation_goal_survives_campaign_round_trip :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	target := (c.outer_dark.continuum.anchor_neighborhood + 1) % c.galaxy.neighborhood_count
	contact := game.Habitable_World_Contact {
		id                 = 0x48414232,
		neighborhood_index = target,
	}
	append(&c.habitable_contacts, contact)
	ok, _ := game.long_term_navigation_goal_set(c, contact.id)
	testing.expect(t, ok)
	if !ok do return
	data := game.campaign_serialize(c)
	defer delete(data)
	restored := game.new_campaign_heap(1)
	defer game.campaign_destroy_heap(restored)
	result := game.campaign_deserialize(data[:], restored)
	testing.expect(t, result.ok)
	if !result.ok do return
	testing.expect_value(t, restored.long_term_navigation_goal.contact_id, contact.id)
	testing.expect_value(t, restored.long_term_navigation_goal.target_neighborhood, target)
}

@(test)
fleet_navigation_initializes_physical_propellant_and_water_sources :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	testing.expect(t, c.fleet_navigation.initialized)
	testing.expect(t, c.fleet_navigation.deposit_count > 0)
	testing.expect(t, game.fleet_propellant_capacity(c) > 0)
	testing.expect(t, game.fleet_propellant_remaining(c) > game.fleet_propellant_reserve(c))
	testing.expect_value(
		t,
		c.material_economy.fleet.stock.propellant,
		i64(math.floor(game.fleet_propellant_remaining(c) + .5)),
	)
	for ship in c.ships[:c.ship_count] {
		testing.expect(t, ship.propellant_capacity_kt > 0)
		testing.expect(t, ship.propellant_kt > 0)
		testing.expect(t, ship.propellant_kt <= ship.propellant_capacity_kt)
	}
}

@(test)
asteroid_resource_deposits_have_deterministic_composition_and_finite_feedstock :: proc(
	t: ^testing.T,
) {
	a := game.new_campaign_heap(24301)
	b := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(a)
	defer game.campaign_destroy_heap(b)
	testing.expect_value(t, a.fleet_navigation.deposits, b.fleet_navigation.deposits)
	for deposit in a.fleet_navigation.deposits[:a.fleet_navigation.deposit_count] {
		testing.expect(t, deposit.initial_propellant_kt >= deposit.remaining_propellant_kt)
		testing.expect(t, deposit.initial_feedstock >= deposit.remaining_feedstock)
		switch deposit.composition {
		case .Icy:
			testing.expect(t, deposit.water_fraction > deposit.feedstock_fraction)
		case .Metallic:
			testing.expect(t, deposit.feedstock_fraction > deposit.water_fraction)
		case .Carbonaceous, .Silicate:
		}
	}
}

@(test)
holding_at_a_material_body_surveys_it_and_recovers_feedstock :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	deposit := &c.fleet_navigation.deposits[0]
	c.fleet_navigation.current_body = deposit.body
	game.fleet_resource_intel_update(c)
	testing.expect_value(t, deposit.intel, game.Resource_Intel.Surveyed)
	before_stock := c.material_economy.fleet.stock.raw_materials
	before_source := deposit.remaining_feedstock
	deadline := game.campaign_time_add(c.clock.now, 120 * game.CAMPAIGN_DAY_SECONDS)
	ok, _ := game.fleet_navigation_commit_harvest(
		c,
		game.fleet_propellant_remaining(c),
		deadline,
		min(game.fleet_feedstock_headroom(c), deposit.remaining_feedstock),
	)
	testing.expect(t, ok)
	advanced := game.campaign_advance_exact(
		c,
		i64(c.fleet_navigation.harvest.due_at) - i64(c.clock.now),
	)
	testing.expect(t, advanced > 0)
	testing.expect(t, c.material_economy.fleet.stock.raw_materials >= before_stock)
	testing.expect(t, deposit.remaining_feedstock < before_source || before_source == 0)
}

@(test)
fleet_transfer_forecast_is_deterministic_and_commit_conserves_propellant :: proc(t: ^testing.T) {
	a := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(a)
	b := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(b)
	first, found := navigation_test_forecast(a)
	testing.expect(t, found)
	if !found do return
	second := game.fleet_transfer_forecast(b, first.target, first.arrival_at)
	testing.expect_value(t, first, second)
	before := game.fleet_propellant_remaining(a)
	ok, _ := game.fleet_navigation_commit_transfer(a, first)
	testing.expect(t, ok)
	testing.expect(
		t,
		math.abs(game.fleet_propellant_remaining(a) - (before - first.propellant_cost_kt)) < 1e-6,
	)
	testing.expect_value(t, a.fleet_navigation.phase, game.Fleet_Navigation_Phase.Transfer)
	advanced := game.campaign_advance_exact(a, i64(first.arrival_at) - i64(a.clock.now))
	testing.expect(t, advanced > 0)
	testing.expect_value(t, a.fleet_navigation.phase, game.Fleet_Navigation_Phase.Holding)
	testing.expect(t, a.fleet_navigation.current_body == first.target)
	pending := game.campaign_pending_attention(a)
	testing.expect(t, pending != nil)
	if pending != nil do testing.expect_value(t, pending.source, game.Attention_Source.Fleet_Navigation)
}

@(test)
fleet_transfer_forecast_accounts_for_ship_damage_and_mobility_impairment :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	baseline, found := navigation_test_forecast(c)
	testing.expect(t, found)
	if !found do return
	testing.expect(t, baseline.has_recovery_source)
	for &ship in c.ships[:c.ship_count] {
		if !ship.active || ship.committed do continue
		ship.damage += 2
		ship.impairments.mobility = 2
	}
	impaired := game.fleet_transfer_forecast(c, baseline.target, baseline.arrival_at)
	testing.expect(t, impaired.valid)
	testing.expect(t, impaired.total_delta_v_km_s == baseline.total_delta_v_km_s)
	testing.expect(t, impaired.propellant_cost_kt > baseline.propellant_cost_kt)
	testing.expect(t, impaired.propellant_after_kt < baseline.propellant_after_kt)
}

@(test)
fleet_transfer_forecast_exposes_destination_recovery_shortfall :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	forecast, found := navigation_test_forecast(c)
	testing.expect(t, found)
	if !found do return
	at := game.fleet_deposit_index(c, forecast.target)
	testing.expect(t, at >= 0)
	if at < 0 do return
	c.fleet_navigation.deposits[at].remaining_propellant_kt = forecast.propellant_cost_kt * .25
	limited := game.fleet_transfer_forecast(c, forecast.target, forecast.arrival_at)
	testing.expect(t, limited.expected_harvest_kt < limited.propellant_cost_kt)
	testing.expect(t, limited.recovery_shortfall_kt > 0)
	testing.expect(
		t,
		limited.expected_harvest_kt + limited.recovery_shortfall_kt >=
		limited.propellant_cost_kt - 1e-9,
	)
}

@(test)
fleet_navigation_best_window_is_deterministic_safe_and_lowest_burn_on_its_grid :: proc(
	t: ^testing.T,
) {
	a := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(a)
	b := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(b)
	baseline, available := navigation_test_forecast(a)
	testing.expect(t, available)
	if !available do return
	target := baseline.target
	first, found := game.fleet_transfer_best_window(a, target, 60, 1200, 60)
	second, matched := game.fleet_transfer_best_window(b, target, 60, 1200, 60)
	testing.expect(t, found)
	testing.expect(t, matched)
	if !found || !matched do return
	testing.expect_value(t, first, second)
	testing.expect(t, first.valid && first.feasible && !first.crosses_reserve)
	for days := i64(60); days <= 1200; days += 60 {
		candidate := game.fleet_transfer_forecast(
			a,
			target,
			game.campaign_time_add(a.clock.now, days * game.CAMPAIGN_DAY_SECONDS),
		)
		if candidate.valid && candidate.feasible do testing.expect(t, first.propellant_cost_kt <= candidate.propellant_cost_kt + 1e-9)
	}
}

@(test)
fleet_navigation_fastest_window_is_deterministic_and_first_safe_on_its_grid :: proc(
	t: ^testing.T,
) {
	a := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(a)
	b := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(b)
	baseline, available := navigation_test_forecast(a)
	testing.expect(t, available)
	if !available do return
	first, found := game.fleet_transfer_fastest_safe_window(a, baseline.target, 30, 1200, 5)
	second, matched := game.fleet_transfer_fastest_safe_window(b, baseline.target, 30, 1200, 5)
	testing.expect(t, found)
	testing.expect(t, matched)
	if !found || !matched do return
	testing.expect_value(t, first, second)
	testing.expect(t, first.valid && first.feasible && !first.crosses_reserve)
	for days := i64(30); days < i64(first.duration_days); days += 5 {
		candidate := game.fleet_transfer_forecast(
			a,
			baseline.target,
			game.campaign_time_add(a.clock.now, days * game.CAMPAIGN_DAY_SECONDS),
		)
		testing.expect(t, !candidate.valid || !candidate.feasible)
	}
}

@(test)
fleet_transfer_requires_recorded_emergency_authority_below_reserve :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	c.fleet_navigation.protected_reserve_fraction = .64
	forecast: game.Fleet_Transfer_Forecast
	found := false
	options := [6]i64{60, 120, 240, 480, 720, 1200}
	for deposit in c.fleet_navigation.deposits[:c.fleet_navigation.deposit_count] {
		if deposit.body == c.fleet_navigation.current_body do continue
		for days in options {
			candidate := game.fleet_transfer_forecast(
				c,
				deposit.body,
				game.campaign_time_add(c.clock.now, days * game.CAMPAIGN_DAY_SECONDS),
			)
			if candidate.valid && candidate.crosses_reserve {
				forecast = candidate
				found = true
				break
			}
		}
		if found do break
	}
	testing.expect(t, found)
	if !found do return
	ok, _ := game.fleet_navigation_commit_transfer(c, forecast)
	testing.expect(t, !ok)
	before_events := c.event_sequence
	ok, _ = game.fleet_navigation_commit_transfer(c, forecast, true)
	testing.expect(t, ok)
	testing.expect(t, c.fleet_navigation.transfer.emergency_override)
	testing.expect(t, c.event_sequence > before_events)
}

@(test)
fleet_transfer_cannot_use_emergency_authority_for_an_unexecutable_burn :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	forecast, found := navigation_test_forecast(c)
	testing.expect(t, found)
	if !found do return
	for &ship in c.ships[:c.ship_count] {
		if !ship.active || ship.committed do continue
		ship.propellant_kt = 0
	}
	impossible := game.fleet_transfer_forecast(c, forecast.target, forecast.arrival_at)
	testing.expect(t, !impossible.valid)
	ok, _ := game.fleet_navigation_commit_transfer(c, impossible, true)
	testing.expect(t, !ok)
	testing.expect_value(t, c.fleet_navigation.phase, game.Fleet_Navigation_Phase.Holding)
}

@(test)
fleet_transfer_stops_for_a_material_deviation_without_cancelling_the_leg :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	forecast, found := navigation_test_forecast(c)
	testing.expect(t, found)
	if !found do return
	ok, _ := game.fleet_navigation_commit_transfer(c, forecast)
	testing.expect(t, ok)
	if !ok do return
	for &ship in c.ships[:c.ship_count] {
		if !ship.active || ship.committed do continue
		ship.impairments.mobility = 3
		break
	}
	advanced := game.campaign_advance_exact(c, game.CAMPAIGN_HOUR_SECONDS)
	testing.expect_value(t, advanced, game.CAMPAIGN_HOUR_SECONDS)
	testing.expect_value(t, c.fleet_navigation.phase, game.Fleet_Navigation_Phase.Transfer)
	testing.expect(t, c.fleet_navigation.transfer.active)
	testing.expect(t, c.fleet_navigation.transfer.deviation_reported)
	pending := game.campaign_pending_attention(c)
	testing.expect(t, pending != nil)
	if pending != nil do testing.expect_value(t, pending.title, "NAVIGATION PLAN DEVIATED")
}

@(test)
fleet_harvest_stops_and_revises_its_deadline_when_throughput_is_damaged :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	deposit := &c.fleet_navigation.deposits[0]
	c.fleet_navigation.current_body = deposit.body
	_ = game.fleet_propellant_distribute(c, game.fleet_propellant_capacity(c) * .25)
	deadline := game.campaign_time_add(c.clock.now, 120 * game.CAMPAIGN_DAY_SECONDS)
	ok, _ := game.fleet_navigation_commit_harvest(
		c,
		game.fleet_propellant_capacity(c) * .75,
		deadline,
	)
	testing.expect(t, ok)
	if !ok do return
	old_due := c.fleet_navigation.harvest.due_at
	for &ship in c.ships[:c.ship_count] {
		if !ship.active || ship.committed do continue
		ship.impairments.support = 3
		break
	}
	advanced := game.campaign_advance_exact(c, game.CAMPAIGN_HOUR_SECONDS)
	testing.expect_value(t, advanced, game.CAMPAIGN_HOUR_SECONDS)
	testing.expect_value(t, c.fleet_navigation.phase, game.Fleet_Navigation_Phase.Harvesting)
	testing.expect(t, c.fleet_navigation.harvest.deviation_reported)
	testing.expect(t, c.fleet_navigation.harvest.due_at >= old_due)
	pending := game.campaign_pending_attention(c)
	testing.expect(t, pending != nil)
	if pending != nil do testing.expect_value(t, pending.title, "RECOVERY PLAN DEVIATED")
}

@(test)
fleet_harvest_throughput_deviation_preserves_the_declared_departure_deadline :: proc(
	t: ^testing.T,
) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	deposit := &c.fleet_navigation.deposits[0]
	c.fleet_navigation.current_body = deposit.body
	_ = game.fleet_propellant_distribute(c, game.fleet_propellant_capacity(c) * .25)
	deadline := game.campaign_time_add(c.clock.now, game.CAMPAIGN_DAY_SECONDS)
	ok, _ := game.fleet_navigation_commit_harvest(
		c,
		game.fleet_propellant_capacity(c) * .9,
		deadline,
	)
	testing.expect(t, ok)
	if !ok do return
	initial_gain := c.fleet_navigation.harvest.planned_propellant_kt
	for &ship in c.ships[:c.ship_count] {
		if !ship.active || ship.committed do continue
		ship.impairments.support = 3
		break
	}
	_ = game.campaign_advance_exact(c, game.CAMPAIGN_HOUR_SECONDS)
	testing.expect_value(t, c.fleet_navigation.harvest.due_at, deadline)
	testing.expect_value(
		t,
		c.fleet_navigation.harvest.stop,
		game.Fleet_Navigation_Stop.Latest_Departure,
	)
	testing.expect(t, c.fleet_navigation.harvest.planned_propellant_kt < initial_gain)
}

@(test)
fleet_harvest_stops_at_declared_condition_and_depletes_the_source :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	testing.expect(t, c.fleet_navigation.deposit_count > 0)
	if c.fleet_navigation.deposit_count <= 0 do return
	deposit := &c.fleet_navigation.deposits[0]
	c.fleet_navigation.current_body = deposit.body
	_ = game.fleet_propellant_distribute(c, game.fleet_propellant_capacity(c) * .25)
	before_propellant := game.fleet_propellant_remaining(c)
	before_deposit := deposit.remaining_propellant_kt
	target := min(game.fleet_propellant_capacity(c) * .5, before_propellant + 1)
	deadline := game.campaign_time_add(c.clock.now, 120 * game.CAMPAIGN_DAY_SECONDS)
	forecast := game.fleet_harvest_forecast(c, target, deadline)
	testing.expect(t, forecast.valid)
	if !forecast.valid do return
	ok, _ := game.fleet_navigation_commit_harvest(c, target, deadline)
	testing.expect(t, ok)
	advanced := game.campaign_advance_exact(
		c,
		i64(c.fleet_navigation.harvest.due_at) - i64(c.clock.now),
	)
	testing.expect(t, advanced > 0)
	testing.expect(t, game.fleet_propellant_remaining(c) > before_propellant)
	testing.expect(t, deposit.remaining_propellant_kt < before_deposit)
	testing.expect_value(t, c.fleet_navigation.phase, game.Fleet_Navigation_Phase.Holding)
}

@(test)
fleet_metabolism_does_not_create_propellant_and_direct_relativistic_legs_are_retired :: proc(
	t: ^testing.T,
) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	before := game.fleet_propellant_remaining(c)
	game.advance_fleet_metabolism(c)
	testing.expect(t, math.abs(game.fleet_propellant_remaining(c) - before) < 1e-9)
	c.passage.active = true
	c.passage.domain = .Normal_Space
	c.passage.phase = .Awaiting_Leg
	testing.expect(t, !game.plot_normal_course(c, &c.passage, 1, .18))
}

@(test)
fleet_navigation_round_trip_preserves_active_order_and_deposits :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	forecast, found := navigation_test_forecast(c)
	testing.expect(t, found)
	if !found do return
	ok, _ := game.fleet_navigation_commit_transfer(c, forecast)
	testing.expect(t, ok)
	// Acknowledged deviations must not become duplicate attention stops after a
	// save/load while the transfer is still underway.
	c.fleet_navigation.transfer.deviation_reported = true
	data := game.campaign_serialize(c)
	defer delete(data)
	restored := game.new_campaign_heap(1)
	defer game.campaign_destroy_heap(restored)
	result := game.campaign_deserialize(data[:], restored)
	testing.expect(t, result.ok)
	testing.expect_value(t, restored.fleet_navigation.phase, c.fleet_navigation.phase)
	testing.expect_value(t, restored.fleet_navigation.transfer.active, true)
	testing.expect_value(t, restored.fleet_navigation.transfer.deviation_reported, true)
	testing.expect_value(t, restored.fleet_navigation.transfer.forecast.target, forecast.target)
	testing.expect_value(
		t,
		restored.fleet_navigation.deposit_count,
		c.fleet_navigation.deposit_count,
	)
	testing.expect(
		t,
		math.abs(game.fleet_propellant_remaining(restored) - game.fleet_propellant_remaining(c)) <
		1e-6,
	)
}

@(test)
fleet_navigation_harvest_round_trip_preserves_revised_order_state :: proc(t: ^testing.T) {
	c := game.new_campaign_heap(24301)
	defer game.campaign_destroy_heap(c)
	deposit := &c.fleet_navigation.deposits[0]
	c.fleet_navigation.current_body = deposit.body
	_ = game.fleet_propellant_distribute(c, game.fleet_propellant_capacity(c) * .25)
	deadline := game.campaign_time_add(c.clock.now, 120 * game.CAMPAIGN_DAY_SECONDS)
	ok, _ := game.fleet_navigation_commit_harvest(
		c,
		game.fleet_propellant_capacity(c) * .7,
		deadline,
	)
	testing.expect(t, ok)
	if !ok do return
	c.fleet_navigation.harvest.deviation_reported = true
	data := game.campaign_serialize(c)
	defer delete(data)
	restored := game.new_campaign_heap(1)
	defer game.campaign_destroy_heap(restored)
	result := game.campaign_deserialize(data[:], restored)
	testing.expect(t, result.ok)
	if !result.ok do return
	testing.expect_value(
		t,
		restored.fleet_navigation.phase,
		game.Fleet_Navigation_Phase.Harvesting,
	)
	testing.expect_value(t, restored.fleet_navigation.harvest.active, true)
	testing.expect_value(t, restored.fleet_navigation.harvest.deviation_reported, true)
	testing.expect_value(
		t,
		restored.fleet_navigation.harvest.planned_propellant_rate_kt_day,
		c.fleet_navigation.harvest.planned_propellant_rate_kt_day,
	)
	testing.expect_value(
		t,
		restored.fleet_navigation.harvest.due_at,
		c.fleet_navigation.harvest.due_at,
	)
}
