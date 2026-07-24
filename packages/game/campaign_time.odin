package game

import "core:fmt"

// Fleet-facing time is stored as whole simulated seconds. Runtime frame time is
// accumulated separately and may only commit complete one-hour quanta.
Campaign_Time :: distinct i64

CAMPAIGN_HOUR_SECONDS :: i64(60 * 60)
CAMPAIGN_DAY_SECONDS :: i64(24 * CAMPAIGN_HOUR_SECONDS)
CAMPAIGN_YEAR_DAYS :: i64(365)
CAMPAIGN_REPORT_YEARS :: i64(3)
CAMPAIGN_REPORT_SECONDS :: i64(CAMPAIGN_REPORT_YEARS * CAMPAIGN_YEAR_DAYS * CAMPAIGN_DAY_SECONDS)
CAMPAIGN_REALTIME_SECONDS_PER_SECOND :: f64(CAMPAIGN_DAY_SECONDS)
MAX_SCHEDULED_WORK :: 64
MAX_ATTENTION_EVENTS :: 32
MAX_ATTENTION_CHOICES :: 4
MAX_ATTENTION_ACTORS :: 8

Campaign_Speed :: enum {
	Paused,
	One,
	Ten,
	Hundred,
	Next_Attention,
}

campaign_speed_multiplier :: proc(speed: Campaign_Speed) -> f64 {
	switch speed {
	case .Paused:
		return 0
	case .One:
		return 1
	case .Ten:
		return 10
	case .Hundred, .Next_Attention:
		return 100
	}
	return 0
}

Campaign_Clock :: struct {
	now:                        Campaign_Time,
	fixed_accumulator_seconds:  f64,
	reporting_period:           i32,
	next_reporting_at:          Campaign_Time,
	speed:                      Campaign_Speed,
	paused_for_attention:       bool,
	operation_fraction_seconds: f64,
	synced_combat_minutes:      f64,
	synced_deep_seconds:        f64,
	synced_passage_days:        f64,
	synced_passage_id:          u64,
}

Scheduled_Work_Source :: enum {
	None,
	Council,
	Project,
	Repair,
	Settlement,
	Obligation,
	Passage,
	Far_Engagement,
	Close_Engagement,
	Fleet_Navigation,
}

Scheduled_Work :: struct {
	id:             u64,
	source:         Scheduled_Work_Source,
	source_id:      u64,
	due_at:         Campaign_Time,
	started_at:     Campaign_Time,
	priority:       i32,
	progress_basis: i32,
	active:         bool,
}

Attention_Level :: enum {
	Record,
	Forecast,
	Decision,
	Constitutional,
}

Attention_Source :: enum {
	None,
	Council,
	Campaign,
	Passage,
	Far_Engagement,
	Close_Engagement,
	Fleet_Navigation,
}

Attention_Record_Status :: enum {
	Pending,
	Resolved,
	Invalidated,
}

Attention_Event :: struct {
	id:                           u64,
	source:                       Attention_Source,
	level:                        Attention_Level,
	raised_at:                    Campaign_Time,
	response_deadline:            Campaign_Time,
	source_id:                    u64,
	cause_event:                  u64,
	priority:                     i32,
	title:                        string,
	cause:                        string,
	default_action:               string,
	underway_action:              string,
	changed_fact:                 string,
	standing_order:               string,
	affected_summary:             string,
	threshold:                    string,
	response_window:              string,
	known_costs:                  string,
	irreversible_effects:         string,
	authorization_status:         string,
	no_response_default:          string,
	affected_ships:               [MAX_ATTENTION_ACTORS]Ship_ID,
	affected_ship_count:          int,
	affected_actors:              [MAX_ATTENTION_ACTORS]string,
	affected_actor_ids:           [MAX_ATTENTION_ACTORS]u32,
	affected_actor_count:         int,
	origin_event_id:              u64,
	undertaking_id:               u32,
	authority_basis_id:           u32,
	operation_id:                 u64,
	ship_id:                      Ship_ID,
	community_id:                 Community_ID,
	institution_id:               Institution_ID,
	promise_id:                   u32,
	precedent_id:                 u32,
	explicit_resolution_required: bool,
	choices:                      [MAX_ATTENTION_CHOICES]string,
	choice_count:                 int,
	default_choice:               int,
	choice_values:                [MAX_ATTENTION_CHOICES]i32,
	record_status:                Attention_Record_Status,
	active:                       bool,
}

campaign_time_seconds :: proc(t: Campaign_Time) -> i64 {
	return i64(t)
}

campaign_time_add :: proc(t: Campaign_Time, seconds: i64) -> Campaign_Time {
	return Campaign_Time(i64(t) + max(seconds, i64(0)))
}

campaign_clock_initialize :: proc(c: ^Campaign) {
	if c.clock.next_reporting_at == 0 {
		c.clock.now = Campaign_Time(i64(max(c.season, 0)) * CAMPAIGN_REPORT_SECONDS)
		c.clock.reporting_period = max(c.season, 0)
		c.clock.next_reporting_at = campaign_time_add(c.clock.now, CAMPAIGN_REPORT_SECONDS)
		c.clock.speed = .One
	}
	campaign_clock_refresh_legacy_calendar(c)
}

campaign_clock_refresh_legacy_calendar :: proc(c: ^Campaign) {
	seconds := max(i64(c.clock.now), i64(0))
	c.season = i32(seconds / CAMPAIGN_REPORT_SECONDS)
	c.year = i32(seconds / (CAMPAIGN_YEAR_DAYS * CAMPAIGN_DAY_SECONDS))
	c.clock.reporting_period = c.season
}

campaign_set_speed :: proc(c: ^Campaign, speed: Campaign_Speed) -> bool {
	if int(speed) < int(Campaign_Speed.Paused) || int(speed) > int(Campaign_Speed.Next_Attention) {
		return false
	}
	if campaign_pending_attention(c) != nil && speed != .Paused {
		return false
	}
	c.clock.speed = speed
	return true
}

campaign_schedule_work :: proc(
	c: ^Campaign,
	source: Scheduled_Work_Source,
	source_id: u64,
	due_at: Campaign_Time,
	priority: i32 = 0,
) -> u64 {
	for &work in c.scheduled_work {
		if work.active && work.source == source && work.source_id == source_id {
			work.due_at = due_at
			work.priority = priority
			return work.id
		}
	}
	for &work in c.scheduled_work {
		if work.active do continue
		c.next_scheduled_work_id += 1
		if c.next_scheduled_work_id == 0 do c.next_scheduled_work_id = 1
		work = {
			id         = c.next_scheduled_work_id,
			source     = source,
			source_id  = source_id,
			started_at = c.clock.now,
			due_at     = due_at,
			priority   = priority,
			active     = true,
		}
		return work.id
	}
	return 0
}

campaign_can_schedule_work :: proc(
	c: ^Campaign,
	source: Scheduled_Work_Source,
	source_id: u64,
) -> bool {
	for work in c.scheduled_work {
		if !work.active || work.source == source && work.source_id == source_id {
			return true
		}
	}
	return false
}

campaign_cancel_work :: proc(c: ^Campaign, source: Scheduled_Work_Source, source_id: u64) {
	for &work in c.scheduled_work {
		if work.active && work.source == source && work.source_id == source_id {
			work.active = false
		}
	}
}

campaign_raise_attention :: proc(c: ^Campaign, event: Attention_Event) -> u64 {
	item := event
	if item.origin_event_id == 0 do item.origin_event_id = item.cause_event
	if item.underway_action == "" do item.underway_action = "Fleet work was underway under standing orders."
	if item.changed_fact == "" do item.changed_fact = item.cause
	if item.standing_order == "" do item.standing_order = "The recorded standing order no longer settles the changed condition."
	if item.affected_summary == "" {
		if item.affected_ship_count > 0 || item.affected_actor_count > 0 {
			item.affected_summary = "Named ships or actors in the cited record are exposed."
		} else {
			item.affected_summary = "Fleet capacity, authority, or an active commitment is exposed."
		}
	}
	if item.threshold == "" do item.threshold = "A recorded decision threshold became uncertain or was crossed."
	if item.response_window == "" {
		if item.response_deadline > item.raised_at {
			item.response_window = fmt.tprintf(
				"Respond before campaign time %d.",
				i64(item.response_deadline),
			)
		} else {
			item.response_window = "Resolve before fleet time resumes."
		}
	}
	if item.no_response_default == "" do item.no_response_default = item.default_action
	valid_default :=
		item.no_response_default != "" &&
		(item.choice_count == 0 ||
				item.default_choice >= 0 && item.default_choice < item.choice_count)
	if (item.level == .Decision || item.level == .Constitutional) &&
	   !valid_default &&
	   !item.explicit_resolution_required {
		return 0
	}
	slot := -1
	for item, i in c.attention_queue {
		if !item.active {
			slot = i
			break
		}
	}
	if slot < 0 do return 0
	c.next_attention_id += 1
	if c.next_attention_id == 0 do c.next_attention_id = 1
	item.id = c.next_attention_id
	item.active = true
	item.record_status = .Pending
	if item.raised_at == 0 do item.raised_at = c.clock.now
	if item.response_deadline == 0 do item.response_deadline = item.raised_at
	c.attention_queue[slot] = item
	if item.level == .Decision || item.level == .Constitutional {
		c.clock.paused_for_attention = true
		c.clock.speed = .Paused
	}
	return item.id
}

campaign_pending_attention :: proc(c: ^Campaign) -> ^Attention_Event {
	best := -1
	for &event, i in c.attention_queue {
		if !event.active || event.level != .Decision && event.level != .Constitutional {
			continue
		}
		if best < 0 ||
		   event.raised_at < c.attention_queue[best].raised_at ||
		   event.raised_at == c.attention_queue[best].raised_at &&
			   (event.priority > c.attention_queue[best].priority ||
					   event.priority == c.attention_queue[best].priority &&
						   (event.source_id < c.attention_queue[best].source_id ||
								   event.source_id == c.attention_queue[best].source_id &&
									   event.id < c.attention_queue[best].id)) {
			best = i
		}
	}
	if best < 0 do return nil
	return &c.attention_queue[best]
}

campaign_resolve_campaign_default :: proc(c: ^Campaign, source_id: u64) -> bool {
	if source_id == 0 do return true
	switch source_id {
	case 0x200000001:
		// Doctrine prefers structural remedies, then recoverable rationing.
		commands := [5]Food_Shortage_Command {
			.Invest_Capacity,
			.Import_Route,
			.Change_Diet,
			.Reduce_Growth,
			.Ration,
		}
		for command in commands {
			if food_shortage_command_legal(c, command) {
				return apply_food_shortage_command(c, command)
			}
		}
	case 0x200000002:
		for item in c.precedent_cases[:c.precedent_case_count] {
			if item.status == .Pending && item.review_season <= c.season {
				return review_precedent_case(c, item.id, .Affirm)
			}
		}
	case 0x200000003:
		if resolve_economy_loss_decision(c, true) do return true
		return resolve_economy_loss_decision(c, false)
	case 0x200000004:
		return acknowledge_stranded_outcome(c)
	case 0x200000005:
		return conclude_chronicle(c)
	case:
		if source_id & 0x100000000 != 0 && c.current_situation.phase == .Decision {
			for i in 0 ..< c.current_situation.choice_count {
				if resolve_interaction(c, i) do return true
			}
		}
	}
	return false
}

campaign_resolve_passage_default :: proc(c: ^Campaign) -> bool {
	p := &c.passage
	switch p.pause_reason {
	case .Coherence_Limit:
		ok, _ := stabilize_passage_coherence(c, p, true)
		return ok
	case .Material_Obstruction:
		preview := passage_obstruction_response_preview(c, p)
		ok, _ := respond_to_material_obstruction(c, p, preview.can_wait)
		return ok
	case .Dangerous_Contact:
		for &track in p.dark_navigation.tracker.tracks[:p.dark_navigation.tracker.track_count] {
			if !dark_track_requires_response(&track) do continue
			accept := p.strategy.ecology == .Contact_Tolerant
			ok, _ := respond_to_dark_contact(c, p, accept, track.organism_id)
			return ok
		}
	case .Course_Arrival, .Unknown_Door, .Contract_Evidence, .Propellant_Reserve, .None:
		// These boundaries change the route or undertaking and therefore cannot be
		// dismissed as though "open Passage" were an operational decision.
		return false
	}
	return false
}

campaign_resolve_attention :: proc(c: ^Campaign, id: u64, choice: int) -> bool {
	for &event in c.attention_queue {
		if !event.active || event.id != id do continue
		selected := choice
		if selected < 0 || selected >= event.choice_count do selected = event.default_choice
		ok := true
		switch event.source {
		case .Council:
			if c.council.exception_pending do ok = resolve_political_exception(c, selected)
		case .Far_Engagement:
			if c.far_engagement != nil && c.far_engagement.decision.pending {
				ok = far_resolve_decision(
					c.far_engagement,
					Far_Command(event.choice_values[selected]),
				)
			}
		case .Close_Engagement:
			if c.combat_runtime != nil && c.combat_runtime.request_pending {
				combat_resolve_request(c.combat_runtime, event.choice_values[selected] != 0)
			}
		case .Passage:
			ok = campaign_resolve_passage_default(c)
		case .Fleet_Navigation:
			ok = true
		case .Campaign:
			ok = campaign_resolve_campaign_default(c, event.source_id)
		case .None:
			ok = false
		}
		if !ok do return false
		event.active = false
		event.record_status = .Resolved
		c.clock.paused_for_attention = campaign_pending_attention(c) != nil
		return true
	}
	return false
}

campaign_attention_exists :: proc(c: ^Campaign, source: Attention_Source, source_id: u64) -> bool {
	for event in c.attention_queue {
		if event.active && event.source == source && event.source_id == source_id {
			return true
		}
	}
	return false
}

campaign_clear_attention_source :: proc(c: ^Campaign, source: Attention_Source, source_id: u64) {
	for &event in c.attention_queue {
		if event.active &&
		   event.source == source &&
		   (source_id == 0 || event.source_id == source_id) {
			event.active = false
			event.record_status = .Invalidated
		}
	}
	c.clock.paused_for_attention = campaign_pending_attention(c) != nil
}

campaign_advance_operation_delta :: proc(c: ^Campaign, seconds: f64) -> i64 {
	if seconds > 0 do c.clock.operation_fraction_seconds += seconds
	whole := i64(c.clock.operation_fraction_seconds)
	if whole <= 0 do return 0
	advanced := campaign_advance_exact(c, whole)
	// Keep any duration stopped by a campaign attention boundary. The adapter
	// has already observed it in subsystem-local time, so it must be retried
	// after attention resolves rather than silently discarded.
	c.clock.operation_fraction_seconds -= f64(advanced)
	return advanced
}

campaign_sync_close_engagement :: proc(c: ^Campaign, m: ^Combat_Mission) {
	if c == nil || m == nil do return
	if f64(m.time) < c.clock.synced_combat_minutes {
		c.clock.synced_combat_minutes = 0
	}
	delta := f64(m.time) - c.clock.synced_combat_minutes
	c.clock.synced_combat_minutes = f64(m.time)
	_ = campaign_advance_operation_delta(c, delta * 60)
	source_id := m.seed
	if m.request_pending {
		if !campaign_attention_exists(c, .Close_Engagement, source_id) {
			_ = campaign_raise_attention(
				c,
				{
					source = .Close_Engagement,
					level = .Decision,
					source_id = source_id,
					operation_id = source_id,
					undertaking_id = u32(c.compact.active.id),
					origin_event_id = c.compact.active.accepted_event,
					title = "COMMAND REQUEST",
					cause = m.request_text,
					default_action = m.request_consequence,
					choices = {"APPROVE", "DENY", "", ""},
					choice_values = {1, 0, 0, 0},
					choice_count = 2,
					default_choice = combat_request_default(m) ? 0 : 1,
				},
			)
		}
	} else {
		campaign_clear_attention_source(c, .Close_Engagement, source_id)
	}
}

campaign_sync_far_engagement :: proc(c: ^Campaign, e: ^Far_Engagement) {
	if c == nil || e == nil do return
	elapsed := e.elapsed_seconds
	if elapsed <= 0 do elapsed = e.hour * 3600
	if elapsed < c.clock.synced_deep_seconds do c.clock.synced_deep_seconds = 0
	delta := elapsed - c.clock.synced_deep_seconds
	c.clock.synced_deep_seconds = elapsed
	_ = campaign_advance_operation_delta(c, delta)
	source_id := e.seed
	if e.decision.pending {
		if !campaign_attention_exists(c, .Far_Engagement, source_id) {
			event := Attention_Event {
				source          = .Far_Engagement,
				level           = .Decision,
				source_id       = source_id,
				operation_id    = source_id,
				undertaking_id  = u32(c.compact.active.id),
				origin_event_id = c.compact.active.accepted_event,
				title           = e.decision.title,
				cause           = e.decision.situation,
				default_action  = e.decision.default_text,
				choice_count    = e.decision.option_count,
				default_choice  = e.decision.default_option,
			}
			for i in 0 ..< e.decision.option_count {
				event.choices[i] = e.decision.labels[i]
				event.choice_values[i] = i32(e.decision.commands[i])
			}
			_ = campaign_raise_attention(c, event)
		}
	} else {
		campaign_clear_attention_source(c, .Far_Engagement, source_id)
	}
}

campaign_sync_passage :: proc(c: ^Campaign, p: ^Passage) {
	if c == nil || p == nil do return
	if c.clock.synced_passage_id != p.id {
		c.clock.synced_passage_id = p.id
		c.clock.synced_passage_days = 0
	}
	if p.elapsed_days < c.clock.synced_passage_days {
		c.clock.synced_passage_days = 0
	}
	delta := p.elapsed_days - c.clock.synced_passage_days
	c.clock.synced_passage_days = p.elapsed_days
	_ = campaign_advance_operation_delta(c, delta * f64(CAMPAIGN_DAY_SECONDS))
	if p.phase == .Awaiting_Leg && p.pause_reason != .None {
		if !campaign_attention_exists(c, .Passage, p.id) {
			event := Attention_Event {
				source                       = .Passage,
				level                        = .Decision,
				source_id                    = p.id,
				operation_id                 = p.id,
				undertaking_id               = u32(p.contract.undertaking_id),
				title                        = "EXPEDITION REQUIRES DIRECTION",
				underway_action              = "The expedition was following its recorded Passage strategy.",
				cause                        = fmt.tprintf(
					"%v interrupted the standing expedition plan.",
					p.pause_reason,
				),
				changed_fact                 = fmt.tprintf("Passage reported %v.", p.pause_reason),
				standing_order               = "The expedition strategy does not settle this route boundary.",
				affected_summary             = "The named expedition ships remain exposed in Passage.",
				threshold                    = fmt.tprintf(
					"%v now requires a recorded response.",
					p.pause_reason,
				),
				default_action               = "No automatic response; player direction is required.",
				no_response_default          = "No automatic response; player direction is required.",
				explicit_resolution_required = true,
				choices                      = {"OPEN PASSAGE", "", "", ""},
				choice_count                 = 1,
				default_choice               = 0,
			}
			event.affected_ship_count = min(p.ship_count, len(event.affected_ships))
			for ship_id, i in p.ships[:event.affected_ship_count] do event.affected_ships[i] = ship_id
			if event.affected_ship_count > 0 do event.ship_id = event.affected_ships[0]
			_ = campaign_raise_attention(c, event)
		}
	} else {
		campaign_clear_attention_source(c, .Passage, p.id)
	}
}

campaign_next_due_work_index :: proc(c: ^Campaign) -> int {
	best := -1
	for work, i in c.scheduled_work {
		if !work.active || work.due_at > c.clock.now do continue
		if best < 0 ||
		   work.due_at < c.scheduled_work[best].due_at ||
		   work.due_at == c.scheduled_work[best].due_at &&
			   (work.priority > c.scheduled_work[best].priority ||
					   work.priority == c.scheduled_work[best].priority &&
						   work.id < c.scheduled_work[best].id) {
			best = i
		}
	}
	return best
}

campaign_process_due_work :: proc(c: ^Campaign) {
	for {
		index := campaign_next_due_work_index(c)
		if index < 0 do break
		work := &c.scheduled_work[index]
		work.active = false
		switch work.source {
		case .Council:
			if c.council.active && !c.council.exception_pending {
				advance_council_enactment(c)
				if c.council.exception_pending {
					_ = campaign_raise_attention(
						c,
						{
							source = .Council,
							level = .Constitutional,
							source_id = u64(c.council.id),
							cause_event = c.council.last_event,
							origin_event_id = c.council.last_event,
							institution_id = c.compact.active.charter.hard_authority.reviewer,
							title = "COUNCIL AUTHORITY CONFLICT",
							cause = c.council.exception_reason,
							default_action = "Withdraw the motion under standing doctrine.",
							choices = {
								"WITHDRAW",
								"RETAIN · 2 COHESION",
								"EMERGENCY AUTHORITY",
								"",
							},
							choice_count = 3,
							default_choice = 0,
						},
					)
				} else if c.council.active {
					_ = campaign_schedule_work(
						c,
						.Council,
						u64(c.council.id),
						campaign_time_add(c.clock.now, 30 * CAMPAIGN_DAY_SECONDS),
						20,
					)
				}
			}
		case .Project:
			advance_project(c, int(work.source_id) - 1)
		case .Fleet_Navigation:
			fleet_navigation_resolve_due(c, work.source_id)
		case .Repair,
		     .Settlement,
		     .Obligation,
		     .Passage,
		     .Far_Engagement,
		     .Close_Engagement,
		     .None:
		}
		if c.clock.paused_for_attention do break
	}
}

campaign_process_reporting_boundaries :: proc(c: ^Campaign) {
	for c.clock.now >= c.clock.next_reporting_at && !c.clock.paused_for_attention {
		if campaign_raise_existing_attention(c) do break
		campaign_clock_refresh_legacy_calendar(c)
		campaign_process_reporting_period(c)
		c.clock.next_reporting_at = campaign_time_add(
			c.clock.next_reporting_at,
			CAMPAIGN_REPORT_SECONDS,
		)
		campaign_clock_refresh_legacy_calendar(c)
		if campaign_raise_existing_attention(c) do break
	}
}

campaign_raise_existing_attention :: proc(c: ^Campaign) -> bool {
	source_id: u64
	title, cause, default_action: string
	level := Attention_Level.Decision
	if c.current_situation.phase != .None && c.current_situation.phase != .Resolved {
		source_id = 0x100000000 | u64(c.current_situation.id)
		title = c.current_situation.title
		cause = c.current_situation.proposal
		default_action = "Open the council record before fleet time resumes."
	} else if c.material_economy.food_shortage_response_pending {
		source_id = 0x200000001
		title = "FOOD SHORTAGE REQUIRES A STRUCTURAL RESPONSE"
		cause = "Secure production no longer covers fleet consumption."
		default_action = "Open the shortage account."
	} else if precedent_review_due(c) {
		source_id = 0x200000002
		title = "A PRECEDENT IS DUE FOR REVIEW"
		cause = "Standing law reached its recorded review date."
		default_action = "Open the council record."
		level = .Constitutional
	} else if c.economy_loss_decision_pending {
		source_id = 0x200000003
		title = "ESSENTIAL CAPABILITY EXPOSED"
		cause = "Fleet losses require repair, substitution, or an accepted gap."
		default_action = "Open the loss account."
	} else if c.stranded_outcome_notice_pending {
		source_id = 0x200000004
		title = "A SEPARATED EXPEDITION REPORTED"
		cause = "The fleet must acknowledge the expedition's autonomous decision."
		default_action = "Open the expedition report."
	} else if c.ending_prompt_pending {
		source_id = 0x200000005
		title = "THE CHRONICLE HORIZON ARRIVED"
		cause = "The fleet must conclude, enter its finale, or continue."
		default_action = "Open the chronicle decision."
	} else {
		for &event in c.attention_queue {
			// Compatibility callers may resolve a campaign modal directly
			// instead of through campaign_resolve_attention. Once no matching
			// campaign state remains, every queued Campaign decision is stale
			// and must stop pausing the deterministic clock.
			if event.active && event.source == .Campaign && event.source_id != 0 {
				event.active = false
				event.record_status = .Invalidated
			}
		}
		c.clock.paused_for_attention = campaign_pending_attention(c) != nil
		return false
	}
	if !campaign_attention_exists(c, .Campaign, source_id) {
		_ = campaign_raise_attention(
			c,
			{
				source = .Campaign,
				level = level,
				source_id = source_id,
				origin_event_id = c.current_situation.origin_event,
				ship_id = c.current_situation.initiator,
				community_id = c.current_situation.affected_community,
				undertaking_id = u32(c.compact.active.id),
				authority_basis_id = c.current_situation.law_domain != .None ? u32(c.current_situation.law_domain) : 0,
				title = title,
				cause = cause,
				default_action = default_action,
				active = true,
			},
		)
	}
	return true
}

campaign_advance_exact :: proc(c: ^Campaign, simulated_seconds: i64) -> i64 {
	if simulated_seconds <= 0 ||
	   c.ending != .In_Progress ||
	   c.clock.paused_for_attention ||
	   campaign_pending_attention(c) != nil {
		return 0
	}
	campaign_clock_initialize(c)
	remaining := simulated_seconds
	advanced: i64
	for remaining > 0 && !c.clock.paused_for_attention {
		step := min(remaining, CAMPAIGN_HOUR_SECONDS)
		c.clock.now = campaign_time_add(c.clock.now, step)
		advanced += step
		remaining -= step
		if fleet_navigation_report_material_deviation(c) do break
		if fleet_navigation_report_harvest_deviation(c) do break
		campaign_process_due_work(c)
		campaign_process_reporting_boundaries(c)
	}
	campaign_clock_refresh_legacy_calendar(c)
	return advanced
}

campaign_tick :: proc(c: ^Campaign, real_elapsed_seconds: f64) -> i64 {
	if campaign_raise_existing_attention(c) do return 0
	if real_elapsed_seconds <= 0 || c.clock.paused_for_attention || c.clock.speed == .Paused {
		return 0
	}
	rate := campaign_speed_multiplier(c.clock.speed)
	c.clock.fixed_accumulator_seconds +=
		real_elapsed_seconds * CAMPAIGN_REALTIME_SECONDS_PER_SECOND * rate
	whole_hours := i64(c.clock.fixed_accumulator_seconds) / CAMPAIGN_HOUR_SECONDS
	if whole_hours <= 0 do return 0
	seconds := whole_hours * CAMPAIGN_HOUR_SECONDS
	c.clock.fixed_accumulator_seconds -= f64(seconds)
	return campaign_advance_exact(c, seconds)
}

campaign_advance_to_attention :: proc(c: ^Campaign) -> bool {
	if campaign_pending_attention(c) != nil do return true
	campaign_clock_initialize(c)
	for iteration in 0 ..< 100000 {
		next := c.clock.next_reporting_at
		found := false
		for work in c.scheduled_work {
			if !work.active do continue
			if !found || work.due_at < next {
				next = work.due_at
				found = true
			}
		}
		delta := max(i64(next) - i64(c.clock.now), CAMPAIGN_HOUR_SECONDS)
		advanced := campaign_advance_exact(c, delta)
		if campaign_pending_attention(c) != nil do return true
		if c.ending != .In_Progress || advanced <= 0 do return false
	}
	return false
}

advance_season :: proc(c: ^Campaign) {
	legacy_season := c.season
	if c.ending != .In_Progress || resolve_fleet_dissolution(c) do return
	campaign_clock_initialize(c)
	// Compatibility callers resolve campaign modals directly rather than
	// through campaign_resolve_attention. Reconcile the shared queue first so a
	// resolved modal cannot leave the legacy reporting-boundary command paused.
	if campaign_raise_existing_attention(c) do return
	if precedent_review_due(c) ||
	   c.material_economy.food_shortage_response_pending ||
	   c.ending_prompt_pending ||
	   c.economy_loss_decision_pending ||
	   c.stranded_outcome_notice_pending {
		return
	}
	derived := i32(max(i64(c.clock.now), i64(0)) / CAMPAIGN_REPORT_SECONDS)
	if legacy_season != derived {
		c.clock.now = Campaign_Time(i64(max(legacy_season, 0)) * CAMPAIGN_REPORT_SECONDS)
		c.clock.reporting_period = max(legacy_season, 0)
		c.clock.next_reporting_at = campaign_time_add(c.clock.now, CAMPAIGN_REPORT_SECONDS)
		c.season = legacy_season
		c.year = legacy_season * i32(CAMPAIGN_REPORT_YEARS)
	}
	target := c.clock.next_reporting_at
	_ = campaign_advance_exact(c, max(i64(target) - i64(c.clock.now), i64(0)))
}
