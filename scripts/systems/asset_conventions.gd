extends RefCounted
class_name AssetConventions

const STABLE_ID_PATTERN := "^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$"
const ALLOWED_SOCKET_IDS: Array[String] = ["hand_l", "hand_r", "back"]

static func validate_stable_id(content_id: String) -> bool:
	return RegEx.create_from_string(STABLE_ID_PATTERN).search(content_id) != null

static func validate_intake_entry(entry: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var entry_id := str(entry.get("id", ""))
	if not validate_stable_id(entry_id):
		errors.append("Invalid stable asset ID: %s" % entry_id)
	var owner := str(entry.get("runtime_owner", ""))
	if not owner.begins_with("res://"):
		owner = "res://" + owner
	if not owner.begins_with("res://scripts/") and not owner.begins_with("res://scenes/"):
		errors.append("Runtime owner must be project-local code or prefab: %s" % entry_id)
	for path_value in entry.get("runtime_paths", []):
		if not str(path_value).begins_with("res://assets/"):
			errors.append("Runtime asset leaves the controlled assets folder: %s" % path_value)
	return errors

static func validate_socket(socket_id: String) -> bool:
	return socket_id in ALLOWED_SOCKET_IDS
