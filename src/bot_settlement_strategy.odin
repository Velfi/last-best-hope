package main

import game "../packages/game"

bot_survey_candidate_home :: proc(c: ^game.Campaign) -> bool {
	ids: [4]game.Ship_ID; count := 0; roles := [4]game.Role{.Survey, .Archive, .Foundry, .Hospital}
	for role in roles {for ship in c.ships[:c.ship_count] do if ship.active && !ship.committed && ship.role == role {ids[count] = ship.id; count += 1; break}}
	if count < 2 do return false
	if count < len(ids) do for ship in c.ships[:c.ship_count] do if ship.active && !ship.committed {known := false; for id in ids[:count] do if id == ship.id do known = true; if !known {ids[count] = ship.id; count += 1; if count == len(ids) do break}}
	if count < 3 || !game.commission_expedition(c, ids[:count], "Evaluate a possible home") do return false
	return game.resolve_expedition(c).candidate_home
}

// Long-horizon policy turns a completed package into a recorded proposal even
// when unrelated director beats keep occupying the ordinary situation window.
bot_found_ready_settlement :: proc(c: ^game.Campaign) -> bool {
	if !c.candidate_home_known || !c.colony_package_ready do return false
	community := game.Community_ID(
		0,
	); for candidate in c.communities[:c.community_count] do if candidate.consents_to_settle && candidate.population >= 1000 {community = candidate.id; break}
	if community == 0 do return false
	name := game.generate_settlement_name(u64(c.settlement_count) + c.seed)
	if !game.begin_settlement_proposal(c, name, name) do return false
	p := &c.settlement_proposal; p.procedure = .Council_Assignment; p.requested_communities[game.community_index(c, community)] = true
	profile, _ := game.candidate_profile_for_reference(c, p.celestial)
	required :=
		profile.classification == .Naturally_Habitable ? [3]game.Role{.Colony, .Agriculture, .Habitat} : [3]game.Role{.Habitat, .Foundry, .Hospital}
	for role in required {found := false; for candidate, i in c.ships[:c.ship_count] do if candidate.active && !candidate.committed && candidate.role == role {p.requested_ships[i] = true; found = true; break}; if !found && role != .Habitat do return false}
	preview := game.proposal_assess(c, p^)
	// A prepared candidate can still lack opening stocks. Treat that as the
	// explicit, recorded risk decision the settlement system provides instead of
	// silently abandoning every proposal. The waiver carries viability and
	// grievance consequences into the persistent settlement economy.
	if !preview.valid && u16(preview.proposal.founding_requirements.unmet) != 0 {
		if !game.authorize_settlement_founding_exception(c, preview.proposal.founding_requirements.unmet_summary) do return false
		p = &c.settlement_proposal; preview = game.proposal_assess(c, p^)
	}
	if !preview.valid do return false
	return game.open_settlement_deliberation(c) && game.finalize_settlement_proposal(c)
}

bot_regional_economy_diagnostics :: proc(c: ^game.Campaign) -> (i32, i32) {
	regions: [game.MAX_SETTLEMENT_ECONOMIES +
	game.MAX_SETTLEMENT_ECONOMY_ARCHIVE]string; count: i32
	for economy in c.settlement_economies.economies[:c.settlement_economies.count] do if economy.active && game.economy_stock_total(economy.produced) > 0 {known := false; for region in regions[:count] do if region == economy.identity.region do known = true; if !known {regions[count] = economy.identity.region; count += 1}}
	for archived in c.settlement_economies.archived[:c.settlement_economies.archived_count] do if game.economy_stock_total(archived.economy.produced) > 0 {known := false; for region in regions[:count] do if region == archived.economy.identity.region do known = true; if !known {regions[count] = archived.economy.identity.region; count += 1}}
	changed: i32; for flow in c.settlement_economies.flows[:c.settlement_economies.flow_count] do if flow.last_event > flow.origin_event && (flow.delivered > 0 || flow.lost > 0) do changed += 1
	return count, changed
}

bot_sponsor_productive_daughter :: proc(c: ^game.Campaign) -> bool {
	if c.settlement_count != 1 do return false
	parent :=
		c.settlements[0].id; at := game.settlement_economy_index(&c.settlement_economies, parent); if at < 0 do return false
	e := &c.settlement_economies.economies[at]; if game.economy_stock_total(e.produced) <= 0 do return false
	people := i64(500); assets := game.Economy_Stock {
		food      = 8,
		goods     = 4,
		services  = 2,
		knowledge = 1,
	}
	name := game.generate_settlement_name(
		c.seed + 0x5151,
	); region := game.generate_settlement_name(c.seed + 0x7171)
	return(
		game.found_core_daughter_settlement(
			c,
			parent,
			name,
			region,
			"sponsored commons",
			people,
			assets,
			true,
			true,
			c.event_sequence,
		) !=
		0 \
	)
}
