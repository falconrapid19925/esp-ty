# Studio validation before a public release

This repository is an initial playable implementation. Linux checks compile Luau, exercise deterministic economy and mocked persistence logic, and export a place. They cannot verify the Roblox renderer, real DataStores, asset access, audio playback, touch feel, or a published multiplayer session.

## Open and configure

1. Open `build/EspressoCafeTycoon.rbxlx` in current Roblox Studio on Windows/macOS. Press **Play**; the map and UI are created at runtime. Use a private test experience first.
2. For sourced Creator Store geometry, verify **Allow Loading Third Party Assets** remains enabled under the experience's security settings. The exported place preconfigures it through `AssetService.AllowInsertFreeAssets = true`; the owner can change it in Studio. Review `src/shared/AssetCatalog.luau` and `docs/ASSET_RESEARCH.md`. Imported content is reduced to decorative geometry; executable scripts are removed.
3. Published persistence uses `EspressoCafeTycoon_Profiles_v1`. For Studio tests against the published test experience, enable **Studio Access to API Services**. Use a separate test experience so you do not touch live player saves. An unpublished/API-disabled Studio test visibly says **Session only**; temporary progress disappears on Stop.
4. Set the experience's maximum server size to **6 players**. All six cafés are publicly visitable; profile mutations only affect the requesting player.

## First session and progression

- New player receives $60, sees a personal café and a customer, and can brew an espresso. Serving before extraction finishes must never pay. Serve in the green window for the perfect bonus. A second Serve remote cannot sell the same drink twice.
- The first sale makes the $65 machine upgrade affordable. Buy it and observe faster extraction plus a visual change. Test all eight tracks, max-level states, locked recipes, insufficient cash and the selected-recipe UI.
- Test expired shots, switching recipes while brewing, reset character, switching themes and visiting another café. A visitor must not buy another owner's upgrades or earn against their customer.
- Hire staff, then keep a manual shot active: staff earnings must continue without consuming or replacing that manual order. Watch a complete rush period and check that the bonus ends.
- Complete/claim each daily goal and milestone. Reclaiming must not pay twice. Roll into the next UTC day and verify only daily goals reset.
- Franchise requires $20,000, 18 current-café upgrade levels and both expansions. The UI must show what resets and require confirmation. Verify levels/cash reset, lifetime stats/claimed milestones remain, income gains 20%, and the appropriate style unlocks.

## Saves and multiple clients

- Start a local server with 2 clients, then 6 if hardware permits. Each has a distinct plot, wallet, order and leaderstats. Leaving frees exactly that plot. Rejoining restores the saved profile.
- Restart a published test server, claim an eligible offline reward, then leave/rejoin. The reward must not be duplicated; the cap is four hours, at 12% of automated service value, and requires hired staff.
- Exercise a controlled DataStore failure: live load failure must block progression rather than produce a writable empty save. Two servers cannot acquire the same unexpired save lease. Save failure must be visible.
- Test PlayerRemoving during load and shutdown during save. Verify the next join can acquire the released lease and that the final saved balance is sane.

## Assets, audio and devices

- Inspect the actual sourced espresso machine, tables and plants for scale, missing textures, collision, obscured walkways and unwanted descendants. Check warnings for permission failures and compare against `Assets.getStatus()` output. Fallback geometry does not demonstrate successful imported-asset access.
- Check the bundled CC0 model sources and license files before manual Studio import. Local OBJ/FBX files do not become published Roblox mesh IDs merely by being committed to GitHub.
- Opt into music. Confirm playback rights/access for the specific experience, sane volume and mute behavior. Check the click/brew sounds. Audio permission/loading failure must leave the core game usable.
- Check desktop, tablet, 320px-wide phone, phone landscape and gamepad in Studio's device emulator. No overlapping wallet/manage controls; scrolling and extraction controls must remain reachable with readable text.
- Check 6-player frame rate, spawned customer counts, plot rebuilds, respawns and long-session memory growth. Character/customers should stay within bounded numbers.

## Release measurement

Server-confirmed onboarding events exist for cafe-ready, first-brew, first-sale and first-upgrade in published servers. Verify event ingestion in Creator Dashboard. The early pacing and extended-session goals are hypotheses: measure funnel completion, D1/D7 retention, average session duration and device segments. Public competitor ratings do not supply those private metrics or guarantee our game's results.
