# CHANGELOG — Visual & Audio Overhaul (drop-in pass)

Scope note: sculpted meshes, hand-painted 2048² sheets and recorded 48 kHz WAV
masters require DCC tools and are out of scope for a code terminal. Everything
below is fully generated, drop-in compatible, and regenerable/replaceable:
any PNG under `assets/textures/generated/` can be swapped for a painted master
at the same path without touching materials or code.

## Entity material realism pass (v3)
- M assets/shaders/entity_body.gdshader - v3 drop-in superset: per-clone albedo_variation / variation_seed tonal+hue roll, micro_roughness world-space grain, rain_response shared with the world_rain_level downpour, emission_pulse_speed breathing for weak points, and a secondary detail_tex layer for bark+stone and clay+crust hybrids. All default OFF so prior materials render identically until bound.
- M entity_hushling.tres - clone tonal variation + micro roughness + rain
- M entity_boss.tres - bark/stone secondary albedo layer, heart pulse, rain
- M hushling_eye.tres - glossier lens + breathing weak-point glow
- M entity_hero.tres, entity_hero_ember.tres - micro roughness + rain
- M scripts/entities/entity_animator.gd - duplicates the shared enemy material per clone with a unique seed (shared .tres stays pristine)
- M scripts/systems/loot_drop.gd - gold drops render as warm shaded metal

## Shaders
- **M** `assets/shaders/entity_body.gdshader` — v2, strict superset: albedo /
  normal / ORM (R=AO G=Rough B=Metal) / emission-mask inputs with mix factors,
  tiled detail normal, rim_width shaping, cheap SSS wrap (fungal pods),
  scan_reveal dirt-scanline overlay. All prior uniforms & outputs unchanged at
  defaults → existing `.tres` files render identically until bound.
- **A** `assets/shaders/lantern_flame.gdshader` — layered noise flame,
  two-clock flicker, `sway_vec` uniform fed from EntityAnimator's pendulum.
- **A** `assets/shaders/fog_card.gdshader` — soft mist cards, sky-palette tint,
  near/far distance fade (pairs with `scenes/world/fog_bank.tscn`).
- **M** `assets/shaders/grass_blade.gdshader` — `wind_zone` gust vector for
  WorldManager weather + tip gloss; defaults keep the old look.
- **M** `assets/shaders/water_fen.gdshader` — fine chop detail, voronoi
  caustics in shallows, depth-fade shoreline foam. Planar reflections: add a
  ReflectionProbe over the fen (grazing roughness already tuned to catch it).

## Materials
- **M** `entity_hero.tres`, `entity_boss.tres`, `entity_hushling.tres` — bound
  to generated normal/ORM/emission sets; hushling gets SSS pods; boss heart
  mask gates its pulse.
- **A** `entity_hero_ember.tres` — "ember-forged" hero tier variant (hotter
  veins, lower roughness, warmer base/rim).
- **A** `master_character.tres` — neutral look-dev master instance base.
- **A** `fog_bank.tres` — fog card material.

## Textures (procedural masters)
- **A** `tools/generate_character_textures.gd` — offline foundry (FastNoiseLite
  → PNG). Run: `Godot --headless --path . --script tools/generate_character_textures.gd`
- **A** `assets/textures/generated/`: `hero_normal|orm|emission_mask`,
  `hero_ember_normal|orm|emission_mask`, `boss_bark_normal|orm|heart_mask`,
  `hushling_emission_mask`, shared `detail_grain`, `detail_normal`,
  `hero_height_master`. Regenerate at any resolution by editing the tool.

## Audio
- **A** `scripts/autoload/audio_cue_config.gd` + **A** `assets/audio/audio_config.tres`
  — cue table (volumes, pitch windows, buses, variant counts) per the SFX brief.
- **M** `scripts/autoload/audio_manager.gd` — synth cue engine: seeded
  multi-variant rendering (footsteps ×3/surface, swing stages ×2, …), tone/
  sweep/hum/noise/crackle/whoosh primitives, `play_cue()` honoring config,
  positional `play_synth_at()` (distance attenuation), grove + **new fen**
  ambient beds (loop-locked bubbles), beds mixed under combat on the Music bus.
  New API: `play_footstep_surface`, `play_swing_stage`, `play_lantern_hum/_creak`,
  `play_boss_stomp/_death`, `play_ui_confirm/_cancel`, `play_forge_success`.
  Existing methods (`play_slash`, `play_magic_cast`, `play_dash`,
  `play_enemy_telegraph/special`, `play_explosion`) now route through richer
  cues with identical signatures.

## Script integration (motion + hooks; APIs preserved)
- **M** `entity_animator.gd` — idle weight-shift after ~2 s; dodge-roll
  squash→stretch curve; landing knee-bend recovery in `notify_land()`;
  BLOB micro-spin `trigger_spin()`; pounce root-lunge; BRUTE footfall signal +
  breathing-chest + hollow-heart emissive pulse synced to the lumber;
  LOD levels (0 full / 1 reduced / 2 silhouette bob) with optional
  `silhouette_material` swap; pushes shader `scan_reveal` after lens reveals;
  `pendulum_speed()` exposed.
- **M** `hero.gd` — combo-stage whooshes, surface-aware footsteps (realm →
  grass/mud/stone), element-matched double blade-trail ribbons, lantern creaks
  when the pendulum swings hard.
- **M** `hushling.gd` — hypnotic tendril spiral, direction-change spin call,
  death spore-wilt layer.
- **M** `boss_base.gd` — footfall → camera shake + dust + stomp cue
  (profile-aware); death plays bark-crumble under the locked victory sting.
- **M** `combat_fx.gd` — `spawn_burst()` gained optional `gravity` (default unchanged).
- **M** `scan_manager.gd` — static `reveal_stamp_msec` drives the scanline.

## Scenes / environments
- **A** `assets/environments/hrp_env.tres` + **A** `scenes/dev/hrp_reference.tscn`
  — HRP look-dev reference: ACES tonemap, volumetric fog (god rays via key
  light density), glow, SSAO/SSIL, SDFGI, warm key + cool rim lights, fog banks.
- **A** `scenes/world/fog_bank.tscn` — reusable drifting atmospheric fog bank.

## Not delivered here (needs DCC tools / recording studio)
- Sculpted `.blend/.glb` character meshes (8–12 k hero, 15–20 k boss) — current
  primitive rigs remain; bone names already match any future swap.
- Hand-painted 2048² texture masters (procedural stand-ins provided above).
- Recorded 48 kHz/24-bit foley stems + OGG fallbacks (synthesized equivalents
  provided; drop recorded WAVs into `assets/audio/` and extend
  `audio_config.tres` paths when available).

---

# CHANGELOG — Progression, Mini-Map, HUD Hub & Dual Economy

## Currencies
- **M** `game_state.gd` — `embers` → `gold` (🪙) with legacy save migration;
  new 💎 `diamonds` (+ signals). Diamonds buy cosmetics only, by contract.
- **M** `shop_menu.gd/.tscn`, `hud`, `hero.gd` — gold API + `+N 🪙` floating text.

## Progression
- **M** `game_state.gd` — XP table (1–10) + post-10 formula; multi-level-ups
  grant 3 stat points each and heal the gained capacity. Five stats:
  STR/DEX/VIT/LUK/END with derived getters (attack bonus, attack/move speed,
  crit chance/damage, defense, max HP).
- **M** `hero.gd` — attack-speed-scaled strike cadence, lucky crits layered on
  zone crits, DEX move-speed stacking, END defense stacking.
- **A** `scripts/ui/stats_screen.gd` + `.tscn` — Embersona allocation screen
  (preview → Confirm commits / Reset reverts).

## HUD & Mini-Map
- **M** `hud.tscn/.gd` — top-right hub (STATS/SATCHEL/SCAN/SHOP/GLINT/MENU +
  gold/diamond labels), EXP progress bar under the warmth bar, animated
  level-up toast with fanfare.
- **A** `scripts/ui/minimap.gd` — custom-drawn realm disc (top-left): realm
  tint/bounds from data, landmark glyphs (🔥🚪⛓💀), pulsing amber player dot,
  tap-to-expand 148↔264 px, realm name label.

## Diamond cosmetics (The Glintmonger's Case)
- **A** `scripts/ui/diamond_shop.gd` + `.tscn` — SFX voice packs (map to the
  existing profile system), blade-trail colors, body auras. Equip/back-to-
  vanilla flows; zero stat lines anywhere.
- **M** `game_state.gd` — owned/equipped cosmetic persistence.
- **M** `hero.gd` — aura emission, trail color routing, cosmetic combat voice.

## Realms
- **M** `bestiary.gd` — `WORLD_REALMS` table (scene, unlock gate, map bounds,
  map color); Whispergrove ↔ Moonfen travel now tracks
  `current_realm`/`unlocked_realms` in the save. Further realms are data-only
  additions.

## Drops
- Boss first-kills grant diamonds once per save (`boss_first_kills`);
  elite hushlings glint 5 % (luck-independent by design).

## Tests
- **A** `tests/test_progression.gd`; **M** `tests/test_shop_skills.gd`;
  UI instantiation smoke validated live (HUD/stats/diamond shop/minimap).

Deferred: emote wheel, full animation-skin libraries, additional realm scenes.

## UI Kit & Screens (Ember Glass parity pass)
- **A** `tools/generate_ui_textures.gd` — offline foundry for UI surfaces:
  `ui_parchment_paper.png` (fiber grain + edge vignette),
  `ui_parchment_ink.png`, `ui_ink_wash.png`. Swappable at the same path.
- **M** `scripts/ui/ui_kit.gd` — new tokens (parchment stock, danger/sage
  brights, chip bg, modal dim) and helpers: import-independent `_ui_tex()`
  (PNG bytes → ImageTexture, works headless without an import cache),
  `style_secondary_button` / `style_danger_button` roles, `style_label`
  (routes code-built labels through the Theme's font variations),
  `parchment_stylebox` / `apply_parchment` (warm stock + fiber veil,
  idempotent), `pill_stylebox`.
- **M** `scenes/ui/main_menu.tscn` + `scripts/ui/main_menu.gd` — landing page:
  hero/confirm cards on parchment, full button-role pass (primary CTA &
  confirm-yes, secondary continue/settings/confirm-no, danger quit), theme-
  routed typography, version-chip tint, green firefly ambience, wordmark
  fade-in entrance, two-line footer hint.
- **M** shop / satchel / forge / diamond shop / stats / settings — every
  code-built row now routes through `UiKit.style_label` (fixes invisible
  `Color(0.09,0.21,0.17)` item names), rows sit on parchment stock, and all
  buttons carry a role (buy/equip/scan/confirm primary; equip/worn/close
  secondary; desktop QUIT danger).
- **M** `scripts/ui/hud.gd` — quest ledger rendered as ink-on-parchment so its
  sepia/ink label colors read as authored (was dark-on-dark glass).
- **A** `tests/test_landing_page.gd` — headless suite: textures load without
  import cache, parchment surfaces present, all six landing buttons carry the
  correct role color, typography variations resolve, fireflies exist, entrance
  completes.

## UE-style Scanned Surfaces & Physics (Chaos-lite pass)
- **A** `assets/textures/pbr/{grass,dirt,sand,rock,bark,wood,clay}/` — 21 CC0
  photo-scanned maps (PolyHaven, 1024², jpg) with `LICENSES.md`. Swappable at
  the same paths for painted/4k masters.
- **M** `assets/shaders/terrain_ground.gdshader` — v3: four PBR layer sets
  (albedo+normal+roughness each), UE-landscape-style exp height-weighted
  blending (`height_contrast`), tier-gated parallax occlusion
  (`pom_mode` 0/1/2, near-faded), per-layer detail normals close-range,
  rain wetting via `world_rain_level`, wear map applied post-POM,
  `debug_view` weight inspector. Realm tints still drive every biome.
- **A** `assets/materials/terrain_{bramblewood,whispergrove,mistfen,heartwood,moonfen}.tres`
  — realm materials binding the scanned sets; TerrainRelief loads by biome id
  (bare-shader fallback) and follows QualityScaler pom tiers.
- **M** `rock.gdshader` / `bark.gdshader` — triplanar scan-rock and streak-
  space scan-bark; grove/moonfen stone + GroveDressing props auto-bind.
- **M** `scripts/systems/quality_scaler.gd` — new tier knobs `debris_max`
  (6/12/24), `pom_mode` (0/1/2), `vegetation_pushers` (1/4/4),
  `corpse_pool_size` (2/4/6), `contact_shadows`; omni/spot shadows now opt-in
  via the `contact_shadow` light group so decorative fills never become blocky
  shadow casters; softer sun blur at HIGH. Fixed negative sun shadow_bias in
  grove/moonfen that banded per-pixel normal-mapped ground.
- **A** `scripts/systems/debris_system.gd` — pooled RigidBody3D shard bursts
  (rock/wood/leaf/crystal/ceramic styles), environment-only collision,
  oldest-first cap retire, scene-reset park. Wired through ImpactDirector:
  strikes, slams and hard landings spray surface-appropriate debris.
- **A** `scripts/props/destructible_prop.gd` — code-built breakable pots /
  crates / glowcaps placed by GroveDressing near flatten anchors; chip-flash,
  debris + CombatFx burst, loot rolls into GameState.add_loot; hero strikes,
  slams and hard landings damage nearby props.
- **A** `scripts/systems/tumble_corpse.gd` — death physics: visuals reparent
  into a rigid shell on kill, take the killing impulse, tumble, sink and fade;
  static registry enforces the tier corpse budget. Bosses attempt a per-bone
  PhysicalBoneSimulator3D ragdoll first and fall back to a big tumble.
  Hushling/boss death flows updated (deferred launches — die() can run inside
  physics callbacks).
- **M** `grass_blade.gdshader` + `project.godot` — vegetation trample/push via
  `world_pusher_1/2/3` vec4 shader globals (arrays are unsupported as globals);
  WorldState publishes nearest enemies/boss as push spheres and gained
  `gust(strength)` for slam/boss-death wind surges.
- **A** `tests/test_material_bindings.gd`, `tests/test_debris_system.gd`,
  `tests/test_destructibles.gd`, `tests/test_death_corpse.gd`;
  **M** `tests/test_quality_scaler.gd` — knob assertions plus contact-shadow
  group contract. Full headless suite green.
- **A** `tests/diag_debug_shot.gd` — rendered terrain probe (weight debug view,
  LOW/HIGH tiers, wide angle) used to bisect the shadow-map artifacts.
- **M** `scripts/systems/quality_scaler.gd` — POM tier now actually pushed into
  the live terrain-ground materials on level change **and** scene load
  (MEDIUM = single-step offset, LOW = off), closing a gap where MEDIUM/LOW
  still ran the full 8-step march; HIGH gains +0.2 SSAO intensity for the
  grounded UE look (Task 9). Re-applied on realm travel so boot/LOW-mode and
  scene swaps keep the correct tier.
