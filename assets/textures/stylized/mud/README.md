# Mud terrain surface

- Source: Generated in-session with OpenAI image generation.
- License status: Original generated project asset; no third-party source license.
- Runtime use: `assets/shaders/terrain_ground.gdshader` via `mud_tex`
  (`mud_norm`/`mud_rough` are bound when the layer compositor shader is used).
- Files: `albedo.png` (512x512), `normal.png`/`roughness.png` (1024x1024)
  (consolidated from the retired `mud_v2` shadow folder on 2026-09-18).
- Format: Opaque RGB PNG, mipmaps enabled on every channel.
- Intended realms: Bramblewood, Mistfen, and wet-ground transitions.
