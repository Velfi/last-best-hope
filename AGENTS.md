# Last Best Hope contributor notes

Read `docs/writing-guidelines.md` before authoring or reviewing player-facing text.
Read `docs/art-direction.md` before creating or reviewing visual assets, shaders,
UI treatments, or image-generation prompts.

- Keep simulation rules deterministic for a supplied seed.
- Keep game state in `packages/game`; executable and presentation policy belong in `src`.
- Put dedicated game tests in `tests/game`, not `packages/game`, so application
  builds do not parse and check them. Update `tests/game/game_package_aliases.odin`
  when a migrated test needs another exported game declaration.
- `zelda-engine` is a sibling dependency and must remain product-neutral.
- Prefer recoverable setbacks to abrupt run termination. Standard difficulty targets a 75% campaign win rate for experienced players.
- Ships are persistent characters. New mechanics should create history, relationships, scars, or consequential choices—not only stat growth.
