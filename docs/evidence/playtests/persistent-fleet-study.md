# Persistent fleet playtest

Use this protocol to validate whether players understand and plan around named
ships, commitments, and relationships. Telemetry supports the interview record;
it does not replace it.

## Session fixture

Run the `persistent_fleet_playtest_fixture` campaign with seed `0x50463138`.
Allow 45–60 minutes. Do not teach the authority, attention, or dossier systems
beyond the prompts shown in the product.

The fixture is valid only when its preflight report confirms all of these:

- a named Compact call and a contested undertaking;
- a prior bond between two named ships;
- evidence acquired during Passage;
- a close-combat attention event;
- a recoverable capability loss;
- a public account of the operation;
- a later autonomous response or Compact call whose available action, offer,
  default, forecast, or support differs because of an earlier operation or
  relationship;
- at least two viable doctrines, neither identified as morally correct.

## Event log

Write one row to `persistent-fleet-session.csv` for each choice, screen visit,
attention opening or resolution, dossier opening, causal-link opening, and
accepted default. Timestamps are elapsed milliseconds from fixture start.
Stable IDs must refer to the campaign objects, not display-list positions.

Do not log inferred emotion or intent. Interview observations belong in the
notes column and must distinguish the player's words from the observer's
description.

## Pivotal-moment questions

After each designated attention event, ask without opening another screen:

1. What was underway?
2. What changed?
3. Why did the game stop now?
4. Which ship, contributor, community, promise, or expectation matters here?
5. What will happen if you do nothing?
6. What do you expect this choice to change later?

Record the answer before giving help. Score “why now?” and the no-response
default separately. A correct answer must name the relevant changed fact or
threshold and the executable default; vague answers such as “something bad
happened” do not pass.

## End-of-session questions

Ask the player to:

- name three ships and distinguish each by current duty or remembered history;
- describe one relationship between named actors;
- describe one undertaking and one contributor expectation;
- identify one later decision changed by an earlier relationship, report, or
  operation;
- explain how they used doctrine and when they chose to intervene;
- describe whether ships felt interchangeable, citing what produced that view.

Do not supply names or reopen the dossier until recall is recorded.

## Longitudinal follow-up

Continue the same save for at least three sessions. At each return, repeat the
three-ship recall before showing the fleet screen. Record routine factual
records, modal decisions, dossier visits, defaults, and causal-link openings.
Inspect the accumulated dossier for pivotal stakes hidden beneath routine
history.

Review each campaign for:

- a policy selected in more than 70% of comparable viable opportunities;
- a relationship benefit that makes its own future selection unavoidable;
- a social cascade with no implemented reconciliation path;
- a dossier whose active pivotal stake is not visible in its concise view;
- experienced players doing routine work manually because doctrine cannot
  express their intended rule.

## Release calculations

Calculate rates from completed, protocol-valid sessions:

- attention comprehension: players who correctly explain every tested
  interruption and default / players receiving those events; target 80%;
- ship recall: players naming and distinguishing three ships / completed
  players; target 75%;
- causal reuse: players identifying a later changed decision / completed
  players; target 70%;
- interchangeable ships: players primarily describing ships as stat packages /
  completed players; must remain below 15%;
- experienced standard wins: wins / completed experienced campaigns; target
  near 75%, reported with sample size and confidence interval.

Every failed criterion gets a linked issue naming the observed confusion,
affected screen or rule, causal evidence, and proposed systems or legibility
change. A copy-only change is insufficient unless the rule was already exposed
and the observed failure was specifically wording comprehension.
