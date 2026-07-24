package game_tests

found_test_settlement :: proc(
	c: ^Campaign,
	community: Community_ID,
	ship: Ship_ID,
	name: string,
	generous: bool = true,
) -> bool {
	if !begin_settlement_proposal(c, name, name) do return false
	p := &c.settlement_proposal
	p.procedure = .Council_Assignment
	p.requested_communities[community_index(c, community)] = true
	p.sovereign = generous
	p.continuing_jurisdiction = !generous
	roles := [3]Role{.Habitat, .Foundry, .Hospital}
	for role in roles {
		for candidate, i in c.ships[:c.ship_count] {
			if candidate.active && candidate.role == role {
				p.requested_ships[i] = true
				break
			}
		}
	}
	at := ship_index(c, ship)
	if at >= 0 do p.requested_ships[at] = true
	return open_settlement_deliberation(c) && finalize_settlement_proposal(c)
}
