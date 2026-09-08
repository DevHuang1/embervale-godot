extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/asset_budget_catalog.gd")
	var manifest: Dictionary = catalog.empty_manifest()
	manifest["hero"] = {"instances": 1, "materials": 12, "texture_mb": 32}
	if not catalog.validate_manifest(manifest).is_empty():
		push_error("Valid boundary budget was rejected")
		quit(1)
		return
	manifest["foliage"] = {"instances": 65, "materials": 8, "texture_mb": 16}
	var errors: Array[String] = catalog.validate_manifest(manifest)
	if errors.size() != 1 or not str(errors[0]).contains("foliage/instances"):
		push_error("Exceeded foliage budget was not reported with an actionable category/field")
		quit(1)
		return
	print("ALL ASSET BUDGET CATALOG TESTS PASSED")
	quit()
