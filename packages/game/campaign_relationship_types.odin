package game

import "core:fmt"
import "core:testing"

Ship_Relationship_Kind :: enum {
	Shared_Passage,
	Construction_Siblings,
}

Ship_Relationship :: struct {
	ship_a:          Ship_ID,
	ship_b:          Ship_ID,
	kind:            Ship_Relationship_Kind,
	strength:        i32,
	shared_passages: i32,
	origin_event:    u64,
	last_event:      u64,
	semantic_tags:   Semantic_Tags,
}

Institution_Ship_Stance :: enum {
	Stewardship,
	Contested,
	Reconciled,
}
Institution_Ship_Relationship :: struct {
	institution:     Institution_ID,
	ship:            Ship_ID,
	stance:          Institution_Ship_Stance,
	strength:        i32,
	origin_event:    u64,
	last_event:      u64,
	precedent_event: u64,
	semantic_tags:   Semantic_Tags,
}

Community_Institution_Stance :: enum {
	Coalition,
	Opposition,
}
Community_Institution_Relationship :: struct {
	community:     Community_ID,
	institution:   Institution_ID,
	stance:        Community_Institution_Stance,
	strength:      i32,
	origin_event:  u64,
	last_event:    u64,
	semantic_tags: Semantic_Tags,
}

Authority_Policy :: enum {
	Central_Command,
	Shared_Authority,
	Ship_Autonomy,
}
Disclosure_Policy :: enum {
	Restricted,
	Accountable,
	Open,
}
Rescue_Policy :: enum {
	Discretionary,
	Mutual_Aid,
	Absolute_Duty,
}
Institution_Relationship_Stance :: enum {
	Rivalry,
	Accord,
}
Institution_Relationship :: struct {
	institution_a, institution_b: Institution_ID,
	stance:                       Institution_Relationship_Stance,
	strength:                     i32,
	policy:                       Semantic_Tag,
	origin_event, last_event:     u64,
	semantic_tags:                Semantic_Tags,
}

Community :: struct {
	id:                  Community_ID,
	name:                string,
	population:          i32,
	children:            i32,
	tolerance:           i32,
	settlement_desire:   i32,
	trust:               i32,
	consents_to_settle:  bool,
	position:            Community_Position,
	grievance:           i32,
	petitions_honored:   i32,
	petitions_neglected: i32,
	last_memory_event:   u64,
	semantic_tags:       Semantic_Tags,
}

Civilization_Attribute :: struct {
	class:         Attribute_Class,
	name:          string,
	description:   string,
	tested_count:  i32,
	semantic_tags: Semantic_Tags,
}
Institution :: struct {
	id:                Institution_ID,
	name:              string,
	capability:        string,
	legitimacy:        i32,
	active:            bool,
	community:         Community_ID,
	semantic_tags:     Semantic_Tags,
	authority_policy:  Authority_Policy,
	disclosure_policy: Disclosure_Policy,
	rescue_policy:     Rescue_Policy,
}
Cultural_Archive :: struct {
	id:            Archive_ID,
	name:          string,
	integrity:     i32,
	mass:          i32,
	unique:        bool,
	preserved:     bool,
	copied:        bool,
	semantic_tags: Semantic_Tags,
}
Need :: struct {
	kind:                 Need_Kind,
	community:            Community_ID,
	ship:                 Ship_ID,
	deadline:             i32,
	cost:                 i32,
	active:               bool,
	resolved:             bool,
	detail:               string,
	response:             Need_Response,
	defer_count:          i32,
	source_event:         u64,
	institution:          Institution_ID,
	opposing_institution: Institution_ID,
	settlement:           Settlement_ID,
	precedent_event:      u64,
	archive_id:           Archive_ID,
	figure:               Figure_ID,
	semantic_tags:        Semantic_Tags,
}

Project :: struct {
	kind:          Project_Kind,
	ship:          Ship_ID,
	remaining:     i32,
	reserve_cost:  i32,
	active:        bool,
	semantic_tags: Semantic_Tags,
}

Promise :: struct {
	beneficiary:   Community_ID,
	deadline:      i32,
	status:        Promise_Status,
	detail:        string,
	semantic_tags: Semantic_Tags,
}

Settlement :: struct {
	id:                             Settlement_ID,
	name:                           string,
	region:                         string,
	celestial:                      Celestial_Reference,
	population:                     i32,
	viability:                      i32,
	liberty:                        i32,
	founded_season:                 i32,
	report_due:                     i32,
	reported:                       bool,
	active:                         bool,
	founding_community:             Community_ID,
	founder_ship:                   Ship_ID,
	founding_event:                 u64,
	last_report_event:              u64,
	report_count:                   i32,
	archive_id:                     Archive_ID,
	archive_origin_event:           u64,
	founding_conduct:               Settlement_Conduct,
	founding_procedure:             Settlement_Procedure,
	continuing_obligations:         Continuing_Obligations,
	participating_ships:            [MAX_SHIPS]Ship_ID,
	participating_ship_count:       int,
	participating_communities:      [MAX_COMMUNITIES]Community_ID,
	participating_community_count:  int,
	proposal_event:                 u64,
	decision_event:                 u64,
	initial_grievance:              i32,
	fleet_relationship:             i32,
	public_founding_account:        string,
	authoritative_founding_account: string,
	world_class:                    Candidate_World_Class,
	founding_maintenance_seasons:   i32,
	maintenance_basis_points:       i32,
	orbital_refuge:                 bool,
	orbital_refuge_capacity:        i32,
	waived_founding_requirements:   u16,
	waiver_account:                 string,
	biosphere_evidence:             Biosphere_Evidence,
	biosphere_disclosed:            bool,
	preservation_obligation:        bool,
	restricted_development:         bool,
	semantic_tags:                  Semantic_Tags,
}

Settlement_Relationship_Kind :: enum {
	Exchange,
	Dependency,
}
Settlement_Relationship :: struct {
	settlement_a, settlement_b: Settlement_ID,
	kind:                       Settlement_Relationship_Kind,
	strength:                   i32,
	origin_event, last_event:   u64,
	semantic_tags:              Semantic_Tags,
}

Campaign_Event :: struct {
	sequence:              u64,
	kind:                  Event_Kind,
	season:                i32,
	ship_id:               Ship_ID,
	value:                 i32,
	detail:                string,
	authoritative_detail:  string,
	account_status:        Account_Status,
	community:             Community_ID,
	cause_sequence:        u64,
	figure_id:             Figure_ID,
	institution_id:        Institution_ID,
	settlement_id:         Settlement_ID,
	related_ship_id:       Ship_ID,
	precedent_event:       u64,
	archive_id:            Archive_ID,
	operation_id:          u64,
	observation_index:        i32,
	account_exposed:       bool,
	causes:                [MAX_EVENT_CAUSES]Event_Cause,
	cause_count:           int,
	semantic_tags:         Semantic_Tags,
	// Passage events retain both the duration experienced aboard and the
	// corresponding elapsed membrane time. A zero passage_id is a fleet event.
	passage_id:            u64,
	ship_elapsed_days:     f64,
	membrane_elapsed_days: f64,
	dark_depth:            f64,
}

Archived_Era :: struct {
	id:                                                       u32,
	first_sequence, last_sequence:                            u64,
	first_season, last_season:                                i32,
	population_start, population_end:                         i32,
	ships_changed, institutions_changed, settlements, losses: i32,
	promises_upheld, promises_broken:                         i32,
	defining_precedents:                                      [4]Precedent_Kind,
	defining_precedent_count:                                 int,
	detail:                                                   string,
}

Archived_Epoch :: struct {
	id:                                                                  u32,
	first_sequence, last_sequence:                                       u64,
	first_season, last_season:                                           i32,
	population_start, population_end:                                    i32,
	era_count, ships_changed, institutions_changed, settlements, losses: i32,
	promises_upheld, promises_broken:                                    i32,
	defining_precedents:                                                 [4]Precedent_Kind,
	defining_precedent_count:                                            int,
	detail:                                                              string,
}

Archival_Reference :: struct {
	sequence: u64,
	era_id:   u32,
}

Ship_Service_Era :: struct {
	ship:                          Ship_ID,
	name:                          string,
	first_season, last_season:     i32,
	first_sequence, last_sequence: u64,
	changes, losses:               i32,
}

Event_Cause_Role :: enum {
	Trigger,
	Precedent,
	Memory,
	Opposition,
	Continuation,
	Contradiction,
}
Event_Cause :: struct {
	sequence:      u64,
	role:          Event_Cause_Role,
	semantic_tags: Semantic_Tags,
}

Expedition_Contract :: struct {
	ships:              [6]Ship_ID,
	ship_count:         int,
	objective:          string,
	doctrine:           string,
	risk:               i32, // 0 conservative, 1 balanced, 2 desperate
	supplies:           i32,
	deadline:           i32,
	target_contact:     u64,
	settlement_package: bool,
	active:             bool,
}

Expedition_Result :: struct {
	outcome:          Expedition_Outcome,
	pattern:          string,
	reserves:         i32,
	population:       i32,
	damage:           i32,
	candidate_home:   bool,
	discovered_world: Celestial_Reference,
	survey:           World_Survey_Record,
	narrative:        string,
}
