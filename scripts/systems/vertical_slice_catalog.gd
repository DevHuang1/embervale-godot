extends RefCounted
class_name VerticalSliceCatalog

## The deliberately small content set used to prove the first route end to end.
## Stable IDs are gameplay-facing; paths are replaceable implementation details.
const SET: Dictionary = {
	"hero_loadout": {
		"id": "starter_warden",
		"scene": "res://scenes/entities/hero.tscn",
		"weapon_id": "thorn_mace",
		"armor_id": "warden_plate",
	},
	"vendor": {
		"id": "grove_trader",
		"scene": "res://scenes/world/service_npc.tscn",
		"model_profile": "merchant",
		"service": "shop",
	},
	"craftsman": {
		"id": "grove_craftsman",
		"scene": "res://scenes/world/service_npc.tscn",
		"model_profile": "craftsman",
		"service": "crafting",
	},
	"animal": {
		"id": "grove_ambient_life",
		"script": "res://scripts/systems/ambient_life_field.gd",
		"behavior": "bounded_butterflies_and_fireflies",
	},
	"enemy_factions": [
		{"id": "hushling", "scene": "res://scenes/entities/hushling.tscn", "role": "attacker"},
		{"id": "spitter", "scene": "res://scenes/entities/spitter.tscn", "role": "ranged_controller"},
		{"id": "thorn_charger", "scene": "res://scenes/entities/thorn_charger.tscn", "role": "disruptor"},
	],
	"boss": {
		"id": "bramblewood_thornwarden",
		"scene": "res://scenes/entities/boss_bramblewood_thornwarden.tscn",
		"reward_id": "bramblewood_thornwarden",
	},
	"realm_kit": {
		"id": "whispergrove",
		"scene": "res://scenes/world/grove.tscn",
		"activity": "gathering_and_beacon",
		"landmark_pack": "kenney_nature",
	},
}

static func validate() -> Array[String]:
	var errors: Array[String] = []
	for key in ["hero_loadout", "vendor", "craftsman", "animal", "boss", "realm_kit"]:
		var record: Dictionary = SET.get(key, {})
		if record.is_empty():
			errors.append("Missing vertical-slice record: %s" % key)
			continue
		var path_key := "script" if key == "animal" else "scene"
		var path := str(record.get(path_key, ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			errors.append("Missing vertical-slice %s resource: %s" % [key, path])
	var factions: Array = SET.get("enemy_factions", [])
	if factions.size() != 3:
		errors.append("Vertical slice requires exactly three enemy factions")
	for faction in factions:
		var scene_path := str(faction.get("scene", ""))
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			errors.append("Missing enemy faction resource: %s" % faction.get("id", ""))
	return errors

static func loadable_resources() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in ["hero_loadout", "vendor", "craftsman", "animal", "boss", "realm_kit"]:
		var record: Dictionary = SET[key]
		result.append({"id": str(record.get("id", "")), "path": str(record.get("scene", record.get("script", "")))})
	for faction in SET["enemy_factions"]:
		result.append({"id": str(faction.get("id", "")), "path": str(faction.get("scene", ""))})
	return result
