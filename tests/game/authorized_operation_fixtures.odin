package game_tests

import game "../../packages/game"
import "core:testing"

authorize_test_operation :: proc(
	c: ^Campaign,
	operation: Operation_Kind,
	route: Compact_Operation_Route,
	ship_ids: []Ship_ID,
	propellant: i32,
) -> Compact_Undertaking_ID {
	call_id := game.Compact_Call_ID(c.compact.next_call_id)
	c.compact.next_call_id += 1
	c.compact.call_count = 1
	call := &c.compact.calls[0]
	call^ = {
		id = call_id,
		status = .Accepted,
		sponsor = c.institutions[0].id,
		beneficiary = c.communities[0].id,
		source_event = 1,
		deadline = c.season + 2,
		title = "Authorized test operation",
		stakes = "Exercise the authorized operation path.",
		autonomous_trajectory = "The sponsor proceeds without Compact coordination.",
		approach_count = MAX_COMPACT_APPROACHES,
		selected_approach = 0,
		offer_count = len(ship_ids),
		source = {
			kind = .Institution,
			id = u64(c.institutions[0].id),
			causal_event = 1,
		},
	}
	undertaking := Compact_Undertaking_ID(c.compact.next_undertaking_id)
	c.compact.next_undertaking_id += 1
	call.undertaking = undertaking
	for ship, i in ship_ids {
		call.offers[i] = {
			contributor = c.institutions[0].id,
			ship = ship,
			condition = .Protect_Ship,
			available = true,
			selected = true,
			source_event = 1,
		}
	}
	reserved := Operation_Resources {propellant = propellant}
	c.compact.active = {
		id = undertaking,
		call = call_id,
		status = .Planning,
		operation = operation,
		route = route,
		seconded_count = len(ship_ids),
		reserved = reserved,
		resource_ledger = {reserved = reserved},
		charter = {
			version = 1,
			undertaking = undertaking,
			call = call_id,
			intent_event = 1,
			compiled_event = 1,
			valid = true,
		},
	}
	for ship, i in ship_ids do c.compact.active.seconded_ships[i] = ship
	return undertaking
}

begin_authorized_test_passage :: proc(
	c: ^Campaign,
	contract: Dark_Contract,
	ship_indices: []int,
	out: ^Passage,
) -> (bool, string) {
	ship_ids: [MAX_EXPEDITION_SHIPS]Ship_ID
	for ship_index, i in ship_indices {
		ship_ids[i] = c.ships[ship_index].id
	}
	undertaking := authorize_test_operation(
		c,
		.Passage,
		.Passage,
		ship_ids[:len(ship_indices)],
		i32(max(len(ship_indices) * 2, 4)),
	)
	authorized := contract
	authorized.undertaking_id = undertaking
	return game.begin_passage(c, authorized, ship_indices, out)
}

begin_authorized_test_combat_deployment :: proc(
	c: ^Campaign,
	ships: []Ship_ID,
	groups: []int,
) -> (Combat_Deployment_Preview, bool) {
	_ = authorize_test_operation(
		c,
		.Combat,
		.Close_Engagement,
		ships,
		i32(max(len(ships), 1)),
	)
	return game.combat_begin_campaign_deployment(c, ships, groups)
}

@(test)
authorized_operation_fixture_is_persistable :: proc(t: ^testing.T) {
	c: Campaign
	campaign_init(&c, 99117)
	defer campaign_destroy(&c)
	ships := [1]int{0}
	ok, message := begin_authorized_test_passage(
		&c,
		default_passage_contract(),
		ships[:],
		&c.passage,
	)
	testing.expectf(t, ok, "%s", message)
	data := campaign_serialize(&c)
	defer delete(data)
	restored: Campaign
	defer campaign_destroy(&restored)
	decoded := campaign_deserialize(data[:], &restored)
	testing.expectf(t, decoded.ok, "%s", decoded.message)
}
