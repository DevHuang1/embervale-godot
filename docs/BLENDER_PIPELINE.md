# Embervale Blender-to-Godot Pipeline

Blender 5.2.1 LTS is available locally at `/Applications/Blender.app`. New hero,
enemy, boss, weapon, and landmark assets should pass the project exporter before
they enter Godot. Existing FBX assets remain supported while they are migrated;
new production exports use binary glTF (`.glb`).

Editable `.blend` sources live under `tools/blender/source/`, which is excluded
from Godot imports by `.gdignore`. Runtime builds receive only exporter-validated
GLBs under `assets/models/`; this avoids platform Blender dependencies and
accidental source-file imports in CI/headless editor runs.

## Scene contract

- Metric units at scale `1.0`; one Blender meter equals one Godot meter.
- Apply mesh rotation and scale before export. Preserve the armature rest pose.
- Render meshes end in `_LOD0`, `_LOD1`, or `_LOD2`.
- Character and boss files contain exactly one armature.
- Attachment empties use `SOCKET_Hand_R`, `SOCKET_Hand_L`,
  `SOCKET_VFX_Chest`, `SOCKET_VFX_Foot_L`, and `SOCKET_VFX_Foot_R`.
- Animation actions begin with `LOC_`, `ATK_`, `HIT_`, `DODGE_`, `DEATH_`, or
  `BOSS_`. Put anticipation, contact, and recovery into the authored clip;
  gameplay damage remains synchronized by Godot's impact event.
- LOD triangle ceilings are enforced by asset type. Transparent leaf cards,
  duplicate materials, and unapplied transforms should be resolved in Blender.

## Validate and export

Regenerate the editable Matriarch source deterministically:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python tools/blender/build_matriarch.py -- \
  --output tools/blender/source/matriarch_authored.blend
```

Render its fixed LOD0 art-review frame with
`tools/blender/render_matriarch_preview.py`; this checks silhouette and material
read in Blender but does not replace an in-game Godot renderer capture.

From the project root, validate the currently open `.blend` without exporting:

```sh
/Applications/Blender.app/Contents/MacOS/Blender character.blend --background \
  --python tools/blender/embervale_export.py -- \
  --kind character --validate-only
```

Export a validated character:

```sh
/Applications/Blender.app/Contents/MacOS/Blender character.blend --background \
  --python tools/blender/embervale_export.py -- \
  --kind character --asset-name hero \
  --output assets/models/characters/hero.glb
```

Use `--kind boss` for the Matriarch and `--kind prop` for weapons, landmarks,
and destructibles. Never overwrite the existing fallback FBX until the GLB has
passed Godot import, socket, animation, collision, and mobile LOD validation.

## First authored animation set

The highest-value Blender deliverable is one complete hero weapon set:

1. `LOC_Idle`, `LOC_Walk`, `LOC_Run`, `DODGE_Forward`.
2. `ATK_Blunt_01`, `ATK_Slash_01`, `ATK_Magic_01`.
3. One charged heavy for each family, aligned to the commitment data in
   `WeaponCombatProfiles`.
4. `HIT_Light_Front`, `HIT_Heavy_Front`, `DEATH_Forward`.
5. Matriarch clips only after the hero set imports and plays correctly.

Record the actual contact frame for every attack. Godot timing, hitboxes, audio,
VFX, and camera feedback must all resolve on that same frame; visual acceptance
requires a real-renderer capture, not the dummy renderer.
