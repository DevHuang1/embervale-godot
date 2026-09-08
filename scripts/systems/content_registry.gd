extends RefCounted
class_name ContentRegistry

## Stable-ID index over the existing data sources. This is intentionally a
## read-only adapter first: gameplay and saves continue to consume their
## current definitions while callers gain one duplicate/reference gate.

const CATEGORIES: Array[String] = ["weapon", "armor", "material", "recipe", "realm", "boss", "objective",
	"skill", "loot_table", "quest", "enemy", "npc", "mount", "animal", "vfx", "sfx", "prop", "terrain_material"]

const CURRENT_VERSION: int = 1

static func snapshot(weapons: Dictionary, armor: Dictionary, materials: Dictionary,
		recipes: Dictionary, realms: Dictionary, bosses: Dictionary,
		objectives: Dictionary = {}, enemies: Dictionary = {}, npcs: Dictionary = {},
		mounts: Dictionary = {}, animals: Dictionary = {}, vfx: Dictionary = {},
		sfx: Dictionary = {}, props: Dictionary = {}, terrain_materials: Dictionary = {},
		skills: Dictionary = {}, loot_tables: Dictionary = {}, quests: Dictionary = {}) -> Dictionary:
	return {
		"schema_version": CURRENT_VERSION,
		"weapon": weapons.duplicate(true),
		"armor": armor.duplicate(true),
		"material": materials.duplicate(true),
		"recipe": recipes.duplicate(true),
		"realm": realms.duplicate(true),
		"boss": bosses.duplicate(true),
		"objective": objectives.duplicate(true),
		"enemy": enemies.duplicate(true),
		"npc": npcs.duplicate(true),
		"mount": mounts.duplicate(true),
		"animal": animals.duplicate(true),
		"vfx": vfx.duplicate(true),
		"sfx": sfx.duplicate(true),
		"prop": props.duplicate(true),
		"terrain_material": terrain_materials.duplicate(true),
		"skill": skills.duplicate(true),
		"loot_table": loot_tables.duplicate(true),
		"quest": quests.duplicate(true),
	}

static func validate(registry: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(registry.get("schema_version", 0)) != CURRENT_VERSION:
		errors.append("Unsupported content registry schema version: %s" % registry.get("schema_version", 0))
	var global_ids: Dictionary = {}
	for category in CATEGORIES:
		var records: Dictionary = registry.get(category, {})
		for key in records:
			var id := str(key).strip_edges()
			var record: Dictionary = records[key] if records[key] is Dictionary else {}
			if id.is_empty() or str(record.get("id", id)).strip_edges() != id:
				errors.append("%s has mismatched stable ID: %s" % [category, id])
			if global_ids.has(id) and not ((str(global_ids[id]) == "weapon" and category == "recipe") or (str(global_ids[id]) == "recipe" and category == "weapon")):
				errors.append("Cross-category duplicate stable ID: %s (%s/%s)" % [
					id, str(global_ids[id]), category])
			else:
				global_ids[id] = category
			for reference_key in ["scene", "source", "path"]:
				var reference := str(record.get(reference_key, "")).strip_edges()
				if reference.begins_with("res://") and not FileAccess.file_exists(reference):
					errors.append("%s record %s references missing %s: %s" % [
						category, id, reference_key, reference])
	return errors

static func lookup(registry: Dictionary, category: String, content_id: String) -> Dictionary:
	var records: Dictionary = registry.get(category, {})
	return (records.get(content_id, {}) as Dictionary).duplicate(true)

static func resolve_asset_path(registry: Dictionary, category: String,
		content_id: String, fallback_path: String = "") -> String:
	## Runtime consumers depend on this semantic ID contract, never on a path in
	## save data. A missing replacement falls back deterministically.
	var record := lookup(registry, category, content_id)
	var candidate := str(record.get("path", "")).strip_edges()
	if candidate.begins_with("res://assets/") and FileAccess.file_exists(candidate):
		return candidate
	return fallback_path

static func asset_records(entries: Array[Dictionary]) -> Dictionary:
	## Converts the reviewed intake representatives into stable content records.
	## Files remain replaceable behind the semantic ID and are never save data.
	var result: Dictionary = {}
	for entry in entries:
		var pack_id := str(entry.get("id", "")).strip_edges()
		if pack_id.is_empty():
			continue
		var category := _asset_category(str(entry.get("category", "prop")))
		if not result.has(category):
			result[category] = {}
		var paths: Array = entry.get("runtime_paths", [])
		for path_value in paths:
			var path := str(path_value)
			var file_id := path.get_file().get_basename().to_lower().replace("-", "_")
			var stable_id := "%s_%s" % [pack_id, file_id]
			result[category][stable_id] = {
				"id": stable_id,
				"asset_pack": pack_id,
				"path": path,
				"realm": str(entry.get("realm", "all")),
				"use_case": str(entry.get("runtime_use_case", "")),
			}
	return result

static func _asset_category(intake_category: String) -> String:
	match intake_category:
		"characters": return "npc"
		"foliage", "environment": return "prop"
		"props": return "prop"
		_: return "prop"
