"""Validate exported Boss Roster V2 GLBs without requiring Blender startup."""

from __future__ import annotations

import json
import struct
from pathlib import Path

from build_boss_roster_v2_fallback import BOSSES


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "models" / "bosses_v2"
LOD_RANGES = {0: (25_000, 55_000), 1: (12_000, 30_000), 2: (1, 13_000)}
REQUIRED_SOCKETS = {
    "SOCKET_Hand_R", "SOCKET_Hand_L", "SOCKET_VFX_Chest", "SOCKET_VFX_Foot_L",
    "SOCKET_VFX_Foot_R", "SOCKET_VFX_Muzzle_L", "SOCKET_VFX_Muzzle_R",
    "SOCKET_VFX_Weapon_L", "SOCKET_VFX_Weapon_R", "SOCKET_VFX_Crown",
}
REQUIRED_ANIMATION_PREFIXES = ("LOC_", "DODGE_", "HIT_", "DEATH_", "BOSS_")
DETAIL_BONES = {
    "root_harrow": {"RootBranch_L", "RootBranch_R", "RootBranch_L_2", "RootBranch_R_2"},
    "thorn_regent": {"Jaw", "Weapon_L", "Weapon_R"},
    "briar_widow": {"Leg_L", "Leg_R", "Mandible_L", "Mandible_R"},
    "fogmaw": {"Jaw", "Tail_3"},
    "cinderhart": {"Core", "Hand_L", "Hand_R"},
    "ash_bellower": {"BellClapper"},
    "tide_oracle": {"Fin_L", "Fin_R", "Core"},
    "lunar_leviathan": {"Jaw", "Wing_L_2", "Wing_R_2", "Tail_3"},
}


def read_document(path: Path) -> dict:
    raw = path.read_bytes()
    if raw[:4] != b"glTF" or struct.unpack_from("<I", raw, 4)[0] != 2:
        raise ValueError("not a glTF 2.0 binary")
    total = struct.unpack_from("<I", raw, 8)[0]
    offset = 12
    while offset < total:
        size, kind = struct.unpack_from("<II", raw, offset)
        payload = raw[offset + 8:offset + 8 + size]
        if kind == 0x4E4F534A:
            return json.loads(payload)
        offset += 8 + size
    raise ValueError("missing JSON chunk")


def validate_one(boss_id: str) -> list[str]:
    path = OUT / f"boss_{boss_id}.glb"
    errors: list[str] = []
    if not path.exists():
        return [f"missing {path}"]
    doc = read_document(path)
    triangles = {0: 0, 1: 0, 2: 0}
    for mesh in doc.get("meshes", []):
        name = str(mesh.get("name", ""))
        lod = next((value for value in (0, 1, 2) if name.endswith(f"LOD{value}")), None)
        if lod is None:
            errors.append(f"mesh {name} has no LOD suffix")
            continue
        for primitive in mesh.get("primitives", []):
            if primitive.get("mode", 4) != 4:
                errors.append(f"mesh {name} is not triangle-list geometry")
            indices = primitive.get("indices")
            if indices is not None:
                triangles[lod] += int(doc["accessors"][indices]["count"]) // 3
            attrs = primitive.get("attributes", {})
            for attribute in ("POSITION", "NORMAL", "TEXCOORD_0", "COLOR_0", "JOINTS_0", "WEIGHTS_0"):
                if attribute not in attrs:
                    errors.append(f"mesh {name} missing {attribute}")
    for lod, (lower, upper) in LOD_RANGES.items():
        if not lower <= triangles[lod] <= upper:
            errors.append(f"LOD{lod} triangle count {triangles[lod]} outside {lower}..{upper}")

    node_names = {str(node.get("name", "")) for node in doc.get("nodes", [])}
    errors.extend(f"missing socket {name}" for name in sorted(REQUIRED_SOCKETS - node_names))
    style = BOSSES[boss_id][0]
    errors.extend(f"missing detail bone {name}" for name in sorted(DETAIL_BONES[style] - node_names))
    if len(doc.get("skins", [])) != 1:
        errors.append(f"expected one armature skin, found {len(doc.get('skins', []))}")
    animation_names = [str(animation.get("name", "")) for animation in doc.get("animations", [])]
    for prefix in REQUIRED_ANIMATION_PREFIXES:
        if not any(name.startswith(prefix) for name in animation_names):
            errors.append(f"missing animation prefix {prefix}")
    for skill in BOSSES[boss_id][-1]:
        if f"BOSS_{skill}" not in animation_names:
            errors.append(f"missing authored skill clip BOSS_{skill}")
    detail_motion_names: set[str] = set()
    for animation in doc.get("animations", []):
        if not str(animation.get("name", "")).startswith("BOSS_"):
            continue
        for channel in animation.get("channels", []):
            target = channel.get("target", {})
            node_index = target.get("node")
            if isinstance(node_index, int) and node_index < len(doc.get("nodes", [])):
                detail_motion_names.add(str(doc["nodes"][node_index].get("name", "")))
    errors.extend(f"detail bone {name} has no skill motion" for name in sorted(DETAIL_BONES[style] - detail_motion_names))
    image_uris = {str(image.get("uri", "")) for image in doc.get("images", [])}
    if "../../textures/bosses_v2/boss_v2_atlas.png" not in image_uris:
        errors.append("missing shared atlas image")
    if "../../textures/bosses_v2/boss_v2_orm.png" not in image_uris:
        errors.append("missing shared ORM image")
    if "../../textures/bosses_v2/boss_v2_normal.png" not in image_uris:
        errors.append("missing shared normal image")
    for material in doc.get("materials", []):
        if "normalTexture" not in material:
            errors.append(f"material {material.get('name', '?')} has no normal map")
    if len(doc.get("materials", [])) > 5:
        errors.append(f"material family expanded to {len(doc['materials'])} slots")
    if errors:
        return errors
    print(f"PASS {boss_id}: LOD0={triangles[0]} LOD1={triangles[1]} LOD2={triangles[2]} sockets=10 skins=1 clips={len(animation_names)}")
    return []


def main() -> int:
    errors: list[str] = []
    for boss_id in BOSSES:
        errors.extend(f"{boss_id}: {error}" for error in validate_one(boss_id))
    if errors:
        print("BOSS ROSTER V2 VALIDATION FAILED")
        print("\n".join(f"- {error}" for error in errors))
        return 1
    print("BOSS ROSTER V2 VALIDATION PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
