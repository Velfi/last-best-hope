package game

import "core:fmt"
import "core:math"
plot_normal_course :: proc(c: ^Campaign, p: ^Passage, destination: int, v: f64 = .18) -> bool {
	_ = c
	_ = p
	_ = destination
	_ = v
	// Interstellar motion belongs to mapped Outer Dark correspondences. Local
	// normal-space transfers are planned by Fleet_Navigation against system
	// ephemerides; Passage may no longer synthesize direct relativistic legs.
	return false
}
galaxy_neighborhood_distance :: proc(c: ^Campaign, a, b: int) -> (f64, bool) {
	g := c.galaxy
	if a < 0 || b < 0 || a >= g.neighborhood_count || b >= g.neighborhood_count do return 0, false
	x := g.neighborhoods[a]
	y := g.neighborhoods[b]
	dx, dy, dz := x.x_kpc - y.x_kpc, x.y_kpc - y.y_kpc, x.z_kpc - y.z_kpc
	return math.sqrt(dx * dx + dy * dy + dz * dz), true
}
plot_normal_course_to_fleet :: proc(c: ^Campaign, p: ^Passage, v: f64 = .18) -> bool {
	if c.outer_dark.continuum.anchor_door_id == 0 do return false
	destination := c.outer_dark.continuum.anchor_neighborhood
	return plot_normal_course(c, p, destination, v)
}
passage_dark_return_available :: proc(c: ^Campaign, p: ^Passage, door_id: u64 = 0) -> bool {
	if !p.active || p.domain != .Normal_Space || p.phase == .Underway do return false
	_ = dark_ensure_correspondence_loaded(
		&c.outer_dark.continuum,
		door_id,
		p.normal_course.start_neighborhood,
	)
	for door in c.outer_dark.continuum.doors[:c.outer_dark.continuum.door_count] {
		if door_id != 0 && door.id != door_id do continue
		if door.galaxy_neighborhood != p.normal_course.start_neighborhood || door.access <= 0 do continue
		known := dark_fleet_door_known(c, door.id)
		if !known {for discovery in p.local_atlas[:p.local_atlas_count] do if discovery.door_id == door.id {known = true; break}}
		if known do return true
	}
	return false
}

enter_passage_dark :: proc(c: ^Campaign, p: ^Passage, door_id: u64 = 0) -> (bool, string) {
	if !passage_dark_return_available(c, p, door_id) do return false, "No accessible mapped Dark correspondence reaches this galaxy neighborhood."
	for &door in c.outer_dark.continuum.doors[:c.outer_dark.continuum.door_count] {
		if door_id != 0 && door.id != door_id do continue
		if door.galaxy_neighborhood != p.normal_course.start_neighborhood || door.access <= 0 do continue
		known := dark_fleet_door_known(c, door.id)
		if !known {for discovery in p.local_atlas[:p.local_atlas_count] do if discovery.door_id == door.id {known = true; break}}
		if !known do continue
		p.domain = .Dark
		p.dark_navigation.position = door.position
		p.phase = .Awaiting_Leg
		p.pause_reason = .Course_Arrival
		depth := dark_depth_from_anchor(c.outer_dark.continuum.seed, c.outer_dark.continuum.anchor_position, p.dark_navigation.position)
		if p.emergency_target_door_id != 0 && depth <= passage_field_depth_rating(p) do p.emergency_target_door_id = 0
		p.pending_door_id = door.id
		return true, "The expedition entered the mapped Dark correspondence."
	}
	return false, "No accessible mapped Dark correspondence reaches this galaxy neighborhood."
}

// Crossing resolves the endpoint and removes this door from the unknown search.
// Re-enter through the newly mapped correspondence before selecting the next leg.
continue_systematic_dark_search :: proc(c: ^Campaign, p: ^Passage) -> bool {
	if !p.systematic_search_active do return false
	p.systematic_search_active = false
	crossed, _ := cross_passage_door(c, p)
	if !crossed || p.contract.objective_met do return false
	entered, _ := enter_passage_dark(c, p, p.pending_door_id)
	if !entered do return false
	continued, _ := order_systematic_dark_search(c, p)
	return continued
}

dark_expedition_ship_offset :: proc(id: Ship_ID) -> Dark_Vec4 {
	state := u64(id) ~ 0x736869702d3464
	return {
		planet_random_range(&state, -.32, .32),
		planet_random_range(&state, -.32, .32),
		planet_random_range(&state, -.22, .22),
		planet_random_range(&state, -.18, .18),
	}
}

resolve_dark_ship_contacts :: proc(c: ^Campaign, p: ^Passage, before, after: Dark_Vec4) -> bool {
	dangerous := false
	for &organism in c.outer_dark.continuum.organisms[:c.outer_dark.continuum.organism_count] {
		if !organism.alive do continue
		if organism.attached_ship != 0 {
			organism.position = dark_vec4_add(
				after,
				dark_expedition_ship_offset(organism.attached_ship),
			)
			organism.chunk = dark_chunk_coord_at(organism.position)
			continue
		}
		for ship_id in p.ships[:p.ship_count] {
			ship_at := ship_index(c, ship_id)
			if ship_at < 0 || !c.ships[ship_at].active do continue
			offset := dark_expedition_ship_offset(ship_id)
			ship_before := dark_vec4_add(before, offset)
			ship_after := dark_vec4_add(after, offset)
			ship_radius := .42 + f64(c.ships[ship_at].power) * .025
			organism_before := dark_vec4_sub(
				organism.position,
				dark_vec4_scale(organism.velocity, DARK_FIXED_STEP),
			)
			if !sdf_swept_hyperspheres_contact(ship_before, ship_after, ship_radius, organism_before, organism.position, organism.radius) do continue
			switch organism.role {
			case .Hush_Colony:
				organism.attached_ship = ship_id
				organism.target_id = u64(ship_id)
				organism.behavior = .Colonizing
				c.ships[ship_at].dark_symbiont_id = organism.id
				c.ships[ship_at].dark_contact_procedure = .Field_Quarantine
				record_event(
					c,
					.Ship_Bond_Changed,
					fmt.tprintf(
						"A Hush colony attached to %s during a four-dimensional contact.",
						c.ships[ship_at].name,
					),
					ship_id,
					institution_id = p.contract.sponsor,
				)
			case .Shear_Hunter:
				dangerous = true
				contact_interval :=
					c.ships[ship_at].dark_contact_procedure == .Shear_Evasion ? u64(20) : u64(10)
				if c.outer_dark.continuum.simulation_tick >=
				   organism.last_contact_tick + contact_interval {
					organism.last_contact_tick = c.outer_dark.continuum.simulation_tick
					c.ships[ship_at].damage = min(
						c.ships[ship_at].damage + 1,
						max(c.ships[ship_at].power - 1, 0),
					)
					c.ships[ship_at].dark_contact_procedure = .Shear_Evasion
					c.ships[ship_at].dark_field_scars = min(
						c.ships[ship_at].dark_field_scars + 1,
						12,
					)
					organism.energy = clamp(organism.energy + .04, 0, 1)
					record_event(
						c,
						.Ship_Scarred,
						fmt.tprintf(
							"%s was struck by a Shear hunter approaching through the fourth axis.",
							c.ships[ship_at].name,
						),
						ship_id,
						institution_id = p.contract.sponsor,
					)
				}
			case .Wake_Film, .Lantern_Grazer, .Grave_Reef:
				dangerous = organism.role == .Grave_Reef
			}
			break
		}
	}
	return dangerous
}

advance_passage_dark_fixed :: proc(c: ^Campaign, p: ^Passage) {
	d := &c.outer_dark.continuum
	before := p.dark_navigation.position
	objective_before := p.contract.objective_met
	advance_dark_continuum_fixed(d)
	advance_dark_navigation_fixed(d, &p.dark_navigation)
	sensor_profile := dark_sensor_profile(p.dark_navigation.sensor_posture)
	emission_change := dark_apply_sensor_emission(
		d,
		p.dark_navigation.position,
		sensor_profile.emission,
	)
	dark_deposit_wake(
		d,
		before,
		p.dark_navigation.position,
		clamp(DARK_FIXED_STEP * f64(p.ship_count) * .025 * sensor_profile.wake_scale, 0, .2),
	)
	depth := dark_depth_from_anchor(d.seed, d.anchor_position, p.dark_navigation.position)
	ship_days := DARK_FIXED_STEP * .72
	p.elapsed_days += ship_days
	p.membrane_elapsed_days += dark_membrane_days_for_step(depth, ship_days)
	p.accumulated_depth += depth * ship_days
	contact_danger := resolve_dark_ship_contacts(c, p, before, p.dark_navigation.position)
	distance := dark_metric_distance(d.seed, before, p.dark_navigation.position)
	p.course_cost += distance
	local_law, local_weather := dark_environment_at(d, p.dark_navigation.position)
	p.environment_exposure += local_weather * DARK_FIXED_STEP
	field_scars, symbionts := i32(0), i32(0)
	for ship_id in p.ships[:p.ship_count] do if ship_at := ship_index(c, ship_id); ship_at >= 0 {field_scars += c.ships[ship_at].dark_field_scars; if c.ships[ship_at].dark_symbiont_id != 0 do symbionts += 1}
	ship_count := f64(max(p.ship_count, 1))
	p.coherence_exposure +=
		(depth * .012 +
			local_law * .018 +
			f64(field_scars) / ship_count * .0015 +
			f64(symbionts) / ship_count * .002 +
			sensor_profile.coherence_rate) *
		DARK_FIXED_STEP
	sensor_impairment: i32
	for ship_id in p.ships[:p.ship_count] do if ship_at := ship_index(c, ship_id); ship_at >= 0 do sensor_impairment += c.ships[ship_at].impairments.sensors
	sensor_range := max(
		(7 - f64(symbionts) / ship_count * .35 - f64(sensor_impairment) / ship_count * .45) *
		sensor_profile.range_scale,
		3.5,
	)
	if d.simulation_tick % sensor_profile.update_ticks == 0 {
		prior_tracker := p.dark_navigation.tracker
		p.dark_navigation.tracker = dark_tracker_scan(
			d,
			p.dark_navigation.position,
			sensor_range,
			clamp((1 - p.coherence_exposure * .25) * sensor_profile.confidence_scale, 0, 1),
		)
		for &track in p.dark_navigation.tracker.tracks[:p.dark_navigation.tracker.track_count] {
			for prior in prior_tracker.tracks[:prior_tracker.track_count] do if prior.organism_id == track.organism_id {
				delta := track.confidence - prior.confidence
				if abs(delta) > .001 do forecast_add_factor(&track.factors, &track.factor_count, "confidence change since last scan", delta, 1, .Observed, p.ship_count > 0 ? p.ships[0] : 0, p.dark_navigation.sensor_posture_event)
				break
			}
			forecast_add_factor(
				&track.factors,
				&track.factor_count,
				fmt.tprintf(
					"%s sensor posture",
					dark_sensor_posture_name(p.dark_navigation.sensor_posture),
				),
				sensor_profile.confidence_scale - 1,
				1,
				.Observed,
				p.ship_count > 0 ? p.ships[0] : 0,
				p.dark_navigation.sensor_posture_event,
			)
			if sensor_impairment > 0 do forecast_add_factor(&track.factors, &track.factor_count, "damaged sensor capability", -f64(sensor_impairment) / ship_count, 1, .Observed)
		}
	}
	dark_update_local_observations(p, &p.dark_navigation.tracker, d.simulation_tick)
	dangerous_contact := dark_contact_pause_required(p, &p.dark_navigation.tracker, contact_danger)
	for field in d.fields[:d.field_count] do if field.film > .02 && dark_metric_distance(d.seed, p.dark_navigation.position, field.position) <= field.radius + sensor_range {p.observed_ecology_roles |= 1 << u32(Dark_Ecological_Role.Wake_Film); break}
	if p.contract.purpose == .Ecological_Survey && p.contract.required_ecology_roles != 0 && p.observed_ecology_roles & p.contract.required_ecology_roles == p.contract.required_ecology_roles do p.contract.objective_met = true
	coherence_limit := passage_coherence_limit(p)
	if p.systematic_search_active && auto_explore_return_reserve_required(c, p) {
		p.phase = .Awaiting_Leg
		p.pause_reason = .Propellant_Reserve
		p.systematic_search_active = false
		p.dark_navigation.autopilot_active = false
		p.dark_navigation.manual_active = false
	} else if illumination_pause :=
		   emission_change != 0 &&
		   p.dark_navigation.sensor_posture == .Illuminate &&
		   dark_tracker_contains(&p.dark_navigation.tracker, emission_change); illumination_pause {
		p.phase = .Awaiting_Leg
		p.pause_reason = .Dangerous_Contact
		p.dark_navigation.autopilot_active = false
		record_event(
			c,
			.Fleet_Hazard,
			"Illumination changed a resolved organism's behavior; the expedition held for a new decision.",
			p.ships[0],
			institution_id = p.contract.sponsor,
			cause_sequence = p.dark_navigation.sensor_posture_event,
		)
	} else if p.dark_navigation.paused_for_replan {p.phase = .Awaiting_Leg
		p.pause_reason = .Material_Obstruction} else if dangerous_contact && p.strategy.ecology != .Contact_Tolerant {p.phase = .Awaiting_Leg
		p.pause_reason = .Dangerous_Contact
		p.dark_navigation.autopilot_active =
			false} else if p.coherence_exposure >= coherence_limit {p.phase = .Awaiting_Leg
		p.pause_reason = .Coherence_Limit
		p.coherence_incidents += 1
		p.dark_navigation.autopilot_active =
			false} else if !objective_before && p.contract.objective_met {p.phase = .Awaiting_Leg
		p.pause_reason = .Contract_Evidence
		p.dark_navigation.autopilot_active =
			false} else if !p.dark_navigation.manual_active && !p.dark_navigation.autopilot_active && p.dark_navigation.course.waypoint_count >= 2 && p.dark_navigation.segment >= p.dark_navigation.course.waypoint_count - 1 {
		p.phase = .Awaiting_Leg
		p.pause_reason = .Course_Arrival
		if p.systematic_search_active {
			continued := continue_systematic_dark_search(c, p)
			if !continued && auto_explore_return_reserve_required(c, p) do p.pause_reason = .Propellant_Reserve
		}
	}
}

advance_passage :: proc(c: ^Campaign, p: ^Passage, elapsed: f64) {if !p.active || p.phase != .Underway || elapsed <= 0 do return
	if p.domain == .Dark {
		d := &c.outer_dark.continuum
		if d.paused do return
		d.accumulator += elapsed
		for d.accumulator + 1e-9 >= DARK_FIXED_STEP && p.phase == .Underway {
			advance_passage_dark_fixed(c, p)
			d.accumulator -= DARK_FIXED_STEP
		}
		p.dark_navigation.accumulator = 0
	}
	else if p.normal_course.active {prior_elapsed := p.normal_course.elapsed_days
		p.normal_course.elapsed_days = min(
			p.normal_course.elapsed_days + elapsed,
			p.normal_course.total_days,
		)
		coordinate_delta := p.normal_course.elapsed_days - prior_elapsed
		fraction :=
			p.normal_course.total_days > 0 ? coordinate_delta / p.normal_course.total_days : 1
		proper_delta := fraction * p.normal_course.total_proper_days
		p.normal_course.elapsed_proper_days += proper_delta
		overall_fraction :=
			p.normal_course.total_days > 0 ? p.normal_course.elapsed_days / p.normal_course.total_days : 1
		for axis in 0 ..< 3 do p.normal_course.current_position[axis] = p.normal_course.start_position[axis] + (p.normal_course.destination_position[axis] - p.normal_course.start_position[axis]) * overall_fraction
		p.elapsed_days += proper_delta
		p.membrane_elapsed_days += coordinate_delta
		p.course_cost += fraction * p.normal_course.energy_cost * f64(p.ship_count)
		if p.normal_course.elapsed_days >= p.normal_course.total_days {p.normal_course.active =
				false
			p.normal_course.start_neighborhood = p.normal_course.destination_neighborhood
			if p.normal_course.total_proper_days > 3650 {for ship_id in p.ships[:p.ship_count] do if at := ship_index(c, ship_id); at >= 0 do c.ships[at].damage = min(c.ships[at].damage + 1, max(c.ships[at].power - 1, 0))}
			p.phase = .Awaiting_Leg
			p.pause_reason = .Course_Arrival
			establish_arrival_communications(c, p)}}}
set_passage_safe_endpoint :: proc(
	c: ^Campaign,
	p: ^Passage,
	e: Dark_Safe_Endpoint,
	relay: u64 = 0,
) -> bool {if !p.active || p.phase == .Underway || e == .None || e == .Authenticated_Relay && relay == 0 do return false
	if e == .Fleet {
		if p.domain != .Normal_Space || c.outer_dark.continuum.anchor_door_id == 0 || p.normal_course.start_neighborhood != c.outer_dark.continuum.anchor_neighborhood do return false
	}
	else {
		at := dark_relay_index(c, relay)
		if at < 0 || !c.dark_relays[at].authenticated || p.domain != .Normal_Space || c.dark_relays[at].galaxy_neighborhood != p.normal_course.start_neighborhood do return false
		if passage_dark_return_available(c, p, p.pending_door_id) do return false
	}
	p.safe_endpoint = e
	p.authenticated_relay_id = relay
	p.phase = .At_Safe_Endpoint
	return true}

dark_strategy_apply_voyage :: proc(
	r: ^Dark_Strategy_Statistics,
	v: Dark_Voyage_Record,
	direction: i32,
) {
	r.resolved += direction
	if v.objective_met do r.objective_successes += direction
	if v.safe_conclusion do r.safe_conclusions += direction
	if v.record_recovered do r.records_recovered += direction
	r.ships_lost += v.ships_lost * direction
	r.ships_departed += v.ships_departed * direction
	r.coherence_incidents += v.coherence_incidents * direction
	r.total_damage += v.damage * direction
	r.total_elapsed_days += v.elapsed_days * f64(direction)
	r.total_course_cost += v.course_cost * f64(direction)
	r.total_depth += v.mean_depth * f64(direction)
	r.total_environment += v.environment * f64(direction)
	depth_band := v.mean_depth < 1.5 ? 0 : v.mean_depth < 4 ? 1 : 2
	environment_band := v.environment < .25 ? 0 : v.environment < .7 ? 1 : 2
	r.depth_bands[depth_band] += direction
	r.environment_bands[environment_band] += direction
	cell := depth_band * 3 + environment_band; r.band_resolved[cell] += direction
	if v.objective_met do r.band_objective_successes[cell] += direction
	if v.safe_conclusion do r.band_safe_conclusions[cell] += direction
	if v.record_recovered do r.band_records_recovered[cell] += direction
	r.band_damage[cell] += f64(
		v.damage * direction,
	); r.band_elapsed_days[cell] += v.elapsed_days * f64(direction); r.band_course_cost[cell] += v.course_cost * f64(direction)
}

passage_debrief_reward :: proc(scenario: Operation_Objective) -> Fleet_Stock {
	#partial switch scenario {
	case .Passage_Recover_Reserves:
		return {raw_materials = 4, supplies = 18}
	case .Passage_Evaluate_Home:
		return {raw_materials = 3, supplies = 6, services = 3}
	case .Passage_Evacuate_Harbor:
		return {equipment = 2, supplies = 8, services = 4}
	case .Passage_Inspect_Treaty:
		return {supplies = 4, services = 4}
	case .Passage_Escort_Migration:
		return {supplies = 8, services = 2}
	case .Passage_Recover_Missing_Ship:
		return {manufactured_goods = 4, equipment = 3, supplies = 4, services = 4}
	case:
		return {}
	}
}

apply_passage_debrief_reward :: proc(c: ^Campaign, p: ^Passage, recovered: bool) -> Fleet_Stock {
	if !recovered || p.safe_endpoint != .Fleet || !p.contract.objective_met do return {}
	reward := passage_debrief_reward(p.contract.scenario)
	// Every successful expedition returning to the fleet brings reusable field
	// assemblies and trained service work home. An undertaking can add a larger,
	// scenario-specific return, but is not required for ordinary Passage play to
	// participate in the material economy.
	reward.manufactured_goods += 2
	reward.services += 4
	fleet_stock_gain(c, reward, .Reward, p.departure_event)
	detail :=
		p.contract.scenario == .None ? "The completed Passage returned reusable material and service capacity." : "The completed Passage undertaking returned its material debrief."
	record_event(
		c,
		.Resource_Changed,
		fmt.tprintf("%s %s", detail, fleet_stock_label(reward)),
		p.ships[0],
		institution_id = p.contract.sponsor,
		cause_sequence = p.departure_event,
	)
	return reward
}

settle_passage_manifest :: proc(c: ^Campaign, p: ^Passage) -> bool {
	if p.manifest.settled do return false
	allocated := p.manifest.allocated.propellant
	if allocated > 0 {
		// Dark movement is a field-depth problem, not conventional reaction-mass
		// expenditure. The physical manifest remains escrowed for the expedition.
		consumed := i64(0)
		p.manifest.consumed.propellant = consumed
		if p.safe_endpoint ==
		   .Fleet {p.manifest.recovered.propellant = allocated - consumed; fleet_stock_gain(c, p.manifest.recovered, .Recovery, p.departure_event)} else {p.manifest.lost.propellant = allocated - consumed}
	}
	p.manifest.settled = true
	record_event(
		c,
		.Resource_Changed,
		fmt.tprintf(
			"Passage propellant: allocated %d; consumed %d; recovered %d; lost %d.",
			p.manifest.allocated.propellant,
			p.manifest.consumed.propellant,
			p.manifest.recovered.propellant,
			p.manifest.lost.propellant,
		),
		p.ships[0],
		cause_sequence = p.departure_event,
	)
	return true
}

ingest_dark_voyage_record :: proc(c: ^Campaign, v: Dark_Voyage_Record) -> bool {if !v.resolved || v.source == .None do return false
	found := false
	revision := false
	prior_record: Dark_Voyage_Record
	for i in 0 ..< c.dark_unresolved_voyage_count do if c.dark_unresolved_voyages[i].id == v.id {
		prior_record = c.dark_unresolved_voyages[i]
		if prior_record.resolved {
			if prior_record.source != .Confirmed_Loss || v.source == .Confirmed_Loss || prior_record.sponsor != v.sponsor || prior_record.purpose != v.purpose || !dark_strategy_equal(prior_record.strategy, v.strategy) do return false
			revision = true
		}
		c.dark_unresolved_voyages[i] = v
		found = true
		break
	}
	if !found do return false
	at := dark_strategy_record_ensure(c, v.sponsor, v.purpose, v.strategy)
	if at < 0 do return false
	r := &c.dark_strategy_records[at]
	prior_evidence := r.resolved
	comparison_contract := Dark_Contract {
		sponsor       = v.sponsor,
		purpose       = v.purpose,
		term          = v.term,
		semantic_tags = make_semantic_tags(.Rule, .Passage, .Navigation),
	}
	prior_recommendation := recommend_dark_strategy(c, &comparison_contract)
	if revision do dark_strategy_apply_voyage(r, prior_record, -1)
	dark_strategy_apply_voyage(r, v, 1)
	r.last_event = v.resolution_event
	if revision do record_event(c, .Situation_Decided, fmt.tprintf("A late voyage record revised the %s's confirmed-loss assessment.", institution_name(c, v.sponsor)), institution_id = v.sponsor)
	if prior_evidence >= 2 {revised := recommend_dark_strategy(c, &comparison_contract)
		if !dark_strategy_equal(prior_recommendation.strategy, revised.strategy) do record_event(c, .Situation_Decided, fmt.tprintf("The %s reversed its Dark recommendation after voyage evidence: %v/%v became %v/%v.", institution_name(c, v.sponsor), prior_recommendation.strategy.depth, prior_recommendation.strategy.course, revised.strategy.depth, revised.strategy.course), institution_id = v.sponsor)}
	return true}

conclude_passage :: proc(c: ^Campaign, p: ^Passage) -> (bool, string) {if !p.active || p.phase != .At_Safe_Endpoint do return false, "Reach the fleet or an authenticated relay before ending the mission."
	if p.safe_endpoint == .Authenticated_Relay && !begin_stranded_passage_group(c, p, p.authenticated_relay_id) do return false, "The relay cannot preserve another separated expedition record."
	recovered := p.safe_endpoint == .Fleet || p.authenticated_relay_id != 0
	departed, lost, damage: i32
	for ship_number := 0; ship_number < p.ship_count; ship_number += 1 {id := p.ships[ship_number]
		at := ship_index(c, id)
		if at < 0 {lost += 1; continue}
		s := &c.ships[at]
		damage += max(s.damage, 0)
		if !s.active || s.departure == .Lost {lost += 1; s.committed = false; continue}
		s.committed = false
		if p.safe_endpoint == .Authenticated_Relay {s.active = false; s.departure = .Dark_Voyage
			s.current_commitment = "Remained at an authenticated relay after the route home became inaccessible."
			add_ship_history(c, s.id, s.current_commitment)
			departed += 1}}
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The %s mission ended at %v; objective %s.",
			institution_name(c, p.contract.sponsor),
			p.safe_endpoint,
			p.contract.objective_met ? "met" : "unmet",
		),
		p.ships[0],
		institution_id = p.contract.sponsor,
	)
	v := Dark_Voyage_Record {
		id                  = p.id,
		sponsor             = p.contract.sponsor,
		purpose             = p.contract.purpose,
		term                = p.contract.term,
		strategy            = p.strategy,
		ships               = p.ships,
		ship_count          = p.ship_count,
		objective_met       = p.contract.objective_met,
		safe_conclusion     = lost == 0,
		record_recovered    = recovered,
		ships_lost          = lost,
		ships_departed      = departed,
		coherence_incidents = p.coherence_incidents,
		damage              = max(damage - p.initial_total_damage, 0),
		elapsed_days        = p.elapsed_days,
		course_cost         = p.course_cost,
		mean_depth          = p.elapsed_days > 0 ? p.accumulated_depth / p.elapsed_days : 0,
		environment         = p.environment_exposure,
		emergency_depth_committed = p.emergency_depth_committed,
		resolved            = true,
		source              = p.safe_endpoint == .Fleet ? .Fleet_Debrief : .Authenticated_Relay,
		departure_event     = p.departure_event,
		resolution_event    = c.event_sequence,
	}
	_ = ingest_dark_voyage_record(c, v)
	if recovered do dark_transmit_passage_knowledge(c, p, p.authenticated_relay_id)
	_ = settle_passage_manifest(c, p)
	_ = apply_passage_debrief_reward(c, p, recovered)
	_ = apply_operation_return(
		c,
		.Passage,
		p.id,
		p.contract.objective_met,
		p.ships[:p.ship_count],
		i64(p.elapsed_days * f64(CAMPAIGN_DAY_SECONDS)),
		withdrawals = i32(departed),
		protected_exposure = i32(p.environment_exposure),
		evidence = recovered ? 1 : 0,
	)
	campaign_clear_attention_source(c, .Passage, p.id)
	p.active = false
	p.phase = .Concluded
	c.outer_dark.continuum.paused = true
	return true,
		p.safe_endpoint == .Fleet ? "The fleet received the expedition debrief." : "The relay received the record; the expedition ships remained there."}

declare_passage_missing :: proc(c: ^Campaign, p: ^Passage) -> (bool, string) {
	if !p.active do return false, "No active Dark expedition can be declared missing."
	// The ships remain active-but-committed: they are absent from fleet use, not
	// proven destroyed. Their original unresolved voyage record is deliberately
	// left censored until authenticated evidence or confirmed loss arrives.
	for ship_id in p.ships[:p.ship_count] do if at := ship_index(c, ship_id); at >= 0 do c.ships[at].committed = true
	for &v in c.dark_unresolved_voyages[:c.dark_unresolved_voyage_count] do if v.id == p.id && !v.resolved {
		v.emergency_depth_committed = p.emergency_depth_committed
		break
	}
	campaign_clear_attention_source(c, .Passage, p.id)
	record_event(
		c,
		.Situation_Decided,
		fmt.tprintf(
			"The %s listed Dark voyage %d as overdue and missing; no loss was presumed.",
			institution_name(c, p.contract.sponsor),
			p.id,
		),
		p.ships[0],
		institution_id = p.contract.sponsor,
	)
	p.active = false
	p.phase = .Concluded
	p.safe_endpoint = .None
	_ = settle_passage_manifest(c, p)
	p.pause_reason = .None
	c.outer_dark.continuum.paused = true
	return true, "The voyage is missing and remains an unresolved institutional observation."
}
confirm_dark_voyage_lost :: proc(c: ^Campaign, id: u64, cause: u64 = 0) -> bool {for v in c.dark_unresolved_voyages[:c.dark_unresolved_voyage_count] do if v.id == id && !v.resolved {
		if c.passage.id == id && !c.passage.manifest.settled {c.passage.safe_endpoint = .None; _ = settle_passage_manifest(c, &c.passage)}
		r := v; r.resolved = true; r.source = .Confirmed_Loss; r.ships_lost = i32(r.ship_count); r.resolution_event = cause
		if !ingest_dark_voyage_record(c, r) do return false
		for ship_id in r.ships[:r.ship_count] do if at := ship_index(c, ship_id); at >= 0 {
			s := &c.ships[at]; s.active = false; s.committed = false; s.departure = .Lost; s.current_commitment = "Confirmed lost on a Dark voyage."; add_ship_history(c, s.id, s.current_commitment)
		}
		return true
	}
	return false}
refresh_passage_semantic_tags :: proc(p: ^Passage) {p.semantic_tags = make_semantic_tags(
		.Entity,
		.Passage,
		.Navigation,
	)
	p.contract.semantic_tags = make_semantic_tags(.Rule, .Passage, .Navigation)}
