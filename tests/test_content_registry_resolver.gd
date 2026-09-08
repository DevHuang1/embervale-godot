extends SceneTree

func _init() -> void:
	var registry := ContentRegistry.snapshot({}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {
		"nature_tree": {"id": "nature_tree", "path": "res://assets/models/kenney_nature/Models/tree_detailed.fbx"}}, {})
	var resolved := ContentRegistry.resolve_asset_path(registry, "prop", "nature_tree", "res://fallback.tres")
	if resolved != "res://assets/models/kenney_nature/Models/tree_detailed.fbx":
		push_error("Stable asset ID did not resolve to its current imported path")
		quit(1)
		return
	var fallback := ContentRegistry.resolve_asset_path(registry, "prop", "missing", "res://fallback.tres")
	if fallback != "res://fallback.tres":
		push_error("Missing semantic asset did not use deterministic fallback")
		quit(1)
		return
	print("ALL CONTENT REGISTRY RESOLVER TESTS PASSED")
	quit()
