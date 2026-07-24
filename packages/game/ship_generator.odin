package game

import "core:math"
import "core:strings"

// Ship_Generator_Config controls one hull. Percent fields use 100 as the
// role-authentic baseline and are clamped to keep generated values plausible.
// Set role_locked=false to select a role from the supplied Fleet_Goals.
Ship_Generator_Config :: struct {
	id:                 Ship_ID,
	name:               string,
	community:          Community_ID,
	role:               Role,
	role_locked:        bool,
	hull_class:         Hull_Class,
	hull_archetype:     Ship_Hull_Archetype,
	operational_role:   Ship_Operational_Role,
	capability_percent: i32,
	crew_percent:       i32,
	mass_percent:       i32,
	variation_percent:  i32,
	trait:              Passage_Ship_Trait,
	trait_locked:       bool,
}

default_ship_generator_config :: proc(index: int = 0) -> Ship_Generator_Config {
	return {
		id = Ship_ID(index + 1),
		community = Community_ID(index % INITIAL_COMMUNITIES + 1),
		hull_class = .Fleet_Ship,
		capability_percent = 100,
		crew_percent = 100,
		mass_percent = 100,
		variation_percent = 10,
	}
}

ship_hull_class_name :: proc(hull_class: Hull_Class) -> string {
	switch hull_class {
	case .Strike_Craft:
		return "strike craft"
	case .Corvette:
		return "corvette"
	case .Fleet_Ship:
		return "fleet ship"
	case .Cruiser:
		return "cruiser"
	case .Capital_Ship:
		return "capital ship"
	case .Unspecified:
		return "unspecified"
	}
	return "unspecified"
}

ship_hull_class_power :: proc(role: Role, hull_class: Hull_Class) -> i32 {
	base := fleet_role_base_power(role)
	switch hull_class {
	case .Strike_Craft:
		return max(base * 2 / 7, 1)
	case .Corvette:
		return max(base * 3 / 5, 1)
	case .Cruiser:
		return base * 2
	case .Capital_Ship:
		return base * 6
	case .Fleet_Ship, .Unspecified:
		return base
	}
	return base
}

ship_hull_class_crew :: proc(role: Role, hull_class: Hull_Class) -> i32 {
	base := fleet_role_base_crew(role)
	switch hull_class {
	case .Strike_Craft:
		if role == .Survey || role == .Escort do return 1
		return 2
	case .Corvette:
		return max(base / 4, 8)
	case .Cruiser:
		return base * 6
	case .Capital_Ship:
		return base * 100
	case .Fleet_Ship, .Unspecified:
		return base
	}
	return base
}

ship_role_mass_percent :: proc(role: Role) -> i64 {
	switch role {
	case .Habitat:
		return 150
	case .Agriculture:
		return 140
	case .Foundry:
		return 130
	case .Archive:
		return 85
	case .Hospital:
		return 110
	case .Survey:
		return 70
	case .Escort:
		return 100
	case .Colony:
		return 160
	}
	return 100
}

ship_hull_mass_range :: proc(hull_class: Hull_Class) -> (i64, i64) {
	switch hull_class {
	case .Strike_Craft:
		return 8, 35
	case .Corvette:
		return 800, 12000
	case .Fleet_Ship:
		return 18000, 180000
	case .Cruiser:
		return 120000, 2500000
	case .Capital_Ship:
		return 4000000, 120000000
	case .Unspecified:
		return 18000, 180000
	}
	return 18000, 180000
}

// Production archetypes occupy narrower displacement bands inside the broad
// legacy hull classes. These ranges drive generation and presentation alike.
ship_hull_archetype_mass_range :: proc(archetype: Ship_Hull_Archetype) -> (i64, i64) {
	switch archetype {
	case .Scout:
		return 8, 12; case .Interceptor:
		return 10, 16; case .Fighter:
		return 14, 22; case .Strike_Fighter:
		return 18, 28; case .Bomber:
		return 24, 35; case .Assault_Shuttle:
		return 20, 34
	case .Patrol_Boat:
		return 800, 2000; case .Torpedo_Boat:
		return 1200, 3500; case .Corvette:
		return 2500, 6500; case .Gunship:
		return 5000, 12000
	case .Utility_Hull:
		return 18000, 60000; case .Picket_Frigate:
		return 24000, 55000; case .Combat_Frigate:
		return 35000, 90000; case .Support_Frigate:
		return 45000, 110000; case .Minelayer_Frigate:
		return 40000, 100000; case .Transport_Hull:
		return 60000, 180000; case .Destroyer:
		return 90000, 180000
	case .Light_Cruiser:
		return 120000, 450000; case .Heavy_Cruiser:
		return 400000, 1200000; case .Carrier:
		return 650000, 2100000; case .Battlecruiser:
		return 1100000, 2500000
	case .Battleship:
		return 4000000, 20000000; case .Habitat_Hull:
		return 10000000, 90000000; case .Dreadnought:
		return 30000000, 120000000
	case .Unspecified:
		return 18000, 180000
	}
	return 18000, 180000
}

ship_hull_archetype_nominal_mass :: proc(archetype: Ship_Hull_Archetype) -> i64 {low, high :=
		ship_hull_archetype_mass_range(archetype)
	return low + (high - low) / 2}

// A logarithmic display scale preserves the true ordering across seven orders
// of magnitude without making strike craft illegible or capitals screen-sized.
ship_tonnage_visual_scale :: proc(tonnes: i64) -> f32 {
	minimum := f64(8); maximum := f64(120000000); mass := clamp(f64(tonnes), minimum, maximum)
	normalized := math.log10(mass / minimum) / math.log10(maximum / minimum)
	return 8 + f32(normalized) * 24
}

ship_tonnage_band :: proc(tonnes: i64) -> int {return clamp(
		int(math.floor(f64((ship_tonnage_visual_scale(tonnes) - 8) / 24 * 5))) + 1,
		1,
		5,
	)}

ship_hull_class_from_role :: proc(seed: u64, role: Role) -> Hull_Class {
	state := ship_generator_stream(seed, 0x6a09e667f3bcc909)
	roll := fleet_generator_next(&state) % 100
	switch role {
	case .Habitat:
		if roll < 20 do return .Fleet_Ship
		if roll < 75 do return .Cruiser
		return .Capital_Ship
	case .Agriculture:
		return roll < 75 ? .Fleet_Ship : .Cruiser
	case .Foundry:
		if roll < 60 do return .Fleet_Ship
		if roll < 95 do return .Cruiser
		return .Capital_Ship
	case .Archive:
		if roll < 65 do return .Corvette
		if roll < 95 do return .Fleet_Ship
		return .Cruiser
	case .Hospital:
		return roll < 70 ? .Fleet_Ship : .Cruiser
	case .Survey:
		if roll < 35 do return .Strike_Craft
		if roll < 85 do return .Corvette
		return .Fleet_Ship
	case .Escort:
		if roll < 40 do return .Strike_Craft
		if roll < 85 do return .Corvette
		return .Cruiser
	case .Colony:
		return roll < 45 ? .Cruiser : .Capital_Ship
	}
	return .Fleet_Ship
}

generate_ship_mass :: proc(
	state: ^u64,
	role: Role,
	hull_class: Hull_Class,
	mass_percent: i32,
) -> i64 {
	low, high := ship_hull_mass_range(hull_class)
	base := low + i64(fleet_generator_next(state) % u64(high - low + 1))
	role_scale := ship_role_mass_percent(role)
	user_scale := i64(clamp(mass_percent, 25, 200))
	combined_scale := clamp(role_scale * user_scale / 100, i64(25), i64(200))
	if combined_scale <= 100 {
		return low + (base - low) * combined_scale / 100
	}
	return base + (high - base) * (combined_scale - 100) / 100
}

generate_ship_archetype_mass :: proc(
	state: ^u64,
	role: Role,
	archetype: Ship_Hull_Archetype,
	mass_percent: i32,
) -> i64 {
	low, high := ship_hull_archetype_mass_range(archetype)
	base := low + i64(fleet_generator_next(state) % u64(high - low + 1))
	combined_scale := clamp(
		ship_role_mass_percent(role) * i64(clamp(mass_percent, 25, 200)) / 100,
		i64(25),
		i64(200),
	)
	if combined_scale <= 100 do return low + (base - low) * combined_scale / 100
	return base + (high - base) * (combined_scale - 100) / 100
}

ship_role_from_goals :: proc(seed: u64, goals: Fleet_Goals) -> Role {
	state := seed
	if state == 0 do state = 1
	best_role := Role.Habitat
	best_score := i32(-1)
	for role_value in 0 ..< 8 {
		role := Role(role_value)
		score := fleet_role_score(role, goals) + i32(fleet_generator_next(&state) % 17)
		if score > best_score {best_score = score; best_role = role}
	}
	return best_role
}

// Names are authored rather than assembled from interchangeable word lists. A
// ship keeps its name for an entire campaign, so each entry needs to survive
// repetition in reports, votes, distress calls, and memorial records. The pool
// deliberately mixes short names, working names, civic names, place-memory,
// and a few rare ceremonial names instead of one uniform adjective+noun form.
SHIP_GENERATOR_NAMES :: [72]string {
	"Aster's Wake",
	"Bellwether",
	"Borrowed Fire",
	"Cairn at Noon",
	"Cartographer",
	"Cold Meridian",
	"Concordance",
	"Copper Finch",
	"Crossing Guard",
	"Dear Prudence",
	"Deep Sounding",
	"Due North",
	"Every Hand",
	"Field Note",
	"First Principle",
	"Foxglove",
	"Good Measure",
	"Grey Heron",
	"Held in Trust",
	"Ilex",
	"In Good Order",
	"Juniper",
	"Kepler's Lantern",
	"Labor's Rest",
	"Larkspur",
	"Long Baseline",
	"Mended Bell",
	"Morrow",
	"No Fixed Address",
	"Northing",
	"Old Salt",
	"One More Mile",
	"Orchard Wall",
	"Our Share",
	"Parallax",
	"Pilgrim's Mark",
	"Plumb Line",
	"Quarry Light",
	"Red Willow",
	"Reference Point",
	"Rookery",
	"Safe Conduct",
	"Salt Meadow",
	"Second Opinion",
	"Signal Twelve",
	"Small Hours",
	"Soundings",
	"Stated Purpose",
	"Stone Soup",
	"Navigator's Mark",
	"Table for Twelve",
	"The Almanac",
	"The Allotment",
	"The Good Knife",
	"The Long Now",
	"The Night Watch",
	"The Open Door",
	"The Register",
	"The Spare Key",
	"Thirty Fathoms",
	"True Account",
	"Under Repair",
	"Variable One",
	"Warm Harbor",
	"Water Table",
	"Waymark",
	"Welcome Field",
	"Westing",
	"Winter Elm",
	"Witness Table",
	"Yellow Finch",
	"Zenith Sample",
}

GENERATED_SHIP_TRAITS :: [5]Passage_Ship_Trait {
	.Curious,
	.Protective,
	.Cautious,
	.Committed,
	.Independent,
}

ship_generator_name_index :: proc(seed: u64, id: Ship_ID) -> int {
	name_count := len(SHIP_GENERATOR_NAMES)
	index := (int(id) - 1 + int(seed % u64(name_count))) % name_count
	if index < 0 do index += name_count
	return index
}

ship_generator_name :: proc(seed: u64, id: Ship_ID) -> string {
	names := SHIP_GENERATOR_NAMES
	return names[ship_generator_name_index(seed, id)]
}

scaled_ship_value :: proc(base, percent, variation_percent: i32, state: ^u64) -> i32 {
	scale := clamp(percent, 25, 200)
	variation := clamp(variation_percent, 0, 50)
	// Symmetric integer variation around the requested scale.
	span := base * variation / 100
	offset := i32(0)
	if span > 0 do offset = i32(fleet_generator_next(state) % u64(span * 2 + 1)) - span
	return max(base * scale / 100 + offset, 1)
}

ship_generator_stream :: proc(seed, domain: u64) -> u64 {
	state := seed ~ domain
	if state == 0 do state = domain | 1
	// Diffuse nearby seeds and domain constants before the first sampled value.
	for _ in 0 ..< 3 do _ = fleet_generator_next(&state)
	return state
}

ship_construction_identity_seed :: proc(seed: u64, id: Ship_ID) -> u64 {
	identity := seed ~ (u64(id) * 0x9e3779b97f4a7c15)
	return ship_generator_stream(identity, 0x243f6a8885a308d3)
}

ship_with_construction_identity :: proc(ship: Ship, identity_seed: u64) -> Ship {
	result := ship
	result.construction_seed = ship_construction_identity_seed(identity_seed, ship.id)
	result.utility_hardpoint = u8(
		ship_construction_visual_mix(result.construction_seed ~ 0xd1310ba698dfb5ac) % 9 + 1,
	)
	result.bow_profile = u8(
		ship_construction_visual_mix(result.construction_seed ~ 0x9216d5d98979fb1b) % 3 + 1,
	)
	result.wing_sweep = u8(
		ship_construction_visual_mix(result.construction_seed ~ 0x6a09e667f3bcc909) % 3 + 1,
	)
	result.wing_stance = u8(
		ship_construction_visual_mix(result.construction_seed ~ 0x13198a2e03707344) % 3 + 1,
	)
	result.keel_profile = u8(
		ship_construction_visual_mix(result.construction_seed ~ 0x082efa98ec4e6c89) % 3 + 1,
	)
	result.mission_profile = u8(
		ship_construction_visual_mix(result.construction_seed ~ 0x510e527fade682d1) % 3 + 1,
	)
	result.drive_layout = u8(
		ship_construction_visual_mix(result.construction_seed ~ 0x3f84d5b5b5470917) % 3 + 1,
	)
	result.drive_setback = u8(
		ship_construction_visual_mix(result.construction_seed ~ 0xbb67ae8584caa73b) % 3 + 1,
	)
	return result
}

// Construction identity is simulation data: presentation layers may render it
// with different assets, but they must agree on which ships share a design
// family and whether two hulls are structurally the same construction.
ship_construction_visual_mix :: proc(value: u64) -> u64 {
	mixed := value
	mixed = mixed ~ (mixed >> 30)
	mixed *= 0xbf58476d1ce4e5b9
	mixed = mixed ~ (mixed >> 27)
	mixed *= 0x94d049bb133111eb
	return mixed ~ (mixed >> 31)
}

// Presentation detail is a persistent construction choice, but remains
// stat-neutral. The returned value is normalized to 0..4 so renderers can
// share the same none, sparse, standard, dense, and industrial contract.
ship_construction_greebly_density :: proc(ship: Ship) -> int {
	if ship.greebly_density >= 1 && ship.greebly_density <= 5 do return int(ship.greebly_density) - 1
	return 2
}

ship_construction_family_pair :: proc(ship: Ship) -> (int, int) {
	identity := ship.construction_lineage
	if identity == 0 {
		identity = ship.construction_seed
		if identity == 0 do identity = u64(ship.id)
	}
	family_seed := ship_construction_visual_mix(identity)
	primary := int(family_seed % 6)
	accent := (primary + 1 + int((family_seed >> 32) % 5)) % 6
	return primary, accent
}

ship_construction_family_fingerprint :: proc(ship: Ship) -> u64 {
	primary, accent := ship_construction_family_pair(ship)
	return u64(primary * 6 + accent)
}

ship_construction_layout_code :: proc(ship: Ship) -> u64 {
	identity := ship.construction_seed
	if identity == 0 do identity = u64(ship.id)
	if ship.construction_lineage == 0 do return (ship_construction_visual_mix(identity ~ 0xa4093822299f31d0) >> 38) % 30 + 1
	key := ship_construction_visual_mix(ship.construction_lineage ~ 0xa4093822299f31d0)
	// An affine permutation gives siblings distinct layouts while keeping every
	// five-part hull visibly split between its two shared construction families.
	multipliers := [8]u64{1, 7, 11, 13, 17, 19, 23, 29}
	multiplier := multipliers[int((key >> 8) % u64(len(multipliers)))]
	offset := (key >> 40) % 30
	stable_index := u64(max(int(ship.id) - 1, 0))
	return (stable_index * multiplier + offset) % 30 + 1
}

ship_construction_utility_hardpoint :: proc(ship: Ship) -> int {
	if ship.utility_hardpoint >= 1 && ship.utility_hardpoint <= 9 do return int(ship.utility_hardpoint) - 1
	// Legacy saves did not persist this field; retain their exact old mounting.
	return int((ship_construction_layout_code(ship) - 1) % 9)
}

// Wing stance is part of a hull's persistent construction identity. Keeping it
// in the simulation contract lets every presentation render the same compact,
// balanced, or broad silhouette without depending on mutable ship statistics.
ship_construction_wing_stance :: proc(ship: Ship) -> int {
	if ship.wing_stance >= 1 && ship.wing_stance <= 3 do return int(ship.wing_stance) - 1
	identity := ship.construction_seed
	if identity == 0 do identity = u64(ship.id)
	return int(ship_construction_visual_mix(identity ~ 0x13198a2e03707344) % 3)
}

// Wing sweep is an independent frame choice: 0 reaches forward, 1 stays
// level with the keel, and 2 sweeps aft. It changes silhouette only and is
// derived from immutable construction identity for legacy-save compatibility.
