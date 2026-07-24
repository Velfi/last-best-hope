package game_tests

import "core:testing"

@(test)
campaign_balance_setup_defaults_and_lengths :: proc(t: ^testing.T) {
	d := civilization_setup_generate(5301)
	testing.expect_value(t, d.length, Chronicle_Length.Standard)
	testing.expect_value(t, d.material_pressure, Material_Pressure.Standard)
	testing.expect_value(t, d.consequence_severity, Consequence_Severity.Standard)
	testing.expect_value(t, chronicle_length_seasons(.Short), i32(12))
	testing.expect_value(t, chronicle_length_seasons(.Standard), i32(24))
	testing.expect_value(t, chronicle_length_seasons(.Long), i32(50))
	testing.expect_value(t, chronicle_length_seasons(.Open), i32(0))
}

@(test)
newly_founded_campaign_surfaces_an_opening_compact_call :: proc(t: ^testing.T) {
	for seed in 1 ..< 257 {
		d := civilization_setup_generate(u64(seed))
		c: Campaign
		ok, _ := civilization_setup_commit(&d, &c)
		testing.expect(t, ok)
		testing.expect(t, c.compact.call_count > 0)
		if c.compact.call_count > 0 do testing.expect(t, c.compact.calls[0].status == .Open)
		campaign_destroy(&c)
	}
}

@(test)
fixed_horizon_stops_and_can_convert_to_endless :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 5302, .Short); c.season = 11; c.year = 33
	advance_season(&c)
	testing.expect_value(t, c.season, i32(12)); testing.expect(t, c.ending_prompt_pending)
	advance_season(&c); testing.expect_value(t, c.season, i32(12))
	testing.expect(
		t,
		convert_chronicle_to_endless(&c),
	); testing.expect_value(t, c.length, Chronicle_Length.Open); testing.expect_value(t, c.max_seasons, i32(0)); testing.expect(t, !c.ending_prompt_pending)
}

@(test)
fixed_horizon_begins_a_three_season_finale_before_recording_an_ending :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 5311, .Short); c.season = 12; c.ending_prompt_pending = true
	testing.expect(t, conclude_chronicle(&c)); testing.expect(t, c.ending_finale.active)
	testing.expect_value(
		t,
		c.ending_finale.ends_season,
		i32(15),
	); testing.expect_value(t, c.max_seasons, i32(15))
	data := campaign_serialize(
		&c,
	); defer delete(data); restored: Campaign; result := campaign_deserialize(data[:], &restored); testing.expect(t, result.ok); defer campaign_destroy(&restored)
	testing.expect_value(t, restored.ending_finale, c.ending_finale)
}

@(test)
material_pressure_rounding_is_authored_and_deterministic :: proc(t: ^testing.T) {
	testing.expect_value(t, pressure_scale(10, .Gentle, true), i64(12))
	testing.expect_value(t, pressure_scale(10, .Gentle, false), i64(9))
	testing.expect_value(t, pressure_scale(10, .Standard, true), i64(10))
	testing.expect_value(t, pressure_scale(10, .Severe, true), i64(9))
	testing.expect_value(t, pressure_scale(10, .Severe, false), i64(12))
	testing.expect_value(t, maintenance_scale(4, .Gentle), i32(3))
	testing.expect_value(t, maintenance_scale(4, .Severe), i32(5))
}

@(test)
nomadic_ending_requires_sustainability_and_objectives :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		5303,
	); c.sustainable_seasons = 3; c.material_economy.fleet.maintenance_debt = 0
	c.dark_strategy_record_count = 1; c.dark_strategy_records = make([dynamic]Dark_Strategy_Statistics, 1); defer delete(c.dark_strategy_records); c.dark_strategy_records[0].objective_successes = 2
	r := ending_readiness(&c); testing.expect(t, r.eligible[int(Ending.Nomadic_Fleet)])
	c.dark_strategy_records[0].objective_successes = 0; r = ending_readiness(&c); testing.expect(t, !r.eligible[int(Ending.Nomadic_Fleet)])
}

@(test)
economy_loss_always_waits_for_a_recoverable_decision :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		5304,
	); c.consequence_severity = .Severe; c.material_economy.fleet.stock.manufactured_goods = 0; c.material_economy.fleet.stock.services = 0
	for &ship in c.ships[:c.ship_count] do ship.role = .Survey
	c.ships[0].scar = .Hull_Breach; c.economy_damage_episodes = 2; c.material_economy.fleet.maintenance_debt = economy_damage_threshold(.Severe)
	advance_fleet_metabolism(
		&c,
	); testing.expect(t, c.economy_loss_decision_pending); testing.expect(t, c.ships[0].active)
	c.material_economy.fleet.stock.equipment = 2; c.material_economy.fleet.stock.services = 2
	testing.expect(
		t,
		resolve_economy_loss_decision(&c, true),
	); testing.expect(t, c.ships[0].active); testing.expect(t, !c.economy_loss_decision_pending)
}

@(test)
economy_loss_abandonment_recovers_salvage_and_removes_future_demand :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		9902,
	); defer campaign_destroy(&c); c.economy_loss_decision_pending = true; c.economy_loss_candidate = c.ships[0].id
	raw :=
		c.material_economy.fleet.stock.raw_materials; equipment := c.material_economy.fleet.stock.equipment; active := active_ship_count(&c)
	testing.expect(
		t,
		resolve_economy_loss_decision(&c, false),
	); testing.expect_value(t, c.material_economy.fleet.stock.raw_materials, raw + 4); testing.expect_value(t, c.material_economy.fleet.stock.equipment, equipment + 2); testing.expect_value(t, active_ship_count(&c), active - 1)
}

@(test)
pressure_changes_economy_without_consuming_campaign_rng :: proc(t: ^testing.T) {
	gentle: Campaign
	campaign_init(&gentle, 5305); severe: Campaign
	campaign_init(
		&severe,
		5305,
	); gentle.material_pressure = .Gentle; severe.material_pressure = .Severe
	rng :=
		gentle.rng_sequence; advance_material_economy(&gentle); advance_material_economy(&severe)
	testing.expect_value(
		t,
		gentle.rng_sequence,
		rng,
	); testing.expect_value(t, severe.rng_sequence, rng)
	testing.expect(
		t,
		gentle.material_economy.fleet.stock.food > severe.material_economy.fleet.stock.food,
	)
	testing.expect(
		t,
		gentle.material_economy.fleet.stock.manufactured_goods >=
		severe.material_economy.fleet.stock.manufactured_goods,
	)
}

@(test)
project_previews_match_executed_effects :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 5306)
	ship := c.ships[0].id
	refit := project_preview(
		&c,
		.Refit,
		ship,
	); testing.expect_value(t, refit.outcome, "Raises ship Power by 2.")
	power :=
		c.ships[0].power; testing.expect(t, queue_project(&c, .Refit, ship)); advance_projects(&c); testing.expect_value(t, c.ships[0].power, power + 2)
	habitat := project_preview(
		&c,
		.Habitat_Expansion,
	); testing.expect_value(t, habitat.outcome, "Raises Fleet Cohesion by 5.")
	c.strategic.cohesion = 50; testing.expect(t, queue_project(&c, .Habitat_Expansion)); advance_projects(&c); testing.expect_value(t, c.strategic.cohesion, i32(55))
	analysis := project_preview(
		&c,
		.Analyze_Discovery,
	); testing.expect_value(t, analysis.outcome, "Raises deployable analysis by 12.")
	knowledge :=
		c.material_economy.knowledge.deployable_capacity; testing.expect(t, queue_project(&c, .Analyze_Discovery)); advance_projects(&c); testing.expect_value(t, c.material_economy.knowledge.deployable_capacity, knowledge + 12)
	production := project_preview(
		&c,
		.Produce_Reserves,
	); testing.expect_value(t, production.outcome, "Produces 18 Expedition Supplies.")
	supplies :=
		c.material_economy.fleet.stock.supplies; testing.expect(t, queue_project(&c, .Produce_Reserves)); advance_projects(&c); testing.expect_value(t, c.material_economy.fleet.stock.supplies, supplies + 18)
}
