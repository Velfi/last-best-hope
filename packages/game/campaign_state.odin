package game

import "core:fmt"
import "core:testing"
Campaign :: struct {
	owns_strings:                             bool `json:"-"`,
	format_version:                           u32,
	rules_identity:                           u64,
	initial_seed:                             u64,
	seed:                                     u64,
	rng_state:                                u64,
	rng_sequence:                             u64,
	event_sequence:                           u64,
	length:                                   Chronicle_Length,
	ruleset:                                  Ruleset,
	story_tempo:                              Story_Tempo,
	material_pressure:                        Material_Pressure,
	consequence_severity:                     Consequence_Severity,
	ending_prompt_pending:                    bool,
	ending_finale:                            Ending_Finale,
	ending_quality:                           Ending_Quality,
	sustainable_seasons:                      i32,
	economy_damage_episodes:                  i32,
	economy_loss_decision_pending:            bool,
	economy_loss_candidate:                   Ship_ID,
	loss:                                     Loss_Kind,
	preserved_inheritance:                    Preserved_Inheritance,
	founding_precedent:                       Precedent_Kind,
	founding_decision_event:                  u64,
	season:                                   i32,
	clock:                                    Campaign_Clock,
	fleet_navigation:                         Fleet_Navigation,
	scheduled_work:                           [MAX_SCHEDULED_WORK]Scheduled_Work,
	next_scheduled_work_id:                   u64,
	attention_queue:                          [MAX_ATTENTION_EVENTS]Attention_Event,
	next_attention_id:                        u64,
	galaxy:                                   ^Galaxy `json:"-"`,
	candidate_homes:                          [MAX_CANDIDATE_HOMES]Candidate_Home,
	candidate_home_count:                     int,
	candidate_celebration_cursor:             int,
	world_surveys:                            [MAX_WORLD_SURVEYS]World_Survey_Record,
	world_survey_count:                       int,
	surveyed_system_mask:                     u64,
	habitable_contacts:                       [dynamic]Habitable_World_Contact,
	long_term_navigation_goal:                 Long_Term_Navigation_Goal,
	guidance_step:                            i32,
	max_seasons:                              i32,
	year:                                     i32,
	strategic:                                Strategic_State,
	material_economy:                         Material_Economy,
	capacities:                               Fleet_Capacities,
	obligations:                              Obligation_State,
	public_politics:                          Public_Politics_State,
	narrative_director:                       Narrative_Director_State,
	council:                                  Council_Enactment,
	politics:                                 Dynamic_Politics_State `json:"-"`,
	transformations:                          Fleet_Transformation_State,
	capacity_commitments:                     [MAX_CAPACITY_COMMITMENTS]Capacity_Commitment,
	current_situation:                        Fleet_Situation,
	situation_queue:                          [MAX_SITUATION_QUEUE]Fleet_Situation,
	situation_queue_count:                    int,
	next_situation_id:                        u32,
	stores:                                   Intangible_Resources,
	stability:                                i32,
	ship_count:                               int,
	ships:                                    [MAX_SHIPS]Ship,
	communities:                              [MAX_COMMUNITIES]Community,
	community_count:                          int,
	attributes:                               [6]Civilization_Attribute,
	values:                                   [2]Civilization_Value,
	institutions:                             [MAX_INSTITUTIONS]Institution,
	archives:                                 [MAX_ARCHIVES]Cultural_Archive,
	precedents:                               [MAX_PRECEDENTS]Precedent,
	precedent_count:                          int,
	next_precedent_id:                        u32,
	precedent_cases:                          [MAX_PRECEDENT_CASES]Precedent_Case,
	precedent_case_count:                     int,
	next_precedent_case_id:                   u32,
	needs:                                    [MAX_NEEDS]Need,
	compact:                                  Expeditionary_Compact_State,
	pending_aftermath:                        Operation_Aftermath,
	applying_operation_id:                    Operation_ID,
	applying_observation_index:               i32,
	completed_aftermaths:                     [MAX_COMPLETED_AFTERMATHS]Operation_ID,
	completed_aftermath_count:                int,
	social_consequences:                      [MAX_SOCIAL_CONSEQUENCES]Social_Consequence_Record,
	social_consequence_count:                 int,
	operational_practices:                    [len(Operational_Practice)]i32,
	projects:                                 [MAX_PROJECTS]Project,
	promises:                                 [MAX_PROMISES]Promise,
	promise_count:                            int,
	settlements:                              [MAX_SETTLEMENTS]Settlement,
	settlement_economies:                     Settlement_Economy_Network,
	settlement_count:                         int,
	settlement_relationships:                 [MAX_SETTLEMENT_RELATIONSHIPS]Settlement_Relationship,
	settlement_relationship_count:            int,
	settlement_proposal:                      Settlement_Proposal,
	events:                                   [dynamic]Campaign_Event,
	event_count:                              int,
	archived_eras:                            [MAX_ARCHIVED_ERAS]Archived_Era,
	archived_era_count:                       int,
	archived_epochs:                          [MAX_ARCHIVED_EPOCHS]Archived_Epoch,
	archived_epoch_count:                     int,
	archival_references:                      [MAX_ARCHIVAL_REFERENCES]Archival_Reference,
	archival_reference_count:                 int,
	service_eras:                             [MAX_SERVICE_ERAS]Ship_Service_Era,
	service_era_count:                        int,
	chronicle_compactions:                    i32,
	chronicle_saturation_failures:            i32,
	history_hooks:                            [MAX_HISTORY_HOOKS]History_Hook,
	history_hook_count:                       int,
	relationships:                            [MAX_RELATIONSHIPS]Ship_Community_Relationship,
	relationship_count:                       int,
	ship_relationships:                       [MAX_SHIP_RELATIONSHIPS]Ship_Relationship,
	ship_relationship_count:                  int,
	institution_ship_relationships:           [MAX_INSTITUTION_SHIP_RELATIONSHIPS]Institution_Ship_Relationship,
	institution_ship_relationship_count:      int,
	community_institution_relationships:      [MAX_COMMUNITY_INSTITUTION_RELATIONSHIPS]Community_Institution_Relationship,
	community_institution_relationship_count: int,
	institution_relationships:                [MAX_INSTITUTION_RELATIONSHIPS]Institution_Relationship,
	institution_relationship_count:           int,
	historical_figures:                       [MAX_HISTORICAL_FIGURES]Campaign_Historical_Figure,
	historical_figure_count:                  int,
	captain_relationships:                    [MAX_CAPTAIN_RELATIONSHIPS]Captain_Relationship,
	captain_relationship_count:               int,
	captain_obligations:                      [MAX_CAPTAIN_OBLIGATIONS]Captain_Obligation,
	captain_obligation_count:                 int,
	ending_evidence:                          [MAX_ENDING_EVIDENCE]string,
	ending_evidence_count:                    int,
	expedition:                               Expedition_Contract,
	passage:                                  Passage,
	dark_fleet_atlas:                         [dynamic]Dark_Atlas_Discovery,
	dark_organism_observations:               [dynamic]Dark_Organism_Observation,
	dark_strategy_records:                    [dynamic]Dark_Strategy_Statistics,
	dark_strategy_record_count:               int,
	dark_unresolved_voyages:                  [dynamic]Dark_Voyage_Record,
	dark_unresolved_voyage_count:             int,
	dark_relays:                              [dynamic]Dark_Relay_Record,
	dark_relay_count:                         int,
	stranded_passage_groups:                  [MAX_STRANDED_PASSAGE_GROUPS]Stranded_Passage_Group,
	stranded_passage_group_count:             int,
	stranded_outcome_notice_pending:          bool,
	stranded_outcome_candidate:               int,
	combat_deployment_active:                 bool,
	combat_deployment_seed:                   u64,
	combat_deployment_ships:                  [MAX_SHIPS]Ship_ID,
	combat_deployment_groups:                 [MAX_SHIPS]int,
	combat_deployment_count:                  int,
	combat_deployment_propellant_cost:        i32,
	combat_deployment_doctrine_deviation:     bool,
	combat_deployment_authorized_doctrine:    Combat_Doctrine,
	combat_deployment_doctrines:              [COMBAT_GROUP_COUNT]Combat_Doctrine,
	combat_fire_control_preference:           Combat_Fire_Control,
	combat_operation:                         Combat_Operation,
	combat_runtime:                           ^Combat_Mission `json:"-"`,
	far_engagement:                           ^Far_Engagement `json:"-"`,
	fronts:                                   [MAX_ACTIVE_FRONTS]Historical_Front,
	front_count:                              int,
	future_fronts:                            [MAX_FUTURE_FRONTS]Historical_Front_Proposal,
	future_front_count:                       int,
	next_front_id:                            u32,
	last_front_beat_season:                   i32,
	outer_dark:                               Outer_Dark,
	candidate_home_known:                     bool,
	colony_package_ready:                     bool,
	constitutional_emergency:                 bool,
	pending_accountability_event:             u64,
	emergency_count:                          i32,
	first_emergency_season:                   i32,
	last_emergency_cause:                     Emergency_Cause,
	last_emergency_season:                    i32,
	emergency_recovery_active:                bool,
	emergency_recovery_target:                i32,
	emergency_stable_seasons:                 i32,
	emergency_recurrence_by_cause:            [4]i32,
	emergency_refractory_until_by_cause:      [4]i32,
	emergency_structural_response_pending:    bool,
	emergency_structural_response_required:   bool,
	emergency_structural_response:            Emergency_Structural_Response,
	emergency_preparedness:                   i32,
	emergency_response_uses:                  [3]i32,
	hazard_count:                             i32,
	uncontained_hazard_count:                 i32,
	last_major_beat_season:                   i32,
	ending:                                   Ending,
}

Emergency_Structural_Response :: enum {
	None,
	Institutional_Recovery,
	Protect_Development,
	Contract_Obligations,
}

emergency_refractory_seasons :: proc(c: ^Campaign) -> i32 {switch c.story_tempo {case .Volatile:
		return 4; case .Spacious:
		return 8; case .Measured:
		return 6}; return 6}
development_reserves_available :: proc(c: ^Campaign) -> i32 {floor :=
		fleet_operating_floor(c).stock
	return i32(max(c.material_economy.fleet.stock.supplies - floor.supplies, 0))}

apply_emergency_structural_response :: proc(
	c: ^Campaign,
	response: Emergency_Structural_Response,
) -> bool {
	if !c.emergency_structural_response_pending || response == .None do return false
	switch response {
	case .Institutional_Recovery:
		if development_reserves_available(c) < 6 do return false
		if !fleet_stock_spend(c, {supplies = 6}, .Emergency) do return false; c.emergency_recovery_target = max(EMERGENCY_FLOOR + 6, c.emergency_recovery_target - 6)
		for &institution in c.institutions do if institution.active {institution.legitimacy = min(institution.legitimacy + 2, 100); break}
		c.emergency_preparedness = max(c.emergency_preparedness, 64)
	case .Protect_Development:
		c.emergency_recovery_target = max(EMERGENCY_FLOOR + 8, c.emergency_recovery_target - 4)
		c.emergency_preparedness = max(c.emergency_preparedness, 64)
	case .Contract_Obligations:
		contracted := false
		for i in 0 ..< c.obligations.count {o := &c.obligations.items[i]; if obligation_active(o^) && contract_obligation(c, i, .Reduce_Guarantee) {contracted = true; break}}
		if !contracted do return false
		c.emergency_recovery_target = max(EMERGENCY_FLOOR + 8, c.emergency_recovery_target - 4)
		c.emergency_preparedness = max(c.emergency_preparedness, 64)
	case .None:
		return false
	}
	c.emergency_structural_response =
		response; c.emergency_structural_response_pending = false; c.emergency_structural_response_required = false
	record_event(
		c,
		.Emergency_Response,
		fmt.tprintf(
			"The fleet adopted %v as the structural response to recurring emergency pressure.",
			response,
		),
		value = i32(response),
	)
	return true
}

Emergency_Pressure :: struct {
	cohesion_loss, reserve_loss, expiring_promises, scheduled_cohesion, projected_cohesion: i32,
	immediate_relief, structural_recovery, recovery_target:                                 i32,
	recovery_active:                                                                        bool,
	critical:                                                                               bool,
}

make_semantic_tags :: proc(values: ..Semantic_Tag) -> Semantic_Tags {bits: u64; for value in values do bits |= u64(1) << u64(value)
	return Semantic_Tags(bits)}
semantic_has :: proc(tags: Semantic_Tags, value: Semantic_Tag) -> bool {return(
		u64(tags) & (u64(1) << u64(value)) !=
		0 \
	)}
semantic_add :: proc(tags: Semantic_Tags, values: ..Semantic_Tag) -> Semantic_Tags {bits := u64(
		tags,
	)
	for value in values do bits |= u64(1) << u64(value)
	return Semantic_Tags(bits)}
semantic_contains_all :: proc(tags, required: Semantic_Tags) -> bool {return(
		u64(tags) & u64(required) ==
		u64(required) \
	)}

semantic_tags_for_ship :: proc(role: Role) -> Semantic_Tags {
	tags := make_semantic_tags(.Entity, .Ship)
	switch role {case .Hospital:
		return semantic_add(tags, .Care, .Rescue); case .Archive:
		return semantic_add(tags, .Knowledge); case .Foundry:
		return semantic_add(tags, .Industry, .Repair); case .Survey:
		return semantic_add(tags, .Navigation, .Discovery); case .Escort:
		return semantic_add(tags, .Conflict, .Survival); case .Agriculture:
		return semantic_add(tags, .Care, .Survival); case .Habitat, .Colony:
		return semantic_add(tags, .Migration, .Survival)}
	return tags
}
semantic_tags_for_need :: proc(kind: Need_Kind) -> Semantic_Tags {
	tags := make_semantic_tags(.Need)
	switch kind {case .Sustenance_Shortfall:
		return semantic_add(tags, .Survival, .Care); case .Settlement_Demand, .Settlement_Charter:
		return semantic_add(tags, .Migration, .Governance); case .Ship_Repair:
		return semantic_add(tags, .Ship, .Repair, .Damage); case .Archive_Staffing:
		return semantic_add(tags, .Archive, .Knowledge); case .Settlement_Defense:
		return semantic_add(tags, .Settlement, .Conflict, .Survival); case .Representation:
		return semantic_add(tags, .Community, .Governance); case .Jurisdiction_Dispute:
		return semantic_add(
			tags,
			.Ship,
			.Institution,
			.Governance,
			.Jurisdiction,
			.Relationship,
			.Contested,
		); case .Institution_Dispute:
		return semantic_add(tags, .Institution, .Governance, .Relationship, .Contested)}
	return tags
}
semantic_tags_for_precedent :: proc(kind: Precedent_Kind) -> Semantic_Tags {
	tags := make_semantic_tags(.Rule, .Governance)
	switch kind {case .Shared_Authority,
	                  .Ship_Sovereignty,
	                  .Consent_Of_The_Settled,
	                  .Right_Of_Departure,
	                  .Council_Assignment,
	                  .Proportionate_Asset_Division,
	                  .Founding_Independence,
	                  .Continuing_Fleet_Jurisdiction:
		return tags
	case .Emergency_Command:
		return semantic_add(tags, .Conflict, .Survival)
	case .Open_Archives:
		return semantic_add(tags, .Archive, .Knowledge)
	case .Adaptation_Accepted:
		return semantic_add(tags, .Migration, .Survival)
	case .No_One_Left_Behind:
		return semantic_add(tags, .Rescue, .Care)
	case .Accountable_Disclosure, .Custodial_Archives:
		return semantic_add(tags, .Archive, .Knowledge)
	case .Protective_Withholding, .Closed_Berths:
		return semantic_add(tags, .Survival, .Contested)
	case .Right_Of_Refuge, .Emergency_Admission:
		return semantic_add(tags, .Migration, .Care, .Survival)
	case .Continuity_Of_The_Fleet:
		return semantic_add(tags, .Institution, .Migration)}
	return tags
}
semantic_tags_for_event :: proc(
	kind: Event_Kind,
	ship, related: Ship_ID,
	community: Community_ID,
	figure: Figure_ID,
	institution: Institution_ID,
	settlement: Settlement_ID,
	archive: Archive_ID,
	account: Account_Status,
) -> Semantic_Tags {
	tags := make_semantic_tags(.Event)
	if ship != 0 || related != 0 do tags = semantic_add(tags, .Ship)
	if community != 0 do tags = semantic_add(tags, .Community)
	if figure != 0 do tags = semantic_add(tags, .Figure)
	if institution != 0 do tags = semantic_add(tags, .Institution)
	if settlement != 0 do tags = semantic_add(tags, .Settlement)
	if archive != 0 do tags = semantic_add(tags, .Archive, .Knowledge)
	if account != .Uncontested do tags = semantic_add(tags, .Contested)
	#partial switch kind {
	case .Need_Surfaced, .Need_Mitigated, .Need_Deferred, .Need_Resolved, .Need_Neglected:
		tags = semantic_add(tags, .Need)
	case .Autonomy_Triggered:
		tags = semantic_add(tags, .Autonomy, .Passage)
	case .Ship_Damaged, .Ship_Scarred:
		tags = semantic_add(tags, .Damage, .Passage)
	case .Ship_Repaired:
		tags = semantic_add(tags, .Repair)
	case .Ship_Lost:
		tags = semantic_add(tags, .Loss, .Survival, .Passage)
	case .Ship_Bond_Changed:
		tags = semantic_add(tags, .Relationship, .Passage)
	case .Promise_Changed:
		tags = semantic_add(tags, .Promise)
	case .Precedent_Enacted:
		tags = semantic_add(tags, .Rule, .Governance)
	case .Settlement_Founded, .Local_Settlement:
		tags = semantic_add(tags, .Founding, .Migration, .Settlement)
	case .Settlement_Reported,
	     .Settlement_Supported,
	     .Settlement_Setback,
	     .Settlement_Charter_Changed:
		tags = semantic_add(tags, .Settlement)
	case .Archive_Established:
		tags = semantic_add(tags, .Archive, .Knowledge, .Founding)
	case .Archive_Revelation:
		tags = semantic_add(tags, .Archive, .Knowledge, .Accountability, .Contested)
	case .Community_Joined:
		tags = semantic_add(tags, .Community, .Migration)
	case .History_Continued, .Community_Memory_Changed:
		tags = semantic_add(tags, .Memory)
	case .Historical_Figure_Emerged, .Historical_Figure_Changed:
		tags = semantic_add(tags, .Figure)
	case .Institution_Changed:
		tags = semantic_add(tags, .Institution, .Governance)
	case .Jurisdiction_Changed:
		tags = semantic_add(tags, .Institution, .Ship, .Governance, .Jurisdiction, .Relationship)
	case .Political_Relationship_Changed:
		tags = semantic_add(tags, .Institution, .Community, .Governance, .Relationship)
	case .Settlement_Relationship_Changed:
		tags = semantic_add(tags, .Settlement, .Migration, .Relationship)
	case .Expedition_Commissioned, .Expedition_Departed, .Expedition_Returned:
		tags = semantic_add(tags, .Passage)
	case .Habitable_World_Confirmed:
		tags = semantic_add(tags, .Knowledge, .Settlement)
	case .Constitutional_Emergency:
		tags = semantic_add(tags, .Governance, .Conflict, .Survival)
	case .Front_Proposed, .Front_Advanced, .Front_Transformed, .Front_Dormant, .Front_Returned:
		tags = semantic_add(tags, .Governance, .Causality)
	case .Region_Changed:
		tags = semantic_add(tags, .Passage, .Route, .Environment)
	}
	return tags
}
