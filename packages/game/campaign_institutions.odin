package game

import "core:fmt"
import "core:testing"

advance_institution_politics :: proc(c: ^Campaign) {
	candidates: [MAX_INSTITUTIONS * MAX_INSTITUTIONS]Narrative_Candidate
	count := collect_institution_rivalry_candidates(c, candidates[:])
	if count == 0 do return
	selected, ok := narrative_select_candidate(c, candidates[:count])
	if ok && surface_institution_rivalry_candidate(c, selected) do narrative_record_selection(c, selected, candidates[:count])
}

collect_institution_rivalry_candidates :: proc(c: ^Campaign, out: []Narrative_Candidate) -> int {
	if c.institution_relationship_count > 0 do return 0
	count := 0
	for a in 0 ..< len(c.institutions) {if !c.institutions[a].active do continue; for b in a + 1 ..< len(c.institutions) {
			if !c.institutions[b].active do continue
			_, conflict := institution_policy_conflict(
				c.institutions[a],
				c.institutions[b],
			); if !conflict do continue
			if institution_relationship_index(c, c.institutions[a].id, c.institutions[b].id) >= 0 do continue
			if count >= len(out) do return count
			cause := latest_event_for_institution(
				c,
				c.institutions[a].id,
			); if cause == 0 do cause = latest_event_for_institution(c, c.institutions[b].id)
			lo := min(
				u64(c.institutions[a].id),
				u64(c.institutions[b].id),
			); hi := max(u64(c.institutions[a].id), u64(c.institutions[b].id))
			out[count] = {
				domain = .Institution_Rivalry,
				priority = .Developing,
				source_kind = .Institution_Pair,
				stable_id = narrative_mix(0x8100000000000000 ~ lo << 16 ~ hi),
				source_event = cause,
				urgency = 25,
				source_index = a,
				secondary_index = b,
				principal_actor = {kind = .Institution, id = u32(c.institutions[a].id)},
			}
			count += 1
		}}
	return count
}

surface_institution_rivalry_candidate :: proc(
	c: ^Campaign,
	candidate: Narrative_Candidate,
) -> bool {
	a, b := candidate.source_index, candidate.secondary_index
	if a < 0 || a >= len(c.institutions) || b < 0 || b >= len(c.institutions) do return false
	policy, conflict := institution_policy_conflict(
		c.institutions[a],
		c.institutions[b],
	); if !conflict do return false
	cause := latest_event_for_institution(
		c,
		c.institutions[a].id,
	); if cause == 0 do cause = latest_event_for_institution(c, c.institutions[b].id)
	return set_institution_relationship(
		c,
		c.institutions[a].id,
		c.institutions[b].id,
		.Rivalry,
		policy,
		cause,
	)
}

latest_event_for_institution :: proc(c: ^Campaign, institution: Institution_ID) -> u64 {
	for i := c.event_count - 1; i >= 0; i -= 1 do if c.events[i].institution_id == institution do return c.events[i].sequence
	return 0
}

settlement_index :: proc(c: ^Campaign, id: Settlement_ID) -> int {
	if id == 0 do return -1
	for settlement, i in c.settlements[:c.settlement_count] do if settlement.id == id do return i
	return -1
}

archive_index :: proc(c: ^Campaign, id: Archive_ID) -> int {
	if id == 0 do return -1
	for archive, i in c.archives do if archive.id == id do return i
	return -1
}

establish_copied_archive :: proc(c: ^Campaign, settlement_at: int, cause: u64) -> bool {
	if settlement_at < 0 || settlement_at >= c.settlement_count do return false
	if !has_precedent(c, .Open_Archives) do return false
	settlement := &c.settlements[settlement_at]
	if settlement.archive_id != 0 do return false
	for archive in c.archives {
		if !archive.preserved || !archive.copied do continue
		settlement.archive_id = archive.id
		record_event(
			c,
			.Archive_Established,
			fmt.tprintf("%s established a public copy of the %s.", settlement.name, archive.name),
			settlement.founder_ship,
			archive.integrity,
			settlement.founding_community,
			cause,
			settlement_id = settlement.id,
			archive_id = archive.id,
		)
		settlement.archive_origin_event = c.event_sequence
		settlement.last_report_event = c.event_sequence
		return true
	}
	return false
}

review_contested_account :: proc(c: ^Campaign) -> bool {
	if !has_precedent(c, .Open_Archives) || c.pending_accountability_event != 0 || !chronicle_can_record(c, 2) do return false
	report_at := -1
	for event, i in c.events[:c.event_count] {
		if event.account_status == .Uncontested || !semantic_has(event.semantic_tags, .Contested) || event.account_exposed || event.season >= c.season do continue
		report_at = i; break
	}
	if report_at < 0 do return false
	report := &c.events[report_at]; report.account_exposed = true; report.semantic_tags = semantic_add(report.semantic_tags, .Accountability, .Contested)
	community := report.community
	if community ==
	   0 {ship_at := ship_index(c, report.ship_id); if ship_at >= 0 do community = c.ships[ship_at].community}
	if community == 0 do community = 1
	archive_id := Archive_ID(3); if archive_index(c, archive_id) < 0 do archive_id = 1
	rule_event := precedent_event_for(c, .Open_Archives)
	detail := fmt.tprintf(
		"A public archive review exposed the disputed account recorded in E%03d.",
		report.sequence,
	)
	record_event(
		c,
		.Archive_Revelation,
		detail,
		report.ship_id,
		community = community,
		cause_sequence = report.sequence,
		institution_id = 1,
		precedent_event = rule_event,
		archive_id = archive_id,
	)
	c.pending_accountability_event = c.event_sequence
	if community_at := community_index(c, community);
	   community_at >=
	   0 {subject := &c.communities[community_at]; subject.grievance = min(subject.grievance + 1, 10); subject.position = community_position_for(subject); subject.last_memory_event = c.event_sequence}
	if assembly_at := institution_index(c, 1);
	   assembly_at >=
	   0 {assembly := &c.institutions[assembly_at]; assembly.legitimacy = max(assembly.legitimacy - 3, 0); record_event(c, .Institution_Changed, "The Civic Assembly opened an accountability hearing after the archive disclosure.", report.ship_id, assembly.legitimacy, community, c.pending_accountability_event, institution_id = assembly.id, archive_id = archive_id)}
	return true
}

latest_event_for_settlement :: proc(c: ^Campaign, settlement: Settlement_ID) -> u64 {
	for i := c.event_count - 1; i >= 0; i -= 1 do if c.events[i].settlement_id == settlement && c.events[i].kind != .Need_Surfaced do return c.events[i].sequence
	return 0
}

institution_need_kind :: proc(id: Institution_ID) -> Need_Kind {
	switch id {case 1, 5:
		return .Representation; case 2, 3:
		return .Archive_Staffing; case 4:
		return .Ship_Repair}
	return .Representation
}

institution_need_detail :: proc(id: Institution_ID) -> string {
	switch id {
	case 1:
		return "The Civic Assembly calls for a review of fleet representation."
	case 2:
		return "The Navigation Guild requests protected staffing for route records."
	case 3:
		return "The Seed Archive requests specialists to stabilize its collections."
	case 4:
		return "The Fleet Foundry Council requests priority maintenance authority."
	case 5:
		return "The Mercy Compact asks the council to renew its rescue obligations."
	}
	return "An institution has placed a petition before the fleet."
}

first_active_ship_with_role :: proc(c: ^Campaign, role: Role) -> Ship_ID {
	return narrative_cast_ship_for_role(c, role)
}

ship_for_community :: proc(c: ^Campaign, community: Community_ID) -> Ship_ID {
	return narrative_cast_ship_for_community(c, community)
}

precedent_event_for :: proc(c: ^Campaign, kind: Precedent_Kind) -> u64 {
	for i := c.precedent_count - 1; i >= 0; i -= 1 do if c.precedents[i].kind == kind do return c.precedents[i].event_sequence
	return 0
}

derive_historical_need :: proc(c: ^Campaign, used: ^[NEED_KIND_COUNT]bool) -> (Need, bool) {
	if c.pending_accountability_event != 0 && !used[int(Need_Kind.Representation)] {
		revelation_at := event_index_by_sequence(c, c.pending_accountability_event)
		if revelation_at >=
		   0 {revelation := c.events[revelation_at]; return {kind = .Representation, community = revelation.community, ship = revelation.ship_id, source_event = revelation.sequence, institution = 1, precedent_event = revelation.precedent_event, archive_id = revelation.archive_id}, true}
	}
	if !used[int(Need_Kind.Sustenance_Shortfall)] && fleet_supply(c) <= 30 {
		return {
				kind = .Sustenance_Shortfall,
				community = 1,
				ship = first_active_ship_with_role(c, .Agriculture),
				source_event = latest_event_of_kind(c, .Resource_Changed),
			},
			true
	}
	if !used[int(Need_Kind.Ship_Repair)] {
		best := -1; best_score: i32 = -1
		for ship, i in c.ships[:c.ship_count] {
			if !ship.active || ship.damage <= 0 do continue
			score := ship.damage * 10; ci := community_index(c, ship.community)
			if ci >= 0 &&
			   c.communities[ci].trust <
				   55 {score += 10; if ship.role == .Hospital do score += 100}
			if score > best_score {best = i; best_score = score}
		}
		if best >=
		   0 {ship := c.ships[best]; source := latest_ship_memory_with_tag(c, ship.id, .Damage); if source == 0 do source = latest_event_for_ship(c, ship.id); return {kind = .Ship_Repair, community = ship.community, ship = ship.id, source_event = source}, true}
	}
	if !used[int(Need_Kind.Jurisdiction_Dispute)] {
		best := -1
		for relationship, i in c.institution_ship_relationships[:c.institution_ship_relationship_count] do if relationship.stance == .Contested && ship_index(c, relationship.ship) >= 0 && (best < 0 || relationship.strength < c.institution_ship_relationships[best].strength) do best = i
		if best >=
		   0 {relationship := c.institution_ship_relationships[best]; ship_at := ship_index(c, relationship.ship); return {kind = .Jurisdiction_Dispute, community = c.ships[ship_at].community, ship = relationship.ship, source_event = relationship.last_event, institution = relationship.institution, precedent_event = relationship.precedent_event, figure = c.ships[ship_at].captain}, true}
	}
	if !used[int(Need_Kind.Institution_Dispute)] {
		for relationship in c.institution_relationships[:c.institution_relationship_count] do if relationship.stance == .Rivalry && relationship.strength == -1 {a_at := institution_index(c, relationship.institution_a); if a_at >= 0 do return {kind = .Institution_Dispute, community = c.institutions[a_at].community, source_event = relationship.last_event, institution = relationship.institution_a, opposing_institution = relationship.institution_b}, true}
	}
	if !used[int(Need_Kind.Representation)] {
		best := -1
		for relationship, i in c.community_institution_relationships[:c.community_institution_relationship_count] do if relationship.stance == .Opposition && relationship.strength <= -2 && (best < 0 || relationship.strength < c.community_institution_relationships[best].strength) do best = i
		if best >=
		   0 {relationship := c.community_institution_relationships[best]; figure_id := Figure_ID(0); ship := ship_for_community(c, relationship.community); if figure_at := figure_for_institution(c, relationship.institution); figure_at >= 0 {figure_id = c.historical_figures[figure_at].id}; return {kind = .Representation, community = relationship.community, ship = ship, source_event = relationship.last_event, institution = relationship.institution, figure = figure_id}, true}
	}
	if !used[int(Need_Kind.Settlement_Defense)] {
		for settlement in c.settlements[:c.settlement_count] do if settlement.active && settlement.reported && settlement.viability < 60 do return {kind = .Settlement_Defense, community = settlement.founding_community, ship = first_active_ship_with_role(c, .Escort), source_event = settlement.last_report_event, settlement = settlement.id}, true
	}
	if !used[int(Need_Kind.Settlement_Charter)] {
		for settlement in c.settlements[:c.settlement_count] do if settlement.active && settlement.reported && settlement.liberty < 55 {
			rule_event := precedent_event_for(c, .Ship_Sovereignty)
			if rule_event == 0 do rule_event = precedent_event_for(c, .Shared_Authority)
			if rule_event == 0 && settlement.archive_id != 0 do rule_event = precedent_event_for(c, .Open_Archives)
			return {kind = .Settlement_Charter, community = settlement.founding_community, ship = settlement.founder_ship, source_event = settlement.last_report_event, settlement = settlement.id, precedent_event = rule_event, archive_id = settlement.archive_id}, true
		}
	}
	for institution in c.institutions {
		initiative_threshold: i32 = institution.id == 1 ? 70 : 60
		if !institution.active || institution.legitimacy >= initiative_threshold do continue
		kind := institution_need_kind(institution.id); if used[int(kind)] do continue
		ship := ship_for_community(c, institution.community)
		if institution.id == 4 do ship = first_active_ship_with_role(c, .Foundry)
		figure_id := Figure_ID(0); source := latest_event_for_institution(c, institution.id)
		if figure_at := figure_for_institution(c, institution.id);
		   figure_at >=
		   0 {figure_id = c.historical_figures[figure_at].id; source = c.historical_figures[figure_at].last_event; ship = c.historical_figures[figure_at].ship}
		return {
				kind = kind,
				community = institution.community,
				ship = ship,
				source_event = source,
				institution = institution.id,
				figure = figure_id,
			},
			true
	}
	if !used[int(Need_Kind.Representation)] {
		lowest := -1; highest_pressure: i32 = -1
		for community, i in c.communities[:c.community_count] {
			if community.trust >= 55 && community.grievance < 3 do continue
			pressure := (100 - community.trust) + community.grievance * 10
			if pressure > highest_pressure {lowest = i; highest_pressure = pressure}
		}
		if lowest >=
		   0 {community := c.communities[lowest]; source := community.last_memory_event; if source == 0 do source = latest_event_for_community(c, community.id); return {kind = .Representation, community = community.id, ship = ship_for_community(c, community.id), source_event = source}, true}
	}
	if !used[int(Need_Kind.Archive_Staffing)] {
		for archive in c.archives do if archive.preserved && archive.integrity < 70 do return {kind = .Archive_Staffing, community = 2, ship = first_active_ship_with_role(c, .Archive), source_event = latest_event_of_kind(c, .Resource_Changed)}, true
	}
	if !used[int(Need_Kind.Settlement_Demand)] {
		highest := -1
		for community, i in c.communities[:c.community_count] do if community.settlement_desire >= 5 && (highest < 0 || community.settlement_desire > c.communities[highest].settlement_desire) do highest = i
		if highest >=
		   0 {community := c.communities[highest]; return {kind = .Settlement_Demand, community = community.id, ship = ship_for_community(c, community.id), source_event = latest_event_for_community(c, community.id)}, true}
	}
	return {}, false
}

surface_needs :: proc(c: ^Campaign) {
	used: [NEED_KIND_COUNT]bool
	for need in c.needs do if need.active do used[int(need.kind)] = true
	// The founding season presents the full strategic board. Later seasons vary
	// their incoming workload so routine history has room around major beats.
	budget := 1
	if c.season > 0 {
		switch c.story_tempo {
		case .Spacious:
			cadence := (c.season + i32(c.initial_seed % 11)) % 8
			if c.last_major_beat_season == c.season || cadence <= 1 do budget = 0
			if cadence == 6 do budget = 2
		case .Volatile:
			cadence := (c.season + i32(c.initial_seed % 5)) % 5
			budget = 2
			if c.last_major_beat_season == c.season || cadence == 0 do budget = 1
			if cadence == 4 do budget = 3
		case .Measured:
			cadence := (c.season + i32(c.initial_seed % 7)) % 6
			if c.last_major_beat_season == c.season || cadence == 0 do budget = 0
			if cadence == 4 do budget = 2
		}
		// Accountability is a callback to an exposed record, not an unrelated
		// surprise; it may occupy the one available slot after a major beat.
		if c.pending_accountability_event != 0 do budget = max(budget, 1)
	} else {
		budget = MAX_NEEDS
	}
	created := 0
	for i in 0 ..< MAX_NEEDS {
		if created >= budget do break
		if c.needs[i].active do continue
		need, derived := derive_historical_need(c, &used)
		if !derived {
			for offset in 0 ..< 6 {kind := Need_Kind((int(c.season) * MAX_NEEDS + i + offset + int(c.initial_seed % 6)) % 6); if used[int(kind)] do continue; need.kind = kind; break}
			need.community = Community_ID((int(c.season) + i) % max(c.community_count, 1) + 1)
			need.ship = Ship_ID((int(c.season) * 2 + i) % MAX_SHIPS + 1)
		}
		kind := need.kind; community := need.community; ship := need.ship
		cost: i32 = max(
			i32(7 + i * 3) +
			precedent_need_cost_modifier(c, kind) +
			community_institution_need_cost_modifier(c, need.community, need.institution),
			2,
		)
		if kind == .Institution_Dispute do cost = min(cost, 3)
		need.deadline =
			c.season +
			1; need.cost = cost; need.active = true; need.detail = need.institution != 0 ? institution_need_detail(need.institution) : need_detail(kind); need.response = .Open
		if figure_at := historical_figure_index(c, need.figure);
		   figure_at >=
		   0 {figure := c.historical_figures[figure_at]; institution_at := institution_index(c, need.institution); if institution_at >= 0 do need.detail = fmt.tprintf("%s, %s, presents a petition through the %s.", figure.name, figure.role, c.institutions[institution_at].name)}
		if need.kind ==
		   .Settlement_Charter {settlement_at := settlement_index(c, need.settlement); if settlement_at >= 0 {settlement := c.settlements[settlement_at]; need.detail = fmt.tprintf("%s petitions to revise its founding charter.", settlement.name); archive_at := archive_index(c, settlement.archive_id); if archive_at >= 0 do need.detail = fmt.tprintf("Readers of the %s at %s petition to revise its founding charter.", c.archives[archive_at].name, settlement.name)}}
		if need.kind ==
		   .Ship_Repair {ship_at := ship_index(c, need.ship); community_at := community_index(c, need.community); if ship_at >= 0 {need.cost += min(c.ships[ship_at].damage, 3); if community_at >= 0 do need.detail = fmt.tprintf("The %s requests priority repairs for %s after its recorded damage.", c.communities[community_at].name, c.ships[ship_at].name)}}
		if need.kind ==
		   .Jurisdiction_Dispute {ship_at := ship_index(c, need.ship); institution_at := institution_index(c, need.institution); figure_at := historical_figure_index(c, need.figure); if ship_at >= 0 && institution_at >= 0 && figure_at >= 0 do need.detail = fmt.tprintf("The %s and Captain %s dispute who holds operational authority over %s.", c.institutions[institution_at].name, c.historical_figures[figure_at].name, c.ships[ship_at].name)}
		if need.kind ==
		   .Institution_Dispute {a_at := institution_index(c, need.institution); b_at := institution_index(c, need.opposing_institution); if a_at >= 0 && b_at >= 0 do need.detail = fmt.tprintf("The %s and the %s demand a ruling on their incompatible public policies.", c.institutions[a_at].name, c.institutions[b_at].name)}
		if need.kind ==
		   .Representation {community_at := community_index(c, need.community); if community_at >= 0 && c.communities[community_at].grievance > 0 {community := c.communities[community_at]; need.detail = fmt.tprintf("The %s cites %d unanswered petitions in its representation claim.", community.name, community.petitions_neglected)}}
		if source_at := event_index_by_sequence(c, need.source_event);
		   source_at >= 0 &&
		   c.events[source_at].kind ==
			   .Political_Relationship_Changed {community_at := community_index(c, need.community); institution_at := institution_index(c, need.institution); if community_at >= 0 && institution_at >= 0 do need.detail = fmt.tprintf("The %s challenges the %s after their recorded political break.", c.communities[community_at].name, c.institutions[institution_at].name)}
		if source_at := event_index_by_sequence(c, need.source_event);
		   source_at >= 0 &&
		   c.events[source_at].kind ==
			   .Archive_Revelation {community_at := community_index(c, need.community); if community_at >= 0 do need.detail = fmt.tprintf("The %s demands an accounting for the report exposed by the public archives.", c.communities[community_at].name)}
		need.semantic_tags = semantic_tags_for_need(
			kind,
		); c.needs[i] = need; used[int(kind)] = true
		record_event(
			c,
			.Need_Surfaced,
			need.detail,
			ship,
			community = community,
			cause_sequence = need.source_event,
			figure_id = need.figure,
			institution_id = need.institution,
			settlement_id = need.settlement,
			precedent_event = need.precedent_event,
			archive_id = need.archive_id,
		)
		created += 1
	}
}

resolve_need :: proc(c: ^Campaign, index: int) -> bool {
	if index < 0 || index >= MAX_NEEDS || !c.needs[index].active || c.needs[index].resolved do return false
	n := &c.needs[index]
	
	afforded := false
	switch n.kind {
	case .Sustenance_Shortfall:
		if fleet_stock_spend(c, {supplies = i64(n.cost)}, .Emergency) do afforded = true
	case .Ship_Repair, .Settlement_Defense:
		if fleet_stock_spend(c, {supplies = i64(n.cost)}, .Emergency) do afforded = true
	case .Archive_Staffing:
		if spend_knowledge(c, n.cost, .Archive_Operation) do afforded = true
	case .Settlement_Demand,
	     .Representation,
	     .Settlement_Charter,
	     .Jurisdiction_Dispute,
	     .Institution_Dispute:
		if c.strategic.cohesion >= n.cost {c.strategic.cohesion -= n.cost / 2; afforded = true}
	}
	if !afforded do return false
	n.resolved = true
	n.active = false
	n.response = .Resolved
	ci := community_index(c, n.community)
	if ci >= 0 {c.communities[ci].trust = min(c.communities[ci].trust + 5, 100)}
	c.strategic.cohesion = min(c.strategic.cohesion + 3, 100)
	record_event(
		c,
		.Need_Resolved,
		n.detail,
		n.ship,
		community = n.community,
		cause_sequence = n.source_event,
		figure_id = n.figure,
		institution_id = n.institution,
		settlement_id = n.settlement,
		precedent_event = n.precedent_event,
		archive_id = n.archive_id,
	)
	resolved_event := c.event_sequence
	record_community_memory(c, n.community, n.ship, true, false, resolved_event, n.kind)
	if n.institution != 0 do _ = record_community_institution_response(c, n.community, n.institution, true, resolved_event)
	if n.kind ==
	   .Institution_Dispute {relation_at := institution_relationship_index(c, n.institution, n.opposing_institution); policy := Semantic_Tag.Governance; if relation_at >= 0 do policy = c.institution_relationships[relation_at].policy; _ = set_institution_relationship(c, n.institution, n.opposing_institution, .Accord, policy, resolved_event)}
	if n.kind == .Jurisdiction_Dispute do _ = set_institution_ship_relationship(c, n.institution, n.ship, .Reconciled, 2, resolved_event, n.precedent_event)
	if n.source_event == c.pending_accountability_event do c.pending_accountability_event = 0
	if n.kind == .Ship_Repair {
		ship_at := ship_index(c, n.ship)
		if ship_at >= 0 {
			ship := &c.ships[ship_at]; repaired := min(ship.damage, 2); ship.damage -= repaired
			detail := fmt.tprintf(
				"%s received priority repairs; damage fell by %d.",
				ship.name,
				repaired,
			)
			add_ship_history(c, ship.id, detail)
			record_event(c, .Ship_Repaired, detail, ship.id, repaired, n.community, resolved_event)
		}
	}
	if settlement_at := settlement_index(c, n.settlement);
	   n.kind == .Settlement_Defense && settlement_at >= 0 {
		settlement := &c.settlements[settlement_at]
		settlement.viability = min(settlement.viability + 10, 100)
		record_event(
			c,
			.Settlement_Supported,
			settlement.name,
			n.ship,
			settlement.viability,
			n.community,
			resolved_event,
			settlement_id = settlement.id,
		)
		settlement.last_report_event = c.event_sequence
	}
	if settlement_at := settlement_index(c, n.settlement);
	   n.kind == .Settlement_Charter && settlement_at >= 0 {
		settlement := &c.settlements[settlement_at]
		gain: i32 = 15; if has_precedent(c, .Shared_Authority) do gain += 5; if has_precedent(c, .Ship_Sovereignty) do gain += 5; if n.archive_id != 0 {gain += 5; record_knowledge_gain(c, 3, .Archives)}
		settlement.liberty = min(settlement.liberty + gain, 100)
		record_event(
			c,
			.Settlement_Charter_Changed,
			fmt.tprintf("%s revised its charter.", settlement.name),
			n.ship,
			settlement.liberty,
			n.community,
			resolved_event,
			settlement_id = settlement.id,
			precedent_event = n.precedent_event,
			archive_id = n.archive_id,
		)
		settlement.last_report_event = c.event_sequence
	}
	if institution_at := institution_index(c, n.institution); institution_at >= 0 {
		institution := &c.institutions[institution_at]; institution.legitimacy = min(institution.legitimacy + 5, 100)
		record_event(
			c,
			.Institution_Changed,
			"The institution's petition received a funded response.",
			n.ship,
			institution.legitimacy,
			n.community,
			resolved_event,
			n.figure,
			institution_id = institution.id,
		)
		record_figure_institution_response(c, n.figure, true, c.event_sequence)
	}
	advance_history_hook_for_need(c, n.community, n.ship, true)
	return true
}

mitigate_need :: proc(c: ^Campaign, index: int) -> bool {
	if index < 0 || index >= MAX_NEEDS do return false
	n := &c.needs[index]
	if !n.active || n.resolved || n.response == .Mitigated do return false
	cost := max(n.cost / 3, 2)
	afforded := false
	switch n.kind {
	case .Sustenance_Shortfall:
		if fleet_stock_spend(c, {supplies = i64(cost)}, .Emergency) do afforded = true
	case .Ship_Repair, .Settlement_Defense:
		if fleet_stock_spend(c, {supplies = i64(cost)}, .Emergency) do afforded = true
	case .Archive_Staffing:
		if spend_knowledge(c, cost, .Archive_Operation) do afforded = true
	case .Settlement_Demand,
	     .Representation,
	     .Settlement_Charter,
	     .Jurisdiction_Dispute,
	     .Institution_Dispute:
		if c.strategic.cohesion >= cost {c.strategic.cohesion -= cost; afforded = true}
	}
	if !afforded do return false
	n.response = .Mitigated
	record_event(c, .Need_Mitigated, n.detail, n.ship, cost)
	return true
}

defer_need :: proc(c: ^Campaign, index: int) -> bool {
	if index < 0 || index >= MAX_NEEDS do return false
	n := &c.needs[index]
	if !n.active || n.resolved || n.defer_count > 0 || c.strategic.cohesion < 2 do return false
	c.strategic.cohesion -= 2
	n.deadline += 1
	n.defer_count += 1
	n.response = .Deferred
	record_event(c, .Need_Deferred, n.detail, n.ship, n.deadline)
	return true
}

absorb_with_emergency_preparedness :: proc(c: ^Campaign, loss: i32) -> i32 {
	if loss <= 0 || c.emergency_preparedness <= 0 do return max(loss, 0)
	absorbed := min(loss, c.emergency_preparedness); c.emergency_preparedness -= absorbed
	if absorbed > 0 do record_event(c, .Emergency_Response, fmt.tprintf("Prepared institutions absorbed %d points of scheduled public pressure.", absorbed), value = absorbed)
	return loss - absorbed
}

neglect_open_needs :: proc(c: ^Campaign) {
	for i in 0 ..< MAX_NEEDS {
		n := &c.needs[i]
		if !n.active || n.resolved || n.deadline > c.season + 1 do continue
		mitigated := n.response == .Mitigated
		trust_loss: i32 = 8
		cohesion_loss: i32 = 5
		if mitigated {trust_loss = 4; cohesion_loss = 2}
		if n.kind == .Institution_Dispute {trust_loss = 2; cohesion_loss = 1}
		ci := community_index(c, n.community)
		repair_damage_recorded := false
		if ci >= 0 {c.communities[ci].trust = max(c.communities[ci].trust - trust_loss, 0)}
		#partial switch n.kind {
		case .Sustenance_Shortfall:
			loss: i32 = mitigated ? 4 : 8
			_ = fleet_stock_spend(c, {supplies = i64(min(loss, fleet_supply(c)))}, .Emergency)
		case .Ship_Repair:
			si := ship_index(c, n.ship)
			if si >= 0 && !mitigated {c.ships[si].damage += 1; repair_damage_recorded = true}
		case .Settlement_Demand:
			if ci >= 0 do c.communities[ci].settlement_desire = min(c.communities[ci].settlement_desire + 2, 10)
		case:
			c.strategic.cohesion = max(
				c.strategic.cohesion - absorb_with_emergency_preparedness(c, cohesion_loss),
				0,
			)
		}
		record_event(
			c,
			.Need_Neglected,
			n.detail,
			n.ship,
			community = n.community,
			cause_sequence = n.source_event,
			figure_id = n.figure,
			institution_id = n.institution,
			settlement_id = n.settlement,
			precedent_event = n.precedent_event,
			archive_id = n.archive_id,
		)
		neglected_event := c.event_sequence
		record_community_memory(c, n.community, n.ship, false, mitigated, neglected_event, n.kind)
		if n.institution != 0 do _ = record_community_institution_response(c, n.community, n.institution, false, neglected_event)
		if n.kind ==
		   .Institution_Dispute {relation_at := institution_relationship_index(c, n.institution, n.opposing_institution); policy := Semantic_Tag.Governance; if relation_at >= 0 do policy = c.institution_relationships[relation_at].policy; _ = set_institution_relationship(c, n.institution, n.opposing_institution, .Rivalry, policy, neglected_event)}
		if n.kind == .Jurisdiction_Dispute do _ = set_institution_ship_relationship(c, n.institution, n.ship, .Contested, mitigated ? 1 : 2, neglected_event, n.precedent_event)
		if n.source_event == c.pending_accountability_event do c.pending_accountability_event = 0
		if repair_damage_recorded {
			ship_at := ship_index(c, n.ship); ship := &c.ships[ship_at]
			detail := fmt.tprintf(
				"%s's repair petition closed unanswered; damage increased by one.",
				ship.name,
			)
			add_ship_history(c, ship.id, detail)
			record_event(c, .Ship_Damaged, detail, ship.id, 1, n.community, neglected_event)
		}
		if settlement_at := settlement_index(c, n.settlement);
		   n.kind == .Settlement_Defense && settlement_at >= 0 {
			settlement := &c.settlements[settlement_at]
			settlement.viability = max(settlement.viability - (mitigated ? 4 : 10), 0)
			record_event(
				c,
				.Settlement_Setback,
				settlement.name,
				n.ship,
				settlement.viability,
				n.community,
				neglected_event,
				settlement_id = settlement.id,
			)
			settlement.last_report_event = c.event_sequence
		}
		if settlement_at := settlement_index(c, n.settlement);
		   n.kind == .Settlement_Charter && settlement_at >= 0 {
			settlement := &c.settlements[settlement_at]
			settlement.liberty = max(settlement.liberty - (mitigated ? 3 : 8), 0)
			settlement.viability = max(settlement.viability - (mitigated ? 1 : 3), 0)
			record_event(
				c,
				.Settlement_Charter_Changed,
				fmt.tprintf("%s's charter petition closed without revision.", settlement.name),
				n.ship,
				settlement.liberty,
				n.community,
				neglected_event,
				settlement_id = settlement.id,
				precedent_event = n.precedent_event,
				archive_id = n.archive_id,
			)
			settlement.last_report_event = c.event_sequence
		}
		if institution_at := institution_index(c, n.institution); institution_at >= 0 {
			institution := &c.institutions[institution_at]; institution.legitimacy = max(institution.legitimacy - (mitigated ? 2 : 5), 0)
			record_event(
				c,
				.Institution_Changed,
				"The institution recorded that its petition went unanswered.",
				n.ship,
				institution.legitimacy,
				n.community,
				neglected_event,
				n.figure,
				institution_id = institution.id,
			)
			record_figure_institution_response(c, n.figure, false, c.event_sequence)
		}
		advance_history_hook_for_need(c, n.community, n.ship, false)
		n.active = false
		n.response = .Neglected
	}
}
