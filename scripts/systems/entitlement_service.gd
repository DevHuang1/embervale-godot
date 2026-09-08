extends RefCounted
class_name EntitlementService

signal entitlements_changed(entitlements: Array[Dictionary])

var _entitlements: Dictionary = {}

func apply_server_snapshot(rows: Array) -> void:
	_entitlements.clear()
	for raw in rows:
		if raw is Dictionary:
			var id := str(raw.get("entitlement_id", "")).strip_edges()
			if not id.is_empty():
				_entitlements[id] = raw.duplicate(true)
	entitlements_changed.emit(all())

func has_active(entitlement_id: String) -> bool:
	return bool(_entitlements.get(entitlement_id, {}).get("active", false))

func all() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in _entitlements.values():
		if value is Dictionary:
			result.append(value.duplicate(true))
	return result
