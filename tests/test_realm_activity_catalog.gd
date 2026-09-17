extends SceneTree

## Static contract for the authored six-beat activity catalog.

const CATALOG := preload("res://scripts/world/realm_activity_catalog.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var errors: Array[String] = CATALOG.validate()
	if errors.is_empty() and CATALOG.all_activity_definitions().size() == 30:
		print("REALM ACTIVITY CATALOG PASSED (activities=30)")
		quit(0)
		return
	for error in errors:
		print("FAIL: ", error)
	print("FAIL: expected 30 activity definitions, got %d" % CATALOG.all_activity_definitions().size())
	quit(1)
