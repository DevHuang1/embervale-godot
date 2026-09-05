# FIX-4 — Hushling: invalid `result.gear` dictionary access

**Severity:** 🟡 Medium — crashes whenever a hushling dies and the loot
code tries to access a `gear` key that doesn't exist in the result dict.

---

## File

`scripts/entities/hushling.gd`

---

## Location

Line 1436 (approximately) — inside the death/loot callback, likely inside
`_spawn_rewards()` or a connected function.

---

## Root cause

The code does a direct dict key access like:

```gdscript
var gear = result.gear       # or result["gear"]
```

`result` is a Dictionary returned by `GameState.perform_auto_strike()` or a
similar helper. That dict does not always contain a `"gear"` key — it only
appears when a weapon proc triggers. A bare `.gear` access on a Dictionary
without a `.get()` guard produces:

```
Invalid get index 'gear' on base 'Dictionary'.
```

---

## Exact fix

Find the line containing `result.gear` (or `result["gear"]`) in `hushling.gd`
around line 1436. Replace the bare access with a guarded `.get()` call:

```gdscript
# BEFORE (exact line varies — search for `result.gear` or `result["gear"]`)
var gear = result.gear
```

```gdscript
# AFTER
var gear = result.get("gear", {})
```

If the gear value is then used in a conditional, the empty dict `{}` will
safely evaluate as falsy or empty:

```gdscript
# Example — wrap downstream usage
if not gear.is_empty():
    # ... use gear data
```

---

## Verification

1. Run the grove scene.
2. Kill a hushling (any archetype).
3. No `Invalid get index 'gear'` error in the Output panel.
4. Loot/XP still grants correctly.
