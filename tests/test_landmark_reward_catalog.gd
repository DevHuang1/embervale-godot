extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/realm_identity_catalog.gd")
	for realm in catalog.realms():
		var profile: Dictionary = catalog.for_realm(realm)
		var reward: Dictionary = profile.get("reward", {})
		if str(reward.get("type", "")).is_empty() or int(reward.get("quantity", 0)) <= 0:
			push_error("Realm %s has no bounded landmark reward" % realm)
			quit(1)
			return
	print("ALL LANDMARK REWARD CATALOG TESTS PASSED")
	quit()
