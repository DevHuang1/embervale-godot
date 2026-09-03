"""Build Embervale's authored low-poly Matriarch source scene.

Run with Blender in background mode. The output is deterministic and remains
editable in Blender: three complete LODs, one gameplay rig, attachment/VFX
sockets, realm-mask vertex colors, and the first synchronized boss clip set.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    raw = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args(raw)


def reset_scene() -> None:
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
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


def material(name: str, color: tuple[float, float, float, float], roughness: float,
             metallic: float = 0.0, emission: tuple[float, float, float, float] | None = None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    # Blender glTF only recognizes a direct vertex-color Base Color path.
    # realm_mask() therefore bakes the authored material factor into COLOR_0;
    # the original mask remains reversible against that known factor.
    vertex_color = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    vertex_color.layer_name = "RealmMask"
    mat.node_tree.links.new(vertex_color.outputs["Color"], bsdf.inputs["Base Color"])
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = 2.2
    return mat


def create_rig() -> bpy.types.Object:
    data = bpy.data.armatures.new("Matriarch_Rig")
    rig = bpy.data.objects.new("Matriarch_Rig", data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    def bone(name: str, head, tail, parent: str | None = None):
        b = data.edit_bones.new(name)
        b.head, b.tail = head, tail
        if parent:
            b.parent = data.edit_bones[parent]
        return b

    bone("Root", (0, 0, 0), (0, 0, 0.5))
    bone("Torso", (0, 0, 0.45), (0, 0, 2.45), "Root")
    bone("Head", (0, 0, 2.35), (0, 0, 3.35), "Torso")
    bone("Arm_L", (0, 0, 2.25), (-1.28, 0, 2.0), "Torso")
    bone("Claw_L", (-1.28, 0, 2.0), (-2.18, -0.04, 1.45), "Arm_L")
    bone("Arm_R", (0, 0, 2.25), (1.28, 0, 2.0), "Torso")
    bone("Claw_R", (1.28, 0, 2.0), (2.18, -0.04, 1.45), "Arm_R")
    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.select_set(False)
    return rig


def realm_mask(obj: bpy.types.Object, values: tuple[float, float, float, float]) -> None:
    # Channels are moss, ash, wetness, and corruption/emission respectively.
    # The material's alpha-only connection exports RGB as COLOR_0 without
    # multiplying the visible albedo.
    base = obj.data.materials[0].diffuse_color
    encoded = tuple(base[i] * (1.0 - max(0.0, min(1.0, values[i])) * 0.12)
                    for i in range(3)) + (values[3],)
    attr = obj.data.color_attributes.new(name="RealmMask", type="BYTE_COLOR", domain="CORNER")
    for entry in attr.data:
        entry.color = encoded


def skin_rigid(obj: bpy.types.Object, rig: bpy.types.Object, bone: str) -> None:
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    modifier = obj.modifiers.new(name="MatriarchRig", type="ARMATURE")
    modifier.object = rig
    obj.parent = rig


def finish_mesh(obj: bpy.types.Object, name: str, mat, rig, bone: str,
                mask=(0.0, 0.0, 0.0, 1.0)) -> bpy.types.Object:
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    obj.data.materials.append(mat)
    realm_mask(obj, mask)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    skin_rigid(obj, rig, bone)
    obj.select_set(False)
    return obj


def sphere(name: str, location, scale, segments: int, rings: int, mat, rig, bone: str,
           mask=(0.0, 0.0, 0.0, 1.0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=location)
    obj = bpy.context.object
    obj.scale = scale
    return finish_mesh(obj, name, mat, rig, bone, mask)


def cone(name: str, location, radius: float, depth: float, vertices: int, rotation,
         mat, rig, bone: str, mask=(0.0, 0.0, 0.0, 1.0)):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=0.015,
                                    depth=depth, location=location, rotation=rotation)
    return finish_mesh(bpy.context.object, name, mat, rig, bone, mask)


def build_lod(lod: int, rig, bark, dark_bark, moss, heart, eye) -> None:
    seg = (16, 12, 8)[lod]
    rings = (10, 8, 5)[lod]
    tag = f"LOD{lod}"
    sphere(f"MatriarchTorso_{tag}", (0, 0, 1.65), (1.30, 0.92, 1.55),
           seg, rings, bark, rig, "Torso", (0.22, 0.05, 0.0, 1.0))
    sphere(f"MatriarchCrownMass_{tag}", (0, 0, 2.75), (1.0, 0.78, 0.78),
           seg, rings, moss, rig, "Head", (0.72, 0.08, 0.0, 1.0))
    sphere(f"MatriarchHeart_{tag}", (0, -0.88, 1.62), (0.31, 0.16, 0.40),
           max(8, seg), max(5, rings), heart, rig, "Torso", (0.0, 0.0, 1.0, 1.0))
    sphere(f"MatriarchJaw_{tag}", (0, -0.72, 2.43), (0.66, 0.18, 0.14),
           max(8, seg), max(5, rings), dark_bark, rig, "Head", (0.12, 0.0, 0.0, 1.0))
    for side, suffix in ((-1, "L"), (1, "R")):
        sphere(f"MatriarchEye{suffix}_{tag}", (0.34 * side, -0.80, 2.86),
               (0.15, 0.055, 0.038), max(8, seg), max(5, rings), eye, rig, "Head",
               (0.0, 0.0, 1.0, 1.0))
        cone(f"MatriarchBrow{suffix}_{tag}", (0.38 * side, -0.78, 3.03),
             0.11, 0.72, max(5, seg // 2),
             (math.radians(88), math.radians(22) * side, math.radians(8) * side),
             dark_bark, rig, "Head", (0.20, 0.0, 0.0, 1.0))
        cone(f"MatriarchFang{suffix}_{tag}", (0.43 * side, -0.80, 2.31),
             0.10, 0.48, max(5, seg // 2), (math.pi, 0, 0),
             dark_bark, rig, "Head", (0.16, 0.0, 0.0, 1.0))

    for side, suffix in ((-1, "L"), (1, "R")):
        sphere(f"MatriarchShoulder{suffix}_{tag}", (1.12 * side, 0, 2.22),
               (0.58, 0.55, 0.62), seg, rings, dark_bark, rig, f"Arm_{suffix}",
               (0.12, 0.0, 0.0, 1.0))
        cone(f"MatriarchClaw{suffix}_{tag}", (1.72 * side, -0.06, 1.72),
             0.34, 1.45, max(6, seg // 2), (0, math.radians(58) * side, 0),
             dark_bark, rig, f"Claw_{suffix}")

    root_count = (7, 5, 3)[lod]
    for i in range(root_count):
        angle = math.tau * i / root_count
        cone(f"MatriarchRoot{i:02d}_{tag}",
             (math.cos(angle) * 0.84, math.sin(angle) * 0.56, 0.48),
             0.38, 1.55, max(6, seg // 2),
             (math.sin(angle) * 0.30, math.cos(angle) * 0.30, -angle),
             dark_bark, rig, "Root", (0.08, 0.0, 0.0, 1.0))

    crown_count = (9, 6, 4)[lod]
    for i in range(crown_count):
        angle = math.tau * i / crown_count
        cone(f"MatriarchThorn{i:02d}_{tag}",
             (math.cos(angle) * 0.72, math.sin(angle) * 0.52, 3.33),
             0.18, 1.20 if i % 2 == 0 else 0.88, max(5, seg // 2),
             (math.sin(angle) * 0.30, math.cos(angle) * 0.30, -angle),
             dark_bark, rig, "Head", (0.18, 0.0, 0.0, 1.0))
    for side, suffix in ((-1, "L"), (1, "R")):
        cone(f"MatriarchAntler{suffix}_{tag}", (1.02 * side, 0.08, 3.45),
             0.24, 1.95, max(6, seg // 2),
             (0, math.radians(34) * side, math.radians(-12) * side),
             dark_bark, rig, "Head", (0.24, 0.0, 0.0, 1.0))


def add_socket(rig: bpy.types.Object, name: str, bone: str, location) -> None:
    empty = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(empty)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.18
    empty.location = location
    empty.parent = rig
    empty.parent_type = "BONE"
    empty.parent_bone = bone


def clear_pose(rig: bpy.types.Object) -> None:
    for bone in rig.pose.bones:
        bone.rotation_euler = (0, 0, 0)
        bone.location = (0, 0, 0)
        bone.scale = (1, 1, 1)


def make_action(rig: bpy.types.Object, name: str, length: int,
                poses: dict[int, dict[str, tuple[float, float, float]]]) -> None:
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action
    for frame, pose in poses.items():
        clear_pose(rig)
        for bone_name, rotation in pose.items():
            bone = rig.pose.bones[bone_name]
            bone.rotation_euler = tuple(math.radians(v) for v in rotation)
        for bone in rig.pose.bones:
            bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
    action.frame_range = (1, length)
    rig.animation_data.action = None


def build_actions(rig: bpy.types.Object) -> None:
    make_action(rig, "LOC_Idle", 60, {
        1: {"Torso": (0, 0, -2), "Head": (0, 0, 3), "Arm_L": (0, 0, -4), "Arm_R": (0, 0, 4)},
        30: {"Torso": (2, 0, 2), "Head": (-2, 0, -3), "Arm_L": (0, 0, 2), "Arm_R": (0, 0, -2)},
        60: {"Torso": (0, 0, -2), "Head": (0, 0, 3), "Arm_L": (0, 0, -4), "Arm_R": (0, 0, 4)},
    })
    make_action(rig, "BOSS_Attack1_Slam", 36, {
        1: {}, 9: {"Torso": (-14, 0, 0), "Arm_L": (0, -12, -58), "Arm_R": (0, 12, 58)},
        20: {"Torso": (28, 0, 0), "Arm_L": (0, 18, 76), "Arm_R": (0, -18, -76)},
        36: {},
    })
    make_action(rig, "BOSS_Cast_RootPrison", 42, {
        1: {}, 16: {"Torso": (-10, 0, 0), "Head": (12, 0, 0), "Arm_L": (-18, 0, -72), "Arm_R": (-18, 0, 72)},
        28: {"Torso": (14, 0, 0), "Arm_L": (24, 0, -28), "Arm_R": (24, 0, 28)},
        42: {},
    })
    make_action(rig, "BOSS_Buff_Phase", 48, {
        1: {}, 20: {"Torso": (-12, 0, 0), "Head": (-18, 0, 0), "Arm_L": (-28, 0, -82), "Arm_R": (-28, 0, 82)},
        34: {"Torso": (8, 0, 0), "Head": (16, 0, 0), "Arm_L": (12, 0, -48), "Arm_R": (12, 0, 48)},
        48: {},
    })
    make_action(rig, "HIT_Heavy_Front", 18, {
        1: {}, 5: {"Torso": (-22, 8, 0), "Head": (-18, 0, 12)}, 18: {},
    })
    make_action(rig, "DEATH_Forward", 60, {
        1: {}, 18: {"Torso": (28, 0, 0), "Head": (-24, 0, 0), "Arm_L": (18, 0, 44), "Arm_R": (18, 0, -44)},
        60: {"Torso": (86, 0, 0), "Head": (-34, 0, 0), "Arm_L": (32, 0, 68), "Arm_R": (32, 0, -68)},
    })
    clear_pose(rig)


def build(output: Path) -> None:
    reset_scene()
    bark = material("MAT_Bark", (0.16, 0.075, 0.045, 1.0), 0.88)
    dark_bark = material("MAT_Thorn", (0.055, 0.022, 0.018, 1.0), 0.94)
    moss = material("MAT_Moss", (0.10, 0.26, 0.13, 1.0), 0.82)
    heart = material("MAT_Heart", (0.16, 0.035, 0.02, 1.0), 0.42,
                     emission=(1.0, 0.16, 0.035, 1.0))
    eye = material("MAT_Eyes", (0.30, 0.02, 0.008, 1.0), 0.30,
                   emission=(1.0, 0.08, 0.015, 1.0))
    rig = create_rig()
    for lod in range(3):
        build_lod(lod, rig, bark, dark_bark, moss, heart, eye)
    add_socket(rig, "SOCKET_Hand_R", "Claw_R", (0, 0, 0.45))
    add_socket(rig, "SOCKET_Hand_L", "Claw_L", (0, 0, 0.45))
    add_socket(rig, "SOCKET_VFX_Chest", "Torso", (0, -0.85, 1.28))
    add_socket(rig, "SOCKET_VFX_Foot_L", "Root", (-0.65, 0, 0.08))
    add_socket(rig, "SOCKET_VFX_Foot_R", "Root", (0.65, 0, 0.08))
    build_actions(rig)
    bpy.context.scene["embervale_asset_kind"] = "boss"
    bpy.context.scene["embervale_asset_version"] = 1
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output.resolve()))
    print(f"MATRIARCH SOURCE BUILT {output.resolve()}")


def main() -> int:
    args = parse_args()
    build(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
