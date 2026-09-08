extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState") as GameState
	if gs == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	var registry: Dictionary = gs.get_content_registry()
	for category in ["weapon", "armor", "enemy", "npc", "mount", "animal", "vfx", "sfx", "prop", "terrain_material"]:
		var records: Dictionary = registry.get(category, {})
		if records.is_empty():
			push_error("Content registry category is empty: %s" % category)
			quit(1)
			return
		for key in records:
			if str(records[key].get("id", "")) != str(key):
				push_error("Content registry ID mismatch in %s: %s" % [category, key])
				quit(1)
				return
	var errors: Array[String] = ContentRegistry.validate(registry)
	if not errors.is_empty():
		push_error("Content registry population invalid: %s" % "; ".join(errors))
		quit(1)
		return
	print("CONTENT REGISTRY POPULATION PASSED")
	quit(0)
