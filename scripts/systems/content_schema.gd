extends RefCounted
class_name ContentSchema

## Versioned normalization for saved content records. Keep migrations
## additive and deterministic; never rebalance a saved item during load.

const CURRENT_VERSION: int = 1
const CONTENT_CATEGORIES: Array[String] = ["weapon", "armor", "material", "recipe",
	"realm", "boss", "objective", "enemy", "npc", "mount", "animal", "vfx",
	"sfx", "prop", "terrain_material", "skill", "loot_table", "quest"]

static func normalize_content_id(raw_id: Variant) -> String:
	return str(raw_id).strip_edges().to_lower().replace(" ", "_")

static func migrate_content_record(record: Dictionary, category: String) -> Dictionary:
	var migrated := record.duplicate(true)
	migrated["content_schema"] = maxi(int(migrated.get("content_schema", 0)), CURRENT_VERSION)
	migrated["content_id"] = normalize_content_id(migrated.get("content_id",
		migrated.get("id", "")))
	migrated["category"] = category.strip_edges().to_lower()
	return migrated

static func migrate_content_records(saved: Variant, category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	if not saved is Array:
		return result
	for raw in saved:
		if not raw is Dictionary:
			continue
		var migrated := migrate_content_record(raw, category)
		var content_id := str(migrated.get("content_id", ""))
		if content_id.is_empty() or seen.has(content_id):
			continue
		seen[content_id] = true
		result.append(migrated)
	return result

static func migrate_catalog_records(saved: Variant, category: String) -> Array[Dictionary]:
	## Normalizes asset/content catalog rows without rewriting their semantic IDs
	## or paths. Unknown categories are rejected rather than silently persisted.
	var normalized_category := category.strip_edges().to_lower()
	if normalized_category not in CONTENT_CATEGORIES:
		return []
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	if not saved is Array:
		return result
	for raw in saved:
		if not raw is Dictionary:
			continue
		var migrated := migrate_content_record(raw, normalized_category)
		var content_id := str(migrated.get("content_id", ""))
		if content_id.is_empty() or seen.has(content_id):
			continue
		seen[content_id] = true
		result.append(migrated)
	return result

static func migrate_string_list(saved: Variant, fallback: Array[String]) -> Array[String]:
	var result: Array[String] = []
	if saved is Array:
		for value in saved:
			var normalized := str(value).strip_edges().to_lower()
			if not normalized.is_empty() and normalized not in result:
				result.append(normalized)
	for required in fallback:
		if required not in result:
			result.append(required)
	return result

static func migrate_scan_state(scans: Variant, fragments: Variant,
		max_scans: int, fragments_per_scan: int) -> Dictionary:
	return {"scans": clampi(int(scans), 0, max_scans),
		"fragments": clampi(int(fragments), 0, maxi(0, fragments_per_scan - 1))}

static func migrate_analysis_state(saved: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not saved is Dictionary:
		return result
	for raw_key in saved:
		var key := str(raw_key).strip_edges().to_lower()
		if key.is_empty():
			continue
		result[key] = maxi(0, int(saved[raw_key]))
	return result

static func migrate_gear(record: Dictionary, category: String) -> Dictionary:
	var migrated := migrate_content_record(record, category)
	migrated["id"] = normalize_content_id(migrated.get("id", ""))
	if str(migrated.get("content_id", "")).is_empty():
		migrated["content_id"] = migrated["id"]
	migrated["rarity"] = maxi(0, int(migrated.get("rarity", 0)))
	if category == "weapon":
		if not migrated.has("skills"):
			migrated["skills"] = []
		if not migrated.has("upgrade_level"):
			migrated["upgrade_level"] = 0
	elif category == "armor" and not migrated.has("upgrade_level"):
		migrated["upgrade_level"] = 0
	return migrated

static func migrate_inventory(saved: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not saved is Dictionary:
		return result
	for raw_id in saved:
		var id := str(raw_id).strip_edges()
		if id.is_empty():
			continue
		result[id] = maxi(0, int(saved[raw_id]))
	return result

static func migrate_objectives(saved: Variant, valid_types: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not saved is Array:
		return result
	for raw in saved:
		if not raw is Dictionary:
			continue
		var id := str(raw.get("id", "")).strip_edges()
		var objective_type := str(raw.get("type", ""))
		if id.is_empty() or objective_type not in valid_types:
			continue
		var target := maxi(1, int(raw.get("target_qty", 1)))
		var current := clampi(int(raw.get("current_qty", 0)), 0, target)
		result.append({"id": id, "description": str(raw.get("description", id)),
			"type": objective_type, "target_qty": target, "current_qty": current,
			"completed": bool(raw.get("completed", false)) or current >= target})
	return result
