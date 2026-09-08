extends SceneTree

func _init() -> void:
	var schema := preload("res://scripts/systems/content_schema.gd")
	var state: Dictionary = schema.migrate_scan_state(99, -3, 9, 10)
	if state.get("scans") != 9 or state.get("fragments") != 0:
		push_error("Scan migration bounds failed: %s" % state)
		quit(1)
		return
	var realms: Array[String] = schema.migrate_string_list(["Mistfen", "mistfen", ""], ["bramblewood", "heartwood"])
	if realms != ["mistfen", "bramblewood", "heartwood"]:
		push_error("Realm migration failed: %s" % realms)
		quit(1)
		return
	print("ALL CONTENT SCAN MIGRATION TESTS PASSED")
	quit()
