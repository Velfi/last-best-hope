package game

import "core:fmt"

MAX_SHIP_SOCIAL_ITEMS :: 32

Ship_Social_Item_Kind :: enum {
	Duty,
	Undertaking,
	Operation,
	Precedent,
	Exposure,
	Community,
	Captain,
	Bond,
	Conflict,
	Promise,
	Obligation,
	Jurisdiction,
	Claim,
	Scar,
	Recovery,
	Memory,
}

Ship_Social_Reference_Kind :: enum {
	None,
	Ship,
	Actor,
	Community,
	Institution,
	Undertaking,
	Promise,
	Precedent,
	Operation,
	Chronicle_Event,
}

Ship_Social_Item :: struct {
	kind:              Ship_Social_Item_Kind,
	reference_kind:    Ship_Social_Reference_Kind,
	reference_id:      u64,
	cause_event:       u64,
	relevance:         i32,
	recency:           u64,
	stable_id:         u64,
	label:             string,
	detail:            string,
	decision_effect:   string,
	active:            bool,
}

Ship_Social_Position :: struct {
	ship:       Ship_ID,
	duty:       string,
	items:      [MAX_SHIP_SOCIAL_ITEMS]Ship_Social_Item,
	item_count: int,
}

ship_social_item_before :: proc(a, b: Ship_Social_Item) -> bool {
	if a.relevance != b.relevance do return a.relevance > b.relevance
	if a.recency != b.recency do return a.recency > b.recency
	return a.stable_id < b.stable_id
}

ship_social_add :: proc(p: ^Ship_Social_Position, item: Ship_Social_Item) {
	if p.item_count >= len(p.items) do return
	at := p.item_count
	p.items[at] = item
	p.items[at].active = true
	p.item_count += 1
	for at > 0 && ship_social_item_before(p.items[at], p.items[at - 1]) {
		p.items[at], p.items[at - 1] = p.items[at - 1], p.items[at]
		at -= 1
	}
}

ship_social_latest_promise_event :: proc(c: ^Campaign, community: Community_ID) -> u64 {
	for i := c.event_count - 1; i >= 0; i -= 1 {
		event := c.events[i]
		if event.kind == .Promise_Changed && event.community == community do return event.sequence
	}
	return 0
}

ship_social_position :: proc(c: ^Campaign, id: Ship_ID) -> Ship_Social_Position {
	p := Ship_Social_Position{ship = id}
	si := ship_index(c, id)
	if si < 0 do return p
	ship := c.ships[si]
	p.duty = ship.current_position
	if p.duty == "" {
		p.duty = ship.committed ? "Committed to fleet work." : ship.active ? "Available for assignment." : "No active assignment."
	}
	ship_social_add(&p, {
		kind = .Duty, reference_kind = .Ship, reference_id = u64(id),
		relevance = ship.committed ? 95 : 55, stable_id = u64(id),
		label = "CURRENT DUTY", detail = p.duty,
		decision_effect = ship.committed ? "Assignment changes require releasing the current commitment." : "The ship remains available to current options.",
	})
	u := &c.compact.active
	if u.status == .Planning || u.status == .Operating {
		undertaking_role := compact_ship_is_seconded(c, id) ? "seconded ship" : "observer"
		ship_social_add(&p, {
			kind = .Undertaking, reference_kind = .Undertaking, reference_id = u64(u.id),
			cause_event = u.accepted_event, recency = u.accepted_event,
			relevance = 100, stable_id = 0x100000000 | u64(u.id),
			label = "ACTIVE UNDERTAKING",
			detail = fmt.tprintf("%v · %v · %s", u.operation, u.approach, undertaking_role),
			decision_effect = "The charter records authority, intent, expectations, and standing doctrine.",
		})
		ship_social_add(&p, {
			kind = .Operation,
			reference_kind = .Operation,
			reference_id = u64(u.id),
			cause_event = u.accepted_event,
			recency = u.accepted_event,
			relevance = compact_ship_is_seconded(c, id) ? 99 : 72,
			stable_id = 0x110000000 | u64(u.id),
			label = "CURRENT OPERATION",
			detail = fmt.tprintf("%v · %s", u.operation, undertaking_role),
			decision_effect = "Operation participation changes exposure, forecast, and available assignment.",
		})
	}
	if ship.current_commitment != "" {
		ship_social_add(&p, {
			kind = .Exposure, reference_kind = .Ship, reference_id = u64(id),
			relevance = 92, stable_id = 0x200000000 | u64(id),
			label = "ACCEPTED EXPOSURE", detail = ship.current_commitment,
			decision_effect = "Changing course may alter a recorded commitment.",
		})
	}
	ci := community_index(c, ship.community)
	if ci >= 0 {
		community := c.communities[ci]
		ship_social_add(&p, {
			kind = .Community, reference_kind = .Community, reference_id = u64(community.id),
			cause_event = community.last_memory_event, recency = community.last_memory_event,
			relevance = community.position == .Aggrieved ? 91 : 65,
			stable_id = 0x300000000 | u64(community.id),
			label = "COMMUNITY AFFILIATION",
			detail = fmt.tprintf("%s · %v · grievance %d", community.name, community.position, community.grievance),
			decision_effect = community.position == .Aggrieved ? "Current grievance may change support, cost, or consent." : "Community standing informs consent and support.",
		})
	}
	fi := historical_figure_index(c, ship.captain)
	if fi >= 0 {
		figure := c.historical_figures[fi]
		dossier := captain_dossier(c, figure.id)
		ship_social_add(&p, {
			kind = .Captain, reference_kind = .Actor, reference_id = u64(figure.id),
			cause_event = figure.last_event, recency = figure.last_event, relevance = dossier.tension != "" ? 88 : 68,
			stable_id = 0x400000000 | u64(figure.id), label = "CAPTAIN",
			detail = dossier.tension == "" ? figure.name : fmt.tprintf("%s · %s", figure.name, dossier.tension),
			decision_effect = dossier.tension == "" ? "Captain conduct remains part of operational forecasts." : "This tension may change compliance or autonomous action.",
		})
		for obligation in c.captain_obligations[:c.captain_obligation_count] {
			if obligation.captain != figure.id || obligation.status != .Active do continue
			ship_social_add(&p, {
				kind = .Obligation, reference_kind = .Institution, reference_id = u64(obligation.issuer),
				cause_event = obligation.issued_event, recency = obligation.issued_event, relevance = 98,
				stable_id = 0x500000000 | u64(obligation.id), label = "CAPTAIN OBLIGATION",
				detail = fmt.tprintf("%v · stakes %d", obligation.decision_context, obligation.stakes),
				decision_effect = "Compliance is evaluated when this decision context recurs.",
			})
		}
	}
	for relationship, ri in c.ship_relationships[:c.ship_relationship_count] {
		if relationship.ship_a != id && relationship.ship_b != id do continue
		other := relationship.ship_a == id ? relationship.ship_b : relationship.ship_a
		oi := ship_index(c, other)
		name := oi >= 0 ? c.ships[oi].name : "unavailable ship record"
		kind := relationship.strength < 0 ? Ship_Social_Item_Kind.Conflict : .Bond
		ship_social_add(&p, {
			kind = kind, reference_kind = .Ship, reference_id = u64(other),
			cause_event = relationship.last_event, recency = relationship.last_event,
			relevance = 70 + abs(relationship.strength) * 4,
			stable_id = 0x600000000 | u64(ri), label = kind == .Bond ? "SHIP BOND" : "SHIP CONFLICT",
			detail = fmt.tprintf("%s · %v · strength %d", name, relationship.kind, relationship.strength),
			decision_effect = kind == .Bond ? "This bond may reduce coordination cost or support recovery." : "This conflict may change coordination cost or available support.",
		})
	}
	for relationship, ri in c.institution_ship_relationships[:c.institution_ship_relationship_count] {
		if relationship.ship != id do continue
		ii := institution_index(c, relationship.institution)
		name := ii >= 0 ? c.institutions[ii].name : "institution record"
		ship_social_add(&p, {
			kind = .Jurisdiction, reference_kind = .Institution, reference_id = u64(relationship.institution),
			cause_event = relationship.last_event, recency = relationship.last_event,
			relevance = relationship.stance == .Contested ? 97 : 76,
			stable_id = 0x700000000 | u64(ri), label = "JURISDICTION",
			detail = fmt.tprintf("%s · %v", name, relationship.stance),
			decision_effect = relationship.stance == .Contested ? "Authorization is contested for current choices." : "This institution governs applicable authorization.",
		})
		if relationship.precedent_event != 0 {
			ship_social_add(&p, {
				kind = .Precedent,
				reference_kind = .Precedent,
				reference_id = relationship.precedent_event,
				cause_event = relationship.precedent_event,
				recency = relationship.precedent_event,
				relevance = 89,
				stable_id = 0x710000000 | u64(ri),
				label = "GOVERNING PRECEDENT",
				detail = fmt.tprintf("Chronicle event E%03d", relationship.precedent_event),
				decision_effect = "The cited precedent changes applicable authority.",
			})
		}
	}
	if ship.pending_claim != "" {
		ship_social_add(&p, {
			kind = .Claim, reference_kind = .Ship, reference_id = u64(id), relevance = 96,
			stable_id = 0x800000000 | u64(id), label = "ACTIVE CLAIM", detail = ship.pending_claim,
			decision_effect = "The claim may change authority, cost, or an available option.",
		})
	}
	if ship.scar != .None {
		scar_event: u64
		for i := ship.memory_count - 1; i >= 0; i -= 1 {
			if ship.memories[i].kind == .Ship_Scarred {
				scar_event = ship.memories[i].event_sequence
				break
			}
		}
		ship_social_add(&p, {
			kind = .Scar, reference_kind = .Ship, reference_id = u64(id),
			cause_event = scar_event,
			recency = scar_event,
			relevance = 86, stable_id = 0x900000000 | u64(id), label = "SCAR",
			detail = fmt.tprintf("%v", ship.scar),
			decision_effect = "The scar remains part of the ship's physical and social record.",
		})
	}
	for project, pi in c.projects {
		if !project.active || project.ship != id || project.kind != .Repair do continue
		ship_social_add(&p, {
			kind = .Recovery, reference_kind = .Ship, reference_id = u64(id),
			relevance = 94, stable_id = 0xa00000000 | u64(pi), label = "RECOVERY WORK",
			detail = fmt.tprintf("Repair · %d periods remaining", project.remaining),
			decision_effect = "Reassignment may interrupt repair and preserve current damage.",
		})
	}
	for promise, pi in c.promises[:c.promise_count] {
		if promise.status != .Active || promise.beneficiary != ship.community do continue
		event := ship_social_latest_promise_event(c, promise.beneficiary)
		ship_social_add(&p, {
			kind = .Promise, reference_kind = .Promise, reference_id = u64(pi + 1),
			cause_event = event, recency = event, relevance = 93,
			stable_id = 0xb00000000 | u64(pi), label = "ACTIVE PROMISE", detail = promise.detail,
			decision_effect = fmt.tprintf("Standing doctrine records a deadline at season %d.", promise.deadline),
		})
	}
	for memory, mi in ship.memories[:ship.memory_count] {
		ship_social_add(&p, {
			kind = .Memory, reference_kind = .Chronicle_Event, reference_id = memory.event_sequence,
			cause_event = memory.event_sequence, recency = memory.event_sequence, relevance = 35,
			stable_id = 0xc00000000 | u64(mi), label = "SERVICE HISTORY",
			detail = fmt.tprintf("%v", memory.kind),
			decision_effect = "Open the causal record for the recorded change.",
		})
	}
	return p
}
