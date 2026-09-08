extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/minimap.gd")
	var world_source := FileAccess.get_file_as_string("res://scripts/systems/world_manager.gd")
	var required := ["trader", "craftsman", "structure", "task", "event", "portal",
		"get_nodes_in_group(\"interactable\")", "MAX_MARKERS", "SMALL_LEGEND_HEIGHT",
		"T C S ! E P", "E EVENT   P PORTAL", "quest_board.add_to_group(\"task\")",
		"beacon_spawn.add_to_group(\"event\")"]
	var failures: Array[String] = []
	for token in required:
		if not source.contains(token) and not world_source.contains(token):
			failures.append("missing minimap category contract: %s" % token)
	if failures.is_empty():
		print("MINIMAP MARKER CATEGORY TESTS PASSED")
	else:
		print("FAILURES: ", failures)
	quit(1 if not failures.is_empty() else 0)
