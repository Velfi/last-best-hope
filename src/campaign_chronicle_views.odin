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
draw_settlement_proposal :: proc(s: ^Ux_State) {
	top_rail(
		s,
	); p := &s.campaign.settlement_proposal; preview := game.proposal_assess(s.campaign, p^)
	draw_text(
		"SETTLEMENT PROPOSAL",
		28,
		78,
		TYPE_TITLE,
	); draw_fmt(28, 112, TYPE_SMALL_EMPHASIS, UX.info, "%s · %s · %v", p.name, p.destination, p.phase)
	panel(R(28, 145, 360, 490)); label_caps("PROCEDURE", 50, 168)
	for procedure, i in game.Settlement_Procedure {if radio_button(R(50, 192 + f32(i) * 34, 310, 28), fmt.tprintf("%v", procedure), p.procedure == procedure, p.phase == .Draft) do _ = execute_command(s, {kind = .Set_Settlement_Procedure, procedure = procedure})}
	label_caps("RECORD AND CHARTER", 50, 302)
	if checkbox(R(50, 326, 310, 28), "DISCLOSE EVIDENCE", p.disclose_evidence, p.phase == .Draft) do _ = execute_command(s, {kind = .Set_Settlement_Disclosure, flag = !p.disclose_evidence})
	if checkbox(R(50, 360, 310, 28), "INDEPENDENT CHARTER", p.sovereign, p.phase == .Draft) do _ = execute_command(s, {kind = .Set_Settlement_Charter, flag = !p.sovereign})
	if checkbox(R(50, 394, 310, 28), "PARTICIPATORY CHARTER", p.charter_participation, p.phase == .Draft) do _ = execute_command(s, {kind = .Set_Settlement_Charter_Participation, flag = !p.charter_participation})
	label_caps("CONTINUING GUARANTEES", 50, 438)
	for obligation, i in game.Continuing_Obligation {checked := game.continuing_has(p.obligations, obligation); if checkbox(R(50 + f32(i % 2) * 156, 458 + f32(i / 2) * 30, 148, 24), fmt.tprintf("%v", obligation), checked, p.phase == .Draft) do _ = execute_command(s, {kind = .Set_Settlement_Obligation, obligation = obligation, flag = !checked})}
	label_caps("INSTITUTIONS / ARCHIVES", 50, 522)
	for institution, i in s.campaign.institutions {if checkbox(R(50, 542 + f32(i) * 24, 148, 22), institution.name, p.transfer_institutions[i], p.phase == .Draft && institution.active) do _ = execute_command(s, {kind = .Set_Settlement_Institution, index = int(institution.id), flag = !p.transfer_institutions[i]})}
	for archive, i in s.campaign.archives {if checkbox(R(210, 542 + f32(i) * 24, 150, 22), archive.name, p.transfer_archives[i], p.phase == .Draft && archive.preserved) do _ = execute_command(s, {kind = .Set_Settlement_Archive, index = int(archive.id), flag = !p.transfer_archives[i]})}
	panel(R(410, 145, 420, 490)); label_caps("REQUESTED SHIPS", 432, 168)
	for ship, i in s.campaign.ships[:s.campaign.ship_count] {if !ship.active do continue; y := 190 + f32(i) * 27; if checkbox(R(432, y, 180, 23), ship.name, p.requested_ships[i], p.phase == .Draft) do _ = execute_command(s, {kind = .Set_Settlement_Ship, ship = ship.id, flag = !p.requested_ships[i]}); a := preview.proposal.assessments[i]; draw_fmt(620, y + 4, TYPE_LABEL, a.consent.final_stance == .Committed_To_Depart ? UX.good : a.consent.final_stance == .Strongly_Remain ? UX.warn : UX.text, "%v · %d%% · C%d", a.consent.final_stance, a.consent.support, a.consent.confidence)}
	label_caps("COMMUNITIES", 432, 526)
	for community, i in s.campaign.communities[:s.campaign.community_count] {if checkbox(R(432 + f32(i % 2) * 190, 550 + f32(i / 2) * 29, 182, 24), community.name, p.requested_communities[i], p.phase == .Draft) do _ = execute_command(s, {kind = .Set_Settlement_Community, community = community.id, flag = !p.requested_communities[i]})}
	panel(
		R(850, 145, 402, 490),
	); label_caps("PROJECTED RECORD", 874, 168); draw_fmt(874, 197, TYPE_SUBHEADING_COMPACT, preview.valid ? UX.good : UX.warn, "%v", preview.conduct); draw_fmt(874, 230, TYPE_BODY_COMPACT, UX.text, "%d SHIPS · %d PEOPLE", preview.participating_ships, preview.population); draw_fmt(874, 256, TYPE_BODY_COMPACT, UX.text, "VIABILITY %d · FLEET COHESION %d", preview.projected_colony_viability, preview.projected_fleet_cohesion); draw_text_wrapped(preview.message, R(874, 286, 350, 50), TYPE_SMALL_EMPHASIS, UX.dim)
	label_caps(
		"SELECTED SHIP POSITION",
		874,
		350,
	); selected := clamp(s.selected_ship, 0, s.campaign.ship_count - 1); a := preview.proposal.assessments[selected]; draw_fmt(874, 376, TYPE_BODY, UX.info, "%s · %v", s.campaign.ships[selected].name, a.consent.final_stance); draw_fmt(874, 402, TYPE_SMALL_EMPHASIS, UX.text, "DEPART %d · REMAIN %d", a.departure_score, a.remaining_score); draw_fmt(874, 425, TYPE_SMALL_EMPHASIS, UX.text, "SUPPORT %d · OPPOSITION %d", a.consent.support, a.consent.opposition); for reason, i in a.consent.reasons[:a.consent.reason_count] do draw_text_wrapped(reason, R(874, 452 + f32(i) * 52, 350, 48), TYPE_LABEL, UX.dim)
	if p.phase == .Draft {
		if button(
			R(874, 570, 166, 38),
			"OPEN DELIBERATION",
			true,
			true,
		) {r := execute_command(s, {kind = .Open_Settlement_Deliberation}); s.status = r.message}
		if button(R(1050, 570, 174, 38), "WITHDRAW") do _ = execute_command(s, {kind = .Withdraw_Settlement_Proposal})
	} else if p.phase == .Deliberation {
		if button(R(874, 570, 130, 38), "REVISE") do _ = execute_command(s, {kind = .Revise_Settlement_Proposal})
		if button(R(1014, 570, 210, 38), "AUTHORIZE FOUNDING", preview.valid, true) {
			from_passage :=
				s.campaign.passage.active; autosave_before(s); r := execute_command(s, {kind = .Finalize_Settlement_Proposal}); s.status = r.message
			if r.ok {if from_passage {s.screen = .Debrief} else {s.screen = .Fleet}}
		}
	}
	bottom_rail(s, "LET SHIPS DECIDE WHAT THEY WILL FOUND")
}

chronicle_event_matches_filter :: proc(event: game.Campaign_Event, filter: int) -> bool {switch
	filter {case 1:
		return game.semantic_has(event.semantic_tags, .Ship); case 2:
		return game.semantic_has(event.semantic_tags, .Community); case 3:
		return game.semantic_has(event.semantic_tags, .Institution); case 4:
		return game.semantic_has(event.semantic_tags, .Settlement); case 5:
		return game.semantic_has(event.semantic_tags, .Contested); case:
		return true}}

draw_chronicle :: proc(s: ^Ux_State) {
	top_rail(
		s,
	); draw_text("THE CHRONICLE", 28, 78, TYPE_TITLE); draw_text("PUBLIC RECORD / AUTHORITATIVE EVENTS", 28, 113, TYPE_SMALL_EMPHASIS, UX.info)
	chronicle_tabs := [2]string{"CURRENT", "ERAS"}
	s.chronicle_view = tab_group(R(202, 108, 196, 24), chronicle_tabs[:], s.chronicle_view)
	filters := [6]string {
		"ALL",
		"SHIPS",
		"PEOPLE",
		"INSTITUTIONS",
		"HARBORS",
		"CONTESTED",
	}; for label, i in filters {if button(R(420 + f32(i) * 82, 108, 76, 24), label, true, s.chronicle_filter == i) do s.chronicle_filter = i}
	panel(R(28, 145, 790, 500)); visible: [12]int; visible_count := 0
	if s.chronicle_view == 0 {
		for i := s.campaign.event_count - 1;
		    i >= 0 && visible_count < 12;
		    i -= 1 {if chronicle_event_matches_filter(s.campaign.events[i], s.chronicle_filter) {visible[visible_count] = i; visible_count += 1}}
		for row in 0 ..< visible_count {i := visible[visible_count - 1 - row]; e := s.campaign.events[i]; y := 170 + f32(row) * 36; if e.passage_id != 0 {draw_fmt(40, y + 2, TYPE_CAPTION, e.account_status == .Uncontested ? UX.dim : UX.warn, "+%.2fD", e.membrane_elapsed_days)} else {draw_fmt(48, y + 2, TYPE_LABEL, e.account_status == .Uncontested ? UX.dim : UX.warn, "S%02d", e.season)}; if button(R(92, y - 5, 706, 30), e.detail, true, s.selected_event == i) do s.selected_event = i}
	} else {
		for era, row in s.campaign.archived_eras[:min(s.campaign.archived_era_count, 12)] {y := 170 + f32(row) * 36; draw_fmt(48, y + 2, TYPE_LABEL, UX.dim, "S%02d–%02d", era.first_season, era.last_season); draw_text(era.detail, 128, y + 2, TYPE_LABEL, UX.text)}
	}
	panel(R(842, 145, 410, 500)); label_caps("FOUNDING RECORD", 870, 170)
	draw_fmt(
		870,
		201,
		TYPE_BODY_COMPACT,
		UX.text,
		"LOSS · %s",
		game.LOSS_NAMES[int(s.campaign.loss)],
	)
	draw_fmt(
		870,
		230,
		TYPE_BODY_COMPACT,
		UX.info,
		"PRESERVED · %s",
		game.PRESERVED_NAMES[int(s.campaign.preserved_inheritance)],
	)
	divider(870, 263, 350); label_caps("CLAIMED VALUES", 870, 278)
	for value, i in s.campaign.values do draw_fmt(870, 300 + f32(i) * 22, TYPE_SMALL_EMPHASIS, value.status == .Compromised ? UX.warn : UX.committed, "%s · %v", game.value_name(value.kind), value.status)
	label_caps(
		"ACTIVE RULES",
		870,
		346,
	); row := 0; for p in s.campaign.precedents[:s.campaign.precedent_count] {if p.status == .Superseded || row >= 2 do continue; draw_fmt(870, 368 + f32(row) * 20, TYPE_SMALL, p.status == .Contested ? UX.warn : UX.text, "E%03d · %v · %v", p.event_sequence, p.kind, p.status); row += 1}; for case_record in s.campaign.precedent_cases[:s.campaign.precedent_case_count] do if case_record.status == .Pending {draw_fmt(870, 408, TYPE_FINE, UX.warn, "REVIEW S%02d · CASE %d", case_record.review_season, case_record.id); break}
	divider(870, 405, 350); label_caps("CAUSAL RECORD", 870, 425)
	if s.campaign.event_count > 0 {
		selected := clamp(
			s.selected_event,
			0,
			s.campaign.event_count - 1,
		); event := s.campaign.events[selected]
		draw_fmt(
			870,
			446,
			TYPE_SMALL_EMPHASIS,
			UX.text,
			"SEASON %d · E%03d · %v",
			event.season,
			event.sequence,
			event.kind,
		)
		if event.passage_id != 0 {
			draw_fmt(
				870,
				462,
				TYPE_CAPTION,
				UX.dim,
				"SHIP +%.2f D · MEMBRANE +%.2f D · DEPTH %.2f",
				event.ship_elapsed_days,
				event.membrane_elapsed_days,
				event.dark_depth,
			)
		} else {draw_text(
				game.semantic_tag_summary(event.semantic_tags),
				870,
				462,
				TYPE_CAPTION,
				UX.dim,
			)}
		if event.account_status != .Uncontested {
			draw_fmt(870, 474, TYPE_SMALL, UX.warn, "PUBLIC · %s", event.detail)
			draw_fmt(
				870,
				492,
				TYPE_SMALL,
				UX.committed,
				"AUTHORITATIVE · %s",
				event.authoritative_detail,
			)
			if event.account_exposed do draw_text("EXPOSED BY PUBLIC ARCHIVE", 870, 514, TYPE_SMALL, UX.good)
		}
		figure_index := game.historical_figure_index(s.campaign, event.figure_id)
		if figure_index >=
		   0 {figure := s.campaign.historical_figures[figure_index]; draw_fmt(870, 474, TYPE_SMALL_EMPHASIS, UX.committed, "%s · AGE %d · %s", figure.name, figure.age_years, figure.role)}
		community_at := game.community_index(s.campaign, event.community)
		if community_at >= 0 &&
		   figure_index < 0 &&
		   event.account_status ==
			   .Uncontested {community := s.campaign.communities[community_at]; draw_fmt(870, 474, TYPE_SMALL_EMPHASIS, community.position == .Aggrieved ? UX.warn : UX.info, "%s · %v · GRIEVANCE %d", community.name, community.position, community.grievance)}
		institution_at := game.institution_index(s.campaign, event.institution_id)
		if institution_at >=
		   0 {institution := s.campaign.institutions[institution_at]; draw_fmt(870, 490, TYPE_SMALL_EMPHASIS, UX.info, "%s · LEGITIMACY %d", institution.name, institution.legitimacy)}
		ship_at := game.ship_index(s.campaign, event.ship_id)
		if ship_at >= 0 &&
		   institution_at <
			   0 {draw_fmt(870, 490, TYPE_SMALL_EMPHASIS, UX.info, "SHIP · %s", s.campaign.ships[ship_at].name)}
		settlement_at := game.settlement_index(s.campaign, event.settlement_id)
		if settlement_at >=
		   0 {settlement := s.campaign.settlements[settlement_at]; draw_fmt(870, 506, TYPE_SMALL_EMPHASIS, UX.good, "%s · LIBERTY %d · VIABILITY %d", settlement.name, settlement.liberty, settlement.viability); draw_trade_dependency_record(s, 870, 526, 350, event.settlement_id, max_rows = 1)}
		related_ship_at := game.ship_index(s.campaign, event.related_ship_id)
		if related_ship_at >=
		   0 {draw_fmt(870, 506, TYPE_SMALL_EMPHASIS, UX.info, "WITH · %s", s.campaign.ships[related_ship_at].name)}
		archive_at := game.archive_index(s.campaign, event.archive_id)
		if archive_at >=
		   0 {draw_fmt(870, 522, TYPE_SMALL, UX.committed, "ARCHIVE · %s", s.campaign.archives[archive_at].name)}
		rule_index := game.event_index_by_sequence(s.campaign, event.precedent_event)
		if rule_index >=
		   0 {rule := s.campaign.events[rule_index]; if button(R(870, 536, 350, 24), fmt.tprintf("RULE E%03d · %s", rule.sequence, rule.detail)) do s.selected_event = rule_index}
		cause_row := 0; for cause in event.causes[:event.cause_count] {if cause_row >= 2 do break; cause_index := game.event_index_by_sequence(s.campaign, cause.sequence); if cause_index < 0 {era_index := game.archived_era_index_by_sequence(s.campaign, cause.sequence); if era_index >= 0 {era := s.campaign.archived_eras[era_index]; if button(R(870, 562 + f32(cause_row) * 26, 350, 24), fmt.tprintf("← %s E%03d · ERA %d", game.event_cause_role_name(cause.role), cause.sequence, era.id)) do s.chronicle_view = 1; cause_row += 1}; continue}; source := s.campaign.events[cause_index]; if button(R(870, 562 + f32(cause_row) * 26, 350, 24), fmt.tprintf("← %s E%03d · %v", game.event_cause_role_name(cause.role), source.sequence, source.kind)) do s.selected_event = cause_index; cause_row += 1}
		if cause_row == 0 do draw_text("No recorded cause.", 870, 558, TYPE_SMALL_EMPHASIS, UX.dim)
		led_to_y := max(f32(598), 566 + f32(cause_row) * 26)
		label_caps("LED TO", 870, led_to_y); row := 0
		for consequence, i in s.campaign.events[:s.campaign.event_count] {if !game.event_cites(consequence, event.sequence) || row >= 2 do continue; if button(R(870, led_to_y + 16 + f32(row) * 24, 350, 22), fmt.tprintf("E%03d · %v", consequence.sequence, consequence.kind)) do s.selected_event = i; row += 1}
		if row == 0 do draw_text("No recorded consequence yet.", 870, led_to_y + 20, TYPE_SMALL_EMPHASIS, UX.dim)
	}
	for case_record in s.campaign.precedent_cases[:s.campaign.precedent_case_count] {if case_record.status != .Pending do continue; pi := game.precedent_index_by_id(s.campaign, case_record.primary); if pi < 0 do break; p := s.campaign.precedents[pi]; narrow := game.precedent_narrow_interpretation(p.kind); if button(R(48, 604, 118, 28), "AFFIRM") do _ = execute_command(s, {kind = .Resolve_Precedent_Case, index = int(case_record.id), target = int(game.Precedent_Review.Affirm)}); if button(R(174, 604, 118, 28), "NARROW", narrow != .Default) do _ = execute_command(s, {kind = .Resolve_Precedent_Case, index = int(case_record.id), target = int(game.Precedent_Review.Narrow), amount = i32(narrow)}); if button(R(300, 604, 118, 28), "REPLACE", case_record.secondary != 0) {ri := game.precedent_index_by_id(s.campaign, case_record.secondary); if ri >= 0 do _ = execute_command(s, {kind = .Resolve_Precedent_Case, index = int(case_record.id), target = int(game.Precedent_Review.Replace), precedent = s.campaign.precedents[ri].kind})}; if button(R(426, 604, 150, 28), "LEAVE CONTESTED") do _ = execute_command(s, {kind = .Resolve_Precedent_Case, index = int(case_record.id), target = int(game.Precedent_Review.Leave_Contested)}); break}
	if page_back_button(navigation_return_label(s.navigation_return_screen)) do close_chronicle(s)
	bottom_rail(s, "FOLLOW WHAT EACH DECISION SET IN MOTION")
}

draw_build :: proc(s: ^Ux_State) {top_rail(s); draw_text("BUILD & REPAIR", 28, 78, TYPE_TITLE)
	draw_text(
		"THREE PROJECT SLOTS · INDUSTRY IS COMMITTED IMMEDIATELY",
		28,
		113,
		TYPE_SMALL_EMPHASIS,
		UX.info,
	)
	ship := s.campaign.ships[clamp(s.selected_ship, 0, s.campaign.ship_count - 1)]
	preview := game.project_preview(s.campaign, .Repair, ship.id)
	draw_fmt(720, 78, TYPE_BODY_COMPACT, UX.text, "TARGET · %s", ship.name)
	draw_fmt(
		720,
		102,
		TYPE_SMALL,
		ship.damage > 0 ? UX.warn : UX.good,
		"DAMAGE %d → %d",
		ship.damage,
		preview.resulting_damage,
	)
	for i := 0;
	    i < len(s.campaign.projects);
	    i += 1 {project := s.campaign.projects[i]; rect := R(28 + f32(i) * 405, 150, 380, 180)
		panel(rect, true)
		draw_fmt(rect.x + 22, rect.y + 20, TYPE_BODY_COMPACT, UX.dim, "SLOT %d", i + 1)
		if project.active {draw_fmt(rect.x + 22, rect.y + 58, TYPE_HEADING_COMPACT, UX.text, "%v", project.kind)
			draw_fmt(
				rect.x + 22,
				rect.y + 98,
				TYPE_BODY,
				UX.warn,
				"%d SEASONS REMAIN",
				project.remaining,
			)} else {draw_text("AVAILABLE", rect.x + 22, rect.y + 52, TYPE_SUBHEADING, UX.good); draw_fmt(rect.x + 22, rect.y + 82, TYPE_SMALL_EMPHASIS, UX.text, "REPAIR %s · %d SEASON", ship.name, preview.duration)
			if button(
				R(rect.x + 22, rect.y + 108, 160, 38),
				"REVIEW REPAIR",
				preview.valid,
			) {s.pending_project = .Repair; s.modal = .Project}}}
	panel(R(28, 360, 570, 240))
	draw_text("OPPORTUNITY COST", 52, 385, TYPE_SUBHEADING_COMPACT)
	draw_fmt(52, 424, TYPE_BODY, UX.text, "PROJECT COST  %s", preview.cost_summary)
	draw_fmt(
		52,
		452,
		TYPE_SMALL_EMPHASIS,
		UX.dim,
		"AVAILABLE  %s",
		game.fleet_stock_label(s.campaign.material_economy.fleet.stock),
	)
	floor := game.fleet_operating_floor(s.campaign).stock
	spendable := game.fleet_stock_min_zero(
		game.fleet_stock_sub(s.campaign.material_economy.fleet.stock, floor),
	)
	draw_fmt(52, 470, TYPE_FINE, UX.dim, "PROTECTED  %s", game.fleet_stock_label(floor))
	draw_fmt(52, 486, TYPE_FINE, UX.text, "SPENDABLE  %s", game.fleet_stock_label(spendable))
	draw_text(
		"Projects complete during season advance. Committed Industry cannot answer council needs.",
		52,
		482,
		TYPE_BODY,
		UX.dim,
	)
	draw_research_direction(s)
	bottom_rail(s, "PREPARE SHIPS WITHOUT ERASING THEIR HISTORY")}


select_recommended_passage_ships :: proc(s: ^Ux_State) {
	s.passage_ships = {}
	indices: [game.MAX_EXPEDITION_SHIPS]int
	count := game.recommend_passage_ships(s.campaign, &s.contract, &indices)
	for index in indices[:count] do s.passage_ships[index] = true
}

prepare_dark_briefing :: proc(s: ^Ux_State) {
	s.contract = game.default_passage_contract()
	_ = game.apply_active_charter_to_passage_contract(s.campaign, &s.contract)
	available: [game.MAX_NEEDS]game.Dark_Contract
	if s.contract.need_index < 0 && game.dark_available_contracts(s.campaign, &available) > 0 do s.contract = available[0]
	s.dark_strategy = game.recommend_dark_strategy(s.campaign, &s.contract).strategy
	select_recommended_passage_ships(s)
}

prepare_combat_campaign_briefing :: proc(s: ^Ux_State) {
	s.passage_ships = {}
	s.combat_deployment_groups = {}
	selected := 0
	for ship, i in s.campaign.ships[:s.campaign.ship_count] {
		if !ship.active ||
		   ship.departure != .None ||
		   !game.compact_operation_ship_available(s.campaign, ship.id) {
			continue
		}
		s.passage_ships[i] = true
		s.combat_deployment_groups[i] = selected % game.COMBAT_GROUP_COUNT
		selected += 1
		if selected >= 12 do break
	}
}

draw_combat_campaign_briefing :: proc(s: ^Ux_State) {
	top_rail(s)
	draw_text("COMBAT DEPLOYMENT", 28, 78, TYPE_TITLE)
	panel(R(28, 130, 1224, 500))
	seed := s.campaign.initial_seed ~ (u64(s.campaign.season + 1) * 0x9e3779b97f4a7c15)
	kind := game.combat_campaign_mission_kind(s.campaign, seed)
	contract_seed := game.combat_mix(
		seed ~ u64(s.campaign.compact.active.id + 1) * 0x6a09e667f3bcc909,
	)
	contract := game.skirmish_generate_objectives(contract_seed, kind)
	label_caps("AUTHORIZED OPERATION", 58, 158, UX.info)
	draw_text(game.skirmish_mission_name(kind), 58, 184, TYPE_SUBHEADING, UX.text)
	draw_text_wrapped(
		game.skirmish_mission_description(kind),
		R(58, 216, 350, 48),
		TYPE_SMALL,
		UX.dim,
	)
	for objective, i in contract.objectives[:contract.count] {
		role := objective.optional ? "OPTIONAL" : "PRIMARY"
		draw_text_fitted(
			fmt.tprintf("%s · %s", role, game.skirmish_objective_name(objective.kind)),
			R(58, 276 + f32(i) * 26, 350, 22),
			TYPE_MICRO,
			objective.optional ? UX.dim : UX.committed,
		)
	}

	label_caps("DEPLOYED SHIPS", 450, 158, UX.info)
	draw_text("Select ships and assign Screen, Strike, or Support.", 450, 184, TYPE_SMALL, UX.dim)
	ids: [game.MAX_SHIPS]game.Ship_ID
	groups: [game.MAX_SHIPS]int
	count := 0
	for ship, i in s.campaign.ships[:s.campaign.ship_count] {
		if i >= 12 do break
		eligible :=
			ship.active &&
			ship.departure == .None &&
			game.compact_operation_ship_available(s.campaign, ship.id)
		row := i % 6
		column := i / 6
		x := 450 + f32(column) * 380
		y := 218 + f32(row) * 46
		if checkbox(R(x, y, 210, 24), fmt.tprintf("%s · %s", ship.name, game.role_name(ship.role)), s.passage_ships[i], eligible) do s.passage_ships[i] = !s.passage_ships[i]
		if s.passage_ships[i] && eligible {
			group := clamp(s.combat_deployment_groups[i], 0, game.COMBAT_GROUP_COUNT - 1)
			group_name := group == 0 ? "SCREEN" : group == 1 ? "STRIKE" : "SUPPORT"
			if button(R(x + 218, y, 118, 24), group_name) do s.combat_deployment_groups[i] = (group + 1) % game.COMBAT_GROUP_COUNT
			ids[count] = ship.id
			groups[count] = group
			count += 1
		}
	}
	preview := game.combat_deployment_preview(s.campaign, ids[:count], groups[:count])
	draw_text_wrapped(
		preview.warning,
		R(58, 392, 350, 42),
		TYPE_SMALL,
		preview.valid ? UX.info : UX.warn,
	)
	draw_fmt(
		58,
		448,
		TYPE_CAPTION,
		UX.text,
		"SHIPS %d · PROPELLANT %d",
		preview.ship_count,
		preview.propellant_cost,
	)
	draw_fmt(
		58,
		472,
		TYPE_FINE,
		UX.dim,
		"CONTROL %d · STRIKE %d · SUPPORT %d · RECON %d",
		preview.control,
		preview.strike,
		preview.support,
		preview.recon,
	)
	if button(R(344, 520, 64, 44), s.combat_deployment_why_open ? "HIDE" : "WHY") do s.combat_deployment_why_open = !s.combat_deployment_why_open
	if s.combat_deployment_why_open {
		for factor, i in preview.factors[:min(preview.factor_count, 5)] do draw_fmt(58, 570 + f32(i) * 15, TYPE_MICRO, factor.evidence == .Unknown ? UX.warn : factor.contribution < 0 ? UX.bad : UX.dim, "%+.1f %s", factor.contribution, factor.label)
	}
	if button(R(58, 520, 280, 44), "COMMIT DEPLOYMENT", preview.valid, true) {
		_, ok := game.combat_begin_campaign_deployment(s.campaign, ids[:count], groups[:count])
		if ok {
			operation_planning_prepare_campaign(s)
			_ = ux_save(s, true)
		}
	}
	if page_back_button("← COMPACT") do s.screen = .Care
	bottom_rail(s, "CHOOSE SHIPS · ASSIGN TASK GROUPS · COMMIT THE DEPLOYMENT")
}

draw_briefing :: proc(s: ^Ux_State) {
	if s.campaign.compact.active.operation == .Combat &&
	   (s.campaign.compact.active.status == .Planning ||
			   s.campaign.compact.active.status == .Operating) {
		draw_combat_campaign_briefing(s)
		return
	}
	top_rail(
		s,
	); draw_text("EXPEDITION COMMISSION", 28, 78, TYPE_TITLE); panel(R(28, 130, 1224, 500))
	draw_text(
		"PURPOSE",
		58,
		158,
		TYPE_SMALL_EMPHASIS,
	); available: [game.MAX_NEEDS]game.Dark_Contract; available_count := game.dark_available_contracts(s.campaign, &available)
	if available_count == 0 {
		draw_text("NO PASSAGE UNDERTAKING IS READY", 58, 190, TYPE_LABEL, UX.warn)
		draw_text_wrapped(
			"The Compact must authorize a Passage before ships can be commissioned. Open Compact when a call or council decision is awaiting attention.",
			R(58, 218, 570, 48),
			TYPE_SMALL,
			UX.dim,
		)
		bottom_rail(s, "COMPACT AUTHORIZES THE PURPOSE · COMMISSION ASSIGNS THE SHIPS")
		return
	}
	if available_count > 0 &&
	   s.contract.need_index <
		   0 {s.contract = available[0]; s.dark_strategy = game.recommend_dark_strategy(s.campaign, &s.contract).strategy; select_recommended_passage_ships(s)}
	for contract, i in available[:available_count] {selected :=
			s.contract.need_index == contract.need_index
		if radio_button(
			R(58, 190 + f32(i) * 46, 360, 36),
			fmt.tprintf(
				"%v · %s",
				contract.purpose,
				game.institution_name(s.campaign, contract.sponsor),
			),
			selected,
		) {s.contract = contract; s.dark_strategy = game.recommend_dark_strategy(s.campaign, &s.contract).strategy; select_recommended_passage_ships(s)}}
	selected_indices: [game.MAX_EXPEDITION_SHIPS]int; selected_count := 0
	chosen_total := 0; for chosen in s.passage_ships do if chosen do chosen_total += 1
	// A charter requires capabilities, not particular hulls.  Mark only a role
	// that the current available selection still fails to cover; otherwise an
	// unseconded duplicate can look like a required but unusable ship.
	covered_roles := i32(0)
	for ship, i in s.campaign.ships[:s.campaign.ship_count] {
		if s.passage_ships[i] && ship.active && game.compact_operation_ship_available(s.campaign, ship.id) do covered_roles |= i32(1) << u32(ship.role)
	}
	missing_roles := s.contract.required_roles & ~covered_roles
	draw_text("SHIP CAPABILITIES", 58, 326, TYPE_CAPTION, UX.dim)
	draw_text(
		missing_roles == 0 ? "REQUIRED CAPABILITIES COVERED · ONLY SECONDED SHIPS MAY DEPLOY" : "◆ REQUIRED CAPABILITY MISSING · ONLY SECONDED SHIPS MAY DEPLOY",
		258,
		326,
		TYPE_FINE,
		missing_roles == 0 ? UX.good : UX.warn,
	)
	for ship, i in s.campaign.ships[:s.campaign.ship_count] {
		if i >= 12 do break
		x := f32(58 + (i / 6) * 180); y := f32(350 + (i % 6) * 28)
		eligible := ship.active && game.compact_operation_ship_available(s.campaign, ship.id)
		required := missing_roles & (i32(1) << u32(ship.role)) != 0
		label := fmt.tprintf(
			"%s%s · %s",
			required ? "◆ " : "",
			ship.name,
			game.role_name(ship.role),
		)
		row := R(x, y, 170, 24)
		if checkbox(
			row,
			label,
			s.passage_ships[i],
			eligible && (s.passage_ships[i] || chosen_total < game.MAX_EXPEDITION_SHIPS),
		) {if s.passage_ships[i] {s.passage_ships[i] = false; chosen_total -= 1} else {s.passage_ships[i] = true; chosen_total += 1}}
		if required {color := s.passage_ships[i] ? UX.good : UX.warn; rl.DrawRectangle(i32(row.x), i32(row.y + row.height - 2), i32(row.width), 2, color)}
		if s.passage_ships[i] &&
		   eligible &&
		   selected_count <
			   game.MAX_EXPEDITION_SHIPS {selected_indices[selected_count] = i; selected_count += 1}
	}
	if s.contract.purpose == .Ecological_Survey do draw_text("SURVEY SHIP · DOCUMENT AT STANDOFF RANGE; OTHER TASK GROUPS MUST CLOSE", 58, 526, TYPE_MICRO, UX.info)
	draw_text("FLEET CORRESPONDENCE ATLAS", 920, 190, TYPE_LABEL, UX.dim)
	if len(s.campaign.dark_fleet_atlas) == 0 do draw_text("No recovered correspondences.", 920, 214, TYPE_CAPTION, UX.dim)
	for discovery, i in s.campaign.dark_fleet_atlas[:min(len(s.campaign.dark_fleet_atlas), 5)] do draw_fmt(920, 214 + f32(i) * 21, TYPE_FINE, UX.info, "%s · %04d  →  GALAXY %d", game.dark_correspondence_name(s.campaign, discovery.door_id, discovery.galaxy_neighborhood, discovery.position_name_hash), discovery.door_id % 10000, discovery.galaxy_neighborhood)
	draw_text("RECORDED DARK ORGANISMS", 920, 350, TYPE_LABEL, UX.dim)
	if len(s.campaign.dark_organism_observations) == 0 do draw_text("No recovered observations.", 920, 374, TYPE_CAPTION, UX.dim)
	for observation, i in s.campaign.dark_organism_observations[:min(len(s.campaign.dark_organism_observations), 5)] do draw_fmt(920, 374 + f32(i) * 21, TYPE_FINE, UX.text, "%s · %d entries", game.dark_organism_name(observation.organism_id, observation.role), observation.manifestation_count)
	preview := game.dark_expedition_preview(
		s.campaign,
		&s.contract,
		selected_indices[:selected_count],
	); draw_text_wrapped(preview.message, R(470, 190, 420, 55), TYPE_BODY_COMPACT, preview.valid ? UX.info : UX.warn); draw_text_wrapped(preview.recommendation.reason, R(470, 250, 420, 48), TYPE_SMALL, UX.dim)
	selected_strategy := s.dark_strategy
	comparison := game.compare_dark_strategy(s.campaign, &s.contract, selected_strategy)
	draw_fmt(
		470,
		300,
		TYPE_CAPTION,
		comparison.difference_count == 0 ? UX.good : UX.warn,
		"%d differences from sponsor · %d resolved",
		comparison.difference_count,
		comparison.selected_estimate.evidence,
	)
	draw_text_wrapped(comparison.failure_mode, R(470, 318, 420, 20), TYPE_FINE, UX.dim)
	draw_fmt(
		470,
		340,
		TYPE_FINE,
		UX.info,
		"SELECTED · OBJECTIVE %.0f%% · SAFE %.0f%% · RECORD %.0f%%",
		comparison.selected_estimate.objective_rate * 100,
		comparison.selected_estimate.safety_rate * 100,
		comparison.selected_estimate.record_rate * 100,
	)
	if comparison.difference_count > 0 do draw_text("Departure record will note this departure from Compact guidance.", 470, 356, TYPE_FINE, UX.warn)
	strategy_y := f32(370)
	draw_fmt(470, strategy_y, TYPE_CAPTION, UX.text, "DEPTH  %v", selected_strategy.depth)
	if button(R(760, strategy_y - 7, 34, 25), "←") do s.dark_strategy.depth = game.Dark_Depth_Posture((int(selected_strategy.depth) + 2) % 3)
	if button(R(800, strategy_y - 7, 34, 25), "→") do s.dark_strategy.depth = game.Dark_Depth_Posture((int(selected_strategy.depth) + 1) % 3)
	strategy_y += 31
	draw_fmt(470, strategy_y, TYPE_CAPTION, UX.text, "COURSE  %v", selected_strategy.course)
	if button(R(760, strategy_y - 7, 34, 25), "←") do s.dark_strategy.course = game.Dark_Course_Priority((int(selected_strategy.course) + 2) % 3)
	if button(R(800, strategy_y - 7, 34, 25), "→") do s.dark_strategy.course = game.Dark_Course_Priority((int(selected_strategy.course) + 1) % 3)
	strategy_y += 31
	draw_fmt(470, strategy_y, TYPE_CAPTION, UX.text, "ECOLOGY  %v", selected_strategy.ecology)
	if button(R(760, strategy_y - 7, 34, 25), "←") do s.dark_strategy.ecology = game.Dark_Ecology_Posture((int(selected_strategy.ecology) + 2) % 3)
	if button(R(800, strategy_y - 7, 34, 25), "→") do s.dark_strategy.ecology = game.Dark_Ecology_Posture((int(selected_strategy.ecology) + 1) % 3)
	strategy_y += 31
	draw_fmt(470, strategy_y, TYPE_CAPTION, UX.text, "RELAY  %v", selected_strategy.relay)
	if button(R(760, strategy_y - 7, 34, 25), "←") || button(R(800, strategy_y - 7, 34, 25), "→") do s.dark_strategy.relay = game.Dark_Relay_Posture((int(selected_strategy.relay) + 1) % 2)
	strategy_y += 31
	draw_fmt(
		470,
		strategy_y,
		TYPE_CAPTION,
		UX.text,
		"WITHDRAWAL  %v",
		selected_strategy.withdrawal,
	)
	if button(R(760, strategy_y - 7, 34, 25), "←") do s.dark_strategy.withdrawal = game.Dark_Withdrawal_Margin((int(selected_strategy.withdrawal) + 2) % 3)
	if button(R(800, strategy_y - 7, 34, 25), "→") do s.dark_strategy.withdrawal = game.Dark_Withdrawal_Margin((int(selected_strategy.withdrawal) + 1) % 3)
	if button(
		R(470, 520, 280, 44),
		"AUTHORIZE DEPARTURE",
		preview.valid && available_count > 0,
		true,
	) {_ = game.apply_active_charter_to_passage_contract(s.campaign, &s.contract); ok, message := game.begin_passage(s.campaign, s.contract, selected_indices[:selected_count], &s.campaign.passage); if ok {_, _ = game.set_dark_strategy(s.campaign, &s.campaign.passage, s.dark_strategy); if s.campaign.guidance_step == 4 do s.campaign.guidance_step = 5; s.screen = .Passage}; s.status = message}
	bottom_rail(s, "COMMISSION A PURPOSE, SHIPS, AND A PUBLIC RETURN")
}

dark_shape_course :: proc(s: ^Ux_State, p: ^game.Passage, dz, dw: f64) {
	s.dark_waypoint_z = clamp(s.dark_waypoint_z + dz, -6, 6)
	s.dark_waypoint_w = clamp(s.dark_waypoint_w + dw, -6, 6)
	if s.dark_course_draft.waypoint_count < 3 do return
	a := s.dark_course_draft.waypoints[0].position
	b := s.dark_course_draft.waypoints[s.dark_course_draft.waypoint_count - 1].position
	mid := &s.dark_course_draft.waypoints[1].position
	for axis in 0 ..< 4 do mid[axis] = (a[axis] + b[axis]) * .5
	mid[2] += s.dark_waypoint_z
	mid[3] += s.dark_waypoint_w
}
draw_trade_dependency_record :: proc(
	s: ^Ux_State,
	x, y, width: f32,
	settlement: game.Settlement_ID = 0,
	max_rows: int = 2,
) {
	target := settlement
	if target == 0 {
		for e in s.campaign.settlement_economies.economies[:s.campaign.settlement_economies.count] do if e.active {target = e.settlement; break}
	}
	if target == 0 do return
	ledger, ok := game.settlement_ledger_view(s.campaign, target); if !ok do return
	label_caps("SETTLEMENT TRADE RECORD", x, y, UX.info)
	prefix := fmt.tprintf(
		"%s · %s ·",
		ledger.name,
		ledger.status,
	); draw_text(prefix, x, y + 18, TYPE_LABEL, UX.text); resource_x := x + measure_text(prefix, TYPE_LABEL).x + 8; resource_x += draw_resource_amount(resource_x, y + 18, ledger.stock.food, ICON_AGRICULTURE, UX.text, TYPE_LABEL) + 10; _ = draw_resource_amount(resource_x, y + 18, ledger.stock.goods, ICON_CONTAINER, UX.text, TYPE_LABEL)
	views: [dynamic]game.Trade_Dependency_View; defer delete(views); _ = game.trade_dependency_views(s.campaign, target, &views)
	if len(views) ==
	   0 {draw_text_wrapped("No named import or export dependency recorded.", R(x, y + 40, width, 36), TYPE_SMALL, UX.dim); return}
	row_height: f32 = 46
	for dependency, i in views[:min(len(views), max_rows)] {
		state := dependency.interrupted ? "CLOSED" : fmt.tprintf("%d%%", dependency.reliability)
		color := dependency.interrupted ? UX.warn : UX.info
		draw_text_fitted(
			fmt.tprintf(
				"%s · %s → %s · %s %d/%d · %s",
				dependency.route,
				dependency.supplier,
				dependency.consumer,
				dependency.resource,
				dependency.delivered,
				dependency.requested,
				state,
			),
			R(x, y + 40 + f32(i) * row_height, width, 20),
			TYPE_SMALL,
			color,
		)
		draw_text_fitted(
			fmt.tprintf(
				"E%03d → E%03d · %s · %s",
				dependency.origin_event,
				dependency.last_event,
				dependency.authority,
				dependency.guarantee,
			),
			R(x, y + 62 + f32(i) * row_height, width, 20),
			TYPE_SMALL,
			UX.dim,
		)
	}
}
