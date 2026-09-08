extends SceneTree

func _initialize() -> void:
	var credits := FileAccess.get_file_as_string("res://ASSET_CREDITS.md")
	var catalog := preload("res://scripts/systems/asset_intake_catalog.gd")
	var audit := preload("res://scripts/systems/license_audit.gd")
	var errors: Array[String] = audit.validate_catalog(catalog.ENTRIES, credits)
	if not errors.is_empty():
		push_error("Asset license audit failed: %s" % "; ".join(errors))
		quit(1)
		return
	print("ALL ASSET LICENSE AND CREDIT TESTS PASSED")
	quit(0)
