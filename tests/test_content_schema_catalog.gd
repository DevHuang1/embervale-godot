extends SceneTree

func _init() -> void:
	var schema := preload("res://scripts/systems/content_schema.gd")
	var records: Array[Dictionary] = schema.migrate_catalog_records([
		{"id": "Nature Tree", "path": "res://assets/models/kenney_nature/Models/tree_detailed.fbx"},
		{"content_id": "nature_tree", "path": "res://duplicate"},
		{"id": "", "path": "res://invalid"},
	], "prop")
	if records.size() != 1 or str(records[0].get("content_id", "")) != "nature_tree" \
			or str(records[0].get("category", "")) != "prop":
		push_error("Catalog record migration did not normalize stable IDs additively")
		quit(1)
		return
	if not schema.migrate_catalog_records(records, "unknown_category").is_empty():
		push_error("Unknown catalog category was accepted")
		quit(1)
		return
	print("ALL CONTENT SCHEMA CATALOG TESTS PASSED")
	quit()
