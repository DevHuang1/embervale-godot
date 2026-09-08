extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/realm_identity_catalog.gd")
	var required := ["traversal", "resource_ritual", "ambient_behavior", "elite_composition", "landmark_reward", "loop", "ecology"]
	for realm in catalog.realms():
		var profile: Dictionary = catalog.for_realm(realm)
		for key in required:
			if str(profile.get(key, "")).is_empty():
				push_error("Realm %s is missing identity field %s" % [realm, key])
				quit(1)
				return
		var loop: Dictionary = profile.get("loop", {})
		for duration in ["short", "medium", "long"]:
			if str(loop.get(duration, "")).is_empty():
				push_error("Realm %s is missing %s loop activity" % [realm, duration])
				quit(1)
				return
		var ecology: Dictionary = profile.get("ecology", {})
		for relationship in ["predator_prey", "rivals", "elemental_reaction", "hazard"]:
			if str(ecology.get(relationship, "")).is_empty():
				push_error("Realm %s is missing ecology relationship %s" % [realm, relationship])
				quit(1)
				return
	var fallback: Dictionary = catalog.for_realm("unknown_realm")
	if fallback.get("traversal") != "thorn-lane scouting":
		push_error("Unknown realms do not use the safe Bramblewood fallback")
		quit(1)
		return
	var bestiary_script := preload("res://scripts/systems/bestiary.gd")
	var summary := bestiary_script.ecology_summary("moonfen")
	if not summary.contains("PREDATOR / PREY") or not summary.contains("HAZARD"):
		push_error("Bestiary ecology summary is not player-readable")
		quit(1)
		return
	print("ALL REALM IDENTITY CATALOG TESTS PASSED")
	quit()
