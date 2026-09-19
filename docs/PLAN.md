# Embervale Asset Integration Plan

## Goal

Integrate a curated, commercially usable asset library into Embervale without
duplicating existing systems, weakening realm identity, or exceeding Android
performance budgets.

## Realm placement

### Whispergrove onboarding

- Use `kenney_nature` trees, rocks, mushrooms, and logs.
- Use `kenney_survival` campfire, bedroll, barrels, and bottles.
- Use `kenney_mini_dungeon` chest, banners, and chairs.
- Keep procedural dressing as the primary foliage system.
- Use imported assets as authored landmarks and nearby props.

### Bramblewood expedition

- Use nature trees, rocks, mushrooms, and logs.
- Use tower-defense crystals and larger rocks.
- Use graveyard altar and damaged fence pieces as old forest ruins.
- Keep existing thorn arches and procedural foliage.

### Mistfen

- Use rocks near water and mushrooms as navigation markers.
- Use survival barrels and bottles around abandoned camps.
- Use dungeon columns and banners for drowned ruins.
- Keep fog and telegraph readability a priority; avoid excessive tree density.

### Heartwood

- Use graveyard altar and coffin pieces.
- Recolor tower-defense crystals with Heartwood ember materials.
- Use survival camp props near volcanic routes.
- Keep existing charred-spire procedural landmarks.

### Moonfen

- Use tower-defense crystals, nature rocks, and mushrooms.
- Use dungeon columns as ancient magical ruins.
- Keep the existing blue/purple procedural environment and water identity.

## Characters and enemies

- `character-human.fbx`: craftsman, merchant, healer, and wandering villager.
- `character-orc.fbx`: brute, elite guard, and ogre-like placeholder.
- Skeleton: add a licensed undead model pack for graveyard encounters.
- Goblin: add a compatible low-poly creature pack.
- Knight: human model with armor and weapon variants.
- Gnome: short human variant with custom scale and hat.
- Ogre: scaled orc variant.
- Cyclops: custom single-eye variant.
- Blob: retain the existing procedural mesh approach.
- Fire spirit: procedural body plus elemental VFX.
- Dragon: add a separate low-poly dragon pack.
- Thunder spirit: procedural body plus lightning VFX.
- Dark entity: retain existing boss/procedural silhouette systems.

All character models must go through `CharacterRigLoader`. Validate scale,
animations, materials, collision, hitboxes, and mobile LOD before gameplay use.

## Weapons and armor

Use the existing Quaternius weapons first:

- Swords and claymores: melee progression.
- Axes and hammers: heavy weapons.
- Bows: ranged progression.
- Staff: magic progression.
- Shields: defensive builds.
- Daggers: fast weapons.

Attach armor through `AttachmentSocket`; do not bake armor into every character
model. Preserve equipment swapping and existing gameplay call sites.

## VFX

Keep `CombatFx` and `MagicVfxProfiles` as the owning systems.

- Fire: Heartwood and fire spirits.
- Ice: Moonfen.
- Lightning: thunder spirits and late-game weapons.
- Nature: Whispergrove and Bramblewood.
- Water/fog: Mistfen.
- Dark/void: bosses and dark entities.
- Crafting sparks: forge and equipment upgrades.

Every effect must retain quality scaling, a lifetime, cleanup, and hard caps.

## Audio

Organize SFX under:

- `assets/audio/fx/combat`
- `assets/audio/fx/weapons`
- `assets/audio/fx/enemies`
- `assets/audio/fx/gathering`
- `assets/audio/fx/crafting`
- `assets/audio/fx/loot`
- `assets/audio/fx/ui`
- `assets/audio/fx/realms`

Prefer OGG for longer ambience and WAV for short effects. Preserve source
licenses and attribution records.

## Materials and textures

- Grass, trees, and nature: Whispergrove/Bramblewood.
- Mud, reeds, and wet rocks: Mistfen.
- Sand and dry rock: transition areas.
- Lava, magma, and charred rock: Heartwood.
- Ice, blue stone, and crystal: Moonfen.
- Thunder/electric: VFX emission materials.
- Dark/void: bosses and corrupted landmarks.
- Elf/nature materials: future faction and ruin areas.

Use existing realm shaders and palette controls instead of introducing parallel
shader systems.

## Implementation order

1. Add authored props to realm landmarks.
2. Create a character showcase scene for human and orc models.
3. Connect usable hero weapons through equipment sockets.
4. Add merchants, craftsmen, and villagers.
5. Add enemy model variants.
6. Add elemental VFX and sound groups.
7. Add realm-specific materials.
8. Run real-renderer captures and Android performance checks.

## First vertical-slice target

Whispergrove camp → blacksmith/merchant → weapon comparison → Bramblewood
ruin landmark → orc elite encounter.

## Licensing and acceptance rules

- Prefer CC0 or licenses that clearly permit commercial use and modification.
- Do not use CC-BY-NC assets in the monetized submission.
- Preserve each pack's license and source URL in its asset folder.
- Do not claim visual acceptance from headless import checks.
- Gameplay timing, damage, collisions, and telegraph readability must remain
  identical across quality tiers.
- Measure Android performance before expanding dense foliage, VFX, or NPC use.

## Player-facing UI and progression plan

### Skill icon language

Use custom icons instead of emojis. Every icon should communicate its effect:

- Blade: visible sword slash.
- Bleed: red blade with blood droplets.
- Stun: cracked shield or impact ring.
- Fire: burning weapon.
- Ice: frozen blade.
- Lightning: electric weapon.
- Heal: green heart or glowing leaf.
- Shield: shield with a defensive ring.
- Dash: motion trail or arrow.
- Dark magic: black orb with purple cracks.

Use a consistent frame: rarity border, element marker, action silhouette, skill
slot number, radial cooldown overlay, and desaturated locked state.

### Inventory layout

Use three regions:

```text
[Equipment]       [Character preview]       [Item details]
helmet            3D hero model             name / rarity
chest armor       weapon visible             stats / comparison
leggings                                      equip / salvage
boots
ring 1
ring 2
amulet
backpack
shield
mount
```

Equipment slots are helmet, chest armor, gloves, leggings, boots, main hand,
off hand/shield, two rings, amulet, backpack, and mount. Backpack tabs are
Weapons, Armor, Accessories, Potions, Materials, Quest Items, and Scan Tokens.

Every item card shows icon, name, rarity, level, main stat, quantity, equipped
or new state, and Compare. Add short explanations such as `+Attack Speed` and
`Restores 30 HP` so players do not need to memorize icons.

### Shop presentation

Use large item cards in a grid. Each card displays a 3D preview or large icon,
name, rarity, price, gameplay summary, required level, Compare, Preview-on-Hero,
and Buy actions.

Example:

```text
Ashfang Blade
Epic · Level 8

+14 Attack
+6% Critical Chance
Passive: Burns enemies for 3 seconds

[Compare] [Preview] [Buy 240 Gold]
```

Shop tabs: Weapons, Armor, Potions, Crafting Materials, Mounts, Scan Purchases,
and Limited Realm Stock.

### Camera scanning flow

Scanning must never silently convert a camera image into an item.

1. Open Scan and request camera permission.
2. Show a framed live camera preview.
3. Capture an image and show a review screen.
4. Classify it as weapon, enemy, material, or unknown.
5. Ask the player to confirm the intended result.
6. Generate a stylized result from an approved template.
7. Show a 3D preview and let the player accept, discard, or save it.

Weapon pipeline:

```text
Image → silhouette/color/material extraction → weapon archetype
→ bounded stat roll → 3D preview in hero hand → inventory save
```

The scan may influence color, pattern, and shape language, but the game must
control scale, collision, animation, and performance. Use the existing
AttachmentSocket system to display the weapon in the hero's hand.

### Enemy scanning

Use the same review and confirmation flow:

```text
Image → creature category → approved enemy template → visual traits
→ combat role → balanced stats → 3D preview → encounter placement
```

Enemy roles are Attacker, Defender, Ranged, Controller, Support, Disruptor,
and Elite. The scan must not directly invent damage or health; those values come
from role, realm, level, and rarity data.

### Player stat model

Keep the core player-facing stats to Attack Damage, Attack Speed, Movement Speed,
Armor, Magic Resist, Critical Chance, Critical Damage, Healing Power, and Luck.

Reserve Lethality, Armor Pierce, Magic Boost, Cooldown Reduction, and Status
Effect Power for advanced equipment. Suggested sources:

| Stat | Primary sources |
|---|---|
| Attack Damage | Weapons, chest armor |
| Attack Speed | Daggers, gloves, rings |
| Movement Speed | Boots, mounts |
| Armor | Chest, helmet, leggings |
| Magic Resist | Helmet, rings, amulets |
| Critical Chance | Weapons, rings |
| Luck | Rings, backpack, amulet |
| Lethality | Daggers, assassin gear |
| Armor Pierce | Axes, heavy weapons |
| Magic Boost | Staffs, robes, amulets |
| Healing Power | Potions, healer gear, rings |
| Physical Resist | Chest armor, shields |

Use soft caps so stacking one stat cannot dominate the game.

### Enemy reward identity

- Bramble enemies: nature materials, bleed resistance, movement upgrades.
- Mistfen enemies: magic resist, healing items, water materials.
- Heartwood enemies: fire damage, armor, attack damage.
- Moonfen enemies: magic boost, critical effects, elemental materials.
- Skeletons: armor, physical resist, bones.
- Goblins: luck, attack speed, gold.
- Knights: armor, shields, defensive materials.
- Ogres: attack damage, armor pierce.
- Blobs: healing materials, status resistance.
- Fire spirits: fire boost, burn resistance.
- Thunder spirits: attack speed, critical chance.
- Dark entities: lethality, magic boost, rare scan components.

Bosses should grant unique build-defining rewards instead of random stat piles.

### Mobile combat targeting

The attack button should support target selection without replacing movement:

- Tap an enemy to lock on.
- Tap attack to hit the locked target.
- Swipe or drag to rotate aim.
- Hold attack for a charged attack where supported.
- Add a target-switch button for nearby enemies.
- Make auto-target optional.
- Show a clear target ring and off-screen direction arrow.
- Allow the player to cancel lock-on.

### Chapters, tasks, and quizzes

Use a chapter map:

1. The Whispergrove
2. The Bramblewood
3. Mistfen Hollows
4. Heartwood
5. Moonfen Drift

Each chapter should contain story, exploration, gathering, combat, scan,
upgrade, optional challenge, boss, and knowledge-quiz tasks. Quizzes should
teach combat and world knowledge. Reward them with modest gold, materials, or
scan fragments rather than power skips.

### Economy and scan purchases

Use three currencies only:

- Gold: gameplay-earned currency for normal equipment and crafting materials.
- Diamonds: rare premium currency for cosmetics, convenience, and scan packs.
- Scan charges: the resource consumed by scanning.

Example scan product:

```text
Scan Pack
5 scans · $4.99
Includes 5 camera scans and 1 bonus reroll.
No guaranteed legendary result.
```

Provide earnable scan progress so scanning is not pay-to-win: daily task scan
fragment, chapter scan reward, boss-challenge fragment chance, and 10 fragments
for one scan. Keep scanned combat items within bounded stat ranges and make
premium scans primarily cosmetic or variety-based. RevenueCat owns purchase
entitlements; the game tracks consumed scan credits and supports restore
purchases and clear purchase states.

### Upgrade loop

```text
Acquire → Compare → Equip → Test in combat → Upgrade or salvage
```

Every upgrade explains the changed stat, gameplay effect, next cost, required
material, and permanence. Use predictable upgrade paths with limited variation;
avoid unlimited random rerolls.

### UI implementation order

1. Skill icon system.
2. Inventory and equipment screen.
3. Target-lock attack UI.
4. Shop item comparison.
5. One camera weapon scan.
6. Weapon preview in the hero's hand.
7. Enemy scanning.
8. Chapter quizzes and task tracking.
9. Premium scan packs and purchase restoration.
10. Expanded boss rewards and realm challenges.

The first player-facing vertical slice is: skill icon system → inventory/equipment
screen → target-lock attack UI → shop comparison → one camera weapon scan →
weapon preview in the hero's hand.

## GDScript implementation standards

Apply the installed `godot-gdscript-patterns` skill to future implementation:

- Use typed GDScript for new and materially changed code.
- Treat Nodes as scene-tree behavior, Scenes as reusable node trees, Resources
  as serializable data, and Signals as event communication.
- Keep state owned by the appropriate system and expose changes through signals.
- Initialize child-node references in `_ready()` or with `@onready`, never in
  `_init()`.
- Keep movement and timing-sensitive gameplay in `_physics_process()`.
- Use reusable scenes for entities and UI components rather than duplicating
  node trees.
- Store item, skill, enemy, shop, and scan definitions in typed Resources where
  designer editing or save/load is required.
- Keep presentation listening to state signals; it must not mutate gameplay data
  directly.
- Validate every implementation with the smallest affected Godot test first,
  then run the relevant project smoke checks and a real-renderer check when
  visuals are involved.
- Treat external service, credential, camera-permission, store, or device
  setup as a separate approval-gated concern.

## Implementation decisions and completed slice

- The normal Divining Lens scan consumes exactly one scan charge when it starts.
- Starting while a scan is already active, or starting with zero charges, does
  not consume another charge and emits a clear recovery message.
- The forge menu displays `SCANS AVAILABLE: N`, disables the scan action at
  zero, and points the player toward quests or scan-pack recovery.
- Trader cards now show weapon/armor deltas against the currently equipped
  item and visibly disable unaffordable purchases before interaction.
- The HUD quest ledger now projects up to two active side objectives with
  progress counts, sourced from the save-backed GameState objective list.
- Chapter transitions seed idempotent, stage-appropriate objectives so the
  route gains a visible next action while legacy empty saves remain unchanged.
- The satchel now exposes a compact Crafting Bench with explicit iron/gold
  recipes, live requirements, and atomic save-backed craft feedback.
- The Grove craftsman now opens the satchel crafting bench; only the trader
  opens the shop, keeping NPC roles aligned with their visible services.
- Crafted armor is now rendered in the satchel with defense/speed deltas,
  equip controls, and the existing material/gold upgrade transaction.
- The satchel stat grid now adapts from six to three columns on portrait/narrow
  screens, keeping the expanded RPG stats readable on mobile.
- The stat sheet now also exposes the allocated Strength, Dexterity, Luck, and
  Endurance attributes that drive the displayed combat totals.
- Added `ASSET_CREDITS.md` to track every imported third-party pack, local
  license record, source URL, and shipping checklist.
- The boss altar's raw camera capture path remains separate and keeps its
  existing guarded charge consumption, preserving boss customization behavior.
- Camera recognition remains an honest bounded prototype: desktop fallback is
  simulated detection and captured silhouettes become offline extruded relic
  meshes. No external ML, credential, store, or camera-permission setup is
  assumed without explicit approval.
- The Divining Lens scene now includes a real camera preview surface with
  mobile feed binding and explicit offline/desktop fallback messaging.
- Targeted enemies now expose an `ANALYZE FOE` action that spends one scan and
  reports bounded HP, attack, speed, resistances, and reward identity.
- Enemy analysis is limited to once per target instance, preventing repeated
  charges while the target card refreshes.
- The semantic skill renderer now includes a dedicated bleed treatment: three
  cut marks plus a droplet, ready for damage-over-time weapon kits.
- The premium shop now displays the planned 5-scan/$4.99 product honestly as
  unavailable until approved RevenueCat configuration exists; no credentials
  or external billing service were initialized.
- Added a persistent `QuizManager` state/data layer with one chapter question,
  retryable wrong answers, one-time completion rewards, and save/load support;
  quiz presentation UI is now available from the HUD quest ledger, with
  retryable answers, world-freeze handling, and reward feedback.
- Chapter lessons can now award bounded scan fragments; ten fragments convert
  into one scan charge, persist through save/load, and cannot overflow a full
  scan inventory.
- The stage-three elite encounter now completes a visible expedition objective
  on pack clear, tying the encounter reward path into the chapter route.
- The HUD now presents the first movement lesson immediately and advances the
  field-guide hint as onboarding triggers complete, without modal tutorial
  interruption.
- The real-render capture harness now supports `--keep-ui`, allowing visual
  QA of the actual mobile HUD, field guide, touch controls, and combat cards.
- Reduced Whispergrove mobile exposure and ambient energy after real-render
  review showed the hero and bright props clipping toward white; combat timing,
  telegraphs, and quality-tier logic are unchanged.
- Lowered the Grove's primary sun energy as a second targeted readability pass;
  this keeps the authored hero silhouette and terrain separation visible while
  retaining warm landmark lights.
- Audited mobile targeting: attack, skill, and touch paths share nearest-enemy
  acquisition and the existing target marker; target-marker and combat-recovery
  tests pass without introducing a parallel targeting system.
- Added a `NEXT FOE` touch action to the target card; it cycles nearby living
  enemies through the same GameState lock and target-marker path.
- Added target-direction feedback to the combat card: targets report `IN VIEW`
  or a left/right/behind turn cue based on the active 3D camera projection.
- Added satchel inventory filters for all, weapons, armor, consumables,
  materials, and quest items, backed by the existing inventory and forged-gear
  collections.
- The active satchel filter now uses the primary button treatment while the
  other categories remain secondary, making the current inventory view clear.
- The Materials filter now renders gathered `raw_materials` with quantity,
  crafting purpose, realm source, and rarity treatment instead of appearing
  empty when material state exists.
- Combat-focus capture remains useful for verifying the boss bar and controls,
  but its deterministic camera is too close for final composition approval and
  needs a later boss-framing pass.
- Adjusted the capture-only boss camera for authored-scale variation so the
  full silhouette and arena remain inside the portrait frame for visual QA.

## Realm ground and ambient asset intake

- Added Kenney Foliage Sprites under `assets/ambient/kenney_foliage_sprites/`.
  It contains flat and shaded foliage billboard source art for grass clumps,
  tiny flowers, small/big bushes, garden edges, field dressing, and low-cost
  distant tree layers. The original `License.txt` is preserved.
- License check: Kenney's official page and the OpenGameArt mirror identify
  this pack as Creative Commons CC0. Source records are kept in
  `ASSET_CREDITS.md`; credit is optional but will be retained in the project.
- Planned realm usage: Whispergrove gets flowers, small bushes, garden beds,
  butterflies/fireflies as sparse ambient particles, and soft grass; Bramblewood
  gets dense grass, brambles, large bushes, pines, and field paths; Mistfen gets
  darker reeds/grass and fireflies; Heartwood gets dry grass, ash, and ember
  particles; Moonfen gets wet-ground decals, cool foliage, and blue fireflies.
- Keep the existing Kenney Nature Kit as the primary 3D tree/rock source. Use
  the new foliage sprites only as billboard/detail layers so Android memory,
  overdraw, and draw-call budgets remain bounded.
- Butterflies and fireflies are planned as authored, capped ambient VFX using
  these foliage colors/scale references; no separate creature asset is imported
  until a compatible CC0 animated source is found and validated in-engine.
- Follow-up implementation slice: create one reusable `AmbientFoliagePatch`
  scene with deterministic seed, realm palette, max-instance cap, wind toggle,
  and cleanup on chunk unload; then place small test patches in each realm.
- Implemented `AmbientFoliagePatch` as a capped `MultiMeshInstance3D` used by
  streamed chunks. It uses the imported CC0 foliage source, deterministic chunk
  seeds, realm tinting, visibility limits, and chunk-owned cleanup. Quality
  tiers select 12/18/24 instances per patch. Butterfly/firefly behavior remains
  a separate ambient-VFX follow-up so it does not multiply world draw calls.
- Added `tests/test_ambient_foliage_patch.gd` covering the hard 64-instance cap
  and deterministic transforms for the same realm seed.
- Added a reusable `AmbientLifeField` with a capped, seeded butterfly particle
  field, realm color variants, bounded visibility, and chunk/world ownership.
  Existing realm firefly systems remain the single firefly source; this avoids
  duplicate particle fields while preserving their current tuning.

## Current implementation progress

- Added a save-safe `route_checkpoint_id` to `GameState`. Stage transitions set
  stable route markers (`grove_arrival`, `hushling_cleared`, `shard_claimed`,
  `beacon_relit`) idempotently, persist them, and emit one change signal for
  future checkpoint/respawn presentation. Legacy saves fall back to the marker
  implied by their current stage.
- Added `tests/test_route_checkpoint.gd` covering normalization, duplicate
  no-op behavior, and save/load round-tripping.
- The HUD now presents the active route checkpoint in the quest ledger using
  signal-driven presentation (`GROVE ARRIVAL`, `HUSHLING CLEARED`, `EMBER SHARD
  CLAIMED`, `BEACON RELIT`), so progress is visible without a blocking modal.
- Route checkpoints now also persist stage-specific respawn positions; player
  defeat returns to the latest route beat instead of always returning to the
  opening spawn. Clean saves retain the original spawn and legacy saves derive
  safe positions from their checkpoint marker.
- Added a shared stat soft-cap projection: the first 20 points retain their
  full value, while points beyond that contribute at 50% to attack, speed,
  critical, defense, and vitality-derived health. Early-game values are
  unchanged, and `tests/test_stat_soft_caps.gd` covers both sides of the curve.
- The stats screen now explains the soft-cap rule directly above allocation
  rows, so late-game diminishing returns are visible before a player commits
  points.
- Weapon cards now have an explicit non-mutating `INSPECT` action that focuses
  the selected-item panel with combat identity, attack delta, passive effect,
  tactical decision, and upgrade-path context before the player equips it.
- Armor cards now provide the same non-mutating inspection flow with defense
  and movement deltas, descriptive role text, and bounded upgrade context.
- The shop now supports deterministic recommended, price, and power sorting,
  with the active sort mode visible in the shop tabs while preserving existing
  affordability, comparison, and purchase behavior.
- The shop also supports a compact category filter cycle for all stock,
  weapons, armor, and potions; filtering happens before sorting so the active
  category remains predictable on touch screens.
- Shop filter scope is now explicit: category filtering is enabled for Buy and
  disabled with explanatory tooltip text during Sell, avoiding a misleading
  control state.
- Added a clear `NO STOCK IN THIS CATEGORY` empty state for filtered shop views,
  preventing blank inventory panels when a future realm stock category has no
  available items.
- Shop gear rows now include a non-mutating `PREVIEW` action that hands the
  stock definition to the existing Satchel 3D hero inspection viewport before
  purchase or equip.
- Inventory weapon cards now explain the weapon's combat identity and decision
  (Breaker, Duelist, or Controller) from `WeaponCombatProfiles`, alongside the
  passive and attack delta. Quest items are no longer misclassified as materials
  solely because their IDs contain `shard` or `iron`.
- Added an optional `CombatTrainingTarget` scene for camp/practice-altar use.
  It shares the targetable enemy contract, shows bounded health state, resets
  after defeat, and grants no XP, loot, objectives, or scan charges. Its first
  focused contract test passes; placement in the route remains a composition
  decision for the next real-render pass.
- The target is now placed beside the post-boss practice altar when that altar
  is available, keeping training discoverable without adding an enemy to the
  critical first encounter or changing campaign rewards.
- The training target scene now includes the shared world-space enemy health
  plate and a scan description identifying it as practice-only, making the
  interaction legible before the player attacks.
- Added an in-world `PRACTICE · NO REWARDS` label above the target so its role
  is clear before lock-on; it remains a presentation-only aid.
- Added a reusable `CameraRig.play_focus_moment()` contract for short,
  world-space arrival, landmark, unlock, and reward reveals. Durations are
  clamped, the player can skip with attack/cancel input, and camera/time-scale
  state is restored through one cancellation path.
- Connected meaningful reward reveals to the HUD: diamonds, weapons, and
  armor briefly frame the hero while ordinary gold/XP rewards remain
  uninterrupted during combat. Focused route/reward integration still needs
  real-rendered validation before the roadmap checkbox is marked complete.
- Forged relic weapon dictionaries now carry their deterministic elemental
  affinity at creation time, keeping saved inventory, equipped combat, and
  impact VFX on the same identity.
- Hushlings now expose bounded poise accumulation: repeated light hits build
  toward stagger, heavy hits can break in one blow, and the meter resets into
  the existing recovery lockout. Their world-space health plate shows the
  amber poise strip only when the enemy supports that contract.
- Added a shared target-side damage-event dispatcher for player, enemy, and
  boss damage feedback, keeping damage numbers and camera response aligned
  without changing damage or collision timing.
- Added persisted Motion Feedback settings (`full`, `mobile`, `reduced`,
  `off`) and made both CameraRig shake and ScreenFX chroma/vignette pulses
  honor the setting immediately.
- Added defensive standard audio-bus creation and routed realm ambient beds
  through the Music bus so volume controls work for realm transitions.
- Realm entry now starts a bounded, crossfaded realm-specific ambient bed while
  palette/fog and camera arrival framing transition together.
- Added `BalanceHarness` for deterministic weapon time-to-kill/DPS comparisons
  against armor, swing time, attack speed, and crit assumptions. It is a review
  tool, not a runtime balance override; encounter tuning still requires
  measured route/device evidence.

## High-end RPG quality roadmap

This is the next quality bar after the current vertical-slice systems. The goal
is premium-feeling moment-to-moment play built from readable authored systems,
not expensive effects or feature count. Every item must be demonstrated in a
real-rendered route and remain viable on the Android target.

### Phase A — Make the first 30 minutes feel finished

- [ ] Play the complete Whispergrove → Bramblewood route from a clean save and
  record a beat sheet for movement, first interaction, first fight, gathering,
  upgrade, elite, boss, reward, and unlock; remove dead walking and unclear
  transitions.
- [x] Added an executable ten-beat Golden Route catalog covering the documented
  0:00–30:00 timing windows, required authored signals, and save-safe recovery
  endpoints. It provides a deterministic structural target; real-rendered and
  Android playthrough evidence is still required before the full route item is
  complete.
- [x] Added `GoldenRouteTracker`, an explicitly started and capped runtime
  tracker that emits beat changes, exposes a save-safe snapshot, records route
  beats in the bounded activity ledger when a live `GameState` exists, and stops
  at the 30-minute route limit. Standalone tracker coverage passes; a real
  rendered route playthrough is still required.
- [x] Wired the tracker into `WorldManager` for clean Whispergrove arrivals
  only. Recovered checkpoints and failed activities do not restart the pacing
  clock; the runtime contract test also verifies this integration hook.
- [x] Added required authored-signal coverage to every Golden Route beat and
  exposed `WorldManager` forwarding/report hooks. The route can now report
  exactly which landmark, combat, crafting, reward, and unlock signals are
  missing during a playthrough; real-rendered/device evidence is still open.
- [x] Added behavioral coverage for Golden Route signal capture: partial reports
  identify missing authored beats, complete reports reach zero missing signals,
  and stopped routes reject late events. This remains an acceptance aid, not
  a substitute for a real-rendered/device playthrough.
- [x] Wired live encounter reveals, elite telegraph setup, elite reward reveals,
  and boss reward reveals to the Golden Route signal API. Runtime systems now
  contribute evidence automatically; unimplemented authored moments and
  rendered/device acceptance remain visible as missing signals.
- [x] Give every onboarding beat one diegetic teaching moment: a landmark,
  readable enemy action, interactable prop, or reward reveal; limit blocking
  tutorial overlays to essential safety information.
- [x] Add a short arrival/reward camera language pass: controlled framing,
  subject focus, restrained ease-in/ease-out, and skip/cancel support. Preserve
  player control and cap every camera impulse.
- [x] Make the first upgrade visibly change the hero's held weapon, combat
  feedback, and one practical decision in the next encounter.
- [x] Add a save-safe route-completion checkpoint and verify death, reload,
  scene transition, and repeated interaction cannot duplicate rewards or strand
  the player.

### Phase B — Premium combat feel

- [x] Define weapon families as distinct verbs: sword spacing, dagger tempo,
  axe commitment, hammer stagger, bow positioning, staff zoning, and shield
  timing; document startup, active, recovery, cancel, and stamina rules in data.
- [x] Add authored hit-stop tiers, hit reactions, impact direction, damage
  numbers, sound priority, and camera response with one shared damage event so
  combat feedback never disagrees across systems.
- [x] Add anticipation and recovery to every elite/boss attack; telegraph shape,
  collision window, damage, and recovery must be generated from the same profile.
- [x] Implement a fair stagger/poise loop with explicit resistance, break,
  punish, and reset states; test simultaneous attackers and interrupted attacks.
- [x] Give bosses two to three phase patterns with arena-readable safe zones,
  vulnerability windows, phase transition rewards, and reliable reset after
  death or retreat.
- [x] Add a combat training encounter that exposes frame/timing readability,
  target switching, dodge timing, status effects, and weapon differences without
  relying on debug controls.

### Phase C — Living realms and authored composition

- [x] Build a visual grammar sheet for each realm: foreground detail, midground
  landmarks, background silhouette, dominant hue, accent light, weather, and
  traversal pressure. Use it to review every new prop placement.
- [x] Give each realm one signature traversal activity, one resource ritual,
  one ambient life behavior, one elite composition, and one landmark reward.
- [x] Replace random-looking prop scatter with authored encounter pockets:
  approach, reveal, readable combat space, reward space, and an exit sightline.
- [x] Add distant vista dressing and landmark silhouettes before adding more
  small props; verify the player can orient from the camera at normal movement
  speed.
- [x] Add realm transitions with controlled palette, fog, ambient-light, music,
  and material interpolation; do not pop between unrelated visual states.
- [ ] Validate foliage, ponds, rocks, fields, gardens, pines, fireflies, and
  butterflies at gameplay scale; keep ambient life non-interactive unless a
  deliberate quest or resource rule owns it.
- [x] Structural realm validation now covers deterministic instanced foliage,
  realm-specific ambient-life behavior, capped butterfly/firefly particles,
  and non-interactive ambient ownership across the supported realms. A real
  renderer/device capture at gameplay scale is still required for the complete
  foliage/pond/garden/pine/cactus acceptance item.

### Phase D — Animation, presentation, and tactile response

- [x] Create an animation matrix for hero, humanoid NPCs, and enemy roles:
  idle, locomotion, turn, attack, hit, stagger, death, interact, and special.
  Track missing clips and fallback behavior explicitly.
- [x] Align weapon sockets, hand poses, trails, hit frames, and damage events;
  the full equipment scene covers visible placement/trail attachment and the
  attack-event contract enforces telegraph → trail → impact wait → damage order.
- [x] Add footstep and surface response by realm/material, with movement-speed
  variation kept separate from audio pitch so audio remains readable.
- [x] Add authored audio buses for combat, UI, ambience, dialogue, and music;
  define voice limits, ducking rules, pause behavior, and settings persistence.
- [x] Introduce a restrained music state machine: exploration, danger, elite,
  boss phase, victory, defeat, and menu; transitions must be interruptible and
  avoid stacked playback.
- [x] Add optional haptics, screen shake, hit flash, and reduced-motion controls;
  verify each setting changes actual runtime behavior and persists.

### Phase E — High-end UI and player clarity

- [x] Establish a single responsive token theme for spacing, typography,
  surfaces, rarity colors, focus states, safe areas, and touch-target minimums.
- [x] Make every important action explain state: locked, unavailable, loading,
  purchased, equipped, crafting, scanning, restoring, or failed.
- [x] Added a semantic-action audit covering HUD, FightButton, shop, forge,
  satchel, dungeon select, main menu, and diamond shop. Each owner must consume
  the shared `UiKit.action_state` contract, whose state vocabulary includes all
  required locked/loading/purchase/crafting/scanning/recovery/failure states.
- [x] Extended the shared action vocabulary with an explicit `success` state
  for saved settings, completed quests, and successful restores, so callers do
  not have to present those outcomes as purchases.
- [x] Add item inspection as a focused flow: 3D hero preview, before/after
  comparison, stat explanation, source, salvage result, and clear back path.
- [x] Add a readable quest journal with chapter map, active objective, optional
  task, reward preview, completion history, and a single next-action emphasis.
- [x] Improve shops with sorting, filters, owned/equipped state, preview-on-hero,
  affordability, comparison deltas, and no hidden currency conversion.
- [x] Make scan results explain confidence, template used, bounded stat roll,
  confirmation, discard, reroll cost, and saved inventory identity.
- [ ] Run portrait, landscape, large-text, color-vision, touch, keyboard, and
  controller passes on all high-frequency screens before adding more menus.
- [x] Added live viewport handling to the stat screen: compact layouts switch
  to two columns, expanded layouts use four, and the panel clamps to the
  available safe width. Shared token/touch tests cover the responsive contract;
  portrait/landscape/large-text/color-vision/controller visual passes remain
  release evidence.
- [x] Added a normal scene-boot regression for the stat screen that exercises
  480×800 compact and 1280×800 expanded viewports and verifies the live column
  count/panel clamp, rather than relying only on source or token inspection.
- [x] Added a persisted 100%/125%/150% touch-target setting for the combat
  action controls. Attack, skills, dodge, and jump share the accessibility
  group and resize their hit regions without changing combat timing or damage;
  Android visual/readability validation remains a release-evidence task.
- [x] Added a migration-safe `InputManager` key-binding backend for scan,
  skills, interact, pause, dodge, and jump. Defaults remain unchanged;
  persisted invalid or duplicate layouts fall back atomically, and runtime
  assignments reject collisions. A visible key-capture editor and controller
  mapping pass remain open.
- [x] Added a visible Settings key-capture section for those bindings. Players
  can select an action, press a key, cancel with Escape, and receive explicit
  bound/collision/cancel feedback; the section also restores defaults. A real
  device usability pass and controller-specific bindings remain open.
- [x] Added a persisted 100%/115%/130% text-size setting with non-compounding
  font overrides applied to live labels and buttons. It changes readability
  only; layout and gameplay timing remain owned by their existing systems.
- [x] Corrected key-capture feedback so successful bindings immediately update
  their visible action labels, including after restoring defaults; accessibility,
  binding, UI-shell, and editor checks remain green.
- [x] Added standard controller input routing: A/interact, B/dodge, X/Y/left
  shoulder/skills, right shoulder/scan, Start/pause, and left-stick movement.
  It reuses the existing signals and deadzone, so controller combat semantics
  stay aligned with keyboard and touch. Physical-controller validation remains
  release evidence.

### Phase F — Data, balance, and long-term motivation

- [ ] Consolidate items, skills, enemies, loot, recipes, quests, and realm
  rewards into versioned data resources with stable IDs and migration tests.
- [x] Extended `ContentSchema` migration coverage to all registry asset/content
  categories, including NPCs, enemies, props, VFX, SFX, and terrain materials.
  Catalog rows normalize IDs additively, preserve replacement paths, reject
  unknown categories, and de-duplicate stable IDs without rewriting saves.
- [x] Added stable runtime registry records for weapon-derived skills and live
  quest objectives, plus the four central loot-table presets copied from the
  actual `LootTable` definitions; cross-category duplicate validation remains
  active for all populated families.
- [x] Added `ContentManifestResource` and a checked-in
  `res://resources/content_manifest.tres` envelope for versioned registry
  review/build data. Runtime creation, resource loading, validation, and legacy
  migration are covered without placing registry dictionaries in player saves.
- [x] Define a compact stat budget per rarity and level; use soft caps and
  diminishing returns so attack, speed, crit, defenses, and magic stats remain
  meaningful without mandatory spreadsheets.
- [x] Build a deterministic balance harness for time-to-kill, incoming damage,
  healing economy, upgrade cost, scan income, and boss retry cost across stages.
- [x] Make loot tables communicate why a drop matters: build tag, realm source,
  upgrade path, salvage value, and future recipe usage.
- [x] Add build-defining boss rewards with alternate choices rather than piles
  of random stats; ensure no single reward is required to finish the campaign.
- [ ] Add daily/weekly goals only after the core route is satisfying; keep them
  optional, bounded, and never dependent on premium spending.
- [ ] Add accessibility-safe difficulty assists that change pressure or recovery
  windows without invalidating achievements or changing story rewards.
- [x] Added a separate persisted Telegraph Clarity assist. It extends the
  shared enemy special/counter wind-up by a capped 25%, while damage, recovery
  rewards, story rewards, and achievements remain unchanged. Recovery Assist
  and Telegraph Clarity are independently switchable and contract-tested.
- [x] Added persisted `Telegraph Shape + Text` accessibility mode. Ground
  warnings retain their protected ring and exact timing/radius while adding a
  high-contrast `DANGER` cue, so telegraph meaning does not depend on color
  alone; accessibility and skill-VFX checks pass.

### Phase G — Android production bar

- [ ] Establish a repeatable physical-device profile route covering startup,
  exploration, crowded combat, boss phases, inventory, shop, scan preview, and
  realm transition; record FPS, frame time, memory, draw calls, particles,
  lights, audio voices, and loading spikes.
- [x] Added `AndroidProfileRoute` with eight deterministic checkpoints and eight
  required metrics, plus a validator test. It standardizes future physical
  Android measurements without claiming emulator/device performance.
- [x] Added bounded `AndroidProfileTelemetry` runtime sampling with a 60-sample
  cap, fixed interval, snapshot/latest APIs, renderer metrics, active audio
  voice counting, and loading-spike field support. The sampler contract passes;
  target-device collection is still required for performance acceptance.
- [x] Attached the telemetry sampler to normal `WorldManager` boot and exposed
  `get_android_profile_snapshot()` as a read-only tooling hook. The profile
  route, world-stream, and editor checks pass; no gameplay timing or state is
  changed by sampling.
- [x] Added `WorldManager.save_android_profile_report()` as the runtime-facing
  export hook for the bounded local JSON profile report. Route, world-stream,
  and editor checks pass; this does not replace physical Android measurement.
- [x] Added local JSON report aggregation to `AndroidProfileTelemetry`, with
  bounded raw samples and min/average/max summaries for every profile metric.
  Report, telemetry, and editor checks pass; the report must still be captured
  on a physical Android target for acceptance.
- [x] Set explicit budgets for each quality tier and enforce them with tests or
  development warnings; gameplay timing and collision must remain invariant.
- [ ] Add async import/streaming checks for first-use stutter, shader warm-up,
  texture memory, scene transition hitching, and chunk rebuild spikes.
- [x] Added `StreamingBudgetCatalog` with explicit first-use, shader-warmup,
  texture-memory, realm-transition, and chunk-rebuild thresholds plus a
  measurement evaluator. It is a release diagnostic contract; actual Android
  timing and memory capture remain required.
- [ ] Test suspend/resume, low-memory recovery, orientation changes, offline
  mode, interrupted purchases, interrupted scans, and corrupted-save recovery.
- [x] Added explicit `GameState` application pause/resume hooks. Android pause
  flushes the existing local save and queued intents; resume emits a lifecycle
  signal for future transport/UI adapters and performs no remote mutation.
  Structural lifecycle coverage passes; device suspend/resume validation remains
  required.
- [x] Added a low-memory warning handler that flushes the local save/queue and
  requests the existing Low quality tier. It discards no progression, inventory,
  rewards, or combat state; structural coverage passes, while physical-device
  memory-pressure validation remains required.
- [ ] Create a release checklist for package identity, signing, permissions,
  privacy disclosures, store screenshots, attribution, crash logging, and
  RevenueCat entitlement restore before any public submission.
- [x] Added `RELEASE_CHECKLIST.md` with explicit Android package/signing,
  privacy/permission, store/attribution, reliability/support, and RevenueCat
  gates. It is intentionally all unchecked until release evidence exists and
  does not contain credentials or production configuration.

### Phase H — Premium RPG presentation pass

- [ ] Build a cinematic language guide for arrivals, discoveries, elite reveals,
  boss entrances, victories, defeats, and fast travel; keep every shot skippable
  and return control reliably.
- [ ] Add authored camera compositions for landmarks and bosses with explicit
  subject, screen position, duration, and exit state; prevent camera ownership
  conflicts with combat targeting and touch input.
- [x] Replace placeholder combat/UI symbols with a cohesive icon family: clear
  silhouettes for slash, bleed, stun, guard, fire, frost, lightning, poison,
  shadow, healing, and scan; provide a text label or shape cue for color-blind
  players.
- [ ] Add layered environmental storytelling to each realm: readable ruins,
  camps, trails, abandoned tools, gathering traces, and creature evidence that
  reinforce the next objective without invisible walls or exposition dumps.
- [x] Added `EnvironmentStoryCatalog` with all six readable story layers for
  every realm, using existing authored POI/landmark/dressing owners. It is a
  composition contract only; collision, combat, and navigation remain unchanged
  until each clue receives a real-rendered placement pass.
- [ ] Create a controlled weather and time-of-day layer with bounded particles,
  lighting transitions, ambient audio variation, and a deterministic fallback
  for low-end Android devices.
- [x] Added `WeatherProfileCatalog` with bounded fog, particle, and ambient
  variation values plus deterministic low-quality fallbacks for every realm.
  The catalog is validated independently; runtime weather rendering and
  physical-device readability/performance evidence remain open.
- [ ] Add hero presentation moments for equipment changes: weapon draw, armor
  silhouette update, material tint, and a short comparison pose; never hide a
  gameplay stat change behind a cosmetic-only animation.
- [ ] Add enemy faction readability through silhouette, material accents, attack
  language, and audio motifs before adding more enemy variants; validate that
  skeletons, goblins, knights, elementals, and bosses read at mobile distance.
- [ ] Add a reusable reward reveal sequence for ordinary loot, rare gear, boss
  choices, recipes, and realm unlocks with rarity pacing, duplicate protection,
  skip support, and an accessible summary after the animation.
- [x] Added `RewardRevealModel` as the shared bounded presentation contract:
  rarity-based reveal durations, duplicate filtering, a twelve-entry cap,
  skip support, and an accessible text summary. It never grants rewards or
  changes transaction timing; the visual sequence remains a presentation task.
- [x] Added `RewardRevealPanel`, a reusable Control presenter with capped rows,
  rarity/quantity labels, an always-visible accessible summary, and a
  continue/skip action. It is non-mutating; RewardManager remains the sole
  authority for grants and idempotency.
- [x] Wired rare gear reward grants from `RewardManager` into the HUD presenter
  after the authoritative grant completes. The overlay is dismissible and
  presentation-only; existing toast/history and reward-choice ownership remain
  intact.
- [ ] Define a premium presentation hierarchy: exploration is calm and spacious,
  combat is readable and forceful, discoveries are intimate, and bosses are
  exceptional; reserve the strongest camera, lighting, audio, and VFX moments
  for decisions that matter.
- [ ] Build a consistent cinematic camera grammar for close-ups, reveals,
  traversals, and victories with explicit interruption rules; combat, pause,
  accessibility, and touch controls must always be able to reclaim the camera.
- [ ] Add animation-authored locomotion and combat transitions for the hero and
  priority enemies: anticipation, contact, recovery, hit reaction, stagger,
  death, and locomotion starts/stops must share a readable timing language.
- [ ] Establish a restrained material language for rarity, faction, and element:
  use albedo, roughness, silhouette accents, and controlled emission instead of
  global glow; validate readability in daylight, fog, and low-quality modes.
- [ ] Add an authored ambient layer per realm—wind, insects, distant creatures,
  water, fire, storms, and silence—with distance falloff, voice caps, and
  transitions that do not restart or stack on every scene change.
- [ ] Create a photo-mode-quality inspection state for hero gear, scanned
  weapons, bosses, and rare loot with fixed lighting, orbit limits, readable
  stats, and a fast return to gameplay; keep it optional on mobile.
- [ ] Perform a “first five minutes” polish pass: title-to-game transition,
  input handoff, first landmark, first enemy, first reward, first upgrade, and
  first quest update must feel like one authored sequence.

### Phase I — Production content pipeline and trust

- [x] Define an asset intake checklist for license, attribution, source URL,
  package version, polygon/material budget, texture dimensions, animation
  coverage, collision, scale, pivot, import settings, and mobile fallback.
- `AssetIntakeCatalog.REQUIRED_FIELDS` now enforces these fields for every
  current pack, with local license evidence and runtime-owner references.
- [ ] Create a stable content registry for every weapon, armor piece, enemy,
  NPC, mount, animal, VFX, SFX, prop, and terrain material; reject duplicate
  IDs and missing references before a build is considered shippable.
- [x] Extended the registry with stable categories and lookup/duplicate
  validation for enemy, NPC, mount, animal, VFX, SFX, prop, and terrain
  material records; population and per-record reference audits remain open.
- [x] Populated the runtime registry with current enemy roles, service NPCs,
  bounded ambient animals, mount replacement metadata, VFX/SFX semantic
  records, and Whispergrove terrain material ownership. The population test
  rejects empty required families, ID mismatches, and cross-category duplicate
  IDs while preserving path-independent save data.
- [x] Added a non-destructive startup gate in `GameState`: normal game boot
  validates the live registry once, exposes diagnostics, and reports malformed
  stable IDs before late gameplay use. It does not discard saves or turn a
  recoverable content issue into a crash; the adapter test asserts a clean gate.
- [x] Added `ContentManifest` as the single versioned wrapper around the live
  content registry. It validates registry/schema versions and migrates legacy
  manifest metadata additively without rewriting saved gear or asset paths.
  `tests/test_content_manifest.gd` covers live validation and legacy migration.
- [x] Established naming, folder, LOD, collision, socket, and prefab
  conventions in `ASSET_CONVENTIONS.md`, with a typed validator covering every
  current intake entry and the allowed equipment sockets. Negative cases pass;
  gameplay data and save files remain path-independent.
- [x] Completed the staging gallery with gameplay-scale previews, neutral
  lighting, optional animation playback (preferred `idle`, then first clip),
  bounded collision visualization, and sampled memory/draw-call telemetry.
  `test_asset_staging_gallery.gd` covers the gallery contract; rendered and
  Android performance review remain separate acceptance gates.
- [ ] Build a small set of authored modular kits per realm—ground cover,
  flowers, gardens, fields, bushes, pines, cactuses, ponds, rocks, ruins, and
  realm accents—before broadening the creature catalog.
- [ ] Add a license and attribution audit to the release checklist; quarantine
  assets whose license is unclear, requires attribution not yet documented, or
  forbids commercial/game redistribution.
- [x] Added `LicenseAudit`, which cross-checks every intake entry against local
  license evidence, HTTPS source metadata, and the matching pack/license/source
  markers in `ASSET_CREDITS.md`. Unclear or undocumented entries fail the audit
  and cannot be treated as release-ready.
- [x] Added `RealmModularKitCatalog` for all five realms, requiring ground
  cover, flowers, gardens, fields, bushes, pines, ponds, rocks, ruins, and
  realm accents with realm-specific palettes and ambient identity. The catalog
  test prevents a realm from expanding creatures before its visual kit exists.
- [x] Define and enforce a “one new asset, one use case” rule: every imported asset must be
  assigned to a realm, encounter, quest, shop, crafting recipe, or readable
  navigation purpose before it enters production; the intake registry requires
  a runtime owner/use case and the runtime-usage validation covers all current packs.
- [x] Strengthened runtime asset validation so each declared representative
  asset must be referenced by the source of its declared runtime owner, not
  merely exist on disk. All current imported packs pass this stronger static
  ownership/reference gate; rendered visibility and device profiling remain
  release validation.
- [x] Expanded the isolated staging gallery to include representatives from all
  six current imported packs, including a `Sprite3D` texture fallback for the
  foliage SVG, with a bounded two-row gameplay-scale review layout. Staging,
  runtime-reference, and intake-review checks pass; collision visualization and
  memory/draw-call telemetry remain open for the full staging-scene item.
- [x] Added isolated staging telemetry for loaded station count and sampled
  renderer draw calls, updated at a bounded interval and labeled as review-only
  evidence. The gallery build contract passes; Android profiling and collision
  visualization remain separate release gates.
- [x] Added bounded wireframe `CollisionBounds_*` review aids around every
  staging station and required them in the gallery contract test. These are
  clearly review bounds, not authoritative gameplay collision shapes; staging
  and runtime-reference checks pass.
- [x] Added an explicit `review_all_downloads` mode to the isolated staging
  gallery. It enumerates every downloaded FBX source for visual inspection and
  telemetry while the default gameplay-scale gallery remains bounded; this
  keeps complete asset review separate from Android shipping content.
- [x] Strengthened that full-download mode to load every inventoried source,
  including audio streams, and require loaded-count equality in
  `test_asset_staging_gallery.gd` (190/190 at the current inventory). This
  proves every download is consumed by a runtime review station; authored
  gameplay placement remains limited by owner and Android budget gates.
- [x] Moved declared runtime-asset reference enforcement into
  `AssetIntakeCatalog.validate_entries()`: owner source files and each declared
  asset filename are now validated as part of the catalog itself. Catalog,
  runtime-reference, and intake-review checks pass.
- [x] Added path/import safety gates to the intake catalog: runtime assets must
  be project-local under `res://assets/`, use an approved extension, exist on
  disk, and be referenced by the declared owner. Negative-path catalog tests
  cover invalid paths and extensions; mesh/material/scale inspection remains
  open for the complete automated import-gate item.
- [x] Extended the catalog gate to load each declared runtime resource and
  reject failed imports, model scenes without renderable mesh instances, or
  textures with invalid dimensions. Catalog, runtime-reference, and staging
  checks pass; detailed material/scale budgets and device profiling remain open.
- [ ] Add automated import gates for scale, pivot, orientation, texture color
  space, material count, animation clips, collision layers, and missing files;
  fail with an actionable asset path and owner instead of a runtime surprise.
- [x] Extended the import gate with actionable model scale, material-surface,
  character animation-library, and collision-object checks while retaining the
  catalog's path, extension, loadability, and texture-dimension checks. Pivot,
  orientation, texture color-space, and per-layer collision inspection remain
  platform/importer-specific follow-up gates.
- [x] Added finite root position/rotation checks and an upper bound on imported
  root scale to the model import gate, with a zero-scale negative case. Invalid
  transforms now fail with the asset ID and path instead of reaching runtime.
- [x] Create an asset quality scorecard with required, review, and optional
  fields; make license evidence and gameplay-scale preview mandatory before an
  asset can be referenced by a shipped scene. `AssetIntakeCatalog.quality_score`
  and `quality_band` are covered by `tests/test_asset_quality_scorecard.gd`;
  uncleared license data cannot be ship-ready.
- [ ] Maintain a replacement-safe abstraction for external packs: gameplay
  data references stable semantic IDs while meshes, icons, sounds, and VFX can
  be swapped without save migration.
- [x] Added `ContentRegistry.resolve_asset_path()` so runtime consumers can
  resolve a stable semantic asset ID to a project-local replacement, with a
  deterministic fallback when an optional import is unavailable. Save schemas
  remain path-independent; wiring every gameplay owner through this resolver is
  still open.
- [x] Wired GroveDressing and CharacterRigLoader through semantic asset IDs with
  their existing direct-path fallback, so realm props and NPC/orc imports can be
  replaced without changing gameplay callers or save data.
- [x] Wired `EncounterZone` enemy scene resolution through the semantic content
  registry, registering spitter, fenling, moonfen fenling, and relic leech
  records while retaining deterministic legacy fallbacks. Encounter-pocket,
  registry-integrity, and population checks pass.
- [x] Expanded authored realm landmark dressing with a hard four-prop-per-realm
  pack set, using additional nature, graveyard, survival, mini-dungeon, and
  tower-defense imports at gameplay landmarks while keeping props visual-only
  until authoritative collision/interaction contracts are added.
- [x] Expanded intake ownership from pack-level representatives to every
  model file currently used by the authored landmark sets, splitting Mini
  Dungeon character and prop ownership so the runtime-reference gate covers
  both loaders without weakening stable IDs or license checks.
- [x] Added the remaining downloaded model variants (large nature rock, survival
  fence, Mini Dungeon barrel, and floor) to capped authored landmark dressing;
  the landmark set now consumes all downloaded model source files in gameplay
  owners, while foliage alternates remain review-only for overdraw control.
- [ ] Add deterministic asset budgets per category—hero, enemy, prop, foliage,
  VFX, UI, and audio—and review aggregate scene cost, not only individual files.
- [x] Added `AssetBudgetCatalog` with deterministic Android-oriented aggregate
  limits for hero, enemy, prop, foliage, VFX, UI, and audio content. Validation
  reports the exact category and field that exceeds a cap; device profiling and
  measured scene manifests remain release gates.
- [x] Built a curated vertical-slice catalog in
  `VerticalSliceCatalog`: one hero loadout, vendor, craftsman, bounded ambient
  animal/life system, three enemy factions with distinct encounter roles, one
  boss, and the complete Whispergrove realm kit. Resource existence/loadability
  and role coverage are enforced by `tests/test_vertical_slice_catalog.gd`.
- [x] Added the asset-usage gate: every imported pack has a gameplay owner and
  visible use case, while every downloaded source variant is explicitly
  enumerated by the full staging gallery. Only the 28 gameplay-owned files are
  used by shipped runtime owners; the remaining 162 files are labeled
  `REVIEW_ONLY` in the gallery so no file is silently lost or treated as
  required mobile gameplay content. Final release review still needs a real
  rendered/device pass.
- [x] Added a deterministic downloaded-asset inventory audit. Every source file
  is now classified as `GAMEPLAY` or explicit `REVIEW_ONLY`; importer metadata,
  licenses, readmes, and URL notes are excluded. This prevents silent unused
  files while keeping mobile gameplay bounded.
- [x] Added per-pack asset-coverage counts to the read-only support export, so
  reviewers can see gameplay-owned versus review-only downloaded files without
  exposing images or uploading any asset data.

### Phase J — Live-service restraint and player trust

- [x] Keep premium scan packs optional and transparent: show exact quantity,
  price, remaining balance, duplicate behavior, and restore path before purchase.
- [x] The Divining Lens offer now displays 5 scans, the exact dollar price,
  current/max scan balance, duplicate handling, and provider restore guidance.
  The purchase button remains disabled until a real provider integration is
  connected; scans remain earnable through gameplay.
- [ ] Define a fair economy ceiling before adding more currencies: every paid
  action needs an earnable route, a clear receipt state, restore handling, and
  no gameplay-critical purchase requirement.
- [x] Added `EconomyCeilingCatalog` for gold, diamonds, and scans. It documents
  each purpose and earnable route and rejects any paid currency marked
  gameplay-critical. Provider receipt/restore integration remains a launch
  gate, and no new currency should be added without a catalog row.
- [x] Add a player-facing ownership ledger for scans, currencies, purchases,
  rewards, and refunds; make every mutation idempotent and recoverable after a
  disconnect or app suspend.
- [x] The local ledger covers scans, currencies, purchases, rewards, sales, and
  owned gear with persisted activity entries and idempotent quest/chest reward
  claims. Provider-side refund records and authenticated disconnect recovery
  remain launch-gate work.
- [x] The journal now exposes an `OWNERSHIP LEDGER` summary for current gold,
  diamonds, scans, owned weapon/armor counts, and recorded purchases, alongside
  the persisted activity events. Refund semantics and provider-side idempotent
  reconciliation remain launch-gate work.
- [x] Corrected the shop ownership-history display to use each purchase's
  recorded currency instead of labeling all entries as GOLD, so diamond
  cosmetic purchases are transparent. Shop browse/comparison and UI shell
  checks pass.
- [x] Added successful sale events to the persisted ownership/activity ledger,
  including item id and exact gold value returned, so inventory outflow is
  visible alongside purchases and rewards. Shop and activity-history checks
  pass.
- [x] Completed scan-balance event visibility by recording earned scan charges
  and fragment gains alongside consumption, failures, and detection results.
  Existing scan economy, fragment, and activity-history checks pass.
- [x] Added explicit ledger entries for quest-stage milestone rewards and daily
  login bonuses before their centralized drop grants, making those reward
  sources distinguishable in support history. Progression, reward-history, and
  clean-route checks pass.
- [x] Made quest-stage milestone rewards save-safe and idempotent with persisted
  `quest_reward_claims`; repeated reward signals return without granting a
  second payout. `tests/test_quest_reward_idempotence.gd` verifies the contract,
  alongside progression and content-schema migration checks.
- [x] Added source-specific chest-open events to the persisted activity ledger
  while retaining the existing `opened_chests` and boss-gate protections.
  Chest-system, reward-history, activity-history, and whitespace checks pass.
- [x] Add consent, privacy, and camera explanations before scanning; clearly
  distinguish local image processing, uploaded processing, and generated game
  results in the UI and store copy.
- [x] Added pre-scan privacy copy to the Divining Lens: camera frames are
  processed locally, are not uploaded, and the generated weapon result is
  derived from the detected class rather than a stored photo. Desktop fallback
  status carries the same disclosure; forge camera, scan economy, and UI shell
  checks pass.
- [ ] Run a “no dark patterns” review for shop urgency, random rewards,
  duplicate outcomes, confirmation wording, accessibility, and child-safety
  expectations before monetization is enabled.
- [x] Added `MonetizationSafetyAudit` for the current shop, forge, and scan
  surfaces. It rejects urgency language and requires scan duplicate handling,
  exact balance disclosure, restore guidance, and no-guarantee wording before
  monetization can be enabled. Provider receipts, age/parental controls, and
  platform review remain launch gates.
- [x] Extended the monetization audit to inspect the paid catalog itself. Paid
  entries are restricted to cosmetic/SFX items or explicitly disclosed scan
  utility, reject gameplay power fields, and require scan duplicate/restore
  policies; the current catalog passes.

#### Android account and cloud-data architecture

- [x] Add a local idempotent intent queue primitive for future cloud sync;
  action IDs, payloads, retry counts, restore, and acknowledgement are covered
  without granting the client authority over balances.
- [x] Wire successful gold-shop and diamond-cosmetic purchases into the queue
  as server-validatable intent records; duplicate and failed purchases remain
  absent from pending cloud actions.
- [x] Wire successful crafting, weapon-upgrade, and armor-upgrade transactions
  into the queue with stable action IDs and cost/item payloads for later server
  validation.
- [x] Wire the authoritative scan-spend mutation into the queue with remaining
  balance metadata; random expedition rewards remain deferred until their grant
  transaction receives a stable idempotency key.
- [x] Wire successful checkpoint elemental attunement into the queue with the
  equipped item, selected element, and gold cost; unchanged and failed binds
  remain unqueued.
- [x] Add persisted expedition run IDs and queue exact expedition reward
  outcomes for later server validation; reward claims no longer depend on a
  realm name alone for idempotency.
- [x] Expose persisted retry-attempt marking through `GameState` so a future
  Android transport can record failed delivery and resume safely after process
  death.
- [x] Document the backend table contract, stable-ID invariants, RevenueCat
  boundary, and idempotent mutation-ledger response shape in `DATABASE_SCHEMA.md`.
- [x] Bound pending cloud intents to 128 actions so prolonged offline play
  cannot grow local sync storage without limit; overflow is rejected safely.
- [x] Added transport-agnostic queue reconciliation: accepted IDs are removed,
  retryable and terminal failures remain locally inspectable, unknown responses
  are ignored, and no server response can directly mutate local balances or
  inventory.
- [x] Persisted `delivery_status` and `last_error` on retryable/rejected local
  intents, so Android process death and support exports retain the exact
  resolution state instead of only a transient reconciliation summary.
- [x] Preserved queued delivery status and error text during queue restore, so
  Android suspend/process death does not turn retryable or rejected intents
  back into unexplained pending actions; the queue regression now covers this
  save round-trip.
- [x] Added a transport-neutral `PlayerSyncContract` for Android adapters:
  HTTPS-only endpoints, allowlisted gameplay intents, rejection of client-owned
  balances/inventory, and authoritative response-shape validation. It performs
  no network calls; authenticated backend integration remains a release task.
- [x] Hardened sync responses with required non-negative server revisions and
  duplicate response-ID rejection. Contract tests now cover malformed and
  duplicate responses before any future reconnect path can reconcile them.

- [ ] Keep `GameState` as the fast local cache so movement and offline gameplay
  remain responsive; synchronize through an authenticated HTTPS API when the
  device is online.
- [ ] Store player accounts, currencies, inventory, equipment, cosmetics,
  quests, scans, purchases, rewards, and refunds in a PostgreSQL/Supabase
  backend using stable content IDs and transaction records.
- [ ] Make gold, diamonds, purchases, rewards, and upgrades server-authoritative;
  the Android client submits intent (for example `upgrade_weapon` with an item
  ID), never a replacement currency balance.
- [x] Hardened `CloudSyncQueue` to reject authoritative replacement fields,
  including nested `gold`, `diamonds`, balances, inventory, equipment, stats,
  and player-state payloads. Intent metadata such as item IDs and costs remains
  accepted for later server validation.
- [x] Queue idempotent offline actions and reconcile them after reconnect,
  app suspension, or process death; stable action IDs reject duplicates,
  pending intents are capped and persisted, and failed reconciliation preserves
  the local save as the recovery point. The authenticated transport/reconnect
  integration remains a separate release task.
- [ ] Validate RevenueCat Android purchase or subscription entitlements on the
  server. RevenueCat confirms paid access; it does not become the inventory,
  combat-stat, or currency database.
- [ ] Protect authentication tokens with Android secure storage, use TLS for
  every request, and never upload scan images unless the player explicitly
  consents and the UI identifies local versus uploaded processing.
- [ ] Add conflict, duplicate-request, reconnect, suspend/resume, and corrupted
  response tests before enabling cloud progression for production players.

### Phase L — High-end RPG depth without feature bloat

- [x] Give every realm a three-layer loop: a short readable activity, a medium
  encounter route, and a long-term mastery goal; reward returning players with
  new decisions rather than only larger numbers.
- [ ] Add faction and creature ecology relationships—predator/prey, rival
  factions, elemental reactions, and realm hazards—only where they create
  visible tactical choices and remain understandable in the bestiary.
- [x] Added `EcologyTacticsCatalog` with one bounded, player-readable choice
  for each realm, connecting existing predator/prey, rival, elemental, and
  hazard descriptions to concrete consequences. The catalog is validated for
  complete choice/trigger/consequence records; encounter opt-in wiring and
  real-rendered readability remain open.
- [x] Encounter pockets now opt into the catalog at setup: their reveal
  contract carries the realm ecology trigger, player choice, and consequence,
  and the reveal label surfaces the trigger. Spawn counts, damage, timing, and
  rewards remain unchanged until an authored interactive choice pass.
- [x] Added a bounded `EncounterZone` ecology choice API with a primary tactic
  and a safe defer branch. Selection is exposed in the pocket contract and via
  `ecology_choice_changed`, rejects invalid/late choices, and preserves combat
  balance until branch-specific effects receive authored tuning and UI.
- [x] Added bounded primary-tactic modifiers for each realm and exposes them in
  the encounter contract; the defer branch remains neutral and the selection
  receives a restrained visual state cue. Structural consequence tests pass;
  authored in-combat application and real-rendered readability remain open.
- [ ] Design boss encounters as authored lessons: introduce one rule, test it,
  combine it with a second rule, then provide a mastery payoff; never rely on
  surprise damage or unreadable arena clutter for difficulty.
- [x] Formalized the Matriarch lesson in `BossLessonCatalog`: introduce thorn
  spacing, test root-denied center movement, combine storm timing with crown
  vulnerability, then pay off mastery with the relic reward. Catalog and boss
  source coverage are validated; real-rendered teaching clarity remains open.
- [x] Wired `BossBase.boss_lesson()` into phase guidance labels. Each phase now
  surfaces its corresponding lesson rule at runtime without changing attack
  timing, damage, hitboxes, or rewards; catalog and lesson-contract checks pass.
- [ ] Add meaningful build planning with a small number of high-impact stats,
  clear soft caps, loadout presets, respec rules, and side-by-side previews;
  prevent inventory sorting and comparison from becoming friction.
- [x] Added four bounded, save-safe loadout presets storing semantic weapon and
  armor IDs. Applying a preset reuses existing equip transactions, changes no
  currency or reward state, and rejects out-of-range slots. Preset capture and
  application are covered by `tests/test_loadout_presets.gd`; respec and
  side-by-side UI presentation remain open.
- [x] Added explicit stat respec rules: a level-scaled gold cost, exact return
  of allocated points, bounded empty-respec rejection, and no changes to level,
  XP, gear, rewards, or achievements. The transaction is persisted and logged
  in activity history; `tests/test_respec_rules.gd` covers the contract.
- [x] Added visible loadout preset controls to the stat screen. Each bounded
  slot can save/apply the equipped weapon and armor using semantic IDs, with
  explicit SUCCESS/FAILED copy and unavailable slots disabled.
- [x] Added a side-by-side stat projection to the build guide: current STR/DEX/
  VIT/LUK/END values remain visible beside the selected preset's preview before
  any points are committed. The player-stat projection test covers the UI
  contract.
- [x] Create a quest journal that tracks why, where, risk, reward, and next
  action in one glance; support pinned objectives, readable map context, and
  recovery after abandoning or failing an activity.
- [ ] Add accessibility as a content requirement: remapping, target-size
  controls, subtitle/audio mix, color-safe status shapes, reduced motion,
  flash/shake controls, text scaling, and one-handed mobile layouts must be
  validated in real gameplay scenes.
- [ ] Establish a release-candidate playtest loop with scripted observation:
  measure confusion, deaths, upgrade comprehension, shop trust, scan clarity,
  and route completion before adding more content.
- [ ] Add purchase failure, cancellation, offline, restore, and interrupted
  transaction states to the shop UI; grant scans only after the entitlement
  provider confirms the transaction.
- [x] Added an explicit scan-pack purchase state model covering unavailable,
  pending, failed, cancelled, offline, restoring, and provider-confirmed states.
  Failed/cancelled states permit retry; all other states block duplicate
  activation, and no state grants scans by itself. Provider integration remains
  intentionally unconfigured.
- [ ] Keep gameplay-critical power earnable through play; audit every paid item
  for pay-to-win pressure, unclear probability, forced currency conversion, and
  accidental repeat purchase risk.
- [ ] Add a player-facing combat log and reward history for recent damage,
  status effects, drops, purchases, scans, crafting, and boss selections;
  make it useful for support and balance investigations.
- [x] The expedition journal already provides a bounded `RECENT ACTIVITY`
  surface fed by the persisted activity ledger and reward events, with newest
  entries first and a hard display cap. `test_reward_history.gd` and
  `test_activity_history.gd` pass; a dedicated expanded combat-log screen is
  not being duplicated until the route proves it is needed.
- [ ] Add a safe account/data export and reset explanation before launch, with
  clear local-save versus entitlement ownership semantics.
- [x] Settings now explains that support export is diagnostic, local reset is
  device-only, and provider-owned purchases require provider restore/cancel
  semantics. `test_data_export.gd` and the UI-shell test pass; no destructive
  reset action or external entitlement integration is enabled yet.
- [ ] Run a final “new player, returning player, and lapsed player” usability
  review to remove unnecessary friction, overlong tutorials, and dead-end
  progression states.

### Phase K — High-end vertical-slice excellence

- [ ] Lock one 20–30 minute “golden route” and review it as a complete authored
  experience: arrival, orientation, first combat, gathering, escalation, elite,
  boss, reward, upgrade, and visible next objective. Do not add new systems to
  the route until its pacing and comprehension are strong.
- [ ] Create a pacing sheet with target minutes, player intent, expected threat,
  reward value, camera language, music state, and recovery point for every beat.
  Use it to remove empty travel, repeated tutorials, and back-to-back menus.
- [ ] Give every encounter a composition pass: entry signal, readable arena,
  enemy roles, reinforcement rules, retreat space, loot position, and a clean
  exit state. Cap simultaneous threats for touch controls and low-end Android.
- [ ] Author a threat hierarchy for each fight so the player immediately knows
  what to dodge, what to interrupt, what can be ignored, and what is safe to
  approach. Confirm the hierarchy remains clear during overlapping VFX.
- [ ] Finish one hero combat kit end to end before expanding the roster: idle,
  locomotion, anticipation, attack, hit, stagger, dodge, death, equipment swap,
  weapon trails, sound, camera response, and exact damage-frame alignment.
- [ ] Add animation quality gates for foot sliding, root motion, hand-to-weapon
  alignment, hit-reaction direction, weapon clipping, mirrored attacks, and
  transitions at both normal and boosted movement speeds.
- [ ] Establish a material response library for wood, stone, metal, bone, cloth,
  slime, foliage, ice, magma, and shadow. Pair each material with a restrained
  hit sound, impact color, decal rule, and particle budget.
- [ ] Build a realm ambience mix with foreground, midground, and distant layers:
  wind/water/wildlife, landmark sounds, activity sounds, combat ducking, and
  music transitions. Enforce voice limits and cleanup for every looping source.
- [ ] Add controlled discovery rewards for landmarks, shortcuts, rare gatherables,
  secret rooms, and optional lore. Every discovery must be signposted, useful,
  save-safe, and understandable without requiring a collectibles checklist.
- [ ] Add a deterministic encounter seed and debug overlay showing spawn roles,
  threat caps, navigation cost, active hazards, reward source, and cleanup state.
  Keep it editor/debug-only and exclude it from release builds.
- [ ] Define a visual-quality ladder for Low/Medium/High/Ultra where gameplay
  timing, collision, telegraphs, silhouettes, and reward logic never change;
  only presentation cost, density, shadows, reflections, and audio layering vary.
- [ ] Run a mobile readability pass at real gameplay distance: enemy silhouette,
  target ring, telegraph contrast, loot sparkle, interact prompt, health bars,
  status icons, and objective markers must remain legible without zooming.
- [ ] Add failure recovery design for death, disconnect, app suspend, scene load,
  interrupted purchase, interrupted craft, and boss reset. Each path must return
  the player to a valid state without duplicated currency, loot, or quest credit.
- [ ] Introduce release candidate gates: clean import, parser scan, save migration,
  route smoke test, asset/license audit, audio cleanup audit, performance profile,
  accessibility review, and two consecutive fresh-save completion passes.
- [ ] Capture before/after evidence for every premium polish change. Separate
  structural headless results from real-renderer screenshots and physical-device
  measurements; never approve a visual or performance claim from code alone.

### Definition of high-end readiness

- [ ] A new player can complete the first route without unexplained stalls,
  duplicated rewards, unreadable combat, or menu dead ends.
- [ ] Every realm has a recognizable visual and gameplay identity at a glance.
- [ ] Every combat action has intentional timing, readable feedback, and a
  reason to choose it.
- [ ] Every reward creates an understandable decision and survives save/load.
- [ ] Every important screen is legible and usable on the Android target.
- [ ] Real-rendered and physical-device evidence supports the claimed quality;
  headless tests remain structural evidence only.

### Verified implementation notes

- Boss reward choices now use the shared semantic action-state contract: each
  option is explicitly marked `AVAILABLE` and its tooltip explains that the
  selection is only a preview until the reward flow confirms it. Reward
  selection, persistence, and economy behavior are unchanged; focused panel,
  selection, and wiring tests pass.

- BossBase now exposes a bounded phase-guidance contract and emits
  `phase_guidance_changed` on transitions. Each phase has a readable pattern
  and safe-space rule for future HUD/arena presentation; it does not alter
  collision, damage, or telegraph timing. Boss phase validation covers all
  four stages.

- Custom mobile combat controls now consume the shared semantic action-state
  contract. Attack, dodge, jump, equipped skills, empty skill slots, and skill
  cooldowns expose consistent availability labels and explanatory tooltips;
  input routing and combat timing are unchanged.

- Combat-card scan and target controls now expose explicit AVAILABLE,
  UNAVAILABLE, ANALYZED, and TARGET SWITCHED feedback with concise tooltips;
  scan consumption and target cycling behavior remain unchanged.

- Chapter lesson state now refreshes independently of side-objective content,
  so an empty side-objective list cannot leave the lesson button stale. The
  button exposes completion/readiness copy and a tooltip through the shared
  action-state vocabulary.

- Removed the remaining dependency between lesson-state refresh and the
  side-objective label node, so a missing/hidden objective surface cannot leave
  chapter lesson state stale.

- Gathering nodes now teach the interaction diegetically with a clear
  `HOLD TO GATHER` prompt alongside the realm-specific ritual cue. The hold
  duration, cancel-on-exit behavior, yield, and persistence remain unchanged.

- Reward toasts now use a restrained rarity-aware reveal title for rare, epic,
  and legendary weapon/armor drops while retaining existing reward focus,
  grant timing, and history entries.

- Shop purchase feedback now explicitly distinguishes `PURCHASED` confirmation
  from `PURCHASE FAILED`, while the rebuilt stock row still derives ownership,
  equipment state, and affordability from GameState.

- Added a backward-compatible informational `purchase_ledger` to GameState.
  Successful shop purchases record item, kind, and price and round-trip through
  saves; the ledger does not authorize purchases or affect gameplay stats.

- Shop save/load coverage now verifies that recorded ownership entries survive
  a complete GameState round trip alongside equipped gear.

- The shop now exposes a compact player-facing `OWNERSHIP LEDGER` summary with
  the count and latest recorded purchase, plus an informational tooltip.

- Added a `VIEW OWNERSHIP HISTORY` shop action showing the five most recent
  recorded purchases and their prices, keeping the ledger inspectable without
  changing any purchase or inventory behavior.

- Diamond/cosmetic shop actions now use shared semantic states: disconnected
  scan purchases are explicitly unavailable, active cosmetics are equipped,
  owned cosmetics are ready to equip, and purchasable cosmetics explain their
  cosmetic-only scope.

- Forge camera preview now discloses `LOCAL CAPTURE · NO PHOTO UPLOAD` and the
  scan button tooltip repeats the local-only boundary before capture; scan
  consumption and camera pipeline behavior are unchanged.

- Added a deterministic asset quality scorecard (license/provenance, mobile,
  geometry, texture, collision, and Android fallback evidence) with
  `SHIP-READY`, `REVIEW`, or `HOLD` bands shown in the intake review tool.

- Asset intake summary now reports aggregate average quality and the number of
  `SHIP-READY` packs, making release review gaps visible at a glance.

- Service NPC prompts now name their destination (`VISIT SHOP` or `OPEN FORGE`)
  instead of presenting an ambiguous generic interaction label; existing menu
  routing remains unchanged.

- Added an isolated `AssetStagingGallery` tool scene with bounded pedestals,
  controlled review lighting, gameplay-scale labels, and three representative
  imported assets. It is a production review surface, not a gameplay preload;
  the gallery scene load/build test passes.

- The asset gallery now includes a dedicated centered review camera, making
  the tool scene immediately viewable without editor camera setup. Camera
  framing is isolated to the tool and does not affect gameplay camera ownership.

- [x] Restored the elemental-status compatibility surface for enemy and boss
  callers: status snapshots, frost/shock aliases, bounded active effects,
  timed DoT cadence, movement slowdown, and readable MELT reaction feedback.
- [x] Added a restrained live-hand upgrade presentation: upgraded imported
  weapons receive a bounded scale accent and forge-colored accent ring while
  gameplay stats and combat timing remain data-driven and unchanged.
- [x] Made merchant controls responsive: the shop tab row changes from a
  four-column desktop grid to a two-column compact layout, preserving readable
  labels and touch-sized controls on narrow screens.
- [x] Made merchant action states explicit: unaffordable stock shows the exact
  gold shortfall, owned gear distinguishes EQUIPPED from OWNED / EQUIP, and
  each state exposes a concise tooltip without enabling invalid actions.
- [x] Centralized compact/expanded breakpoints, safe margins, content width,
  spacing, and tab-column metrics in `UiKit.responsive_metrics()` and routed
  the merchant layout through that shared token contract.
- [x] Made forge actions state-aware: attunement shows the exact gold shortfall,
  already-active elements explain why they are disabled, valid elements expose
  an action tooltip, and scan availability is reflected in the primary button.
- [x] Clarified combat target commitment in the HUD: the card explicitly labels
  the selected foe as LOCKED and the cycling action now says NEXT TARGET with a
  precise tooltip, while target selection and combat timing remain unchanged.
- [x] Added role-based, color-independent target guidance to the combat card:
  boss survival, ranged interruption, guard flanking, elite telegraph reading,
  and general threat closure are stated as text beside the live HP readout.
- [x] Updated the realm-expansion validation harness to exercise the current
  gate/altar public contract when legacy removed geometry is absent, preventing
  obsolete scene assertions from hiding real visual-suite failures.

- [x] Shop browse controls have runtime regression coverage for deterministic
  price ascending sort, power descending sort, armor category filtering, and
  disabling the buy-only filter while selling.
- [x] Gear inspection exposes candidate-versus-equipped deltas, rarity,
  combat/defensive identity, source, and readable salvage value without
  mutating equipment state.
- [x] Gear inspection regression test covers weapon comparison and armor
  context text after the UI is instantiated.
- [x] Gear inspection now creates an isolated, non-gameplay 3D hero-and-item
  preview with bounded nodes and explicit cleanup when a new item is inspected.
- [x] Preview presentation places the weapon at the mannequin's right-hand
  grip and armor across the torso, with simple arm geometry for readable
  equipped context.
- [x] Preview attempts the shipped authored hero FBX first and falls back to
  the bounded mannequin when the import is unavailable.
- [x] Weapon inspection attempts shipped authored weapon assets per stable item
  ID and retains procedural geometry only as an explicit fallback.
- [x] Scan results now show detected template, confidence, bounded-roll
  language, explicit inventory-save identity, and a separate discard action.
- [x] HUD now exposes a focused expedition journal overlay using the existing
  save-backed chapter, checkpoint, objective, and reward-progress state.
- [x] Expedition journal includes a four-chapter map with explicit cleared,
  current, and locked states derived from the active quest stage.
- [x] Dungeon selection now derives available/current/locked presentation from
  save-backed realm unlocks instead of treating every non-starter card as a
  permanently locked placeholder.
- [x] Dungeon realm-state presentation has a focused regression test covering
  card count and the available/current/locked copy contract.
- [x] Unlocked non-Embervault cards now route to their actual realm scene;
  Embervault retains its dedicated dungeon-expansion route.
- [x] Realm travel now uses a bounded 0.28-second fade transition before scene
  replacement, removing abrupt visual pops while preserving route behavior.
- [x] Dungeon selector regression coverage now guards the realm-routing and
  bounded fade-transition contract.
- [x] First-clear realm unlock messages now use a longer, explicit `REALM
  UNLOCKED` HUD toast that directs players to the expedition journal.
- [x] Boss phase HUD copy now communicates the player's combat read (“watch
  the arena”, “new pattern”, “survive the window”) instead of exposing only a
  bare phase number.
- [x] Boss customization payloads now round-trip palette colors and preserve
  the legacy `sfx_profile` plus current `sfx_preset` naming contract; the
  Heartwood hard-tier roster assertion matches the shipped Spore Weaver.
- [x] Matriarch thorn-guard break presentation is safe when exercised before
  scene-tree attachment, avoiding off-tree transform reads in validation and
  tooling paths.
- [x] Boss default attack timing and warning geometry are centralized in
  auditable `ATTACK_PROFILES`; existing damage and collision values remain
  unchanged while subclasses retain their specialized telegraphs.
- [x] Added `ANIMATION_MATRIX.md` as the production coverage sheet for hero,
  NPC, enemy, boss, and training-target animation states and fallback rules.
- [x] Added `REALM_VISUAL_GRAMMAR.md` with realm-specific composition, palette,
  landmark, weather, traversal-pressure, and ambient-life rules; runtime and
  Android validation checkboxes remain open until each realm is captured.
- [x] Added a typed `EncounterZone.pocket_contract()` authoring contract and
  regression test so encounter dressing can name approach, reveal, combat,
  reward, and exit beats without changing enemy timing, damage, or rewards.
- [x] Procedural placement now assigns stable realm/tier-specific pocket
  profiles so generated encounters carry authored approach, reveal, reward,
  and exit language instead of anonymous random-zone identity.
- [x] Added `RealmIdentityCatalog` and regression coverage defining a
  signature traversal activity, resource ritual, ambient behavior, elite
  composition, and landmark reward for every shipped realm.
- [x] The expedition journal now surfaces the active realm's traversal and
  resource identity plus landmark reward, giving the player a clear reason to
  explore the current realm before closing the map.
- [x] Gathering nodes now surface the active realm's resource ritual in their
  interaction prompt, while preserving the existing hold-to-gather flow,
  quantities, objective updates, depletion, respawn, and save behavior.
- [x] Added an optional in-world `RealmActivityBeacon` to each dressed realm;
  it teaches the signature traversal activity and records discovery through
  the existing landmark save state without blocking the main route.
- [x] Realm activity beacons now grant bounded, realm-specific landmark rewards
  exactly once on first interaction; repeat interactions are informational and
  cannot duplicate gold, materials, or scan fragments.
- [x] Activity beacon labels now preview both the realm traversal activity and
  its landmark reward direction before interaction, keeping the world-space
  affordance consistent with the expedition journal.
- [x] Added a content-registry integrity gate covering stable weapon/armor IDs
  and reachable crafting outputs, preventing future data additions from
  silently creating duplicate or uncraftable content.
- [x] Added versioned `ContentSchema` gear normalization and save-load
  migration coverage; legacy weapon and armor records gain only safe additive
  defaults while saved stats and progression remain unchanged.
- [x] Added an end-to-end legacy-save fixture proving `GameState.load_game()`
  applies the content migration to old weapon and armor records.
- [x] Added a typed `BossRewardCatalog` with distinct build-direction choices
  for the Matriarch encounters; existing guaranteed rewards remain unchanged
  until a dedicated post-boss choice UI and exactly-once selection flow are
  implemented.
- [x] Added a non-mutating `BossRewardChoicePanel` that presents those choices
  as readable build cards and emits a selection request; reward granting remains
  intentionally gated until save-backed exactly-once authorization is complete.
- [x] Added save-backed `GameState.choose_boss_reward()` authorization with
  catalog validation, exactly-once selection, gear grant, and round-trip
  coverage. The existing boss-kill path remains unchanged until the panel is
  connected to the intended post-boss moment.
- [x] Connected repeat boss clears to the choice panel; first-clear guaranteed
  rewards remain unchanged, while later eligible clears emit a choice request
  that uses the save-backed exactly-once authorization path.
- [x] Made boss-choice grant and selection persistence a single save transaction
  with duplicate-safe inventory insertion, removing the crash window between
  granting gear and recording the chosen reward.
- [x] Connected the repeat-clear choice announcement to the finalized boss
  death lifecycle, after subclass rewards settle and before the boss is freed;
  first-clear and practice encounters remain excluded.
- [x] Added a single, interruptible music-state contract over the existing
  combat bed and synchronized boss score: exploration, danger, elite, and boss
  transitions cannot stack competing playback; menu/victory/defeat states are
  reserved for their owning flows.
- [x] Boss-score start, victory/defeat fade, and immediate teardown now update
  the music state explicitly, preventing stale `boss` state after a realm
  transition or an interrupted encounter.
- [x] Boss music lifecycle regression coverage now exercises victory and defeat
  transitions with generated score layers plus immediate teardown, including
  the no-external-asset headless path used by automated validation.
- [x] Added a typed asset-intake catalog for imported environment and foliage
  packs, recording source, license evidence, realm purpose, and mobile review
  status; invalid or duplicate intake IDs fail focused validation.
- [x] Centralized the Android 48dp-equivalent touch-target floor in `UiKit`;
  all shared button styling roles now preserve larger authored dimensions while
  preventing undersized code-built actions.
- [x] Added full-scene equipment regression coverage through the real
  MainMenu-to-Grove boot path, confirming equipped weapon identity reaches the
  live Hero and mounts into its hand socket.
- [x] Extended the real boss lifecycle validation to check the shared
  anticipation/impact/recovery contract during a normal boss scene boot,
  keeping timing evidence attached to the same autoload-aware harness.
- [x] Authored encounter pockets now trigger a short, non-blocking camera focus
  beat on arrival, using the existing skippable cinematic contract before pack
  spawn while preserving movement, input, and combat timing.
- [x] Added Grove-scene coverage for encounter focus cancellation and bounded
  auto-release, proving camera ownership returns to normal after interruption or
  the timed reveal.
- [x] Targeted combat cards now show a readable threat role plus target name and
  HP, with deterministic role fallback for legacy enemies that do not expose a
  dedicated kind field; target cycling behavior remains unchanged.
- [x] Added a bounded recent-activity section to the expedition journal so
  loot, rewards, crafting, upgrades, scans, and purchases remain reviewable
  after transient HUD notifications expire.
- [x] Made the Expedition Journal resize and reposition from viewport bounds,
  preserving readable minimum dimensions in portrait while keeping the panel
  inside safe margins in landscape; full-Grove coverage checks containment.
- [x] Expanded asset intake to all six current imported packs and made local
  license evidence mandatory during validation; missing attribution files now
  fail before an asset is treated as production-ready.
- [x] Added an asset-intake review scene that lists every imported pack with
  category, realm purpose, license, and mobile-review state in a bounded scroll
  surface; all six current packs are covered by scene-level validation.
- [x] Extended the asset-intake review surface with bounded readiness totals,
  category coverage, and realm coverage so staging review exposes what is
  production-ready before more assets are assigned to gameplay.
- [x] Realm swaps now keep the current environment as the transition baseline
  and interpolate fog color, fog density, ambient energy, and realm audio while
  the existing fade protects the biome rebuild; no gameplay timing changes.
- [x] Realm environment blending now uses one deterministic helper for fog,
  ambient light, and sky colors; midpoint and endpoint regression coverage keeps
  transition math reviewable even when renderer timing is unavailable.
- [x] Added a bounded `DistantLandmarkSilhouettes` layer to the shared world
  composition: each realm receives up to three route-keyed far silhouettes with
  no collision or shadow cost, and five-realm visual coverage verifies the cap.
- [x] Made weather presentation quality-aware: `WorldState` preserves the
  logical/save rain level while its shader-facing rain level follows the active
  Low/Medium/High particle scale, with world-state regression coverage.
- [x] Made world gust easing interruptible: a new gust cancels the prior
  transition before starting its bounded return-to-calm tween, preventing
  overlapping wind callbacks during repeated weather events.
- [x] Centralized legacy inventory and quest-objective normalization in
  `ContentSchema`, with bounded quantities, valid objective types, and
  completion reconstruction protected by regression tests.
- [x] Extended `ContentSchema` to normalize scan charges/fragments and
  de-duplicate normalized realm unlock lists while retaining mandatory starter
  realms; added focused migration coverage.
- [x] Added `tests/test_clean_route_contract.gd` to protect the fresh-save
  route spine across all four stages, checkpoint ordering, objective presence,
  save/load recovery, and repeated-checkpoint idempotence. Real-rendered
  playthrough acceptance remains intentionally separate.
- [x] Closed a route-state continuity gap: advancing a story stage now clears
  stale active/failed/abandoned activity recovery in the same checkpoint
  transition, and the clean-route contract verifies the recovery banner cannot
  leak across stage progression.
- [x] Ambient life now applies realm-specific behavior data: Whispergrove uses
  drifting butterflies while the other realms use slower firefly-like motion,
  with the existing particle caps, deterministic seeds, and cleanup preserved.
- [x] Realm activity beacons now communicate discovery state in-world: the
  player sees the realm activity and reward before interaction, then receives a
  persistent `DISCOVERED · ALREADY CLAIMED` state after the save-safe reward.
- [x] Cleared encounter pockets now reveal a short, auto-cleaning in-world
  reward marker using the authored reward label, giving the player a visible
  payoff without changing reward timing or economy.
- [x] Meaningful loot now carries player-facing context in the reward summary:
  weapons identify a new build option, armor points to Satchel comparison,
  and materials explain their crafting/upgrade use plus realm affinity; the
  HUD shows this context without changing drop rates, quantities, or economy.
- [x] Added `tests/test_loot_context.gd` to protect reward-context wording and
  keep ordinary gold/XP rewards free of unnecessary explanation text.
- [x] Added a bounded, save-safe activity ledger for economy events: gold and
  diamond gains/spends are retained in `GameState` and surfaced in the journal
  alongside the session reward list; cap/order coverage lives in
  `tests/test_activity_history.gd`. Combat/status/drop event coverage remains
  a follow-up to the full combat-log task.
- [x] Routed authoritative hero combat call sites into the same ledger for
  player hits, skill hits, critical hits, incoming damage, and elemental
  status applications. The entries are bounded and journal-visible; enemy
  drop/purchase/scan/boss-event detail still needs its own event labels.
- [x] Added concise persisted ledger labels for shop/cosmetic purchases, scan
  consumption, and boss reward selection, including both gold and diamond
  spending paths. Scan economy and boss reward regression suites pass.
- [x] Routed the central `RewardManager.grant_drops()` dispatcher into the
  ledger so item, material, weapon, armor, XP, and currency drops are recorded
  once at the authoritative grant point; first-kill boss rewards receive a
  distinct event label. Reward-context, boss-selection, route, and journal
  regression suites pass.
- [x] Added scan telemetry to the same player-facing ledger at the authoritative
  scan boundary: failed attempts, charge consumption, detected class, and
  confidence are recorded for camera and desktop-simulated scans. Scan economy,
  fragment, product, and activity-history tests pass.
- [x] Added boss lifecycle ledger events for boss defeat, realm context, and
  available repeat-kill reward choices at the centralized reward boundary.
  Boss catalog, selection, lesson, and activity-history tests pass.
- [x] Added a read-only `GameState.build_data_export()` support payload with
  local progression, inventory, equipment, realm, and activity data separated
  from non-authoritative purchase records. The export explicitly requires
  account-provider entitlement revalidation and never presents local ledger
  entries as receipts; `tests/test_data_export.gd` covers the contract.
- [x] Exposed the support export from Settings as a non-destructive
  `COPY SUPPORT EXPORT` action with player-facing local-save versus entitlement
  guidance and a post-copy safety message. UI shell and data-export checks pass.
- [x] Added successful crafting, weapon-upgrade, armor-upgrade, and element
  attunement events to the bounded activity ledger after their authoritative
  mutations complete. Crafting bench, upgrade clarity, armor-loop, and ledger
  regression suites pass.
- [x] Added boss phase-transition events to the activity ledger, including
  phase number and boss node identity, so phase escalation is visible in the
  player-facing history. Deterministic elite timing and boss telegraph
  contracts pass; the scene-based phase probe passes when invoked through its
  attached validation scene.
- [x] Added centralized boss-hit and encounter-reset events to the ledger,
  including applied damage and critical-hit context. Elite timing, boss
  telegraph, activity-history, and whitespace checks pass.
- [x] Corrected the boss phase validation invocation/documentation: the
  attached `tests/boss_phase_transition_validation.tscn` now provides the
  authoritative scene-based probe, which passes all phase thresholds, grounded
  visibility, pattern, safe-zone, and vulnerability checks.
- [x] Made the HUD reward toast animation-owned and interruptible: a new loot
  or reward reveal kills the prior fade tween before starting its bounded timer,
  preventing stacked playback and stale visual state.
- [x] Added a typed `QualityScaler` presentation-budget report and invariant
  check covering particles, debris, VFX pools/trails, transient lights,
  corpses, vegetation, grass density, and material detail without coupling
  gameplay timing or damage to quality settings.
- [x] Extended quality-budget validation across Low, Medium, and High tiers;
  each tier now has deterministic pool/trail/light caps and the consolidated
  visual suite verifies the caps without changing gameplay behavior.
- [x] Extended full-scene equipment coverage through a real weapon upgrade:
  attack increases, `weapon_changed` refreshes the equipped presentation, and
  the live hand socket receives the bounded upgrade accent.
- [x] Extended full-scene equipment validation to assert the held sword keeps
  its intended hand-socket parent and stays within the authored palm offset
  after boot and upgrade; this protects visible weapon alignment without
  changing the combat clock.
- [x] Added `CharacterRigLoader.animation_coverage()` so imported rigs report
  idle, movement, attack, hit, death, and authored-ready coverage by stable
  clip tokens while preserving procedural fallback for missing animations.
- [x] Added a shared elite special-attack timing contract for charge, bramble
  charge, and counter attacks; charger telegraph anticipation now reads that
  contract, with bounded timing regression coverage.
- [x] Expanded content-registry integrity coverage beyond gear and recipes to
  validate stable realm IDs, normal/hard/elite enemy variants, realm identity
  metadata, and boss skill-pool IDs before content is treated as shippable.
- [x] Structural realm ecosystem validation passes with 47 checks across
  Bramblewood and Moonfen, including deterministic landmarks, instanced foliage,
  terrain materials, realm tint/moisture, reserved-anchor clearance, and
  separation. Gameplay-scale real-render review remains open for the broad
  foliage/ambient acceptance item.
- [x] Added a persisted Recovery Assist setting that grants only a capped dodge
  grace increase; it leaves damage, rewards, achievements, and progression
  unchanged and is exposed with an explanatory tooltip in Settings.
- [x] Added shared semantic action-state copy for locked, unavailable, loading,
  purchased, owned, equipped, crafting, scanning, restoring, and failed states;
  shop purchase/equip controls now consume the common contract.
- [x] Extended semantic action-state adoption to Forge camera and scan controls:
  desktop simulation, unavailable camera fallback, unavailable scan inventory,
  and active scanning now communicate through shared state labels; forge/shop/UI
  focused tests pass.
- [x] Extended the semantic action-state contract into Satchel weapon and armor
  equip actions, including explicit equipped/owned labels and tooltips; the
  inventory and full-scene equipment paths retain their existing behavior.
- [x] Extended semantic action-state adoption to Dungeon Select, including
  locked, available, and current-realm entry states with explicit tooltips and
  disabled behavior for the current realm.
- [ ] Add bounded recovery-assist regression coverage through normal gameplay
  scene boot; direct isolated loading of `hero.gd` is invalid because its
  autoload-dependent `ScanManager` reference requires the project class registry.
- [x] Added an autoload-aware Grove scene boot probe for Recovery Assist. It
  verifies the live Hero exposes only the capped dodge-grace increase and that
  default HP/gold progression remains unchanged after boot.
- [x] Strengthened asset intake gates with explicit polygon, texture, animation,
  collision, and Android-fallback review fields; all six current packs pass the
  catalog, credit, and review-surface tests.
- [x] Restricted asset intake licenses to an explicit approved set and rejected
  non-HTTPS source URLs; negative-path catalog coverage confirms unclear legal
  provenance cannot pass review.
- [x] Re-ran the consolidated visual suite after the latest combat, registry,
  asset, and UI changes: all four validation scenes and six visual scripts
  passed, including boss phases, elemental status, realm visuals, and VFX/UI
  budgets.
- [x] Re-ran the progression baseline: clean-route checkpoints, content-schema
  load/progress/scan migrations, scan economy/fragments, vertical-slice
  progression, and route checkpoint idempotence all pass. Camera acquisition
  remains intentionally unavailable in headless mode while scan economy logic
  still passes.
- [x] Extended the boss timing contract with explicit active-impact windows and
  migrated Matriarch root-prison and bramble-storm delays to named profiles;
  the timing suite now covers core boss attacks plus those authored specials.
- [x] Added per-archetype elite special timing profiles for charger, ambusher,
  stalker, elemental, leech, fenling, and elite variants; telegraph anticipation
  and recovery now use the same state-machine contract instead of one shared
  literal, with coverage for all eleven profile keys.
- [x] Routed Matriarch special-attack radii through the same profile data used
  by their telegraphs and delayed damage, with bounded-radius assertions for
  every boss timing profile; timing and boss phase validation both pass.
- [x] Added bounded per-archetype elite special radii and routed the visible
  ground/ring telegraphs plus chain-lightning range through those profiles;
  elite timing and combat-recovery regression tests pass without changing
  damage values or effect shapes.
- [x] Expanded content-registry integrity coverage beyond gear and recipes to
  validate stable realm IDs, normal/hard/elite enemy variants, realm identity
  metadata, and boss skill-pool IDs before content is treated as shippable.
- [x] Migrated Matriarch thorn-rain, thorn-lattice, and spore-bloom timing
  literals to the same named profiles; elite/boss timing coverage now includes
  eight attack families. The separate boss phase scene is validated through its
  intended `.tscn` entrypoint for runtime lifecycle evidence.
- [x] Added `GOLDEN_ROUTE_BEATS.md` as the pacing contract for the first
  20–30-minute vertical slice, including target minutes, player intent,
  authored signals, rewards, recovery points, and explicit real-rendered/
  Android acceptance criteria.
- [x] Verified the boss phase transition scene through its intended scene
  entrypoint: thorn-guard break, crown vulnerability, phase 2, phase 3, and
  enrage all preserve visibility and grounding, and the scene exits with
  `RESULT: PASS`. The earlier apparent hang came from invoking a Node scene
  script with `--script` instead of its `.tscn` entrypoint.
- [x] Re-ran world-chunk streaming validation across streamed and static realms:
  deterministic content, per-chunk caps, terrain vertex limits, arena
  clearances, far-fill presence, movement rebuilds, and wall relocation all
  pass. Physical-device hitch and shader-warmup profiling remains open.
### Verified implementation notes — purchase history coverage

- Extended the purchase ledger to include successful diamond cosmetics as
  `cosmetic_<kind>` entries with currency metadata, while retaining gold shop
  entries and migrating legacy ledger rows as gold.
- Duplicate cosmetic purchases remain no-op successes and do not create a
  second ledger row; failed purchases do not create history.
- Progression round-trip coverage now verifies the cosmetic ledger survives
  save/load with its diamond currency classification.

- Onboarding steps now carry explicit diegetic teaching signals (`landmark`,
  `enemy_reveal`, `telegraph`, `reward_drop`, `gather_node`, and
  `forge_preview`) and are contract-tested as non-blocking field guidance.

- The Hushling Matriarch now overrides generic boss copy with authored guidance
  for lash spacing, root denial, storm/crown vulnerability, and bramble enrage;
  phase-transition validation confirms the opening pattern is boss-specific.

- Expanded boss lifecycle timing coverage across all base and Matriarch attack
  kinds; every profile must expose positive anticipation, active, and recovery
  windows through the shared timing contract.

- [x] Completed the attached boss phase, lifecycle, and encounter-contract scene
  probes. They verify three escalating arena phases plus enrage guidance, safe
  zones, vulnerability/guard behavior, bounded arena transformation, phase
  transition activity records, reward-choice wiring, and reset after a failed
  attempt or death. Headless runs still report known spring-bone colinear-vector
  warnings and ObjectDB/RID cleanup diagnostics; all assertions return `PASS`.

- Extended full-scene equipment coverage to verify the swing trail has a bounded
  live attachment and the hero exposes the animator impact-frame handoff that
  coordinates weapon motion, VFX, SFX, and damage.

- Extended semantic UI states to the main-menu Continue action and satchel
  weapon/armor upgrades, including explicit unavailable reasons and tooltips
  while preserving the existing player-facing button copy.

- Added a shared versioned content-record migration primitive with normalized
  stable IDs and categories; gear migration now uses the same contract, with
  additive migration coverage for future items, skills, enemies, recipes, and
  quest/reward records.

- Added deterministic list migration for content registries: malformed records
  are ignored, IDs are normalized, duplicates are removed while preserving
  order, and every accepted record receives category/version metadata.

- Added explicit crafting action states and tooltips for affordability, success,
  and failure; failed crafts communicate that no resources were deducted while
  successful crafts confirm immediate persistence.

- Added semantic available/equipped/unavailable/restoring/purchased/failed
  states to checkpoint elemental attunement, with clear gold requirements and
  explicit no-deduction messaging on failed transactions.
