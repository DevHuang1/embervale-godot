# Scan → Forge Migration Plan

Status: proposed, not started. Decisions below were confirmed 2026-09-19.

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

## Risks and open questions

- Display re-theme names in the table above need sign-off.
- Family→blueprint mapping and tier costs need a first balance pass; top tier
  must stay reachable with free-earned materials.
- Back-socket relic mesh and relic trophy pedestal become dead paths — decide
  remove vs keep dormant in S5.
- Whether analysis should keep costing a charge (recommended yes, keeps the
  economy untouched) — revisit if blueprint progress feels slow in onboarding.
- Android camera permission entries in the export preset become unused once the
  camera is gone; clean up in S5.
