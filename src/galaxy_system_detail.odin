package main

import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:testing"
import "core:time"
import rl "zelda_engine:canvas2d"

system_event_label :: proc(kind: game.System_Event_Kind) -> string {
	switch kind {case .Stellar_Phase_Changed:
		return "Stellar phase changed."; case .Wind_Mass_Loss:
		return "The system lost stellar mass."; case .Tidal_Circularization:
		return "The stellar orbit circularized."; case .Mass_Transfer:
		return "Mass crossed between the stellar components."; case .Common_Envelope:
		return "Both components entered a shared envelope."; case .Supernova:
		return "A stellar component underwent core collapse."; case .Binary_Disrupted:
		return "The stellar pair became unbound."; case .Stellar_Merger:
		return "The stellar components merged."; case .Planet_Orbit_Changed:
		return "A planetary orbit changed after stellar evolution."; case .Planet_Engulfed:
		return "A planet entered an expanded stellar envelope."; case .Planet_Ejected:
		return "A planet became unbound."; case .Climate_Changed:
		return "A planet crossed a modeled climate boundary."}
	return "The system record changed."
}

draw_celestial_body_modal :: proc(s: ^Ux_State) {
	central_black_hole := s.selected_body.kind == .Central_Black_Hole
	detail :=
		central_black_hole ? 0 : clamp(s.selected_system_detail, 0, s.galaxy.detailed_system_count - 1)
	system: ^game.Solar_System
	if !central_black_hole {
		system = &s.galaxy.detailed_systems[detail].system
		if planet_detail_benchmark_time >= 0 && planet_detail_benchmark_system.planet_count > 0 do system = &planet_detail_benchmark_system
	}
	rect := R(184, 88, 912, 548)
	panel(rect, true)

	// The dossier is typeset as a survey plate: oversized identity at left,
	// compact measured facts at right, and orbital rules crossing the gutter.
	draw_text("CELESTIAL SURVEY / VERIFIED EPHEMERIS", 224, 120, TYPE_CAPTION, UX.info)
	record_label :=
		central_black_hole ? "GALACTIC NUCLEUS" : fmt.tprintf("SYSTEM %02d", detail + 1)
	record_width := measure_text(record_label, TYPE_FINE).x
	draw_text(record_label, 1056 - record_width, 120, TYPE_FINE, UX.dim)
	rl.DrawLineEx(V(224, 145), V(1056, 145), 1, UX.line)
	rl.DrawLineEx(V(224, 149), V(548, 149), .5, UX.dim)
	if central_black_hole {
		draw_galactic_black_hole_modal_content(s)
		draw_text("ARCHIVE PLATE  /  VALUES ARE MODEL ESTIMATES", 224, 594, TYPE_FINE, UX.dim)
		if back_button(R(930, 578, 126, 32), "CLOSE") do s.modal = .None
		return
	}
	if s.selected_body.kind == .Barycenter {
		draw_text("SYSTEM EVOLUTION", 224, 174, TYPE_HERO_MAX, UX.text)
		draw_fmt(
			224,
			220,
			TYPE_SUBHEADING_COMPACT,
			UX.info,
			"%d STELLAR COMPONENTS · %.2f GYR · METALLICITY %+.2f DEX",
			system.star_count,
			system.present_age_billion_years,
			system.metallicity_dex,
		)
		limits := game.system_stability_limits(system)
		if system.star_count == 2 &&
		   system.binary_bound {draw_fmt(224, 258, TYPE_BODY, UX.text, "BINARY ORBIT %.3f AU · ECCENTRICITY %.3f", system.binary_orbit.semi_major_axis_au, system.binary_orbit.eccentricity); draw_fmt(224, 284, TYPE_SMALL, UX.dim, "S-A %.2f AU · S-B %.2f AU · P-TYPE BEYOND %.2f AU", limits.circumprimary_outer_au, limits.circumsecondary_outer_au, limits.circumbinary_inner_au)}
		draw_text("SURVEY TIMELINE", 224, 326, TYPE_SUBHEADING_COMPACT, UX.info)
		line := 0; start := max(0, system.event_count - 7); for event in system.events[start:system.event_count] {draw_fmt(224, 358 + f32(line * 28), TYPE_SMALL, UX.text, "%.3f GYR  %s", event.age_billion_years, system_event_label(event.kind)); line += 1}
		if system.event_count == 0 do draw_text("No architecture-changing event is recorded.", 224, 358, TYPE_SMALL, UX.dim)
		draw_fmt(
			780,
			190,
			TYPE_SMALL_EMPHASIS,
			UX.info,
			"%02d PLANETS",
			system.planet_count,
		); draw_fmt(780, 222, TYPE_SMALL, UX.dim, "%02d MOONS · %02d BELTS", system.moon_count, system.belt_count)
		draw_text("ARCHIVE PLATE  /  RAPID EVOLUTION MODEL", 224, 594, TYPE_FINE, UX.dim)
		if back_button(R(930, 578, 126, 32), "CLOSE") do s.modal = .None
		return
	}

	if s.selected_body.kind == .Star {
		star_index := clamp(s.selected_body.index, 0, system.star_count - 1)
		star := system.stars[star_index]
		black_hole := star.phase == .Black_Hole
		accretion := game.black_hole_accretion_state(system, star_index)
		// Stars and planets share one inspection plate. Identity stays above the
		// image while the right column changes to measurements for the body type.
		if black_hole {
			draw_text("BH", 224, 168, TYPE_HERO_MAX, UX.text)
			draw_text("STELLAR-MASS BLACK HOLE", 296, 190, TYPE_SUBHEADING_COMPACT, UX.text)
			draw_black_hole_detail(
				accretion,
				system.seed ~ u64(star_index + 1),
				R(286, 186, 400, 400),
				s.reduced_motion,
			)
		} else {
			draw_fmt(224, 168, TYPE_HERO_MAX, UX.text, "%v", star.class)
			draw_fmt(296, 190, TYPE_SUBHEADING_COMPACT, UX.info, "%v", star.phase)
			draw_system_star_detail(&star, system.seed, R(286, 186, 400, 400), s.reduced_motion)
		}
		rl.DrawRectangleRec(R(216, 528, 500, 49), {7, 8, 7, 238})
		rl.DrawLineEx(V(224, 528), V(706, 528), .7, UX.line)
		if black_hole {
			draw_fmt(
				224,
				538,
				TYPE_CAPTION,
				UX.dim,
				"SYSTEM COMPONENT %c · COMPACT REMNANT",
				u8('A' + star_index),
			)
			if accretion.kind == .Dormant {
				draw_text(
					"LENSING RECONSTRUCTION · NO PRESENT MATTER SUPPLY",
					224,
					558,
					TYPE_CAPTION,
					UX.text,
				)
			} else {
				draw_fmt(
					224,
					558,
					TYPE_CAPTION,
					UX.text,
					"%s · DONOR COMPONENT %c",
					black_hole_accretion_label(accretion.kind),
					u8('A' + accretion.donor_index),
				)
			}
		} else {
			draw_fmt(
				224,
				538,
				TYPE_CAPTION,
				UX.dim,
				"SYSTEM COMPONENT %c · %v",
				u8('A' + star_index),
				star.phase,
			)
			draw_fmt(
				224,
				558,
				TYPE_CAPTION,
				UX.info,
				"%02d CONFIRMED ORBITS · FROST LINE %.2f AU",
				system.planet_count,
				system.frost_line_au,
			)
		}

		rl.DrawLineEx(V(748, 170), V(748, 568), 1, UX.line)
		if black_hole {
			mass := star.profile.mass_solar
			draw_celestial_stat(
				780,
				180,
				"REMNANT MASS",
				fmt.tprintf("%.3f M-SOLAR", mass),
				UX.text,
				"Mass of the black-hole remnant, compared with the Sun.",
			)
			draw_celestial_stat(
				924,
				180,
				"EVENT HORIZON",
				fmt.tprintf("%.2f KM", game.black_hole_schwarzschild_radius_km(mass)),
				UX.text,
				"Radius beyond which light cannot escape, calculated for a non-spinning black hole.",
			)
			draw_celestial_stat(
				780,
				252,
				"PHOTON SPHERE",
				fmt.tprintf("%.2f KM", game.black_hole_photon_sphere_radius_km(mass)),
				UX.text,
				"Radius of unstable circular paths for light around the remnant.",
			)
			draw_celestial_stat(
				924,
				252,
				"ISCO / ZERO SPIN",
				fmt.tprintf("%.2f KM", game.black_hole_isco_radius_km(mass)),
				UX.text,
				"Innermost stable circular orbit, assuming the black hole has no spin.",
			)
			draw_celestial_stat(
				780,
				324,
				"SYSTEM AGE",
				fmt.tprintf("%.2f GYR", star.profile.age_billion_years),
				UX.text,
				"Time since the system formed. GYR means billion years.",
			)
			draw_celestial_stat(
				924,
				324,
				"PROGENITOR MASS",
				fmt.tprintf("%.2f M-SOLAR", star.initial_mass_solar),
				UX.text,
				"Mass of the star that collapsed to form this remnant, compared with the Sun.",
			)
			draw_celestial_stat(780, 396, "BOUND STATE", star.bound ? "BOUND" : "UNBOUND", UX.text, "Whether this remnant remains gravitationally bound to the system.")
			draw_celestial_stat(
				924,
				396,
				"ACCRETION STATE",
				black_hole_accretion_label(accretion.kind),
				UX.text,
				"Whether the remnant is presently receiving matter from a companion or surrounding material.",
			)
			draw_celestial_stat(
				780,
				468,
				"EDDINGTON FRACTION",
				accretion.kind == .Dormant ? "< 1e-7" : fmt.tprintf("%.2e", accretion.eddington_fraction),
				UX.text,
				"Brightness from infalling matter as a share of the theoretical radiation-pressure limit.",
			)
			draw_celestial_stat(
				924,
				468,
				"VIEW / POSITION ANGLE",
				fmt.tprintf(
					"%.0f / %+.0f DEG",
					black_hole_view_angle_degrees(accretion),
					black_hole_position_angle_degrees(accretion),
				),
				UX.text,
				"Viewing tilt and sky orientation used for this reconstruction, in degrees.",
			)
		} else {
			draw_celestial_stat(
				780,
				180,
				"EFFECTIVE TEMPERATURE",
				fmt.tprintf("%.0f K", star.effective_temperature_k),
				UX.warn,
				"The temperature of a blackbody that would emit the same total light. K means kelvin.",
			)
			draw_celestial_stat(
				924,
				180,
				"STELLAR MASS",
				fmt.tprintf("%.3f M-SOLAR", star.profile.mass_solar),
				UX.text,
				"Mass compared with the Sun. It governs the star's gravity and evolution.",
			)
			draw_celestial_stat(
				780,
				252,
				"STELLAR RADIUS",
				fmt.tprintf("%.3f R-SUN", star.profile.radius_solar),
				UX.text,
				"Radius compared with the Sun's radius.",
			)
			draw_celestial_stat(
				924,
				252,
				"LUMINOSITY",
				fmt.tprintf("%.3f L-SUN", star.profile.luminosity_solar),
				UX.text,
				"Total energy emitted compared with the Sun. It sets the light and heat reaching each orbit.",
			)
			draw_celestial_stat(
				780,
				324,
				"CURRENT AGE",
				fmt.tprintf("%.2f GYR", star.profile.age_billion_years),
				UX.text,
				"Time since the star formed. GYR means billion years.",
			)
			draw_celestial_stat(
				924,
				324,
				"MAIN-SEQUENCE LIFE",
				fmt.tprintf("%.2f GYR", star.main_sequence_lifetime_billion_years),
				UX.text,
				"Expected duration of the star's stable hydrogen-burning phase.",
			)
			draw_celestial_stat(
				780,
				396,
				"ORBITING PLANETS",
				fmt.tprintf("%02d", system.planet_count),
				UX.info,
			)
			draw_celestial_stat(
				924,
				396,
				"FROST LINE",
				fmt.tprintf("%.2f AU", system.frost_line_au),
				UX.text,
				"Distance where water and other volatiles can freeze into ice. One AU is the Earth–Sun distance.",
			)
			draw_celestial_stat(
				780,
				468,
				"EVOLUTIONARY PHASE",
				fmt.tprintf("%v", star.phase),
				UX.info,
				"The current stage of the star's life cycle.",
			)
			draw_celestial_stat(
				924,
				468,
				"INITIAL MASS",
				fmt.tprintf("%.3f M-SOLAR", star.initial_mass_solar),
				UX.text,
				"Mass when the star formed, before stellar winds or interactions changed it.",
			)
		}
	} else {
		index := clamp(s.selected_body.index, 0, system.planet_count - 1)
		planet := system.planets[index]
		body := planet.body
		// Identity is the only type allowed to challenge the image: rank first,
		// classification second, with the instrument readout deliberately quiet.
		draw_fmt(224, 168, TYPE_HERO_MAX, UX.text, "%02d", index + 1)
		draw_text(
			system_planet_kind_label(planet.kind),
			296,
			190,
			TYPE_SUBHEADING_COMPACT,
			UX.info,
		)
		// Use the same procedural engraved renderer as the dedicated planet
		// plates. The clicked body is the subject here, not an orbital locator.
		draw_system_planet_detail(&planet, R(286, 186, 400, 400), s.reduced_motion)
		rl.DrawRectangleRec(R(216, 528, 500, 49), {7, 8, 7, 238})
		rl.DrawLineEx(V(224, 528), V(706, 528), .7, UX.line)
		draw_fmt(
			224,
			538,
			TYPE_CAPTION,
			UX.dim,
			"CLIMATE / %v · TIDAL / %v",
			body.climate,
			body.tidal_state,
		)
		draw_fmt(
			224,
			558,
			TYPE_CAPTION,
			body.in_habitable_flux_band ? UX.good : UX.warn,
			"%s · ORBIT %s",
			body.in_habitable_flux_band ? "HABITABLE FLUX BAND" : "OUTSIDE HABITABLE FLUX BAND",
			body.orbit_stable ? "STABLE" : "UNSTABLE",
		)

		rl.DrawLineEx(V(748, 170), V(748, 568), 1, UX.line)
		draw_celestial_stat(
			780,
			180,
			"SEMI-MAJOR AXIS",
			fmt.tprintf("%.3f AU", body.inputs.semi_major_axis_au),
			UX.info,
			"The orbit's average distance from its host. One AU is the Earth–Sun distance.",
		)
		draw_celestial_stat(
			924,
			180,
			"ORBITAL PERIOD",
			fmt.tprintf("%.1f DAYS", body.orbital_period_days),
			UX.text,
			"Time required to complete one orbit around the host.",
		)
		draw_celestial_stat(780, 252, "MASS", fmt.tprintf("%.3f EARTH", body.inputs.mass_earth), UX.text, "Mass compared with Earth.")
		draw_celestial_stat(
			924,
			252,
			"MEAN RADIUS",
			fmt.tprintf("%.3f EARTH", body.inputs.radius_earth),
			UX.text,
			"Average radius compared with Earth's radius.",
		)
		draw_celestial_stat(
			780,
			324,
			"SURFACE GRAVITY",
			fmt.tprintf("%.2f G", body.surface_gravity_earth),
			UX.text,
			"Gravity at the surface, measured in Earth gravities.",
		)
		draw_celestial_stat(
			924,
			324,
			"ESCAPE VELOCITY",
			fmt.tprintf("%.2f KM/S", body.escape_velocity_km_s),
			UX.text,
			"Minimum speed needed to escape the planet's gravity without further thrust.",
		)
		draw_celestial_stat(
			780,
			396,
			"SURFACE TEMP.",
			fmt.tprintf("%.0f K", body.surface_temperature_k),
			body.climate == .Temperate ? UX.good : UX.warn,
			"Modeled average surface temperature. K means kelvin.",
		)
		draw_celestial_stat(
			924,
			396,
			"STELLAR FLUX",
			fmt.tprintf("%.2f EARTH", body.stellar_flux_earth),
			UX.text,
			"Starlight reaching the planet, compared with the sunlight Earth receives.",
		)
		draw_celestial_stat(
			780,
			468,
			"ECCENTRICITY",
			fmt.tprintf("%.3f", body.inputs.eccentricity),
			UX.text,
			"How stretched the orbit is: 0 is circular; larger values vary its distance from the host more.",
		)
		host_label :=
			planet.host.body.kind == .Barycenter ? "BARYCENTER" : fmt.tprintf("STAR %c", u8('A' + planet.host.body.index))
		draw_celestial_stat(
			924,
			468,
			"HOST / FLUX RANGE",
			fmt.tprintf(
				"%s · %.2f–%.2f",
				host_label,
				planet.flux_envelope.minimum_earth,
				planet.flux_envelope.maximum_earth,
			),
			UX.info,
			"The body being orbited and the lowest-to-highest starlight received across this planet's orbit, in Earth units.",
		)
	}

	draw_text("ARCHIVE PLATE  /  VALUES ARE MODEL ESTIMATES", 224, 594, TYPE_FINE, UX.dim)
	if back_button(R(930, 578, 126, 32), "CLOSE") do s.modal = .None
}

draw_galaxy_inspector :: proc(s: ^Ux_State) {
	g := &s.galaxy
	panel(R(928, 104, 328, 536))
	label_caps("GALAXY", 956, 128)
	draw_fmt(956, 154, TYPE_HEADING_COMPACT, UX.text, "%v", g.morphology)
	draw_fmt(
		956,
		188,
		TYPE_SMALL,
		UX.dim,
		"%.2e STARS · %d REACHABLE",
		f64(g.estimated_star_count),
		g.detailed_system_count,
	)
	draw_fmt(
		956,
		210,
		TYPE_SMALL,
		UX.dim,
		"%.1f KPC RADIUS · %.1f M☉/YR",
		g.disk_radius_kpc,
		g.star_formation_rate_solar_masses_year,
	)
	if g.central_black_hole_occupied {
		draw_fmt(
			956,
			230,
			TYPE_FINE,
			UX.warn,
			"CENTRAL BLACK HOLE · %.2e M-SOLAR",
			g.central_black_hole_mass_solar,
		)
	} else {
		draw_text("NO CENTRAL BLACK HOLE DETECTED", 956, 230, TYPE_FINE, UX.dim)
	}
	divider(956, 240, 270)
	index := clamp(s.selected_neighborhood, 0, g.neighborhood_count - 1)
	n := g.neighborhoods[index]
	label_caps("SELECTED REGION", 956, 260, UX.info)
	draw_fmt(956, 286, TYPE_BODY_EMPHASIS, UX.text, "SYSTEM %02d · %v", index + 1, n.population)
	draw_fmt(
		956,
		316,
		TYPE_SMALL,
		UX.dim,
		"RADIUS %.2f KPC · Z %+.2f KPC",
		n.galactocentric_radius_kpc,
		n.z_kpc,
	)
	draw_fmt(956, 338, TYPE_SMALL, UX.dim, "METALLICITY %+.2f DEX", n.metallicity_dex)
	draw_fmt(956, 360, TYPE_SMALL, UX.dim, "MEAN AGE %.1f GYR", n.mean_age_billion_years)
	draw_fmt(
		956,
		382,
		TYPE_SMALL,
		n.in_galactic_habitable_zone ? UX.good : UX.warn,
		"%s",
		n.in_galactic_habitable_zone ? "WITHIN HABITABLE ANNULUS" : "OUTSIDE HABITABLE ANNULUS",
	)
	correspondence_count := 0
	for door in s.campaign.outer_dark.continuum.doors[:s.campaign.outer_dark.continuum.door_count] do if door.endpoint_known && door.galaxy_neighborhood == index do correspondence_count += 1
	if correspondence_count > 0 do draw_fmt(956, 400, TYPE_LABEL, UX.committed, "DARK CORRESPONDENCE · %d APERTURE", correspondence_count)
	detail := galaxy_detailed_system_index(g, index)
	contact_count := game.habitable_contacts_at_neighborhood(s.campaign, index)
	if contact_count > 0 {
		divider(956, 416, 270)
		draw_fmt(
			956,
			430,
			TYPE_FINE,
			UX.good,
			"30 PC RECONNAISSANCE · %d CANDIDATE%s",
			contact_count,
			contact_count == 1 ? "" : "S",
		)
		CONTACTS_PER_PAGE :: 4
		page_count := max((contact_count + CONTACTS_PER_PAGE - 1) / CONTACTS_PER_PAGE, 1)
		s.galaxy_contact_page = clamp(s.galaxy_contact_page, 0, page_count - 1)
		row, seen := 0, 0
		for contact in s.campaign.habitable_contacts {
			if contact.neighborhood_index != index do continue
			if seen / CONTACTS_PER_PAGE != s.galaxy_contact_page {seen += 1; continue}
			if row >= CONTACTS_PER_PAGE do break
			label := game.habitable_contact_intel_label(s.campaign, contact)
			selected_goal :=
				s.campaign.long_term_navigation_goal.active &&
				s.campaign.long_term_navigation_goal.contact_id == contact.id
			if button(R(956, 446 + f32(row) * 22, 270, 20), label, true, selected_goal) {
				_, s.status = game.long_term_navigation_goal_set(s.campaign, contact.id)
			}
			row += 1
			seen += 1
		}
		if page_count > 1 {
			if button(R(956, 538, 78, 20), "← CONTACTS", s.galaxy_contact_page > 0) do s.galaxy_contact_page -= 1
			draw_fmt(1042, 542, TYPE_MICRO, UX.dim, "%d/%d", s.galaxy_contact_page + 1, page_count)
			if button(R(1082, 538, 144, 20), "MORE CONTACTS →", s.galaxy_contact_page + 1 < page_count) do s.galaxy_contact_page += 1
		}
		goal := game.long_term_navigation_goal_progress(s.campaign)
		if goal.valid && goal.target_neighborhood == index {
			resolution_km := f64(0)
			for contact in s.campaign.habitable_contacts do if contact.id == s.campaign.long_term_navigation_goal.contact_id {
				resolution_km = game.habitable_contact_sensor_resolution_km(s.campaign, contact, goal)
				break
			}
			goal_y := f32(560)
			draw_text_fitted(
				fmt.tprintf(
					"NAVIGATION GOAL · %s · %.0f KM RESOLUTION",
					game.long_term_navigation_stage_name(goal.stage),
					resolution_km,
				),
				R(956, goal_y, 270, 18),
				TYPE_FINE,
				goal.stage == .Charting ? UX.info : goal.stage == .Reached ? UX.good : UX.committed,
			)
			if button(R(956, 580, 270, 22), "PLOT NEXT GOAL LEG", s.campaign.passage.active) {
				_, s.status = game.follow_fastest_known_route(
					s.campaign,
					&s.campaign.passage,
					goal.target_neighborhood,
				)
			}
		}
		if detail >= 0 do draw_selected_solar_system(s, detail)
	} else if detail >= 0 {
		system := &g.detailed_systems[detail].system
		divider(956, 416, 270)
		draw_fmt(
			956,
			438,
			TYPE_SMALL_EMPHASIS,
			UX.info,
			"%v STAR · %.2f SOLAR MASS",
			system.stars[0].class,
			system.stars[0].profile.mass_solar,
		)
		draw_fmt(
			956,
			460,
			TYPE_SMALL,
			UX.dim,
			"%.2f SOLAR LUMINOSITY",
			system.stars[0].profile.luminosity_solar,
		)
		for survey in s.campaign.world_surveys[:s.campaign.world_survey_count] do if int(survey.system_index) == detail {
			draw_fmt(956, 482, TYPE_FINE, survey.funnel.settlement_capable > 0 ? UX.good : UX.warn, "SURVEY · %v", survey.profile.classification)
			draw_fmt(956, 498, TYPE_FINE, UX.dim, "%d PLANETS · %d ROCKY · %d HZ", survey.funnel.planets, survey.funnel.terrestrial, survey.funnel.conservative_hz)
			draw_text("MEASURED + MODELED INFERENCE", 956, 514, TYPE_FINE, UX.dim)
			break
		}
		draw_selected_solar_system(s, detail)
	} else {
		draw_text("No detailed survey generated.", 956, 444, TYPE_SMALL, UX.dim)
	}
	divider(956, 582, 270)
	draw_fmt(956, 602, TYPE_SMALL, UX.info, "ZOOM %.2f×", s.galaxy_zoom)
	draw_text("WHEEL ZOOMS · DRAG PANS", 956, 622, TYPE_CAPTION, UX.dim)
}

draw_galaxy_map :: proc(s: ^Ux_State) {
	if !s.galaxy_ready {
		s.galaxy = s.campaign.galaxy^
		s.galaxy_ready = true
		s.galaxy_zoom = 1
		s.selected_neighborhood = 0
	}
	update_galaxy_camera(s)
	top_rail(s)
	draw_text("GALACTIC SURVEY", 24, 72, TYPE_TITLE_COMPACT)
	if button(R(250, 68, 110, 30), "RESET VIEW") {
		s.galaxy_zoom = 1
		s.galaxy_pan_x, s.galaxy_pan_y = 0, 0
	}
	panel(GALAXY_VIEW)
	rl.BeginScissorMode(GALAXY_VIEW)
	draw_galaxy_structure(s)
	draw_galaxy_neighborhoods(s)
	rl.EndScissorMode()
	draw_galaxy_inspector(s)
	goal := game.long_term_navigation_goal_progress(s.campaign)
	objective := "SURVEY THE GALACTIC ENVIRONMENT"
	if goal.valid do objective = fmt.tprintf("NAVIGATION TARGET · %.1f KPC REMAINING", goal.remaining_distance_kpc)
	bottom_rail(s, objective)
}
