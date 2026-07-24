package game

import "core:fmt"

MAX_COMPACT_CALLS :: 3
MAX_COMPACT_OFFERS :: 6
MAX_COMPACT_EXPECTATIONS :: 6
MAX_COMPACT_COUNSEL_OPTIONS :: 3
MAX_COMPACT_APPROACHES :: 2
MAX_COMPACT_CALLBACKS :: 8
MAX_COMPACT_HISTORY :: 8
MAX_COMPACT_INTENT_CHANGES :: 8
COMPACT_CONTRACT_VERSION :: u32(1)

Compact_Call_ID :: distinct u32
Compact_Undertaking_ID :: distinct u32

Compact_Call_Source_Kind :: enum {
	None,
	Need,
	Historical_Front,
	Settlement,
	Institution,
	Ship,
	Precedent,
	Threat,
	Discovery,
	Operation_Callback,
}

Compact_Call_Source :: struct {
	kind:         Compact_Call_Source_Kind,
	index:        i32,
	id:           u64,
	causal_event: u64,
}

Compact_Call_Family :: enum {
	None,
	Survey_Verify,
	Rescue_Recover,
	Escort_Evacuate,
	Stabilize_Build,
	Defend_Intercept,
}

Compact_Call_Status :: enum {
	None,
	Open,
	Accepted,
	Resolved_Autonomously,
	Completed,
	Withdrawn,
	Expired,
}

Compact_Undertaking_Status :: enum {
	None,
	Planning,
	Operating,
	Returned,
	Withdrawn,
}

Compact_Operation_Route :: enum {
	None,
	Passage,
	Close_Engagement,
	Far_Engagement,
}

Compact_Expectation_Kind :: enum {
	None,
	Protect_Ship,
	Disclose_Findings,
	Prefer_Withdrawal,
	Rescue_When_Possible,
}

Compact_Response_Kind :: enum {
	None,
	Adopted,
	Amended,
	Rejected,
	Independent_Action,
}

Compact_Counsel_Action :: enum {
	None,
	Renew_Narrowly,
	Local_Response,
	Publish_Evidence,
}

Compact_Counsel_Option :: struct {
	action:           Compact_Counsel_Action,
	label:            string,
	required_event:   u64,
	projected_effect: string,
}

Compact_Approach_Kind :: enum {
	None,
	Remote_Observation,
	Deep_Verification,
	Rapid_Extraction,
	Stabilize_And_Recover,
	Route_Preparation,
	Concentrated_Escort,
	Immediate_Restoration,
	Resilient_Construction,
	Close_Defense,
	Delayed_Interception,
}

Compact_Approach :: struct {
	kind:               Compact_Approach_Kind,
	label:              string,
	operational_effect: string,
	exposure_summary:   string,
}

Compact_Escalation_Stage :: enum {
	Initial,
	Pressing,
	Critical,
	Transformed,
}

Compact_Offer :: struct {
	contributor:      Institution_ID,
	community:        Community_ID,
	ship:             Ship_ID,
	supplies:         i32,
	materials:        i32,
	propellant:       i32,
	condition:        Compact_Expectation_Kind,
	condition_detail: string,
	source_event:     u64,
	selected:         bool,
	available:        bool,
}

Compact_Call :: struct {
	id:                    Compact_Call_ID,
	family:                Compact_Call_Family,
	status:                Compact_Call_Status,
	source:                Compact_Call_Source,
	source_need_index:     i32,
	source_event:          u64,
	sponsor:               Institution_ID,
	sponsor_community:     Community_ID,
	beneficiary:           Community_ID,
	beneficiary_ship:      Ship_ID,
	opened_season:         i32,
	deadline:              i32,
	title:                 string,
	stakes:                string,
	autonomous_trajectory: string,
	approaches:            [MAX_COMPACT_APPROACHES]Compact_Approach,
	approach_count:        int,
	default_approach:      int,
	selected_approach:     int,
	escalation:            Compact_Escalation_Stage,
	offers:                [MAX_COMPACT_OFFERS]Compact_Offer,
	offer_count:           int,
	undertaking:           Compact_Undertaking_ID,
	resolution_event:      u64,
}

Undertaking_Intent :: struct {
	objective:          Operation_Objective,
	beneficiary:        Community_ID,
	beneficiary_ship:   Ship_ID,
	promised_attempt:   string,
	accepted_exposure:  Operation_Exposure,
	accepted_event:     u64,
	last_changed_event: u64,
}

Undertaking_Intent_Change :: struct {
	objective:         Operation_Objective,
	promised_attempt:  string,
	accepted_exposure: Operation_Exposure,
	reason:            string,
	communicated_at:   Campaign_Time,
	causal_event:      u64,
}

Compact_Resource_Ledger :: struct {
	reserved:  Operation_Resources,
	consumed:  Operation_Resources,
	recovered: Operation_Resources,
	lost:      Operation_Resources,
	released:  Operation_Resources,
	settled:   bool,
}

Standing_Doctrine :: struct {
	rescue:         Rescue_Policy,
	exposure:       Operation_Exposure,
	withdrawal:     Operation_Withdrawal,
	disclosure:     Disclosure_Policy,
	communications: Operation_Deviation_Authority,
	source_event:   u64,
}

Contributor_Expectation :: struct {
	contributor:  Institution_ID,
	community:    Community_ID,
	ship:         Ship_ID,
	kind:         Compact_Expectation_Kind,
	detail:       string,
	source_event: u64,
}

Operation_Charter :: struct {
	version:            u32,
	undertaking:        Compact_Undertaking_ID,
	call:               Compact_Call_ID,
	hard_authority:     Operation_Authority,
	undertaking_intent: Undertaking_Intent,
	intent:             string,
	intent_event:       u64,
	expectations:       [MAX_COMPACT_EXPECTATIONS]Contributor_Expectation,
	expectation_count:  int,
	doctrine:           Standing_Doctrine,
	standing_doctrine:  string,
	compiled_event:     u64,
	valid:              bool,
}

Compact_Operation_Preview :: struct {
	valid:                bool,
	source_actor:         Institution_ID,
	source_event:         u64,
	authority_basis:      string,
	intent:               string,
	expectations:         [MAX_COMPACT_EXPECTATIONS]Contributor_Expectation,
	expectation_count:    int,
	exposure:             Operation_Resources,
	standing_default:     string,
	authority_override:   string,
	intent_override:      string,
	expectation_override: string,
	doctrine_override:    string,
}

Compact_Undertaking :: struct {
	id:                   Compact_Undertaking_ID,
	call:                 Compact_Call_ID,
	status:               Compact_Undertaking_Status,
	accepted_event:       u64,
	intent:               string,
	operation:            Operation_Kind,
	route:                Compact_Operation_Route,
	approach:             Compact_Approach_Kind,
	charter:              Operation_Charter,
	intent_changes:       [MAX_COMPACT_INTENT_CHANGES]Undertaking_Intent_Change,
	intent_change_count:  int,
	seconded_ships:       [MAX_COMPACT_OFFERS]Ship_ID,
	seconded_count:       int,
	reserved:             Operation_Resources,
	resources_settled:    bool,
	resource_ledger:      Compact_Resource_Ledger,
	withdrawal_requested: bool,
	last_aftermath:       Operation_ID,
}

Compact_Counsel :: struct {
	available:       bool,
	call:            Compact_Call_ID,
	undertaking:     Compact_Undertaking_ID,
	aftermath:       Operation_ID,
	factual_basis:   u64,
	options:         [MAX_COMPACT_COUNSEL_OPTIONS]string,
	actions:         [MAX_COMPACT_COUNSEL_OPTIONS]Compact_Counsel_Option,
	option_count:    int,
	chosen:          int,
	response:        Compact_Response_Kind,
	response_reason: string,
	response_event:  u64,
}

Compact_Callback_Stage :: enum {
	None,
	Near_Term,
	Later,
	Resolved,
}

Compact_Callback_Effect :: enum {
	None,
	Source_Capacity,
	Offer_Reconsideration,
	Ship_History,
}

Compact_Callback :: struct {
	id:            u64,
	undertaking:   Compact_Undertaking_ID,
	call:          Compact_Call_ID,
	source:        Compact_Call_Source,
	operation:     Operation_ID,
	stage:         Compact_Callback_Stage,
	due_at:        Campaign_Time,
	causal_event:  u64,
	ship:          Ship_ID,
	contributor:   Institution_ID,
	effect:        Compact_Callback_Effect,
	value:         i32,
	detail:        string,
	applied_event: u64,
}

Expeditionary_Compact_State :: struct {
	version:                    u32,
	calls:                      [MAX_COMPACT_CALLS]Compact_Call,
	call_count:                 int,
	active:                     Compact_Undertaking,
	history:                    [MAX_COMPACT_HISTORY]Compact_Undertaking,
	history_count:              int,
	counsel:                    Compact_Counsel,
	next_call_id:               u32,
	next_undertaking_id:        u32,
	last_call_boundary_season:  i32,
	quiet_until_season:         i32,
	last_aftermath_operation:   Operation_ID,
	callbacks:                  [MAX_COMPACT_CALLBACKS]Compact_Callback,
	callback_count:             int,
	next_callback_id:           u64,
	family_last_surface_season: [5]i32,
}

compact_initialize :: proc(state: ^Expeditionary_Compact_State) {
	if state.version != 0 do return
	state.version = COMPACT_CONTRACT_VERSION
	state.next_call_id = 1
	state.next_undertaking_id = 1
	state.next_callback_id = 1
	state.last_call_boundary_season = -1
	state.quiet_until_season = -1
	state.counsel.chosen = -1
}

compact_approaches_for_family :: proc(
	family: Compact_Call_Family,
) -> (
	approaches: [MAX_COMPACT_APPROACHES]Compact_Approach,
	count: int,
	default_index: int,
) {
	switch family {
	case .Survey_Verify:
		approaches = {
			{
				.Remote_Observation,
				"RELAY REVIEW",
				"Compare the available record from range before committing a field team.",
				"Keeps ships at lower exposure; the record may remain incomplete.",
			},
			{
				.Deep_Verification,
				"FIELD VERIFICATION",
				"Send a team to the source to recover and authenticate direct evidence.",
				"Places seconded ships at higher exposure for a stronger record.",
			},
		}
	case .Rescue_Recover:
		approaches = {
			{
				.Rapid_Extraction,
				"RAPID EXTRACTION",
				"Reach survivors first; leave nonessential material behind.",
				"Reduces time at the site; recovered material will be limited.",
			},
			{
				.Stabilize_And_Recover,
				"STABILIZE AND RECOVER",
				"Make the site safe enough to recover people and essential material.",
				"Extends exposure; supports a broader recovery if the site holds.",
			},
		}
	case .Escort_Evacuate:
		approaches = {
			{
				.Route_Preparation,
				"ROUTE PREPARATION",
				"Survey and clear the route before the convoy enters it.",
				"Delays departure; conditions at the origin may worsen.",
			},
			{
				.Concentrated_Escort,
				"CONCENTRATED ESCORT",
				"Move the convoy now under a concentrated protective screen.",
				"Exposes more ships and passengers in the same engagement.",
			},
		}
	case .Stabilize_Build:
		approaches = {
			{
				.Immediate_Restoration,
				"IMMEDIATE RESTORATION",
				"Restore minimum function with material already within reach.",
				"Provides relief quickly; the restored capacity may be fragile.",
			},
			{
				.Resilient_Construction,
				"RESILIENT CONSTRUCTION",
				"Secure redundant capacity before the work is declared usable.",
				"Consumes more time and material before relief is available.",
			},
		}
	case .Defend_Intercept:
		approaches = {
			{
				.Close_Defense,
				"CLOSE DEFENSE",
				"Hold near the beneficiary and meet the attack there.",
				"Keeps the beneficiary inside the operational area.",
			},
			{
				.Delayed_Interception,
				"DELAYED INTERCEPTION",
				"Meet the threat at distance before it reaches the beneficiary.",
				"Uses delayed tracks and commands; the situation may change first.",
			},
		}
	case .None:
		return
	}
	count = MAX_COMPACT_APPROACHES
	default_index = 0
	return
}

compact_family_for_need :: proc(kind: Need_Kind) -> Compact_Call_Family {
	switch kind {
	case .Sustenance_Shortfall:
		return .Stabilize_Build
	case .Settlement_Demand:
		return .Escort_Evacuate
	case .Ship_Repair:
		return .Rescue_Recover
	case .Archive_Staffing:
		// Staff allocation is a fleet decision. It belongs in the public-need
		// process, where its institutional cost is visible, rather than being
		// disguised as an expedition.
		return .None
	case .Settlement_Defense:
		return .Defend_Intercept
	case .Representation, .Settlement_Charter, .Jurisdiction_Dispute, .Institution_Dispute:
		return .None
	}
	return .None
}

compact_call_source_is_visible :: proc(c: ^Campaign, need_index: int) -> bool {
	if need_index < 0 || need_index >= MAX_NEEDS do return false
	n := &c.needs[need_index]
	if !n.active || n.resolved || n.source_event == 0 do return false
	if compact_family_for_need(n.kind) == .None do return false
	for call in c.compact.calls {
		if call.status != .None && call.source_event == n.source_event do return false
	}
	return true
}

compact_source_is_visible :: proc(c: ^Campaign, source: Compact_Call_Source) -> bool {
	if source.kind == .None || source.causal_event == 0 do return false
	for call in c.compact.calls[:c.compact.call_count] {
		if call.status != .None &&
		   call.source.kind == source.kind &&
		   call.source.id == source.id &&
		   call.source.causal_event == source.causal_event {
			return false
		}
	}
	return true
}

compact_actor_name :: proc(
	c: ^Campaign,
	institution: Institution_ID,
	community: Community_ID,
) -> string {
	if at := institution_index(c, institution); at >= 0 do return c.institutions[at].name
	if at := community_index(c, community); at >= 0 do return c.communities[at].name
	return "an independent contributor"
}

compact_beneficiary_name :: proc(c: ^Campaign, n: ^Need) -> string {
	if at := ship_index(c, n.ship); at >= 0 do return c.ships[at].name
	if at := settlement_index(c, n.settlement); at >= 0 do return c.settlements[at].name
	if at := community_index(c, n.community); at >= 0 do return c.communities[at].name
	return "the affected people"
}

compact_offer_condition :: proc(
	c: ^Campaign,
	ship: ^Ship,
	contributor: Institution_ID,
) -> Compact_Expectation_Kind {
	if at := institution_index(c, contributor); at >= 0 {
		switch c.institutions[at].rescue_policy {
		case .Absolute_Duty:
			return .Rescue_When_Possible
		case .Mutual_Aid:
			return .Protect_Ship
		case .Discretionary:
		}
		if c.institutions[at].disclosure_policy == .Open do return .Disclose_Findings
	}
	if ship.damage > 0 do return .Prefer_Withdrawal
	return .Protect_Ship
}

compact_condition_detail :: proc(
	ship_name: string,
	condition: Compact_Expectation_Kind,
) -> string {
	switch condition {
	case .Protect_Ship:
		return fmt.tprintf(
			"%s is offered with an expectation of proportionate exposure.",
			ship_name,
		)
	case .Disclose_Findings:
		return "Recovered findings are expected to enter the open record."
	case .Prefer_Withdrawal:
		return fmt.tprintf("%s should withdraw before further structural damage.", ship_name)
	case .Rescue_When_Possible:
		return(
			"The contributor expects rescue to take priority when it remains physically possible." \
		)
	case .None:
	}
	return ""
}

compact_add_offer :: proc(
	c: ^Campaign,
	call: ^Compact_Call,
	ship_index_value: int,
	source: ^Need,
) {
	if ship_index_value < 0 || ship_index_value >= c.ship_count || call.offer_count >= MAX_COMPACT_OFFERS do return
	ship := &c.ships[ship_index_value]
	if !ship.active || ship.committed do return
	for offer in call.offers[:call.offer_count] do if offer.ship == ship.id do return
	contributor := source.institution
	if contributor == 0 {
		for institution in c.institutions {
			if institution.active && institution.community == ship.community {
				contributor = institution.id
				break
			}
		}
	}
	condition := compact_offer_condition(c, ship, contributor)
	available := true
	if relationship_at := institution_ship_relationship_index(c, contributor, ship.id);
	   relationship_at >= 0 {
		relationship := c.institution_ship_relationships[relationship_at]
		if relationship.stance == .Contested {
			condition = .Prefer_Withdrawal
			available = relationship.strength > -2
		}
	}
	call.offers[call.offer_count] = {
		contributor      = contributor,
		community        = ship.community,
		ship             = ship.id,
		supplies         = source.cost > 0 ? min(source.cost, 4) : 0,
		propellant       = 2,
		condition        = condition,
		condition_detail = compact_condition_detail(ship.name, condition),
		source_event     = source.source_event,
		available        = available,
	}
	call.offer_count += 1
}

// Calls sometimes originate before the need has been assigned to a particular
// institution. They still need a real reviewer before they can become an
// undertaking, so resolve one from the affected community (and finally from
// the active Compact) rather than leaving an unacceptably anonymous call open.
compact_resolve_call_sponsor :: proc(
	c: ^Campaign,
	candidate: Institution_ID,
	community: Community_ID,
) -> Institution_ID {
	if at := institution_index(c, candidate); at >= 0 && c.institutions[at].active do return candidate
	for institution in c.institutions do if institution.active && institution.community == community do return institution.id
	for institution in c.institutions do if institution.active do return institution.id
	return 0
}

compact_make_call :: proc(c: ^Campaign, need_index: int) -> (call: Compact_Call, ok: bool) {
	if !compact_call_source_is_visible(c, need_index) do return
	n := &c.needs[need_index]
	sponsor_id := compact_resolve_call_sponsor(c, n.institution, n.community)
	if sponsor_id == 0 do return
	call.id = Compact_Call_ID(c.compact.next_call_id)
	call.family = compact_family_for_need(n.kind)
	call.status = .Open
	call.source = {
		kind         = .Need,
		index        = i32(need_index),
		id           = u64(need_index),
		causal_event = n.source_event,
	}
	call.source_need_index = i32(need_index)
	call.source_event = n.source_event
	call.sponsor = sponsor_id
	call.sponsor_community = n.community
	call.beneficiary = n.community
	call.beneficiary_ship = n.ship
	call.opened_season = c.season
	call.deadline = n.deadline
	sponsor := compact_actor_name(c, sponsor_id, n.community)
	beneficiary := compact_beneficiary_name(c, n)
	call.title = fmt.tprintf("%s asks the Compact to aid %s", sponsor, beneficiary)
	call.stakes = fmt.tprintf("%s %s", beneficiary, n.detail)
	call.autonomous_trajectory = fmt.tprintf(
		"If the Compact does not undertake this call by season %d, %s will proceed with available local capacity.",
		n.deadline,
		sponsor,
	)
	call.approaches, call.approach_count, call.default_approach = compact_approaches_for_family(
		call.family,
	)
	call.selected_approach = call.default_approach
	if n.ship != 0 do compact_add_offer(c, &call, ship_index(c, n.ship), n)
	for ship, i in c.ships[:c.ship_count] {
		if call.offer_count >= MAX_COMPACT_OFFERS do break
		if ship.community == n.community do compact_add_offer(c, &call, i, n)
	}
	for _, i in c.ships[:c.ship_count] {
		if call.offer_count >= 2 do break
		compact_add_offer(c, &call, i, n)
	}
	ok = call.offer_count > 0
	return
}

compact_make_sourced_call :: proc(
	c: ^Campaign,
	source: Compact_Call_Source,
	family: Compact_Call_Family,
	sponsor: Institution_ID,
	community: Community_ID,
	beneficiary_ship: Ship_ID,
	title, stakes, trajectory: string,
	deadline: i32,
) -> (
	call: Compact_Call,
	ok: bool,
) {
	if !compact_source_is_visible(c, source) || family == .None do return
	resolved_sponsor := sponsor
	resolved_community := community
	if resolved_sponsor == 0 {
		for institution in c.institutions do if institution.active && (resolved_community == 0 || institution.community == resolved_community) {
			resolved_sponsor = institution.id
			break
		}
	}
	if resolved_sponsor == 0 || institution_index(c, resolved_sponsor) < 0 do return
	if resolved_community == 0 {
		if at := institution_index(c, resolved_sponsor); at >= 0 do resolved_community = c.institutions[at].community
	}
	if resolved_community == 0 && beneficiary_ship != 0 {
		if at := ship_index(c, beneficiary_ship); at >= 0 do resolved_community = c.ships[at].community
	}
	if resolved_community == 0 do return
	call = {
		id                    = Compact_Call_ID(c.compact.next_call_id),
		family                = family,
		status                = .Open,
		source                = source,
		source_need_index     = -1,
		source_event          = source.causal_event,
		sponsor               = resolved_sponsor,
		sponsor_community     = resolved_community,
		beneficiary           = resolved_community,
		beneficiary_ship      = beneficiary_ship,
		opened_season         = c.season,
		deadline              = max(deadline, c.season + 1),
		title                 = fmt.tprintf("%s", title),
		stakes                = fmt.tprintf("%s", stakes),
		autonomous_trajectory = fmt.tprintf("%s", trajectory),
	}
	call.approaches, call.approach_count, call.default_approach = compact_approaches_for_family(
		family,
	)
	call.selected_approach = call.default_approach
	offer_source := Need {
		community    = resolved_community,
		ship         = beneficiary_ship,
		cost         = 2,
		source_event = source.causal_event,
		institution  = resolved_sponsor,
	}
	if beneficiary_ship != 0 do compact_add_offer(c, &call, ship_index(c, beneficiary_ship), &offer_source)
	for ship, i in c.ships[:c.ship_count] {
		if call.offer_count >= 3 do break
		if ship.community == resolved_community do compact_add_offer(c, &call, i, &offer_source)
	}
	for _, i in c.ships[:c.ship_count] {
		if call.offer_count >= 2 do break
		compact_add_offer(c, &call, i, &offer_source)
	}
	ok = call.offer_count > 0
	return
}

compact_make_world_call :: proc(c: ^Campaign) -> (call: Compact_Call, ok: bool) {
	for callback, i in c.compact.callbacks[:c.compact.callback_count] {
		if callback.stage != .Resolved ||
		   callback.effect != .Source_Capacity ||
		   callback.applied_event == 0 {
			continue
		}
		origin_at := compact_call_index(c, callback.call)
		if origin_at < 0 do continue
		origin := &c.compact.calls[origin_at]
		source := Compact_Call_Source {
			.Operation_Callback,
			i32(i),
			callback.id,
			callback.applied_event,
		}
		if !compact_source_is_visible(c, source) do continue
		return compact_make_sourced_call(
			c,
			source,
			origin.family,
			origin.sponsor,
			origin.beneficiary,
			origin.beneficiary_ship,
			"A prior undertaking returns as a narrower exceptional call",
			callback.detail,
			"The sponsor applies the report through its own reduced local response.",
			c.season + 2,
		)
	}
	for case_record, i in c.precedent_cases[:c.precedent_case_count] {
		if case_record.status != .Pending ||
		   case_record.review_season > c.season ||
		   case_record.last_event == 0 ||
		   case_record.responsible_institution == 0 ||
		   case_record.affected_community == 0 {
			continue
		}
		source := Compact_Call_Source {
			.Precedent,
			i32(i),
			u64(case_record.id),
			case_record.last_event,
		}
		if !compact_source_is_visible(c, source) do continue
		return compact_make_sourced_call(
			c,
			source,
			.Survey_Verify,
			case_record.responsible_institution,
			case_record.affected_community,
			case_record.initiator_ship,
			"A precedent review requests operational verification",
			"Conflicting precedent cannot be evaluated from the existing factual record.",
			"The responsible institution reviews the case from existing testimony and authority.",
			c.season + 2,
		)
	}
	for institution, i in c.institutions {
		if !institution.active || institution.legitimacy > 30 || institution.community == 0 {
			continue
		}
		source_event := latest_event_for_institution(c, institution.id)
		source := Compact_Call_Source{.Institution, i32(i), u64(institution.id), source_event}
		if !compact_source_is_visible(c, source) do continue
		return compact_make_sourced_call(
			c,
			source,
			.Survey_Verify,
			institution.id,
			institution.community,
			0,
			fmt.tprintf("%s requests independent operational verification", institution.name),
			"Available institutional evidence no longer supports a confident capacity forecast.",
			"The institution continues under its existing authority with reduced confidence.",
			c.season + 2,
		)
	}
	for front, i in c.fronts[:c.front_count] {
		if front.dormant || front.pressure <= 2 || front.last_change_event == 0 do continue
		source := Compact_Call_Source{.Threat, i32(i), u64(front.id), front.last_change_event}
		if !compact_source_is_visible(c, source) do continue
		return compact_make_sourced_call(
			c,
			source,
			.Defend_Intercept,
			0,
			0,
			0,
			fmt.tprintf("The Compact receives an interception call from %s", front.name),
			fmt.tprintf(
				"%s is under pressure %d; delay will change the operational geometry.",
				front.name,
				front.pressure,
			),
			"The responsible actors continue their existing defense and the front changes without Compact control.",
			c.season + 2,
		)
	}
	for settlement, i in c.settlements[:c.settlement_count] {
		if !settlement.active || settlement.viability >= 55 || settlement.last_report_event == 0 do continue
		source := Compact_Call_Source {
			.Settlement,
			i32(i),
			u64(settlement.id),
			settlement.last_report_event,
		}
		if !compact_source_is_visible(c, source) do continue
		return compact_make_sourced_call(
			c,
			source,
			.Stabilize_Build,
			0,
			settlement.founding_community,
			0,
			fmt.tprintf("%s requests exceptional stabilization", settlement.name),
			fmt.tprintf(
				"%s has viability %d and cannot restore full redundancy locally.",
				settlement.name,
				settlement.viability,
			),
			"The settlement contracts or redirects local capacity under its own authority.",
			c.season + 2,
		)
	}
	for ship, i in c.ships[:c.ship_count] {
		// A damaged ship remains a local maintenance problem until damage has
		// become severe or left a permanent scar. Only then does a recovery
		// undertaking justify seconding other ships from the fleet.
		if !ship.active || (ship.damage < 3 && ship.scar == .None) do continue
		source_event := latest_ship_event(c, ship.id)
		source := Compact_Call_Source{.Ship, i32(i), u64(ship.id), source_event}
		if !compact_source_is_visible(c, source) do continue
		return compact_make_sourced_call(
			c,
			source,
			.Rescue_Recover,
			0,
			ship.community,
			ship.id,
			fmt.tprintf("%s requests exceptional recovery support", ship.name),
			fmt.tprintf(
				"%s carries damage %d and continued service risks lasting impairment.",
				ship.name,
				ship.damage,
			),
			"The ship and its community choose a local repair, withdrawal, or continued-service response.",
			c.season + 2,
		)
	}
	for candidate, i in c.candidate_homes[:c.candidate_home_count] {
		if candidate.independent_review || candidate.discovered_event == 0 do continue
		source := Compact_Call_Source{.Discovery, i32(i), u64(i + 1), candidate.discovered_event}
		if !compact_source_is_visible(c, source) do continue
		return compact_make_sourced_call(
			c,
			source,
			.Survey_Verify,
			2,
			0,
			0,
			"The Navigation Guild requests independent verification",
			"A candidate home has evidence strong enough to justify exceptional verification.",
			"Institutions continue evaluating the discovery from the evidence already available.",
			c.season + 3,
		)
	}
	return
}

compact_clear_call :: proc(c: ^Campaign, call: ^Compact_Call) {
	if c.owns_strings {
		destroy_owned_string(call.title)
		destroy_owned_string(call.stakes)
		destroy_owned_string(call.autonomous_trajectory)
		for offer in call.offers do destroy_owned_string(offer.condition_detail)
	}
	call^ = {}
}

compact_surface_one_call :: proc(c: ^Campaign) -> bool {
	compact_initialize(&c.compact)
	if c.compact.last_call_boundary_season == c.season || c.season < c.compact.quiet_until_season {
		return false
	}
	slot := c.compact.call_count
	if slot >= MAX_COMPACT_CALLS {
		slot = -1
		for call, i in c.compact.calls {
			if call.status != .Open && call.status != .Accepted {
				slot = i
				break
			}
		}
		if slot < 0 do return false
	}
	for need, i in c.needs {
		if !compact_call_source_is_visible(c, i) do continue
		call, ok := compact_make_call(c, i)
		if !ok do continue
		family_index := int(call.family) - 1
		if family_index >= 0 &&
		   c.compact.family_last_surface_season[family_index] > 0 &&
		   c.season - c.compact.family_last_surface_season[family_index] < 2 {
			continue
		}
		if slot < c.compact.call_count do compact_clear_call(c, &c.compact.calls[slot])
		c.compact.calls[slot] = call
		if slot == c.compact.call_count do c.compact.call_count += 1
		c.compact.next_call_id += 1
		c.compact.last_call_boundary_season = c.season
		c.compact.family_last_surface_season[family_index] = c.season
		record_event(
			c,
			.Need_Surfaced,
			fmt.tprintf("The Expeditionary Compact received a call: %s", call.title),
			cause_sequence = call.source_event,
			community = call.beneficiary,
			institution_id = call.sponsor,
		)
		return true
	}
	call, ok := compact_make_world_call(c)
	if ok {
		if slot < c.compact.call_count do compact_clear_call(c, &c.compact.calls[slot])
		c.compact.calls[slot] = call
		if slot == c.compact.call_count do c.compact.call_count += 1
		c.compact.next_call_id += 1
		c.compact.last_call_boundary_season = c.season
		c.compact.family_last_surface_season[int(call.family) - 1] = c.season
		record_event(
			c,
			.Need_Surfaced,
			fmt.tprintf("The Expeditionary Compact received a call: %s", call.title),
			cause_sequence = call.source_event,
			community = call.beneficiary,
			institution_id = call.sponsor,
		)
		return true
	}
	return false
}

compact_refresh_calls :: proc(c: ^Campaign) {
	compact_initialize(&c.compact)
	for &call in c.compact.calls[:c.compact.call_count] {
		if call.status != .Open do continue
		source_resolved := false
		source_event := call.source.causal_event
		switch call.source.kind {
		case .Need:
			index := int(call.source.index)
			if index < 0 || index >= MAX_NEEDS {
				source_resolved = true
			} else {
				n := &c.needs[index]
				source_resolved = !n.active || n.resolved
				source_event = n.source_event
			}
		case .Historical_Front, .Threat:
			index := int(call.source.index)
			if index < 0 || index >= c.front_count {
				source_resolved = true
			} else {
				front := &c.fronts[index]
				source_resolved = front.dormant || front.pressure <= 2
				source_event = front.last_change_event
			}
		case .Settlement:
			index := int(call.source.index)
			if index < 0 || index >= c.settlement_count {
				source_resolved = true
			} else {
				settlement := &c.settlements[index]
				source_resolved = !settlement.active || settlement.viability >= 55
				source_event = settlement.last_report_event
			}
		case .Ship:
			at := ship_index(c, Ship_ID(call.source.id))
			if at < 0 {
				source_resolved = true
			} else {
				source_resolved = !c.ships[at].active || c.ships[at].damage < 2
				source_event = latest_ship_event(c, c.ships[at].id)
			}
		case .Discovery:
			index := int(call.source.index)
			if index < 0 || index >= c.candidate_home_count {
				source_resolved = true
			} else {
				candidate := &c.candidate_homes[index]
				source_resolved = candidate.independent_review
				source_event = candidate.discovered_event
			}
		case .Institution:
			index := int(call.source.index)
			if index < 0 || index >= len(c.institutions) {
				source_resolved = true
			} else {
				institution := &c.institutions[index]
				source_resolved = !institution.active || institution.legitimacy > 30
				source_event = latest_event_for_institution(c, institution.id)
			}
		case .Precedent:
			index := int(call.source.index)
			if index < 0 || index >= c.precedent_case_count {
				source_resolved = true
			} else {
				case_record := &c.precedent_cases[index]
				source_resolved = case_record.status != .Pending
				source_event = case_record.last_event
			}
		case .Operation_Callback:
			index := int(call.source.index)
			if index < 0 || index >= c.compact.callback_count {
				source_resolved = true
			} else {
				callback := &c.compact.callbacks[index]
				source_resolved = callback.stage != .Resolved
				source_event = callback.applied_event
			}
		case .None:
			source_resolved = true
		}
		if source_resolved {
			call.status = .Resolved_Autonomously
			call.resolution_event = source_event
		} else if c.season > call.deadline {
			switch call.escalation {
			case .Initial:
				call.escalation = .Pressing
				call.deadline = c.season + 1
			case .Pressing:
				call.escalation = .Critical
				call.deadline = c.season + 1
			case .Critical:
				prior_family := call.family
				switch call.family {
				case .Survey_Verify:
					call.family = .Rescue_Recover
				case .Rescue_Recover:
					call.family = .Escort_Evacuate
				case .Escort_Evacuate:
					call.family = .Defend_Intercept
				case .Stabilize_Build:
					call.family = .Escort_Evacuate
				case .Defend_Intercept:
					call.family = .Rescue_Recover
				case .None:
				}
				call.escalation = .Transformed
				call.deadline = c.season + 1
				if c.owns_strings {
					for approach in call.approaches {
						destroy_owned_string(approach.label)
						destroy_owned_string(approach.operational_effect)
						destroy_owned_string(approach.exposure_summary)
					}
				}
				call.approaches, call.approach_count, call.default_approach =
					compact_approaches_for_family(call.family)
				call.selected_approach = call.default_approach
				if c.owns_strings {
					destroy_owned_string(call.title)
					destroy_owned_string(call.stakes)
				}
				call.title = fmt.tprintf(
					"A deferred %v call has become %v",
					prior_family,
					call.family,
				)
				call.stakes = fmt.tprintf(
					"The source changed while the Compact waited; the original operational problem no longer exists.",
				)
			case .Transformed:
				call.status = .Expired
				call.resolution_event = source_event
			}
		}
		for &offer in call.offers[:call.offer_count] {
			at := ship_index(c, offer.ship)
			offer.available = at >= 0 && c.ships[at].active && !c.ships[at].committed
			if relationship_at := institution_ship_relationship_index(
				c,
				offer.contributor,
				offer.ship,
			); relationship_at >= 0 {
				relationship := c.institution_ship_relationships[relationship_at]
				if relationship.stance == .Contested && relationship.strength <= -2 do offer.available = false
			}
		}
	}
}

compact_advance_reporting_boundary :: proc(c: ^Campaign) {
	compact_refresh_calls(c)
	compact_advance_callbacks(c)
	_ = compact_surface_one_call(c)
}

compact_schedule_callback :: proc(
	c: ^Campaign,
	u: ^Compact_Undertaking,
	call: ^Compact_Call,
	operation: Operation_ID,
	stage: Compact_Callback_Stage,
	due_at: Campaign_Time,
	cause: u64,
	detail: string,
	value: i32 = 0,
) -> bool {
	if c.compact.callback_count >= MAX_COMPACT_CALLBACKS do return false
	callback := &c.compact.callbacks[c.compact.callback_count]
	callback^ = {
		id           = c.compact.next_callback_id,
		undertaking  = u.id,
		call         = call.id,
		source       = call.source,
		operation    = operation,
		stage        = stage,
		due_at       = due_at,
		causal_event = cause,
		value        = value,
		detail       = fmt.tprintf("%s", detail),
	}
	if u.seconded_count > 0 do callback.ship = u.seconded_ships[0]
	if u.charter.expectation_count > 0 {
		callback.contributor = u.charter.expectations[0].contributor
	}
	callback.effect =
		stage == .Near_Term ? .Source_Capacity : stage == .Later ? .Offer_Reconsideration : .None
	c.compact.callback_count += 1
	c.compact.next_callback_id += 1
	return true
}

compact_advance_callbacks :: proc(c: ^Campaign) {
	for &callback in c.compact.callbacks[:c.compact.callback_count] {
		if callback.stage == .None ||
		   callback.stage == .Resolved ||
		   callback.due_at > c.clock.now {
			continue
		}
		switch callback.effect {
		case .Source_Capacity:
			#partial switch callback.source.kind {
			case .Need:
				index := int(callback.source.index)
				if index >= 0 && index < MAX_NEEDS {
					need := &c.needs[index]
					need.cost = max(need.cost - callback.value, 0)
					need.source_event = callback.causal_event
				}
			case .Settlement:
				for &settlement in c.settlements[:c.settlement_count] do if u64(settlement.id) == callback.source.id {
					settlement.viability = clamp(settlement.viability + callback.value, 0, 100)
					settlement.last_report_event = callback.causal_event
					break
				}
			case .Historical_Front, .Threat:
				for &front in c.fronts[:c.front_count] do if u64(front.id) == callback.source.id {
					front.pressure = max(front.pressure - callback.value, 0)
					front.last_change_season = c.season
					front.last_change_event = callback.causal_event
					break
				}
			case .Institution:
				if at := institution_index(c, Institution_ID(callback.source.id)); at >= 0 {
					c.institutions[at].legitimacy = clamp(
						c.institutions[at].legitimacy + callback.value,
						0,
						100,
					)
				}
			case .Ship:
				if at := ship_index(c, Ship_ID(callback.source.id)); at >= 0 {
					c.ships[at].damage = max(c.ships[at].damage - callback.value, 0)
				}
			case:
			}
		case .Offer_Reconsideration:
			if callback.ship != 0 {
				add_ship_history(c, callback.ship, callback.detail)
				if callback.contributor != 0 {
					stance := callback.value < 0 ? Institution_Ship_Stance.Contested : .Stewardship
					_ = set_institution_ship_relationship(
						c,
						callback.contributor,
						callback.ship,
						stance,
						max(abs(callback.value), 1),
						callback.causal_event,
					)
				}
			}
		case .Ship_History:
			if callback.ship != 0 do add_ship_history(c, callback.ship, callback.detail)
		case .None:
		}
		record_event(
			c,
			.Situation_Response,
			callback.detail,
			callback.ship,
			cause_sequence = callback.causal_event,
			operation_id = u64(callback.operation),
		)
		callback.applied_event = c.event_sequence
		if callback.effect == .Source_Capacity {
			#partial switch callback.source.kind {
			case .Need:
				index := int(callback.source.index)
				if index >= 0 && index < MAX_NEEDS do c.needs[index].source_event = callback.applied_event
			case .Settlement:
				for &settlement in c.settlements[:c.settlement_count] do if u64(settlement.id) == callback.source.id {
					settlement.last_report_event = callback.applied_event
					break
				}
			case .Historical_Front, .Threat:
				for &front in c.fronts[:c.front_count] do if u64(front.id) == callback.source.id {
					front.last_change_event = callback.applied_event
					break
				}
			case:
			}
		}
		callback.stage = .Resolved
	}
}

compact_call_index :: proc(c: ^Campaign, id: Compact_Call_ID) -> int {
	for call, i in c.compact.calls[:c.compact.call_count] do if call.id == id do return i
	return -1
}

compact_toggle_offer :: proc(c: ^Campaign, call_id: Compact_Call_ID, offer_index: int) -> bool {
	if c.compact.counsel.available do return false
	if c.compact.active.status == .Planning || c.compact.active.status == .Operating do return false
	at := compact_call_index(c, call_id)
	if at < 0 do return false
	call := &c.compact.calls[at]
	if call.status != .Open || offer_index < 0 || offer_index >= call.offer_count do return false
	offer := &call.offers[offer_index]
	if !offer.available do return false
	offer.selected = !offer.selected
	return true
}

compact_select_approach :: proc(
	c: ^Campaign,
	call_id: Compact_Call_ID,
	approach_index: int,
) -> bool {
	if c.compact.counsel.available do return false
	if c.compact.active.status == .Planning || c.compact.active.status == .Operating do return false
	at := compact_call_index(c, call_id)
	if at < 0 do return false
	call := &c.compact.calls[at]
	if call.status != .Open || approach_index < 0 || approach_index >= call.approach_count do return false
	call.selected_approach = approach_index
	return true
}

compact_operation_for_family :: proc(family: Compact_Call_Family) -> Operation_Kind {
	if family == .Defend_Intercept do return .Combat
	return .Passage
}

compact_route_for_approach :: proc(approach: Compact_Approach_Kind) -> Compact_Operation_Route {
	switch approach {
	case .Close_Defense:
		return .Close_Engagement
	case .Delayed_Interception:
		return .Far_Engagement
	case .Remote_Observation,
	     .Deep_Verification,
	     .Rapid_Extraction,
	     .Stabilize_And_Recover,
	     .Route_Preparation,
	     .Concentrated_Escort,
	     .Immediate_Restoration,
	     .Resilient_Construction:
		return .Passage
	case .None:
	}
	return .None
}

compact_resources_equal :: proc(a, b: Operation_Resources) -> bool {
	return a.supplies == b.supplies && a.materials == b.materials && a.propellant == b.propellant
}

compact_resources_add :: proc(a, b: Operation_Resources) -> Operation_Resources {
	return {
		supplies = a.supplies + b.supplies,
		materials = a.materials + b.materials,
		propellant = a.propellant + b.propellant,
	}
}

compact_resources_valid :: proc(r: Operation_Resources) -> bool {
	return r.supplies >= 0 && r.materials >= 0 && r.propellant >= 0
}

compact_resources_within :: proc(value, limit: Operation_Resources) -> bool {
	return(
		compact_resources_valid(value) &&
		value.supplies <= limit.supplies &&
		value.materials <= limit.materials &&
		value.propellant <= limit.propellant \
	)
}

compact_resources_to_stock :: proc(r: Operation_Resources) -> Fleet_Stock {
	return {
		supplies = i64(r.supplies),
		manufactured_goods = i64(r.materials),
		propellant = i64(r.propellant),
	}
}

compact_aftermath_recovered_resources :: proc(a: ^Operation_Aftermath) -> Operation_Resources {
	if a == nil do return {}
	return {
		supplies = max(a.resources.supplies, 0),
		materials = max(a.resources.materials, 0),
		propellant = max(a.resources.propellant, 0),
	}
}

compact_resource_report_valid :: proc(u: ^Compact_Undertaking, a: ^Operation_Aftermath) -> bool {
	if u == nil || a == nil || u.resource_ledger.settled do return false
	return compact_resources_within(
		compact_aftermath_recovered_resources(a),
		u.resource_ledger.reserved,
	)
}

compact_resource_ledger_conserved :: proc(ledger: Compact_Resource_Ledger) -> bool {
	if !compact_resources_valid(ledger.reserved) ||
	   !compact_resources_valid(ledger.consumed) ||
	   !compact_resources_valid(ledger.recovered) ||
	   !compact_resources_valid(ledger.lost) ||
	   !compact_resources_valid(ledger.released) {
		return false
	}
	total := compact_resources_add(
		compact_resources_add(ledger.consumed, ledger.recovered),
		compact_resources_add(ledger.lost, ledger.released),
	)
	return !ledger.settled || compact_resources_equal(total, ledger.reserved)
}

compact_release_committed_resources :: proc(c: ^Campaign, reserved: Operation_Resources) -> bool {
	stock := compact_resources_to_stock(reserved)
	committed := &c.material_economy.fleet.committed
	if !fleet_stock_can_spend(committed^, stock) do return false
	committed^ = fleet_stock_sub(committed^, stock)
	return true
}

compact_settle_operation_resources :: proc(
	c: ^Campaign,
	u: ^Compact_Undertaking,
	a: ^Operation_Aftermath,
) -> bool {
	if !compact_resource_report_valid(u, a) do return false
	recovered := compact_aftermath_recovered_resources(a)
	if !compact_release_committed_resources(c, u.resource_ledger.reserved) do return false
	u.resource_ledger.recovered = recovered
	u.resource_ledger.consumed = {
		supplies   = u.resource_ledger.reserved.supplies - recovered.supplies,
		materials  = u.resource_ledger.reserved.materials - recovered.materials,
		propellant = u.resource_ledger.reserved.propellant - recovered.propellant,
	}
	u.resource_ledger.lost = {}
	u.resource_ledger.released = {}
	u.resource_ledger.settled = true
	u.resources_settled = true
	if recovered.supplies > 0 || recovered.materials > 0 || recovered.propellant > 0 {
		fleet_stock_gain(c, compact_resources_to_stock(recovered), .Recovery, a.intent_event)
	}
	return true
}

compact_archive_active :: proc(c: ^Campaign) -> bool {
	u := &c.compact.active
	if u.id == 0 || u.status == .Planning || u.status == .Operating do return false
	if c.compact.history_count >= MAX_COMPACT_HISTORY {
		for i in 1 ..< MAX_COMPACT_HISTORY {
			c.compact.history[i - 1] = c.compact.history[i]
		}
		c.compact.history_count = MAX_COMPACT_HISTORY - 1
	}
	c.compact.history[c.compact.history_count] = u^
	c.compact.history_count += 1
	c.compact.active = {}
	return true
}

compact_ship_is_seconded :: proc(c: ^Campaign, ship: Ship_ID) -> bool {
	u := &c.compact.active
	if u.status != .Planning && u.status != .Operating do return false
	for seconded in u.seconded_ships[:u.seconded_count] do if seconded == ship do return true
	return false
}

compact_operation_preview :: proc(c: ^Campaign) -> Compact_Operation_Preview {
	u := &c.compact.active
	if u.status != .Planning && u.status != .Operating do return {}
	if !u.charter.valid do return {}
	preview := Compact_Operation_Preview {
		valid                = true,
		source_actor         = u.charter.hard_authority.reviewer,
		source_event         = u.charter.hard_authority.compiled_event,
		authority_basis      = fmt.tprintf(
			"%s delegated the commands enumerated by the charter at event %d.",
			u.charter.hard_authority.reviewer_name,
			u.charter.hard_authority.compiled_event,
		),
		intent               = u.charter.intent,
		expectation_count    = u.charter.expectation_count,
		exposure             = u.resource_ledger.reserved,
		standing_default     = u.charter.standing_doctrine,
		authority_override   = "An unavailable command is recorded as unauthorized and is not silently legalized.",
		intent_override      = "A changed objective is recorded with its communication time and causal event.",
		expectation_override = "Affected contributors remember exposure, disclosure, rescue, and withdrawal conduct.",
		doctrine_override    = "Intervention replaces the standing default and records the resulting factual exposure.",
	}
	for expectation, i in u.charter.expectations[:u.charter.expectation_count] {
		preview.expectations[i] = expectation
	}
	return preview
}

compact_operation_ship_available :: proc(c: ^Campaign, ship: Ship_ID) -> bool {
	if c.compact.active.status == .Planning || c.compact.active.status == .Operating {
		return compact_ship_is_seconded(c, ship)
	}
	at := ship_index(c, ship)
	return at >= 0 && c.ships[at].active && !c.ships[at].committed
}

compact_compile_charter :: proc(
	c: ^Campaign,
	call: ^Compact_Call,
	undertaking: ^Compact_Undertaking,
) -> bool {
	authority, validation := compile_compact_operation_authority(c, call, undertaking)
	if !validation.valid do return false
	charter := &undertaking.charter
	charter.version = COMPACT_CONTRACT_VERSION
	charter.undertaking = undertaking.id
	charter.call = call.id
	charter.hard_authority = authority
	charter.undertaking_intent = {
		objective          = authority.objective,
		beneficiary        = call.beneficiary,
		beneficiary_ship   = call.beneficiary_ship,
		promised_attempt   = fmt.tprintf("%s", undertaking.intent),
		accepted_exposure  = authority.exposure,
		accepted_event     = undertaking.accepted_event,
		last_changed_event = undertaking.accepted_event,
	}
	charter.intent = fmt.tprintf("%s", undertaking.intent)
	charter.intent_event = undertaking.accepted_event
	charter.standing_doctrine = "Protect seconded ships, preserve return capability, and withdraw when the undertaking can no longer be pursued in good faith."
	charter.doctrine = {
		rescue         = authority.rescue,
		exposure       = authority.exposure,
		withdrawal     = authority.withdrawal,
		disclosure     = authority.disclosure,
		communications = authority.deviation,
		source_event   = undertaking.accepted_event,
	}
	charter.compiled_event = undertaking.accepted_event
	for offer in call.offers[:call.offer_count] {
		if !offer.selected || charter.expectation_count >= MAX_COMPACT_EXPECTATIONS do continue
		charter.expectations[charter.expectation_count] = {
			contributor  = offer.contributor,
			community    = offer.community,
			ship         = offer.ship,
			kind         = offer.condition,
			detail       = fmt.tprintf("%s", offer.condition_detail),
			source_event = offer.source_event,
		}
		charter.expectation_count += 1
	}
	charter.valid =
		charter.expectation_count > 0 &&
		charter.intent != "" &&
		charter.intent_event != 0 &&
		charter.hard_authority.valid
	return charter.valid
}

compact_accept_call :: proc(c: ^Campaign, call_id: Compact_Call_ID) -> bool {
	compact_initialize(&c.compact)
	if c.compact.counsel.available do return false
	if c.compact.active.status == .Planning || c.compact.active.status == .Operating do return false
	at := compact_call_index(c, call_id)
	if at < 0 do return false
	call := &c.compact.calls[at]
	if call.status != .Open do return false
	// Repair calls serialized by versions that permitted a missing sponsor. This
	// keeps an already-visible call actionable instead of making its button fail
	// solely because the originating need had not named an institution.
	call.sponsor = compact_resolve_call_sponsor(c, call.sponsor, call.sponsor_community)
	if call.sponsor == 0 do return false
	selected_count := 0
	for offer in call.offers[:call.offer_count] do if offer.selected && offer.available do selected_count += 1
	if selected_count == 0 do return false
	operation := compact_operation_for_family(call.family)
	undertaking: Compact_Undertaking
	undertaking.id = Compact_Undertaking_ID(c.compact.next_undertaking_id)
	undertaking.call = call.id
	undertaking.status = .Planning
	undertaking.operation = operation
	undertaking.approach = call.approaches[call.selected_approach].kind
	undertaking.route = compact_route_for_approach(undertaking.approach)
	undertaking.intent = fmt.tprintf(
		"Attempt the aid described in call %d: %s",
		call.id,
		call.stakes,
	)
	undertaking.accepted_event = call.source_event
	for &offer in call.offers[:call.offer_count] {
		if !offer.selected || !offer.available do continue
		if ship_at := ship_index(c, offer.ship); ship_at >= 0 do c.ships[ship_at].committed = true
		undertaking.seconded_ships[undertaking.seconded_count] = offer.ship
		undertaking.seconded_count += 1
		undertaking.reserved.supplies += max(offer.supplies, 0)
		undertaking.reserved.materials += max(offer.materials, 0)
		undertaking.reserved.propellant += max(offer.propellant, 0)
	}
	reserved_stock := Fleet_Stock {
		supplies           = i64(undertaking.reserved.supplies),
		manufactured_goods = i64(undertaking.reserved.materials),
		propellant         = i64(undertaking.reserved.propellant),
	}
	if (reserved_stock.supplies > 0 ||
		   reserved_stock.manufactured_goods > 0 ||
		   reserved_stock.propellant > 0) &&
	   !fleet_stock_transfer(c, reserved_stock, undertaking.accepted_event) {
		for ship in undertaking.seconded_ships[:undertaking.seconded_count] {
			if ship_at := ship_index(c, ship); ship_at >= 0 do c.ships[ship_at].committed = false
		}
		return false
	}
	if !compact_compile_charter(c, call, &undertaking) {
		for ship in undertaking.seconded_ships[:undertaking.seconded_count] {
			if ship_at := ship_index(c, ship); ship_at >= 0 do c.ships[ship_at].committed = false
		}
		fleet_stock_gain(c, reserved_stock, .Recovery, undertaking.accepted_event)
		return false
	}
	undertaking.resource_ledger.reserved = undertaking.reserved
	c.compact.active = undertaking
	c.compact.next_undertaking_id += 1
	call.status = .Accepted
	call.undertaking = undertaking.id
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The Expeditionary Compact accepted call %d as a good-faith undertaking with %d seconded ship(s).",
			call.id,
			selected_count,
		),
		cause_sequence = call.source_event,
		community = call.beneficiary,
		institution_id = call.sponsor,
	)
	return true
}

compact_redirect_intent :: proc(c: ^Campaign, change: Undertaking_Intent_Change) -> bool {
	u := &c.compact.active
	recorded_change := change
	if (u.status != .Planning && u.status != .Operating) ||
	   change.promised_attempt == "" ||
	   change.objective == .None ||
	   operation_objective_kind(change.objective) != u.operation ||
	   int(change.accepted_exposure) > int(u.charter.hard_authority.exposure) ||
	   u.intent_change_count >= MAX_COMPACT_INTENT_CHANGES {
		return false
	}
	if c.owns_strings {
		destroy_owned_string(u.intent)
		destroy_owned_string(u.charter.intent)
		destroy_owned_string(u.charter.undertaking_intent.promised_attempt)
	}
	u.intent = fmt.tprintf("%s", change.promised_attempt)
	u.charter.intent = fmt.tprintf("%s", change.promised_attempt)
	record_event(
		c,
		.Situation_Response,
		fmt.tprintf(
			"The Compact redirected undertaking %d: %s",
			u.id,
			change.reason == "" ? change.promised_attempt : change.reason,
		),
		cause_sequence = u.accepted_event,
	)
	recorded_change.causal_event = c.event_sequence
	if recorded_change.communicated_at == 0 do recorded_change.communicated_at = c.clock.now
	u.charter.intent_event = c.event_sequence
	u.charter.undertaking_intent.objective = change.objective
	u.charter.undertaking_intent.promised_attempt = fmt.tprintf("%s", change.promised_attempt)
	u.charter.undertaking_intent.accepted_exposure = change.accepted_exposure
	u.charter.undertaking_intent.last_changed_event = c.event_sequence
	u.charter.compiled_event = c.event_sequence
	u.intent_changes[u.intent_change_count] = {
		objective         = recorded_change.objective,
		promised_attempt  = fmt.tprintf("%s", recorded_change.promised_attempt),
		accepted_exposure = recorded_change.accepted_exposure,
		reason            = fmt.tprintf("%s", recorded_change.reason),
		communicated_at   = recorded_change.communicated_at,
		causal_event      = recorded_change.causal_event,
	}
	u.intent_change_count += 1
	return true
}

compact_change_intent :: proc(c: ^Campaign, intent: string) -> bool {
	u := &c.compact.active
	return compact_redirect_intent(
		c,
		{
			objective = u.charter.undertaking_intent.objective,
			promised_attempt = intent,
			accepted_exposure = u.charter.undertaking_intent.accepted_exposure,
			reason = intent,
			communicated_at = c.clock.now,
		},
	)
}

compact_withdraw_undertaking :: proc(c: ^Campaign, reason: string) -> bool {
	u := &c.compact.active
	if u.status != .Planning && u.status != .Operating do return false
	if u.status == .Operating {
		if u.withdrawal_requested do return false
		u.withdrawal_requested = true
		withdrawal_intent :=
			reason == "" ? "Withdraw under standing doctrine and return every surviving secondment." : reason
		_ = compact_change_intent(c, withdrawal_intent)
		record_event(
			c,
			.Situation_Response,
			fmt.tprintf(
				"The Compact ordered undertaking %d to withdraw through its active operation.",
				u.id,
			),
			cause_sequence = u.charter.intent_event,
		)
		return true
	}
	if !u.resource_ledger.settled &&
	   !fleet_stock_can_spend(
			   c.material_economy.fleet.committed,
			   compact_resources_to_stock(u.resource_ledger.reserved),
		   ) {
		return false
	}
	for ship in u.seconded_ships[:u.seconded_count] {
		if at := ship_index(c, ship); at >= 0 do c.ships[at].committed = false
	}
	if at := compact_call_index(c, u.call); at >= 0 {
		c.compact.calls[at].status = .Withdrawn
		c.compact.calls[at].resolution_event = c.event_sequence + 1
	}
	u.status = .Withdrawn
	if !u.resource_ledger.settled {
		if !compact_release_committed_resources(c, u.resource_ledger.reserved) {
			return false
		}
		fleet_stock_gain(
			c,
			compact_resources_to_stock(u.resource_ledger.reserved),
			.Recovery,
			u.accepted_event,
		)
		u.resource_ledger.released = u.resource_ledger.reserved
		u.resource_ledger.settled = true
		u.resources_settled = true
	}
	c.compact.quiet_until_season = c.season + 1
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The Compact withdrew undertaking %d and reported the reason: %s",
			u.id,
			reason == "" ? "the undertaking could no longer be pursued in good faith" : reason,
		),
		cause_sequence = u.accepted_event,
	)
	_ = compact_archive_active(c)
	return true
}

compact_source_apply_aftermath :: proc(
	c: ^Campaign,
	call: ^Compact_Call,
	a: ^Operation_Aftermath,
	cause: u64,
) {
	if call == nil || a == nil do return
	switch call.source.kind {
	case .Need:
		need_at := int(call.source.index)
		if need_at >= 0 && need_at < MAX_NEEDS {
			n := &c.needs[need_at]
			if n.source_event == call.source.causal_event {
				n.resolved = a.objective == .Achieved
				n.active = !n.resolved
				n.response = n.resolved ? .Resolved : .Deferred
			}
		}
	case .Historical_Front, .Threat:
		for &front in c.fronts[:c.front_count] do if u64(front.id) == call.source.id {
			if a.objective == .Achieved {
				front.pressure = max(front.pressure - 2, 0)
				front.stage = .Recovering
			} else {
				front.pressure += 1
			}
			front.last_change_event = cause
			front.last_change_season = c.season
			break
		}
	case .Ship:
		if at := ship_index(c, Ship_ID(call.source.id)); at >= 0 {
			if a.objective == .Achieved do c.ships[at].damage = max(c.ships[at].damage - 1, 0)
		}
	case .Settlement:
		for &settlement in c.settlements[:c.settlement_count] do if u64(settlement.id) == call.source.id {
			settlement.last_report_event = cause
			if a.objective == .Achieved do settlement.viability = min(settlement.viability + 1, 100)
			break
		}
	case .Institution, .Precedent, .Discovery, .Operation_Callback, .None:
	// These sources retain ownership of their ordinary simulation. The
	// authenticated report and callback are their deterministic input.
	}
}

compact_apply_contributor_observations :: proc(
	c: ^Campaign,
	u: ^Compact_Undertaking,
	a: ^Operation_Aftermath,
	cause: u64,
) {
	for expectation in u.charter.expectations[:u.charter.expectation_count] {
		if expectation.contributor == 0 || expectation.ship == 0 do continue
		delta: i32 = 1
		for outcome in a.ships[:a.ship_count] do if outcome.ship == expectation.ship {
			if outcome.lost || expectation.kind == .Protect_Ship && outcome.damage > 0 || expectation.kind == .Prefer_Withdrawal && outcome.damage > 0 && !outcome.withdrew {
				delta = -2
			}
			break
		}
		for observation in a.observations[:a.observation_count] do if observation.ship == expectation.ship {
			if observation.kind == .Expectation_Unmet || observation.kind == .Exposure_Exceeded || observation.kind == .Deviation_Uncommunicated || observation.kind == .Evidence_Withheld {
				delta = -2
			}
		}
		stance := delta < 0 ? Institution_Ship_Stance.Contested : .Stewardship
		_ = set_institution_ship_relationship(
			c,
			expectation.contributor,
			expectation.ship,
			stance,
			abs(delta),
			cause,
		)
	}
}

compact_counsel_action_available :: proc(
	c: ^Campaign,
	call: ^Compact_Call,
	action: Compact_Counsel_Action,
) -> bool {
	if c == nil || call == nil do return false
	sponsor_at := institution_index(c, call.sponsor)
	if sponsor_at < 0 || !c.institutions[sponsor_at].active do return false
	sponsor := &c.institutions[sponsor_at]
	switch action {
	case .Renew_Narrowly:
		return call.source.kind != .None && sponsor.legitimacy >= 20
	case .Local_Response:
		if sponsor.legitimacy < 30 do return false
		return(
			call.source.kind == .Settlement ||
			call.source.kind == .Historical_Front ||
			call.source.kind == .Threat \
		)
	case .Publish_Evidence:
		return sponsor.disclosure_policy != .Restricted
	case .None:
	}
	return false
}

compact_add_counsel_action :: proc(
	counsel: ^Compact_Counsel,
	action: Compact_Counsel_Action,
	label, projected_effect: string,
	basis: u64,
) {
	if counsel == nil || counsel.option_count >= MAX_COMPACT_COUNSEL_OPTIONS do return
	index := counsel.option_count
	counsel.actions[index] = {
		action           = action,
		label            = label,
		required_event   = basis,
		projected_effect = projected_effect,
	}
	counsel.options[index] = fmt.tprintf("%s", label)
	counsel.option_count += 1
}

compact_receive_aftermath :: proc(
	c: ^Campaign,
	a: ^Operation_Aftermath,
	report_event: u64,
) -> bool {
	if a == nil || a.id == 0 || c.compact.last_aftermath_operation == a.id do return false
	u := &c.compact.active
	if u.status != .Operating ||
	   a.undertaking_id != u.id ||
	   a.intent_event != u.charter.intent_event {
		return false
	}
	call_at := compact_call_index(c, u.call)
	if call_at < 0 do return false
	call := &c.compact.calls[call_at]
	if !compact_settle_operation_resources(c, u, a) do return false
	u.status = .Returned
	u.last_aftermath = a.id
	c.compact.last_aftermath_operation = a.id
	c.compact.quiet_until_season = c.season + 1
	for ship_id in u.seconded_ships[:u.seconded_count] {
		if at := ship_index(c, ship_id); at >= 0 do c.ships[at].committed = false
	}
	call.status = .Completed
	call.resolution_event = report_event
	compact_source_apply_aftermath(c, call, a, report_event)
	compact_apply_contributor_observations(c, u, a, report_event)
	lost, damaged, withdrawn := 0, 0, 0
	for outcome in a.ships[:a.ship_count] {
		if outcome.lost do lost += 1
		if outcome.damage > 0 do damaged += 1
		if outcome.withdrew do withdrawn += 1
	}
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"Compact report for call %d: objective %v; %d ship(s) damaged, %d lost, %d withdrawn; %d evidence item(s) recovered.",
			call.id,
			a.objective,
			damaged,
			lost,
			withdrawn,
			a.evidence_recovered,
		),
		cause_sequence = report_event,
		operation_id = u64(a.id),
	)
	c.compact.counsel = {
		chosen = -1,
	}
	if a.evidence_recovered > 0 && report_event != 0 && institution_index(c, call.sponsor) >= 0 {
		counsel := Compact_Counsel {
			available     = true,
			call          = call.id,
			undertaking   = u.id,
			aftermath     = a.id,
			factual_basis = report_event,
			chosen        = -1,
		}
		if compact_counsel_action_available(c, call, .Renew_Narrowly) {
			compact_add_counsel_action(
				&counsel,
				.Renew_Narrowly,
				"Recommend a renewed undertaking with narrower exposure.",
				"The sponsor may return the source as a narrower later call.",
				report_event,
			)
		}
		if compact_counsel_action_available(c, call, .Local_Response) {
			compact_add_counsel_action(
				&counsel,
				.Local_Response,
				"Recommend that the sponsor proceed locally using the recovered evidence.",
				"The originating subsystem receives a bounded local response.",
				report_event,
			)
		}
		if compact_counsel_action_available(c, call, .Publish_Evidence) {
			compact_add_counsel_action(
				&counsel,
				.Publish_Evidence,
				"Recommend publication before any further action.",
				"The authenticated report becomes public evidence.",
				report_event,
			)
		}
		counsel.available = counsel.option_count >= 2
		c.compact.counsel = counsel
	}
	_ = compact_schedule_callback(
		c,
		u,
		call,
		a.id,
		.Near_Term,
		campaign_time_add(c.clock.now, 7 * CAMPAIGN_DAY_SECONDS),
		report_event,
		"The undertaking's immediate physical consequences changed the sponsor's available capacity.",
		value = a.objective == .Achieved ? 1 : -1,
	)
	_ = compact_schedule_callback(
		c,
		u,
		call,
		a.id,
		.Later,
		campaign_time_add(c.clock.now, 3 * CAMPAIGN_REPORT_SECONDS),
		report_event,
		"The undertaking returned as later history: contributors reconsidered what they would offer next.",
		value = a.objective == .Achieved && a.losses == 0 ? 1 : -1,
	)
	_ = compact_archive_active(c)
	return true
}

compact_resolve_counsel :: proc(c: ^Campaign, option: int) -> bool {
	counsel := &c.compact.counsel
	if !counsel.available ||
	   counsel.response_event != 0 ||
	   option < -1 ||
	   option >= counsel.option_count {
		return false
	}
	counsel.chosen = option
	call_at := compact_call_index(c, counsel.call)
	if call_at < 0 do return false
	call := &c.compact.calls[call_at]
	legitimacy := i32(50)
	disclosure := Disclosure_Policy.Accountable
	if at := institution_index(c, call.sponsor); at >= 0 {
		legitimacy = c.institutions[at].legitimacy
		disclosure = c.institutions[at].disclosure_policy
	}
	action := Compact_Counsel_Action.None
	if option >= 0 do action = counsel.actions[option].action
	if option >= 0 &&
	   (counsel.actions[option].required_event != counsel.factual_basis ||
			   !compact_counsel_action_available(c, call, action)) {
		return false
	}
	if option < 0 {
		counsel.response = .Independent_Action
		counsel.response_reason = "No counsel was appended. The sponsor acted from its own authority, capacity, and the factual report."
	} else if action == .Publish_Evidence && disclosure == .Open {
		counsel.response = .Adopted
		counsel.response_reason = "The sponsor adopted publication because its standing disclosure policy favors an open record and authenticated evidence was available."
	} else if legitimacy >= 55 {
		counsel.response = .Amended
		counsel.response_reason = "The sponsor accepted the evidence but amended the recommendation to fit its own authority and available capacity."
	} else {
		counsel.response = .Rejected
		counsel.response_reason = "The sponsor retained the factual report but rejected the recommendation because its authority and institutional capacity were insufficient."
	}
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The sponsor responded %v to Compact counsel: %s",
			counsel.response,
			counsel.response_reason,
		),
		cause_sequence = counsel.factual_basis,
		institution_id = call.sponsor,
	)
	counsel.response_event = c.event_sequence
	if counsel.response == .Adopted || counsel.response == .Amended {
		switch action {
		case .Publish_Evidence:
			if at := institution_index(c, call.sponsor); at >= 0 {
				c.institutions[at].legitimacy = min(c.institutions[at].legitimacy + 1, 100)
			}
		case .Local_Response:
			#partial switch call.source.kind {
			case .Settlement:
				for &settlement in c.settlements[:c.settlement_count] do if u64(settlement.id) == call.source.id {
					settlement.viability = min(settlement.viability + 1, 100)
					settlement.last_report_event = c.event_sequence
					break
				}
			case .Historical_Front, .Threat:
				for &front in c.fronts[:c.front_count] do if u64(front.id) == call.source.id {
					front.pressure = max(front.pressure - 1, 0)
					front.last_change_event = c.event_sequence
					break
				}
			case:
			}
		case .Renew_Narrowly:
			if c.compact.callback_count < MAX_COMPACT_CALLBACKS {
				callback := &c.compact.callbacks[c.compact.callback_count]
				callback^ = {
					id           = c.compact.next_callback_id,
					undertaking  = counsel.undertaking,
					call         = counsel.call,
					source       = call.source,
					operation    = counsel.aftermath,
					stage        = .Later,
					due_at       = campaign_time_add(c.clock.now, CAMPAIGN_REPORT_SECONDS),
					causal_event = c.event_sequence,
					effect       = .Source_Capacity,
					detail       = fmt.tprintf(
						"The sponsor reconsidered the source as a narrower exceptional undertaking.",
					),
				}
				c.compact.callback_count += 1
				c.compact.next_callback_id += 1
			}
		case .None:
		}
	}
	counsel.available = false
	return true
}

validate_expeditionary_compact :: proc(c: ^Campaign) -> bool {
	if c.compact.version != COMPACT_CONTRACT_VERSION ||
	   c.compact.call_count < 0 ||
	   c.compact.call_count > MAX_COMPACT_CALLS ||
	   c.compact.callback_count < 0 ||
	   c.compact.callback_count > MAX_COMPACT_CALLBACKS ||
	   c.compact.history_count < 0 ||
	   c.compact.history_count > MAX_COMPACT_HISTORY ||
	   c.compact.next_call_id == 0 ||
	   c.compact.next_undertaking_id == 0 ||
	   c.compact.next_callback_id == 0 {
		return false
	}
	accepted_calls := 0
	for call_index in 0 ..< c.compact.call_count {
		call := &c.compact.calls[call_index]
		if call.id == 0 ||
		   call.source.kind == .None ||
		   call.source.causal_event != call.source_event ||
		   call.source_event == 0 ||
		   call.deadline < call.opened_season ||
		   call.title == "" ||
		   call.stakes == "" ||
		   call.autonomous_trajectory == "" ||
		   call.approach_count != MAX_COMPACT_APPROACHES ||
		   call.selected_approach < 0 ||
		   call.selected_approach >= call.approach_count ||
		   call.offer_count <= 0 ||
		   call.offer_count > MAX_COMPACT_OFFERS {
			return false
		}
		if call.sponsor == 0 ||
		   institution_index(c, call.sponsor) < 0 ||
		   call.beneficiary == 0 ||
		   community_index(c, call.beneficiary) < 0 {
			return false
		}
		for prior in c.compact.calls[:call_index] do if prior.id == call.id do return false
		if u32(call.id) >= c.compact.next_call_id do return false
		if call.status == .Accepted do accepted_calls += 1
		for offer in call.offers[:call.offer_count] {
			if offer.ship == 0 || offer.source_event == 0 || offer.condition == .None do return false
		}
	}
	for callback in c.compact.callbacks[:c.compact.callback_count] {
		if callback.id == 0 ||
		   callback.undertaking == 0 ||
		   callback.call == 0 ||
		   callback.source.kind == .None ||
		   callback.causal_event == 0 ||
		   callback.detail == "" ||
		   callback.stage == .None ||
		   callback.effect == .None {
			return false
		}
		if compact_call_index(c, callback.call) < 0 do return false
		found_undertaking := c.compact.active.id == callback.undertaking
		for undertaking in c.compact.history[:c.compact.history_count] do if undertaking.id == callback.undertaking {
			found_undertaking = true
			break
		}
		if !found_undertaking do return false
	}
	max_undertaking_id := u32(0)
	for undertaking, i in c.compact.history[:c.compact.history_count] {
		if undertaking.id == 0 ||
		   undertaking.status == .Planning ||
		   undertaking.status == .Operating ||
		   undertaking.route == .None ||
		   !undertaking.charter.valid ||
		   undertaking.charter.undertaking != undertaking.id ||
		   undertaking.charter.call != undertaking.call ||
		   undertaking.seconded_count <= 0 ||
		   !compact_resource_ledger_conserved(undertaking.resource_ledger) ||
		   !undertaking.resource_ledger.settled {
			return false
		}
		for prior in c.compact.history[:i] do if prior.id == undertaking.id do return false
		max_undertaking_id = max(max_undertaking_id, u32(undertaking.id))
	}
	if accepted_calls > 1 do return false
	if c.compact.active.status == .Planning || c.compact.active.status == .Operating {
		if accepted_calls != 1 ||
		   !c.compact.active.charter.valid ||
		   c.compact.active.seconded_count <= 0 ||
		   c.compact.active.route == .None ||
		   c.compact.active.charter.undertaking != c.compact.active.id ||
		   c.compact.active.charter.call != c.compact.active.call ||
		   c.compact.active.resource_ledger.settled ||
		   !compact_resource_ledger_conserved(c.compact.active.resource_ledger) ||
		   !compact_resources_equal(
				   c.compact.active.reserved,
				   c.compact.active.resource_ledger.reserved,
			   ) {
			return false
		}
		call_at := compact_call_index(c, c.compact.active.call)
		if call_at < 0 do return false
		call := &c.compact.calls[call_at]
		for ship in c.compact.active.seconded_ships[:c.compact.active.seconded_count] {
			matched := false
			for offer in call.offers[:call.offer_count] do if offer.selected && offer.ship == ship {
				matched = true
				break
			}
			if !matched do return false
		}
		max_undertaking_id = max(max_undertaking_id, u32(c.compact.active.id))
	}
	if c.compact.counsel.available {
		if c.compact.counsel.call == 0 ||
		   c.compact.counsel.undertaking == 0 ||
		   c.compact.counsel.aftermath == 0 ||
		   c.compact.counsel.factual_basis == 0 ||
		   c.compact.counsel.option_count < 2 ||
		   c.compact.counsel.option_count > MAX_COMPACT_COUNSEL_OPTIONS ||
		   compact_call_index(c, c.compact.counsel.call) < 0 {
			return false
		}
		for action in c.compact.counsel.actions[:c.compact.counsel.option_count] {
			if action.action == .None ||
			   action.label == "" ||
			   action.required_event != c.compact.counsel.factual_basis ||
			   action.projected_effect == "" {
				return false
			}
			call_at := compact_call_index(c, c.compact.counsel.call)
			if call_at < 0 ||
			   !compact_counsel_action_available(c, &c.compact.calls[call_at], action.action) {
				return false
			}
		}
	}
	if max_undertaking_id >= c.compact.next_undertaking_id do return false
	return true
}
