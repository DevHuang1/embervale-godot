# Embervale Transcendent Vision — All Phases Implementation Plan

Date: 2026-08-25
Scope: Implement the full 8-phase sensory/gameplay upgrade (WorldState, ambient life, combat feedback, living canvas, audio, model evolution, player agency, performance) as one dependency-ordered workstream.

## Ground Truth (verified in repo — supersedes the earlier chat blueprint)

- Godot **4.7**, portrait mobile game (`project.godot`: 1080x1920, name "Embervale Mobile"). No explicit `rendering_method` override → editor default applies; env resource uses **SSAO + volumetric fog** (Forward+/Mobile-renderer-dependent features). Phase 0 verifies this.
- **Post-processing already exists**: `assets/environments/embervale_env.tres` ships ACES tonemap (mode 3, exposure 1.32), tuned glow levels, SSAO, height+fog+volumetric fog, adjustments. **Do NOT build the custom canvas-item ACES/bloom shader from the earlier chat** — it was broken and duplicates built-ins. Realm grading extends Environment params instead.
- **All models are procedural primitives**: characters are primitive rigs animated by `EntityAnimator` (BIPED/BLOB/BRUTE) with an existing LOD system (`lod_distance`, silhouette swap at LOD2); vegetation is seeded MultiMesh batches in `GroveDressing`. "Model improvements" = mesh composition, materials, shader params — no FBX re-exports exist or are needed.
- **Weapons are Dictionaries** in `GameState.WEAPON_DEFS` (+ relic-forged defs via `RelicData.build_weapon_def`). No WeaponData class; **no element concept yet**.
- **Combat feedback skeleton exists**: `CombatFx` static toolkit (pooled bursts/rings/slash/telegraph/bolt/pillar/motes/shockwave/charge/decal + `impact()` director for shake+hit-stop+chroma), `ScreenFX.punch_chroma/pulse_vignette`, `CameraRig.add_shake/play_kill_cam/play_boss_intro`, perfect-dodge slow-mo precedent in `hero.gd`.
- **AudioManager is a full procedural synth engine** (named cues rendered to cached WAVs via `assets/audio/audio_config.tres`, positional `play_synth_at`, ambient beds "grove"/"fen", boss `SFX_PROFILES`). Reactive music = synthesize layers; no external assets required.
- `grass_blade.gdshader` already exposes a `wind_zone` uniform "WorldManager can drive for weather/realm gusts" — currently undriven.
- `entity_body.gdshader` is a strict-superset PBR shader (`flash_intensity`, `scan_reveal`, rim, SSS, joint AO) — extend with new default-off uniforms only.
- Autoloads: GameState, ScanManager, AudioManager, InputManager. `BiomeManager extends WorldManager`; realms/tiers live in `Bestiary.REALMS/WAVES/biome()`.
- Tests are headless SceneTree scripts: `godot --headless --path . --script tests/test_X.gd`.

## Architecture Decisions

1. **New lightweight autoload `WorldState`** (scripts/autoload/world_state.gd) that subscribes to existing signals (GameState.combat_state via engage/disengage, hp_changed; ScanManager.relic_forged; day-night night factor polled) — GameState stays untouched except zero schema changes in this phase.
2. **Shader globals via `RenderingServer.set_shader_parameter`** published once per frame from WorldState: `world_combat_intensity` (float 0-1, decayed), `world_magic_level` (float), `world_biome_tint` (Color), `world_wind` (vec2 dir*strength), `world_hero_pos_radius` (vec3+radius), plus a wear-map sampler (Phase 3). Defaults set in WorldState._ready so shaders never sample unset globals.
3. **Session-only persistence** for wear map and corruption (no save-schema churn; can persist later behind `progress/` keys if desired).
4. **Boss evolution is cosmetic-first** (emissive/attachment/anim changes on phase transitions), reusing `AttachmentSocket` and the existing heart-emissive hook in EntityAnimator; combat stat changes limited to speed multipliers already supported by variants.
5. **Realm grading through DayNightCycle** (it owns the runtime Environment copy — exactly one mutator, keep it that way): add per-realm tonemap/adjustment/glow biases next to existing `apply_realm()`.
6. Element effects use only existing CombatFx primitives + new cues; no new VFX framework.

## Implementation Phases (ordered; each keeps headless suites green)

### Phase 0 — Foundations
1. Verify renderer: confirm `forward_plus` vs mobile renderer behavior for SSAO/volumetric fog on the Android export preset; record findings in docs/MODEL_PIPELINE.md-adjacent note. If Compatibility is the shipping target, gate SSAO/volumetric-fog writes in DayNightCycle behind `RenderingServer.get_current_rendering_method()` checks.
2. Create `scripts/autoload/world_state.gd` (autoload entry after ScanManager in project.godot):
   - State: `combat_intensity` (rises on engage/hit signals, exponential decay ~0.25/s), `magic_level` = f(DayNightCycle night factor, relics forged this session), `biome_tint` from Bestiary realm of current scene, `wind` vector (Phase 4 driver).
   - Publishes shader globals each frame (cheap: ~6 uniforms).
   - Public API: `notify_impact(strength)`, `notify_relic_forged()`.
3. Expose `night_factor` as a cached property on DayNightCycle (computed in `_apply()`), so WorldState polls without duplicating gradient math.

### Phase 1 — Reactive world visuals (shader-global payoff)
1. `entity_body.gdshader`: add default-off uniforms reading globals — subtle rim/emission lift scaled by `world_magic_level` at night; grime-free. Keep strict-superset rule.
2. `ScreenFX`: vignette micro-pulse proportional to `world_combat_intensity` (cap well below low-HP vignette).
3. `DayNightCycle.apply_realm()` extension: per-realm `adjustment_contrast/saturation` and `glow_intensity` bias table in Bestiary.REALMS; lerp over ~2s on realm change.
4. Fireflies/mist: `amount_ratio` additionally scaled by magic_level (multiply with existing night crossfade, never exceed base amounts).

### Phase 2 — Combat as a sensory event
1. New `scripts/systems/impact_director.gd` (static helper beside CombatFx): maps (weapon style blunt/slash/magic × surface class flesh/plant/stone) → {cue name, VFX color, burst shape, shake, hitstop}. Wire into hero auto-strike/skill payload moments and hushling counter-strikes where CombatFx calls already happen.
2. Elements on relic weapons: `RelicData.build_weapon_def` accepts element derived from scanned class (CLASS_TO_WEAPON mapping extended with element per family: fire/frost/shock/nature). Payload effects at impact:
   - fire → `spawn_decal` scorch + ember burst + lingering motes;
   - frost → `spawn_ring` pale ring + brief enemy tint via entity_body uniforms (roughness/emission);
   - shock → jagged stretched bursts chained between nearby enemies (reuse bolt primitive, 2 hops max);
   - nature → spore motes + green pillar on kill.
3. Bloom crits (every third strike) and skill finishers: short time-scale breath (pattern exists in perfect-dodge code) + `ScreenFX.punch_chroma`.
4. AudioManager: add 4 element cues + 2-3 surface-differentiated impact cues to `_render_cue()` and `audio_config.tres`.

### Phase 3 — World as living canvas
1. `TerrainWear` node (in world scenes via WorldManager._ready): 256x256 FORMAT_R8 ImageTexture spanning the play area; `record(pos, strength)` splats small kernels; publishes as shader global `world_wear_map`. Update image + upload throttled (max ~10 Hz).
2. `terrain_ground.gdshader`: default-off `uniform sampler2D wear_map`; darken/desaturate albedo + raise roughness where worn. Session-only reset on scene load.
3. Grass interaction: `grass_blade.gdshader` reads `world_hero_pos_radius` global; radial push-away bend in `vertex()` clamped to blade tip weight (`v_h`). Zero cost when radius uniform = 0.
4. Canopy/bark get the same wind global hookup used by grass (single source of truth for gusts).

### Phase 4 — Ambient life, weather & reactive audio
1. `WindDriver` (owned by WorldState): idle breeze baseline + gust envelopes (Perlin-ish noise walk); storms during high combat_intensity or scripted boss intro. Writes `world_wind` global (drives existing `wind_zone`-style bending).
2. Rain (optional toggle, default off on low-end): camera-following GPU particle cylinder + screen_fx wetness uniform (subtle specular sheen streaks); fog_add bump through DayNightCycle stage-bias mechanism.
3. Adaptive fireflies: flee vector away from hero within 2.5u (offset process_material emission box center), brightness follows magic_level.
4. `AudioDirector` (small node added by WorldManager/BiomeManager): renders a 12s tense "combat bed" loop at startup (extend AudioManager bed renderer), crossfades ambient↔combat beds by combat_intensity; low-pass cutoff eases down at night (bus effect on Music bus). Footsteps/impacts already surface-aware — extend to element-wet surfaces when rain is on.

### Phase 5 — Model evolution & boss spectacle
1. BossBase phase transitions emit `phase_changed(index)`; Matriarch handler: raises EntityAnimator animation rate multiplier, boosts heart emissive energy (existing `_heart_base_energy` hook), attaches spore-cluster meshes via AttachmentSocket, triggers stomp shockwave VFX + camera rumble.
2. Damage wear: entity_body gains default-off `hp_ratio` uniform path — albedo darkens and roughness rises below 40% HP (applied to bosses + hushlings; hero armor tint already restyles body).
3. Hero aura cosmetics pulse with magic_level (existing active_aura_color plumbing).

### Phase 6 — Player agency: relic environment effects
1. On `ScanManager.relic_forged`: trophy pedestal gains element-typed ambience (pillar color/motes per element), WorldState.scan_depth++ → firefly brightness bonus.
2. Beacon-lit state biases weather calm + warm adjustment grade (extend STAGE_BIAS with a "complete" weather lock flag).

### Phase 7 — Performance & adaptive quality
1. `QualityScaler` node (autoload or per-scene): FPS EMA monitor with hysteresis; degradation order: rain off → particle amount_ratio down → SSAO off → volumetric fog density halved → EntityAnimator LOD distance shortened → DOF off. Restores with headroom. Settings menu: Low/Auto/High (persist via AudioManager-style settings cfg).
2. Pool hygiene: cap CombatFx particle pool (~24), reuse AudioStreamPlayer for non-positional cues (current code allocates per play).
3. Budget guardrails: all new per-frame work is uniform writes + one EMA check; no allocations in _process.

## Out of Scope (explicitly rejected from earlier blueprint)
- Custom canvas-item ACES/bloom/LUT post chain (duplicates Environment built-ins; proposed code was invalid GDScript/godot-shader).
- Vertex-color wear masks / FBX mutation slots (no imported skeletal models exist).
- Fire/Ice/Plant/FireManager simulation systems (element FX are momentary + decal-level).
- SDFGI/GTAA/ray-traced anything (mobile budget).
- Persisting wear/corruption to save file (later, behind product decision).

## Risks
- Renderer feature availability on Android export → Phase 0 verification gates everything visual; QualityScaler degrades gracefully regardless.
- Shader-global naming collisions → prefix `world_`, set defaults before any scene loads.
- GameState is save-critical → no schema changes in this workstream.
- Old-device GPU particle limits → mirror DayNightCycle's amount_ratio pattern; keep counts ≤ current bases.

## Validation
1. Existing suites green (zero SCRIPT ERROR / FAIL lines):
   - `godot --headless --path . --script tests/test_vfx_ui_smoke.gd`
   - `godot --headless --path . --script tests/test_combat_recovery.gd`
   - `godot --headless --path . --script tests/test_anim_state_reset.gd`
   - `godot --headless --path . --script tests/test_weapon_mount.gd`
   - `godot --headless --path . --script tests/test_boss_custom.gd`
   - `godot --headless --path . --script tests/test_biomes.gd`
2. New suites mirroring repo style:
   - `tests/test_world_state.gd` — intensity rise/decay math, signal wiring, globals set.
   - `tests/test_impact_director.gd` — style×surface→profile mapping, element dispatch, cue existence in config.
   - `tests/test_terrain_wear.gd` — splat writes, texture upload throttle, reset on reload.
   - `tests/test_quality_scaler.gd` — degradation ordering + hysteresis with simulated FPS.
3. Manual: 10-minute portrait playthrough on device targeting 60 FPS; verify rain/wind toggles, boss phase visuals, relic trophy ambience.

## Open Questions (non-blocking)
- Final Android renderer choice (affects whether SSAO/volumetric fog ship enabled or fall back) — resolve during Phase 0.
- Whether corruption/wear ever persist across sessions — product call, deferred.
