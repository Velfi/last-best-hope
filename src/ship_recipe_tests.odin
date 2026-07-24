package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:os"
import filepath "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"
import ui "zelda_engine:ui"

@(test)
ship_role_identity_covers_all_eight_roles :: proc(t: ^testing.T) {
	roles := [8]game.Role {
		.Habitat,
		.Agriculture,
		.Foundry,
		.Archive,
		.Hospital,
		.Survey,
		.Escort,
		.Colony,
	}
	seen_markings: [36]bool
	for role in roles {
		recipe := ship_render_recipe(game.Ship{id = 1, role = role})
		testing.expect(t, recipe.role_module >= 0 && recipe.role_module < 6)
		testing.expect(t, recipe.role_marking >= 0 && recipe.role_marking < len(seen_markings))
		testing.expect(t, !seen_markings[recipe.role_marking])
		seen_markings[recipe.role_marking] = true
	}
	habitat := ship_render_recipe(game.Ship{id = 1, role = .Habitat})
	hospital := ship_render_recipe(game.Ship{id = 1, role = .Hospital})
	colony := ship_render_recipe(game.Ship{id = 1, role = .Colony})
	agriculture := ship_render_recipe(game.Ship{id = 1, role = .Agriculture})
	testing.expect_value(t, habitat.role_module, hospital.role_module)
	testing.expect(t, habitat.role_marking != hospital.role_marking)
	testing.expect_value(t, colony.role_module, agriculture.role_module)
	testing.expect(t, colony.role_marking != agriculture.role_marking)
}

@(test)
ship_trait_insignia_covers_every_behavior_without_rebuilding_the_hull :: proc(t: ^testing.T) {
	traits := [5]game.Passage_Ship_Trait {
		.Curious,
		.Protective,
		.Cautious,
		.Committed,
		.Independent,
	}
	seen: [6]bool
	ship := game.Ship {
		id                = 8,
		construction_seed = 0x12345678,
		role              = .Survey,
	}
	baseline := ship_render_recipe(ship)
	for trait in traits {
		ship.passage_trait = trait
		recipe := ship_render_recipe(ship)
		testing.expect(t, recipe.trait_marking >= 0 && recipe.trait_marking < len(seen))
		testing.expect(t, !seen[recipe.trait_marking])
		seen[recipe.trait_marking] = true
		testing.expect_value(t, recipe.core, baseline.core)
		testing.expect_value(t, recipe.nose, baseline.nose)
		testing.expect_value(t, recipe.engine, baseline.engine)
		testing.expect_value(t, recipe.wing, baseline.wing)
		testing.expect_value(t, recipe.utility, baseline.utility)
	}
	ship.passage_trait = .None
	testing.expect_value(t, ship_render_recipe(ship).trait_marking, -1)
}

@(test)
ship_render_recipes_cover_the_initial_fleet :: proc(t: ^testing.T) {
	recipes: [game.MAX_SHIPS]Ship_Render_Recipe
	unique := 0
	for i in 0 ..< game.MAX_SHIPS {
		ship := game.Ship {
			id         = game.Ship_ID(i + 1),
			role       = game.Role(i % 8),
			hull_class = game.Hull_Class(i % 5 + 1),
		}
		recipes[i] = ship_render_recipe(ship)
		duplicate := false
		for prior in 0 ..< i {
			if recipes[prior].core == recipes[i].core && recipes[prior].nose == recipes[i].nose && recipes[prior].engine == recipes[i].engine && recipes[prior].wing == recipes[i].wing && recipes[prior].utility == recipes[i].utility do duplicate = true
		}
		if !duplicate do unique += 1
	}
	testing.expect(t, unique >= 10)
}

@(test)
ship_construction_variants_are_balanced_across_id_space :: proc(t: ^testing.T) {
	core_counts, nose_counts, engine_counts, wing_counts, utility_counts: [6]int
	seen: [7776]bool
	unique := 0
	for i in 0 ..< 256 {
		recipe := ship_render_recipe(game.Ship{id = game.Ship_ID(i + 1)})
		core_counts[recipe.core] += 1
		nose_counts[recipe.nose] += 1
		engine_counts[recipe.engine] += 1
		wing_counts[recipe.wing] += 1
		utility_counts[recipe.utility] += 1
		fingerprint :=
			recipe.core +
			recipe.nose * 6 +
			recipe.engine * 36 +
			recipe.wing * 216 +
			recipe.utility * 1296
		if !seen[fingerprint] {seen[fingerprint] = true; unique += 1}
	}
	for variant in 0 ..< 6 {
		testing.expect(t, core_counts[variant] >= 25 && core_counts[variant] <= 60)
		testing.expect(t, nose_counts[variant] >= 25 && nose_counts[variant] <= 60)
		testing.expect(t, engine_counts[variant] >= 25 && engine_counts[variant] <= 60)
		testing.expect(t, wing_counts[variant] >= 25 && wing_counts[variant] <= 60)
		testing.expect(t, utility_counts[variant] >= 25 && utility_counts[variant] <= 60)
	}
	// With at most two of six families per hull there are 456 visually distinct
	// unordered recipes. Requiring 185/256 sampled identities guards strong
	// variety while preserving the compatibility constraint.
	testing.expect(t, unique >= 185)
}

@(test)
ship_construction_uses_a_coherent_two_family_design_language :: proc(t: ^testing.T) {
	mixed_family_hulls := 0
	for identity in 1 ..= 1024 {
		recipe := ship_render_recipe(game.Ship{construction_seed = u64(identity)})
		parts := [5]int{recipe.core, recipe.nose, recipe.engine, recipe.wing, recipe.utility}
		families: [2]int
		family_count := 0
		for part in parts {
			known := false
			for family in families[:family_count] do if family == part do known = true
			if !known {
				testing.expect(t, family_count < len(families))
				if family_count < len(families) {
					families[family_count] = part
					family_count += 1
				}
			}
		}
		testing.expect(t, family_count >= 1 && family_count <= 2)
		if family_count == 2 do mixed_family_hulls += 1
	}
	// A named two-yard pattern must always visibly use both source families.
	testing.expect_value(t, mixed_family_hulls, 1024)
}

@(test)
construction_siblings_share_design_families_but_keep_individual_layouts :: proc(t: ^testing.T) {
	for seed in 1 ..= 256 {
		campaign := game.new_campaign_heap(u64(seed))
		game.apply_generated_fleet(campaign, game.balanced_fleet_goals(), "FCS")
		distinct_layouts := 0
		for relationship in campaign.ship_relationships[:campaign.ship_relationship_count] {
			if relationship.kind != .Construction_Siblings do continue
			first_at := game.ship_index(campaign, relationship.ship_a)
			second_at := game.ship_index(campaign, relationship.ship_b)
			testing.expect(t, first_at >= 0 && second_at >= 0)
			if first_at < 0 || second_at < 0 do continue
			first, second := campaign.ships[first_at], campaign.ships[second_at]
			first_primary, first_accent := ship_construction_family_pair(first)
			second_primary, second_accent := ship_construction_family_pair(second)
			testing.expect_value(t, first_primary, second_primary)
			testing.expect_value(t, first_accent, second_accent)
			testing.expect_value(t, ship_yard_pattern_name(first), ship_yard_pattern_name(second))
			a, b := ship_render_recipe(first), ship_render_recipe(second)
			testing.expect_value(t, a.keel_profile, b.keel_profile)
			if a.core != b.core || a.nose != b.nose || a.engine != b.engine || a.wing != b.wing || a.utility != b.utility do distinct_layouts += 1
		}
		testing.expect_value(t, distinct_layouts, campaign.ship_relationship_count)
		game.campaign_destroy_heap(campaign)
	}
}

@(test)
yard_pattern_names_cover_every_ordered_family_pair_and_fit_the_dossier :: proc(t: ^testing.T) {
	seen: [36]bool
	for seed in 1 ..= 4096 {
		ship := game.Ship {
			id                = game.Ship_ID(seed),
			construction_seed = u64(seed),
		}
		primary, accent := ship_construction_family_pair(ship)
		testing.expect(
			t,
			primary >= 0 && primary < 6 && accent >= 0 && accent < 6 && primary != accent,
		)
		seen[primary * 6 + accent] = true
		name := ship_yard_pattern_name(ship)
		testing.expect(t, len(name) >= 9 && len(name) <= 15)
	}
	covered := 0
	for present in seen do if present do covered += 1
	testing.expect_value(t, covered, 30)
}

@(test)
ship_render_recipe_reflects_damage_and_departure :: proc(t: ^testing.T) {
	ship := game.Ship {
		id         = 3,
		role       = .Escort,
		hull_class = .Cruiser,
		active     = true,
	}
	healthy := ship_render_recipe(ship)
	ship.damage = 2
	damaged := ship_render_recipe(ship)
	testing.expect(t, damaged.damage / 6 == 2)
	testing.expect(t, damaged.effect / 6 == 4)
	ship.active = false
	departed := ship_render_recipe(ship)
	testing.expect(t, departed.effect / 6 == 5)
	testing.expect_value(t, healthy.core, damaged.core)
}

@(test)
ship_damage_visuals_distinguish_critical_breaches_from_persistent_scars :: proc(t: ^testing.T) {
	ship := game.Ship {
		id     = 8,
		active = true,
		damage = 4,
	}
	critical := ship_render_recipe(ship)
	testing.expect_value(t, critical.damage / 6, 3)
	ship.scar = .Hull_Breach
	scarred := ship_render_recipe(ship)
	testing.expect_value(t, scarred.damage / 6, 5)
	testing.expect_value(t, scarred.damage % 6, int(game.Ship_Scar.Hull_Breach) - 1)
}

@(test)
completed_repairs_leave_persistent_patchwork_until_a_scar_supersedes_it :: proc(t: ^testing.T) {
	ship := game.Ship {
		id                = 9,
		construction_seed = 0x7193,
		active            = true,
	}
	ship.memory_count = 1
	ship.memories[0].kind = .Ship_Repaired
	repaired := ship_render_recipe(ship)
	testing.expect(t, ship_damage_mark_visible(ship))
	testing.expect_value(t, repaired.damage / 6, 4)
	ship.memory_count = 0
	ship.archived_memory_tags = game.make_semantic_tags(.Memory, .Repair)
	archived_repair := ship_render_recipe(ship)
	testing.expect(t, ship_has_repair_memory(ship))
	testing.expect_value(t, archived_repair.damage / 6, 4)
	ship.damage = 1
	damaged := ship_render_recipe(ship)
	testing.expect_value(t, damaged.damage / 6, 1)
	ship.damage = 0
	ship.scar = .Alien_Symbiosis
	scarred := ship_render_recipe(ship)
	testing.expect_value(t, scarred.damage / 6, 5)
	testing.expect_value(t, repaired.core, damaged.core)
	testing.expect_value(t, damaged.core, scarred.core)
}

@(test)
ship_scar_types_have_unique_story_driven_visuals :: proc(t: ^testing.T) {
	scars := [6]game.Ship_Scar {
		.Storm_Shaken,
		.Hull_Breach,
		.Survivor_Guilt,
		.Alien_Symbiosis,
		.Oathbound,
		.Passage_Scarred,
	}
	seen: [6]bool
	for scar in scars {
		first := ship_render_recipe(game.Ship{id = 1, scar = scar})
		second := ship_render_recipe(game.Ship{id = 99, scar = scar})
		column := first.damage % 6
		testing.expect(t, column >= 0 && column < len(seen))
		testing.expect(t, !seen[column])
		seen[column] = true
		testing.expect_value(t, first.damage / 6, 5)
		testing.expect_value(t, first.damage, second.damage)
	}
}

@(test)
ship_render_recipe_shows_deployment_without_changing_construction :: proc(t: ^testing.T) {
	ship := game.Ship {
		id         = 4,
		role       = .Foundry,
		hull_class = .Fleet_Ship,
		active     = true,
	}
	idle := ship_render_recipe(ship)
	ship.committed = true
	deployed := ship_render_recipe(ship)
	ship.power = game.ship_hull_class_power(ship.role, ship.hull_class) * 3 / 2
	overdrive := ship_render_recipe(ship)
	testing.expect(t, idle.effect / 6 == 0)
	testing.expect(t, deployed.effect / 6 == 2)
	testing.expect(t, overdrive.effect / 6 == 3)
	testing.expect_value(t, idle.core, deployed.core)
	testing.expect_value(t, idle.engine, deployed.engine)
	testing.expect_value(t, deployed.engine, overdrive.engine)
}

@(test)
ship_propulsion_states_preserve_installed_engine_identity :: proc(t: ^testing.T) {
	ship := game.Ship {
		id     = 14,
		role   = .Survey,
		active = true,
	}
	idle := ship_render_recipe(ship)
	ship.committed = true
	deployed := ship_render_recipe(ship)
	ship.damage = 2
	failing := ship_render_recipe(ship)
	ship.active = false
	disabled := ship_render_recipe(ship)
	recipes := [4]Ship_Render_Recipe{idle, deployed, failing, disabled}
	for recipe in recipes {
		testing.expect_value(t, recipe.effect % 6, recipe.engine)
	}
	testing.expect_value(t, idle.effect / 6, 0)
	testing.expect_value(t, deployed.effect / 6, 2)
	testing.expect_value(t, failing.effect / 6, 4)
	testing.expect_value(t, disabled.effect / 6, 5)
}

@(test)
constellation_propulsion_visibility_tracks_persistent_ship_condition :: proc(t: ^testing.T) {
	ship := game.Ship {
		id         = 3,
		role       = .Survey,
		hull_class = .Corvette,
		active     = true,
	}
	testing.expect(t, !ship_marker_effect_visible(ship))
	ship.committed = true
	testing.expect(t, ship_marker_effect_visible(ship))
	ship.committed = false
	ship.damage = 2
	testing.expect(t, ship_marker_effect_visible(ship))
	ship.damage = 0
	ship.active = false
	testing.expect(t, ship_marker_effect_visible(ship))
	hull := R(50, 50, 40, 52)
	committed := ship_marker_effect_rect(hull, 1, 2)
	overdrive := ship_marker_effect_rect(hull, 1, 3)
	failing := ship_marker_effect_rect(hull, 1, 4)
	disabled := ship_marker_effect_rect(hull, 1, 5)
	testing.expect(t, overdrive.height > committed.height)
	testing.expect(t, committed.height > failing.height && failing.height > disabled.height)
	effects := [4]rl.Rectangle{committed, overdrive, failing, disabled}
	for effect in effects {
		testing.expect(t, effect.x >= hull.x && effect.x + effect.width <= hull.x + hull.width)
		testing.expect(t, effect.y < hull.y + hull.height)
		testing.expect(t, effect.y + effect.height <= hull.y + hull.height * 1.72)
	}
}

@(test)
ship_render_recipe_separates_construction_from_community_identity :: proc(t: ^testing.T) {
	ship := game.Ship {
		id                = 9,
		construction_seed = 0x9147,
		role              = .Agriculture,
		hull_class        = .Fleet_Ship,
		community         = 1,
		promises_broken   = 1,
	}
	first := ship_render_recipe(ship)
	ship.community = 4
	second := ship_render_recipe(ship)
	testing.expect_value(t, first.core, second.core)
	testing.expect_value(t, first.nose, second.nose)
	testing.expect_value(t, first.engine, second.engine)
	testing.expect_value(t, first.wing, second.wing)
	testing.expect(t, first.livery != second.livery)
	testing.expect(t, first.community_marking != second.community_marking)
	testing.expect_value(t, first.registry_marking, second.registry_marking)
	testing.expect_value(t, first.history_marking, second.history_marking)
}

@(test)
ship_render_recipe_mutations_change_only_their_visual_domain :: proc(t: ^testing.T) {
	ship := game.Ship {
		id                = 5,
		construction_seed = 0x5181,
		role              = .Agriculture,
		hull_class        = .Fleet_Ship,
		community         = 2,
		passage_trait     = .Cautious,
		active            = true,
		promises_upheld   = 1,
	}
	base := ship_render_recipe(ship)

	role_changed := ship
	role_changed.role = .Escort
	role_recipe := ship_render_recipe(role_changed)
	testing.expect(
		t,
		role_recipe.role_module != base.role_module &&
		role_recipe.role_marking != base.role_marking,
	)
	testing.expect_value(t, role_recipe.core, base.core)
	testing.expect_value(t, role_recipe.livery, base.livery)
	testing.expect_value(t, role_recipe.registry_marking, base.registry_marking)
	testing.expect_value(t, role_recipe.history_marking, base.history_marking)

	trait_changed := ship
	trait_changed.passage_trait = .Protective
	trait_recipe := ship_render_recipe(trait_changed)
	testing.expect(t, trait_recipe.trait_marking != base.trait_marking)
	testing.expect_value(t, trait_recipe.role_module, base.role_module)
	testing.expect_value(t, trait_recipe.registry_marking, base.registry_marking)

	damaged := ship
	damaged.damage = 2
	damage_recipe := ship_render_recipe(damaged)
	testing.expect(t, damage_recipe.damage != base.damage && damage_recipe.effect != base.effect)
	testing.expect_value(t, damage_recipe.core, base.core)
	testing.expect_value(t, damage_recipe.registry_marking, base.registry_marking)
	testing.expect_value(t, damage_recipe.history_marking, base.history_marking)
}

@(test)
ship_render_recipe_keeps_individual_registry_stable :: proc(t: ^testing.T) {
	ship := game.Ship {
		id         = 2,
		role       = .Archive,
		hull_class = .Corvette,
		community  = 2,
	}
	before := ship_render_recipe(ship)
	ship.experience = 6
	after := ship_render_recipe(ship)
	testing.expect_value(t, before.registry_marking, after.registry_marking)
	testing.expect(t, before.service_marking != after.service_marking)
	testing.expect_value(t, before.core, after.core)
}

@(test)
service_heraldry_progresses_with_experience_discovery_and_archived_memory :: proc(t: ^testing.T) {
	ship := game.Ship {
		id                = 7,
		construction_seed = 0x7719,
		role              = .Survey,
		hull_class        = .Corvette,
	}
	base_recipe := ship_render_recipe(ship)
	testing.expect_value(t, ship_service_rank(ship), -1)
	testing.expect(t, !ship_service_mark_visible(ship))
	scores := [6]int{1, 3, 6, 9, 13, 18}
	for score, rank in scores {
		ship.experience = i32(score)
		testing.expect_value(t, ship_service_rank(ship), rank)
		testing.expect_value(t, ship_render_recipe(ship).service_marking, 12 + rank)
		testing.expect_value(t, ship_render_recipe(ship).core, base_recipe.core)
	}
	ship.experience = 0
	ship.discoveries = 2
	ship.memory_count = 1
	ship.archived_memory_count = 1
	testing.expect_value(t, ship_service_score(ship), 6)
	testing.expect_value(t, ship_service_rank(ship), 2)
	ship.memory_count = 12
	ship.archived_memory_count = 40
	testing.expect_value(t, ship_service_score(ship), 10)
}

@(test)
ship_render_recipe_preserves_construction_through_refit :: proc(t: ^testing.T) {
	ship := game.Ship {
		id         = 6,
		role       = .Survey,
		hull_class = .Corvette,
		community  = 2,
	}
	original := ship_render_recipe(ship)
	ship.role = .Escort
	ship.hull_class = .Cruiser
	refit := ship_render_recipe(ship)
	testing.expect_value(t, original.core, refit.core)
	testing.expect_value(t, original.nose, refit.nose)
	testing.expect_value(t, original.engine, refit.engine)
	testing.expect_value(t, original.wing, refit.wing)
	testing.expect_value(t, original.utility, refit.utility)
	testing.expect(t, original.role_module != refit.role_module)
}

@(test)
ship_render_recipe_records_promise_outcome_without_rebuilding_hull :: proc(t: ^testing.T) {
	ship := game.Ship {
		id              = 11,
		role            = .Hospital,
		hull_class      = .Cruiser,
		community       = 3,
		promises_upheld = 1,
	}
	upheld := ship_render_recipe(ship)
	ship.promises_upheld = 0
	ship.promises_broken = 1
	broken := ship_render_recipe(ship)
	testing.expect_value(t, upheld.core, broken.core)
	testing.expect_value(t, upheld.livery, broken.livery)
	testing.expect(t, upheld.history_marking != broken.history_marking)
}

@(test)
ship_hull_class_proportions_are_ordered :: proc(t: ^testing.T) {
	classes := [5]game.Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	for i in 1 ..< len(classes) {
		testing.expect(
			t,
			ship_hull_width_scale(classes[i]) > ship_hull_width_scale(classes[i - 1]),
		)
		testing.expect(
			t,
			ship_hull_length_scale(classes[i]) > ship_hull_length_scale(classes[i - 1]),
		)
		testing.expect(t, ship_wing_fraction(classes[i]) < ship_wing_fraction(classes[i - 1]))
		testing.expect(t, ship_core_fraction(classes[i]) > ship_core_fraction(classes[i - 1]))
		testing.expect(t, ship_nose_fraction(classes[i]) > ship_nose_fraction(classes[i - 1]))
		testing.expect(
			t,
			ship_engine_volume_scale(classes[i]) > ship_engine_volume_scale(classes[i - 1]),
		)
		prior_top, prior_height := ship_wing_vertical_profile(classes[i - 1])
		current_top, current_height := ship_wing_vertical_profile(classes[i])
		testing.expect(t, current_top > prior_top)
		testing.expect(t, current_height < prior_height)
	}
}

@(test)
ship_bow_profiles_create_ordered_bounded_planforms :: proc(t: ^testing.T) {
	hull := R(20, 30, 100, 160)
	blunt := ship_marker_nose_rect(hull, .Fleet_Ship, 1, 0)
	standard := ship_marker_nose_rect(hull, .Fleet_Ship, 1, 1)
	needle := ship_marker_nose_rect(hull, .Fleet_Ship, 1, 2)
	testing.expect(t, blunt.width > standard.width && standard.width > needle.width)
	testing.expect(t, blunt.height < standard.height && standard.height < needle.height)
	rects := [3]rl.Rectangle{blunt, standard, needle}
	for rect in rects {
		testing.expect(t, rect.x >= hull.x && rect.x + rect.width <= hull.x + hull.width)
		testing.expect(t, rect.y >= hull.y && rect.y + rect.height <= hull.y + hull.height)
	}
}

@(test)
ship_visual_geometry_stays_inside_dossier_preview :: proc(t: ^testing.T) {
	center_x, center_y: f32 = 1156, 158
	base := R(center_x - 58, 84, 116, 154)
	classes := [5]game.Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	for hull in classes do for profile in 0 ..< 3 {
		keel_width, keel_length := ship_keel_profile_scale(profile)
		scaled := scale_ship_rect(base, center_x, center_y, ship_hull_width_scale(hull) * keel_width, ship_hull_length_scale(hull) * keel_length)
		testing.expect(t, scaled.x >= 1080 && scaled.x + scaled.width <= 1232)
		testing.expect(t, scaled.y >= 64 && scaled.y + scaled.height <= 260)
	}
}

@(test)
ship_utility_volume_tracks_mass_with_safe_bounds :: proc(t: ^testing.T) {
	light := ship_utility_volume_scale(game.Ship{hull_class = .Fleet_Ship, mass_tonnes = 18000})
	heavy := ship_utility_volume_scale(game.Ship{hull_class = .Fleet_Ship, mass_tonnes = 180000})
	testing.expect(t, light < heavy)
	testing.expect(t, light >= .819 && heavy <= 1.181)
}

@(test)
ship_utility_volume_is_normalized_inside_every_hull_class :: proc(t: ^testing.T) {
	classes := [5]game.Hull_Class{.Strike_Craft, .Corvette, .Fleet_Ship, .Cruiser, .Capital_Ship}
	for hull_class in classes {
		low, high := game.ship_hull_mass_range(hull_class)
		mid := low + (high - low) / 2
		minimum := ship_utility_volume_scale(game.Ship{hull_class = hull_class, mass_tonnes = low})
		middle := ship_utility_volume_scale(game.Ship{hull_class = hull_class, mass_tonnes = mid})
		maximum := ship_utility_volume_scale(
			game.Ship{hull_class = hull_class, mass_tonnes = high},
		)
		testing.expect(t, math.abs(f64(minimum - .82)) < .001)
		testing.expect(t, math.abs(f64(middle - 1)) < .01)
		testing.expect(t, math.abs(f64(maximum - 1.18)) < .001)
		testing.expect(t, minimum < middle && middle < maximum)
	}
	legacy := ship_utility_volume_scale(game.Ship{hull_class = .Unspecified, mass_tonnes = 45000})
	testing.expect(t, legacy >= .82 && legacy <= 1.18)
}
