extends SceneTree

## Visual probe: boots the grove WITH rendering, waits for settle,
## saves screenshots from the live camera.

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _snap(path: String) -> void:
	var vp := root.get_viewport()
	var img := vp.get_texture().get_image()
	img.save_png(path)
	print("saved ", path)

func _run() -> void:
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	change_scene_to_file("res://scenes/world/grove.tscn")
	await _frames(150)
	_snap("/var/folders/t5/3pcs06_d6tnd5psczflhtgkh0000gp/T/kilo/world_shot_1.png")
	await _frames(60)
	_snap("/var/folders/t5/3pcs06_d6tnd5psczflhtgkh0000gp/T/kilo/world_shot_2.png")
	print("WORLD SHOT DONE")
	gs.delete_save()
	quit(0)
