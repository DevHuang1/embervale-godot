# Third-Party Notices

The MIT license in [`LICENSE`](LICENSE) covers Embervale's own source code,
scenes, and project-authored data. Third-party assets bundled with the project
are **not** covered by it: each asset pack keeps its own license and
attribution.

Every imported asset set ships with its upstream license file (or a per-set
`SOURCE.txt`). The per-pack inventory in
[`ASSET_CREDITS.md`](ASSET_CREDITS.md) repeats this list with import details;
the table below is the canonical record of source, license, and download date.

## Bundled asset packs

| Pack | Bundled content | License | Downloaded | Source |
|---|---|---|---|---|
| Kenney Nature Kit | trees, rocks, logs, mushrooms | CC0 1.0 | 2026-09-08 | https://kenney.nl/assets/nature-kit |
| Kenney Graveyard Kit | altar, coffin, candle, fence, graves | CC0 1.0 | 2026-09-08 | https://kenney.nl/assets/graveyard-kit |
| Kenney Survival Kit | barrel, bedroll, bottle, fence, tent | CC0 1.0 | 2026-09-08 | https://kenney.nl/assets/survival-kit |
| Kenney Tower Defense Kit | crystal, rocks, tree detail | CC0 1.0 | 2026-09-08 | https://kenney.nl/assets/tower-defense-kit |
| Kenney Mini Dungeon | human/orc characters, dungeon props | CC0 1.0 | 2026-09-08 | https://kenney.nl/assets/mini-dungeon |
| Kenney Foliage Sprites | grass, flowers, foliage billboards | CC0 1.0 | 2026-09-08 | https://kenney.nl/assets/foliage-sprites |
| Kenney Castle Kit | castle walls, towers, roofs, gate, stairs, flags | CC0 1.0 | 2026-09-18 | https://kenney.nl/assets/castle-kit |
| Kenney Fantasy Town Kit | town/roof/wall modules for realm dressing | CC0 1.0 | 2026-09-18 | https://kenney.nl/assets/fantasy-town-kit |
| KayKit Dungeon Remastered (Kay Lousberg) | interior floors, walls, doorways, stairs, props | CC0 1.0 | 2026-09-18 | https://kaylousberg.com/ |
| Quaternius Animated Monsters | structure bosses (skeleton warden, matron slime, sealed dragon, bat) | CC0 1.0 | 2026-09-18 | https://quaternius.com/ |
| Quaternius Medieval Weapons | hammer and dagger runtime hand-weapon fallbacks | CC0 1.0 | 2026-08-29 | https://quaternius.com/packs/medievalweapons.html |
| Quaternius Animated Animals | frog, rat, snake, spider, and wasp realm enemies | CC0 1.0 | 2026-08-29 | https://quaternius.com/ |
| Poly Haven surfaces — cobblestone_floor_05 | interior stone (1K albedo/normal/roughness) | CC0 1.0 | 2026-09-18 | https://polyhaven.com/a/cobblestone_floor_05 |
| Poly Haven surfaces — wood_floor_worn | interior wood (1K albedo/normal/roughness) | CC0 1.0 | 2026-09-18 | https://polyhaven.com/a/wood_floor_worn |
| Poly Haven surfaces — grass_ground | exterior grass (1K albedo/normal/roughness) | CC0 1.0 | 2026-09-18 | https://polyhaven.com/a/grass_ground |
| Poly Haven surfaces — rock_face | exterior rock (1K albedo/normal/roughness) | CC0 1.0 | 2026-09-18 | https://polyhaven.com/a/rock_face |
| Poly Haven surfaces — thatch_roof_angled | exterior thatch (1K albedo/normal/roughness) | CC0 1.0 | 2026-09-18 | https://polyhaven.com/a/thatch_roof_angled |
| Poly Haven terrain PBR sets (7) | grass, dirt, sand, rock, bark, wood, clay | CC0 1.0 | 2026-08-26 | https://polyhaven.com/ (per-set URLs in `assets/textures/pbr/LICENSES.md`) |
| Cinzel, Manrope fonts | variable UI/display type | SIL OFL 1.1 | 2026-08-26 | https://github.com/google/fonts |
| PressStart2P, VT323 fonts | pre-existing display type | SIL OFL 1.1 | pre-existing | https://github.com/google/fonts |

CC0 1.0 terms: https://creativecommons.org/publicdomain/zero/1.0/ — public
domain dedication, no attribution required; packs are credited anyway.

## Bundled components

| Component | License | Terms |
|---|---|---|
| Godot Engine runtime | MIT | Bundled by the Godot export template |
| RevenueCat `purchases-android` SDK | MIT | Linked into the Android plugin AAR |
| RevenueCat Godot bridge plugin (`android-plugin/revenuecat_bridge`) | MIT | Project-authored; wraps the RevenueCat Android SDK |

## Notes

- Local license records: Kenney kits → `assets/models/kenney_*/License.txt`
  (foliage: `assets/ambient/kenney_foliage_sprites/License.txt`); KayKit →
  `assets/models/kaykit_dungeon/LICENSE.txt`; Quaternius →
  `assets/models/quaternius_monsters/License.txt`,
  `assets/models/weapons/quaternius/LICENSES.md`,
  `assets/models/enemies/quaternius/LICENSES.md`; Poly Haven 1K sets →
  `assets/textures/cc0/<set>/SOURCE.txt`; Poly Haven terrain sets →
  `assets/textures/pbr/LICENSES.md`; fonts → `assets/fonts/LICENSES.md`.
- Assets generated for this project (for example the stylized terrain surfaces
  under `assets/textures/stylized/`) are project-owned; their provenance is
  recorded in `ASSET_CREDITS.md`.
- Recheck the license and attribution requirements if an asset is replaced or
  downloaded from a different source.
