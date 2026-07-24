package game

import "base:runtime"

import "core:fmt"
import "core:testing"

MAX_SHIPS :: 12
INITIAL_SHIPS :: 12
MAX_COMMUNITIES :: 8
INITIAL_COMMUNITIES :: 4
MAX_SHIP_HISTORY :: 5
MAX_SHIP_MEMORIES :: 12
MAX_HISTORY_HOOKS :: 8
MAX_RELATIONSHIPS :: 24
MAX_SHIP_RELATIONSHIPS :: 48
MAX_INSTITUTION_SHIP_RELATIONSHIPS :: 24
MAX_COMMUNITY_INSTITUTION_RELATIONSHIPS :: 32
MAX_INSTITUTION_RELATIONSHIPS :: 16
MAX_HISTORICAL_FIGURES :: 16
MAX_ENDING_EVIDENCE :: 3
MAX_NEEDS :: 3
NEED_KIND_COUNT :: 9
MAX_PROJECTS :: 3
MAX_PROMISES :: 8
MAX_SETTLEMENTS :: 12
MAX_SETTLEMENT_RELATIONSHIPS :: 8
MAX_PROPOSAL_REASONS :: 3
MAX_SITUATION_POSITIONS :: 3
MAX_SITUATION_REASONS :: 2
MAX_SITUATION_CHOICES :: 4
MAX_SITUATION_QUEUE :: 3
MAX_CAPACITY_COMMITMENTS :: 12
MAX_INSTITUTIONS :: 5
MAX_ARCHIVES :: 6
MAX_PRECEDENTS :: 30
MAX_PRECEDENT_CASES :: 3
MAX_EVENTS :: 512
MAX_EVENT_CAUSES :: 4
MAX_ACTIVE_FRONTS :: 3
MAX_FUTURE_FRONTS :: 5
MAX_ARCHIVED_ERAS :: 32
MAX_ARCHIVED_EPOCHS :: 32
MAX_ARCHIVAL_REFERENCES :: MAX_EVENTS
MAX_SERVICE_ERAS :: 48
campaign_storage_allocator :: proc() -> runtime.Allocator {
	when ODIN_TEST do return context.temp_allocator
	return context.allocator
}
CAMPAIGN_FORMAT_VERSION :: u32(10)
CAMPAIGN_RULES_IDENTITY :: u64(0x4c42482d43563941) // "LBH-CV9A"
EMERGENCY_FLOOR :: i32(15)

Ship_ID :: distinct u32
Community_ID :: distinct u32
Figure_ID :: distinct u32
Institution_ID :: distinct u32
Settlement_ID :: distinct u32
Archive_ID :: distinct u32
Precedent_ID :: distinct u32
Precedent_Case_ID :: distinct u32

Semantic_Tag :: enum u8 {
	Entity,
	Event,
	Memory,
	Relationship,
	Rule,
	Need,
	Project,
	Promise,
	Ship,
	Community,
	Figure,
	Institution,
	Settlement,
	Archive,
	Passage,
	Governance,
	Rescue,
	Knowledge,
	Repair,
	Damage,
	Migration,
	Survival,
	Autonomy,
	Conflict,
	Discovery,
	Accountability,
	Contested,
	Founding,
	Loss,
	Care,
	Industry,
	Navigation,
	Identity,
	Capability,
	Value,
	Destination,
	Route,
	Environment,
	Species,
	Infrastructure,
	Jurisdiction,
	Causality,
}
Semantic_Tags :: distinct u64

Chronicle_Length :: enum {
	Short,
	Standard,
	Long,
	Open,
}
Material_Pressure :: enum {
	Gentle,
	Standard,
	Severe,
}
Consequence_Severity :: enum {
	Gentle,
	Standard,
	Severe,
}

chronicle_length_seasons :: proc(length: Chronicle_Length) -> i32 {
	switch length {case .Short:
		return 12; case .Standard:
		return 24; case .Long:
		return 50; case .Open:
		return 0}
	return 0
}
Story_Tempo :: enum {
	Measured,
	Spacious,
	Volatile,
}
Ruleset_Preset :: enum {
	Fleet_Parity,
	Heroic_Line,
	Space_Opera,
	Grand_Fleet,
	Custom,
}
Ruleset :: struct {
	preset:        Ruleset_Preset,
	// Average equivalent enemy ships a player ship is expected to defeat.
	heroism_scale: i32,
}

DEFAULT_RULESET :: Ruleset {
	preset        = .Heroic_Line,
	heroism_scale = 8,
}
Role :: enum {
	Habitat,
	Agriculture,
	Foundry,
	Archive,
	Hospital,
	Survey,
	Escort,
	Colony,
}
Hull_Class :: enum {
	Unspecified,
	Strike_Craft,
	Corvette,
	Fleet_Ship,
	Cruiser,
	Capital_Ship,
}
Ship_Construction_Style :: enum u8 {
	Distributed_Fabrication,
	Living_Hullcraft,
	Machine_Partnership,
	Closed_Cycle,
}
Ship_Generator_Kind :: enum u8 {
	Modular_Frame,
	Single_Hull,
	// Retained at value 2 so older campaign data remains readable. Production
	// generation normalizes this retired architecture to Delta.
	Saucer,
	Delta,
}
Crisis :: enum {
	Ion_Storm,
	Blockade,
	Silent_System,
}
Fleet_Hazard :: enum {
	Micrometeoroid_Swarm,
	Crop_Blight,
	Reactor_Cascade,
	Membrane_Shear,
}
Ship_Scar :: enum {
	None,
	Storm_Shaken,
	Hull_Breach,
	Survivor_Guilt,
	Alien_Symbiosis,
	Oathbound,
	Passage_Scarred,
}
Ship_Departure :: enum {
	None,
	Lost,
	Settlement,
	Dark_Voyage,
	Political_Schism,
}
Dark_Contact_Procedure :: enum {
	Unspecified,
	Observation_Only,
	Wake_Discipline,
	Field_Quarantine,
	Shear_Evasion,
}
Need_Kind :: enum {
	Sustenance_Shortfall,
	Settlement_Demand,
	Ship_Repair,
	Archive_Staffing,
	Settlement_Defense,
	Representation,
	Settlement_Charter,
	Jurisdiction_Dispute,
	Institution_Dispute,
}
Need_Response :: enum {
	Open,
	Mitigated,
	Deferred,
	Resolved,
	Neglected,
}
Operation_Kind :: enum {
	None,
	Passage,
	Combat,
}
Operation_Conduct :: enum {
	None,
	Preserve_Lives,
	Open_Record,
	Mission_First,
}
Operation_Objective :: enum {
	None,
	Passage_Recover_Reserves,
	Passage_Evaluate_Home,
	Passage_Evacuate_Harbor,
	Passage_Inspect_Treaty,
	Passage_Escort_Migration,
	Passage_Recover_Missing_Ship,
	Combat_Recover_Seedship,
	Combat_Defend_Settlement,
	Combat_Break_Blockade,
	Combat_Escort_Migration,
	Combat_Recover_Disabled_Fleet,
	Combat_Contested_Route,
}
Operation_Withdrawal :: enum {
	Command_Discretion,
	Protected_Return,
	Mandatory_Threshold,
}
Emergency_Cause :: enum {
	None,
	Reserves,
	Capacity,
	Cohesion,
}
Project_Kind :: enum {
	None,
	Repair,
	Refit,
	Habitat_Expansion,
	Analyze_Discovery,
	Colony_Package,
	Restore_Archive,
	Produce_Reserves,
	Maintenance_Recovery,
}
Promise_Status :: enum {
	Active,
	Honored,
	Broken,
}
Expedition_Outcome :: enum {
	Triumph,
	Success,
	Partial_Return,
	Disaster,
	Lost,
	Local_Settlement,
}
Ending :: enum {
	In_Progress,
	New_Home,
	Harbor_Network,
	Nomadic_Fleet,
	Federation,
	Transformed,
	Fragmented_Survival,
}
Ending_Quality :: enum {
	None,
	Fragile,
	Stable,
	Flourishing,
}
Ending_Finale :: struct {
	active:                      bool,
	ending:                      Ending,
	started_season, ends_season: i32,
}
Attribute_Class :: enum {
	Identity,
	Capability,
	Value,
}
Loss_Kind :: enum {
	Catastrophe,
	Expulsion,
	Civil_War,
	Unknown_Event,
}
Preserved_Inheritance :: enum {
	Seed_Banks,
	Scientific_Corpora,
	Cultural_Archives,
	Machine_Memories,
}
Precedent_Kind :: enum {
	Shared_Authority,
	Emergency_Command,
	Ship_Sovereignty,
	Open_Archives,
	Adaptation_Accepted,
	No_One_Left_Behind,
	Consent_Of_The_Settled,
	Right_Of_Departure,
	Council_Assignment,
	Proportionate_Asset_Division,
	Founding_Independence,
	Continuing_Fleet_Jurisdiction,
	Accountable_Disclosure,
	Protective_Withholding,
	Right_Of_Refuge,
	Emergency_Admission,
	Closed_Berths,
	Custodial_Archives,
	Continuity_Of_The_Fleet,
}
Event_Kind :: enum {
	Chronicle_Started,
	Season_Advanced,
	Need_Surfaced,
	Need_Mitigated,
	Need_Deferred,
	Need_Resolved,
	Need_Neglected,
	Emergency_Response,
	Project_Completed,
	Expedition_Commissioned,
	Expedition_Departed,
	Resource_Changed,
	Autonomy_Triggered,
	Command_Used,
	Ship_Damaged,
	Ship_Repaired,
	Ship_Lost,
	Expedition_Returned,
	Habitable_World_Confirmed,
	Ship_Scarred,
	Ship_Bond_Changed,
	Promise_Changed,
	Settlement_Founded,
	Settlement_Reported,
	Settlement_Supported,
	Settlement_Setback,
	Settlement_Charter_Changed,
	Archive_Established,
	Archive_Revelation,
	Local_Settlement,
	Community_Joined,
	History_Continued,
	Historical_Figure_Emerged,
	Historical_Figure_Changed,
	Institution_Changed,
	Jurisdiction_Changed,
	Political_Relationship_Changed,
	Settlement_Relationship_Changed,
	Settlement_Proposal_Started,
	Settlement_Deliberated,
	Settlement_Decided,
	Settlement_Proposal_Withdrawn,
	Situation_Proposed,
	Situation_Response,
	Situation_Decided,
	Situation_Complied,
	Capacity_Committed,
	Capacity_Released,
	Community_Memory_Changed,
	Constitutional_Emergency,
	Fleet_Hazard,
	Chronicle_Ended,
	Precedent_Enacted,
	Front_Proposed,
	Front_Advanced,
	Front_Transformed,
	Front_Dormant,
	Front_Returned,
	Region_Changed,
	Value_Tested,
	Precedent_Applied,
	Precedent_Contradicted,
	Precedent_Reviewed,
}

History_Hook_Kind :: enum {
	None,
	Broken_Procession,
}
History_Hook_Stage :: enum {
	None,
	Contact,
	Obligation,
	Consequence,
}
Relationship_Kind :: enum {
	Sponsorship,
	Advocated_For,
	Unanswered_Obligation,
}
Account_Status :: enum {
	Uncontested,
	Contradicted,
	Withheld,
}
Community_Position :: enum {
	Cooperative,
	Watchful,
	Aggrieved,
}

Strategic_State :: struct {
	cohesion: i32,
}

Capacity :: struct {
	total, reserved, damaged: i32,
}
Fleet_Capacities :: struct {
	compute, manpower, raw_materials: Capacity,
}

Capacity_Kind :: enum {
	Compute,
	Manpower,
	Raw_Materials,
}
Capacity_Commitment :: struct {
	active:                           bool,
	situation_id:                     u32,
	release_season:                   i32,
	origin_event:                     u64,
	compute, manpower, raw_materials: i32,
	source_ships:                     [3]Ship_ID,
	source_ship_count:                int,
	detail:                           string,
}

Situation_Kind :: enum {
	None,
	Repair_Debt,
	Settlement,
	Rescue,
	Contested_Evidence,
	Combat_Aftermath,
	Value_No_One_Left_Behind,
	Value_Truth_Before_Comfort,
	Value_Consent_To_Settle,
	Value_Shelter_Is_Sacred,
	Value_Shared_Authority,
	Value_Open_Archives,
	Value_The_Fleet_Endures,
	Value_Every_Home_Is_Free,
}
Situation_Phase :: enum {
	None,
	Proposal,
	Responses,
	Decision,
	Resolved,
}
Ship_Position_Kind :: enum {
	Support,
	Conditional,
	Oppose,
	Abstain,
}
Situation_Choice_Effect :: enum {
	None,
	Found_Settlement,
	Amend_Settlement,
	Delay,
	Decline,
	Full_Rescue,
	Bounded_Rescue,
	Promise_Return,
	Refuse_Rescue,
	Publish_Evidence,
	Review_Evidence,
	Restricted_Disclosure,
	Conceal_Evidence,
	Honor_Combat_Withdrawal,
	Commend_Combat_Recovery,
	Expand_Combat_Authority,
	Value_Comply,
	Value_Bounded,
	Value_Exception,
	Value_Depart,
}
Situation_Reason :: struct {
	detail:       string,
	weight:       i32,
	source_event: u64,
}
Situation_Position :: struct {
	ship:         Ship_ID,
	position:     Ship_Position_Kind,
	reasons:      [MAX_SITUATION_REASONS]Situation_Reason,
	reason_count: int,
}
Situation_Choice :: struct {
	label, consequence:               string,
	effect:                           Situation_Choice_Effect,
	irreversible:                     bool,
	compute, manpower, raw_materials: i32,
}
Fleet_Situation :: struct {
	id:                                           u32,
	kind:                                         Situation_Kind,
	phase:                                        Situation_Phase,
	initiator:                                    Ship_ID,
	affected_community:                           Community_ID,
	origin_event, proposal_event, decision_event: u64,
	title, proposal, stakes:                      string,
	positions:                                    [MAX_SITUATION_POSITIONS]Situation_Position,
	position_count:                               int,
	choices:                                      [MAX_SITUATION_CHOICES]Situation_Choice,
	choice_count:                                 int,
	selected_choice:                              int,
	auto_resolved:                                bool,
	dramatic_score:                               i32,
	celestial:                                    Celestial_Reference,
	value:                                        Value_Kind,
	law_domain:                                   Precedent_Domain,
}

Intangible_Resources :: struct {
	science, influence, value: i32,
}

Ship_Memory :: struct {
	event_sequence: u64,
	kind:           Event_Kind,
	other_ship:     Ship_ID,
	community:      Community_ID,
	figure:         Figure_ID,
	settlement:     Settlement_ID,
	account_status: Account_Status,
	semantic_tags:  Semantic_Tags,
}

Ship_Impairments :: struct {
	mobility, sensors, strike, support, endurance: i32,
}

Ship :: struct {
	id:                                          Ship_ID,
	name:                                        string,
	construction_seed:                           u64,
	construction_lineage:                        u64,
	construction_style:                          Ship_Construction_Style,
	generator_kind:                              Ship_Generator_Kind,
	// Encoded as 1..3 so zero remains a compatible legacy-save sentinel.
	bow_profile:                                 u8,
	// Encoded as 1..9; zero preserves the coupled legacy layout formula.
	utility_hardpoint:                           u8,
	// Encoded as 1..3; zero derives the legacy value from construction seed.
	wing_sweep:                                  u8,
	wing_stance:                                 u8,
	keel_profile:                                u8,
	mission_profile:                             u8,
	// Encoded as 1..3; zero derives the legacy value from construction seed.
	drive_layout:                                u8,
	drive_setback:                               u8,
	// Encoded as 1..5 (none through industrial); zero is the legacy standard.
	greebly_density:                             u8,
	role:                                        Role,
	hull_class:                                  Hull_Class,
	hull_archetype:                              Ship_Hull_Archetype,
	operational_role:                            Ship_Operational_Role,
	weapon_package:                              Ship_Weapon_Package,
	defense_packages:                            Ship_Defense_Packages,
	mass_tonnes:                                 i64,
	propellant_capacity_kt:                      f64,
	propellant_kt:                               f64,
	drive_exhaust_velocity_km_s:                 f64,
	drive_thrust_kilonewtons:                    f64,
	power:                                       i32,
	damage:                                      i32,
	impairments:                                 Ship_Impairments,
	dark_symbiont_id:                            u64,
	dark_contact_procedure:                      Dark_Contact_Procedure,
	dark_field_scars:                            i32,
	experience:                                  i32,
	discoveries:                                 i32,
	crew:                                        i32,
	community:                                   Community_ID,
	active:                                      bool,
	departure:                                   Ship_Departure,
	committed:                                   bool,
	history_count:                               i32,
	scar:                                        Ship_Scar,
	passage_trait:                               Passage_Ship_Trait,
	history_note:                                string,
	history_records:                             [MAX_SHIP_HISTORY]string,
	history_record_count:                        int,
	promises_upheld:                             i32,
	promises_broken:                             i32,
	promises_transformed:                        i32,
	last_promise_status:                         Passage_Promise_Status,
	last_promise_event:                          u64,
	captain:                                     Figure_ID,
	memories:                                    [MAX_SHIP_MEMORIES]Ship_Memory,
	memory_count:                                int,
	archived_memory_count:                       i32,
	archived_memory_first, archived_memory_last: u64,
	archived_memory_tags:                        Semantic_Tags,
	semantic_tags:                               Semantic_Tags,
	current_position:                            string,
	current_commitment:                          string,
	pending_claim:                               string,
}

History_Hook :: struct {
	kind:              History_Hook_Kind,
	stage:             History_Hook_Stage,
	community:         Community_ID,
	ship:              Ship_ID,
	created_season:    i32,
	population:        i32,
	origin_event:      u64,
	obligation_event:  u64,
	consequence_event: u64,
	figure:            Figure_ID,
	detail:            string,
	semantic_tags:     Semantic_Tags,
}

Campaign_Historical_Figure :: struct {
	id:              Figure_ID,
	name:            string,
	role:            string,
	community:       Community_ID,
	ship:            Ship_ID,
	emerged_season:  i32,
	origin_event:    u64,
	last_event:      u64,
	public_actions:  i32,
	passage_actions: i32,
	age_years:       i32,
	institution:     Institution_ID,
	settlement:      Settlement_ID,
	predecessor:     Figure_ID,
	active:          bool,
	semantic_tags:   Semantic_Tags,
	captain_profile: Captain_Profile,
}

Ship_Community_Relationship :: struct {
	ship:          Ship_ID,
	community:     Community_ID,
	kind:          Relationship_Kind,
	strength:      i32,
	origin_event:  u64,
	last_event:    u64,
	semantic_tags: Semantic_Tags,
}
