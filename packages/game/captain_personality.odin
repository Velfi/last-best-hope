package game

import "core:fmt"

MAX_CAPTAIN_MARKS :: 8
MAX_CAPTAIN_RELATIONSHIPS :: 128
MAX_CAPTAIN_OBLIGATIONS :: 64
CAPTAIN_FACET_COUNT :: 12

Captain_Facet :: enum {
	Life_Preservation,
	Mission_Commitment,
	Institutional_Duty,
	Personal_Autonomy,
	Solidarity,
	Discovery,
	Deliberation,
	Consultation,
	Procedure,
	Improvisation,
	Confrontation,
	Risk_Tolerance,
}

Captain_Context :: enum {
	General,
	Friendly_Fire,
	Rescue,
	Withdrawal,
	Pursuit,
	Objective_Exposure,
	Command_Degraded,
	Passage_Contact,
	Undertaking,
	Fleet_Situation,
}

Captain_Mark_Kind :: enum {
	Loss,
	Rescue,
	Breach,
	Commendation,
	Censure,
	Promise,
	Discovery,
	Succession,
}
Captain_Target_Kind :: enum {
	None,
	Ship,
	Captain,
	Community,
	Institution,
	Settlement,
}
Captain_Obligation_Status :: enum {
	Active,
	Complied,
	Reinterpreted,
	Refused,
	Breached,
	Released,
	Accounted,
}
Captain_Accountability_Outcome :: enum {
	None,
	Commendation,
	Reconciliation,
	Restitution,
	Censure,
	Restricted_Authority,
	Transfer,
	Dismissal,
	Resignation,
	Political_Realignment,
}

Captain_Mark :: struct {
	kind:             Captain_Mark_Kind,
	decision_context: Captain_Context,
	source_event:     u64,
	target_kind:      Captain_Target_Kind,
	target_id:        u32,
	intensity:        i8,
}

Captain_Profile :: struct {
	initialized:             bool,
	facets:                  [CAPTAIN_FACET_COUNT]u8,
	evidence:                [CAPTAIN_FACET_COUNT]i8,
	convictions:             [2]Captain_Facet,
	marks:                   [MAX_CAPTAIN_MARKS]Captain_Mark,
	mark_count:              int,
	autonomy_cooldown_until: i32,
	last_departure_event:    u64,
}

Captain_Relationship :: struct {
	captain:                                         Figure_ID,
	target_kind:                                     Captain_Target_Kind,
	target_id:                                       u32,
	trust, respect, attachment, obligation, rivalry: i8,
	origin_event, last_event:                        u64,
}

Captain_Obligation :: struct {
	id:                           u32,
	captain:                      Figure_ID,
	ship:                         Ship_ID,
	decision_context:             Captain_Context,
	status:                       Captain_Obligation_Status,
	issued_event, resolved_event: u64,
	issuer:                       Institution_ID,
	stakes:                       i8,
}

Captain_Decision_Option :: struct {
	available:     bool,
	complies:      bool,
	base_utility:  i16,
	facet_weights: [CAPTAIN_FACET_COUNT]i8,
	label:         string,
}

Captain_Decision_Query :: struct {
	captain:          Figure_ID,
	decision_context: Captain_Context,
	stakes:           i8,
	source_event:     u64,
	target_kind:      Captain_Target_Kind,
	target_id:        u32,
	options:          []Captain_Decision_Option,
}

Captain_Decision_Result :: struct {
	valid:             bool,
	option_index:      int,
	score:             i32,
	obligation_status: Captain_Obligation_Status,
	overt_departure:   bool,
	reason_facets:     [2]Captain_Facet,
	source_events:     [2]u64,
}

Captain_Dossier :: struct {
	valid:                                                               bool,
	name, office, status, primary_tendency, secondary_tendency, tension: string,
	ship:                                                                Ship_ID,
	predecessor:                                                         Figure_ID,
	mark_count, relationship_count, active_obligation_count:             int,
	last_noted_event:                                                    u64,
}

Captain_Appointment_Candidate :: struct {
	valid:       bool,
	name:        string,
	community:   Community_ID,
	institution: Institution_ID,
	endorsement: i8,
}

captain_mix :: proc(value: u64) -> u64 {
	x := value + 0x9e3779b97f4a7c15
	x = (x ~ (x >> 30)) * 0xbf58476d1ce4e5b9
	x = (x ~ (x >> 27)) * 0x94d049bb133111eb
	return x ~ (x >> 31)
}

captain_refresh_convictions :: proc(profile: ^Captain_Profile) {
	first, second := 0, 1
	for i in 0 ..< 6 {
		if profile.facets[i] >
		   profile.facets[first] {second = first; first = i} else if i != first && (second == first || profile.facets[i] > profile.facets[second]) {second = i}
	}
	profile.convictions = {Captain_Facet(first), Captain_Facet(second)}
}

captain_profile_initialize :: proc(c: ^Campaign, figure: ^Campaign_Historical_Figure) {
	profile := &figure.captain_profile
	if profile.initialized || figure.role != "ship captain" do return
	state := captain_mix(
		c.initial_seed ~
		(u64(figure.id) << 32) ~
		u64(figure.community) ~
		(u64(figure.ship) << 16) ~
		figure.origin_event,
	)
	profile.initialized = true
	for i in 0 ..< CAPTAIN_FACET_COUNT {
		state = captain_mix(state ~ u64(i + 1))
		profile.facets[i] = u8(state % 5)
	}
	// Office and origin provide tendencies, not archetypes.
	ship_at := ship_index(c, figure.ship)
	if ship_at >= 0 {
		#partial switch c.ships[ship_at].role {
		case .Hospital:
			profile.facets[int(Captain_Facet.Life_Preservation)] = min(
				profile.facets[int(Captain_Facet.Life_Preservation)] + 1,
				4,
			)
		case .Survey:
			profile.facets[int(Captain_Facet.Discovery)] = min(
				profile.facets[int(Captain_Facet.Discovery)] + 1,
				4,
			)
		case .Escort:
			profile.facets[int(Captain_Facet.Mission_Commitment)] = min(
				profile.facets[int(Captain_Facet.Mission_Commitment)] + 1,
				4,
			)
		}
	}
	captain_refresh_convictions(profile)
}

captain_facet_name :: proc(facet: Captain_Facet) -> string {
	switch facet {
	case .Life_Preservation:
		return "life-preserving"
	case .Mission_Commitment:
		return "mission-committed"
	case .Institutional_Duty:
		return "institution-minded"
	case .Personal_Autonomy:
		return "self-directing"
	case .Solidarity:
		return "mutual-aid oriented"
	case .Discovery:
		return "discovery-oriented"
	case .Deliberation:
		return "deliberate"
	case .Consultation:
		return "consultative"
	case .Procedure:
		return "procedural"
	case .Improvisation:
		return "improvisational"
	case .Confrontation:
		return "confrontational"
	case .Risk_Tolerance:
		return "risk-tolerant"
	}
	return "unrecorded"
}

captain_relationship_index :: proc(
	c: ^Campaign,
	captain: Figure_ID,
	kind: Captain_Target_Kind,
	target: u32,
) -> int {
	for relationship, i in c.captain_relationships[:c.captain_relationship_count] do if relationship.captain == captain && relationship.target_kind == kind && relationship.target_id == target do return i
	return -1
}

captain_target_exists :: proc(c: ^Campaign, kind: Captain_Target_Kind, target: u32) -> bool {
	switch kind {
	case .Ship:
		return ship_index(c, Ship_ID(target)) >= 0
	case .Captain:
		return historical_figure_index(c, Figure_ID(target)) >= 0
	case .Community:
		return community_index(c, Community_ID(target)) >= 0
	case .Institution:
		return institution_index(c, Institution_ID(target)) >= 0
	case .Settlement:
		return settlement_index(c, Settlement_ID(target)) >= 0
	case .None:
		return false
	}
	return false
}

captain_set_relationship :: proc(
	c: ^Campaign,
	captain: Figure_ID,
	kind: Captain_Target_Kind,
	target: u32,
	trust, respect, attachment, obligation, rivalry: i8,
	source: u64,
) -> bool {
	if historical_figure_index(c, captain) < 0 || !captain_target_exists(c, kind, target) || source == 0 || !event_reference_exists(c, source) do return false
	i := captain_relationship_index(c, captain, kind, target)
	if i < 0 {
		if c.captain_relationship_count >= MAX_CAPTAIN_RELATIONSHIPS do return false
		i = c.captain_relationship_count; c.captain_relationship_count += 1
		c.captain_relationships[i] = {
			captain      = captain,
			target_kind  = kind,
			target_id    = target,
			origin_event = source,
		}
	}
	r := &c.captain_relationships[i]
	r.trust = i8(
		clamp(i32(r.trust) + i32(trust), -4, 4),
	); r.respect = i8(clamp(i32(r.respect) + i32(respect), -4, 4)); r.attachment = i8(clamp(i32(r.attachment) + i32(attachment), -4, 4)); r.obligation = i8(clamp(i32(r.obligation) + i32(obligation), -4, 4)); r.rivalry = i8(clamp(i32(r.rivalry) + i32(rivalry), -4, 4)); r.last_event = source
	return true
}

captain_add_mark :: proc(c: ^Campaign, captain: Figure_ID, mark: Captain_Mark) -> bool {
	fi := historical_figure_index(
		c,
		captain,
	); if fi < 0 || mark.source_event == 0 || !event_reference_exists(c, mark.source_event) || mark.intensity < -4 || mark.intensity > 4 do return false
	p := &c.historical_figures[fi].captain_profile; if !p.initialized do captain_profile_initialize(c, &c.historical_figures[fi])
	if p.mark_count >=
	   MAX_CAPTAIN_MARKS {for i in 0 ..< MAX_CAPTAIN_MARKS - 1 do p.marks[i] = p.marks[i + 1]; p.mark_count = MAX_CAPTAIN_MARKS - 1}
	p.marks[p.mark_count] = mark; p.mark_count += 1
	return true
}

captain_record_evidence :: proc(
	c: ^Campaign,
	captain: Figure_ID,
	facet: Captain_Facet,
	amount: i8,
) -> bool {
	fi := historical_figure_index(c, captain); if fi < 0 || amount == 0 do return false
	p := &c.historical_figures[fi].captain_profile; if !p.initialized do captain_profile_initialize(c, &c.historical_figures[fi])
	i := int(facet); p.evidence[i] = i8(clamp(i32(p.evidence[i]) + i32(amount), -12, 12))
	threshold := i8(6 + i32(p.facets[i]))
	if p.evidence[i] >= threshold &&
	   p.facets[i] <
		   4 {p.facets[i] += 1; p.evidence[i] = 0; captain_refresh_convictions(p)} else if p.evidence[i] <= -threshold && p.facets[i] > 0 {p.facets[i] -= 1; p.evidence[i] = 0; captain_refresh_convictions(p)}
	return true
}

captain_issue_obligation :: proc(
	c: ^Campaign,
	captain: Figure_ID,
	ship: Ship_ID,
	decision_context: Captain_Context,
	issuer: Institution_ID,
	stakes: i8,
	cause: u64,
) -> u32 {
	if historical_figure_index(c, captain) < 0 || ship_index(c, ship) < 0 || cause == 0 || !event_reference_exists(c, cause) || c.captain_obligation_count >= MAX_CAPTAIN_OBLIGATIONS do return 0
	id := u32(
		c.captain_obligation_count + 1,
	); c.captain_obligations[c.captain_obligation_count] = {
		id               = id,
		captain          = captain,
		ship             = ship,
		decision_context = decision_context,
		status           = .Active,
		issued_event     = cause,
		issuer           = issuer,
		stakes           = i8(clamp(i32(stakes), 1, 4)),
	}; c.captain_obligation_count += 1; return id
}

captain_active_obligation_index :: proc(
	c: ^Campaign,
	captain: Figure_ID,
	decision_context: Captain_Context,
) -> int {
	for i := c.captain_obligation_count - 1;
	    i >= 0;
	    i -= 1 {o := c.captain_obligations[i]; if o.captain == captain && o.status == .Active && (o.decision_context == decision_context || o.decision_context == .General) do return i}
	return -1
}

captain_decide :: proc(c: ^Campaign, query: Captain_Decision_Query) -> Captain_Decision_Result {
	fi := historical_figure_index(
		c,
		query.captain,
	); if fi < 0 || len(query.options) == 0 do return {}
	figure := &c.historical_figures[fi]; if !figure.captain_profile.initialized do captain_profile_initialize(c, figure); p := &figure.captain_profile
	obligation_at := captain_active_obligation_index(c, query.captain, query.decision_context)
	best := -1; best_score := i32(-0x3fffffff); second_score := best_score; best_reasons: [2]Captain_Facet
	for option, oi in query.options {
		if !option.available do continue
		score := i32(
			option.base_utility,
		); top, next := 0, 1; top_value, next_value := i32(-1000), i32(-1000)
		for weight, i in option.facet_weights {contribution := i32(weight) * (i32(p.facets[i]) - 2); score += contribution; magnitude := abs(contribution); if magnitude > top_value {next, next_value = top, top_value; top, top_value = i, magnitude} else if magnitude > next_value {next, next_value = i, magnitude}}
		for mark in p.marks[:p.mark_count] do if mark.decision_context == query.decision_context || mark.decision_context == .General do score += i32(mark.intensity) * 2
		if ri := captain_relationship_index(c, query.captain, query.target_kind, query.target_id);
		   ri >=
		   0 {r := c.captain_relationships[ri]; score += i32(r.trust + r.respect + r.attachment + r.obligation - r.rivalry)}
		if obligation_at >= 0 &&
		   option.complies {score += 14 + i32(c.captain_obligations[obligation_at].stakes) * 3}
		tie := i32(
			captain_mix(
				c.initial_seed ~
				u64(query.captain) ~
				(u64(query.decision_context) << 24) ~
				query.source_event ~
				u64(oi),
			) %
			3,
		)
		score += tie
		if score >
		   best_score {second_score = best_score; best_score = score; best = oi; best_reasons = {Captain_Facet(top), Captain_Facet(next)}} else if score > second_score do second_score = score
	}
	if best < 0 do return {}
	result := Captain_Decision_Result {
		valid         = true,
		option_index  = best,
		score         = best_score,
		reason_facets = best_reasons,
	}
	if obligation_at >= 0 {
		o := &c.captain_obligations[obligation_at]
		if query.options[best].complies {result.obligation_status = .Complied} else if query.stakes >= 2 && c.season >= p.autonomy_cooldown_until && best_score - second_score >= 8 {result.obligation_status = .Breached; result.overt_departure = true} else {result.obligation_status = .Reinterpreted}
	}
	return result
}

captain_apply_decision :: proc(
	c: ^Campaign,
	query: Captain_Decision_Query,
	result: Captain_Decision_Result,
) -> bool {
	if !result.valid do return false
	oi := captain_active_obligation_index(c, query.captain, query.decision_context)
	if oi >= 0 &&
	   result.obligation_status !=
		   .Active {o := &c.captain_obligations[oi]; o.status = result.obligation_status; o.resolved_event = query.source_event}
	for facet in result.reason_facets do _ = captain_record_evidence(c, query.captain, facet, 1)
	if result.overt_departure {
		fi := historical_figure_index(
			c,
			query.captain,
		); if fi < 0 do return false; figure := &c.historical_figures[fi]; ship_at := ship_index(c, figure.ship); if ship_at < 0 do return false
		record_ship_autonomy(
			c,
			fmt.tprintf(
				"%s departed from a recorded order during %v operations.",
				figure.name,
				query.decision_context,
			),
			figure.ship,
			i32(query.stakes),
			query.source_event,
		)
		figure.captain_profile.last_departure_event =
			c.event_sequence; figure.captain_profile.autonomy_cooldown_until = c.season + 3
		_ = captain_add_mark(
			c,
			query.captain,
			{
				kind = .Breach,
				decision_context = query.decision_context,
				source_event = c.event_sequence,
				intensity = 2,
			},
		)
		return true
	}
	return true
}

captain_dossier :: proc(c: ^Campaign, captain: Figure_ID) -> Captain_Dossier {
	fi := historical_figure_index(
		c,
		captain,
	); if fi < 0 do return {}; f := &c.historical_figures[fi]; if !f.captain_profile.initialized do captain_profile_initialize(c, f); p := &f.captain_profile
	d := Captain_Dossier {
		valid              = true,
		name               = f.name,
		office             = f.role,
		ship               = f.ship,
		predecessor        = f.predecessor,
		primary_tendency   = captain_facet_name(p.convictions[0]),
		secondary_tendency = captain_facet_name(p.convictions[1]),
		mark_count         = p.mark_count,
		last_noted_event   = f.last_event,
	}
	d.status = f.active ? "serving" : "not serving"
	if p.facets[int(Captain_Facet.Life_Preservation)] >= 3 && p.facets[int(Captain_Facet.Risk_Tolerance)] >= 3 do d.tension = "accepts risk when lives are exposed"
	for r in c.captain_relationships[:c.captain_relationship_count] do if r.captain == captain do d.relationship_count += 1
	for o in c.captain_obligations[:c.captain_obligation_count] do if o.captain == captain && o.status == .Active do d.active_obligation_count += 1
	return d
}

captain_appointment_candidates :: proc(
	c: ^Campaign,
	ship: Ship_ID,
) -> [3]Captain_Appointment_Candidate {
	result: [3]Captain_Appointment_Candidate; si := ship_index(c, ship); if si < 0 do return result
	s := c.ships[si]
	for i in 0 ..< len(result) {
		name_at := (c.historical_figure_count + i) % len(CAPTAIN_NAMES)
		institution := captain_institution_for_role(s.role)
		mixed := captain_mix(c.initial_seed ~ u64(ship) ~ u64(i + 1) ~ (u64(c.season) << 32))
		result[i] = {
			valid       = true,
			name        = CAPTAIN_NAMES[name_at],
			community   = s.community,
			institution = institution,
			endorsement = i8(mixed % 5),
		}
	}
	return result
}

captain_resolve_accountability :: proc(
	c: ^Campaign,
	captain: Figure_ID,
	outcome: Captain_Accountability_Outcome,
	source: u64,
) -> bool {
	fi := historical_figure_index(
		c,
		captain,
	); if fi < 0 || outcome == .None || source == 0 || !event_reference_exists(c, source) do return false
	f := &c.historical_figures[fi]; detail := "The review closed without changing the captain's office."
	switch outcome {
	case .Commendation:
		detail = fmt.tprintf("%s received a recorded commendation.", f.name)
		_ = captain_set_relationship(c, captain, .Institution, u32(f.institution), 0, 1, 0, 0, 0, source)
	case .Reconciliation:
		detail = fmt.tprintf("%s and the reviewing institution recorded a reconciliation.", f.name)
		_ = captain_set_relationship(c, captain, .Institution, u32(f.institution), 1, 0, 0, 0, -1, source)
	case .Restitution:
		detail = fmt.tprintf("%s accepted a recorded obligation of restitution.", f.name)
		_ = captain_set_relationship(c, captain, .Community, u32(f.community), 0, 0, 0, 2, 0, source)
	case .Censure:
		detail = fmt.tprintf("%s received a recorded censure.", f.name)
		_ = captain_set_relationship(c, captain, .Institution, u32(f.institution), -1, -1, 0, 0, 1, source)
	case .Restricted_Authority:
		detail = fmt.tprintf("%s remained in office under restricted authority.", f.name)
		_ = captain_set_relationship(c, captain, .Institution, u32(f.institution), -1, 0, 0, 1, 1, source)
	case .Transfer:
		detail = fmt.tprintf("%s left the ship pending another appointment.", f.name); if si := ship_index(c, f.ship); si >= 0 && c.ships[si].captain == captain do c.ships[si].captain = 0
		f.active = false
		f.role = "captain awaiting transfer"
	case .Dismissal:
		detail = fmt.tprintf("%s was dismissed from the captaincy.", f.name); if si := ship_index(c, f.ship); si >= 0 && c.ships[si].captain == captain do c.ships[si].captain = 0
		f.active = false
		f.role = "dismissed captain"
	case .Resignation:
		detail = fmt.tprintf("%s resigned the captaincy.", f.name); if si := ship_index(c, f.ship); si >= 0 && c.ships[si].captain == captain do c.ships[si].captain = 0
		f.active = false
		f.role = "former captain"
	case .Political_Realignment:
		detail = fmt.tprintf("%s entered a new institutional alignment after review.", f.name)
		_ = captain_set_relationship(c, captain, .Institution, u32(f.institution), -1, 0, 0, 0, 2, source)
	case .None:
	}
	record_event(
		c,
		.Historical_Figure_Changed,
		detail,
		f.ship,
		i32(outcome),
		f.community,
		source,
		captain,
		institution_id = f.institution,
	)
	f.last_event = c.event_sequence
	for &o in c.captain_obligations[:c.captain_obligation_count] do if o.captain == captain && (o.status == .Breached || o.status == .Refused || o.status == .Reinterpreted) {o.status = .Accounted; o.resolved_event = c.event_sequence}
	if outcome == .Censure || outcome == .Dismissal || outcome == .Restricted_Authority do _ = captain_add_mark(c, captain, {kind = .Censure, decision_context = .General, source_event = c.event_sequence, intensity = 2})
	return true
}
