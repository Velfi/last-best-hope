package game_tests

import "core:math"
import "core:testing"

@(test)
procedural_ship_identity_selects_family_and_structural_proportions :: proc(t: ^testing.T) {
	strike := Ship {
		id                = 1,
		construction_seed = 101,
		hull_archetype    = .Fighter,
		keel_profile      = 1,
		wing_stance       = 1,
	}
	diaspora := Ship {
		id                = 2,
		construction_seed = 202,
		hull_archetype    = .Habitat_Hull,
		keel_profile      = 3,
		wing_stance       = 3,
		bow_profile       = 3,
		mission_profile   = 3,
		utility_hardpoint = 9,
	}
	testing.expect_value(t, procedural_ship_family_for_ship(strike), Procedural_Ship_Family.Strike)
	testing.expect_value(
		t,
		procedural_ship_family_for_ship(diaspora),
		Procedural_Ship_Family.Habitat,
	)
	a := procedural_ship_generate_for_ship(strike)
	b := procedural_ship_generate_for_ship(diaspora)
	testing.expect(t, a.complete && b.complete)
	testing.expect(
		t,
		b.frame.keel_length > procedural_ship_generate(202, .Habitat).frame.keel_length,
	)
	testing.expect(t, b.frame.beam > procedural_ship_generate(202, .Habitat).frame.beam)
	testing.expect_value(t, b.modules[b.frame.station_count - 1].variant, u8(2))
	mission_found :=
		false; for module in b.modules[:b.module_count] do if module.module == .Mission {mission_found = true; testing.expect_value(t, module.variant, u8(2)); testing.expect_value(t, module.mount_variant, u8(8 + ship_construction_centerline_bias(diaspora) * 9))}
	testing.expect(t, mission_found)
}

@(test)
procedural_ship_identity_wing_sweep_moves_and_reorients_off_keel_structure :: proc(t: ^testing.T) {
	forward := Ship {
		id                = 31,
		construction_seed = 771,
		hull_archetype    = .Heavy_Cruiser,
		keel_profile      = 2,
		wing_stance       = 2,
		wing_sweep        = 1,
	}
	aft := forward; aft.wing_sweep = 3
	a := procedural_ship_generate_for_ship(forward); b := procedural_ship_generate_for_ship(aft)
	moved := 0
	for module, i in a.modules[:a.module_count] {
		if math.abs(module.position[1]) + math.abs(module.position[2]) < .1 do continue
		moved += 1; testing.expect(t, module.position[0] > b.modules[i].position[0])
		parent := int(a.sockets[i].parent)
		if parent >= 0 && module.module != .Ring_Segment {
			testing.expect(t, math.abs(module.direction[0] - b.modules[i].direction[0]) > .01)
		}
	}
	testing.expect(t, moved > 0); testing.expect(t, a.fingerprint != b.fingerprint)
}

@(test)
procedural_ship_identity_drive_layout_and_setback_change_the_stern :: proc(t: ^testing.T) {
	recessed := Ship {
		id                = 41,
		construction_seed = 881,
		hull_archetype    = .Heavy_Cruiser,
		drive_layout      = 1,
		drive_setback     = 1,
	}
	extended := recessed; extended.drive_layout = 3; extended.drive_setback = 3
	a := procedural_ship_generate_for_ship(
		recessed,
	); b := procedural_ship_generate_for_ship(extended)
	testing.expect_value(t, a.modules[0].module, Procedural_Ship_Module.Drive)
	testing.expect_value(
		t,
		a.modules[0].variant,
		u8(0),
	); testing.expect_value(t, b.modules[0].variant, u8(2))
	testing.expect(t, a.modules[0].position[0] > b.modules[0].position[0])
	testing.expect(t, a.fingerprint != b.fingerprint)
}

@(test)
procedural_ship_capability_scales_engines_and_weapons_independently :: proc(t: ^testing.T) {
	base := Ship {
		id                = 41,
		construction_seed = 881,
		hull_archetype    = .Heavy_Cruiser,
		operational_role  = .Heavy_Cruiser,
		role              = .Escort,
		hull_class        = .Cruiser,
		power             = 20,
	}
	low_power := base; low_power.power = 10; high_power := base; high_power.power = 30
	low := procedural_ship_generate_for_ship(
		low_power,
	); high := procedural_ship_generate_for_ship(high_power)
	testing.expect(t, low.drive_capability_scale < high.drive_capability_scale)
	testing.expect_value(t, low.weapon_capability_scale, high.weapon_capability_scale)
	scout := base; scout.operational_role = .Scout
	scout_recipe := procedural_ship_generate_for_ship(scout)
	testing.expect(t, scout_recipe.weapon_capability_scale < low.weapon_capability_scale)
	low_drive, high_drive := -1, -1
	for module, i in low.modules[:low.module_count] do if module.module == .Drive {low_drive = i; break}
	for module, i in high.modules[:high.module_count] do if module.module == .Drive {high_drive = i; break}
	testing.expect(t, low_drive >= 0 && high_drive >= 0)
	if low_drive >= 0 && high_drive >= 0 {
		testing.expect_value(t, low.modules[low_drive].drive_power_tier, i8(-1))
		testing.expect_value(t, high.modules[high_drive].drive_power_tier, i8(1))
	}
}

@(test)
procedural_ship_recipe_preserves_weapon_package_for_visual_hardpoints :: proc(t: ^testing.T) {
	missile_ship := Ship {
		id                = 41,
		construction_seed = 0x4100,
		role              = .Escort,
		hull_class        = .Cruiser,
		hull_archetype    = .Strike_Fighter,
		operational_role  = .Missile_Frigate,
		weapon_package    = .Guided_Missiles,
	}
	torpedo_ship := missile_ship
	torpedo_ship.id = 42
	torpedo_ship.construction_seed = 0x4200
	torpedo_ship.operational_role = .Torpedo_Boat
	torpedo_ship.weapon_package = .Heavy_Torpedoes
	testing.expect_value(
		t,
		procedural_ship_generate_for_ship(missile_ship).weapon_package,
		Ship_Weapon_Package.Guided_Missiles,
	)
	testing.expect_value(
		t,
		procedural_ship_generate_for_ship(torpedo_ship).weapon_package,
		Ship_Weapon_Package.Heavy_Torpedoes,
	)
}

@(test)
procedural_ship_operational_roles_install_compatible_signature_hardware :: proc(t: ^testing.T) {
	verified := 0
	for seed in 1 ..= 128 {
		warship := Ship {
			id                = 51,
			construction_seed = u64(seed),
			hull_archetype    = .Heavy_Cruiser,
			operational_role  = .Heavy_Cruiser,
		}
		command := Ship {
			id                = 52,
			construction_seed = u64(seed),
			hull_archetype    = .Carrier,
			operational_role  = .Command_Ship,
		}
		a := procedural_ship_generate_for_ship(
			warship,
		); b := procedural_ship_generate_for_ship(command)
		for module, i in a.modules[:a.module_count] {
			if i < a.frame.station_count || module.module != .Armor || b.modules[i].module != .Antenna do continue
			verified += 1; testing.expect(t, a.complete && b.complete); testing.expect_value(t, a.modules[i].material, Ship_Material_Class.Armor); testing.expect_value(t, b.modules[i].material, Ship_Material_Class.Glass); testing.expect(t, b.modules[i].scale[2] > b.modules[i].scale[0] * 3); break
		}
	}
	testing.expect(t, verified >= 64)
}

@(test)
procedural_ship_role_refit_converts_surplus_mission_bays_but_preserves_reserve :: proc(
	t: ^testing.T,
) {
	roles := [3]Ship_Operational_Role{.Strike_Fighter, .Scout, .Assault_Shuttle}
	expected := [3]Procedural_Ship_Module{.Armor, .Antenna, .Dock}
	for role, index in roles {
		ship := Ship {
			id                   = Ship_ID(80 + index),
			construction_seed    = 900 + u64(index),
			construction_lineage = 900,
			hull_archetype       = ship_operational_role_hull(role),
			operational_role     = role,
		}
		r := procedural_ship_generate_for_ship(ship); mission_count, signature_count := 0, 0
		for module in r.modules[:r.module_count] {
			if module.module == .Mission do mission_count += 1
			if module.module == expected[index] do signature_count += 1
		}
		testing.expect(t, mission_count >= 1)
		testing.expect(t, signature_count >= 1)
		testing.expect(t, r.complete)
	}
}

@(test)
procedural_ship_role_refit_emphasizes_natural_signature_pair :: proc(t: ^testing.T) {
	cases := [6]struct {
		family: Procedural_Ship_Family,
		role:   Ship_Operational_Role,
	} {
		{.Strike, .Scout},
		{.Strike, .Assault_Shuttle},
		{.Fleet, .Heavy_Cruiser},
		{.Fleet, .Fleet_Carrier},
		{.Habitat, .Colony_Transport},
		{.Habitat, .Fabricator_Ship},
	}
	for item in cases {
		verified := false
		for seed in 1 ..= 256 {
			before := procedural_ship_generate(u64(seed), item.family)
			signature := procedural_ship_role_signature(
				Ship{operational_role = item.role},
				item.family,
			)
			candidate := -1
			for module, i in before.modules[:before.module_count] do if module.module == signature && i >= before.frame.station_count && before.sockets[i].exposed {candidate = i; break}
			if candidate < 0 do continue
			after :=
				before; procedural_ship_apply_role_signature(&after, Ship{operational_role = item.role})
			emphasis := procedural_ship_role_signature_emphasis(signature)
			for axis in 0 ..< 3 do testing.expect(t, math.abs(after.modules[candidate].scale[axis] - before.modules[candidate].scale[axis] * emphasis[axis]) < .001)
			partner := procedural_ship_symmetric_counterpart(&before, candidate)
			if partner >= 0 do testing.expect_value(t, after.modules[candidate].scale, after.modules[partner].scale)
			testing.expect(t, after.mass > before.mass); verified = true; break
		}
		testing.expect(t, verified)
	}
}

@(test)
procedural_ship_role_signature_density_scales_with_frame_family :: proc(t: ^testing.T) {
	cases := [6]struct {
		family: Procedural_Ship_Family,
		role:   Ship_Operational_Role,
		hull:   Ship_Hull_Archetype,
	} {
		{.Strike, .Scout, .Scout},
		{.Strike, .Assault_Shuttle, .Assault_Shuttle},
		{.Fleet, .Fleet_Carrier, .Carrier},
		{.Fleet, .Command_Ship, .Carrier},
		{.Habitat, .Colony_Transport, .Transport_Hull},
		{.Habitat, .Fabricator_Ship, .Utility_Hull},
	}
	for item in cases do for seed in 1 ..= 96 {
		ship := Ship {
			id                = Ship_ID(seed),
			construction_seed = u64(seed),
			hull_archetype    = item.hull,
			operational_role  = item.role,
		}
		r := procedural_ship_generate_for_ship(ship); signature := procedural_ship_role_signature(ship, item.family); count, missions := 0, 0
		for module in r.modules[:r.module_count] {if module.module == signature do count += 1; if module.module == .Mission do missions += 1}
		testing.expectf(t, count >= procedural_ship_role_signature_target(item.family), "family=%v role=%v seed=%d signature=%v count=%d target=%d", item.family, item.role, seed, signature, count, procedural_ship_role_signature_target(item.family))
		testing.expect(t, missions >= 1)
		testing.expect(t, r.complete)
	}
}

@(test)
procedural_ship_saturated_refit_adds_a_supported_hardpoint_without_touching_reserves :: proc(
	t: ^testing.T,
) {
	ship := Ship {
		id                = 1,
		construction_seed = 1,
		hull_archetype    = .Scout,
		operational_role  = .Scout,
	}
	base := procedural_ship_generate(
		1,
		.Strike,
	); r := procedural_ship_generate_for_ship(ship); repeat := procedural_ship_generate_for_ship(ship)
	testing.expect_value(
		t,
		r.module_count,
		base.module_count + 4,
	); testing.expect_value(t, r.socket_count, base.socket_count + 4)
	signatures, missions := 0, 0
	for module, i in r.modules[:r.module_count] {
		if module.module == .Mission do missions += 1
		if module.module != .Antenna do continue
		signatures += 1; parent := int(r.sockets[i].parent); testing.expect(t, parent >= 0)
		if parent >= 0 do testing.expect_value(t, r.modules[parent].module, Procedural_Ship_Module.Truss)
		testing.expect_value(t, module, repeat.modules[i])
	}
	testing.expect(t, signatures >= 1 && missions >= 1 && r.complete)
}

@(test)
procedural_ship_role_signatures_preserve_manufactured_pairs :: proc(t: ^testing.T) {
	ships := [3]Ship {
		{id = 61, hull_archetype = .Strike_Fighter, operational_role = .Strike_Fighter},
		{id = 62, hull_archetype = .Carrier, operational_role = .Command_Ship},
		{id = 63, hull_archetype = .Habitat_Hull, operational_role = .Habitat_Ship},
	}
	for template in ships do for seed in 1 ..= 128 {
		ship := template; ship.construction_seed = u64(seed); r := procedural_ship_generate_for_ship(ship)
		for module, i in r.modules[:r.module_count] {
			partner := procedural_ship_symmetric_partner(&r, i); if partner < 0 do continue
			other := r.modules[partner]; testing.expect_value(t, module.module, other.module); testing.expect_value(t, module.scale, other.scale); testing.expect_value(t, module.material, other.material)
		}
	}
}

@(test)
procedural_ship_lineage_siblings_share_frame_topology_without_becoming_clones :: proc(
	t: ^testing.T,
) {
	first := Ship {
		id                   = 71,
		construction_seed    = 1001,
		construction_lineage = 0xabc123,
		hull_archetype       = .Heavy_Cruiser,
		operational_role     = .Heavy_Cruiser,
		keel_profile         = 2,
		wing_stance          = 2,
		wing_sweep           = 2,
		drive_layout         = 1,
		drive_setback        = 2,
		bow_profile          = 2,
		mission_profile      = 2,
		utility_hardpoint    = 5,
	}
	second :=
		first; second.id = 72; second.construction_seed = 2002; second.drive_layout = 3; second.bow_profile = 3; second.utility_hardpoint = 9
	a := procedural_ship_generate_for_ship(first); b := procedural_ship_generate_for_ship(second)
	testing.expect_value(
		t,
		a.socket_count,
		b.socket_count,
	); testing.expect_value(t, a.module_count, b.module_count)
	for socket, i in a.sockets[:a.socket_count] {
		other :=
			b.sockets[i]; testing.expect_value(t, socket.parent, other.parent); testing.expect_value(t, socket.domain, other.domain); testing.expect_value(t, a.modules[i].module, b.modules[i].module)
	}
	testing.expect_value(
		t,
		a.modules[0].variant,
		u8(0),
	); testing.expect_value(t, b.modules[0].variant, u8(2))
	testing.expect(t, a.fingerprint != b.fingerprint)
}

@(test)
procedural_ship_service_history_is_local_deterministic_and_fingerprint_neutral :: proc(
	t: ^testing.T,
) {
	pristine := Ship {
		id                = 91,
		construction_seed = 0x9137,
		hull_archetype    = .Heavy_Cruiser,
		operational_role  = .Heavy_Cruiser,
	}
	damaged := pristine; damaged.damage = 3; damaged.scar = .Hull_Breach
	a := procedural_ship_generate_for_ship(
		pristine,
	); b := procedural_ship_generate_for_ship(damaged); repeat := procedural_ship_generate_for_ship(damaged)
	marks, breaches := 0, 0
	for module, i in b.modules[:b.module_count] {
		if module.service_mark == .None do continue
		marks += 1; if module.service_mark == .Breach_Cage do breaches += 1
		testing.expect_value(t, module.service_mark, repeat.modules[i].service_mark)
		testing.expect(t, procedural_ship_service_mark_compatible(module.module))
	}
	testing.expect_value(t, marks, 3); testing.expect_value(t, breaches, 1)
	testing.expect_value(t, a.fingerprint, b.fingerprint)
	for module in a.modules[:a.module_count] do testing.expect_value(t, module.service_mark, Procedural_Ship_Service_Mark.None)
}

@(test)
procedural_ship_dark_history_uses_a_distinct_service_mark :: proc(t: ^testing.T) {
	ship := Ship {
		id                = 92,
		construction_seed = 0x2271,
		hull_archetype    = .Habitat_Hull,
		operational_role  = .Habitat_Ship,
		dark_field_scars  = 2,
	}
	r := procedural_ship_generate_for_ship(ship); dark := 0
	for module in r.modules[:r.module_count] do if module.service_mark == .Dark_Scar do dark += 1
	testing.expect_value(t, dark, 1)
}

@(test)
procedural_keels_taper_from_the_structural_center :: proc(t: ^testing.T) {
	for family in Procedural_Ship_Family {
		center := procedural_ship_keel_profile(family, 0)
		quarter := procedural_ship_keel_profile(family, .5)
		end := procedural_ship_keel_profile(family, 1)
		testing.expect(t, center > quarter && quarter > end)
		testing.expect_value(t, procedural_ship_keel_profile(family, 2), end)
	}
}

@(test)
large_ship_keels_carry_broader_spines_than_strike_frames :: proc(t: ^testing.T) {
	for family in Procedural_Ship_Family {
		state := u64(91)
		keel := procedural_ship_module_scale(family, .Keel, &state)
		truss := procedural_ship_module_scale(family, .Truss, &state)
		ratio := keel[1] / truss[1]
		if family == .Strike {
			testing.expect(t, ratio < 2.6)
		} else {
			testing.expect(t, ratio > 2.6)
		}
	}
}

@(test)
fleet_frames_terminate_in_a_commanding_armored_prow :: proc(t: ^testing.T) {
	strike_state, fleet_state, habitat_state := u64(91), u64(91), u64(91)
	strike := procedural_ship_module_scale(.Strike, .Bow, &strike_state)
	fleet := procedural_ship_module_scale(.Fleet, .Bow, &fleet_state)
	habitat := procedural_ship_module_scale(.Habitat, .Bow, &habitat_state)
	testing.expect(t, fleet[0] > strike[0] * 1.8)
	testing.expect(t, fleet[1] > strike[1] * 1.8)
	testing.expect(t, habitat[1] > fleet[1])
	testing.expect(t, habitat[2] > fleet[2])
}

@(test)
strike_branch_payloads_form_strong_aft_swept_load_paths :: proc(t: ^testing.T) {
	for seed in 1 ..= 128 {
		r := procedural_ship_frame_generate(u64(seed), .Strike)
		verified := 0
		for socket in r.sockets[:r.socket_count] {
			if !socket.exposed || !socket.symmetric || socket.parent < 0 do continue
			root := r.sockets[int(socket.parent)]
			if root.parent < 0 do continue
			anchor := r.sockets[int(root.parent)].position
			lateral := math.abs(socket.position[1] - anchor[1])
			setback := anchor[0] - socket.position[0]
			testing.expect(t, setback > lateral * .48)
			testing.expect(t, lateral >= 1.14 && lateral <= 1.91)
			verified += 1
		}
		testing.expect(t, verified >= 2)
	}
}

@(test)
habitat_branches_form_ring_districts_with_exposed_keel_between :: proc(t: ^testing.T) {
	for seed in 1 ..= 128 {
		r := procedural_ship_frame_generate(u64(seed), .Habitat)
		spacing := r.frame.keel_length / f32(r.frame.station_count - 1)
		clear_bays := 0
		for station in 1 ..< r.frame.station_count - 1 {
			has_branch := false
			for socket in r.sockets[r.frame.station_count + r.frame.ring_station_count:r.socket_count] {
				if !socket.exposed && int(socket.parent) == station {
					has_branch = true
					break
				}
			}
			if !has_branch do clear_bays += 1
		}
		testing.expect(t, clear_bays >= 1)
		for socket in r.sockets[r.frame.station_count + r.frame.ring_station_count:r.socket_count] {
			if !socket.exposed do continue
			nearest := r.frame.keel_length
			for ring in r.sockets[r.frame.station_count:r.frame.station_count + r.frame.ring_station_count] {
				nearest = min(nearest, math.abs(socket.position[0] - ring.position[0]))
			}
			testing.expect(t, nearest < spacing * 1.6)
		}
	}
}

@(test)
fleet_branches_form_an_amidships_citadel_with_clear_approaches :: proc(t: ^testing.T) {
	for seed in 1 ..= 128 {
		r := procedural_ship_frame_generate(u64(seed), .Fleet)
		first, last := procedural_ship_fleet_citadel_bounds(r.frame.station_count)
		testing.expect(t, first > 1)
		testing.expect(t, last < r.frame.station_count - 2)
		roots := 0
		for socket in r.sockets[r.frame.station_count:r.socket_count] {
			if socket.exposed || socket.parent < 0 do continue
			parent := int(socket.parent)
			testing.expect(t, parent >= first && parent <= last)
			roots += 1
		}
		testing.expect(t, roots >= 1)
	}
}

@(test)
procedural_payload_mass_zones_are_family_specific_and_preserve_structure :: proc(t: ^testing.T) {
	base := Procedural_Ship_Recipe {
		frame = {keel_length = 12},
	}
	base.family = .Strike
	testing.expect(
		t,
		procedural_ship_axial_mass_factor(&base, .Armor, {3, 0, 0}) >
		procedural_ship_axial_mass_factor(&base, .Armor, {-4, 0, 0}),
	)
	base.family = .Fleet
	testing.expect(
		t,
		procedural_ship_axial_mass_factor(&base, .Mission, {0, 0, 0}) >
		procedural_ship_axial_mass_factor(&base, .Mission, {5, 0, 0}),
	)
	base.family = .Habitat; base.module_count = 1; base.modules[0] = {
		module   = .Ring_Segment,
		position = {2, 0, 0},
	}
	testing.expect(
		t,
		procedural_ship_axial_mass_factor(&base, .Pressure_Hull, {2.5, 0, 0}) >
		procedural_ship_axial_mass_factor(&base, .Pressure_Hull, {-4, 0, 0}),
	)
	for family in Procedural_Ship_Family {
		base.family = family
		structural_modules := [7]Procedural_Ship_Module {
			.Keel,
			.Bow,
			.Drive,
			.Truss,
			.Radiator,
			.Antenna,
			.Ring_Segment,
		}
		for structural in structural_modules do testing.expect_value(t, procedural_ship_axial_mass_factor(&base, structural, {0, 0, 0}), f32(1))
	}
}

@(test)
procedural_keel_blocks_leave_inspectable_station_breaks :: proc(t: ^testing.T) {
	for family in Procedural_Ship_Family do for seed in 1 ..= 128 {
		r := procedural_ship_generate(u64(seed), family)
		for station in 2 ..< r.frame.station_count - 1 {
			if r.modules[station - 1].module != .Keel || r.modules[station].module != .Keel do continue
			spacing := r.modules[station].position[0] - r.modules[station - 1].position[0]
			testing.expect(t, r.modules[station - 1].scale[0] + r.modules[station].scale[0] < spacing)
		}
	}
}

@(test)
procedural_ship_recipes_are_deterministic_valid_and_bounded :: proc(t: ^testing.T) {
	for family in Procedural_Ship_Family do for seed in 1 ..= 256 {a := procedural_ship_generate(u64(seed), family); b := procedural_ship_generate(u64(seed), family); testing.expect_value(t, a.fingerprint, b.fingerprint); testing.expect(t, a.complete && a.connected && a.pressure_connected && a.radiators_exposed && a.drives_valid); switch family {case .Strike:
			testing.expect(t, a.module_count >= 8 && a.module_count <= 16); case .Fleet:
			testing.expect(t, a.module_count >= 20 && a.module_count <= 40); case .Habitat:
			testing.expect(t, a.module_count >= 24 && a.module_count <= 60)}}
}

@(test)
procedural_ship_seed_sweep_varies_every_family :: proc(t: ^testing.T) {
	for family in Procedural_Ship_Family {unique := 0; seen: [32]u64
		for seed in 1 ..= len(seen) {r := procedural_ship_generate(u64(seed), family); fresh := true; for prior in seen[:unique] do if prior == r.fingerprint do fresh = false
			if fresh {seen[unique] = r.fingerprint; unique += 1}}
		testing.expect(t, unique >= 30)}
}

@(test)
procedural_habitats_include_deterministic_ring_segments :: proc(t: ^testing.T) {
	for seed in 1 ..= 256 {
		r := procedural_ship_generate(u64(seed), .Habitat); rings := 0
		for m, i in r.modules[:r.module_count] {
			if m.module != .Ring_Segment do continue
			rings += 1; socket := r.sockets[i]
			testing.expect(t, socket.parent >= 0 && int(socket.parent) < r.frame.station_count)
			testing.expect(
				t,
				math.abs(socket.position[1]) < .001 && math.abs(socket.position[2]) < .001,
			)
		}
		testing.expect_value(t, rings, r.frame.ring_station_count)
		testing.expect(t, rings >= 2 && rings <= 3)
	}
}

@(test)
procedural_large_branches_use_load_bearing_truss_roots :: proc(t: ^testing.T) {
	for family in Procedural_Ship_Family do for seed in 1 ..= 256 {
		r := procedural_ship_generate(u64(seed), family)
		if r.module_count - r.frame.station_count < 4 do continue
		root_count, root_child_count, full_span_count := 0, 0, 0
		for module, i in r.modules[:r.module_count] {
			socket := r.sockets[i]
			if module.module == .Truss && socket.parent >= 0 && int(socket.parent) < r.frame.station_count && math.abs(socket.direction[1]) > .5 {
				root_count += 1; parent_position := r.modules[int(socket.parent)].position
				pdx, pdy, pdz := module.position[0] - parent_position[0], module.position[1] - parent_position[1], module.position[2] - parent_position[2]; parent_distance := f32(math.sqrt(f64(pdx * pdx + pdy * pdy + pdz * pdz)))
				for child, j in r.sockets[:r.socket_count] {
					if int(child.parent) != i do continue
					cdx, cdy, cdz := r.modules[j].position[0] - module.position[0], r.modules[j].position[1] - module.position[1], r.modules[j].position[2] - module.position[2]; child_distance := f32(math.sqrt(f64(cdx * cdx + cdy * cdy + cdz * cdz)))
					testing.expect(t, math.abs(parent_distance - child_distance) < .01); testing.expect(t, math.abs(module.scale[0] - parent_distance) < .01); full_span_count += 1
				}
			}
			if socket.parent >= 0 && r.modules[int(socket.parent)].module == .Truss && math.abs(socket.direction[1]) > .5 do root_child_count += 1
		}
		testing.expect(t, root_count >= 2)
		testing.expect(t, root_child_count >= 2)
		testing.expect(t, full_span_count >= 2)
	}
}

@(test)
procedural_strike_branches_have_an_aft_sweep :: proc(t: ^testing.T) {
	root_count, swept_count := 0, 0
	for seed in 1 ..= 256 {
		r := procedural_ship_generate(u64(seed), .Strike)
		for module, i in r.modules[:r.module_count] {
			socket := r.sockets[i]
			if module.module != .Truss || socket.parent < 0 || math.abs(socket.direction[1]) <= .5 do continue
			root_count += 1; if socket.direction[0] < -.05 do swept_count += 1
		}
	}
	testing.expect(t, root_count > 0)
	testing.expect(t, swept_count * 4 >= root_count * 3)
}

@(test)
procedural_paired_branches_use_family_specific_keel_axis_roll :: proc(t: ^testing.T) {
	counts: [3]int
	for family in Procedural_Ship_Family do for seed in 1 ..= 128 {
		r := procedural_ship_generate(u64(seed), family)
		for module, i in r.modules[:r.module_count] {
			socket := r.sockets[i]
			if module.module != .Truss || !socket.symmetric || socket.parent < 0 || int(socket.parent) >= r.frame.station_count do continue
			partner := procedural_ship_symmetric_partner(&r, i); if partner < 0 do continue
			other := r.modules[partner]; counts[int(family)] += 1
			testing.expect(t, math.abs(module.position[1] + other.position[1]) < .001)
			testing.expect(t, math.abs(module.position[2] + other.position[2]) < .001)
			ratio := math.abs(module.position[2]) / max(math.abs(module.position[1]), f32(.001))
			switch family {case .Strike:
				testing.expect(t, ratio < .09); case .Fleet:
				testing.expect(t, ratio > .13 && ratio < .52); case .Habitat:
				testing.expect(t, ratio > .2 && ratio < 1)}
		}
	}
	for count in counts do testing.expect(t, count > 0)
}

@(test)
procedural_large_ship_branches_repeat_quantized_mounting_planes :: proc(t: ^testing.T) {
	families := [2]Procedural_Ship_Family {
		Procedural_Ship_Family.Fleet,
		Procedural_Ship_Family.Habitat,
	}
	for family in families {
		seen_shallow, seen_steep := false, false
		shallow := family == .Fleet ? math.tan(f32(.18)) : math.tan(f32(.28))
		steep := family == .Fleet ? math.tan(f32(.40)) : math.tan(f32(.66))
		for seed in 1 ..= 256 {
			r := procedural_ship_generate(u64(seed), family)
			for module, i in r.modules[:r.module_count] {
				socket := r.sockets[i]
				if module.module != .Truss || !socket.symmetric || socket.parent < 0 || int(socket.parent) >= r.frame.station_count do continue
				ratio :=
					math.abs(module.position[2]) / max(math.abs(module.position[1]), f32(.001))
				near_shallow := math.abs(ratio - shallow) < .002
				near_steep := math.abs(ratio - steep) < .002
				testing.expect(t, near_shallow || near_steep)
				seen_shallow = seen_shallow || near_shallow; seen_steep = seen_steep || near_steep
			}
		}
		testing.expect(t, seen_shallow && seen_steep)
	}
}

@(test)
procedural_manufactured_pairs_share_module_and_dimensions :: proc(t: ^testing.T) {
	for family in Procedural_Ship_Family do for seed in 1 ..= 256 {
		r := procedural_ship_generate(u64(seed), family); pair_count := 0
		for module, i in r.modules[:r.module_count] {
			partner := procedural_ship_symmetric_partner(&r, i)
			if partner < 0 do continue
			pair_count += 1; other := r.modules[partner]
			testing.expect_value(t, module.module, other.module)
			testing.expect_value(t, module.scale, other.scale)
			testing.expect_value(t, module.material, other.material)
		}
		testing.expect(t, pair_count > 0)
	}
}

@(test)
procedural_symmetric_payloads_are_always_truss_supported :: proc(t: ^testing.T) {
	for family in Procedural_Ship_Family do for seed in 1 ..= 256 {
		r := procedural_ship_generate(u64(seed), family)
		for module, i in r.modules[:r.module_count] {
			socket := r.sockets[i]
			if !socket.symmetric || module.module == .Truss || module.module == .Ring_Segment do continue
			testing.expect(t, socket.parent >= 0)
			if socket.parent >= 0 do testing.expect_value(t, r.modules[int(socket.parent)].module, Procedural_Ship_Module.Truss)
		}
	}
}

@(test)
procedural_every_off_keel_payload_is_truss_supported :: proc(t: ^testing.T) {
	for family in Procedural_Ship_Family do for seed in 1 ..= 256 {
		r := procedural_ship_generate(u64(seed), family)
		for module, i in r.modules[:r.module_count] {
			if i < r.frame.station_count || module.module == .Truss || module.module == .Ring_Segment do continue
			socket := r.sockets[i]; testing.expect(t, socket.parent >= 0)
			if socket.parent >= 0 do testing.expect_value(t, r.modules[int(socket.parent)].module, Procedural_Ship_Module.Truss)
		}
	}
}

@(test)
procedural_strike_exposed_payloads_stay_angular :: proc(t: ^testing.T) {
	for seed in 1 ..= 512 {
		r := procedural_ship_generate(u64(seed), .Strike)
		for module, i in r.modules[:r.module_count] {
			if i < r.frame.station_count || module.module == .Truss do continue
			testing.expect(t, module.module != .Tank && module.module != .Pressure_Hull)
		}
	}
}
