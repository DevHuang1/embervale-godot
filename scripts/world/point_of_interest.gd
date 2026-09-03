extends Node3D
class_name PointOfInterest

## Lightweight exploration point with interaction prompt and reward.

@export var poi_id: String = "lore_stone"
@export var poi_type: String = "lore"
@export var display_name: String = "Ancient Stone"
@export var realm: String = "bramblewood"

var _claimed: bool = false
var _label: Label3D
var _interact_area: Area3D

func _ready() -> void:
	_build_visual()
	_build_interact()
	_check_claimed()

func configure(id: String, type: String, name: String, rlm: String) -> void:
	poi_id = id
	poi_type = type
	display_name = name
	realm = rlm

func _build_visual() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.55, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.45, 0.3)
	mat.emission_energy_multiplier = 0.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position.y = 0.25
	add_child(mi)
	_label = Label3D.new()
	_label.text = "Examine"
	_label.font_size = 14
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 0.8
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
	sphere.radius = 2.0
	shape.shape = sphere
	_interact_area.add_child(shape)
	add_child(_interact_area)
	_interact_area.body_entered.connect(_on_hero_enter)
	_interact_area.body_exited.connect(_on_hero_exit)

func _on_hero_enter(body: Node3D) -> void:
	if body != null and body.is_in_group("player") and not _claimed:
		_label.visible = true

func _on_hero_exit(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_label.visible = false

func interact() -> void:
	if _claimed:
		return
	_claimed = true
	_label.visible = false
	GameState.set("poi_%s" % poi_id, true) if GameState.has_method("set") else null
	match poi_type:
		"lore":
			FloatingText.spawn_on_entity(get_tree().get_first_node_in_group("player"),
				"Ancient inscription reveals forgotten knowledge", Color(0.7, 0.65, 0.5), 1.5)
		"reward":
			var gold := randi_range(10, 25)
			GameState.add_gold(gold, "Found %d gold." % gold)
		"materials":
			GameState.add_material("moss_fiber", 2)
			GameState.add_material("bramble_wood", 1)
			FloatingText.spawn_on_entity(get_tree().get_first_node_in_group("player"),
				"+2 Moss Fiber, +1 Bramblewood", Color(0.52, 0.90, 1.0), 1.2)
		"map_reveal":
			FloatingText.spawn_on_entity(get_tree().get_first_node_in_group("player"),
				"Nearby area revealed on map", Color(0.9, 0.85, 0.3), 1.2)

func _check_claimed() -> void:
	_claimed = GameState.get("poi_%s" % poi_id) if GameState.has_method("get") else false
	if _claimed:
		_label.visible = false
