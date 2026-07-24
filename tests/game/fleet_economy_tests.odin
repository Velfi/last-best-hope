package game_tests

import "core:testing"

@(test)
operating_floors_block_routine_spending_and_allow_explicit_emergency :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		2110,
	); floor := fleet_operating_floor(&c).stock; c.material_economy.fleet.stock.supplies = floor.supplies + 2
	before := fleet_supply(
		&c,
	); testing.expect(t, !fleet_stock_spend(&c, {supplies = 3}, .Routine)); testing.expect_value(t, fleet_supply(&c), before)
	testing.expect(
		t,
		fleet_stock_spend(&c, {supplies = 3}, .Emergency),
	); testing.expect_value(t, fleet_supply(&c), before - 3)
}

@(test)
maintenance_recovery_consumes_materials_without_repairing_damage :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		2111,
	); c.material_economy.fleet.maintenance_debt = 4; c.ships[0].damage = 3; raw := c.material_economy.fleet.stock.raw_materials; services := c.material_economy.fleet.stock.services
	testing.expect(t, queue_project(&c, .Maintenance_Recovery)); advance_projects(&c)
	testing.expect_value(
		t,
		c.material_economy.fleet.maintenance_debt,
		i32(2),
	); testing.expect_value(t, c.ships[0].damage, i32(3)); testing.expect_value(t, c.material_economy.fleet.stock.raw_materials, raw - 6); testing.expect_value(t, c.material_economy.fleet.stock.services, services - 3)
}

@(test)
maintenance_surplus_repays_prior_debt_before_more_damage :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 1699)
	e := &c.material_economy.fleet
	e.maintenance_debt = 5
	e.stock.manufactured_goods = 20; e.stock.services = 20
	advance_fleet_metabolism(&c)
	first_demand := e.maintenance_demand
	testing.expect_value(t, e.maintenance_debt, max(5 - first_demand, 0))
	testing.expect_value(
		t,
		e.season.consumed.manufactured_goods,
		i64(first_demand + min(5, first_demand)),
	)
	testing.expect_value(t, e.season.consumed.services, i64(first_demand + min(5, first_demand)))
	advance_fleet_metabolism(&c)
	testing.expect_value(t, e.maintenance_debt, i32(0))
}

@(test)
food_metabolism_does_not_create_industrial_or_expedition_supplies :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		2101,
	); supplies := c.material_economy.fleet.stock.supplies; goods := c.material_economy.fleet.stock.manufactured_goods
	advance_material_economy(&c)
	testing.expect_value(t, c.material_economy.fleet.stock.supplies, supplies)
	// Goods may be produced and maintained, but their ledger must explain the delta.
	e :=
		c.material_economy.fleet; testing.expect_value(t, e.stock.manufactured_goods, goods + e.season.produced.manufactured_goods - e.season.consumed.manufactured_goods)
}

@(test)
projects_research_and_successors_consume_named_fleet_stocks :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		2102,
	); goods := c.material_economy.fleet.stock.manufactured_goods; equipment := c.material_economy.fleet.stock.equipment
	c.ships[0].damage = 3; testing.expect(t, queue_project(&c, .Repair, c.ships[0].id)); testing.expect(t, c.material_economy.fleet.stock.manufactured_goods < goods); testing.expect(t, c.material_economy.fleet.stock.equipment < equipment)
	before :=
		c.material_economy.fleet.stock.manufactured_goods; testing.expect(t, start_research_program(&c, .Closed_Cycle_Agriculture, c.ships[7].id)); advance_research(&c); testing.expect(t, c.material_economy.fleet.stock.manufactured_goods < before)
}

@(test)
settlement_to_fleet_food_trade_is_conserved_and_route_named :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 2103); c.settlement_count = 1; c.settlements[0] = {
		id         = 1,
		name       = "Provision Harbor",
		population = 1000,
		viability  = 70,
		active     = true,
	}; sync_campaign_settlement_economies(
		&c,
	); e := &c.settlement_economies.economies[0]; e.stock.food = 100; c.material_economy.food_shortage_response_pending = true
	testing.expect(
		t,
		apply_food_shortage_command(&c, .Import_Route),
	); before_settlement := e.stock.food; before_losses := e.route_losses.food; before_fleet := c.material_economy.fleet.stock.food; delivered := settle_fleet_food_import(&c); lost := e.route_losses.food - before_losses
	testing.expect(
		t,
		delivered > 0,
	); testing.expect(t, c.material_economy.fleet.trade.route_name != ""); testing.expect_value(t, before_settlement - e.stock.food, i64(delivered) + lost); testing.expect_value(t, c.material_economy.fleet.stock.food - before_fleet, i64(delivered))
}

@(test)
unfunded_maintenance_creates_specific_ship_damage :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(
		&c,
		2104,
	); c.material_economy.fleet.stock.manufactured_goods = 0; c.material_economy.fleet.stock.services = 0; before := c.ships[0].damage
	for &ship in c.ships[:c.ship_count] do ship.role = .Survey
	for _ in 0 ..< 3 do advance_fleet_metabolism(&c)
	testing.expect(
		t,
		c.ships[0].damage > before,
	); testing.expect(t, c.material_economy.fleet.maintenance_debt >= 0)
}

@(test)
fleet_economy_is_deterministic_and_persistent :: proc(t: ^testing.T) {
	a: Campaign
	campaign_init(&a, 2105); b: Campaign
	campaign_init(
		&b,
		2105,
	); for _ in 0 ..< 12 {advance_material_economy(&a); advance_material_economy(&b)}; testing.expect_value(t, a.material_economy.fleet, b.material_economy.fleet)
	data := campaign_serialize(
		&a,
	); defer delete(data); restored: Campaign; defer campaign_destroy(&restored); result := campaign_deserialize(data[:], &restored); testing.expect(t, result.ok); testing.expect_value(t, restored.material_economy.fleet, a.material_economy.fleet)
}
