extends Node3D
class_name ServiceNpc

## Non-combat service NPC using the existing WorldManager interaction contract.
## The NPC emits no gameplay mutations itself; it only opens an already-owned
## shop or forge UI after the player deliberately interacts nearby.

@export var display_name: String = "Wandering Merchant"
@export_enum("shop", "forge", "camp") var service_kind: String = "shop"
@export var model_profile: String = "merchant"
@export var authored_rig_height: float = 1.9

var _visual: Node3D
var _idle_time: float = 0.0
var _visual_base_y: float = 0.0
var _visual_base_scale: Vector3 = Vector3.ONE

@onready var interact_area: Area3D = $InteractArea
@onready var prompt: Label3D = $Prompt

func _ready() -> void:
	add_to_group("interactable")
	CharacterRigLoader.try_if_wire(self, model_profile)
	call_deferred("_setup_idle_motion")
	var service_label := "VISIT SHOP" if service_kind == "shop" else "OPEN FORGE"
	if service_kind == "camp":
		service_label = "VISIT CAMP"
	prompt.text = "%s  ·  %s" % [display_name.to_upper(), service_label]
	prompt.visible = false
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)

func _setup_idle_motion() -> void:
	_visual = get_node_or_null("Visual") as Node3D
	if _visual != null:
		_visual_base_y = _visual.position.y
		_visual_base_scale = _visual.scale

func _process(delta: float) -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	_idle_time += delta
	# Small breathing/weight shift keeps service NPCs alive without moving the
	# interaction body or creating unbounded animation/tween state.
	_visual.position.y = _visual_base_y + sin(_idle_time * 1.7) * 0.025
	_visual.scale = _visual_base_scale * (1.0 + sin(_idle_time * 1.7) * 0.006)
	var hero := get_tree().get_first_node_in_group("player") as Node3D
	if hero != null and global_position.distance_to(hero.global_position) < 12.0:
		var flat_target := Vector3(hero.global_position.x, global_position.y,
			hero.global_position.z)
		_visual.look_at(flat_target, Vector3.UP)
	_visual.rotation.z += sin(_idle_time * 1.15) * 0.018

func interact() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var menu_name := "ShopMenu" if service_kind == "shop" else "SatchelUI"
	if service_kind == "camp":
		menu_name = "CampMenu"
	var menu := current_scene.find_child(menu_name, true, false)
	if menu == null:
		return
	if service_kind == "forge" and menu.has_method("show_stats"):
		menu.call("show_stats")
	elif menu.has_method("open"):
		menu.call("open")
	else:
		menu.visible = true

func _on_body_entered(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		prompt.visible = false
