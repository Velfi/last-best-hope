package game

import "core:fmt"

Front_Kind :: enum {
	Closed_Cycle_Ecology,
	Fleet_Authority,
	Passage_Access,
	Settlement_Obligation,
}
Front_Stage :: enum {
	Proposed,
	Emerging,
	Escalating,
	Recovering,
	Transformed,
	Resolved,
}
Front_Transformation :: enum {
	None,
	Shared_Ownership,
	Distributed_Cost,
	Broadened_Constituency,
	Revised_Doctrine,
	Damaged_Institution,
	Constrained_Route,
	Continuing_Obligation,
	Changed_Authority,
}

Historical_Front :: struct {
	id:                                        u32,
	kind:                                      Front_Kind,
	stage:                                     Front_Stage,
	pressure:                                  i32,
	involved_ships:                            [3]Ship_ID,
	involved_ship_count:                       int,
	involved_communities:                      [3]Community_ID,
	involved_community_count:                  int,
	originating_events:                        [MAX_EVENT_CAUSES]u64,
	originating_event_count:                   int,
	last_change_event:                         u64,
	last_change_season:                        i32,
	dormant:                                   bool,
	transformation:                            Front_Transformation,
	name, last_public_record, known_next_risk: string,
	semantic_tags:                             Semantic_Tags,
}

Historical_Front_Proposal :: struct {
	kind:             Front_Kind,
	source_event:     u64,
	credibility:      i32,
	name, known_risk: string,
	semantic_tags:    Semantic_Tags,
}

Front_Telemetry :: struct {
	active, dormant, queued: int,
	highest_pressure:        i32,
	last_beat_season:        i32,
}
Front_Family_Coverage :: struct {
	stage_count, transformation_count, role_solution_count, passage_interaction_count: int,
	dormant_callback:                                                                  bool,
}

front_family_transformations :: proc(kind: Front_Kind) -> [3]Front_Transformation {switch
	kind {case .Closed_Cycle_Ecology:
		return {
			.Distributed_Cost,
			.Broadened_Constituency,
			.Revised_Doctrine,
		}; case .Fleet_Authority:
		return {.Shared_Ownership, .Changed_Authority, .Damaged_Institution}; case .Passage_Access:
		return {
			.Shared_Ownership,
			.Constrained_Route,
			.Continuing_Obligation,
		}; case .Settlement_Obligation:
		return{.Broadened_Constituency, .Continuing_Obligation, .Changed_Authority}}
	return{}}

front_role_solution :: proc(kind: Front_Kind, role: Role) -> Front_Transformation {
	switch kind {
	case .Closed_Cycle_Ecology:
		#partial switch role {case .Agriculture, .Hospital, .Habitat:
			return .Broadened_Constituency; case .Foundry, .Colony:
			return .Distributed_Cost; case:
			return .Revised_Doctrine}
	case .Fleet_Authority:
		#partial switch role {case .Escort, .Survey:
			return .Changed_Authority; case .Archive, .Habitat:
			return .Shared_Ownership; case:
			return .Damaged_Institution}
	case .Passage_Access:
		#partial switch role {case .Survey, .Escort:
			return .Constrained_Route; case .Hospital, .Colony:
			return .Continuing_Obligation; case:
			return .Shared_Ownership}
	case .Settlement_Obligation:
		#partial switch role {case .Colony, .Habitat, .Agriculture:
			return .Broadened_Constituency; case .Archive, .Hospital:
			return .Continuing_Obligation; case:
			return .Changed_Authority}
	}
	return .None
}

front_family_coverage :: proc(kind: Front_Kind) -> Front_Family_Coverage {roles := 0; for role in Role do if front_role_solution(kind, role) != .None do roles += 1
	return{
		stage_count = 6,
		transformation_count = 3,
		role_solution_count = roles,
		passage_interaction_count = 1,
		dormant_callback = true,
	}}
front_transformation_record :: proc(value: Front_Transformation) -> string {switch
	value {case .Shared_Ownership:
		return "ownership was shared"; case .Distributed_Cost:
		return "the cost was distributed"; case .Broadened_Constituency:
		return "the represented constituency widened"; case .Revised_Doctrine:
		return "the operating doctrine changed"; case .Damaged_Institution:
		return "the responsible institution remained damaged"; case .Constrained_Route:
		return "the route remained constrained"; case .Continuing_Obligation:
		return "a continuing obligation was recorded"; case .Changed_Authority:
		return "authority passed under new terms"; case .None:
		return "no transformation was recorded"}
	return "no transformation was recorded"}

front_family_text :: proc(kind: Front_Kind) -> (string, string) {
	switch kind {
	case .Closed_Cycle_Ecology:
		return "Closed-cycle food ecology",
			"Another failed harvest will constrain fleet sustenance."
	case .Fleet_Authority:
		return "Contested fleet authority",
			"An unresolved command dispute may change who can bind the fleet."
	case .Passage_Access:
		return "Passage access compact", "The route authority may restrict the next crossing."
	case .Settlement_Obligation:
		return "Settlement independence",
			"A settlement may demand a new account of continuing obligations."
	}
	return "Unrecorded pressure", "The next consequence is not yet established."
}

front_source_for_kind :: proc(c: ^Campaign, kind: Front_Kind) -> u64 {
	for i := c.event_count - 1; i >= 0; i -= 1 {e := c.events[i]
		switch kind {
		case .Closed_Cycle_Ecology:
			if e.kind == .Fleet_Hazard || e.kind == .Need_Surfaced && semantic_has(e.semantic_tags, .Survival) do return e.sequence
		case .Fleet_Authority:
			if e.kind == .Precedent_Enacted || e.kind == .Jurisdiction_Changed || e.kind == .Constitutional_Emergency do return e.sequence
		case .Passage_Access:
			if semantic_has(e.semantic_tags, .Passage) && e.kind != .Front_Proposed do return e.sequence
		case .Settlement_Obligation:
			if e.settlement_id != 0 || e.kind == .Promise_Changed do return e.sequence
		}
	}
	if c.event_count > 0 do return c.events[0].sequence
	return 0
}

seed_front_families :: proc(c: ^Campaign) {
	if c.next_front_id == 0 do c.next_front_id = 1
	for kind in Front_Kind {
		if c.future_front_count >= MAX_FUTURE_FRONTS do break
		name, risk := front_family_text(kind); source := front_source_for_kind(c, kind)
		c.future_fronts[c.future_front_count] = {
			kind          = kind,
			source_event  = source,
			credibility   = i32(3 + int(kind)),
			name          = name,
			known_risk    = risk,
			semantic_tags = make_semantic_tags(.Governance, .Causality),
		}
		c.future_front_count += 1
	}
}

activate_front_proposal :: proc(c: ^Campaign, index: int) -> bool {
	if index < 0 || index >= c.future_front_count || c.front_count >= MAX_ACTIVE_FRONTS do return false
	p := c.future_fronts[index]; f := &c.fronts[c.front_count]
	f^ = {
		id                      = c.next_front_id,
		kind                    = p.kind,
		stage                   = .Emerging,
		pressure                = 2,
		originating_event_count = 1,
		last_change_season      = c.season,
		name                    = p.name,
		known_next_risk         = p.known_risk,
		semantic_tags           = semantic_add(p.semantic_tags, .Entity, .Event),
	}
	f.originating_events[0] = p.source_event
	record_event(
		c,
		.Front_Proposed,
		fmt.tprintf("%s entered the public record.", p.name),
		cause_sequence = p.source_event,
	)
	f.last_change_event =
		c.event_sequence; f.last_public_record = c.events[c.event_count - 1].detail
	c.next_front_id += 1; c.front_count += 1
	for i in index ..< c.future_front_count - 1 do c.future_fronts[i] = c.future_fronts[i + 1]
	c.future_front_count -= 1
	return true
}

preserve_low_pressure_front :: proc(c: ^Campaign, index: int, shared_event: u64) -> bool {
	if index < 0 || index >= c.future_front_count || c.front_count >= MAX_ACTIVE_FRONTS || shared_event == 0 do return false
	p :=
		c.future_fronts[index]; f := &c.fronts[c.front_count]; transformations := front_family_transformations(p.kind)
	f^ = {
		id                      = c.next_front_id,
		kind                    = p.kind,
		stage                   = .Transformed,
		pressure                = 1,
		originating_event_count = 1,
		last_change_event       = shared_event,
		last_change_season      = c.season,
		dormant                 = true,
		transformation          = transformations[0],
		name                    = p.name,
		known_next_risk         = p.known_risk,
		last_public_record      = fmt.tprintf(
			"%s remained in the historical docket under %s.",
			p.name,
			front_transformation_record(transformations[0]),
		),
		semantic_tags           = semantic_add(p.semantic_tags, .Entity, .Event),
	}
	f.originating_events[0] =
		p.source_event; c.next_front_id += 1; c.front_count += 1; for i in index ..< c.future_front_count - 1 do c.future_fronts[i] = c.future_fronts[i + 1]; c.future_front_count -= 1; return true
}

advance_historical_fronts :: proc(c: ^Campaign) -> bool {
	if !major_story_beat_ready(c) do return false
	if c.future_front_count == 0 && c.front_count == 0 do seed_front_families(c)
	candidates: [MAX_NARRATIVE_CANDIDATES]Narrative_Candidate
	count := collect_historical_front_candidates(c, candidates[:])
	if count == 0 do return false
	selected, ok := narrative_select_candidate(c, candidates[:count]); if !ok do return false
	if !surface_historical_front_candidate(c, selected) do return false
	narrative_record_selection(c, selected, candidates[:count])
	return true
}

collect_historical_front_candidates :: proc(c: ^Campaign, out: []Narrative_Candidate) -> int {
	count := 0
	for f, i in c.fronts[:c.front_count] do if f.dormant {
		source := front_source_for_kind(c, f.kind); if source == 0 do continue
		if count >= len(out) do return count
		out[count] = {
			domain       = .Historical_Front,
			priority     = .Urgent,
			source_kind  = .Front_Return,
			stable_id    = narrative_mix(0x8200000000000000 ~ u64(f.id)),
			source_event = source,
			urgency      = 40 + max(c.season - f.last_change_season, 0),
			source_index = i,
		}
		count += 1
	}
	if count > 0 do return count
	if c.front_count < MAX_ACTIVE_FRONTS {
		for proposal, i in c.future_fronts[:c.future_front_count] {
			if count >= len(out) do return count
			out[count] = {
				domain        = .Historical_Front,
				priority      = .Developing,
				source_kind   = .Front_Proposal,
				stable_id     = narrative_mix(
					0x8300000000000000 ~ u64(proposal.kind) ~ proposal.source_event,
				),
				source_event  = proposal.source_event,
				urgency       = proposal.credibility * 5,
				source_index  = i,
				semantic_tags = proposal.semantic_tags,
			}
			count += 1
		}
	}
	if count > 0 do return count
	for f, i in c.fronts[:c.front_count] do if !f.dormant && f.last_change_season != c.season {
		source := front_source_for_kind(c, f.kind); if source == 0 do continue
		if count >= len(out) do return count
		out[count] = {
			domain       = .Historical_Front,
			priority     = .Discretionary,
			source_kind  = .Front_Advance,
			stable_id    = narrative_mix(0x8400000000000000 ~ u64(f.id)),
			source_event = source,
			urgency      = f.pressure * 8,
			source_index = i,
		}
		count += 1
	}
	return count
}

surface_historical_front_candidate :: proc(c: ^Campaign, candidate: Narrative_Candidate) -> bool {
	#partial switch candidate.source_kind {
	case .Front_Return:
		if candidate.source_index < 0 || candidate.source_index >= c.front_count do return false
		f := &c.fronts[candidate.source_index]; if !f.dormant do return false
		source := front_source_for_kind(c, f.kind); if source == 0 do return false
		f.dormant = false; f.stage = .Recovering; f.pressure = max(f.pressure, 2)
		record_event(
			c,
			.Front_Returned,
			fmt.tprintf("The council reopened %s after event %d.", f.name, source),
			cause_sequence = source,
		)
		f.last_change_event =
			c.event_sequence; f.last_change_season = c.season; f.last_public_record = c.events[c.event_count - 1].detail
	case .Front_Proposal:
		if !activate_front_proposal(c, candidate.source_index) do return false
		if c.front_count < 2 && c.future_front_count > 0 {
			remaining: [MAX_NARRATIVE_CANDIDATES]Narrative_Candidate
			remaining_count := collect_historical_front_candidates(c, remaining[:])
			if remaining_count > 0 {
				low, ok := narrative_select_candidate(c, remaining[:remaining_count])
				if ok && low.source_kind == .Front_Proposal do _ = preserve_low_pressure_front(c, low.source_index, c.fronts[c.front_count - 1].last_change_event)
			}
		}
	case .Front_Advance:
		if candidate.source_index < 0 || candidate.source_index >= c.front_count do return false
		f := &c.fronts[candidate.source_index]; if f.dormant || f.last_change_season == c.season do return false
		source := front_source_for_kind(c, f.kind); if source == 0 do return false
		f.pressure = min(f.pressure + 1, 10); f.stage = .Escalating
		record_event(
			c,
			.Front_Advanced,
			fmt.tprintf("%s reached pressure %d.", f.name, f.pressure),
			value = f.pressure,
			cause_sequence = source,
		)
		f.last_change_event =
			c.event_sequence; f.last_change_season = c.season; f.last_public_record = c.events[c.event_count - 1].detail
	case:
		return false
	}
	c.last_front_beat_season = c.season
	mark_major_story_beat(c)
	return true
}

transform_front :: proc(
	c: ^Campaign,
	id: u32,
	transformation: Front_Transformation,
	source_event: u64,
) -> bool {
	for &f in c.fronts[:c.front_count] do if f.id == id {
		if transformation == .None || source_event == 0 || event_index_by_sequence(c, source_event) < 0 do return false
		f.transformation = transformation; f.stage = .Transformed; f.pressure = max(f.pressure - 2, 0)
		switch transformation {case .Shared_Ownership:
			if c.institutions[0].active do c.institutions[0].legitimacy = min(c.institutions[0].legitimacy + 2, 100); case .Distributed_Cost:
			_ = fleet_stock_spend(c, {supplies = 3}, .Emergency); c.strategic.cohesion = min(c.strategic.cohesion + 2, 100); case .Broadened_Constituency:
			if c.community_count > 0 {c.communities[0].trust = min(c.communities[0].trust + 3, 100); c.communities[0].grievance = max(c.communities[0].grievance - 1, 0)}; case .Revised_Doctrine:
			_ = spend_knowledge(c, min(c.material_economy.knowledge.deployable_capacity, 2), .Front_Transformation); fleet_stock_gain(c, {supplies = 3}, .Reward); case .Damaged_Institution:
			if c.institutions[0].active do c.institutions[0].legitimacy = max(c.institutions[0].legitimacy - 8, 0); case .Constrained_Route:
			c.strategic.cohesion = max(c.strategic.cohesion - 1, 0); case .Continuing_Obligation:
			c.strategic.cohesion = max(c.strategic.cohesion - 2, 0); case .Changed_Authority:
			if c.institutions[1].active do c.institutions[1].legitimacy = min(c.institutions[1].legitimacy + 4, 100); case .None:}
		#partial switch transformation {case .Damaged_Institution:
			f.known_next_risk = "The damaged institution may fail another public obligation."; case .Constrained_Route:
			f.known_next_risk = "The constrained route may close without new access terms."; case .Continuing_Obligation:
			f.known_next_risk = "The obligation will return with the next settlement report."; case .Changed_Authority:
			f.known_next_risk = "The new authority will be tested by the next command dispute."; case:
			f.known_next_risk = "The successor arrangement will be tested by later conduct."}
		apply_front_material_change(c, f.kind, transformation)
		record_event(c, .Front_Transformed, fmt.tprintf("%s: %s.", f.name, front_transformation_record(transformation)), value = i32(transformation), cause_sequence = source_event)
		f.last_change_event = c.event_sequence; f.last_change_season = c.season; f.last_public_record = c.events[c.event_count - 1].detail
		return true
	}
	return false
}

set_front_dormant :: proc(c: ^Campaign, id: u32, source_event: u64) -> bool {for &f in c.fronts[:c.front_count] do if f.id == id && !f.dormant && source_event != 0 {f.dormant = true; f.stage = .Recovering; record_event(c, .Front_Dormant, fmt.tprintf("The council removed %s from the active docket after event %d.", f.name, source_event), cause_sequence = source_event); f.last_change_event = c.event_sequence; f.last_change_season = c.season; f.last_public_record = c.events[c.event_count - 1].detail; return true}
	return false}

front_telemetry :: proc(c: ^Campaign) -> Front_Telemetry {r := Front_Telemetry {
		queued           = c.future_front_count,
		last_beat_season = c.last_front_beat_season,
	}; for f in c.fronts[:c.front_count] {if f.dormant {r.dormant += 1} else {r.active += 1}; r.highest_pressure = max(r.highest_pressure, f.pressure)}; return r}
