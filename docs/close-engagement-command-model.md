# Close Engagement command model

## Goal

Close Engagement should support varied missions without adding a permanent order
button for every new objective. A command has three independent parts:

1. **Stance** — how the formation behaves while carrying out work.
2. **Action** — what the formation is doing and, when required, its target.
3. **Ability** — a limited ship-specific intervention with its own cost or
   cooldown.

Missions define objectives and interactions. They do not extend the global
stance or action enums merely to obtain a new button.

## Stances

Stances persist until changed and never require the player to place a target.
Changing stance must not cancel the current action.

| Stance | Behavior |
| --- | --- |
| **Engage** | Fight valid contacts using doctrine priority and pursuit limits. |
| **Screen** | Stay close to the current action target or formation and prioritize threats to it. |
| **Evade** | Preserve the formation, minimize exposure, and avoid optional engagements while continuing the action. |

The stance answers: **How should these ships behave?**

## Actions

Actions continue until completed, replaced, cancelled, or made impossible.

| Action | Target | Behavior |
| --- | --- | --- |
| **Move** | Position | Travel to a destination. |
| **Act** | Mission objective or friendly asset | Perform the interaction supplied by that target. |
| **Attack** | Hostile contact | Engage a specific contact within stance and doctrine limits. |
| **Hold** | None | Cancel travel or interaction and remain at the present position. |
| **Withdraw** | Extraction boundary | Leave the engagement. |

The action answers: **What should these ships do, and where?**

`Extract` remains an internal mission transition for forced extraction. It is
not a separate player action.

## Contextual interactions

Every actionable mission target supplies one interaction record:

```text
id
kind
position or unit target
available-to predicate
short verb
one-sentence consequence
progress
completion state
```

The global **Act** control uses that record. The visible verb may be specific:

- relay -> **Capture**
- seedship -> **Recover**
- disabled ally -> **Rescue**
- anomaly -> **Scan**
- convoy -> **Escort**
- wreck -> **Salvage**
- beacon site -> **Deploy**
- damaged installation -> **Repair**

These are mission interactions, not new action enum values. If no valid target
is selected or under the pointer, Act is unavailable and explains why.

## Abilities

Emergency Defense and ship abilities remain outside the action model. They may
modify an action's outcome but do not replace the action or stance. Cooldowns,
charges, and known costs remain visible at the point of use.

## Sidebar contract

The left command rail should expose three visually separate regions:

```text
STANCE
  ENGAGE   SCREEN   EVADE

ACTION
  MOVE     ACT
  HOLD     WITHDRAW

ABILITY
  contextual emergency or selected-ship ability
```

The selected stance remains highlighted while actions show active targeting,
progress, or availability. The action section may show the contextual Act verb
instead of the generic word when a target is known. Mission authors must not
add permanent buttons to this rail.

## Causal examples

```text
relay must be secured
-> player chooses Screen + Capture
-> formation travels to the relay and protects the capture perimeter
-> capture progress and incoming threats remain visible
-> player may switch to Evade without restarting capture
```

```text
disabled ally is exposed
-> player chooses Evade + Rescue
-> recovery formation approaches while avoiding optional engagements
-> the ally is restored and both formations withdraw
-> the rescued ships retain their damage history
```

## Migration

1. Add `Combat_Stance` to command elements and groups. Default to Engage. *(Implemented.)*
2. Make targeting, pursuit, and exposure behavior read stance independently of
   the active action.
   *(Implemented for Screen targeting/pursuit and Evade engagement suppression.)*
3. Replace order-specific Guard and Intercept behavior with Screen and Engage
   stance rules.
   *(Player input migrated; legacy authored mission values remain compatible.)*
4. Introduce mission interaction records and route existing Control, Recover,
   and disabled-ship rescue through contextual Act.
   *(Contextual interaction routing is implemented; data-authored objective records remain extensible work.)*
5. Reduce player actions to Move, Act, Attack, Hold, and Withdraw. Retain
   internal compatibility mapping while deterministic mission tests migrate.
   *(Implemented.)*
6. Replace the sidebar with separate Stance, Action, and Ability regions.
   *(Implemented.)*

## Validation

- Changing stance never clears destination, target, or interaction progress.
- Reissuing the same action with a different stance produces a deterministic
  but observably different combat response.
- Current relay capture, seedship recovery, rescue, attack, and withdrawal
  scenarios remain completable with the new vocabulary.
- A new interaction such as Scan can be added without changing the action enum
  or the permanent sidebar layout.
- First-use testing verifies that players can answer both “what are they doing?”
  and “how are they behaving?” from the task-group row.
