# Free asset sourcing

Checked **30 October 2026**. Existing free assets are the first choice for the café props, audio, and music. The shell/layout and gameplay code are authored for this game. Small geometry fallbacks keep a café playable only when a sourced prop cannot load.

## Selected Roblox models

Live Roblox Toolbox search, the public economy metadata endpoint, and thumbnail inspection were used together. Each selected model reported `AssetTypeId = 10` and `IsPublicDomain = true` on the check date. This Roblox distribution flag means the item is freely distributed on Roblox; **it does not make a community model CC0 or license its extraction for sale outside Roblox**. The repo references the IDs rather than redistributing downloaded community model files.

| Runtime key | Model and creator | What was checked |
| --- | --- | --- |
| `espresso_machine` | [Coffee Machine — Ashbashthesmash](https://create.roblox.com/store/asset/12520208389/Coffee-Machine) | Thumbnail shows an espresso machine with pressure gauge, portafilter, and cups. |
| `cafe_table` | [Cafe Table & Chairs — Elliott_RBLX](https://create.roblox.com/store/asset/186713502/Cafe-Table-Chairs) | Round marble table and two wooden chairs; imported as one seating set. |
| `plant` | [Potted Plant — maadhouse](https://create.roblox.com/store/asset/13218937353/Potted-Plant) | Textured leafy plant in a pot. |
| `coffee_cup` | [Coffee Cup — LittleWorlds](https://create.roblox.com/store/asset/1471275477/Coffee-Cup) | Plain takeaway cup with lid and sleeve. |
| `pastry` | [Croissant — ViperXVI](https://create.roblox.com/store/asset/5854562478/Croissant) | Textured croissant. |
| Reference only | [Cafe Furniture — BunnyFilms1](https://create.roblox.com/store/asset/472584642/Cafe-Furniture) | Whole furniture collection; not automatically placed as a single prop. Select individual pieces in Studio. |

Some search results had plausible espresso titles but unrelated thumbnails. Those were rejected. A standalone `cafe_chair` is deliberately not guessed; the selected table model already contains chairs. A locally imported `cafe_chair` override is supported.

## Loading and source control

`src/server/Assets.luau` loads only the IDs in `src/shared/AssetCatalog.luau` using [`AssetService:LoadAssetAsync`](https://create.roblox.com/docs/reference/engine/classes/AssetService). It keeps the default sandbox, removes scripts/modules, packages, tools, remotes, prompts, sounds, constraints, particles, and other non-geometry objects before a model is parented into the world. Geometry is anchored and non-colliding; the world supplies interactions. Loads are cached and capped at 300 parts / 2,000 descendants per model, with a bounded initial wait. Model contents are not executed.

**The exported place preconfigures the free-model setting:** `default.project.json` serializes `AssetService.AllowInsertFreeAssets = true`, corresponding to **Allow Loading Third Party Assets** in Experience Settings. Rojo successfully exported that property; verify Studio retains it when opening/publishing the place. A normal runtime script cannot change it. This configures the project file for the user's requested free assets; no Roblox account credentials were used and no assets were acquired on the user's account. If Studio/experience policy disables the setting or Roblox denies an asset, the loader emits a clear warning and the world uses a fallback. The owner can review or disable it in Studio.

For stable art that does not change when an uploader updates their model, import/review the models in Studio edit mode, disable/remove every supplied script, and put the visual models under `ServerStorage.AssetOverrides` with the runtime key names above. Local overrides take priority. This also supports the CC0 models below. Save the edited place and commit it after checking the props. To include overrides in future Rojo builds, export each reviewed model to an `.rbxm` and map it into `ServerStorage.AssetOverrides` in `default.project.json`; do not expect an edit made only in Studio to become a source file automatically.

**Validation boundary:** unauthenticated HTTP downloads from `assetdelivery.roblox.com` returned **401 Unauthorized** in this Linux session. No Roblox account token was configured or requested. Public metadata/free-distribution status and preview images were verified; actual model loading, mesh permissions, scaling, and final appearance still require a Studio playtest. The build is not evidence that every remote mesh is rendered correctly.

## Curated CC0 source models included

The following packs were downloaded directly from Kenney's official download flow, with their included license files preserved. Only selected model files are committed in `assets/source/`; full downloads and research previews stay in ignored `assets/_incoming/`.

| Official pack | Included selection | Formats |
| --- | --- | --- |
| [Furniture Kit](https://kenney.nl/assets/furniture-kit) | `kitchenCoffeeMachine`, counter/bar and end, two chair styles, round table, plant, ceiling lamp | FBX, OBJ+MTL, GLB |
| [Food Kit](https://kenney.nl/assets/food-kit) | Coffee cup, croissant, chocolate donut, muffin, chocolate cookie | FBX, OBJ+MTL, GLB; required colormap textures |
| [Interface Sounds](https://kenney.nl/assets/interface-sounds) | Click, confirmation, error, select, open, close | OGG |

All three included pack licenses specify **Creative Commons Zero (CC0)** and permit personal, educational, and commercial use. Attribution is optional; credit is retained here: **Models and interface sounds by Kenney, https://kenney.nl**. The exact selected files, byte sizes, and SHA-256 hashes are in `assets/source/manifest.json`.

The machine and other props are actual downloaded artist models, not newly generated approximations. They can be opened in Blender and imported into Roblox Studio using the 3D Importer (FBX is supplied for that workflow). A filesystem `.obj`, `.fbx`, or `.glb` path cannot be used as a Roblox `MeshId`: import/upload it in Studio to create Roblox assets, group the result into a Model, and use the override keys above. This headless Linux session has no Studio or Roblox upload credentials, so those source files are **available for import**, not claimed as already uploaded.

Quaternius was also researched. Its [current asset license](https://quaternius.com/license.html), updated 28 August 2026, permits use in finished products but forbids repackaging raw assets as an asset collection. No Quaternius source asset was bundled; the included source props use the explicit Kenney CC0 licenses.

## Sound and music

Roblox documents a large collection of [free-to-use audio on the Creator Store](https://create.roblox.com/docs/audio/assets). The following current IDs were verified against public Roblox metadata. They are platform audio references, not standalone music files redistributed in this repo.

| Use | Asset | Creator / provenance |
| --- | --- | --- |
| UI click | [button.wav — 12221967](https://create.roblox.com/store/asset/12221967) | Roblox verified account, public distribution. |
| Brew sound | [CoffeeBrew — 365956378](https://create.roblox.com/store/asset/365956378) | Roblox verified account; original [coffee pot finishing brew.wav by hatchetgirl](https://freesound.org/people/hatchetgirl/sounds/185143/) independently lists CC0. |
| Opt-in music | [Sunday In Bed — 9047104336](https://create.roblox.com/store/asset/9047104336/Sunday-In-Bed) | APMOfficial, 170-second relaxed lofi track; public distribution. |
| Opt-in music | [Cool Vibes — 1840684529](https://create.roblox.com/store/asset/1840684529/Cool-Vibes) | APMOfficial, 126-second lounge track; public distribution. |
| Opt-in music | [Cafe Boy — 1837623244](https://create.roblox.com/store/asset/1837623244/Cafe-Boy) | APMOfficial, 183-second lounge track; public distribution. |

The catalog starts music **off** until the player enables it. `PlaybackVerified = false` records the absence of an engine/audio playtest here. Check audibility and permissions in the published experience before release; catalog visibility is not an actual playback test. Keep APM music usage on Roblox under the applicable Roblox/provider terms, and do not reupload it or claim authorship. Raw APM music was not downloaded. The included CC0 Kenney interface clips can be imported/uploaded through Studio if replacements are needed.

The live metadata snapshot is in `assets/source/roblox-verification.json`. Free availability, uploader changes, and asset permissions may change after the recorded check date.
