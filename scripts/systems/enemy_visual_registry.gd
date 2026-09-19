extends RefCounted
class_name EnemyVisualRegistry

## Imported enemy models are mapped to combat archetypes, never directly to
## save data. Missing imports fall back to the existing procedural silhouette.
const ENEMY_PATHS: Dictionary = {
	"thorn_charger": "res://assets/models/enemies/quaternius/Rat.fbx",
	"mire_stalker": "res://assets/models/enemies/quaternius/Frog.fbx",
	"spore_weaver": "res://assets/models/enemies/quaternius/Spider.fbx",
	"ember_warden": "res://assets/models/enemies/quaternius/Wasp.fbx",
	"relic_leech": "res://assets/models/enemies/quaternius/Snake_angry.fbx",
}

## Combat kind -> scene. Every Bestiary kind resolves here so spawn pockets
## anywhere on the map produce the same creatures as the authored encounters
## instead of falling back to a recolored hushling.
const ENEMY_SCENES: Dictionary = {
	"hushling": "res://scenes/entities/hushling.tscn",
	"spitter": "res://scenes/entities/spitter.tscn",
	"elite_hushling": "res://scenes/entities/elite_hushling.tscn",
	"fenling": "res://scenes/entities/moonfen_fenling.tscn",
	"moonfen_fenling": "res://scenes/entities/moonfen_fenling.tscn",
	"thorn_charger": "res://scenes/entities/thorn_charger.tscn",
	"mire_stalker": "res://scenes/entities/mire_stalker.tscn",
	"spore_weaver": "res://scenes/entities/spore_weaver.tscn",
	"ember_warden": "res://scenes/entities/ember_warden.tscn",
	"relic_leech": "res://scenes/entities/relic_leech.tscn",
	"charger": "res://scenes/entities/thorn_charger.tscn",
	"ambusher": "res://scenes/entities/mire_stalker.tscn",
}

static func scene_for(enemy_id: String) -> String:
	var path := str(ENEMY_SCENES.get(enemy_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return "res://scenes/entities/hushling.tscn"
	return path

static func path_for(enemy_id: String) -> String:
	var path := str(ENEMY_PATHS.get(enemy_id, ""))
	return path if not path.is_empty() and ResourceLoader.exists(path) else ""

static func profile_for(enemy_id: String) -> String:
	return "enemy_%s" % enemy_id if not path_for(enemy_id).is_empty() else "hushling"

static func supported_ids() -> Array[String]:
	var result: Array[String] = []
	for enemy_id in ENEMY_PATHS:
		if not path_for(str(enemy_id)).is_empty():
			result.append(str(enemy_id))
	return result
