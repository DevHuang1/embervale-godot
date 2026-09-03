"""Embervale Blender 5.x mobile asset validator and deterministic GLB exporter.

Run inside Blender. The scene is never modified; invalid production assets fail
before export so Godot does not receive silent scale, naming, or rig drift.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import bpy


LOD_PATTERN = re.compile(r"^[A-Za-z0-9_]+_LOD([0-2])$")
SOCKET_PREFIX = "SOCKET_"
REQUIRED_CHARACTER_SOCKETS = {
    "SOCKET_Hand_R",
    "SOCKET_Hand_L",
    "SOCKET_VFX_Chest",
    "SOCKET_VFX_Foot_L",
    "SOCKET_VFX_Foot_R",
}
REQUIRED_BOSS_ACTION_TOKENS = {
    "idle": ("idle",),
    "attack": ("attack", "slam"),
    "cast": ("cast", "rootprison"),
    "phase": ("buff", "phase"),
    "hit": ("hit",),
    "death": ("death",),
}
TRIANGLE_BUDGETS = {
    "character": {0: 45_000, 1: 22_000, 2: 9_000},
    "boss": {0: 65_000, 1: 32_000, 2: 13_000},
    "prop": {0: 18_000, 1: 8_000, 2: 3_000},
}


def parse_args() -> argparse.Namespace:
    raw = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", choices=TRIANGLE_BUDGETS, default="prop")
    parser.add_argument("--asset-name", default="")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args(raw)


def triangle_count(obj: bpy.types.Object) -> int:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    try:
        mesh.calc_loop_triangles()
        return len(mesh.loop_triangles)
    finally:
        evaluated.to_mesh_clear()


def validate(kind: str) -> list[str]:
    errors: list[str] = []
    scene = bpy.context.scene
    if scene.unit_settings.system != "METRIC":
        errors.append("Scene units must be METRIC.")
    if abs(scene.unit_settings.scale_length - 1.0) > 1e-6:
        errors.append("Scene unit scale must be 1.0 meter.")

    meshes = [obj for obj in scene.objects if obj.type == "MESH" and not obj.hide_render]
    if not meshes:
        errors.append("No renderable mesh objects found.")
    lods_found: set[int] = set()
    triangles_by_lod = {0: 0, 1: 0, 2: 0}
    for obj in meshes:
        match = LOD_PATTERN.match(obj.name)
        if not match:
            errors.append(f"Mesh '{obj.name}' must end in _LOD0, _LOD1, or _LOD2.")
            continue
        lod = int(match.group(1))
        lods_found.add(lod)
        if any(abs(value - 1.0) > 1e-4 for value in obj.scale):
            errors.append(f"Mesh '{obj.name}' has unapplied scale {tuple(obj.scale)}.")
        if any(abs(value) > 1e-4 for value in obj.rotation_euler):
            errors.append(f"Mesh '{obj.name}' has unapplied rotation.")
        triangles = triangle_count(obj)
        triangles_by_lod[lod] += triangles
        if kind == "boss" and obj.data.color_attributes.get("RealmMask") is None:
            errors.append(f"Boss mesh '{obj.name}' is missing the RealmMask vertex-color layer.")
    if 0 not in lods_found:
        errors.append("A production asset requires an authored _LOD0 mesh.")
    if kind in {"character", "boss"} and lods_found != {0, 1, 2}:
        errors.append(
            f"{kind.capitalize()} assets require complete LOD0/LOD1/LOD2 coverage; "
            f"found {sorted(lods_found)}."
        )
    for lod, triangles in triangles_by_lod.items():
        if lod not in lods_found:
            continue
        budget = TRIANGLE_BUDGETS[kind][lod]
        if triangles > budget:
            errors.append(
                f"Combined {kind} LOD{lod} has {triangles} triangles; cap is {budget}."
            )

    if kind in {"character", "boss"}:
        armatures = [obj for obj in scene.objects if obj.type == "ARMATURE"]
        if len(armatures) != 1:
            errors.append(f"{kind.capitalize()} assets require exactly one armature.")
        sockets = {obj.name for obj in scene.objects if obj.type == "EMPTY"}
        missing = sorted(REQUIRED_CHARACTER_SOCKETS - sockets)
        if missing:
            errors.append("Missing attachment empties: " + ", ".join(missing))
        for action in bpy.data.actions:
            if not action.name.startswith(("LOC_", "ATK_", "HIT_", "DODGE_", "DEATH_", "BOSS_")):
                errors.append(
                    f"Action '{action.name}' needs a gameplay prefix "
                    "(LOC/ATK/HIT/DODGE/DEATH/BOSS)."
                )
        if kind == "boss":
            action_names = [action.name.lower() for action in bpy.data.actions]
            for purpose, tokens in REQUIRED_BOSS_ACTION_TOKENS.items():
                if not any(any(token in action_name for token in tokens)
                           for action_name in action_names):
                    errors.append(
                        f"Boss asset is missing a {purpose} action "
                        f"(expected one of: {', '.join(tokens)})."
                    )
    return errors


def export_glb(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    result = bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_visible=True,
        export_animations=True,
        export_skins=True,
        export_morph=True,
        export_attributes=True,
        export_yup=True,
        export_apply=False,
    )
    if "FINISHED" not in result:
        raise RuntimeError(f"glTF exporter returned {result}")


def self_test() -> int:
    expected = {"character", "boss", "prop"}
    assert set(TRIANGLE_BUDGETS) == expected
    assert LOD_PATTERN.match("HeroBody_LOD0")
    assert not LOD_PATTERN.match("HeroBody")
    assert len(REQUIRED_CHARACTER_SOCKETS) == 5
    assert set(REQUIRED_BOSS_ACTION_TOKENS) == {
        "idle", "attack", "cast", "phase", "hit", "death"
    }
    print("EMBEREXPORT SELF-TEST PASSED")
    return 0


def main() -> int:
    args = parse_args()
    if args.self_test:
        return self_test()
    errors = validate(args.kind)
    if errors:
        print("EMBEREXPORT VALIDATION FAILED", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 2
    print(f"EMBEREXPORT VALIDATION PASSED ({args.kind})")
    if args.validate_only:
        return 0
    if args.output is None:
        print("--output is required unless --validate-only is used.", file=sys.stderr)
        return 2
    export_glb(args.output.resolve())
    print(f"EXPORTED {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
