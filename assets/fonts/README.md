# Game fonts

The game UI faces are custom condensed builds of Iosevka 34.7.0:

- `Iosevka-Regular.ttf`, `Iosevka-Bold.ttf`, and `Iosevka-Italic.ttf` use a
  480-unit advance width (80% of upstream Iosevka's 600-unit normal width).
- `private-build-plans.toml` is the reproducible upstream build plan. Build it
  from the Iosevka 34.7.0 source with
  `npm run build -- ttf-unhinted::LBHCondensed`.
- The build copies the regular face to the stable `ZeldaSans-Regular-v1.otf`
  compatibility path used by `zelda-engine`'s UI package.
- `Iosevka-LICENSE.md` contains the upstream SIL Open Font License 1.1.

Source: <https://github.com/be5invis/Iosevka/releases/tag/v34.7.0>

`NotoSansSymbols2-Regular.ttf` supplies the compact non-ASCII symbol fallback
atlas used by the canvas renderer. It is Noto Sans Symbols 2 from the Noto
project and is distributed under the SIL Open Font License 1.1 in
`Noto-LICENSE.md`.

The identical `ZeldaSerif-Regular-v0_1.otf` compatibility copy is retained for
`zelda-engine`'s display-font lookup. Runtime staging copies both files under
their checked-in names instead of renaming the Noto source during the build.

Source: <https://github.com/notofonts/noto-fonts/tree/main/unhinted/ttf/NotoSansSymbols2>

Bold and italic are bundled for future weight and style selection; the current
renderer uses the regular face for all UI text.
