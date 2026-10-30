# Espresso Cafe Tycoon — implementation contract

Rojo maps `src/shared` to `ReplicatedStorage.Shared`, `src/server` to `ServerScriptService.Server`, and `src/client` to `StarterPlayerScripts.Client`. `Main.server.luau` boots the world and game service. All player currency and progression changes happen on the server.

## Shared modules

`Config` is pure data. Ordered arrays: `Recipes` (`Id, Name, Price, BrewTime, MenuLevel, Color` RGB arrays), `Upgrades` (`Id, Name, Description, BaseCost, CostScale, MaxLevel`), `Quests` (`Id, Name, Metric, Target, Reward`), `Achievements` (`Id, Name, Metric, Target, Reward`), `Themes` (`Id, Name, RequiredFranchises, Primary, Accent` RGB arrays). General settings include StartingCash, MaxPlots, SaveInterval, OfflineCapSeconds, OfflineRate, FranchiseCash, FranchiseUpgrades. Eight upgrade IDs: machine, beans, seating, menu, staff, bakery, decor, expansion. Recipe IDs: espresso, americano, cappuccino, latte, mocha, cold_brew. Theme IDs: sage, terracotta, midnight.

`Economy` is pure Luau (no Roblox services). Public functions: `newProfile(now)`, `sanitize(raw, now)`, `rollDaily(profile, now)`, `recipe(profile, id)` (nil if locked), `unlockedRecipes(profile)`, `upgradeCost(profile, id)` (nil at max), `buyUpgrade(profile, id, now)` -> bool,message, `brewDuration(profile, recipe)`, `saleValue(profile, recipe, perfect, vip, rush)`, `recordSale(profile, recipeId, perfect, vip, rush, now)` -> amount, `staffInterval(profile)`, `offlineEarnings(profile, seconds)`, `claimQuest(profile,id,now)` -> bool,message, `claimAchievement(profile,id)` -> bool,message, `canFranchise(profile)` -> bool,message, `franchise(profile,now)` -> bool,message, `setTheme(profile,id)` -> bool,message, `formatMoney(amount)`.

Profile fields: Version, Cash, LifetimeEarned, LifetimeServed, ManualServed, PerfectShots, TotalUpgrades, Franchises, Upgrades (dictionary), Theme, Daily={Day,Served,Earned,Upgrades,Claimed}, Achievements (claimed dictionary), LastSeen. Derived run upgrades = sum(Upgrades). Epoch seconds `now` is supplied by caller. ManualServed is incremented by GameService, PerfectShots by recordSale. Sale credits update LifetimeEarned, LifetimeServed and Daily. Offline reward only credits Cash/LifetimeEarned, not fictitious served customers. No client amounts are accepted.

## Network

Server creates `ReplicatedStorage.Remotes.Action` RemoteEvent (client -> server), `State` RemoteEvent (server -> client), and `GetState` RemoteFunction (read only snapshot).

Action payloads: `("Brew")`, `("Serve")`, `("BuyUpgrade", upgradeId)`, `("SelectRecipe", recipeId)`, `("ClaimQuest", questId)`, `("ClaimAchievement", achievementId)`, `("SetTheme", themeId)`, `("Franchise")`. `Serve` timing is validated with server time. Rate-limit and validate all actions. Rebirth confirmation happens in UI before `Franchise` is sent.

Snapshot: `{Ready, Error?, Profile, PlotIndex, SelectedRecipe, Order={RecipeId,Vip}, Brew={StartedAt,ReadyAt,PerfectUntil,ExpiresAt}?, ServerTime, Rush={Active,EndsAt,NextAt}, SaveStatus, OfflineReward, Message?}`. Times use `workspace:GetServerTimeNow()` for matching client UI. An order always exists while Ready, recipe selection replaces it only when no brew. Snapshot Profile is server-owned; clients cannot send it back. State updates after mutations and every ~2 seconds for time/state reconciliation.

## Server modules (backend agent owns)

`DataService`: DataStore profile loading/saving with UpdateAsync session leases, retries, autosave, player-leave and BindToClose. Never overwrite on failed load. Studio API-disabled mode is explicitly session-only. Do not persist NPC state. Per-user pending load/close race must be handled.

`GameService.start(world)` owns profiles, player lifecycle, order/brew state, staff sales, rush schedule, RemoteEvent validation, leaderstats and save/UI state. Require Config/Economy from ReplicatedStorage.Shared.

## World module (world agent owns)

`World.build()` -> world object; `world:assignPlot(player)` -> index or nil; `world:releasePlot(player)`; `world:refreshPlot(player, profile)`; `world:showOrder(player, recipe, vip)`; `world:serveCustomer(player, recipe, amount, perfect)`; `world:setBrew(player, active)`; `world:spawnPlayer(player)`; `world:setHandlers({Brew=function(player), BuyUpgrade=function(player,id)})`.

Build 6 publicly visitable cafés around a landscaped pedestrian plaza. AssignPlot auto claims an available plot and places owner label. SpawnPlayer moves the current character to owned plot safely. Use ProximityPrompt for brewing and upgrade pads, routed through handlers (same server validations as remotes). RefreshPlot visibly reflects machine/seating/staff/bakery/decor/expansion levels and palette. Customers are bounded decorative rigs/tweens; earnings come only from GameService. ShowOrder makes visible customer and order bubble, serveCustomer transitions them out and displays tip feedback. **User refinement: prefer sourced free assets for hero props, furniture, audio and décor.** Assets module loads reviewed Creator Store models using official AssetService, removes executable/unrelated content and caches geometry. Authored simple geometry is only a fallback when import fails. The Studio third-party-asset setting and mesh/audio permissions must be documented honestly; do not silently claim those imports were validated in this Linux environment. Include central leaderboard SurfaceGui if practical; GameService maintains normal leaderstats.

## Client module (UI agent owns)

`Main.client.luau` builds branded responsive UI from Roblox Instances, requires Config/Economy. HUD, contextual first-session checklist, current order, server-timed brew/perfect extraction interaction, upgrades, menu, daily quests, milestones, themes, franchise confirmation, save status, offline reward, server leaderboard and teleport-to-own-cafe via character movement is NOT client authoritative (omit unless server action agreed). Use TweenService for subtle feedback, buttons usable with touch/mouse/gamepad; ProximityPrompt supports E near machine. UI can call GetState once connected and listen State before invoking it to avoid missed initial messages. Include Loading/Error state and retry `GetState` while loading. Do not fabricate online users, revenue metrics, Robux products or leaderboards.

## Ownership

Root owns shared modules, project config, docs, build/test tooling, integration and GitHub. Backend agent owns src/server/DataService.luau and GameService.luau. World agent owns src/server/World.luau. UI agent owns src/client/Main.client.luau. Coordinate contract changes in messages; do not edit other agents' files.
