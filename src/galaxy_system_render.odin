package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:testing"
import "core:time"
draw_selected_solar_system :: proc(s: ^Ux_State, sample_index: int) {
	sample := &s.galaxy.detailed_systems[sample_index]
	system := &sample.system
	if system.planet_count == 0 do return
	names := game.generate_solar_system_names(system^)
	center := V(f32(1091), f32(520))
	maximum_radius := f32(116)
	tilt := f32(.24)
	rotation := f32(-.13)
	cos_rotation := f32(math.cos(f64(rotation)))
	sin_rotation := f32(math.sin(f64(rotation)))
	outer := f64(
		.01,
	); for planet in system.planets[:system.planet_count] do outer = max(outer, planet.orbit.semi_major_axis_au)
	survey_epoch_days := f64(s.campaign.year) * 365.256 + f64(s.campaign.season) * 30.438

	// A low camera angle turns the orbital plane into a severe diagonal instead
	// of an overhead diagram. The far half is deliberately fainter, giving the
	// tiny panel a useful sense of depth without introducing camera state.
	for planet in system.planets[:system.planet_count] {
		fraction := math.log10(1 + planet.body.inputs.semi_major_axis_au) / math.log10(1 + outer)
		radius := 15 + f32(fraction) * (maximum_radius - 15)
		previous := center
		for segment in 0 ..= 64 {
			angle := f32(segment) * 2 * f32(math.PI) / 64
			local_x := math.cos(angle) * radius
			local_y := math.sin(angle) * radius * tilt
			current := V(
				center.x + local_x * cos_rotation - local_y * sin_rotation,
				center.y + local_x * sin_rotation + local_y * cos_rotation,
			)
			if segment > 0 {
				alpha := math.sin(angle) < 0 ? u8(35) : u8(78)
				rl.DrawLineEx(
					previous,
					current,
					math.sin(angle) < 0 ? f32(.55) : f32(.9),
					{151, 160, 158, alpha},
				)
			}
			previous = current
		}
	}

	// Belts read as engraved dust rather than additional UI rules.
	for belt, belt_index in system.belts[:system.belt_count] {
		belt_au := (belt.inner_au + belt.outer_au) * .5
		fraction := math.log10(1 + belt_au) / math.log10(1 + outer)
		radius := 15 + f32(clamp(fraction, 0, 1.08)) * (maximum_radius - 15)
		for grain in 0 ..< 34 {
			phase := galaxy_star_unit(system.seed + u64(belt_index), grain, 7) * 2 * math.PI
			jitter := f32(galaxy_star_unit(system.seed + u64(belt_index), grain, 8) - .5) * 5
			local_x := f32(math.cos(phase)) * (radius + jitter)
			local_y := f32(math.sin(phase)) * (radius + jitter) * tilt
			point := V(
				center.x + local_x * cos_rotation - local_y * sin_rotation,
				center.y + local_x * sin_rotation + local_y * cos_rotation,
			)
			rl.DrawCircleV(point, grain % 5 == 0 ? f32(1) : f32(.55), {185, 185, 174, 92})
		}
	}

	for planet, planet_index in system.planets[:system.planet_count] {
		fraction := math.log10(1 + planet.body.inputs.semi_major_axis_au) / math.log10(1 + outer)
		radius := 15 + f32(fraction) * (maximum_radius - 15)
		rel, _ := game.system_relative_state_at(
			system,
			{kind = .Planet, index = planet_index},
			planet.host,
			survey_epoch_days,
		)
		phase := math.atan2(rel.position_au[1], rel.position_au[0])
		local_x := f32(math.cos(phase)) * radius
		local_y := f32(math.sin(phase)) * radius * tilt
		position := V(
			center.x + local_x * cos_rotation - local_y * sin_rotation,
			center.y + local_x * sin_rotation + local_y * cos_rotation,
		)
		color :=
			planet.kind == .Gas_Giant ? UX.warn : planet.kind == .Ice_Giant || planet.kind == .Ice ? UX.info : UX.good
		body_radius :=
			planet.kind == .Gas_Giant ? f32(4.8) : planet.kind == .Ice_Giant ? f32(4) : f32(2.7)
		depth_scale := .88 + f32(math.sin(phase)) * .12
		hit_radius := max(body_radius * depth_scale + 4, f32(8))
		hit_rect := R(
			position.x - hit_radius,
			position.y - hit_radius,
			hit_radius * 2,
			hit_radius * 2,
		)
		interaction := rl.ButtonBehavior(ux_button_cursor, hit_rect, true)
		ux_button_cursor += 1
		active := interaction.hovered || interaction.focused
		if interaction.activated && s.modal == .None {
			s.selected_system_detail = sample_index
			s.selected_body = {
				kind  = .Planet,
				index = planet_index,
			}
			s.modal = .Body_Detail
		}
		if active {
			rl.DrawCircleV(position, body_radius * depth_scale + 3, {104, 181, 198, 75})
			ux_tooltip = {
				visible = true,
				anchor  = hit_rect,
				title   = fmt.tprintf("%s · %v", names.planet_names[planet_index], planet.kind),
				body    = fmt.tprintf(
					"%.2f AU · %.0f DAY ORBIT · %.2f EARTH MASS · %.2f G · %.0f K · %d MOONS",
					planet.body.inputs.semi_major_axis_au,
					planet.body.orbital_period_days,
					planet.body.inputs.mass_earth,
					planet.body.surface_gravity_earth,
					planet.body.surface_temperature_k,
					planet.moon_count,
				),
			}
		}
		rl.DrawCircleV(position, body_radius * depth_scale + .8, {8, 10, 10, 230})
		rl.DrawCircleV(position, body_radius * depth_scale, color)
		rl.DrawCircleV(
			V(position.x - 1, position.y - 1),
			max(.65, body_radius * .22),
			{231, 229, 211, 175},
		)
		// A black offset disc creates an etched terminator, making each planet a
		// lit body rather than a colored node.
		rl.DrawCircleV(
			V(position.x + body_radius * .48, position.y + body_radius * .18),
			body_radius * .72,
			{5, 7, 7, 205},
		)
	}

	star_hatch :=
		LBH_HATCH_ENGRAVING; star_hatch.spacing = 2.2; star_hatch.line_width = .7; star_hatch.strength = .72; star_hatch.layer_count = 2
	if system.star_count == 2 && system.binary_bound {
		previous := V(center.x + 13, center.y)
		for segment in 1 ..= 32 {angle := f32(segment) * 2 * f32(math.PI) / 32; current := V(center.x + math.cos(angle) * 13, center.y + math.sin(angle) * 13); rl.DrawLineEx(previous, current, .6, {151, 160, 158, 70}); previous = current}
	}
	for star, star_index in system.stars[:system.star_count] {
		stellar_position := center
		if system.star_count == 2 &&
		   system.binary_bound {state, _ := game.system_body_state_at(system, {kind = .Star, index = star_index}, survey_epoch_days); scale := f32(13 / max(system.binary_orbit.semi_major_axis_au, 1.0e-9)); stellar_position = V(center.x + f32(state.position_au[0]) * scale, center.y + f32(state.position_au[1]) * scale * tilt)}
		star_hatch.offset = V(
			-stellar_position.x,
			-stellar_position.y,
		); radius := star_index == 0 ? f32(8.5) : f32(6.8)
		hit := R(
			stellar_position.x - 11,
			stellar_position.y - 11,
			22,
			22,
		); interaction := rl.ButtonBehavior(ux_button_cursor, hit, true); ux_button_cursor += 1
		if interaction.activated &&
		   s.modal == .None {s.selected_system_detail = sample_index; s.selected_body = {
				kind  = .Star,
				index = star_index,
			}; s.modal = .Body_Detail}
		if interaction.hovered ||
		   interaction.focused {rl.DrawCircleV(stellar_position, radius + 3, {224, 185, 96, 62}); ux_tooltip = {
				visible = true,
				anchor  = hit,
				title   = fmt.tprintf("%s · %v", names.star_names[star_index], star.phase),
				body    = fmt.tprintf(
					"%.0f K · %.2f SOLAR MASS · %.1f GYR",
					star.effective_temperature_k,
					star.profile.mass_solar,
					star.profile.age_billion_years,
				),
			}}
		rl.DrawCircleHatched(
			stellar_position,
			radius,
			{224, 185, 96, 235},
			star_hatch,
			32,
		); rl.DrawCircleV(V(stellar_position.x - 2, stellar_position.y - 2), max(1.4, radius * .25), {241, 225, 178, 210})
	}
	draw_fmt(
		956,
		558,
		TYPE_LABEL,
		UX.dim,
		"%d STARS · %d PLANETS · %d MOONS",
		system.star_count,
		system.planet_count,
		system.moon_count,
	)
	if button(
		R(1164, 548, 76, 20),
		"HISTORY",
	) {s.selected_system_detail = sample_index; s.selected_body = {
			kind = .Barycenter,
		}; s.modal = .Body_Detail}
}

// A metric's definition belongs at its point of use. The dossier remains a
// compact survey plate while players who hover an unfamiliar term get its
// measurement basis without leaving the system record.
draw_celestial_stat :: proc(x, y: f32, label, value: string, color := UX.text, description := "") {
	draw_text(label, x, y, TYPE_FINE, UX.dim)
	draw_text(value, x, y + 17, TYPE_SUBHEADING_COMPACT, color)
	if len(description) > 0 && rl.CheckCollisionPointRec(ux_mouse, R(x, y - 3, 132, 43)) do ux_tooltip = {
		visible = true,
		anchor  = R(x, y - 3, 132, 43),
		title   = label,
		body    = description,
	}
}

system_planet_kind_label :: proc(kind: game.System_Planet_Kind) -> string {
	switch kind {
	case .Rocky:
		return "ROCK WORLD"
	case .Ocean:
		return "OCEAN WORLD"
	case .Ice:
		return "ICE WORLD"
	case .Ice_Giant:
		return "ICE GIANT"
	case .Gas_Giant:
		return "GAS GIANT"
	}
	return "PLANETARY BODY"
}

draw_system_planet_detail :: proc(
	planet: ^game.System_Planet,
	bounds: rl.Rectangle,
	reduced_motion: bool,
) {
	kind: Planet_Kind
	switch planet.kind {
	case .Rocky:
		kind = .Rocky
	case .Ocean:
		kind = .Fertile
	case .Ice:
		kind = .Ice
	case .Ice_Giant:
		kind = .Ice_Giant
	case .Gas_Giant:
		kind = .Gas_Giant
	}
	seed := planet.body.seed
	phase := f32(seed % 10007) / 10007 * 2 * f32(math.PI)
	giant := planet.kind == .Gas_Giant || planet.kind == .Ice_Giant
	ringed := giant && ((seed >> 5) & 3) != 0
	config := Planet_Config {
		kind             = kind,
		seed             = f32(seed % 1000003),
		phase            = phase,
		axial_tilt       = (f32((seed >> 17) % 1000) / 1000 - .5) * .78,
		ocean_fraction   = planet.kind == .Ocean ? .72 : planet.kind == .Rocky ? .035 : .08,
		atmosphere       = planet.kind == .Ocean ? .72 : planet.kind == .Rocky ? .08 : planet.kind == .Ice ? .28 : .54,
		cloud_cover      = planet.kind == .Ocean ? .58 : planet.kind == .Rocky ? .04 : planet.kind == .Ice ? .14 : .36,
		banding          = giant ? .84 : .08,
		rings            = ringed ? .68 : 0,
		flattening       = giant ? .94 : 1,
		body_radius      = ringed ? .42 : .92,
		ring_inner       = ringed ? 1.28 : 0,
		ring_outer       = ringed ? 2.18 : 0,
		ring_density     = ringed ? .62 : 0,
		ring_structure   = ringed ? .76 : 0,
		rotation_rate    = giant ? 1.2 : .78,
		humidity         = planet.kind == .Ocean ? .72 : giant ? .7 : .12,
		circulation      = giant ? .9 : planet.kind == .Ocean ? .52 : .26,
		cloud_altitude   = giant ? .026 : planet.kind == .Ocean ? .018 : .012,
		atmosphere_time  = planet_detail_benchmark_time >= 0 ? planet_detail_benchmark_time : f32(rl.GetTime()),
		geometric_albedo = f32(planet.geometric_albedo),
	}
	apply_planet_mark_palette(&config, planet_surface_palette(planet.surface))
	set_cloud_composition(&config, planet.clouds)
	atmosphere_started := time.tick_now()
	atlas := atmosphere_texture_for(&config, seed, config.atmosphere_time, reduced_motion)
	planet_detail_atmosphere_cpu_ms =
		time.duration_seconds(time.tick_since(atmosphere_started)) * 1000
	DrawPlanet(bounds, {231, 229, 211, 255}, config, atlas)
}

draw_system_star_detail :: proc(
	star: ^game.System_Star,
	seed: u64,
	bounds: rl.Rectangle,
	reduced_motion: bool,
) {
	kind := stellar_render_kind(star.phase)
	// Apparent plate size communicates evolutionary state without attempting to
	// put stellar radii on the same literal scale as the surrounding system map.
	body_radius := f32(.68)
	#partial switch star.phase {
	case .Protostar:
		body_radius = .62
	case .Hertzsprung_Gap:
		body_radius = .70
	case .Red_Giant, .Asymptotic_Giant:
		body_radius = .74
	case .Core_Helium_Burning:
		body_radius = .70
	case .Stripped_Helium:
		body_radius = .48
	case .White_Dwarf:
		body_radius = .42
	case .Neutron_Star:
		body_radius = .12
	case .Black_Hole:
		body_radius = .18
	}
	spin_rate := f32(clamp(.24 / max(star.spin_period_days, .0001), .0004, 1.8))
	config := Star_Config {
		kind               = kind,
		seed               = f32(seed % 1000003),
		phase              = f32(seed % 10007) / 10007 * 2 * f32(math.PI),
		activity           = .34 + f32((seed >> 11) % 1000) / 1000 * .58,
		spots              = .28 + f32((seed >> 23) % 1000) / 1000 * .62,
		granulation        = .55 + f32((seed >> 37) % 1000) / 1000 * .4,
		corona             = .38 + f32((seed >> 49) % 1000) / 1000 * .54,
		rotation           = (f32((seed >> 7) % 1000) / 1000 - .5) * .6,
		body_radius        = body_radius,
		temperature_kelvin = f32(star.effective_temperature_k),
		luminosity_solar   = f32(star.profile.luminosity_solar),
		mass_solar         = f32(star.profile.mass_solar),
		radius_solar       = f32(star.profile.radius_solar),
		time_seconds       = planet_detail_benchmark_time >= 0 ? planet_detail_benchmark_time : f32(rl.GetTime()),
		rotation_rate      = spin_rate,
		reduced_motion     = reduced_motion,
	}
	DrawStar(bounds, {231, 229, 211, 255}, config)
}

stellar_render_kind :: proc(phase: game.Stellar_Phase) -> Star_Kind {
	switch phase {
	case .Protostar:
		return .Protostar
	case .Hertzsprung_Gap, .Red_Giant, .Asymptotic_Giant, .Merged:
		return .Red_Giant
	case .Core_Helium_Burning:
		return .Blue_Giant
	case .Stripped_Helium:
		return .Stripped_Star
	case .White_Dwarf:
		return .White_Dwarf
	case .Neutron_Star:
		return .Neutron
	case .Black_Hole:
		return .Black_Hole
	case .Main_Sequence:
		return .Main_Sequence
	}
	return .Main_Sequence
}

@(test)
stellar_render_kinds_cover_evolved_phases :: proc(t: ^testing.T) {
	testing.expect_value(t, stellar_render_kind(.Protostar), Star_Kind.Protostar)
	testing.expect_value(t, stellar_render_kind(.Stripped_Helium), Star_Kind.Stripped_Star)
	testing.expect_value(t, stellar_render_kind(.White_Dwarf), Star_Kind.White_Dwarf)
	testing.expect_value(t, stellar_render_kind(.Neutron_Star), Star_Kind.Neutron)
	testing.expect_value(t, stellar_render_kind(.Black_Hole), Star_Kind.Black_Hole)
}
