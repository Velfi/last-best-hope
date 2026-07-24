package game

import "core:fmt"

// Operation aftermath is deliberately a fixed-size campaign record: it can be
// saved at the handoff between an operation simulation and campaign play.
MAX_AFTERMATH_SHIPS :: MAX_SHIPS
MAX_AFTERMATH_FACTS :: 24
MAX_AFTERMATH_EVENTS :: 32
MAX_AFTERMATH_OBSERVATIONS :: 16
MAX_COMPLETED_AFTERMATHS :: 32
MAX_SOCIAL_CONSEQUENCES :: 128

Operation_ID :: distinct u64

Operation_Layer :: enum {
	None,
	Passage,
	Close_Engagement,
	Far_Engagement,
}

Operation_Objective_Result :: enum {
	Unresolved,
	Achieved,
	Partial,
	Failed,
}

Operation_Ship_Outcome :: struct {
	ship:             Ship_ID,
	damage:           i32,
	impairments:      Ship_Impairments,
	crew_change:      i32,
	experience:       i32,
	scar:             Ship_Scar,
	withdrew:         bool,
	lost:             bool,
	protected:        bool,
	exposure:         i32,
	recovery_seconds: i64,
}

Operation_Observation_Kind :: enum {
	None,
	Authority_Used,
	Intent_Changed,
	Expectation_Observed,
	Expectation_Unmet,
	Exposure_Exceeded,
	Deviation_Communicated,
	Deviation_Uncommunicated,
	Evidence_Withheld,
}

Operation_Observation :: struct {
	kind:        Operation_Observation_Kind,
	expectation: int,
	actor:       Institution_ID,
	ship:        Ship_ID,
	cause_event: u64,
}

Social_Consequence_Kind :: enum {
	None,
	Witnessed_Rescue,
	Refused_Rescue,
	Abandonment,
	Covering_Withdrawal,
	Unauthorized_Exposure,
	Uncommunicated_Deviation,
	Accepted_Responsibility,
	Concealed_Evidence,
	Shared_Survival,
}

Social_Knowledge :: struct {
	participants_know:   bool,
	authenticated:       bool,
	public_account:      bool,
	witness_ship:        Ship_ID,
	witness_community:   Community_ID,
	witness_institution: Institution_ID,
}

Social_Consequence_Input :: struct {
	kind:                    Social_Consequence_Kind,
	actor_ship:              Ship_ID,
	subject_ship:            Ship_ID,
	community:               Community_ID,
	institution:             Institution_ID,
	settlement:              Settlement_ID,
	historical_front:        u32,
	accepted_responsibility: bool,
	knowledge:               Social_Knowledge,
}

Operation_Causal_Event :: struct {
	kind:              Event_Kind,
	ship:              Ship_ID,
	related_ship:      Ship_ID,
	community:         Community_ID,
	institution:       Institution_ID,
	observation_index: int,
	value:             i32,
	detail:            string,
	cause_event:       u64,
	recorded_event:    u64,
}

Operation_Resources :: struct {
	supplies, propellant, materials: i32,
}

Operation_Aftermath :: struct {
	id:                                       Operation_ID,
	layer:                                    Operation_Layer,
	undertaking_id:                           Compact_Undertaking_ID,
	intent_event:                             u64,
	started_at:                               Campaign_Time,
	elapsed_seconds:                          i64,
	time_already_applied:                     bool,
	objective:                                Operation_Objective_Result,
	protected_exposure:                       i32,
	rescues, withdrawals, losses, deviations: i32,
	evidence_recovered:                       i32,
	resources:                                Operation_Resources,
	ships:                                    [MAX_AFTERMATH_SHIPS]Operation_Ship_Outcome,
	ship_count:                               int,
	observations:                             [MAX_AFTERMATH_OBSERVATIONS]Operation_Observation,
	observation_count:                        int,
	social:                                   [MAX_AFTERMATH_FACTS]Social_Consequence_Input,
	social_count:                             int,
	events:                                   [MAX_AFTERMATH_EVENTS]Operation_Causal_Event,
	event_count:                              int,
	applied:                                  bool,
	application_event:                        u64,
}

Operation_Aftermath_Issue :: enum {
	None,
	Missing_Operation,
	Duplicate_Operation,
	Missing_Active_Undertaking,
	Undertaking_Mismatch,
	Intent_Mismatch,
	Layer_Mismatch,
	Invalid_Manifest,
	Invalid_Resources,
	Missing_Call,
	Invalid_Charter,
}

Operation_Aftermath_Validation :: struct {
	issue: Operation_Aftermath_Issue,
	valid: bool,
}

Operation_Outcome_Facts :: struct {
	id:                                                           Operation_ID,
	elapsed_seconds:                                              i64,
	time_already_applied:                                         bool,
	objective:                                                    Operation_Objective_Result,
	protected_exposure, rescues, withdrawals, losses, deviations: i32,
	evidence_recovered:                                           i32,
	resources:                                                    Operation_Resources,
	ships:                                                        []Operation_Ship_Outcome,
	social:                                                       []Social_Consequence_Input,
	events:                                                       []Operation_Causal_Event,
}

operation_aftermath_translate :: proc(
	c: ^Campaign,
	layer: Operation_Layer,
	facts: Operation_Outcome_Facts,
) -> Operation_Aftermath {
	a: Operation_Aftermath
	a.id = facts.id
	a.layer = layer
	a.started_at = c.clock.now
	a.elapsed_seconds = max(facts.elapsed_seconds, i64(0))
	a.time_already_applied = facts.time_already_applied
	a.objective = facts.objective
	a.protected_exposure = max(facts.protected_exposure, 0)
	a.rescues = max(facts.rescues, 0)
	a.withdrawals = max(facts.withdrawals, 0)
	a.losses = max(facts.losses, 0)
	a.deviations = max(facts.deviations, 0)
	a.evidence_recovered = max(facts.evidence_recovered, 0)
	a.resources = facts.resources
	a.ship_count = min(len(facts.ships), MAX_AFTERMATH_SHIPS)
	for item, i in facts.ships[:a.ship_count] do a.ships[i] = item
	a.social_count = min(len(facts.social), MAX_AFTERMATH_FACTS)
	for item, i in facts.social[:a.social_count] do a.social[i] = item
	a.event_count = min(len(facts.events), MAX_AFTERMATH_EVENTS)
	for item, i in facts.events[:a.event_count] do a.events[i] = item
	u := &c.compact.active
	if u.status == .Operating || u.status == .Returned {
		a.undertaking_id = u.id
		a.intent_event = u.charter.intent_event
		a.observations[a.observation_count] = {
			kind        = facts.objective == .Achieved ? .Authority_Used : .Intent_Changed,
			cause_event = u.charter.intent_event,
		}
		a.observation_count += 1
		for expectation, i in u.charter.expectations[:u.charter.expectation_count] {
			if a.observation_count >= MAX_AFTERMATH_OBSERVATIONS do break
			unmet := false
			for outcome in facts.ships do if outcome.ship == expectation.ship {
				unmet = outcome.lost || expectation.kind == .Prefer_Withdrawal && !outcome.withdrew && outcome.damage > 0
				break
			}
			a.observations[a.observation_count] = {
				kind        = unmet ? .Expectation_Unmet : .Expectation_Observed,
				expectation = i,
				actor       = expectation.contributor,
				ship        = expectation.ship,
				cause_event = expectation.source_event,
			}
			a.observation_count += 1
		}
		if facts.deviations > 0 && a.observation_count < MAX_AFTERMATH_OBSERVATIONS {
			a.observations[a.observation_count] = {
				kind        = .Deviation_Uncommunicated,
				cause_event = u.charter.intent_event,
			}
			a.observation_count += 1
		}
	}
	return a
}

passage_operation_aftermath :: proc(
	c: ^Campaign,
	facts: Operation_Outcome_Facts,
) -> Operation_Aftermath {
	return operation_aftermath_translate(c, .Passage, facts)
}
close_engagement_operation_aftermath :: proc(
	c: ^Campaign,
	facts: Operation_Outcome_Facts,
) -> Operation_Aftermath {
	return operation_aftermath_translate(c, .Close_Engagement, facts)
}
far_engagement_operation_aftermath :: proc(
	c: ^Campaign,
	facts: Operation_Outcome_Facts,
) -> Operation_Aftermath {
	return operation_aftermath_translate(c, .Far_Engagement, facts)
}

// Production adapters call this at their existing campaign-result boundary.
// Physical changes already committed by a legacy adapter are represented as
// zero-delta ship outcomes until that adapter is fully retired.
apply_operation_return :: proc(
	c: ^Campaign,
	layer: Operation_Layer,
	id: u64,
	objective_met: bool,
	ships: []Ship_ID,
	elapsed_seconds: i64,
	rescues: i32 = 0,
	withdrawals: i32 = 0,
	protected_exposure: i32 = 0,
	deviations: i32 = 0,
	evidence: i32 = 0,
) -> bool {
	outcomes: [MAX_AFTERMATH_SHIPS]Operation_Ship_Outcome
	count := min(len(ships), MAX_AFTERMATH_SHIPS)
	for ship, i in ships[:count] do outcomes[i].ship = ship
	facts := Operation_Outcome_Facts {
		id                   = Operation_ID((u64(layer) << 60) ~ (id == 0 ? u64(1) : id)),
		objective            = objective_met ? .Achieved : .Failed,
		elapsed_seconds      = max(elapsed_seconds, i64(0)),
		time_already_applied = true,
		rescues              = rescues,
		withdrawals          = withdrawals,
		protected_exposure   = protected_exposure,
		deviations           = deviations,
		evidence_recovered   = evidence,
		ships                = outcomes[:count],
	}
	a := operation_aftermath_translate(c, layer, facts)
	return queue_operation_aftermath(c, a) && apply_operation_aftermath(c)
}

aftermath_completed :: proc(c: ^Campaign, id: Operation_ID) -> bool {
	for item in c.completed_aftermaths[:c.completed_aftermath_count] do if item == id do return true
	return false
}

validate_operation_aftermath :: proc(
	c: ^Campaign,
	a: ^Operation_Aftermath,
) -> Operation_Aftermath_Validation {
	if c == nil || a == nil || a.id == 0 do return {.Missing_Operation, false}
	if a.ship_count <= 0 ||
	   a.ship_count > MAX_AFTERMATH_SHIPS ||
	   a.observation_count < 0 ||
	   a.observation_count > MAX_AFTERMATH_OBSERVATIONS ||
	   a.social_count < 0 ||
	   a.social_count > MAX_AFTERMATH_FACTS ||
	   a.event_count < 0 ||
	   a.event_count > MAX_AFTERMATH_EVENTS {
		return {.Invalid_Manifest, false}
	}
	if aftermath_completed(c, a.id) ||
	   c.compact.last_aftermath_operation == a.id {
		return {.Duplicate_Operation, false}
	}
	u := &c.compact.active
	if u.id == 0 || u.status != .Operating do return {.Missing_Active_Undertaking, false}
	if !u.charter.valid ||
	   u.charter.undertaking != u.id ||
	   u.charter.call != u.call {
		return {.Invalid_Charter, false}
	}
	call_at := compact_call_index(c, u.call)
	if call_at < 0 do return {.Missing_Call, false}
	call := &c.compact.calls[call_at]
	if call.status != .Accepted ||
	   call.undertaking != u.id {
		return {.Invalid_Charter, false}
	}
	if a.undertaking_id != u.id do return {.Undertaking_Mismatch, false}
	if a.intent_event == 0 || a.intent_event != u.charter.intent_event {
		return {.Intent_Mismatch, false}
	}
	expected_layer :=
		u.route == .Passage ? Operation_Layer.Passage :
		u.route == .Close_Engagement ? Operation_Layer.Close_Engagement :
		u.route == .Far_Engagement ? Operation_Layer.Far_Engagement :
		Operation_Layer.None
	if a.layer == .None || a.layer != expected_layer do return {.Layer_Mismatch, false}
	for outcome, i in a.ships[:a.ship_count] {
		if outcome.ship == 0 || !compact_ship_is_seconded(c, outcome.ship) {
			return {.Invalid_Manifest, false}
		}
		for prior in a.ships[:i] do if prior.ship == outcome.ship {
			return {.Invalid_Manifest, false}
		}
	}
	if !compact_resources_valid(u.resource_ledger.reserved) ||
	   !compact_resource_report_valid(u, a) ||
	   !fleet_stock_can_spend(
		   c.material_economy.fleet.committed,
		   compact_resources_to_stock(u.resource_ledger.reserved),
	   ) {
		return {.Invalid_Resources, false}
	}
	return {.None, true}
}

queue_operation_aftermath_validated :: proc(
	c: ^Campaign,
	a: Operation_Aftermath,
) -> Operation_Aftermath_Validation {
	if c == nil || a.id == 0 do return {.Missing_Operation, false}
	if c.pending_aftermath.id != 0 {
		if c.pending_aftermath.id == a.id {
			return validate_operation_aftermath(c, &c.pending_aftermath)
		}
		return {.Duplicate_Operation, false}
	}
	candidate := a
	validation := validate_operation_aftermath(c, &candidate)
	if !validation.valid do return validation
	c.pending_aftermath = candidate
	return validation
}

queue_operation_aftermath :: proc(c: ^Campaign, a: Operation_Aftermath) -> bool {
	return queue_operation_aftermath_validated(c, a).valid
}

Social_Consequence_Record :: struct {
	operation:                Operation_ID,
	kind:                     Social_Consequence_Kind,
	actor_ship, subject_ship: Ship_ID,
	community:                Community_ID,
	institution:              Institution_ID,
	event:                    u64,
	public:                   bool,
	reconciled:               bool,
}

Operational_Practice :: enum {
	None,
	Mutual_Rescue,
	Covered_Withdrawal,
	Accountable_Disclosure,
	Shared_Survival,
}

social_record_exists :: proc(c: ^Campaign, operation: Operation_ID, index: int) -> bool {
	if index < 0 do return false
	for record in c.social_consequences[:c.social_consequence_count] do if record.operation == operation && record.event == u64(index + 1) do return true
	return false
}

social_consequence_known :: proc(input: Social_Consequence_Input, public_account: bool) -> bool {
	return(
		input.knowledge.participants_know ||
		input.knowledge.authenticated ||
		input.knowledge.public_account ||
		public_account \
	)
}

apply_social_consequence :: proc(
	c: ^Campaign,
	operation: Operation_ID,
	input: Social_Consequence_Input,
	ordinal: int,
	cause: u64,
	public_account: bool = false,
) {
	if !social_consequence_known(input, public_account) ||
	   social_record_exists(c, operation, ordinal) ||
	   c.social_consequence_count >= MAX_SOCIAL_CONSEQUENCES {
		return
	}
	actor_at := ship_index(c, input.actor_ship)
	if actor_at < 0 do return
	delta: i32
	kind := Relationship_Kind.Advocated_For
	mark := Captain_Mark_Kind.Rescue
	ctx := Captain_Context.Rescue
	practice := Operational_Practice.Mutual_Rescue
	#partial switch input.kind {
	case .Witnessed_Rescue:
		delta = 2
	case .Refused_Rescue, .Abandonment:
		delta = -2; kind = .Unanswered_Obligation; mark = .Breach
	case .Covering_Withdrawal:
		delta = 1; ctx = .Withdrawal; practice = .Covered_Withdrawal
	case .Unauthorized_Exposure:
		delta = -2; mark = .Censure; ctx = .Objective_Exposure
	case .Uncommunicated_Deviation:
		delta = -2; mark = .Breach; ctx = .Undertaking
	case .Accepted_Responsibility:
		delta = 1; mark = .Commendation; practice = .Accountable_Disclosure
	case .Concealed_Evidence:
		delta = -1; mark = .Censure; practice = .Accountable_Disclosure
	case .Shared_Survival:
		delta = 2; practice = .Shared_Survival
	case:
		return
	}
	record_event(
		c,
		.Political_Relationship_Changed,
		"Operational conduct entered the account.",
		input.actor_ship,
		delta,
		input.community,
		cause,
		c.ships[actor_at].captain,
		institution_id = input.institution,
		related_ship_id = input.subject_ship,
		operation_id = u64(operation),
	)
	event := c.event_sequence
	if input.subject_ship != 0 {
		index := ship_relationship_index(c, input.actor_ship, input.subject_ship)
		if index < 0 && c.ship_relationship_count < MAX_SHIP_RELATIONSHIPS {
			a, b := input.actor_ship, input.subject_ship; if a > b do a, b = b, a
			index = c.ship_relationship_count; c.ship_relationship_count += 1
			c.ship_relationships[index] = {
				ship_a       = a,
				ship_b       = b,
				kind         = .Shared_Passage,
				origin_event = event,
			}
		}
		if index >= 0 {
			r := &c.ship_relationships[index]
			r.strength = clamp(r.strength + delta, -3, 3); r.last_event = event
			r.semantic_tags = make_semantic_tags(.Relationship, .Ship, .Causality)
		}
	}
	if input.community != 0 &&
	   (public_account ||
			   input.knowledge.public_account ||
			   input.knowledge.authenticated ||
			   input.knowledge.witness_community == input.community) {
		_ = set_ship_community_relationship(c, input.actor_ship, input.community, kind, delta)
		if ci := community_index(c, input.community); ci >= 0 {
			c.communities[ci].trust = clamp(c.communities[ci].trust + max(delta, 0), 0, 100)
			c.communities[ci].grievance = clamp(
				c.communities[ci].grievance + (delta < 0 ? -delta : -1),
				0,
				10,
			)
		}
	}
	if input.institution != 0 &&
	   (public_account ||
			   input.knowledge.public_account ||
			   input.knowledge.authenticated ||
			   input.knowledge.witness_institution == input.institution) {
		if c.ships[actor_at].captain != 0 &&
		   historical_figure_index(c, c.ships[actor_at].captain) >= 0 {
			stance :=
				delta < 0 ? Institution_Ship_Stance.Contested : Institution_Ship_Stance.Stewardship
			_ = set_institution_ship_relationship(
				c,
				input.institution,
				input.actor_ship,
				stance,
				abs(delta),
				event,
			)
		}
	}
	if input.settlement != 0 {
		for &settlement in c.settlements[:c.settlement_count] do if settlement.id == input.settlement {
			settlement.fleet_relationship = clamp(settlement.fleet_relationship + delta, -100, 100)
			settlement.last_report_event = event
			break
		}
	}
	if input.historical_front != 0 {
		for &front in c.fronts[:c.front_count] do if front.id == input.historical_front {
			front.pressure = max(front.pressure + (delta < 0 ? -delta : -1), 0)
			if input.accepted_responsibility do front.stage = .Recovering
			front.last_change_event = event; front.last_change_season = c.season
			break
		}
	}
	captain := c.ships[actor_at].captain
	_ = captain_add_mark(
		c,
		captain,
		{
			kind = mark,
			decision_context = ctx,
			source_event = event,
			target_kind = input.community != 0 ? Captain_Target_Kind.Community : .Ship,
			target_id = input.community != 0 ? u32(input.community) : u32(input.subject_ship),
			intensity = i8(clamp(delta, -4, 4)),
		},
	)
	if input.accepted_responsibility || input.kind == .Accepted_Responsibility do _ = captain_set_relationship(c, captain, .Community, u32(input.community), 1, 1, 0, 1, 0, event)
	if delta > 0 && practice != .None {
		c.operational_practices[int(practice)] += 1
	}
	c.social_consequences[c.social_consequence_count] = {
		operation    = operation,
		kind         = input.kind,
		actor_ship   = input.actor_ship,
		subject_ship = input.subject_ship,
		community    = input.community,
		institution  = input.institution,
		event        = u64(ordinal + 1),
		public       = public_account || input.knowledge.public_account || input.knowledge.authenticated,
	}
	c.social_consequence_count += 1
}

apply_operation_aftermath :: proc(c: ^Campaign) -> bool {
	a := &c.pending_aftermath
	if a.id == 0 do return false
	if aftermath_completed(c, a.id) {a^ = {}; return true}
	validation := validate_operation_aftermath(c, a)
	if !validation.valid {
		a^ = {}
		return false
	}
	if !chronicle_can_record(c, a.event_count + a.ship_count + a.observation_count + 1) do return false
	c.applying_operation_id = a.id
	c.applying_observation_index = -1
	if !a.time_already_applied {
		c.clock.now = campaign_time_add(c.clock.now, a.elapsed_seconds)
		campaign_clock_refresh_legacy_calendar(c)
	}
	essential_loss := false
	for outcome in a.ships[:a.ship_count] {
		si := ship_index(c, outcome.ship); if si < 0 do continue
		ship := &c.ships[si]
		ship.damage = max(ship.damage + max(outcome.damage, 0), 0)
		ship.impairments.mobility = min(
			ship.impairments.mobility + outcome.impairments.mobility,
			3,
		)
		ship.impairments.sensors = min(ship.impairments.sensors + outcome.impairments.sensors, 3)
		ship.impairments.strike = min(ship.impairments.strike + outcome.impairments.strike, 3)
		ship.impairments.support = min(ship.impairments.support + outcome.impairments.support, 3)
		ship.impairments.endurance = min(
			ship.impairments.endurance + outcome.impairments.endurance,
			3,
		)
		ship.crew = max(ship.crew + outcome.crew_change, 0)
		ship.experience += max(outcome.experience, 0)
		if outcome.scar != .None do ship.scar = outcome.scar
		if outcome.lost {
			essential_loss =
				essential_loss ||
				ship.role == .Hospital ||
				ship.role == .Foundry ||
				ship.role == .Agriculture ||
				ship.role == .Archive
			ship.active =
				false; record_event(c, .Ship_Lost, fmt.tprintf("%s did not return from the operation.", ship.name), ship.id, cause_sequence = a.intent_event)
		} else if outcome.damage >
		   0 {record_event(c, .Ship_Damaged, fmt.tprintf("%s returned with recorded damage.", ship.name), ship.id, outcome.damage, cause_sequence = a.intent_event)}
		if outcome.recovery_seconds > 0 {
			_ = campaign_schedule_work(
				c,
				.Repair,
				u64(a.id) ~ u64(outcome.ship),
				campaign_time_add(c.clock.now, outcome.recovery_seconds),
				50,
			)
			if outcome.crew_change < 0 do _ = campaign_schedule_work(c, .Obligation, (u64(a.id) << 8) ~ u64(outcome.ship), campaign_time_add(c.clock.now, max(outcome.recovery_seconds / 2, CAMPAIGN_DAY_SECONDS)), 60)
		}
	}
	// Debrief and evidence analysis are separate clock work so campaign play can
	// resume while their consequences mature.
	_ = campaign_schedule_work(
		c,
		a.layer == .Far_Engagement ? .Far_Engagement : a.layer == .Close_Engagement ? .Close_Engagement : .Passage,
		u64(a.id),
		campaign_time_add(c.clock.now, CAMPAIGN_DAY_SECONDS),
		45,
	)
	if a.evidence_recovered > 0 do _ = campaign_schedule_work(c, .Council, u64(a.id) ~ 0xe100000000000000, campaign_time_add(c.clock.now, 2 * CAMPAIGN_DAY_SECONDS), 55)
	if essential_loss {
		// Losing an essential ship creates replacement work, not an abrupt loss
		// state. Existing fleet capacity can substitute while this is active.
		_ = campaign_schedule_work(
			c,
			.Project,
			u64(a.id) ~ 0xf100000000000000,
			campaign_time_add(c.clock.now, 30 * CAMPAIGN_DAY_SECONDS),
			100,
		)
	}
	for &observation in a.observations[:a.observation_count] {
		if observation.cause_event == 0 do observation.cause_event = a.intent_event
		record_event(
			c,
			.Situation_Decided,
			fmt.tprintf(
				"Operation observation: %v%s",
				observation.kind,
				observation.expectation >= 0 ? fmt.tprintf(" (expectation %d)", observation.expectation + 1) : "",
			),
			observation.ship,
			cause_sequence = observation.cause_event,
			institution_id = observation.actor,
			operation_id = u64(a.id),
		)
	}
	for &item in a.events[:a.event_count] {
		record_event(
			c,
			item.kind,
			item.detail,
			item.ship,
			item.value,
			item.community,
			item.cause_event != 0 ? item.cause_event : a.intent_event,
			institution_id = item.institution,
			related_ship_id = item.related_ship,
			operation_id = u64(a.id),
		)
		item.recorded_event = c.event_sequence
	}
	cause := c.event_sequence
	public_account :=
		c.compact.active.id == a.undertaking_id &&
		c.compact.active.charter.doctrine.disclosure == .Open
	for input, i in a.social[:a.social_count] do apply_social_consequence(c, a.id, input, i, cause, public_account)
	if !compact_receive_aftermath(c, a, cause) {
		// Admission establishes every Compact precondition, and no preceding
		// physical mutation changes them. Reaching this branch indicates an
		// internal invariant violation rather than a recoverable operation
		// result.
		assert(false, "validated operation aftermath failed Compact application")
		return false
	}
	a.applied = true; a.application_event = cause
	if c.completed_aftermath_count < MAX_COMPLETED_AFTERMATHS {
		c.completed_aftermaths[c.completed_aftermath_count] =
			a.id; c.completed_aftermath_count += 1
	} else {
		for i in 1 ..< MAX_COMPLETED_AFTERMATHS do c.completed_aftermaths[i - 1] = c.completed_aftermaths[i]
		c.completed_aftermaths[MAX_COMPLETED_AFTERMATHS - 1] = a.id
	}
	a^ = {}
	c.applying_operation_id = 0
	c.applying_observation_index = -1
	return true
}

reconcile_social_consequence :: proc(
	c: ^Campaign,
	operation: Operation_ID,
	actor: Ship_ID,
	community: Community_ID,
) -> bool {
	for &record in c.social_consequences[:c.social_consequence_count] {
		if record.operation != operation || record.actor_ship != actor || record.reconciled do continue
		if record.kind != .Abandonment && record.kind != .Refused_Rescue && record.kind != .Uncommunicated_Deviation do continue
		record_event(
			c,
			.Political_Relationship_Changed,
			"Responsibility was accepted and restitution entered the record.",
			actor,
			1,
			community,
			record.event,
		)
		record.reconciled = true
		if ci := community_index(c, community); ci >= 0 {
			c.communities[ci].trust = min(c.communities[ci].trust + 2, 100)
			c.communities[ci].grievance = max(c.communities[ci].grievance - 1, 0)
		}
		if ri := relationship_index(c, actor, community); ri >= 0 {
			c.relationships[ri].strength = min(c.relationships[ri].strength + 1, 3)
		}
		if record.subject_ship != 0 {
			if ri := ship_relationship_index(c, actor, record.subject_ship); ri >= 0 {
				c.ship_relationships[ri].strength = min(c.ship_relationships[ri].strength + 1, 3)
				c.ship_relationships[ri].last_event = c.event_sequence
			}
		}
		return true
	}
	return false
}

Operational_Choice_Modifiers :: struct {
	rescue_default,
	staffing_substitution,
	joint_assignment,
	settlement_departure,
	exposure_acceptance: i32,
	council_support,
	contributor_conditions,
	captain_requests,
	deviation_authority:                         i32,
}

Operational_Policy :: enum {
	Rescue,
	Conceal,
	Withdraw,
}
Operational_Policy_Report :: struct {
	score:                [len(Operational_Policy)]i32,
	universally_dominant: bool,
	dominant:             Operational_Policy,
}

// Evaluate policies across materially different operation states. Benefits are
// paired with exposure, evidence, obligation, and abandonment costs.
analyze_operational_policy_dominance :: proc() -> Operational_Policy_Report {
	r: Operational_Policy_Report
	exposure := [6]i32{0, 1, 3, 8, 20, 30}
	rescue_value := [6]i32{1, 3, 6, 5, 4, 3}
	evidence_value := [6]i32{0, 2, 20, 1, 8, 3}
	for cost, i in exposure {
		r.score[int(Operational_Policy.Rescue)] += rescue_value[i] - cost
		r.score[int(Operational_Policy.Conceal)] += evidence_value[i] / 2 - (i32(i) + 1)
		r.score[int(Operational_Policy.Withdraw)] += cost / 2 - rescue_value[i] / 2
	}
	for policy in Operational_Policy {
		wins_all := true
		for cost, i in exposure {
			rescue := rescue_value[i] - cost
			conceal := evidence_value[i] / 2 - (i32(i) + 1)
			withdraw := cost / 2 - rescue_value[i] / 2
			values := [3]i32{rescue, conceal, withdraw}
			for other in Operational_Policy do if other != policy && values[int(policy)] <= values[int(other)] {wins_all = false; break}
			if !wins_all do break
		}
		if wins_all {r.universally_dominant = true; r.dominant = policy; break}
	}
	return r
}

operational_social_choice_modifiers :: proc(
	c: ^Campaign,
	ship: Ship_ID,
	other: Ship_ID = 0,
) -> Operational_Choice_Modifiers {
	r: Operational_Choice_Modifiers
	if other != 0 {
		if i := ship_relationship_index(c, ship, other); i >= 0 {
			strength := c.ship_relationships[i].strength
			r.rescue_default += strength; r.staffing_substitution += strength
			r.joint_assignment += strength; r.exposure_acceptance += strength
		}
	}
	for relationship in c.relationships[:c.relationship_count] do if relationship.ship == ship {
		r.settlement_departure += relationship.strength
		r.council_support += relationship.strength
	}
	for relationship in c.institution_ship_relationships[:c.institution_ship_relationship_count] do if relationship.ship == ship {
		r.contributor_conditions += relationship.strength
		r.deviation_authority += relationship.stance == .Contested ? -1 : 1
	}
	if si := ship_index(c, ship); si >= 0 {
		captain := c.ships[si].captain
		for relationship in c.captain_relationships[:c.captain_relationship_count] do if relationship.captain == captain {
			r.captain_requests += i32(relationship.obligation) - i32(relationship.rivalry)
		}
	}
	if c.operational_practices[int(Operational_Practice.Mutual_Rescue)] >= 3 do r.rescue_default += 1
	if c.operational_practices[int(Operational_Practice.Covered_Withdrawal)] >= 3 do r.joint_assignment += 1
	if c.operational_practices[int(Operational_Practice.Accountable_Disclosure)] >= 3 {
		r.council_support += 1; r.deviation_authority += 1
	}
	if c.operational_practices[int(Operational_Practice.Shared_Survival)] >= 3 {
		r.staffing_substitution += 1; r.exposure_acceptance += 1
	}
	return r
}
