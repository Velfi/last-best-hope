package game

import "core:fmt"
import "core:math"

MAX_EXPEDITION_SHIPS :: 7
MAX_LOCAL_DOOR_DISCOVERIES :: 48
MAX_LOCAL_DARK_OBSERVATIONS :: 64

// Ship-history vocabulary retained independently of the removed Passage graph.
Passage_Ship_Trait :: enum {
	None,
	Curious,
	Protective,
	Cautious,
	Committed,
	Independent,
}
Passage_Promise_Status :: enum {
	Active,
	Upheld,
	Broken,
	Transformed,
}

Expedition_Domain :: enum {
	Dark,
	Normal_Space,
}
Dark_Contract_Purpose :: enum {
	None,
	Map_Unknown_Door,
	Verify_Correspondence,
	Ecological_Survey,
	Stabilize_Relay,
	Infrastructure_Run,
}
Dark_Depth_Posture :: enum {
	Shallow,
	Balanced,
	Deep,
}
Dark_Course_Priority :: enum {
	Shortest_Metric,
	Best_Mapped,
	Lowest_Coherence,
}
Dark_Ecology_Posture :: enum {
	Avoidant,
	Balanced,
	Contact_Tolerant,
}
Dark_Relay_Posture :: enum {
	Relay_First,
	Objective_First,
}
Dark_Withdrawal_Margin :: enum {
	Conservative,
	Balanced,
	Mission_First,
}
// Player-facing policy deliberately couples previously independent switches.
// A voyage now declares a comprehensible posture rather than a five-axis
// optimisation profile. The derived strategy remains the rule-level adapter
// used by navigation and ecology.
Dark_Route_Policy :: enum {
	Fast,
	Informed,
	Low_Exposure,
}
Dark_Contact_Policy :: enum {
	Avoid,
	Observe,
	Tolerate,
}
Dark_Return_Policy :: enum {
	Fleet_First,
	Balanced_Return,
	Objective_First_Return,
}
Dark_Expedition_Policy :: struct {
	route:         Dark_Route_Policy,
	contact:       Dark_Contact_Policy,
	return_policy: Dark_Return_Policy,
}
DARK_STRATEGY_PROFILE_COUNT :: 3 * 3 * 3
Dark_Expedition_Phase :: enum {
	Briefing,
	Underway,
	Awaiting_Leg,
	At_Safe_Endpoint,
	Concluded,
}
Dark_Safe_Endpoint :: enum {
	None,
	Fleet,
	Authenticated_Relay,
}
Dark_Pause_Reason :: enum {
	None,
	Course_Arrival,
	Unknown_Door,
	Dangerous_Contact,
	Coherence_Limit,
	Material_Obstruction,
	Contract_Evidence,
	Propellant_Reserve,
}
Dark_Record_Source :: enum {
	None,
	Fleet_Debrief,
	Authenticated_Relay,
	Recovered_Record,
	Confirmed_Loss,
}

Dark_Strategy_Profile :: struct {
	depth:      Dark_Depth_Posture,
	course:     Dark_Course_Priority,
	ecology:    Dark_Ecology_Posture,
	relay:      Dark_Relay_Posture,
	withdrawal: Dark_Withdrawal_Margin,
}
Dark_Contract :: struct {
	purpose:                                                         Dark_Contract_Purpose,
	scenario:                                                        Operation_Objective,
	need_index:                                                      int,
	undertaking_id:                                                  Compact_Undertaking_ID,
	sponsor, reviewer:                                               Institution_ID,
	term:                                                            Operation_Conduct,
	authority:                                                       Authority_Policy,
	disclosure:                                                      Disclosure_Policy,
	rescue:                                                          Rescue_Policy,
	withdrawal:                                                      Operation_Withdrawal,
	resource_threshold, habitability_threshold:                      f64,
	required_roles:                                                  i32,
	required_ecology_roles:                                          u32,
	protected_roles:                                                 [8]bool,
	negotiation_first, breach_authorized, objective_met, standalone: bool,
	evidence_count:                                                  i32,
	semantic_tags:                                                   Semantic_Tags,
	operation_authority:                                             Operation_Authority,
}
Dark_Normal_Course :: struct {
	start_neighborhood, destination_neighborhood:                int,
	start_position, destination_position, current_position:      [3]f64,
	distance_kpc, velocity_fraction_c, elapsed_days, total_days: f64,
	elapsed_proper_days, total_proper_days, energy_cost:         f64,
	active:                                                      bool,
}
Dark_Atlas_Discovery :: struct {
	door_id:             u64,
	position_name_hash:  u64,
	galaxy_neighborhood: int,
	discovered_tick:     u64,
	transmitted:         bool,
	relay_id:            u64,
}
Dark_Organism_Observation :: struct {
	organism_id:                                                            u64,
	role:                                                                   Dark_Ecological_Role,
	first_seen_tick, last_seen_tick, last_entry_tick, last_withdrawal_tick: u64,
	manifestation_count, reported_manifestation_count:                      i32,
	currently_manifested:                                                   bool,
	confidence:                                                             f64,
	last_behavior:                                                          Dark_Behavior,
	last_target:                                                            u64,
}
Dark_Relay_Record :: struct {
	id:                  u64,
	galaxy_neighborhood: int,
	condition:           f64,
	authenticated:       bool,
	established_event:   u64,
	last_service_event:  u64,
	sponsor:             Institution_ID,
	semantic_tags:       Semantic_Tags,
}
Dark_Contract_Progress :: struct {
	purpose:                                        Dark_Contract_Purpose,
	objective_met:                                  bool,
	evidence_count:                                 i32,
	observed_ecology_roles, required_ecology_roles: u32,
	current_neighborhood:                           int,
	endpoint_resource, endpoint_habitability:       f64,
	relay_available:                                bool,
}
Dark_Strategy_Statistics :: struct {
	sponsor:                                                                                                                                      Institution_ID,
	purpose:                                                                                                                                      Dark_Contract_Purpose,
	strategy:                                                                                                                                     Dark_Strategy_Profile,
	attempted,
	resolved,
	objective_successes,
	safe_conclusions,
	records_recovered,
	ships_lost,
	ships_departed,
	coherence_incidents,
	total_damage: i32,
	total_elapsed_days,
	total_course_cost,
	total_depth,
	total_environment:                                                                        f64,
	depth_bands,
	environment_bands:                                                                                                               [3]i32,
	band_resolved,
	band_objective_successes,
	band_safe_conclusions,
	band_records_recovered:                                                       [9]i32,
	band_damage,
	band_elapsed_days,
	band_course_cost:                                                                                             [9]f64,
	last_event:                                                                                                                                   u64,
}
Dark_Strategy_Estimate :: struct {
	objective_rate, safety_rate, record_rate, confidence: f64,
	evidence:                                             i32,
	mean_damage, mean_days:                               f64,
}
Dark_Strategy_Recommendation :: struct {
	policy:      Dark_Expedition_Policy,
	strategy:    Dark_Strategy_Profile,
	estimate:    Dark_Strategy_Estimate,
	score:       f64,
	exploratory: bool,
	reason:      string,
}
Dark_Strategy_Comparison :: struct {
	selected, recommended:                   Dark_Strategy_Profile,
	selected_estimate, recommended_estimate: Dark_Strategy_Estimate,
	difference_count:                        int,
	failure_mode:                            string,
}
Dark_Voyage_Record :: struct {
	id:                                                      u64,
	sponsor:                                                 Institution_ID,
	purpose:                                                 Dark_Contract_Purpose,
	term:                                                    Operation_Conduct,
	strategy:                                                Dark_Strategy_Profile,
	ships:                                                   [MAX_EXPEDITION_SHIPS]Ship_ID,
	ship_count:                                              int,
	objective_met, safe_conclusion, record_recovered:        bool,
	ships_lost, ships_departed, coherence_incidents, damage: i32,
	elapsed_days, course_cost, mean_depth, environment:      f64,
	emergency_depth_committed:                               bool,
	resolved:                                                bool,
	source:                                                  Dark_Record_Source,
	departure_event, resolution_event:                       u64,
}
Passage_Manifest :: struct {
	allocated, consumed, recovered, lost: Fleet_Stock,
	settled:                              bool,
}

Passage :: struct {
	active:                                                                                                        bool,
	id:                                                                                                            u64,
	phase:                                                                                                         Dark_Expedition_Phase,
	domain:                                                                                                        Expedition_Domain,
	contract:                                                                                                      Dark_Contract,
	policy,
	recommended_policy:                                                                                    Dark_Expedition_Policy,
	strategy,
	recommended_strategy:                                                                                Dark_Strategy_Profile,
	recommendation_overridden:                                                                                     bool,
	relay_advised:                                                                                                 bool,
	ships:                                                                                                         [MAX_EXPEDITION_SHIPS]Ship_ID,
	ship_count:                                                                                                    int,
	dark_navigation:                                                                                               Dark_Expedition_Navigation,
	normal_course:                                                                                                 Dark_Normal_Course,
	local_atlas:                                                                                                   [MAX_LOCAL_DOOR_DISCOVERIES]Dark_Atlas_Discovery,
	local_atlas_count:                                                                                             int,
	local_observations:                                                                                            [MAX_LOCAL_DARK_OBSERVATIONS]Dark_Organism_Observation,
	local_observation_count:                                                                                       int,
	local_habitable_contacts:                                                                                      [dynamic]Habitable_World_Contact,
	safe_endpoint:                                                                                                 Dark_Safe_Endpoint,
	authenticated_relay_id:                                                                                        u64,
	pause_reason:                                                                                                  Dark_Pause_Reason,
	systematic_search_active:                                                                                      bool,
	pending_door_id:                                                                                               u64,
	departure_door_id:                                                                                             u64,
	departure_door_position_name_hash:                                                                             u64,
	departure_neighborhood:                                                                                        int,
	cleared_contact_id:                                                                                            u64,
	emergency_target_door_id:                                                                                      u64,
	field_depth_rating,
	emergency_depth_limit:                                                                                         f64,
	emergency_depth_committed:                                                                                     bool,
	elapsed_days,
	membrane_elapsed_days,
	course_cost,
	accumulated_depth,
	environment_exposure,
	coherence_exposure: f64,
	observed_ecology_roles:                                                                                        u32,
	coherence_incidents,
	initial_total_damage:                                                                     i32,
	manifest:                                                                                                      Passage_Manifest,
	departure_event:                                                                                               u64,
	semantic_tags:                                                                                                 Semantic_Tags,
}

institution_name :: proc(c: ^Campaign, id: Institution_ID) -> string {if i := institution_index(c, id); i >= 0 do return c.institutions[i].name
	return "Fleet Council"}

// Membrane time has no universal rate in the Dark. This baseline models the
// setting contract C(d): normal correspondence at the anchor, then a smooth
// approach toward stopped membrane time with increasing depth. Local temporal
// currents can multiply this coefficient later without changing its contract.
dark_membrane_time_coefficient :: proc(depth: f64) -> f64 {
	return math.exp(-max(depth, 0))
}

dark_membrane_days_for_step :: proc(depth, ship_days: f64) -> f64 {
	return max(ship_days, 0) * dark_membrane_time_coefficient(depth)
}
dark_fleet_door_known :: proc(c: ^Campaign, id: u64) -> bool {
	if id == c.outer_dark.continuum.anchor_door_id do return true
	for discovery in c.dark_fleet_atlas do if discovery.door_id == id do return true
	return false
}

dark_door_position_name_hash :: proc(position: Dark_Vec4) -> u64 {
	hash := u64(0x646f6f725f346470)
	for coordinate, axis in position {
		bits := transmute(u64)coordinate
		hash = ship_construction_visual_mix(hash ~ bits ~ u64(axis + 1) * 0x9e3779b97f4a7c15)
	}
	return hash
}

dark_correspondence_name :: proc(
	c: ^Campaign,
	door_id: u64,
	neighborhood: int = -1,
	position_name_hash: u64 = 0,
) -> string {
	if c != nil && c.galaxy != nil && neighborhood >= 0 {
		for system in c.galaxy.detailed_systems[:c.galaxy.detailed_system_count] do if system.neighborhood_index == neighborhood {
			names := generate_solar_system_names(system.system)
			return fmt.tprintf("%s Correspondence", names.proper_name)
		}
	}
	resolved_hash := position_name_hash
	if resolved_hash == 0 && c != nil {
		for door in c.outer_dark.continuum.doors[:c.outer_dark.continuum.door_count] do if door.id == door_id {
			resolved_hash = dark_door_position_name_hash(door.position)
			break
		}
	}
	// Door IDs preserve readable names for records saved before positional hashes existed.
	return generate_door_hash_name(resolved_hash != 0 ? resolved_hash : door_id)
}

dark_fleet_record_discovery :: proc(c: ^Campaign, discovery: Dark_Atlas_Discovery) -> bool {
	for &known in c.dark_fleet_atlas do if known.door_id == discovery.door_id {
		known.galaxy_neighborhood = discovery.galaxy_neighborhood
		if discovery.position_name_hash != 0 do known.position_name_hash = discovery.position_name_hash
		known.discovered_tick = min(known.discovered_tick, discovery.discovered_tick)
		known.transmitted = true
		known.relay_id = discovery.relay_id
		return false
	}
	record := discovery
	record.transmitted = true
	append(&c.dark_fleet_atlas, record)
	return true
}
dark_update_local_observations :: proc(p: ^Passage, tracker: ^Dark_Tracker, tick: u64) {
	for &observation in p.local_observations[:p.local_observation_count] do if observation.currently_manifested {observation.currently_manifested = false; observation.last_withdrawal_tick = tick}
	for track in tracker.tracks[:tracker.track_count] {
		at := -1
		for observation, i in p.local_observations[:p.local_observation_count] do if observation.organism_id == track.organism_id {at = i; break}
		if at <
		   0 {if p.local_observation_count >= MAX_LOCAL_DARK_OBSERVATIONS do continue; at = p.local_observation_count; p.local_observation_count += 1; p.local_observations[at] = {
				organism_id     = track.organism_id,
				role            = track.role,
				first_seen_tick = tick,
			}}
		o := &p.local_observations[at]
		if !o.currently_manifested {o.manifestation_count += 1; o.last_entry_tick = tick}
		o.currently_manifested = true
		o.last_seen_tick = tick
		o.confidence = max(o.confidence, track.confidence)
		o.last_behavior = track.behavior
		o.last_target = track.target_id
	}
}
dark_fleet_ingest_observation :: proc(c: ^Campaign, observation: Dark_Organism_Observation) {
	for &known in c.dark_organism_observations do if known.organism_id == observation.organism_id {known.first_seen_tick = min(known.first_seen_tick, observation.first_seen_tick); known.last_seen_tick = max(known.last_seen_tick, observation.last_seen_tick); known.last_entry_tick = max(known.last_entry_tick, observation.last_entry_tick); known.last_withdrawal_tick = max(known.last_withdrawal_tick, observation.last_withdrawal_tick); known.manifestation_count += observation.manifestation_count; known.confidence = max(known.confidence, observation.confidence); known.last_behavior = observation.last_behavior; known.last_target = observation.last_target; known.currently_manifested = false; return}
	record := observation
	record.currently_manifested = false
	append(&c.dark_organism_observations, record)
}
dark_transmit_passage_knowledge :: proc(c: ^Campaign, p: ^Passage, relay_id: u64 = 0) {
	for &observation in p.local_observations[:p.local_observation_count] {
		new_entries := observation.manifestation_count - observation.reported_manifestation_count
		if new_entries <= 0 do continue
		report := observation
		report.manifestation_count = new_entries
		report.reported_manifestation_count = new_entries
		dark_fleet_ingest_observation(c, report)
		observation.reported_manifestation_count = observation.manifestation_count
	}
	for &discovery in p.local_atlas[:p.local_atlas_count] {
		if discovery.transmitted do continue
		discovery.transmitted = true
		discovery.relay_id = relay_id
		_ = dark_fleet_record_discovery(c, discovery)
		_ = dark_mark_door_known(&c.outer_dark.continuum, discovery.door_id)
	}
	for &contact in p.local_habitable_contacts {
		if contact.transmitted do continue
		contact.transmitted = true
		_ = habitable_ingest_contact(c, contact)
	}
}
dark_strategy_equal :: proc(a, b: Dark_Strategy_Profile) -> bool {return(
		a.depth == b.depth &&
		a.course == b.course &&
		a.ecology == b.ecology &&
		a.relay == b.relay &&
		a.withdrawal == b.withdrawal \
	)}
dark_default_strategy :: proc(term: Operation_Conduct = .None) -> Dark_Strategy_Profile {s :=
		Dark_Strategy_Profile{.Balanced, .Lowest_Coherence, .Balanced, .Relay_First, .Balanced}
	switch
	term {case .Preserve_Lives:
		s.depth = .Shallow; s.ecology = .Avoidant; s.withdrawal = .Conservative; case .Open_Record:
		s.course = .Best_Mapped; case .Mission_First:
		s.depth = .Deep; s.course = .Shortest_Metric; s.relay = .Objective_First
		s.withdrawal = .Mission_First; case .None:}
	return s}
