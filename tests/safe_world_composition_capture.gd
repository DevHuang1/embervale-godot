extends SceneTree

## Real-render visual QA harness. It redirects GameState persistence to /tmp
## before loading a realm and never reads, deletes, or overwrites the player's
## normal user://embervale_save.cfg.

var scene_path := "res://scenes/world/grove.tscn"
var output_path := "/private/tmp/embervale_world_composition.png"
var focus := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1, 2):
		match args[i]:
			"--scene": scene_path = args[i + 1]
			"--out": output_path = args[i + 1]
			"--focus": focus = args[i + 1]
	_run.call_deferred()

func _run() -> void:
	var game_state := root.get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.set("save_path", "/private/tmp/embervale_visual_capture_save.cfg")
		game_state.call("reset")
		if focus == "equipment":
			game_state.call("add_weapon", game_state.WEAPON_DEFS["ember_sword"], true)
			game_state.call("add_armor", game_state.ARMOR_DEFS["warden_plate"], true)
	change_scene_to_file(scene_path)
	for frame in 150:
		await process_frame
	if focus == "cave" and current_scene != null:
		var cave := current_scene.find_child("EmbervaultEntrance", true, false) as Node3D
		if cave != null:
			for layer in current_scene.find_children("*", "CanvasLayer", true, false):
				(layer as CanvasLayer).visible = false
			var camera := Camera3D.new()
			current_scene.add_child(camera)
			camera.global_position = cave.global_position + Vector3(0.0, 3.25, 7.5)
			camera.look_at(cave.global_position + Vector3(0.0, 1.25, 0.0))
			camera.make_current()
			for frame in 20:
				await process_frame
	elif focus == "equipment" and current_scene != null:
		for layer in current_scene.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false
		var hero := current_scene.find_child("Hero", true, false) as Node3D
		if hero != null:
			var camera := Camera3D.new()
			current_scene.add_child(camera)
			camera.global_position = hero.global_position + Vector3(2.4, 1.55, 3.4)
			camera.look_at(hero.global_position + Vector3(0.0, 0.92, 0.0))
			camera.fov = 34.0
			camera.make_current()
			for frame in 30:
				await process_frame
	var image := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var error := image.save_png(output_path)
	print("SAFE WORLD CAPTURE ", output_path, " size=", image.get_size(), " error=", error)
	quit(0 if error == OK else 1)
