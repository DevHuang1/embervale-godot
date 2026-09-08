extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs: Node = root.get_node_or_null("/root/GameState")
	if gs == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	var registry: Dictionary = gs.get_content_registry()
	if registry.get("skill", {}).is_empty() or registry.get("loot_table", {}).is_empty() \
			or not registry.has("quest"):
		push_error("Game registry omitted stable skill, loot-table, or quest category")
		quit(1)
		return
	var errors: Array[String] = ContentRegistry.validate(registry)
	if not errors.is_empty():
		push_error("Gameplay-family registry validation failed: %s" % errors)
		quit(1)
		return
	print("ALL CONTENT REGISTRY GAMEPLAY FAMILY TESTS PASSED")
	quit()
