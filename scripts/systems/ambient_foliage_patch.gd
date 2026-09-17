extends MultiMeshInstance3D
class_name AmbientFoliagePatch

## Lightweight realm dressing for streamed chunks.
## One MultiMesh keeps the foliage detail to a single draw call per chunk.

# Use one transparent foliage silhouette per billboard.  The old full-sheet
# atlas was rendered as a single card, so its rectangular atlas bounds showed
# up as beige squares scattered across the ground at distance.
const FOLIAGE_TEXTURE: Texture2D = preload("res://assets/ambient/kenney_foliage_sprites/PNG/Flat/sprite_0001.png")
const REALM_TINTS: Dictionary = {
	"whispergrove": Color(0.78, 1.0, 0.70, 1.0),
	"bramblewood": Color(0.63, 0.82, 0.43, 1.0),
	"mistfen": Color(0.43, 0.72, 0.68, 1.0),
	"heartwood": Color(0.92, 0.62, 0.28, 1.0),
	"moonfen": Color(0.50, 0.67, 0.92, 1.0),
}

@export_range(0, 64, 1) var max_instances: int = 24
@export var realm_id: String = "whispergrove"
@export var patch_size: Vector2 = Vector2(58.0, 58.0)
@export var seed_value: int = 1
@export var wind_enabled: bool = true
var terrain_relief: TerrainRelief

func setup(p_realm_id: String, p_seed: int, p_max_instances: int = 24,
		p_terrain_relief: TerrainRelief = null) -> void:
	realm_id = p_realm_id
	seed_value = p_seed
	max_instances = clampi(p_max_instances, 0, 64)
	terrain_relief = p_terrain_relief
	_build()

func _ready() -> void:
	if multimesh == null:
		_build()

func set_coverage_range(range_begin: float, range_end: float) -> void:
	visibility_range_begin = maxf(0.0, range_begin)
	visibility_range_end = maxf(visibility_range_begin + 1.0, range_end)
	visibility_range_end_margin = 18.0
	set_meta("coverage_min", visibility_range_begin)
	set_meta("coverage_max", visibility_range_end)
	set_meta("source_layer", "ambient_detail")

func _build() -> void:
	var count := clampi(max_instances, 0, 64)
	if count == 0:
		multimesh = null
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 1.2)
	quad.orientation = PlaneMesh.FACE_Z
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.35
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = FOLIAGE_TEXTURE
	material.albedo_color = REALM_TINTS.get(realm_id, REALM_TINTS["whispergrove"])
	quad.material = material

	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = quad
	batch.instance_count = count
	for index in range(count):
		var local_position := Vector3(
			rng.randf_range(-patch_size.x * 0.5, patch_size.x * 0.5),
			0.52,
			rng.randf_range(-patch_size.y * 0.5, patch_size.y * 0.5))
		if terrain_relief != null:
			var world_xz := Vector2(position.x + local_position.x,
				position.z + local_position.z)
			local_position.y = terrain_relief.sample_surface_height(
				Vector3(world_xz.x, 0.0, world_xz.y)) + 0.52
		var scale := rng.randf_range(0.42, 0.92)
		var transform := Transform3D(Basis.IDENTITY.scaled(Vector3(scale, scale, scale)), local_position)
		batch.set_instance_transform(index, transform)
		batch.set_instance_color(index, Color(1.0, 1.0, 1.0, rng.randf_range(0.72, 1.0)))
	multimesh = batch
	set_coverage_range(0.0, 145.0)
