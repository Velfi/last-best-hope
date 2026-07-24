# Application icon

`last-best-hope.png` is the 1024 px cross-platform master. Packaging uses
`last-best-hope.icns` on macOS and the PNG on Linux. `last-best-hope.ico` is
ready for a future Windows executable/resource packaging target.

The `app.iconset` directory contains the standard macOS raster sizes. Keep
`last-best-hope-source.png` as the original generated artwork when deriving
new formats.

## UI icon atlas

`ui-icon-atlas-manga-source.png` is the current 6 × 6 monochrome production
source. `ui-icon-atlas.png` is its transparency-processed runtime atlas. Icon
order is an executable contract: preserve all 36 row-major meanings when
redrawing the source. Runtime pixels are white with alpha so presentation code
can apply the small set of semantic colors without baking color into the art.

`ui-icon-atlas-garden-source.png` and `ui-icon-atlas-garden.png` are the expanded
fleet-garden family now used at runtime. Its 36 row-major meanings are named by
the `ICON_*` constants in `src/command_chronicle.odin`; use those constants at
call sites so accidental icon reuse is visible in review.

`depth-planes/depth-planes-strip.png` is the transparent three-cell combat
sprite strip for **High**, **Plane**, and **Low**, in that order. The individual
128 px files and generated source remain beside it for review and future
derivation. Runtime combat UI keeps the corresponding text label visible with
the icon.
