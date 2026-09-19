extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := load("res://scenes/ui/forge_menu.tscn") as PackedScene
	if scene == null:
		print("FAIL: forge scene missing")
		quit(1)
		return
	var menu := scene.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	if menu.get_node_or_null("Root/VBox/BlueprintList") == null:
		print("FAIL: blueprint list missing")
		quit(1)
		return
	if menu.get_node_or_null("Root/VBox/Result/ResultVBox/TierRow") == null:
		print("FAIL: forge tier row missing")
		quit(1)
		return
	if menu.get_node_or_null("Root/VBox/CameraView") != null:
		print("FAIL: camera surface still mounted after ready")
		quit(1)
		return
	if menu.get_node_or_null("Root/VBox/ScanButton") != null:
		print("FAIL: legacy scan action still mounted after ready")
		quit(1)
		return
	var source := FileAccess.get_file_as_string("res://scripts/ui/forge_menu.gd")
	if source.contains("CameraFeed") or source.contains("CONFIDENCE"):
		print("FAIL: camera or confidence language remains in forge menu")
		quit(1)
		return
	if not source.contains("forge_blueprint") or not source.contains("blueprint_progress"):
		print("FAIL: forge menu is not wired to the blueprint transaction")
		quit(1)
		return
	print("ALL FORGE BLUEPRINT SURFACE TESTS PASSED")
	quit(0)
