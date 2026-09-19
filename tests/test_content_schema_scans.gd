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
	var analysis: Dictionary = schema.migrate_analysis_state({"Swarm": 3, "brute": -2, "": 9})
	if int(analysis.get("swarm", 0)) != 3 or int(analysis.get("brute", 0)) != 0 \
			or analysis.has("") or analysis.has("Swarm"):
		push_error("Analysis migration failed: %s" % analysis)
		quit(1)
		return
	if not schema.migrate_analysis_state("garbage").is_empty():
		push_error("Analysis migration accepted a non-dictionary")
		quit(1)
		return
	print("ALL CONTENT SCAN MIGRATION TESTS PASSED")
	quit()
