# Last Best Hope

![Last Best Hope main menu](main-menu.png)

**Last Best Hope** is a deterministic command chronicle about guiding a refugee
fleet after the loss of its home. Its named ships persist as characters: they
accumulate damage, obligations, relationships, repairs, and history.

Across seasons, decide what the fleet can preserve, repair, promise, settle,
or risk. Commission task groups to navigate the continuous four-dimensional
Outer Dark, return with evidence and consequences, and take command of fleet
operations when the voyage requires it. A failed expedition should leave a
record and a changed fleet, not simply end the chronicle.

## Contributor quick start

This project expects the product-neutral `zelda-engine` repository beside this
one:

```text
parent-directory/
├── last-best-hope/
└── zelda-engine/
```

On macOS, install Xcode command-line tools and [Homebrew](https://brew.sh),
then bootstrap the pinned compilers and native dependencies:

```sh
./tools/bootstrap-macos.sh
make doctor
make test-fast
make run
```

`make doctor` verifies the toolchain, native text dependencies, and engine
checkout. The bootstrap is safe to rerun; it downloads pinned tools to the
ignored `.tools/` directory. Set `ZELDA_ENGINE_ROOT` when the engine checkout
is elsewhere. The build system also supports Linux when its equivalent native
dependencies and pinned toolchain are available; the bootstrap helper is
macOS-only.

## Everyday work

| Command | Purpose |
| --- | --- |
| `make fmt` | Format Odin sources. |
| `make check` | Run static checks and module-size checks. |
| `make test-fast` | Run the edit-time test suite. |
| `make test` | Run all game, canvas, and application tests. |
| `make run` | Build and launch the Chronicle interface. |
| `make release` | Build the optimized executable in `build/release/`. |

Development builds are written to `build/dev/`. Use `make test-balance` and
`make test-generative` when changes affect difficulty, procedural generation,
or long-horizon behavior.

## Contributor conventions

- Keep simulation rules deterministic for a supplied seed.
- Put game state, rules, persistence, and history in `packages/game`.
  Executable and presentation policy belong in `src`.
- Add dedicated game tests under `tests/game`, not `packages/game`. Update
  `tests/game/game_package_aliases.odin` if a migrated test needs another
  exported game declaration.
- Keep `zelda-engine` product-neutral.
- Read [writing guidelines](docs/project/writing-guidelines.md) before changing
  player-facing text, and [art direction](docs/project/art-direction.md) before
  changing visual assets or UI treatments.

## Further reading

- [Documentation index](docs/README.md) — current contracts, setting, plans,
  and evidence.
- [Diaspora Fleet](docs/planning/diaspora-fleet.md) — planned campaign loop and
  persistent-civilization target.
- [Passage expeditions](docs/project/passage-expeditions.md) — current Outer
  Dark operations and persistence rules.
- [Close engagement](docs/project/close-engagement.md) — current fleet-operation
  controls and implementation contract.
- [Campaign validation](docs/evidence/campaign-validation.md) — dated balance
  and release evidence.
