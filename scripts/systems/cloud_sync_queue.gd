extends RefCounted
class_name CloudSyncQueue

## Offline-first action queue for the future authenticated API. The client
## submits intent, never authoritative balances; action IDs make retries safe.

var _actions: Array[Dictionary] = []
const MAX_PENDING_ACTIONS: int = 128
const FORBIDDEN_AUTHORITATIVE_FIELDS: Array[String] = ["gold", "diamonds",
	"balance", "inventory", "equipment", "stats", "player_state"]

func enqueue(action_id: String, action: String, payload: Dictionary) -> bool:
	var normalized := action_id.strip_edges()
	if normalized.is_empty() or action.strip_edges().is_empty():
		return false
	if _contains_forbidden_field(payload):
		return false
	if _actions.size() >= MAX_PENDING_ACTIONS:
		return false
	for existing in _actions:
		if str(existing.get("id", "")) == normalized:
			return false
	_actions.append({"id": normalized, "action": action.strip_edges(),
			"payload": payload.duplicate(true), "attempts": 0,
			"delivery_status": "pending", "last_error": ""})
	return true

func _contains_forbidden_field(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if str(key).strip_edges().to_lower() in FORBIDDEN_AUTHORITATIVE_FIELDS:
				return true
			if _contains_forbidden_field(value[key]):
				return true
	elif value is Array:
		for item in value:
			if _contains_forbidden_field(item):
				return true
	return false

func pending() -> Array[Dictionary]:
	return _actions.duplicate(true)

func pending_batch(limit: int = 32) -> Array[Dictionary]:
	## Transport adapters may send only a bounded batch after authentication.
	var bounded: Array[Dictionary] = []
	for entry in _actions:
		if bounded.size() >= maxi(1, limit):
			break
		if str(entry.get("delivery_status", "pending")) in ["pending", "retryable"]:
			bounded.append(entry.duplicate(true))
	return bounded

func mark_attempted(action_id: String) -> bool:
	for entry in _actions:
		if str(entry.get("id", "")) == action_id:
			entry["attempts"] = int(entry.get("attempts", 0)) + 1
			return true
	return false

func acknowledge(action_id: String) -> bool:
	for index in _actions.size():
		if str(_actions[index].get("id", "")) == action_id:
			_actions.remove_at(index)
			return true
	return false

func reconcile(response: Variant) -> Dictionary:
	## Applies only delivery state from a future authenticated transport. It never
	## mutates currencies, inventory, or other authoritative player state.
	var summary := {"acknowledged": 0, "retryable": 0, "rejected": 0}
	if not response is Array:
		return summary
	for raw in response:
		if not raw is Dictionary:
			continue
		var action_id := str(raw.get("id", "")).strip_edges()
		var status := str(raw.get("status", "")).strip_edges().to_lower()
		if action_id.is_empty():
			continue
		match status:
			"accepted", "acknowledged":
				if acknowledge(action_id):
					summary["acknowledged"] = int(summary["acknowledged"]) + 1
			"retry", "retryable", "offline", "timeout":
				if _set_delivery_state(action_id, "retryable", str(raw.get("error", status))):
					summary["retryable"] = int(summary["retryable"]) + 1
			"rejected", "invalid", "conflict":
				if _set_delivery_state(action_id, "rejected", str(raw.get("error", status))):
					summary["rejected"] = int(summary["rejected"]) + 1
	return summary

func _set_delivery_state(action_id: String, status: String, error: String) -> bool:
	for entry in _actions:
		if str(entry.get("id", "")) == action_id:
			entry["delivery_status"] = status
			entry["last_error"] = error
			return true
	return false

func restore(saved: Variant) -> void:
	_actions.clear()
	if not saved is Array:
		return
	for raw in saved:
		if not raw is Dictionary:
			continue
		var action_id := str(raw.get("id", "")).strip_edges()
		var action := str(raw.get("action", "")).strip_edges()
		if action_id.is_empty() or action.is_empty() or not enqueue(action_id, action,
			raw.get("payload", {}) if raw.get("payload", {}) is Dictionary else {}):
			continue
		_actions[-1]["attempts"] = maxi(0, int(raw.get("attempts", 0)))
		var delivery_status := str(raw.get("delivery_status", "pending")).strip_edges().to_lower()
		if delivery_status in ["pending", "retryable", "rejected"]:
			_actions[-1]["delivery_status"] = delivery_status
		_actions[-1]["last_error"] = str(raw.get("last_error", ""))
