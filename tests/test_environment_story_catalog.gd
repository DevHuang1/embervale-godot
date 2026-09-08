extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/environment_story_catalog.gd")
	var errors: Array[String] = catalog.validate()
	if not errors.is_empty():
		push_error("Environment story catalog failed: %s" % "; ".join(errors))
		quit(1)
		return
	var bramble: Dictionary = catalog.for_realm("bramblewood")
	if not str(bramble.get("tools", "")).contains("axe") \
			or not str(bramble.get("creature_evidence", "")).contains("gouges"):
		push_error("Bramblewood story layers are not readable")
		quit(1)
		return
	print("ENVIRONMENT STORY CATALOG PASSED")
	quit(0)
