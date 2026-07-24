package game

import "core:fmt"
import "core:testing"

forecast_emergency_pressure :: proc(c: ^Campaign) -> Emergency_Pressure {
	r := Emergency_Pressure {
		recovery_active = c.emergency_recovery_active,
		recovery_target = c.emergency_recovery_target,
	}
	for need in c.needs {
		if !need.active || need.resolved || need.deadline > c.season + 1 do continue
		cohesion_loss: i32 = 4
		if need.kind != .Sustenance_Shortfall && need.kind != .Ship_Repair && need.kind != .Settlement_Demand do cohesion_loss += 5
		if need.response == .Mitigated do cohesion_loss = max(cohesion_loss / 2, 1)
		r.cohesion_loss += cohesion_loss
		if need.kind == .Sustenance_Shortfall do r.reserve_loss += need.response == .Mitigated ? 4 : 8
	}
	for promise in c.promises[:c.promise_count] {
		if promise.status == .Active &&
		   promise.deadline < c.season + 1 {r.expiring_promises += 1; r.cohesion_loss += 10}
	}
	for project in c.projects {
		if !project.active || project.remaining > 1 do continue
		if project.kind == .Habitat_Expansion do r.scheduled_cohesion += 5
		if project.kind == .Restore_Archive do r.scheduled_cohesion += 4
	}
	population := total_population(c)
	consumption := max(population / 5500, 4)
	agriculture: i32
	for ship in c.ships do if ship.active && ship.role == .Agriculture do agriculture += max(8 - ship.damage, 1)
	projected_sustenance := max(fleet_supply(c) - r.reserve_loss + agriculture - consumption, 0)
	if projected_sustenance == 0 do r.cohesion_loss += 8
	r.projected_cohesion = clamp(
		c.strategic.cohesion - r.cohesion_loss + r.scheduled_cohesion,
		0,
		100,
	)
	if c.emergency_recovery_active {r.structural_recovery = 2; r.projected_cohesion = min(r.projected_cohesion + 2, 100)}
	// Warning-band forecasts and season resolution share one pressure model.
	pressure := strategic_pressure(
		c,
		-r.reserve_loss + agriculture - consumption,
		r.projected_cohesion - c.strategic.cohesion,
	)
	r.critical = pressure.warning
	return r
}

publish_discovery :: proc(c: ^Campaign) -> bool {
	if c.emergency_structural_response_required || c.material_economy.knowledge.deployable_capacity < 8 do return false
	uses :=
		c.emergency_response_uses[0]; gain := max(6 - uses * 2, 1); c.emergency_response_uses[0] += 1
	_ = spend_knowledge(c, 8, .Emergency)
	c.strategic.cohesion = min(c.strategic.cohesion + gain, 100)
	c.emergency_preparedness = max(c.emergency_preparedness, 64)
	record_event(
		c,
		.Emergency_Response,
		fmt.tprintf(
			"The fleet published a discovery; Analysis capacity fell by 8 and Cohesion rose by %d. This was temporary relief use %d.",
			gain,
			uses + 1,
		),
		value = gain,
	)
	return true
}

use_contingency_reserves :: proc(c: ^Campaign) -> bool {
	if c.emergency_structural_response_required || development_reserves_available(c) < 13 do return false
	uses :=
		c.emergency_response_uses[1]; gain := max(4 - uses, 1); c.emergency_response_uses[1] += 1
	if !fleet_stock_spend(c, {supplies = 13}, .Emergency) do return false
	c.emergency_preparedness = max(c.emergency_preparedness, 64)
	c.strategic.cohesion = min(c.strategic.cohesion + gain, 100)
	record_event(
		c,
		.Emergency_Response,
		fmt.tprintf(
			"The fleet opened contingency reserves; Reserves fell by 13 and Cohesion rose by %d. This was temporary relief use %d.",
			gain,
			uses + 1,
		),
		value = gain,
	)
	return true
}

hold_community_forum :: proc(c: ^Campaign) -> bool {
	if c.emergency_structural_response_required || development_reserves_available(c) < 5 do return false
	uses :=
		c.emergency_response_uses[2]; gain := max(6 - uses * 2, 1); c.emergency_response_uses[2] += 1
	if !fleet_stock_spend(c, {supplies = 5}, .Emergency) do return false; c.strategic.cohesion = min(c.strategic.cohesion + gain, 100)
	c.emergency_preparedness = max(c.emergency_preparedness, 64)
	for i in 0 ..< c.community_count do c.communities[i].trust = min(c.communities[i].trust + 2, 100)
	record_event(
		c,
		.Emergency_Response,
		fmt.tprintf(
			"The fleet funded a public forum; Reserves fell by 5, Cohesion rose by %d, and community trust rose by 2. This was temporary relief use %d.",
			gain,
			uses + 1,
		),
		value = gain,
	)
	return true
}

queue_project :: proc(c: ^Campaign, kind: Project_Kind, ship := Ship_ID(0)) -> bool {
	preview := project_preview(c, kind, ship); if !preview.valid do return false
	cost := preview.reserve_cost; duration := preview.duration
	for i in 0 ..< MAX_PROJECTS {
		if !c.projects[i].active {
			if !campaign_can_schedule_work(c, .Project, u64(i + 1)) do return false
			if !fleet_stock_spend(c, fleet_project_cost(kind)) do return false
			c.projects[i] = {
				kind          = kind,
				ship          = ship,
				remaining     = duration,
				reserve_cost  = cost,
				active        = true,
				semantic_tags = semantic_add(
					make_semantic_tags(.Project),
					kind == .Repair ? .Repair : .Industry,
				),
			}
			campaign_clock_initialize(c)
			work_id := campaign_schedule_work(
				c,
				.Project,
				u64(i + 1),
				campaign_time_add(c.clock.now, CAMPAIGN_REPORT_SECONDS),
				5,
			)
			if work_id == 0 {
				// Capacity was checked before spending; retain a defensive
				// rollback in case scheduling invariants change.
				fleet_stock_gain(c, fleet_project_cost(kind))
				c.projects[i] = {}
				return false
			}
			return true
		}
	}
	return false
}

advance_projects :: proc(c: ^Campaign) {
	for i in 0 ..< MAX_PROJECTS {
		advance_project(c, i)
	}
}

advance_project :: proc(c: ^Campaign, i: int) {
	if i < 0 || i >= MAX_PROJECTS do return
	p := &c.projects[i]
	if !p.active do return
	p.remaining -= 1
	if p.remaining > 0 {
		if campaign_schedule_work(
			c,
			.Project,
			u64(i + 1),
			campaign_time_add(c.clock.now, CAMPAIGN_REPORT_SECONDS),
			5,
		) == 0 {
			// Keep the project eligible for an explicit retry rather than
			// completing or charging it again without a boundary.
			p.remaining += 1
		}
		return
	}
		si := ship_index(c, p.ship)
		switch p.kind {
		case .Repair:
			if si >= 0 {
				ship := &c.ships[si]
				repaired := min(ship.damage, 3)
				ship.damage = max(ship.damage - repaired, 0)
				ship_clear_impairments(ship)
				if repaired > 0 {
					detail := fmt.tprintf(
						"%s completed structural repairs; damage fell by %d.",
						ship.name,
						repaired,
					)
					add_ship_history(c, ship.id, detail)
					record_event(c, .Ship_Repaired, detail, ship.id, repaired)
				}
				detect_essential_exposure(c, c.event_sequence)
			}
		case .Refit:
			if si >= 0 do c.ships[si].power += 2
		case .Habitat_Expansion:
			c.strategic.cohesion = min(c.strategic.cohesion + 5, 100)
		case .Analyze_Discovery:
			record_knowledge_gain(c, 12, .Project)
		case .Colony_Package:
			c.colony_package_ready = true
		case .Restore_Archive:
			record_knowledge_gain(c, 6, .Archives)
			c.strategic.cohesion = min(c.strategic.cohesion + 4, 100)
		case .Produce_Reserves:
			fleet_stock_gain(c, {supplies = 18})
		case .Maintenance_Recovery:
			c.material_economy.fleet.maintenance_debt = max(
				c.material_economy.fleet.maintenance_debt - 2,
				0,
			)
		case .None:
		}
		detail: string
		switch p.kind {case .Repair:
			detail = "The assigned ship completed structural repairs."; case .Refit:
			detail = "The assigned ship completed a refit; Power rose by 2."; case .Habitat_Expansion:
			detail = "Habitat expansion completed; Cohesion rose by 5."; case .Analyze_Discovery:
			detail = "Discovery analysis completed; deployable analysis rose by 12."; case .Colony_Package:
			detail = "The fleet completed a colony package."; case .Restore_Archive:
			detail = "Archive restoration completed; deployable analysis rose by 6 and Cohesion by 4."; case .Produce_Reserves:
			detail = "Support production completed; Expedition Supplies rose by 18."; case .Maintenance_Recovery:
			detail = "Maintenance recovery completed; fleet maintenance debt fell by up to 2."; case .None:
			detail = "No project change was recorded."}
		record_event(c, .Project_Completed, detail, p.ship, i32(p.kind))
		p.active = false
}

commission_expedition :: proc(
	c: ^Campaign,
	ids: []Ship_ID,
	objective: string,
	risk: i32 = 1,
	settlement_package := false,
	target_contact: u64 = 0,
) -> bool {
	if c.expedition.active || len(ids) < 3 || len(ids) > 6 || c.material_economy.fleet.stock.supplies < i64(len(ids)) * 2 do return false
	if target_contact != 0 {
		at := habitable_contact_index(c.habitable_contacts[:], target_contact)
		if at < 0 || c.habitable_contacts[at].surveyed do return false
	}
	contract := Expedition_Contract {
		objective          = objective,
		doctrine           = "Preserve ships and return with the truth",
		risk               = clamp(risk, 0, 2),
		supplies           = i32(len(ids)) * 2,
		deadline           = c.season + 1,
		target_contact     = target_contact,
		settlement_package = settlement_package,
		active             = true,
	}
	if settlement_package && !c.colony_package_ready do return false
	for id, i in ids {
		si := ship_index(c, id)
		if si < 0 || !c.ships[si].active || c.ships[si].committed do return false
		for prior in ids[:i] do if prior == id do return false
		contract.ships[i] = id
	}
	contract.ship_count = len(ids)
	for id in ids {si := ship_index(c, id); c.ships[si].committed = true}
	if !fleet_stock_spend(c, {supplies = i64(contract.supplies)}) do return false
	c.expedition = contract
	record_event(c, .Expedition_Commissioned, objective)
	return true
}

resolve_expedition :: proc(c: ^Campaign) -> Expedition_Result {
	if !c.expedition.active do return {}
	e := &c.expedition
	power: i32
	has_survey, has_archive, has_foundry, has_escort, has_hospital, has_colony: bool
	for id in e.ships[:e.ship_count] {
		si := ship_index(c, id); ship := &c.ships[si]
		power += max(ship.power + ship.experience - ship.damage, 1)
		#partial switch ship.role {case .Survey:
			has_survey = true; case .Archive:
			has_archive = true; case .Foundry:
			has_foundry = true; case .Escort:
			has_escort = true; case .Hospital:
			has_hospital = true; case .Colony:
			has_colony = true}
	}
	pattern := "Ad hoc flotilla"
	bonus: i32
	if has_survey &&
	   has_archive &&
	   has_foundry &&
	   has_hospital {pattern = "Deep Expedition"; bonus = 18} else if has_survey && has_archive && has_foundry {pattern = "Salvage Survey"; bonus = 13} else if has_foundry && has_escort {pattern = "Convoy"; bonus = 10} else if has_survey && has_archive {pattern = "Survey Chain"; bonus = 8} else if has_hospital && has_foundry {pattern = "Relief Flotilla"; bonus = 8}
	roll := i32(rng_range(c, 21)) - 10
	score := power + bonus + roll + e.risk * 5
	result := Expedition_Result {
		pattern        = pattern,
		reserves       = max(score / 6, 2) + max(score / 7, 1),
		candidate_home = has_survey && has_archive,
		narrative      = "The expedition returns with consequences, cargo, and a new entry in the fleet chronicle.",
	}
	if score >=
	   62 {result.outcome = .Triumph} else if score >= 45 {result.outcome = .Success} else if score >= 32 {result.outcome = .Partial_Return; result.damage = 1} else if score >= 20 {result.outcome = .Disaster; result.damage = 2} else {result.outcome = .Lost; result.damage = 4}
	if has_hospital && result.outcome != .Lost do result.population = 250 + score * 5
	if result.outcome == .Lost {
		for id in e.ships[:e.ship_count] {si := ship_index(c, id); ship := &c.ships[si]; ship.active = false; ship.departure = .Lost; ship.committed = false; ship.history_count += 1; add_ship_history(c, ship.id, "Lost beyond the expedition deadline."); record_event(c, .Ship_Lost, fmt.tprintf("%s did not return before the expedition deadline.", ship.name), ship.id, ship.damage)}
		c.strategic.cohesion = max(c.strategic.cohesion - 14, 0)
		result.narrative = "No ship returned before the deadline. Signals and a rescue path remain."
	} else {
		for id in e.ships[:e.ship_count] {
			si := ship_index(
				c,
				id,
			); ship := &c.ships[si]; ship.committed = false; ship.experience += 1; ship.damage += result.damage; ship.history_count += 1
			if result.damage > 0 &&
			   ship.scar ==
				   .None {ship.scar = .Passage_Scarred; add_ship_history(c, ship.id, "Passage-scarred"); record_event(c, .Ship_Scarred, ship.name, ship.id)}
			if has_survey && ship.role == .Survey do ship.discoveries += 1
		}
		fleet_stock_gain(
			c,
			{
				supplies = i64(max(result.reserves / 2, 1)),
				raw_materials = i64(max(result.reserves / 3, 1)),
				manufactured_goods = i64(
					max(result.reserves - result.reserves / 2 - result.reserves / 3, 0),
				),
			},
		)

		record_knowledge_gain(c, max(score / 5, 2), .Expedition)
		c.strategic.cohesion = min(c.strategic.cohesion + 2, 100)
		if result.population > 0 {c.communities[3].population += result.population}
		if result.candidate_home {
			survey_seed := c.rng_sequence ~ u64(c.expedition.deadline) ~ u64(score)
			reference: Celestial_Reference
			discovered := false
			if e.target_contact != 0 {
				reference, discovered = survey_habitable_contact(
					c,
					e.target_contact,
					survey_seed,
				)
			} else {
				reference, discovered = discover_candidate_home(c, survey_seed)
			}
			if c.world_survey_count >
			   0 {c.world_surveys[c.world_survey_count - 1].survey_cost.supplies = i64(c.expedition.supplies); result.survey = c.world_surveys[c.world_survey_count - 1]}
			result.candidate_home = discovered; result.discovered_world = reference
			if discovered {result.narrative = fmt.tprintf("The expedition returned from %s in %s with a surveyed candidate at %s.", reference.system_name, reference.neighborhood_name, reference.planet_name)} else if reference.valid {result.narrative = fmt.tprintf("The expedition surveyed %s in %s. Its best-characterized world is not settlement-capable.", reference.system_name, reference.neighborhood_name)} else {result.narrative = "The expedition surveyed a reachable barren system; no planet was detected."}
		}
	}
	record_event(c, .Expedition_Returned, result.narrative, value = i32(result.outcome))
	c.expedition = {}
	return result
}

found_settlement :: proc(
	c: ^Campaign,
	community: Community_ID,
	ship: Ship_ID,
	name: string,
	generous := true,
) -> bool {
	if !c.candidate_home_known || c.candidate_home_count <= 0 || !c.colony_package_ready || c.settlement_count >= MAX_SETTLEMENTS do return false
	ci := community_index(c, community); si := ship_index(c, ship)
	if ci < 0 || si < 0 || !c.ships[si].active || !c.communities[ci].consents_to_settle do return false
	if !begin_settlement_proposal(c, name, name) do return false
	p := &c.settlement_proposal; p.procedure = .Council_Assignment; p.requested_ships[si] = true; p.requested_communities[ci] = true; p.sovereign = generous; p.continuing_jurisdiction = !generous; p.charter_participation = true
	if !open_settlement_deliberation(c) do return false
	return finalize_settlement_proposal(c)
}

advance_settlements :: proc(c: ^Campaign) {
	for i in 0 ..< c.settlement_count {
		s := &c.settlements[i]
		if !s.active || c.season < s.report_due do continue
		network_modifier: i32; for relationship in c.settlement_relationships[:c.settlement_relationship_count] {if relationship.settlement_a != s.id && relationship.settlement_b != s.id do continue; if relationship.kind == .Exchange {network_modifier += 1} else {other := relationship.settlement_a == s.id ? relationship.settlement_b : relationship.settlement_a; other_at := settlement_index(c, other); if other_at >= 0 {network_modifier += c.settlements[other_at].viability > s.viability ? 2 : -1}}}
		variance := i32(rng_range(c, 11)) - 5 + network_modifier
		s.viability = clamp(s.viability + variance, 0, 100)
		s.reported = true
		s.report_count += 1
		s.report_due = c.season + 2
		if s.viability >=
		   60 {c.strategic.cohesion = min(c.strategic.cohesion + (s.report_count == 1 ? 8 : 2), 100); record_knowledge_gain(c, s.report_count == 1 ? 3 : 1, .Settlement_Report)} else {c.strategic.cohesion = max(c.strategic.cohesion - (s.report_count == 1 ? 7 : 3), 0)}
		if s.archive_id != 0 do record_knowledge_gain(c, 1, .Archives)
		cause := s.last_report_event
		record_event(
			c,
			.Settlement_Reported,
			s.name,
			s.founder_ship,
			s.viability,
			s.founding_community,
			cause,
			settlement_id = s.id,
			archive_id = s.archive_id,
		)
		s.last_report_event = c.event_sequence
		if figure_at := figure_for_settlement(c, s.id);
		   figure_at >=
		   0 {figure := &c.historical_figures[figure_at]; figure.public_actions += 1; figure.role = "settlement delegate"; record_event(c, .Historical_Figure_Changed, fmt.tprintf("%s delivered %s's report to the traveling fleet.", figure.name, s.name), figure.ship, figure.public_actions, figure.community, s.last_report_event, figure.id, settlement_id = s.id); figure.last_event = c.event_sequence; s.last_report_event = c.event_sequence}
	}
	advance_settlement_relationships(c)
}

settlement_relationship_index :: proc(c: ^Campaign, a, b: Settlement_ID) -> int {lo := min(a, b)
	hi := max(a, b)
	for relationship, i in c.settlement_relationships[:c.settlement_relationship_count] do if relationship.settlement_a == lo && relationship.settlement_b == hi do return i
	return -1}

advance_settlement_relationships :: proc(c: ^Campaign) {
	if c.settlement_relationship_count >= MAX_SETTLEMENT_RELATIONSHIPS do return
	for a in 0 ..< c.settlement_count {if !c.settlements[a].active || !c.settlements[a].reported do continue; for b in a + 1 ..< c.settlement_count {if !c.settlements[b].active || !c.settlements[b].reported || settlement_relationship_index(c, c.settlements[a].id, c.settlements[b].id) >= 0 do continue
			kind :=
				Settlement_Relationship_Kind.Exchange; if abs(c.settlements[a].viability - c.settlements[b].viability) >= 15 do kind = .Dependency
			relationship := &c.settlement_relationships[c.settlement_relationship_count]; relationship.settlement_a = c.settlements[a].id; relationship.settlement_b = c.settlements[b].id; relationship.kind = kind; relationship.strength = 1
			detail :=
				kind == .Exchange ? fmt.tprintf("%s and %s opened a regular exchange compact.", c.settlements[a].name, c.settlements[b].name) : fmt.tprintf("%s and %s entered an unequal support dependency.", c.settlements[a].name, c.settlements[b].name)
			record_event(
				c,
				.Settlement_Relationship_Changed,
				detail,
				c.settlements[a].founder_ship,
				1,
				c.settlements[a].founding_community,
				c.settlements[a].last_report_event,
				settlement_id = c.settlements[a].id,
			)
			_ = add_event_cause(
				c,
				c.event_sequence,
				c.settlements[b].last_report_event,
				.Continuation,
			); relationship.origin_event = c.event_sequence; relationship.last_event = c.event_sequence; relationship.semantic_tags = make_semantic_tags(.Relationship, .Settlement, .Migration); if kind == .Exchange do relationship.semantic_tags = semantic_add(relationship.semantic_tags, .Industry); if kind == .Dependency do relationship.semantic_tags = semantic_add(relationship.semantic_tags, .Care, .Survival); c.settlement_relationship_count += 1; return
		}}
}

operational_role_available :: proc(c: ^Campaign, role: Role) -> bool {
	for ship in c.ships[:c.ship_count] do if ship.active && ship.role == role && ship.damage < 3 do return true
	return false
}

random_active_ship :: proc(c: ^Campaign) -> int {
	indices: [MAX_SHIPS]int
	count := 0
	for ship, index in c.ships[:c.ship_count] {
		if !ship.active do continue
		indices[count] = index
		count += 1
	}
	if count == 0 do return -1
	return indices[int(rng_range(c, u64(count)))]
}

apply_seasonal_hazard :: proc(c: ^Campaign) {
	// Major systemic beats always leave at least one clear season between them.
	// The probability check still consumes its deterministic draw only when the
	// cadence permits a hazard.
	if !major_story_beat_ready(c) do return
	threshold := i32(35)
	switch c.story_tempo {case .Spacious:
		threshold = 22; case .Volatile:
		threshold = 55; case .Measured:}
	if rng_range(c, 100) >= u64(threshold) do return
	hazard := Fleet_Hazard(rng_range(c, 4))
	c.hazard_count += 1
	contained := false
	detail := ""
	ship_id := Ship_ID(0)
	value: i32
	switch hazard {
	case .Micrometeoroid_Swarm:
		contained = operational_role_available(c, .Escort)
		if ship_at := random_active_ship(c); ship_at >= 0 {
			ship := &c.ships[ship_at]
			damage := contained ? i32(1) : i32(2)
			ship.damage = min(ship.damage + damage, max(ship.power - 1, 0))
			ship_id = ship.id
			value = damage
			detail = fmt.tprintf(
				"A micrometeoroid swarm opened %d damage aboard %s.",
				damage,
				ship.name,
			)
			add_ship_history(c, ship.id, "Struck during a fleetwide micrometeoroid swarm.")
		}
	case .Crop_Blight:
		contained = operational_role_available(c, .Agriculture)
		loss := contained ? i32(6) : i32(16)
		_ = fleet_stock_spend(c, {supplies = i64(min(loss, fleet_supply(c)))}, .Emergency)
		value = loss
		detail = fmt.tprintf("A crop blight consumed %d Reserves before the next harvest.", loss)
	case .Reactor_Cascade:
		contained = operational_role_available(c, .Foundry)
		loss := contained ? i32(1) : i32(3)
		c.capacities.raw_materials.damaged = min(
			c.capacities.raw_materials.damaged + loss,
			c.capacities.raw_materials.total,
		)
		value = loss
		for ship, ship_at in c.ships[:c.ship_count] {
			if !ship.active || ship.role != .Foundry do continue
			c.ships[ship_at].damage = min(ship.damage + 1, max(ship.power - 1, 0))
			ship_id = ship.id
			add_ship_history(c, ship.id, "Its reactor banks carried a fleetwide cascade.")
			break
		}
		detail = fmt.tprintf(
			"A reactor cascade damaged %d Raw Materials capacity and a foundry ship.",
			loss,
		)
	case .Membrane_Shear:
		contained =
			operational_role_available(c, .Survey) && operational_role_available(c, .Archive)
		cohesion_loss := contained ? i32(3) : i32(10)
		c.strategic.cohesion = max(c.strategic.cohesion - cohesion_loss, 0)
		value = cohesion_loss
		detail = fmt.tprintf(
			"Membrane shear separated the fleet's signals; Cohesion fell by %d.",
			cohesion_loss,
		)
	}
	if !contained do c.uncontained_hazard_count += 1
	if contained && c.uncontained_hazard_count > 0 {
		c.uncontained_hazard_count -= 1
		detail = fmt.tprintf(
			"%s Fleet capability also cleared one unresolved hazard obligation.",
			detail,
		)
	}
	record_event(c, .Fleet_Hazard, detail, ship_id, value)
	c.last_major_beat_season = c.season
}

hazard_pressure_cadence :: proc(c: ^Campaign) -> i32 {
	switch c.story_tempo {case .Volatile:
		return 2; case .Spacious:
		return 4; case .Measured:
		return 3}
	return 3
}

advance_persistent_hazard_pressure :: proc(c: ^Campaign) {
	if c.uncontained_hazard_count <= 0 || c.season % hazard_pressure_cadence(c) != 0 do return
	coverage: i32
	roles := [5]Role{Role.Escort, Role.Agriculture, Role.Foundry, Role.Survey, Role.Archive}
	for role in roles do if operational_role_available(c, role) do coverage += 1
	if coverage >= 3 {
		c.uncontained_hazard_count -= 1
		record_event(
			c,
			.Fleet_Hazard,
			"Fleet capability cleared one unresolved hazard obligation.",
			value = -1,
		)
		return
	}
	// Persistent hazards consume margin but do not terminate a run. Players can
	// restore or substitute essential roles before the next tempo-based review.
	loss := min(c.uncontained_hazard_count, 3)
	c.strategic.cohesion = max(c.strategic.cohesion - loss, 0)
	// This is recurring pressure from an existing hazard, not a new story root.
	// Preserve that relationship in the chronicle so tempo telemetry and later
	// callbacks can distinguish escalation from a fresh hazard.
	source := latest_event_of_kind(c, .Fleet_Hazard)
	record_event(
		c,
		.Fleet_Hazard,
		fmt.tprintf("Unresolved hazards reduced Cohesion by %d.", loss),
		value = loss,
		cause_sequence = source,
	)
}

major_story_beat_ready :: proc(c: ^Campaign) -> bool {
	minimum_gap := i32(2)
	switch c.story_tempo {case .Spacious:
		minimum_gap = 3; case .Volatile:
		minimum_gap = 1; case .Measured:}
	return c.season - c.last_major_beat_season >= minimum_gap
}

mark_major_story_beat :: proc(c: ^Campaign) {
	c.last_major_beat_season = c.season
}
