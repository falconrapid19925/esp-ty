# Espresso Cafe Tycoon

A Roblox café-management tycoon: pull espresso shots, serve customers, improve your coffee house and grow into a franchise. Built as a Rojo project with an exported `.rbxlx` you can open directly in Roblox Studio.

**Status:** initial playable implementation; Luau/economy/build checks run in Linux. Roblox Studio playtesting and asset/audio permissions still need validation on Windows or macOS. This is not a claim of a production-tested release or a guaranteed retention rate.

## Pull and play on Windows / macOS

```sh
git clone YOUR_REPOSITORY_URL
cd espresso-cafe-tycoon
git pull
```

Replace `YOUR_REPOSITORY_URL` with the project's GitHub URL once pushed. If using the downloadable ZIP, extract it instead of cloning. Open **`build/EspressoCafeTycoon.rbxlx`** in Roblox Studio and press **Play**. The café plaza and interface are generated when the server starts. No Rojo installation is needed just to open this committed build.

**Free assets:** the exported place preconfigures **Allow Loading Third Party Assets** (`AssetService.AllowInsertFreeAssets = true`) for the reviewed free Creator Store models. Verify that setting remains enabled when opening/publishing in Studio. Geometry is sanitized before use. If access fails, limited fallback geometry keeps the game playable; see [asset research and import instructions](docs/ASSET_RESEARCH.md) and inspect the result in Studio. Bundled Kenney CC0 source models are an alternative for Studio's 3D Importer. Music is opt-in, and audio playback remains to be checked in the target experience.

**Saving:** unpublished/API-disabled Studio play uses clearly marked temporary sessions. Publish to a private test experience and enable Studio API access to test persistence. Set maximum players to **6**. Follow the [Studio test plan](docs/STUDIO_TEST_PLAN.md) before releasing publicly.

## Included gameplay

- Six owned, visitable café plots around a pedestrian plaza.
- Manual espresso extraction with a server-timed perfect-shot bonus, VIP orders and periodic coffee rushes.
- Six recipes: Espresso, Americano, Cappuccino, Cafe Latte, Mocha and Cold Brew.
- Eight progression tracks: machine, beans, seating, menu, staff, pastries, decor and expansion.
- Earned staff automation; staff do not consume the player's active manual order.
- Daily goals, one-time milestones, visible cash/customer/franchise leaderstats, three unlockable café palettes.
- Optional franchise reset with confirmation, permanent service-income bonuses and style unlocks.
- Session-protected saves, autosave/checkpoints/shutdown saves, capped offline earnings with hired staff.
- Responsive management UI, contextual onboarding and optional sourced café audio. No Robux products are configured.

These are initial systems to test and tune. There is no free-form furniture placement, shared ownership, trading, global persistent leaderboard or measured multi-hour retention yet.

## Build and develop

Python 3.10+ can install pinned official tool releases locally:

```sh
python scripts/bootstrap.py
python scripts/check.py
```

On Windows, `py` may replace `python`; on macOS/Linux use `python3` if required. Alternatively install the pinned Rojo/Lune tools in `aftman.toml` with Aftman. The check command runs tests, builds the place and inspects the exported scripts. GitHub Actions repeats the build on pushes and provides the place as an artifact.

```sh
# With Rojo on PATH, for live editing through the Rojo Studio plugin:
rojo serve
# Export a fresh place after editing source:
rojo build default.project.json -o build/EspressoCafeTycoon.rbxlx
```

The `.rbxlx` is a generated snapshot: after changing source, rebuild it before someone pulls it. Studio edits made only to a runtime-generated object are not automatically written back to Luau.

## Research and sources

Checked **30 October 2026**. [Benchmark snapshots](docs/BENCHMARKS.md) identify three café/restaurant games exceeding 95% positive approval at retrieval and distinguish public evidence from session-length assumptions. [Game design](docs/GAME_DESIGN.md) explains how their loops inform this implementation. [Architecture](docs/ARCHITECTURE.md) documents server authority and module contracts.

External asset rights remain with their creators. Kenney sources include their CC0 licenses; Roblox/APM assets are referenced by IDs for use under applicable Roblox terms, with no ownership claim or redistribution of their audio/model files. See [asset provenance](docs/ASSET_RESEARCH.md).
