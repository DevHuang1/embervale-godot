extends SceneTree

func _init() -> void:
	var records := ContentRegistry.asset_records([
		{"id": "nature", "category": "environment", "realm": "all",
			"runtime_paths": ["res://assets/models/kenney_nature/Models/tree_detailed.fbx"],
			"runtime_use_case": "realm dressing"},
	])
	var props: Dictionary = records.get("prop", {})
	var record: Dictionary = props.get("nature_tree_detailed", {})
	if str(record.get("id", "")) != "nature_tree_detailed":
		push_error("Asset representative did not receive a stable semantic ID")
		quit(1)
		return
	if str(record.get("path", "")) != "res://assets/models/kenney_nature/Models/tree_detailed.fbx":
		push_error("Asset representative path was not preserved")
		quit(1)
		return
	print("ALL CONTENT REGISTRY ASSET RECORD TESTS PASSED")
	quit()
