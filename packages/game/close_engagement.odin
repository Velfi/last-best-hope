package game

// Deterministic command-level Close Engagement for the Recover the Seedship slice.
// Presentation deliberately lives in src; this file owns mission generation,
// autonomous intent, combat, objectives, and the factual outcome record.

import "core:fmt"
import "core:math"

COMBAT_MAX_SHIPS :: 16384
COMBAT_DURATION :: f32(1440)
COMBAT_FINALE_DURATION :: f32(1020)
COMBAT_FINALE_WITHDRAWAL :: f32(900)
COMBAT_FINALE_BEAM_CYCLE :: f32(180)
COMBAT_FINALE_BEAM_LOCK :: f32(18)
COMBAT_GROUP_COUNT :: 8
COMBAT_SECTOR_COLUMNS :: 6
COMBAT_SECTOR_ROWS :: 6
COMBAT_MAX_WRECKAGE_FIELDS :: 12
COMBAT_WRECKAGE_THRESHOLD :: 8
COMBAT_MAP_SCALE :: f32(1.65)
COMBAT_RELAY_CAPTURE_RATE :: f32(.9)
COMBAT_RELAY_DECAY_RATE :: f32(.15)
COMBAT_RECOVERY_RATE :: f32(.55)
COMBAT_ANOMALY_RATE :: f32(.8)
COMBAT_SPINAL_SALVO_LAUNCH_DELAY :: f32(1.4)
COMBAT_SPINAL_SALVO_SPEED :: f32(120)
COMBAT_CONTACT_FRESH_TIME :: f32(3)
COMBAT_CONTACT_STALE_TIME :: f32(12)
COMBAT_CONTACT_LOST_TIME :: f32(30)
COMBAT_MAX_SALVOS :: 256
COMBAT_MAX_INTERACTIONS :: 16

Combat_Vec3 :: struct {
	x, y, z: f32,
}
Combat_Side :: enum {
	Friendly,
	Raider,
}
Combat_Role :: enum {
	Fighter,
	Bomber,
	Corvette,
	Recovery,
	Carrier,
	Capital,
}
Combat_Capital_Type :: enum {
	None,
	Linebreaker,
}
Combat_Ship_Ability :: enum {
	None,
	Silent_Running,
	Vector_Screen,
	Combat_Air_Patrol,
	Ripple_Strike,
	Reserve_Torpedoes,
	Breach_Drop,
	Pursuit_Burn,
	Evasive_Screen,
	Ambush_Salvo,
	Flak_Saturation,
	Long_Baseline,
	Adaptive_Countermeasures,
	Field_Repair,
	Mine_Curtain,
	Overdrive_Pursuit,
	Coordinated_Broadside,
	Spinal_Salvo,
	Breakthrough_Burn,
	Line_Barrage,
	Flight_Surge,
	Siege_Salvo,
	Tow_And_Restore,
	Cargo_Sacrifice,
	Shelter_Fleet,
}
Combat_Doctrine :: enum {
	Cautious_Screen,
	Balanced,
	Hunter_Killer,
	Last_Stand,
}
Combat_Stance :: enum {
	Engage,
	Screen,
	Evade,
}
Combat_Interaction_Kind :: enum {
	None,
	Capture,
	Recover,
	Rescue,
	Scan,
	Escort,
	Salvage,
	Deploy,
	Repair,
}
Combat_Command_Action :: enum {
	Hold,
	Move,
	Act,
	Attack,
	Withdraw,
}
Combat_Order :: enum {
	Hold,
	Move,
	Guard,
	Control,
	Intercept,
	Recover,
	Withdraw,
	Extract,
	Attack,
}
Combat_Phase :: enum {
	Reconnaissance,
	Relay_Control,
	Recovery,
	Capital_Contact,
	Extraction,
	Complete,
}
Combat_Action :: enum {
	Holding,
	Navigating,
	Screening,
	Capturing,
	Attack_Run,
	Repositioning,
	Disengaging,
	Repairing,
	Extracting,
}
Combat_Target_Priority :: enum {
	Threats_To_Objective,
	Strike_Craft,
	Support,
	Capital,
}
Combat_Complication :: enum {
	None,
	Radiation_Surge,
	Raider_Reinforcements,
	Relay_Drift,
}
Combat_Terrain_Kind :: enum {
	Debris,
	Open_Lane,
	Radiation,
}
Combat_Request_Kind :: enum {
	None,
	Commit_Screen,
	Release_Torpedoes,
	Damaged_Withdrawal,
	Pursuit,
	Authorize_Fire,
	Authorize_Ability,
	Authorize_Emergency_Defense,
}
Combat_Fire_Control :: enum {
	Automatic,
	Confirm_Costly,
	Confirm_Engagements,
}
Combat_Weapon_Class :: enum {
	Kinetic,
	Laser,
	Guided_Missile,
	Heavy_Torpedo,
	Defensive_Gun,
	Defensive_Laser,
	Spinal_Kinetic,
}
Combat_Seeker :: enum {
	None,
	Radar,
	Infrared,
	Multimode,
}
Combat_Assessment :: enum {
	Unassessed,
	Apparently_Damaged,
	Confirmed_Disabled,
}
Combat_Contact_Display :: enum {
	Signal,
	Track,
	Identified,
	Firing_Solution,
}
Combat_Exposure_State :: enum {
	Quiet,
	Emitting,
	Exposed,
	Fixed,
}
Combat_Survival_Method :: enum {
	Concealment,
	Mobility,
	Endurance,
}
Combat_Emission_Policy :: enum {
	Silent,
	Passive_First,
	Burst_Sharing,
	Continuous,
}
Combat_Attack_Rhythm :: enum {
	Ambush,
	Repeated_Passes,
	Sustained,
}
Combat_Displacement_Trigger :: enum {
	After_Firing,
	When_Tracked,
	When_Pressured,
	Never,
}
Combat_Maneuver :: enum {
	Shadow,
	Masked_Approach,
	Establish_Cross_Bearing,
	Ambush,
	Skirmish_Pass,
	Fire_And_Displace,
	Break_Contact,
	Screen_Withdrawal,
	Reform,
	Decline_Engagement,
}
Combat_Maneuver_Job :: enum {
	Scout,
	Main_Effort,
	Screen,
	Support,
	Reserve,
}
Combat_Communication_State :: enum {
	Local,
	Burst,
	Continuous,
}
Combat_Maneuver_Reason :: enum {
	Searching,
	Concealed_Route,
	Building_Solution,
	Firing_Window,
	Shot_Exposed,
	Track_Threat,
	Pressure_Threat,
	Escape_Threat,
	Cohesion_Low,
	Objective_Safe,
}
Combat_Group_Posture :: enum {
	Holding,
	Transit,
	Executing,
	Disengaging,
	Unable,
}
Combat_Scenario :: enum {
	Seedship,
	Stress,
	Finale,
}
Combat_Finale_Phase :: enum {
	Approach,
	Line_Engagement,
	Relay_Assault,
	Exposed_Strike,
	Withdrawal,
	Complete,
}
Combat_Depth_Plane :: enum {
	Low,
	Plane,
	High,
}
Combat_Contact_Liveness :: enum {
	Unknown,
	Fresh,
	Aging,
	Stale,
	Lost,
}
Combat_Contact_Identity :: enum {
	Unknown,
	Classification,
	Identified,
}

// A contact is a side's imperfect report about an authoritative command
// element. Traces retain their last measured motion after direct detection is
// lost; callers must not read the hidden unit position for presentation.
Combat_Contact_Trace :: struct {
	position,
	velocity:                                                                                     Combat_Vec3,
	observed_acceleration:                                                                                  Combat_Vec3,
	last_seen,
	age,
	confidence,
	error_radius,
	identity_confidence,
	solution_quality,
	assessment_confidence: f32,
	prediction_uncertainty,
	last_network_update:                                                            f32,
	liveness:                                                                                               Combat_Contact_Liveness,
	identity:                                                                                               Combat_Contact_Identity,
	assessment:                                                                                             Combat_Assessment,
	detected,
	illuminated,
	relayed:                                                                         bool,
	observer_count:                                                                                         int,
}

Combat_Salvo :: struct {
	source, target:                                           int,
	side:                                                     Combat_Side,
	weapon:                                                   Combat_Weapon_Class,
	seeker:                                                   Combat_Seeker,
	position, velocity, target_volume:                        Combat_Vec3,
	time_remaining, speed, strength, guidance, last_guidance: f32,
	soft_kill, hard_kill, evasion:                            f32,
	phase:                                                     Combat_Wave_Phase,
	weapons_launched, weapons_surviving:                       int,
	delta_v_remaining_km_s:                                    f32,
	launch_time, arrival_earliest, arrival_latest:             f32,
	active:                                                   bool,
}

// Engagement grids provide stable operational addresses without constraining
// continuous movement. Letters run across the fleet's front; numbers advance
// from the fleet entry edge toward the opposing line.
Combat_Engagement_Grid :: struct {
	min_x, max_x, min_y, max_y: f32,
	low_ceiling, high_floor:    f32,
}

Combat_Command_State :: struct {
	report_delay, sensor_sharing, synchronized_precision, captain_autonomy: f32,
	command_ship_active:                                                    bool,
}

Combat_Terrain :: struct {
	kind:   Combat_Terrain_Kind,
	center: Combat_Vec3,
	radius: f32,
}
Combat_Wreckage_Field :: struct {
	center:                       Combat_Vec3,
	radius, tonnage:              f32,
	friendly_ships, raider_ships: int,
}
Combat_Interaction :: struct {
	kind:                     Combat_Interaction_Kind,
	position:                 Combat_Vec3,
	target:                   int,
	verb, title, consequence: string,
	active, complete:         bool,
}
Combat_Group :: struct {
	name:                                                            string,
	objective:                                                       Combat_Order,
	stance:                                                          Combat_Stance,
	doctrine:                                                        Combat_Doctrine,
	destination:                                                     Combat_Vec3,
	target, guard:                                                   int,
	pursuit_limit, withdraw_threshold:                               f32,
	priority:                                                        Combat_Target_Priority,
	posture:                                                         Combat_Group_Posture,
	ship_count, active_elements, plan_revision:                      int,
	strength, cohesion, readiness:                                   f32,
	survival_method:                                                 Combat_Survival_Method,
	emission_policy:                                                 Combat_Emission_Policy,
	attack_rhythm:                                                   Combat_Attack_Rhythm,
	displacement_trigger:                                            Combat_Displacement_Trigger,
	maneuver:                                                        Combat_Maneuver,
	maneuver_reason:                                                 Combat_Maneuver_Reason,
	maneuver_timer, preferred_range, escape_margin, last_fired_time: f32,
	planned_displacement:                                            Combat_Vec3,
	allow_fire, allow_burn:                                          bool,
	objective_policy:                                                Combat_Objective_Priority_Policy,
	engagement_policy:                                               Combat_Engagement_Policy,
	cohesion_policy:                                                 Combat_Cohesion_Policy,
	rescue_policy:                                                   Combat_Rescue_Policy,
	ordnance_policy:                                                 Combat_Ordnance_Policy,
	operation_boundary:                                             Combat_Plan_Volume,
	boundary_enforced:                                               bool,
}

// Combat_Ship_Record preserves exact hull consequences while command elements
// remain the tactical simulation entities. Records do not navigate,
// acquire targets, or run AI of their own.
Combat_Ship_Record :: struct {
	hull: f32,
}
