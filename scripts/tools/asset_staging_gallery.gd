extends Node3D
class_name AssetStagingGallery

## Bounded review gallery for imported assets. It is intentionally isolated from
## gameplay scenes so scale, silhouette, material response, and provenance can
## be reviewed before an asset receives a production use case.

const REVIEW_ASSETS: Array[Dictionary] = [
	{"label": "NATURE PROP", "path": "res://assets/models/kenney_nature/Models/tree_detailed.fbx"},
	{"label": "GRAVEYARD PROP", "path": "res://assets/models/kenney_graveyard/Models/altar-stone.fbx"},
	{"label": "FOLIAGE SPRITE", "path": "res://assets/ambient/kenney_foliage_sprites/PNG/Flat/sprite_0001.png"},
	{"label": "SURVIVAL PROP", "path": "res://assets/models/kenney_survival/Models/tent.fbx"},
	{"label": "REALM CRYSTAL", "path": "res://assets/models/kenney_tower_defense/Models/detail-crystal.fbx"},
	{"label": "DUNGEON CHARACTER", "path": "res://assets/models/kenney_mini_dungeon/Models/character-human.fbx"},
	{"label": "WEAPON", "path": "res://assets/models/weapons/quaternius/Sword.fbx"},
	{"label": "SHIELD", "path": "res://assets/models/weapons/quaternius/Shield_Heater.fbx"},
]
const ASSET_CATALOG := preload("res://scripts/systems/asset_intake_catalog.gd")

@export var review_all_downloads: bool = false
@export var preview_animation: String = "idle"
var _review_list: Array[Dictionary] = []

var _review_assets_loaded: int = 0
var _telemetry_label: Label3D = null
var _telemetry_timer: float = 0.0

func _ready() -> void:
	_review_list = _build_review_list()
	_build_lighting()
	_build_floor()
	_build_gallery()
	_build_camera()
	_build_telemetry()

func _process(delta: float) -> void:
	if _telemetry_label == null:
		return
	_telemetry_timer += delta
	if _telemetry_timer < 0.5:
		return
	_telemetry_timer = 0.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var memory_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	_telemetry_label.text = "STAGING TELEMETRY\n%d / %d ASSETS LOADED · %d DRAW CALLS · %.1f MB" % [
		_review_assets_loaded, _review_list.size(), draws, memory_mb]

func _build_review_list() -> Array[Dictionary]:
	if not review_all_downloads:
		return REVIEW_ASSETS.duplicate(true)
	var result: Array[Dictionary] = []
	for item in ASSET_CATALOG.inventory_downloaded_assets():
		var path := str(item.get("path", ""))
		result.append({
			"label": path.get_file().get_basename().to_upper(),
			"path": path,
			"classification": str(item.get("classification", "REVIEW_ONLY")),
		})
	return result

func _build_telemetry() -> void:
	_telemetry_label = Label3D.new()
	_telemetry_label.name = "ReviewTelemetry"
	_telemetry_label.text = "STAGING TELEMETRY\n0 / %d ASSETS LOADED" % _review_list.size()
	_telemetry_label.font_size = 20
	_telemetry_label.modulate = Color(0.72, 0.88, 0.80)
	_telemetry_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_telemetry_label.position = Vector3(0.0, 3.4, 0.0)
	add_child(_telemetry_label)

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "ReviewCamera"
	camera.position = Vector3(0.0, 6.0, 14.5)
	camera.fov = 42.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)

func _build_lighting() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.025, 0.026)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.32, 0.37, 0.40)
	environment.ambient_light_energy = 0.65
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.name = "ReviewKeyLight"
	key.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	key.light_color = Color(1.0, 0.86, 0.68)
	key.light_energy = 1.15
	key.shadow_enabled = true
	add_child(key)

func _build_floor() -> void:
	var floor := MeshInstance3D.new()
	floor.name = "ScaleFloor"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(14.0, 0.20, 10.0)
	floor.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.10, 0.12, 0.12)
	material.roughness = 0.82
	floor.material_override = material
	floor.position.y = -0.1
	add_child(floor)

func _build_gallery() -> void:
	for index in _review_list.size():
		var entry := _review_list[index]
		var pedestal := MeshInstance3D.new()
		pedestal.name = "Pedestal_%02d" % index
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.65
		cylinder.bottom_radius = 0.72
		cylinder.height = 0.35
		pedestal.mesh = cylinder
		var column := index % 8
		var row := index / 8
		pedestal.position = Vector3(-13.3 + float(column) * 3.8, 0.18, -2.0 + float(row) * 4.0)
		var pedestal_mat := StandardMaterial3D.new()
		pedestal_mat.albedo_color = Color(0.20, 0.22, 0.23)
		pedestal_mat.roughness = 0.55
		pedestal.material_override = pedestal_mat
		add_child(pedestal)
		var packed := load(str(entry.get("path", ""))) as PackedScene
		if packed != null:
			var asset := packed.instantiate() as Node3D
			if asset != null:
				asset.name = "Asset_%02d" % index
				asset.position = pedestal.position + Vector3(0, 0.35, 0)
				asset.scale = Vector3.ONE * 0.9
				add_child(asset)
				_preview_animation(asset)
				_review_assets_loaded += 1
		else:
			var texture := load(str(entry.get("path", ""))) as Texture2D
			if texture != null:
				var sprite := Sprite3D.new()
				sprite.name = "Asset_%02d" % index
				sprite.texture = texture
				sprite.pixel_size = 0.006
				sprite.position = pedestal.position + Vector3(0, 0.7, 0)
				add_child(sprite)
				_review_assets_loaded += 1
			else:
				var audio_stream := load(str(entry.get("path", ""))) as AudioStream
				if audio_stream != null:
					var audio_preview := AudioStreamPlayer3D.new()
					audio_preview.name = "AudioAsset_%02d" % index
					audio_preview.stream = audio_stream
					audio_preview.position = pedestal.position + Vector3(0, 0.7, 0)
					add_child(audio_preview)
					_review_assets_loaded += 1
		_add_collision_review_bounds(index, pedestal.position + Vector3(0, 0.8, 0))
		var label := Label3D.new()
		label.name = "Label_%02d" % index
		label.text = "%s\n%s" % [str(entry.get("label", "ASSET")), str(entry.get("classification", "REVIEW_ONLY"))]
		label.font_size = 22
		label.modulate = Color(0.85, 0.90, 0.88)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = pedestal.position + Vector3(0, 1.55, 0)
		add_child(label)

func _preview_animation(asset: Node3D) -> void:
	var players := asset.find_children("*", "AnimationPlayer", true, false)
	for player_node in players:
		var player := player_node as AnimationPlayer
		if player == null:
			continue
		var clips := player.get_animation_list()
		if clips.is_empty():
			continue
		var clip := preview_animation if preview_animation in clips else str(clips[0])
		player.play(clip)
		return

func _add_collision_review_bounds(index: int, center: Vector3) -> void:
	var bounds := MeshInstance3D.new()
	bounds.name = "CollisionBounds_%02d" % index
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners: Array[Vector3] = []
	for y in [-0.7, 0.7]:
		for z in [-0.7, 0.7]:
			for x in [-0.7, 0.7]:
				corners.append(Vector3(x, y, z))
	var edges := [[0, 1], [0, 2], [1, 3], [2, 3],
		[4, 5], [4, 6], [5, 7], [6, 7],
		[0, 4], [1, 5], [2, 6], [3, 7]]
	for edge in edges:
		mesh.surface_add_vertex(corners[int(edge[0])])
		mesh.surface_add_vertex(corners[int(edge[1])])
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.35, 0.85, 0.72, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bounds.mesh = mesh
	bounds.material_override = material
	bounds.position = center
	add_child(bounds)
