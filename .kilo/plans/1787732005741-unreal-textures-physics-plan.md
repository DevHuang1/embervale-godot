# Unreal-Style Textures & Physics — Embervale Mobile

## Goal
Push Embervale toward an Unreal-Engine feel on two fronts, tiered for mobile-first performance:

1. **Textures**: photo-scanned CC0 PBR surface sets driving terrain/rock/bark, with UE-Landscape-style height blending and parallax depth, layered *under* the existing realm-tint/wear overlay systems.
2. **Physics**: Chaos-style physical feedback — pooled impact debris, loot-dropping destructible props, tumble-corpse deaths (per-bone ragdoll for boss), and interactive vegetation.

All heavy features gated through `QualityScaler` tiers: HIGH = full effect, MEDIUM = cheaper variant, LOW = reduced/off. Renderer is Forward+ (`project.godot` has no override).

## Resolved decisions
- Texture source: **CC0 scanned PBR sets** (albedo+normal+roughness) + existing shader overlays for realm tinting/wear/rain.
- Death physics: **tumble corpses** (pooled whole-body RigidBody3D) for hushlings/fenlings; **per-bone ragdoll attempt only for the boss**, with automatic fallback to tumble if bone setup fails.
- Destructible props are **gameplay**: they drop small loot (embers/tonics).
- Perf priority: **mobile-first**; desktop/dev Mac gets everything on HIGH.

## Key existing systems to preserve (do not break)
- `WorldState` shader globals: `world_wear_map`, `world_hero_pos_radius`, `world_wind`, `world_rain_level`, `world_magic_level` (`scripts/autoload/world_state.gd`)
- `impact_director.gd` dispatch (weapon style × surface class) — debris hooks in here, it stays the single impact entry point
- `terrain_relief.gd` visual-only heightfield + flat BoxShape collider at y=-0.5 (grove.tscn); `height_at(x,z)` used by dressing
- `hushling.gd die()` flow: `died` signal must still fire (quest/XP depend on it)
- `quality_scaler.gd` hysteresis FPS monitor + persisted mode
- Realm palette table in `terrain_relief.gd` (`REALM_TERRAIN`) keeps driving biome colors

---

## Task 1 — Import CC0 PBR texture sets
Create `assets/textures/pbr/<set>/` with `albedo|normal|roughness` JPG/PNG per set, ~1K resolution (2K allowed only for ground sets):

| Set | Used by | Suggested source (any CC0 equivalent acceptable) |
|---|---|---|
| ground grass | terrain_grass layer | ambientCG Ground037 / ForestGround styles |
| ground dirt | terrain dirt layer | ambientCG Ground054 |
| ground sand | terrain sand layer | ambientCG Sand014 |
| ground rock | terrain stone layer + rock.gdshader | ambientCG Rock052 |
| bark | bark.gdshader triplanar | PolyHaven pine bark |
| wood planks | destructible crates | ambientCG Wood069 |
| clay/ceramic | destructible pots | ambientCG Clay / Terracotta |
| crystal | moonfen glowcaps | generated emissive ok |

- Add all licenses to a new `assets/textures/pbr/LICENSES.md`.
- **Offline fallback**: if network unavailable during implementation, extend `tools/generate_ground_textures.gd` to also emit matching normal+roughness maps at 1024px so downstream steps proceed; swap real scans in later without touching shaders (same filenames).
- Import settings: default (sRGB albedo, linear normal/roughness), mipmaps on, VRAM compress for mobile where Godot defaults apply.

## Task 2 — Terrain shader v3 (`assets/shaders/terrain_ground.gdshader`)
The samplers (`grass_tex/dirt_tex/sand_tex/rock_tex/ground_normal_tex`) already exist but nothing binds them. Upgrade and wire:

1. **Height-weighted layer blending** (UE Landscape style): give each layer a pseudo-height from its detail texture luminance + per-layer noise offset; blend with sharp `smoothstep` transitions driven by height difference (not just wide noise masks) so grass→dirt/rock edges show texture-level interpenetration.
2. **Parallax occlusion mapping** (HIGH tier): new uniforms `pom_enabled`, `depth_scale` (start 0.02–0.04), using the shared `ground_normal_tex`'s paired height or a new `ground_height_tex`; MEDIUM = simple parallax offset (single step); LOW = current analytic bump only.
3. **Per-layer roughness**: sample roughness maps; keep base `roughness` uniform as multiplier; darken+gloss shift scaled by `world_rain_level` (hook exists via ScreenFX wetness today—extend into terrain).
4. Preserve: wear-map splatting applied **after** POM UV offset (order matters), accent flecks, slope rock mask, crest color, distance smoothing.
5. Create `assets/materials/terrain_<realm>.tres` ShaderMaterials (one per realm palette) binding the new textures; update `terrain_relief.gd` REALM_TERRAIN table entries to reference them (keep runtime tint overrides working).

## Task 3 — Rock & bark triplanar upgrade
- `rock.gdshader`: replace/augment value-noise mottle with world-triplanar sampling of the CC0 rock set (albedo+normal+roughness); keep moss pooling, crevice AO, mineral glints.
- `bark.gdshader`: triplanar bark albedo+normal along trunk axis; keep furrow bump as detail layer, moon-rim emission unchanged.
- Both must stay MultiMesh-safe (world-position-based variation only).

## Task 4 — Debris system (new)
`scripts/systems/debris_system.gd` — instanced under `/root/WorldState` next to QualityScaler (or autoload; follow existing pattern):
- Pool of `RigidBody3D` shards, pre-warmed meshes: rock chip (tetra/irregular), wood splinter, leaf/grass bit, crystal shard, ceramic chunk.
- `spawn_burst(origin: Vector3, dir: Vector3, style: int, count: int)`; per-shard random spin, impulse spread around reflect(dir, normal).
- Shared `PhysicsMaterial` (bounce ~0.35, friction ~0.8); collision_layer = projectile(3)-adjacent free layer, mask = environment(6) only → debris never shoves characters.
- Sleep when slow; after lifetime (~2.5–3.5 s) shrink+fade tween → return to pool.
- Tier caps: HIGH 24 active, MEDIUM 12, LOW 6 (spawn calls clamp; never allocate beyond cap).
- Integrate: `impact_director.gd` gains debris payload per (weapon style × surface class): blunt→more chips, slash→splinters, magic→crystal motes; landing dust adds pebble chips on hard landings (`hero.gd _on_landed`); spell impacts (fire/frost/shock payloads) each emit their shard flavor.
- Test: `tests/test_debris_system.gd` (pool recycle, cap clamp, no allocation above cap) mirroring `test_impact_director.gd` headless style.

## Task 5 — Destructible props (loot)
New: `scripts/props/destructible_prop.gd` + `scenes/props/destructible_prop.tscn` (mesh swapped per variant: ember pot / root crate / moonfen glowcap).
- Body: `StaticBody3D` (environment layer) + child `Area3D` hitbox; `take_hit(amount, from_pos)` API; hit-flash via existing `hit_flash.gdshader`; 2–3 hits to break.
- On break: hide body → `debris_system.spawn_burst(...)` (ceramic/wood/crystal per variant) + shake via camera rig + SFX cue through AudioManager + spawn 1–2 loot pickups (existing pickup group; ember shards / occasional Moss Tonic) with small upward toss.
- Spawning: extend `grove_dressing.gd` `_build_realm_flavor()` (+ Bramblewood default) to place 8–14 props near the flattened landmark points already defined in `terrain_relief.gd` (reuse that list or expose it); snap to `height_at(x,z)`. Respawn props on realm re-entry (they're rebuilt with dressing anyway).
- Hero combat: ensure strike detection calls `take_hit` on nodes in group `"destructible"` inside AttackArea overlap (same pass that damages enemies).
- Test: `tests/test_destructibles.gd` — hits reduce hp, break emits loot + frees prop.

## Task 6 — Death physics
- **Tumble corpses** (hushling, fenling, future minions): in `die()`, keep `died.emit()` timing; replace final shrink-tween portion with: detach visible mesh(es) into a pooled `TumbleCorpse` RigidBody3D (script `scripts/systems/tumble_corpse.gd`), inherit material, impulse away from killer + angular velocity, collide with environment only, settle → sink+fade after ~2.5 s → pool. Blood-less, fits tone.
- **Boss**: try `PhysicalBoneSimulator3D` ragdoll on `boss_matriarch.fbx` skeleton at death (physical_bones on major bones, gravity takeover, one-shot). If the FBX rig lacks usable bone chain after tuning effort, fall back to tumble corpse (large-scale, slower fade). Time-box the true-ragdoll attempt; ship fallback without blocking.
- Tests: `tests/test_death_corpse.gd` — `died` still emitted once, corpse spawned, returned to pool; boss death path completes.

## Task 7 — Interactive vegetation
- Extend `world_state.gd` with `world_pushers : vec4[4]` global (xz = position, w = radius) fed each frame by up to 4 nearest movers (hero keeps priority slot; enemies/boss fill rest).
- `grass_blade.gdshader`: loop pushers, same bend-away falloff as hero trample; hero radius unchanged.
- Canopy: boss slam / thunder moments spike `world_wind` briefly (WorldState helper `gust(strength, duration)`) → visible canopy surge using existing sway path.
- Tier behavior: LOW = hero-only pushers (current behavior), MEDIUM/HIGH = 4.

## Task 8 — QualityScaler extension
Add per-level knobs alongside particle_scale (persisted in same cfg section):
- `debris_max` (6/12/24), `pom_mode` (off/offset/full), `vegetation_pushers` (1/4/4), `corpse_pool_size` (2/4/6), `contact_shadows` on key lights (off/off/on), destructible physics simplified on LOW (non-rigid pop + debris count 6).
- Extend degradation order docs; restore-from-cache pattern reused.
- Update `tests/test_quality_scaler.gd`.

## Task 9 — Post/lighting garnish (HIGH tier only, small)
- Contact shadows on sun + boss arena omni lights.
- Directional shadow blur/softness bump; SSAO intensity +0.2 on HIGH.
- Optional SSIL experiment flagged OFF unless frame budget holds on dev Mac (hrp_env.tres shows the pattern).
- No tonemap/exposure changes (ACES setup already good).

## Task 10 — Validation
- Headless: run all new + existing tests (`godot --headless --script tests/test_*.gd` pattern used by repo).
- Visual: `tests/diag_world_shot.gd` screenshots per realm at HIGH/MEDIUM/LOW; verify terrain layer edges, POM close-up, debris mid-burst.
- Manual F5 checklist: strike hushling (chips + tumble), smash pot (loot pops), boss kill (ragdoll-or-fallback), sprint through grass (bend), FPS holds ≥60 on dev Mac at HIGH.
- Update CHANGELOG.md per repo convention.

## Risks / mitigations
- **Network needed for CC0 downloads** → offline generator fallback (Task 1) unblocks everything else.
- **FBX boss rig may not ragdoll cleanly** → time-boxed, tumble fallback ships regardless.
- **POM + wear-map ordering bugs** → wear sampled after parallax offset; covered by realm screenshot check.
- **Mobile RigidBody cost** → strict caps, pooling, environment-only masks, sleep thresholds.
- **Branch state**: working tree has large uncommitted combat-skills-overhaul changes; implement on top or branch fresh — do not revert existing WIP.

## Out of scope
- Real-time virtual texturing / Nanite-equivalents (Godot lacks them).
- Cloth simulation, soft-body, vehicle physics.
- Replacing character ORM/normal generation pipeline (already good; minor mix tweaks only).
- Desktop-first features (SDFGI/SSIL shipping enabled by default).
