# Art direction

*Last Best Hope* uses a monochrome cosmic-horror engraving aesthetic. The
supplied July 21, 2026 reference images are the visual benchmark: immense black
spaces, fine white linework, inhabited machinery, and organic structures whose
scale is understood only after the viewer finds a ship.

This direction is defined by the observable craft below rather than by an
artist's name. Use these terms in briefs and generation prompts.

## The image language

- Work primarily in black, bone white, graphite, and cold silver. Build light
  from marks cut out of darkness, not from broad grey gradients.
- Render with dense pen-and-ink hatching, cross-hatching, stipple, scratched
  highlights, and engraved contour lines. Large areas of untouched black are
  as important as intricate passages.
- Put human engineering beside porous, fibrous, webbed, ossified, or cellular
  forms. The boundary between constructed and grown may be ambiguous; the
  machinery itself should remain purposeful and mechanically plausible.
- Establish scale through nested silhouettes. A readable ship or habitat is a
  small anchor against structures that continue beyond the frame.
- Favor severe perspective, long diagonals, occlusion, and cropped megastructures.
  Avoid centered fleets posed against empty space.
- Let detail accumulate unevenly. Keep a clear focal silhouette, one controlled
  area of near-white, and enough black rest for the subject to remain readable.
- Treat damage as history: patches, replaced plates, exposed ribs, registry
  marks, and scar tissue should be specific to the vessel rather than generic
  grime.

## Ships

Ships are persistent characters, not disposable tokens. Their silhouettes must
remain recognizable at map scale and their close views must preserve accrued
history.

- Start with a strong axial keel and a legible role-specific massing.
- Assemble vessels from pressure hulls, trusses, tanks, radiators, antennae,
  docking collars, and mission structures with visible functions.
- Use repeated modules to show human manufacture; use local asymmetry for
  repairs, adaptations, ownership, and service history.
- Reserve filigree for close views. At small sizes, express the style through a
  black silhouette, a thin engraved rim light, and two or three interior cuts.
- Engines illuminate nearby structure with narrow white scatter. Avoid colorful
  exhaust except when a mechanic requires identification.

## Places and the Outer Dark

- Space is a field of black, not a blue nebula backdrop. Stars are sparse,
  irregular pinpricks and may disappear around the focal subject.
- Alien places should feel older and larger than the camera can inventory.
  Prefer partial evidence—repeating cavities, impossible load paths, embedded
  machinery—to a fully explained creature or ruin.
- Membrane-space geometry uses threads, shells, laminae, branching capillaries,
  and nested voids. It must not default to tentacles, wet gore, or decorative
  skulls.
- Habitable locations may be beautiful, but never pastoral by default. Show the
  material conditions that would let people live there.

## Interface

The interface is an archival instrument laid over the engraving, not a glowing
science-fiction cockpit.

- Use near-black panels, warm off-white primary text, graphite rules, and
  hairline diagrams.
- Cyan-grey identifies information and selection. Muted green, ochre, and
  rust identify favorable, cautionary, and destructive states. Violet is
  reserved for commitments and irreversible precedents.
- Color is semantic and scarce. Never tint a whole illustration to communicate
  mood, and never make color the only carrier of state.
- Prefer square or very slightly rounded geometry. Dense illustration belongs
  behind generous black margins; text must never compete with hatching.
- Typography remains plain and highly legible. Do not imitate hand lettering in
  operational UI or player-facing records.
- Frame major panels like manga captions: hard rectangular edges, emphatic
  corner strokes, selective double rules, and occasional cropped ink bars.
  Rounded app-card containers, glossy controls, and pastel pictograms are out.
- Icons use black-and-white brush contours with sparse dry-brush hatching. They
  remain uncolored source masks; the renderer may tint an icon only when its
  state already has a defined semantic color.

## Motion

- Keep motion slow and material: parallax between engraved planes, drifting
  particulate, a crawling line of light, or a newly revealed hatch pattern.
- Do not animate every mark. Stillness communicates mass.
- Transitions may expose an image as if light is scanning across a plate. Honor
  reduced-motion settings with cuts and short dissolves.

## Asset and prompt template

Use a brief of this form:

> Monochrome cosmic-horror pen-and-ink engraving. [Subject and concrete action].
> Vast black negative space; bone-white etched contour lines; dense localized
> cross-hatching and stipple; mechanically plausible human spacecraft contrasted
> with porous, cellular megastructure; extreme scale established by one small,
> readable ship; severe perspective; a single controlled white focal light;
> archival, solemn, materially specific. No text, no border.

Then specify composition, aspect ratio, required empty UI regions, the ship's
identity and persistent damage, and the one story fact the image must show.
Avoid artist names, generic "detailed" modifiers, glossy 3D rendering, smooth
airbrush gradients, neon palettes, centered poster composition, ornamental
gore, and detail distributed uniformly across the frame.

## Review checklist

- The composition reads in silhouette before its fine detail is visible.
- The ship, action, or decision remains identifiable at its delivery size.
- Black negative space survives; the image is not a uniform grey thicket.
- Human and nonhuman materials have distinct construction logic.
- Scale is demonstrated by an object, repetition, or occlusion—not asserted.
- Damage and markings agree with the campaign record.
- UI color is semantic, sparse, and supported by shape or text.
- The image depicts an observable event without declaring its moral meaning.
