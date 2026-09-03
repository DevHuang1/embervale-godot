"""Build and export Embervale's realm boss variants from the authored Matriarch rig.

The builder keeps the shared readable boss proportions, three LODs, rig, sockets,
and synchronized action set while varying silhouette, materials, accents, and
realm identity. Run with Blender in background mode:
  blender --background --python build_boss_variants.py
"""
from __future__ import annotations

import importlib.util
import math
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent / "build_matriarch.py"
OUT = ROOT / "assets" / "models" / "boss_variants"
BLEND_OUT = ROOT / "tools" / "blender" / "source" / "boss_variants"

VARIANTS = [
    ("whispergrove", "rootwarden", (0.12, 0.28, 0.16, 1), (0.28, 0.78, 0.42, 1), (0.72, 0.96, 0.62, 1), "roots"),
    ("whispergrove", "dewseer", (0.10, 0.22, 0.18, 1), (0.34, 0.92, 0.72, 1), (0.68, 0.95, 0.84, 1), "crown"),
    ("bramblewood", "thornregent", (0.20, 0.08, 0.05, 1), (0.78, 0.18, 0.06, 1), (0.98, 0.46, 0.16, 1), "thorns"),
    ("bramblewood", "briarwidow", (0.24, 0.07, 0.11, 1), (0.94, 0.24, 0.14, 1), (1.0, 0.55, 0.28, 1), "petals"),
    ("mistfen", "veilmother", (0.07, 0.14, 0.20, 1), (0.22, 0.66, 0.78, 1), (0.42, 0.92, 1.0, 1), "veil"),
    ("mistfen", "drownedsage", (0.08, 0.10, 0.19, 1), (0.34, 0.32, 0.86, 1), (0.68, 0.56, 1.0, 1), "halo"),
    ("heartwood", "cinderhart", (0.22, 0.055, 0.025, 1), (1.0, 0.18, 0.025, 1), (1.0, 0.72, 0.16, 1), "antlers"),
    ("heartwood", "ashcolossus", (0.12, 0.065, 0.05, 1), (0.86, 0.30, 0.06, 1), (1.0, 0.42, 0.10, 1), "plates"),
    ("moonfen", "tideoracle", (0.035, 0.10, 0.18, 1), (0.10, 0.60, 0.94, 1), (0.48, 0.94, 1.0, 1), "crown"),
    ("moonfen", "lunarleviathan", (0.08, 0.035, 0.18, 1), (0.46, 0.18, 0.92, 1), (0.82, 0.56, 1.0, 1), "fins"),
]


def load_builder():
    spec = importlib.util.spec_from_file_location("matriarch_builder", SOURCE)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def add_accent(builder, kind: str, mats: dict, rig):
    dark = mats["dark"]
    glow = mats["glow"]
    if kind == "roots":
        for i in range(6):
            angle = math.tau * i / 6.0
            builder.cone(f"RootWardenVine{i:02d}_LOD0", (math.cos(angle) * 0.92, math.sin(angle) * 0.60, 1.0), 0.12, 1.5, 6, (0.2, math.cos(angle) * 0.2, angle), dark, rig, "Root", (0.5, 0.0, 0.0, 1.0))
    elif kind == "crown":
        for i in range(5):
            angle = math.tau * i / 5.0
            builder.cone(f"CrownShard{i:02d}_LOD0", (math.cos(angle) * 0.66, math.sin(angle) * 0.44, 3.56), 0.16, 1.05, 6, (math.sin(angle) * 0.22, math.cos(angle) * 0.22, -angle), glow, rig, "Head", (0.0, 0.0, 1.0, 1.0))
    elif kind == "thorns":
        for side in (-1, 1):
            builder.cone(f"ShoulderThorn{'L' if side < 0 else 'R'}_LOD0", (1.34 * side, 0.0, 2.45), 0.20, 1.2, 6, (0.0, math.radians(68) * side, 0.0), dark, rig, f"Arm_{'L' if side < 0 else 'R'}")
    elif kind == "petals":
        for i in range(8):
            angle = math.tau * i / 8.0
            builder.sphere(f"Petal{i:02d}_LOD0", (math.cos(angle) * 0.78, math.sin(angle) * 0.56, 3.18), (0.24, 0.10, 0.38), 8, 5, glow, rig, "Head", (0.0, 0.0, 1.0, 1.0))
    elif kind == "veil":
        for side in (-1, 1):
            builder.cone(f"VeilFin{'L' if side < 0 else 'R'}_LOD0", (0.72 * side, 0.12, 2.68), 0.18, 1.8, 6, (math.radians(90), math.radians(24) * side, 0), glow, rig, "Head")
    elif kind == "halo":
        bpy.ops.mesh.primitive_torus_add(major_radius=0.96, minor_radius=0.075, major_segments=16, minor_segments=6, location=(0, 0.10, 3.28), rotation=(math.pi / 2, 0, 0))
        builder.finish_mesh(bpy.context.object, "SageHalo_LOD0", glow, rig, "Head", (0.0, 0.0, 1.0, 1.0))
    elif kind == "antlers":
        for side in (-1, 1):
            builder.cone(f"CinderBranch{'L' if side < 0 else 'R'}_LOD0", (1.12 * side, 0.12, 3.28), 0.24, 2.25, 7, (0, math.radians(32) * side, math.radians(-12) * side), dark, rig, "Head")
            builder.cone(f"CinderTip{'L' if side < 0 else 'R'}_LOD0", (1.45 * side, 0.12, 4.02), 0.14, 1.25, 6, (0, math.radians(58) * side, 0), glow, rig, "Head", (0.0, 0.0, 1.0, 1.0))
    elif kind == "plates":
        for i in range(4):
            builder.sphere(f"AshPlate{i:02d}_LOD0", (0, -0.72, 1.0 + i * 0.38), (0.58 - i * 0.07, 0.08, 0.18), 8, 5, dark, rig, "Torso")
    elif kind == "fins":
        for side in (-1, 1):
            builder.cone(f"LeviathanFin{'L' if side < 0 else 'R'}_LOD0", (1.18 * side, 0.18, 2.18), 0.22, 2.0, 6, (0, math.radians(72) * side, 0), glow, rig, f"Arm_{'L' if side < 0 else 'R'}")


def build_variant(builder, realm: str, variant: str, body_c, emissive_c, eye_c, accent: str):
    builder.reset_scene()
    mats = {
        "bark": builder.material(f"MAT_{realm}_{variant}_Body", body_c, 0.88),
        "dark": builder.material(f"MAT_{realm}_{variant}_Thorn", tuple(max(0.01, c * 0.42) for c in body_c[:3]) + (1,), 0.92),
        "moss": builder.material(f"MAT_{realm}_{variant}_Accent", tuple(min(1.0, c * 0.72 + 0.08) for c in emissive_c[:3]) + (1,), 0.78),
        "glow": builder.material(f"MAT_{realm}_{variant}_Glow", emissive_c, 0.36, emission=emissive_c),
        "heart": builder.material(f"MAT_{realm}_{variant}_Core", tuple(min(1.0, c * 0.7) for c in emissive_c[:3]) + (1,), 0.34, emission=emissive_c),
        "eye": builder.material(f"MAT_{realm}_{variant}_Eyes", eye_c, 0.25, emission=eye_c),
    }
    rig = builder.create_rig()
    for lod in range(3):
        builder.build_lod(lod, rig, mats["bark"], mats["dark"], mats["moss"], mats["heart"], mats["eye"])
    add_accent(builder, accent, mats, rig)
    for name, bone, location in [
        ("SOCKET_Hand_R", "Claw_R", (0, 0, 0.45)),
        ("SOCKET_Hand_L", "Claw_L", (0, 0, 0.45)),
        ("SOCKET_VFX_Chest", "Torso", (0, -0.85, 1.28)),
        ("SOCKET_VFX_Foot_L", "Root", (-0.65, 0, 0.08)),
        ("SOCKET_VFX_Foot_R", "Root", (0.65, 0, 0.08)),
    ]:
        builder.add_socket(rig, name, bone, location)
    builder.build_actions(rig)
    bpy.context.scene["embervale_asset_kind"] = "boss"
    bpy.context.scene["embervale_asset_version"] = 2
    bpy.context.scene["embervale_realm"] = realm
    bpy.context.scene["embervale_variant"] = variant
    blend_path = BLEND_OUT / f"boss_{realm}_{variant}.blend"
    glb_path = OUT / f"boss_{realm}_{variant}.glb"
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    glb_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path.resolve()))
    bpy.ops.export_scene.gltf(filepath=str(glb_path.resolve()), export_format="GLB", use_visible=True, export_animations=True, export_skins=True, export_morph=True, export_attributes=True, export_yup=True, export_apply=False)
    print(f"BUILT {realm}/{variant}: {glb_path}")


def main():
    builder = load_builder()
    for args in VARIANTS:
        build_variant(builder, *args)


if __name__ == "__main__":
    main()
