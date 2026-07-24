package main

import rl "zelda_engine:canvas2d"
import game "../packages/game"
import "core:fmt"
import "core:math"

black_hole_accretion_label :: proc(kind: game.Black_Hole_Accretion_Kind) -> string {
	switch kind {
	case .Dormant:
		return "DORMANT"
	case .Wind_Fed:
		return "WIND-FED"
	case .Transfer_Disk:
		return "TRANSFER DISK"
	case .Thick_Flow:
		return "THICK FLOW"
	}
	return "UNRESOLVED"
}

black_hole_view_angle_degrees :: proc(accretion: game.Black_Hole_Accretion) -> f64 {
	return math.acos(clamp(accretion.view_cosine, .0, 1.0)) * 180 / math.PI
}

black_hole_position_angle_degrees :: proc(accretion: game.Black_Hole_Accretion) -> f64 {
	return accretion.view_position_angle_radians * 180 / math.PI
}

black_hole_project_point :: proc(center: rl.Vector2, x, y, angle: f32) -> rl.Vector2 {
	c, s := f32(math.cos(angle)), f32(math.sin(angle))
	return V(center.x + x * c - y * s, center.y + x * s + y * c)
}

black_hole_lensed_disk_point :: proc(
	center: rl.Vector2,
	x, y, position_angle, critical_radius, far_weight: f32,
) -> (
	direct, secondary: rl.Vector2,
	secondary_visible: bool,
) {
	beta := math.sqrt(x * x + y * y)
	if beta < .001 do return center, center, false
	// Schwarzschild screen-space approximation. The positive branch displaces the
	// direct image outward; the negative branch is folded back against the critical
	// curve. Only the far half of the equatorial disk receives the strong branch.
	lens2 := critical_radius * critical_radius * clamp(far_weight, 0, 1)
	root := math.sqrt(beta * beta + 4 * lens2)
	direct_radius := (beta + root) * .5
	direct_scale := direct_radius / beta
	direct = black_hole_project_point(center, x * direct_scale, y * direct_scale, position_angle)
	if far_weight <= .035 do return direct, center, false
	negative_radius := max((root - beta) * .5, 0)
	secondary_radius :=
		critical_radius * (1.015 + .105 * far_weight) + min(negative_radius, critical_radius * .18)
	secondary_scale := -secondary_radius / beta
	secondary = black_hole_project_point(
		center,
		x * secondary_scale,
		y * secondary_scale,
		position_angle,
	)
	return direct, secondary, true
}

black_hole_draw_emission_glow :: proc(a, b: rl.Vector2, strength: f32) {
	s := clamp(strength, f32(0), f32(1))
	if s <= .002 do return
	// Two restrained silver scatter layers approximate the star renderer's corona
	// while retaining hard engraved contours and untouched black between them.
	rl.DrawLineEx(a, b, 5.5, {197, 207, 203, u8(2 + s * 10)})
	rl.DrawLineEx(a, b, 2.6, {218, 220, 207, u8(3 + s * 17)})
}

black_hole_capture_fixture :: proc(kind: string) -> game.Solar_System {
	s: game.Solar_System
	s.seed = 0x626c61636b686f6c
	s.model_version = game.STELLAR_SYSTEM_MODEL_VERSION
	s.present_age_billion_years = 11.5
	s.star_count = 2
	s.binary_bound = true
	s.stars[0] = game.evolve_star_to_age(35, 0, 1)
	s.stars[1] = game.evolve_star_to_age(1, 0, 4.6)
	s.binary_orbit = {
		semi_major_axis_au = 2,
		eccentricity       = .05,
	}
	switch kind {
	case "black-hole-wind":
		s.stars[1] = game.evolve_star_to_age(1, 0, 11.5)
		s.binary_orbit = {
			semi_major_axis_au = 2,
			eccentricity       = .08,
		}
	case "black-hole-transfer", "black-hole-transfer-face", "black-hole-transfer-edge":
		s.stars[1] = game.evolve_star_to_age(6, 0, .025)
		s.binary_orbit = {
			semi_major_axis_au = .024,
			eccentricity       = 0,
		}
		if kind == "black-hole-transfer-face" do s.seed = 366
		if kind == "black-hole-transfer-edge" do s.seed = 694
	case "black-hole-thick":
		s.stars[1] = game.evolve_star_to_age(1, 0, 11.5)
		s.binary_orbit = {
			semi_major_axis_au = .15,
			eccentricity       = 0,
		}
	case:
	}
	return s
}

draw_black_hole_detail :: proc(
	accretion: game.Black_Hole_Accretion,
	seed: u64,
	bounds: rl.Rectangle,
	reduced_motion: bool,
) {
	center := V(bounds.x + bounds.width * .5, bounds.y + bounds.height * .5)
	plate_radius := min(bounds.width, bounds.height) * .43
	critical_radius := plate_radius * .205
	phase := f32(seed % 10007) / 10007 * 2 * f32(math.PI)
	if !reduced_motion do phase += f32(rl.GetTime()) * .008

	bone := rl.Color{224, 222, 207, 205}
	active := accretion.kind != .Dormant
	emission_strength :=
		active ? f32(math.pow(clamp(accretion.eddington_fraction, 0, 1), .25)) : f32(0)
	faint := rl.Color{180, 182, 172, 42}

	// Sparse source marks make the lens legible by showing what it distorts.
	// Their exclusion zone preserves the untouched black around the horizon.
	for i in 0 ..< 34 {
		x := bounds.x + f32(galaxy_star_unit(seed, i, 701)) * bounds.width
		y := bounds.y + f32(galaxy_star_unit(seed, i, 702)) * bounds.height
		dx, dy := x - center.x, y - center.y
		if dx * dx + dy * dy < plate_radius * plate_radius * .32 do continue
		alpha := u8(34 + int(galaxy_star_unit(seed, i, 703) * 70))
		rl.DrawCircleV(V(x, y), i % 9 == 0 ? f32(.8) : f32(.42), {218, 217, 204, alpha})
	}

	// Warped survey grid: straight bearings bend tangentially as they pass the
	// compact mass. This is a measurement diagram, not an accretion structure.
	for axis in -3 ..= 3 {
		if axis == 0 do continue
		previous := V(f32(0), f32(0))
		for segment in 0 ..= 48 {
			t := f32(segment) / 48 * 2 - 1
			offset := f32(axis) * plate_radius * .19
			x, y := t * plate_radius, offset
			distance2 := x * x + y * y
			bend :=
				plate_radius *
				plate_radius *
				.026 /
				max(distance2, plate_radius * plate_radius * .035)
			y += math.sign(offset) * bend * plate_radius * .11
			p := V(center.x + x, center.y + y)
			if segment > 0 do rl.DrawLineEx(previous, p, .55, faint)
			previous = p
		}
	}

	if active {
		view_cosine := accretion.view_cosine > 0 ? f32(accretion.view_cosine) : f32(.32)
		position_angle := f32(accretion.view_position_angle_radians)
		beaming_strength := math.sqrt(max(0, 1 - view_cosine * view_cosine))
		intrinsic_thickness :=
			accretion.kind == .Thick_Flow ? f32(.32) : accretion.kind == .Wind_Fed ? f32(.20) : f32(.08)
		vertical_scale := clamp(
			math.sqrt(view_cosine * view_cosine + intrinsic_thickness * intrinsic_thickness),
			.18,
			.96,
		)
		// The disk is built only from sampled contours. There is no unwarped base
		// ellipse: every visible material ring passes through the same lens mapping.
		disk_radius := accretion.kind == .Wind_Fed ? plate_radius * .55 : plate_radius * .76
		inner_disk_radius := accretion.kind == .Wind_Fed ? plate_radius * .25 : plate_radius * .34
		groove_count := accretion.kind == .Wind_Fed ? 8 : accretion.kind == .Thick_Flow ? 13 : 16
		for groove in 0 ..< groove_count {
			u := f32(groove) / f32(max(groove_count - 1, 1))
			radius := disk_radius * (1 - u) + inner_disk_radius * u
			for segment in 0 ..< 96 {
				gap := (segment + groove * 11 + int(seed % 17)) % 19
				if gap < (accretion.kind == .Thick_Flow ? 8 : 3) do continue
				a0 := f32(segment) * 2 * f32(math.PI) / 96
				a1 := f32(segment + 1) * 2 * f32(math.PI) / 96
				x0, y0 := math.cos(a0) * radius, math.sin(a0) * radius * vertical_scale
				x1, y1 := math.cos(a1) * radius, math.sin(a1) * radius * vertical_scale
				far0 := max(-math.sin(a0), f32(0))
				far1 := max(-math.sin(a1), f32(0))
				p0, s0, secondary0 := black_hole_lensed_disk_point(
					center,
					x0,
					y0,
					position_angle,
					critical_radius,
					far0,
				)
				p1, s1, secondary1 := black_hole_lensed_disk_point(
					center,
					x1,
					y1,
					position_angle,
					critical_radius,
					far1,
				)
				alpha := u8(32 + groove * 7)
				if groove % 2 == 0 do black_hole_draw_emission_glow(p0, p1, emission_strength * .72)
				rl.DrawLineEx(p0, p1, .42, {232, 229, 211, alpha})
				if secondary0 && secondary1 {
					approaching_secondary := x0 < 0
					beam_factor :=
						approaching_secondary ? 1 + beaming_strength * .35 : 1 - beaming_strength * .18
					secondary_alpha := u8(clamp((52 + far0 * 64) * beam_factor, 24, 148))
					secondary_width :=
						approaching_secondary ? .48 + beaming_strength * .18 : .48 - beaming_strength * .08
					black_hole_draw_emission_glow(s0, s1, emission_strength * far0 * .9)
					rl.DrawLineEx(s0, s1, secondary_width, {224, 222, 207, secondary_alpha})
				}
			}
		}

		if accretion.kind == .Wind_Fed {
			// A captured stellar wind arrives as a broad, incoherent wake rather than a
			// Roche-lobe stream. Sparse converging cuts preserve that distinction.
			for filament in 0 ..< 9 {
				offset := (f32(filament) - 4) * plate_radius * .035
				start := black_hole_project_point(
					center,
					-plate_radius * .9,
					-plate_radius * .38 + offset,
					position_angle,
				)
				control := black_hole_project_point(
					center,
					-plate_radius * .48,
					-plate_radius * .18 + offset * .45,
					position_angle,
				)
				finish := black_hole_project_point(
					center,
					-plate_radius * .19,
					offset * .12,
					position_angle,
				)
				previous := start
				for segment in 1 ..= 14 {
					t := f32(segment) / 14
					one_minus_t := 1 - t
					p := V(
						one_minus_t * one_minus_t * start.x +
						2 * one_minus_t * t * control.x +
						t * t * finish.x,
						one_minus_t * one_minus_t * start.y +
						2 * one_minus_t * t * control.y +
						t * t * finish.y,
					)
					if (segment + filament * 3) % 7 != 0 do rl.DrawLineEx(previous, p, .38, {208, 209, 197, u8(38 + filament * 3)})
					previous = p
				}
			}
		} else if accretion.kind == .Transfer_Disk {
			// A coherent Roche-lobe stream strikes the outer rim at one localized bright
			// incision. The donor itself remains outside this cropped survey plate.
			start := black_hole_project_point(
				center,
				plate_radius * .93,
				-plate_radius * .48,
				position_angle,
			)
			control := black_hole_project_point(
				center,
				plate_radius * .72,
				-plate_radius * .18,
				position_angle,
			)
			finish := black_hole_project_point(
				center,
				disk_radius * .61,
				disk_radius * vertical_scale * .78,
				position_angle,
			)
			previous := start
			for segment in 1 ..= 24 {
				t := f32(segment) / 24
				one_minus_t := 1 - t
				p := V(
					one_minus_t * one_minus_t * start.x +
					2 * one_minus_t * t * control.x +
					t * t * finish.x,
					one_minus_t * one_minus_t * start.y +
					2 * one_minus_t * t * control.y +
					t * t * finish.y,
				)
				if segment % 6 != 0 do rl.DrawLineEx(previous, p, .72, {230, 227, 210, 135})
				previous = p
			}
			rl.DrawCircleV(finish, 2.1, {230, 227, 210, 185})
		} else if accretion.kind == .Thick_Flow {
			// Short, uneven radial cuts distinguish an optically thick turbulent flow
			// from the orderly nested grooves of a thin transfer disk.
			for cut in 0 ..< 24 {
				a := f32(cut) / 24 * 2 * f32(math.PI) + phase
				r0 := plate_radius * (.3 + f32(galaxy_star_unit(seed, cut, 811)) * .18)
				r1 := r0 + plate_radius * (.035 + f32(galaxy_star_unit(seed, cut, 812)) * .08)
				p0 := black_hole_project_point(
					center,
					math.cos(a) * r0,
					math.sin(a) * r0 * vertical_scale,
					position_angle,
				)
				p1 := black_hole_project_point(
					center,
					math.cos(a + .035) * r1,
					math.sin(a + .035) * r1 * vertical_scale,
					position_angle,
				)
				rl.DrawLineEx(p0, p1, .7, {226, 223, 207, u8(48 + cut % 5 * 12)})
			}
		}

	} else {
		// With no matter supply there is no visible disk. What the survey can recover
		// is a broken Einstein-ring solution from displaced background sources.
		for ring in 0 ..< 2 {
			radius := plate_radius * (ring == 0 ? f32(.29) : f32(.315))
			for segment in 0 ..< 80 {
				if (segment * 7 + ring * 13 + int(seed % 29)) % 23 < 9 do continue
				a0 := f32(segment) * 2 * f32(math.PI) / 80
				a1 := f32(segment + 1) * 2 * f32(math.PI) / 80
				p0 := V(center.x + math.cos(a0) * radius, center.y + math.sin(a0) * radius)
				p1 := V(center.x + math.cos(a1) * radius, center.y + math.sin(a1) * radius)
				rl.DrawLineEx(
					p0,
					p1,
					ring == 0 ? f32(.9) : f32(.45),
					{218, 217, 204, ring == 0 ? u8(116) : u8(62)},
				)
			}
		}
	}

	// The dark image is the apparent capture shadow, not a direct photograph of
	// the smaller event horizon. A dim dashed overlay retains the horizon as an
	// archival scale measurement without confusing it with the observed boundary.
	shadow_radius := plate_radius * .188
	rl.DrawCircleV(center, shadow_radius, {0, 0, 0, 255})

	photon_radius := critical_radius
	for segment in 0 ..< 72 {
		if (segment + int(seed % 11)) % 13 == 0 do continue
		a0 := f32(segment) * 2 * f32(math.PI) / 72
		a1 := f32(segment + 1) * 2 * f32(math.PI) / 72
		p0 := V(center.x + math.cos(a0) * photon_radius, center.y + math.sin(a0) * photon_radius)
		p1 := V(center.x + math.cos(a1) * photon_radius, center.y + math.sin(a1) * photon_radius)
		if active do black_hole_draw_emission_glow(p0, p1, emission_strength * .82)
		rl.DrawLineEx(p0, p1, 1.05, bone)
	}

	horizon_radius := plate_radius * .135
	for segment in 0 ..< 64 {
		if (segment + int(seed % 7)) % 8 < 4 do continue
		a0 := f32(segment) * 2 * f32(math.PI) / 64
		a1 := f32(segment + 1) * 2 * f32(math.PI) / 64
		p0 := V(center.x + math.cos(a0) * horizon_radius, center.y + math.sin(a0) * horizon_radius)
		p1 := V(center.x + math.cos(a1) * horizon_radius, center.y + math.sin(a1) * horizon_radius)
		rl.DrawLineEx(p0, p1, .55, {143, 148, 143, 68})
	}

	if active {
		// Depth-composite the near half after the shadow and critical curve. Material
		// between the observer and the hole must occlude both; drawing the whole disk
		// before the shadow incorrectly erased this foreground branch.
		view_cosine := accretion.view_cosine > 0 ? f32(accretion.view_cosine) : f32(.32)
		position_angle := f32(accretion.view_position_angle_radians)
		beaming_strength := math.sqrt(max(0, 1 - view_cosine * view_cosine))
		intrinsic_thickness :=
			accretion.kind == .Thick_Flow ? f32(.32) : accretion.kind == .Wind_Fed ? f32(.20) : f32(.08)
		vertical_scale := clamp(
			math.sqrt(view_cosine * view_cosine + intrinsic_thickness * intrinsic_thickness),
			.18,
			.96,
		)
		outer_radius := accretion.kind == .Wind_Fed ? plate_radius * .55 : plate_radius * .76
		inner_radius := accretion.kind == .Wind_Fed ? plate_radius * .25 : plate_radius * .34
		for spoke in 3 ..< 45 {
			if (spoke * 7 + int(seed % 23)) % 13 < 4 do continue
			a := f32(spoke) * f32(math.PI) / 48
			p0 := black_hole_project_point(
				center,
				math.cos(a) * inner_radius,
				math.sin(a) * inner_radius * vertical_scale,
				position_angle,
			)
			p1 := black_hole_project_point(
				center,
				math.cos(a) * outer_radius,
				math.sin(a) * outer_radius * vertical_scale,
				position_angle,
			)
			rl.DrawLineEx(p0, p1, .48, {153, 158, 151, u8(38)})
		}
		groove_count := accretion.kind == .Wind_Fed ? 8 : accretion.kind == .Thick_Flow ? 13 : 16
		for groove in 0 ..< groove_count {
			u := f32(groove) / f32(max(groove_count - 1, 1))
			radius := outer_radius * (1 - u) + inner_radius * u
			for segment in 3 ..< 45 {
				gap := (segment + groove * 11 + int(seed % 17)) % 19
				if gap < (accretion.kind == .Thick_Flow ? 8 : 3) do continue
				a0 := f32(segment) * f32(math.PI) / 48
				a1 := f32(segment + 1) * f32(math.PI) / 48
				p0, _, _ := black_hole_lensed_disk_point(
					center,
					math.cos(a0) * radius,
					math.sin(a0) * radius * vertical_scale,
					position_angle,
					critical_radius,
					0,
				)
				p1, _, _ := black_hole_lensed_disk_point(
					center,
					math.cos(a1) * radius,
					math.sin(a1) * radius * vertical_scale,
					position_angle,
					critical_radius,
					0,
				)
				alpha := u8(42 + f32(groove) / f32(max(groove_count - 1, 1)) * 72)
				if groove % 2 == 0 do black_hole_draw_emission_glow(p0, p1, emission_strength * .8)
				rl.DrawLineEx(p0, p1, .46, {230, 227, 210, alpha})
			}
		}
		// The near rim receives the sharpest cut. Unequal brightness across the major
		// axis records relativistic beaming while remaining wholly monochrome.
		for segment in 4 ..< 44 {
			if accretion.kind == .Thick_Flow && (segment * 5 + int(seed % 19)) % 13 < 4 do continue
			a0 := f32(segment) * f32(math.PI) / 48
			a1 := f32(segment + 1) * f32(math.PI) / 48
			p0, _, _ := black_hole_lensed_disk_point(
				center,
				math.cos(a0) * outer_radius,
				math.sin(a0) * outer_radius * vertical_scale,
				position_angle,
				critical_radius,
				0,
			)
			p1, _, _ := black_hole_lensed_disk_point(
				center,
				math.cos(a1) * outer_radius,
				math.sin(a1) * outer_radius * vertical_scale,
				position_angle,
				critical_radius,
				0,
			)
			approaching := math.cos(a0) < 0
			alpha :=
				approaching ? u8(132 + beaming_strength * 88) : u8(132 - beaming_strength * 27)
			line_width := approaching ? .9 + beaming_strength * .55 : .9 - beaming_strength * .15
			beam_glow := approaching ? 1 + beaming_strength * .3 : 1 - beaming_strength * .15
			black_hole_draw_emission_glow(p0, p1, emission_strength * beam_glow)
			rl.DrawLineEx(p0, p1, line_width, {224, 222, 207, alpha})
		}
	}

	// A compact radial scale distinguishes three otherwise easy-to-conflate facts:
	// modeled horizon, apparent shadow, and photon critical curve. Unequal tick
	// heights encode the hierarchy without adding text over the illustration.
	leader_y := center.y + photon_radius + plate_radius * .075
	rl.DrawLineEx(
		V(center.x, leader_y),
		V(center.x + photon_radius, leader_y),
		.55,
		{143, 148, 143, 76},
	)
	radii := [?]f32{horizon_radius, shadow_radius, photon_radius}
	tick_heights := [?]f32{3, 5, 8}
	for radius, index in radii {
		tick_height := tick_heights[index]
		x := center.x + radius
		rl.DrawLineEx(
			V(x, leader_y - tick_height),
			V(x, leader_y + tick_height),
			radius == photon_radius ? f32(1) : f32(.6),
			radius == photon_radius ? bone : rl.Color{143, 148, 143, 82},
		)
	}
}

draw_galactic_black_hole_modal_content :: proc(s: ^Ux_State) {
	g := &s.galaxy
	mass := g.central_black_hole_mass_solar
	draw_text("BH", 224, 168, TYPE_HERO_MAX, UX.text)
	draw_text("CENTRAL MASSIVE BLACK HOLE", 296, 190, TYPE_SUBHEADING_COMPACT, UX.text)
	draw_black_hole_detail({}, g.seed ~ 0x6e75636c657573, R(286, 186, 400, 400), s.reduced_motion)
	rl.DrawRectangleRec(R(216, 528, 500, 49), {7, 8, 7, 238})
	rl.DrawLineEx(V(224, 528), V(706, 528), .7, UX.line)
	draw_text("GALACTIC NUCLEUS · DYNAMICAL MASS RECONSTRUCTION", 224, 538, TYPE_CAPTION, UX.dim)
	draw_text("NO PRESENT ACCRETION STATE INFERRED", 224, 558, TYPE_CAPTION, UX.text)

	rl.DrawLineEx(V(748, 170), V(748, 568), 1, UX.line)
	draw_celestial_stat(780, 180, "MEASURED MASS", fmt.tprintf("%.3e SOL", mass), UX.text)
	draw_celestial_stat(
		924,
		180,
		"EVENT HORIZON",
		fmt.tprintf("%.3e KM", game.black_hole_schwarzschild_radius_km(mass)),
		UX.text,
	)
	draw_celestial_stat(
		780,
		252,
		"PHOTON SPHERE",
		fmt.tprintf("%.3e KM", game.black_hole_photon_sphere_radius_km(mass)),
		UX.text,
	)
	draw_celestial_stat(
		924,
		252,
		"ISCO / ZERO SPIN",
		fmt.tprintf("%.3e KM", game.black_hole_isco_radius_km(mass)),
		UX.text,
	)
	draw_celestial_stat(780, 324, "HOST MORPHOLOGY", fmt.tprintf("%v", g.morphology), UX.text)
	draw_celestial_stat(
		924,
		324,
		"HOST STELLAR MASS",
		fmt.tprintf("%.2e SOL", g.stellar_mass_solar),
		UX.text,
	)
	draw_celestial_stat(
		780,
		396,
		"OCCUPATION PRIOR",
		fmt.tprintf("%.1f%%", g.central_black_hole_occupation_chance * 100),
		UX.text,
	)
	draw_celestial_stat(924, 396, "NUCLEAR ACTIVITY", "NOT CONSTRAINED", UX.dim)
	draw_celestial_stat(780, 468, "SURVEY BASIS", "STELLAR DYNAMICS", UX.text)
	draw_celestial_stat(924, 468, "SPIN", "NOT CONSTRAINED", UX.dim)
}
