package game

import "core:fmt"

// Fixed campaign collections are intentionally classified here beside the
// compactor: world state (ships, communities, institutions, settlements,
// precedents), reusable slots (needs, projects, promises, situation queues),
// rolling detail (active events, ship memories/history), and archival history
// (eras, service eras, event-to-era ranges).

event_is_referenced_by_live_state :: proc(c: ^Campaign, sequence: u64) -> bool {
	if sequence == 0 do return false
	q := &c.public_politics.open
	if q.status != .None && (q.origin_event == sequence || q.opened_event == sequence || q.objection_event == sequence || q.resolution_event == sequence || q.accounting_event == sequence) do return true
	for v in c.public_politics.commitments[:c.public_politics.commitment_count] do if v.outcome == .Pending && (v.origin_event == sequence || v.last_event == sequence) do return true
	for r in c.public_politics.rivals[:c.public_politics.rival_count] do if r.active && (r.origin_event == sequence || r.last_event == sequence) do return true
	if c.pending_accountability_event == sequence do return true
	if c.current_situation.phase != .None && c.current_situation.phase != .Resolved {
		s := &c.current_situation
		if s.origin_event == sequence || s.proposal_event == sequence || s.decision_event == sequence do return true
		for position_index in 0 ..< s.position_count do for reason_index in 0 ..< s.positions[position_index].reason_count do if s.positions[position_index].reasons[reason_index].source_event == sequence do return true
	}
	for need in c.needs do if need.active && !need.resolved && (need.source_event == sequence || need.precedent_event == sequence) do return true
	for promise in c.promises[:c.promise_count] do if promise.status == .Active { 	// Promise records have no event field; preserve matching active records.
		for event in c.events[:c.event_count] do if event.sequence == sequence && event.kind == .Promise_Changed && event.community == promise.beneficiary do return true
	}
	for hook in c.history_hooks[:c.history_hook_count] do if hook.stage != .Consequence && (hook.origin_event == sequence || hook.obligation_event == sequence || hook.consequence_event == sequence) do return true
	for &ship in c.ships[:c.ship_count] {
		if ship.last_promise_event == sequence do return true
		for memory in ship.memories[:ship.memory_count] do if memory.event_sequence == sequence do return true
	}
	for figure in c.historical_figures[:c.historical_figure_count] do if figure.origin_event == sequence || figure.last_event == sequence do return true
	for settlement in c.settlements[:c.settlement_count] do if settlement.founding_event == sequence || settlement.last_report_event == sequence || settlement.archive_origin_event == sequence || settlement.proposal_event == sequence || settlement.decision_event == sequence do return true
	for relationship in c.relationships[:c.relationship_count] do if relationship.origin_event == sequence || relationship.last_event == sequence do return true
	for relationship in c.ship_relationships[:c.ship_relationship_count] do if relationship.origin_event == sequence || relationship.last_event == sequence do return true
	for relationship in c.institution_ship_relationships[:c.institution_ship_relationship_count] do if relationship.origin_event == sequence || relationship.last_event == sequence || relationship.precedent_event == sequence do return true
	for relationship in c.community_institution_relationships[:c.community_institution_relationship_count] do if relationship.origin_event == sequence || relationship.last_event == sequence do return true
	for relationship in c.institution_relationships[:c.institution_relationship_count] do if relationship.origin_event == sequence || relationship.last_event == sequence do return true
	for relationship in c.settlement_relationships[:c.settlement_relationship_count] do if relationship.origin_event == sequence || relationship.last_event == sequence do return true
	for precedent in c.precedents[:c.precedent_count] do if precedent.event_sequence == sequence do return true
	for precedent in c.precedents[:c.precedent_count] do if precedent.status != .Superseded && precedent.source_decision == sequence do return true
	for value in c.values do if value.claimed_event == sequence || value.last_test_event == sequence do return true
	for case_record in c.precedent_cases[:c.precedent_case_count] do if case_record.status == .Pending && (case_record.source_decision == sequence || case_record.contradiction_event == sequence || case_record.cited_authority_event == sequence || case_record.last_event == sequence) do return true
	for front in c.fronts[:c.front_count] {
		if front.last_change_event == sequence do return true
		for i in 0 ..< front.originating_event_count do if front.originating_events[i] == sequence do return true
	}
	for proposal in c.future_fronts[:c.future_front_count] do if proposal.source_event == sequence do return true
	for obligation in c.obligations.items[:c.obligations.count] do if obligation_active(obligation) && (obligation.origin_event == sequence || obligation.last_event == sequence) do return true
	return false
}

archived_era_index_by_sequence :: proc(c: ^Campaign, sequence: u64) -> int {
	for era, i in c.archived_eras[:c.archived_era_count] do if sequence >= era.first_sequence && sequence <= era.last_sequence do return i
	return -1
}

archived_epoch_index_by_sequence :: proc(c: ^Campaign, sequence: u64) -> int {
	for epoch, i in c.archived_epochs[:c.archived_epoch_count] do if sequence >= epoch.first_sequence && sequence <= epoch.last_sequence do return i
	return -1
}

event_reference_exists :: proc(c: ^Campaign, sequence: u64) -> bool {
	return(
		event_index_by_sequence(c, sequence) >= 0 ||
		archived_era_index_by_sequence(c, sequence) >= 0 ||
		archived_epoch_index_by_sequence(c, sequence) >= 0 \
	)
}

add_epoch_precedent :: proc(epoch: ^Archived_Epoch, value: Precedent_Kind) {
	for existing in epoch.defining_precedents[:epoch.defining_precedent_count] do if existing == value do return
	if epoch.defining_precedent_count <
	   len(
		   epoch.defining_precedents,
	   ) {epoch.defining_precedents[epoch.defining_precedent_count] = value; epoch.defining_precedent_count += 1}
}

refresh_epoch_detail :: proc(epoch: ^Archived_Epoch) {
	epoch.detail = fmt.tprintf(
		"Seasons %d–%d: %d archived eras; population %d–%d; %d ship changes, %d institution changes, %d settlements, %d losses; promises upheld/broken %d/%d.",
		epoch.first_season,
		epoch.last_season,
		epoch.era_count,
		epoch.population_start,
		epoch.population_end,
		epoch.ships_changed,
		epoch.institutions_changed,
		epoch.settlements,
		epoch.losses,
		epoch.promises_upheld,
		epoch.promises_broken,
	)
}

merge_oldest_epochs :: proc(c: ^Campaign) -> bool {
	if c.archived_epoch_count < 2 do return false
	a := c.archived_epochs[0]; b := c.archived_epochs[1]; merged := a
	merged.id = 1; merged.last_sequence = b.last_sequence; merged.last_season = b.last_season; merged.population_end = b.population_end; merged.era_count += b.era_count; merged.ships_changed += b.ships_changed; merged.institutions_changed += b.institutions_changed; merged.settlements += b.settlements; merged.losses += b.losses; merged.promises_upheld += b.promises_upheld; merged.promises_broken += b.promises_broken
	for value in b.defining_precedents[:b.defining_precedent_count] do add_epoch_precedent(&merged, value)
	if c.owns_strings {destroy_owned_string(a.detail); destroy_owned_string(b.detail)}
	refresh_epoch_detail(&merged); c.archived_epochs[0] = merged
	for i in 2 ..< c.archived_epoch_count {c.archived_epochs[i - 1] = c.archived_epochs[i]; c.archived_epochs[i - 1].id = u32(i)}
	c.archived_epoch_count -= 1; c.archived_epochs[c.archived_epoch_count] = {}; return true
}

archive_oldest_eras_to_epoch :: proc(c: ^Campaign) -> bool {
	if c.archived_era_count < 2 do return false
	if c.archived_epoch_count >= MAX_ARCHIVED_EPOCHS && !merge_oldest_epochs(c) do return false
	a :=
		c.archived_eras[0]; b := c.archived_eras[1]; epoch := &c.archived_epochs[c.archived_epoch_count]; epoch^ = {
		id                   = u32(c.archived_epoch_count + 1),
		first_sequence       = a.first_sequence,
		last_sequence        = b.last_sequence,
		first_season         = a.first_season,
		last_season          = b.last_season,
		population_start     = a.population_start,
		population_end       = b.population_end,
		era_count            = 2,
		ships_changed        = a.ships_changed + b.ships_changed,
		institutions_changed = a.institutions_changed + b.institutions_changed,
		settlements          = a.settlements + b.settlements,
		losses               = a.losses + b.losses,
		promises_upheld      = a.promises_upheld + b.promises_upheld,
		promises_broken      = a.promises_broken + b.promises_broken,
	}
	for value in a.defining_precedents[:a.defining_precedent_count] do add_epoch_precedent(epoch, value)
	for value in b.defining_precedents[:b.defining_precedent_count] do add_epoch_precedent(epoch, value)
	refresh_epoch_detail(epoch); c.archived_epoch_count += 1
	if c.owns_strings {destroy_owned_string(a.detail); destroy_owned_string(b.detail)}
	for i in 2 ..< c.archived_era_count {c.archived_eras[i - 2] = c.archived_eras[i]; c.archived_eras[i - 2].id = u32(i - 1)}
	c.archived_era_count -= 2; for i in c.archived_era_count ..< c.archived_era_count + 2 do c.archived_eras[i] = {}; return true
}

merge_oldest_service_eras :: proc(c: ^Campaign) -> bool {
	first, second := -1, -1
	for i in 0 ..< c.service_era_count {for j in i + 1 ..< c.service_era_count do if c.service_eras[i].ship == c.service_eras[j].ship {first = i; second = j; break}; if first >= 0 do break}
	if first < 0 do return false
	a := &c.service_eras[first]; b := c.service_eras[second]; a.last_season = b.last_season; a.last_sequence = b.last_sequence; a.changes += b.changes; a.losses += b.losses
	if c.owns_strings do destroy_owned_string(b.name)
	for i in second + 1 ..< c.service_era_count do c.service_eras[i - 1] = c.service_eras[i]
	c.service_era_count -= 1; c.service_eras[c.service_era_count] = {}; return true
}

chronicle_can_record :: proc(c: ^Campaign, count: int = 1) -> bool {
	if c.event_count + count <= MAX_EVENTS do return true
	return compact_chronicle(c) && c.event_count + count <= MAX_EVENTS
}

record_service_era :: proc(c: ^Campaign, event: Campaign_Event) {
	if event.ship_id == 0 do return
	index := -1
	for era, i in c.service_eras[:c.service_era_count] do if era.ship == event.ship_id && era.last_season + 4 >= event.season {index = i; break}
	if index < 0 {
		if c.service_era_count >= MAX_SERVICE_ERAS && !merge_oldest_service_eras(c) do return
		index = c.service_era_count; c.service_era_count += 1
		ship_at := ship_index(
			c,
			event.ship_id,
		); name := "Fleet service"; if ship_at >= 0 do name = fmt.tprintf("%s service era", c.ships[ship_at].name)
		c.service_eras[index] = {
			ship           = event.ship_id,
			name           = name,
			first_season   = event.season,
			last_season    = event.season,
			first_sequence = event.sequence,
			last_sequence  = event.sequence,
		}
	}
	era := &c.service_eras[index]; era.last_season = event.season; era.last_sequence = event.sequence; era.changes += 1; if event.kind == .Ship_Lost do era.losses += 1
}

compact_chronicle :: proc(c: ^Campaign) -> bool {
	if c.event_count < MAX_EVENTS do return true
	if c.archived_era_count >= MAX_ARCHIVED_ERAS &&
	   !archive_oldest_eras_to_epoch(c) {c.chronicle_saturation_failures += 1; return false}
	remove: [MAX_EVENTS]bool; remove_count := 0
	// Retain at least two seasons of current detail and every live reference.
	for event, i in c.events[:c.event_count] {
		if remove_count >= MAX_EVENTS / 2 do break
		if event.season > c.season - 2 || event_is_referenced_by_live_state(c, event.sequence) do continue
		remove[i] = true; remove_count += 1
	}
	if remove_count == 0 {c.chronicle_saturation_failures += 1; return false}
	era := &c.archived_eras[c.archived_era_count]; era.id = u32(c.archived_era_count + 1)
	first := true
	for event, i in c.events[:c.event_count] {
		if !remove[i] do continue
		if first {era.first_sequence = event.sequence; era.first_season = event.season; era.population_start = total_population(c); first = false}
		era.last_sequence =
			event.sequence; era.last_season = event.season; era.population_end = total_population(c)
		#partial switch event.kind {
		case .Ship_Damaged, .Ship_Repaired, .Ship_Scarred, .Ship_Lost:
			era.ships_changed += 1; record_service_era(c, event)
			if event.kind == .Ship_Lost do era.losses += 1
		case .Institution_Changed, .Jurisdiction_Changed:
			era.institutions_changed += 1
		case .Settlement_Founded:
			era.settlements += 1
		case .Promise_Changed:
			if event.value ==
			   i32(
				   Promise_Status.Honored,
			   ) {era.promises_upheld += 1} else if event.value == i32(Promise_Status.Broken) {era.promises_broken += 1}
		case .Precedent_Enacted:
			if era.defining_precedent_count <
			   len(
				   era.defining_precedents,
			   ) {era.defining_precedents[era.defining_precedent_count] = Precedent_Kind(event.value); era.defining_precedent_count += 1}
		case:
		}
	}
	era.detail = fmt.tprintf(
		"Seasons %d–%d: population %d–%d; %d ship changes, %d institution changes, %d settlements, %d losses; promises upheld/broken %d/%d.",
		era.first_season,
		era.last_season,
		era.population_start,
		era.population_end,
		era.ships_changed,
		era.institutions_changed,
		era.settlements,
		era.losses,
		era.promises_upheld,
		era.promises_broken,
	)
	c.archived_era_count += 1
	if c.owns_strings do for event, i in c.events[:c.event_count] {if remove[i] {destroy_owned_string(event.detail); destroy_owned_string(event.authoritative_detail)}}
	write := 0
	for event, i in c.events[:c.event_count] {if remove[i] do continue; c.events[write] = event; write += 1}
	for i in write ..< c.event_count do c.events[i] = {}
	c.event_count = write; c.chronicle_compactions += 1
	return true
}
