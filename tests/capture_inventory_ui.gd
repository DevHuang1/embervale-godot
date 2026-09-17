extends SceneTree

## Deterministic real-renderer capture. Run without --headless at 1080x1920.

const CAPTURE_DIR := "/private/tmp/embervale_inventory_capture"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1080, 1920)
	var scene := load("res://scenes/ui/satchel.tscn") as PackedScene
	if scene == null:
		push_error("Satchel scene missing")
		quit(1)
		return
	var satchel := scene.instantiate() as SatchelUI
	root.add_child(satchel)
	satchel.visible = true
	await _frames(4)
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	for tab_id in [&"items", &"hero", &"stats"]:
		satchel.open_tab(tab_id)
		await _frames(3)
		var image: Image = root.get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [CAPTURE_DIR, str(tab_id)]
		if image.save_png(path) != OK:
			push_error("Could not save %s" % path)
		else:
			print("CAPTURED ", path)
	quit(0)

func _frames(count: int) -> void:
	for _i in count:
		await process_frame
