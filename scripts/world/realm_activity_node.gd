extends Node3D
class_name RealmActivityNode

## Small diegetic marker used by RealmActivityDirector.  It deliberately uses
## round meshes and an interaction area only; combat and gathering contracts
## are supplied by the existing EncounterZone and GatheringNode nodes.

signal activity_started(activity_id: String)
signal activity_completed(activity_id: String, result: Dictionary)
signal activity_state_changed(activity_id: String)

var activity_definition: Dictionary = {}
var director: Node = null
var activity_id: String = ""
var _label: Label3D = null
var _visual: Node3D = null
var _available: bool = true
var _approach_visible: bool = false
var _interaction_visible: bool = false

func configure(definition: Dictionary, owner: Node) -> void:
	activity_definition = definition.duplicate(true)
	director = owner
	activity_id = str(activity_definition.get("id", ""))

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("activity_marker")
	add_to_group("activity")
	_build_visual()
	_build_interact_area()
	_refresh_label()

func activity_contract() -> Dictionary:
	return {
		"id": activity_id,
		"realm": str(activity_definition.get("realm", "")),
		"type": str(activity_definition.get("type", "")),
		"label": str(activity_definition.get("label", activity_id)),
		"position": global_position,
		"reward": (activity_definition.get("reward", {}) as Dictionary).duplicate(true),
		"persistence": str(activity_definition.get("persistence", "one_time")),
		"cooldown_seconds": float(activity_definition.get("cooldown_seconds", 0.0)),
		"soft_unlock": (activity_definition.get("soft_unlock", {}) as Dictionary).duplicate(true),
		"available": _available,
	}

func begin_activity(requested_id: String) -> bool:
	if requested_id != activity_id or director == null or not director.has_method("begin_activity"):
		return false
	var started := bool(director.call("begin_activity", requested_id))
	if started:
		activity_started.emit(activity_id)
		activity_state_changed.emit(activity_id)
	return started

func complete_activity(requested_id: String, result: Dictionary) -> bool:
	if requested_id != activity_id or director == null or not director.has_method("complete_activity"):
		return false
	var completed := bool(director.call("complete_activity", requested_id, result))
	if completed:
		activity_completed.emit(activity_id, result)
		activity_state_changed.emit(activity_id)
	return completed

func interact() -> void:
	if not _available:
		return
	begin_activity(activity_id)

func set_available(value: bool) -> void:
	_available = value
	visible = value
	_refresh_label()
	activity_state_changed.emit(activity_id)

func is_available() -> bool:
	return _available

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "ActivityVisual"
	add_child(_visual)
	var tint := _activity_color()
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.10
	stem_mesh.bottom_radius = 0.18
	stem_mesh.height = 0.65
	stem_mesh.radial_segments = 8
	stem.mesh = stem_mesh
	stem.position.y = 0.32
	stem.material_override = _emissive_material(tint, 0.55)
	_visual.add_child(stem)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.34
	ring_mesh.outer_radius = 0.48
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	ring.position.y = 0.05
	ring.material_override = _emissive_material(tint.lightened(0.18), 0.35)
	_visual.add_child(ring)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.24
	core_mesh.height = 0.48
	core_mesh.radial_segments = 8
	core_mesh.rings = 4
	core.mesh = core_mesh
	core.position.y = 0.72
	core.material_override = _emissive_material(tint.lightened(0.28), 0.72)
	_visual.add_child(core)
	_label = Label3D.new()
	_label.name = "ActivityLabel"
	_label.font_size = 18
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position.y = 1.25
	_label.modulate = tint.lightened(0.25)
	_label.visible = false
	add_child(_label)

func _build_interact_area() -> void:
	var area := Area3D.new()
	area.name = "ActivityInteractArea"
	area.collision_layer = 0
	area.collision_mask = 1 << 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.5
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body != null and body.is_in_group("player") and _available:
		_interaction_visible = true
		_refresh_label()

func _on_body_exited(body: Node3D) -> void:
	if body != null and body.is_in_group("player") and _label != null:
		_interaction_visible = false
		_refresh_label()

func set_approach_visible(value: bool) -> void:
	_approach_visible = value
	_refresh_label()

func _refresh_label() -> void:
	if _label == null:
		return
	var prompt := "INTERACT" if _interaction_visible else "AHEAD"
	_label.text = "%s\n%s" % [str(activity_definition.get("label", activity_id)).to_upper(), prompt]
	_label.visible = _available and (_approach_visible or _interaction_visible)

func _activity_color() -> Color:
	match str(activity_definition.get("type", "")):
		"combat_patrol", "combat_ambush":
			return Color(1.0, 0.42, 0.20)
		"gathering":
			return Color(0.42, 0.92, 0.58)
		"beacon":
			return Color(0.42, 0.78, 1.0)
		"cache":
			return Color(1.0, 0.76, 0.28)
		_:
			return Color(0.78, 0.66, 1.0)

func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.roughness = 0.68
	return material
