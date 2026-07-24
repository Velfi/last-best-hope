package game

import "core:fmt"
import "core:strings"

MAX_SETTLEMENT_ECONOMIES :: 12
MAX_SETTLEMENT_ECONOMY_ARCHIVE :: 24
MAX_TRADE_FLOWS :: 24
MAX_SETTLEMENT_POLITICAL_LINKS :: 24

Route_Condition :: enum {
	Stable,
	Strained,
	Degrading,
	Closed,
	Reopened,
}

Settlement_Specialization :: enum {
	Mixed,
	Agricultural,
	Industrial,
	Archival,
	Medical,
	Navigational,
	Habitat,
	Defensive,
}
Settlement_Lifecycle :: enum {
	Founding,
	Dependent,
	Viable,
	Self_Sustaining,
	Recovering,
	Merging,
	Planned_Closure,
	Archived,
}
Economy_Resource :: enum {
	Food,
	Manufactured_Goods,
	Services,
	Ships,
	People,
	Knowledge,
}
Settlement_Resilience_Action :: enum {
	Alternate_Supplier,
	Stockpile_Release,
	Convoy_Escort,
	Local_Production,
	Rationing,
	Accept_Shortage,
}
Regional_Political_Relationship :: enum {
	Sponsor,
	Merger,
	Federation,
	Opposition,
}
Settlement_Migration_Direction :: enum {
	Fleet_To_Settlement,
	Settlement_To_Fleet,
}

Economy_Stock :: struct {
	food, goods, services, ships, people, knowledge: i64,
}

economy_stock_get :: proc(s: Economy_Stock, kind: Economy_Resource) -> i64 {
	switch kind {case .Food:
		return s.food; case .Manufactured_Goods:
		return s.goods; case .Services:
		return s.services; case .Ships:
		return s.ships; case .People:
		return s.people; case .Knowledge:
		return s.knowledge}
	return 0
}

economy_stock_add :: proc(s: ^Economy_Stock, kind: Economy_Resource, amount: i64) {
	switch kind {case .Food:
		s.food += amount; case .Manufactured_Goods:
		s.goods += amount; case .Services:
		s.services += amount; case .Ships:
		s.ships += amount; case .People:
		s.people += amount; case .Knowledge:
		s.knowledge += amount}
}

economy_stock_total :: proc(s: Economy_Stock) -> i64 {return(
		s.food +
		s.goods +
		s.services +
		s.ships +
		s.people +
		s.knowledge \
	)}
founding_waiver_count :: proc(mask: u16) -> i32 {count: i32; value := mask; for value !=
	    0 {count += i32(value & 1); value >>= 1}
	return count}

Settlement_Identity :: struct {
	name, region, founding_account, charter: string,
	founder_ship:                            Ship_ID,
	founding_community:                      Community_ID,
	origin_event:                            u64,
}

Settlement_Economy :: struct {
	settlement:                                                            Settlement_ID,
	identity:                                                              Settlement_Identity,
	specialization:                                                        Settlement_Specialization,
	lifecycle:                                                             Settlement_Lifecycle,
	population, labor, housing:                                            i64,
	stock, emergency_reserve:                                              Economy_Stock,
	produced, consumed, imports, exports, route_losses:                    Economy_Stock,
	infrastructure, ecology, authority, maintenance_due, shortage_seasons: i32,
	sustainable_seasons, warning_seasons, waiver_exposures:                i32,
	evacuation_pending:                                                    bool,
	recorded_development, last_synced_viability:                           i32,
	assumed_maintenance:                                                   bool,
	active:                                                                bool,
	last_cause:                                                            u64,
}

Trade_Flow :: struct {
	id:                                                   u32,
	name:                                                 string,
	producer, consumer:                                   Settlement_ID,
	resource:                                             Economy_Resource,
	requested:                                            i64,
	shipped:                                              i64,
	delivered:                                            i64,
	lost:                                                 i64,
	route:                                                u32,
	route_name, authority, guarantee:                     string,
	condition:                                            Route_Condition,
	traffic, front_pressure, political_cost, reliability: i32,
	active:                                               bool,
	origin_event, last_event:                             u64,
}
Settlement_Political_Link :: struct {
	a, b:                     Settlement_ID,
	kind:                     Regional_Political_Relationship,
	active:                   bool,
	origin_event, last_event: u64,
}

Archived_Settlement_Economy :: struct {
	economy:       Settlement_Economy,
	closed_season: i32,
	successor:     Settlement_ID,
	cause:         u64,
}

Settlement_Economy_Network :: struct {
	economies:                        [dynamic]Settlement_Economy,
	count:                            int,
	archived:                         [dynamic]Archived_Settlement_Economy,
	archived_count:                   int,
	flows:                            [dynamic]Trade_Flow,
	flow_count:                       int,
	next_settlement_id, next_flow_id: u32,
	political_links:                  [dynamic]Settlement_Political_Link,
	political_link_count:             int,
}

Settlement_Ledger_View :: struct {
	settlement:                                          Settlement_ID,
	name, specialization, status:                        string,
	population:                                          i64,
	stock, produced, consumed, imports, exports, losses: Economy_Stock,
	infrastructure, ecology, authority:                  i32,
}
Trade_Dependency_View :: struct {
	flow:                                                            u32,
	name, route, supplier, consumer, resource, authority, guarantee: string,
	requested, delivered, lost:                                      i64,
	reliability, political_cost:                                     i32,
	origin_event, last_event:                                        u64,
	interrupted:                                                     bool,
}

settlement_economy_network_ensure_storage :: proc(n: ^Settlement_Economy_Network) {
	allocator := campaign_storage_allocator()
	if len(n.economies) == 0 do n.economies = make([dynamic]Settlement_Economy, MAX_SETTLEMENT_ECONOMIES, allocator)
	if len(n.archived) == 0 do n.archived = make([dynamic]Archived_Settlement_Economy, MAX_SETTLEMENT_ECONOMY_ARCHIVE, allocator)
	if len(n.flows) == 0 do n.flows = make([dynamic]Trade_Flow, MAX_TRADE_FLOWS, allocator)
	if len(n.political_links) == 0 do n.political_links = make([dynamic]Settlement_Political_Link, MAX_SETTLEMENT_POLITICAL_LINKS, allocator)
}

settlement_economy_index :: proc(
	n: ^Settlement_Economy_Network,
	id: Settlement_ID,
) -> int {settlement_economy_network_ensure_storage(n); for e, i in n.economies[:n.count] do if e.active && e.settlement == id do return i
	return -1}

economy_unique_name :: proc(
	n: ^Settlement_Economy_Network,
	base: string,
	id: Settlement_ID,
) -> string {
	name := base
	if name == "" do name = generate_settlement_name(u64(id))
	for attempt in u32(0) ..< u32(len(SETTLEMENT_NAMES)) {
		duplicate := false
		for e in n.economies[:n.count] do if e.active && strings.equal_fold(e.identity.name, name) {duplicate = true; break}
		if !duplicate do return name
		// Authored table entries have static lifetime, so persistent identities
		// never retain a temporary formatted string.
		name = generate_settlement_name(u64(id), reroll = attempt + 1)
	}
	return "Common Ground"
}

specialization_for_founders :: proc(c: ^Campaign, s: ^Settlement) -> Settlement_Specialization {
	food, industry, archives, medicine, navigation, habitat, defense := 0, 0, 0, 0, 0, 0, 0
	for id in s.participating_ships[:s.participating_ship_count] {at := ship_index(c, id); if at < 0 do continue; switch c.ships[at].role {case .Agriculture:
			food += 3; case .Foundry:
			industry += 3; case .Archive:
			archives += 3; case .Hospital:
			medicine += 3; case .Survey:
			navigation += 3; case .Habitat, .Colony:
			habitat += 3; case .Escort:
			defense += 3}}
	if s.archive_id != 0 do archives += 2
	best := max(
		max(max(food, industry), max(archives, medicine)),
		max(max(navigation, habitat), defense),
	); if best < 3 do return .Mixed
	if food == best do return .Agricultural; if industry == best do return .Industrial; if archives == best do return .Archival; if medicine == best do return .Medical; if navigation == best do return .Navigational; if habitat == best do return .Habitat; return .Defensive
}

initialize_settlement_economy :: proc(
	n: ^Settlement_Economy_Network,
	c: ^Campaign,
	s: ^Settlement,
	charter: string = "independent charter",
) -> bool {
	if n.count >= MAX_SETTLEMENT_ECONOMIES || settlement_economy_index(n, s.id) >= 0 do return false
	e := &n.economies[n.count]; e.settlement = s.id; e.active = true; e.lifecycle = .Founding; e.population = i64(max(s.population, 0)); e.labor = e.population * 2 / 5; e.housing = max(e.population + e.population / 5 + i64(s.orbital_refuge_capacity), 1000); e.infrastructure = clamp(s.viability, 20, 100); e.ecology = 70; e.authority = clamp(s.liberty, 20, 100); e.waiver_exposures = founding_waiver_count(s.waived_founding_requirements); e.maintenance_due = max(1, e.infrastructure / 20) * max(s.maintenance_basis_points, 10000) / 10000 + e.waiver_exposures + (s.orbital_refuge ? 1 : 0); e.warning_seasons = e.waiver_exposures > 0 ? 1 : 0; e.last_synced_viability = s.viability
	e.identity = {
		name               = economy_unique_name(n, s.name, s.id),
		region             = s.region != "" ? s.region : "unrecorded region",
		founding_account   = s.public_founding_account,
		charter            = charter,
		founder_ship       = s.founder_ship,
		founding_community = s.founding_community,
		origin_event       = s.founding_event,
	}
	e.specialization = specialization_for_founders(c, s)
	// Every opening balance is traceable to people, founding vessels, transferred records, place, and charter.
	e.stock.people =
		e.population; e.stock.food = max(e.population / 80, 20); e.stock.goods = i64(max(i32(s.participating_ship_count) * 8 + e.infrastructure / 10, 8)); e.stock.services = i64(max(i32(s.participating_community_count) * 5 + e.authority / 20, 4)); e.stock.ships = i64(s.participating_ship_count); e.stock.knowledge = (s.archive_id != 0 ? i64(12) : i64(2)) + i64(s.participating_community_count) * 2
	if s.orbital_refuge do e.stock.services += 4
	if s.biosphere_evidence != .None {e.ecology = min(e.ecology + 10, 100); e.stock.knowledge += 8}
	for community_id in s.participating_communities[:s.participating_community_count] {ci := community_index(c, community_id); if ci >= 0 {e.stock.services += i64(max(c.communities[ci].trust / 20, 1)); e.authority = clamp(e.authority - c.communities[ci].grievance, 20, 100)}}
	if c.settlement_proposal.name ==
	   s.name {for transfer, i in c.settlement_proposal.transfer_institutions do if transfer {e.stock.services += 5; e.stock.knowledge += 3; if i == 2 do e.specialization = .Archival}; for transfer in c.settlement_proposal.transfer_archives do if transfer do e.stock.knowledge += 6}
	if charter ==
	   "collective charter" {e.authority = min(e.authority + 5, 100); e.stock.services += 3} else if charter == "council charter" {e.infrastructure = min(e.infrastructure + 4, 100); e.stock.goods += 4}
	e.emergency_reserve.food = max(
		e.stock.food / 5,
		2,
	); e.emergency_reserve.goods = max(e.stock.goods / 5, 1)
	if s.orbital_refuge do e.emergency_reserve.goods += 2
	n.count += 1; if u32(s.id) >= n.next_settlement_id do n.next_settlement_id = u32(s.id) + 1
	return true
}

economy_production :: proc(e: ^Settlement_Economy) -> Economy_Stock {
	condition := i64(
		clamp(min(e.infrastructure, e.ecology), 0, 100),
	); labor := max(e.labor, 0); p: Economy_Stock
	p.food = max(
		labor * condition / 5000,
		1,
	); p.goods = max(labor * i64(e.infrastructure) / 9000, 1); p.services = max(labor * i64(e.authority) / 12000, 1); p.knowledge = max(labor * i64(e.authority) / 40000, 0)
	switch e.specialization {case .Agricultural:
		p.food = p.food * 2; case .Industrial:
		p.goods = p.goods * 2; case .Archival:
		p.knowledge = max(p.knowledge * 2, 2); case .Medical:
		p.services = p.services * 2; case .Navigational:
		p.services += 2; case .Habitat:
		e.housing += max(labor / 1000, 1); case .Defensive:
		p.goods += 1; case .Mixed:}
	return p
}

advance_settlement_economy :: proc(e: ^Settlement_Economy) {
	if !e.active do return
	p := economy_production(
		e,
	); economy_stock_add(&e.stock, .Food, p.food); economy_stock_add(&e.stock, .Manufactured_Goods, p.goods); economy_stock_add(&e.stock, .Services, p.services); economy_stock_add(&e.stock, .Knowledge, p.knowledge); e.produced.food += p.food; e.produced.goods += p.goods; e.produced.services += p.services; e.produced.knowledge += p.knowledge
	food_need := max(
		e.population / 100,
		1,
	); goods_need := i64(max(e.maintenance_due, 1)); food_used := min(e.stock.food, food_need); goods_used := min(e.stock.goods, goods_need); e.stock.food -= food_used; e.stock.goods -= goods_used; e.consumed.food += food_used; e.consumed.goods += goods_used
	short := food_used < food_need || goods_used < goods_need
	if short &&
	   e.emergency_reserve.food >
		   0 {release := min(e.emergency_reserve.food, food_need - food_used); e.emergency_reserve.food -= release; e.consumed.food += release; food_used += release; short = food_used < food_need || goods_used < goods_need}
	if short {
		e.shortage_seasons += 1; e.sustainable_seasons = 0; e.lifecycle = .Recovering; e.infrastructure = max(e.infrastructure - 1, 10)
		if e.shortage_seasons >= 2 {e.warning_seasons += 1; e.evacuation_pending = true}
	} else {
		e.shortage_seasons = 0; e.sustainable_seasons += 1; e.assumed_maintenance = true
		if e.sustainable_seasons >=
		   3 {e.lifecycle = .Self_Sustaining; e.evacuation_pending = false} else if e.sustainable_seasons >= 1 {e.lifecycle = .Viable} else {e.lifecycle = .Dependent}
	}
}

route_capacity_reliability :: proc(
	condition: Route_Condition,
	traffic, front_pressure: i32,
	guaranteed: bool,
) -> (
	i64,
	i32,
	i32,
) {
	capacity: i64 = 24; reliability: i32 = 95
	switch condition {case .Stable:; case .Reopened:
		capacity = 18; reliability = 85; case .Strained:
		capacity = 12; reliability = 75; case .Degrading:
		capacity = 8; reliability = 60; case .Closed:
		capacity = 0; reliability = 0}
	capacity = max(
		capacity - i64(max(traffic - 4, 0)) - i64(max(front_pressure, 0)),
		0,
	); reliability = clamp(reliability - front_pressure * 4 + (guaranteed ? i32(10) : i32(0)), 0, 100); political: i32 = max(front_pressure + (guaranteed ? i32(2) : i32(0)) + (traffic > 6 ? i32(1) : i32(0)), 0); return capacity, reliability, political
}

add_trade_flow :: proc(
	n: ^Settlement_Economy_Network,
	name: string,
	producer, consumer: Settlement_ID,
	resource: Economy_Resource,
	requested: i64,
	route: u32,
	route_name, authority, guarantee: string,
	condition: Route_Condition,
	traffic, front_pressure: i32,
	cause: u64 = 0,
) -> int {
	if n.flow_count >= MAX_TRADE_FLOWS || producer == consumer || settlement_economy_index(n, producer) < 0 || settlement_economy_index(n, consumer) < 0 do return -1
	i := n.flow_count; n.next_flow_id += 1; n.flows[i] = {
		id             = n.next_flow_id,
		name           = name,
		producer       = producer,
		consumer       = consumer,
		resource       = resource,
		requested      = max(requested, 0),
		route          = route,
		route_name     = route_name,
		authority      = authority,
		guarantee      = guarantee,
		condition      = condition,
		traffic        = traffic,
		front_pressure = front_pressure,
		active         = true,
		origin_event   = cause,
		last_event     = cause,
	}; n.flow_count += 1; return i
}

settle_trade_flow :: proc(n: ^Settlement_Economy_Network, index: int) -> bool {
	if index < 0 || index >= n.flow_count do return false; f := &n.flows[index]; if !f.active do return false; pi := settlement_economy_index(n, f.producer); ci := settlement_economy_index(n, f.consumer); if pi < 0 || ci < 0 do return false
	p := &n.economies[pi]; c := &n.economies[ci]; capacity, reliability, cost := route_capacity_reliability(f.condition, f.traffic, f.front_pressure, f.guarantee != ""); available := economy_stock_get(p.stock, f.resource); reserve: i64 = 0; if f.resource == .Food do reserve = max(p.population / 100, 1); shipped: i64 = min(min(max(available - reserve, 0), f.requested), capacity); delivered := shipped * i64(reliability) / 100; lost := shipped - delivered
	economy_stock_add(
		&p.stock,
		f.resource,
		-shipped,
	); economy_stock_add(&p.exports, f.resource, shipped); economy_stock_add(&c.stock, f.resource, delivered); economy_stock_add(&c.imports, f.resource, delivered); economy_stock_add(&p.route_losses, f.resource, lost); f.shipped = shipped; f.delivered = delivered; f.lost = lost; f.reliability = reliability; f.political_cost = cost
	if delivered < f.requested do c.lifecycle = .Dependent
	return true
}

settle_campaign_trade_flow :: proc(c: ^Campaign, index: int) -> bool {
	if !settle_trade_flow(&c.settlement_economies, index) do return false
	f := &c.settlement_economies.flows[index]
	// One factual Chronicle entry establishes the causal edge. Later seasons
	// update the ledger without flooding the record with identical notices.
	if f.last_event == f.origin_event {
		detail :=
			f.condition == .Closed ? fmt.tprintf("%s closed; %s received no %v.", f.route_name, c.settlement_economies.economies[settlement_economy_index(&c.settlement_economies, f.consumer)].identity.name, f.resource) : fmt.tprintf("%s delivered %d %v from %s to %s; %d was lost in transit.", f.route_name, f.delivered, f.resource, c.settlement_economies.economies[settlement_economy_index(&c.settlement_economies, f.producer)].identity.name, c.settlement_economies.economies[settlement_economy_index(&c.settlement_economies, f.consumer)].identity.name, f.lost)
		record_event(
			c,
			.Resource_Changed,
			detail,
			settlement_id = f.consumer,
			cause_sequence = f.origin_event,
			value = i32(min(f.delivered, i64(2147483647))),
		)
		f.last_event = c.event_sequence
	}
	return true
}

interrupt_trade_route :: proc(n: ^Settlement_Economy_Network, route: u32) {for &f in n.flows[:n.flow_count] do if f.route == route {f.condition = .Closed; f.active = true}}

recover_settlement :: proc(
	e: ^Settlement_Economy,
	aid: Economy_Stock,
	mode: Settlement_Lifecycle,
) {economy_stock_add(&e.stock, .Food, aid.food); economy_stock_add(
		&e.stock,
		.Manufactured_Goods,
		aid.goods,
	)
	economy_stock_add(&e.stock, .Services, aid.services)
	economy_stock_add(&e.stock, .Ships, aid.ships)
	economy_stock_add(&e.stock, .People, aid.people)
	economy_stock_add(&e.stock, .Knowledge, aid.knowledge)
	e.lifecycle = mode
	e.population += aid.people
	e.labor = e.population * 2 / 5}

archive_settlement_economy :: proc(
	n: ^Settlement_Economy_Network,
	id, successor: Settlement_ID,
	season: i32,
	cause: u64,
) -> bool {
	i := settlement_economy_index(
		n,
		id,
	); if i < 0 || n.archived_count >= MAX_SETTLEMENT_ECONOMY_ARCHIVE do return false; e := &n.economies[i]; e.lifecycle = .Archived; e.active = false; n.archived[n.archived_count] = {
		economy       = e^,
		closed_season = season,
		successor     = successor,
		cause         = cause,
	}; n.archived_count += 1
	// Reuse the bounded active slot without erasing its archived era.
	last :=
		n.count -
		1; if i != last do n.economies[i] = n.economies[last]; n.economies[last] = {}; n.count -= 1; return true
}

migrate_between_settlements :: proc(
	n: ^Settlement_Economy_Network,
	from, to: Settlement_ID,
	people: i64,
	consent, route_open: bool,
) -> bool {
	fi := settlement_economy_index(
		n,
		from,
	); ti := settlement_economy_index(n, to); if fi < 0 || ti < 0 || people <= 0 || !consent || !route_open do return false; a := &n.economies[fi]; b := &n.economies[ti]; if a.population < people || a.stock.food < people / 100 || b.population + people > b.housing do return false; a.population -= people; a.labor = a.population * 2 / 5; a.stock.people -= people; b.population += people; b.labor = b.population * 2 / 5; b.stock.people += people; return true
}


