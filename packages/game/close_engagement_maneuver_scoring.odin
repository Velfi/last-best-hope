package game

combat_maneuver_utility :: proc(
	maneuver: Combat_Maneuver,
	g: Combat_Group,
	p: Combat_AI_Parameters,
	has_contact: bool,
	solution, distance, pressure, signature, masking, force_ratio, objective_progress: f32,
	fired_recently: bool,
) -> f32 {
	score: f32 = 0
	sensor_advantage := (solution - signature * .08) * p.sensor_value
	escape := clamp(g.escape_margin / 220, -1, 1) * p.escape_value
	support := clamp(g.cohesion / 100, 0, 1) * p.support_value
	travel := clamp(distance / 500, 0, 1) * p.travel_cost
	ordnance_pressure := clamp((100 - g.readiness) / 100, 0, 1) * p.readiness_value
	objective := objective_progress * p.objective_value
	mask := masking * p.masking_value
	force := force_ratio * p.force_value
	threat_pressure := pressure * p.pressure_cost
	switch g.objective_policy {
	case .Preserve_Force:
		objective *= .3
		escape += .25
	case .Complete_At_Cost:
		objective *= 2
		escape -= .2
	case .Balanced:
	}
	switch maneuver {
	case .Shadow:
		score =
			(has_contact ? .15 : .8) +
			sensor_advantage * .25 +
			objective * .35 -
			travel * .15
	case .Masked_Approach:
		score = mask * .8 + (has_contact ? .2 : .55) + objective * .45 - signature * .2
	case .Establish_Cross_Bearing:
		score =
			(has_contact ? .55 : -1) +
			(.62 - solution) * .8 +
			support * .35 +
			force * .2 -
			travel * .2
	case .Ambush:
		score =
			(has_contact ? solution * 1.2 : -1) +
			mask * .45 +
			objective * .35 +
			escape * .5 +
			force * .25 -
			ordnance_pressure * .15
		if g.attack_rhythm == .Ambush do score += .35
	case .Skirmish_Pass:
		score =
			(has_contact ? solution : .0) +
			objective * .25 +
			escape * .35 +
			force * .35 +
			g.readiness / 250 -
			threat_pressure / 180
		if g.attack_rhythm == .Repeated_Passes do score += .35
	case .Fire_And_Displace:
		score = (fired_recently ? 2.5 : -.8) + escape * .35 + mask * .25
		if g.displacement_trigger == .After_Firing do score += .35
	case .Break_Contact:
		score = threat_pressure / 70 + signature * .35 - escape * .7 + (g.strength < .55 ? .35 : 0)
		if g.displacement_trigger == .When_Pressured do score += .2
	case .Screen_Withdrawal:
		score =
			(g.objective == .Withdraw || g.objective == .Extract ? .9 : -.7) +
			threat_pressure / 120 +
			support * .3
	case .Reform:
		score = (1 - support) * 1.45 + (1 - g.strength) * .35 + (1 - g.readiness / 100) * .25
	case .Decline_Engagement:
		score = -escape * .9 - force * .45 + (has_contact ? .15 : -.2)
		if g.survival_method == .Endurance do score -= .35
	}
	switch g.survival_method {
	case .Concealment:
		if maneuver == .Masked_Approach || maneuver == .Ambush || maneuver == .Break_Contact do score += .25
	case .Mobility:
		if maneuver == .Skirmish_Pass || maneuver == .Fire_And_Displace || maneuver == .Decline_Engagement do score += .25
	case .Endurance:
		if maneuver == .Establish_Cross_Bearing || maneuver == .Reform do score += .18
	}
	aggressive :=
		maneuver == .Ambush || maneuver == .Skirmish_Pass ||
		maneuver == .Establish_Cross_Bearing
	switch g.engagement_policy {
	case .Avoid:
		score += aggressive ? -1.4 : maneuver == .Decline_Engagement ? .9 : 0
	case .Defend:
		score += aggressive && g.objective != .Guard ? -.55 : 0
	case .Seek_Battle:
		score += aggressive ? .7 : maneuver == .Decline_Engagement ? -.8 : 0
	case .Favorable:
	}
	if maneuver == .Reform {
		switch g.cohesion_policy {
		case .Tight:
			score += .75
		case .Mutual_Support:
			score += .35
		case .Independent:
			score -= .7
		case .Flexible:
		}
	}
	if aggressive {
		switch g.ordnance_policy {
		case .Conserve:
			score -= g.readiness < 75 ? .8 : .25
		case .Liberal:
			score += .35
		case .Confirmed_Priority:
		}
	}
	return score
}

combat_group_contact_trace :: proc(
	m: ^Combat_Mission,
	side: Combat_Side,
	group, index: int,
) -> ^Combat_Contact_Trace {
	if index < 0 || index >= m.unit_count || group < 0 || group >= COMBAT_GROUP_COUNT do return nil
	return &m.group_contacts[combat_side_index(side)][group][index]
}

combat_group_contact_targetable :: proc(
	m: ^Combat_Mission,
	side: Combat_Side,
	group, index: int,
) -> bool {
	trace := combat_group_contact_trace(m, side, group, index)
	public := combat_contact_trace(m, side, index)
	return(
		trace != nil &&
		(public == nil || public.assessment != .Confirmed_Disabled) &&
		trace.assessment != .Confirmed_Disabled &&
		(trace.liveness == .Fresh || trace.liveness == .Aging) &&
		trace.confidence >= .3 \
	)
}

combat_group_contact_position :: proc(
	m: ^Combat_Mission,
	side: Combat_Side,
	group, index: int,
) -> (
	Combat_Vec3,
	bool,
) {
	trace := combat_group_contact_trace(m, side, group, index)
	if trace == nil || trace.liveness == .Unknown || trace.liveness == .Lost do return {}, false
	prediction := min(trace.age, COMBAT_CONTACT_STALE_TIME)
	return {
			trace.position.x + trace.velocity.x * prediction,
			trace.position.y + trace.velocity.y * prediction,
			trace.position.z + trace.velocity.z * prediction,
		},
		true
}
