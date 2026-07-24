package game

import "core:testing"

// Ship_Hull_Archetype is the production vocabulary: the distinct physical
// hulls that yards build. Role remains a ship's strategic diaspora duty;
// equipment and assignment may change without changing this value.
Ship_Hull_Archetype :: enum u8 {
	Unspecified,
	Scout,
	Interceptor,
	Fighter,
	Strike_Fighter,
	Bomber,
	Assault_Shuttle,
	Patrol_Boat,
	Corvette,
	Torpedo_Boat,
	Gunship,
	Picket_Frigate,
	Combat_Frigate,
	Support_Frigate,
	Minelayer_Frigate,
	Destroyer,
	Light_Cruiser,
	Heavy_Cruiser,
	Battlecruiser,
	Battleship,
	Carrier,
	Dreadnought,
	Utility_Hull,
	Transport_Hull,
	Habitat_Hull,
}

Ship_Family :: enum u8 {
	Unspecified,
	Strike_Craft,
	Light_Combatant,
	Frigate,
	Line_Warship,
	Carrier_And_Command,
	Diaspora,
}

ship_family_name :: proc(family: Ship_Family) -> string {switch family {case .Strike_Craft:
		return "STRIKE CRAFT"; case .Light_Combatant:
		return "LIGHT COMBATANTS"; case .Frigate:
		return "FRIGATES"; case .Line_Warship:
		return "LINE WARSHIPS"; case .Carrier_And_Command:
		return "CARRIERS & COMMAND"; case .Diaspora:
		return "CIVILIAN & DIASPORA"; case .Unspecified:
		return "UNSPECIFIED"}; return "UNSPECIFIED"}

SHIP_HULL_ARCHETYPE_COUNT :: 24

// The source design says "roughly 35" roles, but enumerates 37. Preserve every
// named role; production scope stays bounded because they share 24 hulls.
Ship_Operational_Role :: enum u8 {
	Unspecified,
	Scout,
	Interceptor,
	Fighter,
	Strike_Fighter,
	Bomber,
	Assault_Shuttle,
	Patrol_Boat,
	Corvette,
	Torpedo_Boat,
	Picket_Ship,
	Gunship,
	Flak_Frigate,
	Missile_Frigate,
	Electronic_Warfare_Frigate,
	Shield_Frigate,
	Support_Frigate,
	Minelayer_Frigate,
	Destroyer,
	Light_Cruiser,
	Heavy_Cruiser,
	Battlecruiser,
	Battleship,
	Dreadnought,
	Escort_Carrier,
	Fleet_Carrier,
	Command_Ship,
	Courier,
	Freighter,
	Tanker,
	Fabricator_Ship,
	Recovery_Tug,
	Hospital_Ship,
	Habitat_Ship,
	Colony_Transport,
	Seedship,
	Generation_Ship,
	Arkship,
}

SHIP_OPERATIONAL_ROLE_COUNT :: 37

SHIP_OPERATIONAL_FUNCTIONS :: [SHIP_OPERATIONAL_ROLE_COUNT + 1]string {
	"",
	"Maps contacts and designates targets while avoiding direct combat.",
	"Reaches incoming bombers and missiles before they enter the fleet screen.",
	"Contests local space and escorts vulnerable formations.",
	"Raids light ships, support vessels, and exposed subsystems.",
	"Makes limited torpedo runs against line warships and fixed targets.",
	"Carries boarding teams to disabled ships and installations.",
	"Inspects traffic, captures objectives, and provides security in numbers.",
	"Pursues strike craft and raids exposed auxiliaries.",
	"Ambushes capital ships with weapons its hull cannot survive trading fire with.",
	"Extends the sensor picture and reveals stealthy approaches.",
	"Stays close to protected ships and drives off light attackers.",
	"Projects a short-range defensive envelope against squadrons.",
	"Applies long-range pressure through allied sensor coverage.",
	"Disrupts sensors, guidance, and synchronized attacks nearby.",
	"Reduces damage to ships inside its limited protection radius.",
	"Repairs active hulls and recovers disabled command elements.",
	"Deploys mines and sensors that make a volume costly to cross.",
	"Drives into frigate formations with concentrated forward fire.",
	"Combines sensors, protection, and weapons for detached operations.",
	"Anchors the battle line with armor and sustained fire.",
	"Carries heavy weapons at cruiser speed without battleship protection.",
	"Controls open space through armor, broad fire arcs, and supporting screens.",
	"Serves as a strategic objective whose movement and fire shape the operation.",
	"Supports a local wing with limited repair and rearming capacity.",
	"Repairs, rearms, and coordinates several strike-craft wings.",
	"Shares sensors and orders; its loss delays reports and increases captain autonomy.",
	"Moves messages, specialists, and critical data faster than the main fleet.",
	"Carries modular ordinary cargo between ships and settlements.",
	"Extends fleet range with propellant and reaction mass.",
	"Produces parts, ammunition, and small craft away from fixed industry.",
	"Tows wrecks and disabled ships out of exposed volumes.",
	"Preserves wounded people and reduces permanent demographic loss.",
	"Houses a permanent population that cannot be evacuated quickly.",
	"Moves settlers, surface equipment, and the authority to found a colony.",
	"Carries genomes, archives, and machinery with a small living crew.",
	"Sustains a traveling population with its own industry and institutions.",
	"Carries a complete civilizational package as a campaign-defining asset.",
}

SHIP_OPERATIONAL_RESPONSES :: [SHIP_OPERATIONAL_ROLE_COUNT + 1]string {
	"",
	"Use pickets and interceptors; force it to reveal itself before it fixes a target.",
	"Draw it away from its carrier or engage it with fighters after the first pass.",
	"Use flak, corvettes, or a stronger fighter screen; avoid an equal turning fight without support.",
	"Keep auxiliaries screened and deny a clean approach to exposed systems.",
	"Use interceptors, fighters, flak, debris masks, or maneuver during its attack cycle.",
	"Protect disabled ships with fighters and point defense until recovery arrives.",
	"Concentrate force locally; individual patrol boats cannot sustain heavy fire.",
	"Use gunships, light cruisers, terrain, or a coordinated fighter screen.",
	"Screen likely ambush lanes and force it to fire before reaching a capital flank.",
	"Jam or destroy it before committing stealth craft or a concealed approach.",
	"Separate it from the ship it protects or attack from beyond its short range.",
	"Use missiles, armor, or standoff fire; do not feed squadrons into its envelope.",
	"Break allied sensor coverage, close through masked terrain, or raid the launcher.",
	"Leave its disruption radius, attack the frigate, or rely on unguided close fire.",
	"Attack from more than one bearing or force the protected formation to move.",
	"Raid it early or keep damaged ships beyond its recovery reach.",
	"Detect the field with scouts and pickets, clear it, or choose another approach.",
	"Flank it or answer with strike fighters and heavier line ships.",
	"Overmatch one function at a time; it cannot equal a specialist in every role.",
	"Use bombers, battlecruisers, isolation, or attacks outside its preferred broadside.",
	"Force it to trade durability for speed, then answer with heavy cruisers or bombers.",
	"Isolate it from screens and support before committing bombers or torpedo craft.",
	"Treat it as the operation's objective; use maneuver, relays, and limited exposure windows.",
	"Raid it with corvettes or strike fighters after drawing off its local wing.",
	"Pressure its repair cycle and attack from multiple bearings before wings can rearm.",
	"Disable or separate it to reduce sensor sharing and synchronized attacks.",
	"Control exits and sensor coverage; it survives by speed rather than armor.",
	"Capture or disable it when cargo matters; destroying it removes the cargo too.",
	"Disable it away from the fleet; damaged tanks remain hazardous nearby.",
	"Raid it before a long operation or deny it raw material and recovery time.",
	"Keep disabled ships screened so the tug cannot reach a safe towing position.",
	"Disable its drives and isolate it; its tactical weapons are limited.",
	"Avoid damage near populated sections; boarding and evacuation take time.",
	"Intercept it before landing operations begin or deny a viable settlement route.",
	"Capture it intact when possible; its archive value survives only if the payload does.",
	"Treat it as a city: isolate routes, industry, and escorts rather than expecting a quick evacuation.",
	"Its loss changes the campaign; operations around it should prioritize control and recovery.",
}

ship_operational_role_function :: proc(role: Ship_Operational_Role) -> string {index := int(role)
	if index < 0 || index > SHIP_OPERATIONAL_ROLE_COUNT do return ""
	values := SHIP_OPERATIONAL_FUNCTIONS
	return values[index]}
ship_operational_role_response :: proc(role: Ship_Operational_Role) -> string {index := int(role)
	if index < 0 || index > SHIP_OPERATIONAL_ROLE_COUNT do return ""
	values := SHIP_OPERATIONAL_RESPONSES
	return values[index]}

Ship_Module :: enum u8 {
	Sensors,
	Interception,
	Flak,
	Missiles,
	Torpedoes,
	Boarding,
	Electronic_Warfare,
	Active_Defense,
	Repair,
	Recovery,
	Mines,
	Command,
	Flight_Deck,
	Cargo,
	Tankage,
	Fabrication,
	Medical,
	Habitat,
	Colony,
	Archive,
}
Ship_Modules :: bit_set[Ship_Module]

Ship_Weapon_Package :: enum u8 {
	Unspecified,
	Chemical_Autocannon,
	Coilgun_Battery,
	Railgun_Battery,
	Defensive_Laser,
	Offensive_Laser,
	Guided_Missiles,
	Heavy_Torpedoes,
}
Ship_Weapon_Packages :: bit_set[Ship_Weapon_Package]
Ship_Defense_Package :: enum u8 {
	Unspecified,
	Chaff,
	Thermal_Flares,
	Active_Decoys,
	ECM,
	Defensive_Guns,
	Defensive_Lasers,
}
Ship_Defense_Packages :: bit_set[Ship_Defense_Package]

ship_weapon_package_name :: proc(value: Ship_Weapon_Package) -> string {switch
	value {case .Chemical_Autocannon:
		return "chemical autocannon"; case .Coilgun_Battery:
		return "coilgun battery"; case .Railgun_Battery:
		return "railgun battery"; case .Defensive_Laser:
		return "defensive laser"; case .Offensive_Laser:
		return "offensive laser"; case .Guided_Missiles:
		return "guided missiles"; case .Heavy_Torpedoes:
		return "heavy torpedoes"; case .Unspecified:
		return "unarmed"}
	return "unarmed"}
ship_defense_package_name :: proc(value: Ship_Defense_Package) -> string {switch
	value {case .Chaff:
		return "chaff"; case .Thermal_Flares:
		return "thermal flares"; case .Active_Decoys:
		return "active decoys"; case .ECM:
		return "ECM"; case .Defensive_Guns:
		return "defensive guns"; case .Defensive_Lasers:
		return "defensive lasers"; case .Unspecified:
		return "none"}
	return "none"}

ship_weapon_package_for :: proc(
	id: Ship_ID,
	hull: Ship_Hull_Archetype,
	role: Ship_Operational_Role,
) -> Ship_Weapon_Package {
	if role == .Missile_Frigate || role == .Strike_Fighter do return .Guided_Missiles
	if role == .Bomber || role == .Torpedo_Boat do return .Heavy_Torpedoes
	if role == .Flak_Frigate || role == .Interceptor do return (combat_mix(u64(id) ~ 0xdefe) & 1) == 0 ? .Defensive_Laser : .Chemical_Autocannon
	family := ship_hull_archetype_family(
		hull,
	); roll := combat_mix(u64(id) ~ u64(hull) * 0x9e3779b97f4a7c15) % 4
	switch family {case .Strike_Craft:
		return(
			roll < 2 ? .Chemical_Autocannon : roll == 2 ? .Defensive_Laser : .Guided_Missiles \
		); case .Light_Combatant, .Frigate:
		return(
			roll == 0 ? .Coilgun_Battery : roll == 1 ? .Offensive_Laser : roll == 2 ? .Guided_Missiles : .Chemical_Autocannon \
		); case .Line_Warship:
		return(
			roll < 2 ? .Railgun_Battery : roll == 2 ? .Offensive_Laser : .Guided_Missiles \
		); case .Carrier_And_Command:
		return(
			roll < 2 ? .Defensive_Laser : roll == 2 ? .Coilgun_Battery : .Guided_Missiles \
		); case .Diaspora:
		return roll < 2 ? .Chemical_Autocannon : .Defensive_Laser; case .Unspecified:
		return .Chemical_Autocannon}; return .Chemical_Autocannon
}

ship_defense_packages_for :: proc(
	id: Ship_ID,
	hull: Ship_Hull_Archetype,
	role: Ship_Operational_Role,
) -> Ship_Defense_Packages {
	r: Ship_Defense_Packages = {
		.Chaff,
	}; roll := combat_mix(u64(id) ~ u64(hull) * 0xbf58476d1ce4e5b9)
	if (roll & 1) != 0 {r += {.Thermal_Flares}} else {r += {.Active_Decoys}}
	modules := ship_operational_role_modules(
		role,
	); if .Electronic_Warfare in modules || .Active_Defense in modules do r += {.ECM, .Active_Decoys}
	if .Flak in modules || .Active_Defense in modules do r += ((roll >> 1) & 1) != 0 ? Ship_Defense_Packages{.Defensive_Lasers} : Ship_Defense_Packages{.Defensive_Guns}
	return r
}

Ship_Operational_Profile :: struct {
	recon,
	stealth,
	interception,
	anti_ship,
	boarding,
	capture,
	point_defense,
	long_range,
	electronic_warfare,
	shield,
	repair,
	recovery,
	area_denial,
	command,
	flight_support: i32,
	cargo,
	propellant,
	fabrication,
	medical,
	population,
	colony,
	archive:                                                                                                            i32,
}

ship_operational_role_name :: proc(role: Ship_Operational_Role) -> string {
	switch role {
	case .Scout:
		return "scout"; case .Interceptor:
		return "interceptor"; case .Fighter:
		return "fighter"; case .Strike_Fighter:
		return "strike fighter"; case .Bomber:
		return "bomber"; case .Assault_Shuttle:
		return "assault shuttle"
	case .Patrol_Boat:
		return "patrol boat"; case .Corvette:
		return "corvette"; case .Torpedo_Boat:
		return "torpedo boat"; case .Picket_Ship:
		return "picket ship"; case .Gunship:
		return "gunship"
	case .Flak_Frigate:
		return "flak frigate"; case .Missile_Frigate:
		return "missile frigate"; case .Electronic_Warfare_Frigate:
		return "electronic-warfare frigate"; case .Shield_Frigate:
		return "active-defense frigate"; case .Support_Frigate:
		return "support frigate"; case .Minelayer_Frigate:
		return "minelayer frigate"
	case .Destroyer:
		return "destroyer"; case .Light_Cruiser:
		return "light cruiser"; case .Heavy_Cruiser:
		return "heavy cruiser"; case .Battlecruiser:
		return "battlecruiser"; case .Battleship:
		return "battleship"; case .Dreadnought:
		return "dreadnought"
	case .Escort_Carrier:
		return "escort carrier"; case .Fleet_Carrier:
		return "fleet carrier"; case .Command_Ship:
		return "command ship"
	case .Courier:
		return "courier"; case .Freighter:
		return "freighter"; case .Tanker:
		return "tanker"; case .Fabricator_Ship:
		return "fabricator ship"; case .Recovery_Tug:
		return "recovery tug"; case .Hospital_Ship:
		return "hospital ship"; case .Habitat_Ship:
		return "habitat ship"; case .Colony_Transport:
		return "colony transport"; case .Seedship:
		return "seedship"; case .Generation_Ship:
		return "generation ship"; case .Arkship:
		return "arkship"
	case .Unspecified:
		return "unspecified"
	}; return "unspecified"
}

ship_operational_role_fits_hull :: proc(
	role: Ship_Operational_Role,
	hull: Ship_Hull_Archetype,
) -> bool {
	switch hull {
	case .Scout:
		return role == .Scout; case .Interceptor:
		return role == .Interceptor; case .Fighter:
		return role == .Fighter; case .Strike_Fighter:
		return role == .Strike_Fighter; case .Bomber:
		return role == .Bomber; case .Assault_Shuttle:
		return role == .Assault_Shuttle
	case .Patrol_Boat:
		return role == .Patrol_Boat; case .Corvette:
		return role == .Corvette; case .Torpedo_Boat:
		return role == .Torpedo_Boat; case .Gunship:
		return role == .Gunship
	case .Picket_Frigate:
		return role == .Picket_Ship
	case .Combat_Frigate:
		return(
			role == .Flak_Frigate ||
			role == .Missile_Frigate ||
			role == .Electronic_Warfare_Frigate ||
			role == .Shield_Frigate \
		)
	case .Support_Frigate:
		return role == .Support_Frigate
	case .Minelayer_Frigate:
		return role == .Minelayer_Frigate
	case .Destroyer:
		return role == .Destroyer; case .Light_Cruiser:
		return role == .Light_Cruiser; case .Heavy_Cruiser:
		return role == .Heavy_Cruiser; case .Battlecruiser:
		return role == .Battlecruiser; case .Battleship:
		return role == .Battleship; case .Dreadnought:
		return role == .Dreadnought
	case .Carrier:
		return role == .Escort_Carrier || role == .Fleet_Carrier || role == .Command_Ship
	case .Utility_Hull:
		return(
			role == .Courier ||
			role == .Tanker ||
			role == .Recovery_Tug ||
			role == .Hospital_Ship \
		)
	case .Transport_Hull:
		return role == .Freighter || role == .Fabricator_Ship || role == .Colony_Transport
	case .Habitat_Hull:
		return(
			role == .Habitat_Ship ||
			role == .Seedship ||
			role == .Generation_Ship ||
			role == .Arkship \
		)
	case .Unspecified:
		return false
	}; return false
}

ship_operational_role_hull :: proc(role: Ship_Operational_Role) -> Ship_Hull_Archetype {for hull_value in 1 ..= SHIP_HULL_ARCHETYPE_COUNT {hull :=
			Ship_Hull_Archetype(hull_value)
		if ship_operational_role_fits_hull(role, hull) do return hull}
	return .Unspecified}

