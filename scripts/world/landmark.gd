extends Node3D
class_name Landmark

## Handcrafted landmark with discovery tracking and gameplay purpose.

signal discovered(landmark_id: String)

@export var landmark_id: String = "watchtower"
@export var display_name: String = "Abandoned Watchtower"
@export var purpose: String = "loot"
@export var realm: String = "bramblewood"

var _discovered: bool = false
var _interact_area: Area3D
var _label: Label3D

func _ready() -> void:
	_build_visual()
	_build_interact()
	_check_discovery()

func configure(id: String, name: String, p: String, rlm: String) -> void:
	landmark_id = id
	display_name = name
	purpose = p
	realm = rlm

func _build_visual() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _realm_color()
	mat.emission_enabled = true
	mat.emission = _realm_color().lightened(0.3)
	mat.emission_energy_multiplier = 0.8
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.2, 0.8, 1.2)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = 0.4
	add_child(mi)
	_label = Label3D.new()
	_label.text = display_name
	_label.font_size = 16
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 1.2
	_label.modulate = Color(0.9, 0.85, 0.6)
	_label.visible = false
	add_child(_label)

func _build_interact() -> void:
	_interact_area = Area3D.new()
	_interact_area.name = "InteractArea"
	_interact_area.collision_layer = 0
	_interact_area.collision_mask = 1 << 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.0
	shape.shape = sphere
	_interact_area.add_child(shape)
	add_child(_interact_area)
	_interact_area.body_entered.connect(_on_hero_enter)
	_interact_area.body_exited.connect(_on_hero_exit)

func _on_hero_enter(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_label.visible = true
		if not _discovered:
			_discover()

func _on_hero_exit(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_label.visible = false

func _discover() -> void:
	_discovered = true
	GameState.discovered_landmarks[landmark_id] = true
	GameState.save_game()
	discovered.emit(landmark_id)
	FloatingText.spawn_on_entity(get_tree().get_first_node_in_group("player"),
		"Discovered: %s" % display_name, Color(0.9, 0.85, 0.3), 1.5)

func _check_discovery() -> void:
	_discovered = GameState.discovered_landmarks.get(landmark_id, false)

func interact() -> void:
	match purpose:
		"loot":
			var gold := randi_range(15, 35)
			GameState.add_gold(gold, "Found %d gold at the %s." % [gold, display_name])
		"heal":
			GameState.heal(GameState.max_hp)
			FloatingText.spawn_on_entity(get_tree().get_first_node_in_group("player"),
				"Fully healed", Color(0.4, 1.0, 0.4), 1.2)
		"materials":
			GameState.add_material("iron_shard", 3)
			GameState.add_material("crystal_fragment", 1)
			FloatingText.spawn_on_entity(get_tree().get_first_node_in_group("player"),
				"+3 Iron Shard, +1 Crystal Fragment", Color(0.52, 0.90, 1.0), 1.2)
		"crafting":
			FloatingText.spawn_on_entity(get_tree().get_first_node_in_group("player"),
				"Checkpoint forge available", Color(0.9, 0.85, 0.3), 1.2)

func _realm_color() -> Color:
	match realm:
		"bramblewood": return Color(0.35, 0.50, 0.30)
		"mistfen": return Color(0.45, 0.50, 0.55)
		"heartwood": return Color(0.60, 0.35, 0.20)
		"moonfen": return Color(0.35, 0.40, 0.60)
		_: return Color(0.40, 0.50, 0.35)
