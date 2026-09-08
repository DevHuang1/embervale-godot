extends SceneTree

func _init() -> void:
	var schema := preload("res://scripts/systems/content_schema.gd")
	var inventory: Dictionary = schema.migrate_inventory({"moss_tonic": 3, "bad": -4, "": 9})
	if inventory.get("moss_tonic") != 3 or inventory.get("bad") != 0 or inventory.has(""):
		push_error("Inventory migration failed: %s" % inventory)
		quit(1)
		return
	var objectives: Array[Dictionary] = schema.migrate_objectives(
		[{"id": "gather", "type": "gather", "target_qty": 3, "current_qty": 9},
			{"id": "invalid", "type": "unknown"}], ["gather"])
	if objectives.size() != 1 or not bool(objectives[0].get("completed", false)) \
			or int(objectives[0].get("current_qty", 0)) != 3:
		push_error("Objective migration failed: %s" % objectives)
		quit(1)
		return
	var records: Array[Dictionary] = schema.migrate_content_records(
		[{"id": "Iron Sword"}, {"content_id": "iron_sword"}, "invalid",
			{"id": "Healing Potion"}], "item")
	if records.size() != 2 or str(records[0].get("content_id", "")) != "iron_sword" \
			or str(records[1].get("category", "")) != "item":
		push_error("Content record list migration failed: %s" % records)
		quit(1)
		return
	print("ALL CONTENT PROGRESS MIGRATION TESTS PASSED")
	quit()
