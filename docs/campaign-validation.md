# Campaign validation

This document defines durable release gates and records only the latest
authoritative balance evidence. Point-in-time investigation transcripts should
not become separate design documents.

## Commands

```sh
build/last-best-hope --investigate-actions 5 77 100
build/last-best-hope --validate-long-runs 1 77
build/last-best-hope --sample-balance 1500 77
build/last-best-hope --validate-campaigns 10005 77
```

## Product gates

- Every operation begins from a valid v8 Compact charter and selected
  secondment manifest. Passage, Close Engagement, and Far Engagement must
  enforce the same authority, intent, expectation, and doctrine semantics.
- Compact aftermath, resource settlement, relationship consequences, and
  callbacks are idempotent across replay and save/load. Invalid cross-links are
  rejected rather than repaired silently.
- Ignoring every visible call advances the autonomous world without deadlock;
  no reporting boundary surfaces more than one new call or more than three
  visible calls.
- A 100-season deterministic soak completes without invalid actions, exhausted
  fixed collections, integer overflow, or loss of causal records.
- No general-purpose bot profile reaches a 95% win rate in matched samples.
  Standard difficulty targets a 75% campaign win rate for experienced players.
- Every profile reaches at least three materially distinct states by season 24.
- At least two historical fronts remain active or transformed after season 12
  in 80% of campaigns.
- Revisiting a Passage region after six seasons changes a route, authority,
  environmental condition, or available objective.
- Campaigns preserve more than 512 events and obey Story Tempo without
  suppressing direct consequences.
- Irreversible choices name their costs, affected ships or communities, and
  persistent rules.
- Knowledge has recurring productive uses and does not accumulate as an
  unbacked currency.
- Loss of an essential ship role creates a visible replacement, substitution,
  migration, or contraction decision.
- Settlements maintain local flows, stockpiles, and trade. Repeated shortages
  can produce adaptation, planned contraction, or migration.
- Long campaigns produce distinct successor economies and material changes
  traceable to accumulated history without collection saturation.

## Action-dominance sampling

An action enters the dominance sample only when its situation exposes at least
two implemented choices whose typed costs fit current unreserved capacity.
Unaffordable fallback attempts and single-option states are excluded. A choice
is flagged when it exceeds 70% within one situation family and at least five
comparable affordable opportunities exist. Lower-evidence repetition is
reported separately as low-sample lock-in.

## Latest authoritative evidence

Campaign format v8 makes the Expeditionary Compact charter, secondment
manifest, resource ledger, aftermath, counsel, and callbacks authoritative.
Earlier balance matrices are not authoritative for this campaign loop.

The first corrected 300-run matched audit used seed 9127 and 20 campaigns in
each profile/tempo cell. It reported:

- 69.67% aggregate wins;
- zero invalid actions and zero collection saturation;
- event preservation beyond sequence 512;
- no qualifying action above the 70% dominance threshold;
- Measured cell win rates of 70–90%, Spacious rates of 75–95%, and Volatile
  rates of 30–55%.

This is structural evidence, not a passing balance baseline. Setbacks occurred
in 98% of campaigns, scars in 65.33%, ship loss in 22.67%, and emergencies in
35.67%, all above their gates. Ordinary Passage manifests also consumed nearly
every allocation, leaving effectively no recovered Supplies.

The v8 full-suite, bot matrix, 1,500- and 10,005-campaign matrices, and human
Compact study remain outstanding. Until they are complete, this document must
not describe the release balance gate as closed.
