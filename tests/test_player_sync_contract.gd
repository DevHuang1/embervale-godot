extends SceneTree

func _init() -> void:
	var contract := preload("res://scripts/systems/player_sync_contract.gd")
	if not contract.validate_endpoint("https://api.example.invalid/sync") \
			or contract.validate_endpoint("http://insecure.example.invalid"):
		push_error("HTTPS endpoint policy failed")
		quit(1)
		return
	var intent: Dictionary = contract.build_intent(" upgrade-1 ", "UPGRADE_WEAPON", {"item_id": "ember_sword"})
	if intent.is_empty() or str(intent.get("action", "")) != "upgrade_weapon":
		push_error("Valid gameplay intent was rejected")
		quit(1)
		return
	if not contract.build_intent("bad", "upgrade_weapon", {"gold": 12}).is_empty():
		push_error("Authoritative replacement field was accepted")
		quit(1)
		return
	var errors: Array[String] = contract.validate_response([{"id": "upgrade-1", "status": "accepted", "server_revision": 4}])
	if not errors.is_empty():
		push_error("Valid response rejected: %s" % "; ".join(errors))
		quit(1)
		return
	if contract.validate_response([{"id": "same", "status": "accepted", "server_revision": 4},
			{"id": "same", "status": "accepted", "server_revision": 4}]).is_empty():
		push_error("Duplicate sync response IDs were accepted")
		quit(1)
		return
	if contract.validate_response([{"id": "bad", "status": "accepted"}]).is_empty():
		push_error("Response without server revision was accepted")
		quit(1)
		return
	print("PLAYER SYNC CONTRACT PASSED")
	quit(0)
