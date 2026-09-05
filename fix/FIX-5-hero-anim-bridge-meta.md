# FIX-5 — Hero: `get_meta("anim_bridge")` called without `has_meta` guard

**Severity:** 🟡 Medium — repeated runtime errors every physics frame during
combat; degrades performance and fills the Output panel with noise.

---

## File

`scripts/entities/hero.gd`

---

## Location

Two call sites, approximately lines 1183 and 1427.

---

## Root cause

The hero combat code calls:

```gdscript
get_meta("anim_bridge")
```

`"anim_bridge"` is a meta key set by the authored rig bridge when a `.glb`
or `.fbx` model is mounted. If the model hasn't mounted yet (e.g. on the first
frame, or when running with the procedural fallback), the meta key is absent
and Godot raises:

```
Meta "anim_bridge" not found on Node.
```

Because this appears in `_physics_process` or an attack callback, it fires
repeatedly.

---

## Exact fix

At each call site (~lines 1183 and 1427), wrap with `has_meta`:

```gdscript
# BEFORE (repeated at both locations)
var bridge = get_meta("anim_bridge")
bridge.do_something()
```

```gdscript
# AFTER
if has_meta("anim_bridge"):
    var bridge = get_meta("anim_bridge")
    bridge.do_something()
```

If the code pattern is:

```gdscript
var bridge = get_meta("anim_bridge") if has_meta("anim_bridge") else null
if bridge:
    bridge.do_something()
```

…that is also acceptable.

### Finding the exact lines

Search `hero.gd` for `get_meta("anim_bridge"` — there should be exactly two
matches. Apply the guard to both.

---

## Verification

1. Run the grove scene without a mounted hero model (procedural fallback active).
2. Enter combat with a hushling.
3. No `Meta "anim_bridge" not found` errors appear in Output during the fight.
4. Combat still functions (auto-strikes fire, damage applies).
5. Repeat with `hero.fbx` mounted — still no errors.
