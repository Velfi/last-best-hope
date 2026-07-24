package game

import "core:fmt"
import "core:math"

combat_resolve_capital_ability :: proc(m: ^Combat_Mission) {
	if !m.ability_pending do return
	#partial switch m.ability_kind {
	case .Spinal_Salvo:
		for &u, i in m.units[:m.unit_count] {
			if u.disabled || u.extracted do continue
			distance := combat_distance(u.position, m.ability_target)
			if distance > 85 do continue
			falloff := 1 - distance / 120
			damage := 58 * falloff
			if u.side == .Friendly do damage *= .45
			combat_apply_damage(m, i, damage); u.impact_flash = .8
		}
		source :=
			m.units[clamp(m.ability_source, 0, m.friendly_count - 1)]; combat_add_event_at(m, fmt.tprintf("%s's spinal salvo struck the designated volume", source.name), m.ability_target)
	case .None:
	}
	m.ability_pending = false; m.ability_flash = 1.2
}

combat_new_mission :: proc(seed: u64, heroism_scale: i32 = 0) -> Combat_Mission {
	m := Combat_Mission {
		seed           = seed,
		rng            = combat_mix(seed),
		scenario       = .Seedship,
		heroism_scale  = heroism_scale,
		phase          = .Reconnaissance,
		recovery_unit  = 4,
		request_unit   = -1,
		request_target = -1,
	}
	m.grid = {
		min_x       = -900,
		max_x       = 900,
		min_y       = -900,
		max_y       = 900,
		low_ceiling = -55,
		high_floor  = 55,
	}
	angle := combat_rand(&m) * 6.28318; spread := combat_rand(&m) * 70
	m.relays[0] = combat_map_position(
		{-250 + spread, 110, -35},
	); m.relays[1] = combat_map_position({120, -230 + spread * .5, 55})
	m.seedship = combat_map_position(
		{70 + f32(math.cos(angle)) * 80, 45 + f32(math.sin(angle)) * 75, 20},
	)
	// The recovery target and relay baselines remain in inertial motion. Their
	// seeded velocities are slow enough to forecast but require matching rather
	// than parking on a fixed map marker.
	m.seedship_velocity = {
		.035 + combat_rand(&m) * .02,
		-.018 + combat_rand(&m) * .036,
		-.006 + combat_rand(&m) * .012,
	}
	m.relay_velocity[0] = {.008, -.004, .001}
	m.relay_velocity[1] = {-.006, .007, -.001}
	m.extraction = combat_map_position(
		{-450 + combat_rand(&m) * 50, 190 + combat_rand(&m) * 110, -20 + combat_rand(&m) * 40},
	); m.anomaly = combat_map_position({270 + combat_rand(&m) * 55, -210 + combat_rand(&m) * 60, 65 + combat_rand(&m) * 45})
	_ = combat_add_interaction(
		&m,
		{
			kind = .Capture,
			position = m.relays[0],
			target = 0,
			verb = "CAPTURE",
			title = "CAPTURE RELAY A",
			consequence = "Hold the relay control volume until the fix is secured.",
		},
	)
	_ = combat_add_interaction(
		&m,
		{
			kind = .Capture,
			position = m.relays[1],
			target = 1,
			verb = "CAPTURE",
			title = "CAPTURE RELAY B",
			consequence = "Hold the relay control volume until the fix is secured.",
		},
	)
	_ = combat_add_interaction(
		&m,
		{
			kind = .Recover,
			position = m.seedship,
			target = -1,
			verb = "RECOVER",
			title = "RECOVER SEEDSHIP",
			consequence = "Approach the seedship and continue stabilization.",
		},
	)
	m.terrain[0] = {
		.Debris,
		combat_map_position({-110 + combat_rand(&m) * 65, -20 + combat_rand(&m) * 70, 0}),
		(135 + combat_rand(&m) * 25) * 1.25,
	}; m.terrain[1] = {.Open_Lane, combat_map_position({190 + combat_rand(&m) * 55, 115 + combat_rand(&m) * 55, 20}), (115 + combat_rand(&m) * 25) * 1.25}; m.terrain[2] = {.Radiation, m.anomaly, (82 + combat_rand(&m) * 18) * 1.25}
	m.groups[0] = {
		name               = "SCREEN",
		objective          = .Control,
		doctrine           = .Cautious_Screen,
		destination        = m.relays[0],
		target             = -1,
		guard              = 4,
		pursuit_limit      = 150,
		withdraw_threshold = 55,
		priority           = .Threats_To_Objective,
	}
	m.groups[1] = {
		name               = "STRIKE",
		objective          = .Attack,
		doctrine           = .Hunter_Killer,
		destination        = m.relays[1],
		target             = -1,
		guard              = -1,
		pursuit_limit      = 390,
		withdraw_threshold = 20,
		priority           = .Capital,
	}
	m.groups[2] = {
		name               = "RECOVERY",
		objective          = .Guard,
		doctrine           = .Balanced,
		destination        = {-330, -15, 0},
		target             = -1,
		guard              = 4,
		pursuit_limit      = 240,
		withdraw_threshold = 30,
		priority           = .Support,
	}
	for &group in m.groups do combat_apply_group_doctrine(&group, group.doctrine)
	friendly := [7]Combat_Unit {
		combat_unit(
			"Lantern Wing",
			"Lt. Sato",
			"Disciplined",
			"Held formation through the Ilex breach.",
			.Friendly,
			.Fighter,
			combat_map_position({-390, 120, 0}),
		),
		combat_unit(
			"Kestrel Wing",
			"Cmdr. Vale",
			"Protective",
			"Returned for the hospital convoy at Oros.",
			.Friendly,
			.Fighter,
			combat_map_position({-410, 75, 25}),
		),
		combat_unit(
			"Ashfall Wing",
			"Maj. Nkiru",
			"Veteran bombers",
			"Four ships survived the Narrows run.",
			.Friendly,
			.Bomber,
			combat_map_position({-430, 25, -20}),
		),
		combat_unit(
			"Morrow Guard",
			"Capt. Ilyan",
			"Steady",
			"Its crews have recovered eleven hulks.",
			.Friendly,
			.Corvette,
			combat_map_position({-400, -30, 10}),
		),
		combat_unit(
			"Common Hearth",
			"Capt. Amini",
			"Cautious",
			"Carries the fleet's last field cradles.",
			.Friendly,
			.Recovery,
			combat_map_position({-450, -80, 0}),
		),
		combat_unit(
			"Wayfarer",
			"Commodore Chen",
			"Improvised carrier",
			"Its port radiator was rebuilt at Kepler Wake.",
			.Friendly,
			.Carrier,
			combat_map_position({-480, 55, -10}),
		),
		combat_unit(
			"Resolute",
			"Capt. Okafor",
			"Scarred prow",
			"Still carries the breach opened at Ilex Gate.",
			.Friendly,
			.Capital,
			combat_map_position({-500, -25, 15}),
		),
	}
	combat_configure_archetype(
		&friendly[0],
		.Interceptor,
		.Interceptor,
	); combat_configure_archetype(&friendly[1], .Fighter, .Fighter); combat_configure_archetype(&friendly[2], .Bomber, .Bomber); combat_configure_archetype(&friendly[3], .Gunship, .Gunship); combat_configure_archetype(&friendly[4], .Utility_Hull, .Recovery_Tug); combat_configure_archetype(&friendly[5], .Carrier, .Command_Ship); combat_configure_archetype(&friendly[6], .Heavy_Cruiser, .Heavy_Cruiser)
	for source, i in friendly {u := source; u.group = i < 2 ? 0 : i < 4 ? 1 : 2
		u.doctrine = m.groups[u.group].doctrine
		combat_add_element(&m, u)}; m.friendly_count = m.unit_count
	combat_configure_capital(&m.units[6], .Linebreaker)
	combat_issue_group_order(
		&m,
		0,
		.Control,
		m.relays[0],
	); combat_issue_group_order(&m, 1, .Control, m.relays[1]); combat_issue_order(&m, m.recovery_unit, .Hold, m.units[m.recovery_unit].position); combat_issue_order(&m, 5, .Guard, m.units[m.recovery_unit].position); m.units[5].guard = m.recovery_unit; combat_issue_order(&m, 6, .Move, m.terrain[1].center)
	raider_count := 4 + int(combat_rand(&m) * 2)
	desired_raider_ships := raider_count
	if heroism_scale > 0 do desired_raider_ships = m.friendly_count * int(clamp(heroism_scale, 1, 1000))
	power_divisor := heroism_scale > 0 ? f32(1) : f32(0)
	roles := [5]Combat_Role{.Fighter, .Bomber, .Corvette, .Corvette, .Fighter}
	for i in 0 ..< raider_count {
		relay_index :=
			i %
			2; file := i / 2; p := m.relays[relay_index]; p.x += 420 + combat_rand(&m) * 75; p.y += f32(file - 1) * 105 + (relay_index == 0 ? 360 : -360) + (combat_rand(&m) - .5) * 35; p.z += -70 + f32((i % 3)) * 70
		u := combat_unit(
			i == 1 ? "Knife Relay Team" : i == 2 ? "Carrion Torpedoes" : "Raider Screen",
			"Unknown",
			i == 1 ? "Objective raider" : "Roving",
			"Contact logged during the recovery.",
			.Raider,
			roles[i % len(roles)],
			p,
		)
		combat_configure_roster_archetype(&u, i + 2)
		combat_apply_heroism(&u, power_divisor)
		u.formation_ships =
			desired_raider_ships / raider_count + (i < desired_raider_ships % raider_count ? 1 : 0)
		combat_add_element(&m, u)
	}
	if heroism_scale > 0 {
		// Heroism changes how many hulls carry the opposition, not its aggregate
		// opening power. These budgets equal the seven-contact parity formation.
		total_hull, total_damage: f32
		for u in m.units[m.friendly_count:m.unit_count] {total_hull += u.max_hull; total_damage += u.damage}
		hull_correction := f32(450) / total_hull; damage_correction := f32(74) / total_damage
		for &u in m.units[m.friendly_count:m.unit_count] {u.hull *= hull_correction; u.max_hull = u.hull; u.damage *= damage_correction}
	}
	m.complication = Combat_Complication(1 + int(combat_rand(&m) * 3))
	combat_add_event(
		&m,
		"Operational area entered. Raider contacts are divided between both dark relays.",
	)
	combat_build_ship_roster(&m)
	return m
}

// Campaign operations borrow the authored command-element roles while giving
// each element the identity and recorded history of a persistent fleet ship.
combat_campaign_mission_kind :: proc(c: ^Campaign, seed: u64) -> Skirmish_Mission_Kind {
	scenario := c.compact.active.charter.undertaking_intent.objective
	roll := int(combat_mix(seed ~ u64(int(scenario) + 1) * 0x517cc1b727220a95) % 4)
	switch scenario {
	case .Combat_Recover_Seedship:
		kinds := [4]Skirmish_Mission_Kind {
			.Seedship_Recovery,
			.Contested_Salvage,
			.Reconnaissance,
			.Disabled_Ship_Rescue,
		}
		return kinds[roll]
	case .Combat_Defend_Settlement:
		kinds := [4]Skirmish_Mission_Kind {
			.Rearguard_Withdrawal,
			.Relay_Control,
			.Convoy_Escort,
			.Fleet_Engagement,
		}
		return kinds[roll]
	case .Combat_Break_Blockade:
		kinds := [4]Skirmish_Mission_Kind {
			.Capital_Interception,
			.Raid_And_Deploy,
			.Fleet_Engagement,
			.Citadel_Assault,
		}
		return kinds[roll]
	case .Combat_Escort_Migration:
		kinds := [4]Skirmish_Mission_Kind {
			.Convoy_Escort,
			.Rearguard_Withdrawal,
			.Relay_Control,
			.Capital_Interception,
		}
		return kinds[roll]
	case .Combat_Recover_Disabled_Fleet:
		kinds := [4]Skirmish_Mission_Kind {
			.Disabled_Ship_Rescue,
			.Repair_And_Tow,
			.Rearguard_Withdrawal,
			.Contested_Salvage,
		}
		return kinds[roll]
	case .Combat_Contested_Route:
		kinds := [4]Skirmish_Mission_Kind {
			.Relay_Control,
			.Raid_And_Deploy,
			.Reconnaissance,
			.Capital_Interception,
		}
		return kinds[roll]
	case .None,
	     .Passage_Recover_Reserves,
	     .Passage_Evaluate_Home,
	     .Passage_Evacuate_Harbor,
	     .Passage_Inspect_Treaty,
	     .Passage_Escort_Migration,
	     .Passage_Recover_Missing_Ship:
		return .Seedship_Recovery
	}
	return .Seedship_Recovery
}

combat_new_campaign_mission :: proc(c: ^Campaign) -> Combat_Mission {
	seed :=
		c.combat_deployment_active && c.combat_deployment_seed != 0 ? c.combat_deployment_seed : c.initial_seed ~ (u64(c.season + 1) * 0x9e3779b97f4a7c15)
	kind := combat_campaign_mission_kind(c, seed)
	setup := skirmish_default_setup()
	setup.seed = seed
	setup.contract_seed = combat_mix(seed ~ u64(c.compact.active.id + 1) * 0x6a09e667f3bcc909)
	setup.mission = kind
	setup.faction_count = 2
	m := combat_new_skirmish_mission(seed, setup, c.ruleset.heroism_scale)
	// Campaign operations require eight genuinely independent command
	// elements. Insert the eighth before the hostile slice so group identity is
	// preserved throughout targeting, damage, withdrawal, and continuity.
	if m.friendly_count < COMBAT_GROUP_COUNT {
		enemies := make([]Combat_Unit, m.unit_count - m.friendly_count)
		copy(enemies, m.units[m.friendly_count:m.unit_count])
		combat_truncate_elements(&m, m.friendly_count)
		rearguard := combat_unit(
			"Rearguard",
			"Fleet command",
			"Unassigned reserve",
			"No ship has yet been assigned to this command element.",
			.Friendly,
			.Corvette,
			{-690, 330, -60},
		)
		rearguard.group = 7
		combat_add_element(&m, rearguard)
		m.friendly_count = m.unit_count
		for enemy in enemies do combat_add_element(&m, enemy)
		delete(enemies)
	}
	m.fire_control = c.combat_fire_control_preference
	m.campaign_doctrine_deviation = c.combat_deployment_doctrine_deviation
	if c.front_count > 0 {
		best := 0; for front, i in c.fronts[:c.front_count] do if front.last_change_event > c.fronts[best].last_change_event do best = i
		front :=
			c.fronts[best]; m.campaign_origin_event = front.last_change_event; m.campaign_incident = fmt.tprintf("%s brought armed contacts into the seedship corridor.", front.name)
	} else {
		for i := c.event_count - 1;
		    i >= 0;
		    i -= 1 {e := c.events[i]; if semantic_has(e.semantic_tags, .Passage) || semantic_has(e.semantic_tags, .Governance) {m.campaign_origin_event = e.sequence; m.campaign_incident = fmt.tprintf("The operation follows the record entered in E%03d.", e.sequence); break}}
	}
	if m.campaign_incident == "" do m.campaign_incident = "A dark relay report placed the seedship within reach of the fleet."
	doctrine :=
		Combat_Doctrine.Balanced; m.campaign_authority = "Standing fleet authority permits balanced engagement and withdrawal."
	if has_precedent(
		c,
		.No_One_Left_Behind,
	) {doctrine = .Cautious_Screen; m.campaign_authority = "The rescue precedent requires screens to preserve recovery and withdrawal."}
	if has_precedent(
		c,
		.Emergency_Command,
	) {doctrine = .Hunter_Killer; m.campaign_authority = "Emergency command authorizes pursuit beyond the ordinary screen."}
	for &group, i in m.groups {chosen := c.combat_deployment_active ? c.combat_deployment_doctrines[i] : doctrine; group.doctrine = chosen}
	for &unit in m.units[:m.friendly_count] do unit.doctrine = m.groups[unit.group].doctrine
	counts: [COMBAT_GROUP_COUNT]int
	group_cursor: [COMBAT_GROUP_COUNT]int
	power, damage, experience: [COMBAT_GROUP_COUNT]i32
	mass: [COMBAT_GROUP_COUNT]i64
	manifest_count := c.combat_deployment_active ? c.combat_deployment_count : c.ship_count
	for manifest_index in 0 ..< manifest_count {
		ship :=
			c.combat_deployment_active ? c.ships[ship_index(c, c.combat_deployment_ships[manifest_index])] : c.ships[manifest_index]
		if !ship.active || ship.departure != .None || (!c.combat_deployment_active && ship.committed) do continue
		// Objective logic continues to address seven stable command elements;
		// persistent ships are distributed across them without imposing a fleet cap.
		group :=
			c.combat_deployment_active ? c.combat_deployment_groups[manifest_index] : m.campaign_ship_count % COMBAT_GROUP_COUNT
		element := group
		group_cursor[group] += 1
		append(&m.campaign_ships, ship.id)
		append(&m.campaign_ship_elements, element)
		if counts[element] == 0 {
			m.units[element].name = ship.name
			m.units[element].history =
				ship.history_note != "" ? ship.history_note : "No prior combat damage is recorded."
			captain_at := historical_figure_index(c, ship.captain)
			if captain_at >=
			   0 {captain_profile_initialize(c, &c.historical_figures[captain_at]); m.units[element].captain_profile = c.historical_figures[captain_at].captain_profile}
		}
		counts[element] += 1
		power[element] +=
			ship.power; damage[element] += ship.damage; experience[element] += ship.experience; mass[element] += max(ship.mass_tonnes, 1); m.units[element].campaign_modules += ship_operational_role_modules(ship.operational_role)
		weapon :=
			ship.weapon_package; if weapon == .Unspecified do weapon = ship_weapon_package_for(ship.id, ship.hull_archetype, ship.operational_role); m.units[element].weapon_packages += {weapon}
		defenses :=
			ship.defense_packages; if defenses == {} do defenses = ship_defense_packages_for(ship.id, ship.hull_archetype, ship.operational_role); m.units[element].defense_packages += defenses
		m.campaign_ship_count += 1
	}
	for &unit, i in m.units[:m.friendly_count] {
		unit.formation_ships = max(counts[i], 1)
		if counts[i] >
		   0 {condition := clamp(1 - f32(damage[i]) / f32(counts[i] * 5), .35, 1); quality := 1 + f32(power[i]) / f32(max(counts[i], 1)) * 0.035 + f32(experience[i]) / f32(max(counts[i], 1)) * 0.025; unit.hull *= condition * quality; unit.max_hull = unit.hull; unit.damage *= quality; unit.tonnage_each = mass[i] / i64(counts[i]); combat_apply_mass_mobility(&unit); unit.engine_power *= quality; unit.max_acceleration = unit.engine_power / f32(max(unit.tonnage_each, 1)); unit.readiness = condition * 100; unit.veterancy = clamp(1 + int(experience[i]) / max(counts[i], 1), 1, 6)}
	}
	combat_build_ship_roster(&m)
	roster_cursor: [COMBAT_GROUP_COUNT]int
	for element in m.campaign_ship_elements {append(&m.campaign_ship_roster_indices, m.units[element].roster_start + roster_cursor[element]); roster_cursor[element] += 1}
	return m
}

Combat_Campaign_Application :: struct {
	ships_deployed,
	ships_damaged,
	new_scars,
	population_joined,
	knowledge_gained,
	industry_gained: int,
	aftermath_opened,
	applied:                                                                      bool,
}

Combat_Deployment_Preview :: struct {
	valid:                                      bool,
	ship_count, propellant_cost:                int,
	group_ships:                                [COMBAT_GROUP_COUNT]int,
	control, strike, support, recon, endurance: i32,
	factors:                                    [MAX_FORECAST_FACTORS]Forecast_Factor,
	factor_count:                               int,
	shortfall_count:                            int,
	warning:                                    string,
}
