package game

import "core:encoding/json"
import "core:testing"

SAVE_MAGIC :: [4]u8{'L', 'B', 'H', 'S'}
SAVE_HEADER_SIZE :: 16
Save_Decode_Result :: struct {
	ok:      bool,
	message: string,
}
Campaign_Save_Payload :: struct {
	campaign:       Campaign,
	galaxy:         Galaxy,
	far_engagement: Far_Engagement,
}

validate_saved_situation :: proc(c: ^Campaign, s: Fleet_Situation) -> bool {
	if s.phase == .None do return s.kind == .None
	if s.id == 0 || s.kind == .None || s.initiator == 0 || ship_index(c, s.initiator) < 0 || s.position_count < 0 || s.position_count > MAX_SITUATION_POSITIONS || s.choice_count < 0 || s.choice_count > MAX_SITUATION_CHOICES do return false
	if s.origin_event != 0 && event_index_by_sequence(c, s.origin_event) < 0 do return false
	if s.proposal_event != 0 && event_index_by_sequence(c, s.proposal_event) < 0 do return false
	if s.decision_event != 0 && event_index_by_sequence(c, s.decision_event) < 0 do return false
	if s.kind == .Settlement && !celestial_reference_valid(c, s.celestial) do return false
	for i in 0 ..< s.position_count {position := s.positions[i]; if ship_index(c, position.ship) < 0 || position.reason_count < 0 || position.reason_count > MAX_SITUATION_REASONS do return false; for j in 0 ..< position.reason_count {reason := position.reasons[j]; if reason.source_event != 0 && event_index_by_sequence(c, reason.source_event) < 0 do return false}}
	return true
}

campaign_serialize :: proc(c: ^Campaign) -> [dynamic]u8 {
	refresh_semantic_tags(c)
	if c.galaxy == nil do return nil
	state := new(Campaign_Save_Payload); defer free(state)
	state.campaign = c^
	// Older tools and compatibility tests may still assign the derived season
	// field directly. Normalize the serialized copy to that reporting boundary
	// without mutating live state, and preserve every scheduled interval.
	derived_period := i32(max(i64(state.campaign.clock.now), i64(0)) / CAMPAIGN_REPORT_SECONDS)
	if state.campaign.season != derived_period {
		old_now := state.campaign.clock.now
		new_now := Campaign_Time(i64(max(state.campaign.season, 0)) * CAMPAIGN_REPORT_SECONDS)
		delta := i64(new_now) - i64(old_now)
		state.campaign.clock.now = new_now
		state.campaign.clock.reporting_period = max(state.campaign.season, 0)
		state.campaign.clock.next_reporting_at = campaign_time_add(
			new_now,
			CAMPAIGN_REPORT_SECONDS,
		)
		state.campaign.year = max(state.campaign.season, 0) * i32(CAMPAIGN_REPORT_YEARS)
		for &work in state.campaign.scheduled_work {
			if !work.active do continue
			work.started_at = campaign_time_add(work.started_at, delta)
			work.due_at = campaign_time_add(work.due_at, delta)
		}
		for &event in state.campaign.attention_queue {
			if !event.active do continue
			event.raised_at = campaign_time_add(event.raised_at, delta)
			event.response_deadline = campaign_time_add(event.response_deadline, delta)
		}
	}
	state.galaxy = c.galaxy^
	if c.far_engagement != nil do state.far_engagement = c.far_engagement^
	payload, error := json.marshal(state^)
	if error != nil do return nil
	defer delete(payload)
	out := make([dynamic]u8, SAVE_HEADER_SIZE, SAVE_HEADER_SIZE + len(payload))
	for value, i in SAVE_MAGIC do out[i] = value
	for i in 0 ..< 4 do out[4 + i] = u8(c.format_version >> u32(i * 8))
	for i in 0 ..< 8 do out[8 + i] = u8(c.rules_identity >> u64(i * 8))
	append(&out, ..payload)
	return out
}

campaign_save_header_validate :: proc(data: []u8) -> Save_Decode_Result {
	if len(data) <= SAVE_HEADER_SIZE do return {false, "save is corrupt or truncated"}
	for value, i in SAVE_MAGIC do if data[i] != value do return {false, "save has an unknown format"}
	version: u32
	rules: u64
	for i in 0 ..< 4 do version |= u32(data[4 + i]) << u32(i * 8)
	for i in 0 ..< 8 do rules |= u64(data[8 + i]) << u64(i * 8)
	if version == 60 do return {false, "This campaign uses the retired expedition-resource economy and cannot be loaded by the current rules."}
	if version == 63 do return {false, "This campaign predates centralized narrative scheduling; begin a new chronicle."}
	if version >= 1 && version < CAMPAIGN_FORMAT_VERSION do return {false, "This chronicle predates physical normal-space resource extraction and cannot be continued; begin a new chronicle."}
	if version != CAMPAIGN_FORMAT_VERSION do return {false, "campaign format changed; begin a new chronicle"}
	if rules != CAMPAIGN_RULES_IDENTITY do return {false, "save belongs to incompatible campaign rules"}
	return {true, ""}
}

campaign_save_payload_decode :: proc(data: []u8) -> (^Campaign, Save_Decode_Result) {
	state := new(Campaign_Save_Payload); defer free(state)
	if json.unmarshal(data[SAVE_HEADER_SIZE:], state, allocator = campaign_storage_allocator()) != nil do return nil, {false, "save payload is invalid"}
	decoded := new(Campaign)
	decoded^ = state.campaign
	decoded.galaxy = new(Galaxy, campaign_storage_allocator())
	decoded.galaxy^ = state.galaxy
	dark_rebuild_neighborhood_distance_order(&decoded.outer_dark.continuum, decoded.galaxy)
	if decoded.passage.field_depth_rating <= 0 do decoded.passage.field_depth_rating = STANDARD_FIELD_DEPTH_RATING
	if decoded.passage.emergency_depth_limit <= 0 do decoded.passage.emergency_depth_limit = EMERGENCY_FIELD_DEPTH_LIMIT
	decoded.far_engagement = new(Far_Engagement, campaign_storage_allocator())
	decoded.far_engagement^ = state.far_engagement
	decoded.owns_strings = true
	return decoded, {true, ""}
}

@(optimization_mode = "none")
campaign_save_validate_core :: proc(decoded: ^Campaign) -> Save_Decode_Result {
	if decoded.format_version != CAMPAIGN_FORMAT_VERSION ||
	   decoded.rules_identity != CAMPAIGN_RULES_IDENTITY ||
	   decoded.rng_state == 0 ||
	   !far_validate(decoded.far_engagement) ||
	   !combat_operation_validate_loaded(&decoded.combat_operation) ||
	   !validate_expeditionary_compact(
			   decoded,
		   ) {return {false, "save contains invalid campaign or Expeditionary Compact state"}}
	if int(decoded.clock.speed) < int(Campaign_Speed.Paused) ||
	   int(decoded.clock.speed) > int(Campaign_Speed.Next_Attention) ||
	   decoded.clock.now < 0 ||
	   decoded.clock.next_reporting_at < decoded.clock.now ||
	   decoded.clock.reporting_period != decoded.season {
		return {false, "save contains an invalid campaign clock"}
	}
	has_pending_attention := false
	for event in decoded.attention_queue {
		if !event.active do continue
		if event.id == 0 ||
		   event.choice_count < 0 ||
		   event.choice_count > MAX_ATTENTION_CHOICES ||
		   event.default_choice < 0 ||
		   event.choice_count > 0 && event.default_choice >= event.choice_count ||
		   event.raised_at > decoded.clock.now {
			return {false, "save contains an invalid attention event"}
		}
		if (event.level == .Decision || event.level == .Constitutional) &&
		   event.no_response_default == "" &&
		   !event.explicit_resolution_required {
			return {false, "save contains attention without a deterministic default"}
		}
		if event.level == .Decision || event.level == .Constitutional {
			has_pending_attention = true
		}
	}
	if decoded.clock.paused_for_attention != has_pending_attention {
		return {false, "save contains inconsistent attention state"}
	}
	for work in decoded.scheduled_work {
		if !work.active do continue
		if work.id == 0 ||
		   work.source == .None ||
		   work.due_at < decoded.clock.now ||
		   work.started_at > decoded.clock.now {
			return {false, "save contains invalid scheduled work"}
		}
	}
	expected_horizon := chronicle_length_seasons(
		decoded.length,
	); if decoded.ending_finale.active && expected_horizon > 0 do expected_horizon = decoded.ending_finale.ends_season
	if int(decoded.material_pressure) < 0 ||
	   int(decoded.material_pressure) > int(Material_Pressure.Severe) ||
	   int(decoded.consequence_severity) < 0 ||
	   int(decoded.consequence_severity) > int(Consequence_Severity.Severe) ||
	   decoded.max_seasons != expected_horizon ||
	   decoded.ending_finale.active &&
		   (decoded.ending_finale.ending == .In_Progress ||
				   decoded.ending_finale.started_season < 0 ||
				   decoded.ending_finale.ends_season != decoded.ending_finale.started_season + 3 ||
				   decoded.season < decoded.ending_finale.started_season ||
				   decoded.season > decoded.ending_finale.ends_season) ||
	   decoded.ending_prompt_pending &&
		   (!decoded.ending_finale.active &&
					   (decoded.length == .Open || decoded.season < decoded.max_seasons) ||
				   decoded.ending_finale.active &&
					   decoded.season <
						   decoded.ending_finale.ends_season) {return {false, "save contains invalid campaign balance settings"}}
	food := decoded.material_economy.food_shortage_episode
	if decoded.material_economy.next_food_shortage_episode_id == 0 ||
	   decoded.material_economy.food_shortage_response_pending != food.active ||
	   food.active &&
		   (food.id == 0 ||
				   food.origin_event == 0 ||
				   food.resolution_event != 0 ||
				   food.opened_season > decoded.season) ||
	   !food.active &&
		   food.resolution_event != 0 &&
		   food.response ==
			   .None {return {false, "save contains an invalid food shortage episode"}}
	fleet :=
		decoded.material_economy.fleet; if fleet.stock.food < 0 || fleet.stock.raw_materials < 0 || fleet.stock.manufactured_goods < 0 || fleet.stock.equipment < 0 || fleet.stock.propellant < 0 || fleet.stock.supplies < 0 || fleet.stock.services < 0 || fleet.maintenance_debt < 0 || fleet.trade.active && (settlement_index(decoded, fleet.trade.supplier) < 0 || fleet.trade.route == 0) {return {false, "save contains an invalid fleet economy ledger"}}
	nav := &decoded.fleet_navigation
	if !nav.initialized ||
	   nav.system_index < 0 ||
	   decoded.galaxy == nil ||
	   nav.system_index >= decoded.galaxy.detailed_system_count ||
	   nav.protected_reserve_fraction <= 0 ||
	   nav.protected_reserve_fraction >= 1 ||
	   nav.deposit_count < 0 ||
	   nav.deposit_count > MAX_RESOURCE_DEPOSITS ||
	   nav.phase == .Transfer != nav.transfer.active ||
	   nav.phase == .Harvesting != nav.harvest.active {
		return {false, "save contains invalid fleet navigation state"}
	}
	for ship in decoded.ships[:decoded.ship_count] {
		if !(ship.propellant_capacity_kt >= 0) ||
		   !(ship.propellant_kt >= 0) ||
		   ship.propellant_kt > ship.propellant_capacity_kt + 1e-6 ||
		   !(ship.drive_exhaust_velocity_km_s > 0) ||
		   !(ship.drive_thrust_kilonewtons > 0) {
			return {false, "save contains invalid ship propulsion state"}
		}
	}
	for deposit in nav.deposits[:nav.deposit_count] {
		if !(deposit.initial_propellant_kt >= 0) ||
		   !(deposit.remaining_propellant_kt >= 0) ||
		   deposit.remaining_propellant_kt > deposit.initial_propellant_kt + 1e-6 ||
		   deposit.initial_feedstock < 0 ||
		   deposit.remaining_feedstock < 0 ||
		   deposit.remaining_feedstock > deposit.initial_feedstock ||
		   int(deposit.intel) < int(Resource_Intel.Catalogued) ||
		   int(deposit.intel) > int(Resource_Intel.Surveyed) ||
		   !system_ref_valid(
				   &decoded.galaxy.detailed_systems[nav.system_index].system,
				   deposit.body,
			   ) {
			return {false, "save contains invalid propellant deposit state"}
		}
	}
	m := decoded.passage.manifest; manifest_total := Fleet_Stock {
		food               = m.consumed.food + m.recovered.food + m.lost.food,
		raw_materials      = m.consumed.raw_materials + m.recovered.raw_materials + m.lost.raw_materials,
		manufactured_goods = m.consumed.manufactured_goods + m.recovered.manufactured_goods + m.lost.manufactured_goods,
		equipment          = m.consumed.equipment + m.recovered.equipment + m.lost.equipment,
		propellant         = m.consumed.propellant + m.recovered.propellant + m.lost.propellant,
		supplies           = m.consumed.supplies + m.recovered.supplies + m.lost.supplies,
		services           = m.consumed.services + m.recovered.services + m.lost.services,
	}; if !fleet_stock_can_spend(m.allocated, manifest_total) ||
	   !m.settled &&
		   (m.recovered != {} ||
				   m.lost != {}) {return {false, "save contains an invalid Passage manifest"}}
	if decoded.ship_count < 0 ||
	   decoded.ship_count > MAX_SHIPS ||
	   decoded.community_count < 0 ||
	   decoded.community_count > MAX_COMMUNITIES ||
	   decoded.settlement_count < 0 ||
	   decoded.settlement_count > MAX_SETTLEMENTS ||
	   decoded.settlement_relationship_count < 0 ||
	   decoded.settlement_relationship_count > MAX_SETTLEMENT_RELATIONSHIPS ||
	   decoded.event_count < 0 ||
	   decoded.event_count > MAX_EVENTS ||
	   decoded.archived_era_count < 0 ||
	   decoded.archived_era_count > MAX_ARCHIVED_ERAS ||
	   decoded.archived_epoch_count < 0 ||
	   decoded.archived_epoch_count > MAX_ARCHIVED_EPOCHS ||
	   decoded.service_era_count < 0 ||
	   decoded.service_era_count > MAX_SERVICE_ERAS ||
	   decoded.history_hook_count < 0 ||
	   decoded.history_hook_count > MAX_HISTORY_HOOKS ||
	   decoded.relationship_count < 0 ||
	   decoded.relationship_count > MAX_RELATIONSHIPS ||
	   decoded.ship_relationship_count < 0 ||
	   decoded.ship_relationship_count > MAX_SHIP_RELATIONSHIPS ||
	   decoded.institution_ship_relationship_count < 0 ||
	   decoded.institution_ship_relationship_count > MAX_INSTITUTION_SHIP_RELATIONSHIPS ||
	   decoded.community_institution_relationship_count < 0 ||
	   decoded.community_institution_relationship_count >
		   MAX_COMMUNITY_INSTITUTION_RELATIONSHIPS ||
	   decoded.institution_relationship_count < 0 ||
	   decoded.institution_relationship_count > MAX_INSTITUTION_RELATIONSHIPS ||
	   decoded.historical_figure_count < 0 ||
	   decoded.historical_figure_count > MAX_HISTORICAL_FIGURES ||
	   decoded.captain_relationship_count < 0 ||
	   decoded.captain_relationship_count > MAX_CAPTAIN_RELATIONSHIPS ||
	   decoded.captain_obligation_count < 0 ||
	   decoded.captain_obligation_count > MAX_CAPTAIN_OBLIGATIONS ||
	   decoded.ending_evidence_count < 0 ||
	   decoded.ending_evidence_count > MAX_ENDING_EVIDENCE ||
	   decoded.front_count < 0 ||
	   decoded.front_count > MAX_ACTIVE_FRONTS ||
	   decoded.future_front_count < 0 ||
	   decoded.future_front_count >
		   MAX_FUTURE_FRONTS {return {false, "save contains invalid collection counts"}}
	return {true, ""}
}

@(optimization_mode = "none")
campaign_save_validate_galaxy :: proc(decoded: ^Campaign) -> Save_Decode_Result {
	if decoded.galaxy == nil ||
	   decoded.galaxy.seed != (decoded.initial_seed ~ CAMPAIGN_GALAXY_SEED_SALT) ||
	   decoded.galaxy.neighborhood_count <= 0 ||
	   decoded.candidate_home_count < 0 ||
	   decoded.candidate_home_count > MAX_CANDIDATE_HOMES ||
	   decoded.candidate_celebration_cursor < 0 ||
	   decoded.candidate_celebration_cursor > decoded.candidate_home_count ||
	   decoded.candidate_home_known != (decoded.candidate_home_count > 0) ||
	   decoded.world_survey_count < 0 ||
	   decoded.world_survey_count >
		   MAX_WORLD_SURVEYS {return {false, "save contains invalid authoritative galaxy data"}}
	for survey in decoded.world_surveys[:decoded.world_survey_count] do if survey.system_index < 0 || int(survey.system_index) >= int(decoded.galaxy.detailed_system_count) || survey.reference.valid && !celestial_reference_valid(decoded, survey.reference) {return {false, "save contains an invalid world survey record"}}
	for candidate in decoded.candidate_homes[:decoded.candidate_home_count] do if !celestial_reference_valid(decoded, candidate.reference) || !candidate_world_selectable(candidate.profile) {return {false, "save contains an invalid candidate world reference"}}
	for contact, i in decoded.habitable_contacts {
		if contact.id == 0 ||
		   contact.neighborhood_index < 0 ||
		   contact.neighborhood_index >= decoded.galaxy.neighborhood_count ||
		   contact.distance_pc < 0 ||
		   contact.distance_pc > HABITABLE_OBSERVATION_RADIUS_PC + 1e-8 ||
		   !contact.transmitted ||
		   contact.materialized_system_index >= decoded.galaxy.detailed_system_count {
			return {false, "save contains an invalid habitable-world contact"}
		}
		for prior in decoded.habitable_contacts[:i] do if prior.id == contact.id {
			return {false, "save contains duplicate habitable-world contacts"}
		}
	}
	goal := decoded.long_term_navigation_goal
	if goal.active {
		at := habitable_contact_index(decoded.habitable_contacts[:], goal.contact_id)
		if at < 0 ||
		   decoded.habitable_contacts[at].neighborhood_index != goal.target_neighborhood ||
		   goal.origin_neighborhood < 0 ||
		   goal.origin_neighborhood >= decoded.galaxy.neighborhood_count {
			return {false, "save contains an invalid long-term navigation goal"}
		}
	}
	for settlement in decoded.settlements[:decoded.settlement_count] do if settlement.active && !celestial_reference_valid(decoded, settlement.celestial) {return {false, "save contains a settlement without a discovered world reference"}}
	return {true, ""}
}

@(optimization_mode = "none")
campaign_save_validate_combat_and_politics :: proc(decoded: ^Campaign) -> Save_Decode_Result {
	if decoded.combat_deployment_count < 0 ||
	   decoded.combat_deployment_count > MAX_SHIPS ||
	   decoded.combat_deployment_active != (decoded.combat_deployment_count > 0) ||
	   decoded.combat_deployment_propellant_cost <
		   0 {return {false, "save contains an invalid combat deployment"}}
	if int(decoded.combat_fire_control_preference) < 0 ||
	   int(decoded.combat_fire_control_preference) >
		   int(
			   Combat_Fire_Control.Confirm_Engagements,
		   ) {return {false, "save contains an invalid fleet fire-control policy"}}
	ce := &decoded.council; if ce.position_count < 0 || ce.position_count > MAX_COUNCIL_POSITIONS || ce.setbacks < 0 || ce.setbacks > 3 || ce.success_chance < 0 || ce.advance_chance < 0 || ce.debate_chance < 0 || ce.stall_chance < 0 || ce.active && ce.phase == .None || ce.exception_pending && !ce.active {return {false, "save contains an invalid council enactment"}}
	if !validate_dynamic_politics(
		decoded,
	) {return {false, "save contains invalid dynamic politics"}}
	if !validate_public_politics(decoded) {return {false, "save contains invalid public politics"}}
	if !validate_narrative_director(
		decoded,
	) {return {false, "save contains an invalid narrative director"}}
	for id, i in decoded.combat_deployment_ships[:decoded.combat_deployment_count] {if ship_index(decoded, id) < 0 || decoded.combat_deployment_groups[i] < 0 || decoded.combat_deployment_groups[i] >= COMBAT_GROUP_COUNT {return {false, "save contains an invalid combat manifest"}}; for prior in decoded.combat_deployment_ships[:i] do if prior == id {return {false, "save contains duplicate combat ships"}}}
	if decoded.combat_deployment_active {for doctrine in decoded.combat_deployment_doctrines do if int(doctrine) < 0 || int(doctrine) > int(Combat_Doctrine.Last_Stand) {return {false, "save contains an invalid combat doctrine"}}}
	return {true, ""}
}

@(optimization_mode = "none")
campaign_save_validate_fleet_history :: proc(decoded: ^Campaign) -> Save_Decode_Result {
	for era, i in decoded.archived_eras[:decoded.archived_era_count] {if era.id != u32(i + 1) || era.first_sequence == 0 || era.last_sequence < era.first_sequence || era.last_season < era.first_season || era.defining_precedent_count < 0 || era.defining_precedent_count > len(era.defining_precedents) || era.detail == "" {return {false, "save contains an invalid archived era"}}}
	for epoch, i in decoded.archived_epochs[:decoded.archived_epoch_count] {if epoch.id != u32(i + 1) || epoch.first_sequence == 0 || epoch.last_sequence < epoch.first_sequence || epoch.last_season < epoch.first_season || epoch.era_count < 2 || epoch.defining_precedent_count < 0 || epoch.defining_precedent_count > len(epoch.defining_precedents) || epoch.detail == "" {return {false, "save contains an invalid archived epoch"}}}
	for era in decoded.service_eras[:decoded.service_era_count] do if era.ship == 0 || ship_index(decoded, era.ship) < 0 || era.first_sequence == 0 || era.last_sequence < era.first_sequence || era.last_season < era.first_season || era.name == "" {return {false, "save contains an invalid ship service era"}}
	if decoded.situation_queue_count < 0 ||
	   decoded.situation_queue_count > MAX_SITUATION_QUEUE ||
	   decoded.capacities.compute.total <= 0 ||
	   decoded.capacities.compute.reserved < 0 ||
	   decoded.capacities.compute.damaged < 0 ||
	   decoded.capacities.compute.reserved + decoded.capacities.compute.damaged >
		   decoded.capacities.compute.total ||
	   decoded.capacities.manpower.total <= 0 ||
	   decoded.capacities.manpower.reserved < 0 ||
	   decoded.capacities.manpower.damaged < 0 ||
	   decoded.capacities.manpower.reserved + decoded.capacities.manpower.damaged >
		   decoded.capacities.manpower.total ||
	   decoded.capacities.raw_materials.total <= 0 ||
	   decoded.capacities.raw_materials.reserved < 0 ||
	   decoded.capacities.raw_materials.damaged < 0 ||
	   decoded.capacities.raw_materials.reserved + decoded.capacities.raw_materials.damaged >
		   decoded.capacities.raw_materials.total {return {false, "save contains invalid fleet capacities or situation queue"}}
	if !validate_saved_situation(
		decoded,
		decoded.current_situation,
	) {return {false, "save contains an invalid current fleet situation"}}
	for situation in decoded.situation_queue[:decoded.situation_queue_count] do if !validate_saved_situation(decoded, situation) {return {false, "save contains an invalid queued fleet situation"}}
	for commitment in decoded.capacity_commitments do if commitment.active {
		if commitment.situation_id == 0 || commitment.origin_event == 0 || event_index_by_sequence(decoded, commitment.origin_event) < 0 || commitment.release_season < decoded.season || commitment.compute < 0 || commitment.manpower < 0 || commitment.raw_materials < 0 || commitment.source_ship_count < 0 || commitment.source_ship_count > len(commitment.source_ships) {return {false, "save contains an invalid capacity commitment"}}
		for i in 0 ..< commitment.source_ship_count do if ship_index(decoded, commitment.source_ships[i]) < 0 {return {false, "save commitment names an unknown ship"}}
	}
	return {true, ""}
}

@(optimization_mode = "none")
campaign_save_validate_passage_and_dark :: proc(decoded: ^Campaign) -> Save_Decode_Result {
	dark := &decoded.outer_dark
	if dark.semantic_tags ==
	   Semantic_Tags(0) {return {false, "save contains an invalid Outer Dark record"}}
	continuum := &dark.continuum
	if continuum.seed == 0 ||
	   continuum.semantic_tags == Semantic_Tags(0) ||
	   continuum.galaxy_neighborhood_count <= 0 ||
	   continuum.anchor_door_id == 0 ||
	   continuum.anchor_neighborhood < 0 ||
	   continuum.loaded_chunk_count < 0 ||
	   continuum.loaded_chunk_count > MAX_DARK_LOADED_CHUNKS ||
	   continuum.archived_chunk_count < 0 ||
	   continuum.archived_chunk_count != len(continuum.archived_chunks) ||
	   continuum.door_count < 0 ||
	   continuum.door_count > MAX_DARK_DOORS ||
	   continuum.organism_count < 0 ||
	   continuum.organism_count > MAX_DARK_ORGANISMS ||
	   continuum.field_count < 0 ||
	   continuum.field_count > MAX_DARK_FIELD_CELLS ||
	   continuum.simulation_time < 0 ||
	   continuum.accumulator < 0 {return {false, "save contains an invalid Dark continuum"}}
	for door in continuum.doors[:continuum.door_count] do if door.id == 0 || door.radius <= 0 || door.galaxy_neighborhood < 0 || door.semantic_tags == Semantic_Tags(0) {return {false, "save contains an invalid Dark door"}}
	for organism in continuum.organisms[:continuum.organism_count] do if organism.id == 0 || organism.radius <= 0 || organism.energy < 0 || organism.energy > 1 || organism.condition < 0 || organism.condition > 1 || !organism.alive && organism.death_tick == 0 || organism.injury_mask_count < 0 || organism.injury_mask_count > MAX_DARK_INJURY_MASKS || organism.semantic_tags == Semantic_Tags(0) {return {false, "save contains an invalid Dark organism"}}
	for field in continuum.fields[:continuum.field_count] do if field.id == 0 || field.radius <= 0 || field.semantic_tags == Semantic_Tags(0) {return {false, "save contains an invalid Dark life field"}}
	for &archived in continuum.archived_chunks[:continuum.archived_chunk_count] {
		if archived.door_count < 0 ||
		   archived.door_count > len(archived.doors) ||
		   archived.organism_count < 0 ||
		   archived.organism_count != len(archived.organisms) ||
		   archived.field_count < 0 ||
		   archived.field_count >
			   len(
				   archived.fields,
			   ) {return {false, "save contains an invalid archived Dark chunk"}}
		for door in archived.doors[:archived.door_count] do if door.id == 0 || door.radius <= 0 || door.galaxy_neighborhood < 0 || door.semantic_tags == Semantic_Tags(0) {return {false, "save contains an invalid archived Dark door"}}
		for organism in archived.organisms[:archived.organism_count] do if organism.id == 0 || organism.radius <= 0 || organism.energy < 0 || organism.energy > 1 || organism.condition < 0 || organism.condition > 1 || !organism.alive && organism.death_tick == 0 || organism.injury_mask_count < 0 || organism.injury_mask_count > MAX_DARK_INJURY_MASKS || organism.semantic_tags == Semantic_Tags(0) {return {false, "save contains an invalid archived Dark organism"}}
		for field in archived.fields[:archived.field_count] do if field.id == 0 || field.radius <= 0 || field.semantic_tags == Semantic_Tags(0) {return {false, "save contains an invalid archived Dark life field"}}
	}
	p := &decoded.passage; if p.semantic_tags == Semantic_Tags(0) || p.contract.semantic_tags == Semantic_Tags(0) || p.local_atlas_count < 0 || p.local_atlas_count > MAX_LOCAL_DOOR_DISCOVERIES || p.local_observation_count < 0 || p.local_observation_count > MAX_LOCAL_DARK_OBSERVATIONS {return {false, "save contains an invalid Dark expedition record"}}
	for discovery in p.local_atlas[:p.local_atlas_count] do if discovery.door_id == 0 || discovery.galaxy_neighborhood < 0 {return {false, "save contains an invalid local correspondence record"}}
	for observation in p.local_observations[:p.local_observation_count] do if observation.organism_id == 0 || observation.first_seen_tick > observation.last_seen_tick || observation.manifestation_count < 1 || observation.reported_manifestation_count < 0 || observation.reported_manifestation_count > observation.manifestation_count || observation.confidence < 0 || observation.confidence > 1 {return {false, "save contains an invalid local Dark organism observation"}}
	for contact, i in p.local_habitable_contacts {
		if contact.id == 0 ||
		   contact.neighborhood_index < 0 ||
		   contact.neighborhood_index >= decoded.galaxy.neighborhood_count ||
		   contact.distance_pc < 0 ||
		   contact.distance_pc > HABITABLE_OBSERVATION_RADIUS_PC + 1e-8 {
			return {false, "save contains an invalid local habitable-world contact"}
		}
		for prior in p.local_habitable_contacts[:i] do if prior.id == contact.id {
			return {false, "save contains duplicate local habitable-world contacts"}
		}
	}
	if decoded.dark_strategy_record_count < 0 ||
	   decoded.dark_strategy_record_count != len(decoded.dark_strategy_records) ||
	   decoded.dark_unresolved_voyage_count < 0 ||
	   decoded.dark_unresolved_voyage_count != len(decoded.dark_unresolved_voyages) ||
	   decoded.dark_relay_count < 0 ||
	   decoded.dark_relay_count !=
		   len(
			   decoded.dark_relays,
		   ) {return {false, "save contains invalid Dark institutional records"}}
	for discovery, i in decoded.dark_fleet_atlas {if discovery.door_id == 0 || discovery.galaxy_neighborhood < 0 || !discovery.transmitted {return {false, "save contains an invalid fleet correspondence atlas"}}; for prior in decoded.dark_fleet_atlas[:i] do if prior.door_id == discovery.door_id {return {false, "save contains duplicate fleet correspondence records"}}}
	for observation, i in decoded.dark_organism_observations {if observation.organism_id == 0 || observation.first_seen_tick > observation.last_seen_tick || observation.manifestation_count < 1 || observation.confidence < 0 || observation.confidence > 1 {return {false, "save contains an invalid Dark organism observation"}}; for prior in decoded.dark_organism_observations[:i] do if prior.organism_id == observation.organism_id {return {false, "save contains duplicate Dark organism observations"}}}
	for relay in decoded.dark_relays[:decoded.dark_relay_count] do if relay.id == 0 || relay.galaxy_neighborhood < 0 || relay.condition < 0 || relay.condition > 1 || relay.semantic_tags == Semantic_Tags(0) {return {false, "save contains an invalid Dark relay"}}
	if !validate_stranded_passage_groups(
		decoded,
	) {return {false, "save contains an invalid stranded expedition record"}}
	for front in decoded.fronts[:decoded.front_count] do if front.id == 0 || front.originating_event_count < 1 || front.originating_event_count > MAX_EVENT_CAUSES || front.semantic_tags == Semantic_Tags(0) || front.last_change_event == 0 {return {false, "save contains an invalid historical front"}}
	for proposal in decoded.future_fronts[:decoded.future_front_count] do if proposal.source_event == 0 || proposal.semantic_tags == Semantic_Tags(0) {return {false, "save contains an invalid future front"}}
	return {true, ""}
}

@(optimization_mode = "none")
campaign_save_validate_society_and_history :: proc(decoded: ^Campaign) -> Save_Decode_Result {
	// Resolve zero-valued construction sentinels before validation. This also
	// gives hand-authored test fleets the same persistent identity as generated fleets.
	for &ship in decoded.ships[:decoded.ship_count] {if ship.weapon_package == .Unspecified do ship.weapon_package = ship_weapon_package_for(ship.id, ship.hull_archetype, ship.operational_role); if ship.defense_packages == {} do ship.defense_packages = ship_defense_packages_for(ship.id, ship.hull_archetype, ship.operational_role)}
	for ship, i in decoded.ships[:decoded.ship_count] {
		if int(ship.dark_contact_procedure) < 0 ||
		   int(ship.dark_contact_procedure) >
			   int(
				   Dark_Contact_Procedure.Shear_Evasion,
			   ) {return {false, "save contains an invalid Dark contact procedure"}}
		if ship.dark_field_scars < 0 ||
		   ship.dark_field_scars > 12 {return {false, "save contains invalid Dark field scars"}}
		if ship.id == 0 ||
		   ship.hull_archetype == .Unspecified ||
		   int(ship.hull_archetype) > SHIP_HULL_ARCHETYPE_COUNT ||
		   ship_hull_archetype_class(ship.hull_archetype) != ship.hull_class ||
		   ship.operational_role == .Unspecified ||
		   !ship_operational_role_fits_hull(ship.operational_role, ship.hull_archetype) ||
		   ship.weapon_package == .Unspecified ||
		   int(ship.weapon_package) > int(Ship_Weapon_Package.Heavy_Torpedoes) ||
		   ship.defense_packages == {} ||
		   ship.bow_profile > 3 ||
		   ship.utility_hardpoint > 9 ||
		   ship.wing_sweep > 3 ||
		   ship.wing_stance > 3 ||
		   ship.keel_profile > 3 ||
		   ship.mission_profile > 3 ||
		   ship.drive_layout > 3 ||
		   ship.drive_setback > 3 ||
		   ship.greebly_density > 5 ||
		   ship.semantic_tags == Semantic_Tags(0) ||
		   ship.history_record_count < 0 ||
		   ship.history_record_count > MAX_SHIP_HISTORY ||
		   ship.memory_count < 0 ||
		   ship.memory_count > MAX_SHIP_MEMORIES ||
		   ship.archived_memory_count < 0 ||
		   ship.archived_memory_count > 0 &&
			   (ship.archived_memory_first == 0 ||
					   ship.archived_memory_last < ship.archived_memory_first ||
					   ship.archived_memory_tags == Semantic_Tags(0)) ||
		   ship.promises_upheld < 0 ||
		   ship.promises_broken < 0 ||
		   ship.promises_transformed <
			   0 {return {false, "save contains an invalid ship identity, armament, or history"}}
		if ship.captain !=
		   0 {captain_at := historical_figure_index(decoded, ship.captain); if captain_at < 0 || decoded.historical_figures[captain_at].ship != ship.id {return {false, "save contains an invalid ship captain"}}}
		for memory_index in 0 ..< ship.memory_count {memory := ship.memories[memory_index]; event_at := event_index_by_sequence(decoded, memory.event_sequence); if event_at < 0 || memory.semantic_tags == Semantic_Tags(0) || memory.other_ship != 0 && ship_index(decoded, memory.other_ship) < 0 || memory.community != 0 && community_index(decoded, memory.community) < 0 || memory.figure != 0 && historical_figure_index(decoded, memory.figure) < 0 || memory.settlement != 0 && settlement_index(decoded, memory.settlement) < 0 {return {false, "save contains an invalid ship memory"}}; if memory.semantic_tags != semantic_add(decoded.events[event_at].semantic_tags, .Memory) {return {false, "save contains inconsistent ship memory tags"}}}
		for prior in decoded.ships[:i] do if prior.id == ship.id {return {false, "save contains duplicate ship identities"}}
	}
	for community in decoded.communities[:decoded.community_count] do if community.id == 0 || community.semantic_tags == Semantic_Tags(0) || community.grievance < 0 || community.grievance > 10 || community.petitions_honored < 0 || community.petitions_neglected < 0 {return {false, "save contains invalid community memory"}}
	for attribute in decoded.attributes do if attribute.semantic_tags == Semantic_Tags(0) {return {false, "save contains an untagged civilization attribute"}}
	for institution in decoded.institutions do if institution.semantic_tags == Semantic_Tags(0) {return {false, "save contains an untagged institution"}}
	for archive, i in decoded.archives {
		if archive.id == 0 ||
		   archive.semantic_tags ==
			   Semantic_Tags(0) {return {false, "save contains an invalid archive identity"}}
		for prior in decoded.archives[:i] do if prior.id == archive.id {return {false, "save contains duplicate archive identities"}}
	}
	for settlement, i in decoded.settlements[:decoded.settlement_count] {
		if settlement.id == 0 ||
		   settlement.semantic_tags ==
			   Semantic_Tags(0) {return {false, "save contains an invalid settlement identity"}}
		if settlement.participating_ship_count < 0 ||
		   settlement.participating_ship_count > MAX_SHIPS ||
		   settlement.participating_community_count < 0 ||
		   settlement.participating_community_count > MAX_COMMUNITIES ||
		   settlement.initial_grievance < 0 ||
		   settlement.initial_grievance > 10 ||
		   settlement.orbital_refuge !=
			   (settlement.orbital_refuge_capacity >
					   0) {return {false, "save contains invalid settlement founding politics"}}
		if settlement.archive_id != 0 &&
		   archive_index(decoded, settlement.archive_id) <
			   0 {return {false, "save contains an unknown settlement archive"}}
		for prior in decoded.settlements[:i] do if prior.id == settlement.id {return {false, "save contains duplicate settlement identities"}}
	}
	proposal := &decoded.settlement_proposal
	if proposal.assessment_count < 0 ||
	   proposal.assessment_count >
		   MAX_SHIPS {return {false, "save contains an invalid settlement proposal"}}
	for assessment in proposal.assessments[:proposal.assessment_count] {if assessment.ship != 0 && ship_index(decoded, assessment.ship) < 0 || assessment.consent.support < 0 || assessment.consent.support > 100 || assessment.consent.opposition < 0 || assessment.consent.opposition > 100 || assessment.consent.participation < 0 || assessment.consent.participation > 100 || assessment.consent.confidence < 0 || assessment.consent.confidence > 100 || assessment.consent.reason_count < 0 || assessment.consent.reason_count > MAX_PROPOSAL_REASONS {return {false, "save contains an invalid ship settlement mandate"}}}
	for relationship, i in decoded.settlement_relationships[:decoded.settlement_relationship_count] {if relationship.semantic_tags == Semantic_Tags(0) || relationship.settlement_a == 0 || relationship.settlement_b == 0 || relationship.settlement_a >= relationship.settlement_b || relationship.strength < 1 || settlement_index(decoded, relationship.settlement_a) < 0 || settlement_index(decoded, relationship.settlement_b) < 0 || event_index_by_sequence(decoded, relationship.origin_event) < 0 || event_index_by_sequence(decoded, relationship.last_event) < 0 {return {false, "save contains an invalid settlement relationship"}}; for prior in decoded.settlement_relationships[:i] do if prior.settlement_a == relationship.settlement_a && prior.settlement_b == relationship.settlement_b {return {false, "save contains duplicate settlement relationships"}}}
	for relationship, i in decoded.ship_relationships[:decoded.ship_relationship_count] {
		if relationship.semantic_tags == Semantic_Tags(0) ||
		   relationship.ship_a == 0 ||
		   relationship.ship_b == 0 ||
		   relationship.ship_a == relationship.ship_b ||
		   ship_index(decoded, relationship.ship_a) < 0 ||
		   ship_index(decoded, relationship.ship_b) <
			   0 {return {false, "save contains an invalid ship relationship"}}
		for prior in decoded.ship_relationships[:i] do if prior.ship_a == relationship.ship_a && prior.ship_b == relationship.ship_b {return {false, "save contains duplicate ship relationships"}}
	}
	for relationship, i in decoded.institution_ship_relationships[:decoded.institution_ship_relationship_count] {
		if relationship.semantic_tags == Semantic_Tags(0) ||
		   relationship.institution == 0 ||
		   relationship.ship == 0 ||
		   relationship.strength < -3 ||
		   relationship.strength > 3 ||
		   institution_index(decoded, relationship.institution) < 0 ||
		   ship_index(decoded, relationship.ship) < 0 ||
		   relationship.origin_event != 0 &&
			   event_index_by_sequence(decoded, relationship.origin_event) < 0 ||
		   relationship.last_event != 0 &&
			   event_index_by_sequence(decoded, relationship.last_event) < 0 ||
		   relationship.precedent_event != 0 &&
			   event_index_by_sequence(decoded, relationship.precedent_event) <
				   0 {return {false, "save contains an invalid institution-ship relationship"}}
		for prior in decoded.institution_ship_relationships[:i] do if prior.institution == relationship.institution && prior.ship == relationship.ship {return {false, "save contains duplicate institution-ship relationships"}}
	}
	for relationship, i in decoded.community_institution_relationships[:decoded.community_institution_relationship_count] {
		if relationship.semantic_tags == Semantic_Tags(0) ||
		   relationship.community == 0 ||
		   relationship.institution == 0 ||
		   relationship.strength < -3 ||
		   relationship.strength > 3 ||
		   community_index(decoded, relationship.community) < 0 ||
		   institution_index(decoded, relationship.institution) < 0 ||
		   relationship.origin_event != 0 &&
			   event_index_by_sequence(decoded, relationship.origin_event) < 0 ||
		   relationship.last_event != 0 &&
			   event_index_by_sequence(decoded, relationship.last_event) <
				   0 {return {false, "save contains an invalid community-institution relationship"}}
		for prior in decoded.community_institution_relationships[:i] do if prior.community == relationship.community && prior.institution == relationship.institution {return {false, "save contains duplicate community-institution relationships"}}
	}
	for relationship, i in decoded.institution_relationships[:decoded.institution_relationship_count] {
		if relationship.semantic_tags == Semantic_Tags(0) ||
		   relationship.institution_a == 0 ||
		   relationship.institution_b == 0 ||
		   relationship.institution_a >= relationship.institution_b ||
		   relationship.strength < -3 ||
		   relationship.strength > 3 ||
		   institution_index(decoded, relationship.institution_a) < 0 ||
		   institution_index(decoded, relationship.institution_b) < 0 ||
		   relationship.origin_event != 0 &&
			   event_index_by_sequence(decoded, relationship.origin_event) < 0 ||
		   relationship.last_event != 0 &&
			   event_index_by_sequence(decoded, relationship.last_event) <
				   0 {return {false, "save contains an invalid institution relationship"}}
		for prior in decoded.institution_relationships[:i] do if prior.institution_a == relationship.institution_a && prior.institution_b == relationship.institution_b {return {false, "save contains duplicate institution relationships"}}
	}
	for figure, i in decoded.historical_figures[:decoded.historical_figure_count] {
		if figure.id == 0 ||
		   figure.semantic_tags == Semantic_Tags(0) ||
		   figure.age_years < 0 ||
		   figure.passage_actions <
			   0 {return {false, "save contains an invalid historical figure"}}
		if figure.captain_profile.initialized {p := figure.captain_profile; if p.mark_count < 0 || p.mark_count > MAX_CAPTAIN_MARKS {return {false, "save contains an invalid captain profile"}}; for facet in p.facets do if facet > 4 {return {false, "save contains an invalid captain facet"}}; for mark in p.marks[:p.mark_count] do if mark.source_event == 0 || !event_reference_exists(decoded, mark.source_event) || mark.intensity < -4 || mark.intensity > 4 {return {false, "save contains an invalid captain mark"}}}
		if figure.institution != 0 &&
		   institution_index(decoded, figure.institution) <
			   0 {return {false, "save contains an unknown figure institution"}}
		if figure.predecessor != 0 &&
		   (historical_figure_index(decoded, figure.predecessor) < 0 ||
				   figure.predecessor ==
					   figure.id) {return {false, "save contains an invalid figure succession"}}
		for prior in decoded.historical_figures[:i] do if prior.id == figure.id {return {false, "save contains duplicate historical figures"}}
	}
	for relationship, i in decoded.captain_relationships[:decoded.captain_relationship_count] {if historical_figure_index(decoded, relationship.captain) < 0 || !captain_target_exists(decoded, relationship.target_kind, relationship.target_id) || relationship.origin_event == 0 || !event_reference_exists(decoded, relationship.origin_event) || relationship.last_event == 0 || !event_reference_exists(decoded, relationship.last_event) || relationship.trust < -4 || relationship.trust > 4 || relationship.respect < -4 || relationship.respect > 4 || relationship.attachment < -4 || relationship.attachment > 4 || relationship.obligation < -4 || relationship.obligation > 4 || relationship.rivalry < -4 || relationship.rivalry > 4 {return {false, "save contains an invalid captain relationship"}}; for prior in decoded.captain_relationships[:i] do if prior.captain == relationship.captain && prior.target_kind == relationship.target_kind && prior.target_id == relationship.target_id {return {false, "save contains a duplicate captain relationship"}}}
	for obligation, i in decoded.captain_obligations[:decoded.captain_obligation_count] {if obligation.id != u32(i + 1) || historical_figure_index(decoded, obligation.captain) < 0 || ship_index(decoded, obligation.ship) < 0 || obligation.issued_event == 0 || !event_reference_exists(decoded, obligation.issued_event) || obligation.stakes < 1 || obligation.stakes > 4 || obligation.status != .Active && (obligation.resolved_event == 0 || !event_reference_exists(decoded, obligation.resolved_event)) {return {false, "save contains an invalid captain obligation"}}}
	for relationship in decoded.relationships[:decoded.relationship_count] do if relationship.semantic_tags == Semantic_Tags(0) {return {false, "save contains an untagged community relationship"}}
	for hook in decoded.history_hooks[:decoded.history_hook_count] do if hook.semantic_tags == Semantic_Tags(0) {return {false, "save contains an untagged history hook"}}
	if decoded.precedent_count < 0 ||
	   decoded.precedent_count > MAX_PRECEDENTS ||
	   decoded.precedent_case_count < 0 ||
	   decoded.precedent_case_count >
		   MAX_PRECEDENT_CASES {return {false, "save contains invalid law collection counts"}}
	for value, i in decoded.values {if int(value.kind) < 0 || int(value.kind) >= 8 || i > 0 && value.kind == decoded.values[0].kind || value.claimed_event == 0 || !event_reference_exists(decoded, value.claimed_event) || value.last_test_event != 0 && !event_reference_exists(decoded, value.last_test_event) || value.renounced_event != 0 && !event_reference_exists(decoded, value.renounced_event) || value.tests < 0 || value.consistent_tests < 0 || value.contradictions < 0 || value.consistent_tests + value.contradictions > value.tests || value.status != derived_value_status(value) || value.enacted_precedent != 0 && precedent_index_by_id(decoded, value.enacted_precedent) < 0 {return {false, "save contains an invalid civilization value"}}}
	max_precedent_id: u32
	allowed_scope := u32((u64(1) << u64(int(Precedent_Domain.Fleet_Continuity) + 1)) - 2)
	for precedent, i in decoded.precedents[:decoded.precedent_count] {if precedent.id == 0 || int(precedent.kind) < 0 || int(precedent.kind) > int(Precedent_Kind.Continuity_Of_The_Fleet) || int(precedent.status) < 0 || int(precedent.status) > int(Precedent_Status.Superseded) || int(precedent.interpretation) < 0 || int(precedent.interpretation) > int(Precedent_Interpretation.Emergency_Adaptation_Descendant_Review) || !precedent_interpretation_valid(precedent.kind, precedent.interpretation) || precedent.semantic_tags == Semantic_Tags(0) || u32(precedent.scope) == 0 || (u32(precedent.scope) &~ allowed_scope) != 0 || precedent.source_decision == 0 || !event_reference_exists(decoded, precedent.source_decision) || precedent.event_sequence == 0 || !event_reference_exists(decoded, precedent.event_sequence) || precedent.status == .Superseded != (precedent.superseded_by != 0) || precedent.superseded_by != 0 && (precedent_index_by_id(decoded, precedent.superseded_by) < 0 || precedent.superseded_by == precedent.id) {return {false, "save contains an invalid precedent"}}; if u32(precedent.id) > max_precedent_id do max_precedent_id = u32(precedent.id); for prior in decoded.precedents[:i] do if prior.id == precedent.id {return {false, "save contains duplicate precedent IDs"}}}
	for precedent in decoded.precedents[:decoded.precedent_count] {seen := precedent.id; next := precedent.superseded_by; steps := 0; for next != 0 {steps += 1; if steps > decoded.precedent_count {return {false, "save contains a precedent supersession cycle"}}; at := precedent_index_by_id(decoded, next); if at < 0 do break; next = decoded.precedents[at].superseded_by}; _ = seen}
	if decoded.next_precedent_id <=
	   max_precedent_id {return {false, "save contains an invalid next precedent ID"}}
	max_case_id: u32
	for case_record, i in decoded.precedent_cases[:decoded.precedent_case_count] {if case_record.id == 0 || int(case_record.status) < 0 || int(case_record.status) > int(Precedent_Case_Status.Contested) || precedent_index_by_id(decoded, case_record.primary) < 0 || case_record.secondary != 0 && precedent_index_by_id(decoded, case_record.secondary) < 0 || case_record.source_decision == 0 || !event_reference_exists(decoded, case_record.source_decision) || case_record.contradiction_event == 0 || !event_reference_exists(decoded, case_record.contradiction_event) || case_record.cited_authority_event != 0 && !event_reference_exists(decoded, case_record.cited_authority_event) || case_record.last_event == 0 || !event_reference_exists(decoded, case_record.last_event) || case_record.review_season < 0 {return {false, "save contains an invalid precedent case"}}; if u32(case_record.id) > max_case_id do max_case_id = u32(case_record.id); for prior in decoded.precedent_cases[:i] do if prior.id == case_record.id {return {false, "save contains duplicate precedent case IDs"}}}
	if decoded.precedent_case_count > 0 &&
	   decoded.next_precedent_case_id <=
		   max_case_id {return {false, "save contains an invalid next precedent case ID"}}
	for need in decoded.needs do if need.active || need.resolved || need.detail != "" {if need.semantic_tags == Semantic_Tags(0) || need.opposing_institution != 0 && institution_index(decoded, need.opposing_institution) < 0 {return {false, "save contains an invalid need"}}}
	for project in decoded.projects do if (project.active || project.kind != .None) && project.semantic_tags == Semantic_Tags(0) {return {false, "save contains an untagged project"}}
	for promise in decoded.promises[:decoded.promise_count] do if promise.semantic_tags == Semantic_Tags(0) {return {false, "save contains an untagged promise"}}
	for &event in decoded.events[:decoded.event_count] {
		if event.cause_count < 0 ||
		   event.cause_count >
			   MAX_EVENT_CAUSES {return {false, "save contains an invalid event cause count"}}
		expected := semantic_tags_for_event(
			event.kind,
			event.ship_id,
			event.related_ship_id,
			event.community,
			event.figure_id,
			event.institution_id,
			event.settlement_id,
			event.archive_id,
			event.account_status,
		); if event.account_exposed do expected = semantic_add(expected, .Accountability); if event.cause_count > 0 do expected = semantic_add(expected, .Causality); if event.semantic_tags != expected {return {false, "save contains inconsistent event tags"}}
		for i in 0 ..< event.cause_count {cause := event.causes[i]; if cause.sequence == 0 || cause.sequence == event.sequence || !event_reference_exists(decoded, cause.sequence) || cause.semantic_tags != semantic_tags_for_event_cause(cause.role) {return {false, "save contains an invalid event cause"}}; for prior_index in 0 ..< i {prior := event.causes[prior_index]; if prior.sequence == cause.sequence && prior.role == cause.role {return {false, "save contains duplicate event causes"}}}}
	}
	if decoded.pending_accountability_event != 0 &&
	   event_index_by_sequence(decoded, decoded.pending_accountability_event) <
		   0 {return {false, "save contains an unknown accountability event"}}
	if decoded.completed_aftermath_count < 0 ||
	   decoded.completed_aftermath_count > MAX_COMPLETED_AFTERMATHS ||
	   decoded.social_consequence_count < 0 ||
	   decoded.social_consequence_count > MAX_SOCIAL_CONSEQUENCES {
		return {false, "save contains invalid operation aftermath history"}
	}
	a := &decoded.pending_aftermath
	if a.id != 0 &&
	   (a.layer == .None ||
			   a.ship_count < 0 ||
			   a.ship_count > MAX_AFTERMATH_SHIPS ||
			   a.observation_count < 0 ||
			   a.observation_count > MAX_AFTERMATH_OBSERVATIONS ||
			   a.social_count < 0 ||
			   a.social_count > MAX_AFTERMATH_FACTS ||
			   a.event_count < 0 ||
			   a.event_count > MAX_AFTERMATH_EVENTS) {
		return {false, "save contains an invalid pending operation aftermath"}
	}
	return {true, ""}
}

campaign_save_validate :: proc(decoded: ^Campaign) -> Save_Decode_Result {
	result := campaign_save_validate_core(decoded)
	if !result.ok {campaign_destroy_heap(decoded); return result}
	result = campaign_save_validate_galaxy(decoded)
	if !result.ok {campaign_destroy_heap(decoded); return result}
	result = campaign_save_validate_combat_and_politics(decoded)
	if !result.ok {campaign_destroy_heap(decoded); return result}
	result = campaign_save_validate_fleet_history(decoded)
	if !result.ok {campaign_destroy_heap(decoded); return result}
	result = campaign_save_validate_passage_and_dark(decoded)
	if !result.ok {campaign_destroy_heap(decoded); return result}
	result = campaign_save_validate_society_and_history(decoded)
	if !result.ok {campaign_destroy_heap(decoded); return result}
	return {true, ""}
}

campaign_deserialize :: proc(data: []u8, out: ^Campaign) -> Save_Decode_Result {
	header := campaign_save_header_validate(data)
	if !header.ok do return header
	decoded, decode := campaign_save_payload_decode(data)
	if !decode.ok do return decode
	validation := campaign_save_validate(decoded)
	if !validation.ok do return validation
	out^ = decoded^
	free(decoded)
	return {true, "campaign restored"}
}
