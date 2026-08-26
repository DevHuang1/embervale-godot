# Fix: enemy fighting animation keeps playing when not attacking

## Root cause (verified)

`EntityAnimator._play_pounce()` (`scripts/entities/entity_animator.gd:1095`) is the
only attack variant whose tween never resets `anim_state`. Every other variant
ends with:

```gdscript
_attack_tween.chain().tween_callback(func():
    if anim_state == AnimState.ATTACK:
        anim_state = AnimState.IDLE)
```

`_play_pounce()` (the BLOB-mode attack) has no such callback. Hushling lunge
(`scripts/entities/hushling.gd:230`) and counter-windup (`hushling.gd:464`) both
call `animator.trigger_attack()`, which routes BLOB mode to `_play_pounce()`.
So after any Hushling/MoonfenFenling attacks once, its animator stays in
`ATTACK` forever.

Symptom surface: authored rigs ARE mounted (`assets/models/hushling.fbx`,
`fenling.fbx` via `CharacterRigLoader.try_if_wire`). `AnimTreeBridge._process`
(`scripts/systems/anim_tree_bridge.gd:109`) polls state every frame and
re-plays the attack clip endlessly while `anim_state == ATTACK` — creatures keep
playing their fighting animation while orbiting/walking. Hero (BIPED) and bosses
(BRUTE, `_play_slam`) already reset correctly; only BLOB leaks.

## Changes

1. **Primary fix** — `scripts/entities/entity_animator.gd`, end of `_play_pounce()`:
   append the standard completion callback used by every other variant:

   ```gdscript
   _attack_tween.chain().tween_callback(func():
       if anim_state == AnimState.ATTACK:
           anim_state = AnimState.IDLE)
   ```

2. **Hardening (same bug class, tiny)** — the degenerate early-returns inside
   `_play_heavy`, `_play_buff`, `_play_hurl`, `_play_sky`, `_play_spin`,
   `_play_cast`, the three swing variants, `_play_slam`, and `_play_pounce`
   (`if not arm_x ...: attack_impact.emit(); return`) leave `anim_state`
   stuck at ATTACK because `trigger_attack` sets it before dispatch. Add
   `anim_state = AnimState.IDLE` next to each `attack_impact.emit()` /
   `_emit_impact()` early-return so a missing-limb fallback can never wedge
   the state machine.

3. **Regression test** — new `tests/test_anim_state_reset.gd` (SceneTree script,
   same pattern as `tests/test_combat_recovery.gd`):
   - instantiate `res://scenes/entities/hushling.tscn`, add to tree;
   - assert `animator.anim_state == ATTACK` right after `trigger_attack()`;
   - wait ~0.8 s (pounce tween ≈ 0.38 s), assert back to `IDLE`.
   - Repeat a re-trigger mid-pounce to confirm kill/restart also settles to IDLE.
   - Same asserts for a BIPED stand-in if cheap (hero scene requires more setup;
     optional).

## Edge cases covered by the guarded callback

- Hit mid-pounce: `trigger_hit` sets HIT; final callback's `== ATTACK` guard
  skips; hit tween restores IDLE (unchanged semantics).
- Death mid-pounce: DEAD wins; bridge picks death cue.
- Rapid re-trigger: old tween killed, fresh callback still resets.

## Out of scope

- `AnimTreeBridge` replaying one-shot clips during legitimate long recoveries
  (existing behavior, unrelated).
- Any gameplay/AI changes in hushling.gd.

## Validation

- `godot --headless --path . --script tests/test_anim_state_reset.gd` → passes.
- `godot --headless --path . --script tests/test_combat_recovery.gd` → still passes.
- Manual: run game, provoke one hushling lunge + one counter-windup; confirm the
  creature returns to hop/orbit visuals and its rig resumes walk/idle clips
  instead of repeating the claw/attack animation.
