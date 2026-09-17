"""Headless-safe GLB fallback for the authored Boss Roster V2.

The normal source of truth is ``build_boss_roster_v2.py`` and Blender remains
the preferred editable authoring tool.  This companion uses only Python's
standard library to emit valid glTF 2.0 binary assets when Blender cannot start
on a CI or workstation.  It deliberately emits the same socket, LOD, skin,
material, and animation contract consumed by CharacterRigLoader.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

try:
    from generate_boss_v2_textures import generate as generate_shared_textures
except ImportError:
    generate_shared_textures = None


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "models" / "bosses_v2"
TEXTURE_DIR = ROOT / "assets" / "textures" / "bosses_v2"
ATLAS_URI = "../../textures/bosses_v2/boss_v2_atlas.png"
ORM_URI = "../../textures/bosses_v2/boss_v2_orm.png"
NORMAL_URI = "../../textures/bosses_v2/boss_v2_normal.png"

BOSSES = {
    "whispergrove_root_harrow": ("root_harrow", (0.08, 0.19, 0.11, 1), (0.18, 0.34, 0.18, 1), (0.22, 0.84, 0.30, 1), (0.72, 1.0, 0.38, 1), ["root_sword_combo", "seed_burst"]),
    "bramblewood_thorn_regent": ("thorn_regent", (0.10, 0.12, 0.06, 1), (0.25, 0.20, 0.08, 1), (0.80, 0.28, 0.06, 1), (1.0, 0.60, 0.14, 1), ["regent_cleave", "root_crash"]),
    "bramblewood_briar_widow": ("briar_widow", (0.16, 0.045, 0.12, 1), (0.28, 0.08, 0.20, 1), (0.86, 0.10, 0.34, 1), (0.66, 0.38, 1.0, 1), ["needle_salvo", "briar_mine", "widow_bloom"]),
    "mistfen_fogmaw": ("fogmaw", (0.035, 0.12, 0.16, 1), (0.08, 0.24, 0.27, 1), (0.12, 0.68, 0.78, 1), (0.48, 0.94, 1.0, 1), ["fog_roll", "burrow_burst"]),
    "heartwood_cinderhart": ("cinderhart", (0.12, 0.025, 0.012, 1), (0.28, 0.065, 0.018, 1), (0.95, 0.16, 0.015, 1), (1.0, 0.66, 0.08, 1), ["furnace_pound", "magma_mortar"]),
    "heartwood_ash_bellower": ("ash_bellower", (0.10, 0.055, 0.035, 1), (0.24, 0.12, 0.055, 1), (0.90, 0.24, 0.035, 1), (1.0, 0.78, 0.20, 1), ["ash_mortar", "flare_wall", "bell_regen"]),
    "moonfen_tide_oracle": ("tide_oracle", (0.025, 0.06, 0.18, 1), (0.06, 0.16, 0.34, 1), (0.10, 0.66, 0.92, 1), (0.56, 0.76, 1.0, 1), ["tide_bolt", "moon_tide_ring", "oracle_split"]),
    "moonfen_lunar_leviathan": ("lunar_leviathan", (0.045, 0.025, 0.16, 1), (0.10, 0.07, 0.30, 1), (0.42, 0.18, 0.86, 1), (0.86, 0.42, 1.0, 1), ["lunar_breath", "crescent_sweep", "orbit_barrage"]),
}

JOINT_PARENTS = {
    "Root": None, "Pelvis": "Root", "Torso": "Pelvis", "Chest": "Torso",
    "Neck": "Chest", "Head": "Neck",
    "Arm_L": "Chest", "Forearm_L": "Arm_L", "Hand_L": "Forearm_L", "Weapon_L": "Hand_L",
    "Arm_R": "Chest", "Forearm_R": "Arm_R", "Hand_R": "Forearm_R", "Weapon_R": "Hand_R",
    "Leg_L": "Pelvis", "Shin_L": "Leg_L", "Foot_L": "Shin_L",
    "Leg_R": "Pelvis", "Shin_R": "Leg_R", "Foot_R": "Shin_R",
    "Wing_L": "Chest", "Wing_L_1": "Wing_L", "Wing_L_2": "Wing_L_1", "Wing_L_3": "Wing_L_2",
    "Wing_L_4": "Wing_L_3",
    "Wing_R": "Chest", "Wing_R_1": "Wing_R", "Wing_R_2": "Wing_R_1", "Wing_R_3": "Wing_R_2",
    "Wing_R_4": "Wing_R_3",
    "Tail_1": "Pelvis", "Tail_2": "Tail_1", "Tail_3": "Tail_2",
    "Tail_4": "Tail_3", "Tail_5": "Tail_4",
    "Jaw": "Head", "Core": "Chest", "BellClapper": "Chest",
    "Mandible_L": "Head", "Mandible_R": "Head",
    "RootBranch_L": "Forearm_L", "RootBranch_L_2": "RootBranch_L",
    "RootBranch_R": "Forearm_R", "RootBranch_R_2": "RootBranch_R",
    "Fin_L": "Chest", "Fin_R": "Chest",
}

JOINT_POSITIONS = {
    "Root": (0, 0, 0), "Pelvis": (0, 0, 0.3), "Torso": (0, 0, 0.85),
    "Chest": (0, 0, 1.8), "Neck": (0, 0, 2.62), "Head": (0, 0, 2.92),
    "Arm_L": (-0.0, 0, 2.45), "Forearm_L": (-1.25, -0.05, 2.15),
    "Hand_L": (-1.90, -0.05, 1.62), "Weapon_L": (-2.18, -0.12, 1.42),
    "Arm_R": (0.0, 0, 2.45), "Forearm_R": (1.25, -0.05, 2.15),
    "Hand_R": (1.90, -0.05, 1.62), "Weapon_R": (2.18, -0.12, 1.42),
    "Leg_L": (-0.52, 0, 0.86), "Shin_L": (-0.58, 0, 0.28), "Foot_L": (-0.62, -0.05, -0.25),
    "Leg_R": (0.52, 0, 0.86), "Shin_R": (0.58, 0, 0.28), "Foot_R": (0.62, -0.05, -0.25),
    "Wing_L": (-0.75, 0.12, 2.18), "Wing_L_1": (-1.60, 0.30, 2.65),
    "Wing_L_2": (-1.94, 0.30, 2.75), "Wing_L_3": (-2.28, 0.30, 2.85),
    "Wing_L_4": (-2.62, 0.30, 2.95),
    "Wing_R": (0.75, 0.12, 2.18), "Wing_R_1": (1.60, 0.30, 2.65),
    "Wing_R_2": (1.94, 0.30, 2.75), "Wing_R_3": (2.28, 0.30, 2.85),
    "Wing_R_4": (2.62, 0.30, 2.95),
    "Tail_1": (0, 0.25, 0.62), "Tail_2": (0, 0.59, 0.50), "Tail_3": (0, 0.93, 0.38),
    "Tail_4": (0, 1.27, 0.26), "Tail_5": (0, 1.61, 0.18),
    "Jaw": (0, -0.18, 2.25), "Core": (0, -0.40, 1.90),
    "BellClapper": (0, -0.12, 1.15),
    "Mandible_L": (-0.35, -0.10, 2.10), "Mandible_R": (0.35, -0.10, 2.10),
    "RootBranch_L": (-1.60, -0.02, 1.40), "RootBranch_L_2": (-1.90, -0.03, 1.00),
    "RootBranch_R": (1.60, -0.02, 1.40), "RootBranch_R_2": (1.90, -0.03, 1.00),
    "Fin_L": (-1.10, 0.18, 1.70), "Fin_R": (1.10, 0.18, 1.70),
}


def add(a, b):
    return tuple(a[i] + b[i] for i in range(3))


def sub(a, b):
    return tuple(a[i] - b[i] for i in range(3))


def mul(a, scalar):
    return tuple(v * scalar for v in a)


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(a):
    length = math.sqrt(max(dot(a, a), 1e-12))
    return mul(a, 1.0 / length)


def rotate(point, rotation):
    x, y, z = rotation
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    px, py, pz = point
    # XYZ Euler rotation, sufficient for authored rigid detail pieces.
    qx = px
    qy = py * cx - pz * sx
    qz = py * sx + pz * cx
    rx = qx * cy + qz * sy
    rz = -qx * sy + qz * cy
    return (rx * cz - qy * sz, rx * sz + qy * cz, rz)


def basis_from_z(axis):
    z = norm(axis)
    up = (0.0, 1.0, 0.0) if abs(dot(z, (0.0, 1.0, 0.0))) < 0.92 else (1.0, 0.0, 0.0)
    x = norm(cross(up, z))
    y = cross(z, x)
    return x, y, z


@dataclass
class MeshGroup:
    vertices: list[tuple[float, float, float]] = field(default_factory=list)
    normals: list[tuple[float, float, float]] = field(default_factory=list)
    uvs: list[tuple[float, float]] = field(default_factory=list)
    colors: list[tuple[float, float, float, float]] = field(default_factory=list)
    joints: list[tuple[int, int, int, int]] = field(default_factory=list)
    weights: list[tuple[float, float, float, float]] = field(default_factory=list)
    indices: list[int] = field(default_factory=list)

    def add(self, vertices, normals, bone_index: int):
        start = len(self.vertices)
        self.vertices.extend(vertices)
        self.normals.extend(normals)
        self.colors.extend([(1.0, 1.0, 1.0, 1.0)] * len(vertices))
        self.joints.extend([(bone_index, 0, 0, 0)] * len(vertices))
        self.weights.extend([(1.0, 0.0, 0.0, 0.0)] * len(vertices))
        self.indices.extend(start + index for index in range(len(vertices)))


class BossGeometry:
    def __init__(self, joint_indices: dict[str, int]):
        self.joint_indices = joint_indices
        self.groups: dict[tuple[int, str, str], MeshGroup] = {}

    def group(self, lod: int, material: str, bone: str) -> MeshGroup:
        key = (lod, material, bone)
        if key not in self.groups:
            self.groups[key] = MeshGroup()
        return self.groups[key]

    def add(self, lod: int, material: str, bone: str, vertices, normals):
        self.group(lod, material, bone).add(vertices, normals, self.joint_indices[bone])

    @staticmethod
    def uv_for(material: str, point) -> tuple[float, float]:
        # Five material tiles share one atlas. A deterministic planar blend
        # avoids extra UV seams while keeping every rigid detail in its tile.
        tile = {"body": 0, "armor": 1, "accent": 2, "glow": 3, "dark": 4}[material]
        u_local = (abs(point[0] * 0.17 + point[1] * 0.11 + point[2] * 0.23) % 1.0)
        v_local = (abs(point[0] * 0.07 + point[1] * 0.19 + point[2] * 0.13) % 1.0)
        return ((tile + 0.04 + u_local * 0.92) / 5.0,
                0.04 + v_local * 0.92)

    def sphere(self, lod, material, bone, center, radii, segments=None, rings=None):
        segments = segments or (32, 20, 12)[lod]
        rings = rings or (18, 12, 8)[lod]
        vertices, normals = [], []
        for ring in range(rings + 1):
            phi = math.pi * ring / rings
            sp, cp = math.sin(phi), math.cos(phi)
            for segment in range(segments):
                theta = math.tau * segment / segments
                st, ct = math.sin(theta), math.cos(theta)
                local = (sp * ct, sp * st, cp)
                vertices.append(add(center, (local[0] * radii[0], local[1] * radii[1], local[2] * radii[2])))
                normals.append(norm((local[0] / max(radii[0], 0.01), local[1] / max(radii[1], 0.01), local[2] / max(radii[2], 0.01))))
        triangles = []
        for ring in range(rings):
            for segment in range(segments):
                a = ring * segments + segment
                b = ring * segments + (segment + 1) % segments
                c = (ring + 1) * segments + (segment + 1) % segments
                d = (ring + 1) * segments + segment
                triangles.extend([a, b, c, a, c, d])
        self._add_indexed(lod, material, bone, vertices, normals, triangles)

    def _hard_box(self, lod, material, bone, center, size, rotation=(0, 0, 0)):
        hx, hy, hz = mul(size, 0.5)
        corners = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
                   (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]
        faces = [((0, 1, 2, 3), (0, 0, -1)), ((4, 7, 6, 5), (0, 0, 1)),
                 ((0, 4, 5, 1), (0, -1, 0)), ((3, 2, 6, 7), (0, 1, 0)),
                 ((1, 5, 6, 2), (1, 0, 0)), ((0, 3, 7, 4), (-1, 0, 0))]
        vertices, normals, triangles = [], [], []
        for face, normal in faces:
            base = len(vertices)
            vertices.extend(add(center, rotate(corners[i], rotation)) for i in face)
            normals.extend(rotate(normal, rotation) for _ in face)
            triangles.extend([base, base + 1, base + 2, base, base + 2, base + 3])
        self._add_indexed(lod, material, bone, vertices, normals, triangles)

    def box(self, lod, material, bone, center, size, rotation=(0, 0, 0)):
        self._hard_box(lod, material, bone, center, size, rotation)

    def rounded_box(self, lod, material, bone, center, size, rotation=(0, 0, 0), bevel=0.08):
        """A compact chamfered plate made from a recessed box, edge rails, and corners.

        The fallback exporter cannot rely on Blender's Bevel modifier, so this
        keeps the same visual intent with deterministic geometry. The edge
        rails and corner caps catch highlights without adding runtime objects
        or material slots, and their resolution drops with the LOD.
        """
        half = mul(size, 0.5)
        b = min(float(bevel), half[0] * 0.42, half[1] * 0.42, half[2] * 0.42)
        if b <= 0.008:
            self._hard_box(lod, material, bone, center, size, rotation)
            return
        core_size = (max(size[0] - b * 2.0, 0.02),
                     max(size[1] - b * 2.0, 0.02),
                     max(size[2] - b * 2.0, 0.02))
        self._hard_box(lod, material, bone, center, core_size, rotation)

        def place(local):
            return add(center, rotate(local, rotation))

        def axis(local_axis):
            return rotate(local_axis, rotation)

        hx, hy, hz = half
        edge_specs = [
            ((0, hy - b, hz - b), (size[0] - b * 2.0, 0, 0)),
            ((0, -hy + b, hz - b), (size[0] - b * 2.0, 0, 0)),
            ((0, hy - b, -hz + b), (size[0] - b * 2.0, 0, 0)),
            ((0, -hy + b, -hz + b), (size[0] - b * 2.0, 0, 0)),
            ((hx - b, 0, hz - b), (0, size[1] - b * 2.0, 0)),
            ((-hx + b, 0, hz - b), (0, size[1] - b * 2.0, 0)),
            ((hx - b, 0, -hz + b), (0, size[1] - b * 2.0, 0)),
            ((-hx + b, 0, -hz + b), (0, size[1] - b * 2.0, 0)),
            ((hx - b, hy - b, 0), (0, 0, size[2] - b * 2.0)),
            ((-hx + b, hy - b, 0), (0, 0, size[2] - b * 2.0)),
            ((hx - b, -hy + b, 0), (0, 0, size[2] - b * 2.0)),
            ((-hx + b, -hy + b, 0), (0, 0, size[2] - b * 2.0)),
        ]
        for edge_center, edge_axis in edge_specs:
            self.cylinder(lod, material, bone, place(edge_center), b,
                          max(max(edge_axis), 0.02), axis(edge_axis))
        corner_segments = (8, 6, 4)[lod]
        corner_rings = (4, 3, 2)[lod]
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    self.sphere(lod, material, bone,
                                place((sx * (hx - b), sy * (hy - b), sz * (hz - b))),
                                (b, b, b), corner_segments, corner_rings)

    def cone(self, lod, material, bone, center, radius, depth, axis=(0, 0, 1)):
        x, y, z = basis_from_z(axis)
        sides = (14, 9, 6)[lod]
        vertices, normals, triangles = [], [], []
        tip = add(center, mul(z, depth * 0.5))
        base_center = add(center, mul(z, -depth * 0.5))
        for side in range(sides):
            angle = math.tau * side / sides
            radial = add(mul(x, math.cos(angle) * radius), mul(y, math.sin(angle) * radius))
            vertices.extend([add(base_center, radial), tip])
            side_normal = norm(add(radial, mul(z, radius * 0.35)))
            normals.extend([side_normal, side_normal])
        for side in range(sides):
            a = side * 2
            b = ((side + 1) % sides) * 2
            triangles.extend([a, b, a + 1])
        self._add_indexed(lod, material, bone, vertices, normals, triangles)

    def cylinder(self, lod, material, bone, center, radius, depth, axis=(0, 0, 1)):
        x, y, z = basis_from_z(axis)
        sides = (16, 10, 6)[lod]
        vertices, normals, triangles = [], [], []
        for side in range(sides):
            angle = math.tau * side / sides
            radial = add(mul(x, math.cos(angle) * radius), mul(y, math.sin(angle) * radius))
            n = norm(radial)
            vertices.extend([add(add(center, mul(z, -depth * 0.5)), radial), add(add(center, mul(z, depth * 0.5)), radial)])
            normals.extend([n, n])
        for side in range(sides):
            a = side * 2
            b = ((side + 1) % sides) * 2
            triangles.extend([a, b, a + 1, b, b + 1, a + 1])
        self._add_indexed(lod, material, bone, vertices, normals, triangles)

    def torus(self, lod, material, bone, center, major, minor, rotation=(0, 0, 0)):
        segments, sides = (24, 10), (8, 6)
        segments, sides = ((24, 8), (16, 6), (10, 4))[lod]
        vertices, normals, triangles = [], [], []
        for segment in range(segments):
            theta = math.tau * segment / segments
            for side in range(sides):
                phi = math.tau * side / sides
                local = ((major + minor * math.cos(phi)) * math.cos(theta),
                         (major + minor * math.cos(phi)) * math.sin(theta),
                         minor * math.sin(phi))
                vertices.append(add(center, rotate(local, rotation)))
                normals.append(norm(rotate((math.cos(phi) * math.cos(theta), math.cos(phi) * math.sin(theta), math.sin(phi)), rotation)))
        for segment in range(segments):
            for side in range(sides):
                a = segment * sides + side
                b = ((segment + 1) % segments) * sides + side
                c = ((segment + 1) % segments) * sides + (side + 1) % sides
                d = segment * sides + (side + 1) % sides
                triangles.extend([a, b, c, a, c, d])
        self._add_indexed(lod, material, bone, vertices, normals, triangles)

    def _add_indexed(self, lod, material, bone, vertices, normals, triangles):
        group = self.group(lod, material, bone)
        start = len(group.vertices)
        group.vertices.extend(vertices)
        group.normals.extend(normals)
        group.uvs.extend(self.uv_for(material, vertex) for vertex in vertices)
        group.colors.extend([(1.0, 1.0, 1.0, 1.0)] * len(vertices))
        group.joints.extend([(self.joint_indices[bone], 0, 0, 0)] * len(vertices))
        group.weights.extend([(1.0, 0.0, 0.0, 0.0)] * len(vertices))
        group.indices.extend(start + index for index in triangles)


def add_common(geo: BossGeometry, style: str, mats: dict[str, str], lod: int):
    # The V2 roster deliberately does not share the visible humanoid core.
    # Keep the armature and socket contract shared, but build a creature-first
    # body for every canonical style so the GLBs cannot read as recolors of one
    # template. Identity details are added by add_identity below.
    if style in {"root_harrow", "thorn_regent", "briar_widow", "fogmaw",
                 "cinderhart", "ash_bellower", "tide_oracle", "lunar_leviathan"}:
        add_primary_silhouette(geo, mats, style, lod)
        return
    tag = lod
    geo.sphere(lod, mats["body"], "Torso", (0, 0, 1.62), (1.18, 0.78, 1.32))
    geo.sphere(lod, mats["armor"], "Chest", (0, -0.58, 1.92), (0.92, 0.16, 0.74))
    geo.sphere(lod, mats["glow"], "Chest", (0, -0.78, 1.82), (0.28, 0.10, 0.36), max(8, 20 - lod * 4), max(5, 12 - lod * 2))
    # Dense authored plate filigree keeps LOD0/LOD1 in the production target
    # while remaining merged by (lod, material, bone) for a small draw-call
    # footprint. These are modeled details, not runtime particle instances.
    ornament_count = (16, 16, 4)[lod]
    for index in range(ornament_count):
        angle = math.tau * index / max(1, ornament_count)
        center = (math.cos(angle) * 0.72, -0.68 + math.sin(angle) * 0.08,
                  1.18 + (index % 5) * 0.28)
        geo.sphere(lod, mats["armor"], "Chest", center, (0.11, 0.055, 0.15))
    collar_count = (10, 8, 3)[lod]
    for index in range(collar_count):
        geo.torus(lod, mats["accent"], "Chest",
                  (0, -0.12, 1.22 + index * 0.12),
                  0.58 + (index % 2) * 0.06, 0.018 + (index % 3) * 0.006,
                  (math.radians(90), 0, 0))
    geo.sphere(lod, mats["armor"], "Head", (0, -0.02, 2.82), (0.78, 0.62, 0.72))
    geo.box(lod, mats["dark"], "Head", (0, -0.58, 2.54), (0.92, 0.20, 0.20), (0, 0, 0))
    for side, suffix in ((-1, "L"), (1, "R")):
        geo.sphere(lod, mats["glow"], "Head", (0.30 * side, -0.60, 2.94), (0.14, 0.055, 0.075), max(8, 16 - lod * 3), max(5, 8 - lod))
        geo.box(lod, mats["armor"], f"Arm_{suffix}", (1.02 * side, 0, 2.23), (0.58, 0.46, 0.42), (0, 0, math.radians(12 * side)))
        geo.cylinder(lod, mats["body"], f"Arm_{suffix}", (1.28 * side, 0, 1.90), 0.30, 1.10, (1, 0, 0))
        geo.cylinder(lod, mats["armor"], f"Forearm_{suffix}", (1.80 * side, -0.04, 1.46), 0.26, 0.92, (0.93 * side, 0, -0.36))
        geo.sphere(lod, mats["accent"], f"Hand_{suffix}", (2.12 * side, -0.10, 1.20), (0.30, 0.24, 0.30), max(8, 16 - lod * 3), max(5, 8 - lod))
        geo.cylinder(lod, mats["body"], f"Leg_{suffix}", (0.48 * side, 0, 0.72), 0.34, 0.90)
        geo.cylinder(lod, mats["armor"], f"Shin_{suffix}", (0.55 * side, -0.04, 0.22), 0.25, 0.74)
        geo.box(lod, mats["dark"], f"Foot_{suffix}", (0.55 * side, -0.28, -0.18), (0.48, 0.68, 0.28))
    for index in range((12, 7, 3)[lod]):
        angle = math.tau * index / max(1, (12, 7, 3)[lod])
        geo.box(lod, mats["dark"], "Torso", (math.cos(angle) * 0.82, math.sin(angle) * 0.40 - 0.40, 1.12 + (index % 4) * 0.30), (0.16, 0.07, 0.28), (0, angle * 0.12, angle))
    for index in range((10, 6, 3)[lod]):
        angle = math.tau * index / max(1, (10, 6, 3)[lod])
        geo.cone(lod, mats["accent"] if index % 3 == 0 else mats["dark"], "Head", (math.cos(angle) * 0.54, math.sin(angle) * 0.42, 3.36), 0.13, 0.74 + (index % 2) * 0.20, (math.sin(angle) * 0.24, math.cos(angle) * 0.22, 0.6))
    if style not in {"tide_oracle", "lunar_leviathan"}:
        for side, suffix in ((-1, "L"), (1, "R")):
            geo.cone(lod, mats["dark"], "Head", (0.64 * side, 0.05, 3.40), 0.22, 1.30, (math.radians(8), math.radians(28 * side), 0))
    add_primary_silhouette(geo, mats, style, lod)


def add_primary_silhouette(geo: BossGeometry, mats: dict[str, str], style: str, lod: int):
    """Build the visible creature core for one boss identity.

    Only the bones, sockets, atlas, and LOD contract are shared. The actual
    body language is intentionally different: a rooted tree beast, armored
    monster, spider, jaw wheel, furnace beast, bell elemental, fish oracle,
    and winged dragon-like leviathan.
    """
    if style == "root_harrow":
        geo.cylinder(lod, mats["body"], "Torso", (0, 0.22, 1.48), 0.72, 2.86)
        geo.sphere(lod, mats["body"], "Chest", (0, 0.26, 2.32), (1.34, 0.56, 0.96))
        geo.sphere(lod, mats["armor"], "Chest", (0, -0.48, 1.68), (0.92, 0.22, 1.06))
        geo.sphere(lod, mats["dark"], "Head", (0, -0.52, 2.55), (0.72, 0.28, 0.56))
        geo.rounded_box(lod, mats["dark"], "Head", (0, -0.78, 2.38),
                        (0.84, 0.16, 0.18), bevel=0.045)
        geo.sphere(lod, mats["glow"], "Head", (-0.28, -0.80, 2.60), (0.13, 0.05, 0.08), 16, 8)
        geo.sphere(lod, mats["glow"], "Head", (0.28, -0.80, 2.60), (0.13, 0.05, 0.08), 16, 8)
        for side in (-1, 1):
            arm = "Arm_L" if side < 0 else "Arm_R"
            forearm = "Forearm_L" if side < 0 else "Forearm_R"
            hand = "Hand_L" if side < 0 else "Hand_R"
            geo.cone(lod, mats["armor"], arm, (side * 1.02, 0.18, 2.02),
                     0.25, 2.30, (0, math.radians(28 * side), math.radians(8 * side)))
            geo.cone(lod, mats["body"], forearm, (side * 1.40, -0.02, 1.36),
                     0.20, 1.62, (0, math.radians(65 * side), 0))
            geo.sphere(lod, mats["accent"], hand, (side * 1.86, -0.10, 0.92),
                       (0.27, 0.22, 0.34), 16, 8)
            branch = "RootBranch_L" if side < 0 else "RootBranch_R"
            branch_tip = "%s_2" % branch
            geo.cone(lod, mats["accent"], branch, (side * 1.70, 0.08, 1.18),
                     0.13, 1.16, (0, math.radians(72 * side), 0))
            geo.cone(lod, mats["dark"], branch_tip, (side * 1.92, 0.02, 0.78),
                     0.09, 0.82, (0, math.radians(76 * side), 0))
        for index in range((8, 5, 3)[lod]):
            angle = math.tau * index / max(1, (8, 5, 3)[lod])
            geo.cone(lod, mats["dark"] if index % 2 else mats["accent"], "Root",
                     (math.cos(angle) * 0.95, math.sin(angle) * 0.58, 0.34),
                     0.17, 1.55, (math.sin(angle) * 0.42, math.cos(angle) * 0.30, -0.12))
        for index in range((10, 6, 3)[lod]):
            angle = math.tau * index / max(1, (10, 6, 3)[lod])
            geo.cone(lod, mats["accent" if index % 3 == 0 else "dark"], "Head",
                     (math.cos(angle) * 0.56, 0.0, 3.18), 0.13, 0.96,
                     (math.sin(angle) * 0.28, math.cos(angle) * 0.24, 0.62))
    elif style == "thorn_regent":
        geo.sphere(lod, mats["body"], "Torso", (0, 0.14, 1.48), (1.56, 0.82, 1.20))
        geo.sphere(lod, mats["armor"], "Chest", (0, -0.48, 1.66), (1.42, 0.28, 1.10))
        geo.sphere(lod, mats["body"], "Pelvis", (0, 0.20, 0.70), (1.24, 0.72, 0.66))
        geo.sphere(lod, mats["dark"], "Head", (0, -0.58, 2.38), (1.02, 0.56, 0.66))
        geo.rounded_box(lod, mats["dark"], "Head", (0, -1.00, 2.15),
                        (1.28, 0.24, 0.36), bevel=0.085)
        for side in (-1, 1):
            arm = "Arm_L" if side < 0 else "Arm_R"
            forearm = "Forearm_L" if side < 0 else "Forearm_R"
            geo.sphere(lod, mats["armor"], arm, (side * 1.32, 0.02, 1.78),
                       (0.58, 0.72, 0.62))
            geo.cylinder(lod, mats["body"], forearm, (side * 1.62, -0.18, 1.12),
                         0.38, 1.28, (0, math.radians(72 * side), 0))
            geo.cone(lod, mats["accent"], f"Hand_{'L' if side < 0 else 'R'}",
                     (side * 1.86, -0.36, 0.54), 0.34, 0.82,
                     (0, math.radians(78 * side), 0))
            geo.cylinder(lod, mats["body"], f"Leg_{'L' if side < 0 else 'R'}",
                         (side * 0.82, 0.04, 0.30), 0.48, 1.10)
            geo.rounded_box(lod, mats["dark"], f"Foot_{'L' if side < 0 else 'R'}",
                            (side * 0.86, -0.38, -0.20), (0.74, 0.94, 0.36),
                            bevel=0.11)
            geo.cone(lod, mats["accent"], "Head", (side * 0.64, -0.86, 2.38),
                     0.20, 0.98, (0, math.radians(18 * side), 0))
        for index in range((12, 7, 3)[lod]):
            angle = math.tau * index / max(1, (12, 7, 3)[lod])
            geo.box(lod, mats["armor"], "Torso",
                    (math.cos(angle) * 1.20, -0.60, 1.02 + (index % 4) * 0.36),
                    (0.28, 0.16, 0.46), (0, angle * 0.15, angle))
    elif style == "briar_widow":
        geo.sphere(lod, mats["dark"], "Pelvis", (0, 0.36, 1.24), (1.58, 1.12, 1.18))
        geo.sphere(lod, mats["body"], "Torso", (0, -0.30, 2.04), (0.86, 0.70, 0.72))
        geo.sphere(lod, mats["armor"], "Head", (0, -0.82, 2.24), (0.60, 0.42, 0.44))
        geo.rounded_box(lod, mats["dark"], "Head", (0, -1.14, 2.08),
                        (0.82, 0.18, 0.16), bevel=0.045)
        for side in (-1, 1):
            geo.sphere(lod, mats["glow"], "Head", (side * 0.28, -1.18, 2.36),
                       (0.10, 0.04, 0.08), 14, 7)
            for index in range((4, 3, 2)[lod]):
                limb_bone = "Leg_L" if side < 0 else "Leg_R"
                geo.cone(lod, mats["accent" if index == 0 else "dark"], limb_bone,
                         (side * (1.18 + index * 0.22), 0.20 + index * 0.10,
                          1.82 - index * 0.42), 0.15, 1.78 - index * 0.10,
                         (0, math.radians(70 * side), math.radians(14 * side)))
                geo.cone(lod, mats["dark"], "Forearm_L" if side < 0 else "Forearm_R",
                         (side * (1.30 + index * 0.20), -0.10 + index * 0.12,
                          1.64 - index * 0.38), 0.10, 1.20,
                         (0, math.radians(78 * side), math.radians(12 * side)))
        geo.cone(lod, mats["accent"], "Mandible_L", (-0.38, -0.92, 1.98), 0.12, 0.90, (-0.1, -0.5, -0.8))
        geo.cone(lod, mats["accent"], "Mandible_R", (0.38, -0.92, 1.98), 0.12, 0.90, (-0.1, 0.5, -0.8))
    elif style == "fogmaw":
        geo.sphere(lod, mats["body"], "Torso", (0, 0.12, 1.34), (1.66, 1.06, 1.10))
        geo.torus(lod, mats["accent"], "Jaw", (0, -0.76, 1.38), 1.40, 0.28, (math.radians(90), 0, 0))
        geo.rounded_box(lod, mats["dark"], "Jaw", (0, -1.02, 1.38),
                        (1.48, 0.26, 0.74), bevel=0.10)
        geo.sphere(lod, mats["glow"], "Head", (-0.46, -1.18, 1.52), (0.15, 0.05, 0.12), 16, 8)
        geo.sphere(lod, mats["glow"], "Head", (0.46, -1.18, 1.52), (0.15, 0.05, 0.12), 16, 8)
        for index in range((12, 8, 4)[lod]):
            angle = math.tau * index / max(1, (12, 8, 4)[lod])
            geo.cone(lod, mats["dark"], "Torso", (math.cos(angle) * 1.26,
                     math.sin(angle) * 0.82, 1.12), 0.16, 1.25,
                     (math.sin(angle) * 0.32, math.cos(angle) * 0.24, 0))
        for side in (-1, 1):
            geo.cone(lod, mats["glow"], "Torso", (side * 1.48, 0.20, 1.22), 0.22, 1.80,
                     (0, math.radians(76 * side), 0))
        for index in range((8, 5, 3)[lod]):
            angle = math.tau * index / max(1, (8, 5, 3)[lod])
            geo.cone(lod, mats["glow"], "Jaw", (math.cos(angle) * 0.82, -1.04,
                     1.18 + math.sin(angle) * 0.26), 0.08, 0.42,
                     (math.sin(angle) * 0.28, 0, -0.84))
        for index in range((14, 8, 4)[lod]):
            angle = math.tau * index / max(1, (14, 8, 4)[lod])
            geo.cone(lod, mats["armor"], "Head", (math.cos(angle) * 0.88,
                     0.12 + math.sin(angle) * 0.24, 2.26), 0.11, 0.72,
                     (math.sin(angle) * 0.18, math.cos(angle) * 0.18, 0.55))
    elif style == "cinderhart":
        geo.sphere(lod, mats["body"], "Torso", (0, 0.04, 1.46), (1.56, 1.02, 1.54))
        geo.sphere(lod, mats["armor"], "Chest", (0, -0.58, 1.54), (1.34, 0.34, 1.28))
        geo.cylinder(lod, mats["glow"], "Core", (0, -0.96, 1.62), 0.82, 0.36, (math.radians(90), 0, 0))
        geo.sphere(lod, mats["dark"], "Head", (0, -0.50, 2.78), (0.82, 0.58, 0.68))
        geo.rounded_box(lod, mats["dark"], "Head", (0, -0.90, 2.56),
                        (1.02, 0.20, 0.24), bevel=0.06)
        for side in (-1, 1):
            arm = "Arm_L" if side < 0 else "Arm_R"
            hand = "Hand_L" if side < 0 else "Hand_R"
            geo.sphere(lod, mats["body"], arm, (side * 1.32, -0.02, 1.72), (0.60, 0.72, 0.70))
            geo.cylinder(lod, mats["body"], hand, (side * 1.94, -0.18, 1.20), 0.46, 1.22,
                         (0, math.radians(82 * side), 0))
            geo.sphere(lod, mats["glow"], hand, (side * 2.40, -0.18, 1.16), (0.68, 0.56, 0.70), 20, 10)
            geo.cylinder(lod, mats["body"], f"Leg_{'L' if side < 0 else 'R'}",
                         (side * 0.70, 0.04, 0.32), 0.48, 1.20)
            geo.rounded_box(lod, mats["dark"], f"Foot_{'L' if side < 0 else 'R'}",
                            (side * 0.74, -0.38, -0.22), (0.72, 0.92, 0.38),
                            bevel=0.11)
            geo.cone(lod, mats["dark"], "Head", (side * 0.62, -0.28, 3.16), 0.22, 1.30,
                     (0, math.radians(28 * side), 0))
        for index in range((12, 7, 3)[lod]):
            angle = math.tau * index / max(1, (12, 7, 3)[lod])
            geo.box(lod, mats["armor"], "Torso", (math.cos(angle) * 0.92,
                     -0.72 + math.sin(angle) * 0.26, 0.90 + (index % 6) * 0.34),
                     (0.24, 0.10, 0.42), (0, angle * 0.12, angle))
    elif style == "ash_bellower":
        geo.cone(lod, mats["armor"], "Torso", (0, 0.02, 1.50), 1.34, 2.64, (0, 0, 0))
        geo.torus(lod, mats["glow"], "Pelvis", (0, 0.02, 0.28), 1.24, 0.18, (0, 0, 0))
        geo.cylinder(lod, mats["dark"], "Chest", (0, -0.04, 2.82), 0.58, 0.58, (0, 0, 0))
        geo.sphere(lod, mats["glow"], "BellClapper", (0, -0.54, 1.54), (0.42, 0.18, 0.58), 20, 10)
        geo.sphere(lod, mats["dark"], "BellClapper", (0, -0.48, 0.72), (0.28, 0.20, 0.38), 16, 8)
        geo.cylinder(lod, mats["glow"], "BellClapper", (0, -0.22, 0.42), 0.12, 0.72,
                     (0, 0, 1))
        for index in range((14, 9, 4)[lod]):
            angle = math.tau * index / max(1, (14, 9, 4)[lod])
            geo.box(lod, mats["armor"], "Torso", (math.cos(angle) * 0.88,
                     -0.18 + math.sin(angle) * 0.40, 1.10 + (index % 4) * 0.34),
                     (0.16, 0.10, 0.44), (0, angle * 0.18, angle))
    elif style == "tide_oracle":
        # Broad fish body and snout; the lower fins float instead of using
        # humanoid legs, while the shared sockets remain available to skills.
        geo.sphere(lod, mats["body"], "Torso", (0, 0.16, 2.02), (1.36, 1.18, 0.86))
        geo.sphere(lod, mats["armor"], "Head", (0, -0.82, 2.08), (0.92, 0.62, 0.66))
        geo.rounded_box(lod, mats["dark"], "Head", (0, -1.30, 1.96),
                        (1.20, 0.24, 0.28), bevel=0.07)
        geo.sphere(lod, mats["glow"], "Head", (-0.52, -1.28, 2.30), (0.16, 0.06, 0.12), 16, 8)
        geo.sphere(lod, mats["glow"], "Head", (0.52, -1.28, 2.30), (0.16, 0.06, 0.12), 16, 8)
        geo.cone(lod, mats["body"], "Tail_1", (0, 1.22, 2.02), 0.62, 1.70, (0, 1, 0))
        geo.cone(lod, mats["accent"], "Tail_2", (0, 2.04, 2.02), 0.46, 1.28, (0, 1, 0))
        geo.cone(lod, mats["glow"], "Tail_3", (0, 2.72, 2.02), 0.30, 0.86, (0, 1, 0))
        for side in (-1, 1):
            geo.cone(lod, mats["accent"], "Fin_L" if side < 0 else "Fin_R", (side * 1.16, 0.14, 2.16),
                     0.28, 1.86, (0, math.radians(82 * side), math.radians(12 * side)))
            geo.cone(lod, mats["body"], "Fin_L" if side < 0 else "Fin_R", (side * 0.72, 0.34, 0.88),
                     0.32, 1.82, (0, math.radians(76 * side), math.radians(18 * side)))
        geo.torus(lod, mats["glow"], "Chest", (0, -0.86, 2.08), 0.68, 0.06, (math.radians(90), 0, 0))
    elif style == "lunar_leviathan":
        # Dragon-like silhouette: long neck, muzzle, horns, four claws, wing
        # roots, and an articulated tail. It is intentionally not a biped core.
        geo.sphere(lod, mats["body"], "Torso", (0, 0.26, 1.74), (1.58, 0.92, 0.94))
        geo.sphere(lod, mats["body"], "Chest", (0, -0.44, 2.30), (0.96, 0.78, 0.94))
        geo.sphere(lod, mats["dark"], "Head", (0, -0.92, 2.86), (0.88, 0.62, 0.66))
        geo.rounded_box(lod, mats["dark"], "Jaw", (0, -1.42, 2.68),
                        (1.20, 0.28, 0.34), bevel=0.08)
        geo.sphere(lod, mats["glow"], "Head", (-0.46, -1.32, 3.02), (0.14, 0.06, 0.10), 16, 8)
        geo.sphere(lod, mats["glow"], "Head", (0.46, -1.32, 3.02), (0.14, 0.06, 0.10), 16, 8)
        for side in (-1, 1):
            wing = "Wing_L" if side < 0 else "Wing_R"
            forewing = f"Wing_{'L' if side < 0 else 'R'}_1"
            geo.box(lod, mats["accent"], wing, (side * 1.52, 0.28, 2.48),
                    (0.30, 0.40, 3.70), (0, math.radians(18 * side), math.radians(12 * side)))
            geo.box(lod, mats["body"], forewing, (side * 2.06, 0.38, 2.78),
                    (0.18, 0.24, 2.72), (0, math.radians(28 * side), math.radians(12 * side)))
            geo.box(lod, mats["glow"], f"Wing_{'L' if side < 0 else 'R'}_3",
                    (side * 2.48, 0.42, 3.04), (0.12, 0.16, 1.62),
                    (0, math.radians(34 * side), math.radians(12 * side)))
            geo.cylinder(lod, mats["body"], f"Leg_{'L' if side < 0 else 'R'}",
                         (side * 0.86, 0.10, 0.80), 0.32, 1.20, (0, 0, 0))
            geo.cone(lod, mats["accent"], f"Foot_{'L' if side < 0 else 'R'}",
                     (side * 0.92, -0.26, 0.18), 0.24, 0.90, (0, math.radians(16 * side), -0.9))
            geo.cone(lod, mats["dark"], "Head", (side * 0.60, -0.90, 3.42), 0.20, 1.30,
                     (0, math.radians(26 * side), 0))
        for index in range((10, 6, 3)[lod]):
            bone = f"Tail_{min(index + 1, 5)}"
            geo.sphere(lod, mats["body"], bone, (0, 0.88 + index * 0.44,
                       1.54 - index * 0.18), (0.62 - index * 0.07, 0.42 - index * 0.04,
                       0.46 - index * 0.04), 20, 10)
        geo.cone(lod, mats["glow"], "Tail_3", (0, 3.58, 0.98), 0.16, 1.32, (0, 1, -0.15))
    add_creature_surface_details(geo, mats, style, lod)


def add_creature_surface_details(geo: BossGeometry, mats: dict[str, str], style: str, lod: int):
    """Add dense, identity-specific surface detail without restoring a shared body.

    These small scales, bark knots, plates, and bell segments keep the
    authored LOD density in range while remaining merged into five atlas
    materials and existing articulated bones.
    """
    # The exporter contract intentionally keeps LOD0/LOD1 dense enough for
    # close-up authored presentation; LOD2 drops to a compact mobile shell.
    count = (52, 56, 8)[lod]
    segments, rings = ((20, 12), (12, 8), (8, 6))[lod]
    for index in range(count):
        angle = math.tau * index / max(1, count)
        if style == "root_harrow":
            center = (math.cos(angle) * 0.72, -0.40 + math.sin(angle) * 0.34,
                      0.52 + (index % 8) * 0.29)
            radii, material, bone = (0.18, 0.10, 0.24), mats["dark"], "Torso"
        elif style == "thorn_regent":
            center = (math.cos(angle) * 1.22, -0.52 + math.sin(angle) * 0.30,
                      0.74 + (index % 6) * 0.34)
            radii, material, bone = (0.22, 0.10, 0.30), mats["armor"], "Torso"
        elif style == "briar_widow":
            center = (math.cos(angle) * 1.20, 0.22 + math.sin(angle) * 0.74,
                      0.80 + (index % 5) * 0.24)
            radii, material, bone = (0.20, 0.13, 0.17), mats["accent"], "Pelvis"
        elif style == "fogmaw":
            center = (math.cos(angle) * 1.40, -0.46, 1.38 + math.sin(angle) * 1.02)
            radii, material, bone = (0.14, 0.12, 0.20), mats["glow"], "Torso"
        elif style == "cinderhart":
            center = (math.cos(angle) * 1.02, -0.70 + math.sin(angle) * 0.28,
                      0.70 + (index % 6) * 0.34)
            radii, material, bone = (0.22, 0.10, 0.30), mats["armor"], "Torso"
        elif style == "ash_bellower":
            center = (math.cos(angle) * 0.90, -0.12 + math.sin(angle) * 0.42,
                      0.92 + (index % 6) * 0.28)
            radii, material, bone = (0.16, 0.10, 0.34), mats["armor"], "Torso"
        elif style == "tide_oracle":
            center = (math.cos(angle) * 0.98, -0.12 + math.sin(angle) * 0.78,
                      1.56 + (index % 5) * 0.23)
            radii, material, bone = (0.16, 0.12, 0.12), mats["accent"], "Torso"
        else:
            center = (math.cos(angle) * 1.02, 0.06 + math.sin(angle) * 0.48,
                      1.12 + (index % 7) * 0.26)
            radii, material, bone = (0.20, 0.13, 0.16), mats["accent"], "Torso"
        geo.sphere(lod, material, bone, center, radii, segments, rings)


def add_identity(geo: BossGeometry, mats: dict[str, str], style: str, lod: int):
    if style == "root_harrow":
        count = (20, 12, 6)[lod]
        for index in range(count):
            angle = math.tau * index / count
            geo.cone(lod, mats["dark"] if index % 3 else mats["accent"], "Root", (math.cos(angle) * 1.18, math.sin(angle) * 0.72, 0.46 + (index % 4) * 0.16), 0.12, 1.20 + (index % 3) * 0.20, (math.sin(angle) * 0.34, math.cos(angle) * 0.28, -angle))
        for side, suffix in ((-1, "L"), (1, "R")):
            geo.cone(lod, mats["glow"], f"Weapon_{suffix}", (2.22 * side, -0.12, 0.62), 0.18, 1.55, (0, math.radians(22 * side), 0))
    elif style == "thorn_regent":
        for index in range((24, 14, 7)[lod]):
            side = -1 if index % 2 == 0 else 1
            geo.box(lod, mats["armor"], "Torso", (side * (0.76 + (index % 3) * 0.11), -0.44, 0.92 + (index % 8) * 0.28), (0.28, 0.12, 0.22 + (index % 3) * 0.04), (0, side * 0.22, side * 0.12))
        for side, suffix in ((-1, "L"), (1, "R")):
            geo.rounded_box(lod, mats["glow"], f"Weapon_{suffix}",
                            (2.24 * side, -0.12, 0.52), (0.20, 0.16, 1.55),
                            (0, math.radians(12 * side), 0), bevel=0.055)
            geo.cone(lod, mats["glow"], f"Weapon_{suffix}", (2.24 * side, -0.12, -0.62), 0.20, 0.65)
    elif style == "briar_widow":
        for side in (-1, 1):
            for index in range((4, 3, 2)[lod]):
                geo.cone(lod, mats["dark"], "Leg_L" if side < 0 else "Leg_R",
                         (side * (1.0 + index * 0.18), 0.10 + index * 0.08,
                          1.95 - index * 0.38), 0.12, 1.45 - index * 0.10,
                         (0, math.radians(62 * side), math.radians(18 * side)))
        for index in range((18, 10, 5)[lod]):
            angle = math.tau * index / max(1, (18, 10, 5)[lod])
            geo.cone(lod, mats["accent"] if index % 2 else mats["glow"], "Head", (math.cos(angle) * 0.84, -0.60 + math.sin(angle) * 0.30, 2.10), 0.055, 0.72, (math.sin(angle), 0, math.cos(angle)))
        geo.torus(lod, mats["glow"], "Chest", (0, 0.28, 2.42), 1.05, 0.035, (math.radians(90), 0, 0))
    elif style == "fogmaw":
        geo.torus(lod, mats["accent"], "Torso", (0, 0.16, 1.54), 1.18, 0.16, (math.radians(90), 0, 0))
        for index in range((12, 8, 4)[lod]):
            angle = math.tau * index / max(1, (12, 8, 4)[lod])
            geo.torus(lod, mats["armor"], "Head", (0, -0.46, 2.58 + (index % 3) * 0.12), 0.62 + (index % 2) * 0.10, 0.045, (math.radians(90), angle * 0.12, angle))
        for side in (-1, 1):
            for index in range((5, 3, 2)[lod]):
                geo.cone(lod, mats["glow"] if index == 0 else mats["accent"], "Jaw",
                         (side * (1.10 + index * 0.14), 0.22, 1.30 + index * 0.34),
                         0.16, 1.15, (0, math.radians(70 * side), 0))
    elif style == "cinderhart":
        for index in range((26, 15, 7)[lod]):
            angle = math.tau * index / max(1, (26, 15, 7)[lod])
            geo.box(lod, mats["armor"], "Torso",
                    (math.cos(angle) * 0.78, -0.62 + math.sin(angle) * 0.20,
                     0.86 + (index % 7) * 0.30),
                    (0.20 + (index % 3) * 0.04, 0.08, 0.30),
                    (0, angle * 0.12, angle))
        for side, suffix in ((-1, "L"), (1, "R")):
            geo.sphere(lod, mats["glow"], f"Hand_{suffix}", (2.16 * side, -0.10, 1.16), (0.48, 0.42, 0.50), max(10, 20 - lod * 4), max(6, 10 - lod))
            for index in range((6, 4, 2)[lod]):
                geo.cone(lod, mats["accent"], f"Hand_{suffix}", (2.16 * side, -0.10, 1.16 + (index - 2) * 0.12), 0.08, 0.40, (0, math.radians(90), 0))
    elif style == "ash_bellower":
        geo.torus(lod, mats["armor"], "Torso", (0, -0.04, 1.52), 0.92, 0.17, (math.radians(90), 0, 0))
        for index in range((18, 11, 5)[lod]):
            angle = math.tau * index / max(1, (18, 11, 5)[lod])
            geo.rounded_box(lod, mats["armor"], "Torso",
                            (math.cos(angle) * 0.76, -0.18 + math.sin(angle) * 0.35,
                             1.08 + (index % 4) * 0.32), (0.12, 0.08, 0.36),
                            (0, angle * 0.18, angle), bevel=0.03)
        for index in range((12, 8, 4)[lod]):
            angle = math.tau * index / max(1, (12, 8, 4)[lod])
            geo.cone(lod, mats["glow"], "BellClapper", (math.cos(angle) * 0.90,
                     math.sin(angle) * 0.42, 0.66), 0.07, 0.64,
                     (math.sin(angle) * 0.3, math.cos(angle) * 0.2, 0))
        geo.torus(lod, mats["glow"], "Head", (0, 0.10, 3.40), 0.82, 0.07, (math.radians(90), 0, 0))
    elif style == "tide_oracle":
        for index in range((8, 5, 3)[lod]):
            angle = math.tau * index / max(1, (8, 5, 3)[lod])
            geo.sphere(lod, mats["glow"] if index % 2 else mats["accent"], "Core",
                       (math.cos(angle) * 1.36, math.sin(angle) * 0.72,
                        2.05 + math.sin(angle * 2) * 0.26), (0.20, 0.20, 0.20),
                       max(8, 16 - lod * 3), max(5, 8 - lod))
        for index in range((10, 6, 3)[lod]):
            angle = math.tau * index / max(1, (10, 6, 3)[lod])
            geo.torus(lod, mats["glow"], "Chest", (0, 0.10, 2.24), 0.86 + index * 0.035, 0.022, (math.radians(90), angle * 0.1, 0))
    elif style == "lunar_leviathan":
        for side, suffix in ((-1, "L"), (1, "R")):
            for index in range((7, 5, 3)[lod]):
                bone = f"Wing_{suffix}" if index == 0 else f"Wing_{suffix}_{min(index, 4)}"
                geo.cone(lod, mats["accent"] if index % 2 else mats["glow"], bone, (side * (1.02 + index * 0.34), 0.28, 2.24 + index * 0.16), 0.18, 1.72 - index * 0.12, (0, math.radians(70 * side), math.radians(10 * side)))
            geo.rounded_box(lod, mats["glow"], f"Weapon_{suffix}",
                            (2.22 * side, -0.12, 0.64), (0.18, 0.10, 1.46),
                            (0, math.radians(20 * side), 0), bevel=0.04)
        geo.torus(lod, mats["glow"], "Head", (0, 0.24, 2.90), 1.18, 0.08, (math.radians(68), 0, math.radians(18)))
        geo.torus(lod, mats["accent"], "Head", (0, 0.28, 2.90), 0.72, 0.035, (math.radians(68), 0, math.radians(18)))


def quat(euler_degrees):
    x, y, z = [math.radians(value) * 0.5 for value in euler_degrees]
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    return (sx * cy * cz - cx * sy * sz, cx * sy * cz + sx * cy * sz, cx * cy * sz - sx * sy * cz, cx * cy * cz + sx * sy * sz)


def _skill_motion(style, skill, sign):
    """Return a silhouette-specific anticipation/contact/recovery pose.

    Every skill keeps the same authored clip length as the combat contract,
    but its body language now comes from the creature: roots whip, spider legs
    fan, the fog jaw opens, the bell clapper swings, fins steer, and the
    leviathan breathes through its jaw and wing chain.
    """
    s = float(sign)
    if style == "root_harrow":
        if skill == "root_sword_combo":
            return {0: {"Torso": (-10, 0, s * 8), "Arm_L": (0, s * 18, -s * 28), "Arm_R": (0, -s * 18, s * 28), "Forearm_L": (0, s * 14, -s * 36), "Forearm_R": (0, -s * 14, s * 36), "RootBranch_L": (0, -s * 18, 0), "RootBranch_R": (0, s * 18, 0)}, 12: {"Torso": (-24, 0, 0), "Arm_L": (0, s * 44, -s * 78), "Arm_R": (0, -s * 44, s * 78), "Forearm_L": (0, s * 24, -s * 54), "Forearm_R": (0, -s * 24, s * 54), "RootBranch_L": (0, -s * 42, 0), "RootBranch_L_2": (0, -s * 58, 0), "RootBranch_R": (0, s * 42, 0), "RootBranch_R_2": (0, s * 58, 0)}, 24: {"Torso": (18, 0, 0), "RootBranch_L": (0, s * 20, 0), "RootBranch_R": (0, -s * 20, 0)}, 42: {}}
        return {0: {"Torso": (-8, 0, 0), "Arm_L": (-18, s * 22, -s * 12), "Arm_R": (-18, -s * 22, s * 12), "RootBranch_L": (0, -s * 24, 0), "RootBranch_R": (0, s * 24, 0)}, 12: {"Torso": (-26, 0, 0), "Chest": (0, 0, 16), "Arm_L": (-36, s * 30, -s * 18), "Arm_R": (-36, -s * 30, s * 18), "RootBranch_L": (0, -s * 56, 0), "RootBranch_L_2": (0, -s * 72, 0), "RootBranch_R": (0, s * 56, 0), "RootBranch_R_2": (0, s * 72, 0)}, 24: {"Torso": (12, 0, 0), "RootBranch_L_2": (0, s * 26, 0), "RootBranch_R_2": (0, -s * 26, 0)}, 42: {}}
    if style == "thorn_regent":
        if skill == "regent_cleave":
            return {0: {"Torso": (-8, 0, -s * 10), "Arm_L": (0, -s * 14, -s * 24), "Arm_R": (0, s * 14, s * 24), "Weapon_L": (0, -s * 28, 0), "Weapon_R": (0, s * 28, 0), "Jaw": (0, 0, -s * 8)}, 12: {"Torso": (-20, 0, 0), "Arm_L": (0, -s * 46, -s * 64), "Arm_R": (0, s * 46, s * 64), "Weapon_L": (0, -s * 82, 0), "Weapon_R": (0, s * 82, 0), "Jaw": (0, 0, s * 14)}, 24: {"Torso": (16, 0, 0), "Weapon_L": (0, s * 34, 0), "Weapon_R": (0, -s * 34, 0)}, 42: {}}
        return {0: {"Torso": (-10, 0, 0), "Arm_L": (-36, 0, -s * 18), "Arm_R": (-36, 0, s * 18), "Weapon_L": (-18, 0, 0), "Weapon_R": (-18, 0, 0)}, 12: {"Torso": (-34, 0, 0), "Arm_L": (-82, 0, -s * 26), "Arm_R": (-82, 0, s * 26), "Weapon_L": (-48, 0, 0), "Weapon_R": (-48, 0, 0)}, 24: {"Torso": (20, 0, 0), "Jaw": (0, 0, -12)}, 42: {}}
    if style == "briar_widow":
        if skill == "needle_salvo":
            return {0: {"Torso": (0, 0, s * 10), "Forearm_L": (0, s * 28, -s * 18), "Forearm_R": (0, -s * 28, s * 18), "Leg_L": (0, 0, -s * 14), "Leg_R": (0, 0, s * 14), "Mandible_L": (0, -s * 18, 0), "Mandible_R": (0, s * 18, 0)}, 12: {"Torso": (-12, 0, 0), "Forearm_L": (0, s * 70, -s * 44), "Forearm_R": (0, -s * 70, s * 44), "Leg_L": (0, 0, -s * 34), "Leg_R": (0, 0, s * 34), "Mandible_L": (0, -s * 38, 0), "Mandible_R": (0, s * 38, 0)}, 24: {"Torso": (8, 0, 0), "Leg_L": (0, 0, s * 18), "Leg_R": (0, 0, -s * 18)}, 42: {}}
        if skill == "briar_mine":
            return {0: {"Pelvis": (14, 0, 0), "Leg_L": (-20, 0, -s * 18), "Leg_R": (-20, 0, s * 18), "Torso": (12, 0, 0)}, 12: {"Pelvis": (30, 0, 0), "Leg_L": (-44, 0, -s * 34), "Leg_R": (-44, 0, s * 34), "Torso": (18, 0, 0)}, 24: {"Pelvis": (-10, 0, 0), "Leg_L": (12, 0, -s * 10), "Leg_R": (12, 0, s * 10)}, 42: {}}
        return {0: {"Torso": (-10, 0, 0), "Arm_L": (0, -s * 18, -s * 14), "Arm_R": (0, s * 18, s * 14), "Leg_L": (0, 0, -s * 20), "Leg_R": (0, 0, s * 20)}, 12: {"Torso": (-18, 0, 0), "Arm_L": (0, -s * 54, -s * 32), "Arm_R": (0, s * 54, s * 32), "Leg_L": (0, 0, -s * 40), "Leg_R": (0, 0, s * 40), "Mandible_L": (0, -s * 26, 0), "Mandible_R": (0, s * 26, 0)}, 24: {"Torso": (12, 0, 0)}, 42: {}}
    if style == "fogmaw":
        if skill == "fog_roll":
            return {0: {"Torso": (0, s * 18, -s * 12), "Jaw": (0, 0, -s * 12), "Tail_1": (0, -s * 18, 0), "Tail_2": (0, s * 24, 0)}, 12: {"Torso": (0, s * 86, 0), "Jaw": (0, 0, s * 26), "Tail_1": (0, s * 52, 0), "Tail_2": (0, -s * 72, 0), "Tail_3": (0, s * 88, 0)}, 24: {"Torso": (0, -s * 52, 0), "Jaw": (0, 0, -s * 14), "Tail_2": (0, s * 30, 0)}, 42: {}}
        return {0: {"Torso": (-12, 0, 0), "Jaw": (0, 0, -s * 18), "Tail_1": (0, -s * 20, 0)}, 12: {"Torso": (-32, 0, 0), "Jaw": (0, 0, s * 42), "Tail_1": (0, s * 36, 0), "Tail_2": (0, -s * 44, 0), "Tail_3": (0, s * 52, 0)}, 24: {"Torso": (20, 0, 0), "Jaw": (0, 0, -s * 24)}, 42: {}}
    if style == "cinderhart":
        if skill == "furnace_pound":
            return {0: {"Torso": (-14, 0, 0), "Arm_L": (-42, 0, -s * 12), "Arm_R": (-42, 0, s * 12), "Forearm_L": (-28, 0, 0), "Forearm_R": (-28, 0, 0), "Hand_L": (-24, 0, -s * 16), "Hand_R": (-24, 0, s * 16), "Core": (0, 0, -s * 18)}, 12: {"Torso": (-38, 0, 0), "Arm_L": (-92, 0, -s * 22), "Arm_R": (-92, 0, s * 22), "Forearm_L": (-68, 0, 0), "Forearm_R": (-68, 0, 0), "Hand_L": (46, 0, -s * 30), "Hand_R": (46, 0, s * 30), "Core": (0, 0, s * 34)}, 24: {"Torso": (24, 0, 0), "Hand_L": (-12, 0, s * 10), "Hand_R": (-12, 0, -s * 10), "Core": (0, 0, -s * 12)}, 42: {}}
        return {0: {"Torso": (-8, 0, s * 8), "Arm_R": (0, -s * 24, s * 24), "Forearm_R": (0, -s * 24, s * 38), "Hand_R": (0, -s * 18, s * 22), "Core": (0, 0, -s * 14)}, 12: {"Torso": (-24, 0, s * 12), "Arm_R": (0, -s * 64, s * 54), "Forearm_R": (0, -s * 44, s * 78), "Hand_R": (0, -s * 38, s * 46), "Core": (0, 0, s * 48)}, 24: {"Torso": (16, 0, 0), "Hand_R": (0, s * 16, -s * 18), "Core": (0, 0, -s * 20)}, 42: {}}
    if style == "ash_bellower":
        if skill == "ash_mortar":
            return {0: {"BellClapper": (0, -s * 20, 0), "Arm_R": (0, -s * 20, s * 18), "Core": (0, 0, -s * 12)}, 12: {"BellClapper": (0, s * 64, 0), "Arm_R": (0, -s * 62, s * 54), "Forearm_R": (0, -s * 34, s * 72), "Core": (0, 0, s * 36)}, 24: {"BellClapper": (0, -s * 42, 0), "Arm_R": (0, s * 30, -s * 24)}, 42: {}}
        if skill == "flare_wall":
            return {0: {"Arm_L": (0, -s * 20, -s * 32), "Arm_R": (0, s * 20, s * 32), "BellClapper": (0, -s * 12, 0)}, 12: {"Arm_L": (0, -s * 72, -s * 68), "Arm_R": (0, s * 72, s * 68), "BellClapper": (0, s * 28, 0)}, 24: {"Arm_L": (0, s * 36, s * 28), "Arm_R": (0, -s * 36, -s * 28)}, 42: {}}
        return {0: {"BellClapper": (0, -s * 32, 0), "Torso": (-8, 0, 0)}, 12: {"BellClapper": (0, s * 80, 0), "Torso": (-18, 0, 0), "Head": (0, 0, -s * 18)}, 24: {"BellClapper": (0, -s * 58, 0), "Torso": (12, 0, 0)}, 42: {}}
    if style == "tide_oracle":
        if skill == "tide_bolt":
            return {0: {"Head": (0, 0, -s * 10), "Fin_L": (0, -s * 22, -s * 18), "Fin_R": (0, s * 22, s * 18), "Tail_1": (0, -s * 18, 0)}, 12: {"Head": (0, 0, s * 24), "Fin_L": (0, -s * 64, -s * 42), "Fin_R": (0, s * 64, s * 42), "Core": (0, 0, s * 28), "Tail_1": (0, s * 42, 0)}, 24: {"Head": (0, 0, -s * 14), "Fin_L": (0, s * 28, s * 18), "Fin_R": (0, -s * 28, -s * 18)}, 42: {}}
        if skill == "moon_tide_ring":
            return {0: {"Torso": (-12, 0, 0), "Fin_L": (0, -s * 26, 0), "Fin_R": (0, s * 26, 0), "Tail_1": (0, -s * 24, 0)}, 12: {"Torso": (-30, 0, 0), "Fin_L": (0, -s * 70, -s * 18), "Fin_R": (0, s * 70, s * 18), "Tail_1": (0, s * 46, 0), "Tail_2": (0, -s * 58, 0), "Tail_3": (0, s * 70, 0)}, 24: {"Torso": (18, 0, 0), "Fin_L": (0, s * 34, 0), "Fin_R": (0, -s * 34, 0)}, 42: {}}
        return {0: {"Head": (0, 0, -s * 8), "Fin_L": (0, -s * 22, -s * 28), "Fin_R": (0, s * 22, s * 28), "Core": (0, 0, -s * 12)}, 12: {"Head": (0, 0, s * 20), "Fin_L": (0, -s * 78, -s * 54), "Fin_R": (0, s * 78, s * 54), "Core": (0, 0, s * 42)}, 24: {"Head": (0, 0, -s * 16), "Fin_L": (0, s * 36, s * 20), "Fin_R": (0, -s * 36, -s * 20)}, 42: {}}
    if style == "lunar_leviathan":
        if skill == "lunar_breath":
            return {0: {"Neck": (0, 0, -s * 10), "Jaw": (0, 0, -s * 24), "Wing_L": (0, 0, -s * 20), "Wing_R": (0, 0, s * 20), "Tail_1": (0, -s * 18, 0)}, 12: {"Neck": (0, 0, s * 18), "Jaw": (0, 0, s * 52), "Wing_L": (0, 0, -s * 48), "Wing_L_2": (0, 0, -s * 62), "Wing_R": (0, 0, s * 48), "Wing_R_2": (0, 0, s * 62), "Tail_1": (0, s * 40, 0), "Tail_2": (0, -s * 52, 0)}, 24: {"Jaw": (0, 0, -s * 22), "Wing_L_2": (0, 0, s * 28), "Wing_R_2": (0, 0, -s * 28)}, 42: {}}
        if skill == "crescent_sweep":
            return {0: {"Torso": (-10, 0, -s * 12), "Weapon_L": (0, -s * 26, 0), "Weapon_R": (0, s * 26, 0), "Wing_L": (0, 0, -s * 22), "Wing_R": (0, 0, s * 22)}, 12: {"Torso": (-28, 0, 0), "Weapon_L": (0, -s * 82, 0), "Weapon_R": (0, s * 82, 0), "Wing_L": (0, 0, -s * 60), "Wing_R": (0, 0, s * 60), "Wing_L_2": (0, 0, -s * 40), "Wing_R_2": (0, 0, s * 40)}, 24: {"Torso": (18, 0, 0), "Weapon_L": (0, s * 32, 0), "Weapon_R": (0, -s * 32, 0)}, 42: {}}
        return {0: {"Torso": (-12, 0, 0), "Wing_L": (0, 0, -s * 18), "Wing_R": (0, 0, s * 18), "Tail_1": (0, -s * 22, 0)}, 12: {"Torso": (-24, 0, 0), "Wing_L": (0, 0, -s * 48), "Wing_L_2": (0, 0, -s * 64), "Wing_R": (0, 0, s * 48), "Wing_R_2": (0, 0, s * 64), "Tail_1": (0, s * 42, 0), "Tail_2": (0, -s * 58, 0), "Tail_3": (0, s * 70, 0)}, 24: {"Torso": (16, 0, 0), "Wing_L_2": (0, 0, s * 30), "Wing_R_2": (0, 0, -s * 30)}, 42: {}}
    return {}


def animations(skills, style):
    idle = {"Torso": [(0, (0, 0, -2)), (0.5, (2, 0, 2)), (1.0, (0, 0, -2))], "Head": [(0, (0, 0, 3)), (0.5, (-2, 0, -3)), (1.0, (0, 0, 3))], "Arm_L": [(0, (0, -5, -4)), (0.5, (0, 5, 3)), (1.0, (0, -5, -4))], "Arm_R": [(0, (0, 5, 4)), (0.5, (0, -5, -3)), (1.0, (0, 5, 4))], "Tail_1": [(0, (0, -4, 0)), (0.5, (0, 5, 0)), (1.0, (0, -4, 0))]}
    result = [("LOC_Idle", 1.0, idle), ("LOC_Move", 0.5, {"Torso": [(0, (-4, 0, 0)), (0.25, (4, 0, 0)), (0.5, (-4, 0, 0))], "Arm_L": [(0, (16, 0, -8)), (0.25, (-16, 0, 8)), (0.5, (16, 0, -8))], "Arm_R": [(0, (-16, 0, 8)), (0.25, (16, 0, -8)), (0.5, (-16, 0, 8))], "Leg_L": [(0, (18, 0, 0)), (0.25, (-18, 0, 0)), (0.5, (18, 0, 0))], "Leg_R": [(0, (-18, 0, 0)), (0.25, (18, 0, 0)), (0.5, (-18, 0, 0))]})]
    result += [("DODGE_Roll", 0.4, {"Torso": [(0, (0, 0, -12)), (0.2, (0, 0, 20)), (0.4, (0, 0, 0))], "Head": [(0, (0, 0, -18)), (0.2, (0, 0, 28)), (0.4, (0, 0, 0))]})]
    result += [("HIT_Heavy", 0.3, {"Torso": [(0, (0, 0, -10)), (0.12, (18, 0, 0)), (0.3, (0, 0, 0))], "Head": [(0, (0, 0, -8)), (0.12, (-12, 0, 0)), (0.3, (0, 0, 0))]})]
    result += [("DEATH_Forward", 2.0, {"Torso": [(0, (0, 0, 0)), (0.8, (28, 0, 0)), (2.0, (86, 0, 0))], "Head": [(0, (0, 0, 0)), (0.8, (18, 0, 0)), (2.0, (35, 0, 0))]})]
    result += [("BOSS_PhaseShift", 1.5, {"Torso": [(0, (0, 0, -6)), (0.75, (-12, 0, 0)), (1.5, (0, 0, 0))], "Arm_L": [(0, (0, 0, -20)), (0.75, (0, -35, -56)), (1.5, (0, 0, 0))], "Arm_R": [(0, (0, 0, 20)), (0.75, (0, 35, 56)), (1.5, (0, 0, 0))]})]
    for index, skill in enumerate(skills):
        sign = -1 if index % 2 == 0 else 1
        raw_motion = _skill_motion(style, skill, sign)
        if not raw_motion:
            raw_motion = {0: {"Torso": (-8, 0, sign * 4), "Head": (0, 0, -sign * 5), "Arm_L": (0, sign * 12, -sign * 18), "Arm_R": (0, -sign * 12, sign * 18)}, 12: {"Torso": (-24, 0, 0), "Arm_L": (0, sign * 35, -sign * 70), "Arm_R": (0, -sign * 35, sign * 70)}, 24: {"Torso": (22, 0, 0)}, 42: {}}
        keyframes = {}
        for raw_frame, frame_pose in raw_motion.items():
            seconds = 0.9 * float(raw_frame) / 42.0
            for bone, rotation in frame_pose.items():
                keyframes.setdefault(bone, []).append((seconds, rotation))
        result.append((f"BOSS_{skill}", 0.9, keyframes))
    return result


class GlbWriter:
    def __init__(self):
        self.binary = bytearray()
        self.views = []
        self.accessors = []

    def _align(self):
        while len(self.binary) % 4:
            self.binary.append(0)

    def accessor(self, values, fmt, component_type, accessor_type, count, target=None, minimum=None, maximum=None):
        self._align()
        offset = len(self.binary)
        flat = [item for row in values for item in (row if isinstance(row, (tuple, list)) else (row,))]
        self.binary.extend(struct.pack("<" + fmt * len(flat), *flat))
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(self.binary) - offset}
        if target is not None:
            view["target"] = target
        view_index = len(self.views)
        self.views.append(view)
        result = {"bufferView": view_index, "componentType": component_type, "count": count, "type": accessor_type}
        if minimum is not None:
            result["min"] = list(minimum)
        if maximum is not None:
            result["max"] = list(maximum)
        accessor_index = len(self.accessors)
        self.accessors.append(result)
        return accessor_index

    def matrix_accessor(self, matrices):
        return self.accessor(matrices, "f", 5126, "MAT4", len(matrices))

    def build(self, boss_id: str, style: str, colors, skills):
        mats = {"body": "body", "armor": "armor", "accent": "accent", "glow": "glow", "dark": "dark"}
        joint_names = list(JOINT_PARENTS)
        joint_indices = {name: index for index, name in enumerate(joint_names)}
        geo = BossGeometry(joint_indices)
        for lod in range(3):
            add_common(geo, style, mats, lod)
            add_identity(geo, mats, style, lod)

        # Blender authors the source mesh Z-up, while glTF/Godot consumes a
        # Y-up scene.  Blender's normal exporter applies this basis conversion
        # through the scene root; mirror it here so the headless fallback has
        # identical grounding and socket orientation.
        nodes = [{"name": f"BossV2_{boss_id}",
                  "rotation": [-0.7071067812, 0.0, 0.0, 0.7071067812],
                  "children": []}]
        node_indices = {}
        for name in joint_names:
            node_indices[name] = len(nodes)
            nodes.append({"name": name, "translation": list(self._local_translation(name))})
        for name, parent in JOINT_PARENTS.items():
            if parent is None:
                nodes[0]["children"].append(node_indices[name])
            else:
                nodes[node_indices[parent]].setdefault("children", []).append(node_indices[name])

        inverse_bind = []
        for name in joint_names:
            x, y, z = JOINT_POSITIONS[name]
            inverse_bind.append((1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -x, -y, -z, 1))
        skin_accessor = self.matrix_accessor(inverse_bind)
        meshes = []
        for (lod, material_name, bone), group in sorted(geo.groups.items()):
            positions = self.accessor(group.vertices, "f", 5126, "VEC3", len(group.vertices), 34962,
                                      [min(v[i] for v in group.vertices) for i in range(3)],
                                      [max(v[i] for v in group.vertices) for i in range(3)])
            normals = self.accessor(group.normals, "f", 5126, "VEC3", len(group.normals), 34962)
            texcoords = self.accessor(group.uvs, "f", 5126, "VEC2", len(group.uvs), 34962)
            colors_accessor = self.accessor(group.colors, "f", 5126, "VEC4", len(group.colors), 34962)
            joints_accessor = self.accessor(group.joints, "B", 5121, "VEC4", len(group.joints), 34962)
            weights_accessor = self.accessor(group.weights, "f", 5126, "VEC4", len(group.weights), 34962)
            index_fmt, index_type = ("I", 5125) if len(group.vertices) > 65535 else ("H", 5123)
            indices_accessor = self.accessor(group.indices, index_fmt, index_type, "SCALAR", len(group.indices), 34963)
            mesh_index = len(meshes)
            meshes.append({"name": f"BossV2_{boss_id}_{material_name}_{bone}_LOD{lod}", "primitives": [{
                "attributes": {"POSITION": positions, "NORMAL": normals, "TEXCOORD_0": texcoords, "COLOR_0": colors_accessor, "JOINTS_0": joints_accessor, "WEIGHTS_0": weights_accessor},
                "indices": indices_accessor, "material": ["body", "armor", "accent", "glow", "dark"].index(material_name),
            }]})
            nodes.append({"name": f"BossV2_{boss_id}_{material_name}_{bone}_LOD{lod}", "mesh": mesh_index, "skin": 0})
            nodes[0]["children"].append(len(nodes) - 1)

        sockets = [
            ("SOCKET_Hand_R", "Hand_R", (0, 0, 0.34)), ("SOCKET_Hand_L", "Hand_L", (0, 0, 0.34)),
            ("SOCKET_VFX_Chest", "Chest", (0, -0.72, 0)), ("SOCKET_VFX_Foot_L", "Foot_L", (0, -0.28, 0)),
            ("SOCKET_VFX_Foot_R", "Foot_R", (0, -0.28, 0)), ("SOCKET_VFX_Muzzle_L", "Hand_L", (0, -0.18, -0.26)),
            ("SOCKET_VFX_Muzzle_R", "Hand_R", (0, -0.18, -0.26)), ("SOCKET_VFX_Weapon_L", "Weapon_L", (0, 0, 0)),
            ("SOCKET_VFX_Weapon_R", "Weapon_R", (0, 0, 0)), ("SOCKET_VFX_Crown", "Head", (0, -0.04, 0.70)),
        ]
        for name, bone, position in sockets:
            nodes.append({"name": name, "translation": list(position), "extras": {"bone": bone}})
            nodes[node_indices[bone]].setdefault("children", []).append(len(nodes) - 1)

        animations_json = []
        for animation_name, duration, pose in animations(skills, style):
            channels, samplers = [], []
            for bone, keyframes in pose.items():
                inputs = [frame[0] for frame in keyframes]
                outputs = [quat(frame[1]) for frame in keyframes]
                input_accessor = self.accessor(inputs, "f", 5126, "SCALAR", len(inputs))
                output_accessor = self.accessor(outputs, "f", 5126, "VEC4", len(outputs))
                sampler_index = len(samplers)
                samplers.append({"input": input_accessor, "output": output_accessor, "interpolation": "LINEAR"})
                channels.append({"sampler": sampler_index, "target": {"node": node_indices[bone], "path": "rotation"}})
            animations_json.append({"name": animation_name, "samplers": samplers, "channels": channels})

        gltf = {
            "asset": {"version": "2.0", "generator": "Embervale Boss Roster V2 headless builder"},
            "extensionsUsed": ["KHR_materials_emissive_strength"],
            "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes, "meshes": meshes,
            "images": [
                {"uri": ATLAS_URI, "mimeType": "image/png", "name": "BossV2Atlas"},
                {"uri": ORM_URI, "mimeType": "image/png", "name": "BossV2ORM"},
                {"uri": NORMAL_URI, "mimeType": "image/png", "name": "BossV2Normal"},
            ],
            "textures": [{"sampler": 0, "source": 0}, {"sampler": 0, "source": 1}, {"sampler": 0, "source": 2}],
            "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
            "materials": [self.material_json(colors[0], 0), self.material_json(colors[1], 1), self.material_json(colors[2], 2), self.material_json(colors[3], 3, emissive=True), self.material_json(tuple(max(v * 0.42, 0.008) for v in colors[0][:3]) + (1,), 4)],
            "skins": [{"inverseBindMatrices": skin_accessor, "joints": [node_indices[name] for name in joint_names], "skeleton": node_indices["Root"]}],
            "animations": animations_json,
            "buffers": [{"byteLength": len(self.binary)}], "bufferViews": self.views, "accessors": self.accessors,
        }
        json_blob = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
        while len(json_blob) % 4:
            json_blob += b" "
        self._align()
        binary_blob = bytes(self.binary)
        total = 12 + 8 + len(json_blob) + 8 + len(binary_blob)
        return struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(json_blob), b"JSON") + json_blob + struct.pack("<I4s", len(binary_blob), b"BIN\x00") + binary_blob

    def _local_translation(self, name):
        parent = JOINT_PARENTS[name]
        return JOINT_POSITIONS[name] if parent is None else sub(JOINT_POSITIONS[name], JOINT_POSITIONS[parent])

    @staticmethod
    def material_json(color, tile, emissive=False):
        result = {"name": f"BossV2Material_{tile}", "pbrMetallicRoughness": {"baseColorFactor": list(color), "baseColorTexture": {"index": 0, "texCoord": 0}, "metallicRoughnessTexture": {"index": 1, "texCoord": 0}, "metallicFactor": 1.0, "roughnessFactor": 1.0}, "occlusionTexture": {"index": 1, "texCoord": 0}, "normalTexture": {"index": 2, "texCoord": 0, "scale": 1.0}}
        if emissive:
            # The glow band of the shared atlas is a dim base with bright
            # veins, so reusing it as the emissive mask turns the former flat
            # emission into a lighting path worth reading. The image is
            # already banded to this material's UV window.
            result["emissiveTexture"] = {"index": 0, "texCoord": 0}
            result["emissiveFactor"] = list(color[:3])
            result["emissiveStrength"] = 1.5
        return result


def build_one(boss_id: str):
    style, body, armor, accent, glow, skills = BOSSES[boss_id]
    writer = GlbWriter()
    data = writer.build(boss_id, style, (body, armor, accent, glow), skills)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"boss_{boss_id}.glb"
    path.write_bytes(data)
    print(f"BUILT HEADLESS V2 {boss_id}: {path} ({len(data)} bytes)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--boss", choices=sorted(BOSSES), default="")
    args = parser.parse_args()
    if not all((TEXTURE_DIR / name).exists() for name in
               ("boss_v2_atlas.png", "boss_v2_orm.png", "boss_v2_normal.png")):
        if generate_shared_textures is None:
            raise RuntimeError("Shared Boss V2 atlas/ORM/normal generator is unavailable")
        generate_shared_textures()
    for boss_id in ([args.boss] if args.boss else BOSSES):
        build_one(boss_id)


if __name__ == "__main__":
    main()
