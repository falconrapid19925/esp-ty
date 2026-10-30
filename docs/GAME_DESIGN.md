# Espresso Cafe Tycoon: initial game design

Design date: **30 October 2026**. This is the evidence-informed scope for the initial build, aligned with [ARCHITECTURE.md](ARCHITECTURE.md). [BENCHMARKS.md](BENCHMARKS.md) records the checked-at public data and distinguishes observed competitor features from design hypotheses. This document does not claim that visual playtesting or retention validation has been completed.

## Café ownership and core loop

Players receive an available café plot in a six-café pedestrian plaza. Other players can visit and see its growth. Currency and progression belong to the owner; v1 does not include shared ownership or player trading.

The repeatable loop is **read the order → start brewing → serve when ready → earn cash → buy a useful improvement**. A server-timed perfect-extraction window rewards attentive service. VIP orders and scheduled rush periods add occasional variation. The machine's proximity interaction and the order UI expose the same validated actions.

The initial recipe ladder is espresso, americano, cappuccino, latte, mocha and cold brew. The menu upgrade unlocks later recipes. An always-available order keeps the starting loop clear; this first build is not a full free-placement restaurant or a complex customer-pathfinding simulation.

## First-session targets to test

The UI should make the next action and purchase understandable without reading a manual. A short contextual checklist introduces brewing, serving and upgrading.

Initial tuning hypotheses are a first successful sale within roughly a minute and a useful first upgrade within a few minutes of active play. These are proposed playtest targets, not industry standards, measured outcomes, or guarantees. The actual starting cash, costs and timings live in `Config`; evaluate the targets on a supported Studio device before declaring them met.

## Progression and automation

Eight upgrade tracks provide manageable choices: **machine, beans, seating, menu, staff, bakery, décor and expansion**. Equipment, menu and staff improve the earning loop; seating, bakery, décor and expansion communicate the café's growth through their configured economic effects and visible world changes. Costs and level caps come from the shared economy configuration.

Staff unlock a server-run automated sales cadence. Players can continue manually serving for active-play rewards while deciding what to improve next. Automated sales come from the game service, never from decorative NPC movement or a client-supplied amount. The visual café should reflect owned upgrades so progress is more than a larger currency counter.

The milestones are near-term purchases, new drinks, more efficient service, a fuller café and lifetime achievements. A longer session should have new decisions available; increasing waiting time alone is not the intended source of depth.

## Reasons to return

Daily quests use clear served, earned and upgrade targets, with explicit reward claims and a fresh UTC-day set. They do not require a punishment-based login streak. Achievements record longer-lived milestones separately, using the profile's lifetime/manual-service/perfect-shot/upgrade counters as configured.

Offline earnings use server-recorded elapsed time, a configured cap and a configured reduced earning rate. Returning players see the credited reward. Offline rewards increase cash and lifetime earnings, but do not fabricate served customers, manual actions or perfect shots. Saving must succeed before persistent progress is represented as safely stored; Studio session-only mode must be visible.

Franchising is an **optional, confirmed reset of run progress** after its configured cash and upgrade requirements. It rewards long-term franchise progression and access to café themes. The available theme ladder is sage, terracotta and midnight, gated by franchise count. The confirmation UI must explain the actual reset and retained progress implemented by `Economy.franchise`; never frame a reset as a free upgrade or force it to continue serving.

## Presentation and scope

The café identity is cozy, readable and coffee-focused. Themes, visible machines, seating, pastries and décor support ownership. Assets and their import/licensing decisions are tracked separately; a benchmark is not permission to copy another game's assets or layout. Controls should remain usable with touch, mouse and gamepad.

Initial social features are visiting the plaza and a truthful server leaderboard backed by server-owned statistics. No Robux products, passes, subscriptions, paid random rewards or paid progression are included initially. Farming, full furniture placement, trading, co-owned cafés and large seasonal content systems remain future candidates, not delivered-feature claims.

## Retention measurement

After functional and device playtests, instrument the onboarding funnel: join, ready state, first brew, first sale, first upgrade and first staff purchase. Track recipe unlocks, quest claims, achievement claims and franchise confirmations. Inspect where players stop progressing, particularly before a first reward or after unlocking automation.

Evaluate session-duration distributions alongside active service and purchase events, plus D1/D7 return cohorts when the sample supports them. Distinguish active play from idle presence; compare new and returning players rather than treating one overall average as a quality score. Any session-length or retention target is a hypothesis until measured. Analytics instrumentation and dashboards require their own verification and are not implied to exist merely because they are described here.
