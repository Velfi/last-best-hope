package game

import "core:fmt"

institution_form_record :: proc(form: Institution_Form) -> string {switch form {case .Fleetwide:
		return "returned to fleetwide operation"; case .Ship_Bound:
		return "was assigned to a ship"; case .Settlement_Based:
		return "was assigned to a settlement"; case .Federated:
		return "entered a federated placement"; case .Captured:
		return "was placed under another authority"; case .Dissolved:
		return "was dissolved"}; return "recorded a placement change"}

MAX_TRANSFORMATION_RECORDS :: 32
MAX_COMMUNITY_RESIDENCIES :: 16

Ship_Lifecycle :: enum {
	Serving,
	Mothballed,
	Retired,
	Divided_Command,
	Transformed,
}
Ship_Entry_Kind :: enum {
	Founding,
	Construction,
	Accession,
	Rescue,
	Merger,
	Inheritance,
	Division,
}
Institution_Form :: enum {
	Ship_Bound,
	Fleetwide,
	Settlement_Based,
	Federated,
	Captured,
	Dissolved,
}
Transformation_Kind :: enum {
	Retirement,
	Succession,
	Division,
	Role_Change,
	Refit,
	New_Ship,
}

Ship_Transformation_Record :: struct {
	kind:                            Transformation_Kind,
	ship, predecessor, related_ship: Ship_ID,
	from_role, to_role:              Role,
	event:                           u64,
	detail:                          string,
}
Ship_Continuity :: struct {
	ship:                          Ship_ID,
	lifecycle:                     Ship_Lifecycle,
	entry:                         Ship_Entry_Kind,
	predecessor, related_ship:     Ship_ID,
	origin_event, last_event:      u64,
	operational_role, social_role: string,
	autonomy_pressure:             i32,
}
Community_Residency :: struct {
	community:  Community_ID,
	ship:       Ship_ID,
	settlement: Settlement_ID,
	population: i32,
	isolated:   bool,
	last_event: u64,
}
Institution_Placement :: struct {
	institution: Institution_ID,
	form:        Institution_Form,
	ship:        Ship_ID,
	settlement:  Settlement_ID,
	last_event:  u64,
}
Fleet_Transformation_State :: struct {
	initialized:     bool,
	continuity:      [MAX_SHIPS]Ship_Continuity,
	records:         [MAX_TRANSFORMATION_RECORDS]Ship_Transformation_Record,
	record_count:    int,
	residencies:     [MAX_COMMUNITY_RESIDENCIES]Community_Residency,
	residency_count: int,
	placements:      [MAX_INSTITUTIONS]Institution_Placement,
}

initialize_fleet_continuity :: proc(c: ^Campaign) {
	if c.transformations.initialized do return; c.transformations.initialized = true
	for ship, i in c.ships[:c.ship_count] {c.transformations.continuity[i] = {
			ship             = ship.id,
			lifecycle        = .Serving,
			entry            = .Founding,
			operational_role = ship_operational_role_name(ship.operational_role),
			social_role      = fmt.tprintf("%v ship", ship.role),
		}}
	for institution, i in c.institutions {if institution.id != 0 do c.transformations.placements[i] = {
			institution = institution.id,
			form        = .Fleetwide,
		}}
	for community in c.communities[:c.community_count] {ship := c.ships[c.transformations.residency_count % c.ship_count].id; c.transformations.residencies[c.transformations.residency_count] = {
			community  = community.id,
			ship       = ship,
			population = community.population,
		}; c.transformations.residency_count += 1}
}

record_transformation :: proc(
	c: ^Campaign,
	kind: Transformation_Kind,
	ship, predecessor, related: Ship_ID,
	from_role, to_role: Role,
	detail: string,
	cause: u64 = 0,
) -> bool {
	if c.transformations.record_count >= MAX_TRANSFORMATION_RECORDS do return false
	record_event(
		c,
		.History_Continued,
		detail,
		ship,
		i32(kind),
		cause_sequence = cause,
		related_ship_id = related,
	)
	i :=
		c.transformations.record_count; c.transformations.record_count += 1; c.transformations.records[i] = {
		kind         = kind,
		ship         = ship,
		predecessor  = predecessor,
		related_ship = related,
		from_role    = from_role,
		to_role      = to_role,
		event        = c.event_sequence,
		detail       = detail,
	}; return true
}

ship_continuity_index :: proc(c: ^Campaign, id: Ship_ID) -> int {initialize_fleet_continuity(c)
	for item, i in c.transformations.continuity[:c.ship_count] do if item.ship == id do return i
	return -1}

mothball_ship :: proc(c: ^Campaign, id: Ship_ID) -> bool {i := ship_index(c, id); ci :=
		ship_continuity_index(c, id)
	if i < 0 || ci < 0 || !c.ships[i].active || c.ships[i].committed do return false
	c.ships[i].active = false
	c.transformations.continuity[ci].lifecycle = .Mothballed
	detail := fmt.tprintf("%s entered mothball custody with its fittings intact.", c.ships[i].name)
	ok := record_transformation(c, .Retirement, id, 0, 0, c.ships[i].role, c.ships[i].role, detail)
	c.transformations.continuity[ci].last_event = c.event_sequence
	return ok}
restore_mothballed_ship :: proc(c: ^Campaign, id: Ship_ID) -> bool {i := ship_index(c, id); ci :=
		ship_continuity_index(c, id)
	if i < 0 || ci < 0 || c.transformations.continuity[ci].lifecycle != .Mothballed do return false
	c.ships[i].active = true
	c.transformations.continuity[ci].lifecycle = .Serving
	detail := fmt.tprintf("%s returned from mothball custody.", c.ships[i].name)
	return record_transformation(
		c,
		.Refit,
		id,
		0,
		0,
		c.ships[i].role,
		c.ships[i].role,
		detail,
		c.transformations.continuity[ci].last_event,
	)}

severe_damage_loss_selected :: proc(seed: u64, id: Ship_ID) -> bool {_ = id; mixed :=
		seed ~ 0x9e3779b97f4a7c15
	mixed ~= (mixed >> 30)
	mixed *= 0xbf58476d1ce4e5b9
	mixed ~= (mixed >> 27)
	return mixed % 100 < 18}

surface_attributable_severe_setback :: proc(c: ^Campaign, id: Ship_ID, cause: u64) -> bool {si :=
		ship_index(c, id)
	if si < 0 || !c.ships[si].active || c.ships[si].damage < 3 || cause == 0 do return false
	attributable := 0
	for e in c.events[:c.event_count] do if e.ship_id == id && (e.kind == .Ship_Damaged || e.kind == .Fleet_Hazard && e.value > 0) do attributable += 1
	if attributable < 2 do return false
	ship := &c.ships[si]
	name := ship.name
	prior_loss := false
	for e in c.events[:c.event_count] do if e.kind == .Ship_Lost do prior_loss = true
	if !prior_loss && severe_damage_loss_selected(c.initial_seed, id) {initialize_fleet_continuity(
			c,
		)
		ci := ship_continuity_index(c, id)
		ship.active = false
		ship.departure = .Lost
		if ci >= 0 {c.transformations.continuity[ci].lifecycle = .Retired
			c.transformations.continuity[ci].last_event = cause}
		record_event(
			c,
			.Ship_Lost,
			fmt.tprintf("%s was lost after repeated attributable severe-damage records.", name),
			id,
			ship.damage,
			cause_sequence = cause,
		)
		loss_event := c.event_sequence
		if captain_at := historical_figure_index(c, ship.captain);
		   captain_at >= 0 {captain := &c.historical_figures[captain_at]; captain.active = false
			captain.role = "captain lost after cumulative damage"
			record_event(
				c,
				.Historical_Figure_Changed,
				fmt.tprintf("%s was recorded among %s's lost crew.", captain.name, name),
				id,
				community = ship.community,
				cause_sequence = loss_event,
				figure_id = captain.id,
			)
			captain.last_event = c.event_sequence}
		_ = add_obligation(
			c,
			.Fleet_Maintenance,
			fmt.tprintf("Successor or role substitution for %s", name),
			1,
			2,
			2,
			0,
			2,
			ship = id,
			cause = loss_event,
		)
		record_event(
			c,
			.Need_Surfaced,
			fmt.tprintf(
				"%s's loss opened an immediate successor, migration, import, or service-contraction decision.",
				name,
			),
			id,
			ship.damage,
			cause_sequence = loss_event,
		)
		return true}
	if !mothball_ship(c, id) do return false
	_ = add_obligation(
		c,
		.Fleet_Maintenance,
		fmt.tprintf("Recovery or role substitution for %s", name),
		1,
		2,
		2,
		0,
		2,
		ship = id,
		cause = cause,
	)
	record_event(
		c,
		.Need_Surfaced,
		fmt.tprintf(
			"%s left service after repeated recorded damage; repair, replacement, or role substitution is now required.",
			name,
		),
		id,
		c.ships[si].damage,
		cause_sequence = cause,
	)
	return true}

retire_ship :: proc(c: ^Campaign, id: Ship_ID, successor: Ship_ID = 0) -> bool {i := ship_index(
		c,
		id,
	)
	ci := ship_continuity_index(c, id)
	if i < 0 || ci < 0 || !c.ships[i].active || c.ships[i].committed do return false
	c.ships[i].active = false
	c.transformations.continuity[ci].lifecycle = .Retired
	detail := fmt.tprintf("%s retired from fleet service.", c.ships[i].name)
	if successor != 0 do detail = fmt.tprintf("%s retired; its standing obligations passed to ship %d.", c.ships[i].name, u32(successor))
	return record_transformation(
		c,
		.Retirement,
		id,
		id,
		successor,
		c.ships[i].role,
		c.ships[i].role,
		detail,
	)}

refit_ship_role :: proc(
	c: ^Campaign,
	id: Ship_ID,
	new_role: Role,
	social_role: string,
) -> bool {i := ship_index(c, id); ci := ship_continuity_index(c, id); if i < 0 || ci < 0 || !c.ships[i].active || c.ships[i].committed do return false
	old := c.ships[i].role
	if old == new_role do return false
	c.ships[i].role = new_role
	c.transformations.continuity[ci].lifecycle = .Transformed
	c.transformations.continuity[ci].operational_role = fmt.tprintf("%v", new_role)
	c.transformations.continuity[ci].social_role = social_role
	c.transformations.continuity[ci].autonomy_pressure += 2
	detail := fmt.tprintf(
		"%s refit from %v duty to %v duty; its recorded social role is %s.",
		c.ships[i].name,
		old,
		new_role,
		social_role,
	)
	return record_transformation(
		c,
		.Refit,
		id,
		id,
		0,
		old,
		new_role,
		detail,
		c.transformations.continuity[ci].last_event,
	)}

divide_ship_command :: proc(c: ^Campaign, id: Ship_ID) -> bool {ci := ship_continuity_index(c, id)
	i := ship_index(c, id)
	if ci < 0 || i < 0 || !c.ships[i].active do return false
	c.transformations.continuity[ci].lifecycle = .Divided_Command
	c.transformations.continuity[ci].autonomy_pressure += 2
	return record_transformation(
		c,
		.Division,
		id,
		id,
		0,
		c.ships[i].role,
		c.ships[i].role,
		fmt.tprintf(
			"%s recorded two operational commands pending reconciliation.",
			c.ships[i].name,
		),
		c.transformations.continuity[ci].last_event,
	)}

succeed_captain :: proc(
	c: ^Campaign,
	ship_id: Ship_ID,
	name: string,
	reinterpretation: string,
) -> bool {si := ship_index(c, ship_id); if si < 0 do return false; ship := &c.ships[si]; prior :=
		ship.captain
	cause: u64
	if prior != 0 {pi := historical_figure_index(c, prior); if pi >= 0 {c.historical_figures[pi].active =
				false
			c.historical_figures[pi].role = "predecessor captain"
			cause = c.historical_figures[pi].last_event}}
	id := emerge_historical_figure(c, name, "ship captain", ship.community, ship.id, cause)
	if id == 0 do return false
	fi := historical_figure_index(c, id)
	if fi >= 0 {figure := &c.historical_figures[fi]; figure.predecessor = prior
		figure.institution = captain_institution_for_role(ship.role)
		_ = captain_set_relationship(
			c,
			id,
			.Ship,
			u32(ship.id),
			1,
			1,
			2,
			1,
			0,
			figure.origin_event,
		)
		_ = captain_set_relationship(
			c,
			id,
			.Community,
			u32(ship.community),
			1,
			0,
			1,
			0,
			0,
			figure.origin_event,
		)
		if figure.institution != 0 do _ = captain_set_relationship(c, id, .Institution, u32(figure.institution), 0, 1, 0, 1, 0, figure.origin_event)
		if prior != 0 do _ = captain_set_relationship(c, id, .Captain, u32(prior), 0, 2, 0, 1, 0, figure.origin_event)}
	ship.captain = id
	detail := fmt.tprintf("%s succeeded to %s's captaincy.", name, ship.name)
	if reinterpretation != "" do detail = fmt.tprintf("%s %s", detail, reinterpretation)
	record_event(
		c,
		.Historical_Figure_Changed,
		detail,
		ship.id,
		community = ship.community,
		cause_sequence = cause,
		figure_id = id,
	)
	return true}

migrate_community :: proc(
	c: ^Campaign,
	community: Community_ID,
	population: i32,
	to_ship: Ship_ID = 0,
	to_settlement: Settlement_ID = 0,
	consent: bool = false,
) -> bool {initialize_fleet_continuity(c); ci := community_index(c, community); if ci < 0 || population <= 0 || population > c.communities[ci].population || !consent || (to_ship == 0) == (to_settlement == 0) do return false
	if to_ship != 0 {si := ship_index(c, to_ship); if si < 0 || !c.ships[si].active do return false
		capacity := max(c.ships[si].crew * 100, 1000)
		resident: i32
		for r in c.transformations.residencies[:c.transformations.residency_count] do if r.ship == to_ship do resident += r.population
		if resident + population > capacity do return false}
	if to_settlement != 0 {si := settlement_index(c, to_settlement); if si < 0 || !c.settlements[si].active || c.settlements[si].population + population > max(c.settlements[si].viability * 500, 1000) do return false
		c.settlements[si].population += population}
	if c.transformations.residency_count >= MAX_COMMUNITY_RESIDENCIES do return false
	c.communities[ci].trust = clamp(c.communities[ci].trust + 1, 0, 100)
	r := &c.transformations.residencies[c.transformations.residency_count]
	c.transformations.residency_count += 1
	r^ = {
		community  = community,
		ship       = to_ship,
		settlement = to_settlement,
		population = population,
	}
	detail := fmt.tprintf(
		"%d people of %s migrated by recorded consent.",
		population,
		c.communities[ci].name,
	)
	record_event(
		c,
		.Community_Joined,
		detail,
		to_ship,
		population,
		community,
		settlement_id = to_settlement,
	)
	r.last_event = c.event_sequence
	return true}

isolate_community :: proc(
	c: ^Campaign,
	community: Community_ID,
) -> bool {initialize_fleet_continuity(c); for &r in c.transformations.residencies[:c.transformations.residency_count] do if r.community == community {r.isolated = true; record_event(c, .Community_Memory_Changed, "The community lost regular contact but retained a return channel.", r.ship, r.population, community, settlement_id = r.settlement, cause_sequence = r.last_event); r.last_event = c.event_sequence; return true}
	return false}

place_institution :: proc(
	c: ^Campaign,
	id: Institution_ID,
	form: Institution_Form,
	ship: Ship_ID = 0,
	settlement: Settlement_ID = 0,
	cause: u64 = 0,
) -> bool {initialize_fleet_continuity(c); ii := institution_index(c, id); if ii < 0 do return false
	if form == .Ship_Bound && ship_index(c, ship) < 0 do return false
	if form == .Settlement_Based && settlement_index(c, settlement) < 0 do return false
	p := &c.transformations.placements[ii]
	p.form = form
	p.ship = ship
	p.settlement = settlement
	c.institutions[ii].active = form != .Dissolved
	record_event(
		c,
		.Institution_Changed,
		fmt.tprintf("%s %s.", c.institutions[ii].name, institution_form_record(form)),
		ship,
		i32(form),
		institution_id = id,
		settlement_id = settlement,
		cause_sequence = cause,
	)
	p.last_event = c.event_sequence
	return true}

add_historical_ship :: proc(
	c: ^Campaign,
	name: string,
	role: Role,
	entry: Ship_Entry_Kind,
	predecessor: Ship_ID,
	related: Ship_ID = 0,
) -> Ship_ID {initialize_fleet_continuity(c); if entry == .Founding || predecessor == 0 do return 0
	pi := ship_index(c, predecessor)
	if pi < 0 do return 0
	slot := -1
	if c.ship_count < MAX_SHIPS {slot = c.ship_count; c.ship_count += 1}
	else {for item, i in c.transformations.continuity[:c.ship_count] do if item.lifecycle == .Retired {slot = i; break}}
	if slot < 0 do return 0
	max_id: u32
	for ship in c.ships[:c.ship_count] do max_id = max(max_id, u32(ship.id))
	id := Ship_ID(max_id + 1)
	seed := ship_construction_identity_seed(c.initial_seed, id)
	lineage := c.ships[pi].construction_seed
	community := c.ships[pi].community
	predecessor_name := c.ships[pi].name
	c.ships[slot] = {
		id                   = id,
		name                 = name,
		construction_seed    = seed,
		construction_lineage = lineage,
		construction_style   = c.ships[pi].construction_style,
		generator_kind       = c.ships[pi].generator_kind,
		role                 = role,
		hull_class           = .Fleet_Ship,
		hull_archetype       = ship_hull_archetype_from_role(seed, role, .Fleet_Ship),
		operational_role     = ship_operational_role_for_hull(
			seed,
			role,
			ship_hull_archetype_from_role(seed, role, .Fleet_Ship),
		),
		mass_tonnes          = 40000,
		power                = 7,
		crew                 = 200,
		community            = community,
		active               = true,
	}
	c.transformations.continuity[slot] = {
		ship             = id,
		lifecycle        = .Serving,
		entry            = entry,
		predecessor      = predecessor,
		related_ship     = related,
		operational_role = fmt.tprintf("%v", role),
		social_role      = fmt.tprintf("%v ship", role),
	}
	detail := fmt.tprintf(
		"%s entered the fleet by %v from %s's recorded line.",
		name,
		entry,
		predecessor_name,
	)
	_ = record_transformation(c, .New_Ship, id, predecessor, related, role, role, detail)
	c.transformations.continuity[slot].origin_event = c.event_sequence
	c.transformations.continuity[slot].last_event = c.event_sequence
	return id}

advance_fleet_transformations :: proc(c: ^Campaign) {
	initialize_fleet_continuity(c)
	// Seasonal hazards and prior expeditions accumulate in the same attributable
	// record. Evaluate them before succession so losses are not Passage-only.
	for ship in c.ships[:c.ship_count] {if ship.active && !ship.committed && ship.damage >= 3 {cause := latest_event_for_ship(c, ship.id); if surface_attributable_severe_setback(c, ship.id, cause) do return}}
	// One scheduled succession per fifteen seasons keeps the roster legible while
	// ensuring long chronicles do not silently preserve the founding list forever.
	if c.season <= 0 || c.season % 15 != 0 do return
	if !major_story_beat_ready(c) do return
	for ship in c.ships[:c.ship_count] {
		ci := ship_continuity_index(
			c,
			ship.id,
		); if ci < 0 || !ship.active || ship.committed || c.transformations.continuity[ci].entry != .Founding do continue
		old := ship.id; role := ship.role; name := fmt.tprintf("%s Successor", ship.name)
		if retire_ship(
			c,
			old,
		) {_ = add_historical_ship(c, name, role, .Inheritance, old); mark_major_story_beat(c)}
		break
	}
}
