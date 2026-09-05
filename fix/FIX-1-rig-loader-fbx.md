# FIX-1 — CharacterRigLoader: FBX ignored, `set_visual_root` crash

**Severity:** 🔴 High — hero model never mounts; every hit of the `EntityAnimator`
path produces a runtime error.

---

## File

`scripts/systems/character_rig_loader.gd`

---

## Location

| Issue | Line(s) |
|-------|---------|
| Only searches `.glb`, ignores `.fbx` | 31 |
| Calls `animator.set_visual_root(rig)` — method does not exist on `EntityAnimator` | 66 |

---

## Root cause

### Issue A — `.fbx` not searched

```gdscript
# line 31 — current
var path := MODEL_BASE_PATH + profile + ".glb"
```

`assets/models/hero.fbx` is present and loads fine in Godot, but the loader
only constructs a `.glb` path. Because `ResourceLoader.exists(path)` returns
`false`, the function returns `false` early and the procedural 53-mesh fallback
is displayed instead of the authored hero mesh.

### Issue B — `set_visual_root` does not exist

```gdscript
# line 66 — current
animator.set_visual_root(rig)
```

`EntityAnimator` (`scripts/entities/entity_animator.gd`) exposes `visual_root`
as a direct `@export var`, not via a setter method. The correct way to assign
it is:

```gdscript
animator.visual_root = rig
```

The non-existent method call produces:
```
Invalid call. Nonexistent function 'set_visual_root' in base 'Node3D (EntityAnimator)'.
```

---

## Exact fix

### A — try both `.glb` and `.fbx`

Replace the entire `try_if_wire` function body's first block (lines 31–35):

```gdscript
# BEFORE
var path := MODEL_BASE_PATH + profile + ".glb"
if not ResourceLoader.exists(path):
    return false
```

```gdscript
# AFTER
# Try .glb first, fall back to .fbx (Godot 4 imports both natively)
var path := MODEL_BASE_PATH + profile + ".glb"
if not ResourceLoader.exists(path):
    path = MODEL_BASE_PATH + profile + ".fbx"
if not ResourceLoader.exists(path):
    return false
```

Also update the cache key to strip the extension so `.glb` and `.fbx` share
the same registry slot. Replace the cache block (lines 33–37):

```gdscript
# BEFORE
if not _loaded.has(profile):
    var scene : PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
    _loaded[profile] = scene
var packed : PackedScene = _loaded.get(profile)
```

```gdscript
# AFTER
if not _loaded.has(profile):
    var scene : PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
    _loaded[profile] = scene   # key is the profile name, not the path
var packed : PackedScene = _loaded.get(profile)
```

*(No change needed to the cache key line — it already uses `profile` as key.)*

### B — fix the `set_visual_root` call

Replace line 66:

```gdscript
# BEFORE
animator.set_visual_root(rig)
```

```gdscript
# AFTER
animator.visual_root = rig
# Also suppress procedural tweens now that an authored rig is active:
# EntityAnimator auto-detects AnimationPlayer presence via visual_root setter.
```

Also update `preload_all()` at the bottom of the file to try both extensions:

```gdscript
# BEFORE (inside for loop)
var path := MODEL_BASE_PATH + p + ".glb"
if ResourceLoader.exists(path):
    _loaded[p] = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
else:
    _loaded[p] = null
```

```gdscript
# AFTER
var path := MODEL_BASE_PATH + p + ".glb"
if not ResourceLoader.exists(path):
    path = MODEL_BASE_PATH + p + ".fbx"
if ResourceLoader.exists(path):
    _loaded[p] = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
else:
    _loaded[p] = null
```

---

## Verification

1. Open the project in Godot 4.7.
2. Run the scene. The Output panel should show no
   `Nonexistent function 'set_visual_root'` error.
3. The hero in the grove should display the Knight mesh from `hero.fbx` instead
   of the procedural capsule/limb geometry.
4. If the character rig equipment test exists, run it — the three socket-binding
   failures noted in the original report should be resolved (sockets bind to
   real bone names from the FBX skeleton).
