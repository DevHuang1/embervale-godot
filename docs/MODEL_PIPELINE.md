# Authored Character Model Pipeline

This project ships with **runtime-assembled procedural figures** (capsules,
spheres, cylinders) that are fully playable — plus a **drop-in pipeline** for
replacing them with proper authored, skinned, rigged 3D models. You do not
need to touch gameplay code or combat logic; the loader mounts a model file
over the ghost body and hides the primitives.

## What already exists (in-engine, no art required)

| Area | File |
|---|---|
| Procedural rig (Hero) | `scenes/entities/hero.tscn` + `scripts/entities/hero.gd` |
| Procedural rig (Hushling/Fenling) | `scenes/entities/hushling.tscn`, `moonfen_fenling.tscn` |
| Animation state machine | `scripts/entities/entity_animator.gd` |
| Hitbox/SFX/VFX sync | `attack_impact`, `footfall`, `anim_event` signals |
| Per-entity tuning | `scripts/entities/character_model_data.gd` |
| Material/skin system | `assets/materials/*.tres`, `assets/shaders/entity_body.gdshader` |
| Gear/relic mounts | `AttachmentSocket` |

## Drop-in loader

`scripts/systems/character_rig_loader.gd` mounts an optional rigged model at
`_ready` time. Place a file at:

```
assets/models/hero.glb              # player
assets/models/hushling.glb          # bramble enemy
assets/models/boss_matriarch.glb    # boss
```

(`.gltf` also works.) While the file is absent the loader is a **silent
no-op** and the game uses the procedural figures. Drop the file in and restart —
no other wiring required.

The imported rig is parented at `Visual/AuthoredRig`. Procedural ghost meshes
are hidden; the lantern, sockets, swing-trail and ember-trail stay mounted.
If the rig contains an `AnimationPlayer` / `AnimationTree`, a
`scripts/systems/anim_tree_bridge.gd` node (`AnimBridge`) is created so
gameplay cues can drive the clips.

## Authoring requirements

Build with Blender (recommended) exporting **glTF 2.0 binary (.glb)**:

- **Bones**: `Visual` root with children `Body`, `Head`, `ArmL`, `ArmR`,
  `LegL`, `LegR`, optional `Forearm`, `Foot`, `Torso`. Animator-compatible:
  arms/legs pivot at their origin, feet separate.
- **Sockets** (named empties under the rig): `HandSocketL`, `HandSocketR`,
  `BackSocket`, `Lantern` — gear/relics mount here.
- **Clips** (AnimationPlayer animations), named so the bridge can match:
  `idle`, `walk`, `run`, `light_1`, `light_2`, `light_3`, `heavy`, `cast`,
  `buff`, `hit`, `dodge`, `death`.
- **In place:** root-motion should be **baked into the bones**, not the root —
  the gameplay `CharacterBody3D` stays authoritative for position/collision.
- **Budget:** ~5k–15k triangles per figure; keep `Skeleton3D` naming stable.

### Blender → Godot

1. Model + bones + `Armature`/`Skeleton`. Unity naming (`Normal`,
   `Material`) should be stripped before export.
2. `File ▸ Export ▸ glTF 2.0` — `Format: GLB`, `Import Normals` on,
   `Bone Nomincl` off.
3. Drop the `.glb` into `assets/models/`.

## Driving clips from gameplay (optional)

When a rig supplies clips, route the gameplay cue into the bridge:

```gdscript
var bridge = get_meta("anim_bridge") as AnimTreeBridge
if bridge and bridge.play_cue("heavy"):
    pass   # imported clip plays
else:
    animator.trigger_attack("heavy")   # procedural fallback
```

The existing `attack_impact` / `footfall` / `anim_event` signals mean hitboxes
and SFX keep syncing regardless of which system renders the pose.