package main

import game "../packages/game"
import "core:fmt"

print_habitability_report :: proc(report: ^game.Galaxy_Habitability_Report, csv := false) {
	if csv {
		fmt.println("seed,model_version,scenario,samples,tier,median,low_5,high_95,rate_per_star")
		for interval, tier in report.tiers {
			fmt.printf(
				"%d,%d,%s,%d,%s,%.8e,%.8e,%.8e,%.8f\n",
				report.seed,
				report.model_version,
				game.habitability_scenario_name(report.scenario),
				report.sample_count,
				game.habitability_tier_name(game.Habitability_Tier(tier)),
				interval.median,
				interval.low_5,
				interval.high_95,
				interval.rate_per_star,
			)
		}
		return
	}
	fmt.println("GALACTIC HABITABILITY ESTIMATE")
	fmt.printf(
		"Seed: %d · model v%d · %s scenario\n",
		report.seed,
		report.model_version,
		game.habitability_scenario_name(report.scenario),
	)
	fmt.printf(
		"Stars represented: %.3e · Monte Carlo samples: %d\n\n",
		f64(report.star_count),
		report.sample_count,
	)
	for interval, tier in report.tiers {
		fmt.printf(
			"%s\n  median %.3e · 5th–95th %.3e – %.3e · %.6f per star\n",
			game.habitability_tier_name(game.Habitability_Tier(tier)),
			interval.median,
			interval.low_5,
			interval.high_95,
			interval.rate_per_star,
		)
	}
	fmt.println("\nRocky and temperate occurrence is observation-calibrated at model level.")
	fmt.println(
		"Atmosphere, long-term climate, abiogenesis, and complex life are named scenario assumptions.",
	)
}

run_habitability_cli :: proc(
	samples: int,
	scenario: game.Habitability_Scenario,
	seed: u64,
	csv: bool,
) {
	galaxy := game.generate_galaxy(seed)
	defer game.galaxy_destroy(&galaxy)
	report := game.estimate_galaxy_habitability(&galaxy, scenario, samples)
	print_habitability_report(&report, csv)
}
