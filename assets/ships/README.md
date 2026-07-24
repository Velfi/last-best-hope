# Ship image assets

`combat-hologram-atlas-source.png` and `combat-hologram-atlas.png` are retained
as concept references for the close-engagement admiralty symbols. They are no
longer runtime assets; the tactical renderer constructs equivalent marks as
depth-tested world-space line geometry. Both references use a 3×2 grid of
512×512 cells:

1. Fighter squadron
2. Bomber squadron
3. Corvette group
4. Recovery vessel
5. Carrier / command cruiser
6. Heavy capital ship

The source was generated with OpenAI's built-in image-generation tool on July
21, 2026. It was requested as abstract naval plotting-room symbology—not
literal ship drawings—with size encoded by footprint and function encoded by
chevrons, torpedo pips, picket arcs, recovery brackets, carrier bays, command
bars, and weapon ticks. The bone-white marks were generated on a uniform
`#00ff00` background with no labels, borders, scenery, shadows, or watermark.
The background was removed locally with the Codex image-generation skill's
chroma-key helper.

## Production hull archetypes

`ship-archetypes-atlas-source-v1.png` is the flat-magenta generation source for
the 24 production hull archetypes. `ship-archetypes-atlas-v1.png` is the
alpha-matted review asset. Both use a 6×4 grid, ordered left-to-right:

1. Scout, interceptor, fighter, strike fighter, bomber, assault shuttle
2. Patrol boat, corvette, torpedo boat, gunship, picket frigate, combat frigate
3. Support frigate, minelayer frigate, destroyer, light cruiser, heavy cruiser,
   battlecruiser
4. Battleship, carrier, dreadnought, utility hull, transport hull, habitat hull

The source was generated with OpenAI's built-in image-generation tool on July
21, 2026. The prompt followed `docs/project/art-direction.md`: orthographic top-down
ships, monochrome engraved linework, readable axial silhouettes, functional
modules, sparse highlights, no labels, and a uniform `#ff00ff` background. The
background was removed locally with the Codex image-generation skill's
chroma-key helper. This version is a review atlas and is not yet referenced by
the renderer or runtime asset manifest.

## Fleet-combat archetype icons

`combat-archetype-icons-atlas-source-v1.png` is the flat-green generation
source and `combat-archetype-icons-atlas-v1.png` is its tintable alpha-matted
runtime counterpart. The 1536×1024 atlas uses a 6×4 grid of 256×256 cells and
the same archetype ordering listed above.

The 24 centered, individually addressable cells are also retained in
`combat-archetype-icons-v1/`. Run `tools/recenter_craft_symbols.sh` to recover
the complete visual groups from the generated source layout and rebuild the
runtime atlas without cell-edge bleed.

These icons reduce each hull to shared admiralty geometry plus a role mark:
sensor arcs and contact pips for scouts and pickets, interception chevrons,
torpedo marks, boarding and recovery brackets, mine diamonds, command bars,
flight-deck pips, cargo bars, and habitat shelter geometry. They are designed
to remain legible at 48×48 pixels. The source was generated with OpenAI's
built-in image-generation tool on July 21, 2026, using the existing combat
hologram atlas as the style reference. The background was removed locally with
the Codex image-generation skill's chroma-key helper.
