package game

import "core:fmt"
import "core:testing"

capacity_available :: proc(capacity: Capacity) -> i32 {return max(
		capacity.total - capacity.reserved - capacity.damaged,
		0,
	)}
capacity_state :: proc(capacity: Capacity) -> string {available := capacity_available(capacity)
	if available <= 0 do return "UNAVAILABLE"
	if available * 3 <= max(capacity.total, 1) do return "STRAINED"
	return "AVAILABLE"}

interaction_capacity_source :: proc(
	c: ^Campaign,
	kind: Capacity_Kind,
	excluded: []Ship_ID = {},
) -> Ship_ID {
	for ship in c.ships[:c.ship_count] {if !ship.active do continue; skip := false; for id in excluded do if id == ship.id do skip = true; if skip do continue; switch kind {case .Compute:
			if ship.role == .Archive || ship.role == .Survey do return ship.id; case .Manpower:
			if ship.role == .Hospital || ship.role == .Habitat do return ship.id; case .Raw_Materials:
			if ship.role == .Foundry do return ship.id}}
	return 0
}

refresh_capacity_state :: proc(c: ^Campaign) {
	compute_loss, manpower_loss, material_loss: i32
	for ship in c.ships[:c.ship_count] {
		if !ship.active {manpower_loss += max(ship.crew / 250, 1); if ship.role == .Archive || ship.role == .Survey do compute_loss += 2; if ship.role == .Foundry || ship.role == .Agriculture || ship.role == .Habitat || ship.role == .Colony do material_loss += 2; continue}
		if ship.damage >
		   0 {manpower_loss += ship.damage / 3; if ship.role == .Archive || ship.role == .Survey do compute_loss += ship.damage / 2; if ship.role == .Foundry do material_loss += ship.damage / 2}
	}
	c.capacities.compute.damaged = clamp(compute_loss, 0, c.capacities.compute.total)
	c.capacities.manpower.damaged = clamp(manpower_loss, 0, c.capacities.manpower.total)
	c.capacities.raw_materials.damaged = clamp(material_loss, 0, c.capacities.raw_materials.total)
}

interaction_bond_strength :: proc(c: ^Campaign, a, b: Ship_ID) -> i32 {
	i := ship_relationship_index(
		c,
		a,
		b,
	); if i < 0 do return 0; return c.ship_relationships[i].strength
}

interaction_change_bond :: proc(c: ^Campaign, a, b: Ship_ID, change: i32, cause: u64) -> bool {
	i := ship_relationship_index(c, a, b)
	if i <
	   0 {if c.ship_relationship_count >= MAX_SHIP_RELATIONSHIPS do return false; i = c.ship_relationship_count; c.ship_relationship_count += 1; lo, hi := a, b; if lo > hi do lo, hi = hi, lo; c.ship_relationships[i] = {
			ship_a        = lo,
			ship_b        = hi,
			origin_event  = cause,
			semantic_tags = make_semantic_tags(.Relationship, .Ship),
		}}
	c.ship_relationships[i].strength = clamp(
		c.ship_relationships[i].strength + change,
		-3,
		3,
	); c.ship_relationships[i].last_event = cause; return true
}

situation_kind_recent :: proc(c: ^Campaign, kind: Situation_Kind) -> bool {
	seen := 0
	for i := c.event_count - 1; i >= 0 && seen < 12; i -= 1 {
		e := c.events[i]
		if e.kind == .Situation_Decided {seen += 1; if e.value == i32(kind) do return true}
	}
	return false
}

interaction_origin_used :: proc(c: ^Campaign, origin: u64) -> bool {
	if origin == 0 do return false
	for event in c.events[:c.event_count] do if event.kind == .Situation_Proposed && event.cause_sequence == origin do return true
	return false
}

latest_ship_event :: proc(c: ^Campaign, ship: Ship_ID) -> u64 {
	i := ship_index(c, ship); if i < 0 do return 0
	s := &c.ships[i]; if s.memory_count > 0 do return s.memories[s.memory_count - 1].event_sequence
	return 0
}

make_repair_debt_situation :: proc(c: ^Campaign) -> (Fleet_Situation, bool) {
	damaged := -1
	for ship, i in c.ships[:c.ship_count] do if ship.active && ship.damage > 0 && (damaged < 0 || ship.damage > c.ships[damaged].damage) do damaged = i
	if damaged < 0 do return {}, false
	benefactor := -1; best := i32(-99)
	for ship, i in c.ships[:c.ship_count] {
		if i == damaged || !ship.active do continue
		bond := interaction_bond_strength(c, c.ships[damaged].id, ship.id)
		if bond > best {best = bond; benefactor = i}
	}
	if benefactor < 0 do return {}, false
	a := c.ships[damaged]; b := c.ships[benefactor]; origin := latest_ship_event(c, a.id)
	if origin == 0 do return {}, false
	s := Fleet_Situation {
		id                 = c.next_situation_id + 1,
		kind               = .Repair_Debt,
		phase              = .Proposal,
		initiator          = a.id,
		affected_community = a.community,
		origin_event       = origin,
		title              = "A repair owed",
		proposal           = fmt.tprintf(
			"%s can restore %s, but the work will delay its own maintenance.",
			b.name,
			a.name,
		),
		stakes             = fmt.tprintf(
			"%s carries recorded damage. Repair capacity will be unavailable elsewhere.",
			a.name,
		),
		dramatic_score     = i32(8 + abs(best)),
	}
	s.positions[0] = {
		ship         = a.id,
		position     = .Support,
		reason_count = 1,
	}; s.positions[0].reasons[0] = {
		detail       = fmt.tprintf("%s's damage is already part of the record.", a.name),
		weight       = 3,
		source_event = origin,
	}
	s.positions[1] = {
		ship         = b.id,
		position     = best > 0 ? .Support : .Conditional,
		reason_count = 1,
	}; s.positions[1].reasons[0] = {
		detail       = best > 0 ? "Prior operations established a working bond." : "No prior bond establishes an obligation.",
		weight       = i32(max(best, 1)),
		source_event = origin,
	}; s.position_count = 2
	s.choices[0] = {
		label         = "Honor the repair debt",
		consequence   = fmt.tprintf(
			"A foundry ship reserves its fabrication lines; %s receives a complete repair and the ships strengthen their bond.",
			a.name,
		),
		effect        = .Full_Rescue,
		raw_materials = 4,
	}
	s.choices[1] = {
		label         = "Split the work",
		consequence   = fmt.tprintf(
			"The fleet schedules a bounded repair for %s without changing either ship's obligations.",
			a.name,
		),
		effect        = .Bounded_Rescue,
		raw_materials = 2,
	}
	s.choices[2] = {
		label        = "Preserve current capacity",
		consequence  = fmt.tprintf(
			"No capacity is committed. %s retains its damage and records the refusal.",
			a.name,
		),
		effect       = .Refuse_Rescue,
		irreversible = true,
	}; s.choice_count = 3
	return s, true
}

make_settlement_situation :: proc(c: ^Campaign) -> (Fleet_Situation, bool) {
	if !c.candidate_home_known || c.candidate_home_count <= 0 || !c.colony_package_ready || c.settlement_count >= MAX_SETTLEMENTS do return {}, false
	initiator := -1
	for ship, i in c.ships[:c.ship_count] do if ship.active && (ship.role == .Colony || ship.role == .Habitat) {initiator = i; break}
	if initiator < 0 do return {}, false
	ship := c.ships[initiator]; origin := latest_event_of_kind(c, .Expedition_Returned)
	s := Fleet_Situation {
		id                 = c.next_situation_id + 1,
		kind               = .Settlement,
		phase              = .Proposal,
		initiator          = ship.id,
		affected_community = ship.community,
		origin_event       = origin,
		title              = "A ship proposes a home",
		proposal           = fmt.tprintf(
			"%s proposes founding a settlement at the candidate world.",
			ship.name,
		),
		stakes             = "Ships that found the settlement permanently leave the traveling fleet.",
		dramatic_score     = 12,
		celestial          = c.candidate_homes[c.candidate_home_count - 1].reference,
	}
	responders := [3]Role{.Archive, .Hospital, .Habitat}; used := 0
	for role in responders {
		for candidate in c.ships[:c.ship_count] {
			if !candidate.active || candidate.id == ship.id || candidate.role != role || used >= MAX_SITUATION_POSITIONS do continue
			position :=
				Ship_Position_Kind.Conditional; reason := "Its participation depends on the founding terms."
			if role == .Archive do reason = "Its archives require an open record of the destination."
			if role ==
			   .Hospital {position = .Support; reason = "Its medical crews judge adaptation survivable with continuing care."}
			if role == .Habitat do reason = "It offers orbital refuge for residents who refuse alteration."
			s.positions[used] = {
				ship         = candidate.id,
				position     = position,
				reason_count = 1,
			}; s.positions[used].reasons[0] = {
				detail       = reason,
				weight       = 3,
				source_event = origin,
			}; used += 1; break
		}
	}
	s.position_count = used
	s.choices[0] = {
		label         = "Found under open terms",
		consequence   = "The founding ship departs under independent authority and an open environmental record.",
		effect        = .Found_Settlement,
		irreversible  = true,
		compute       = 2,
		manpower      = 3,
		raw_materials = 3,
	}
	s.choices[1] = {
		label         = "Add orbital refuge",
		consequence   = "A habitat commitment preserves civilian mobility while the surface settlement begins.",
		effect        = .Amend_Settlement,
		irreversible  = true,
		compute       = 2,
		manpower      = 4,
		raw_materials = 4,
	}
	s.choices[2] = {
		label       = "Wait for review",
		consequence = "Archive and survey ships reserve compute; a later founding gains an independently reviewed viability forecast.",
		effect      = .Delay,
		compute     = 4,
	}
	s.choices[3] = {
		label       = "Continue the search",
		consequence = "No ship departs and the candidate remains in the record.",
		effect      = .Decline,
	}; s.choice_count = 4
	return s, true
}

make_rescue_situation :: proc(c: ^Campaign) -> (Fleet_Situation, bool) {
	for hook in c.history_hooks[:c.history_hook_count] {
		if hook.kind != .Broken_Procession || hook.stage == .Consequence do continue
		si := ship_index(
			c,
			hook.ship,
		); ci := community_index(c, hook.community); if si < 0 || ci < 0 do continue
		s := Fleet_Situation {
			id                 = c.next_situation_id + 1,
			kind               = .Rescue,
			phase              = .Proposal,
			initiator          = hook.ship,
			affected_community = hook.community,
			origin_event       = hook.origin_event,
			title              = "The berths remain occupied",
			proposal           = fmt.tprintf(
				"%s asks the fleet to continue sheltering the %s.",
				c.ships[si].name,
				c.communities[ci].name,
			),
			stakes             = "Full care commits named ships through the next season.",
			dramatic_score     = 10,
			value              = .No_One_Left_Behind,
			law_domain         = .Rescue,
		}
		s.positions[0] = {
			ship         = hook.ship,
			position     = .Support,
			reason_count = 1,
		}; s.positions[0].reasons[0] = {
			detail       = "The ship accepted sponsorship when the survivors came aboard.",
			weight       = 4,
			source_event = hook.origin_event,
		}; s.position_count = 1
		s.choices[0] = {
			label       = "Continue full care",
			consequence = "Hospital and habitat ships remain committed through the next season; the sponsorship bond strengthens.",
			effect      = .Full_Rescue,
			manpower    = 4,
		}
		s.choices[1] = {
			label       = "Promise a later transfer",
			consequence = "A smaller care team remains assigned and a public promise comes due next season.",
			effect      = .Promise_Return,
			manpower    = 2,
		}
		s.choices[2] = {
			label        = "End fleet support",
			consequence  = "The sponsoring ship and community record an unanswered obligation.",
			effect       = .Refuse_Rescue,
			irreversible = true,
		}; s.choice_count = 3
		return s, true
	}
	return {}, false
}

make_evidence_situation :: proc(c: ^Campaign) -> (Fleet_Situation, bool) {
	for i := c.event_count - 1; i >= 0; i -= 1 {
		e := c.events[i]; if e.account_status == .Uncontested || e.account_exposed do continue
		ship :=
			e.ship_id; if ship == 0 {for candidate in c.ships[:c.ship_count] do if candidate.active {ship = candidate.id; break}}
		s := Fleet_Situation {
			id                 = c.next_situation_id + 1,
			kind               = .Contested_Evidence,
			phase              = .Proposal,
			initiator          = ship,
			affected_community = e.community,
			origin_event       = e.sequence,
			title              = "Two records of the same return",
			proposal           = e.detail,
			stakes             = "Later ship decisions will use the account the fleet permits them to know.",
			dramatic_score     = 9,
			value              = .Truth_Before_Comfort,
			law_domain         = .Disclosure,
		}
		s.positions[0] = {
			ship         = ship,
			position     = .Conditional,
			reason_count = 1,
		}; s.positions[0].reasons[0] = {
			detail       = fmt.tprintf("The disagreement originates in E%03d.", e.sequence),
			weight       = 3,
			source_event = e.sequence,
		}; s.position_count = 1
		s.choices[0] = {
			label        = "Publish both records",
			consequence  = "Every ship receives the authoritative report and its contradiction.",
			effect       = .Publish_Evidence,
			irreversible = true,
		}
		s.choices[1] = {
			label       = "Commission an open review",
			consequence = "Archive and survey ships reserve their analysis capacity before publication.",
			effect      = .Review_Evidence,
			compute     = 3,
		}
		s.choices[2] = {
			label        = "Restrict the evidence",
			consequence  = "Affected ships receive the evidence under a recorded restriction.",
			effect       = .Restricted_Disclosure,
			irreversible = true,
		}; s.choice_count = 3
		return s, true
	}
	return {}, false
}

surface_interaction :: proc(c: ^Campaign) -> bool {
	if c.current_situation.phase != .None && c.current_situation.phase != .Resolved do return false
	untested_value_due :=
		false; if c.season >= 10 do for value in c.values do if value.tests == 0 {untested_value_due = true; break}
	if !major_story_beat_ready(c) && !untested_value_due do return false
	candidates: [6]Fleet_Situation; count := 0
	if s, ok := make_repair_debt_situation(c);
	   ok &&
	   !interaction_origin_used(c, s.origin_event) &&
	   !situation_kind_recent(c, s.kind) {candidates[count] = s; count += 1}
	if s, ok := make_settlement_situation(c);
	   ok &&
	   !interaction_origin_used(c, s.origin_event) &&
	   !situation_kind_recent(c, s.kind) {candidates[count] = s; count += 1}
	if s, ok := make_rescue_situation(c);
	   ok &&
	   !interaction_origin_used(c, s.origin_event) &&
	   !situation_kind_recent(c, s.kind) {candidates[count] = s; count += 1}
	if s, ok := make_evidence_situation(c);
	   ok &&
	   !interaction_origin_used(c, s.origin_event) &&
	   !situation_kind_recent(c, s.kind) {candidates[count] = s; count += 1}
	if count == 0 || c.season >= 3 do for slot in 0 ..< len(c.values) {
		if s, ok := make_value_hard_case(c, slot); ok && !situation_kind_recent(c, s.kind) {candidates[count] = s; count += 1}
	}
	if count == 0 do return false
	best_score := i32(-1000); best_indices: [6]int; best_count := 0
	for candidate, i in candidates[:count] {if situation_kind_recent(c, candidate.kind) do continue
		score := candidate.dramatic_score
		if score >
		   best_score {best_score = score; best_count = 1; best_indices[0] = i} else if score == best_score {best_indices[best_count] = i; best_count += 1}}
	if best_count == 0 do return false
	chosen := best_indices[0]; best_rank := u64(0)
	for candidate_index in best_indices[:best_count] {
		candidate := candidates[candidate_index]
		stable_id := narrative_mix(
			u64(candidate.kind) << 56 ~ candidate.origin_event ~ u64(candidate.initiator),
		)
		rank := narrative_rank(c, .Fleet_Interaction, stable_id, u64(c.next_situation_id + 1))
		if rank > best_rank {chosen = candidate_index; best_rank = rank}
	}
	c.current_situation = candidates[chosen]; c.next_situation_id += 1
	record_event(
		c,
		.Situation_Proposed,
		c.current_situation.proposal,
		c.current_situation.initiator,
		i32(c.current_situation.kind),
		c.current_situation.affected_community,
		c.current_situation.origin_event,
	)
	c.current_situation.proposal_event = c.event_sequence
	mark_major_story_beat(c)
	return true
}


