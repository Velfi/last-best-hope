package game

import "core:fmt"
import "core:strings"
sponsor_daughter_settlement :: proc(
	n: ^Settlement_Economy_Network,
	parent: Settlement_ID,
	name, region, charter: string,
	people: i64,
	assets: Economy_Stock,
	route_open, consent: bool,
	cause: u64,
) -> Settlement_ID {
	pi := settlement_economy_index(
		n,
		parent,
	); if pi < 0 || n.count >= MAX_SETTLEMENT_ECONOMIES || !route_open || !consent || people < 100 || assets.food < (people + 99) / 100 do return 0
	if assets.food < 0 || assets.goods < 0 || assets.services < 0 || assets.ships < 0 || assets.knowledge < 0 do return 0
	p := &n.economies[pi]
	parent_food_floor := max((p.population - people + 99) / 100 * 2, 1)
	parent_goods_floor := i64(max(p.maintenance_due * 2, 1))
	// Sponsorship is available only from a real productive surplus; a daughter
	// may not be created by converting the parent's next meals or maintenance.
	if p.population < people * 2 || p.stock.people < people || p.stock.food - assets.food < parent_food_floor || p.stock.goods - assets.goods < parent_goods_floor || p.stock.services < assets.services || p.stock.ships < assets.ships || p.stock.knowledge < assets.knowledge || p.authority < 40 do return 0
	id := Settlement_ID(
		max(n.next_settlement_id, 1),
	); n.next_settlement_id = u32(id) + 1; e := &n.economies[n.count]; e.settlement = id; e.active = true; e.lifecycle = .Dependent; e.population = people; e.labor = people * 2 / 5; e.housing = people + people / 4; e.stock = assets; e.stock.people = people; e.infrastructure = max(p.infrastructure - 10, 30); e.ecology = p.ecology; e.authority = max(p.authority - 10, 30); e.maintenance_due = max(e.infrastructure / 20, 1); e.identity = {
		name               = economy_unique_name(n, name, id),
		region             = region,
		founding_account   = fmt.tprintf(
			"%s sponsored %s with %d people and recorded assets.",
			p.identity.name,
			name,
			people,
		),
		charter            = charter,
		founder_ship       = p.identity.founder_ship,
		founding_community = p.identity.founding_community,
		origin_event       = cause,
	}; e.specialization = .Mixed; e.last_cause = cause
	p.population -=
		people; p.labor = p.population * 2 / 5; p.stock.people -= people; p.stock.food -= assets.food; p.stock.goods -= assets.goods; p.stock.services -= assets.services; p.stock.ships -= assets.ships; p.stock.knowledge -= assets.knowledge; n.count += 1; return id
}

construct_settlement_ship :: proc(
	e: ^Settlement_Economy,
	goods_cost, service_cost: i64,
) -> bool {if !e.active || goods_cost <= 0 || service_cost < 0 || e.stock.goods < goods_cost || e.stock.services < service_cost do return false
	e.stock.goods -= goods_cost
	e.stock.services -= service_cost
	e.consumed.goods += goods_cost
	e.consumed.services += service_cost
	e.stock.ships += 1
	e.produced.ships += 1
	return true}

settlement_ledger_view :: proc(
	c: ^Campaign,
	id: Settlement_ID,
) -> (
	Settlement_Ledger_View,
	bool,
) {i := settlement_economy_index(&c.settlement_economies, id); if i < 0 do return {}, false; e :=
		c.settlement_economies.economies[i]
	return {
			settlement = id,
			name = e.identity.name,
			specialization = fmt.tprintf("%v", e.specialization),
			status = fmt.tprintf("%v", e.lifecycle),
			population = e.population,
			stock = e.stock,
			produced = e.produced,
			consumed = e.consumed,
			imports = e.imports,
			exports = e.exports,
			losses = e.route_losses,
			infrastructure = e.infrastructure,
			ecology = e.ecology,
			authority = e.authority,
		},
		true}

trade_dependency_views :: proc(
	c: ^Campaign,
	settlement: Settlement_ID,
	views: ^[dynamic]Trade_Dependency_View,
) -> int {
	count := 0
	for f in c.settlement_economies.flows[:c.settlement_economies.flow_count] {
		if f.producer != settlement && f.consumer != settlement do continue
		producer := settlement_economy_index(&c.settlement_economies, f.producer)
		consumer := settlement_economy_index(&c.settlement_economies, f.consumer)
		supplier :=
			producer >= 0 ? c.settlement_economies.economies[producer].identity.name : fmt.tprintf("settlement %d", u32(f.producer))
		buyer :=
			consumer >= 0 ? c.settlement_economies.economies[consumer].identity.name : fmt.tprintf("settlement %d", u32(f.consumer))
		append(
			views,
			Trade_Dependency_View {
				flow = f.id,
				name = f.name,
				route = f.route_name,
				supplier = supplier,
				consumer = buyer,
				resource = fmt.tprintf("%v", f.resource),
				authority = f.authority,
				guarantee = f.guarantee,
				requested = f.requested,
				delivered = f.delivered,
				lost = f.lost,
				reliability = f.reliability,
				political_cost = f.political_cost,
				origin_event = f.origin_event,
				last_event = f.last_event,
				interrupted = f.condition == .Closed,
			},
		)
		count += 1
	}
	return count
}

apply_settlement_resilience :: proc(
	n: ^Settlement_Economy_Network,
	id: Settlement_ID,
	action: Settlement_Resilience_Action,
	resource: Economy_Resource,
	amount: i64,
	flow_index: int = -1,
	alternate: Settlement_ID = 0,
) -> bool {
	i := settlement_economy_index(
		n,
		id,
	); if i < 0 || amount < 0 do return false; e := &n.economies[i]
	switch action {
	case .Stockpile_Release:
		available := economy_stock_get(e.emergency_reserve, resource); release := min(
			available,
			amount,
		)
		if release <= 0 do return false
		economy_stock_add(&e.emergency_reserve, resource, -release)
		economy_stock_add(&e.stock, resource, release)
	case .Rationing:
		e.maintenance_due = max(e.maintenance_due - 1, 1); e.authority = max(e.authority - 1, 20)
	case .Accept_Shortage:
		e.lifecycle = .Dependent; e.shortage_seasons += 1
	case .Local_Production:
		if e.stock.services < amount do return false; e.stock.services -= amount
		economy_stock_add(&e.stock, resource, amount)
		economy_stock_add(&e.produced, resource, amount)
	case .Convoy_Escort:
		if flow_index < 0 || flow_index >= n.flow_count || n.flows[flow_index].consumer != id do return false
		n.flows[flow_index].guarantee = "settlement convoy escort"
		n.flows[flow_index].front_pressure = max(n.flows[flow_index].front_pressure - 2, 0)
	case .Alternate_Supplier:
		if flow_index < 0 || flow_index >= n.flow_count || settlement_economy_index(n, alternate) < 0 do return false
		n.flows[flow_index].producer = alternate
		n.flows[flow_index].name = fmt.tprintf("alternate supply via %s", n.economies[settlement_economy_index(n, alternate)].identity.name)
	}
	return true
}

assume_local_obligation :: proc(
	c: ^Campaign,
	obligation_index: int,
	consent: bool,
) -> bool {if !consent || obligation_index < 0 || obligation_index >= c.obligations.count do return false
	o := &c.obligations.items[obligation_index]
	if !obligation_active(o^) || o.settlement == 0 do return false
	i := settlement_economy_index(&c.settlement_economies, o.settlement)
	if i < 0 do return false
	e := &c.settlement_economies.economies[i]
	goods := i64(max(o.raw_materials, 0))
	services := i64(max(o.manpower + o.compute, 0))
	if e.stock.goods < goods || e.stock.services < services do return false
	if !contract_obligation(c, obligation_index, .Settlement_Assumption) do return false
	e.stock.goods -= goods
	e.stock.services -= services
	e.consumed.goods += goods
	e.consumed.services += services
	e.assumed_maintenance = true
	return true}

found_core_daughter_settlement :: proc(
	c: ^Campaign,
	parent: Settlement_ID,
	name, region, charter: string,
	people: i64,
	assets: Economy_Stock,
	route_open, consent: bool,
	cause: u64,
) -> Settlement_ID {if c.settlement_count >= MAX_SETTLEMENTS do return 0; pi := settlement_index(
		c,
		parent,
	)
	if pi < 0 do return 0
	id := sponsor_daughter_settlement(
		&c.settlement_economies,
		parent,
		name,
		region,
		charter,
		people,
		assets,
		route_open,
		consent,
		cause,
	)
	if id == 0 do return 0
	p := &c.settlements[pi]
	s := &c.settlements[c.settlement_count]
	s.id = id
	s.name = name
	s.population = i32(people)
	s.viability =
		c.settlement_economies.economies[settlement_economy_index(&c.settlement_economies, id)].infrastructure
	s.liberty = max(p.liberty - 5, 20)
	s.founded_season = c.season
	s.report_due = c.season + 2
	s.active = true
	s.founder_ship = p.founder_ship
	s.founding_community = p.founding_community
	s.proposal_event = cause
	s.fleet_relationship = p.fleet_relationship
	s.participating_ships[0] = p.founder_ship
	s.participating_ship_count = 1
	s.participating_communities[0] = p.founding_community
	s.participating_community_count = p.founding_community != 0 ? 1 : 0
	record_event(
		c,
		.Settlement_Founded,
		fmt.tprintf("%s sponsored %s with %d people and recorded assets.", p.name, name, people),
		p.founder_ship,
		i32(people),
		p.founding_community,
		cause,
		settlement_id = id,
	)
	s.founding_event = c.event_sequence
	s.last_report_event = c.event_sequence
	c.settlement_count += 1
	if c.settlement_relationship_count <
	   MAX_SETTLEMENT_RELATIONSHIPS {r := &c.settlement_relationships[c.settlement_relationship_count]
		r.settlement_a = min(parent, id)
		r.settlement_b = max(parent, id)
		r.kind = .Dependency
		r.strength = 1
		r.origin_event = c.event_sequence
		r.last_event = c.event_sequence
		c.settlement_relationship_count += 1}
	_ = set_settlement_political_relationship(c, parent, id, .Sponsor, c.event_sequence)
	s.celestial = p.celestial
	s.region = region
	// Parent-specific commitments divide with the people who made them. The
	// inherited share has its own causal record and remains independently payable.
	prior_obligations := c.obligations.count
	for obligation in c.obligations.items[:prior_obligations] do if obligation.settlement == parent && obligation_active(obligation) {
		_ = add_obligation(c, obligation.kind, fmt.tprintf("%s — %s inherited share", name, obligation.name), max(obligation.compute / 2, 0), max(obligation.manpower / 2, 0), max(obligation.raw_materials / 2, 0), max(obligation.ships / 2, 0), max(obligation.attention / 2, 0), settlement = id, institution = obligation.institution, cause = s.founding_event)
	}
	return id}

migrate_fleet_and_settlement :: proc(
	c: ^Campaign,
	direction: Settlement_Migration_Direction,
	community: Community_ID,
	settlement: Settlement_ID,
	ship: Ship_ID,
	people: i32,
	consent, route_open: bool,
) -> bool {if !consent || !route_open || people <= 0 do return false; ei :=
		settlement_economy_index(&c.settlement_economies, settlement)
	si := settlement_index(c, settlement)
	ci := community_index(c, community)
	if ei < 0 || si < 0 || ci < 0 do return false
	e := &c.settlement_economies.economies[ei]
	if c.settlements[si].fleet_relationship < -2 do return false
	food_need := i64(people + 99) / 100
	if direction == .Fleet_To_Settlement {labor_demand := e.labor < e.population / 2
		if !labor_demand || e.population + i64(people) > e.housing || e.stock.food < food_need do return false
		if !migrate_community(c, community, people, to_settlement = settlement, consent = true) do return false
		e.population += i64(people)
		e.labor = e.population * 2 / 5
		e.stock.people += i64(people)
		return true}
	ship_at := ship_index(c, ship)
	remaining := e.population - i64(people)
	if ship_at < 0 || !c.ships[ship_at].active || remaining < 100 || e.stock.people < i64(people) || e.labor - i64(people) * 2 / 5 < remaining / 5 do return false
	initialize_fleet_continuity(c)
	if c.transformations.residency_count >= MAX_COMMUNITY_RESIDENCIES do return false
	e.population = remaining
	e.labor = e.population * 2 / 5
	e.stock.people -= i64(people)
	c.settlements[si].population = max(c.settlements[si].population - people, 0)
	c.communities[ci].population += people
	r := &c.transformations.residencies[c.transformations.residency_count]
	c.transformations.residency_count += 1
	r^ = {
			community  = community,
			ship       = ship,
			population = people,
		}
	record_event(
		c,
		.Community_Joined,
		fmt.tprintf(
			"%d people returned from %s to %s by recorded consent.",
			people,
			c.settlements[si].name,
			c.ships[ship_at].name,
		),
		ship,
		people,
		community,
		settlement_id = settlement,
	)
	r.last_event = c.event_sequence
	return true}

set_settlement_political_relationship :: proc(
	c: ^Campaign,
	a, b: Settlement_ID,
	kind: Regional_Political_Relationship,
	cause: u64,
) -> bool {n := &c.settlement_economies; if a == b || settlement_economy_index(n, a) < 0 || settlement_economy_index(n, b) < 0 do return false
	for &link in n.political_links[:n.political_link_count] do if min(link.a, link.b) == min(a, b) && max(link.a, link.b) == max(a, b) {link.kind = kind; link.active = true; record_event(c, .Settlement_Relationship_Changed, fmt.tprintf("Settlements %d and %d recorded a %v relationship.", u32(a), u32(b), kind), settlement_id = a, cause_sequence = cause); link.last_event = c.event_sequence; return true}
	if n.political_link_count >= MAX_SETTLEMENT_POLITICAL_LINKS do return false
	link := &n.political_links[n.political_link_count]
	n.political_link_count += 1
	link^ = {
			a            = a,
			b            = b,
			kind         = kind,
			active       = true,
			origin_event = cause,
		}
	record_event(
		c,
		.Settlement_Relationship_Changed,
		fmt.tprintf("Settlements %d and %d recorded a %v relationship.", u32(a), u32(b), kind),
		settlement_id = a,
		cause_sequence = cause,
	)
	link.origin_event = c.event_sequence
	link.last_event = c.event_sequence
	return true}

merge_settlements :: proc(
	c: ^Campaign,
	survivor, joining: Settlement_ID,
	consent: bool,
	cause: u64,
) -> bool {if !consent || survivor == joining do return false; si := settlement_economy_index(
		&c.settlement_economies,
		survivor,
	)
	ji := settlement_economy_index(&c.settlement_economies, joining)
	cs := settlement_index(c, survivor)
	cj := settlement_index(c, joining)
	if si < 0 || ji < 0 || cs < 0 || cj < 0 do return false
	a := &c.settlement_economies.economies[si]
	b := &c.settlement_economies.economies[ji]
	a.population += b.population
	a.labor = a.population * 2 / 5
	a.housing += b.housing
	for resource in Economy_Resource do economy_stock_add(&a.stock, resource, economy_stock_get(b.stock, resource))
	c.settlements[cs].population = i32(a.population)
	c.settlements[cj].active = false
	for &o in c.obligations.items[:c.obligations.count] do if o.settlement == joining do o.settlement = survivor
	record_event(
		c,
		.Settlement_Relationship_Changed,
		fmt.tprintf(
			"%s merged into %s with people, assets, and obligations recorded.",
			c.settlements[cj].name,
			c.settlements[cs].name,
		),
		settlement_id = survivor,
		cause_sequence = cause,
	)
	return archive_settlement_economy(
		&c.settlement_economies,
		joining,
		survivor,
		c.season,
		c.event_sequence,
	)}

settlement_add_persistent_ship :: proc(
	c: ^Campaign,
	settlement: Settlement_ID,
	name, captain_name: string,
	role: Role,
	entry: Ship_Entry_Kind,
	predecessor: Ship_ID,
) -> Ship_ID {if entry == .Founding do return 0; ei := settlement_economy_index(
		&c.settlement_economies,
		settlement,
	)
	if ei < 0 do return 0
	e := &c.settlement_economies.economies[ei]
	goods, services := i64(12), i64(4)
	if entry != .Construction {goods = 4; services = 2}
	if e.stock.goods < goods || e.stock.services < services || e.stock.ships < 1 do return 0
	id := add_historical_ship(c, name, role, entry, predecessor)
	if id == 0 do return 0
	e.stock.goods -= goods
	e.stock.services -= services
	e.stock.ships -= 1
	e.exports.ships += 1
	if captain_name != "" do _ = succeed_captain(c, id, captain_name, fmt.tprintf("The appointment was recorded by settlement %d.", u32(settlement)))
	return id}

sync_campaign_settlement_economies :: proc(c: ^Campaign) {
	n := &c.settlement_economies
	for &s in c.settlements[:c.settlement_count] {
		if !s.active || settlement_economy_index(n, s.id) >= 0 do continue
		charter :=
			s.founding_procedure == .Voluntary_Opt_In ? "voluntary charter" : s.founding_procedure == .Collective_Mandate ? "collective charter" : "council charter"
		_ = initialize_settlement_economy(n, c, &s, charter)
	}
}

advance_settlement_economies :: proc(c: ^Campaign) {
	sync_campaign_settlement_economies(c); n := &c.settlement_economies
	for &e in n.economies[:n.count] do advance_settlement_economy(&e)
	// Existing political exchange records become named, accountable material flows.
	for relationship in c.settlement_relationships[:c.settlement_relationship_count] {
		if relationship.kind != .Exchange && relationship.kind != .Dependency do continue
		a := settlement_economy_index(
			n,
			relationship.settlement_a,
		); b := settlement_economy_index(n, relationship.settlement_b); if a < 0 || b < 0 do continue
		route_id :=
			u32(relationship.settlement_a) * 4099 +
			u32(
				relationship.settlement_b,
			); route_name := "recorded normal-space course"; authority := "local traffic offices"; condition := Route_Condition.Stable; traffic, pressure: i32
		for resource in Economy_Resource {
			if resource == .Ships || resource == .People do continue
			producer, consumer :=
				relationship.settlement_a,
				relationship.settlement_b; if economy_stock_get(n.economies[a].stock, resource) < economy_stock_get(n.economies[b].stock, resource) do producer, consumer = consumer, producer
			found :=
				false; for f in n.flows[:n.flow_count] do if f.producer == producer && f.consumer == consumer && f.resource == resource do found = true
			if found || economy_stock_get(n.economies[settlement_economy_index(n, producer)].stock, resource) < 8 do continue
			_ = add_trade_flow(
				n,
				fmt.tprintf("%s %v exchange", route_name, resource),
				producer,
				consumer,
				resource,
				6,
				route_id,
				route_name,
				authority,
				"exchange compact",
				condition,
				traffic,
				pressure,
				relationship.origin_event,
			)
		}
	}
	for i in 0 ..< n.flow_count do _ = settle_campaign_trade_flow(c, i)
	for &s in c.settlements[:c.settlement_count] {
		i := settlement_economy_index(n, s.id); if i < 0 do continue; e := &n.economies[i]
		// Preserve explicit aid, defense, charter, and development changes made by
		// other campaign systems. Their effect is bounded and fades unless renewed.
		external_change := s.viability - e.last_synced_viability
		if external_change != 0 do e.recorded_development = clamp(e.recorded_development + external_change, -30, 30)
		// Funded maintenance preserves condition. Development requires an explicit project;
		// ordinary surplus contributes only a small, bounded reserve margin.
		base :=
			(e.infrastructure + e.ecology + e.authority) /
			3; food_need := max(e.population / 100, 1); reserve_margin: i32
		if e.stock.food + e.emergency_reserve.food >= food_need * 3 do reserve_margin = 3
		if e.stock.food + e.emergency_reserve.food < food_need do reserve_margin = -6
		dependency_penalty: i32; if e.lifecycle == .Dependent do dependency_penalty = 5; if e.lifecycle == .Recovering do dependency_penalty = 8
		shortage_penalty := min(
			e.shortage_seasons * 2,
			12,
		); s.viability = clamp(base + reserve_margin + e.recorded_development - dependency_penalty - shortage_penalty, 0, 100); e.last_synced_viability = s.viability
		if e.recorded_development >
		   0 {e.recorded_development -= 1} else if e.recorded_development < 0 {e.recorded_development += 1}
		s.population = i32(min(e.population, i64(2147483647)))
	}
}
