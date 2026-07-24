package game

import "core:fmt"
import "core:math"
combat_apply_damage :: proc(m: ^Combat_Mission, element: int, damage: f32) {
	if element < 0 || element >= m.unit_count || damage <= 0 do return
	u := &m.units[element]; active_before := u.formation_active; loss_position := u.position
	remaining := min(damage, max(u.hull, 0))
	u.hull = max(0, u.hull - damage)
	// Contiguous member order is stable; combat_ship_id derives the persistent
	// identity for any member without storing thousands of duplicate IDs.
	start := u.roster_start + u.damage_cursor
	end := u.roster_start + u.formation_ships
	for &ship, index in m.ships[start:end] {
		if remaining <= 0 do break
		if ship.hull <= 0 {u.damage_cursor = max(u.damage_cursor, index + 1); continue}
		applied := min(ship.hull, remaining); ship.hull -= applied; remaining -= applied
		if ship.hull <=
		   0 {ship.hull = 0; u.formation_active = max(u.formation_active - 1, 0); u.damage_cursor = max(u.damage_cursor, index + 1)}
	}
	u.cohesion = max(0, u.cohesion - damage / max(u.max_hull, 1) * 35)
	u.readiness = max(0, u.readiness - damage / max(u.max_hull, 1) * 12)
	subsystem_damage := clamp(damage / max(u.max_hull, 1) * 80, f32(0), f32(35))
	subsystem := int(combat_mix(m.seed ~ u64(element + 1) ~ m.event_serial) % 7)
	switch subsystem {
	case 0:
		u.subsystems.engines = max(0, u.subsystems.engines - subsystem_damage)
	case 1:
		u.subsystems.sensors = max(0, u.subsystems.sensors - subsystem_damage)
	case 2:
		u.subsystems.radiators = max(0, u.subsystems.radiators - subsystem_damage)
	case 3:
		u.subsystems.weapons = max(0, u.subsystems.weapons - subsystem_damage)
	case 4:
		u.subsystems.flight_deck = max(0, u.subsystems.flight_deck - subsystem_damage)
	case 5:
		u.subsystems.command = max(0, u.subsystems.command - subsystem_damage)
	case 6:
		u.subsystems.life_support = max(0, u.subsystems.life_support - subsystem_damage)
	}
	if u.hull <= 0 {u.hull = 0; u.disabled = true; u.formation_active = 0}
	combat_record_wreckage(m, element, max(active_before - u.formation_active, 0), loss_position)
}

combat_restore_element :: proc(m: ^Combat_Mission, element: int, hull: f32) {
	if element < 0 || element >= m.unit_count do return
	u := &m.units[element]; u.hull = clamp(hull, 0, u.max_hull); u.disabled = u.hull <= 0
	remaining := u.hull; u.formation_active = 0; u.damage_cursor = 0
	individual_hull := u.max_hull / f32(max(u.formation_ships, 1))
	for &ship in m.ships[u.roster_start:u.roster_start + u.formation_ships] {
		ship.hull = min(individual_hull, remaining); remaining -= ship.hull
		if ship.hull > 0 do u.formation_active += 1
	}
}

combat_maneuver_reason_name :: proc(reason:Combat_Maneuver_Reason)->string {switch reason {case .Searching:return "SEARCHING FOR CONTACT";case .Concealed_Route:return "MASKED ROUTE AVAILABLE";case .Building_Solution:return "BUILDING FIRING SOLUTION";case .Firing_Window:return "FIRING WINDOW OPEN";case .Shot_Exposed:return "WEAPONS EXPOSED THE GROUP";case .Track_Threat:return "HOSTILE TRACK IS FIRM";case .Pressure_Threat:return "FORMATION UNDER PRESSURE";case .Escape_Threat:return "ESCAPE MARGIN THREATENED";case .Cohesion_Low:return "FORMATION REFORMING";case .Objective_Safe:return "OBJECTIVE DOES NOT REQUIRE CONTACT"};return "SEARCHING FOR CONTACT"}

combat_group_contact :: proc(m:^Combat_Mission,side:Combat_Side,group:int)->(int,f32,f32) {
	best:=-1;best_solution:f32=0;best_distance:f32=1.0e9
	center:=Combat_Vec3{};count:f32=0
	for u in m.units[:m.unit_count] do if u.side==side&&u.group==group&&!u.disabled&&!u.extracted {center.x+=u.position.x;center.y+=u.position.y;center.z+=u.position.z;count+=1}
	if count>0 {center.x/=count;center.y/=count;center.z/=count}
	for _,index in m.units[:m.unit_count] {trace:=combat_group_contact_trace(m,side,group,index);if trace==nil||!combat_group_contact_targetable(m,side,group,index) do continue;position,ok:=combat_group_contact_position(m,side,group,index);if !ok do continue;distance:=combat_distance(center,position);if trace.solution_quality>best_solution||trace.solution_quality==best_solution&&distance<best_distance {best=index;best_solution=trace.solution_quality;best_distance=distance}}
	return best,best_solution,best_distance
}

combat_plan_group :: proc(m:^Combat_Mission,side:Combat_Side,group_index:int) {
	g:=combat_group_state(m,side,group_index)
	if g.plan_revision==0 {if side==.Raider {doctrine:=group_index==0?Combat_Doctrine.Hunter_Killer:group_index==1?.Cautious_Screen:.Balanced;combat_apply_group_doctrine(g,doctrine)} else {combat_apply_group_doctrine(g,g.doctrine)}}
	ships,active:=0,0;strength,cohesion,readiness,pressure,signature:f32
	for u in m.units[:m.unit_count] {if u.side!=side||u.group!=group_index do continue;ships+=u.formation_ships;if u.disabled||u.extracted do continue;active+=1;strength+=u.hull/max(u.max_hull,f32(1));cohesion+=u.cohesion;readiness+=u.readiness;pressure+=u.pressure;signature+=u.signature/max(u.base_signature,f32(.1))}
	g.ship_count=ships;g.active_elements=active;g.strength=active>0?strength/f32(active):0;g.cohesion=active>0?cohesion/f32(active):0;g.readiness=active>0?readiness/f32(active):0
	g.posture=active==0?.Unable:g.objective==.Withdraw||g.objective==.Extract?.Disengaging:g.objective==.Hold?.Holding:.Executing
	if active==0 {g.plan_revision+=1;return}
	pressure/=f32(active);signature/=f32(active);target,solution,distance:=combat_group_contact(m,side,group_index)
	threat_range:f32=150;closing:f32=0;escape_margin:f32
	if target>=0 {
		trace:=combat_group_contact_trace(m,side,group_index,target)
		if trace.identity==.Identified {
			switch m.units[target].role {
			case .Fighter: threat_range=90
			case .Bomber: threat_range=110
			case .Corvette: threat_range=125
			case .Recovery: threat_range=70
			case .Carrier: threat_range=180
			case .Capital: threat_range=230
			}
		}
		position,_:=combat_group_contact_position(m,side,group_index,target)
		dx,dy,dz:=position.x-g.destination.x,position.y-g.destination.y,position.z-g.destination.z
		length:=math.sqrt(dx*dx+dy*dy+dz*dz)
		if length>0 do closing=max(0,-(trace.velocity.x*dx+trace.velocity.y*dy+trace.velocity.z*dz)/length)*3
		escape_margin=distance-(threat_range+trace.error_radius+closing)
	} else {escape_margin=1.0e9}
	g.escape_margin=escape_margin
	masking:f32=0
	for u in m.units[:m.unit_count] do if u.side==side&&u.group==group_index&&!u.disabled&&!u.extracted&&combat_inside(u.position,m.terrain[0]) do masking+=1
	masking=clamp(masking/f32(max(active,1)),0,1)
	force_ratio:=clamp(g.strength/max(target>=0?combat_group_contact_trace(m,side,group_index,target).confidence:f32(.5),f32(.2)),.25,2)
	objective_progress:f32=.5
	if g.objective==.Control||g.objective==.Recover||g.objective==.Guard do objective_progress=.85
	fired_recently:=g.last_fired_time>0&&m.time-g.last_fired_time<=5
	candidates:=[10]Combat_Maneuver{.Shadow,.Masked_Approach,.Establish_Cross_Bearing,.Ambush,.Skirmish_Pass,.Fire_And_Displace,.Break_Contact,.Screen_Withdrawal,.Reform,.Decline_Engagement}
	next:=g.maneuver
	parameters:=combat_ai_parameters_for(m,side)
	current_score:=combat_maneuver_utility(g.maneuver,g^,parameters,target>=0,solution,distance,pressure,signature,masking,force_ratio,objective_progress,fired_recently)
	best_score:=current_score
	for candidate in candidates {
		if g.displacement_trigger==.Never&&(candidate==.Fire_And_Displace||candidate==.Break_Contact||candidate==.Decline_Engagement) do continue
		score:=combat_maneuver_utility(candidate,g^,parameters,target>=0,solution,distance,pressure,signature,masking,force_ratio,objective_progress,fired_recently)
		if score>best_score || score==best_score&&int(candidate)<int(next) {best_score=score;next=candidate}
	}
	if g.maneuver_timer>0 {
		g.maneuver_timer=max(0,g.maneuver_timer-1)
		next=g.maneuver
	} else if next!=g.maneuver&&best_score>=current_score+.15*parameters.hysteresis {
		g.maneuver=next
		g.maneuver_timer=4
	}
	reason:=Combat_Maneuver_Reason.Searching
	switch g.maneuver {
	case .Masked_Approach:reason=.Concealed_Route
	case .Establish_Cross_Bearing:reason=.Building_Solution
	case .Ambush,.Skirmish_Pass:reason=.Firing_Window
	case .Fire_And_Displace:reason=.Shot_Exposed
	case .Break_Contact:reason=pressure>=45?.Pressure_Threat:.Track_Threat
	case .Screen_Withdrawal:reason=.Objective_Safe
	case .Reform:reason=.Cohesion_Low
	case .Decline_Engagement:reason=.Escape_Threat
	case .Shadow:reason=.Searching
	}
	g.maneuver_reason=reason
	g.allow_fire=g.maneuver==.Ambush||g.maneuver==.Skirmish_Pass||g.attack_rhythm==.Sustained
	g.allow_burn=g.survival_method==.Mobility&&(g.maneuver==.Skirmish_Pass||g.maneuver==.Fire_And_Displace||g.maneuver==.Break_Contact)
	g.preferred_range=g.attack_rhythm==.Ambush?.9:g.attack_rhythm==.Repeated_Passes?.82:.68
	contact_position:=g.destination;if target>=0 do contact_position,_=combat_group_contact_position(m,side,group_index,target)
	side_sign:=side==.Friendly?f32(-1):f32(1);offset:=f32((group_index%3)-1)*90
	switch g.maneuver {case .Masked_Approach,.Break_Contact:g.planned_displacement=g.objective==.Control||g.objective==.Recover||g.objective==.Guard?g.destination:m.terrain[0].center;case .Fire_And_Displace:g.planned_displacement=g.objective==.Control||g.objective==.Recover?g.destination:Combat_Vec3{contact_position.x-side_sign*180,contact_position.y+offset+120,contact_position.z+offset*.35};case .Establish_Cross_Bearing:g.planned_displacement={contact_position.x-side_sign*max(distance*.72,f32(120)),contact_position.y+offset,contact_position.z-offset*.45};case .Skirmish_Pass:g.planned_displacement={contact_position.x-side_sign*max(distance*.78,f32(100)),contact_position.y+offset*1.4,contact_position.z+offset*.5};case .Decline_Engagement,.Screen_Withdrawal:g.planned_displacement=side==.Friendly?m.extraction:Combat_Vec3{520,contact_position.y,contact_position.z};case .Reform,.Shadow,.Ambush:g.planned_displacement=g.destination}
	if side == .Friendly && g.boundary_enforced {
		g.planned_displacement =
			combat_operation_clamp_to_volume(
				g.planned_displacement,
				g.operation_boundary,
			)
	}
	for &u in m.units[:m.unit_count] {if u.side!=side||u.group!=group_index||u.disabled||u.extracted do continue
		if side==.Raider do u.doctrine=g.doctrine
		u.maneuver_job=u.role==.Recovery?.Support:(.Sensors in combat_unit_modules(u)||u.hull_archetype==.Scout)?.Scout:u.role==.Fighter?.Screen:u.role==.Bomber||u.role==.Capital?.Main_Effort:.Reserve
		u.tactical_destination=g.planned_displacement;u.silent_running=u.silent_running_timer>0||g.survival_method==.Concealment&&(g.maneuver==.Shadow||g.maneuver==.Masked_Approach||g.maneuver==.Break_Contact)
		u.combat_burn=g.allow_burn&&!u.silent_running&&u.burn_heat<82
		switch g.emission_policy {case .Silent:u.communication=.Local;case .Passive_First:u.communication=g.allow_fire?.Burst:.Local;case .Burst_Sharing:u.communication=.Burst;if g.plan_revision%6==0 do u.network_burst_timer=1.5;case .Continuous:u.communication=.Continuous}
	}
	if side == .Friendly && g.rescue_policy != .Leave_Disabled &&
	   (g.rescue_policy == .Accept_Risk || pressure < 35) {
		disabled := -1
		for candidate, candidate_index in m.units[:m.friendly_count] do if
		   candidate.disabled && !candidate.extracted {
			disabled = candidate_index
			break
		}
		if disabled >= 0 {
			for &rescuer in m.units[:m.friendly_count] do if rescuer.group == group_index &&
			   !rescuer.disabled && !rescuer.extracted &&
			   (rescuer.role == .Recovery || .Repair in combat_unit_modules(rescuer)) {
				rescuer.order = .Recover
				rescuer.target = disabled
				rescuer.destination = m.units[disabled].position
				break
			}
		}
	}
	g.plan_revision+=1
}

combat_plan_groups :: proc(m: ^Combat_Mission) {
	for side in Combat_Side do for group_index in 0..<COMBAT_GROUP_COUNT do combat_plan_group(m,side,group_index)
}

combat_apply_heroism :: proc(u: ^Combat_Unit, power_divisor: f32) {
	if power_divisor <= 0 || u.side != .Raider do return
	u.hull /= power_divisor; u.max_hull = u.hull; u.damage /= power_divisor
}

combat_configure_capital :: proc(u: ^Combat_Unit, capital_type: Combat_Capital_Type) {
	u.capital_type = capital_type
	switch capital_type {
	case .Linebreaker:
		u.ability_charges = 2
	case .None:
	}
}

combat_ship_ability :: proc(u: Combat_Unit) -> Combat_Ship_Ability {switch
	u.hull_archetype {case .Scout:
		return .Silent_Running; case .Interceptor:
		return .Vector_Screen; case .Fighter:
		return .Combat_Air_Patrol; case .Strike_Fighter:
		return .Ripple_Strike; case .Bomber:
		return .Reserve_Torpedoes; case .Assault_Shuttle:
		return .Breach_Drop; case .Patrol_Boat:
		return .Pursuit_Burn; case .Corvette:
		return .Evasive_Screen; case .Torpedo_Boat:
		return .Ambush_Salvo; case .Gunship:
		return .Flak_Saturation; case .Picket_Frigate:
		return .Long_Baseline; case .Combat_Frigate:
		return .Adaptive_Countermeasures; case .Support_Frigate:
		return .Field_Repair; case .Minelayer_Frigate:
		return .Mine_Curtain; case .Destroyer:
		return .Overdrive_Pursuit; case .Light_Cruiser:
		return .Coordinated_Broadside; case .Heavy_Cruiser:
		return .Spinal_Salvo; case .Battlecruiser:
		return .Breakthrough_Burn; case .Battleship:
		return .Line_Barrage; case .Carrier:
		return .Flight_Surge; case .Dreadnought:
		return .Siege_Salvo; case .Utility_Hull:
		return .Tow_And_Restore; case .Transport_Hull:
		return .Cargo_Sacrifice; case .Habitat_Hull:
		return .Shelter_Fleet; case .Unspecified:
		return .None}
	return .None}
combat_ship_ability_name :: proc(a: Combat_Ship_Ability) -> string {switch a {case .Silent_Running:
		return "SILENT RUNNING"; case .Vector_Screen:
		return "VECTOR SCREEN"; case .Combat_Air_Patrol:
		return "COMBAT AIR PATROL"; case .Ripple_Strike:
		return "RIPPLE STRIKE"; case .Reserve_Torpedoes:
		return "RESERVE TORPEDOES"; case .Breach_Drop:
		return "BREACH DROP"; case .Pursuit_Burn:
		return "PURSUIT BURN"; case .Evasive_Screen:
		return "EVASIVE SCREEN"; case .Ambush_Salvo:
		return "AMBUSH SALVO"; case .Flak_Saturation:
		return "FLAK SATURATION"; case .Long_Baseline:
		return "LONG BASELINE"; case .Adaptive_Countermeasures:
		return "ADAPTIVE COUNTERMEASURES"; case .Field_Repair:
		return "FIELD REPAIR"; case .Mine_Curtain:
		return "MINE CURTAIN"; case .Overdrive_Pursuit:
		return "OVERDRIVE PURSUIT"; case .Coordinated_Broadside:
		return "COORDINATED BROADSIDE"; case .Spinal_Salvo:
		return "SPINAL SALVO"; case .Breakthrough_Burn:
		return "BREAKTHROUGH BURN"; case .Line_Barrage:
		return "LINE BARRAGE"; case .Flight_Surge:
		return "FLIGHT SURGE"; case .Siege_Salvo:
		return "SIEGE SALVO"; case .Tow_And_Restore:
		return "TOW AND RESTORE"; case .Cargo_Sacrifice:
		return "CARGO SACRIFICE"; case .Shelter_Fleet:
		return "SHELTER FLEET"; case .None:
		return "NO ABILITY"}; return "NO ABILITY"}
combat_ship_ability_requires_target :: proc(a: Combat_Ship_Ability) -> bool {return(
		a ==
		.Spinal_Salvo \
	)}

combat_ship_ability_time_to_impact :: proc(
	m: ^Combat_Mission,
	index: int,
	target: Combat_Vec3,
) -> (
	f32,
	bool,
) {
	if index < 0 || index >= m.friendly_count do return 0, false
	u := m.units[index]
	#partial switch combat_ship_ability(u) {
	case .Spinal_Salvo:
		distance := combat_distance(u.position, target)
		if distance < combat_weapon_minimum_range(.Spinal_Kinetic) ||
		   distance > combat_weapon_range(u, .Spinal_Kinetic) {
			return 0, false
		}
		return COMBAT_SPINAL_SALVO_LAUNCH_DELAY + combat_weapon_flight_minutes(.Spinal_Kinetic, distance), true
	case:
	}
	return 0, false
}

combat_capital_ability_ready :: proc(m: ^Combat_Mission, index: int) -> bool {
	if index < 0 || index >= m.friendly_count do return false
	u := m.units[index]
	return(
		!u.disabled &&
		!u.extracted &&
		u.ability_charges > 0 &&
		u.ability_cooldown <= 0 &&
		!m.ability_pending &&
		combat_ship_ability(u) != .None \
	)
}

combat_ship_ability_ready :: proc(
	m: ^Combat_Mission,
	index: int,
) -> bool {return combat_capital_ability_ready(m, index)}

combat_activate_ship_ability :: proc(
	m: ^Combat_Mission,
	index: int,
	target: Combat_Vec3 = {},
) -> bool {
	if !combat_ship_ability_ready(m, index) do return false
	u := &m.units[index]; ability := combat_ship_ability(u^)
	if ability == .Spinal_Salvo do return combat_activate_capital_ability(m, index, target)
	switch ability {
	case .Silent_Running:
		u.silent_running=true;u.silent_running_timer=12;u.combat_burn=false;u.active_sensors=false;u.communication=.Local;u.network_burst_timer=0;u.exposure=max(0,u.exposure-35);u.weapon_cooldown=max(u.weapon_cooldown,5)
		opposing:=u.side==.Friendly?Combat_Side.Raider:.Friendly;trace:=combat_contact_trace(m,opposing,index)
		if trace!=nil {trace.prediction_uncertainty=min(260,trace.prediction_uncertainty+65);trace.error_radius=min(300,trace.error_radius+65);trace.solution_quality=max(0,trace.solution_quality-.28);trace.confidence=max(0,trace.confidence-.16)}
		combat_add_event(m, "Scout element ceased transmissions and reduced thrust; hostile track quality fell.")
	case .Vector_Screen:
		for &ally in m.units[:m.friendly_count] do if ally.group == u.group && !ally.disabled && !ally.extracted {ally.decoys += 1; ally.cohesion = min(100, ally.cohesion + 15)}
		combat_add_event(m, "Fighter vectors tightened the task-group screen.")
	case .Combat_Air_Patrol:
		for &ally in m.units[:m.friendly_count] do if ally.group == u.group && !ally.disabled && !ally.extracted {ally.decoys += 2; ally.readiness = min(100, ally.readiness + 10)}
		combat_add_event(m, "Combat air patrol reinforced the task group.")
	case .Ripple_Strike:
		u.torpedoes += 1; u.weapon_cooldown = 0; u.readiness = min(
			100,
			u.readiness + 20,
		)
		combat_add_event(m, "Strike fighters synchronized a ripple attack.")
	case .Reserve_Torpedoes:
		u.torpedoes += 2; u.weapon_cooldown = 0
		combat_add_event(m, "Bomber reserve torpedoes moved to the ready racks.")
	case .Breach_Drop:
		u.torpedoes += 1; u.readiness = min(100, u.readiness + 35)
		u.cohesion = min(100, u.cohesion + 15)
		u.weapon_cooldown = 0
		combat_add_event(m, "Assault shuttles committed their breach teams and demolition stores.")
	case .Pursuit_Burn:
		u.speed *= 1.12; u.readiness = min(100, u.readiness + 20)
		combat_add_event(m, "Patrol boats opened their pursuit reserve.")
	case .Evasive_Screen:
		u.decoys += 3; combat_repair_element(m, index, u.max_hull * .1)
		combat_add_event(m, "Corvettes dispersed decoys through an evasive screen.")
	case .Ambush_Salvo:
		u.torpedoes += 3; u.weapon_cooldown = 0
		combat_add_event(m, "Torpedo boats opened concealed launch cells.")
	case .Flak_Saturation:
		for &ally in m.units[:m.friendly_count] do if !ally.disabled && !ally.extracted && combat_distance(ally.position, u.position) <= 150 {ally.decoys += 2; ally.cohesion = min(100, ally.cohesion + 12)}
		combat_add_event(m, "Gunship flak saturated the local volume.")
	case .Long_Baseline:
		for &ally in m.units[:m.friendly_count] do if ally.group == u.group && !ally.disabled && !ally.extracted {ally.readiness = min(100, ally.readiness + 25); ally.weapon_cooldown = max(0, ally.weapon_cooldown - 1)}
		combat_add_event(m, "Picket sensors established a long-baseline solution.")
	case .Adaptive_Countermeasures:
		for &ally in m.units[:m.friendly_count] do if ally.group == u.group && !ally.disabled && !ally.extracted {ally.decoys += 2; ally.readiness = min(100, ally.readiness + 15)}
		combat_add_event(m, "Combat frigate distributed adaptive countermeasures.")
	case .Field_Repair, .Tow_And_Restore:
		best := -1; missing: f32 = 0; radius: f32 = ability == .Tow_And_Restore ? 150 : 110; for ally, i in
		m.units[:m.friendly_count] {if i == index || ally.extracted || combat_distance(ally.position, u.position) > radius do continue
			gap := ally.max_hull - ally.hull
			if gap > missing {missing = gap; best = i}}
		if best < 0 do return false
		if m.units[best].disabled {combat_restore_element(
				m,
				best,
				m.units[best].max_hull * (ability == .Tow_And_Restore ? .2 : .14),
			)}
		else {combat_repair_element(
				m,
				best,
				m.units[best].max_hull * (ability == .Tow_And_Restore ? .22 : .18),
			)}
		m.units[best].readiness = min(100, m.units[best].readiness + 20)
		combat_add_event(m, ability == .Tow_And_Restore ? "Utility hull completed a tow-and-restore cycle." : "Support frigate completed field repairs.")
	case .Mine_Curtain:
		for &ally in m.units[:m.friendly_count] do if ally.group == u.group && !ally.disabled && !ally.extracted {ally.decoys += 2; ally.cohesion = min(100, ally.cohesion + 20)}
		combat_add_event(m, "Minelayer deployed a defensive curtain around the task group.")
	case .Overdrive_Pursuit:
		u.speed *= 1.1; u.weapon_cooldown = 0; u.readiness = min(100, u.readiness + 25)
		combat_add_event(m, "Destroyer committed its overdrive pursuit reserve.")
	case .Coordinated_Broadside:
		u.torpedoes += 1; u.weapon_cooldown = 0; u.readiness = min(
			100,
			u.readiness + 30,
		)
		u.cohesion = min(100, u.cohesion + 15)
		combat_add_event(m, "Cruiser batteries synchronized a coordinated broadside and released reserve ordnance.")
	case .Breakthrough_Burn:
		u.speed *= 1.08; u.weapon_cooldown = 0; u.cohesion = min(100, u.cohesion + 25)
		combat_add_event(m, "Battlecruiser committed to a breakthrough burn.")
	case .Line_Barrage:
		u.weapon_cooldown = 0; u.readiness = 100; u.torpedoes += 1
		combat_add_event(m, "Battleship opened the line-barrage magazines.")
	case .Flight_Surge:
		for &ally in m.units[:m.friendly_count] do if !ally.disabled && !ally.extracted && combat_distance(ally.position, u.position) <= 260 {ally.decoys += 1; ally.readiness = min(100, ally.readiness + 25); ally.cohesion = min(100, ally.cohesion + 10); ally.weapon_cooldown = max(0, ally.weapon_cooldown - 1)}
		combat_add_event(m, "Carrier surged flight operations and defensive sorties across nearby formations.")
	case .Siege_Salvo:
		u.weapon_cooldown = 0; u.readiness = 100; u.torpedoes += 2; u.cohesion = min(
			100,
			u.cohesion + 20,
		)
		combat_add_event(m, "Dreadnought released its siege-salvo reserve.")
	case .Cargo_Sacrifice:
		combat_repair_element(m, index, u.max_hull * .28); u.decoys += 2; for &ally in m.units[:m.friendly_count] do if ally.group == u.group && !ally.disabled && !ally.extracted do ally.cohesion = min(100, ally.cohesion + 12)
		combat_add_event(m, "Transport sacrificed mission stores for emergency reinforcement and a decoy screen.")
	case .Shelter_Fleet:
		for &ally in m.units[:m.friendly_count] do if !ally.disabled && !ally.extracted && combat_distance(ally.position, u.position) <= 220 {ally.decoys += 3; ally.cohesion = min(100, ally.cohesion + 25)}
		combat_add_event(m, "Habitat hull opened protected approaches to the fleet.")
	case .None, .Spinal_Salvo:
	}
	u.ability_charges -= 1; u.ability_cooldown = 45
	return true
}

combat_activate_capital_ability :: proc(
	m: ^Combat_Mission,
	index: int,
	target: Combat_Vec3,
) -> bool {
	if !combat_capital_ability_ready(m, index) do return false
	u := &m.units[index]
	time_to_impact, projected := combat_ship_ability_time_to_impact(m, index, target)
	if !projected do return false
	m.ability_pending =
		true; m.ability_kind = combat_ship_ability(u^); m.ability_source = index; m.ability_target = target; m.ability_timer = time_to_impact
	u.ability_charges -= 1; u.ability_cooldown = 75
	u.exposure=min(100,u.exposure+55);u.weapon_flash=.8
	combat_add_event_at(
		m,
		fmt.tprintf(
			"%s committed a spinal salvo; projected impact in %s",
			u.name,
			combat_format_duration(time_to_impact),
		),
		target,
	)
	return true
}
