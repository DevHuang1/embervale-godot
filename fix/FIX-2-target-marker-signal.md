# FIX-2 — TargetMarker: `mark_locked` signal type mismatch

**Severity:** 🔴 High — the visual lock-on effect never fires; because most
skills require a marked enemy, the player has no confirmation that targeting
or skill activation worked.

---

## File

`scripts/systems/target_marker.gd`

---

## Location

Line 165 — the `_on_mark_locked` slot connected to `GameState.mark_locked`.

---

## Root cause

`GameState` emits:

```gdscript
signal mark_locked(target: Node3D)
```

But `target_marker.gd` defines the connected slot as:

```gdscript
# line 165 — current (wrong parameter type)
func _on_mark_locked(_flare: float) -> void:
```

Godot's signal system does a type-safe argument check when it delivers the
signal. Because `GameState` sends a `Node3D` and the slot declares `float`,
every emission of `mark_locked` produces:

```
Cannot convert argument 1 from Object to float.
```

The handler body never executes, so the ring brightness spike that gives the
player visual feedback on lock-on is permanently suppressed.

---

## Exact fix

### Change the slot signature

```gdscript
# BEFORE
func _on_mark_locked(_flare: float) -> void:
    # Spike ring brightness on lock-on
    if _ring_mat != null:
        var tw := create_tween()
        tw.tween_property(_ring_mat, "emission_energy_multiplier", 5.5, 0.08)
        tw.tween_property(_ring_mat, "emission_energy_multiplier", 2.2, 0.35)
```

```gdscript
# AFTER
func _on_mark_locked(target: Node3D) -> void:
    # Immediately snap the ring to the new target position
    if target != null and is_instance_valid(target):
        _target = target
    # Spike ring brightness on lock-on
    if _ring_mat != null:
        var tw := create_tween()
        tw.tween_property(_ring_mat, "emission_energy_multiplier", 5.5, 0.08)
        tw.tween_property(_ring_mat, "emission_energy_multiplier", 2.2, 0.35)
```

The change does two things:
1. Fixes the type mismatch (parameter is now `Node3D`, matching the signal).
2. Immediately assigns `_target` from the signal argument so the ring snaps to
   the correct enemy without waiting for the next `_process` poll.

---

## Verification

1. Run the grove scene.
2. Tap an enemy.
3. The amber lock-on ring should appear above the enemy and pulse.
4. No `Cannot convert argument 1 from Object to float` error in Output.
5. The skill buttons in the HUD should become active (they check for a valid
   target through `GameState.enemy_selected`).
