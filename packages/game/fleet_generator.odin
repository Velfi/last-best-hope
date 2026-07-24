package game

import "core:testing"

// Fleet_Goals are relative priorities, not percentages. Values are clamped to
// 0..100, so callers can expose them directly as sliders or use small weights.
Fleet_Goals :: struct {
	survival:     i32,
	exploration:  i32,
	settlement:   i32,
	industry:     i32,
	preservation: i32,
	security:     i32,
}

balanced_fleet_goals :: proc() -> Fleet_Goals {
	return {
		survival = 60,
		exploration = 45,
		settlement = 45,
		industry = 50,
		preservation = 40,
		security = 40,
	}
}

fleet_goal_value :: proc(value: i32) -> i32 {return clamp(value, 0, 100)}

fleet_role_score :: proc(role: Role, goals: Fleet_Goals) -> i32 {
	survival := fleet_goal_value(goals.survival)
	exploration := fleet_goal_value(goals.exploration)
	settlement := fleet_goal_value(goals.settlement)
	industry := fleet_goal_value(goals.industry)
	preservation := fleet_goal_value(goals.preservation)
	security := fleet_goal_value(goals.security)
	switch role {
	case .Habitat:
		return survival * 3 + settlement * 2 + preservation
	case .Agriculture:
		return survival * 4 + settlement * 2
	case .Foundry:
		return industry * 4 + survival + security
	case .Archive:
		return preservation * 4 + exploration * 2
	case .Hospital:
		return survival * 4 + preservation + settlement
	case .Survey:
		return exploration * 5 + settlement
	case .Escort:
		return security * 5 + survival
	case .Colony:
		return settlement * 5 + survival + industry
	}
	return 0
}

fleet_role_base_power :: proc(role: Role) -> i32 {
	switch role {
	case .Habitat:
		return 7
	case .Agriculture:
		return 7
	case .Foundry:
		return 9
	case .Archive:
		return 6
	case .Hospital:
		return 7
	case .Survey:
		return 8
	case .Escort:
		return 10
	case .Colony:
		return 8
	}
	return 7
}

fleet_role_base_crew :: proc(role: Role) -> i32 {
	switch role {
	case .Habitat:
		return 520
	case .Agriculture:
		return 390
	case .Foundry:
		return 340
	case .Archive:
		return 180
	case .Hospital:
		return 310
	case .Survey:
		return 150
	case .Escort:
		return 230
	case .Colony:
		return 460
	}
	return 250
}

fleet_generator_next :: proc(state: ^u64) -> u64 {
	x := state^
	x ~= x << u64(13)
	x ~= x >> u64(7)
	x ~= x << u64(17)
	if x == 0 do x = 1
	state^ = x
	return x
}

fleet_role_count :: proc(roles: ^[MAX_SHIPS]Role, used: int, role: Role) -> int {
	count := 0
	for i in 0 ..< used do if roles[i] == role do count += 1
	return count
}

fleet_hull_role_weight :: proc(role: Role, hull_class: Hull_Class) -> i32 {
	switch role {
	case .Habitat:
		#partial switch hull_class {case .Fleet_Ship:
			return 20; case .Cruiser:
			return 55; case .Capital_Ship:
			return 25}
	case .Agriculture:
		#partial switch hull_class {case .Fleet_Ship:
			return 75; case .Cruiser:
			return 25}
	case .Foundry:
		#partial switch hull_class {case .Fleet_Ship:
			return 60; case .Cruiser:
			return 35; case .Capital_Ship:
			return 5}
	case .Archive:
		#partial switch hull_class {case .Corvette:
			return 65; case .Fleet_Ship:
			return 30; case .Cruiser:
			return 5}
	case .Hospital:
		#partial switch hull_class {case .Fleet_Ship:
			return 70; case .Cruiser:
			return 30}
	case .Survey:
		#partial switch hull_class {case .Strike_Craft:
			return 35; case .Corvette:
			return 50; case .Fleet_Ship:
			return 15}
	case .Escort:
		#partial switch hull_class {case .Strike_Craft:
			return 40; case .Corvette:
			return 45; case .Cruiser:
			return 15}
	case .Colony:
		#partial switch hull_class {case .Cruiser:
			return 45; case .Capital_Ship:
			return 55}
	}
	return 0
}

fleet_hull_class_for_role :: proc(state: ^u64, role: Role, counts: ^[5]int) -> Hull_Class {
	classes := [5]Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	best := Hull_Class.Fleet_Ship
	best_score := i32(-1)
	for hull_class, index in classes {
		weight := fleet_hull_role_weight(role, hull_class)
		if weight == 0 || counts[index] >= 6 do continue
		// Preserve the role-authentic base distribution while making another
		// copy of an already common scale progressively less attractive.
		score :=
			weight * 100 / i32(100 + counts[index] * 80) + i32(fleet_generator_next(state) % 9)
		if counts[index] == 0 do score += 100
		if score > best_score {best_score = score; best = hull_class}
	}
	return best
}

fleet_hull_match_class :: proc(
	class_index: int,
	roles: ^[MAX_SHIPS]Role,
	ship_orders: ^[5][MAX_SHIPS]int,
	matched_class_for_ship: ^[MAX_SHIPS]int,
	visited: ^[MAX_SHIPS]bool,
) -> bool {
	classes := [5]Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	for order in 0 ..< MAX_SHIPS {
		ship_index := ship_orders[class_index][order]
		if visited[ship_index] || fleet_hull_role_weight(roles[ship_index], classes[class_index]) == 0 do continue
		visited[ship_index] = true
		prior_class := matched_class_for_ship[ship_index]
		if prior_class < 0 ||
		   fleet_hull_match_class(
			   prior_class,
			   roles,
			   ship_orders,
			   matched_class_for_ship,
			   visited,
		   ) {
			matched_class_for_ship[ship_index] = class_index
			return true
		}
	}
	return false
}

fleet_hull_classes :: proc(seed: u64, roles: [MAX_SHIPS]Role) -> [MAX_SHIPS]Hull_Class {
	classes := [5]Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	roster := roles
	state := ship_generator_stream(seed, 0x510e527fade682d1)
	ship_orders: [5][MAX_SHIPS]int
	for &order in ship_orders {
		for &ship_index, i in order do ship_index = i
		for i := MAX_SHIPS - 1; i > 0; i -= 1 {
			other := int(fleet_generator_next(&state) % u64(i + 1))
			order[i], order[other] = order[other], order[i]
		}
	}
	matched_class_for_ship: [MAX_SHIPS]int
	for &class_index in matched_class_for_ship do class_index = -1
	class_order := [5]int{0, 1, 2, 3, 4}
	for i := len(class_order) - 1; i > 0; i -= 1 {
		other := int(fleet_generator_next(&state) % u64(i + 1))
		class_order[i], class_order[other] = class_order[other], class_order[i]
	}
	for class_index in class_order {
		visited: [MAX_SHIPS]bool
		_ = fleet_hull_match_class(
			class_index,
			&roster,
			&ship_orders,
			&matched_class_for_ship,
			&visited,
		)
	}
	result: [MAX_SHIPS]Hull_Class
	counts: [5]int
	for class_index, ship_index in matched_class_for_ship {
		if class_index < 0 do continue
		result[ship_index] = classes[class_index]
		counts[class_index] += 1
	}
	for &hull_class, ship_index in result {
		if hull_class != .Unspecified do continue
		hull_class = fleet_hull_class_for_role(&state, roles[ship_index], &counts)
		counts[int(hull_class) - 1] += 1
	}
	return result
}

fleet_hull_class_coverage_capacity :: proc(roles: [MAX_SHIPS]Role) -> int {
	classes := fleet_hull_classes(1, roles)
	seen: [5]bool
	for hull_class in classes do seen[int(hull_class) - 1] = true
	count := 0
	for present in seen do if present do count += 1
	return count
}

fleet_trait_role_weight :: proc(role: Role, trait: Passage_Ship_Trait) -> i32 {
	weight := i32(20)
	switch role {
	case .Habitat:
		if trait == .Committed do weight += 30
		if trait == .Protective do weight += 25
	case .Agriculture:
		if trait == .Cautious do weight += 30
		if trait == .Committed do weight += 25
	case .Foundry:
		if trait == .Cautious do weight += 35
		if trait == .Committed do weight += 20
	case .Archive:
		if trait == .Curious do weight += 30
		if trait == .Cautious do weight += 25
	case .Hospital:
		if trait == .Protective do weight += 40
		if trait == .Cautious do weight += 20
	case .Survey:
		if trait == .Curious do weight += 40
		if trait == .Independent do weight += 20
	case .Escort:
		if trait == .Protective do weight += 40
		if trait == .Committed do weight += 20
	case .Colony:
		if trait == .Committed do weight += 30
		if trait == .Independent do weight += 25
	}
	return weight
}

fleet_trait_for_role :: proc(state: ^u64, role: Role, counts: ^[5]int) -> Passage_Ship_Trait {
	traits := GENERATED_SHIP_TRAITS
	best := Passage_Ship_Trait.Curious
	best_score := i32(-1)
	for trait, index in traits {
		if counts[index] >= 3 do continue
		weight := fleet_trait_role_weight(role, trait)
		score :=
			weight * 100 / i32(100 + counts[index] * 70) + i32(fleet_generator_next(state) % 11)
		if counts[index] == 0 do score += 100
		if score > best_score {best_score = score; best = trait}
	}
	return best
}

fleet_community_offsets_solve :: proc(
	role_index: int,
	role_totals: ^[8]int,
	community_counts: ^[INITIAL_COMMUNITIES]int,
	offsets, priorities: ^[8]int,
) -> bool {
	if role_index == 8 {
		for count in community_counts do if count != MAX_SHIPS / INITIAL_COMMUNITIES do return false
		return true
	}
	total := role_totals[role_index]
	if total == 0 do return fleet_community_offsets_solve(role_index + 1, role_totals, community_counts, offsets, priorities)
	for attempt in 0 ..< INITIAL_COMMUNITIES {
		offset := (priorities[role_index] + attempt) % INITIAL_COMMUNITIES
		valid := true
		for occurrence in 0 ..< total {
			community := (offset + occurrence) % INITIAL_COMMUNITIES
			if community_counts[community] >=
			   MAX_SHIPS / INITIAL_COMMUNITIES {valid = false; break}
		}
		if !valid do continue
		for occurrence in 0 ..< total do community_counts[(offset + occurrence) % INITIAL_COMMUNITIES] += 1
		offsets[role_index] = offset
		if fleet_community_offsets_solve(role_index + 1, role_totals, community_counts, offsets, priorities) do return true
		for occurrence in 0 ..< total do community_counts[(offset + occurrence) % INITIAL_COMMUNITIES] -= 1
	}
	return false
}

fleet_community_assignments :: proc(seed: u64, roles: [MAX_SHIPS]Role) -> [MAX_SHIPS]Community_ID {
	role_totals: [8]int
	for role in roles do role_totals[int(role)] += 1
	state := ship_generator_stream(seed, 0xa4093822299f31d0)
	priorities: [8]int
	for &priority in priorities do priority = int(fleet_generator_next(&state) % INITIAL_COMMUNITIES)
	offsets: [8]int
	community_counts: [INITIAL_COMMUNITIES]int
	solved := fleet_community_offsets_solve(
		0,
		&role_totals,
		&community_counts,
		&offsets,
		&priorities,
	)
	occurrences: [8]int
	assignments: [MAX_SHIPS]Community_ID
	if !solved {
		// Defensive fallback for future configurations that violate the current
		// role-capacity proof. Representation stays balanced and deterministic.
		for &community, i in assignments do community = Community_ID(i % INITIAL_COMMUNITIES + 1)
		return assignments
	}
	for role, i in roles {
		role_index := int(role)
		assignments[i] = Community_ID(
			(offsets[role_index] + occurrences[role_index]) % INITIAL_COMMUNITIES + 1,
		)
		occurrences[role_index] += 1
	}
	return assignments
}


