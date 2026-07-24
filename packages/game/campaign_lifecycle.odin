package game

import "core:fmt"
import "core:testing"

destroy_owned_string :: proc(value: string) {
	when ODIN_TEST do return
	if raw_data(value) != nil do delete(value)
}

destroy_public_question_strings :: proc(q: ^Public_Question) {
	destroy_owned_string(
		q.title,
	); destroy_owned_string(q.request); destroy_owned_string(q.jurisdiction_reason); destroy_owned_string(q.lead.name); destroy_owned_string(q.lead.reason); destroy_owned_string(q.objection_text)
	for actor in q.actors {destroy_owned_string(actor.name); destroy_owned_string(actor.reason)}
	for response in q.responses {destroy_owned_string(response.label); destroy_owned_string(response.consequence)}
}

campaign_destroy :: proc(c: ^Campaign) {
	if !c.owns_strings {
		when !ODIN_TEST do if c.galaxy != nil {galaxy_destroy(c.galaxy); free(c.galaxy)}
		when !ODIN_TEST do if c.far_engagement != nil do free(c.far_engagement)
		dark_continuum_destroy_storage(&c.outer_dark.continuum)
		delete(c.dark_fleet_atlas)
		delete(c.dark_organism_observations)
		delete(c.dark_strategy_records)
		delete(c.dark_unresolved_voyages)
		delete(c.dark_relays)
		delete(c.habitable_contacts)
		delete(c.passage.local_habitable_contacts)
		delete(c.events)
		delete(c.settlement_economies.economies)
		delete(c.settlement_economies.archived)
		delete(c.settlement_economies.flows)
		delete(c.settlement_economies.political_links)
		c^ = {}
		return
	}
	if c.far_engagement != nil {
		destroy_owned_string(c.far_engagement.decision.title)
		destroy_owned_string(c.far_engagement.decision.situation)
		destroy_owned_string(c.far_engagement.decision.forecast)
		destroy_owned_string(c.far_engagement.decision.default_text)
		for label in c.far_engagement.decision.labels do destroy_owned_string(label)
		for consequence in c.far_engagement.decision.consequences do destroy_owned_string(consequence)
		for group in c.far_engagement.groups {
			destroy_owned_string(group.name)
			destroy_owned_string(group.commander)
		}
		for contact in c.far_engagement.contacts do destroy_owned_string(contact.name)
		for record in c.far_engagement.records do destroy_owned_string(record.text)
		destroy_owned_string(c.far_engagement.result.ending)
		when !ODIN_TEST do free(c.far_engagement)
	}
	for ship in c.ships {destroy_owned_string(ship.name); destroy_owned_string(ship.history_note); destroy_owned_string(ship.current_position); destroy_owned_string(ship.current_commitment); destroy_owned_string(ship.pending_claim); for record in ship.history_records do destroy_owned_string(record)}
	for community in c.communities do destroy_owned_string(community.name)
	for attribute in c.attributes {destroy_owned_string(attribute.name); destroy_owned_string(attribute.description)}
	for institution in c.institutions {destroy_owned_string(institution.name); destroy_owned_string(institution.capability)}
	for figure in c.historical_figures {destroy_owned_string(figure.name); destroy_owned_string(figure.role)}
	for archive in c.archives do destroy_owned_string(archive.name)
	for precedent in c.precedents do destroy_owned_string(precedent.detail)
	for need in c.needs do destroy_owned_string(need.detail)
	for call in c.compact.calls {
		destroy_owned_string(call.title)
		destroy_owned_string(call.stakes)
		destroy_owned_string(call.autonomous_trajectory)
		for approach in call.approaches {
			destroy_owned_string(approach.label)
			destroy_owned_string(approach.operational_effect)
			destroy_owned_string(approach.exposure_summary)
		}
		for offer in call.offers do destroy_owned_string(offer.condition_detail)
	}
	destroy_owned_string(c.compact.active.intent)
	destroy_owned_string(c.compact.active.charter.intent)
	destroy_owned_string(c.compact.active.charter.undertaking_intent.promised_attempt)
	destroy_owned_string(c.compact.active.charter.standing_doctrine)
	for expectation in c.compact.active.charter.expectations do destroy_owned_string(expectation.detail)
	for change in c.compact.active.intent_changes {
		destroy_owned_string(change.promised_attempt)
		destroy_owned_string(change.reason)
	}
	for undertaking in c.compact.history {
		destroy_owned_string(undertaking.intent)
		destroy_owned_string(undertaking.charter.intent)
		destroy_owned_string(undertaking.charter.undertaking_intent.promised_attempt)
		destroy_owned_string(undertaking.charter.standing_doctrine)
		for expectation in undertaking.charter.expectations do destroy_owned_string(expectation.detail)
		for change in undertaking.intent_changes {
			destroy_owned_string(change.promised_attempt)
			destroy_owned_string(change.reason)
		}
	}
	for option in c.compact.counsel.options do destroy_owned_string(option)
	destroy_owned_string(c.compact.counsel.response_reason)
	for callback in c.compact.callbacks do destroy_owned_string(callback.detail)
	destroy_public_question_strings(
		&c.public_politics.open,
	); destroy_public_question_strings(&c.public_politics.queued)
	for promise in c.promises do destroy_owned_string(promise.detail)
	for settlement in c.settlements {destroy_owned_string(settlement.name); destroy_owned_string(settlement.public_founding_account); destroy_owned_string(settlement.authoritative_founding_account); destroy_owned_string(settlement.waiver_account); destroy_owned_string(settlement.celestial.neighborhood_name); destroy_owned_string(settlement.celestial.system_name); destroy_owned_string(settlement.celestial.planet_name)}
	for candidate in c.candidate_homes {destroy_owned_string(candidate.reference.neighborhood_name); destroy_owned_string(candidate.reference.system_name); destroy_owned_string(candidate.reference.planet_name); destroy_owned_string(candidate.profile.measured_evidence); destroy_owned_string(candidate.profile.modeled_inference)}
	for survey in c.world_surveys {destroy_owned_string(survey.reference.neighborhood_name); destroy_owned_string(survey.reference.system_name); destroy_owned_string(survey.reference.planet_name); destroy_owned_string(survey.profile.measured_evidence); destroy_owned_string(survey.profile.modeled_inference)}
	destroy_owned_string(c.material_economy.fleet.trade.route_name)
	destroy_owned_string(
		c.settlement_proposal.name,
	); destroy_owned_string(c.settlement_proposal.destination)
	destroy_owned_string(
		c.settlement_proposal.waiver_account,
	); destroy_owned_string(c.settlement_proposal.founding_requirements.unmet_summary)
	destroy_owned_string(
		c.settlement_proposal.celestial.neighborhood_name,
	); destroy_owned_string(c.settlement_proposal.celestial.system_name); destroy_owned_string(c.settlement_proposal.celestial.planet_name)
	for assessment in c.settlement_proposal.assessments do for reason in assessment.consent.reasons do destroy_owned_string(reason)
	for commitment in c.capacity_commitments do destroy_owned_string(commitment.detail)
	for obligation in c.obligations.items do destroy_owned_string(obligation.name)
	destroy_owned_string(
		c.council.direction.name,
	); destroy_owned_string(c.council.direction.effect)
	destroy_owned_string(
		c.council.strongest_supporter,
	); destroy_owned_string(c.council.strongest_opponent)
	destroy_owned_string(
		c.council.support_reason,
	); destroy_owned_string(c.council.opposition_reason)
	destroy_owned_string(
		c.council.exception_doctrine,
	); destroy_owned_string(c.council.exception_reason)
	for position in c.council.positions {destroy_owned_string(position.name); destroy_owned_string(position.reason)}
	for continuity in c.transformations.continuity {destroy_owned_string(continuity.operational_role); destroy_owned_string(continuity.social_role)}
	for record in c.transformations.records do destroy_owned_string(record.detail)
	destroy_situation_strings(&c.current_situation)
	for &situation in c.situation_queue do destroy_situation_strings(&situation)
	for event in c.events {destroy_owned_string(event.detail); destroy_owned_string(event.authoritative_detail)}
	for era in c.archived_eras do destroy_owned_string(era.detail)
	for epoch in c.archived_epochs do destroy_owned_string(epoch.detail)
	for era in c.service_eras do destroy_owned_string(era.name)
	for hook in c.history_hooks do destroy_owned_string(hook.detail)
	for evidence in c.ending_evidence do destroy_owned_string(evidence)
	for front in c.fronts {destroy_owned_string(front.name); destroy_owned_string(front.last_public_record); destroy_owned_string(front.known_next_risk)}
	for proposal in c.future_fronts {destroy_owned_string(proposal.name); destroy_owned_string(proposal.known_risk)}
	destroy_owned_string(c.expedition.objective); destroy_owned_string(c.expedition.doctrine)
	when !ODIN_TEST do if c.galaxy != nil {galaxy_destroy(c.galaxy); free(c.galaxy)}
	dark_continuum_destroy_storage(&c.outer_dark.continuum)
	delete(c.dark_fleet_atlas)
	delete(c.dark_organism_observations)
	delete(c.dark_strategy_records)
	delete(c.dark_unresolved_voyages)
	delete(c.dark_relays)
	delete(c.habitable_contacts)
	delete(c.passage.local_habitable_contacts)
	delete(c.events)
	delete(c.settlement_economies.economies)
	delete(c.settlement_economies.archived)
	delete(c.settlement_economies.flows)
	delete(c.settlement_economies.political_links)
	c^ = {}
}

destroy_situation_strings :: proc(s: ^Fleet_Situation) {
	destroy_owned_string(s.title); destroy_owned_string(s.proposal); destroy_owned_string(s.stakes)
	destroy_owned_string(
		s.celestial.neighborhood_name,
	); destroy_owned_string(s.celestial.system_name); destroy_owned_string(s.celestial.planet_name)
	for position in s.positions do for reason in position.reasons do destroy_owned_string(reason.detail)
	for choice in s.choices {destroy_owned_string(choice.label); destroy_owned_string(choice.consequence)}
}

community_index :: proc(c: ^Campaign, id: Community_ID) -> int {
	for community, i in c.communities[:c.community_count] do if community.id == id do return i
	return -1
}

community_position_for :: proc(community: ^Community) -> Community_Position {
	if community.grievance >= 4 || community.trust < 45 do return .Aggrieved
	if community.grievance > 0 || community.petitions_neglected > community.petitions_honored do return .Watchful
	return .Cooperative
}

record_community_memory :: proc(
	c: ^Campaign,
	community_id: Community_ID,
	ship: Ship_ID,
	resolved: bool,
	mitigated: bool,
	cause: u64,
	kind: Need_Kind,
) {
	community_at := community_index(c, community_id); if community_at < 0 do return
	community := &c.communities[community_at]
	if resolved {community.petitions_honored += 1; community.grievance = max(community.grievance - 3, 0)} else {community.petitions_neglected += 1; community.grievance = min(community.grievance + (mitigated ? 1 : 2), 10)}
	community.position = community_position_for(community)
	detail :=
		resolved ? fmt.tprintf("The %s recorded a funded response to its %v petition.", community.name, kind) : fmt.tprintf("The %s recorded its %v petition as unanswered.", community.name, kind)
	record_event(
		c,
		.Community_Memory_Changed,
		detail,
		ship,
		community.grievance,
		community.id,
		cause,
	)
	community.last_memory_event = c.event_sequence
}

community_passage_modifier :: proc(c: ^Campaign, ships: []Ship_ID) -> (i32, u64, Community_ID) {
	positive_event: u64; positive_community := Community_ID(0)
	for ship_id in ships {
		ship_at := ship_index(c, ship_id); if ship_at < 0 do continue
		community_at := community_index(
			c,
			c.ships[ship_at].community,
		); if community_at < 0 do continue
		community := c.communities[community_at]
		if community.position == .Aggrieved && community.last_memory_event > 0 do return -1, community.last_memory_event, community.id
		if community.position == .Cooperative &&
		   community.petitions_honored >= 2 &&
		   community.last_memory_event >
			   positive_event {positive_event = community.last_memory_event; positive_community = community.id}
	}
	if positive_event > 0 do return 1, positive_event, positive_community
	return 0, 0, 0
}

total_population :: proc(c: ^Campaign) -> i32 {
	total: i32
	for community in c.communities[:c.community_count] do total += max(community.population, 0)
	return total
}

active_ship_count :: proc(c: ^Campaign) -> int {
	count: int
	for ship in c.ships do if ship.active do count += 1
	return count
}

role_name :: proc(role: Role) -> string {
	switch role {case .Habitat:
		return "Habitat"; case .Agriculture:
		return "Agriculture"; case .Foundry:
		return "Foundry"; case .Archive:
		return "Archive"; case .Hospital:
		return "Hospital"; case .Survey:
		return "Survey"; case .Escort:
		return "Escort"; case .Colony:
		return "Colony"}
	return "Unknown"
}

ending_name :: proc(ending: Ending) -> string {
	switch ending {case .In_Progress:
		return "In progress"; case .New_Home:
		return "A Major New Home"; case .Harbor_Network:
		return "A Network of Harbors"; case .Nomadic_Fleet:
		return "The Sustainable Nomadic Fleet"; case .Federation:
		return "Federation"; case .Transformed:
		return "Deliberate Transformation"; case .Fragmented_Survival:
		return "Fragmented Survival"}
	return "Unknown"
}

ending_quality_name :: proc(quality: Ending_Quality) -> string {
	switch quality {case .Fragile:
		return "Under Strain"; case .Stable:
		return "Maintained"; case .Flourishing:
		return "Secure"; case .None:
		return "Unresolved"}
	return "Unresolved"
}

need_detail :: proc(kind: Need_Kind) -> string {
	switch kind {case .Sustenance_Shortfall:
		return "Agricultural output will fall below consumption."; case .Settlement_Demand:
		return "A community demands a credible path to settlement."; case .Ship_Repair:
		return "A storied ship needs priority repairs."; case .Archive_Staffing:
		return(
			"The archives need specialists assigned away from navigation." \
		); case .Settlement_Defense:
		return "A distant settlement asks the fleet for defense."; case .Representation:
		return "Fleetborn children demand representation."; case .Settlement_Charter:
		return(
			"A settlement petitions to revise its founding charter." \
		); case .Jurisdiction_Dispute:
		return(
			"A captain and an institution dispute operational authority over a ship." \
		); case .Institution_Dispute:
		return "Two institutions demand a ruling on incompatible public policies."}
	return "An urgent need has surfaced."
}

latest_event_for_ship :: proc(c: ^Campaign, ship: Ship_ID) -> u64 {
	ship_at := ship_index(
		c,
		ship,
	); if ship_at >= 0 {subject := c.ships[ship_at]; if subject.memory_count > 0 do return subject.memories[subject.memory_count - 1].event_sequence}
	for i := c.event_count - 1; i >= 0; i -= 1 do if c.events[i].ship_id == ship && c.events[i].kind != .Need_Surfaced do return c.events[i].sequence
	return 0
}

latest_ship_memory_of_kind :: proc(c: ^Campaign, ship: Ship_ID, kind: Event_Kind) -> u64 {
	ship_at := ship_index(c, ship); if ship_at < 0 do return 0
	subject :=
		c.ships[ship_at]; for i := subject.memory_count - 1; i >= 0; i -= 1 do if subject.memories[i].kind == kind do return subject.memories[i].event_sequence
	return 0
}

latest_ship_memory_with_tag :: proc(c: ^Campaign, ship: Ship_ID, tag: Semantic_Tag) -> u64 {
	ship_at := ship_index(c, ship); if ship_at < 0 do return 0
	subject :=
		c.ships[ship_at]; for i := subject.memory_count - 1; i >= 0; i -= 1 do if semantic_has(subject.memories[i].semantic_tags, tag) do return subject.memories[i].event_sequence
	return 0
}

latest_event_for_community :: proc(c: ^Campaign, community: Community_ID) -> u64 {
	for i := c.event_count - 1; i >= 0; i -= 1 do if c.events[i].community == community && c.events[i].kind != .Need_Surfaced do return c.events[i].sequence
	return 0
}

latest_event_of_kind :: proc(c: ^Campaign, kind: Event_Kind) -> u64 {
	for i := c.event_count - 1; i >= 0; i -= 1 do if c.events[i].kind == kind do return c.events[i].sequence
	return 0
}

latest_event_matching_tags :: proc(
	c: ^Campaign,
	required: Semantic_Tags,
	excluded: Semantic_Tags = {},
	before_sequence: u64 = 0,
) -> u64 {
	for i := c.event_count - 1;
	    i >= 0;
	    i -= 1 {event := c.events[i]; if before_sequence != 0 && event.sequence >= before_sequence do continue; if semantic_contains_all(event.semantic_tags, required) && u64(event.semantic_tags) & u64(excluded) == 0 do return event.sequence}
	return 0
}

institution_index :: proc(c: ^Campaign, id: Institution_ID) -> int {
	for institution, i in c.institutions do if institution.id == id do return i
	return -1
}

community_institution_relationship_index :: proc(
	c: ^Campaign,
	community: Community_ID,
	institution: Institution_ID,
) -> int {
	for relationship, i in c.community_institution_relationships[:c.community_institution_relationship_count] do if relationship.community == community && relationship.institution == institution do return i
	return -1
}

record_community_institution_response :: proc(
	c: ^Campaign,
	community: Community_ID,
	institution: Institution_ID,
	supported: bool,
	cause: u64,
) -> bool {
	community_at := community_index(
		c,
		community,
	); institution_at := institution_index(c, institution)
	if community_at < 0 || institution_at < 0 || !chronicle_can_record(c) do return false
	index := community_institution_relationship_index(c, community, institution)
	if index <
	   0 {if c.community_institution_relationship_count >= MAX_COMMUNITY_INSTITUTION_RELATIONSHIPS do return false; index = c.community_institution_relationship_count; c.community_institution_relationship_count += 1; c.community_institution_relationships[index] = {
			community    = community,
			institution  = institution,
			origin_event = cause,
		}}
	relationship := &c.community_institution_relationships[index]
	if supported {relationship.stance = .Coalition; relationship.strength = clamp(max(relationship.strength, 0) + 1, -3, 3)} else {relationship.stance = .Opposition; relationship.strength = clamp(min(relationship.strength, 0) - 1, -3, 3)}
	detail :=
		supported ? fmt.tprintf("The %s and the %s formed a working coalition after the funded petition.", c.communities[community_at].name, c.institutions[institution_at].name) : fmt.tprintf("The %s entered opposition to the %s after its petition went unanswered.", c.communities[community_at].name, c.institutions[institution_at].name)
	record_event(
		c,
		.Political_Relationship_Changed,
		detail,
		community = community,
		cause_sequence = cause,
		institution_id = institution,
		value = relationship.strength,
	)
	relationship.last_event =
		c.event_sequence; relationship.semantic_tags = make_semantic_tags(.Relationship, .Community, .Institution, .Governance); if relationship.stance == .Opposition do relationship.semantic_tags = semantic_add(relationship.semantic_tags, .Contested)
	return true
}

community_institution_need_cost_modifier :: proc(
	c: ^Campaign,
	community: Community_ID,
	institution: Institution_ID,
) -> i32 {
	index := community_institution_relationship_index(
		c,
		community,
		institution,
	); if index < 0 do return 0
	relationship := c.community_institution_relationships[index]
	if relationship.stance == .Coalition do return -min(max(relationship.strength, 1), 2)
	return min(max(abs(relationship.strength), 1), 2)
}

community_institution_relationship_description :: proc(
	c: ^Campaign,
	community: Community_ID,
) -> string {
	best := -1; for relationship, i in c.community_institution_relationships[:c.community_institution_relationship_count] do if relationship.community == community && (best < 0 || abs(relationship.strength) > abs(c.community_institution_relationships[best].strength)) do best = i
	if best < 0 do return ""; relationship := c.community_institution_relationships[best]; institution_at := institution_index(c, relationship.institution); if institution_at < 0 do return ""
	return(
		relationship.stance == .Coalition ? fmt.tprintf("Coalition with the %s", c.institutions[institution_at].name) : fmt.tprintf("Opposition to the %s", c.institutions[institution_at].name) \
	)
}

institution_relationship_index :: proc(c: ^Campaign, a, b: Institution_ID) -> int {
	lo := min(
		a,
		b,
	); hi := max(a, b); for relationship, i in c.institution_relationships[:c.institution_relationship_count] do if relationship.institution_a == lo && relationship.institution_b == hi do return i
	return -1
}

institution_policy_conflict :: proc(a, b: Institution) -> (Semantic_Tag, bool) {
	if abs(i32(a.authority_policy) - i32(b.authority_policy)) >= 2 do return .Jurisdiction, true
	if abs(i32(a.disclosure_policy) - i32(b.disclosure_policy)) >= 2 do return .Accountability, true
	if abs(i32(a.rescue_policy) - i32(b.rescue_policy)) >= 2 do return .Rescue, true
	return .Governance, false
}

set_institution_relationship :: proc(
	c: ^Campaign,
	a, b: Institution_ID,
	stance: Institution_Relationship_Stance,
	policy: Semantic_Tag,
	cause: u64,
) -> bool {
	a_at := institution_index(
		c,
		a,
	); b_at := institution_index(c, b); if a_at < 0 || b_at < 0 || a == b || !chronicle_can_record(c) do return false
	lo := min(a, b); hi := max(a, b); index := institution_relationship_index(c, lo, hi)
	if index <
	   0 {if c.institution_relationship_count >= MAX_INSTITUTION_RELATIONSHIPS do return false; index = c.institution_relationship_count; c.institution_relationship_count += 1; c.institution_relationships[index] = {
			institution_a = lo,
			institution_b = hi,
			origin_event  = cause,
		}}
	relationship := &c.institution_relationships[index]; relationship.stance = stance; relationship.policy = policy; if stance == .Rivalry {relationship.strength = clamp(min(relationship.strength, 0) - 1, -3, 3)} else {relationship.strength = clamp(max(relationship.strength, 0) + 1, -3, 3)}
	lo_at := institution_index(
		c,
		lo,
	); hi_at := institution_index(c, hi); detail := stance == .Rivalry ? fmt.tprintf("The %s and the %s entered a public rivalry over %s policy.", c.institutions[lo_at].name, c.institutions[hi_at].name, semantic_tag_summary(make_semantic_tags(policy))) : fmt.tprintf("The %s and the %s reached a working accord.", c.institutions[lo_at].name, c.institutions[hi_at].name)
	record_event(
		c,
		.Political_Relationship_Changed,
		detail,
		community = c.institutions[lo_at].community,
		cause_sequence = cause,
		institution_id = lo,
		value = relationship.strength,
	)
	relationship.last_event =
		c.event_sequence; relationship.semantic_tags = make_semantic_tags(.Relationship, .Institution, .Governance, policy); if stance == .Rivalry do relationship.semantic_tags = semantic_add(relationship.semantic_tags, .Contested)
	return true
}
