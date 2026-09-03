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
var opened: bool = false

const NODE_STATE_KEY_PREFIX := "gather_"

func _game_state() -> Node:
	return get_node_or_null("/root/GameState")

func _ready() -> void:
	add_to_group("interactable")
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

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _realm_color()
	mat.emission_enabled = true
	mat.emission = _realm_color().lightened(0.2)
	mat.emission_energy_multiplier = 0.6
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.18
	mesh.bottom_radius = 0.22
	mesh.height = 0.35
	mesh.radial_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = 0.17
	_visual.add_child(mi)
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

func _build_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.text = "Gather"
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

func _cancel_gather() -> void:
	_gathering = false
	_gather_timer = 0.0
	_progress_ring.visible = false
	_prompt_label.visible = true

func _finish_gather() -> void:
	_gathering = false
	_progress_ring.visible = false
	var qty := randi_range(yield_min, yield_max)
	var gs := _game_state()
	if gs == null:
		return
	gs.call("add_material", material_id, qty)
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
