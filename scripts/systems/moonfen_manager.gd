extends WorldManager

class_name MoonfenManager

var fenlings: Array[Node3D] = []

func _ready() -> void:
	super._ready()
	# Moonfen is an optional post-quest combat area.
	hushling.visible = false
	hushling.set_physics_process(false)
	hushling.collision_layer = 0
	hushling.collision_mask = 0
	hushling.get_node("Hitbox").monitoring = false
	hushling.get_node("AttackArea").monitoring = false
	_spawn_fenlings()
	game_state.quest_progress.emit("The Moonfen wakes beneath the blue ash. Find the return gate when the water goes still.")

func _spawn_fenlings() -> void:
	var scene: PackedScene = load("res://scenes/entities/moonfen_fenling.tscn")
	if scene == null:
		return
	var points := [
		Vector3(-7.0, 0.5, -4.0),
		Vector3(7.5, 0.5, -8.0),
		Vector3(12.0, 0.5, 5.0)
	]
	for point in points:
		var fenling = scene.instantiate()
		fenling.name = "MoonfenFenling_%d" % fenlings.size()
		add_child(fenling)
		fenling.global_position = point
		fenling.call("set_max_hp", 42)
		fenling.call("set_base_atk", 5)
		fenling.call("set_burst_cooldown", 4.0)
		fenlings.append(fenling)
	_spawn_moonfen_elite()

func _spawn_moonfen_elite() -> void:
	var elite_scene: PackedScene = load("res://scenes/entities/elite_hushling.tscn")
	if elite_scene == null:
		return
	var elite: Node3D = elite_scene.instantiate()
	elite.name = "MoonfenEmberWarden"
	add_child(elite)
	elite.global_position = Vector3(0.0, 0.5, 9.0)
	var md := CharacterModelData.new()
	md.display_name = "Moonfen Ember Warden"
	md.model_scale = 1.22
	md.body_tint = Color(0.08, 0.18, 0.24, 1.0)
	md.eye_glow_color = Color(0.42, 0.86, 1.0, 1.0)
	md.configure_entity(elite)
