extends RefCounted
class_name ArmorVisualRegistry

## Stable equipment IDs resolve independently from stats and saves. Most body
## armor is intentionally procedural; a record with `kind: "model"` instead
## mounts one rigid CC0 prop on a skeleton bone (no skinning), which is the
## supported shape for imported armor pieces.
##
## Model record fields:
##   path             res:// .fbx/.glb, authored around its own pivot
##   bone             skeleton bone or socket the piece rides (default Torso)
##   offset           local position after the bone bind (Vector3)
##   rotation_degrees local rotation after the bone bind (Vector3)
##   length           authored size in metres for measured normalization
const ARMOR_VISUALS: Dictionary = {
	"warden_plate": {"kind": "procedural", "visual": "warden_plate"},
	"emberweave_cloak": {"kind": "procedural", "visual": "emberweave_cloak"},
	"spore_wrap": {"kind": "procedural", "visual": "spore_wrap"},
	"moonfen_cloak": {"kind": "procedural", "visual": "moonfen_cloak"},
}

const DEFAULT_MODEL_BONE := "Torso"
const DEFAULT_MODEL_LENGTH := 0.9

static func record_for(armor_id: String) -> Dictionary:
	return (ARMOR_VISUALS.get(armor_id, {}) as Dictionary).duplicate(true)

static func path_for(armor_id: String) -> String:
	var path := str(record_for(armor_id).get("path", ""))
	return path if not path.is_empty() and ResourceLoader.exists(path) else ""

static func has_visual(armor_id: String) -> bool:
	return not record_for(armor_id).is_empty()

static func is_model(armor_id: String) -> bool:
	return str(record_for(armor_id).get("kind", "")) == "model"

static func model_bone(armor_id: String) -> String:
	return str(record_for(armor_id).get("bone", DEFAULT_MODEL_BONE))

static func model_length(armor_id: String) -> float:
	return float(record_for(armor_id).get("length", DEFAULT_MODEL_LENGTH))

static func model_offset(armor_id: String) -> Vector3:
	return record_for(armor_id).get("offset", Vector3.ZERO)

static func model_rotation_degrees(armor_id: String) -> Vector3:
	return record_for(armor_id).get("rotation_degrees", Vector3.ZERO)

static func model_path(armor_id: String) -> String:
	if not is_model(armor_id):
		return ""
	return path_for(armor_id)
