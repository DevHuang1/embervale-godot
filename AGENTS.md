/# Embervale Agent Brief

This is a Godot 4 stylized dark-fantasy action RPG with Android as the primary
performance target. When asked to improve the project, work from the highest
priority unchecked task below that fits the user's request. Finish and verify a
coherent slice before opening another large refactor.

## Non-negotiable working rules

- Inspect `git status --short` before editing. Preserve all unrelated and
  uncommitted user work; never reset or broadly rewrite the worktree.
- Implement requested changes, not just an audit, unless the user asks only for
  analysis.
- Keep current saves and public gameplay/VFX call sites backward compatible, or
  add a tested migration.
- Keep gameplay timing, damage, collision, and telegraph readability identical
  across quality tiers. Tiers may reduce presentation cost only.
- Use typed GDScript for new or materially changed code. Treat parser errors,
  unexpected engine errors, and smoke-test script errors as failures.
- Give every recurring effect, light, projectile, body, tween, and notification
  a lifetime plus a hard cap, cleanup path, or pool.
- Never claim visual acceptance from the dummy renderer or device performance
  without a real renderer/device measurement.
- Do not copy protected art, UI, maps, names, lore, or exact designs from other
  RPGs. Use successful games only as quality references.

## Current baseline — build on it, do not redo it

- Seven seamless stylized-PBR surface families exist under
  `assets/textures/stylized/`, with deterministic normal/roughness generation.
- **Goal**: The current pursuit goal for this session. Updated via `/goal` command.
EOF
- Five realm terrain profiles bind stylized maps and have distinct palettes.
- Terrain detail is tiered: Low off, Medium single offset, High short POM march.
- `QualityScaler` owns VFX density, pool/trail caps, transient lights,
  distortion, fog, and material detail.
- `CombatFx` retains existing `spawn_*` interfaces, deterministic sprite FX,
  capped cleanup, and a protected non-blooming enemy-telegraph layer.
- Realm/material, VFX-budget, combat-feedback, ecosystem, quality, and UI smoke
  validations exist. Extend these rather than creating parallel harnesses.

## Active project backlog

### P0 — Polished vertical slice

- [ ] Make the full 20–30 minute route production-ready:
      Whispergrove onboarding → Bramblewood expedition → gathering → elite fight →
      boss → valuable loot → equipment/crafting upgrade → visible unlock.
- [ ] Repair any crash, soft lock, duplicate reward, stale scene reference,
      input failure, or save/load regression found along that route.
- [ ] Rebuild the first 15 minutes around playable teaching: movement,
      interaction, first readable fight, meaningful reward, upgrade, and a visible
      long-term goal. Avoid tutorial-modal overload.

### P1 — Combat and encounters

- [ ] Audit and tune input buffering, attack startup/active/recovery windows,
      dodge invulnerability, targeting, hit timing, stagger, recovery, and mobile
      responsiveness without casually changing damage balance.
- [ ] Give weapons distinct decisions and playstyles instead of only different
      numbers; centralize tunable combat data.
- [ ] Build encounters from complementary roles (attacker, defender, ranged,
      controller, support, disruptor) and cap simultaneous attackers, projectiles,
      hazards, corpses, and navigation work.
- [ ] Upgrade one boss end to end: readable patterns, fair hitboxes, clear
      vulnerability windows, phase escalation, reliable reset, and meaningful
      reward.
- [ ] Verify enemy telegraphs match their real collision and timing and remain
      visible beneath fog/friendly spectacle at every quality tier.

### P1 — Progression and player motivation

- [ ] Consolidate items, equipment, skills, recipes, loot tables, realm rewards,
      and balance formulas into a coherent data-driven model where current systems
      benefit.
- [ ] Make every upgrade show what changes, why it matters, and what it unlocks;
      remove meaningless micro-stat complexity and avoid currency bloat.
- [ ] Complete the item loop: acquire → understand → compare → equip/use/craft/
      salvage → visibly feel stronger.
- [ ] Make crafting transactional, prevent double activation, explain missing
      requirements, and test exact resource deduction/reward behavior.
- [ ] Make quests save-safe and reward exactly once across death, reload, and
      realm travel.

### P1 — Realm gameplay identity

- [ ] Give each realm exclusive enemies, resources, activities, landmarks,
      ambient audio, elite encounters, and a reason to return—not just a palette.
- [ ] Whispergrove: gentle teaching and exploration. Bramblewood: ambush and
      thorn pressure. Mistfen: visibility/status control. Heartwood: heat and elite
      pressure. Moonfen: water routes, magic threats, and elemental combinations.
- [ ] Improve navigation with compositional landmarks, readable paths, discovery
      states, and uncluttered map/objective guidance.

### P1 — Mobile UX and accessibility

- [ ] Audit portrait layouts, safe areas, touch targets, contextual actions,
      targeting, cooldowns, item comparison, map controls, and modal input capture.
- [ ] Centralize UI theme tokens and stop repeated menu/notification rebuilding
      or tween accumulation.
- [ ] Verify reduced motion, shake strength, flash intensity, text scaling,
      color-vision-safe telegraphs, audio categories, and haptic settings change
      actual runtime behavior and persist.

### P2 — Presentation

- [ ] Perform a synchronized audio pass for weapons, hits, footsteps, enemies,
      bosses, gathering, loot, UI, and realm ambience with bus/voice limits.
- [ ] Refine locomotion, turning, attack blending, hit reactions, weapon
      attachment, enemy anticipation, boss phases, and damage-event alignment.
- [ ] Centralize camera ownership; cap cumulative shake and prevent competing
      zoom/impulse systems.
- [ ] Run real-renderer Low/Medium/High captures for every realm plus light,
      heavy, elemental, boss, telegraph, and crowded-combat scenarios.

### P2 — Android performance and production readiness

- [ ] Profile a deterministic exploration/combat route on Android. Establish
      explicit budgets for draw calls, transparency, particles, trails, lights,
      shadows, enemies, projectiles, fog, reflections, physics, navigation, UI,
      audio voices, texture memory, and loading spikes.
- [ ] Optimize measured bottlenecks only, then repeat the same profile and
      report before/after evidence. An emulator cannot prove physical-device GPU or
      thermal acceptance.
- [ ] Version and round-trip test the save schema, migrations, corrupt-save
      recovery, settings persistence, inventory, equipment, quests, and realm.
- [ ] Improve startup/realm transitions without preloading the whole project;
      eliminate duplicate initialization and visible half-loaded states.

## Minimum verification

Choose commands proportional to the change, then run the affected suites:

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script tests/test_material_bindings.gd
godot --headless --path . --script tests/test_quality_scaler.gd
godot --headless --path . --script tests/test_realm_visuals.gd
godot --headless --path . --script tests/test_visual_vfx_budgets.gd
godot --headless --path . --script tests/test_vfx_ui_smoke.gd
godot --headless --path . --scene res://tests/skill_vfx_validation.tscn
godot --headless --path . --scene res://tests/impact_feedback_validation.tscn
godot --headless --path . --scene res://tests/realm_ecosystem_validation.tscn
```

Distinguish project failures from sandbox-only Godot settings, ADB permission,
certificate, or disconnected local MCP-plugin noise. Never label a suite passed
if it emitted an unexpected project script error.

## Task completion report

Report the player-facing outcome first, then important files changed, tests and
exact results, visual/device evidence actually collected, remaining risks, and
the next highest-value backlog item. Mark a checkbox complete only when the
feature and its relevant validation are genuinely complete.
