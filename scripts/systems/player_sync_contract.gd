extends RefCounted
class_name PlayerSyncContract

## Transport-neutral contract for an authenticated Android sync adapter.
## This file performs no network calls and never accepts client-owned balances.

const ALLOWED_ACTIONS: Array[String] = [
	"purchase", "sell", "craft", "upgrade_weapon", "upgrade_armor",
	"equip", "complete_quest", "consume_scan", "claim_reward", "refund"
]
const REQUIRED_RESPONSE_FIELDS: Array[String] = ["id", "status", "server_revision"]

static func validate_endpoint(endpoint: String) -> bool:
	return endpoint.strip_edges().begins_with("https://")

static func build_intent(action_id: String, action: String, payload: Dictionary) -> Dictionary:
	var normalized_id := action_id.strip_edges()
	var normalized_action := action.strip_edges().to_lower()
	if normalized_id.is_empty() or normalized_action not in ALLOWED_ACTIONS:
		return {}
	if _contains_authoritative_field(payload):
		return {}
	return {"id": normalized_id, "action": normalized_action,
		"payload": payload.duplicate(true)}

static func validate_response(response: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not response is Array:
		errors.append("Sync response must be an array")
		return errors
	var seen_ids: Dictionary = {}
	for raw in response:
		if not raw is Dictionary:
			errors.append("Sync response entry must be an object")
			continue
		for field in REQUIRED_RESPONSE_FIELDS:
			if not raw.has(field) or str(raw.get(field, "")).strip_edges().is_empty():
				errors.append("Sync response missing %s" % field)
		var response_id := str(raw.get("id", "")).strip_edges()
		if not response_id.is_empty() and seen_ids.has(response_id):
			errors.append("Duplicate sync response id: %s" % response_id)
		seen_ids[response_id] = true
		if not raw.has("server_revision") or int(raw.get("server_revision", -1)) < 0:
			errors.append("Invalid sync server revision")
		if str(raw.get("status", "")).to_lower() not in ["accepted", "acknowledged", "retryable", "rejected"]:
			errors.append("Unknown sync response status")
	return errors

static func _contains_authoritative_field(value: Variant) -> bool:
	const FORBIDDEN: Array[String] = ["gold", "diamonds", "balance", "inventory",
		"equipment", "stats", "player_state"]
	if value is Dictionary:
		for key in value:
			if str(key).strip_edges().to_lower() in FORBIDDEN:
				return true
			if _contains_authoritative_field(value[key]):
				return true
	elif value is Array:
		for item in value:
			if _contains_authoritative_field(item):
				return true
	return false
