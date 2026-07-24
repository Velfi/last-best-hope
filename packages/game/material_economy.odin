package game

import "core:fmt"

MAX_KNOWLEDGE_LEDGER :: 96
MAX_RESEARCH_PROGRAMS :: 5
ESSENTIAL_ROLE_COUNT :: 8

Knowledge_Source :: enum {
	Expedition,
	Intel,
	Cargo,
	Archives,
	Settlement_Report,
	Project,
	Emergency,
	Front_Transformation,
	Seasonal_Analysis,
}
Knowledge_Use :: enum {
	Research,
	Archive_Operation,
	Specialist_Training,
	Route_Engineering,
	Institutional_Analysis,
	Emergency,
	Front_Transformation,
	Diffusion,
}
Knowledge_Ledger_Entry :: struct {
	season: i32,
	amount: i32,
	source: Knowledge_Source,
	use:    Knowledge_Use,
	gained: bool,
}
Knowledge_Economy :: struct {
	archival_record:        i32,
	deployable_capacity:    i32,
	ledger:                 [MAX_KNOWLEDGE_LEDGER]Knowledge_Ledger_Entry,
	ledger_count:           int,
	total_gained_by_source: [9]i32,
	total_spent_by_use:     [8]i32,
}

Research_Kind :: enum {
	Closed_Cycle_Agriculture,
	Ecological_Adaptation,
	Ship_Role_Training,
	Route_Stabilization,
	Settlement_Production_Methods,
}
Research_Program :: struct {
	kind:                 Research_Kind,
	active:               bool,
	suspended:            bool,
	completed:            bool,
	remaining:            i32,
	knowledge_per_season: i32,
	industry_per_season:  i32,
	manpower:             i32,
	ship:                 Ship_ID,
	benefit:              string,
}
Knowledge_Commitment_Kind :: enum {
	Research_Program,
	Archive_Operation,
	Specialist_Training,
	Route_Engineering,
	Institutional_Analysis,
}
Knowledge_Commitment :: struct {
	kind:      Knowledge_Commitment_Kind,
	active:    bool,
	suspended: bool,
	cost:      i32,
	benefit:   string,
}

Agricultural_Capacity :: struct {
	cultivation:       i32,
	labor:             i32,
	equipment:         i32,
	diversity:         i32,
	nutrient_closure:  i32,
	seed_reserves:     i32,
	damage:            i32,
	import_dependence: i32,
	reserve_floor:     i32,
	last_production:   i32,
	last_consumption:  i32,
	last_imports:      i32,
	last_exports:      i32,
	last_spoilage:     i32,
	forecast_low:      i32,
	forecast_high:     i32,
}

Capability_Response :: enum {
	None,
	Refit_Ship,
	Construct_Successor,
	Train_Substitute,
	Contract_Demand,
	Import_Service,
	Accept_Gap,
	Restored_Ship,
}
Essential_Exposure :: struct {
	exposed:        bool,
	acknowledged:   bool,
	role:           Role,
	responses:      [6]Capability_Response,
	response_count: int,
	chosen:         Capability_Response,
	lost_ship:      Ship_ID,
	successor:      Ship_ID,
	origin_event:   u64,
	detail:         string,
}
Population_Policy :: enum {
	Stable,
	Reduced_Growth,
	Rationed,
	Planned_Contraction,
	Migration,
}
Food_Shortage_Command :: enum {
	None,
	Invest_Capacity,
	Change_Diet,
	Ration,
	Import_Route,
	Reduce_Growth,
	Contract_Habitat,
	Migrate_Community,
}
Food_Shortage_Response_Terms :: struct {
	label, cost, effect, tradeoff: string,
	reserve_cost, cohesion_cost:   i32,
}
Food_Shortage_Episode :: struct {
	id:                                         u32,
	active:                                     bool,
	opened_season, resolved_season, recurrence: i32,
	production, imports, consumption, deficit:  i32,
	origin_event, resolution_event:             u64,
	response:                                   Food_Shortage_Command,
}
Material_Economy :: struct {
	fleet:                                Fleet_Economy,
	knowledge:                            Knowledge_Economy,
	research:                             [MAX_RESEARCH_PROGRAMS]Research_Program,
	commitments:                          [5]Knowledge_Commitment,
	agriculture:                          Agricultural_Capacity,
	essential:                            [ESSENTIAL_ROLE_COUNT]Essential_Exposure,
	capabilities:                         [MAX_RESEARCH_PROGRAMS]bool,
	population_policy:                    Population_Policy,
	shortage_streak:                      i32,
	diet_savings:                         i32,
	food_shortage_response_pending:       bool,
	food_shortage_command:                Food_Shortage_Command,
	food_shortage_episode:                Food_Shortage_Episode,
	next_food_shortage_episode_id:        u32,
	food_shortage_response_count:         i32,
	last_food_shortage_resolution_season: i32,
	allocation_control:                   Authority_Policy,
	production_owner:                     Settlement_ID,
	last_active_roles:                    [ESSENTIAL_ROLE_COUNT]bool,
}

food_shortage_response_terms :: proc(
	command: Food_Shortage_Command,
) -> Food_Shortage_Response_Terms {
	switch command {
	case .Invest_Capacity:
		return {
			"EXPAND CULTIVATION",
			"8 Goods · 2 Equipment",
			"Adds 3 cultivation and 4 agricultural equipment.",
			"The same Industry cannot fund repairs or development.",
			0,
			0,
		}
	case .Ration:
		return {
			"RATION STORES",
			"6 Cohesion",
			"Cuts recurring consumption by 2 and raises the protected food floor.",
			"Population growth stops while rationing remains in force.",
			0,
			6,
		}
	case .Import_Route:
		return {
			"ESTABLISH IMPORTS",
			"4 Supplies",
			"Adds recurring food imports through a named settlement route.",
			"The fleet becomes dependent on that supplier and route.",
			0,
			0,
		}
	case .Change_Diet:
		return {
			"CHANGE DIET",
			"2 Cohesion",
			"Cuts recurring consumption by 2.",
			"Population growth stops while the restricted diet remains in force.",
			0,
			2,
		}
	case .Reduce_Growth:
		return {
			"REDUCE GROWTH",
			"No immediate cost",
			"Reduces demographic growth.",
			"The food deficit changes slowly rather than immediately.",
			0,
			0,
		}
	case .Contract_Habitat:
		return {
			"CONTRACT HABITAT",
			"Inhabited capacity",
			"Reduces consenting populations over time.",
			"The contraction permanently changes the traveling fleet.",
			0,
			0,
		}
	case .Migrate_Community:
		return {
			"MIGRATE COMMUNITY",
			"Community and destination capacity",
			"Transfers a consenting population to a settlement.",
			"Those people leave the traveling fleet.",
			0,
			0,
		}
	case .None:
		return {}
	}
	return {}
}

food_shortage_command_legal :: proc(
	c: ^Campaign,
	command: Food_Shortage_Command,
	community := Community_ID(0),
	destination := Settlement_ID(0),
) -> bool {
	if !c.material_economy.food_shortage_response_pending || command == .None do return false
	terms := food_shortage_response_terms(command)
	if fleet_supply(c) < terms.reserve_cost do return false
	switch command {
	case .Invest_Capacity:
		return fleet_stock_can_spend(
			c.material_economy.fleet.stock,
			{manufactured_goods = 8, equipment = 2},
		)
	case .Import_Route:
		return(
			fleet_food_import_available(c) &&
			fleet_stock_can_spend(c.material_economy.fleet.stock, {supplies = 4}) \
		)
	case .Migrate_Community:
		return community_index(c, community) >= 0 && settlement_index(c, destination) >= 0
	case .Change_Diet:
		return c.material_economy.diet_savings < 4
	case .Contract_Habitat:
		for group in c.communities[:c.community_count] do if group.consents_to_settle && group.population > 0 do return true
		return false
	case .Ration, .Reduce_Growth:
		return true
	case .None:
		return false
	}
	return false
}

apply_food_shortage_command :: proc(
	c: ^Campaign,
	command: Food_Shortage_Command,
	community := Community_ID(0),
	destination := Settlement_ID(0),
	people: i32 = 0,
) -> bool {
	if !food_shortage_command_legal(c, command, community, destination) do return false
	a := &c.material_economy.agriculture
	terms := food_shortage_response_terms(command)
	if !fleet_stock_spend(c, {supplies = i64(terms.reserve_cost)}, .Emergency) do return false; c.strategic.cohesion = max(c.strategic.cohesion - terms.cohesion_cost, 0)
	switch command {
	case .Invest_Capacity:
		if !fleet_stock_spend(c, {manufactured_goods = 8, equipment = 2}, .Emergency) do return false
		a.equipment += 4
		a.cultivation += 3
	case .Change_Diet:
		c.material_economy.diet_savings = min(c.material_economy.diet_savings + 2, 4)
		c.material_economy.population_policy = .Rationed
	case .Ration:
		c.material_economy.diet_savings = min(c.material_economy.diet_savings + 2, 4)
		c.material_economy.population_policy = .Rationed
		a.reserve_floor = min(a.reserve_floor + 4, 50)
	case .Import_Route:
		if !establish_fleet_food_import(c) || !fleet_stock_spend(c, {supplies = 4}) do return false
		a.import_dependence = min(a.import_dependence + 20, 100)
	case .Reduce_Growth:
		c.material_economy.population_policy = .Reduced_Growth
	case .Contract_Habitat:
		c.material_economy.population_policy = .Planned_Contraction
		for group in c.communities[:c.community_count] do if group.consents_to_settle {change := max(group.population / 300, 1); record_event(c, .Community_Memory_Changed, fmt.tprintf("%s consented to planned habitat contraction from %d people at %d people per season.", group.name, group.population, change), community = group.id, value = -change, cause_sequence = c.material_economy.food_shortage_episode.origin_event)}
	case .Migrate_Community:
		if !plan_population_migration(c, community, destination, people) do return false
	case .None:
		return false
	}
	m := &c.material_economy; m.food_shortage_command = command; m.food_shortage_response_pending = false; m.shortage_streak = 0; m.food_shortage_response_count += 1; m.last_food_shortage_resolution_season = c.season
	m.food_shortage_episode.active =
		false; m.food_shortage_episode.response = command; m.food_shortage_episode.resolved_season = c.season
	record_event(
		c,
		.Resource_Changed,
		fmt.tprintf(
			"The fleet adopted %s after a food deficit of %d.",
			terms.label,
			m.food_shortage_episode.deficit,
		),
		community = community,
		settlement_id = destination,
		value = i32(command),
		cause_sequence = m.food_shortage_episode.origin_event,
	)
	m.food_shortage_episode.resolution_event = c.event_sequence
	return true
}

commitment_terms :: proc(kind: Knowledge_Commitment_Kind) -> (i32, string, Knowledge_Use) {
	switch kind {case .Research_Program:
		return 2,
			"Keeps laboratories and production trials operational.",
			.Research; case .Archive_Operation:
		return 1,
			"Keeps preserved records indexed and available without converting them to tooling.",
			.Archive_Operation; case .Specialist_Training:
		return 2,
			"Maintains substitute crews for essential services.",
			.Specialist_Training; case .Route_Engineering:
		return 2,
			"Maintains route surveys, beacons, and import reliability.",
			.Route_Engineering; case .Institutional_Analysis:
		return 1,
			"Maintains public allocation and obligation reports.",
			.Institutional_Analysis}; return 0, "", .Research
}

set_knowledge_commitment :: proc(
	c: ^Campaign,
	kind: Knowledge_Commitment_Kind,
	active: bool,
) -> bool {cost, benefit, _ := commitment_terms(kind); entry := &c.material_economy.commitments[int(kind)]
	entry^ = {
		kind    = kind,
		active  = active,
		cost    = cost,
		benefit = benefit,
	}
	return true}
suspend_knowledge_commitment :: proc(
	c: ^Campaign,
	kind: Knowledge_Commitment_Kind,
	suspend: bool,
) -> bool {entry := &c.material_economy.commitments[int(kind)]; if !entry.active do return false
	entry.suspended = suspend
	return true}

advance_knowledge_commitments :: proc(c: ^Campaign) {for &entry in c.material_economy.commitments {if !entry.active || entry.suspended do continue
		_, _, use := commitment_terms(entry.kind)
		if !spend_knowledge(c, entry.cost, use) {entry.suspended = true; continue}
		switch
		entry.kind {case .Archive_Operation:
			c.material_economy.knowledge.archival_record += 1; case .Specialist_Training:
			c.material_economy.agriculture.labor += 1; case .Route_Engineering:
			c.material_economy.agriculture.import_dependence = max(
				c.material_economy.agriculture.import_dependence - 1,
				0,
			); case .Institutional_Analysis:; case .Research_Program:}}}

initialize_material_economy :: proc(c: ^Campaign) {
	m := &c.material_economy
	m.knowledge.archival_record = 70
	m.knowledge.deployable_capacity = 10
	m.allocation_control = .Shared_Authority
	m.next_food_shortage_episode_id = 1
	m.last_food_shortage_resolution_season = -1000
	m.agriculture = {
		cultivation      = 18,
		labor            = 12,
		equipment        = 14,
		diversity        = 8,
		nutrient_closure = 55,
		seed_reserves    = 30,
		reserve_floor    = 24,
	}
	initialize_fleet_economy(c)
	// Archive operation is a visible founding commitment, not passive decay.
	// It can be suspended with the same API as every later commitment.
	_ = set_knowledge_commitment(c, .Archive_Operation, true)
	for role in Role do m.last_active_roles[int(role)] = operational_role_available(c, role)
}


