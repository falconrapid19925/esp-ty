# Validation snapshot — 30 October 2026

Command: `python3 scripts/check.py`

| Check | Result |
| --- | --- |
| Official Luau 0.745 syntax compilation | 15 source/test files passed |
| Asset sanitization/load fallback scenarios | 6 passed |
| Mocked DataStore/session persistence scenarios | 12 passed |
| Deterministic economy scenarios | 15 passed |
| Mocked game-service/action lifecycle scenarios | 15 passed |
| Mocked client UI/state scenarios | 9 passed |
| Mocked world lifecycle/sourced-asset scenarios | 7 passed |
| Downloaded Kenney CC0 file integrity | 77 files matched recorded sizes and SHA-256 hashes |
| Rojo 7.7.1 place export | Passed; 9 Luau sources embedded |
| Serialized free third-party asset setting | `AssetService.AllowInsertFreeAssets = true` present |

Total: **64 automated scenarios**. Tests load current source files, not copied snapshots. Mocked UI/world tests exercise control flow and properties; world tests use real Lune Roblox datatypes, enums and property reflection where available. These checks help catch integration mistakes but do not run the Roblox engine.

## Still requires Roblox Studio

Final appearance, third-party mesh/texture access and scale, avatar generation, music/SFX permissions and playback, touch/gamepad feel, real replicated multiplayer, live DataStore behavior, shutdown budgets and analytics ingestion remain unverified in this Linux environment. Use [STUDIO_TEST_PLAN.md](STUDIO_TEST_PLAN.md) on Windows/macOS before a public release.

Competitor approval/current-player snapshots support benchmark selection only. No private retention or average-session data was available, and no measured claim that this prototype retains players for hours is made. See [BENCHMARKS.md](BENCHMARKS.md).
