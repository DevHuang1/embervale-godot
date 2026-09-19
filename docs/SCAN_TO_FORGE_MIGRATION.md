# Scan → Forge Migration Plan

Status: implemented 2026-09-19 (S1–S5 complete; S6 verification below).
Decisions were confirmed 2026-09-19.

## Decision summary

- **Cut the camera scan entirely.** Camera capture fails on Android, and the
  "detection" is a random class pick with a fabricated confidence
  (`scripts/autoload/scan_manager.gd:108`, `scripts/ui/forge_menu.gd:292`), so
  the feature cannot ship honestly.
- **Replace it with a deterministic weapon loop:** analyze foes → unlock
  blueprints → forge with realm materials.
- **Rarity is deterministic from the material tier the player pays.**
- **The boss altar keeps its identity** (choose one rite + SFX) but uses trophy
  palettes unlocked by boss first-kills instead of a camera photo.
- **`scan_pack_5` was never published.** Remove the product; no grandfathering
  needed.
- **Keep the in-world Divining Lens.** Spending a charge to analyze a foe and
  reveal its bounded stats is real, readable, and stays.

## Player-facing loop

Before: point the camera at a real object → random "detected" class + fake
confidence → relic weapon named by the player; the boss altar used the photo
palette and silhouette.

After:

1. **Analyze foes** from the HUD combat card. Costs one lens charge, reveals
   exact stats (`Bestiary.scan_report`), and records blueprint progress for that
   foe's family.
2. **Unlock blueprints** through family analysis counts or boss first-kills.
3. **Forge** at the forge: pick a blueprint, pick the tier (= rarity) you pay
   for, name the weapon and its three rites, see the exact stat preview, commit.
   Costs are exact and deterministic; no randomized paid item exists anywhere in
   the loop.
4. **Shape the boss** at the altar: pick a trophy palette from a boss you have
   felled, plus one rite and an SFX preset.

P0 acceptance: Whispergrove onboarding must unlock the first blueprint and
deliver the first forge inside the first 15 minutes, and the visible weapon
upgrade must be reachable before Bramblewood.

## Non-goals

- No camera capture, no photo-to-mesh, no fake classification.
- No gacha, no paid random power, no diamonds spent on gameplay items
  (`EconomyCeilingCatalog` rule stays intact).
- No rigged or animated assets derived from captures.

## What stays (do not touch)

- `Bestiary.scan_report` (`scripts/systems/bestiary.gd:141`) and the HUD analyze
  flow; the entity reveal shader (`scan_reveal`,
  `scripts/entities/entity_animator.gd:204-219`) reads
  `/root/ScanManager.reveal_stamp_msec`.
- Save fields: `scans_remaining`, `scan_fragments`, `boss_first_kills`,
  `boss_customs`, `forged_weapons`; `content_schema.migrate_scan_state`
  (`scripts/systems/content_schema.gd:72`).
- Combat numbers: `RelicData.build_weapon_def` and `FORGE_RARITY_MULTS`
  (`scripts/entities/relic_data.gd:100`) remain the single stat source.
- Economy ceiling: scans stay free-earnable and non-critical; diamonds stay
  cosmetics-only (`scripts/systems/economy_ceiling_catalog.gd:4-8`).

## Design

### New data: `scripts/systems/forge_catalog.gd`

Pure data (RefCounted, no autoload dependencies — same pattern as
`diamond_catalog.gd` so headless audits can compile it).

**Blueprints (5).** Base ids must not change: forged inventory ids are
`relic_<base>` (`relic_data.gd:180`) and existing saves may hold them. Display
names are re-themed away from the camera-era jokes.

| base id | current display | proposed display | style / element |
| --- | --- | --- | --- |
| `mug_mace` | MUG MACE | Cinder Maul | blunt / fire |
| `pocket_blade` | POCKET BLADE | Shard Dagger | slash / shadow |
| `snip_twins` | SNIP TWINS | Twin Fangs | slash / shock |
| `soda_cannon` | SODA CANNON | Fen Scepter | magic / water |
| `slab_hammer` | SLAB HAMMER | Ashfall Maul | blunt / thunder |

Style and element stay authored in `relic_data.gd:125-145`
(`FORGE_STYLE_BY_BASE`, `FORGE_ELEMENT_BY_BASE`); do not duplicate them in the
new catalog beyond the unlock/cost tables.

**Unlocks.** Each blueprint requires either N analyses of a foe family or a boss
first-kill, checked with `GameState.has_boss_killed`
(`scripts/autoload/game_state.gd:1891`). Families map onto the kinds in
`Bestiary.VARIANTS` (`scripts/systems/bestiary.gd:90-121`):

| family | kinds |
| --- | --- |
| swarm | `hushling` |
| brute | `charger`, `thorn_charger` |
| caster | `spitter`, `spore_weaver` |
| stalker | `mire_stalker`, `fenling`, `ambusher`, `relic_leech` |
| warden | `ember_warden` |

Final counts and the exact blueprint↔family mapping are tuned in Slice 1 so the
first blueprint is reachable in Whispergrove.

**Tiers (0–4 = Common…Legendary).** Deterministic cost ladders built from
existing materials only: `iron_shard`, `bramble_wood`, `hushling_thorn`,
`beast_hide`, `spore_dust`, `fen_reed`, `moonmoss`, `crystal_fragment`,
`emberstone`, `monster_core`. Higher tiers require first-kill boss materials so
top rarities stay boss-gated. Exact bills are a Slice 1 balance pass.

### State and transaction: `scripts/autoload/game_state.gd`

- `analyzed_families: Dictionary` (family id → count). Saved with progress;
  tolerant load (dictionary-or-empty, matching the `boss_first_kills` pattern at
  `game_state.gd:3231-3232`); cleared in `_reset_progress`.
- `register_analysis(kind: String) -> Array` — called on a successful HUD
  analyze; increments the family counter and returns any newly unlocked
  blueprint ids.
- `forge_blueprint(blueprint_id, tier, item_name, skill_names) -> Dictionary`:
  1. validate blueprint, unlock state, and tier range;
  2. validate materials and deduct **exactly once**;
  3. build the def through `RelicData.build_weapon_def`;
  4. `add_weapon(def, true, message)`, `save_game()`;
  5. return `{success, message}`.
- Keep `forge_relic_weapon` (`game_state.gd:2804`) as a thin wrapper so any
  existing caller still works.
- Optional: enqueue a cloud intent for forging, mirroring `consume_scan`
  (`game_state.gd:2838`). Decide in Slice 1.

### UI

- `scripts/ui/forge_menu.gd`: remove the camera members (`:12-14`),
  `_start_camera_preview` (`:240-258`), `_on_scan_completed` (`:288-293`), and
  the four `ScanManager` signal connections (`:105-108`). Add a blueprint list
  (locked rows show requirement progress), a tier picker with the material
  bill, and a FORGE button. Keep the naming fields, the live preview
  (`:360-377`), and the `InputManager.scan_pressed` route (`:91`) so existing
  input bindings keep working.
- `scenes/ui/forge_menu.tscn`: remove the `CameraView` subtree; add the
  blueprint list and tier row; retitle the count label to lens charges.
- `scripts/ui/boss_altar.gd`: replace `_on_scan_pressed`/`_ingest_capture`
  (`:109-138`) with a trophy picker built from
  `Bestiary.BOSS_DEFS[BOSS_ID].trophies` filtered by `has_boss_killed`, reusing
  `_paint_palette_swatches` (`:140`). Keep the skill/SFX selection, the lock-in
  charge cost (`:192`), and the `boss_customization` payload shape.
  `idol_mesh` stays `null` so the boss keeps its authored silhouette
  (`scripts/entities/boss_customization.gd:14`).
- `scripts/systems/bestiary.gd`: add `trophies: [{id, name, palette}]` to the
  relevant `BOSS_DEFS` entries (one palette trio per boss-realm).
- `scripts/ui/hud.gd` copy: `:739`, `:1062-1063` become lens wording
  ("ANALYZE FOE · N LENS"). Keep the guard strings asserted by
  `tests/test_enemy_scan_once.gd` (`hud.gd:1112-1113`).

### Retire

- `ScanManager`: shrink to lens state. Keep `reveal_stamp_msec` and
  `relic_forged`/`last_relic` while any consumer remains. Remove camera members,
  `start_scan`, `_acquire_frame`, `capture_frame`, `_run_detection`,
  `_on_detection_complete`, `simulate_scan`, `CLASS_TO_WEAPON`,
  `min_confidence`, `scan_duration`, the progress tween, and the
  `scan_started`/`scan_progress`/`scan_completed`/`scan_failed`/`forge_completed`
  signals (only `forge_menu.gd` consumes them today — re-grep before removal).
- `scripts/systems/relic_forge.gd`: `forge()` and `extract_palette()` lose all
  callers once the camera is gone — delete the file and update
  `tests/test_boss_custom.gd:66`. `RelicData.mesh`/`texture` are not serialized
  (`relic_data.gd:57-69`), so keep the fields but decide what to do with the now
  dead back-socket and trophy paths: `hero.gd:2461-2471`, `:2572`, `:2767`,
  `world_manager.gd:113-115`, `:691`.
- IAP: remove `scan_pack_5` from `diamond_catalog.gd:11`,
  `diamond_shop.gd:313/330/338`, and `monetization_safety_audit.gd:32/37`.
  Replace `tests/test_scan_pack_product.gd` with a catalog audit that asserts
  only cosmetic kinds exist.
- Store: confirm no live SKU named `scan_pack_5` in Play Console / RevenueCat.
  `docs/REVENUECAT_*` is otherwise unaffected.

## Save compatibility

- Kept: `scans_remaining`, `scan_fragments`, `boss_first_kills`,
  `boss_customs`, `forged_weapons` (relic ids unchanged).
- Added: `analyzed_families`, defaulting to `{}` on old saves.
- Display names are migrated on load and on add: old saves that still carry the
  camera-era names for a canonical weapon id (MUG MACE → CINDER MAUL, POCKET
  BLADE → SHARD DAGGER, SNIP TWINS → TWIN FANGS, SODA CANNON → FEN SCEPTER,
  SLAB HAMMER → ASHFALL MAUL) are rewritten. Player-named relics (`relic_*`
  ids) and crafted names are never touched. Covered by
  `tests/test_legacy_weapon_names.gd`.
- Never serialized: camera frames, relic mesh/texture.
- Extend `content_schema.gd` with `migrate_analysis_state` and cover it in
  `tests/test_content_schema_scans.gd`.

## Test plan

Update:

- `tests/test_scan_economy.gd` — `start_scan()` no longer exists; assert analyze
  consumes exactly one charge, a zero-charge analyze is refused, and the
  fragment→charge conversion still fires.
- `tests/test_boss_custom.gd` — drop the `RelicForge.extract_palette` call
  (`:66`) in favor of an authored trophy palette; keep economy and
  `boss_customs` round-trip checks.
- `tests/test_weapon_catalog_complete.gd` — legacy normalization stays valid;
  update only the label text if it changes.

New:

- `tests/test_forge_blueprint.gd` — locked blueprint rejected; insufficient
  materials rejected with zero deduction; exact deduction on success; second
  craft fails without a second spend; same (blueprint, tier) yields identical
  stats; output def carries three skills.
- `tests/test_boss_trophies.gd` — trophy list gated by first-kill; altar payload
  shape unchanged.
- `tests/test_monetization_catalog.gd` — no diamond item grants gameplay.

Commands (per slice, then the full suite):

```sh
godot --headless --path . --script tests/test_forge_blueprint.gd
godot --headless --path . --script tests/test_scan_economy.gd
godot --headless --path . --script tests/test_boss_custom.gd
godot --headless --path . --script tests/test_boss_trophies.gd
godot --headless --path . --script tests/test_content_schema_scans.gd
godot --headless --path . --script tests/test_weapon_catalog_complete.gd
godot --headless --path . --script tests/test_enemy_scan_once.gd
godot --headless --path . --script tests/test_enemy_scan_report.gd
godot --headless --path . --script tests/test_monetization_catalog.gd
godot --headless --path . --editor --quit
```

## Slices and acceptance

| slice | scope | done when |
| --- | --- | --- |
| S1 | `forge_catalog.gd`, `GameState` state + transaction, `content_schema`, new/updated backend tests | forge tests pass; save round-trips with and without `analyzed_families` |
| S2 | ForgeMenu UI + scene; blueprint/tier/naming/preview; FORGE wired to `forge_blueprint` | menu flow works headless-safe; no camera references remain in the menu |
| S3 | Boss altar trophies + `Bestiary.BOSS_DEFS.trophies` | altar resolves with authored palette, `boss_customs` payload identical in shape |
| S4 | Economy/copy strings (`economy_ceiling_catalog`, HUD, forge, altar) | grep for camera/scan wording shows only in-world analysis language |
| S5 | Retire `ScanManager` camera paths, `relic_forge.gd`, IAP product + audit + store check | no dead camera/mesh code; monetization audit green |
| S6 | Full suite + editor import + route smoke | all tests below green; P0 route delivers first forge inside 15 minutes |

## Implementation record

Delivered:

- `scripts/systems/forge_catalog.gd` (new): five blueprints (base ids unchanged),
  family unlock rules, deterministic tier bills, trophy labels.
- `GameState`: `analyzed_families` (saved, migrated with
  `ContentSchema.migrate_analysis_state`), `register_analysis`,
  `is_blueprint_unlocked`, `unlocked_blueprint_ids`, `blueprint_progress`,
  transactional `forge_blueprint` (exact deduction, cloud intent, craft
  objective + onboarding hook).
- `ForgeMenu`: blueprint list with lock progress, tier picker with live material
  bills, naming + stat preview, FORGE wired to `forge_blueprint`. The retired
  `CameraView`, `Pipeline`, and `ScanButton` nodes and their camera/photo copy
  were removed from `forge_menu.tscn`; the same cleanup removed the altar's
  retired buttons and scan copy. The scripts keep a no-op cleanup fallback for
  older scene variants.
- `BossAltar`: trophy palette picker (starter palettes plus first-kill trophies
  in `Bestiary.BOSS_DEFS.matriarch.trophies`), skill/SFX choice, one lens charge
  on lock-in, same payload shape.
- `HUD`: analyze flow records blueprint progress, pulses the existing reveal
  shader, and shows newly unlocked blueprint names.
- Retired: camera capture paths and fake detection, `relic_forge.gd`, the
  `scan_pack_5` product and its shop/audit branches, and (final pass) the whole
  dormant relic-visual channel: `ScanManager.relic_forged`/`last_relic`,
  `Hero.current_relic`/`_on_relic_forged`/`_build_relic_hand_visual`, the
  world-manager trophy spawn plus its `_process` spin, and
  `RelicData.mesh`/`mesh_scene`/`texture`. `relic_pedestal` stays as the
  practice-altar anchor. Forged `relic_<base>` kits are now given a hand
  visual by `WeaponVisualRegistry.resolve_id`, which maps them to their base
  kit's model; the same pass routes every other registry-mapped weapon id
  (realm and boss rewards) through the in-hand mount instead of falling
  through the id match with no prop. Covered by
  `tests/test_weapon_mount.gd` (relic kit + `thornbite_cleaver`) and the
  relic-id assertions in `tests/test_weapon_model_scale.gd`; real Metal
  captures of two forged kits in hand via `tools/capture_weapon_props.gd`.
- First-15-minutes integration: the onboarding route now teaches `analyze`
  (lens → blueprints) before `craft`, the craft hint points at the forge, the
  HUD reports blueprint progress on every analysis
  (`GameState.analysis_progress_note`), and `tests/test_forge_early_route.gd`
  proves the T0 bill is one-pass reachable in Whispergrove and that two
  Whispergrove analyses unlock and forge the first weapon.

Deviations from the original plan:

- Starter trophies were added so the first Matriarch fight is customizable;
  first-kill trophies remain the progression reward.
- The hero's held props are CC0 models from `WeaponVisualRegistry`, not the
  camera-era procedural sculpts (those are now unreachable fallbacks). Two
  mappings were corrected for the new names — Cinder Maul uses the small hammer,
  Ashfall Maul the double hammer, Fen Scepter a polearm — the satchel preview
  now reads the same registry instead of its own drifting table (which also
  pointed at a missing `Staff.fbx`), and both hand and preview normalize each
  model by measured size (`WeaponVisualRegistry.normalized_scale`). The old
  hardcoded 0.012 quaternius constant had shrunk every mapped FBX to about
  5 cm in hand and hid it entirely in the preview. Verified with real Metal
  captures via `tools/capture_weapon_props.gd` and locked by
  `tests/test_weapon_model_scale.gd` (all 22 mapped models normalize to their
  authored length).
- `ScanManager.relic_forged`/`last_relic` stay as dormant API because `hero.gd`
  and `world_manager.gd` still subscribe; they simply never fire now.
- `tests/test_forge_camera_surface.gd` became
  `tests/test_forge_blueprint_surface.gd`; `tests/test_scan_pack_product.gd`
  became `tests/test_monetization_catalog.gd`.

Pre-existing issue found during verification (not caused by this change):
`scripts/systems/save_service.gd:25` uses a `PackedByteArray(...)` constructor
in a `const`, which some headless runner modes reject with
"isn't a constant expression". Normal game runs are unaffected; the file is
uncommitted work in progress.

Pre-existing failure found during verification (now fixed):
`tests/route_end_to_end_validation.gd` failed its indoor camera-pitch assertion
(70 passes / 1 failure) at committed HEAD `e13aa9c` and in the working tree.
Root cause was a test race, not a camera defect: entering a structure plays a
short camera focus moment that deliberately owns the framing, and the assertion
sampled `target_angle_v` while that cinematic was still live (or had just been
re-triggered a few frames later). Instrumented capture showed the rig reports
`_indoor = true` and clamps the pitch to -0.26 rad within a frame of the
cinematic ending. The test now cancels any live focus moment and waits (bounded)
for the steady indoor state before asserting, so it still fails if the clamp or
the indoor detection regresses. Route suite is 71 passes / 0 failures on three
consecutive runs.

Portrait pass (real Metal renderer, 1080x1920, `tools/capture_ui_portrait.gd`):

- First captures showed both menus overflowing horizontally: the forge tier row
  and the altar trophy row forced a minimum width wider than the frame, and the
  one-line stat string repeated the overflow, clipping every child.
- Fixed: tier and trophy rows are 3-column `GridContainer`s, the forge stat line
  is split (short headline + wrapped skill detail), the weapon icon mounts in
  the glyph slot instead of appending below the actions.
- Re-captured clean; `tests/test_ui_portrait_fit.gd` now fails if either menu's
  combined minimum width exceeds the portrait frame.

## Risks and open questions

- Display re-theme names in the table above need sign-off.
- Family→blueprint mapping and tier costs need a first balance pass; top tier
  must stay reachable with free-earned materials.
- Back-socket relic mesh and relic trophy pedestal dead paths: removed in the
  final cleanup pass; the pedestal itself stays as a landmark/anchor.
- Whether analysis should keep costing a charge (recommended yes, keeps the
  economy untouched) — revisit if blueprint progress feels slow in onboarding.
- Android camera permission entries in the export preset become unused once the
  camera is gone; clean up in S5.
