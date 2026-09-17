"""Generate the shared Boss Roster V2 surface textures.

Three deterministic, stdlib-only maps feed every canonical boss material:

* ``boss_v2_atlas.png``  - five neutral-gray detail tiles (body, armor,
  accent, glow, dark) that multiply the per-boss palette factor, so the
  authored palette still owns the hue while the atlas owns the surface.
* ``boss_v2_normal.png`` - tangent-space normals derived from the same
  height field the albedo is shaded from, kept in glTF/OpenGL green-up
  order so relief and pigment agree.
* ``boss_v2_orm.png``    - glTF ORM (AO in R, roughness in G, metallic in
  B) driven by that height field: seams darken, crevices roughen, plate
  wear picks up metal.

The five-band layout, band order, and neutral-gray convention are part of
the UV contract (fallback planar projection and Blender tile offsets both
assume them), so they never change here. Every value is deterministic: no
RNG, no dependency on wall-clock or platform.
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "textures" / "bosses_v2"
WIDTH, HEIGHT = 1024, 256
TILES = ("body", "armor", "accent", "glow", "dark")
BAND_WIDTH = WIDTH / float(len(TILES))

# Per-tile mean gray. These multiply the per-boss baseColorFactor, so they
# encode only relative material brightness (hide darker than plate, and so
# on) and stay close to the historical values the palette was tuned against.
TILE_GAIN = {"body": 0.88, "armor": 0.98, "accent": 0.86, "glow": 0.72, "dark": 0.62}

# glTF ORM banding per tile: roughness, metallic, and how strongly the
# height field drives each. Authored here rather than in Blender so the
# headless fallback and the editable source agree by construction.
TILE_ORM = {
    "body": (0.82, 0.05),
    "armor": (0.60, 0.28),
    "accent": (0.54, 0.08),
    "glow": (0.34, 0.02),
    "dark": (0.90, 0.03),
}

NORMAL_STRENGTH = 3.2


def _chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)


def _png(pixels: bytearray) -> bytes:
    scanlines = bytearray()
    stride = WIDTH * 4
    for row in range(HEIGHT):
        scanlines.append(0)
        start = row * stride
        scanlines.extend(pixels[start:start + stride])
    header = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + _chunk(b"IHDR", header) + _chunk(b"IDAT", zlib.compress(bytes(scanlines), 9)) + _chunk(b"IEND", b"")


# ── deterministic value noise ────────────────────────────────────────────────

def _hash2(x: int, y: int, seed: int) -> float:
    h = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge1 <= edge0:
        return 1.0 if value >= edge1 else 0.0
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def _clamp01(value: float) -> float:
    return 0.0 if value < 0.0 else (1.0 if value > 1.0 else value)


def _value_noise(x: float, y: float, seed: int) -> float:
    x0 = math.floor(x)
    y0 = math.floor(y)
    tx = x - x0
    ty = y - y0
    sx = tx * tx * (3.0 - 2.0 * tx)
    sy = ty * ty * (3.0 - 2.0 * ty)
    n00 = _hash2(x0, y0, seed)
    n10 = _hash2(x0 + 1, y0, seed)
    n01 = _hash2(x0, y0 + 1, seed)
    n11 = _hash2(x0 + 1, y0 + 1, seed)
    return _lerp(_lerp(n00, n10, sx), _lerp(n01, n11, sx), sy)


def _fbm(x: float, y: float, seed: int, octaves: int = 3) -> float:
    total = 0.0
    amplitude = 0.5
    norm = 0.0
    for octave in range(octaves):
        total += _value_noise(x, y, seed + octave * 7919) * amplitude
        norm += amplitude
        x *= 2.03
        y *= 2.03
        amplitude *= 0.5
    return total / max(norm, 1e-6)


# ── per-tile detail fields ───────────────────────────────────────────────────
# Each returns (height in 0..1, albedo gray). Height is the single source for
# the normal map, the ORM bands, and the albedo shading, so a bright seam is
# always a recessed seam and never a contradiction.

def _detail_body(bx: float, y: float) -> tuple[float, float]:
    warp_x = (_fbm(bx * 0.05, y * 0.05, 11) - 0.5) * 22.0
    warp_y = (_fbm(bx * 0.04 + 5.0, y * 0.04, 12) - 0.5) * 16.0
    grain = _fbm((bx + warp_x) * 0.42, (y + warp_y) * 0.09, 13, 4)
    fibre = _fbm((bx + warp_x * 1.6) * 1.25, (y + warp_y) * 0.16, 14)
    crack = 1.0 - _smoothstep(0.020, 0.055, abs(_fbm(bx * 0.11, y * 0.11, 15) - 0.5))
    height = _clamp01(0.34 + 0.52 * grain + 0.12 * (fibre - 0.5) - 0.30 * crack)
    shade = 0.88 + 0.10 * (grain - 0.5) + 0.05 * (fibre - 0.5) - 0.16 * crack
    return height, shade


def _detail_armor(bx: float, y: float) -> tuple[float, float]:
    cell_w, cell_h = 54.0, 70.0
    lx = bx % cell_w
    ly = y % cell_h
    seam = min(lx, cell_w - lx, ly, cell_h - ly)
    plate = _smoothstep(0.6, 5.0, seam)
    brush = _fbm(bx * 0.75, y * 0.14, 22)
    corner = math.hypot(min(lx, cell_w - lx) - 4.0, min(ly, cell_h - ly) - 4.0)
    rivet = 1.0 - _smoothstep(2.2, 4.6, corner)
    scuff = _smoothstep(0.55, 0.80, _fbm(bx * 0.28 + 9.0, y * 0.22, 23))
    sheen = _smoothstep(6.0, 26.0, seam)
    height = _clamp01(0.26 + 0.46 * plate + 0.14 * (brush - 0.5) + 0.30 * rivet - 0.08 * scuff)
    shade = 0.94 + 0.07 * (brush - 0.5) - 0.20 * (1.0 - plate) + 0.05 * sheen + 0.12 * plate * scuff + 0.08 * rivet
    return height, shade


def _detail_accent(bx: float, y: float) -> tuple[float, float]:
    flow = (_fbm(bx * 0.02, y * 0.02, 41) - 0.5) * 24.0
    strand = abs(math.sin((bx + flow) * 0.16 + y * 0.02))
    weave = _fbm(bx * 0.60, y * 0.60, 42, 2)
    node = _smoothstep(0.62, 0.78, _fbm(bx * 0.11 + 4.0, y * 0.14, 43))
    height = _clamp01(0.28 + 0.34 * (1.0 - strand) + 0.18 * weave + 0.24 * node)
    shade = 0.86 + 0.10 * (0.5 - strand) + 0.05 * (weave - 0.5) + 0.08 * node
    return height, shade


def _detail_glow(bx: float, y: float) -> tuple[float, float]:
    field = _fbm(bx * 0.03, y * 0.02, 51)
    vein = 1.0 - _smoothstep(0.012, 0.060, abs(field - 0.5))
    branch = _smoothstep(0.20, 0.72, _fbm(bx * 0.10, y * 0.10, 52, 2))
    height = _clamp01(0.28 + 0.56 * vein + 0.14 * (field - 0.5) + 0.06 * branch)
    shade = 0.58 + 0.34 * vein + 0.10 * branch + 0.06 * (field - 0.5)
    return height, shade


def _detail_dark(bx: float, y: float) -> tuple[float, float]:
    cell = 21.0
    fx = bx / cell
    fy = y / cell
    ix = math.floor(fx)
    iy = math.floor(fy)
    nearest = 10.0
    second = 10.0
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            px = ox + _hash2(ix + ox, iy + oy, 61)
            py = oy + _hash2(ix + ox, iy + oy, 62)
            distance = math.hypot(fx - (ix + px), fy - (iy + py))
            if distance < nearest:
                second = nearest
                nearest = distance
            elif distance < second:
                second = distance
    edge = _clamp01((second - nearest) * 1.5)
    hide = _fbm(bx * 0.50, y * 0.50, 63, 2)
    height = _clamp01(0.22 + 0.56 * edge + 0.14 * hide)
    shade = 0.62 + 0.10 * edge + 0.05 * (hide - 0.5)
    return height, shade


_TILE_DETAIL = {
    "body": _detail_body,
    "armor": _detail_armor,
    "accent": _detail_accent,
    "glow": _detail_glow,
    "dark": _detail_dark,
}


def _sample(x: int, y: int) -> tuple[float, float, int]:
    tile_index = min(len(TILES) - 1, int(x / BAND_WIDTH))
    tile = TILES[tile_index]
    bx = x - tile_index * BAND_WIDTH
    height, shade = _TILE_DETAIL[tile](bx, float(y))
    albedo = _clamp01(shade * TILE_GAIN[tile])
    return height, albedo, tile_index


def build_fields() -> tuple[list[float], list[float], list[int]]:
    heights = [0.0] * (WIDTH * HEIGHT)
    albedo = [0.0] * (WIDTH * HEIGHT)
    tiles = [0] * (WIDTH * HEIGHT)
    for y in range(HEIGHT):
        row = y * WIDTH
        for x in range(WIDTH):
            height, shade, tile_index = _sample(x, y)
            heights[row + x] = height
            albedo[row + x] = shade
            tiles[row + x] = tile_index
    return heights, albedo, tiles


def _write_atlas(albedo: list[float]) -> None:
    pixels = bytearray(WIDTH * HEIGHT * 4)
    for index in range(WIDTH * HEIGHT):
        channel = int(round(albedo[index] * 255.0))
        offset = index * 4
        pixels[offset:offset + 4] = bytes((channel, channel, channel, 255))
    (OUT / "boss_v2_atlas.png").write_bytes(_png(pixels))


def _write_normal(heights: list[float]) -> None:
    pixels = bytearray(WIDTH * HEIGHT * 4)
    for y in range(HEIGHT):
        row = y * WIDTH
        up_row = (y - 1 if y > 0 else 0) * WIDTH
        down_row = (y + 1 if y < HEIGHT - 1 else HEIGHT - 1) * WIDTH
        for x in range(WIDTH):
            left = heights[row + (x - 1 if x > 0 else 0)]
            right = heights[row + (x + 1 if x < WIDTH - 1 else WIDTH - 1)]
            up = heights[up_row + x]
            down = heights[down_row + x]
            nx = -(right - left) * NORMAL_STRENGTH
            ny = -(down - up) * NORMAL_STRENGTH
            length = math.sqrt(nx * nx + ny * ny + 1.0)
            offset = (row + x) * 4
            pixels[offset] = int(round((nx / length * 0.5 + 0.5) * 255.0))
            pixels[offset + 1] = int(round((ny / length * 0.5 + 0.5) * 255.0))
            pixels[offset + 2] = int(round((1.0 / length * 0.5 + 0.5) * 255.0))
            pixels[offset + 3] = 255
    (OUT / "boss_v2_normal.png").write_bytes(_png(pixels))


def _write_orm(heights: list[float], tiles: list[int]) -> None:
    pixels = bytearray(WIDTH * HEIGHT * 4)
    for index in range(WIDTH * HEIGHT):
        tile = TILES[tiles[index]]
        height = heights[index]
        base_rough, base_metal = TILE_ORM[tile]
        ao = _clamp01(0.58 + 0.42 * height)
        roughness = _clamp01(base_rough + 0.12 * (0.5 - height))
        metallic = _clamp01(base_metal * (0.55 + 0.55 * height))
        offset = index * 4
        pixels[offset] = int(round(ao * 255.0))
        pixels[offset + 1] = int(round(roughness * 255.0))
        pixels[offset + 2] = int(round(metallic * 255.0))
        pixels[offset + 3] = 255
    (OUT / "boss_v2_orm.png").write_bytes(_png(pixels))


def generate() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    heights, albedo, tiles = build_fields()
    _write_atlas(albedo)
    _write_normal(heights)
    _write_orm(heights, tiles)
    print(f"BUILT SHARED BOSS V2 TEXTURES: {OUT}")


if __name__ == "__main__":
    generate()
