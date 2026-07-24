package game

ship_operational_role_family :: proc(
	role: Ship_Operational_Role,
) -> Ship_Family {return ship_hull_archetype_family(ship_operational_role_hull(role))}

ship_operational_role_for_hull :: proc(
	seed: u64,
	strategic: Role,
	hull: Ship_Hull_Archetype,
) -> Ship_Operational_Role {
	switch hull {
	case .Scout:
		return .Scout; case .Interceptor:
		return .Interceptor; case .Fighter:
		return .Fighter; case .Strike_Fighter:
		return .Strike_Fighter; case .Bomber:
		return .Bomber; case .Assault_Shuttle:
		return .Assault_Shuttle
	case .Patrol_Boat:
		return .Patrol_Boat; case .Corvette:
		return .Corvette; case .Torpedo_Boat:
		return .Torpedo_Boat; case .Gunship:
		return .Gunship; case .Picket_Frigate:
		return .Picket_Ship
	case .Combat_Frigate:
		roles := [4]Ship_Operational_Role {
			.Flak_Frigate,
			.Missile_Frigate,
			.Electronic_Warfare_Frigate,
			.Shield_Frigate,
		}
		return roles[int(combat_mix(seed ~ u64(strategic)) % 4)]
	case .Support_Frigate:
		return .Support_Frigate; case .Minelayer_Frigate:
		return .Minelayer_Frigate
	case .Destroyer:
		return .Destroyer; case .Light_Cruiser:
		return .Light_Cruiser; case .Heavy_Cruiser:
		return .Heavy_Cruiser; case .Battlecruiser:
		return .Battlecruiser; case .Battleship:
		return .Battleship; case .Dreadnought:
		return .Dreadnought
	case .Carrier:
		if strategic == .Escort do return .Escort_Carrier; if strategic == .Archive || strategic == .Survey do return .Command_Ship
		return .Fleet_Carrier
	case .Utility_Hull:
		switch strategic {case .Hospital:
			return .Hospital_Ship; case .Survey, .Archive:
			return .Courier; case .Foundry:
			return .Recovery_Tug; case .Habitat, .Agriculture, .Escort, .Colony:
			return .Tanker}
	case .Transport_Hull:
		switch strategic {case .Foundry:
			return .Fabricator_Ship; case .Colony:
			return(
				.Colony_Transport \
			); case .Habitat, .Agriculture, .Archive, .Hospital, .Survey, .Escort:
			return .Freighter}
	case .Habitat_Hull:
		switch strategic {case .Archive:
			return .Seedship; case .Colony:
			return(
				(combat_mix(seed) & 3) == 0 ? .Arkship : .Generation_Ship \
			); case .Habitat, .Agriculture, .Foundry, .Hospital, .Survey, .Escort:
			return .Habitat_Ship}
	case .Unspecified:
		return .Unspecified
	}; return .Unspecified
}

ship_operational_role_modules :: proc(role: Ship_Operational_Role) -> Ship_Modules {
	switch role {
	case .Scout, .Picket_Ship:
		return {.Sensors}; case .Interceptor:
		return {.Sensors, .Interception}; case .Fighter:
		return {.Interception}; case .Strike_Fighter:
		return {.Missiles}; case .Bomber, .Torpedo_Boat:
		return {.Torpedoes}; case .Assault_Shuttle:
		return {.Boarding}
	case .Patrol_Boat:
		return {
			.Sensors,
			.Boarding,
		}; case .Corvette, .Gunship, .Destroyer, .Light_Cruiser, .Heavy_Cruiser, .Battlecruiser, .Battleship, .Dreadnought:
		return {.Flak, .Missiles}; case .Flak_Frigate:
		return {.Flak}; case .Missile_Frigate:
		return {.Missiles}; case .Electronic_Warfare_Frigate:
		return {.Electronic_Warfare}; case .Shield_Frigate:
		return {.Active_Defense, .Electronic_Warfare, .Flak}; case .Support_Frigate:
		return {.Repair, .Recovery}; case .Minelayer_Frigate:
		return {.Mines, .Sensors}
	case .Escort_Carrier:
		return {.Flight_Deck, .Flak}; case .Fleet_Carrier:
		return {.Flight_Deck, .Repair}; case .Command_Ship:
		return {.Command, .Sensors, .Electronic_Warfare, .Flight_Deck}
	case .Courier:
		return {.Cargo, .Sensors}; case .Freighter:
		return {.Cargo}; case .Tanker:
		return {.Tankage}; case .Fabricator_Ship:
		return {.Fabrication, .Cargo}; case .Recovery_Tug:
		return {.Recovery, .Repair}; case .Hospital_Ship:
		return {.Medical}; case .Habitat_Ship:
		return {.Habitat}; case .Colony_Transport:
		return {.Colony, .Cargo}; case .Seedship:
		return {.Archive, .Fabrication}; case .Generation_Ship:
		return {.Habitat, .Fabrication}; case .Arkship:
		return {.Habitat, .Archive, .Fabrication}; case .Unspecified:
		return {}
	}; return {}
}

ship_operational_profile :: proc(role: Ship_Operational_Role) -> (p: Ship_Operational_Profile) {
	modules := ship_operational_role_modules(role)
	if .Sensors in modules do p.recon = 70; if .Interception in modules do p.interception = 80; if .Flak in modules do p.point_defense = 75; if .Missiles in modules {p.long_range = 65; p.anti_ship = 45}; if .Torpedoes in modules do p.anti_ship = 90; if .Boarding in modules {p.boarding = 80; p.capture = 55}; if .Electronic_Warfare in modules do p.electronic_warfare = 80; if .Active_Defense in modules {p.shield = 85; p.point_defense = max(p.point_defense, 85)}; if .Repair in modules do p.repair = 80; if .Recovery in modules do p.recovery = 85; if .Mines in modules do p.area_denial = 90; if .Command in modules do p.command = 90; if .Flight_Deck in modules do p.flight_support = 85; if .Cargo in modules do p.cargo = 75; if .Tankage in modules do p.propellant = 95; if .Fabrication in modules do p.fabrication = 85; if .Medical in modules do p.medical = 95; if .Habitat in modules do p.population = 90; if .Colony in modules do p.colony = 95; if .Archive in modules do p.archive = 95
	switch role {
	case .Scout:
		p.recon = 100; p.stealth = 90
	case .Interceptor:
		p.interception = 100
	case .Fighter:
		p.interception = 75; p.point_defense = 55
	case .Strike_Fighter:
		p.anti_ship = 68
	case .Bomber:
		p.anti_ship = 100
	case .Assault_Shuttle:
		p.boarding = 100; p.capture = 100
	case .Patrol_Boat:
		p.capture = 90; p.recon = max(p.recon, 45)
	case .Corvette:
		p.interception = 65; p.point_defense = 55
	case .Torpedo_Boat:
		p.stealth = 60; p.anti_ship = 100
	case .Picket_Ship:
		p.recon = 100
	case .Gunship:
		p.point_defense = 70
	case .Flak_Frigate:
		p.point_defense = 100
	case .Missile_Frigate:
		p.long_range = 100
	case .Electronic_Warfare_Frigate:
		p.electronic_warfare = 100
	case .Shield_Frigate:
		p.shield = 100; p.point_defense = 100; p.electronic_warfare = max(p.electronic_warfare, 80)
	case .Support_Frigate:
		p.repair = 100; p.recovery = 90
	case .Minelayer_Frigate:
		p.area_denial = 100
	case .Destroyer:
		p.anti_ship = 78
	case .Light_Cruiser:
		p.recon = 50; p.point_defense = 60; p.anti_ship = 65
	case .Heavy_Cruiser:
		p.anti_ship = 82
	case .Battlecruiser:
		p.anti_ship = 95
	case .Battleship:
		p.anti_ship = 100; p.point_defense = 85
	case .Dreadnought:
		p.anti_ship = 100; p.command = 70
	case .Escort_Carrier:
		p.flight_support = 70; p.point_defense = 65
	case .Fleet_Carrier:
		p.flight_support = 100; p.repair = 55
	case .Command_Ship:
		p.command = 100; p.recon = 85
	case .Courier:
		p.cargo = 25; p.stealth = 55; p.recon = 60
	case .Freighter:
		p.cargo = 100
	case .Tanker:
		p.propellant = 100; p.cargo = 45
	case .Fabricator_Ship:
		p.fabrication = 100; p.cargo = 65
	case .Recovery_Tug:
		p.recovery = 100; p.repair = 65
	case .Hospital_Ship:
		p.medical = 100; p.population = 35
	case .Habitat_Ship:
		p.population = 100
	case .Colony_Transport:
		p.colony = 100; p.cargo = 85; p.population = 65
	case .Seedship:
		p.archive = 100; p.fabrication = 70; p.colony = 60
	case .Generation_Ship:
		p.population = 100; p.fabrication = 85; p.medical = 65; p.colony = 75
	case .Arkship:
		p.population = 100; p.fabrication = 100; p.medical = 100; p.archive = 100; p.colony = 100
	case .Unspecified:
	}
	return
}

ship_hull_archetype_name :: proc(archetype: Ship_Hull_Archetype) -> string {
	switch archetype {
	case .Scout:
		return "scout"
	case .Interceptor:
		return "interceptor"
	case .Fighter:
		return "fighter"
	case .Strike_Fighter:
		return "strike fighter"
	case .Bomber:
		return "bomber"
	case .Assault_Shuttle:
		return "assault shuttle"
	case .Patrol_Boat:
		return "patrol boat"
	case .Corvette:
		return "corvette"
	case .Torpedo_Boat:
		return "torpedo boat"
	case .Gunship:
		return "gunship"
	case .Picket_Frigate:
		return "picket frigate"
	case .Combat_Frigate:
		return "combat frigate"
	case .Support_Frigate:
		return "support frigate"
	case .Minelayer_Frigate:
		return "minelayer frigate"
	case .Destroyer:
		return "destroyer"
	case .Light_Cruiser:
		return "light cruiser"
	case .Heavy_Cruiser:
		return "heavy cruiser"
	case .Battlecruiser:
		return "battlecruiser"
	case .Battleship:
		return "battleship"
	case .Carrier:
		return "carrier"
	case .Dreadnought:
		return "dreadnought"
	case .Utility_Hull:
		return "utility hull"
	case .Transport_Hull:
		return "transport hull"
	case .Habitat_Hull:
		return "habitat hull"
	case .Unspecified:
		return "unspecified"
	}
	return "unspecified"
}

ship_hull_archetype_family :: proc(archetype: Ship_Hull_Archetype) -> Ship_Family {
	switch archetype {
	case .Scout, .Interceptor, .Fighter, .Strike_Fighter, .Bomber, .Assault_Shuttle:
		return .Strike_Craft
	case .Patrol_Boat, .Corvette, .Torpedo_Boat, .Gunship:
		return .Light_Combatant
	case .Picket_Frigate, .Combat_Frigate, .Support_Frigate, .Minelayer_Frigate:
		return .Frigate
	case .Destroyer, .Light_Cruiser, .Heavy_Cruiser, .Battlecruiser, .Battleship, .Dreadnought:
		return .Line_Warship
	case .Carrier:
		return .Carrier_And_Command
	case .Utility_Hull, .Transport_Hull, .Habitat_Hull:
		return .Diaspora
	case .Unspecified:
		return .Unspecified
	}
	return .Unspecified
}

ship_hull_archetype_class :: proc(archetype: Ship_Hull_Archetype) -> Hull_Class {
	switch archetype {
	case .Scout, .Interceptor, .Fighter, .Strike_Fighter, .Bomber, .Assault_Shuttle:
		return .Strike_Craft
	case .Patrol_Boat, .Corvette, .Torpedo_Boat, .Gunship:
		return .Corvette
	case .Picket_Frigate,
	     .Combat_Frigate,
	     .Support_Frigate,
	     .Minelayer_Frigate,
	     .Destroyer,
	     .Utility_Hull,
	     .Transport_Hull:
		return .Fleet_Ship
	case .Light_Cruiser, .Heavy_Cruiser, .Battlecruiser, .Carrier:
		return .Cruiser
	case .Battleship, .Dreadnought, .Habitat_Hull:
		return .Capital_Ship
	case .Unspecified:
		return .Unspecified
	}
	return .Unspecified
}

ship_hull_archetype_from_role :: proc(
	seed: u64,
	role: Role,
	hull_class: Hull_Class,
) -> Ship_Hull_Archetype {
	strike := [6]Ship_Hull_Archetype {
		.Scout,
		.Interceptor,
		.Fighter,
		.Strike_Fighter,
		.Bomber,
		.Assault_Shuttle,
	}
	light := [4]Ship_Hull_Archetype{.Patrol_Boat, .Corvette, .Torpedo_Boat, .Gunship}
	frigate := [7]Ship_Hull_Archetype {
		.Picket_Frigate,
		.Combat_Frigate,
		.Support_Frigate,
		.Minelayer_Frigate,
		.Destroyer,
		.Utility_Hull,
		.Transport_Hull,
	}
	cruiser := [4]Ship_Hull_Archetype{.Light_Cruiser, .Heavy_Cruiser, .Battlecruiser, .Carrier}
	capital := [3]Ship_Hull_Archetype{.Battleship, .Dreadnought, .Habitat_Hull}
	mix := ship_generator_stream(seed ~ u64(role), 0x243f6a8885a308d3)
	switch hull_class {
	case .Strike_Craft:
		return strike[int(fleet_generator_next(&mix) % u64(len(strike)))]
	case .Corvette:
		return light[int(fleet_generator_next(&mix) % u64(len(light)))]
	case .Fleet_Ship:
		return frigate[int(fleet_generator_next(&mix) % u64(len(frigate)))]
	case .Cruiser:
		return cruiser[int(fleet_generator_next(&mix) % u64(len(cruiser)))]
	case .Capital_Ship:
		return capital[int(fleet_generator_next(&mix) % u64(len(capital)))]
	case .Unspecified:
		return .Unspecified
	}
	return .Unspecified
}

ship_hull_archetype_is_scenario_defining :: proc(archetype: Ship_Hull_Archetype) -> bool {return(
		archetype == .Battleship ||
		archetype == .Dreadnought \
	)}

ship_hull_archetype_for_ordinary_roster :: proc(
	seed: u64,
	role: Role,
	hull_class: Hull_Class,
) -> Ship_Hull_Archetype {
	archetype := ship_hull_archetype_from_role(seed, role, hull_class)
	if archetype == .Battleship || archetype == .Dreadnought do return .Habitat_Hull
	return archetype
}

ship_operational_role_for_ordinary_roster :: proc(
	seed: u64,
	strategic: Role,
	hull: Ship_Hull_Archetype,
) -> Ship_Operational_Role {
	role := ship_operational_role_for_hull(seed, strategic, hull)
	if role == .Generation_Ship || role == .Arkship do return .Habitat_Ship
	return role
}

