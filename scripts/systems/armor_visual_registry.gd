extends RefCounted
class_name ArmorVisualRegistry

## Stable equipment IDs resolve independently from stats and saves. Most body
## armor is intentionally procedural until an authored wearable with a matching
## skeleton is reviewed; shields already use imported CC0 geometry.
const ARMOR_VISUALS: Dictionary = {
	"warden_plate": {"kind": "procedural", "visual": "warden_plate"},
	"emberweave_cloak": {"kind": "procedural", "visual": "emberweave_cloak"},
	"spore_wrap": {"kind": "procedural", "visual": "spore_wrap"},
	"moonfen_cloak": {"kind": "procedural", "visual": "moonfen_cloak"},
	"round_shield": {"kind": "model", "path": "res://assets/models/weapons/quaternius/Shield_Round.fbx"},
}

static func record_for(armor_id: String) -> Dictionary:
	return (ARMOR_VISUALS.get(armor_id, {}) as Dictionary).duplicate(true)

static func path_for(armor_id: String) -> String:
	var path := str(record_for(armor_id).get("path", ""))
	return path if not path.is_empty() and ResourceLoader.exists(path) else ""

static func has_visual(armor_id: String) -> bool:
	return not record_for(armor_id).is_empty()
