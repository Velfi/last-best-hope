package game

import "core:fmt"

Settlement_Proposal_Phase :: enum {
	None,
	Draft,
	Deliberation,
	Decision,
	Founded,
	Withdrawn,
}
Settlement_Procedure :: enum {
	Voluntary_Opt_In,
	Collective_Mandate,
	Council_Assignment,
}
Settlement_Stance :: enum {
	Strongly_Remain,
	Remain_With_Conditions,
	Undecided,
	Support_With_Conditions,
	Committed_To_Depart,
}
Settlement_Conduct :: enum {
	Voluntary,
	Negotiated,
	Engineered_Departure,
	Coercive_Assignment,
}
Founding_Requirement :: enum u8 {
	Population,
	Habitat,
	Agriculture,
	Foundry,
	Hospital,
	Food,
	Supplies,
	Equipment,
	Propellant,
	Maintenance,
}
Founding_Requirement_Mask :: distinct u16
Settlement_Founding_Requirements :: struct {
	world_class:                                                       Candidate_World_Class,
	minimum_population, maintenance_seasons, maintenance_basis_points: i32,
	cost:                                                              Fleet_Stock,
	unmet:                                                             Founding_Requirement_Mask,
	unmet_summary:                                                     string,
	waived:                                                            bool,
}
Continuing_Obligation :: enum u8 {
	Rescue,
	Communication,
	Civilian_Mobility,
	Archive_Access,
}
Continuing_Obligations :: distinct u8

continuing_obligation :: proc(value: Continuing_Obligation) -> Continuing_Obligations {
	return Continuing_Obligations(u8(1) << u8(value))
}

continuing_has :: proc(values: Continuing_Obligations, value: Continuing_Obligation) -> bool {
	return u8(values) & u8(continuing_obligation(value)) != 0
}

continuing_set :: proc(
	values: Continuing_Obligations,
	value: Continuing_Obligation,
	enabled: bool,
) -> Continuing_Obligations {
	bit := u8(continuing_obligation(value))
	return(
		enabled ? Continuing_Obligations(u8(values) | bit) : Continuing_Obligations(u8(values) &~ bit) \
	)
}

Ship_Consent :: struct {
	support, opposition, participation, confidence: i32,
	final_stance:                                   Settlement_Stance,
	reasons:                                        [MAX_PROPOSAL_REASONS]string,
	reason_events:                                  [MAX_PROPOSAL_REASONS]u64,
	reason_count:                                   int,
}

Ship_Settlement_Assessment :: struct {
	ship:                                                                                    Ship_ID,
	departure_score,
	remaining_score:                                                        i32,
	consent:                                                                                 Ship_Consent,
	requested,
	final_participation:                                                          bool,
	requires_mobility,
	requires_archive_access,
	requires_independence,
	requires_bonded_ship: bool,
	bonded_ship:                                                                             Ship_ID,
}

Settlement_Proposal :: struct {
	phase:                        Settlement_Proposal_Phase,
	name, destination:            string,
	celestial:                    Celestial_Reference,
	procedure:                    Settlement_Procedure,
	disclose_evidence:            bool,
	sovereign:                    bool,
	continuing_jurisdiction:      bool,
	charter_participation:        bool,
	obligations:                  Continuing_Obligations,
	requested_ships:              [MAX_SHIPS]bool,
	requested_communities:        [MAX_COMMUNITIES]bool,
	transfer_institutions:        [MAX_INSTITUTIONS]bool,
	transfer_archives:            [MAX_ARCHIVES]bool,
	assessments:                  [MAX_SHIPS]Ship_Settlement_Assessment,
	assessment_count:             int,
	projected_viability:          i32,
	founding_requirements:        Settlement_Founding_Requirements,
	council_exception_authorized: bool,
	waiver_account:               string,
	conduct:                      Settlement_Conduct,
	origin_event, decision_event: u64,
}

founding_requirement_set :: proc(
	mask: Founding_Requirement_Mask,
	value: Founding_Requirement,
) -> Founding_Requirement_Mask {return Founding_Requirement_Mask(
		u16(mask) | (u16(1) << u16(value)),
	)}
candidate_profile_for_reference :: proc(
	c: ^Campaign,
	r: Celestial_Reference,
) -> (
	Candidate_World_Profile,
	bool,
) {i := candidate_home_index(c, r); if i < 0 do return {}, false; return c.candidate_homes[i].profile,
		true}
settlement_founding_requirements :: proc(
	c: ^Campaign,
	p: ^Settlement_Proposal,
	population: i32,
) -> Settlement_Founding_Requirements {
	profile, ok := candidate_profile_for_reference(c, p.celestial); if !ok do return {}
	r := Settlement_Founding_Requirements {
		world_class              = profile.classification,
		maintenance_basis_points = profile.maintenance_basis_points,
	}
	if profile.classification ==
	   .Naturally_Habitable {r.minimum_population = 1000; r.maintenance_seasons = 3; r.cost = {
			food      = 12,
			supplies  = 8,
			equipment = 4,
		}} else {r.minimum_population = 1500; r.maintenance_seasons = 4; r.cost = {
			manufactured_goods = 16,
			supplies           = 16,
			equipment          = 12,
			propellant               = 8,
		}}
	// World-specific deficits increase opening stock and maintenance requirements.
	r.cost.supplies += i64(
		profile.construction_burden / 12,
	); r.cost.equipment += i64(max(profile.maintenance_basis_points - 10000, 0) / 1500); r.cost.propellant += i64(profile.radiation_exposure * 2)
	has_habitat, has_colony, has_agriculture, has_foundry, has_hospital :=
		false, false, false, false, false
	for a in p.assessments[:p.assessment_count] {if !a.final_participation do continue; at := ship_index(c, a.ship); if at < 0 do continue; #partial switch c.ships[at].role {case .Habitat:
			has_habitat = true; case .Colony:
			has_colony = true; case .Agriculture:
			has_agriculture = true; case .Foundry:
			has_foundry = true; case .Hospital:
			has_hospital = true}}
	if population < r.minimum_population do r.unmet = founding_requirement_set(r.unmet, .Population)
	if profile.classification ==
	   .Naturally_Habitable {if !has_habitat && !has_colony do r.unmet = founding_requirement_set(r.unmet, .Habitat); if !has_agriculture do r.unmet = founding_requirement_set(r.unmet, .Agriculture)} else {if !has_habitat do r.unmet = founding_requirement_set(r.unmet, .Habitat); if !has_foundry do r.unmet = founding_requirement_set(r.unmet, .Foundry); if !has_hospital do r.unmet = founding_requirement_set(r.unmet, .Hospital)}
	stock := c.material_economy.fleet.stock
	if stock.food < r.cost.food do r.unmet = founding_requirement_set(r.unmet, .Food); if stock.supplies < r.cost.supplies do r.unmet = founding_requirement_set(r.unmet, .Supplies); if stock.equipment < r.cost.equipment do r.unmet = founding_requirement_set(r.unmet, .Equipment); if stock.propellant < r.cost.propellant do r.unmet = founding_requirement_set(r.unmet, .Propellant)
	r.unmet_summary = fmt.tprintf(
		"waived founding requirements mask %04x for %v",
		u16(r.unmet),
		profile.classification,
	)
	return r
}

authorize_settlement_founding_exception :: proc(c: ^Campaign, named_requirements: string) -> bool {
	if c.settlement_proposal.phase != .Draft do return false
	preview := proposal_assess(
		c,
		c.settlement_proposal,
	); if u16(preview.proposal.founding_requirements.unmet) == 0 || named_requirements != preview.proposal.founding_requirements.unmet_summary do return false
	c.settlement_proposal =
		preview.proposal; c.settlement_proposal.council_exception_authorized = true; c.settlement_proposal.waiver_account = named_requirements; return true
}

Settlement_Proposal_Preview :: struct {
	valid:                                                      bool,
	message:                                                    string,
	proposal:                                                   Settlement_Proposal,
	participating_ships, participating_communities, population: i32,
	projected_fleet_cohesion, projected_colony_viability:       i32,
	conduct:                                                    Settlement_Conduct,
}

proposal_ship_requested :: proc(p: ^Settlement_Proposal, ship_at: int) -> bool {
	return ship_at >= 0 && ship_at < MAX_SHIPS && p.requested_ships[ship_at]
}

proposal_add_reason :: proc(m: ^Ship_Consent, detail: string, event: u64) {
	if m.reason_count >= MAX_PROPOSAL_REASONS do return
	m.reasons[m.reason_count] = detail
	m.reason_events[m.reason_count] = event
	m.reason_count += 1
}

proposal_bonded_ship :: proc(c: ^Campaign, ship: Ship_ID) -> (Ship_ID, i32, u64) {
	best := -1
	for relationship, i in c.ship_relationships[:c.ship_relationship_count] {
		if relationship.ship_a != ship && relationship.ship_b != ship do continue
		if best < 0 || relationship.strength > c.ship_relationships[best].strength do best = i
	}
	if best < 0 do return 0, 0, 0
	r := c.ship_relationships[best]
	return r.ship_a == ship ? r.ship_b : r.ship_a, r.strength, r.last_event
}

assess_ship_settlement :: proc(
	c: ^Campaign,
	p: ^Settlement_Proposal,
	ship_at: int,
) -> Ship_Settlement_Assessment {
	a: Ship_Settlement_Assessment
	if ship_at < 0 || ship_at >= c.ship_count do return a
	ship := c.ships[ship_at]
	a.ship = ship.id
	a.requested = p.requested_ships[ship_at]
	if !ship.active do return a
	community_at := community_index(c, ship.community)
	trust, grievance, desire := i32(50), i32(0), i32(0)
	if community_at >= 0 {
		community := c.communities[community_at]
		trust, grievance, desire =
			community.trust, community.grievance, community.settlement_desire
	}
	procedure_participation := i32(82)
	if p.procedure == .Collective_Mandate do procedure_participation = 90
	if p.procedure == .Council_Assignment do procedure_participation = 68
	a.consent.support = clamp(20 + desire * 7 + grievance * 4 + (100 - trust) / 5, 0, 100)
	if p.sovereign do a.consent.support = min(a.consent.support + 8, 100)
	if a.requested do a.consent.support = min(a.consent.support + 5, 100)
	a.consent.opposition = 100 - a.consent.support
	a.consent.participation = clamp(procedure_participation - grievance * 2, 30, 100)
	a.consent.confidence = clamp(
		45 + a.consent.participation / 2 + (p.disclose_evidence ? 15 : -15),
		0,
		100,
	)

	a.departure_score = desire * 5 + a.consent.support / 4 + grievance * 3 + (p.sovereign ? 10 : 0)
	a.remaining_score = 38 + trust / 5 + a.consent.opposition / 4 + (!p.disclose_evidence ? 12 : 0)
	if ship.role == .Colony do a.departure_score += 14
	if ship.role == .Habitat do a.departure_score += 6
	if ship.role == .Archive &&
	   !continuing_has(
			   p.obligations,
			   .Archive_Access,
		   ) {a.remaining_score += 9; a.requires_archive_access = true}
	if a.consent.opposition >= 45 &&
	   !continuing_has(
			   p.obligations,
			   .Civilian_Mobility,
		   ) {a.remaining_score += 10; a.requires_mobility = true}
	if !p.sovereign {a.remaining_score += 7; a.requires_independence = true}
	bond, strength, bond_event := proposal_bonded_ship(c, ship.id)
	if strength >= 2 {
		bond_at := ship_index(c, bond)
		if proposal_ship_requested(
			p,
			bond_at,
		) {a.departure_score += 8} else {a.remaining_score += 8; a.requires_bonded_ship = true; a.bonded_ship = bond}
		proposal_add_reason(
			&a.consent,
			fmt.tprintf(
				"Its recorded bond with %s weighs on the decision.",
				c.ships[bond_at].name,
			),
			bond_event,
		)
	}
	if grievance >= 3 do proposal_add_reason(&a.consent, "Unanswered petitions increased support for separate authority.", latest_event_for_community(c, ship.community))
	if !p.disclose_evidence do proposal_add_reason(&a.consent, "The destination record remains incomplete.", latest_event_of_kind(c, .Expedition_Returned))
	if a.requires_mobility do proposal_add_reason(&a.consent, "Internal opposition requested guaranteed civilian passage.", latest_event_for_community(c, ship.community))
	difference := a.departure_score - a.remaining_score
	switch {
	case difference <= -16:
		a.consent.final_stance = .Strongly_Remain
	case difference <= -5:
		a.consent.final_stance = .Remain_With_Conditions
	case difference < 5:
		a.consent.final_stance = .Undecided
	case difference < 16:
		a.consent.final_stance = .Support_With_Conditions
	case:
		a.consent.final_stance = .Committed_To_Depart
	}
	return a
}

proposal_assess :: proc(c: ^Campaign, draft: Settlement_Proposal) -> Settlement_Proposal_Preview {
	r: Settlement_Proposal_Preview
	working := draft
	r.proposal = working
	r.proposal.assessment_count = c.ship_count
	requested_community_count, low_consent_count, opposing_count := 0, 0, 0
	for i in 0 ..< c.community_count do if working.requested_communities[i] {requested_community_count += 1; if c.communities[i].grievance >= 3 do opposing_count += 1}
	for i in 0 ..< c.ship_count {
		a := assess_ship_settlement(c, &working, i)
		participates := false
		if a.requested {
			switch draft.procedure {
			case .Voluntary_Opt_In:
				participates =
					a.consent.final_stance == .Support_With_Conditions ||
					a.consent.final_stance == .Committed_To_Depart
			case .Collective_Mandate:
				participates = a.consent.support >= 60 && a.consent.participation >= 60
			case .Council_Assignment:
				participates = true
			}
		}
		a.final_participation = participates
		if participates {r.participating_ships += 1; r.population += c.ships[i].crew; if a.consent.support < 50 do low_consent_count += 1}
		r.proposal.assessments[i] = a
	}
	for i in 0 ..< c.community_count do if working.requested_communities[i] {r.participating_communities += 1; r.population += c.communities[i].population / 2}
	transferred_assets: i32; for yes in working.transfer_institutions do if yes do transferred_assets += 1; for yes in working.transfer_archives do if yes do transferred_assets += 1
	r.projected_colony_viability = clamp(
		i32(42) +
		r.participating_ships * 6 +
		transferred_assets * 3 +
		(continuing_has(working.obligations, .Rescue) ? 4 : 0),
		0,
		100,
	)
	r.proposal.projected_viability = r.projected_colony_viability
	r.projected_fleet_cohesion = clamp(
		c.strategic.cohesion - i32(low_consent_count * 5) + (r.participating_ships > 0 ? 2 : 0),
		0,
		100,
	)
	r.conduct = .Voluntary
	if low_consent_count > 0 || !working.charter_participation do r.conduct = .Negotiated
	if opposing_count > 0 && requested_community_count > 0 && transferred_assets >= i32(requested_community_count * 2) do r.conduct = .Engineered_Departure
	if working.procedure == .Council_Assignment && (low_consent_count > 0 || !continuing_has(working.obligations, .Civilian_Mobility)) do r.conduct = .Coercive_Assignment
	r.proposal.conduct = r.conduct
	r.proposal.founding_requirements = settlement_founding_requirements(
		c,
		&r.proposal,
		r.population,
	)
	profile, _ := candidate_profile_for_reference(
		c,
		r.proposal.celestial,
	); biosphere_disclosed := profile.biosphere == .None || r.proposal.disclose_evidence
	prepared :=
		(u16(r.proposal.founding_requirements.unmet) == 0 ||
			r.proposal.council_exception_authorized) &&
		biosphere_disclosed
	r.proposal.founding_requirements.waived = !prepared || r.proposal.council_exception_authorized
	r.valid =
		r.participating_ships > 0 &&
		r.participating_communities > 0 &&
		r.projected_colony_viability >= 45 &&
		prepared &&
		c.settlement_count < MAX_SETTLEMENTS
	r.message =
		r.valid ? "The proposal can proceed to a recorded decision." : u16(r.proposal.founding_requirements.unmet) != 0 ? r.proposal.founding_requirements.unmet_summary : "The proposal lacks a viable participating ship, community, or settlement package."
	return r
}

begin_settlement_proposal :: proc(
	c: ^Campaign,
	name, destination: string,
	candidate_index: int = -1,
) -> bool {
	if c.settlement_proposal.phase != .None && c.settlement_proposal.phase != .Withdrawn && c.settlement_proposal.phase != .Founded do return false
	if !c.candidate_home_known || c.candidate_home_count <= 0 do return false
	selected := candidate_index; if selected < 0 do selected = c.candidate_home_count - 1
	if selected < 0 || selected >= c.candidate_home_count do return false
	reference :=
		c.candidate_homes[selected].reference; if !celestial_reference_valid(c, reference) do return false
	p := Settlement_Proposal {
		phase                 = .Draft,
		name                  = name,
		destination           = destination,
		celestial             = reference,
		procedure             = .Voluntary_Opt_In,
		disclose_evidence     = true,
		sovereign             = true,
		charter_participation = true,
	}
	p.obligations = continuing_set(
		p.obligations,
		.Rescue,
		true,
	); p.obligations = continuing_set(p.obligations, .Communication, true); p.obligations = continuing_set(p.obligations, .Civilian_Mobility, true); p.obligations = continuing_set(p.obligations, .Archive_Access, true)
	record_event(
		c,
		.Settlement_Proposal_Started,
		fmt.tprintf("The fleet opened a settlement proposal for %s.", destination),
	)
	p.origin_event = c.event_sequence; c.settlement_proposal = p
	return true
}

begin_passage_settlement_proposal :: proc(c: ^Campaign, p: ^Passage) -> bool {
	if c.current_situation.phase != .None && c.current_situation.phase != .Resolved do return false
	if c.candidate_home_count ==
	   0 {_, ok := discover_candidate_home(c, p.id); if !ok do return false}; c.colony_package_ready = true
	s, ok := make_settlement_situation(c); if !ok do return false
	c.current_situation = s; c.next_situation_id += 1
	record_event(
		c,
		.Situation_Proposed,
		s.proposal,
		s.initiator,
		i32(s.kind),
		s.affected_community,
		s.origin_event,
	); c.current_situation.proposal_event = c.event_sequence
	return true
}

refresh_settlement_proposal :: proc(c: ^Campaign) -> Settlement_Proposal_Preview {
	r := proposal_assess(c, c.settlement_proposal); c.settlement_proposal = r.proposal; return r
}

open_settlement_deliberation :: proc(c: ^Campaign) -> bool {
	if c.settlement_proposal.phase != .Draft do return false
	r := refresh_settlement_proposal(c); c.settlement_proposal.phase = .Deliberation
	record_event(
		c,
		.Settlement_Deliberated,
		fmt.tprintf(
			"%d ships published positions on %s.",
			r.proposal.assessment_count,
			r.proposal.destination,
		),
		cause_sequence = r.proposal.origin_event,
	)
	return true
}

revise_settlement_proposal :: proc(c: ^Campaign) -> bool {
	if c.settlement_proposal.phase != .Deliberation do return false
	c.settlement_proposal.phase = .Draft; return true
}

withdraw_settlement_proposal :: proc(c: ^Campaign) -> bool {
	if c.settlement_proposal.phase != .Draft && c.settlement_proposal.phase != .Deliberation do return false
	record_event(
		c,
		.Settlement_Proposal_Withdrawn,
		fmt.tprintf(
			"The proposal for %s was withdrawn without transferring ships or assets.",
			c.settlement_proposal.destination,
		),
		cause_sequence = c.settlement_proposal.origin_event,
	)
	c.settlement_proposal.phase = .Withdrawn; return true
}

proposal_enact_precedents :: proc(c: ^Campaign, p: ^Settlement_Proposal) {
	source := p.decision_event; if source == 0 do return
	if p.procedure != .Council_Assignment && p.conduct != .Coercive_Assignment do _ = enact_precedent_after_event(c, .Consent_Of_The_Settled, "Settlement participation required a recorded mandate.", source)
	if p.procedure == .Voluntary_Opt_In do _ = enact_precedent_after_event(c, .Right_Of_Departure, "Ships could accept or refuse permanent departure.", source)
	if p.procedure == .Council_Assignment do _ = enact_precedent_after_event(c, .Council_Assignment, "The council assigned ships to a settlement package.", source)
	if p.conduct == .Engineered_Departure do _ = enact_precedent_after_event(c, .Proportionate_Asset_Division, "The fleet recorded how institutions and archives were divided at departure.", source)
	if p.sovereign do _ = enact_precedent_after_event(c, .Founding_Independence, "The founding settlement departed under independent authority.", source)
	if p.continuing_jurisdiction do _ = enact_precedent_after_event(c, .Continuing_Fleet_Jurisdiction, "Fleet jurisdiction continued after settlement.", source)
}

finalize_settlement_proposal :: proc(c: ^Campaign) -> bool {
	if c.settlement_proposal.phase != .Deliberation do return false
	r := proposal_assess(c, c.settlement_proposal); if !r.valid do return false
	p := &r.proposal; p.phase = .Decision
	record_event(
		c,
		.Settlement_Decided,
		fmt.tprintf(
			"%d ships entered the founding decision for %s.",
			r.participating_ships,
			p.destination,
		),
		cause_sequence = p.origin_event,
	); p.decision_event = c.event_sequence
	settlement_id := Settlement_ID(
		c.settlement_count + 1,
	); settlement := &c.settlements[c.settlement_count]
	settlement.id =
		settlement_id; settlement.name = p.name; settlement.population = r.population; settlement.viability = r.projected_colony_viability; settlement.liberty = p.sovereign ? 75 : 45; settlement.founded_season = c.season; settlement.report_due = c.season + 2; settlement.active = true; settlement.founding_conduct = p.conduct; settlement.founding_procedure = p.procedure; settlement.continuing_obligations = p.obligations; settlement.proposal_event = p.origin_event; settlement.decision_event = p.decision_event; settlement.fleet_relationship = 2
	settlement.region = p.destination
	settlement.celestial = p.celestial
	settlement.world_class =
		p.founding_requirements.world_class; settlement.founding_maintenance_seasons = p.founding_requirements.maintenance_seasons; settlement.maintenance_basis_points = p.founding_requirements.maintenance_basis_points; settlement.waived_founding_requirements = p.council_exception_authorized ? u16(p.founding_requirements.unmet) : 0; settlement.waiver_account = p.waiver_account
	world_profile, _ := candidate_profile_for_reference(
		c,
		p.celestial,
	); settlement.biosphere_evidence = world_profile.biosphere; settlement.biosphere_disclosed = world_profile.biosphere == .None || p.disclose_evidence; settlement.preservation_obligation = world_profile.biosphere != .None; settlement.restricted_development = world_profile.biosphere != .None
	if !p.council_exception_authorized && !fleet_stock_spend(c, p.founding_requirements.cost) do return false
	if p.council_exception_authorized {settlement.viability = max(settlement.viability - 10, 20); settlement.initial_grievance = max(settlement.initial_grievance, 3)}
	if p.conduct ==
	   .Engineered_Departure {settlement.initial_grievance = 4; settlement.fleet_relationship = -1; c.strategic.cohesion = max(c.strategic.cohesion - 5, 0)}
	if p.conduct ==
	   .Coercive_Assignment {settlement.initial_grievance = 8; settlement.fleet_relationship = -3; c.strategic.cohesion = max(c.strategic.cohesion - 12, 0)}
	for a in p.assessments[:p.assessment_count] {
		if !a.final_participation do continue
		si := ship_index(c, a.ship); if si < 0 || !c.ships[si].active do continue
		ship := &c.ships[si]; ship.active = false; ship.departure = .Settlement; ship.committed = false; ship.history_count += 1; add_ship_history(c, ship.id, fmt.tprintf("Founding vessel of %s.", p.name)); settlement.participating_ships[settlement.participating_ship_count] = ship.id; settlement.participating_ship_count += 1
		if settlement.founder_ship ==
		   0 {settlement.founder_ship = ship.id; settlement.founding_community = ship.community}
		if captain_at := historical_figure_index(c, ship.captain);
		   captain_at >=
		   0 {c.historical_figures[captain_at].settlement = settlement_id; c.historical_figures[captain_at].institution = 0; c.historical_figures[captain_at].role = "founding settlement captain"}
	}
	for requested, i in p.requested_communities[:c.community_count] do if requested {community := &c.communities[i]; people := community.population / 2; community.population -= people; settlement.participating_communities[settlement.participating_community_count] = community.id; settlement.participating_community_count += 1; if settlement.initial_grievance > community.grievance do community.grievance = settlement.initial_grievance}
	for transfer, i in p.transfer_institutions do if transfer do c.institutions[i].active = false
	for transfer, i in p.transfer_archives do if transfer {c.archives[i].preserved = false; if settlement.archive_id == 0 do settlement.archive_id = c.archives[i].id}
	public_detail := fmt.tprintf(
		"%s was founded by %d ships under a recorded %v procedure.",
		p.name,
		settlement.participating_ship_count,
		p.procedure,
	)
	authoritative := fmt.tprintf(
		"The founding was classified %v from participation, disclosure, charter, and assignment records.",
		p.conduct,
	)
	settlement.public_founding_account =
		public_detail; settlement.authoritative_founding_account = authoritative
	record_event(
		c,
		.Settlement_Founded,
		public_detail,
		settlement.founder_ship,
		settlement.population,
		settlement.founding_community,
		p.decision_event,
		settlement_id = settlement_id,
		authoritative_detail = authoritative,
		account_status = p.conduct == .Voluntary ? .Uncontested : .Contradicted,
	)
	settlement.founding_event =
		c.event_sequence; settlement.last_report_event = c.event_sequence; c.settlement_count += 1
	c.colony_package_ready = false; c.strategic.cohesion = min(c.strategic.cohesion + 8, 100)
	if continuing_has(p.obligations, .Rescue) do _ = add_promise(c, settlement.founding_community, c.season + 4, fmt.tprintf("Maintain rescue passage with %s.", p.name))
	if continuing_has(p.obligations, .Communication) do _ = add_promise(c, settlement.founding_community, c.season + 4, fmt.tprintf("Maintain communications with %s.", p.name))
	proposal_enact_precedents(c, p)
	if settlement.archive_id == 0 && continuing_has(p.obligations, .Archive_Access) do _ = establish_copied_archive(c, c.settlement_count - 1, settlement.founding_event)
	p.phase = .Founded; c.settlement_proposal = p^; refresh_semantic_tags(c)
	return true
}
