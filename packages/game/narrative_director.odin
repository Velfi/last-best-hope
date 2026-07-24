package game


MAX_NARRATIVE_CANDIDATES :: 64
MAX_NARRATIVE_RECENT :: 8
MAX_NARRATIVE_DEFERRED :: 3

Narrative_Domain :: enum {
	None,
	Public_Question,
	Institution_Rivalry,
	Historical_Front,
	Fleet_Interaction,
	Public_Objection,
	Ship_Casting,
}

Narrative_Priority :: enum {
	Discretionary,
	Developing,
	Urgent,
	Mandatory,
}

Narrative_Source_Kind :: enum {
	None,
	Public_Rival,
	Precedent_Case,
	Obligation,
	Front_Question,
	Need,
	Institution_Pair,
	Front_Proposal,
	Front_Return,
	Front_Advance,
}

Narrative_Actor_Key :: struct {
	kind: Public_Actor_Kind,
	id:   u32,
}

Narrative_Candidate :: struct {
	domain:          Narrative_Domain,
	priority:        Narrative_Priority,
	source_kind:     Narrative_Source_Kind,
	stable_id:       u64,
	source_event:    u64,
	urgency:         i32,
	earliest_season: i32,
	deadline:        i32,
	source_index:    int,
	secondary_index: int,
	principal_actor: Narrative_Actor_Key,
	semantic_tags:   Semantic_Tags,
}

Narrative_Deferred_Record :: struct {
	domain:    Narrative_Domain,
	stable_id: u64,
	score:     i32,
}

Narrative_Selection_Record :: struct {
	valid:          bool,
	season:         i32,
	domain:         Narrative_Domain,
	stable_id:      u64,
	source_event:   u64,
	priority:       Narrative_Priority,
	score:          i32,
	repetition:     i32,
	deferred:       [MAX_NARRATIVE_DEFERRED]Narrative_Deferred_Record,
	deferred_count: int,
}

Narrative_Director_State :: struct {
	selection_sequence: u64,
	recent_domains:     [MAX_NARRATIVE_RECENT]Narrative_Domain,
	recent_actors:      [MAX_NARRATIVE_RECENT]Narrative_Actor_Key,
	recent_count:       int,
	last:               Narrative_Selection_Record,
}

narrative_mix :: proc(value: u64) -> u64 {
	x := value
	x = (x ~ (x >> 30)) * 0xbf58476d1ce4e5b9
	x = (x ~ (x >> 27)) * 0x94d049bb133111eb
	return x ~ (x >> 31)
}

narrative_rank :: proc(c: ^Campaign, domain: Narrative_Domain, stable_id, sequence: u64) -> u64 {
	return narrative_mix(
		c.initial_seed ~
		narrative_mix(u64(domain) * 0x9e3779b97f4a7c15) ~
		narrative_mix(stable_id) ~
		narrative_mix(sequence + 0x517cc1b727220a95),
	)
}

narrative_repetition_penalty :: proc(c: ^Campaign, candidate: Narrative_Candidate) -> i32 {
	if candidate.priority == .Mandatory do return 0
	penalty: i32
	for i in 0 ..< c.narrative_director.recent_count {
		distance := c.narrative_director.recent_count - i
		if c.narrative_director.recent_domains[i] == candidate.domain do penalty += i32(max(4 - distance, 1))
		actor := c.narrative_director.recent_actors[i]
		if candidate.principal_actor.id != 0 &&
		   actor == candidate.principal_actor {penalty += i32(max(6 - distance, 2))}
	}
	return penalty
}

narrative_candidate_score :: proc(c: ^Campaign, candidate: Narrative_Candidate) -> (i32, i32) {
	repetition := narrative_repetition_penalty(c, candidate)
	overdue: i32
	if candidate.deadline > 0 && c.season > candidate.deadline do overdue = c.season - candidate.deadline
	return candidate.urgency + overdue * 8 - repetition, repetition
}

narrative_candidate_better :: proc(
	c: ^Campaign,
	candidate, incumbent: Narrative_Candidate,
	candidate_score, incumbent_score: i32,
) -> bool {
	if candidate.priority != incumbent.priority do return candidate.priority > incumbent.priority
	if candidate_score != incumbent_score do return candidate_score > incumbent_score
	sequence := c.narrative_director.selection_sequence + 1
	return(
		narrative_rank(c, candidate.domain, candidate.stable_id, sequence) >
		narrative_rank(c, incumbent.domain, incumbent.stable_id, sequence) \
	)
}

narrative_select_candidate :: proc(
	c: ^Campaign,
	candidates: []Narrative_Candidate,
) -> (
	Narrative_Candidate,
	bool,
) {
	selected: Narrative_Candidate
	found := false
	selected_score: i32
	for candidate in candidates {
		if candidate.domain == .None ||
		   candidate.stable_id == 0 ||
		   candidate.earliest_season > c.season {continue}
		score, _ := narrative_candidate_score(c, candidate)
		if !found || narrative_candidate_better(c, candidate, selected, score, selected_score) {
			selected = candidate
			selected_score = score
			found = true
		}
	}
	return selected, found
}

narrative_append_candidate :: proc(
	out: []Narrative_Candidate,
	count: ^int,
	candidate: Narrative_Candidate,
) {
	if count^ >= len(out) do return
	out[count^] = candidate
	count^ += 1
}

narrative_record_selection :: proc(
	c: ^Campaign,
	selected: Narrative_Candidate,
	candidates: []Narrative_Candidate,
) {
	score, repetition := narrative_candidate_score(c, selected)
	record := Narrative_Selection_Record {
		valid        = true,
		season       = c.season,
		domain       = selected.domain,
		stable_id    = selected.stable_id,
		source_event = selected.source_event,
		priority     = selected.priority,
		score        = score,
		repetition   = repetition,
	}
	for candidate in candidates {
		if candidate.domain == selected.domain && candidate.stable_id == selected.stable_id do continue
		candidate_score, _ := narrative_candidate_score(c, candidate)
		slot := record.deferred_count
		if slot < MAX_NARRATIVE_DEFERRED {
			record.deferred[slot] = {
				domain    = candidate.domain,
				stable_id = candidate.stable_id,
				score     = candidate_score,
			}
			record.deferred_count += 1
		}
	}
	d := &c.narrative_director
	if d.recent_count < MAX_NARRATIVE_RECENT {
		d.recent_domains[d.recent_count] = selected.domain
		d.recent_actors[d.recent_count] = selected.principal_actor
		d.recent_count += 1
	} else {
		for i in 1 ..< MAX_NARRATIVE_RECENT {
			d.recent_domains[i - 1] = d.recent_domains[i]
			d.recent_actors[i - 1] = d.recent_actors[i]
		}
		d.recent_domains[MAX_NARRATIVE_RECENT - 1] = selected.domain
		d.recent_actors[MAX_NARRATIVE_RECENT - 1] = selected.principal_actor
	}
	d.selection_sequence += 1
	d.last = record
}

validate_narrative_director :: proc(c: ^Campaign) -> bool {
	d := &c.narrative_director
	if d.recent_count < 0 || d.recent_count > MAX_NARRATIVE_RECENT do return false
	if d.last.deferred_count < 0 || d.last.deferred_count > MAX_NARRATIVE_DEFERRED do return false
	if d.last.valid &&
	   (d.last.domain == .None || d.last.stable_id == 0 || d.last.season > c.season) {return false}
	return true
}

surface_narrative_candidate :: proc(c: ^Campaign, candidate: Narrative_Candidate) -> bool {
	#partial switch candidate.domain {
	case .Public_Question:
		return surface_public_question_candidate(c, candidate)
	case .Institution_Rivalry:
		return surface_institution_rivalry_candidate(c, candidate)
	case .Historical_Front:
		return surface_historical_front_candidate(c, candidate)
	case:
	}
	return false
}

run_narrative_director :: proc(c: ^Campaign) -> bool {
	if !major_story_beat_ready(c) do return false
	if c.season - c.last_front_beat_season >= 6 && c.future_front_count == 0 && c.front_count == 0 do seed_front_families(c)
	candidates: [MAX_NARRATIVE_CANDIDATES]Narrative_Candidate
	count := 0
	count += collect_public_question_candidates(c, candidates[count:])
	if count < len(candidates) do count += collect_institution_rivalry_candidates(c, candidates[count:])
	if count < len(candidates) && c.season - c.last_front_beat_season >= 6 do count += collect_historical_front_candidates(c, candidates[count:])
	for count > 0 {
		selected, ok := narrative_select_candidate(c, candidates[:count]); if !ok do return false
		if surface_narrative_candidate(c, selected) {
			if selected.domain != .Historical_Front do mark_major_story_beat(c)
			narrative_record_selection(c, selected, candidates[:count])
			return true
		}
		for i in 0 ..< count do if candidates[i].domain == selected.domain && candidates[i].stable_id == selected.stable_id {
			for j in i + 1 ..< count do candidates[j - 1] = candidates[j]
			count -= 1
			break
		}
	}
	return false
}

narrative_cast_ship_for_role :: proc(c: ^Campaign, role: Role) -> Ship_ID {
	selected := Ship_ID(0)
	best_score := i32(-100000)
	best_rank: u64
	for ship in c.ships[:c.ship_count] {
		if !ship.active || ship.role != role do continue
		score := i32(0)
		if !ship.committed do score += 20
		score -= ship.damage * 5
		rank := narrative_rank(
			c,
			.Ship_Casting,
			u64(ship.id),
			u64(role) << 32 | u64(u32(max(c.season, 0))),
		)
		if score > best_score ||
		   score == best_score &&
			   rank > best_rank {selected = ship.id; best_score = score; best_rank = rank}
	}
	return selected
}

narrative_cast_ship_for_community :: proc(c: ^Campaign, community: Community_ID) -> Ship_ID {
	selected := Ship_ID(0)
	best_score := i32(-100000)
	best_rank: u64
	for ship in c.ships[:c.ship_count] {
		if !ship.active || ship.community != community do continue
		score := i32(0)
		if !ship.committed do score += 20
		score -= ship.damage * 5
		rank := narrative_rank(
			c,
			.Ship_Casting,
			u64(ship.id),
			u64(community) << 32 | u64(u32(max(c.season, 0))),
		)
		if score > best_score ||
		   score == best_score &&
			   rank > best_rank {selected = ship.id; best_score = score; best_rank = rank}
	}
	return selected
}
