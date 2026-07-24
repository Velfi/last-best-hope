package game

// This is an automated preflight fixture, not a substitute for the interviews
// required by the playtest protocol. Its timestamps budget a 52-minute session.
PERSISTENT_FLEET_PLAYTEST_VERSION :: 1
PERSISTENT_FLEET_PLAYTEST_DURATION_SECONDS :: 52 * 60
PERSISTENT_FLEET_PLAYTEST_MAX_MOMENTS :: 12
PERSISTENT_FLEET_PLAYTEST_MAX_CAPTURES :: 128

Persistent_Fleet_Playtest_Moment_Kind :: enum {
	None,
	Community_Need,
	Contested_Undertaking,
	Prior_Ship_Bond,
	Passage_Evidence,
	Close_Combat_Interruption,
	Recoverable_Loss,
	Public_Account,
	Altered_Council_Choice,
}

Persistent_Fleet_Playtest_Moment :: struct {
	kind: Persistent_Fleet_Playtest_Moment_Kind,
	at_seconds: i32,
	causal_event: u64,
	caused_by_event: u64,
	ship, related_ship: Ship_ID,
	community: Community_ID,
	detail: string,
}

Persistent_Fleet_Playtest_Doctrine :: struct {
	name: string,
	conduct: Operation_Conduct,
	rescue: Rescue_Policy,
	withdrawal: Operation_Withdrawal,
	exposure: Operation_Exposure,
	ordnance: Operation_Ordnance_Authority,
	viable: bool,
}

Persistent_Fleet_Playtest_Fixture :: struct {
	version: u32,
	seed: u64,
	duration_seconds: i32,
	community_name, need_name: string,
	ship_names: [3]string,
	ship_ids: [3]Ship_ID,
	community_id: Community_ID,
	charter: Operation_Charter,
	authority: Operation_Authority,
	doctrines: [2]Persistent_Fleet_Playtest_Doctrine,
	moments: [PERSISTENT_FLEET_PLAYTEST_MAX_MOMENTS]Persistent_Fleet_Playtest_Moment,
	moment_count: int,
}

Persistent_Fleet_Capture_Kind :: enum {
	None,
	Choice,
	Screen_Visit,
	Attention_Duration,
	Dossier_Use,
	Default_Accepted,
	Causal_Link_Opened,
}

Persistent_Fleet_Playtest_Capture :: struct {
	kind: Persistent_Fleet_Capture_Kind,
	timestamp_seconds: i32,
	duration_seconds: i32,
	moment_event, linked_event: u64,
	ship: Ship_ID,
	value: i32,
}

Persistent_Fleet_Playtest_Log :: struct {
	seed: u64,
	captures: [PERSISTENT_FLEET_PLAYTEST_MAX_CAPTURES]Persistent_Fleet_Playtest_Capture,
	count: int,
}

Persistent_Fleet_Playtest_Preflight_Issue :: enum {
	None,
	Wrong_Duration,
	Missing_Scenario_Beat,
	Invalid_Causal_Order,
	Missing_Authority,
	Insufficient_Doctrines,
	Doctrine_Not_Distinct,
	Unnamed_Identity,
}

Persistent_Fleet_Playtest_Preflight :: struct {
	issues: [12]Persistent_Fleet_Playtest_Preflight_Issue,
	count: int,
	valid: bool,
}

persistent_fleet_fixture_add_moment :: proc(
	f: ^Persistent_Fleet_Playtest_Fixture,
	m: Persistent_Fleet_Playtest_Moment,
) {
	if f.moment_count >= len(f.moments) do return
	f.moments[f.moment_count] = m
	f.moment_count += 1
}

persistent_fleet_playtest_fixture :: proc(seed: u64 = 18150) -> Persistent_Fleet_Playtest_Fixture {
	f: Persistent_Fleet_Playtest_Fixture
	f.version = PERSISTENT_FLEET_PLAYTEST_VERSION
	f.seed = seed
	f.duration_seconds = PERSISTENT_FLEET_PLAYTEST_DURATION_SECONDS
	f.community_name = "Pale Harbor"
	f.need_name = "Evacuate the pressure-front watch"
	f.ship_names = {"Common Hearth", "Far Lantern", "Resolute"}
	f.ship_ids = {Ship_ID(101), Ship_ID(102), Ship_ID(103)}
	f.community_id = Community_ID(7)
	f.authority = {
		version = OPERATION_AUTHORITY_VERSION,
		undertaking_id = 51,
		objective = .Passage_Evacuate_Harbor,
		beneficiary = f.community_id,
		burden_ship = f.ship_ids[0],
		exposure = .Conservative,
		rescue = .Mutual_Aid,
		withdrawal = .Protected_Return,
		ordnance = .Defensive_Only,
		disclosure = .Accountable,
		deviation = .Explicit_Approval,
		reviewer = Institution_ID(2),
		compiled_event = 1003,
		valid = true,
	}
	f.authority.required_roles[int(Role.Hospital)] = true
	f.authority.protected_roles[int(Role.Archive)] = true
	f.charter = {
		version = COMPACT_CONTRACT_VERSION,
		undertaking = Compact_Undertaking_ID(51),
		call = Compact_Call_ID(50),
		hard_authority = f.authority,
		intent = "Evacuate the pressure-front watch.",
		intent_event = 1003,
		standing_doctrine = "Preserve return capability while attempting the evacuation.",
		compiled_event = 1003,
		valid = true,
	}
	f.doctrines = {
		{"Preserve and recover", .Preserve_Lives, .Absolute_Duty, .Protected_Return, .Conservative, .Defensive_Only, true},
		{"Complete with bounded loss", .Mission_First, .Mutual_Aid, .Mandatory_Threshold, .Mission_Critical, .Confirmed_Targets, true},
	}
	persistent_fleet_fixture_add_moment(&f, {.Community_Need, 60, 1001, 0, f.ship_ids[0], 0, f.community_id, "Pale Harbor requests evacuation before the pressure front."})
	persistent_fleet_fixture_add_moment(&f, {.Prior_Ship_Bond, 240, 1002, 980, f.ship_ids[0], f.ship_ids[1], f.community_id, "Common Hearth and Far Lantern retain their shared-passage bond."})
	persistent_fleet_fixture_add_moment(&f, {.Contested_Undertaking, 480, 1003, 1001, f.ship_ids[0], 0, f.community_id, "Two institutions contest who may accept exposure."})
	persistent_fleet_fixture_add_moment(&f, {.Passage_Evidence, 1080, 1004, 1003, f.ship_ids[1], 0, f.community_id, "Far Lantern authenticates the harbor route evidence."})
	persistent_fleet_fixture_add_moment(&f, {.Close_Combat_Interruption, 1560, 1005, 1004, f.ship_ids[2], f.ship_ids[0], f.community_id, "A close contact interrupts the return route."})
	persistent_fleet_fixture_add_moment(&f, {.Recoverable_Loss, 1980, 1006, 1005, f.ship_ids[2], 0, f.community_id, "Resolute withdraws damaged and enters scheduled recovery."})
	persistent_fleet_fixture_add_moment(&f, {.Public_Account, 2520, 1007, 1006, f.ship_ids[0], f.ship_ids[2], f.community_id, "The Compact reports the rescue, damage, and uncommunicated deviation."})
	persistent_fleet_fixture_add_moment(&f, {.Altered_Council_Choice, 3000, 1008, 1007, f.ship_ids[0], f.ship_ids[1], f.community_id, "The prior account changes the later allocation choice."})
	return f
}

persistent_fleet_preflight_add :: proc(
	p: ^Persistent_Fleet_Playtest_Preflight,
	issue: Persistent_Fleet_Playtest_Preflight_Issue,
) {
	if p.count < len(p.issues) {p.issues[p.count] = issue; p.count += 1}
}

persistent_fleet_playtest_preflight :: proc(
	f: ^Persistent_Fleet_Playtest_Fixture,
) -> (p: Persistent_Fleet_Playtest_Preflight) {
	if f == nil {persistent_fleet_preflight_add(&p, .Missing_Scenario_Beat); return}
	if f.duration_seconds < 45 * 60 || f.duration_seconds > 60 * 60 do persistent_fleet_preflight_add(&p, .Wrong_Duration)
	if f.community_name == "" || f.need_name == "" ||
	   f.ship_names[0] == "" || f.ship_names[1] == "" || f.ship_names[2] == "" {
		persistent_fleet_preflight_add(&p, .Unnamed_Identity)
	}
	if !f.authority.valid do persistent_fleet_preflight_add(&p, .Missing_Authority)
	seen: [9]bool
	prior_time: i32 = -1
	for moment in f.moments[:f.moment_count] {
		seen[int(moment.kind)] = true
		if moment.at_seconds <= prior_time || moment.caused_by_event >= moment.causal_event {
			persistent_fleet_preflight_add(&p, .Invalid_Causal_Order)
		}
		prior_time = moment.at_seconds
	}
	for kind := int(Persistent_Fleet_Playtest_Moment_Kind.Community_Need);
	    kind <= int(Persistent_Fleet_Playtest_Moment_Kind.Altered_Council_Choice);
	    kind += 1 {
		if !seen[kind] {persistent_fleet_preflight_add(&p, .Missing_Scenario_Beat); break}
	}
	if !f.doctrines[0].viable || !f.doctrines[1].viable do persistent_fleet_preflight_add(&p, .Insufficient_Doctrines)
	if f.doctrines[0].conduct == f.doctrines[1].conduct &&
	   f.doctrines[0].rescue == f.doctrines[1].rescue &&
	   f.doctrines[0].withdrawal == f.doctrines[1].withdrawal {
		persistent_fleet_preflight_add(&p, .Doctrine_Not_Distinct)
	}
	p.valid = p.count == 0
	return
}

persistent_fleet_capture :: proc(
	log: ^Persistent_Fleet_Playtest_Log,
	capture: Persistent_Fleet_Playtest_Capture,
) -> bool {
	if log == nil || capture.kind == .None || capture.timestamp_seconds < 0 ||
	   log.count >= len(log.captures) {
		return false
	}
	if log.count > 0 && capture.timestamp_seconds < log.captures[log.count - 1].timestamp_seconds do return false
	log.captures[log.count] = capture
	log.count += 1
	return true
}
