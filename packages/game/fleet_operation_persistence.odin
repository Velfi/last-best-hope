package game

import "core:bytes"
import "core:encoding/json"

combat_operation_plan_export_json :: proc(plan: ^Combat_Operation_Plan) -> ([]u8, bool) {
	if plan == nil || plan.version != COMBAT_PLAN_VERSION do return nil, false
	data, error := json.marshal(plan^)
	return data, error == nil
}

combat_operation_plan_canonicalize :: proc(plan: ^Combat_Operation_Plan) {
	if plan == nil do return
	// Forecasts and validation are deterministic caches rebuilt against the
	// receiving battlespace. Group names use a fixed buffer for player edits
	// and a package string for generated defaults; canonicalize both spellings
	// into the persistent buffer before semantic comparison.
	plan.validation = {}
	plan.forecasts = {}
	for &group in plan.groups {
		display_name := combat_plan_group_name(&group)
		canonical_name: [32]u8
		canonical_length := min(len(display_name), len(canonical_name))
		display_bytes := transmute([]u8)display_name
		for index in 0 ..< canonical_length do canonical_name[index] = display_bytes[index]
		group.custom_name = {}
		group.custom_name_length = canonical_length
		for index in 0 ..< canonical_length do group.custom_name[index] = canonical_name[index]
		group.name = ""
	}
}

combat_operation_plans_semantically_equal :: proc(a, b: Combat_Operation_Plan) -> bool {
	left, right := a, b
	combat_operation_plan_canonicalize(&left)
	combat_operation_plan_canonicalize(&right)
	// Compare the canonical persisted representation rather than aggregate
	// memory. This excludes struct padding and allocator-backed string identity,
	// both of which may vary with test or load order despite equal plan values.
	left_data, left_error := json.marshal(left)
	if left_error != nil do return false
	defer delete(left_data)
	right_data, right_error := json.marshal(right)
	if right_error != nil do return false
	defer delete(right_data)
	return bytes.equal(left_data, right_data)
}

combat_operation_plan_import_json :: proc(operation: ^Combat_Operation, data: []u8) -> bool {
	if operation == nil ||
	   operation.operation_context != .Skirmish ||
	   operation.committed_plan.committed {
		return false
	}
	plan: Combat_Operation_Plan
	if json.unmarshal(data, &plan, allocator = context.temp_allocator) != nil ||
	   plan.version != COMBAT_PLAN_VERSION ||
	   plan.committed ||
	   plan.immutable {
		return false
	}
	for &group, index in plan.groups {
		if group.custom_name_length == 0 && group.name != "" {
			group.custom_name_length = min(len(group.name), len(group.custom_name))
			bytes := transmute([]u8)group.name
			for byte_index in 0 ..< group.custom_name_length {
				group.custom_name[byte_index] = bytes[byte_index]
			}
		}
		group.name = combat_plan_default_group_name(index)
	}
	plan.validation = combat_operation_validate_plan(operation, &plan)
	if !plan.validation.valid do return false
	operation.draft = plan
	return true
}

combat_operation_validate_loaded :: proc(operation: ^Combat_Operation) -> bool {
	if operation == nil || !operation.active do return true
	if operation.version != COMBAT_OPERATION_VERSION ||
	   operation.battlespace.feature_count < 0 ||
	   operation.battlespace.feature_count > len(operation.battlespace.features) ||
	   operation.battlespace.node_count < 0 ||
	   operation.battlespace.node_count > len(operation.battlespace.nodes) ||
	   operation.intelligence.contact_count < 0 ||
	   operation.intelligence.contact_count > len(operation.intelligence.contacts) {
		return false
	}
	plans := [3]^Combat_Operation_Plan {
		&operation.draft,
		&operation.committed_plan,
		&operation.enemy_plan,
	}
	for plan in plans {
		if plan.version != 0 && plan.version != COMBAT_PLAN_VERSION do return false
		if plan.group_count < 0 ||
		   plan.group_count > COMBAT_GROUP_COUNT ||
		   plan.assignment_count < 0 ||
		   plan.assignment_count > len(plan.assignments) {
			return false
		}
		for group in plan.groups {
			if group.primary_route.count < 0 ||
			   group.primary_route.count > len(group.primary_route.waypoints) ||
			   group.withdrawal_route.count < 0 ||
			   group.withdrawal_route.count > len(group.withdrawal_route.waypoints) ||
			   group.contingency_count < 0 ||
			   group.contingency_count > len(group.contingencies) {
				return false
			}
		}
	}
	if operation.committed_plan.committed {
		if !operation.committed_plan.immutable do return false
		candidate := operation.committed_plan
		validation := combat_operation_validate_plan(operation, &candidate)
		if !validation.valid do return false
	}
	return true
}
