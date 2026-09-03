extends SceneTree

## Visual probe: boots a realm scene WITH rendering, waits for settle,
## saves screenshots from the live camera.
##   godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --script tests/diag_realm_shot.gd -- --scene res://scenes/world/moonfen.tscn --out /tmp/shot.png

var _scene := "res://scenes/world/grove.tscn"
var _out := "/tmp/realm_shot.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1, 2):
		match args[i]:
			"--scene":
				_scene = args[i + 1]
			"--out":
				_out = args[i + 1]
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var vp := root.get_viewport()
	var img := vp.get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_size())


func _run() -> void:
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	change_scene_to_file(_scene)
	await _frames(150)
	_snap(_out)
	await _frames(60)
	_snap(_out.replace(".png", "_b.png"))
	print("REALM SHOT DONE")
	gs.delete_save()
	quit(0)

