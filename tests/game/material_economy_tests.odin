package game_tests

import "core:testing"

@(test)
material_economy_is_deterministic_and_retains_uncommitted_knowledge :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 4401); b: Campaign
	campaign_init(&b, 4401)
	a.material_economy.knowledge.deployable_capacity = 100; b.material_economy.knowledge.deployable_capacity = 100
	for &entry in a.material_economy.commitments do entry.active = false
	for &entry in b.material_economy.commitments do entry.active = false
	for _ in 0 ..< 30 {a.season += 1; b.season += 1; advance_material_economy(&a); advance_material_economy(&b)}
	testing.expect_value(
		t,
		a.material_economy.knowledge.deployable_capacity,
		b.material_economy.knowledge.deployable_capacity,
	)
	testing.expect_value(t, a.material_economy.fleet.stock, b.material_economy.fleet.stock)
	testing.expect_value(
		t,
		a.material_economy.agriculture.cultivation,
		b.material_economy.agriculture.cultivation,
	)
	testing.expect_value(t, a.material_economy.knowledge.deployable_capacity, i32(100))
	testing.expect(t, a.material_economy.knowledge.archival_record >= 70)
	testing.expect_value(
		t,
		a.material_economy.knowledge.total_spent_by_use[int(Knowledge_Use.Diffusion)],
		i32(0),
	)
}

@(test)
recurring_positive_knowledge_waits_for_an_explicit_program :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 4402)
	for &entry in c.material_economy.commitments do entry.active = false
	for _ in 0 ..< 30 {c.season += 1; record_knowledge_gain(&c, 9, .Seasonal_Analysis); advance_material_economy(&c)}
	testing.expect_value(t, c.material_economy.knowledge.deployable_capacity, i32(280))
	testing.expect_value(
		t,
		c.material_economy.knowledge.total_gained_by_source[int(Knowledge_Source.Seasonal_Analysis)],
		i32(270),
	)
	testing.expect_value(
		t,
		c.material_economy.knowledge.total_spent_by_use[int(Knowledge_Use.Diffusion)],
		i32(0),
	)
	testing.expect(t, start_research_program(&c, .Closed_Cycle_Agriculture, c.ships[7].id))
}

@(test)
research_converts_named_resources_and_time_into_capacity :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 8); c.material_economy.knowledge.deployable_capacity = 40
	testing.expect(
		t,
		start_research_program(&c, .Closed_Cycle_Agriculture, c.ships[7].id),
	); before := c.material_economy.agriculture.nutrient_closure
	for _ in 0 ..< 4 do advance_research(&c)
	testing.expect(t, c.material_economy.capabilities[int(Research_Kind.Closed_Cycle_Agriculture)])
	testing.expect(t, c.material_economy.agriculture.nutrient_closure > before)
	testing.expect(
		t,
		c.material_economy.knowledge.total_spent_by_use[int(Knowledge_Use.Research)] == 16,
	)
}

@(test)
last_agriculture_loss_surfaces_multiple_recoverable_responses :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		91,
	); ag := ship_index(&c, 8); c.ships[ag].active = false; c.ships[ag].departure = .Lost
	detect_essential_exposure(&c); e := c.material_economy.essential[int(Role.Agriculture)]
	testing.expect(
		t,
		e.exposed,
	); testing.expect(t, e.response_count >= 2); testing.expect_value(t, e.lost_ship, Ship_ID(8))
	before := c.material_economy.agriculture.import_dependence
	testing.expect(t, resolve_essential_exposure(&c, .Agriculture, .Import_Service))
	testing.expect(t, c.material_economy.agriculture.import_dependence > before)
	other: Campaign
	campaign_init(
		&other,
		91,
	); other.ships[ag].active = false; detect_essential_exposure(&other); successor := other.ships[0].id
	_ = add_obligation(
		&other,
		.Fleet_Maintenance,
		"Agriculture service debt",
		1,
		1,
		1,
		0,
		1,
		ship = other.ships[ag].id,
		cause = other.material_economy.essential[int(Role.Agriculture)].origin_event,
	)
	lost_community := other.ships[ag].community
	testing.expect(
		t,
		resolve_essential_exposure(&other, .Agriculture, .Refit_Ship, successor),
	); testing.expect_value(t, other.ships[0].role, Role.Agriculture); testing.expect(t, other.ships[0].history_record_count > 0)
	testing.expect_value(
		t,
		other.ships[0].community,
		lost_community,
	); testing.expect_value(t, other.obligations.items[0].ship, successor)
	testing.expect_value(
		t,
		other.transformations.records[other.transformations.record_count - 1].predecessor,
		Ship_ID(8),
	)
}

@(test)
restoring_the_original_ship_closes_its_essential_exposure :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 92); ag := ship_index(&c, 8); c.ships[ag].damage = c.ships[ag].power
	detect_essential_exposure(
		&c,
	); testing.expect(t, c.material_economy.essential[int(Role.Agriculture)].exposed)
	c.ships[ag].damage = 0; detect_essential_exposure(&c)
	e := c.material_economy.essential[int(Role.Agriculture)]
	testing.expect(
		t,
		!e.exposed && e.acknowledged,
	); testing.expect_value(t, e.chosen, Capability_Response.Restored_Ship)
	testing.expect(t, c.ships[ag].history_record_count > 0)
}

@(test)
food_ledger_reserves_and_consent_aware_migration_are_persistent :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 22); advance_material_economy(&c); a := c.material_economy.agriculture
	testing.expect(
		t,
		a.last_production > 0,
	); testing.expect(t, a.last_consumption > 0); testing.expect(t, a.forecast_high >= a.forecast_low)
	c.settlement_count = 1; c.settlements[0] = {
		id         = 1,
		name       = "Test Harbor",
		population = 1000,
		viability  = 50,
		active     = true,
	}; before := c.communities[1].population
	testing.expect(
		t,
		plan_population_migration(&c, 2, 1, 500),
	); testing.expect_value(t, c.communities[1].population, before - 500); testing.expect(t, !plan_population_migration(&c, 1, 1, 500))
}

@(test)
food_security_uses_production_or_a_three_season_buffer_not_prompt_timing :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 17022); m := &c.material_economy
	m.agriculture.last_consumption = 5; m.agriculture.last_production = 3; m.agriculture.last_imports = 0
	m.fleet.stock.food = 15; m.food_shortage_response_pending = true
	testing.expect(t, fleet_food_secure(m))
	m.fleet.stock.food = 14; testing.expect(t, !fleet_food_secure(m))
	m.agriculture.last_imports = 2; testing.expect(t, fleet_food_secure(m))
}

@(test)
food_front_transformations_change_material_stocks :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		37,
	); before := c.material_economy.agriculture.nutrient_closure; apply_front_material_change(&c, .Closed_Cycle_Ecology, .Revised_Doctrine)
	testing.expect(t, c.material_economy.agriculture.nutrient_closure > before)
	apply_front_material_change(
		&c,
		.Passage_Access,
		.Constrained_Route,
	); testing.expect(t, c.material_economy.agriculture.import_dependence > 0)
	apply_front_material_change(
		&c,
		.Fleet_Authority,
		.Changed_Authority,
	); testing.expect_value(t, c.material_economy.allocation_control, Authority_Policy.Central_Command)
	c.settlement_count = 1; c.settlements[0] = {
		id     = 1,
		name   = "Material Harbor",
		active = true,
	}; cultivation := c.material_economy.agriculture.cultivation
	apply_front_material_change(
		&c,
		.Settlement_Obligation,
		.Broadened_Constituency,
	); testing.expect_value(t, c.material_economy.production_owner, Settlement_ID(1)); testing.expect(t, c.material_economy.agriculture.cultivation > cultivation)
}

@(test)
knowledge_sources_and_uses_are_precisely_inventoried :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		73,
	); record_knowledge_gain(&c, 2, .Intel); record_knowledge_gain(&c, 3, .Cargo); record_knowledge_gain(&c, 4, .Settlement_Report)
	testing.expect(
		t,
		spend_knowledge(&c, 1, .Emergency),
	); testing.expect(t, spend_knowledge(&c, 2, .Front_Transformation))
	testing.expect_value(
		t,
		c.material_economy.knowledge.total_gained_by_source[int(Knowledge_Source.Intel)],
		i32(2),
	)
	testing.expect_value(
		t,
		c.material_economy.knowledge.total_gained_by_source[int(Knowledge_Source.Cargo)],
		i32(3),
	)
	testing.expect_value(
		t,
		c.material_economy.knowledge.total_gained_by_source[int(Knowledge_Source.Settlement_Report)],
		i32(4),
	)
	testing.expect_value(
		t,
		c.material_economy.knowledge.total_spent_by_use[int(Knowledge_Use.Front_Transformation)],
		i32(2),
	)
}

@(test)
essential_replacement_reserves_training_before_other_projects :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		74,
	); at := ship_index(&c, 8); c.ships[at].active = false; c.ships[at].departure = .Lost
	testing.expect(
		t,
		reserve_essential_replacement(&c),
	); p := c.material_economy.research[int(Research_Kind.Ship_Role_Training)]
	testing.expect(
		t,
		p.active,
	); testing.expect(t, c.capacities.manpower.reserved >= p.manpower); testing.expect(t, p.ship != 0)
}

@(test)
repeated_food_shortage_requires_a_legal_persistent_command :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1701,
	); c.material_economy.fleet.stock.food = 0; c.material_economy.agriculture.damage = 100
	advance_material_economy(&c); advance_material_economy(&c)
	testing.expect(t, c.material_economy.food_shortage_response_pending)
	testing.expect(t, !apply_food_shortage_command(&c, .Import_Route))
	before :=
		c.material_economy.agriculture.cultivation; goods := c.material_economy.fleet.stock.manufactured_goods
	testing.expect(
		t,
		apply_food_shortage_command(&c, .Invest_Capacity),
	); testing.expect(t, c.material_economy.agriculture.cultivation > before); testing.expect_value(t, c.material_economy.fleet.stock.manufactured_goods, goods - 8); testing.expect(t, !c.material_economy.food_shortage_response_pending)
}

@(test)
food_shortage_policy_persists_in_later_seasons :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1702,
	); c.material_economy.food_shortage_response_pending = true; c.strategic.cohesion = 10
	testing.expect(
		t,
		apply_food_shortage_command(&c, .Change_Diet),
	); before := c.material_economy.diet_savings; advance_material_economy(&c)
	testing.expect_value(
		t,
		c.material_economy.diet_savings,
		before,
	); testing.expect_value(t, c.material_economy.population_policy, Population_Policy.Rationed); testing.expect_value(t, c.strategic.cohesion, i32(8))
}

@(test)
food_shortage_rejects_capped_diet_and_contraction_without_consent :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		17021,
	); c.material_economy.food_shortage_response_pending = true; c.material_economy.diet_savings = 4
	for &group in c.communities[:c.community_count] do group.consents_to_settle = false
	testing.expect(
		t,
		!food_shortage_command_legal(&c, .Change_Diet),
	); testing.expect(t, !food_shortage_command_legal(&c, .Contract_Habitat))
	testing.expect(
		t,
		!apply_food_shortage_command(&c, .Change_Diet),
	); testing.expect(t, c.material_economy.food_shortage_response_pending)
}

@(test)
planned_contraction_names_each_consenting_community_and_rate :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1703,
	); c.material_economy.food_shortage_response_pending = true; c.material_economy.food_shortage_episode.origin_event = c.event_sequence
	before :=
		c.event_count; testing.expect(t, apply_food_shortage_command(&c, .Contract_Habitat)); testing.expect_value(t, c.material_economy.population_policy, Population_Policy.Planned_Contraction)
	recorded := 0; for event in c.events[before:c.event_count] do if event.kind == .Community_Memory_Changed && event.value < 0 do recorded += 1
	consenting := 0; for group in c.communities[:c.community_count] do if group.consents_to_settle do consenting += 1
	testing.expect_value(t, recorded, consenting)
}

@(test)
food_shortage_episode_blocks_time_and_records_a_causal_response :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1703,
	); c.material_economy.fleet.stock.food = 0; c.material_economy.agriculture.damage = 100
	advance_material_economy(&c); advance_material_economy(&c)
	episode := c.material_economy.food_shortage_episode
	testing.expect(t, episode.active && episode.id == 1 && episode.origin_event > 0)
	before := c.season; advance_season(&c); testing.expect_value(t, c.season, before)
	c.strategic.cohesion = 3
	r := execute_command(
		&c,
		{kind = .Resolve_Food_Shortage, target = int(Food_Shortage_Command.Ration)},
	)
	testing.expect(
		t,
		r.ok,
	); testing.expect_value(t, c.strategic.cohesion, i32(0)); testing.expect(t, !c.material_economy.food_shortage_episode.active)
	testing.expect(
		t,
		c.material_economy.food_shortage_episode.resolution_event > episode.origin_event,
	)
	advance_season(&c); testing.expect_value(t, c.season, before + 1)
}

@(test)
food_shortage_can_recur_when_the_first_structural_response_is_insufficient :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		1704,
	); c.material_economy.fleet.stock.food = 0; c.material_economy.agriculture.damage = 100
	advance_material_economy(
		&c,
	); advance_material_economy(&c); testing.expect(t, apply_food_shortage_command(&c, .Ration))
	first := c.material_economy.food_shortage_episode.id
	for _ in 0 ..< 3 {c.season += 1; c.material_economy.fleet.stock.food = 0; advance_material_economy(&c)}
	testing.expect(t, c.material_economy.food_shortage_response_pending)
	testing.expect(t, c.material_economy.food_shortage_episode.id > first)
	testing.expect_value(t, c.material_economy.food_shortage_episode.recurrence, i32(1))
}

@(test)
playable_food_responses_change_distinct_future_flows :: proc(t: ^testing.T) {
	invest: Campaign
	campaign_init(
		&invest,
		1705,
	); invest.material_economy.food_shortage_response_pending = true; before_cultivation := invest.material_economy.agriculture.cultivation
	testing.expect(
		t,
		apply_food_shortage_command(&invest, .Invest_Capacity),
	); testing.expect(t, invest.material_economy.agriculture.cultivation > before_cultivation)
	imports: Campaign
	campaign_init(
		&imports,
		1706,
	); imports.material_economy.food_shortage_response_pending = true; imports.settlement_count = 1; imports.settlements[0] = {
		id         = 1,
		name       = "Provision Harbor",
		population = 1000,
		viability  = 70,
		active     = true,
	}; sync_campaign_settlement_economies(
		&imports,
	); imports.settlement_economies.economies[0].stock.food = 100
	testing.expect(
		t,
		apply_food_shortage_command(&imports, .Import_Route),
	); advance_material_economy(&imports); testing.expect(t, imports.material_economy.agriculture.last_imports > 0)
}
