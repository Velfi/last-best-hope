package game_tests

import "core:testing"

@(test)
combat_autoplay_keeps_the_seedship_objective_when_a_friendly_is_disabled :: proc(t: ^testing.T) {
	m := combat_new_mission(701)
	defer combat_mission_destroy(&m)
	m.seedship_found = true
	m.relays_synchronized = true
	m.units[1].disabled = true
	controller: Combat_Autoplay_Controller

	combat_autoplay_step(&m, &controller)

	recovery := &m.units[m.recovery_unit]
	testing.expect_value(t, recovery.order, Combat_Order.Recover)
	testing.expect_value(t, recovery.target, -1)
	testing.expect_value(t, recovery.destination, m.seedship)
}

@(test)
combat_autoplay_preserves_the_capable_salvage_element_at_assignment :: proc(
	t: ^testing.T,
) {
	setup := skirmish_default_setup()
	setup.mission = .Contested_Salvage
	m := combat_new_skirmish_mission(700, setup)
	defer combat_mission_destroy(&m)
	specialist := m.recovery_unit
	controller: Combat_Autoplay_Controller

	combat_autoplay_step(&m, &controller)

	testing.expect_value(t, m.recovery_unit, specialist)
	testing.expect_value(t, m.units[specialist].order, Combat_Order.Recover)
	testing.expect(t, .Recovery in combat_unit_modules(m.units[specialist]))
}

@(test)
combat_autoplay_refreshes_the_moving_seedship_destination :: proc(t: ^testing.T) {
	m := combat_new_mission(702)
	defer combat_mission_destroy(&m)
	m.seedship_found = true
	m.relays_synchronized = true
	controller: Combat_Autoplay_Controller
	combat_autoplay_step(&m, &controller)
	first := m.units[m.recovery_unit].destination

	m.seedship.x += 12
	m.seedship.y -= 4
	combat_autoplay_step(&m, &controller)

	testing.expect(t, m.units[m.recovery_unit].destination != first)
	testing.expect_value(t, m.units[m.recovery_unit].destination, m.seedship)
}

@(test)
combat_autoplay_assigns_distinct_relay_elements :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Relay_Control
	m := combat_new_skirmish_mission(703, setup)
	defer combat_mission_destroy(&m)
	controller: Combat_Autoplay_Controller

	combat_autoplay_step(&m, &controller)

	testing.expect_value(t, controller.objective_unit_count, 2)
	testing.expect(t, controller.objective_units[0] != controller.objective_units[1])
	testing.expect_value(t, m.units[controller.objective_units[0]].order, Combat_Order.Control)
	testing.expect_value(t, m.units[controller.objective_units[0]].target, 0)
	testing.expect_value(t, m.units[controller.objective_units[1]].order, Combat_Order.Control)
	testing.expect_value(t, m.units[controller.objective_units[1]].target, 1)
}

@(test)
combat_autoplay_extracts_scout_after_scan :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Reconnaissance
	m := combat_new_skirmish_mission(704, setup)
	defer combat_mission_destroy(&m)
	controller: Combat_Autoplay_Controller
	m.anomaly_progress = 100

	combat_autoplay_step(&m, &controller)

	scout := m.objective_unit
	testing.expect_value(t, m.units[scout].order, Combat_Order.Extract)
	testing.expect(t, controller.interaction_complete)
}

@(test)
combat_autoplay_starts_reconnaissance_without_an_arbitrary_delay :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Reconnaissance
	m := combat_new_skirmish_mission(709, setup)
	defer combat_mission_destroy(&m)
	controller: Combat_Autoplay_Controller

	combat_autoplay_step(&m, &controller)

	scout := m.objective_unit
	testing.expect_value(t, m.recon_probe.status, Combat_Recon_Probe_Status.In_Flight)
	testing.expect_value(t, m.recon_probe.launcher, scout)
	testing.expect_value(t, m.units[scout].order, Combat_Order.Hold)
	testing.expect(t, m.units[scout].silent_running)
	testing.expect(t, !m.units[scout].combat_burn)
}

@(test)
combat_autoplay_falls_back_to_a_crewed_scan_when_no_probe_remains :: proc(
	t: ^testing.T,
) {
	setup := skirmish_default_setup()
	setup.mission = .Reconnaissance
	m := combat_new_skirmish_mission(710, setup)
	defer combat_mission_destroy(&m)
	for &unit in m.units[:m.friendly_count] do unit.recon_probes = 0
	controller: Combat_Autoplay_Controller

	combat_autoplay_step(&m, &controller)

	scout := m.objective_unit
	testing.expect_value(t, m.recon_probe.status, Combat_Recon_Probe_Status.Unavailable)
	testing.expect_value(t, m.units[scout].order, Combat_Order.Control)
	testing.expect_value(t, m.units[scout].destination, m.anomaly)
}

@(test)
combat_autoplay_extraction_diagnostic_observes_terminal_state :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Contested_Salvage
	m := combat_new_skirmish_mission(711, setup)
	defer combat_mission_destroy(&m)
	controller: Combat_Autoplay_Controller
	controller.phase = .Extract
	controller.extraction_ordered = true
	controller.objective_unit_count = 1
	controller.objective_units[0] = m.recovery_unit
	m.units[m.recovery_unit].extracted = true

	testing.expect(t, combat_autoplay_extraction_satisfied(&m, &controller))
}

@(test)
combat_autoplay_rescue_order_is_not_replaced_by_casualty_recovery :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Disabled_Ship_Rescue
	m := combat_new_skirmish_mission(705, setup)
	defer combat_mission_destroy(&m)
	controller: Combat_Autoplay_Controller
	extra := m.objective_unit == 1 ? 2 : 1
	m.units[extra].disabled = true

	combat_autoplay_step(&m, &controller)

	recovery := m.recovery_unit
	testing.expect_value(t, m.units[recovery].order, Combat_Order.Recover)
	testing.expect_value(t, m.units[recovery].target, m.objective_unit)
}

@(test)
combat_autoplay_releases_escort_after_convoy_extraction :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Convoy_Escort
	m := combat_new_skirmish_mission(706, setup)
	defer combat_mission_destroy(&m)
	controller: Combat_Autoplay_Controller
	m.units[m.objective_unit].extracted = true

	combat_autoplay_step(&m, &controller)

	for unit in m.units[:m.friendly_count] do if !unit.disabled && !unit.extracted {
		testing.expect_value(t, unit.order, Combat_Order.Extract)
	}
}

@(test)
combat_autoplay_reassigns_disabled_recon_scanner :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Reconnaissance
	m := combat_new_skirmish_mission(707, setup)
	defer combat_mission_destroy(&m)
	controller: Combat_Autoplay_Controller
	combat_autoplay_step(&m, &controller)
	previous := m.objective_unit
	replacement := previous == 0 ? 1 : 0
	m.units[replacement].campaign_modules = {.Sensors}
	m.units[previous].disabled = true

	combat_autoplay_step(&m, &controller)

	testing.expect(t, !controller.aborted)
	testing.expect(t, m.objective_unit != previous)
	testing.expect_value(t, m.objective_unit, replacement)
	testing.expect(t, !m.units[m.objective_unit].disabled)
}

@(test)
combat_autoplay_reassigns_disabled_deployment_team :: proc(t: ^testing.T) {
	setup := skirmish_default_setup()
	setup.mission = .Raid_And_Deploy
	m := combat_new_skirmish_mission(708, setup)
	defer combat_mission_destroy(&m)
	previous := m.objective_unit
	m.units[previous].disabled = true
	controller: Combat_Autoplay_Controller

	combat_autoplay_step(&m, &controller)

	testing.expect(t, !controller.aborted)
	testing.expect(t, m.objective_unit != previous)
	testing.expect_value(t, m.units[m.objective_unit].order, Combat_Order.Control)
}
