extends SceneTree

const REALMS := ["whispergrove", "bramblewood", "mistfen", "heartwood", "moonfen"]

func _initialize() -> void:
	var failures := 0
	var signatures: Dictionary = {}
	var chest_ids: Dictionary = {}
	for realm in REALMS:
		var profile := RealmLayoutData.profile(realm)
		var route: Array = profile.get("route", [])
		var chests: Array = profile.get("chests", [])
		var enemies: Array = profile.get("enemies", [])
		var resources: Array = profile.get("resources", [])
		var encounters: Array = profile.get("encounters", [])
		if route.size() < 5 or chests.size() < 3 or enemies.size() < 3 \
				or resources.size() < 3 or encounters.size() < 2:
			failures += 1
			print("FAIL: %s lacks route/content density" % realm)
		var signature := str(route)
		if signatures.has(signature):
			failures += 1
			print("FAIL: %s duplicates %s route" % [realm, signatures[signature]])
		signatures[signature] = realm
		for chest_value in chests:
			var chest := chest_value as Dictionary
			var chest_id := str(chest.get("id", ""))
			if chest_id.is_empty() or chest_ids.has(chest_id):
				failures += 1
				print("FAIL: duplicate/empty chest id %s" % chest_id)
			chest_ids[chest_id] = true
		for enemy_id in enemies:
			var path := "res://scenes/entities/%s.tscn" % str(enemy_id)
			if not ResourceLoader.exists(path):
				failures += 1
				print("FAIL: %s enemy scene missing: %s" % [realm, path])
		for resource_value in resources:
			var resource := resource_value as Dictionary
			if not GameState.MATERIAL_DEFS.has(str(resource.get("id", ""))):
				failures += 1
				print("FAIL: %s invalid raw material: %s" % [realm, resource.get("id", "")])
		for encounter_value in encounters:
			var encounter := encounter_value as Dictionary
			var encounter_path := "res://scenes/entities/%s.tscn" % str(encounter.get("scene", ""))
			if not ResourceLoader.exists(encounter_path):
				failures += 1
				print("FAIL: %s authored enemy missing: %s" % [realm, encounter_path])
		if not profile.has("arena") or not profile.has("cave"):
			failures += 1
			print("FAIL: %s lacks boss/cave anchors" % realm)
	for family in ["bark", "wood", "clay", "rock"]:
		for map_name in ["albedo", "normal", "roughness"]:
			var texture_path := "res://assets/textures/stylized/%s/%s.png" % [family, map_name]
			if not ResourceLoader.exists(texture_path):
				failures += 1
				print("FAIL: authored landmark texture missing: %s" % texture_path)
	print("REALM LAYOUT TESTS %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(failures)
