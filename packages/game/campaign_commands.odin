package game

import "core:fmt"

campaign_process_reporting_period :: proc(c: ^Campaign) {
	if c.ending != .In_Progress do return
	if resolve_fleet_dissolution(c) do return
	if precedent_review_due(c) do return
	if c.material_economy.food_shortage_response_pending do return
	if c.ending_prompt_pending || c.economy_loss_decision_pending do return
	if c.stranded_outcome_notice_pending do return
	if c.expedition.active do resolve_expedition(c)
	neglect_open_needs(c)
	release_situation_capacity(c)
	refresh_capacity_state(c)
	advance_historical_figures(c)
	advance_fleet_transformations(c)
	advance_stranded_passage_groups(c)
	population := total_population(c)
	advance_material_economy(c)
	// Foundries maintain productive capacity. Food production and reserve
	// coverage are accounted by the material economy rather than receiving an
	// unrelated per-foundry scalar grant.
	if operational_role_available(c, .Foundry) && c.capacities.raw_materials.damaged > 0 do c.capacities.raw_materials.damaged -= 1
	apply_seasonal_hazard(c)
	advance_persistent_hazard_pressure(c)
	advance_settlement_economies(c)
	advance_settlements(c)
	for i in 0 ..< c.promise_count {
		p := &c.promises[i]
		if p.status == .Active &&
		   c.season >
			   p.deadline {p.status = .Broken; c.strategic.cohesion = max(c.strategic.cohesion - 10, 0); record_event(c, .Promise_Changed, fmt.tprintf("Promise broken: %s", p.detail), value = i32(Promise_Status.Broken))}
	}
	_ = review_contested_account(c)
	if fleet_supply(c) == 0 {c.strategic.cohesion = max(c.strategic.cohesion - 8, 0)}
	pressure := strategic_pressure(c)
	if c.emergency_recovery_active {
		if pressure.recovery_met {c.emergency_stable_seasons += 1} else {c.emergency_stable_seasons = 0}
		if c.emergency_stable_seasons >=
		   2 {c.emergency_recovery_active = false; c.emergency_stable_seasons = 0; record_event(c, .Emergency_Response, "Strategic reserve, capacity, and Cohesion margins remained recovered for two consecutive seasons.", value = c.emergency_recovery_target)}
	}
	if pressure.warning &&
	   c.emergency_preparedness <= 16 &&
	   !c.emergency_structural_response_pending {c.emergency_structural_response_pending = true; record_event(c, .Need_Surfaced, "Strategic margin entered the pre-emergency warning band. Structural preparation can prevent constitutional emergency.", value = i32(pressure.cause))}
	effective_floor :=
		c.emergency_preparedness > 0 ? max(EMERGENCY_FLOOR - c.emergency_preparedness, 0) : EMERGENCY_FLOOR + 1
	below_emergency :=
		pressure.reserve_coverage < 0 ||
		pressure.capacity_margin < 0 ||
		pressure.cohesion < effective_floor
	if !below_emergency &&
	   c.emergency_preparedness > 0 &&
	   pressure.emergency {record_event(c, .Emergency_Response, "Prepared institutions absorbed pressure that would otherwise have opened a constitutional emergency.", value = c.emergency_preparedness); c.emergency_preparedness = max(c.emergency_preparedness - 4, 0)}
	if below_emergency {
		cause := pressure.cause
		if cause == .None do cause = .Cohesion
		cause_index := int(cause)
		if c.season < c.emergency_refractory_until_by_cause[cause_index] do cause = .None
		if cause != .None {
			c.constitutional_emergency = true; c.emergency_count += 1
			if c.first_emergency_season < 0 do c.first_emergency_season = c.season
			c.last_emergency_cause = cause
			c.last_emergency_season =
				c.season; c.emergency_recurrence_by_cause[int(cause)] += 1; c.emergency_refractory_until_by_cause[int(cause)] = c.season + emergency_refractory_seasons(c)
			c.emergency_recovery_active =
				true; c.emergency_recovery_target = EMERGENCY_FLOOR + 18; c.emergency_stable_seasons = 0
			if c.emergency_recurrence_by_cause[int(cause)] >=
			   2 {c.emergency_structural_response_pending = true; c.emergency_structural_response_required = true}
			detail := fmt.tprintf(
				"%v pressure exceeded its operating margin; the fleet continues under contested authority.",
				cause,
			)
			detail = fmt.tprintf(
				"%s Recovery target: %d; recurrence for this cause: %d.",
				detail,
				c.emergency_recovery_target,
				c.emergency_recurrence_by_cause[int(cause)],
			)
			record_event(c, .Constitutional_Emergency, detail, value = i32(cause))
			if c.emergency_structural_response_pending do record_event(c, .Need_Surfaced, "Recurring emergency pressure requires institutional recovery, protected development, or contracted obligations.", value = i32(cause), cause_sequence = c.event_sequence)
		}
	}
	record_event(c, .Season_Advanced, "Three years of ordinary history pass.", value = population)
	surface_needs(c)
	compact_advance_reporting_boundary(c)
	advance_obligations(c)
	advance_public_politics(c)
	_ = run_narrative_director(c)
	_ = resolve_open_public_question_autonomously(c)
	refresh_semantic_tags(c)
	if c.ending_finale.active &&
	   c.season >=
		   c.ending_finale.ends_season {c.ending_prompt_pending = true; record_event(c, .Need_Surfaced, "The three-season finale is complete; record the condition of the ending.")
	} else if c.max_seasons > 0 &&
	   c.season >=
		   c.max_seasons {c.ending_prompt_pending = true; record_event(c, .Need_Surfaced, "The chosen chronicle horizon has arrived; begin the finale or continue as an Endless chronicle.")}
}

fleet_is_dissolved :: proc(c: ^Campaign) -> bool {
	return active_ship_count(c) == 0 && !stranded_passage_active(c) || total_population(c) == 0
}

conclude_chronicle :: proc(c: ^Campaign) -> bool {
	if c.ending != .In_Progress ||
	   c.passage.active ||
	   c.current_situation.phase != .None && c.current_situation.phase != .Resolved ||
	   c.length != .Open && !c.ending_prompt_pending {
		return false
	}
	if !c.ending_finale.active {
		c.ending_finale = {
			active         = true,
			ending         = ending_identity(c),
			started_season = c.season,
			ends_season    = c.season + 3,
		}
		c.ending_prompt_pending = false
		if c.max_seasons > 0 do c.max_seasons = c.ending_finale.ends_season
		record_event(
			c,
			.Chronicle_Started,
			fmt.tprintf(
				"The fleet entered a three-season finale toward %s.",
				ending_name(c.ending_finale.ending),
			),
			value = i32(c.ending_finale.ending),
		)
		return true
	}
	if c.season < c.ending_finale.ends_season do return false
	_ = evaluate_ending(c)
	c.ending_prompt_pending = false
	return true
}

convert_chronicle_to_endless :: proc(c: ^Campaign) -> bool {
	if c.ending != .In_Progress || c.length == .Open || !c.ending_prompt_pending || c.ending_finale.active do return false
	c.length = .Open; c.max_seasons = 0; c.ending_prompt_pending = false
	record_event(
		c,
		.Chronicle_Started,
		"The people chose to continue beyond the chronicle's planned horizon.",
	)
	return true
}

resolve_fleet_dissolution :: proc(c: ^Campaign) -> bool {
	if c.ending != .In_Progress || !fleet_is_dissolved(c) do return false
	c.ending = .Fragmented_Survival
	assemble_ending_evidence(c)
	record_event(
		c,
		.Chronicle_Ended,
		"No active ships or population remained in the traveling fleet.",
		value = i32(c.ending),
	)
	return true
}

add_promise :: proc(
	c: ^Campaign,
	beneficiary: Community_ID,
	deadline: i32,
	detail: string,
) -> bool {
	if community_index(c, beneficiary) < 0 || deadline <= c.season do return false
	index := c.promise_count
	if index >=
	   MAX_PROMISES {index = -1; for promise, i in c.promises[:c.promise_count] do if promise.status != .Active {index = i; break}; if index < 0 do return false} else {c.promise_count += 1}
	if c.owns_strings do destroy_owned_string(c.promises[index].detail)
	c.promises[index] = {
		beneficiary   = beneficiary,
		deadline      = deadline,
		status        = .Active,
		detail        = detail,
		semantic_tags = make_semantic_tags(.Promise, .Community),
	}
	return true
}

has_precedent :: proc(c: ^Campaign, kind: Precedent_Kind) -> bool {
	return active_precedent_id(c, kind) != 0
}

precedent_need_cost_modifier :: proc(c: ^Campaign, kind: Need_Kind) -> i32 {
	modifier: i32
	if kind == .Representation && has_precedent(c, .Shared_Authority) do modifier -= 2
	if kind == .Archive_Staffing && has_precedent(c, .Open_Archives) do modifier -= 3
	if kind == .Settlement_Defense && has_precedent(c, .No_One_Left_Behind) do modifier -= 1
	if kind == .Settlement_Charter && has_precedent(c, .Shared_Authority) do modifier -= 2
	if kind == .Settlement_Charter && has_precedent(c, .Ship_Sovereignty) do modifier -= 2
	if kind == .Settlement_Charter && has_precedent(c, .Open_Archives) do modifier -= 1
	return modifier
}

honor_promise :: proc(c: ^Campaign, index: int) -> bool {
	if index < 0 || index >= c.promise_count || c.promises[index].status != .Active do return false
	c.promises[index].status = .Honored
	c.strategic.cohesion = min(c.strategic.cohesion + 5, 100)
	record_event(
		c,
		.Promise_Changed,
		fmt.tprintf("Promise upheld: %s", c.promises[index].detail),
		value = i32(Promise_Status.Honored),
	)
	return true
}

add_ending_evidence :: proc(c: ^Campaign, detail: string) {
	if detail == "" || c.ending_evidence_count >= MAX_ENDING_EVIDENCE do return
	c.ending_evidence[c.ending_evidence_count] = detail
	c.ending_evidence_count += 1
}

assemble_ending_evidence :: proc(c: ^Campaign) {
	c.ending_evidence_count = 0
	for i := c.history_hook_count - 1; i >= 0; i -= 1 {
		hook := &c.history_hooks[i]
		if hook.kind != .Broken_Procession do continue
		si := ship_index(c, hook.ship); if si < 0 do continue
		add_ending_evidence(
			c,
			fmt.tprintf(
				"%s carried %d people of the Broken Procession into the fleet.",
				c.ships[si].name,
				hook.population,
			),
		)
		if hook.stage == .Consequence do add_ending_evidence(c, hook.detail)
		break
	}
	if c.ending_evidence_count < MAX_ENDING_EVIDENCE {
		for figure in c.historical_figures[:c.historical_figure_count] do if figure.active {add_ending_evidence(c, fmt.tprintf("%s served as %s.", figure.name, figure.role)); break}
	}
	for settlement in c.settlements[:c.settlement_count] {
		if c.ending_evidence_count >= MAX_ENDING_EVIDENCE do break
		add_ending_evidence(
			c,
			fmt.tprintf(
				"%s remained active with %d residents.",
				settlement.name,
				settlement.population,
			),
		)
	}
	if c.ending_evidence_count < MAX_ENDING_EVIDENCE {
		for ship in c.ships {
			if ship.history_record_count == 0 do continue
			add_ending_evidence(
				c,
				fmt.tprintf(
					"%s: %s",
					ship.name,
					ship.history_records[ship.history_record_count - 1],
				),
			)
			break
		}
	}
}

evaluate_ending :: proc(c: ^Campaign) -> Ending {
	if c.ending != .In_Progress do return c.ending
	c.ending = c.ending_finale.active ? c.ending_finale.ending : ending_identity(c)
	c.ending_quality = ending_quality(c, c.ending)
	c.ending_finale.active = false
	assemble_ending_evidence(c)
	record_event(
		c,
		.Chronicle_Ended,
		fmt.tprintf("%s · %s", ending_name(c.ending), ending_quality_name(c.ending_quality)),
		value = i32(c.ending),
	)
	return c.ending
}

campaign_snapshot :: proc(c: ^Campaign) -> ^Campaign {
	snapshot := new(Campaign)
	snapshot^ = c^
	allocator := campaign_storage_allocator()
	snapshot.settlement_economies.economies = make(
		[dynamic]Settlement_Economy,
		len(c.settlement_economies.economies),
		allocator,
	)
	copy(snapshot.settlement_economies.economies[:], c.settlement_economies.economies[:])
	snapshot.settlement_economies.archived = make(
		[dynamic]Archived_Settlement_Economy,
		len(c.settlement_economies.archived),
		allocator,
	)
	copy(snapshot.settlement_economies.archived[:], c.settlement_economies.archived[:])
	snapshot.settlement_economies.flows = make(
		[dynamic]Trade_Flow,
		len(c.settlement_economies.flows),
		allocator,
	)
	copy(snapshot.settlement_economies.flows[:], c.settlement_economies.flows[:])
	snapshot.settlement_economies.political_links = make(
		[dynamic]Settlement_Political_Link,
		len(c.settlement_economies.political_links),
		allocator,
	)
	copy(
		snapshot.settlement_economies.political_links[:],
		c.settlement_economies.political_links[:],
	)
	if c.galaxy !=
	   nil {snapshot.galaxy = new(Galaxy, campaign_storage_allocator()); snapshot.galaxy^ = c.galaxy^; snapshot.galaxy.detailed_systems = make([dynamic]Galactic_System, len(c.galaxy.detailed_systems), campaign_storage_allocator()); copy(snapshot.galaxy.detailed_systems[:], c.galaxy.detailed_systems[:])}
	// Forecasts and transactional interaction resolution both destroy their
	// snapshots. Far Engagement is fixed-size state, so clone it instead of
	// retaining the live campaign pointer for the snapshot destructor to free.
	if c.far_engagement != nil {
		snapshot.far_engagement = new(Far_Engagement, allocator)
		snapshot.far_engagement^ = c.far_engagement^
	}
	snapshot.events = make([dynamic]Campaign_Event, len(c.events), allocator)
	copy(snapshot.events[:], c.events[:])
	if len(c.dark_fleet_atlas) >
	   0 {snapshot.dark_fleet_atlas = make([dynamic]Dark_Atlas_Discovery, len(c.dark_fleet_atlas), allocator); copy(snapshot.dark_fleet_atlas[:], c.dark_fleet_atlas[:])} else do snapshot.dark_fleet_atlas = nil
	if len(c.dark_organism_observations) >
	   0 {snapshot.dark_organism_observations = make([dynamic]Dark_Organism_Observation, len(c.dark_organism_observations), allocator); copy(snapshot.dark_organism_observations[:], c.dark_organism_observations[:])} else do snapshot.dark_organism_observations = nil
	if len(c.dark_strategy_records) >
	   0 {snapshot.dark_strategy_records = make([dynamic]Dark_Strategy_Statistics, len(c.dark_strategy_records), allocator); copy(snapshot.dark_strategy_records[:], c.dark_strategy_records[:])} else do snapshot.dark_strategy_records = nil
	if len(c.dark_unresolved_voyages) >
	   0 {snapshot.dark_unresolved_voyages = make([dynamic]Dark_Voyage_Record, len(c.dark_unresolved_voyages), allocator); copy(snapshot.dark_unresolved_voyages[:], c.dark_unresolved_voyages[:])} else do snapshot.dark_unresolved_voyages = nil
	if len(c.dark_relays) >
	   0 {snapshot.dark_relays = make([dynamic]Dark_Relay_Record, len(c.dark_relays), allocator); copy(snapshot.dark_relays[:], c.dark_relays[:])} else do snapshot.dark_relays = nil
	if len(c.habitable_contacts) >
	   0 {snapshot.habitable_contacts = make([dynamic]Habitable_World_Contact, len(c.habitable_contacts), allocator); copy(snapshot.habitable_contacts[:], c.habitable_contacts[:])} else do snapshot.habitable_contacts = nil
	if len(c.passage.local_habitable_contacts) >
	   0 {snapshot.passage.local_habitable_contacts = make([dynamic]Habitable_World_Contact, len(c.passage.local_habitable_contacts), allocator); copy(snapshot.passage.local_habitable_contacts[:], c.passage.local_habitable_contacts[:])} else do snapshot.passage.local_habitable_contacts = nil
	if len(c.outer_dark.continuum.archived_chunks) > 0 {
		snapshot.outer_dark.continuum.archived_chunks = make(
			[dynamic]Dark_Archived_Chunk,
			len(c.outer_dark.continuum.archived_chunks),
			allocator,
		)
		for archived, i in c.outer_dark.continuum.archived_chunks {snapshot.outer_dark.continuum.archived_chunks[i] = archived; if len(archived.organisms) > 0 {snapshot.outer_dark.continuum.archived_chunks[i].organisms = make([dynamic]Dark_Organism, len(archived.organisms), allocator); copy(snapshot.outer_dark.continuum.archived_chunks[i].organisms[:], archived.organisms[:])} else do snapshot.outer_dark.continuum.archived_chunks[i].organisms = nil}
	} else do snapshot.outer_dark.continuum.archived_chunks = nil
	// Snapshot strings are borrowed from the source campaign. The event buffer
	// is owned, but string destruction remains the source campaign's duty.
	snapshot.owns_strings = false
	return snapshot
}
campaign_restore :: proc(c: ^Campaign, snapshot: Campaign) -> bool {if snapshot.format_version != CAMPAIGN_FORMAT_VERSION || snapshot.rules_identity != CAMPAIGN_RULES_IDENTITY do return false
	when !ODIN_TEST do if c.galaxy != nil {galaxy_destroy(c.galaxy); free(c.galaxy)}
	delete(c.events)
	dark_continuum_destroy_storage(&c.outer_dark.continuum)
	delete(c.dark_fleet_atlas)
	delete(c.dark_organism_observations)
	delete(c.dark_strategy_records)
	delete(c.dark_unresolved_voyages)
	delete(c.dark_relays)
	delete(c.habitable_contacts)
	delete(c.passage.local_habitable_contacts)
	delete(c.settlement_economies.economies)
	delete(c.settlement_economies.archived)
	delete(c.settlement_economies.flows)
	delete(c.settlement_economies.political_links)
	c^ = snapshot
	return true}

print_campaign :: proc(c: ^Campaign) {
	fmt.printf(
		"SEASON %d/%d  YEAR %d  POPULATION %d  ENDING: %s\n",
		c.season,
		c.max_seasons,
		c.year,
		total_population(c),
		ending_name(c.ending),
	)
	fmt.printf(
		"Compute:%d/%d Manpower:%d/%d Raw materials:%d/%d\n",
		capacity_available(c.capacities.compute),
		c.capacities.compute.total,
		capacity_available(c.capacities.manpower),
		c.capacities.manpower.total,
		capacity_available(c.capacities.raw_materials),
		c.capacities.raw_materials.total,
	)
	for ship, i in c.ships {state := "active"; if ship.departure == .Lost do state = "lost"; if ship.departure == .Settlement do state = "settled"; fmt.printf("  [%02d] %-18s %-12s damage:%d history:%d %s\n", i, ship.name, role_name(ship.role), ship.damage, ship.history_count, state)}
}
