package game

import "core:fmt"
record_knowledge_gain :: proc(c: ^Campaign, amount: i32, source: Knowledge_Source) {
	if amount <= 0 do return
	k := &c.material_economy.knowledge; k.deployable_capacity += amount; k.total_gained_by_source[int(source)] += amount
	if k.ledger_count < MAX_KNOWLEDGE_LEDGER {k.ledger[k.ledger_count] = {
			season = c.season,
			amount = amount,
			source = source,
			gained = true,
		}; k.ledger_count += 1}
}

spend_knowledge :: proc(c: ^Campaign, amount: i32, use: Knowledge_Use) -> bool {
	if amount <= 0 || c.material_economy.knowledge.deployable_capacity < amount do return false
	k := &c.material_economy.knowledge; k.deployable_capacity -= amount; k.total_spent_by_use[int(use)] += amount
	if k.ledger_count < MAX_KNOWLEDGE_LEDGER {k.ledger[k.ledger_count] = {
			season = c.season,
			amount = amount,
			use    = use,
		}; k.ledger_count += 1}
	return true
}

research_terms :: proc(kind: Research_Kind) -> (i32, i32, i32, i32, string) {
	switch kind {
	case .Closed_Cycle_Agriculture:
		return 4, 2, 2, 4, "Raises nutrient closure, reserves, and recurring food output."
	case .Ecological_Adaptation:
		return 3, 1, 2, 3, "Raises crop diversity and reduces ecological damage."
	case .Ship_Role_Training:
		return 3, 1, 3, 3, "Lets trained crews substitute for a missing essential role."
	case .Route_Stabilization:
		return 4, 2, 2, 3, "Reduces import losses and stabilizes service routes."
	case .Settlement_Production_Methods:
		return 3, 3, 2, 4, "Adds settlement-owned productive capacity."
	}
	return 0, 0, 0, 0, ""
}

start_research_program :: proc(c: ^Campaign, kind: Research_Kind, ship := Ship_ID(0)) -> bool {
	i := int(
		kind,
	); p := &c.material_economy.research[i]; if p.active || p.completed do return false
	knowledge, industry, manpower, duration, benefit := research_terms(kind)
	ship_at := ship_index(
		c,
		ship,
	); if ship_at < 0 || !c.ships[ship_at].active || c.ships[ship_at].committed do return false
	maintenance_reserve := i64(max(c.material_economy.fleet.maintenance_demand, 4) * 3)
	if c.material_economy.fleet.stock.manufactured_goods < i64(industry) + maintenance_reserve || c.capacities.manpower.total - c.capacities.manpower.reserved < manpower do return false
	p^ = {
		kind                 = kind,
		active               = true,
		remaining            = duration,
		knowledge_per_season = knowledge,
		industry_per_season  = industry,
		manpower             = manpower,
		ship                 = ship,
		benefit              = benefit,
	}; c.capacities.manpower.reserved += manpower
	return true
}

suspend_research_program :: proc(
	c: ^Campaign,
	kind: Research_Kind,
	suspend: bool,
) -> bool {p := &c.material_economy.research[int(kind)]; if !p.active do return false
	p.suspended = suspend
	return true}

complete_research :: proc(c: ^Campaign, p: ^Research_Program) {
	m := &c.material_economy; m.capabilities[int(p.kind)] = true; p.active = false; p.completed = true; c.capacities.manpower.reserved = max(c.capacities.manpower.reserved - p.manpower, 0)
	switch p.kind {case .Closed_Cycle_Agriculture:
		m.agriculture.nutrient_closure = min(m.agriculture.nutrient_closure + 25, 100)
		m.agriculture.equipment += 5
		m.agriculture.seed_reserves += 12; case .Ecological_Adaptation:
		m.agriculture.diversity += 6
		m.agriculture.damage = max(m.agriculture.damage - 8, 0); case .Ship_Role_Training:; case .Route_Stabilization:
		m.agriculture.import_dependence = max(
			m.agriculture.import_dependence - 12,
			0,
		); case .Settlement_Production_Methods:
		m.agriculture.cultivation += 5}
	record_event(
		c,
		.Project_Completed,
		fmt.tprintf("Research completed: %s", p.benefit),
		p.ship,
		value = i32(p.kind),
	)
}

advance_research :: proc(c: ^Campaign) {
	for &p in c.material_economy.research {if !p.active || p.suspended do continue; maintenance_reserve := i64(max(c.material_economy.fleet.maintenance_demand, 4) * 3); if c.material_economy.fleet.stock.manufactured_goods < i64(p.industry_per_season) + maintenance_reserve || c.material_economy.knowledge.deployable_capacity < p.knowledge_per_season {p.suspended = true; continue}; _ = fleet_stock_spend(c, {manufactured_goods = i64(p.industry_per_season)}); _ = spend_knowledge(c, p.knowledge_per_season, .Research); p.remaining -= 1; if p.remaining <= 0 do complete_research(c, &p)}
}

food_forecast :: proc(c: ^Campaign) -> (i32, i32, string) {a := c.material_economy.agriculture
	base := max(
		(a.cultivation * 2 +
			a.labor +
			a.equipment +
			a.diversity +
			a.nutrient_closure / 5 -
			a.damage) /
		6,
		0,
	)
	return max(base - a.damage / 3, 0),
		base + a.seed_reserves / 10,
		"Assumes current labor, equipment, damage, nutrient closure, and no new imports."}

apply_population_policy :: proc(c: ^Campaign) {
	a := &c.material_economy.agriculture
	for i in 0 ..< c.community_count {community := &c.communities[i]; growth := community.population / 180
		switch c.material_economy.population_policy {case .Reduced_Growth:
			growth /= 3; case .Planned_Contraction:
			if community.consents_to_settle do growth = -community.population / 300; case .Migration:
			if community.consents_to_settle do growth = -community.population / 240; case .Rationed:
			growth = 0; case .Stable:}
		if c.material_economy.fleet.stock.food <= i64(a.reserve_floor) do growth = min(growth, 0)
		community.population = max(community.population + growth, 0)
	}
}

deploy_surplus_knowledge :: proc(c: ^Campaign) {
	// Deployable knowledge remains available until the player or an explicit
	// institutional policy commits it. Crossing an arbitrary stock threshold
	// must not choose a research direction or silently diffuse evidence.
	_ = c
}

ship_role_impairment :: proc(ship: Ship, role: Role) -> i32 {
	switch role {
	case .Survey, .Archive:
		return ship.impairments.sensors
	case .Foundry, .Hospital, .Habitat, .Agriculture, .Colony:
		return ship.impairments.support
	case .Escort:
		return max(ship.impairments.strike, ship.impairments.mobility)
	}
	return 0
}

active_role :: proc(c: ^Campaign, role: Role) -> bool {for ship in c.ships[:c.ship_count] do if ship.active && !ship.committed && ship.damage < ship.power && ship.role == role && ship_role_impairment(ship, role) < 3 do return true
	return false}

research_support_ship :: proc(c: ^Campaign) -> Ship_ID {
	preferred_roles := [3]Role{.Archive, .Survey, .Foundry}
	for preferred in preferred_roles {
		id := narrative_cast_ship_for_role(c, preferred)
		if id != 0 {at := ship_index(c, id); if at >= 0 && !c.ships[at].committed do return id}
	}
	selected := Ship_ID(0); best_rank: u64
	for ship in c.ships[:c.ship_count] do if ship.active && !ship.committed {
		rank := narrative_rank(c, .Ship_Casting, u64(ship.id), 0x7265736561726368 ~ u64(u32(max(c.season, 0))))
		if selected == 0 || rank > best_rank {selected = ship.id; best_rank = rank}
	}
	return selected
}

detect_essential_exposure :: proc(c: ^Campaign, cause: u64 = 0) {
	m := &c.material_economy
	for role in Role {
		i := int(role); now := active_role(c, role); e := &m.essential[i]
		if now && e.exposed && !e.acknowledged {
			// A damaged or committed essential ship can return to operation. That
			// restoration answers the exposure directly; it must not leave a
			// permanent missing-capability flag behind.
			if at := ship_index(c, e.lost_ship);
			   at >= 0 &&
			   c.ships[at].active &&
			   !c.ships[at].committed &&
			   c.ships[at].damage < c.ships[at].power &&
			   c.ships[at].role == role &&
			   ship_role_impairment(c.ships[at], role) < 3 {
				e.chosen = .Restored_Ship; e.acknowledged = true; e.exposed = false
				detail := fmt.tprintf(
					"%s returned to service and restored the fleet's %s capability.",
					c.ships[at].name,
					role_name(role),
				)
				add_ship_history(
					c,
					e.lost_ship,
					detail,
				); record_event(c, .Resource_Changed, detail, e.lost_ship, cause_sequence = e.origin_event)
			}
		}
		if m.last_active_roles[i] &&
		   !now &&
		   !e.exposed {lost: Ship_ID; for ship in c.ships[:c.ship_count] do if ship.role == role {lost = ship.id; break}; e^ = {
				exposed        = true,
				role           = role,
				lost_ship      = lost,
				response_count = 6,
				detail         = fmt.tprintf(
					"The fleet has no active %s capability.",
					role_name(role),
				),
			}; e.responses = {
				.Refit_Ship,
				.Construct_Successor,
				.Train_Substitute,
				.Contract_Demand,
				.Import_Service,
				.Accept_Gap,
			}; record_event(c, .Need_Surfaced, e.detail, lost, cause_sequence = cause); e.origin_event = c.event_sequence}
		m.last_active_roles[i] = now
	}
}

reserve_essential_replacement :: proc(c: ^Campaign) -> bool {
	detect_essential_exposure(c)
	for role in Role {e := &c.material_economy.essential[int(role)]; if !e.exposed do continue
		if c.material_economy.capabilities[int(Research_Kind.Ship_Role_Training)] do return resolve_essential_exposure(c, role, .Train_Substitute)
		p := &c.material_economy.research[int(Research_Kind.Ship_Role_Training)]
		if p.active do return true
		ship := research_support_ship(c); if ship == 0 do return false
		return start_research_program(c, .Ship_Role_Training, ship)
	}
	return false
}

resolve_essential_exposure :: proc(
	c: ^Campaign,
	role: Role,
	response: Capability_Response,
	successor := Ship_ID(0),
) -> bool {
	e := &c.material_economy.essential[int(role)]; if !e.exposed || response == .None do return false
	switch response {case .Refit_Ship, .Construct_Successor:
		si := ship_index(c, successor); li := ship_index(c, e.lost_ship); if si < 0 || li < 0 || successor == e.lost_ship do return false
		cost :=
			response == .Construct_Successor ? Fleet_Stock{manufactured_goods = 16, equipment = 6, services = 3} : Fleet_Stock{manufactured_goods = 8, equipment = 3, services = 2}
		if !fleet_stock_spend(c, cost) do return false
		lost := c.ships[li]
		prior_role := c.ships[si].role
		c.ships[si].role = role
		c.ships[si].active = true
		c.ships[si].community = lost.community
		first, last := i32(0), i32(0)
		for era in c.service_eras[:c.service_era_count] do if era.ship == e.lost_ship {if first == 0 || era.first_season < first do first = era.first_season; last = max(last, era.last_season)}
		obligations := 0
		for &o in c.obligations.items[:c.obligations.count] do if obligation_active(o) && o.ship == e.lost_ship {o.ship = successor; o.last_event = e.origin_event; obligations += 1}
		community_name := "unassigned community"
		if ci := community_index(c, lost.community); ci >= 0 do community_name = c.communities[ci].name
		detail := fmt.tprintf(
			"Succeeded %s's %s duty with %s and %d unfinished obligations; predecessor service era S%d-S%d.",
			lost.name,
			role_name(role),
			community_name,
			obligations,
			first,
			last,
		)
		add_ship_history(c, successor, detail)
		_ = record_transformation(
			c,
			.Succession,
			successor,
			e.lost_ship,
			e.lost_ship,
			prior_role,
			role,
			detail,
			e.origin_event,
		)
		e.successor = successor
	case .Train_Substitute:
		if !c.material_economy.capabilities[int(Research_Kind.Ship_Role_Training)] do return false; case .Contract_Demand:
		c.material_economy.population_policy = .Planned_Contraction; case .Import_Service:
		if !fleet_stock_spend(c, {supplies = 4, services = 2}) do return false
		c.material_economy.agriculture.import_dependence = min(c.material_economy.agriculture.import_dependence + 20, 100); case .Accept_Gap:; case .Restored_Ship, .None:
		return false}
	e.chosen =
		response; e.acknowledged = true; e.exposed = false; record_event(c, .Resource_Changed, fmt.tprintf("The fleet answered the missing %s capability through %v.", role_name(role), response), successor, cause_sequence = e.origin_event); return true
}

plan_population_migration :: proc(
	c: ^Campaign,
	community: Community_ID,
	destination: Settlement_ID,
	people: i32,
) -> bool {
	ci := community_index(
		c,
		community,
	); si := settlement_index(c, destination); if ci < 0 || si < 0 || people <= 0 do return false
	group := &c.communities[ci]; settlement := &c.settlements[si]; if !group.consents_to_settle || people > group.population || settlement.population + people > settlement.viability * 1000 do return false
	capacity := settlement.viability * 1000; relationship_before := settlement.fleet_relationship
	group.population -=
		people; settlement.population += people; c.material_economy.population_policy = .Migration; settlement.fleet_relationship = max(settlement.fleet_relationship - 1, -100)
	record_event(
		c,
		.Community_Memory_Changed,
		fmt.tprintf(
			"%s transferred %d people to %s by recorded consent; destination occupancy is %d of %d and its fleet relationship changed from %d to %d.",
			group.name,
			people,
			settlement.name,
			settlement.population,
			capacity,
			relationship_before,
			settlement.fleet_relationship,
		),
		community = community,
		settlement_id = destination,
		value = people,
	)
	return true
}

apply_front_material_change :: proc(
	c: ^Campaign,
	kind: Front_Kind,
	transformation: Front_Transformation,
) {
	a := &c.material_economy.agriculture
	switch kind {
	case .Closed_Cycle_Ecology:
		#partial switch transformation {case .Distributed_Cost:
			a.equipment += 3; a.damage = max(a.damage - 2, 0); case .Broadened_Constituency:
			a.labor += 2; a.diversity += 1; case .Revised_Doctrine:
			a.nutrient_closure = min(a.nutrient_closure + 8, 100); a.seed_reserves += 4; case:}
	case .Fleet_Authority:
		if transformation == .Changed_Authority do c.material_economy.allocation_control = .Central_Command
		if transformation == .Shared_Ownership do c.material_economy.allocation_control = .Shared_Authority
	case .Passage_Access:
		if transformation == .Constrained_Route do a.import_dependence = min(a.import_dependence + 15, 100)
		if transformation == .Shared_Ownership do a.import_dependence = max(a.import_dependence - 8, 0)
	case .Settlement_Obligation:
		if transformation == .Broadened_Constituency &&
		   c.settlement_count >
			   0 {c.material_economy.production_owner = c.settlements[0].id; a.cultivation += 2}
	}
}

fleet_food_secure :: proc(m: ^Material_Economy) -> bool {
	a := &m.agriculture
	consumption := max(a.last_consumption, 1)
	production_secure := a.last_production + a.last_imports >= consumption
	stores_secure := m.fleet.stock.food >= i64(consumption * 3)
	return production_secure || stores_secure
}

advance_material_economy :: proc(c: ^Campaign) {
	m := &c.material_economy; a := &m.agriculture
	advance_fleet_metabolism(c)
	advance_research(c); detect_essential_exposure(c)
	advance_knowledge_commitments(c)
	low, high, _ := food_forecast(
		c,
	); a.forecast_low = low; a.forecast_high = high; a.last_production = (low + high) / 2
	if !active_role(c, .Agriculture) do a.last_production = max(a.last_production / 3, 0)
	a.last_production = i32(pressure_scale(i64(a.last_production), c.material_pressure, true))
	population := total_population(
		c,
	); a.last_consumption = i32(pressure_scale(i64(max(population / 5500 - m.diet_savings, 4)), c.material_pressure, false)); a.last_imports = settle_fleet_food_import(c); a.last_exports = max(a.last_production - a.last_consumption - 4, 0); a.last_spoilage = max((i32(m.fleet.stock.food) - a.reserve_floor) / 20, 0)
	delta :=
		a.last_production -
		a.last_consumption -
		a.last_exports -
		a.last_spoilage; m.fleet.stock.food = max(m.fleet.stock.food + i64(delta), 0); m.fleet.season.produced.food += i64(a.last_production); m.fleet.total.produced.food += i64(a.last_production); m.fleet.season.consumed.food += i64(a.last_consumption + a.last_spoilage); m.fleet.total.consumed.food += i64(a.last_consumption + a.last_spoilage)
	if m.fleet.stock.food <
	   i64(a.reserve_floor) {m.shortage_streak += 1} else {m.shortage_streak = 0}
	if m.shortage_streak >= 2 &&
	   !m.food_shortage_response_pending &&
	   c.season - m.last_food_shortage_resolution_season >= 2 {
		m.food_shortage_response_pending = true
		recurrence := m.food_shortage_response_count
		episode := &m.food_shortage_episode
		episode^ = {
			id            = m.next_food_shortage_episode_id,
			active        = true,
			opened_season = c.season,
			recurrence    = recurrence,
			production    = a.last_production,
			imports       = a.last_imports,
			consumption   = a.last_consumption,
			deficit       = max(a.last_consumption - a.last_production - a.last_imports, 0),
		}
		m.next_food_shortage_episode_id += 1
		record_event(
			c,
			.Need_Surfaced,
			fmt.tprintf(
				"Food production and imports fell %d below consumption; a persistent allocation command is required.",
				episode.deficit,
			),
			first_active_ship_with_role(c, .Agriculture),
			value = episode.deficit,
		)
		episode.origin_event = c.event_sequence
	}
	apply_population_policy(c)
	essential_clear :=
		true; for exposure in m.essential do if exposure.exposed && !exposure.acknowledged do essential_clear = false
	// Sustainability follows the material ledger, not whether a reserve-policy
	// prompt happens to be awaiting an answer this season. The prompt still
	// carries its own consequences; it no longer erases a genuinely adequate
	// production flow or three-season food buffer.
	sustainable := fleet_food_secure(m) && m.fleet.maintenance_debt == 0 && essential_clear
	if sustainable {c.sustainable_seasons += 1} else {c.sustainable_seasons = 0}
	// Operational detail is finite unless deliberately deployed; the archive is unchanged.
	deploy_surplus_knowledge(c)
}
