extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/ecology_tactics_catalog.gd")
	var errors: Array[String] = catalog.validate()
	if not errors.is_empty():
		push_error("Ecology tactics validation failed: %s" % "; ".join(errors))
		quit(1)
		return
	for realm_id in catalog.RULES:
		if str(catalog.rule_for(str(realm_id)).get("choice", "")).is_empty():
			push_error("Ecology rule has no player choice: %s" % realm_id)
			quit(1)
			return
	print("ECOLOGY TACTICS CATALOG PASSED")
	quit(0)
