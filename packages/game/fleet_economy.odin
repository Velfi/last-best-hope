package game

import "core:fmt"

Fleet_Stock :: struct {
	food, raw_materials, manufactured_goods, equipment, propellant, supplies, services: i64,
}
Fleet_Flow_Ledger :: struct {
	produced, consumed, imported, exported, lost: Fleet_Stock,
}
Fleet_Spending_Mode :: enum {
	Routine,
	Committed,
	Emergency,
}
Fleet_Transaction_Kind :: enum {
	Production,
	Consumption,
	Commitment,
	Recovery,
	Reward,
	Loss,
}
Fleet_Operating_Floor :: struct {
	stock:     Fleet_Stock,
	principal: string,
}
Fleet_Spend_Forecast :: struct {
	allowed:          bool,
	first, second:    string,
	recovery_seasons: i32,
}
Fleet_Transaction :: struct {
	kind:   Fleet_Transaction_Kind,
	amount: Fleet_Stock,
	cause:  u64,
}
Fleet_Trade_Link :: struct {
	active:                         bool,
	supplier:                       Settlement_ID,
	route:                          u32,
	route_name:                     string,
	food_requested, food_delivered: i64,
	reliability:                    i32,
	origin_event, last_event:       u64,
}
Fleet_Economy :: struct {
	stock:                                                               Fleet_Stock,
	season:                                                              Fleet_Flow_Ledger,
	total:                                                               Fleet_Flow_Ledger,
	skilled_labor, assigned_labor, maintenance_demand, maintenance_debt: i32,
	trade:                                                               Fleet_Trade_Link,
	committed, recovered, rewarded:                                      Fleet_Stock,
	transactions:                                                        [256]Fleet_Transaction,
	transaction_count:                                                   i32,
	seasons_below_floor:                                                 [7]i32,
}

fleet_stock_add :: proc(a: ^Fleet_Stock, b: Fleet_Stock) {a.food += b.food; a.raw_materials +=
		b.raw_materials
	a.manufactured_goods += b.manufactured_goods
	a.equipment += b.equipment
	a.propellant += b.propellant
	a.supplies += b.supplies
	a.services += b.services}
fleet_stock_can_spend :: proc(a: Fleet_Stock, b: Fleet_Stock) -> bool {return(
		a.food >= b.food &&
		a.raw_materials >= b.raw_materials &&
		a.manufactured_goods >= b.manufactured_goods &&
		a.equipment >= b.equipment &&
		a.propellant >= b.propellant &&
		a.supplies >= b.supplies &&
		a.services >= b.services \
	)}
fleet_stock_sub :: proc(a: Fleet_Stock, b: Fleet_Stock) -> Fleet_Stock {return{
		food = a.food - b.food,
		raw_materials = a.raw_materials - b.raw_materials,
		manufactured_goods = a.manufactured_goods - b.manufactured_goods,
		equipment = a.equipment - b.equipment,
		propellant = a.propellant - b.propellant,
		supplies = a.supplies - b.supplies,
		services = a.services - b.services,
	}}
fleet_stock_min_zero :: proc(a: Fleet_Stock) -> Fleet_Stock {return{
		food = max(a.food, 0),
		raw_materials = max(a.raw_materials, 0),
		manufactured_goods = max(a.manufactured_goods, 0),
		equipment = max(a.equipment, 0),
		propellant = max(a.propellant, 0),
		supplies = max(a.supplies, 0),
		services = max(a.services, 0),
	}}
fleet_supply :: proc(c: ^Campaign) -> i32 {return i32(c.material_economy.fleet.stock.supplies)}
fleet_materials :: proc(c: ^Campaign) -> i32 {return i32(
		c.material_economy.fleet.stock.manufactured_goods,
	)}
fleet_propellant :: proc(c: ^Campaign) -> i32 {
	return i32(fleet_propellant_remaining(c) + .5)
}
fleet_record_transaction :: proc(
	c: ^Campaign,
	kind: Fleet_Transaction_Kind,
	amount: Fleet_Stock,
	cause: u64 = 0,
) {e := &c.material_economy.fleet; if e.transaction_count < len(e.transactions) {e.transactions[e.transaction_count] =
			{
				kind   = kind,
				amount = amount,
				cause  = cause,
			}
		e.transaction_count += 1}}
fleet_operating_floor :: proc(
	c: ^Campaign,
) -> Fleet_Operating_Floor {e := &c.material_economy.fleet; maintenance := i64(
		max(e.maintenance_demand, 1) * 2,
	)
	propellant := i64(6)
	if c.passage.active do propellant += c.passage.manifest.allocated.propellant - c.passage.manifest.consumed.propellant
	return{
		stock = {
			food = i64(max(c.material_economy.agriculture.reserve_floor, 0)),
			manufactured_goods = maintenance,
			propellant = propellant,
			supplies = 12,
			services = maintenance,
		},
		principal = "fleet operating floor",
	}}
fleet_stock_spend_preview :: proc(
	c: ^Campaign,
	cost: Fleet_Stock,
	mode: Fleet_Spending_Mode = .Routine,
) -> (
	bool,
	Fleet_Stock,
	string,
) {after := fleet_stock_sub(c.material_economy.fleet.stock, cost); if !fleet_stock_can_spend(c.material_economy.fleet.stock, cost) do return false, after, "insufficient stock"
	if mode == .Emergency do return true, after, "emergency authority exposes an operating floor"
	floor := fleet_operating_floor(c).stock
	if !fleet_stock_can_spend(after, floor) do return false, after, "commitment would cross a protected operating floor"
	return true, after, ""}
fleet_spend_forecast :: proc(
	c: ^Campaign,
	cost: Fleet_Stock,
	mode: Fleet_Spending_Mode = .Routine,
) -> Fleet_Spend_Forecast {ok, after, _ := fleet_stock_spend_preview(c, cost, mode); floor :=
		fleet_operating_floor(c).stock
	r := Fleet_Spend_Forecast {
		allowed = ok,
	}
	values := [7]i64 {
		after.food,
		after.raw_materials,
		after.manufactured_goods,
		after.equipment,
		after.propellant,
		after.supplies,
		after.services,
	}
	floors := [7]i64 {
		floor.food,
		floor.raw_materials,
		floor.manufactured_goods,
		floor.equipment,
		floor.propellant,
		floor.supplies,
		floor.services,
	}
	names := [7]string {
		"Food",
		"Raw Materials",
		"Manufactured Goods",
		"Equipment",
		"Propellant",
		"Supplies",
		"Services",
	}
	first_at, second_at := 0, 1
	first_margin, second_margin := values[0] - floors[0], values[1] - floors[1]
	if second_margin < first_margin {first_at, second_at = second_at, first_at
		first_margin, second_margin = second_margin, first_margin}
	for i := 2; i < len(values); i += 1 {margin := values[i] - floors[i]; if margin <
		   first_margin {second_at, second_margin = first_at, first_margin
			first_at, first_margin = i, margin}
		else if margin < second_margin {second_at, second_margin = i, margin}}
	r.first = fmt.tprintf("%s margin %+d", names[first_at], first_margin)
	r.second = fmt.tprintf("%s margin %+d", names[second_at], second_margin)
	if first_margin < 0 do r.recovery_seasons = i32(-first_margin)
	return r}
fleet_stock_spend :: proc(
	c: ^Campaign,
	cost: Fleet_Stock,
	mode: Fleet_Spending_Mode = .Routine,
	cause: u64 = 0,
) -> bool {e := &c.material_economy.fleet; ok, _, _ := fleet_stock_spend_preview(c, cost, mode)
	if !ok do return false
	if cost.propellant > 0 && !fleet_propellant_consume(c, f64(cost.propellant)) do return false
	negative := Fleet_Stock {
		food               = -cost.food,
		raw_materials      = -cost.raw_materials,
		manufactured_goods = -cost.manufactured_goods,
		equipment          = -cost.equipment,
		propellant          = 0,
		supplies           = -cost.supplies,
		services           = -cost.services,
	}
	fleet_stock_add(&e.stock, negative)
	fleet_stock_add(&e.season.consumed, cost)
	fleet_stock_add(&e.total.consumed, cost)
	fleet_record_transaction(c, .Consumption, cost, cause)
	fleet_propellant_sync_ledger(c)
	return true}
fleet_stock_gain :: proc(
	c: ^Campaign,
	gain: Fleet_Stock,
	kind: Fleet_Transaction_Kind = .Production,
	cause: u64 = 0,
) {
	e := &c.material_economy.fleet
	if gain.propellant > 0 do _ = fleet_propellant_gain(c, f64(gain.propellant))
	ledger_gain := gain
	ledger_gain.propellant = 0
	fleet_stock_add(&e.stock, ledger_gain)
	fleet_stock_add(
		&e.season.produced,
		gain,
	)
	fleet_stock_add(&e.total.produced, gain)
	if kind == .Recovery do fleet_stock_add(&e.recovered, gain)
	if kind == .Reward do fleet_stock_add(&e.rewarded, gain)
	fleet_record_transaction(c, kind, gain, cause)
	fleet_propellant_sync_ledger(c)
}
fleet_stock_transfer :: proc(
	c: ^Campaign,
	amount: Fleet_Stock,
	cause: u64 = 0,
) -> bool {if !fleet_stock_spend(c, amount, .Committed, cause) do return false; fleet_stock_add(
		&c.material_economy.fleet.committed,
		amount,
	)
	fleet_record_transaction(c, .Commitment, amount, cause)
	return true}

initialize_fleet_economy :: proc(c: ^Campaign) {e := &c.material_economy.fleet; e.stock = {
		food               = 80,
		raw_materials      = 36,
		manufactured_goods = 32,
		equipment          = 20,
		propellant               = 24,
		supplies           = 135,
		services           = 24,
	}}

fleet_project_cost :: proc(kind: Project_Kind) -> Fleet_Stock {switch kind {case .Repair:
		return {manufactured_goods = 6, equipment = 2}; case .Refit:
		return {manufactured_goods = 10, equipment = 4, services = 2}; case .Habitat_Expansion:
		return {manufactured_goods = 12, equipment = 4, services = 2}; case .Analyze_Discovery:
		return {supplies = 2, services = 4}; case .Colony_Package:
		return {manufactured_goods = 10, equipment = 5, supplies = 5}; case .Restore_Archive:
		return {equipment = 4, supplies = 3, services = 4}; case .Produce_Reserves:
		return {raw_materials = 8, services = 2}; case .Maintenance_Recovery:
		return {raw_materials = 6, services = 3}; case .None:
		return {}}; return {}}

fleet_stock_label :: proc(stock: Fleet_Stock) -> string {
	return fmt.tprintf(
		"FOOD %d · RAW %d · GOODS %d · EQUIP %d · PROPELLANT %d · SUPPLIES %d · SERVICES %d",
		stock.food,
		stock.raw_materials,
		stock.manufactured_goods,
		stock.equipment,
		stock.propellant,
		stock.supplies,
		stock.services,
	)
}

pressure_scale :: proc(value: i64, pressure: Material_Pressure, production: bool) -> i64 {
	numerator, denominator := i64(100), i64(100)
	switch pressure {case .Gentle:
		if production {numerator = 115} else {numerator = 85}; case .Severe:
		if production {numerator = 90} else {numerator = 120}; case .Standard:}
	return (max(value, 0) * numerator + denominator / 2) / denominator
}

maintenance_scale :: proc(value: i32, pressure: Material_Pressure) -> i32 {
	if pressure == .Gentle do return i32((i64(value) * 85 + 50) / 100)
	if pressure == .Severe do return i32((i64(value) * 125 + 50) / 100)
	return value
}

economy_damage_threshold :: proc(severity: Consequence_Severity) -> i32 {switch
	severity {case .Gentle:
		return 7; case .Standard:
		return 5; case .Severe:
		return 2}
	return 5}
economy_scar_episode_threshold :: proc(severity: Consequence_Severity) -> i32 {switch
	severity {case .Gentle:
		return 4; case .Standard:
		return 3; case .Severe:
		return 2}
	return 3}

establish_fleet_food_import :: proc(c: ^Campaign) -> bool {if c.settlement_count <= 0 do return false
	for s in c.settlements[:c.settlement_count] do if s.active {t := &c.material_economy.fleet.trade; t.active = true; t.supplier = s.id; t.route = u32(s.id) * 7919 + 1; t.route_name = fmt.tprintf("%s fleet supply route", s.name); t.food_requested = 4; t.reliability = 85; t.origin_event = c.material_economy.food_shortage_episode.origin_event; return true}
	return false}
fleet_food_import_available :: proc(c: ^Campaign) -> bool {for s in c.settlements[:c.settlement_count] do if s.active do return true
	return false}

settle_fleet_food_import :: proc(c: ^Campaign) -> i32 {t := &c.material_economy.fleet.trade
	if !t.active || t.reliability <= 0 do return 0
	i := settlement_economy_index(&c.settlement_economies, t.supplier)
	if i < 0 do return 0
	e := &c.settlement_economies.economies[i]
	reserve := max(e.population / 100, 1)
	shipped := min(max(e.stock.food - reserve, 0), t.food_requested)
	reliability :=
		t.reliability +
		(c.material_pressure == .Gentle ? 10 : c.material_pressure == .Severe ? -10 : 0)
	reliability = clamp(reliability, 0, 100)
	delivered := shipped * i64(reliability) / 100
	e.stock.food -= shipped
	e.exports.food += shipped
	e.route_losses.food += shipped - delivered
	t.food_delivered = delivered
	gain := Fleet_Stock {
		food = delivered,
	}
	fleet_stock_add(&c.material_economy.fleet.stock, gain)
	fleet_stock_add(&c.material_economy.fleet.season.imported, gain)
	fleet_stock_add(&c.material_economy.fleet.total.imported, gain)
	if delivered > 0 && t.last_event == 0 {record_event(
			c,
			.Resource_Changed,
			fmt.tprintf("%s delivered %d food to the traveling fleet.", t.route_name, delivered),
			settlement_id = t.supplier,
			cause_sequence = t.origin_event,
			value = i32(delivered),
		)
		t.last_event = c.event_sequence}
	return i32(delivered)}

resolve_economy_loss_decision :: proc(c: ^Campaign, preserve: bool) -> bool {
	if !c.economy_loss_decision_pending do return false
	i := ship_index(
		c,
		c.economy_loss_candidate,
	); if i < 0 {c.economy_loss_decision_pending = false; c.economy_loss_candidate = 0; return false}
	ship := &c.ships[i]
	if preserve {
		if !fleet_stock_spend(c, {equipment = 2, services = 2}, .Emergency) do return false
		ship.damage = max(
			ship.damage - 1,
			0,
		); record_event(c, .Ship_Repaired, fmt.tprintf("The fleet diverted equipment and services to preserve %s after repeated maintenance failure.", ship.name), ship.id, 1)
	} else {
		// Abandonment is a severe but sometimes rational contraction: emergency
		// crews recover portable equipment before the hull leaves service.
		fleet_stock_gain(c, {raw_materials = 4, equipment = 2})
		ship.active =
			false; ship.departure = .Lost; record_event(c, .Ship_Lost, fmt.tprintf("%s was abandoned after its unresolved maintenance exposure became unrecoverable; emergency crews recovered 4 Raw Materials and 2 Equipment.", ship.name), ship.id)
	}
	c.economy_loss_decision_pending = false; c.economy_loss_candidate = 0; return true
}

advance_fleet_metabolism :: proc(c: ^Campaign) {
	e := &c.material_economy.fleet; e.season = {}
	population := total_population(
		c,
	); active := active_ship_count(c); e.skilled_labor = max(population / 6500, 1); foundries, hospitals: i32
	for ship in c.ships[:c.ship_count] do if ship.active && !ship.committed {if ship.role == .Foundry do foundries += 1; if ship.role == .Hospital || ship.role == .Archive do hospitals += 1}
	e.assigned_labor = min(
		e.skilled_labor,
		foundries * 2 + hospitals,
	); operated_foundries := min(foundries, e.assigned_labor / 2); service_crews := min(hospitals, max(e.assigned_labor - operated_foundries * 2, 0)); raw := pressure_scale(i64(operated_foundries * 4), c.material_pressure, true); goods := pressure_scale(min(e.stock.raw_materials + raw, i64(operated_foundries * 3)), c.material_pressure, true); services := pressure_scale(i64(service_crews * 2), c.material_pressure, true)
	e.stock.raw_materials +=
		raw -
		goods; e.stock.manufactured_goods += goods; e.stock.services += services; production := Fleet_Stock {
		raw_materials      = raw,
		manufactured_goods = goods,
		services           = services,
	}; fleet_stock_add(
		&e.season.produced,
		production,
	); fleet_stock_add(&e.total.produced, production)
	e.maintenance_demand = max(
		maintenance_scale(max(i32(active + 2) / 3, 1), c.material_pressure),
		1,
	)
	// Available crews and goods first cover this season, then any arrears. Debt
	// must remain recoverable through later preparation; otherwise one early
	// shortage permanently disqualifies every sustainability ending.
	// Cap arrears service at one additional season of maintenance. Recovery is
	// deliberate but does not consume the fleet's entire industrial stock in a
	// single automatic payment and erase other strategic choices.
	arrears_payment := min(e.maintenance_debt, e.maintenance_demand)
	maintenance_due := i64(e.maintenance_demand + arrears_payment)
	paid := min(maintenance_due, min(e.stock.manufactured_goods, e.stock.services))
	e.stock.manufactured_goods -= paid; e.stock.services -= paid
	maintenance := Fleet_Stock {
		manufactured_goods = paid,
		services           = paid,
	}; fleet_stock_add(
		&e.season.consumed,
		maintenance,
	); fleet_stock_add(&e.total.consumed, maintenance)
	e.maintenance_debt = max(e.maintenance_debt + e.maintenance_demand - i32(paid), 0)
	threshold := economy_damage_threshold(c.consequence_severity)
	if e.maintenance_debt >= threshold &&
	   !c.economy_loss_decision_pending {for &ship in c.ships[:c.ship_count] do if ship.active && !ship.committed {ship.damage += 1; c.economy_damage_episodes += 1; record_event(c, .Ship_Damaged, fmt.tprintf("%s accumulated damage after fleet maintenance went unfunded.", ship.name), ship.id, 1); e.maintenance_debt -= threshold; if c.economy_damage_episodes >= economy_scar_episode_threshold(c.consequence_severity) && ship.scar == .None {ship.scar = .Hull_Breach; record_event(c, .Ship_Scarred, fmt.tprintf("Repeated maintenance failures left a permanent hull breach aboard %s.", ship.name), ship.id)} else if ship.scar != .None {c.economy_loss_decision_pending = true; c.economy_loss_candidate = ship.id; record_event(c, .Need_Surfaced, fmt.tprintf("%s requires an emergency preservation commitment or must be abandoned.", ship.name), ship.id)}; break}}
	floor :=
		fleet_operating_floor(c).stock; values := [7]i64{e.stock.food, e.stock.raw_materials, e.stock.manufactured_goods, e.stock.equipment, e.stock.propellant, e.stock.supplies, e.stock.services}; floors := [7]i64{floor.food, floor.raw_materials, floor.manufactured_goods, floor.equipment, floor.propellant, floor.supplies, floor.services}; for value, i in values do if value < floors[i] do e.seasons_below_floor[i] += 1
}
