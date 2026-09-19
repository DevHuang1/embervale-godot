extends Node3D
class_name GatheringNode

## Data-driven gathering node. Spawns in the world, player holds interact to
## gather materials. Depletes on use, respawns after cooldown.

signal gathered(material_id: String, qty: int)

@export var material_id: String = "moss_fiber"
@export var yield_min: int = 1
@export var yield_max: int = 3
@export var gather_time: float = 2.0
@export var respawn_seconds: float = 300.0
@export var realm: String = "bramblewood"

var _depleted: bool = false
var _gathering: bool = false
var _gather_timer: float = 0.0
var _respawn_timer: float = 0.0
var _interact_prompt: Node3D
var _visual: Node3D
var _progress_ring: MeshInstance3D
var _prompt_label: Label3D
var _ritual_label: String = "Gather local material"
var opened: bool = false

const NODE_STATE_KEY_PREFIX := "gather_"

func _game_state() -> Node:
	return get_node_or_null("/root/GameState")

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("gathering")
	_build_visual()
	_build_prompt()
	_check_persistence()

func configure(mat_id: String, y_min: int, y_max: int, g_time: float, r_seconds: float, rlm: String) -> void:
	material_id = mat_id
	yield_min = y_min
	yield_max = y_max
	gather_time = g_time
	respawn_seconds = r_seconds
	realm = rlm
	_refresh_ritual_label()
	if _prompt_label != null:
		_prompt_label.text = "HOLD TO GATHER\n%s" % _ritual_label

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var style := _material_style()
	var color: Color = style.get("color", _realm_color())
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color.lightened(0.2)
	mat.emission_energy_multiplier = 0.6
	match str(style.get("shape", "stalk")):
		"mound":
			var mound := CylinderMesh.new()
			mound.top_radius = 0.42
			mound.bottom_radius = 0.5
			mound.height = 0.22
			mound.radial_segments = 8
			_add_visual_mesh(mound, mat, Vector3(0.0, 0.11, 0.0))
		"cluster":
			for i in 3:
				var berry := SphereMesh.new()
				berry.radius = 0.14
				berry.height = 0.2
				berry.radial_segments = 6
				berry.rings = 4
				_add_visual_mesh(berry, mat, Vector3(
					cos(float(i) * 2.1) * 0.16, 0.3, sin(float(i) * 2.1) * 0.16))
		"bloom":
			var bloom := SphereMesh.new()
			bloom.radius = 0.22
			bloom.height = 0.32
			bloom.radial_segments = 8
			bloom.rings = 5
			_add_visual_mesh(bloom, mat, Vector3(0.0, 0.3, 0.0))
		"log":
			var log_mesh := CylinderMesh.new()
			log_mesh.top_radius = 0.12
			log_mesh.bottom_radius = 0.15
			log_mesh.height = 0.72
			log_mesh.radial_segments = 7
			_add_visual_mesh(log_mesh, mat, Vector3(0.0, 0.15, 0.0),
				Vector3(0.0, 0.0, PI * 0.5))
		"shell":
			var shell := CylinderMesh.new()
			shell.top_radius = 0.26
			shell.bottom_radius = 0.32
			shell.height = 0.1
			shell.radial_segments = 8
			_add_visual_mesh(shell, mat, Vector3(0.0, 0.06, 0.0))
		_:
			var stalk := CylinderMesh.new()
			stalk.top_radius = 0.18
			stalk.bottom_radius = 0.22
			stalk.height = 0.35
			stalk.radial_segments = 8
			_add_visual_mesh(stalk, mat, Vector3(0.0, 0.17, 0.0))
	_progress_ring = MeshInstance3D.new()
	_progress_ring.name = "ProgressRing"
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.9, 0.8, 0.3)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.9, 0.8, 0.3)
	ring_mat.emission_energy_multiplier = 1.5
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color.a = 0.0
	_progress_ring.material_override = ring_mat
	_progress_ring.visible = false
	_visual.add_child(_progress_ring)

func _add_visual_mesh(mesh: Mesh, material: Material, offset: Vector3,
		rotation: Vector3 = Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	instance.rotation = rotation
	_visual.add_child(instance)

## Distinct silhouettes per raw material so a gather stop reads as its
## substance (clay mound, berry cluster, bloom, bark log, shell) instead of
## one generic stalk everywhere.
func _material_style() -> Dictionary:
	match material_id:
		"river_clay": return {"shape": "mound", "color": Color(0.58, 0.40, 0.31)}
		"wild_berry": return {"shape": "cluster", "color": Color(0.66, 0.18, 0.22)}
		"mire_blossom": return {"shape": "bloom", "color": Color(0.62, 0.80, 0.88)}
		"cinder_bark": return {"shape": "log", "color": Color(0.48, 0.22, 0.10)}
		"star_shell": return {"shape": "shell", "color": Color(0.58, 0.64, 0.90)}
	return {}

func _build_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.name = "PromptLabel"
	_refresh_ritual_label()
	_prompt_label.text = "HOLD TO GATHER\n%s" % _ritual_label
	_prompt_label.font_size = 18
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.position.y = 0.7
	_prompt_label.modulate = Color(0.9, 0.85, 0.6)
	_prompt_label.visible = false
	add_child(_prompt_label)
	var area := Area3D.new()
	area.name = "InteractArea"
	area.collision_layer = 0
	area.collision_mask = 1 << 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.5
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_hero_enter)
	area.body_exited.connect(_on_hero_exit)

func _refresh_ritual_label() -> void:
	var profile: Dictionary = RealmIdentityCatalog.for_realm(realm)
	_ritual_label = str(profile.get("resource_ritual", "Gather local material"))

func _process(delta: float) -> void:
	if _depleted:
		_respawn_timer -= delta
		if _respawn_timer <= 0:
			_respawn()
		return
	if _gathering:
		_gather_timer -= delta
		_update_progress_ring()
		if _gather_timer <= 0:
			_finish_gather()

func _on_hero_enter(body: Node3D) -> void:
	if body != null and body.is_in_group("player") and not _depleted:
		_prompt_label.visible = true

func _on_hero_exit(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_prompt_label.visible = false
		if _gathering:
			_cancel_gather()

func start_gather() -> void:
	if _depleted or _gathering:
		return
	_gathering = true
	_gather_timer = gather_time
	_prompt_label.visible = false
	_progress_ring.visible = true
	_progress_ring.material_override.albedo_color.a = 0.6

func interact() -> void:
	start_gather()

## Contextual-button verb: one press begins the hold ritual.
func interact_prompt() -> String:
	return "GATHER"

func _cancel_gather() -> void:
	_gathering = false
	_gather_timer = 0.0
	_progress_ring.visible = false
	_prompt_label.visible = true

func _finish_gather() -> void:
	_gathering = false
	_progress_ring.visible = false
	var qty := randi_range(yield_min, yield_max)
	var camp := get_node_or_null("/root/CampProgression")
	if camp != null and camp.has_method("gather_yield_bonus"):
		qty += int(camp.gather_yield_bonus())
	var gs := _game_state()
	if gs == null:
		return
	gs.call("add_material", material_id, qty)
	if camp != null:
		camp.record_objective(realm, "gather")
	gs.call("update_objective", "gather", material_id, qty)
	var sm := get_node_or_null("/root/StoryManager")
	if sm != null and sm.has_method("notify_objective"):
		sm.notify_objective("gather", material_id,qty)
	gs.call("check_onboarding_trigger", "gather")
	var mat_name := material_id.replace("_", " ").capitalize()
	FloatingText.spawn_on_entity(self, "+%d %s" % [qty, mat_name], Color(0.52, 0.90, 1.0), 1.2)
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_ui_blip"):
		am.play_ui_blip()
	gathered.emit(material_id, qty)
	_depleted = true
	opened = true
	_respawn_timer = respawn_seconds
	_visual.visible = false
	_prompt_label.visible = false
	_save_node_state()

func _respawn() -> void:
	_depleted = false
	opened = false
	_visual.visible = true
	_prompt_label.visible = false
	_save_node_state()

func _update_progress_ring() -> void:
	var progress := 1.0 - (_gather_timer / gather_time)
	var angle := progress * TAU
	_progress_ring.rotation.y = angle
	_progress_ring.material_override.albedo_color.a = 0.3 + progress * 0.5

func _realm_color() -> Color:
	match realm:
		"bramblewood": return Color(0.30, 0.55, 0.35)
		"mistfen": return Color(0.45, 0.50, 0.55)
		"heartwood": return Color(0.65, 0.35, 0.18)
		"moonfen": return Color(0.35, 0.40, 0.65)
		_: return Color(0.40, 0.50, 0.35)

func _save_node_state() -> void:
	var key := _state_key()
	var state: Dictionary = {}
	if _depleted:
		state = {"depleted_until": Time.get_unix_time_from_system() + _respawn_timer}
	var gs := _game_state()
	if gs != null:
		gs.call("set_gathered_node_state", key, state)

func _check_persistence() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var state: Dictionary = gs.call("get_gathered_node_state", _state_key())
	var depleted_until := float(state.get("depleted_until", 0.0))
	var remaining := depleted_until - Time.get_unix_time_from_system()
	if remaining > 0.0:
		_depleted = true
		opened = true
		_respawn_timer = remaining
		_visual.visible = false
		_prompt_label.visible = false
	elif not state.is_empty():
		gs.call("set_gathered_node_state", _state_key(), {})

func _state_key() -> String:
	return "%s%s_%s" % [NODE_STATE_KEY_PREFIX, realm, str(name)]

func is_depleted() -> bool:
	return _depleted
