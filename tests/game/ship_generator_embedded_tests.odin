package game_tests

import "core:testing"
import "core:strings"

@(test)
ship_generator_name_pool_is_unique_bounded_and_roster_aligned :: proc(t: ^testing.T) {
	names := SHIP_GENERATOR_NAMES
	testing.expect_value(t, len(names) % MAX_SHIPS, 0)
	for name, i in names {
		testing.expect(t, name != "" && len(name) <= 20)
		role_labels := [8]string {
			"Habitat",
			"Agriculture",
			"Foundry",
			"Archive",
			"Hospital",
			"Survey",
			"Escort",
			"Colony",
		}
		for label in role_labels do testing.expect(t, !strings.contains(name, label))
		for prior in names[:i] do testing.expect(t, name != prior)
	}
}
