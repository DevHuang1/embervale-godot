# FIX-6 — TargetMarker: `Node` assigned to typed `Node3D` variable

**Severity:** 🟠 Low — causes a type-check failure in the target-marker test;
also causes a watchdog timeout because the assignment error leaves `_hero`
in an invalid state and the `_process` loop hangs trying to dereference it.

---

## File

`scripts/systems/target_marker.gd`

---

## Location

Approximately line 38 — inside the `ensure()` static factory, where
`_hero` is assigned.

---

## Root cause

The static factory does:

```gdscript
tm._hero = hero
```

`hero` is typed as `Node3D` in the function signature, so this looks fine.
However the test harness passes a bare `Node` (not `Node3D`) to exercise the
null-safety path, which triggers Godot's type enforcement on the typed property:

```gdscript
var _hero : Node3D = null    # typed — rejects plain Node
```

The assignment `tm._hero = hero` silently coerces in production if the actual
object IS a `Node3D`, but the test fails because `Node` is not a subclass of
`Node3D`.

Additionally inside `_process`, `_hero` is read without an `is_instance_valid`
guard. If `_hero` is `null` or the node has been freed, this produces cascading
errors that hang the watchdog.

---

## Exact fix

### 1 — Add a null/type guard in `_process`

At the start of `_process` in `target_marker.gd`:

```gdscript
# BEFORE
func _process(delta: float) -> void:
    _t += delta
    var gs := get_node_or_null("/root/GameState")
```

```gdscript
# AFTER
func _process(delta: float) -> void:
    if _hero == null or not is_instance_valid(_hero):
        return
    _t += delta
    var gs := get_node_or_null("/root/GameState")
```

### 2 — Cast in the factory to surface type errors clearly

```gdscript
# BEFORE (in ensure())
tm._hero = hero
```

```gdscript
# AFTER
tm._hero = hero as Node3D   # explicit cast — null if hero is not Node3D
if tm._hero == null:
    push_error("TargetMarker.ensure: hero must be a Node3D, got %s" % hero.get_class())
```

---

## Verification

1. Run the target-marker test suite (if present).
2. The test should complete without a watchdog timeout.
3. The `Node` to `Node3D` assignment error should not appear.
4. In live play, tapping an enemy and losing it (death/deselect) should not
   produce any cascading `_process` errors.
