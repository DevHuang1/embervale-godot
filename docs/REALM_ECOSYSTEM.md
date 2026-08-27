# Embervale Realm Ecosystem Upgrade

## Scope

The realm-generation pass adds biome-specific terrain response, deterministic ecological zones, multilayer procedural foliage, and unique non-gameplay landmarks while preserving the existing `GroveDressing`, authored character rigs, combat feedback, lantern behavior, and mobile-oriented rendering strategy.

The implementation is centered on [`RealmEcosystem`](../scripts/systems/realm_ecosystem.gd), which is attached beneath `ForestBorder` by [`GroveDressing`](../scripts/systems/grove_dressing.gd). The generator is static after construction: small foliage is visual-only, uses `MultiMeshInstance3D`, and does not create collision bodies or per-asset physics nodes.

## Terrain texture blending

[`terrain_ground.gdshader`](../assets/shaders/terrain_ground.gdshader) retains its existing grass, dirt, sand, and rock PBR layer blending. The new realm layer is applied after those four weights have been resolved, so realm identity augments rather than replaces the established terrain material.

| Shader parameter | Purpose | Example realm behavior |
|---|---|---|
| `realm_tint` | Broad color identity applied to the blended PBR result | Moonfen uses a cool blue-green tint; Heartwood uses a warm ember tint |
| `realm_tint_strength` | Limits the broad tint contribution | Stronger in Moonfen than Bramblewood |
| `moisture_strength` | Controls localized wet response and the moisture contribution to moss coverage | Highest in Moonfen, low in Heartwood |
| `moss_color` | Realm-specific moss/ground accent | Teal-green in fen realms, earthy in Bramblewood |
| `moss_strength` | Maximum moss overlay contribution | Increased in Moonfen and Mistfen |

The shader derives a low-frequency `realm_field` and a higher-frequency `moisture_field`. A smooth moisture mask drives both a restrained albedo wet sheen and a lower roughness response. This keeps moisture visible without flattening the four existing PBR texture layers or making the entire terrain uniformly dark.

## Ecological zone algorithm

The zone map uses a deterministic jittered-cell layout. A square grid is generated at `cell_size` spacing, and each cell receives a seed-derived two-dimensional offset. Points outside the realm radius are discarded. Each remaining point is classified using the following noise layers:

1. **Macro moisture FBM:** four octaves at a broad scale determine wet versus dry ecological character.
2. **Density FBM:** four octaves at a tighter scale determine meadow, deep-grove, and undergrowth density.
3. **Radial edge field:** a smooth radius transition creates the `realm_edge` band near the outer perimeter.
4. **Gameplay clearing rule:** the center and reserved anchors are always classified as `clearing`, keeping the player and authored encounter positions readable.
5. **Realm bias:** Moonfen and Mistfen promote low-moisture points to `raised_island` and high-moisture points to `damp_hollow`; Heartwood promotes high-density points to `deep_grove`.

The current zone identifiers are `clearing`, `meadow`, `deep_grove`, `damp_hollow`, `realm_edge`, and `raised_island`. The same realm id and seed reproduce the same point ordering, zone membership, landmark ids, and landmark positions.

## Foliage batching and density tiers

Foliage is grouped into five bounded batches: trees, canopies, understory, groundcover, and deadwood. Each batch shares a procedural mesh and material, and each instance is represented only by a `Transform3D` in a `MultiMesh`. The generator assigns visibility-range ends of 96, 72, 54, and 70 world units across the layers, with small visual layers also disabling shadow casting.

The density setting is clamped to `0.5–2.5`. Baseline density uses the original jittered candidate population; dense and stress settings add deterministic satellite candidates around ecological points. Layer budgets scale with density and remain capped by exported per-layer maxima, preventing an unbounded foliage explosion on mobile hardware. No claim of iOS GPU performance is made from the headless results below; those results validate generation correctness, batching shape, and CPU-side smoke behavior only.

## Landmark selection

Each realm has a small authored landmark library with realm-specific ids and visual forms. A candidate is accepted only when it is outside the reserved gameplay anchors and sufficiently separated from all previously accepted landmarks. Candidate scoring combines a deterministic FBM score with a mild mid-radius bias, producing stable but non-grid-like placement.

Landmarks are lightweight `Node3D` groups containing a few mesh children. They are visual set dressing rather than gameplay blockers, so they do not add navigation or collision cost. Current identity examples include `heartwood_altar`, `rootway_arch`, and `leafwell_shrine` for Bramblewood, plus `drowned_watch`, `glowcap_basin`, and `mire_shrine` for Moonfen.

## Validation and benchmark results

The deterministic validation scene is [`realm_ecosystem_validation.tscn`](../tests/realm_ecosystem_validation.tscn). It checks same-seed landmark stability, landmark id stability, reserved-anchor avoidance, minimum separation, four-or-more MultiMesh batches, terrain ShaderMaterial configuration, and realm-specific tint/moisture differences. The final run completed with **47 passes and 0 failures**.

The dense-forest benchmark is [`realm_ecosystem_benchmark.tscn`](../tests/realm_ecosystem_benchmark.tscn). It loads Grove and Moonfen at baseline, dense, and stress settings, samples 45 frames, and writes `user://realm_ecosystem_benchmark.json`.

| Realm | Density | Generation ms | Batches | Total instances | Populated zones | Frame p95 ms | Frame max ms | Budget overruns |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Grove | 1.0 | 2405.84 | 5 | 469 | 5 | 8.88 | 9.14 | 0 |
| Grove | 1.5 | 1794.33 | 5 | 935 | 5 | 8.22 | 8.81 | 0 |
| Grove | 2.0 | 1796.83 | 5 | 1414 | 5 | 8.48 | 9.28 | 0 |
| Moonfen | 1.0 | 1535.59 | 5 | 490 | 5 | 8.21 | 8.38 | 0 |
| Moonfen | 1.5 | 1524.00 | 5 | 971 | 5 | 8.39 | 9.16 | 0 |
| Moonfen | 2.0 | 1549.08 | 5 | 1450 | 5 | 8.78 | 11.09 | 0 |

The benchmark completed with `ECOSYSTEM_BENCHMARK_RESULT=PASS`. The measurements were taken with Godot’s headless dummy renderer, so they should not be interpreted as a substitute for an iPhone/iPad GPU capture. A real-device pass should still inspect GPU frame time, thermal throttling, overdraw, and memory residency at the stress tier.

## Reproduction commands

From the project root, run the following commands with the installed Godot binary:

```text
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --scene res://tests/realm_ecosystem_validation.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --scene res://tests/realm_ecosystem_benchmark.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 30 --scene res://scenes/world/grove.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 30 --scene res://scenes/world/moonfen.tscn
```

The bounded Grove and Moonfen smoke tests completed without script, parser, invalid-call, or missing-node errors, and the existing combat feedback validation and benchmark remained passing after the realm changes.

## Project references

The implementation and validation sources are linked here for maintainers:

- [`RealmEcosystem`](../scripts/systems/realm_ecosystem.gd) — seeded zone, foliage, material, and landmark generation.
- [`GroveDressing`](../scripts/systems/grove_dressing.gd) — lifecycle integration and density forwarding.
- [`terrain_ground.gdshader`](../assets/shaders/terrain_ground.gdshader) — four-layer PBR terrain plus realm/moisture response.
- [`realm_ecosystem_validation.gd`](../tests/realm_ecosystem_validation.gd) — deterministic layout and material assertions.
- [`realm_ecosystem_benchmark.gd`](../tests/realm_ecosystem_benchmark.gd) — Grove/Moonfen dense-forest benchmark.

[1]: ../scripts/systems/realm_ecosystem.gd "RealmEcosystem implementation"
[2]: ../assets/shaders/terrain_ground.gdshader "Terrain ground shader"
[3]: ../tests/realm_ecosystem_benchmark.gd "Realm ecosystem benchmark"
