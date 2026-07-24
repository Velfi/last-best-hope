package game

import "core:fmt"
import "core:testing"

append_ship_memory :: proc(
	c: ^Campaign,
	ship_id: Ship_ID,
	event: Campaign_Event,
	other_ship: Ship_ID,
) {
	ship_at := ship_index(c, ship_id); if ship_at < 0 || event.sequence == 0 do return
	ship := &c.ships[ship_at]
	memory: Ship_Memory = {
		event_sequence = event.sequence,
		kind           = event.kind,
		other_ship     = other_ship,
		community      = event.community,
		figure         = event.figure_id,
		settlement     = event.settlement_id,
		account_status = event.account_status,
		semantic_tags  = semantic_add(event.semantic_tags, .Memory),
	}
	if ship.memory_count <
	   MAX_SHIP_MEMORIES {ship.memories[ship.memory_count] = memory; ship.memory_count += 1; return}
	evict := -1; for i in 0 ..< MAX_SHIP_MEMORIES do if !event_memory_is_pivotal(ship.memories[i].kind) {evict = i; break}
	if evict < 0 &&
	   !event_memory_is_pivotal(
			   event.kind,
		   ) {ship.archived_memory_count += 1; if ship.archived_memory_first == 0 do ship.archived_memory_first = event.sequence; ship.archived_memory_last = event.sequence; ship.archived_memory_tags = Semantic_Tags(u64(ship.archived_memory_tags) | u64(memory.semantic_tags)); return}
	if evict < 0 do evict = 0
	evicted :=
		ship.memories[evict]; ship.archived_memory_count += 1; if ship.archived_memory_first == 0 do ship.archived_memory_first = evicted.event_sequence; ship.archived_memory_last = evicted.event_sequence; ship.archived_memory_tags = Semantic_Tags(u64(ship.archived_memory_tags) | u64(evicted.semantic_tags))
	for i in evict + 1 ..< MAX_SHIP_MEMORIES do ship.memories[i - 1] = ship.memories[i]
	ship.memories[MAX_SHIP_MEMORIES - 1] = memory
}

remember_event_for_ships :: proc(c: ^Campaign, event: Campaign_Event) {
	if !event_creates_ship_memory(event.kind) do return
	if event.ship_id != 0 do append_ship_memory(c, event.ship_id, event, event.related_ship_id)
	if event.related_ship_id != 0 && event.related_ship_id != event.ship_id do append_ship_memory(c, event.related_ship_id, event, event.ship_id)
}

relationship_index :: proc(c: ^Campaign, ship: Ship_ID, community: Community_ID) -> int {
	for relationship, i in c.relationships[:c.relationship_count] do if relationship.ship == ship && relationship.community == community do return i
	return -1
}

set_ship_community_relationship :: proc(
	c: ^Campaign,
	ship: Ship_ID,
	community: Community_ID,
	kind: Relationship_Kind,
	strength: i32,
) -> bool {
	if ship_index(c, ship) < 0 || community_index(c, community) < 0 do return false
	index := relationship_index(c, ship, community)
	if index < 0 {
		if c.relationship_count >= MAX_RELATIONSHIPS do return false
		index = c.relationship_count; c.relationship_count += 1
		c.relationships[index] = {
			ship         = ship,
			community    = community,
			origin_event = c.event_sequence,
		}
	}
	c.relationships[index].kind = kind
	c.relationships[index].strength = clamp(strength, -3, 3)
	c.relationships[index].last_event = c.event_sequence
	c.relationships[index].semantic_tags = make_semantic_tags(.Relationship, .Ship, .Community)
	return true
}

relationship_community_name :: proc(c: ^Campaign, ship: Ship_ID) -> string {
	best := -1
	for relationship, i in c.relationships[:c.relationship_count] do if relationship.ship == ship && (best < 0 || abs(relationship.strength) > abs(c.relationships[best].strength)) do best = i
	if best < 0 do return ""
	ci := community_index(c, c.relationships[best].community)
	if ci < 0 do return ""
	return c.communities[ci].name
}

relationship_description :: proc(c: ^Campaign, ship: Ship_ID) -> string {
	index := -1
	for relationship, i in c.relationships[:c.relationship_count] do if relationship.ship == ship && (index < 0 || abs(relationship.strength) > abs(c.relationships[index].strength)) do index = i
	if index < 0 do return ""
	relationship := c.relationships[index]; ci := community_index(c, relationship.community)
	if ci < 0 do return ""
	switch relationship.kind {
	case .Sponsorship:
		return fmt.tprintf("Sponsor of the %s", c.communities[ci].name)
	case .Advocated_For:
		return fmt.tprintf("Advocated for the %s", c.communities[ci].name)
	case .Unanswered_Obligation:
		return fmt.tprintf("Unanswered obligation to the %s", c.communities[ci].name)
	}
	return ""
}

relationship_rescue_autonomy :: proc(c: ^Campaign, ship: Ship_ID) -> (i32, string) {
	for relationship in c.relationships[:c.relationship_count] {
		if relationship.ship != ship do continue
		ci := community_index(c, relationship.community); si := ship_index(c, ship)
		if ci < 0 || si < 0 do continue
		if relationship.kind == .Advocated_For && relationship.strength >= 2 do return 2, fmt.tprintf("%s applied the rescue practice established with the %s.", c.ships[si].name, c.communities[ci].name)
		if relationship.kind == .Unanswered_Obligation && relationship.strength <= -2 do return -1, fmt.tprintf("%s's unresolved obligation to the %s disrupted rescue coordination.", c.ships[si].name, c.communities[ci].name)
	}
	return 0, ""
}

ship_relationship_index :: proc(c: ^Campaign, first, second: Ship_ID) -> int {
	a, b := first, second; if a > b do a, b = b, a
	for relationship, i in c.ship_relationships[:c.ship_relationship_count] do if relationship.ship_a == a && relationship.ship_b == b do return i
	return -1
}

record_shared_passage_bonds :: proc(c: ^Campaign, ships: []Ship_ID, cause: u64) {
	for first_index in 0 ..< len(ships) {
		first := ships[first_index]; first_at := ship_index(c, first)
		if first_at < 0 || !c.ships[first_at].active do continue
		for second in ships[first_index + 1:] {
			second_at := ship_index(c, second)
			if second_at < 0 || !c.ships[second_at].active do continue
			a, b := first, second; if a > b do a, b = b, a
			index := ship_relationship_index(c, a, b)
			if index < 0 {
				if c.ship_relationship_count >= MAX_SHIP_RELATIONSHIPS do continue
				index = c.ship_relationship_count; c.ship_relationship_count += 1
				c.ship_relationships[index] = {
					ship_a       = a,
					ship_b       = b,
					origin_event = cause,
				}
			}
			relationship := &c.ship_relationships[index]
			relationship.shared_passages += 1
			relationship.strength = min(relationship.strength + 1, 3)
			first_name :=
				c.ships[ship_index(c, a)].name; second_name := c.ships[ship_index(c, b)].name
			record_event(
				c,
				.Ship_Bond_Changed,
				fmt.tprintf("%s and %s returned from a shared Passage.", first_name, second_name),
				a,
				relationship.strength,
				cause_sequence = cause,
				related_ship_id = b,
			)
			relationship.last_event = c.event_sequence
			relationship.semantic_tags = semantic_add(
				make_semantic_tags(
					.Relationship,
					.Ship,
					relationship.kind == .Construction_Siblings ? .Identity : .Passage,
				),
				.Passage,
			)
		}
	}
}

ship_bond_modifier :: proc(c: ^Campaign, ships: []Ship_ID) -> (i32, u64, Ship_ID, Ship_ID) {
	modifier: i32; latest: u64; source_a, source_b: Ship_ID
	for first_index in 0 ..< len(ships) do for second in ships[first_index + 1:] {
		index := ship_relationship_index(c, ships[first_index], second)
		if index < 0 do continue
		relationship := c.ship_relationships[index]
		if relationship.strength < 2 do continue
		modifier += 1
		if relationship.last_event > latest {latest = relationship.last_event; source_a = relationship.ship_a; source_b = relationship.ship_b}
	}
	return min(modifier, 2), latest, source_a, source_b
}

ship_bond_description :: proc(c: ^Campaign, ship: Ship_ID) -> string {
	best := -1
	for relationship, i in c.ship_relationships[:c.ship_relationship_count] do if (relationship.ship_a == ship || relationship.ship_b == ship) && (best < 0 || relationship.strength > c.ship_relationships[best].strength) do best = i
	if best < 0 do return ""
	relationship :=
		c.ship_relationships[best]; other := relationship.ship_a == ship ? relationship.ship_b : relationship.ship_a
	other_at := ship_index(c, other); if other_at < 0 do return ""
	if relationship.kind == .Construction_Siblings {
		if relationship.shared_passages == 0 do return fmt.tprintf("construction sibling of %s", c.ships[other_at].name)
		return fmt.tprintf(
			"construction sibling of %s · %d shared Passages",
			c.ships[other_at].name,
			relationship.shared_passages,
		)
	}
	return fmt.tprintf(
		"%d shared Passages with %s",
		relationship.shared_passages,
		c.ships[other_at].name,
	)
}

historical_figure_index :: proc(c: ^Campaign, id: Figure_ID) -> int {
	for figure, i in c.historical_figures[:c.historical_figure_count] do if figure.id == id do return i
	return -1
}

historical_figure_index_by_name :: proc(c: ^Campaign, name: string) -> int {
	for figure, i in c.historical_figures[:c.historical_figure_count] do if figure.name == name do return i
	return -1
}

emerge_historical_figure :: proc(
	c: ^Campaign,
	name, role: string,
	community: Community_ID,
	ship: Ship_ID,
	cause: u64,
) -> Figure_ID {
	existing := historical_figure_index_by_name(c, name)
	if existing >= 0 do return c.historical_figures[existing].id
	if c.historical_figure_count >= MAX_HISTORICAL_FIGURES do return 0
	id := Figure_ID(c.historical_figure_count + 1)
	detail := fmt.tprintf(
		"%s began speaking for the %s.",
		name,
		c.communities[community_index(c, community)].name,
	)
	if role == "ship captain" do detail = fmt.tprintf("%s became publicly known after a ship's autonomous action.", name)
	predecessor := Figure_ID(0); predecessor_event: u64
	if role ==
	   "ship captain" {for i := c.historical_figure_count - 1; i >= 0; i -= 1 {prior := c.historical_figures[i]; if prior.ship == ship && !prior.active && prior.role == "retired ship captain" {predecessor = prior.id; predecessor_event = prior.last_event; break}}}
	record_event(
		c,
		.Historical_Figure_Emerged,
		detail,
		ship,
		community = community,
		cause_sequence = cause,
		figure_id = id,
	)
	if predecessor_event != 0 do _ = add_event_cause(c, c.event_sequence, predecessor_event, .Continuation)
	c.historical_figures[c.historical_figure_count] = {
		id             = id,
		name           = name,
		role           = role,
		community      = community,
		ship           = ship,
		emerged_season = c.season,
		origin_event   = c.event_sequence,
		last_event     = c.event_sequence,
		age_years      = 32 + i32(id) * 3,
		predecessor    = predecessor,
		active         = true,
		semantic_tags  = make_semantic_tags(.Entity, .Figure),
	}
	if role == "ship captain" do captain_profile_initialize(c, &c.historical_figures[c.historical_figure_count])
	c.historical_figure_count += 1
	return id
}

CAPTAIN_NAMES := [MAX_HISTORICAL_FIGURES]string {
	"Ilyan Rook",
	"Sera Quill",
	"Maro Vey",
	"Anik Sol",
	"Edda Marr",
	"Tovan Reed",
	"Nia Corren",
	"Jules Arendt",
	"Pema Sorn",
	"Corin Vale",
	"Lio Cass",
	"Mira Thane",
	"Yara Fen",
	"Oren Pell",
	"Sumi Kade",
	"Tarin Moss",
}

captain_institution_for_role :: proc(role: Role) -> Institution_ID {
	switch role {case .Survey:
		return 2; case .Archive, .Agriculture:
		return 3; case .Foundry:
		return 4; case .Hospital:
		return 5; case .Habitat, .Escort, .Colony:
		return 1}
	return 1
}

institution_ship_relationship_index :: proc(
	c: ^Campaign,
	institution: Institution_ID,
	ship: Ship_ID,
) -> int {
	for relationship, i in c.institution_ship_relationships[:c.institution_ship_relationship_count] do if relationship.institution == institution && relationship.ship == ship do return i
	return -1
}

set_institution_ship_relationship :: proc(
	c: ^Campaign,
	institution: Institution_ID,
	ship: Ship_ID,
	stance: Institution_Ship_Stance,
	change: i32,
	cause: u64,
	precedent_event: u64 = 0,
) -> bool {
	institution_at := institution_index(c, institution); ship_at := ship_index(c, ship)
	if institution_at < 0 || ship_at < 0 || !chronicle_can_record(c) do return false
	index := institution_ship_relationship_index(c, institution, ship)
	if index < 0 {
		if c.institution_ship_relationship_count >= MAX_INSTITUTION_SHIP_RELATIONSHIPS do return false
		index = c.institution_ship_relationship_count; c.institution_ship_relationship_count += 1
		c.institution_ship_relationships[index] = {
			institution  = institution,
			ship         = ship,
			origin_event = cause,
		}
	}
	relationship := &c.institution_ship_relationships[index]
	relationship.stance = stance
	if stance ==
	   .Contested {relationship.strength = clamp(relationship.strength - max(abs(change), 1), -3, 3)} else {relationship.strength = clamp(max(relationship.strength, 0) + max(abs(change), 1), -3, 3)}
	relationship.precedent_event = precedent_event
	detail: string
	switch stance {
	case .Contested:
		captain_name := "the ship's command"
		if figure_at := historical_figure_index(c, c.ships[ship_at].captain);
		   figure_at >= 0 {
			captain_name = c.historical_figures[figure_at].name
		}
		detail = fmt.tprintf(
			"The %s and %s disputed operational jurisdiction over %s.",
			c.institutions[institution_at].name,
			captain_name,
			c.ships[ship_at].name,
		)
	case .Stewardship:
		detail = fmt.tprintf(
			"The %s recorded stewardship over %s.",
			c.institutions[institution_at].name,
			c.ships[ship_at].name,
		)
	case .Reconciled:
		detail = fmt.tprintf(
			"The %s reconciled institutional stewardship with %s's captaincy.",
			c.institutions[institution_at].name,
			c.ships[ship_at].name,
		)
	}
	record_event(
		c,
		.Jurisdiction_Changed,
		detail,
		ship,
		relationship.strength,
		c.ships[ship_at].community,
		cause,
		c.ships[ship_at].captain,
		institution_id = institution,
		precedent_event = precedent_event,
	)
	relationship.last_event = c.event_sequence
	relationship.semantic_tags = make_semantic_tags(
		.Relationship,
		.Ship,
		.Institution,
		.Governance,
		.Jurisdiction,
	); if stance == .Contested do relationship.semantic_tags = semantic_add(relationship.semantic_tags, .Contested)
	return true
}

institution_ship_relationship_description :: proc(c: ^Campaign, ship: Ship_ID) -> string {
	best := -1; for relationship, i in c.institution_ship_relationships[:c.institution_ship_relationship_count] do if relationship.ship == ship && (best < 0 || abs(relationship.strength) > abs(c.institution_ship_relationships[best].strength)) do best = i
	if best < 0 do return ""
	relationship :=
		c.institution_ship_relationships[best]; institution_at := institution_index(c, relationship.institution); if institution_at < 0 do return ""
	switch relationship.stance {case .Contested:
		return fmt.tprintf(
			"Jurisdiction contested by the %s",
			c.institutions[institution_at].name,
		); case .Stewardship:
		return fmt.tprintf(
			"Stewarded by the %s",
			c.institutions[institution_at].name,
		); case .Reconciled:
		return fmt.tprintf(
			"Authority reconciled with the %s",
			c.institutions[institution_at].name,
		)}
	return ""
}

institution_ship_passage_modifier :: proc(
	c: ^Campaign,
	ships: []Ship_ID,
) -> (
	i32,
	u64,
	Ship_ID,
	Institution_ID,
) {
	best := -1
	for relationship, i in c.institution_ship_relationships[:c.institution_ship_relationship_count] {
		selected :=
			false; for ship in ships do if ship == relationship.ship {selected = true; break}; if !selected do continue
		if relationship.stance == .Stewardship do continue
		if best < 0 || abs(relationship.strength) > abs(c.institution_ship_relationships[best].strength) || abs(relationship.strength) == abs(c.institution_ship_relationships[best].strength) && relationship.last_event > c.institution_ship_relationships[best].last_event do best = i
	}
	if best < 0 do return 0, 0, 0, 0
	relationship := c.institution_ship_relationships[best]
	modifier: i32 = 1; if relationship.stance == .Contested do modifier = -1
	return modifier, relationship.last_event, relationship.ship, relationship.institution
}

record_ship_autonomy :: proc(
	c: ^Campaign,
	detail: string,
	ship_id: Ship_ID,
	value: i32,
	cause_sequence: u64 = 0,
	related_ship_id := Ship_ID(0),
	community := Community_ID(0),
	institution_id := Institution_ID(0),
) {
	ship_at := ship_index(c, ship_id); if ship_at < 0 || !chronicle_can_record(c) do return
	ship := &c.ships[ship_at]; captain := ship.captain; created := false
	record_event(
		c,
		.Autonomy_Triggered,
		detail,
		ship_id,
		value,
		community,
		cause_sequence,
		captain,
		institution_id = institution_id,
		related_ship_id = related_ship_id,
	)
	autonomy_event := c.event_sequence
	if captain == 0 {
		if c.historical_figure_count >= MAX_HISTORICAL_FIGURES do return
		captain = emerge_historical_figure(
			c,
			CAPTAIN_NAMES[c.historical_figure_count],
			"ship captain",
			ship.community,
			ship.id,
			autonomy_event,
		)
		if captain == 0 do return
		ship.captain =
			captain; created = true; figure_at := historical_figure_index(c, captain); if figure_at >= 0 {figure := &c.historical_figures[figure_at]; figure.institution = captain_institution_for_role(ship.role); figure.passage_actions = 1; figure.semantic_tags = semantic_add(figure.semantic_tags, .Institution, .Passage, .Autonomy); _ = captain_set_relationship(c, captain, .Ship, u32(ship.id), 1, 1, 2, 1, 0, figure.origin_event); _ = captain_set_relationship(c, captain, .Community, u32(ship.community), 1, 0, 1, 0, 0, figure.origin_event); _ = captain_set_relationship(c, captain, .Institution, u32(figure.institution), 0, 1, 0, 1, 0, figure.origin_event)}
	}
	figure_at := historical_figure_index(
		c,
		captain,
	); if figure_at >= 0 && !created {figure := &c.historical_figures[figure_at]; figure.passage_actions += 1; figure.last_event = autonomy_event}
	institution := captain_institution_for_role(
		ship.role,
	); rule := precedent_event_for(c, .Ship_Sovereignty); if rule == 0 && ship.passage_trait == .Independent do rule = precedent_event_for(c, .Emergency_Command)
	if rule !=
	   0 {if institution_ship_relationship_index(c, institution, ship.id) < 0 do _ = set_institution_ship_relationship(c, institution, ship.id, .Contested, 1, autonomy_event, rule)} else if institution_ship_relationship_index(c, institution, ship.id) < 0 do _ = set_institution_ship_relationship(c, institution, ship.id, .Stewardship, 1, autonomy_event)
}

figure_for_institution :: proc(c: ^Campaign, institution: Institution_ID) -> int {
	for figure, i in c.historical_figures[:c.historical_figure_count] do if figure.active && figure.institution == institution do return i
	return -1
}

figure_for_settlement :: proc(c: ^Campaign, settlement: Settlement_ID) -> int {
	for figure, i in c.historical_figures[:c.historical_figure_count] do if figure.active && figure.settlement == settlement do return i
	return -1
}

advance_historical_figures :: proc(c: ^Campaign) {
	for &figure in c.historical_figures[:c.historical_figure_count] {
		if !figure.active do continue
		figure.age_years += 3
		if figure.age_years < 75 do continue
		cause := figure.last_event
		figure.active = false
		ship_at := ship_index(
			c,
			figure.ship,
		); was_captain := ship_at >= 0 && c.ships[ship_at].captain == figure.id
		figure.role = was_captain ? "retired ship captain" : "retired public figure"
		if was_captain do c.ships[ship_at].captain = 0
		record_event(
			c,
			.Historical_Figure_Changed,
			fmt.tprintf("%s retired from public office at age %d.", figure.name, figure.age_years),
			figure.ship,
			figure.age_years,
			figure.community,
			cause,
			figure.id,
			institution_id = figure.institution,
			settlement_id = figure.settlement,
		)
		figure.last_event = c.event_sequence
	}
}

record_figure_institution_response :: proc(
	c: ^Campaign,
	figure_id: Figure_ID,
	resolved: bool,
	cause: u64,
) {
	figure_at := historical_figure_index(c, figure_id)
	if figure_at < 0 do return
	figure := &c.historical_figures[figure_at]
	figure.public_actions += 1
	is_captain :=
		false; if ship_at := ship_index(c, figure.ship); ship_at >= 0 do is_captain = c.ships[ship_at].captain == figure.id
	if !is_captain {if resolved {figure.role = "senior delegate of the Broken Procession"} else {figure.role = "organizer contesting the Civic Assembly"}}
	detail :=
		resolved ? fmt.tprintf("%s's institutional petition received a funded response.", figure.name) : fmt.tprintf("%s recorded another unanswered institutional petition.", figure.name)
	record_event(
		c,
		.Historical_Figure_Changed,
		detail,
		figure.ship,
		figure.public_actions,
		figure.community,
		cause,
		figure.id,
		institution_id = figure.institution,
	)
	figure.last_event = c.event_sequence
}

find_community_by_name :: proc(c: ^Campaign, name: string) -> int {
	for community, i in c.communities[:c.community_count] do if community.name == name do return i
	return -1
}

ensure_broken_procession :: proc(c: ^Campaign) -> int {
	existing := find_community_by_name(c, "Broken Procession")
	if existing >= 0 do return existing
	if c.community_count >= MAX_COMMUNITIES do return -1
	index := c.community_count
	c.communities[index] = {
		id                = Community_ID(index + 1),
		name              = "Broken Procession",
		tolerance         = 3,
		settlement_desire = 2,
		trust             = 55,
		semantic_tags     = make_semantic_tags(.Entity, .Community),
	}
	c.community_count += 1
	return index
}

create_broken_procession_hook :: proc(c: ^Campaign, population: i32, sponsor: Ship_ID) -> int {
	if c.history_hook_count >= MAX_HISTORY_HOOKS do return -1
	community_index := ensure_broken_procession(c)
	if community_index < 0 do return -1
	community := &c.communities[community_index]
	community.population += population
	hook_index := c.history_hook_count
	c.history_hooks[hook_index] = {
		kind           = .Broken_Procession,
		stage          = .Contact,
		community      = community.id,
		ship           = sponsor,
		created_season = c.season,
		population     = population,
		detail         = fmt.tprintf(
			"%d people of the Broken Procession came aboard under %s's sponsorship.",
			population,
			c.ships[ship_index(c, sponsor)].name,
		),
		semantic_tags  = make_semantic_tags(.Memory, .Community, .Relationship),
	}
	c.history_hook_count += 1
	add_ship_history(
		c,
		sponsor,
		fmt.tprintf("Carried %d people of the Broken Procession.", population),
	)
	record_event(
		c,
		.Community_Joined,
		c.history_hooks[hook_index].detail,
		sponsor,
		population,
		community.id,
	)
	c.history_hooks[hook_index].origin_event = c.event_sequence
	c.history_hooks[hook_index].figure = emerge_historical_figure(
		c,
		"Tala Venn",
		"spokesperson for the Broken Procession",
		community.id,
		sponsor,
		c.history_hooks[hook_index].origin_event,
	)
	_ = set_ship_community_relationship(c, sponsor, community.id, .Sponsorship, 1)
	return hook_index
}

advance_history_hook_for_need :: proc(
	c: ^Campaign,
	community: Community_ID,
	ship: Ship_ID,
	resolved: bool,
) {
	for &hook in c.history_hooks[:c.history_hook_count] {
		if hook.kind != .Broken_Procession || hook.stage != .Obligation || hook.community != community || hook.ship != ship do continue
		hook.stage = .Consequence
		figure_index := historical_figure_index(c, hook.figure)
		if resolved {
			hook.detail = "The Broken Procession received a fleet council voice."
			add_ship_history(c, ship, "Sponsored the Broken Procession's council voice.")
			if figure_index >=
			   0 {figure := &c.historical_figures[figure_index]; figure.role = "delegate of the Broken Procession"; figure.public_actions += 1; figure.institution = 1}
		} else {
			hook.detail = "The Broken Procession's request for a fleet council voice went unanswered."
			add_ship_history(
				c,
				ship,
				"Returned with the Broken Procession's representation request unanswered.",
			)
			if figure_index >=
			   0 {figure := &c.historical_figures[figure_index]; figure.role = "organizer of the unanswered petition"; figure.public_actions += 1; figure.institution = 1}
		}
		record_event(
			c,
			.History_Continued,
			hook.detail,
			ship,
			hook.population,
			community,
			hook.obligation_event,
			hook.figure,
		)
		hook.consequence_event = c.event_sequence
		if figure_index >= 0 do c.historical_figures[figure_index].last_event = c.event_sequence
		c.institutions[0].legitimacy = clamp(
			c.institutions[0].legitimacy + (resolved ? 5 : -7),
			0,
			100,
		)
		record_event(
			c,
			.Institution_Changed,
			resolved ? "The Civic Assembly seated the Broken Procession's delegate." : "The Civic Assembly recorded the petition without seating its delegate.",
			ship,
			c.institutions[0].legitimacy,
			community,
			hook.consequence_event,
			hook.figure,
			c.institutions[0].id,
		)
		if figure_index >= 0 do c.historical_figures[figure_index].last_event = c.event_sequence
		_ = set_ship_community_relationship(
			c,
			ship,
			community,
			resolved ? .Advocated_For : .Unanswered_Obligation,
			resolved ? 2 : -2,
		)
		return
	}
}
