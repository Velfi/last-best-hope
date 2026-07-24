package game

// The strategic model is deliberately small at the player boundary. Detailed
// stocks and institutions remain simulated, but every strategic reading belongs
// to one of three state axes and every order belongs to one of four controls.
Strategic_Axis :: enum {
	Reserves,
	Capacity,
	Cohesion,
}
Control_Family :: enum {
	Allocation,
	Policy,
	Organization,
	Commitment,
}
Information_State :: enum {
	Known,
	Forecast,
	Disputed,
	Unknown,
}

Strategic_State_View :: struct {
	reserves:                                                 i32,
	reserve_floor:                                            i32,
	capacity_available:                                       i32,
	capacity_total:                                           i32,
	compute_available, compute_total:                         i32,
	manpower_available, manpower_total:                       i32,
	materials_available, materials_total:                     i32,
	cohesion:                                                 i32,
	cohesion_baseline, community_trust, community_divergence: i32,
	information:                                              Information_State,
}

// Strategic_Pressure is the authoritative rules snapshot for constitutional
// pressure. UI forecasts and season resolution use the same reserve, capacity,
// and cohesion margins instead of independently interpreting raw fields.
Strategic_Pressure :: struct {
	reserves, reserve_floor, reserve_coverage:           i32,
	capacity_available, capacity_total, capacity_margin: i32,
	cohesion, cohesion_margin:                           i32,
	warning, emergency, recovery_met:                    bool,
	cause:                                               Emergency_Cause,
}

strategic_pressure :: proc(
	c: ^Campaign,
	reserve_adjustment: i32 = 0,
	cohesion_adjustment: i32 = 0,
) -> Strategic_Pressure {
	state := strategic_state_view(c)
	reserves := max(state.reserves + reserve_adjustment, 0)
	cohesion := clamp(state.cohesion + cohesion_adjustment, 0, 100)
	// A fifth of installed capacity is the minimum operating margin; commitments
	// and damage both reduce the available side of the same comparison.
	capacity_floor := max(state.capacity_total / 5, 1)
	r := Strategic_Pressure {
		reserves           = reserves,
		reserve_floor      = state.reserve_floor,
		reserve_coverage   = reserves - state.reserve_floor,
		capacity_available = state.capacity_available,
		capacity_total     = state.capacity_total,
		capacity_margin    = state.capacity_available - capacity_floor,
		cohesion           = cohesion,
		cohesion_margin    = cohesion - EMERGENCY_FLOOR,
	}
	r.warning = r.reserve_coverage <= 12 || r.capacity_margin <= 3 || r.cohesion_margin <= 12
	r.emergency = r.reserve_coverage < 0 || r.capacity_margin < 0 || r.cohesion_margin < 0
	r.recovery_met =
		r.reserve_coverage >= 8 &&
		r.capacity_margin >= 3 &&
		r.cohesion >= c.emergency_recovery_target
	if r.reserve_coverage < 0 do r.cause = .Reserves
	if r.capacity_margin < 0 && (r.cause == .None || r.capacity_margin < r.reserve_coverage) do r.cause = .Capacity
	if r.cohesion_margin < 0 && (r.cause == .None || r.cohesion_margin < min(r.reserve_coverage, r.capacity_margin)) do r.cause = .Cohesion
	return r
}

Ending_Readiness :: struct {
	reserve_coverage, capacity_margin, cohesion:                                         i32,
	unresolved_hazards, viable_settlements, active_promises, broken_promises:            i32,
	passage_objectives, completed_undertakings, transformation_records, sustainable_seasons: i32,
	fleet_food_coverage, sustainable_settlements:                                        i32,
	eligible:                                                                            [7]bool,
	recommended:                                                                         Ending,
	unmet_summary:                                                                       string,
	ready, structurally_fragile:                                                         bool,
}

ending_identity :: proc(c: ^Campaign) -> Ending {
	r := ending_readiness(c)
	// Identity is earned from durable campaign history. The finale grades how
	// securely that identity can continue; it does not revoke the history.
	identity := Ending.Fragmented_Survival
	if active_ship_count(c) >= 6 && r.passage_objectives >= 2 do identity = .Nomadic_Fleet
	if r.transformation_records >= 2 && r.passage_objectives >= 1 do identity = .Transformed
	if r.viable_settlements == 1 do identity = .New_Home
	if r.viable_settlements >= 2 do identity = .Harbor_Network
	federated :=
		false; for link in c.settlement_economies.political_links[:c.settlement_economies.political_link_count] do if link.active && link.kind == .Federation do federated = true
	if r.viable_settlements >= 2 && (federated || has_precedent(c, .Open_Archives)) do identity = .Federation
	return identity
}

ending_quality :: proc(c: ^Campaign, ending: Ending) -> Ending_Quality {
	r := ending_readiness(c); score := i32(0)
	if r.reserve_coverage >= 0 do score += 1
	if r.capacity_margin >= 0 do score += 1
	if r.cohesion >= EMERGENCY_FLOOR do score += 1
	if r.broken_promises == 0 do score += 1
	if r.unresolved_hazards == 0 do score += 1
	#partial switch ending {
	case .Nomadic_Fleet:
		if c.material_economy.fleet.maintenance_debt == 0 do score += 1
		if r.sustainable_seasons >= 3 do score += 1
	case .New_Home, .Harbor_Network, .Federation:
		if r.sustainable_settlements >= max(r.viable_settlements, 1) do score += 2
	case .Transformed:
		if r.completed_undertakings > 0 do score += 1; if r.sustainable_seasons >= 3 do score += 1
	case .Fragmented_Survival:
		if active_ship_count(c) > 0 && total_population(c) > 0 do score += 1
	case .In_Progress:
	}
	if score >= 6 do return .Flourishing
	if score >= 4 do return .Stable
	return .Fragile
}

ending_readiness :: proc(c: ^Campaign) -> Ending_Readiness {
	p := strategic_pressure(c)
	r := Ending_Readiness {
		reserve_coverage   = p.reserve_coverage,
		capacity_margin    = p.capacity_margin,
		cohesion           = p.cohesion,
		unresolved_hazards = c.uncontained_hazard_count,
	}
	for settlement in c.settlements[:c.settlement_count] do if settlement.active && settlement.viability >= 50 do r.viable_settlements += 1
	for promise in c.promises[:c.promise_count] {if promise.status == .Active do r.active_promises += 1; if promise.status == .Broken do r.broken_promises += 1}
	for record in c.dark_strategy_records[:c.dark_strategy_record_count] do r.passage_objectives += record.objective_successes
	for call in c.compact.calls[:c.compact.call_count] do if call.status == .Completed do r.completed_undertakings += 1
	r.transformation_records = i32(
		c.transformations.record_count,
	); r.sustainable_seasons = c.sustainable_seasons
	consumption := max(
		c.material_economy.agriculture.last_consumption,
		1,
	); r.fleet_food_coverage = i32(c.material_economy.fleet.stock.food) / consumption
	for economy in c.settlement_economies.economies[:c.settlement_economies.count] do if economy.active && economy.stock.food > max(economy.population / 100, 1) do r.sustainable_settlements += 1
	r.ready =
		r.viable_settlements > 0 ||
		(r.reserve_coverage >= 0 && r.capacity_margin >= 0 && r.cohesion >= EMERGENCY_FLOOR)
	r.structurally_fragile =
		r.viable_settlements == 0 &&
		r.unresolved_hazards >= 3 &&
		(r.reserve_coverage < 0 || r.capacity_margin < 0 || r.cohesion < EMERGENCY_FLOOR) &&
		r.broken_promises >= 2
	stable := r.sustainable_seasons >= 3
	accounted := r.completed_undertakings > 0
	trade :=
		false; for flow in c.settlement_economies.flows[:c.settlement_economies.flow_count] do if flow.active && flow.condition != .Closed do trade = true
	federated :=
		false; for link in c.settlement_economies.political_links[:c.settlement_economies.political_link_count] do if link.active && link.kind == .Federation do federated = true
	essential :=
		true; for exposure in c.material_economy.essential do if exposure.exposed && !exposure.acknowledged do essential = false
	r.eligible[int(Ending.New_Home)] =
		r.viable_settlements == 1 &&
		r.sustainable_settlements >= 1 &&
		accounted &&
		r.unresolved_hazards == 0
	r.eligible[int(Ending.Harbor_Network)] =
		r.viable_settlements >= 2 && r.sustainable_settlements >= 2 && trade && accounted
	r.eligible[int(Ending.Nomadic_Fleet)] =
		active_ship_count(c) >= 6 &&
		essential &&
		stable &&
		c.material_economy.fleet.maintenance_debt == 0 &&
		r.passage_objectives >= 2
	r.eligible[int(Ending.Federation)] =
		r.viable_settlements >= 2 &&
		r.sustainable_settlements >= 2 &&
		federated &&
		has_precedent(c, .Open_Archives) &&
		r.broken_promises == 0 &&
		stable
	r.eligible[int(Ending.Transformed)] =
		r.transformation_records >= 2 && accounted && stable && r.passage_objectives >= 1
	r.recommended = .Fragmented_Survival
	if r.eligible[int(Ending.Nomadic_Fleet)] do r.recommended = .Nomadic_Fleet
	if r.eligible[int(Ending.Transformed)] do r.recommended = .Transformed
	if r.eligible[int(Ending.New_Home)] do r.recommended = .New_Home
	if r.eligible[int(Ending.Harbor_Network)] do r.recommended = .Harbor_Network
	if r.eligible[int(Ending.Federation)] do r.recommended = .Federation
	if r.recommended == .Fragmented_Survival do r.unmet_summary = "No victory ending has complete sustainability, objective, and accountability evidence."
	return r
}

Control_View :: struct {
	allocation:                                                       i32,
	allocation_compute, allocation_manpower, allocation_materials:    i32,
	policy:                                                           Population_Policy,
	reserve_floor:                                                    i32,
	organization:                                                     Authority_Policy,
	commitments:                                                      i32,
	project_commitments, promise_commitments, obligation_commitments: i32,
	commitment_capacity:                                              i32,
}

Strategic_Invariants :: struct {
	valid:                                                          bool,
	reserves_valid, compute_valid, manpower_valid, materials_valid: bool,
}

strategic_invariants :: proc(c: ^Campaign) -> Strategic_Invariants {
	valid_capacity := proc(capacity: Capacity) -> bool {
		return(
			capacity.total >= 0 &&
			capacity.reserved >= 0 &&
			capacity.damaged >= 0 &&
			capacity.reserved <= capacity.total &&
			capacity.damaged <= capacity.total \
		)
	}
	r := Strategic_Invariants {
		reserves_valid  = c.material_economy.fleet.stock.supplies >= 0,
		compute_valid   = valid_capacity(c.capacities.compute),
		manpower_valid  = valid_capacity(c.capacities.manpower),
		materials_valid = valid_capacity(c.capacities.raw_materials),
	}
	r.valid = r.reserves_valid && r.compute_valid && r.manpower_valid && r.materials_valid
	return r
}

community_cohesion :: proc(c: ^Campaign) -> (effective, trust, divergence: i32) {
	population: i64; weighted: i64; low := i32(100); high := i32(0)
	for community in c.communities[:c.community_count] {if community.population <= 0 do continue; population += i64(community.population); weighted += i64(community.population) * i64(community.trust); low = min(low, community.trust); high = max(high, community.trust)}
	trust = c.strategic.cohesion; if population > 0 do trust = i32(weighted / population)
	divergence = population > 0 ? high - low : 0
	// Broad trust helps collective action; a deeply aggrieved minority remains a
	// constraint even when the population-weighted average looks healthy.
	modifier := (trust - 65) / 5 - divergence / 12
	effective = clamp(c.strategic.cohesion + modifier, 0, 100)
	return
}

strategic_state_view :: proc(c: ^Campaign) -> Strategic_State_View {
	compute := capacity_available(
		c.capacities.compute,
	); manpower := capacity_available(c.capacities.manpower); materials := capacity_available(c.capacities.raw_materials)
	available := compute + manpower + materials
	total :=
		c.capacities.compute.total + c.capacities.manpower.total + c.capacities.raw_materials.total
	information := Information_State.Known
	for event in c.events[:c.event_count] do if !event.account_exposed && (event.account_status == .Contradicted || event.account_status == .Withheld) {information = .Disputed; break}
	if information != .Disputed && !operational_role_available(c, .Archive) && !operational_role_available(c, .Survey) do information = .Unknown
	effective, trust, divergence := community_cohesion(c)
	return {
		reserves = fleet_supply(c),
		reserve_floor = i32(fleet_operating_floor(c).stock.supplies),
		capacity_available = available,
		capacity_total = total,
		compute_available = compute,
		compute_total = c.capacities.compute.total,
		manpower_available = manpower,
		manpower_total = c.capacities.manpower.total,
		materials_available = materials,
		materials_total = c.capacities.raw_materials.total,
		cohesion = effective,
		cohesion_baseline = c.strategic.cohesion,
		community_trust = trust,
		community_divergence = divergence,
		information = information,
	}
}

control_view :: proc(c: ^Campaign) -> Control_View {
	projects, promises, obligations: i32
	for project in c.projects do if project.active do projects += 1
	for promise in c.promises[:c.promise_count] do if promise.status == .Active do promises += 1
	for obligation in c.obligations.items[:c.obligations.count] do if obligation_active(obligation) do obligations += 1
	state := strategic_state_view(c)
	return {
		allocation = max(state.capacity_total - state.capacity_available, 0),
		allocation_compute = max(state.compute_total - state.compute_available, 0),
		allocation_manpower = max(state.manpower_total - state.manpower_available, 0),
		allocation_materials = max(state.materials_total - state.materials_available, 0),
		policy = c.material_economy.population_policy,
		reserve_floor = state.reserve_floor,
		organization = c.material_economy.allocation_control,
		commitments = projects + promises + obligations,
		project_commitments = projects,
		promise_commitments = promises,
		obligation_commitments = obligations,
		commitment_capacity = c.obligations.reserved_compute +
		c.obligations.reserved_manpower +
		c.obligations.reserved_raw_materials,
	}
}
