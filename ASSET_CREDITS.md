# Embervale Asset Credits

The following third-party assets are included in the project under the licenses
shown below. The original license/readme files are kept beside each imported
asset set under `assets/models/`, and each Poly Haven texture set carries its
own `SOURCE.txt` under `assets/textures/cc0/`.

| Pack | Imported content | License | Local record | Source |
|---|---|---|---|---|
| Kenney Nature Kit | trees, rocks, logs, mushrooms | CC0 1.0 | `assets/models/kenney_nature/Models/License.txt` | [kenney.nl/assets/nature-kit](https://kenney.nl/assets/nature-kit) |
| Kenney Graveyard Kit | altar, coffin, candle, fence, graves | CC0 1.0 | `assets/models/kenney_graveyard/Models/License.txt` | [kenney.nl/assets/graveyard-kit](https://kenney.nl/assets/graveyard-kit) |
| Kenney Survival Kit | barrel, bedroll, bottle, fence, tent | CC0 1.0 | `assets/models/kenney_survival/Models/License.txt` | [kenney.nl/assets/survival-kit](https://kenney.nl/assets/survival-kit) |
| Kenney Tower Defense Kit | crystal, rocks, tree detail | CC0 1.0 | `assets/models/kenney_tower_defense/Models/License.txt` | [kenney.nl/assets/tower-defense-kit](https://kenney.nl/assets/tower-defense-kit) |
| Kenney Mini Dungeon | human/orc characters, dungeon props | CC0 1.0 | `assets/models/kenney_mini_dungeon/Models/License.txt` | [kenney.nl/assets/mini-dungeon](https://kenney.nl/assets/mini-dungeon) |
| Kenney Foliage Sprites | grass, flowers, foliage billboards, field/garden detail | CC0 1.0 | `assets/ambient/kenney_foliage_sprites/License.txt` | [kenney.nl/assets/foliage-sprites](https://kenney.nl/assets/foliage-sprites) / [OpenGameArt mirror](https://opengameart.org/content/foliage-sprites) |
| Kenney Castle Kit | castle exterior modules: walls, towers, roofs, gate, stairs, flags | CC0 1.0 | `assets/models/kenney_castle/License.txt` | [kenney.nl/assets/castle-kit](https://kenney.nl/assets/castle-kit) |
| Kenney Fantasy Town Kit | town/roof/wall modules reserved for realm dressing | CC0 1.0 | `assets/models/kenney_fantasy_town/License.txt` | [kenney.nl/assets/fantasy-town-kit](https://kenney.nl/assets/fantasy-town-kit) |
| KayKit Dungeon Remastered | enterable-structure interiors: floors, walls, doorways, stairs, props | CC0 1.0 | `assets/models/kaykit_dungeon/LICENSE.txt` | [kaylousberg.com](https://kaylousberg.com/) |
| Quaternius Animated Monsters | structure bosses (skeleton warden, matron slime, sealed dragon, bat) | CC0 1.0 | `assets/models/quaternius_monsters/License.txt` | [quaternius.com](https://quaternius.com/) / [patreon.com/quaternius](https://www.patreon.com/quaternius) |
| Poly Haven CC0 Surfaces (cobblestone_floor_05, wood_floor_worn, grass_ground, rock_face, thatch_roof_angled) | structure interiors and procedural exteriors: stone, wood, grass, rock, thatch | CC0 1.0 | `assets/textures/cc0/<set>/SOURCE.txt` | [polyhaven.com/a/cobblestone_floor_05](https://polyhaven.com/a/cobblestone_floor_05), [wood_floor_worn](https://polyhaven.com/a/wood_floor_worn), [grass_ground](https://polyhaven.com/a/grass_ground), [rock_face](https://polyhaven.com/a/rock_face), [thatch_roof_angled](https://polyhaven.com/a/thatch_roof_angled) |
| Quaternius Medieval Weapons | hammer and dagger runtime hand-weapon fallbacks | CC0 1.0 | `assets/models/weapons/quaternius/LICENSES.md` | [quaternius.com/packs/medievalweapons.html](https://quaternius.com/packs/medievalweapons.html) |
| Quaternius Animated Animals | frog, rat, snake, spider, and wasp realm enemies | CC0 1.0 | `assets/models/enemies/quaternius/LICENSES.md` | [quaternius.com](https://quaternius.com/) |
| Embervale Generated Terrain Surfaces | moss, wet mud, grass, and sand surface sets (albedo + normal + roughness) | Generated in-session with OpenAI image generation; no third-party source license | `assets/textures/stylized/{moss,mud,grass,sand}/` | Consolidated 2026-09-18: the `*_v2` shadow copies were removed and every realm terrain material binds the canonical stylized folders |
| Embervale App Icon | launcher, adaptive foreground/background, themed monochrome, project icon, boot-splash mark | Project-original, generated deterministically in-repo by `tools/generate_app_icon.gd`; no third-party source | `assets/branding/app_icon/` | Contract: `tests/test_app_icon_assets.gd`. Palette mirrors the UiKit tokens; regenerate with `godot --headless --path . --script tools/generate_app_icon.gd` |

The KayKit Dungeon, Kenney Castle Kit, Kenney Fantasy Town Kit, Quaternius
Animated Monsters and the five Poly Haven surface sets were added to the
repository on 2026-09-18. Each downloaded set keeps its upstream license file
(or per-set `SOURCE.txt`) next to the assets, and
`tests/structure_interior_validation.tscn` verifies that every mapped kit piece
and surface family resolves at build time.

## Shipping checklist

- Keep each pack's `License.txt` and `README.md` in the repository.
- Recheck the license and attribution requirements if an asset is replaced or
  downloaded from a different source.
- Do not treat the pack license as permission to copy another game's identity,
  characters, names, lore, or exact visual design.
