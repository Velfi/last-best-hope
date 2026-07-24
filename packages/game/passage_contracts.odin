package game

import "core:fmt"
import "core:math"
dark_available_contracts :: proc(c: ^Campaign, out: ^[MAX_NEEDS]Dark_Contract) -> int {
	if c.compact.active.status == .Planning || c.compact.active.status == .Operating {
		if c.compact.active.operation != .Passage || c.compact.active.route != .Passage {
			return 0
		}
		contract := default_passage_contract()
		apply_active_charter_to_passage_contract(c, &contract)
		out[0] = contract
		return contract.purpose == .None ? 0 : 1
	}
	return 0
}
default_passage_contract :: proc() -> Dark_Contract {return{
		purpose = .Map_Unknown_Door,
		need_index = -1,
		sponsor = 2,
		reviewer = 2,
		term = .Open_Record,
		semantic_tags = make_semantic_tags(.Rule, .Passage, .Navigation),
	}}

// Choose a small, deterministic expedition that covers every role named by
// the contract. Within a role, prefer the least-damaged available ship; after
// required coverage, add distinct capabilities before duplicating a role.
recommend_passage_ships :: proc(
	c: ^Campaign,
	contract: ^Dark_Contract,
	out: ^[MAX_EXPEDITION_SHIPS]int,
) -> int {
	count := 0
	required_count := 0
	chosen: [MAX_SHIPS]bool
	roles := i32(0)
	for role in Role {
		role_bit := i32(1) << u32(role)
		if contract.required_roles & role_bit == 0 do continue
		required_count += 1
		best := -1
		for ship, i in c.ships[:c.ship_count] {
			if !ship.active ||
			   !compact_operation_ship_available(c, ship.id) ||
			   contract.undertaking_id != 0 &&
				   contract.protected_roles[int(ship.role)] &&
				   !contract.breach_authorized ||
			   ship.role != role {continue}
			if best < 0 || ship.damage < c.ships[best].damage do best = i
		}
		if best >= 0 && count < MAX_EXPEDITION_SHIPS {
			out[count] = best; count += 1; chosen[best] = true; roles |= role_bit
		}
	}
	for pass in 0 ..< 2 {
		prefer_distinct := pass == 0
		for ship, i in c.ships[:c.ship_count] {
			if count >= max(2, min(MAX_EXPEDITION_SHIPS, required_count)) do return count
			role_bit := i32(1) << u32(ship.role)
			if chosen[i] ||
			   !ship.active ||
			   !compact_operation_ship_available(c, ship.id) ||
			   contract.undertaking_id != 0 &&
				   contract.protected_roles[int(ship.role)] &&
				   !contract.breach_authorized ||
			   prefer_distinct && roles & role_bit != 0 {continue}
			out[count] = i; count += 1; chosen[i] = true; roles |= role_bit
		}
	}
	return count
}
apply_active_charter_to_passage_contract :: proc(c: ^Campaign, contract: ^Dark_Contract) -> bool {
	u := &c.compact.active
	if u.status != .Planning && u.status != .Operating ||
	   u.operation != .Passage ||
	   u.route != .Passage ||
	   !u.charter.valid {
		return false
	}
	contract^ = default_passage_contract()
	contract.need_index = -1
	contract.undertaking_id = u.id
	contract.scenario = u.charter.undertaking_intent.objective
	contract.purpose = operation_objective_purpose(contract.scenario)
	contract.reviewer = u.charter.hard_authority.reviewer
	contract.disclosure = u.charter.doctrine.disclosure
	contract.rescue = u.charter.doctrine.rescue
	contract.withdrawal = u.charter.doctrine.withdrawal
	contract.protected_roles = u.charter.hard_authority.protected_roles
	roles := i32(0)
	for required, role in u.charter.hard_authority.required_roles do if required do roles |= 1 << u32(role)
	contract.required_roles = roles
	contract.operation_authority = u.charter.hard_authority
	return true
}

apply_operation_authority_to_passage_contract :: proc(
	contract: ^Dark_Contract,
	authority: Operation_Authority,
) -> bool {
	if contract == nil ||
	   !authority.valid ||
	   operation_objective_kind(authority.objective) != .Passage {
		return false
	}
	contract.undertaking_id = Compact_Undertaking_ID(authority.undertaking_id)
	contract.scenario = authority.objective
	contract.purpose = operation_objective_purpose(authority.objective)
	contract.reviewer = authority.reviewer
	contract.disclosure = authority.disclosure
	contract.rescue = authority.rescue
	contract.withdrawal = authority.withdrawal
	contract.protected_roles = authority.protected_roles
	roles := i32(0)
	for required, role in authority.required_roles do if required do roles |= 1 << u32(role)
	contract.required_roles = roles
	contract.operation_authority = authority
	return true
}

dark_strategy_record_index :: proc(
	c: ^Campaign,
	sponsor: Institution_ID,
	purpose: Dark_Contract_Purpose,
	strategy: Dark_Strategy_Profile,
) -> int {for r, i in c.dark_strategy_records[:c.dark_strategy_record_count] do if r.sponsor == sponsor && r.purpose == purpose && dark_strategy_equal(r.strategy, strategy) do return i
	return -1}
dark_strategy_record_ensure :: proc(
	c: ^Campaign,
	sponsor: Institution_ID,
	purpose: Dark_Contract_Purpose,
	strategy: Dark_Strategy_Profile,
) -> int {
	at := dark_strategy_record_index(c, sponsor, purpose, strategy)
	if at >= 0 do return at
	at = c.dark_strategy_record_count
	append(
		&c.dark_strategy_records,
		Dark_Strategy_Statistics{sponsor = sponsor, purpose = purpose, strategy = strategy},
	)
	c.dark_strategy_record_count += 1
	return at
}
dark_strategy_estimate :: proc(r: ^Dark_Strategy_Statistics) -> Dark_Strategy_Estimate {if r == nil do return {objective_rate = .5, safety_rate = .5, record_rate = .5}
	n := f64(r.resolved)
	e := Dark_Strategy_Estimate {
		evidence       = r.resolved,
		objective_rate = (f64(r.objective_successes) + 1) / (n + 2),
		safety_rate    = (f64(r.safe_conclusions) + 1) / (n + 2),
		record_rate    = (f64(r.records_recovered) + 1) / (n + 2),
		confidence     = n / (n + 4),
	}
	if r.resolved > 0 {e.mean_damage = f64(r.total_damage) / n; e.mean_days =
			r.total_elapsed_days / n}
	return e}
dark_profile_depth_band :: proc(s: Dark_Strategy_Profile) -> int {return int(s.depth)}
dark_environment_band_at_anchor :: proc(c: ^Campaign) -> int {_, weather := dark_environment_at(
		&c.outer_dark.continuum,
		c.outer_dark.continuum.anchor_position,
	)
	return weather < .34 ? 0 : weather < .67 ? 1 : 2}
dark_strategy_environment_estimate :: proc(
	r: ^Dark_Strategy_Statistics,
	depth_band, environment_band: int,
) -> Dark_Strategy_Estimate {
	cell :=
		clamp(depth_band, 0, 2) * 3 +
		clamp(environment_band, 0, 2); resolved := r.band_resolved[cell]; n := f64(resolved)
	e := Dark_Strategy_Estimate {
		evidence       = resolved,
		objective_rate = (f64(r.band_objective_successes[cell]) + 1) / (n + 2),
		safety_rate    = (f64(r.band_safe_conclusions[cell]) + 1) / (n + 2),
		record_rate    = (f64(r.band_records_recovered[cell]) + 1) / (n + 2),
		confidence     = n / (n + 4),
	}
	if resolved >
	   0 {e.mean_damage = r.band_damage[cell] / n; e.mean_days = r.band_elapsed_days[cell] / n}
	return e
}
dark_strategy_estimate_for :: proc(
	c: ^Campaign,
	sponsor: Institution_ID,
	purpose: Dark_Contract_Purpose,
	strategy: Dark_Strategy_Profile,
) -> Dark_Strategy_Estimate {
	at := dark_strategy_record_index(c, sponsor, purpose, strategy)
	return(
		at >= 0 ? dark_strategy_environment_estimate(&c.dark_strategy_records[at], dark_profile_depth_band(strategy), dark_environment_band_at_anchor(c)) : Dark_Strategy_Estimate{objective_rate = .5, safety_rate = .5, record_rate = .5} \
	)
}
dark_strategy_score :: proc(
	i: ^Institution,
	term: Operation_Conduct,
	e: Dark_Strategy_Estimate,
) -> f64 {ow, sw, rw := .42, .38, .20; if i != nil && i.rescue_policy == .Absolute_Duty {ow = .22
		sw = .60
		rw = .18}
	if i != nil && i.disclosure_policy == .Open {ow = .34; sw = .28; rw = .38}
	switch term {case .Preserve_Lives:
		ow -= .14; sw += .22; rw -= .08; case .Open_Record:
		ow -= .14; sw -= .1; rw += .24; case .Mission_First:
		ow += .24; sw -= .16; rw -= .08; case .None:}
	return e.objective_rate * ow + e.safety_rate * sw + e.record_rate * rw - e.mean_damage * .002}
dark_policy_strategy :: proc(policy: Dark_Expedition_Policy) -> Dark_Strategy_Profile {
	route :=
		policy.route == .Fast ? Dark_Strategy_Profile{.Deep, .Shortest_Metric, .Balanced, .Relay_First, .Balanced} : policy.route == .Informed ? Dark_Strategy_Profile{.Balanced, .Best_Mapped, .Balanced, .Relay_First, .Balanced} : Dark_Strategy_Profile{.Shallow, .Lowest_Coherence, .Balanced, .Relay_First, .Balanced}
	switch policy.contact {
	case .Avoid:
		route.ecology = .Avoidant
	case .Observe:
		route.ecology = .Balanced
	case .Tolerate:
		route.ecology = .Contact_Tolerant
	}
	switch policy.return_policy {
	case .Fleet_First:
		route.relay, route.withdrawal = .Relay_First, .Conservative
	case .Balanced_Return:
		route.relay, route.withdrawal = .Objective_First, .Balanced
	case .Objective_First_Return:
		route.relay, route.withdrawal = .Objective_First, .Mission_First
	}
	return route
}

dark_policy_at :: proc(index: int) -> (Dark_Expedition_Policy, bool) {
	if index < 0 || index >= DARK_STRATEGY_PROFILE_COUNT do return {}, false
	n := index
	return {
			route = Dark_Route_Policy(n / 9),
			contact = Dark_Contact_Policy((n / 3) % 3),
			return_policy = Dark_Return_Policy(n % 3),
		},
		true
}

dark_policy_index :: proc(policy: Dark_Expedition_Policy) -> int {
	return int(policy.route) * 9 + int(policy.contact) * 3 + int(policy.return_policy)
}

dark_policy_for_strategy :: proc(
	strategy: Dark_Strategy_Profile,
) -> (
	Dark_Expedition_Policy,
	bool,
) {
	for index in 0 ..< DARK_STRATEGY_PROFILE_COUNT {
		policy, _ := dark_policy_at(index)
		if dark_strategy_equal(dark_policy_strategy(policy), strategy) do return policy, true
	}
	return {}, false
}

dark_candidate_strategy :: proc(n: int, term: Operation_Conduct) -> Dark_Strategy_Profile {
	policy, ok := dark_policy_at(n)
	if !ok do return dark_default_strategy(term)
	return dark_policy_strategy(policy)
}
dark_strategy_profile_at :: proc(index: int) -> (Dark_Strategy_Profile, bool) {
	policy, ok := dark_policy_at(index)
	if !ok do return {}, false
	return dark_policy_strategy(policy), true
}
dark_strategy_profile_index :: proc(strategy: Dark_Strategy_Profile) -> int {
	policy, ok := dark_policy_for_strategy(strategy)
	if !ok do return -1
	return dark_policy_index(policy)
}
dark_strategy_safety_floor :: proc(i: ^Institution) -> f64 {
	if i != nil && i.rescue_policy == .Absolute_Duty do return .5
	return .35
}
recommend_dark_strategy :: proc(
	c: ^Campaign,
	contract: ^Dark_Contract,
) -> Dark_Strategy_Recommendation {best := Dark_Strategy_Recommendation {
		score = -1,
	}; inst: ^Institution =
		nil; if at := institution_index(c, contract.sponsor); at >= 0 do inst = &c.institutions[at]; minimum := dark_strategy_safety_floor(inst); environment_band := dark_environment_band_at_anchor(c); for n in 0 ..< DARK_STRATEGY_PROFILE_COUNT {s, _ := dark_strategy_profile_at(n); at := dark_strategy_record_index(c, contract.sponsor, contract.purpose, s); e := at >= 0 ? dark_strategy_environment_estimate(&c.dark_strategy_records[at], dark_profile_depth_band(s), environment_band) : Dark_Strategy_Estimate{objective_rate = .5, safety_rate = .5, record_rate = .5}; if e.safety_rate < minimum do continue; score := dark_strategy_score(inst, contract.term, e); tie_seed := c.initial_seed ~ u64(u32(contract.sponsor) * 31 + u32(n) * 17); bonus := .08 * (1 - e.confidence) * f64(tie_seed % 11) / 10; score += bonus; if score > best.score do best = {
			strategy    = s,
			estimate    = e,
			score       = score,
			exploratory = bonus > 0 && e.evidence < 3,
		}}; best.policy, _ = dark_policy_for_strategy(best.strategy); best.reason = fmt.tprintf("%d resolved voyages; objective %.0f%%, safe %.0f%%, record %.0f%%.", best.estimate.evidence, best.estimate.objective_rate * 100, best.estimate.safety_rate * 100, best.estimate.record_rate * 100); return best}

compare_dark_strategy :: proc(
	c: ^Campaign,
	contract: ^Dark_Contract,
	selected: Dark_Strategy_Profile,
) -> Dark_Strategy_Comparison {
	recommendation := recommend_dark_strategy(c, contract)
	r := Dark_Strategy_Comparison {
		selected             = selected,
		recommended          = recommendation.strategy,
		selected_estimate    = dark_strategy_estimate_for(
			c,
			contract.sponsor,
			contract.purpose,
			selected,
		),
		recommended_estimate = recommendation.estimate,
	}
	if selected.depth != r.recommended.depth do r.difference_count += 1
	if selected.course != r.recommended.course do r.difference_count += 1
	if selected.ecology != r.recommended.ecology do r.difference_count += 1
	if selected.relay != r.recommended.relay do r.difference_count += 1
	if selected.withdrawal != r.recommended.withdrawal do r.difference_count += 1
	if r.selected_estimate.evidence == 0 do r.failure_mode = "No resolved voyages support this profile."
	else if r.selected_estimate.safety_rate < r.selected_estimate.objective_rate do r.failure_mode = "Known results favor objectives over safe conclusions."
	else if r.selected_estimate.record_rate < r.selected_estimate.safety_rate do r.failure_mode = "Record recovery is the weakest observed dimension."
	else if r.selected_estimate.mean_damage > 1 do r.failure_mode = "Successful use has carried material damage."
	else do r.failure_mode = "No dominant failure mode is established."
	return r
}

validate_contract :: proc(
	c: ^Campaign,
	contract: ^Dark_Contract,
	ships: []int,
) -> (
	bool,
	string,
) {if c.passage.active do return false, "A Dark expedition is already active."
	if contract.purpose == .None do return false, "The contract has no Dark purpose."
	if len(ships) < 1 || len(ships) > MAX_EXPEDITION_SHIPS do return false, "Select between one and seven ships."
	seen: [MAX_SHIPS]bool
	roles := i32(0)
	for index in ships {if index < 0 || index >= c.ship_count || seen[index] || !c.ships[index].active || !compact_operation_ship_available(c, c.ships[index].id) do return false, "Only available ships seconded to this undertaking may deploy."
		seen[index] = true
		ship := &c.ships[index]
		roles |= 1 << u32(ship.role)
		if contract.undertaking_id != 0 && contract.protected_roles[int(ship.role)] && !contract.breach_authorized do return false, "A protected ship role requires explicit authority before exposure."}
	if contract.required_roles & roles != contract.required_roles do return false, "The selected ships do not provide every capability required by the operation charter."
	return true, "Contract ready."}

begin_passage :: proc(
	c: ^Campaign,
	contract: Dark_Contract,
	ship_indices: []int,
	out: ^Passage,
) -> (
	bool,
	string,
) {contract_copy := contract
	if contract_copy.purpose == .Ecological_Survey && contract_copy.required_ecology_roles == 0 do contract_copy.required_ecology_roles = (1 << 5) - 1
	if contract_copy.purpose == .Infrastructure_Run && contract_copy.resource_threshold <= 0 do contract_copy.resource_threshold = .58
	ok, msg := validate_contract(c, &contract_copy, ship_indices)
	if !ok do return false, msg
	if contract_copy.undertaking_id == 0 && !contract_copy.standalone do return false, "Campaign Passage requires an active Compact undertaking."
	manifest_propellant := i64(
		max(c.compact.active.reserved.propellant, i32(max(len(ship_indices) * 2, 4))),
	)
	if contract_copy.breach_authorized {
		record_event(
			c,
			.Situation_Response,
			"The operation explicitly exposed a protected role beyond its stated authority.",
			cause_sequence = c.compact.active.accepted_event,
		)
	}
	c.compact.active.status = .Operating
	rec := recommend_dark_strategy(c, &contract_copy)
	if out.local_habitable_contacts != nil {
		delete(out.local_habitable_contacts)
		out.local_habitable_contacts = nil
	}
	p := Passage {
		active = true,
		id = next_random(c),
		phase = .Awaiting_Leg,
		domain = .Dark,
		contract = contract_copy,
		policy = rec.policy,
		recommended_policy = rec.policy,
		strategy = rec.strategy,
		recommended_strategy = rec.strategy,
		safe_endpoint = .Fleet,
		semantic_tags = make_semantic_tags(.Entity, .Passage, .Navigation),
		departure_door_id = c.outer_dark.continuum.anchor_door_id,
		departure_door_position_name_hash = dark_door_position_name_hash(
			c.outer_dark.continuum.anchor_position,
		),
		departure_neighborhood = c.outer_dark.continuum.anchor_neighborhood,
		field_depth_rating = STANDARD_FIELD_DEPTH_RATING,
		emergency_depth_limit = EMERGENCY_FIELD_DEPTH_LIMIT,
		manifest = {allocated = {propellant = manifest_propellant}},
	}
	p.local_habitable_contacts = make(
		[dynamic]Habitable_World_Contact,
		0,
		0,
		campaign_storage_allocator(),
	)
	p.dark_navigation.speed = .7
	p.dark_navigation.position = c.outer_dark.continuum.anchor_position
	// Standalone deep exploration has no Compact reservation to draw from. Give
	// it enough propellant to reach the first detectable correspondence, return,
	// and continue the automatic search instead of starting at its reserve.
	if contract_copy.standalone {
		if door_at := dark_nearest_unknown_door(&c.outer_dark.continuum, p.dark_navigation.position); door_at >= 0 {
			outbound := dark_metric_distance(
				c.outer_dark.continuum.seed,
				p.dark_navigation.position,
				c.outer_dark.continuum.doors[door_at].position,
			)
			p.manifest.allocated.propellant = max(
				p.manifest.allocated.propellant,
				i64(math.ceil(outbound * 4 + 1)),
			)
		}
	}
	p.dark_navigation.sensor_posture = .Passive
	_ = dark_mark_door_known(&c.outer_dark.continuum, c.outer_dark.continuum.anchor_door_id)
	for index, i in ship_indices {p.ships[i] = c.ships[index].id; p.ship_count += 1
		p.initial_total_damage += c.ships[index].damage
		c.ships[index].committed = true}
	fleet_propellant_sync_ledger(c)
	mobility_impairment: i32
	for ship_id in p.ships[:p.ship_count] do if at := ship_index(c, ship_id); at >= 0 do mobility_impairment += c.ships[at].impairments.mobility
	p.dark_navigation.speed = max(
		.7 - f64(mobility_impairment) / f64(max(p.ship_count, 1)) * .08,
		.35,
	)
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The %s sponsored a Dark voyage to %v.",
			institution_name(c, contract_copy.sponsor),
			contract_copy.purpose,
		),
		p.ships[0],
		institution_id = contract_copy.sponsor,
	)
	p.departure_event = c.event_sequence
	{
		record := Dark_Voyage_Record {
			id              = p.id,
			sponsor         = contract_copy.sponsor,
			purpose         = contract_copy.purpose,
			term            = contract_copy.term,
			strategy        = p.strategy,
			ships           = p.ships,
		ship_count      = p.ship_count,
		emergency_depth_committed = p.emergency_depth_committed,
			departure_event = p.departure_event,
		}
		append(&c.dark_unresolved_voyages, record)
		c.dark_unresolved_voyage_count += 1
		if at := dark_strategy_record_ensure(c, contract_copy.sponsor, contract_copy.purpose, p.strategy); at >= 0 do c.dark_strategy_records[at].attempted += 1
	}
	c.outer_dark.continuum.paused = false
	out^ = p
	return true, "The expedition entered the Dark and awaits a course."}

set_dark_sensor_posture :: proc(
	c: ^Campaign,
	p: ^Passage,
	posture: Dark_Sensor_Posture,
) -> (
	bool,
	string,
) {
	if !p.active || p.domain != .Dark do return false, "No active Dark expedition can change sensor posture."
	if p.dark_navigation.sensor_posture == posture do return false, "That sensor posture is already in force."
	prior := p.dark_navigation.sensor_posture
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The expedition changed sensor posture from %s to %s.",
			dark_sensor_posture_name(prior),
			dark_sensor_posture_name(posture),
		),
		p.ships[0],
		institution_id = p.contract.sponsor,
		cause_sequence = p.dark_navigation.sensor_posture_event,
	)
	p.dark_navigation.sensor_posture = posture
	p.dark_navigation.sensor_posture_event = c.event_sequence
	p.dark_navigation.sensor_emission = dark_sensor_profile(posture).emission
	if posture == .Active_Sweep ||
	   posture == .Illuminate ||
	   prior == .Active_Sweep ||
	   prior == .Illuminate {
		for ship_id in p.ships[:p.ship_count] do add_ship_history(c, ship_id, fmt.tprintf("Adopted %s sensors during voyage %d.", dark_sensor_posture_name(posture), p.id))
	}
	return true, fmt.tprintf(
		"%s sensor posture is now in force.",
		dark_sensor_posture_name(posture),
	)
}

set_dark_strategy :: proc(
	c: ^Campaign,
	p: ^Passage,
	s: Dark_Strategy_Profile,
) -> (
	bool,
	string,
) {if !p.active || p.phase != .Awaiting_Leg do return false, "Strategy can change only while selecting a leg."
	prior := p.strategy
	if !dark_strategy_equal(prior, s) {
		if at := dark_strategy_record_index(c, p.contract.sponsor, p.contract.purpose, prior); at >= 0 do c.dark_strategy_records[at].attempted = max(c.dark_strategy_records[at].attempted - 1, 0)
		if at := dark_strategy_record_ensure(c, p.contract.sponsor, p.contract.purpose, s); at >= 0 do c.dark_strategy_records[at].attempted += 1
		for &v in c.dark_unresolved_voyages[:c.dark_unresolved_voyage_count] do if v.id == p.id && !v.resolved {v.strategy = s; break}
		record_event(
			c,
			.Situation_Decided,
			fmt.tprintf(
				"The expedition changed its Dark strategy from %v/%v/%v to %v/%v/%v.",
				prior.depth,
				prior.course,
				prior.withdrawal,
				s.depth,
				s.course,
				s.withdrawal,
			),
			p.ships[0],
			institution_id = p.contract.sponsor,
		)
	}
	p.strategy = s
	if policy, ok := dark_policy_for_strategy(s); ok do p.policy = policy
	p.recommendation_overridden = !dark_strategy_equal(s, p.recommended_strategy)
	if p.recommendation_overridden {if at := institution_index(c, p.contract.sponsor);
		   at >= 0 && c.institutions[at].authority_policy == .Central_Command {c.institutions[at].legitimacy =
				max(c.institutions[at].legitimacy - 1, 0)
			record_ship_autonomy(
				c,
				"The expedition rejected its sponsor's recommended Dark strategy.",
				p.ships[0],
				1,
				institution_id = p.contract.sponsor,
			)
			if si := ship_index(c, p.ships[0]); si >= 0 && c.ships[si].captain != 0 {captain :=
					c.ships[si].captain
				_ = captain_record_evidence(c, captain, .Personal_Autonomy, 1)
				_ = captain_set_relationship(
					c,
					captain,
					.Institution,
					u32(p.contract.sponsor),
					-1,
					0,
					0,
					0,
					1,
					c.event_sequence,
				)}
		}}
	return true, "Expedition strategy recorded."}

set_dark_policy :: proc(
	c: ^Campaign,
	p: ^Passage,
	policy: Dark_Expedition_Policy,
) -> (
	bool,
	string,
) {
	if !p.active || p.phase != .Awaiting_Leg do return false, "Policy can change only while selecting a leg."
	prior := p.policy
	if prior == policy do return false, "That expedition policy is already in force."
	ok, message := set_dark_strategy(c, p, dark_policy_strategy(policy))
	if ok do p.policy = policy
	return ok, message
}
