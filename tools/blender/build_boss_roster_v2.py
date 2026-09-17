"""Build Embervale's brand-new authored boss roster.

This is intentionally separate from the legacy Matriarch/variant builder.  It
creates eight distinct, mobile-conscious stylized bosses from reusable
component helpers while keeping a common armature and socket contract.

Run from the project root with Blender 5.x:
  blender --background --python tools/blender/build_boss_roster_v2.py
  blender --background --python tools/blender/build_boss_roster_v2.py -- \
      --boss moonfen_lunar_leviathan
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

try:
    # Keep the headless-safe export and the Blender source on the same
    # creature-specific skill-pose table. The import is stdlib-only and does
    # not execute the fallback builder.
    from build_boss_roster_v2_fallback import _skill_motion
except ImportError:
    _skill_motion = None


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "models" / "bosses_v2"
BLEND_OUT = ROOT / "tools" / "blender" / "source" / "bosses_v2"
TEXTURE_DIR = ROOT / "assets" / "textures" / "bosses_v2"
ATLAS_PATH = TEXTURE_DIR / "boss_v2_atlas.png"
ORM_PATH = TEXTURE_DIR / "boss_v2_orm.png"
NORMAL_PATH = TEXTURE_DIR / "boss_v2_normal.png"


BOSSES = {
    "whispergrove_root_harrow": {
        "realm": "whispergrove", "style": "root_harrow",
        "body": (0.08, 0.19, 0.11, 1), "armor": (0.18, 0.34, 0.18, 1),
        "accent": (0.22, 0.84, 0.30, 1), "glow": (0.72, 1.0, 0.38, 1),
        "skills": ["root_sword_combo", "seed_burst"],
    },
    "bramblewood_thorn_regent": {
        "realm": "bramblewood", "style": "thorn_regent",
        "body": (0.10, 0.12, 0.06, 1), "armor": (0.25, 0.20, 0.08, 1),
        "accent": (0.80, 0.28, 0.06, 1), "glow": (1.0, 0.60, 0.14, 1),
        "skills": ["regent_cleave", "root_crash"],
    },
    "bramblewood_briar_widow": {
        "realm": "bramblewood", "style": "briar_widow",
        "body": (0.16, 0.045, 0.12, 1), "armor": (0.28, 0.08, 0.20, 1),
        "accent": (0.86, 0.10, 0.34, 1), "glow": (0.66, 0.38, 1.0, 1),
        "skills": ["needle_salvo", "briar_mine", "widow_bloom"],
    },
    "mistfen_fogmaw": {
        "realm": "mistfen", "style": "fogmaw",
        "body": (0.035, 0.12, 0.16, 1), "armor": (0.08, 0.24, 0.27, 1),
        "accent": (0.12, 0.68, 0.78, 1), "glow": (0.48, 0.94, 1.0, 1),
        "skills": ["fog_roll", "burrow_burst"],
    },
    "heartwood_cinderhart": {
        "realm": "heartwood", "style": "cinderhart",
        "body": (0.12, 0.025, 0.012, 1), "armor": (0.28, 0.065, 0.018, 1),
        "accent": (0.95, 0.16, 0.015, 1), "glow": (1.0, 0.66, 0.08, 1),
        "skills": ["furnace_pound", "magma_mortar"],
    },
    "heartwood_ash_bellower": {
        "realm": "heartwood", "style": "ash_bellower",
        "body": (0.10, 0.055, 0.035, 1), "armor": (0.24, 0.12, 0.055, 1),
        "accent": (0.90, 0.24, 0.035, 1), "glow": (1.0, 0.78, 0.20, 1),
        "skills": ["ash_mortar", "flare_wall", "bell_regen"],
    },
    "moonfen_tide_oracle": {
        "realm": "moonfen", "style": "tide_oracle",
        "body": (0.025, 0.06, 0.18, 1), "armor": (0.06, 0.16, 0.34, 1),
        "accent": (0.10, 0.66, 0.92, 1), "glow": (0.56, 0.76, 1.0, 1),
        "skills": ["tide_bolt", "moon_tide_ring", "oracle_split"],
    },
    "moonfen_lunar_leviathan": {
        "realm": "moonfen", "style": "lunar_leviathan",
        "body": (0.045, 0.025, 0.16, 1), "armor": (0.10, 0.07, 0.30, 1),
        "accent": (0.42, 0.18, 0.86, 1), "glow": (0.86, 0.42, 1.0, 1),
        "skills": ["lunar_breath", "crescent_sweep", "orbit_barrage"],
    },
}


def parse_args() -> argparse.Namespace:
    raw = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--boss", choices=sorted(BOSSES), default="")
    return parser.parse_args(raw)


def reset_scene() -> None:
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures,
                       bpy.data.materials, bpy.data.actions):
        for block in list(datablocks):
            datablocks.remove(block)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 30


def material(name: str, color: tuple[float, float, float, float],
             roughness: float, metallic: float = 0.0,
             tile: int = 0,
             emission: tuple[float, float, float, float] | None = None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat["boss_v2_tile"] = tile
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    atlas = bpy.data.images.load(str(ATLAS_PATH), check_existing=True)
    orm = bpy.data.images.load(str(ORM_PATH), check_existing=True)
    normal = bpy.data.images.load(str(NORMAL_PATH), check_existing=True)
    atlas_tex = nodes.new("ShaderNodeTexImage")
    atlas_tex.name = "BossV2_Atlas"
    atlas_tex.image = atlas
    color_factor = nodes.new("ShaderNodeRGB")
    color_factor.name = "BossV2_RealmColor"
    color_factor.outputs[0].default_value = color
    base_mix = nodes.new("ShaderNodeMixRGB")
    base_mix.blend_type = "MULTIPLY"
    base_mix.inputs[0].default_value = 1.0
    links.new(atlas_tex.outputs["Color"], base_mix.inputs[1])
    links.new(color_factor.outputs[0], base_mix.inputs[2])
    links.new(base_mix.outputs[0], bsdf.inputs["Base Color"])
    orm_tex = nodes.new("ShaderNodeTexImage")
    orm_tex.name = "BossV2_ORM"
    orm_tex.image = orm
    orm_tex.image.colorspace_settings.name = "Non-Color"
    orm_split = nodes.new("ShaderNodeSeparateRGB")
    links.new(orm_tex.outputs["Color"], orm_split.inputs[0])
    links.new(orm_split.outputs["G"], bsdf.inputs["Roughness"])
    links.new(orm_split.outputs["B"], bsdf.inputs["Metallic"])
    # Tangent-space relief shares the atlas height field, so plate seams and
    # bark grain read the same in the editable source and the headless GLBs.
    normal_tex = nodes.new("ShaderNodeTexImage")
    normal_tex.name = "BossV2_Normal"
    normal_tex.image = normal
    normal_tex.image.colorspace_settings.name = "Non-Color"
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.name = "BossV2_NormalMap"
    links.new(normal_tex.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    if emission is not None:
        # The glow band is a dim base with bright veins; reuse the atlas as the
        # emissive mask so glow surfaces emit along their own detail.
        links.new(base_mix.outputs[0], bsdf.inputs["Emission Color"])
        if bsdf.inputs.get("Emission Strength") is not None:
            bsdf.inputs["Emission Strength"].default_value = 1.5
    return mat


def create_rig() -> bpy.types.Object:
    data = bpy.data.armatures.new("BossRosterV2_Rig")
    rig = bpy.data.objects.new("BossRosterV2_Rig", data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    def bone(name: str, head, tail, parent: str | None = None):
        created = data.edit_bones.new(name)
        created.head, created.tail = head, tail
        if parent:
            created.parent = data.edit_bones[parent]
        return created

    bone("Root", (0, 0, 0), (0, 0, 0.35))
    bone("Pelvis", (0, 0, 0.3), (0, 0, 1.0), "Root")
    bone("Torso", (0, 0, 0.85), (0, 0, 2.35), "Pelvis")
    bone("Chest", (0, 0, 1.8), (0, 0, 2.75), "Torso")
    bone("Neck", (0, 0, 2.62), (0, 0, 3.0), "Chest")
    bone("Head", (0, 0, 2.92), (0, 0, 3.75), "Neck")
    for side, suffix in ((-1, "L"), (1, "R")):
        bone(f"Arm_{suffix}", (0, 0, 2.45), (1.25 * side, 0, 2.15), "Chest")
        bone(f"Forearm_{suffix}", (1.25 * side, 0, 2.15),
             (1.90 * side, -0.05, 1.62), f"Arm_{suffix}")
        bone(f"Hand_{suffix}", (1.90 * side, -0.05, 1.62),
             (2.18 * side, -0.12, 1.42), f"Forearm_{suffix}")
        bone(f"Weapon_{suffix}", (2.18 * side, -0.12, 1.42),
             (2.18 * side, -0.12, 0.82), f"Hand_{suffix}")
        bone(f"Leg_{suffix}", (0.52 * side, 0, 0.86),
             (0.58 * side, 0, 0.28), "Pelvis")
        bone(f"Shin_{suffix}", (0.58 * side, 0, 0.28),
             (0.62 * side, -0.05, -0.25), f"Leg_{suffix}")
        bone(f"Foot_{suffix}", (0.62 * side, -0.05, -0.25),
             (0.62 * side, -0.42, -0.28), f"Shin_{suffix}")
        bone(f"Wing_{suffix}", (0.75 * side, 0.12, 2.18),
             (1.60 * side, 0.30, 2.65), "Chest")
        for index in range(1, 4):
            parent = f"Wing_{suffix}" if index == 1 else f"Wing_{suffix}_{index - 1}"
            bone(f"Wing_{suffix}_{index}",
                 (1.60 * side + (index - 1) * 0.34 * side, 0.30,
                  2.65 + (index - 1) * 0.10),
                 (1.60 * side + index * 0.34 * side, 0.30,
                  2.65 + index * 0.10), parent)
        for index in range(1, 4):
            parent = "Pelvis" if index == 1 else f"Tail_{index - 1}"
            bone(f"Tail_{index}",
                 (0, 0.25 + (index - 1) * 0.34, 0.62 - (index - 1) * 0.12),
                 (0, 0.25 + index * 0.34, 0.62 - index * 0.12), parent)

    # Secondary articulation used by the creature-first V2 motion language.
    # These bones are lightweight rigid-detail controls, not extra gameplay
    # bodies, so they add visible life without adding physics cost.
    bone("Wing_L_4", (-2.62, 0.30, 2.95), (-2.96, 0.30, 3.05), "Wing_L_3")
    bone("Wing_R_4", (2.62, 0.30, 2.95), (2.96, 0.30, 3.05), "Wing_R_3")
    bone("Tail_4", (0, 1.27, 0.26), (0, 1.61, 0.18), "Tail_3")
    bone("Tail_5", (0, 1.61, 0.18), (0, 1.95, 0.12), "Tail_4")
    bone("Jaw", (0, -0.18, 2.25), (0, -0.28, 2.55), "Head")
    bone("Core", (0, -0.40, 1.90), (0, -0.50, 2.18), "Chest")
    bone("BellClapper", (0, -0.12, 1.15), (0, -0.12, 1.62), "Chest")
    bone("Mandible_L", (-0.35, -0.10, 2.10), (-0.52, -0.18, 2.30), "Head")
    bone("Mandible_R", (0.35, -0.10, 2.10), (0.52, -0.18, 2.30), "Head")
    bone("RootBranch_L", (-1.60, -0.02, 1.40), (-1.90, -0.03, 1.00), "Forearm_L")
    bone("RootBranch_L_2", (-1.90, -0.03, 1.00), (-2.10, -0.04, 0.72), "RootBranch_L")
    bone("RootBranch_R", (1.60, -0.02, 1.40), (1.90, -0.03, 1.00), "Forearm_R")
    bone("RootBranch_R_2", (1.90, -0.03, 1.00), (2.10, -0.04, 0.72), "RootBranch_R")
    bone("Fin_L", (-1.10, 0.18, 1.70), (-1.46, 0.18, 1.42), "Chest")
    bone("Fin_R", (1.10, 0.18, 1.70), (1.46, 0.18, 1.42), "Chest")

    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.select_set(False)
    return rig


def realm_mask(obj: bpy.types.Object, values: tuple[float, float, float, float]) -> None:
    attr = obj.data.color_attributes.new(
        name="RealmMask", type="BYTE_COLOR", domain="CORNER")
    for entry in attr.data:
        entry.color = values


def skin_rigid(obj: bpy.types.Object, rig: bpy.types.Object, bone: str) -> None:
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new(name="BossRosterV2Rig", type="ARMATURE")
    modifier.object = rig
    world_matrix = obj.matrix_world.copy()
    obj.parent = rig
    obj.matrix_world = world_matrix


def finish_mesh(obj: bpy.types.Object, name: str, mat, rig: bpy.types.Object,
                bone: str, lod: int, mask=(0.0, 0.0, 0.0, 1.0)) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    obj.data.materials.append(mat)
    realm_mask(obj, mask)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # Keep organic surfaces smooth while preserving deliberate hard-surface
    # breaks on jaws, plates, feet, and weapons. Bevelled plates still catch a
    # clean highlight without the faceted fallback look.
    hard_surface = any(token in name for token in
                       ("Jaw", "Plate", "Sword", "Crescent", "Rib", "Foot", "Bulwark"))
    if not hard_surface:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    uv_layer = obj.data.uv_layers.active
    if uv_layer is not None:
        tile = int(mat.get("boss_v2_tile", 0))
        for uv_entry in uv_layer.data:
            uv_entry.uv.x = tile / 5.0 + 0.02 + uv_entry.uv.x * 0.16
            uv_entry.uv.y = 0.02 + uv_entry.uv.y * 0.96
    skin_rigid(obj, rig, bone)
    obj["embervale_lod"] = lod
    obj["embervale_bone"] = bone
    obj.select_set(False)
    return obj


def uv_sphere(name: str, location, scale, mat, rig, bone: str, lod: int,
              mask=(0.0, 0.0, 0.0, 1.0)):
    segments = (32, 20, 12)[lod]
    rings = (20, 14, 8)[lod]
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.scale = scale
    return finish_mesh(obj, name, mat, rig, bone, lod, mask)


def ico_sphere(name: str, location, scale, mat, rig, bone: str, lod: int,
               mask=(0.0, 0.0, 0.0, 1.0)):
    subdivisions = (2, 1, 1)[lod]
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions, radius=1.0, location=location)
    obj = bpy.context.object
    obj.scale = scale
    return finish_mesh(obj, name, mat, rig, bone, lod, mask)


def cone(name: str, location, radius: float, depth: float, rotation,
         mat, rig, bone: str, lod: int,
         mask=(0.0, 0.0, 0.0, 1.0)):
    vertices = (12, 8, 5)[lod]
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices, radius1=radius, radius2=radius * 0.08,
        depth=depth, location=location, rotation=rotation)
    return finish_mesh(bpy.context.object, name, mat, rig, bone, lod, mask)


def cylinder(name: str, location, radius: float, depth: float,
             rotation, mat, rig, bone: str, lod: int,
             mask=(0.0, 0.0, 0.0, 1.0)):
    vertices = (16, 10, 6)[lod]
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth,
        location=location, rotation=rotation)
    return finish_mesh(bpy.context.object, name, mat, rig, bone, lod, mask)


def box(name: str, location, scale, rotation, mat, rig, bone: str, lod: int,
        bevel: float = 0.0, mask=(0.0, 0.0, 0.0, 1.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.scale = scale
    if bevel > 0.0 and lod < 2:
        modifier = obj.modifiers.new(name="ArmorEdge", type="BEVEL")
        modifier.width = bevel if lod == 0 else bevel * 0.7
        modifier.segments = 2 if lod == 0 else 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return finish_mesh(obj, name, mat, rig, bone, lod, mask)


def torus(name: str, location, major: float, minor: float, rotation,
          mat, rig, bone: str, lod: int,
          mask=(0.0, 0.0, 0.0, 1.0)):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major, minor_radius=minor,
        major_segments=(24, 16, 10)[lod], minor_segments=(8, 6, 4)[lod],
        location=location, rotation=rotation)
    return finish_mesh(bpy.context.object, name, mat, rig, bone, lod, mask)


def add_socket(rig: bpy.types.Object, name: str, bone: str, location) -> None:
    empty = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(empty)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.18
    empty.parent = rig
    empty.parent_type = "BONE"
    empty.parent_bone = bone
    empty.location = location


def clear_pose(rig: bpy.types.Object) -> None:
    for bone in rig.pose.bones:
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def make_action(rig: bpy.types.Object, name: str, length: int,
                poses: dict[int, dict[str, tuple[float, float, float]]],
                locations: dict[int, dict[str, tuple[float, float, float]]] | None = None):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action
    locations = locations or {}
    for frame, pose in poses.items():
        clear_pose(rig)
        for bone_name, rotation in pose.items():
            if bone_name in rig.pose.bones:
                rig.pose.bones[bone_name].rotation_euler = tuple(
                    math.radians(value) for value in rotation)
        for bone_name, location in locations.get(frame, {}).items():
            if bone_name in rig.pose.bones:
                rig.pose.bones[bone_name].location = location
        for bone in rig.pose.bones:
            bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
            bone.keyframe_insert("location", frame=frame, group=bone.name)
    action.frame_range = (1, length)
    rig.animation_data.action = None


def build_actions(rig: bpy.types.Object, skills: list[str], style: str) -> None:
    arm_wave = 5.0 if style not in {"cinderhart", "thorn_regent"} else 2.5
    make_action(rig, "LOC_Idle", 60, {
        1: {"Torso": (0, 0, -2), "Chest": (0, 0, 2), "Head": (0, 0, 3),
            "Arm_L": (0, -arm_wave, -4), "Arm_R": (0, arm_wave, 4),
            "Tail_1": (0, -4, 0), "Tail_2": (0, 5, 0)},
        30: {"Torso": (2, 0, 2), "Chest": (-2, 0, -2), "Head": (-2, 0, -3),
             "Arm_L": (0, arm_wave, 3), "Arm_R": (0, -arm_wave, -3),
             "Tail_1": (0, 5, 0), "Tail_2": (0, -6, 0)},
        60: {"Torso": (0, 0, -2), "Chest": (0, 0, 2), "Head": (0, 0, 3),
             "Arm_L": (0, -arm_wave, -4), "Arm_R": (0, arm_wave, 4),
             "Tail_1": (0, -4, 0), "Tail_2": (0, 5, 0)},
    })
    make_action(rig, "LOC_Move", 30, {
        1: {"Torso": (-4, 0, 0), "Arm_L": (16, 0, -8), "Arm_R": (-16, 0, 8),
            "Leg_L": (18, 0, 0), "Leg_R": (-18, 0, 0), "Tail_1": (0, -8, 0)},
        15: {"Torso": (4, 0, 0), "Arm_L": (-16, 0, 8), "Arm_R": (16, 0, -8),
             "Leg_L": (-18, 0, 0), "Leg_R": (18, 0, 0), "Tail_1": (0, 8, 0)},
        30: {"Torso": (-4, 0, 0), "Arm_L": (16, 0, -8), "Arm_R": (-16, 0, 8),
             "Leg_L": (18, 0, 0), "Leg_R": (-18, 0, 0), "Tail_1": (0, -8, 0)},
    })
    make_action(rig, "DODGE_Roll", 24, {
        1: {"Torso": (0, 0, -12), "Head": (0, 0, -18),
            "Arm_L": (0, 0, -32), "Arm_R": (0, 0, 32)},
        12: {"Torso": (0, 0, 20), "Head": (0, 0, 28),
             "Arm_L": (0, 0, 70), "Arm_R": (0, 0, -70)},
        24: {},
    })
    make_action(rig, "HIT_Heavy", 18, {
        1: {"Torso": (0, 0, -10), "Head": (0, 0, -8), "Arm_L": (0, -18, 0),
            "Arm_R": (0, 18, 0)},
        8: {"Torso": (18, 0, 0), "Head": (-12, 0, 0)},
        18: {},
    })
    make_action(rig, "DEATH_Forward", 60, {
        1: {}, 24: {"Torso": (28, 0, 0), "Head": (18, 0, 0),
                    "Arm_L": (0, -35, -70), "Arm_R": (0, 35, 70)},
        60: {"Torso": (86, 0, 0), "Head": (35, 0, 0),
             "Arm_L": (0, -60, -90), "Arm_R": (0, 60, 90)},
    })
    make_action(rig, "BOSS_PhaseShift", 45, {
        1: {"Torso": (0, 0, -6), "Head": (0, 0, 8), "Arm_L": (0, 0, -20),
            "Arm_R": (0, 0, 20), "Wing_L": (0, 0, -12), "Wing_R": (0, 0, 12)},
        22: {"Torso": (-12, 0, 0), "Head": (0, 0, -12), "Arm_L": (0, -35, -56),
             "Arm_R": (0, 35, 56), "Wing_L": (0, 0, -38), "Wing_R": (0, 0, 38)},
        45: {},
    })
    for index, skill in enumerate(skills):
        sign = -1 if index % 2 == 0 else 1
        base_poses = {
            1: {"Torso": (-8, 0, sign * 4), "Head": (0, 0, -sign * 5),
                "Arm_L": (0, sign * 12, -sign * 18),
                "Arm_R": (0, -sign * 12, sign * 18),
                "Forearm_L": (0, sign * 10, -sign * 20),
                "Forearm_R": (0, -sign * 10, sign * 20),
                "Tail_1": (0, sign * 14, 0)},
            14: {"Torso": (-24, 0, 0), "Head": (0, 0, sign * 14),
                 "Arm_L": (0, sign * 35, -sign * 70),
                 "Arm_R": (0, -sign * 35, sign * 70),
                 "Forearm_L": (0, sign * 20, -sign * 42),
                 "Forearm_R": (0, -sign * 20, sign * 42),
                 "Wing_L": (0, 0, -sign * 24), "Wing_R": (0, 0, sign * 24)},
            24: {"Torso": (22, 0, 0), "Head": (0, 0, -sign * 8),
                 "Arm_L": (0, -sign * 24, sign * 58),
                 "Arm_R": (0, sign * 24, -sign * 58),
                 "Tail_1": (0, -sign * 18, 0)},
            42: {},
        }
        # The headless builder is the deterministic source for secondary
        # creature joints. Merging its table here keeps a future Blender
        # rebuild visually aligned with the checked-in fallback GLBs.
        if _skill_motion is not None:
            raw_motion = _skill_motion(style, skill, sign)
            frame_map = {0: 1, 12: 14, 24: 24, 42: 42}
            for raw_frame, pose in raw_motion.items():
                frame = frame_map.get(raw_frame, raw_frame)
                base_poses.setdefault(frame, {}).update(pose)
        make_action(rig, f"BOSS_{skill}", 42, base_poses)


def add_common_body(rig: bpy.types.Object, mats: dict, style: str, lod: int) -> None:
    # V2 bodies are creature-first. The skeleton/socket contract is shared,
    # but the old visible humanoid shell is intentionally skipped for every
    # canonical style so Blender exports match the headless fallback assets.
    if style in {"root_harrow", "thorn_regent", "briar_widow", "fogmaw",
                 "cinderhart", "ash_bellower", "tide_oracle", "lunar_leviathan"}:
        add_primary_silhouette(rig, mats, style, lod)
        return
    tag = f"LOD{lod}"
    body = mats["body"]
    armor = mats["armor"]
    accent = mats["accent"]
    glow = mats["glow"]
    dark = mats["dark"]
    mask_body = (0.18, 0.04, 0.0, 1.0)
    mask_accent = (0.58, 0.14, 0.0, 1.0)
    uv_sphere(f"V2_Torso_{tag}", (0, 0, 1.62), (1.18, 0.78, 1.32),
              body, rig, "Torso", lod, mask_body)
    uv_sphere(f"V2_ChestPlate_{tag}", (0, -0.58, 1.92), (0.92, 0.16, 0.74),
              armor, rig, "Chest", lod, mask_accent)
    uv_sphere(f"V2_Core_{tag}", (0, -0.78, 1.82), (0.28, 0.10, 0.36),
              glow, rig, "Chest", lod, (0.0, 0.0, 1.0, 1.0))
    # Close-up armor filigree keeps the authored LODs in the requested density
    # band while each piece still reuses one of five atlas materials.
    ornament_count = (16, 16, 4)[lod]
    for index in range(ornament_count):
        angle = math.tau * index / max(1, ornament_count)
        uv_sphere(f"V2_ChestOrnament_{index:02d}_{tag}",
                  (math.cos(angle) * 0.72, -0.68 + math.sin(angle) * 0.08,
                   1.18 + (index % 5) * 0.28),
                  (0.11, 0.055, 0.15), armor, rig, "Chest", lod,
                  mask_accent)
    collar_count = (10, 8, 3)[lod]
    for index in range(collar_count):
        torus(f"V2_ChestCollar_{index:02d}_{tag}",
              (0, -0.12, 1.22 + index * 0.12),
              0.58 + (index % 2) * 0.06, 0.018 + (index % 3) * 0.006,
              (math.radians(90), 0, 0), accent, rig, "Chest", lod,
              mask_accent)
    uv_sphere(f"V2_Head_{tag}", (0, -0.02, 2.82), (0.78, 0.62, 0.72),
              armor, rig, "Head", lod, mask_accent)
    box(f"V2_Jaw_{tag}", (0, -0.58, 2.54), (0.92, 0.20, 0.20),
        (0, 0, 0), dark, rig, "Head", lod, 0.06, mask_body)
    for side, suffix in ((-1, "L"), (1, "R")):
        uv_sphere(f"V2_Eye_{suffix}_{tag}", (0.30 * side, -0.60, 2.94),
                  (0.14, 0.055, 0.075), glow, rig, "Head", lod,
                  (0.0, 0.0, 1.0, 1.0))
        box(f"V2_Shoulder_{suffix}_{tag}", (1.02 * side, 0.0, 2.23),
            (0.58, 0.46, 0.42), (0, 0, math.radians(12 * side)),
            armor, rig, f"Arm_{suffix}", lod, 0.08, mask_accent)
        cylinder(f"V2_UpperArm_{suffix}_{tag}", (1.28 * side, 0.0, 1.90),
                 0.30, 1.10, (0, math.radians(90), 0), body, rig,
                 f"Arm_{suffix}", lod, mask_body)
        cylinder(f"V2_Forearm_{suffix}_{tag}", (1.80 * side, -0.04, 1.46),
                 0.26, 0.92, (0, math.radians(68), 0), armor, rig,
                 f"Forearm_{suffix}", lod, mask_accent)
        uv_sphere(f"V2_Hand_{suffix}_{tag}", (2.12 * side, -0.10, 1.20),
                  (0.30, 0.24, 0.30), accent, rig, f"Hand_{suffix}", lod,
                  mask_accent)
        cylinder(f"V2_Thigh_{suffix}_{tag}", (0.48 * side, 0.0, 0.72),
                 0.34, 0.90, (0, 0, 0), body, rig, f"Leg_{suffix}", lod,
                 mask_body)
        cylinder(f"V2_Shin_{suffix}_{tag}", (0.55 * side, -0.04, 0.22),
                 0.25, 0.74, (0, 0, 0), armor, rig, f"Shin_{suffix}", lod,
                 mask_accent)
        box(f"V2_Foot_{suffix}_{tag}", (0.55 * side, -0.28, -0.18),
            (0.48, 0.68, 0.28), (0, 0, 0), dark, rig, f"Foot_{suffix}", lod,
            0.05, mask_body)
    # Layered torso seams make close-up renders read as constructed armor while
    # still using a small set of shared materials.
    panel_count = (12, 7, 3)[lod]
    for index in range(panel_count):
        angle = math.tau * index / max(1, panel_count)
        radius = 0.88 if index % 2 == 0 else 0.72
        x, y = math.cos(angle) * radius, math.sin(angle) * radius * 0.56
        box(f"V2_Rib_{index:02d}_{tag}", (x, y - 0.38, 1.18 + (index % 3) * 0.30),
            (0.16, 0.07, 0.28), (0, angle, angle * 0.35), dark, rig,
            "Torso", lod, 0.035, mask_body)
    if style not in {"tide_oracle", "lunar_leviathan"}:
        for index in range((8, 5, 3)[lod]):
            angle = math.tau * index / max(1, (8, 5, 3)[lod])
            cone(f"V2_CrownSpine_{index:02d}_{tag}",
                 (math.cos(angle) * 0.54, math.sin(angle) * 0.42, 3.36),
                 0.13 if lod == 0 else 0.16, 0.70 + (index % 2) * 0.22,
                 (math.sin(angle) * 0.24, math.cos(angle) * 0.22, -angle),
                 accent if index % 3 else dark, rig, "Head", lod, mask_accent)
    add_primary_silhouette(rig, mats, style, lod)


def add_primary_silhouette(rig: bpy.types.Object, mats: dict, style: str, lod: int) -> None:
    """Build a different primary mass for every boss identity.

    Shared bones, sockets, atlas tiles, and LOD rules are retained, but the
    visible silhouette is intentionally structural: abdomen, fenwheel, bell,
    robe, furnace, or wing mass rather than eight recolored humanoids.
    """
    armor = mats["armor"]
    body = mats["body"]
    accent = mats["accent"]
    glow = mats["glow"]
    dark = mats["dark"]
    if style == "root_harrow":
        uv_sphere("V2_RootMantle", (0, 0.34, 1.62), (1.02, 0.38, 1.54),
                  body, rig, "Torso", lod)
        for side in (-1, 1):
            cone("V2_RootBladeArm", (side * 1.12, 0.22, 1.82), 0.22, 2.10,
                 (0, math.radians(18 * side), math.radians(8 * side)), armor,
                 rig, "Arm_L" if side < 0 else "Arm_R", lod)
            cone("V2_RootBranch", (side * 1.70, 0.08, 1.18), 0.13, 1.16,
                 (0, math.radians(72 * side), 0), accent, rig,
                 "RootBranch_L" if side < 0 else "RootBranch_R", lod)
            cone("V2_RootBranchTip", (side * 1.92, 0.02, 0.78), 0.09, 0.82,
                 (0, math.radians(76 * side), 0), dark, rig,
                 "RootBranch_L_2" if side < 0 else "RootBranch_R_2", lod)
    elif style == "thorn_regent":
        box("V2_RegentBulwark", (0, 0.34, 1.70), (2.78, 0.62, 2.62),
            (0, 0, 0), armor, rig, "Torso", lod, 0.10)
        uv_sphere("V2_RegentHelm", (0, 0.24, 2.82), (1.02, 0.72, 0.72),
                  dark, rig, "Head", lod)
        for side in (-1, 1):
            box("V2_RegentShoulder", (side * 1.42, 0.18, 2.18),
                (0.82, 0.62, 0.48), (0, 0, math.radians(16 * side)), armor,
                rig, "Arm_L" if side < 0 else "Arm_R", lod, 0.08)
    elif style == "briar_widow":
        uv_sphere("V2_WidowAbdomen", (0, 0.48, 1.30), (1.48, 1.02, 1.16),
                  dark, rig, "Pelvis", lod)
        uv_sphere("V2_WidowThorax", (0, -0.08, 2.02), (0.92, 0.72, 0.76),
                  body, rig, "Torso", lod)
        for side in (-1, 1):
            for index in range((4, 3, 2)[lod]):
                cone("V2_WidowLeg", (side * (1.20 + index * 0.20),
                     0.18 + index * 0.08, 1.78 - index * 0.38), 0.13,
                     1.80 - index * 0.12,
                     (0, math.radians(68 * side), math.radians(14 * side)),
                     accent if index == 0 else dark, rig,
                     "Leg_L" if side < 0 else "Leg_R", lod)
    elif style == "fogmaw":
        uv_sphere("V2_FogmawMass", (0, 0.18, 1.36), (1.58, 1.02, 1.08),
                  body, rig, "Torso", lod)
        torus("V2_FogmawJaw", (0, -0.72, 1.42), 1.34, 0.24,
              (math.radians(90), 0, 0), accent, rig, "Jaw", lod)
        box("V2_FogmawJawPlate", (0, -0.94, 1.42), (1.34, 0.18, 0.66),
            (0, 0, 0), dark, rig, "Jaw", lod, 0.08)
        for side in (-1, 1):
            cone("V2_FogmawFin", (side * 1.42, 0.20, 1.22), 0.20, 1.65,
                 (0, math.radians(76 * side), 0), glow, rig,
                 "Fin_L" if side < 0 else "Fin_R", lod)
    elif style == "cinderhart":
        uv_sphere("V2_FurnaceMass", (0, 0.04, 1.62), (1.46, 0.98, 1.62),
                  body, rig, "Torso", lod)
        cylinder("V2_FurnaceCore", (0, -0.86, 1.70), 0.78, 0.34,
                 (math.radians(90), 0, 0), glow, rig, "Core", lod)
        for side in (-1, 1):
            uv_sphere("V2_MagmaFist", (side * 2.34, -0.04, 1.22),
                      (0.62, 0.52, 0.64), glow, rig,
                      "Hand_L" if side < 0 else "Hand_R", lod)
    elif style == "ash_bellower":
        cone("V2_AshBellBody", (0, 0.02, 1.58), 1.28, 2.44,
             (0, 0, 0), armor, rig, "Torso", lod)
        torus("V2_AshBellSkirt", (0, 0.02, 0.40), 1.18, 0.16,
             (0, 0, 0), glow, rig, "Pelvis", lod)
        cylinder("V2_AshBellCap", (0, 0.02, 2.62), 0.54, 0.52,
                 (0, 0, 0), dark, rig, "BellClapper", lod)
        cylinder("V2_AshBellClapper", (0, -0.18, 1.18), 0.14, 0.78,
                 (0, 0, 0), glow, rig, "BellClapper", lod)
    elif style == "tide_oracle":
        # Fish-like oracle body: wide aquatic mass, blunt snout, tail and
        # steering fins. It intentionally has no humanoid robe/leg silhouette.
        uv_sphere("V2_TideFishBody", (0, 0.16, 2.02), (1.36, 1.18, 0.86),
                  body, rig, "Torso", lod)
        uv_sphere("V2_TideSnout", (0, -0.82, 2.08), (0.92, 0.62, 0.66),
                  armor, rig, "Head", lod)
        box("V2_TideMouth", (0, -1.30, 1.96), (1.20, 0.24, 0.28),
            (0, 0, 0), dark, rig, "Jaw", lod, 0.07)
        for side in (-1, 1):
            uv_sphere("V2_TideEye", (side * 0.52, -1.28, 2.30),
                      (0.16, 0.06, 0.12), glow, rig, "Head", lod)
            cone("V2_TideFin", (side * 1.16, 0.14, 2.16), 0.28, 1.86,
                 (0, math.radians(82 * side), math.radians(12 * side)),
                 accent, rig, "Fin_L" if side < 0 else "Fin_R", lod)
        cone("V2_TideTailA", (0, 1.22, 2.02), 0.62, 1.70,
             (math.radians(-90), 0, 0), body, rig, "Tail_1", lod)
        cone("V2_TideTailB", (0, 2.04, 2.02), 0.46, 1.28,
             (math.radians(-90), 0, 0), accent, rig, "Tail_2", lod)
        cone("V2_TideTailC", (0, 2.72, 2.02), 0.30, 0.86,
             (math.radians(-90), 0, 0), glow, rig, "Tail_3", lod)
        uv_sphere("V2_TideCore", (0, -0.86, 2.08), (0.44, 0.22, 0.62),
                  glow, rig, "Core", lod)
    elif style == "lunar_leviathan":
        uv_sphere("V2_LeviathanMass", (0, 0.16, 1.68), (1.52, 0.78, 1.16),
                  body, rig, "Torso", lod)
        uv_sphere("V2_LeviathanNeck", (0, -0.44, 2.30), (0.96, 0.78, 0.94),
                  body, rig, "Chest", lod)
        uv_sphere("V2_LeviathanHead", (0, -0.92, 2.86), (0.88, 0.62, 0.66),
                  dark, rig, "Head", lod)
        box("V2_LeviathanJaw", (0, -1.42, 2.68), (1.20, 0.28, 0.34),
            (0, 0, 0), dark, rig, "Jaw", lod, 0.08)
        for side in (-1, 1):
            box("V2_LeviathanWing", (side * 1.58, 0.34, 2.48),
                (0.24, 0.34, 3.54),
                (0, math.radians(18 * side), math.radians(12 * side)),
                accent, rig, "Wing_L" if side < 0 else "Wing_R", lod, 0.06)
            box("V2_LeviathanWingTip", (side * 2.48, 0.42, 3.04),
                (0.12, 0.16, 1.62),
                (0, math.radians(34 * side), math.radians(12 * side)),
                glow, rig, f"Wing_{'L' if side < 0 else 'R'}_3", lod, 0.04)
            cone("V2_LeviathanTailFin", (side * 0.64, 0.46, 0.72), 0.20,
                 1.80, (math.radians(70), math.radians(24 * side), 0), glow,
                 rig, "Tail_1", lod)
        for index in range((8, 5, 3)[lod]):
            bone = f"Tail_{min(index + 1, 5)}"
            uv_sphere("V2_LeviathanTail", (0, 0.88 + index * 0.44,
                      1.54 - index * 0.18),
                      (0.62 - index * 0.07, 0.42 - index * 0.04,
                       0.46 - index * 0.04), body, rig, bone, lod)
    add_creature_surface_details(rig, mats, style, lod)


def add_creature_surface_details(rig: bpy.types.Object, mats: dict, style: str, lod: int) -> None:
    """Layer identity-specific scales, bark knots, plates, or bell segments."""
    count = (24, 32, 8)[lod]
    body, armor, accent, glow = mats["body"], mats["armor"], mats["accent"], mats["glow"]
    for index in range(count):
        angle = math.tau * index / max(1, count)
        if style == "root_harrow":
            location = (math.cos(angle) * 0.72, -0.40 + math.sin(angle) * 0.34,
                        0.52 + (index % 8) * 0.29)
            scale, mat, bone = (0.18, 0.10, 0.24), armor, "Torso"
        elif style == "thorn_regent":
            location = (math.cos(angle) * 1.22, -0.52 + math.sin(angle) * 0.30,
                        0.74 + (index % 6) * 0.34)
            scale, mat, bone = (0.22, 0.10, 0.30), armor, "Torso"
        elif style == "briar_widow":
            location = (math.cos(angle) * 1.20, 0.22 + math.sin(angle) * 0.74,
                        0.80 + (index % 5) * 0.24)
            scale, mat, bone = (0.20, 0.13, 0.17), accent, "Pelvis"
        elif style == "fogmaw":
            location = (math.cos(angle) * 1.40, -0.46, 1.38 + math.sin(angle) * 1.02)
            scale, mat, bone = (0.14, 0.12, 0.20), glow, "Torso"
        elif style == "cinderhart":
            location = (math.cos(angle) * 1.02, -0.70 + math.sin(angle) * 0.28,
                        0.70 + (index % 6) * 0.34)
            scale, mat, bone = (0.22, 0.10, 0.30), armor, "Torso"
        elif style == "ash_bellower":
            location = (math.cos(angle) * 0.90, -0.12 + math.sin(angle) * 0.42,
                        0.92 + (index % 6) * 0.28)
            scale, mat, bone = (0.16, 0.10, 0.34), armor, "Torso"
        elif style == "tide_oracle":
            location = (math.cos(angle) * 0.98, -0.12 + math.sin(angle) * 0.78,
                        1.56 + (index % 5) * 0.23)
            scale, mat, bone = (0.16, 0.12, 0.12), accent, "Torso"
        else:
            location = (math.cos(angle) * 1.02, 0.06 + math.sin(angle) * 0.48,
                        1.12 + (index % 7) * 0.26)
            scale, mat, bone = (0.20, 0.13, 0.16), accent, "Torso"
        uv_sphere(f"V2_CreatureDetail_{style}_{index:02d}_LOD{lod}", location,
                  scale, mat, rig, bone, lod)


def add_identity_details(rig: bpy.types.Object, mats: dict, style: str, lod: int) -> None:
    tag = f"LOD{lod}"
    armor, accent, glow, dark = mats["armor"], mats["accent"], mats["glow"], mats["dark"]
    if style == "root_harrow":
        count = (20, 12, 6)[lod]
        for index in range(count):
            angle = math.tau * index / count
            cone(f"V2_RootBlade_{index:02d}_{tag}",
                 (math.cos(angle) * 1.18, math.sin(angle) * 0.72, 0.46 + (index % 4) * 0.16),
                 0.12, 1.20 + (index % 3) * 0.20,
                 (math.sin(angle) * 0.34, math.cos(angle) * 0.28, -angle),
                 dark if index % 3 else accent, rig, "Root", lod)
        for side, suffix in ((-1, "L"), (1, "R")):
            cone(f"V2_RootWeapon_{suffix}_{tag}", (2.22 * side, -0.12, 0.62),
                 0.18, 1.55, (0, math.radians(22 * side), 0), glow, rig,
                 f"Weapon_{suffix}", lod, (0.55, 0.16, 0.0, 1.0))
    elif style == "thorn_regent":
        for index in range((24, 14, 7)[lod]):
            side = -1 if index % 2 == 0 else 1
            z = 0.92 + (index % 8) * 0.28
            box(f"V2_RegentPlate_{index:02d}_{tag}",
                (side * (0.76 + (index % 3) * 0.11), -0.44, z),
                (0.28, 0.12, 0.22 + (index % 3) * 0.04),
                (0, side * 0.22, side * 0.12), armor, rig, "Torso", lod, 0.06)
        for index in range((12, 8, 4)[lod]):
            angle = math.tau * index / max(1, (12, 8, 4)[lod])
            cone(f"V2_RegentCrown_{index:02d}_{tag}",
                 (math.cos(angle) * 0.70, math.sin(angle) * 0.46, 3.40),
                 0.18, 1.05, (math.sin(angle) * 0.25, math.cos(angle) * 0.24, -angle),
                 glow if index % 3 == 0 else dark, rig, "Head", lod)
        for side, suffix in ((-1, "L"), (1, "R")):
            box(f"V2_Greatsword_{suffix}_{tag}", (2.24 * side, -0.12, 0.52),
                (0.20, 0.16, 1.55), (0, math.radians(12 * side), 0),
                glow, rig, f"Weapon_{suffix}", lod, 0.08)
            cone(f"V2_GreatswordTip_{suffix}_{tag}", (2.24 * side, -0.12, -0.62),
                 0.20, 0.65, (0, 0, 0), glow, rig, f"Weapon_{suffix}", lod)
    elif style == "briar_widow":
        for side, suffix in ((-1, "L"), (1, "R")):
            for index in range((4, 3, 2)[lod]):
                z = 1.95 - index * 0.38
                cone(f"V2_SpiderLeg_{suffix}_{index}_{tag}",
                     (side * (1.00 + index * 0.18), 0.10 + index * 0.08, z),
                     0.12, 1.45 - index * 0.10,
                     (0, math.radians(62 * side), math.radians(18 * side)),
                     dark, rig, "Leg_L" if side < 0 else "Leg_R", lod)
        for index in range((18, 10, 5)[lod]):
            angle = math.tau * index / max(1, (18, 10, 5)[lod])
            cone(f"V2_Needle_{index:02d}_{tag}",
                 (math.cos(angle) * 0.84, -0.60 + math.sin(angle) * 0.30, 2.10),
                 0.055, 0.72, (math.sin(angle), 0, math.cos(angle)),
                 accent if index % 2 else glow, rig, "Head", lod)
        torus(f"V2_WebHalo_{tag}", (0, 0.28, 2.42), 1.05, 0.035,
              (math.radians(90), 0, 0), glow, rig, "Chest", lod)
    elif style == "fogmaw":
        for index in range((16, 10, 5)[lod]):
            angle = math.tau * index / max(1, (16, 10, 5)[lod])
            torus(f"V2_JawRing_{index:02d}_{tag}",
                  (0, -0.46, 2.58 + (index % 3) * 0.12),
                  0.62 + (index % 2) * 0.10, 0.045,
                  (math.radians(90), angle * 0.12, angle), armor, rig, "Jaw", lod)
        for side, suffix in ((-1, "L"), (1, "R")):
            for index in range((5, 3, 2)[lod]):
                cone(f"V2_FogFin_{suffix}_{index}_{tag}",
                     (side * (1.10 + index * 0.14), 0.22, 1.30 + index * 0.34),
                     0.16, 1.15, (0, math.radians(70 * side), 0),
                     glow if index == 0 else accent, rig,
                     "Fin_L" if side < 0 else "Fin_R", lod)
        torus(f"V2_FenWheel_{tag}", (0, 0.16, 1.54), 1.18, 0.16,
              (math.radians(90), 0, 0), accent, rig, "Torso", lod)
    elif style == "cinderhart":
        for index in range((26, 15, 7)[lod]):
            angle = math.tau * index / max(1, (26, 15, 7)[lod])
            box(f"V2_CinderPlate_{index:02d}_{tag}",
                (math.cos(angle) * 0.78, -0.62 + math.sin(angle) * 0.20,
                 0.86 + (index % 7) * 0.30),
                (0.20 + (index % 3) * 0.04, 0.08, 0.30),
                (0, angle * 0.12, angle), armor, rig, "Torso", lod, 0.045)
        for side, suffix in ((-1, "L"), (1, "R")):
            ico_sphere(f"V2_MagmaFist_{suffix}_{tag}", (2.16 * side, -0.10, 1.16),
                       (0.48, 0.42, 0.50), glow, rig, f"Hand_{suffix}", lod)
            for index in range((6, 4, 2)[lod]):
                cone(f"V2_FistShard_{suffix}_{index}_{tag}",
                     (2.16 * side, -0.10, 1.16 + (index - 2) * 0.12),
                     0.08, 0.40, (0, math.radians(90), 0),
                     accent, rig, f"Hand_{suffix}", lod)
        for side, suffix in ((-1, "L"), (1, "R")):
            cone(f"V2_CinderHorn_{suffix}_{tag}", (0.64 * side, 0.05, 3.40),
                 0.22, 1.30, (0, math.radians(28 * side), 0), dark,
                 rig, "Head", lod)
    elif style == "ash_bellower":
        torus(f"V2_BellRing_{tag}", (0, -0.04, 1.52), 0.92, 0.17,
              (math.radians(90), 0, 0), armor, rig, "Torso", lod)
        for index in range((18, 11, 5)[lod]):
            angle = math.tau * index / max(1, (18, 11, 5)[lod])
            box(f"V2_BellPlate_{index:02d}_{tag}",
                (math.cos(angle) * 0.76, -0.18 + math.sin(angle) * 0.35,
                 1.08 + (index % 4) * 0.32),
                (0.12, 0.08, 0.36), (0, angle * 0.18, angle), armor,
                rig, "Torso", lod, 0.04)
        for index in range((12, 8, 4)[lod]):
            angle = math.tau * index / max(1, (12, 8, 4)[lod])
            cone(f"V2_EmberHanging_{index:02d}_{tag}",
                 (math.cos(angle) * 0.90, math.sin(angle) * 0.42, 0.66),
                 0.07, 0.64, (math.sin(angle) * 0.3, math.cos(angle) * 0.2, 0),
                 glow, rig, "BellClapper", lod)
        torus(f"V2_BellHalo_{tag}", (0, 0.10, 3.40), 0.82, 0.07,
              (math.radians(90), 0, 0), glow, rig, "Head", lod)
    elif style == "tide_oracle":
        for index in range((8, 5, 3)[lod]):
            angle = math.tau * index / max(1, (8, 5, 3)[lod])
            uv_sphere(f"V2_TideOrb_{index:02d}_{tag}",
                      (math.cos(angle) * 1.36, math.sin(angle) * 0.72, 2.05 + math.sin(angle * 2) * 0.26),
                      (0.20, 0.20, 0.20), glow if index % 2 else accent,
                      rig, "Core", lod, (0.0, 0.0, 1.0, 1.0))
        for side, suffix in ((-1, "L"), (1, "R")):
            for index in range((5, 3, 2)[lod]):
                cone(f"V2_TideFin_{suffix}_{index}_{tag}",
                     (side * (0.96 + index * 0.18), 0.20, 1.54 + index * 0.34),
                     0.12, 1.22, (0, math.radians(72 * side), 0),
                     accent, rig, "Fin_L" if side < 0 else "Fin_R", lod)
        for index in range((10, 6, 3)[lod]):
            angle = math.tau * index / max(1, (10, 6, 3)[lod])
            torus(f"V2_TideGlyph_{index:02d}_{tag}", (0, 0.10, 2.24),
                  0.86 + index * 0.035, 0.022, (math.radians(90), angle * 0.1, 0),
                  glow, rig, "Core", lod)
    elif style == "lunar_leviathan":
        for side, suffix in ((-1, "L"), (1, "R")):
            for index in range((7, 5, 3)[lod]):
                bone = f"Wing_{suffix}" if index == 0 else f"Wing_{suffix}_{min(index, 4)}"
                cone(f"V2_LunarFin_{suffix}_{index}_{tag}",
                     (side * (1.02 + index * 0.34), 0.28, 2.24 + index * 0.16),
                     0.18, 1.72 - index * 0.12,
                     (0, math.radians(70 * side), math.radians(10 * side)),
                     accent if index % 2 else glow, rig, bone, lod)
            box(f"V2_Crescent_{suffix}_{tag}", (2.22 * side, -0.12, 0.64),
                (0.18, 0.10, 1.46), (0, math.radians(20 * side), 0),
                glow, rig, f"Weapon_{suffix}", lod, 0.06)
        torus(f"V2_LunarHalo_{tag}", (0, 0.24, 2.90), 1.18, 0.08,
              (math.radians(68), 0, math.radians(18)), glow, rig, "Head", lod)
        torus(f"V2_LunarHaloInner_{tag}", (0, 0.28, 2.90), 0.72, 0.035,
              (math.radians(68), 0, math.radians(18)), accent, rig, "Head", lod)


def build_boss(boss_id: str, spec: dict) -> None:
    reset_scene()
    body = spec["body"]
    dark = tuple(max(0.008, value * 0.42) for value in body[:3]) + (1,)
    mats = {
        "body": material("BossV2_Body", body, 0.84, tile=0),
        "armor": material("BossV2_Armor", spec["armor"], 0.72, 0.12, tile=1),
        "accent": material("BossV2_Accent", spec["accent"], 0.58, 0.08, tile=2),
        "glow": material(f"V2_{boss_id}_Glow", spec["glow"], 0.32,
                         tile=3, emission=spec["glow"]),
        "dark": material("BossV2_Dark", dark, 0.94, tile=4),
    }
    rig = create_rig()
    for lod in range(3):
        add_common_body(rig, mats, spec["style"], lod)
        add_identity_details(rig, mats, spec["style"], lod)

    socket_data = [
        ("SOCKET_Hand_R", "Hand_R", (0.0, 0.0, 0.34)),
        ("SOCKET_Hand_L", "Hand_L", (0.0, 0.0, 0.34)),
        ("SOCKET_VFX_Chest", "Chest", (0.0, -0.72, 0.0)),
        ("SOCKET_VFX_Foot_L", "Foot_L", (0.0, -0.28, 0.0)),
        ("SOCKET_VFX_Foot_R", "Foot_R", (0.0, -0.28, 0.0)),
        ("SOCKET_VFX_Muzzle_L", "Hand_L", (0.0, -0.18, -0.26)),
        ("SOCKET_VFX_Muzzle_R", "Hand_R", (0.0, -0.18, -0.26)),
        ("SOCKET_VFX_Weapon_L", "Weapon_L", (0.0, 0.0, 0.0)),
        ("SOCKET_VFX_Weapon_R", "Weapon_R", (0.0, 0.0, 0.0)),
        ("SOCKET_VFX_Crown", "Head", (0.0, -0.04, 0.70)),
    ]
    for name, bone, location in socket_data:
        add_socket(rig, name, bone, location)
    build_actions(rig, spec["skills"], spec["style"])

    scene = bpy.context.scene
    scene["embervale_asset_kind"] = "boss"
    scene["embervale_asset_version"] = 2
    scene["embervale_canonical_id"] = boss_id
    scene["embervale_realm"] = spec["realm"]
    scene["embervale_detail_contract"] = "v2_articulated_layered"
    blend_path = BLEND_OUT / f"boss_{boss_id}.blend"
    glb_path = OUT / f"boss_{boss_id}.glb"
    blend_path.parent.mkdir(parents=True, exist_ok=True)
    glb_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path.resolve()))
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path.resolve()), export_format="GLB", use_visible=True,
        export_animations=True, export_skins=True, export_morph=True,
        export_attributes=True, export_yup=True, export_apply=False)
    print(f"BUILT V2 {boss_id}: {glb_path}")


def main() -> None:
    args = parse_args()
    selected = [args.boss] if args.boss else list(BOSSES)
    for boss_id in selected:
        build_boss(boss_id, BOSSES[boss_id])


if __name__ == "__main__":
    main()
