package main

import game "../packages/game"
import "core:fmt"
import "core:math"
import "core:os"
import filepath "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:time"
import rl "zelda_engine:canvas2d"
import ui "zelda_engine:ui"

main :: proc() {
	if len(os.args) > 1 && os.args[1] == "--dump-ship-contact-recipes" {
		ship_contact_recipe_dump_main()
		return
	}
	if len(os.args) > 1 && os.args[1] == "--dump-ship-contact-faces" {
		ship_contact_face_dump_main()
		return
	}
	if len(os.args) > 1 &&
	   os.args[1] != "--benchmark-galaxy" &&
	   os.args[1] != "--benchmark-ship-gen" &&
	   os.args[1] != "--benchmark-ship-hatching" &&
	   os.args[1] != "--benchmark-planet-detail" &&
	   os.args[1] != "--benchmark-star-detail" &&
	   os.args[1] != "--benchmark-combat-render" &&
	   os.args[1] != "--benchmark-passage-render" &&
	   os.args[1] != "--capture-galaxy" &&
	   os.args[1] != "--capture-body-detail" &&
	   os.args[1] != "--capture-planet" &&
	   os.args[1] != "--planet-preview" &&
	   os.args[1] != "--capture-star" &&
	   os.args[1] != "--capture-ship-contact-sheet" &&
	   os.args[1] != "--star-preview" &&
	   os.args[1] != "--capture-passage" &&
	   os.args[1] != "--capture-passage-stress" &&
	   os.args[1] != "--capture-passage-deep" &&
	   os.args[1] != "--capture-fleet" &&
	   os.args[1] != "--capture-ship-detail" &&
	   os.args[1] != "--capture-generated-fleet" &&
	   os.args[1] != "--capture-ui-knollboard" &&
	   os.args[1] != "--capture-ui-accents-knollboard" &&
	   os.args[1] != "--capture-ship-board" &&
	   os.args[1] != "--capture-ship-effects-board" &&
	   os.args[1] != "--capture-ship-drive-board" &&
	   os.args[1] != "--capture-ship-wing-board" &&
	   os.args[1] != "--capture-ship-hull-board" &&
	   os.args[1] != "--capture-ship-mission-board" &&
	   os.args[1] != "--capture-ship-damage-board" &&
	   os.args[1] != "--capture-ship-service-board" &&
	   os.args[1] != "--capture-ship-lineage-board" &&
	   os.args[1] != "--capture-ship-seed-board" &&
	   os.args[1] != "--capture-ship-hardpoint-board" &&
	   os.args[1] != "--capture-ship-weapon-board" &&
	   os.args[1] != "--capture-ship-direct-fire-board" &&
	   os.args[1] != "--capture-single-hull-weapon-board" &&
	   os.args[1] != "--capture-single-hull-direct-fire-board" &&
	   os.args[1] != "--capture-delta-weapon-board" &&
	   os.args[1] != "--capture-modular-fleet-weapon-board" &&
	   os.args[1] != "--capture-single-hull-strike-weapon-board" &&
	   os.args[1] != "--capture-strike-weapon-lineage-board" &&
	   os.args[1] != "--capture-strike-ordnance-multiview-board" &&
	   os.args[1] != "--capture-interaction" &&
	   os.args[1] != "--capture-combat" &&
	   os.args[1] != "--capture-combat-stress" &&
	   os.args[1] != "--capture-combat-finale" &&
	   os.args[1] != "--capture-combat-late" &&
	   os.args[1] != "--capture-combat-result" &&
	   os.args[1] != "--capture-combat-resize" &&
	   os.args[1] != "--capture-far-engagement" &&
	   os.args[1] != "--combat" &&
	   os.args[1] != "--far-engagement" &&
	   os.args[1] != "--combat-stress" &&
	   os.args[1] != "--combat-finale" {dark_demo_main()} else {run_graphical()}
}
