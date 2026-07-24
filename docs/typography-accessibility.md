# Typography accessibility

Player-facing typography must remain readable at every interface scale offered
in Settings (100%, 125%, and 150%). These rules apply to every screen, modal,
tooltip, tactical annotation, and disabled control.

## Required invariants

- No rendered text may be smaller than `MIN_BODY_TEXT_SIZE` at 100% scale.
  Larger interface scales multiply that readable floor.
- Text fitting may truncate compact names or metadata with an explicit `...`,
  but must never shrink below the readable floor. Sentences and consequences
  wrap instead of truncating.
- Wrapped lines use the measured paint size plus at least 6 logical pixels of
  leading. Repeated rows must leave enough vertical space for the 150% setting.
- Enabled text colors must meet a 4.5:1 contrast ratio against the void, panel,
  and raised-panel backgrounds. Color remains supplemental to labels, shapes,
  or icons.
- Disabled controls may use the lower-contrast `UX.unavailable` color, but their
  labels must retain the same readable size and remain visibly disabled by the
  control treatment.
- Tooltips wrap their explanations and remain inside the logical viewport.
- Dense tactical labels may truncate, but operational prose, risks, costs,
  consequences, and response text must remain available in full.

## Screen review matrix

The UI is reviewed in these families so new screens do not fall between
feature-specific checks:

| Family | Screens and surfaces | Primary typography risks |
| --- | --- | --- |
| Shell | Menu, pause, settings, credits, rails | control labels, scale setting, footer density |
| Founding | Setup and previews | long explanations, choice hierarchy, persistent-rule copy |
| Fleet | Fleet, story, care, build, ship detail | card overflow, dossier metadata, histories, status copy |
| Record | Chronicle, debrief, ending | dense causal links, long event records, evidence lists |
| Council | Interaction and settlement proposal | proposals, consequences, reasons, compact checkboxes |
| Navigation | Galaxy, body detail, passage, guidebook | map labels, course readouts, tooltips, status prose |
| Combat | Briefing, battlefield, result | tactical annotations, event stream, requests, unit history |
| Development | Ship generator and comparison boards | generated names and compact technical metadata |

## Verification

The source tests enforce the minimum paint size and WCAG normal-text contrast
for all enabled semantic colors. Built-in graphical capture fixtures accept
`LBH_CAPTURE_UI_SCALE=1.25` or `LBH_CAPTURE_UI_SCALE=1.5` so representative
screens can be rendered at the same scales available to players.

For a typography change:

1. Run `odin check src -collection:zelda_engine=../zelda-engine/packages`.
2. Run the source tests and build the game.
3. Capture Fleet, Interaction, Passage, and Combat at 150%.
4. Inspect for overlap, clipped prose, text outside panels, weak hierarchy, and
   labels whose meaning depends on color alone.

