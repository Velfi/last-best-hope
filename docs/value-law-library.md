# Value-to-law library

## Purpose

This document completes the authored design for all eight values available
during civilization setup. It is the content companion to
[`values-become-law.md`](values-become-law.md), which defines the shared rule,
case, interface, persistence, and validation framework.

Every value follows the same contract:

```text
public claim
→ costly test
→ optional precedent
→ later hard case
→ compliance, bounded compliance, exception, or departure
→ constitutional review
→ changed future procedure
```

Values are claims about obligations. Precedents are rules created by recorded
actions. A civilization may claim a value without ever enacting it, enact a rule
that qualifies it, or establish a contradictory rule through later conduct.

## Authoritative value identity

Setup values currently exist only as names in two choice tables. Give them
stable identities so rules do not depend on display strings or array positions:

```odin
Value_Kind :: enum {
    No_One_Left_Behind,
    Truth_Before_Comfort,
    Consent_To_Settle,
    Shelter_Is_Sacred,
    Shared_Authority,
    Open_Archives,
    The_Fleet_Endures,
    Every_Home_Is_Free,
}

Value_Status :: enum {Claimed, Tested, Embodied, Compromised, Renounced}

Civilization_Value :: struct {
    kind:              Value_Kind,
    status:            Value_Status,
    claimed_event:     u64,
    last_test_event:   u64,
    tests:             i32,
    consistent_tests:  i32,
    contradictions:    i32,
    enacted_precedent: Precedent_ID,
}
```

`Value_Status` summarizes recorded conduct; it does not measure virtue.

- **Claimed:** selected during setup and not yet materially tested.
- **Tested:** at least one costly decision cited the value.
- **Embodied:** an active precedent derived from the value has survived a later
  application or review.
- **Compromised:** a related constitutional case remains unresolved or a
  contradiction stands without replacement.
- **Renounced:** a review explicitly replaced the value's derived rule with an
  incompatible precedent.

Status transitions are event-derived and deterministic. One favorable action
cannot erase a contradiction; later review or conduct can change the status
while preserving both records.

## Value and precedent taxonomy

Not every precedent is itself a civilizational value. Several are procedural
answers produced when values collide.

| Setup value | Primary precedent | Possible qualified or opposing precedents |
|---|---|---|
| No One Left Behind | No One Left Behind | Emergency Command |
| Truth Before Comfort | Accountable Disclosure (new) | Protective Withholding (new), Open Archives |
| Consent to Settle | Consent of the Settled | Council Assignment, Proportionate Asset Division |
| Shelter Is Sacred | Right of Refuge (new) | Emergency Admission (new), Closed Berths (new) |
| Shared Authority | Shared Authority | Emergency Command, Ship Sovereignty |
| Open Archives | Open Archives | Custodial Archives (new), Founding Independence |
| The Fleet Endures | Continuity of the Fleet (new) | Right of Departure, Continuing Fleet Jurisdiction |
| Every Home Is Free | Founding Independence | Continuing Fleet Jurisdiction, Council Assignment |

Existing settlement outcomes remain procedural precedents:

- **Right of Departure** answers whether ships may refuse permanent departure.
- **Council Assignment** records compulsory allocation authority.
- **Proportionate Asset Division** records a negotiated or engineered division.
- **Continuing Fleet Jurisdiction** records authority retained after settlement.
- **Ship Sovereignty** records operational authority held by a ship.
- **Adaptation Accepted** records a boundary decision about transformed people;
  it may derive from several values and is not a setup value by itself.

This separation prevents a settlement procedure from retroactively pretending
to be a founding belief.

## Shared content constraints

- The first test must place a named ship, community, institution, archive,
  promise, opportunity, or future capability at material risk.
- A value never supplies a continuous numeric bonus.
- At least two responses must be viable in a normal campaign state.
- Every hard case must put the value in tension with another legitimate value or
  survival requirement.
- Exceptions resolve the immediate problem and create a case; they never delete
  the applicable rule.
- Review outcomes change procedures, ownership, scope, or authority—not merely
  Cohesion.
- Each rule must influence at least three later decision families.
- Every generated record states action and consequence without certifying
  motive or moral meaning.

## 1. No One Left Behind

### Claim

> Distress calls create a public expectation of rescue.

### Law

**No One Left Behind:** attempt recovery when a protected ship or community can
still be reached.

### Complete chain

The enactment test, degrading-correspondence hard case, response matrix, review,
and future reuse are defined in the vertical slice in
[`values-become-law.md`](values-become-law.md#no-one-left-behind-vertical-slice).

### Distinct interaction

Its central tension is care versus preservation of the means to care later.
Review can affirm an absolute attempt, exempt fleet-collapse risk, or limit the
duty to existing protection relationships. It changes rescue responses, combat
recovery corridors, and settlement-defense obligations.

## 2. Truth Before Comfort

### Claim

> Leaders are expected to disclose dangerous knowledge.

The value concerns truthful public accounts of material danger. It does not
require immediate publication of every private record, technical detail, or
uncertain hypothesis.

### Enactment test: the contaminated route report

A survey ship discovers that a frequently used correspondence is degrading. A
public warning will strand a distant convoy until another route is found and may
trigger rationing. Withholding the report preserves the convoy schedule while
placing it at a bounded, evidenced risk.

- **Publish the complete finding:** stop traffic and expose the uncertainty.
- **Publish the danger and withhold exploitable coordinates:** stop traffic but
  restrict technical details to navigators.
- **Commission independent review:** create a dated promise; limited traffic
  continues under a disclosed risk band.
- **Restrict the report:** preserve the schedule and record who received it.

The first two can enact **Accountable Disclosure**. Independent review can enact
it only if the result is published by the promised deadline.

### Active rule

**Accountable Disclosure:** publish evidence of a material danger before asking
people to accept exposure to it.

Interpretations:

- `Material_Risk_Before_Exposure`
- `Verified_Risk_Before_Exposure`
- `Public_Finding_Protected_Method`

### Hard case: the habitable world's biosphere

A candidate home is viable, but evidence of indigenous biology remains
disputed. Full disclosure may collapse a settlement mandate and leave the fleet
without sufficient reserves for another search. The player can:

| Response | Classification | Persistent consequence |
|---|---|---|
| Publish data and dissenting analysis | Complies | Mandate recalculated from the complete record |
| Disclose the risk band; seal dangerous methods | Bounded compliance | Custodial restriction and independent review |
| Delay publication under emergency authority | Exception | Accountability case and dated disclosure duty |
| Certify the world without the evidence | Departure | Contradicted founding account and exposed settlement claim |

### Review futures

- **Affirm material-risk disclosure:** affected people must receive bounded risk
  before consent, even when evidence is disputed.
- **Require verification:** disputed evidence may be held until independent
  review, but exposure cannot exceed a typed threshold during review.
- **Protect methods, publish findings:** create a stable distinction between
  public danger and restricted operational detail.
- **Adopt Protective Withholding:** designated institutions may restrict danger
  reports; affected communities gain later review rights but not prior access.

### Future systems changed

- Passage-risk authorization and mandate disclosure terms.
- Candidate-home and biosphere settlement consent.
- Contested expedition debriefs and archive revelations.
- Institutional legitimacy when authoritative and public accounts diverge.

### Failure risks

Do not make publication always correct by attaching a free legitimacy reward.
Information can cause real delays, strategic exposure, and lost opportunities.
Do not surprise the player with a risk the simulation already knew but the
interface concealed; the choice must show that disclosure affects consent and
operations.

## 3. Consent to Settle

### Claim

> No community should be planted without meaningful consent.

Consent applies to the people and ships being permanently transferred. It does
not grant every fleet resident a veto over other communities' departure.

### Enactment test: the first viable but narrow home

The first candidate can support one community if it departs soon. Its preferred
community is divided, and a delay will increase fleet crowding. The player can:

- **Hold a participatory mandate:** spend attention and disclose the complete
  destination record.
- **Permit voluntary opt-in:** accept a smaller, less viable founding package.
- **Negotiate conditions:** reserve mobility, archive access, and review rights;
  create a deadline.
- **Assign a package:** preserve viability through council authority despite
  measured opposition.

The first three can enact **Consent of the Settled** when participation and
information floors are met. Assignment enacts **Council Assignment** instead.

### Active rule

**Consent of the Settled:** permanent settlement requires a recorded mandate
from each transferred community and ship constituency.

Interpretations:

- `Participatory_Majority_With_Exit`
- `Voluntary_Opt_In`
- `Supermajority_For_Irreversible_Transfer`

### Hard case: the failing habitat fleet

A habitat ship will become uninhabitable before another destination is likely.
The only current home can receive its population, but its mandate narrowly
opposes settlement and remaining aboard threatens dependents who did not vote.

| Response | Classification | Persistent consequence |
|---|---|---|
| Repair and rerun the mandate | Complies | Fleet bears repair and delay cost |
| Settle volunteers; redistribute dependents with review | Bounded compliance | Split community and mobility promise |
| Assign evacuation settlement under emergency power | Exception | Coercion case and founding grievance |
| Transfer the full population by council order | Departure | Council Assignment and rival authority pressure |

### Review futures

- **Affirm participatory consent:** dependents receive representation through a
  named guardian institution; emergency transfer remains reviewable.
- **Narrow to voluntary opt-in:** only affirmative participants depart; the
  fleet retains responsibility for those who remain.
- **Adopt emergency habitation authority:** council assignment is lawful when a
  typed survival threshold is crossed, with mobility and later review required.
- **Replace with collective assignment:** settlement packages are fleet-level
  decisions; communities retain charter participation but not refusal.

### Future systems changed

- Settlement proposal participation and validity.
- Community relocation after ship loss.
- Adaptation programs required for a marginal world.
- Return migration and civilian-mobility obligations.

### Failure risks

Consent cannot be represented by a single hidden percentage. Show participation,
support, opposition, information confidence, and which constituencies are bound.
Avoid making emergency assignment the optimal way to obtain larger colonies;
coercive scale must create durable political and settlement consequences.

## 4. Shelter Is Sacred

### Claim

> Refuge is owed even when it is costly.

This differs from No One Left Behind. Rescue concerns recovering people already
in danger; refuge concerns admitting and sustaining people who reach the fleet,
including strangers and rivals.

### Enactment test: the unregistered convoy

A convoy arrives with insufficient food, damaged life support, and no recognized
political status. Admission will cross the fleet's habitat reserve and require
either rationing or an accelerated settlement. The player can:

- **Open fleet berths:** distribute the arrivals among consenting communities.
- **Establish a provisional refuge:** convert a task-capable ship and create a
  supply obligation.
- **Offer escorted passage:** provide reserves and route information without
  admission.
- **Deny entry:** preserve fleet capacity and leave the convoy autonomous.

The first two can enact **Right of Refuge**. Escorted passage records aid but
does not establish admission law.

### Active rule

**Right of Refuge:** a reachable population facing immediate displacement is
owed temporary safe berth and a status review.

Interpretations:

- `Temporary_Berth_And_Review`
- `Admission_Up_To_Habitat_Floor`
- `Aid_Or_Berth_When_Aid_Is_Viable`

### Hard case: carriers from a hostile settlement

A settlement that previously seized fleet equipment sends civilians during an
epidemic. Admission threatens quarantine capacity; refusal may return them to a
government using the fleet's earlier actions as justification.

| Response | Classification | Persistent consequence |
|---|---|---|
| Quarantine and admit | Complies | Hospital capacity and berth commitments |
| Receive the most exposed; supply the remaining convoy | Bounded compliance | Selection claim and continuing aid promise |
| Close berths under health emergency | Exception | Refuge case and medical-authority review |
| Return the convoy to the settlement | Departure | Closed Berths precedent and settlement grievance |

### Review futures

- **Affirm temporary refuge:** admission lasts until a public status decision;
  distribution among communities still requires local consent.
- **Establish a capacity floor:** the fleet must preserve named refuge berths but
  owes aid rather than admission beyond that floor.
- **Recognize quarantine exception:** medical authority can delay entry while
  providing external support and periodic review.
- **Adopt Closed Berths:** admission becomes discretionary; rescue and escorted
  aid duties remain separate.

### Future systems changed

- Refugee community creation and fleet habitat allocation.
- Epidemic and quarantine responses.
- External-polity diplomacy, rescued enemies, and prisoner release.
- Settlement migration and requests for return passage.

### Failure risks

Do not collapse newcomers into population and Cohesion totals. They retain an
origin, ships, claims, status, and relationships. Avoid using random hidden
disease as a punishment for generosity; quarantine risk must be bounded and
affected by preparation.

## 5. Shared Authority

### Claim

> Communities expect a voice in fleet command.

Shared authority concerns who may bind the fleet. It does not require every
operational order to become a vote.

### Enactment test: allocation after the Loss

Two communities require the same repair capacity before the first Passage. The
player can:

- **Seat community delegates:** publish priorities and divide the schedule.
- **Create a rotating council:** assign this decision to a representative body
  with a review season.
- **Delegate by expertise:** let the relevant institution decide under a public
  mandate.
- **Retain central command:** choose immediately and record the imposed burden.

The first three can enact **Shared Authority**, with different
interpretations. Central command can enact **Emergency Command** if a declared
survival threshold exists.

### Active rule

**Shared Authority:** decisions that permanently bind a community require its
representation or a previously delegated public mandate.

Interpretations:

- `Affected_Communities_Represented`
- `Rotating_Council_Jurisdiction`
- `Institutional_Delegation_With_Review`

### Hard case: a decision window shorter than deliberation

A Passage correspondence is collapsing. One task group can leave before the
council completes debate, but its departure consumes reserves promised to a
community. The player can:

| Response | Classification | Persistent consequence |
|---|---|---|
| Let the council deadline expire | Complies | Opportunity may close; promise remains funded |
| Use the sponsor's delegated mandate | Bounded compliance | Mandate consumed and later report required |
| Invoke emergency command | Exception | Constitutional debt and authority case |
| Order departure without authority | Departure | Ship or command rivalry and disputed mandate |

### Review futures

- **Affirm affected representation:** only directly bound constituencies require
  seats; operational command remains delegated.
- **Adopt rotating council jurisdiction:** categories of decisions belong to
  named councils with scheduled renewal.
- **Broaden institutional delegation:** expertise can bind the fleet inside a
  public mandate and resource ceiling.
- **Replace with Emergency Command:** central command may act first; review and
  compensation follow rather than prior consent.

### Future systems changed

- Council composition and proposal support.
- Passage and combat mandate authorization.
- Allocation of shortages and emergency projects.
- Settlement charter and institution-custody decisions.

### Failure risks

Do not turn representation into a flat Cohesion bonus or an extra confirmation
click. It must alter who can authorize which action, the time required, and whose
trust is placed at risk. Late-game scale requires delegation and standing
mandates rather than more votes.

## 6. Open Archives

### Claim

> Knowledge belongs to the whole diaspora.

Open Archives concerns durable access and copying. Truth Before Comfort concerns
disclosure before exposure. A fleet can practice one without the other.

### Enactment test: the last complete archive

The only complete technical corpus can be copied across the fleet, but doing so
consumes scarce compute and places restricted biological or security records in
several custodians' hands. The player can:

- **Create public redundant copies:** spend compute and accept custody risk.
- **Create community copies with sealed personal records:** broaden technical
  access while preserving typed restrictions.
- **License queries through one custodian:** preserve integrity but maintain
  dependency.
- **Keep the archive under fleet command:** preserve control and a single point
  of failure.

The first two can enact **Open Archives**. Licensed access can enact
**Custodial Archives**.

### Active rule

**Open Archives:** non-personal knowledge held for the diaspora must be
discoverable and reproducible by every recognized community and settlement.

Interpretations:

- `Public_Copy_With_Personal_Seals`
- `Recognized_Custodian_Copies`
- `Open_Queries_And_Emergency_Replication`

### Hard case: a settlement's dangerous discovery

An independent settlement develops a navigation method that could reopen a lost
route and could also destabilize active correspondences. It offers the fleet
access only if the method remains under local custody.

| Response | Classification | Persistent consequence |
|---|---|---|
| Fund safe replication to all custodians | Complies | Compute cost and distributed hazard-control duty |
| Publish findings; restrict executable method | Bounded compliance | Reviewable method seal |
| Accept exclusive settlement custody temporarily | Exception | Archive-access case and dependency |
| Seize or suppress the record | Departure | Custody conflict and settlement authority claim |

### Review futures

- **Affirm reproducibility:** methods must be copyable after a bounded safety
  review; findings remain immediately discoverable.
- **Recognize custodial copies:** several named institutions hold full records;
  communities receive access but not unrestricted replication.
- **Separate findings from executable methods:** public conclusions, controlled
  dangerous procedure, and mandatory independent verification.
- **Defer to founding independence:** settlements own new records but owe access
  only through negotiated treaties.

### Future systems changed

- Archive copying, loss resilience, and settlement archive establishment.
- Application of discoveries and substitution for missing specialists.
- Accountability reviews and contested public records.
- Federation eligibility and inter-settlement knowledge exchange.

### Failure risks

Open access must cost capacity and create custody questions; otherwise it is an
automatic research bonus. Do not represent knowledge as a spendable global
currency. Preserve the distinction among record existence, access, verification,
and practical capability to apply it.

## 7. The Fleet Endures

### Claim

> Fragmentation is treated as an existential failure.

The value protects continuity of a traveling polity, not maximal ship count.
Founding homes can be compatible with it if enough authority, capability, and
shared commitments remain to constitute a fleet.

### Enactment test: the first secession demand

A task group wants to remain at a defensible harbor with its ships and archives.
Allowing it weakens Passage capability; compelling return risks conflict. The
player can:

- **Negotiate a continuing fleet compact:** permit local residence while
  retaining shared Passage and rescue commitments.
- **Rotate ships and personnel:** preserve fleet functions while accepting a
  smaller local community.
- **Recognize independent departure:** release ships, people, and assets.
- **Order the task group to return:** assert central continuity.

The first two can enact **Continuity of the Fleet**. Independent departure can
enact **Right of Departure**. An enforced return may enact **Continuing Fleet
Jurisdiction** or **Emergency Command**, depending on authority.

### Active rule

**Continuity of the Fleet:** no permanent departure may remove the fleet's last
active capability for navigation, sustenance, repair, refuge, or collective
authority without a replacement or continuing compact.

Interpretations:

- `Essential_Capabilities_Preserved`
- `Compact_Allows_Distributed_Fleet`
- `Central_Command_Must_Persist`

### Hard case: the final functioning foundry

The last foundry ship's community has a strong mandate to settle. Keeping it
preserves fleet repair; releasing it creates the best current home and may end
the fleet's ability to continue safely.

| Response | Classification | Persistent consequence |
|---|---|---|
| Build replacement capacity before departure | Complies | Delay and material cost |
| Divide the foundry and establish a support compact | Bounded compliance | Reduced capacity and settlement obligation |
| Retain the ship under emergency continuity power | Exception | Autonomy case and community grievance |
| Release the ship without replacement | Departure | Fleet transformation or dissolution risk |

### Review futures

- **Affirm essential capabilities:** define continuity by a visible set of
  recoverable fleet functions, not ship ownership.
- **Recognize a distributed fleet:** harbors and settlements can satisfy
  continuity through binding support and Passage compacts.
- **Require central command continuity:** key command and navigation capability
  cannot permanently depart while travelers remain.
- **Accept transformation:** supersede the rule when the traveling fleet has
  become a harbor network, federation, or chosen final community.

### Future systems changed

- Settlement-package validity and essential-role replacement.
- Ship departure, stranded task-group return, and fleet transformation.
- Institution relocation and continuity plans.
- Ending eligibility for Nomadic Fleet, Harbor Network, Federation, and
  Fragmented Survival.

### Failure risks

Do not make this value a prohibition on successful settlement. The player must
be able to fulfill it through replacement, distributed support, or deliberate
transformation. A visible capability forecast must distinguish “the fleet
changes form” from “the simulation abruptly ends.”

## 8. Every Home Is Free

### Claim

> Settlements must become sovereign rather than possessions.

Sovereignty concerns authority after founding. It does not cancel negotiated
debts, mutual-defense treaties, archive access, or the right of individuals to
leave.

### Enactment test: the first charter

The fleet provides most of a settlement's ships, archives, and reserves. The
player must decide whether those contributions preserve command authority.

- **Grant founding sovereignty:** transfer charter authority with the package.
- **Create an independence timetable:** retain bounded transitional authority
  with a fixed review and transfer date.
- **Establish a federation compact:** share only enumerated Passage, defense,
  and archive powers.
- **Retain fleet jurisdiction:** treat the settlement as a dependent station.

The first can enact **Founding Independence**. The second can enact it when the
transfer occurs. The third records both founding independence and a typed
compact. The fourth enacts **Continuing Fleet Jurisdiction**.

### Active rule

**Founding Independence:** a viable settlement controls its charter, local
institutions, resources, and later political alignment after founding.

Interpretations:

- `Immediate_Charter_Sovereignty`
- `Timed_Transition_With_Review`
- `Enumerated_Federal_Powers`

### Hard case: a settlement breaks its rescue compact

An independent home refuses a fleet rescue request despite a continuing treaty.
The fleet can impose compliance using ships and infrastructure originally
provided at founding, but doing so contradicts local sovereignty.

| Response | Classification | Persistent consequence |
|---|---|---|
| Invoke treaty arbitration | Complies | Delay and uncertain rescue support |
| Suspend shared benefits inside the compact | Bounded compliance | Relationship loss and review |
| Assume temporary control under emergency treaty power | Exception | Sovereignty case and occupation claim |
| Reassert permanent fleet jurisdiction | Departure | Rival polity or dependent settlement state |

### Review futures

- **Affirm immediate sovereignty:** enforcement is limited to negotiated
  remedies; the fleet cannot reclaim transferred institutions or ships.
- **Adopt timed transition:** new settlements receive a visible period of shared
  administration followed by automatic sovereignty.
- **Define enumerated federal powers:** only named defense, Passage, archive, or
  mobility obligations can be enforced collectively.
- **Restore continuing jurisdiction:** some settlements remain fleet-governed
  stations; affected communities gain representation and later secession paths.

### Future systems changed

- Settlement charter, liberty, and post-founding institutional control.
- Treaty enforcement, rescue obligations, trade dependency, and sanctions.
- Settlement possession of archives and ships.
- Federation, harbor-network, and rival-polity formation.

### Failure risks

Do not make sovereignty equivalent to a permanent positive relationship. Free
homes may refuse requests, criticize the fleet, diverge culturally, or become
rivals. Likewise, continuing jurisdiction must create actual duties and
representation rather than merely reducing a liberty score.

## Cross-value collisions

Hard cases should preferentially test two claimed values rather than opposing a
value with a plainly selfish option. The interface names both applicable rules
and explains which part of each response satisfies or contradicts them.

| Collision | Representative hard case | Genuine tradeoff |
|---|---|---|
| Rescue × Fleet continuity | Risk the only archive ship to recover an expedition | Present lives versus future rescue capacity |
| Truth × Consent | Disputed biosphere evidence before settlement | Informed mandate versus a closing habitation window |
| Refuge × Consent | Distribute refugees among unwilling host communities | Admission duty versus local authority over berths |
| Shared authority × Fleet continuity | Council delay during a collapsing route | Legitimate authorization versus irreversible opportunity |
| Open archives × Free homes | Settlement claims custody of a dangerous discovery | Diaspora access versus local sovereignty |
| Consent × Fleet continuity | Last essential ship votes to settle | Self-determination versus survival of those continuing |
| Free homes × Rescue | Sovereign settlement refuses a rescue compact | Independence versus an accepted continuing duty |
| Truth × Fleet continuity | Revealing a route failure may fragment the fleet | Accountable exposure versus coordinated survival |

When two active precedents conflict, neither disappears. The application result
can classify one action as complying with one and excepting the other. A single
constitutional case records both rule IDs and identifies the decision that
forced the collision.

## Adaptation Accepted as a derived law

**Adaptation Accepted** remains an existing precedent but should arise from a
cross-value test rather than a ninth setup value.

Representative case: a community must adopt heritable biological changes to
inhabit the only viable home.

- Consent to Settle asks whether the affected community authorized the change.
- Truth Before Comfort asks whether uncertainty and irreversible effects were
  disclosed.
- Every Home Is Free asks whether the resulting population controls its future
  biology and charter.
- The Fleet Endures may oppose losing an essential community or capability.

Possible interpretations:

- `Community_Authorized_Heritable_Change`
- `Individual_Opt_In_With_Unmodified_Lineage_Preserved`
- `Emergency_Adaptation_With_Descendant_Review`

The law changes later habitability, medicine, identity disputes, family
mobility, and relations between adapted settlements and the traveling fleet.

## Content scheduling

A standard chronicle begins with two claimed values. Do not schedule eight
independent value arcs.

- Surface the first material test for one claimed value during seasons 1–4.
- Prefer a test involving both claimed values during seasons 4–10.
- Allow unclaimed values to appear as positions held by communities or
  institutions, but do not treat them as civilization-wide expectations.
- Keep no more than one unresolved value test and three unresolved
  constitutional cases.
- After a value becomes Embodied, favor hard cases and cross-value collisions
  over repeated enactment opportunities.
- A standard chronicle should usually enact or explicitly reject two to four
  value-derived laws, not the entire library.

## Founding-decision integration

Setup currently chooses two values and independently chooses one of four
founding precedents. Replace that independent precedent picker with a founding
test generated from the selected value pair.

The player still makes one pivotal evacuation decision, but its options are
derived from both claims and the Loss. For example:

- Truth Before Comfort × The Fleet Endures after a civil war asks whether to
  publish evidence that some departing ships were deliberately excluded.
- Shelter Is Sacred × Shared Authority after an expulsion asks who can admit a
  late refugee convoy when berths are already allocated.
- Consent to Settle × Every Home Is Free asks whether evacuation communities
  may refuse assigned destination ships and retain post-arrival sovereignty.

The chosen response may enact a primary precedent, record an isolated emergency
decision, or leave a referred question for the first council. It must cite at
least one selected value. The unchosen value remains Claimed rather than being
treated as contradicted unless the decision directly applied to it.

For save compatibility, existing founding precedents remain valid historical
records even when they do not derive from a selected value. They receive no
invented value cause. The civilization record labels them **Founding rule** and
keeps the selected values separately Claimed.

## Interface additions

### Setup

For each selected value show:

- the public claim;
- two representative pressures likely to test it;
- the statement: “This is an expectation, not a passive bonus.”

Do not reveal a future authored event or promise that every value will be tested.

### Civilization record

Show the two claimed values separately from enacted precedents:

```text
CLAIMED VALUES
Truth Before Comfort · Tested · last cited E042
Every Home Is Free · Embodied · Founding Independence E071

ACTIVE RULES
Accountable Disclosure · contested · review S19
Founding Independence · active
```

Selecting a value shows its claim, tests, consistent applications,
contradictions, and derived laws. Selecting a law shows its authoritative scope
and causal record.

### Decision preview

When values collide, each response lists both classifications:

```text
PUBLISH THE COMPLETE FINDING
Truth Before Comfort · complies
Consent to Settle · reopens the mandate
Immediate: settlement delayed; 18 reserve-years forecast
```

Values never add hidden utility or success chance.

## AI requirements

Bot profiles receive value postures from the actual civilization setup rather
than fixed profile stereotypes. Profiles determine how costs and uncertainty
are evaluated; claimed values increase the cost of unexplained contradiction,
not the raw reward for clicking a matching option.

A bot may contradict a claimed value when:

- compliance is impossible;
- its forecast crosses a profile-specific survival or capability floor;
- compliance would contradict another active rule it ranks as more directly
  applicable; or
- a bounded exception produces higher long-horizon utility.

The action trace records immediate utility, value classifications, applicable
rules, authority, expected case cost, and rejected-action reasons.

## Library validation

### Per-value scenario requirement

Each value ships with four deterministic fixtures:

1. compliance is affordable;
2. only bounded compliance is affordable;
3. an authorized exception is available;
4. contradiction is the only survivable response.

Every fixture must preserve at least one future recovery path and produce a
navigable causal chain.

### Cross-value matrix

Exercise all 28 unordered pairs of setup values. A pair passes when:

- both values can affect one shared decision without hidden modifiers;
- at least two responses are viable in some fixed scenario;
- choosing either priority produces different persistent state;
- the application result is independent of rule-storage order;
- save/load preserves the same classifications and next review.

Not every pair needs bespoke narrative content. Reuse systemic contexts where
the causal fit is direct, and mark pairs that require only independent parallel
applications rather than manufacturing a false conflict.

### Campaign gates

Across matched campaigns grouped by selected value pair:

- at least 70% materially test one selected value by season 12;
- at least 60% materially test both by season 24;
- at least 80% of enacted rules receive a later application;
- every value produces at least three review outcomes in aggregate;
- no value-matching response exceeds 70% of comparable affordable choices with
  the existing five-opportunity evidence floor;
- selected value pairs produce measurably different law, case, settlement,
  authority, archive, or relationship states without requiring different random
  worlds;
- win rate is reported by value pair, and no pair falls outside the accepted
  difficulty band solely because its value tests remove all recovery tools.

These are structural alarms until human testing establishes final rates.

### Human tests

Players should be able to distinguish:

- No One Left Behind from Shelter Is Sacred;
- Truth Before Comfort from Open Archives;
- Consent to Settle from Every Home Is Free;
- Shared Authority from The Fleet Endures.

Target: four of five first-use testers correctly identify which value governs a
representative decision and explain the immediate tradeoff. If two values are
repeatedly confused, repair their affected actors and procedures before adding
more explanatory prose.

## Delivery order

1. Add stable value identity and event-derived status; replace the independent
   founding-precedent picker with a selected-pair founding test.
2. Complete No One Left Behind through the shared framework.
3. Add Truth Before Comfort and Open Archives together to prove the distinction
   between disclosure and access.
4. Add Consent to Settle and Every Home Is Free through the existing settlement
   proposal system.
5. Add Shared Authority and The Fleet Endures through mandates, councils, ship
   departure, and essential-capability forecasts.
6. Add Shelter Is Sacred after refugee communities, temporary berth allocation,
   and quarantine can persist independently.
7. Add Adaptation Accepted as the first derived cross-value law.
8. Run the 28-pair matrix, bot campaigns, and first-use comprehension tests
   before expanding the value list.

## Definition of library completeness

The value library is complete when every setup value has a materially costly
test, a typed derived law, a later hard case, four playable response classes,
at least three mechanically distinct review futures, and three downstream
system consumers. Claimed values, enacted rules, and procedural precedents are
displayed separately; all decisions retain causal provenance; all eight values
work in every selected pair without order-dependent resolution; and players can
distinguish the paired concepts without relying on hidden bonuses or moralizing
summary text.
