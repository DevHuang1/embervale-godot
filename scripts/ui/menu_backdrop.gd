extends Node3D
class_name MenuBackdrop

## === Live 3D Menu Backdrop ===
## Instantiates the real grove as a cinematic menu background, then contains
## it: HUD/menus hidden, world director and camera rig stopped, enemies freed.
## The hero stays idle under his lantern. A slow orbiting MenuCamera takes the
## viewport; if anything fails, `is_live()` reports false and the menu falls
## back to its flat gradient.

var _world: Node3D = null
var _cam: Camera3D = null
var _center := Vector3.ZERO
var _t := randf() * TAU
var _live := false

func _ready() -> void:
	# Defer building the backdrop until this menu scene is fully in the tree.
	# Instantiating the grove synchronously here runs the world's entire _ready
	# chain (hero, biome_manager, world_manager, combat FX) before their nodes
	# are inside the tree, which triggers add_child/is_inside_tree errors.
	building.call_deferred()

func building() -> void:
	var ps := load("res://scenes/world/grove.tscn") as PackedScene
	if ps == null:
		return
	_world = ps.instantiate()
	if _world == null:
		return
	add_child(_world)
	_contain_world()
	_setup_camera()
	_live = true

func is_live() -> bool:
	return _live

func _contain_world() -> void:
	for overlay in ["HUD", "SatchelUI", "ForgeMenu", "ShopMenu", "SettingsMenu",
			"StatsScreen", "DiamondShop", "BossAltar", "ScreenFX"]:
		var n := _world.get_node_or_null(overlay)
		if n != null:
			n.visible = false
	# Freeze the world director so nothing spawns or advances behind the menu.
	_world.set_physics_process(false)
	_world.set_process(false)
	# Park the game camera rig and yield the viewport to the menu camera.
	var rig := _world.get_node_or_null("CameraRig")
	if rig != null:
		rig.set_physics_process(false)
		rig.set_process(false)
		var game_cam: Camera3D = rig.get("camera")
		if game_cam == null:
			game_cam = _world.get_node_or_null("CameraRig/SpringArm/Camera3D") as Camera3D
		if game_cam != null:
			game_cam.clear_current()
	# Freeze the field: WorldManager holds direct refs to these nodes, so
	# they are parked (hidden + inert), never freed.
	for e in get_tree().get_nodes_in_group("enemy"):
		e.visible = false
		e.set_physics_process(false)
		e.set_process(false)
	for e in get_tree().get_nodes_in_group("boss"):
		e.visible = false
		e.set_physics_process(false)
		e.set_process(false)

func _setup_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "MenuCamera"
	_cam.fov = 38.0
	_cam.near = 0.1
	_cam.far = 220.0
	add_child(_cam)
	var spawn := _world.get_node_or_null("PlayerSpawn") as Node3D
	_center = spawn.global_position if spawn != null else Vector3.ZERO
	_cam.make_current()

func _process(delta: float) -> void:
	if not _live or _cam == null:
		return
	_t += delta * 0.055
	var radius := 6.4
	var height := 2.6
	_cam.position = _center + Vector3(cos(_t) * radius, height, sin(_t) * radius)
	var focus := _center + Vector3(0, 1.0, 0)
	_cam.look_at(focus)
