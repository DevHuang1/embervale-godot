extends SceneTree

func _init() -> void:
	var schema := preload("res://scripts/systems/content_schema.gd")
	if schema.normalize_content_id(" Ember Sword ") != "ember_sword":
		push_error("Stable content ID normalization failed")
	var record: Dictionary = schema.migrate_content_record(
		{"id": "Iron Shard", "content_schema": 0}, "material")
	if str(record.get("content_id", "")) != "iron_shard" \
			or str(record.get("category", "")) != "material" \
			or int(record.get("content_schema", 0)) != schema.CURRENT_VERSION:
		push_error("Versioned content record migration failed: %s" % record)
	var old_weapon: Dictionary = {"id": "ember_sword", "atk": 8}
	var migrated: Dictionary = schema.migrate_gear(old_weapon, "weapon")
	if int(migrated.get("content_schema", 0)) != schema.CURRENT_VERSION \
		or migrated.get("skills", null) == null \
		or int(migrated.get("upgrade_level", -1)) != 0:
		push_error("Weapon content migration failed: %s" % migrated)
		quit(1)
		return
	var old_armor: Dictionary = {"id": "warden_plate", "defense": 3}
	migrated = schema.migrate_gear(old_armor, "armor")
	if int(migrated.get("upgrade_level", -1)) != 0:
		push_error("Armor content migration failed: %s" % migrated)
		quit(1)
		return
	print("ALL CONTENT SCHEMA TESTS PASSED")
	quit()
