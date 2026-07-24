# Values Become Law

## Feature statement

Civilizational values become binding precedents when the fleet acts on them at a
pivotal moment. Later decisions cite those precedents, show the lawful default,
and record compliance or contradiction. Contradictions remain playable: they
create a named constitutional case that the fleet must eventually affirm,
narrow, replace, or leave contested.

The feature completes this causal loop:

```text
claimed value
→ costly action under pressure
→ enacted precedent
→ changed default in a later decision
→ compliance or recorded exception
→ institutional and historical response
→ revised future rule
```

The first complete content chain is **No One Left Behind**. The framework also
supports the existing authority, archive, adaptation, consent, departure, asset
division, and settlement-jurisdiction precedents.

The complete authored library for all eight setup values is defined in
[`value-law-library.md`](value-law-library.md).

## Player outcome

The player can answer five questions wherever a precedent matters:

1. Which recorded rule applies?
2. What does the rule require by default?
3. Who supports or disputes that interpretation?
4. What will compliance or exception cost now?
5. What later review will an exception create?

A precedent changes available procedures and future obligations. It is not a
passive bonus and it does not certify the moral meaning of the player's choice.

## Scope

### Included

- Enactment from a pivotal, recorded decision.
- A central rule query used by simulation, UI, and bots.
- Visible compliance, bounded compliance, and exception paths.
- Persistent cases created by contradictions.
- Council review that can affirm, narrow, replace, or leave a rule contested.
- Causal links among value, decision, precedent, exception, review, and later
  consequences.
- One end-to-end No One Left Behind content chain.
- Save/load, deterministic simulation, bot policy, telemetry, and tests.

### Not included

- A free-form law editor.
- Numeric ideological alignment axes.
- Hard prohibitions on player commands.
- A separate lawmaking minigame.
- Automatic moral judgment in the chronicle.
- Retrofitting every existing precedent consumer in the first implementation.

## Existing foundation

The game already stores `Precedent` records, cites their enactment events,
retains them through chronicle compaction, and uses several kinds to change need
costs, combat doctrine, settlement rules, ship autonomy, endings, and political
behavior. The first implementation should extend those records and replace
scattered boolean checks only along the featured rescue chain. Other consumers
can migrate incrementally after the contract is proven.

## Player flow

### 1. Claim

Civilization setup records a claimed value. For the first chain:

> No one under fleet protection is to be abandoned without an attempted
> recovery.

This is an expectation, not yet a law. It contributes no continuous bonus.

### 2. Test

A rescue situation places the claim under material pressure. At least two
responses must be viable:

- **Open a recovery corridor** — risk ships and reserve capacity now.
- **Promise a later return** — preserve immediate safety, create a dated public
  commitment, and leave people exposed.
- **Withdraw** — preserve the task group and record the refusal.

The choice panel shows known costs, bounded risks, affected ships and
communities, and whether the response can establish a precedent.

### 3. Enact

The first costly action consistent with the claim may be proposed as a
precedent after the immediate outcome. Ratification is a separate pivotal choice
only when the action had material cost or risk; routine rescues cannot farm laws.

Options:

- **Record the recovery duty** — enact No One Left Behind.
- **Record this as an isolated command** — retain the history without a rule.
- **Refer the question to an institution** — create a political commitment and
  a deadline rather than deciding immediately.

Enactment stores the triggering decision, sponsor, beneficiaries, and initial
interpretation. It does not grant an immediate Cohesion reward.

### 4. Apply

When another rescue, combat withdrawal, stranded expedition, or settlement
defense decision appears, the game asks the rule service for an application.
The UI places the applicable rule directly above the choices:

> **Recorded duty · No One Left Behind**
>
> Attempt recovery when a protected ship or community can still be reached.

Each choice receives one of four labels:

- **Complies** — satisfies the recorded duty.
- **Bounded compliance** — satisfies its minimum obligation but leaves a
  visible residual risk or promise.
- **Exception** — contradicts the default under an existing emergency power.
- **Departure** — contradicts the default without claimed legal authority.

The label is derived from authoritative rules, never authored independently in
the presentation layer.

### 5. Contradict

An exception remains available when compliance is unaffordable, physically
impossible, or strategically unacceptable. Choosing it:

- resolves the immediate situation;
- records which precedent was contradicted;
- records the cited authority, if any;
- identifies the people, ships, and institutions bearing the consequence;
- creates or advances one constitutional case;
- changes trust or legitimacy only for actors connected to that case;
- schedules review after an intervention window of at least one season.

The same contradiction cannot apply several immediate fleet-wide penalties.
Downstream consequences must cite the case or its originating event.

### 6. Review

The council review presents the original rule, the exception, observed outcome,
and current positions. It offers up to four resolutions:

- **Affirm** — preserve the rule and treat the event as an exceptional breach.
- **Narrow** — add a precise condition to the rule's applicability.
- **Replace** — supersede it with a conflicting precedent.
- **Leave contested** — preserve both interpretations and move authority toward
  the institution, community, or ships acting on their own account.

Review is not a rewind. Rescue losses, damage, promises, and relationships
remain. Resolution changes how the next case will be judged.

## Rule model

### Precedent state

Extend `Precedent` with:

```odin
Precedent_Status :: enum {Active, Contested, Superseded}

Precedent_Scope :: bit_set[Precedent_Domain]
Precedent_Domain :: enum {
    Rescue,
    Combat_Withdrawal,
    Settlement_Defense,
    Departure,
    Disclosure,
    Adaptation,
    Settlement_Charter,
}

Precedent :: struct {
    // Existing fields remain.
    id:                  Precedent_ID,
    status:              Precedent_Status,
    scope:               Precedent_Scope,
    sponsor_institution: Institution_ID,
    beneficiary:         Community_ID,
    source_decision:     u64,
    superseded_by:       Precedent_ID,
    interpretation:      Precedent_Interpretation,
}
```

`Precedent_Interpretation` is a typed enum or small tagged payload selected by
precedent kind. It must not store executable prose. For No One Left Behind, the
initial interpretations are:

- `Attempt_When_Reachable`
- `Attempt_Unless_Fleet_Collapse_Risk`
- `Answer_Only_Existing_Protection_Duties`

The first is the founding interpretation. Narrowing can select either of the
other two. Content cannot invent arbitrary predicates.

### Constitutional case

```odin
Precedent_Case_Status :: enum {Pending, Affirmed, Narrowed, Replaced, Contested}

Precedent_Case :: struct {
    id:                    Precedent_Case_ID,
    precedent:             Precedent_ID,
    status:                Precedent_Case_Status,
    source_decision:       u64,
    contradiction_event:   u64,
    cited_authority_event:  u64,
    initiator_ship:         Ship_ID,
    affected_community:     Community_ID,
    responsible_institution: Institution_ID,
    review_season:          i32,
    last_event:             u64,
}
```

The campaign supports at most three unresolved cases. A new contradiction of an
already-pending precedent advances the existing case rather than creating a
duplicate. If all slots concern other rules, the decision remains playable and
the oldest case is surfaced for review before another unrelated political beat.

### Central query

All consumers use one pure query:

```odin
precedent_application :: proc(
    c: ^Campaign,
    context: Precedent_Context,
    action: Precedent_Action,
) -> Precedent_Application
```

The result contains:

- applicable precedent and enactment event;
- current interpretation and status;
- classification: none, complies, bounded, exception, or departure;
- the factual reason for that classification;
- authority required for an exception;
- case that would be created or advanced;
- known relationship and obligation consequences;
- event causes that must be attached on resolution.

The query does not mutate state or roll randomness. A separate command validates
that the preview still matches current state, resolves the action, and records
the application atomically.

### Precedence

When several rules apply:

1. A more specific scope outranks a general scope.
2. A later active precedent outranks an earlier contradictory precedent only
   when it explicitly supersedes it.
3. A contested precedent still supplies a default, but authorized actors may
   follow either recorded interpretation and advance the case.
4. Emergency authority permits an exception; it does not erase the underlying
   rule.
5. If no deterministic resolution exists, the action is labeled **Disputed**
   and the conflict must be surfaced before commitment.

These rules prevent enactment order or collection layout from changing results.

## No One Left Behind vertical slice

### Trigger A: enactment opportunity

A reachable vessel has lost propulsion and carries a community not already
aboard the task group. Full recovery threatens mission reserves; a bounded
recovery can stabilize the vessel and create a promise to return.

The full and bounded options can both support ratification. Withdrawal cannot.
The chosen ship records the rescue or refusal in its history.

### Trigger B: later hard case

At least two seasons later, a damaged expedition calls from a degrading
correspondence. Recovery requires an archive ship whose loss would remove the
fleet's only applicable navigation record. Available responses are:

| Response | Immediate outcome | Rule classification | Persistent result |
|---|---|---|---|
| Send the archive ship | Best recovery attempt; archive placed at bounded risk | Complies | Ship and archive carry the outcome |
| Send a limited screen | Some people remain exposed; promise required | Bounded compliance | Dated promise and residual claim |
| Invoke emergency conservation | Archive remains safe; expedition withdraws alone | Exception | Constitutional case and emergency debt |
| Refuse recovery authority | Archive remains safe; expedition withdraws alone | Departure | Case, ship claim, and authority pressure |

Outcomes use the campaign seed and existing Passage or combat resolution. The
precedent changes the decision structure and attribution, not encounter odds.

### Trigger C: review

The review occurs after the expedition outcome is known. Positions derive from
records:

- the rescued or abandoned community;
- the archive's custodian;
- the ship that accepted or refused risk;
- the institution whose authority was cited;
- any active promise created by bounded compliance.

No actor receives a stance solely from its display archetype. Reasons cite
trust, custody, prior conduct, promises, jurisdiction, or direct exposure.

### Later reuse

The resolved interpretation changes at least three future decisions:

- rescue response defaults;
- combat recovery-corridor authority;
- settlement-defense obligations.

It also remains eligible for ship memories, historical-front causes, chronicle
compaction, settlement reports, and endings.

## Costs and recovery

Compliance must sometimes be expensive or the feature becomes ceremonial.
Contradiction must sometimes be survivable or the rule becomes a disguised
command lock.

- Compliance risks relevant ships, capacity, time, or promises.
- Bounded compliance preserves a recovery path but carries a named residual
  obligation.
- An exception shifts authority and trust; it does not apply a generic campaign
  failure penalty.
- Repeated exceptions increase case pressure and may produce decentralized
  rescue behavior, institutional loss of legitimacy, or a replacement rule.
- Recovery comes through review, fulfilled promises, later conduct, or lawful
  transfer of authority. It never deletes the original event.

## Interface contract

### Decision panel

Show, in this order:

1. Immediate pressure and intervention window.
2. Applicable precedent and one-sentence interpretation.
3. For every action: immediate commitment, bounded risk, rule classification,
   and whether review follows.
4. Named strongest supporter and opponent when the action changes precedent.

Do not show speculative future scenes or aggregate moral labels.

### Chronicle

The precedent record links backward to its source decision and forward to every
application, contradiction, review, and superseding rule. A rule card shows:

- status;
- enacted season and factual wording;
- current interpretation;
- sponsor and beneficiary, when present;
- applications, exceptions, and unresolved cases;
- the next known review date.

Example records:

> Wayfarer opened a recovery corridor for the Halcyon community.

> The council recorded a duty to attempt recovery while contact remained
> possible.

> Fleet command invoked emergency conservation and withheld Hearth Archive from
> the second recovery attempt.

> The council narrowed the recovery duty where the fleet's only route record
> would be placed at risk.

These records state actions and rules without assigning motive or historical
meaning.

### Notifications

- Interrupt immediately for a decision that can enact or contradict a rule.
- Notify without interruption when an action complies with an uncontested rule
  and requires no new player choice.
- Batch repeated applications in the seasonal chronicle.
- Surface a review before its deadline and before an unrelated council proposal
  if all case slots are occupied.

## Bot and simulation policy

Bots use the same preview and command path as the player. They score immediate
utility, promised future cost, relationship exposure, and precedent posture.

- Steward favors compliance and bounded compliance.
- Strategist favors compliance unless it threatens essential recovery
  capability.
- Risk Manager prefers the narrow interpretation and authorized exceptions.
- Explorer accepts bounded risk when the recovery preserves information or
  contact.
- World Builder prefers actions that create a stable, broadly applicable rule.

Profiles are preferences, not exemptions. Every bot must sometimes select at
least two classifications under matched contexts, and no classification should
exceed 70% when at least five comparable affordable opportunities exist.

## Determinism and persistence

- IDs are monotonic and serialized.
- Rule matching uses explicit kind and scope ordering.
- Stances are derived in stable actor-ID order.
- No UI call mutates or consumes random state.
- Choice resolution records the previewed precedent ID and validates it before
  commitment.
- Saves preserve active and superseded rules, interpretations, unresolved
  cases, deadlines, cited authority, and causal event references.
- Chronicle compaction protects unresolved cases and the enactment event of any
  active or contested precedent.
- Older saves migrate existing precedents to `Active`, infer scope and the
  default interpretation from kind, and use the enactment event as the source
  decision when no earlier source is recorded.

## Implementation boundaries

Authoritative types, rule matching, case transitions, commands, migration, and
tests belong in `packages/game`. Presentation, bot scoring policy, and executable
telemetry belong in `src`.

Suggested files:

- `packages/game/precedent_law.odin` — queries, matching, applications, cases.
- `tests/game/precedent_law_tests.odin` — deterministic scenario tests.
- `packages/game/campaign_relationship_types.odin` — persisted records.
- `packages/game/persistence.odin` — validation and migration.
- `packages/game/interactions.odin` — first rescue-chain integration.
- `packages/game/council_politics.odin` — review flow and positions.
- `packages/game/chronicle_history.odin` — compaction protection.
- `src/campaign_views.odin` — rule card, labels, causal navigation.
- `src/bot.odin` — profile scoring through the shared query.
- `src/bot_reporting.odin` — feature telemetry.

`has_precedent` remains temporarily available for unmigrated consumers. New
feature code must not add another raw boolean check.

## Validation plan

### Functional tests

- Identical seed and commands produce identical application, case, stance, and
  review results.
- Save/load at claim, enactment, application, contradiction, and review phases
  preserves the next legal actions and causal references.
- A superseded precedent no longer supplies the active default.
- A contested precedent offers the recorded interpretations deterministically.
- Unaffordable compliance remains disabled with a factual reason; exception and
  departure remain available.
- Repeated contradictions advance one case and do not stack duplicate penalties.
- Chronicle compaction preserves every unresolved causal chain.

### Scenario tests

Run the vertical slice with fixed variants for:

- sufficient recovery capacity;
- only bounded compliance affordable;
- emergency authority available;
- no exception authority;
- archive already copied;
- affected community already aggrieved;
- the rescuing ship previously abandoned another vessel;
- active promise fulfilled before review;
- save/load immediately before review.

Every scenario must end in valid state and retain at least one recovery path.

### Simulation gates

Across matched bot campaigns containing at least two applications:

- at least 80% produce a later cited consequence;
- 20–60% produce a constitutional case;
- at least three review resolutions appear in aggregate;
- no qualifying classification exceeds 70% per profile;
- contradiction does not increase abrupt campaign termination by more than two
  percentage points;
- no invalid action, dangling event reference, collection saturation, or
  deterministic mismatch occurs.

These ranges are instrumentation alarms, not final balance targets.

### Human comprehension tests

After the later hard case, a first-use tester should be able to state:

- which rule applied;
- why each option complied or contradicted it;
- what was immediately at risk;
- whether a later review would occur.

Target: four of five testers answer all four without opening the full chronicle.

After review, testers should identify one future decision changed by the
resolution. The test records their explanation; telemetry alone cannot establish
causal understanding.

## Delivery sequence

1. Add persisted IDs, status, scope, interpretation, cases, and migration.
2. Implement the pure rule query and transition tests.
3. Route the two rescue situations and bot choices through the shared contract.
4. Add decision labels and the chronicle rule card.
5. Add council review and its four resolutions.
6. Add compaction, save/load, telemetry, and long-run validation.
7. Run first-use comprehension sessions before migrating other precedents.

## Definition of done

The feature is complete when a claimed value can be tested, enacted through a
costly choice, applied to a later hard case, contradicted without ending the
campaign, reviewed into at least three mechanically different futures, and
recalled through a navigable causal record. Player and bot actions use the same
authoritative rules; fixed-seed and save/load tests pass; the automated gates
show no dominant classification or invalid state; and first-use testers can
explain the rule and its consequences.
