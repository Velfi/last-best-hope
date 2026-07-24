package game

import "core:fmt"
import "core:math"

combat_engine_power_for_mass :: proc(mass_tonnes: i64) -> f32 {
	// Installed drive power grows with hull size, but less quickly than mass.
	// Acceleration therefore emerges from thrust-to-mass ratio instead of role.
	mass := max(f64(mass_tonnes), 1)
	return f32(115 * math.pow(mass, .9))
}

combat_apply_mass_mobility :: proc(u: ^Combat_Unit) {
	u.engine_power = combat_engine_power_for_mass(u.tonnage_each)
	u.max_acceleration = u.engine_power / f32(max(u.tonnage_each, 1))
}

combat_unit :: proc(
	name, commander, trait, history: string,
	side: Combat_Side,
	role: Combat_Role,
	p: Combat_Vec3,
) -> Combat_Unit {
	hull: f32 = 100; range: f32 = 150; damage: f32 = 7; speed: f32 = 52; craft := 1; torps := 0
	switch role {
	case .Fighter:
		hull = 54; range = 82; damage = 8; speed = 82; craft = 8
	case .Bomber:
		hull = 62; range = 70; damage = 15; speed = 63; craft = 6; torps = 4
	case .Corvette:
		hull = 82; range = 105; damage = 10; speed = 58; craft = 3
	case .Recovery:
		hull = 90; range = 55; damage = 3; speed = 38
	case .Carrier:
		hull = 150; range = 165; damage = 8; speed = 30
	case .Capital:
		hull = 230; range = 210; damage = 17; speed = 22; torps = 3
	}
	archetype := Ship_Hull_Archetype.Fighter; operational := Ship_Operational_Role.Fighter
	switch role {case .Fighter:
		archetype = .Fighter; operational = .Fighter; case .Bomber:
		archetype = .Bomber; operational = .Bomber; case .Corvette:
		archetype = .Corvette; operational = .Corvette; case .Recovery:
		archetype = .Utility_Hull; operational = .Recovery_Tug; case .Carrier:
		archetype = .Carrier; operational = .Fleet_Carrier; case .Capital:
		archetype = .Heavy_Cruiser; operational = .Heavy_Cruiser}
	captain_trait := Passage_Ship_Trait.None
	switch trait {case "Cautious":
		captain_trait = .Cautious; case "Protective":
		captain_trait = .Protective; case "Veteran bombers", "Scarred prow", "Roving", "Objective raider":
		captain_trait = .Committed; case "Improvised carrier":
		captain_trait = .Independent; case:}
	unit := Combat_Unit {
		name                 = name,
		commander            = commander,
		trait                = trait,
		history              = history,
		side                 = side,
		role                 = role,
		hull_archetype       = archetype,
		operational_role     = operational,
		doctrine             = .Balanced,
		captain_trait        = captain_trait,
		order                = .Hold,
		action               = .Holding,
		position             = p,
		destination          = p,
		tactical_destination = p,
		target               = -1,
		guard                = -1,
		hull                 = hull,
		max_hull             = hull,
		range                = range,
		damage               = damage,
		speed                = speed,
		turn_authority       = role == .Capital ? .45 : 1,
		base_signature       = combat_contact_signature_for_archetype(archetype),
		signature            = combat_contact_signature_for_archetype(archetype),
		communication        = .Local,
		maneuver_job         = .Main_Effort,
		sensor_mode          = .Passive_Watch,
		maneuver_intent      = .Hold_Geometry,
		subsystems           = {100, 100, 100, 100, 100, 100, 100},
		facing               = 0,
		turn_rate            = role == .Capital ? .55 : 1.8,
		craft                = craft,
		max_craft            = craft,
		torpedoes            = torps,
		decoys               = role == .Fighter || role == .Corvette ? 2 : 1,
		chaff                = role == .Capital || role == .Carrier ? 4 : 2,
		flares               = 2,
		weapon_packages      = {
			ship_weapon_package_for(Ship_ID(int(role) + 1), archetype, operational),
		},
		defense_packages     = ship_defense_packages_for(
			Ship_ID(int(role) + 1),
			archetype,
			operational,
		),
		veterancy            = side == .Friendly ? 2 : 1,
		formation_ships      = 1,
		formation_active     = 1,
		tonnage_each         = ship_hull_archetype_nominal_mass(archetype),
		engagement_target    = -1,
		denied_target        = -1,
		costly_denied_target = -1,
		cohesion             = 100,
		readiness            = 100,
		ability_charges      = side == .Friendly ? 2 : 0,
	}
	combat_apply_mass_mobility(&unit)
	unit.drive_acceleration_g = f32(combat_role_acceleration_g(unit))
	unit.max_acceleration = combat_acceleration_units_per_minute2(f64(unit.drive_acceleration_g))
	unit.speed = combat_role_cruise_speed_units_per_minute(unit)
	return unit
}

combat_unit_primary_weapon :: proc(u: Combat_Unit) -> Ship_Weapon_Package {
	for value in 1 ..= int(Ship_Weapon_Package.Heavy_Torpedoes) do if Ship_Weapon_Package(value) in u.weapon_packages do return Ship_Weapon_Package(value)
	return ship_weapon_package_for(Ship_ID(u.group + 1), u.hull_archetype, u.operational_role)
}

combat_emergency_defense :: proc(m: ^Combat_Mission, index: int) -> bool {
	if index < 0 || index >= m.friendly_count do return false; u := &m.units[index]
	if u.disabled || u.extracted || u.defense_cooldown > 0 || u.chaff + u.flares + u.decoys <= 0 do return false
	inbound :=
		false; for &salvo in m.salvos do if salvo.active && salvo.side != u.side && salvo.target == index {inbound = true; salvo.guidance = max(.08, salvo.guidance - .28); salvo.evasion = min(1, salvo.evasion + .32)}
	if !inbound do return false
	if u.decoys > 0 {
		u.decoys -= 1
	} else if u.chaff > 0 {
		u.chaff -= 1
	} else {
		u.flares -= 1
	}
	u.readiness = max(
		0,
		u.readiness - 18,
	); u.weapon_cooldown = max(u.weapon_cooldown, 2.5); u.exposure = min(100, u.exposure + 22); u.defense_cooldown = 18; u.defense_response = "Emergency defense committed"
	combat_add_event_at(
		m,
		fmt.tprintf("%s committed emergency countermeasures", u.name),
		u.position,
	); return true
}

combat_configure_archetype :: proc(
	u: ^Combat_Unit,
	archetype: Ship_Hull_Archetype,
	operational: Ship_Operational_Role,
) {
	if archetype == .Unspecified || operational == .Unspecified || !ship_operational_role_fits_hull(operational, archetype) do return
	u.hull_archetype =
		archetype; u.operational_role = operational; u.tonnage_each = ship_hull_archetype_nominal_mass(archetype)
	// Differences are responses, not hard counters. Geometry, doctrine, terrain,
	// readiness, and veterancy continue to determine the engagement.
	switch archetype {
	case .Scout:
		u.speed *= 1.22; u.range *= .82; u.damage *= .55; u.hull *= .72
	case .Interceptor:
		u.speed *= 1.28; u.range *= .72; u.damage *= .86; u.hull *= .9
	case .Strike_Fighter:
		u.speed *= 1.08; u.damage *= 1.14; u.torpedoes = max(u.torpedoes, 1)
	case .Assault_Shuttle:
		u.speed *= .82; u.hull *= 1.18; u.damage *= .62
	case .Patrol_Boat:
		u.speed *= 1.08; u.hull *= .78; u.damage *= .72
	case .Torpedo_Boat:
		u.hull *= .68; u.damage *= 1.32; u.torpedoes = max(u.torpedoes, 3)
	case .Gunship:
		u.speed *= .9; u.range *= .82; u.hull *= 1.18; u.damage *= 1.12
	case .Picket_Frigate:
		u.range *= 1.32; u.damage *= .72
	case .Combat_Frigate:
		if operational == .Missile_Frigate {u.range *= 1.45; u.damage *= 1.08}
		if operational == .Flak_Frigate {u.range *= .72; u.damage *= 1.12}
	case .Support_Frigate:
		u.damage *= .42; u.hull *= 1.08
	case .Minelayer_Frigate:
		u.damage *= .78; u.range *= 1.12
	case .Destroyer:
		u.speed *= 1.08; u.damage *= 1.25; u.hull *= 1.08
	case .Light_Cruiser:
		u.speed *= 1.08; u.hull *= 1.18
	case .Heavy_Cruiser:
		u.hull *= 1.35; u.damage *= 1.2
	case .Battlecruiser:
		u.speed *= 1.08; u.damage *= 1.45; u.hull *= 1.12
	case .Battleship:
		u.speed *= .78; u.hull *= 1.8; u.damage *= 1.55
	case .Carrier:
		u.damage *= .62; u.hull *= 1.15; u.craft = max(u.craft, 12); u.max_craft = u.craft
	case .Dreadnought:
		u.speed *= .58; u.hull *= 2.5; u.damage *= 1.9
	case .Utility_Hull:
		u.damage *= .38; u.speed *= operational == .Courier ? 1.35 : 1
		if operational == .Recovery_Tug do u.hull *= 2
	case .Transport_Hull:
		u.damage *= .32; u.hull *= 1.12; u.speed *= .76
	case .Habitat_Hull:
		u.damage *= .22; u.hull *= 2.1; u.speed *= .48
	case .Fighter, .Bomber, .Corvette:
	case .Unspecified:
	}
	u.max_hull = u.hull
	u.base_signature = combat_contact_signature_for_archetype(
		archetype,
	); u.signature = u.base_signature
	combat_apply_mass_mobility(u)
	u.drive_acceleration_g = f32(combat_role_acceleration_g(u^))
	u.max_acceleration = combat_acceleration_units_per_minute2(f64(u.drive_acceleration_g))
	u.speed = combat_role_cruise_speed_units_per_minute(u^)
	u.turn_authority =
		ship_hull_archetype_family(archetype) == .Line_Warship ? f32(.55) : ship_hull_archetype_family(archetype) == .Carrier_And_Command ? f32(.48) : f32(1)
}

combat_configure_roster_archetype :: proc(u: ^Combat_Unit, variant: int) {
	switch u.role {
	case .Fighter:
		archetypes := [4]Ship_Hull_Archetype{.Scout, .Interceptor, .Fighter, .Strike_Fighter}
		roles := [4]Ship_Operational_Role{.Scout, .Interceptor, .Fighter, .Strike_Fighter}
		at := variant % 4
		combat_configure_archetype(u, archetypes[at], roles[at])
	case .Bomber:
		if variant % 2 ==
		   0 {combat_configure_archetype(u, .Bomber, .Bomber)} else {combat_configure_archetype(u, .Assault_Shuttle, .Assault_Shuttle)}
	case .Corvette:
		archetypes := [8]Ship_Hull_Archetype {
			.Patrol_Boat,
			.Corvette,
			.Torpedo_Boat,
			.Gunship,
			.Picket_Frigate,
			.Combat_Frigate,
			.Support_Frigate,
			.Minelayer_Frigate,
		}
		roles := [8]Ship_Operational_Role {
			.Patrol_Boat,
			.Corvette,
			.Torpedo_Boat,
			.Gunship,
			.Picket_Ship,
			.Flak_Frigate,
			.Support_Frigate,
			.Minelayer_Frigate,
		}
		at := variant % 8
		combat_configure_archetype(u, archetypes[at], roles[at])
	case .Recovery:
		combat_configure_archetype(u, .Utility_Hull, .Recovery_Tug)
	case .Carrier:
		combat_configure_archetype(
			u,
			.Carrier,
			variant % 3 == 0 ? .Escort_Carrier : variant % 3 == 1 ? .Fleet_Carrier : .Command_Ship,
		)
	case .Capital:
		archetypes := [6]Ship_Hull_Archetype {
			.Destroyer,
			.Light_Cruiser,
			.Heavy_Cruiser,
			.Battlecruiser,
			.Battleship,
			.Dreadnought,
		}
		roles := [6]Ship_Operational_Role {
			.Destroyer,
			.Light_Cruiser,
			.Heavy_Cruiser,
			.Battlecruiser,
			.Battleship,
			.Dreadnought,
		}
		at := variant % 6
		combat_configure_archetype(u, archetypes[at], roles[at])
	}
}

combat_ship_id :: proc(seed: u64, element, member: int) -> u64 {
	return combat_mix(seed ~ (u64(element + 1) * 0x9e3779b97f4a7c15) ~ u64(member + 1))
}

combat_add_element :: proc(m: ^Combat_Mission, u: Combat_Unit) -> int {
	index := len(m.units)
	append(&m.units, u)
	append(&m.wreckage_pending, 0)
	append(&m.wreckage_pending_tonnage, 0)
	append(&m.wreckage_pending_position, Combat_Vec3{})
	append(&m.withdraw_request_made, false)
	for side := 0; side < 2; side += 1 {
		append(&m.contacts[side], Combat_Contact_Trace{})
		for group in 0 ..< COMBAT_GROUP_COUNT do append(&m.group_contacts[side][group], Combat_Contact_Trace{})
	}
	m.unit_count = len(m.units)
	return index
}

combat_truncate_elements :: proc(m: ^Combat_Mission, count: int) {
	bounded := clamp(count, 0, len(m.units))
	resize(&m.units, bounded)
	resize(&m.wreckage_pending, bounded)
	resize(&m.wreckage_pending_tonnage, bounded)
	resize(&m.wreckage_pending_position, bounded)
	resize(&m.withdraw_request_made, bounded)
	for side in 0 ..< 2 {
		resize(&m.contacts[side], bounded)
		for group in 0 ..< COMBAT_GROUP_COUNT do resize(&m.group_contacts[side][group], bounded)
	}
	m.unit_count = bounded
}

combat_build_ship_roster :: proc(m: ^Combat_Mission) {
	if m.ships != nil do delete(m.ships)
	total := 0; for u in m.units[:m.unit_count] do total += max(u.formation_ships, 1)
	total = min(
		total,
		COMBAT_MAX_SHIPS,
	); m.ships = make([]Combat_Ship_Record, total); m.ship_count = 0
	for &u in m.units[:m.unit_count] {
		count := max(u.formation_ships, 1)
		available := COMBAT_MAX_SHIPS - m.ship_count
		count = min(count, available)
		u.formation_ships =
			count; u.formation_active = count; u.roster_start = m.ship_count; u.damage_cursor = 0
		if count <= 0 do continue
		individual_hull := u.max_hull / f32(count)
		for _ in 0 ..< count {
			m.ships[m.ship_count] = {
				hull = individual_hull,
			}
			m.ship_count += 1
		}
	}
}

combat_append_element_roster :: proc(m: ^Combat_Mission, element: int) {
	if element < 0 || element >= m.unit_count do return
	u := &m.units[element]; count := min(max(u.formation_ships, 1), COMBAT_MAX_SHIPS - m.ship_count)
	u.formation_ships =
		count; u.formation_active = count; u.roster_start = m.ship_count; u.damage_cursor = 0
	if count <= 0 do return
	resized := make(
		[]Combat_Ship_Record,
		m.ship_count + count,
	); copy(resized, m.ships); if m.ships != nil do delete(m.ships); m.ships = resized
	individual_hull := u.max_hull / f32(count)
	for _ in 0 ..< count {m.ships[m.ship_count] = {
			hull = individual_hull,
		}; m.ship_count += 1}
}

combat_mission_destroy :: proc(m: ^Combat_Mission) {if m == nil do return; if m.ships != nil do delete(m.ships)
	delete(m.units)
	delete(m.salvos)
	for side := 0; side < 2; side += 1 {
		delete(m.contacts[side])
		for group := 0; group < COMBAT_GROUP_COUNT; group += 1 {
			delete(m.group_contacts[side][group])
			m.group_contacts[side][group] = nil
		}
	}
	delete(m.wreckage_pending)
	delete(m.wreckage_pending_tonnage)
	delete(m.wreckage_pending_position)
	delete(m.withdraw_request_made)
	delete(m.campaign_ships)
	delete(m.campaign_ship_elements)
	delete(m.campaign_ship_roster_indices)
	m.ships = nil
	m.units = nil
	m.salvos = nil
	m.salvo_count = 0
	for side in 0 ..< 2 do m.contacts[side] = nil
	m.wreckage_pending = nil
	m.wreckage_pending_tonnage = nil
	m.wreckage_pending_position = nil
	m.withdraw_request_made = nil
	m.campaign_ships = nil
	m.campaign_ship_elements = nil
	m.campaign_ship_roster_indices = nil
	m.campaign_ship_count = 0
	m.ship_count = 0
	m.unit_count = 0
	m.friendly_count = 0}

combat_mission_duration :: proc(m: ^Combat_Mission) -> f32 {return(
		m.scenario == .Finale ? COMBAT_FINALE_DURATION : COMBAT_DURATION \
	)}
