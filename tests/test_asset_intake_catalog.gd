extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/asset_intake_catalog.gd")
	var errors: Array[String] = catalog.validate_entries()
	if not errors.is_empty():
		push_error("Asset intake catalog invalid: %s" % ", ".join(errors))
		quit(1)
		return
	if catalog.ENTRIES.size() != 8 or catalog.reviewed_entries().size() != 8:
		push_error("All current imported asset owners should have an explicit review state")
		quit(1)
		return
	for entry in catalog.ENTRIES:
		for field in ["poly_budget", "texture_budget", "animation_coverage",
			"collision_status", "android_fallback"]:
			if not entry.has(field) or str(entry[field]).is_empty():
				push_error("Production-readiness field missing: %s" % field)
				quit(1)
				return
		if catalog.quality_score(entry) < 90 or catalog.quality_band(entry) != "SHIP-READY":
			push_error("Reviewed asset did not meet ship-ready quality score: %s" % entry.id)
			quit(1)
			return
	var invalid := catalog.ENTRIES[0].duplicate(true)
	invalid["license"] = "Custom License"
	invalid["source_url"] = "http://example.invalid/asset"
	var invalid_errors: Array[String] = catalog.validate_entries([invalid])
	if invalid_errors.size() < 2:
		push_error("Unapproved license/source URL was not rejected")
		quit(1)
		return
	var invalid_path := catalog.ENTRIES[0].duplicate(true)
	invalid_path["runtime_paths"] = ["res://external/asset.exe"]
	var path_errors: Array[String] = catalog.validate_entries([invalid_path])
	if path_errors.size() < 2:
		push_error("Invalid runtime asset path/extension was not rejected")
		quit(1)
		return
	var import_probe := Node3D.new()
	import_probe.scale = Vector3.ZERO
	var import_errors: Array[String] = []
	catalog._validate_model_import(import_probe, "probe", "res://assets/probe.fbx", import_errors)
	import_probe.free()
	if import_errors.is_empty():
		push_error("Invalid imported root transform was not rejected")
		quit(1)
		return
	print("ALL ASSET INTAKE CATALOG TESTS PASSED")
	quit()
