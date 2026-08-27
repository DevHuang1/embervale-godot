class_name TerrainWear
extends Node

## === Persistent ground wear (session-only) ===
## A low-res R8 wear map spanning the realm bounds. Impacts, dashes and
## footsteps splat soft kernels; terrain_ground.gdshader samples it via the
## `world_wear_map` global to trodden paths darkened and roughened.
## Uploads are throttled; the image is the source of truth for tests.

const RES := 256
const UPLOAD_MIN_INTERVAL := 0.12
const BOUNDS_MIN := -300.0
const BOUNDS_SIZE := 600.0

var image: Image = null
var texture: ImageTexture = null
var _dirty := false
var _since_upload := 0.0


func _ready() -> void:
	image = Image.create(RES, RES, false, Image.FORMAT_R8)
	image.fill(Color(0, 0, 0))
	texture = ImageTexture.create_from_image(image)
	RenderingServer.global_shader_parameter_set("world_wear_map", texture)


func _process(delta: float) -> void:
	if not _dirty:
		return
	_since_upload += delta
	if _since_upload >= UPLOAD_MIN_INTERVAL:
		_since_upload = 0.0
		_dirty = false
		if texture != null:
			texture.update(image)


## Splat a soft round kernel at a world position.
func record(world_pos: Vector3, radius: float = 1.2, strength: float = 0.5) -> void:
	if image == null:
		return
	var uv := world_to_uv(Vector2(world_pos.x, world_pos.z))
	var r_px := maxf(radius / BOUNDS_SIZE * float(RES), 1.0)
	var cx := int(uv.x * float(RES))
	var cy := int(uv.y * float(RES))
	var ir := int(ceil(r_px))
	for y in range(cy - ir, cy + ir + 1):
		for x in range(cx - ir, cx + ir + 1):
			if x < 0 or y < 0 or x >= RES or y >= RES:
				continue
			var d := Vector2(x - cx, y - cy).length() / r_px
			if d > 1.0:
				continue
			var k := (1.0 - smoothstep(0.35, 1.0, d)) * strength
			var old := image.get_pixel(x, y).r
			image.set_pixel(x, y, Color(minf(old + k * 0.08, 1.0), 0, 0))
	_dirty = true


func reset() -> void:
	if image == null:
		return
	image.fill(Color(0, 0, 0))
	_dirty = true
	if texture != null:
		texture.update(image)


static func world_to_uv(pos: Vector2) -> Vector2:
	var u := (pos.x - BOUNDS_MIN) / BOUNDS_SIZE
	var v := (pos.y - BOUNDS_MIN) / BOUNDS_SIZE
	return Vector2(clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0))
