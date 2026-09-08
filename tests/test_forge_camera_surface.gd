extends SceneTree

func _initialize() -> void:
	var scene := load("res://scenes/ui/forge_menu.tscn") as PackedScene
	if scene == null:
		print("FAIL: forge scene missing")
		quit(1)
		return
	var menu := scene.instantiate()
	root.add_child(menu)
	await process_frame
	if menu.get_node_or_null("Root/VBox/CameraView/CameraFeed") == null:
		print("FAIL: camera preview surface missing")
		quit(1)
		return
	if menu.get_node_or_null("Root/VBox/CameraView/CameraStatus") == null:
		print("FAIL: camera fallback status missing")
		quit(1)
		return
	if not menu.scan_button.disabled and menu.scan_button.text.is_empty():
		print("FAIL: scan action state was not initialized")
		quit(1)
		return
	var source := FileAccess.get_file_as_string("res://scripts/ui/forge_menu.gd")
	if not source.contains("NO PHOTO UPLOAD") or not source.contains("local capture only"):
		print("FAIL: camera-use disclosure missing")
		quit(1)
		return
	print("ALL FORGE CAMERA SURFACE TESTS PASSED")
	quit(0)
