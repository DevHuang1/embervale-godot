extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1080, 1920)
	var cases: Array[Dictionary] = [
		{"scene": "res://scenes/ui/satchel.tscn", "header": "Root/Header", "close": "Root/Header/CloseButton"},
		{"scene": "res://scenes/ui/stats_screen.tscn", "header": "Root/Panel/Header", "close": "Root/Panel/Header/CloseButton"},
		{"scene": "res://scenes/ui/forge_menu.tscn", "header": "Root/Header", "close": "Root/Header/CloseButton"},
		{"scene": "res://scenes/ui/shop_menu.tscn", "header": "Root/Header", "close": "Root/Header/CloseButton"},
		{"scene": "res://scenes/ui/camp_menu.tscn", "header": "Root/Header", "close": "Root/Header/Close"},
		{"scene": "res://scenes/ui/settings_menu.tscn", "header": "Root/Panel/Header", "close": "Root/Panel/Header/CloseButton"},
	]
	for entry in cases:
		var packed := load(str(entry.scene)) as PackedScene
		if packed == null:
			_fail("Missing menu scene %s" % str(entry.scene))
			continue
		var menu := packed.instantiate() as CanvasLayer
		root.add_child(menu)
		await process_frame
		var header := menu.get_node(str(entry.header)) as Control
		var close := menu.get_node(str(entry.close)) as Button
		if close.get_global_rect().end.x < header.get_global_rect().end.x - 2.0:
			_fail("Close control is not at the right edge for %s" % str(entry.scene))
		if not str(close.text).contains("CLOSE"):
			_fail("Close control is not labelled CLOSE for %s" % str(entry.scene))
		menu.visible = true
		close.pressed.emit()
		if menu.visible:
			_fail("Close control did not close %s" % str(entry.scene))
		menu.queue_free()
		await process_frame
	if failures.is_empty():
		print("MENU EXIT ALIGNMENT TESTS PASSED")
	else:
		print("MENU EXIT ALIGNMENT TESTS FAILED: ", failures)
	quit(1 if not failures.is_empty() else 0)

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL: ", message)
