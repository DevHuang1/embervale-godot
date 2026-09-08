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
