extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := load("res://scenes/ui/dungeon_select.tscn") as PackedScene
	if scene == null:
		print("FAIL: dungeon selector scene missing")
		quit(1)
		return
	var selector := scene.instantiate()
	root.add_child(selector)
	await process_frame
	var cards: VBoxContainer = selector.get_node("Root/Center/Panel/VBox/CardsScroll/Cards")
	if cards.get_child_count() != 3:
		print("FAIL: expected three dungeon cards")
		quit(1)
		return
	var source := FileAccess.get_file_as_string("res://scripts/ui/dungeon_select.gd")
	if not source.contains("UiKit.action_state"):
		print("FAIL: dungeon states do not use shared action semantics")
		quit(1)
		return
	if not source.contains("CURRENT REALM") or not source.contains("AVAILABLE") or not source.contains("UNLOCK") or not source.contains("Bestiary.biome_scene") or not source.contains("_travel_with_fade") or not source.contains("0.28"):
		print("FAIL: realm state copy missing")
		quit(1)
		return
	selector.queue_free()
	print("ALL DUNGEON UNLOCK PRESENTATION TESTS PASSED")
	quit(0)
