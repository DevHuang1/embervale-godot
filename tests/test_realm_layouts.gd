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
		# Realm elites carry their own creature rig so elite pockets read as a
		# species, not the shared blob. Both fields must resolve for every realm.
		var elite: Dictionary = Bestiary.variant_for(realm, "elite")
		var elite_rig := str(elite.get("rig", ""))
		# Read the static table directly: _any_model() consults the live
		# SceneTree, which does not exist yet during _initialize().
		var elite_path := str(CharacterRigLoader.EXTERNAL_MODEL_PATHS.get(elite_rig, ""))
		if elite_path.is_empty() or not ResourceLoader.exists(elite_path, "PackedScene"):
			failures += 1
			print("FAIL: %s elite rig does not resolve: %s" % [realm, elite_rig])
		if float(elite.get("rig_height", 0.0)) <= 0.0:
			failures += 1
			print("FAIL: %s elite rig_height is not positive" % realm)
		if str(elite.get("kind", "")).is_empty() or int(elite.get("hp", 0)) <= 0:
			failures += 1
			print("FAIL: %s elite lost its kind/health" % realm)
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
		if realm == "bramblewood":
			var expansion: Array = profile.get("expansion_pockets", [])
			var expected_expansion := {
				"split_road_oak": Vector3(20, 0, -48),
				"rootcut_gully": Vector3(46, 0, -86),
				"hollow_camp": Vector3(82, 0, -124),
				"beacon_breach": Vector3(124, 0, -164),
				"rootbound_court": Vector3(172, 0, -208),
			}
			if expansion.size() != expected_expansion.size():
				failures += 1
				print("FAIL: Bramblewood expansion pocket count changed")
			for pocket_value in expansion:
				var pocket: Dictionary = pocket_value as Dictionary
				var pocket_id := str(pocket.get("id", ""))
				var position: Vector3 = pocket.get("position", Vector3.ZERO)
				if not expected_expansion.has(pocket_id) \
						or position != expected_expansion[pocket_id]:
					failures += 1
					print("FAIL: Bramblewood pocket contract changed -> ", pocket_id)
				if str(pocket.get("checkpoint_id", "")).is_empty():
					failures += 1
					print("FAIL: Bramblewood pocket lacks checkpoint -> ", pocket_id)
				if str(pocket.get("reward_marker", "")).is_empty():
					failures += 1
					print("FAIL: Bramblewood pocket lacks reward marker -> ", pocket_id)
				if pocket_id in ["beacon_breach", "rootbound_court"] \
						and not (pocket.get("encounter", {}) is Dictionary):
					failures += 1
					print("FAIL: Bramblewood encounter payload missing -> ", pocket_id)
			var boss_pocket: Dictionary = expansion.back() as Dictionary
			if str(boss_pocket.get("role", "")) != "boss" \
					or str(boss_pocket.get("boss_id", "")) != "rootbound_warden":
				failures += 1
				print("FAIL: Rootbound Court encounter contract changed")
	for family in ["bark", "wood", "clay", "rock"]:
		for map_name in ["albedo", "normal", "roughness"]:
			var texture_path := "res://assets/textures/stylized/%s/%s.png" % [family, map_name]
			if not ResourceLoader.exists(texture_path):
				failures += 1
				print("FAIL: authored landmark texture missing: %s" % texture_path)
	# === Route reach + boss spread ===
	# Content must span the map instead of clustering in a pocket at spawn.
	var spawn := Vector2(0.0, 2.0)
	var terrain_half := 290.0
	var spread_min := {
		"whispergrove": 60.0, "bramblewood": 100.0, "mistfen": 100.0,
		"heartwood": 140.0, "moonfen": 24.0,
	}
	for realm in REALMS:
		var profile := RealmLayoutData.profile(realm)
		var arena_value: Vector3 = profile.get("arena", Vector3.ZERO)
		var arena := Vector2(arena_value.x, arena_value.z)
		var arena_distance := spawn.distance_to(arena)
		if arena_distance < float(spread_min.get(realm, 60.0)):
			failures += 1
			print("FAIL: %s boss arena only %.1f m from spawn" % [realm, arena_distance])
		var reach := 0.0
		for point_value in profile.get("route", []):
			var point := point_value as Vector3
			reach = maxf(reach, spawn.distance_to(Vector2(point.x, point.z)))
		if reach + 0.01 < arena_distance:
			failures += 1
			print("FAIL: %s route ends %.1f m out but its arena sits at %.1f m" \
				% [realm, reach, arena_distance])
		for anchor in RealmLayoutData.boss_anchor_points(realm):
			if anchor.length() > terrain_half:
				failures += 1
				print("FAIL: %s boss anchor outside terrain relief: %s" % [realm, anchor])

	# === Map-wide content integrity: spawn pockets + authored structures ===
	var pocket_ids: Dictionary = {}
	var structure_ids: Dictionary = {}
	var valid_tiers := ["normal", "hard", "elite"]
	var valid_kinds := ["arch", "watch", "spire", "shrine", "basin", "ruins", "camp"]
	for realm in REALMS:
		var profile := RealmLayoutData.profile(realm)
		var pockets: Array = profile.get("spawn_pockets", [])
		if pockets.size() < 5:
			failures += 1
			print("FAIL: %s lacks map-wide spawn pockets (%d)" % [realm, pockets.size()])
		for pocket_value in pockets:
			var pocket := pocket_value as Dictionary
			var pid := "%s/%s" % [realm, str(pocket.get("id", ""))]
			if str(pocket.get("id", "")).is_empty() or pocket_ids.has(pid):
				failures += 1
				print("FAIL: duplicate/empty spawn pocket id %s" % pid)
			pocket_ids[pid] = true
			if not (str(pocket.get("tier", "")) in valid_tiers):
				failures += 1
				print("FAIL: %s pocket %s has invalid tier '%s'" \
					% [realm, pid, pocket.get("tier", "")])
			var pocket_count := int(pocket.get("count", 0))
			if pocket_count < 1 or pocket_count > 4:
				failures += 1
				print("FAIL: %s pocket %s count out of band (%d)" % [realm, pid, pocket_count])
			var pocket_radius := float(pocket.get("radius", 0.0))
			if pocket_radius < 8.0 or pocket_radius > 40.0:
				failures += 1
				print("FAIL: %s pocket %s radius out of band (%.1f)" \
					% [realm, pid, pocket_radius])
			var pocket_value_pos: Vector3 = pocket.get("pos", Vector3.ZERO)
			if Vector2(pocket_value_pos.x, pocket_value_pos.z).length() > terrain_half:
				failures += 1
				print("FAIL: %s spawn pocket outside terrain relief: %s" % [realm, pid])
		var structures: Array = profile.get("structures", [])
		if structures.size() < 5:
			failures += 1
			print("FAIL: %s lacks authored structures (%d)" % [realm, structures.size()])
		for structure_value in structures:
			var structure := structure_value as Dictionary
			var sid := "%s/%s" % [realm, str(structure.get("id", ""))]
			if str(structure.get("id", "")).is_empty() or structure_ids.has(sid):
				failures += 1
				print("FAIL: duplicate/empty structure id %s" % sid)
			structure_ids[sid] = true
			if not (str(structure.get("kind", "")) in valid_kinds):
				failures += 1
				print("FAIL: %s structure %s has invalid kind '%s'" \
					% [realm, sid, structure.get("kind", "")])
			if str(structure.get("label", "")).is_empty():
				failures += 1
				print("FAIL: %s structure %s lacks a map label" % [realm, sid])
			var structure_pos: Vector3 = structure.get("pos", Vector3.ZERO)
			if Vector2(structure_pos.x, structure_pos.z).length() > terrain_half:
				failures += 1
				print("FAIL: %s structure outside terrain relief: %s" % [realm, sid])

	# === Realm-wide hostile ceiling is a budget, not decoration ===
	var manager_source := FileAccess.get_file_as_string("res://scripts/systems/biome_manager.gd")
	var cap_regex := RegEx.new()
	cap_regex.compile("const POCKET_GLOBAL_CAP := (\\d+)")
	var cap_result := cap_regex.search(manager_source)
	if cap_result == null:
		failures += 1
		print("FAIL: BiomeManager POCKET_GLOBAL_CAP is missing")
	else:
		var pocket_cap := int(cap_result.get_string(1))
		for realm in REALMS:
			var authored_total := 0
			var widest := 0
			for pocket_value in RealmLayoutData.profile(realm).get("spawn_pockets", []):
				var pocket := pocket_value as Dictionary
				authored_total += int(pocket.get("count", 0))
				widest = maxi(widest, int(pocket.get("count", 0)))
			if widest > pocket_cap:
				failures += 1
				print("FAIL: %s single pocket holds %d, above the realm cap %d" \
					% [realm, widest, pocket_cap])
			if authored_total < pocket_cap:
				failures += 1
				print("FAIL: %s authored pocket budget %d is thinner than the live cap %d" \
					% [realm, authored_total, pocket_cap])
	for required_hook in ["_build_spawn_pockets", "_tick_spawn_pockets", "_hostile_budget_remaining",
			"_build_structures", "_build_structure_kind"]:
		if not manager_source.contains(required_hook):
			failures += 1
			print("FAIL: BiomeManager missing map-population hook %s" % required_hook)
	print("REALM LAYOUT TESTS %s" % ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	quit(failures)
