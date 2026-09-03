"""Render a deterministic Blender preview of the authored Matriarch LOD0."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def args() -> argparse.Namespace:
    raw = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args(raw)


def point_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def main() -> int:
    output = args().output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and (obj.name.endswith("_LOD1") or obj.name.endswith("_LOD2")):
            obj.hide_render = True

    bpy.ops.mesh.primitive_plane_add(size=24, location=(0, 0, -0.02))
    ground = bpy.context.object
    ground.name = "PreviewGround"
    ground_mat = bpy.data.materials.new("PreviewGroundMat")
    ground_mat.diffuse_color = (0.025, 0.035, 0.03, 1.0)
    ground.data.materials.append(ground_mat)

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (6.4, -9.8, 4.9)
    camera_data.lens = 58
    point_at(camera, Vector((0, 0, 1.75)))
    bpy.context.scene.camera = camera

    def area(name: str, location, energy: float, color, size: float):
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.color, data.shape, data.size = energy, color, "DISK", size
        light = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(light)
        light.location = location
        point_at(light, Vector((0, 0, 1.7)))

    area("Key_Jade", (-4.5, -5.5, 7.5), 1050, (0.48, 0.82, 0.58), 5.0)
    area("Rim_Ember", (4.8, 2.5, 5.8), 1250, (1.0, 0.24, 0.07), 3.5)
    area("Fill_Moon", (0.5, -1.5, 7.8), 650, (0.36, 0.48, 0.78), 4.0)

    world = bpy.context.scene.world or bpy.data.worlds.new("PreviewWorld")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.008, 0.012, 0.012, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.18

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output)
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)
    print(f"MATRIARCH PREVIEW RENDERED {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
