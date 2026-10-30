# Imported source art

These are selected, unmodified files from Kenney's official free packs. Included `License.txt` files specify CC0. `manifest.json` records source pages, selected files, and hashes.

Use FBX with Roblox Studio's 3D Importer, or open FBX/GLB/OBJ in Blender. Retain the `Textures` directory beside Food Kit model files. Imported meshes must be uploaded to Roblox by the experience owner; a raw local model path cannot be a `MeshId`.

After importing and grouping into Models, put café props under `ServerStorage.AssetOverrides` using these names:

| Model | Runtime override |
| --- | --- |
| Furniture `kitchenCoffeeMachine` | `espresso_machine` |
| Furniture `tableRound` | `cafe_table` (group with two chairs for a complete set) |
| Furniture `chair` / `chairModernCushion` | `cafe_chair` |
| Furniture `pottedPlant` | `plant` |
| Food `cup-coffee` | `coffee_cup` |
| Food `croissant` / `donut-chocolate` / `muffin` | `pastry` |

Artist credit: **Kenney — https://kenney.nl**. See [asset research](../../docs/ASSET_RESEARCH.md) for current Roblox model/audio references and setup.
