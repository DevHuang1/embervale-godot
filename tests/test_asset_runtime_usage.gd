extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/asset_intake_catalog.gd")
	for entry in catalog.ENTRIES:
		var owner_path := str(entry.get("runtime_owner", ""))
		var use_case := str(entry.get("runtime_use_case", ""))
		if owner_path.is_empty() or use_case.is_empty():
			push_error("Imported pack has no runtime owner/use case: %s" % entry.get("id", ""))
			quit(1)
			return
		if not FileAccess.file_exists("res://" + owner_path.trim_prefix("res://")):
			push_error("Runtime owner missing for imported pack %s: %s" % [entry.get("id", ""), owner_path])
			quit(1)
			return
		var owner_source := FileAccess.get_file_as_string("res://" + owner_path.trim_prefix("res://"))
		for runtime_path in entry.get("runtime_paths", []):
			if not FileAccess.file_exists(str(runtime_path)):
				push_error("Declared runtime asset missing: %s" % runtime_path)
				quit(1)
				return
			var asset_name := str(runtime_path).get_file()
			if not owner_source.contains(asset_name):
				push_error("Runtime owner does not reference declared asset %s: %s" % [asset_name, owner_path])
				quit(1)
				return
	print("ALL IMPORTED PACKS HAVE RUNTIME USE CASES")
	quit()
