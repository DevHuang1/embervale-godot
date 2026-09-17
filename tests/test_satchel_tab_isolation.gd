extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1080, 1920)
	var scene := load("res://scenes/ui/satchel.tscn") as PackedScene
	if scene == null:
		_fail("Satchel scene missing")
		quit(1)
		return
	var satchel := scene.instantiate() as SatchelUI
	root.add_child(satchel)
	await process_frame
	var pages: Array[Control] = [
		satchel.get_node("Root/VBox/TabContent/ItemsPage") as Control,
		satchel.get_node("Root/VBox/TabContent/HeroPage") as Control,
		satchel.get_node("Root/VBox/TabContent/StatsPage") as Control,
		satchel.get_node("Root/VBox/TabContent/CraftingPage") as Control,
	]
	var tab_ids := [&"items", &"hero", &"stats", &"crafting"]
	for tab_id in tab_ids:
		satchel.open_tab(tab_id)
		await process_frame
		var visible_count := 0
		for page in pages:
			if page.visible:
				visible_count += 1
		if visible_count != 1:
			_fail("More than one Satchel page visible for %s" % str(tab_id))
	var tabs := satchel.get_node("Root/VBox/SatchelSections") as GridContainer
	if tabs.get_child_count() != 4:
		_fail("Satchel does not expose exactly four tabs")
	for tab_node in tabs.get_children():
		if (tab_node as Button).custom_minimum_size.y < UiKit.TOUCH_TARGET_MIN:
			_fail("Satchel tab is below the touch target minimum")
	root.size = Vector2i(1440, 900)
	await process_frame
	if tabs.columns != 4:
		_fail("Desktop Satchel did not switch to the expanded tab layout")
	root.size = Vector2i(1080, 1920)
	await process_frame
	var header := satchel.get_node("Root/Header") as Control
	var close := satchel.get_node("Root/Header/CloseButton") as Control
	await process_frame
	if close.get_global_rect().end.x < header.get_global_rect().end.x - 2.0:
		_fail("Satchel close button is not aligned to the right edge")
	satchel.visible = true
	close.get_signal_connection_list("pressed")
	close.pressed.emit()
	if satchel.visible:
		_fail("Satchel close button did not close the overlay")
	if failures.is_empty():
		print("SATCHEL TAB ISOLATION TESTS PASSED")
	else:
		print("SATCHEL TAB ISOLATION TESTS FAILED: ", failures)
	quit(1 if not failures.is_empty() else 0)

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL: ", message)
