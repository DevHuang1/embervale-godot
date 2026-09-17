extends SceneTree

const BESTIARY := preload("res://scripts/systems/bestiary.gd")
const LAYOUT := preload("res://scripts/world/realm_layout_data.gd")
const ROSTER := preload("res://scripts/systems/boss_roster_catalog.gd")
const DIRECTOR := preload("res://scripts/systems/boss_encounter_director.gd")

func _init() -> void:
	var failures := 0
	var primary_by_realm := {
		"bramblewood": "bramblewood_thorn_regent",
		"mistfen": "mistfen_fogmaw",
		"heartwood": "heartwood_cinderhart",
		"moonfen": "moonfen_tide_oracle",
	}
	for realm in primary_by_realm:
		var actual := str(BESTIARY.BIOMES[realm].get("boss_id", ""))
		if actual != str(primary_by_realm[realm]):
			push_error("Primary boss mismatch for %s: %s" % [realm, actual])
			failures += 1
		var primary_canonical := ROSTER.canonical_id_for(actual)
		if ROSTER.definition_for(primary_canonical).is_empty():
			push_error("Primary boss is not in the canonical roster for %s: %s" \
				% [realm, actual])
			failures += 1
	for realm in ["bramblewood", "heartwood", "moonfen"]:
		var side_bosses: Array = LAYOUT.profile(realm).get("side_bosses", [])
		if side_bosses.size() != 1:
			push_error("%s should expose one optional side-boss arena" % realm)
			failures += 1
			continue
		var side_id := ROSTER.canonical_id_for(str((side_bosses[0] as Dictionary).get("id", "")))
		if ROSTER.definition_for(side_id).is_empty():
			push_error("Unknown side boss %s" % side_id)
			failures += 1
	for realm in primary_by_realm:
		var anchors := LAYOUT.boss_anchor_points(realm)
		for first_index in anchors.size():
			for second_index in range(first_index + 1, anchors.size()):
				var separation := anchors[first_index].distance_to(anchors[second_index])
				if separation + 0.001 < LAYOUT.BOSS_ARENA_MIN_SEPARATION:
					push_error("Boss arenas are too close in %s: %.2f m" \
						% [realm, separation])
					failures += 1
		var profile := LAYOUT.profile(realm)
		for pocket_value in profile.get("expansion_pockets", []):
			if not pocket_value is Dictionary:
				continue
			var pocket := pocket_value as Dictionary
			if str(pocket.get("role", "")) != "boss":
				continue
			var pocket_id := ROSTER.canonical_id_for(str(pocket.get("boss_id", "")))
			if ROSTER.definition_for(pocket_id).is_empty():
				push_error("Unknown expansion boss %s" % pocket_id)
				failures += 1

	var center := Vector3(12.0, 1.0, -8.0)
	for player in [Vector3(12.0, 1.0, 4.0), Vector3(-8.0, 1.0, -8.0),
			Vector3(12.0, 1.0, -24.0), Vector3(28.0, 1.0, -8.0)]:
		var entry := DIRECTOR.entry_position_for(center, player)
		var player_direction := Vector2(player.x - center.x, player.z - center.z).normalized()
		var boss_direction := Vector2(entry.x - center.x, entry.z - center.z).normalized()
		if center.distance_to(entry) < DIRECTOR.BOSS_ENTRY_DISTANCE - 0.001 \
				or boss_direction.dot(player_direction) > -0.99:
			push_error("Boss entry is not opposite the player at %s" % player)
			failures += 1
	var centered_entry_a := DIRECTOR.entry_position_for(center, center)
	var centered_entry_b := DIRECTOR.entry_position_for(center, center)
	if not centered_entry_a.is_equal_approx(centered_entry_b):
		push_error("Centered boss entry fallback is not deterministic")
		failures += 1
	var manager_source := FileAccess.get_file_as_string("res://scripts/systems/biome_manager.gd")
	for required_hook in ["_engage_side_boss", "_process_side_bosses", "_reset_biome_boss",
			"entry_position_for"]:
		if not manager_source.contains(required_hook):
			push_error("BiomeManager missing roster hook %s" % required_hook)
			failures += 1
	for source_path in ["res://scripts/world/bramblewood_expedition.gd",
			"res://scripts/systems/world_manager.gd"]:
		var source := FileAccess.get_file_as_string(source_path)
		if not source.contains("entry_position_for"):
			push_error("Boss spawn path missing shared entry helper: %s" % source_path)
			failures += 1
	if failures == 0:
		print("BOSS MAP ROSTER TEST PASSED")
	else:
		print("BOSS MAP ROSTER TEST FAILED: %d" % failures)
	quit(failures)
