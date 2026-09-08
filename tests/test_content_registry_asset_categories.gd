extends SceneTree

func _init() -> void:
	var registry := ContentRegistry.snapshot({}, {}, {}, {}, {}, {}, {},
		{"hushling": {"id": "hushling"}},
		{"merchant": {"id": "merchant"}},
		{"horse": {"id": "horse"}},
		{"butterfly": {"id": "butterfly"}},
		{"fire_burst": {"id": "fire_burst"}},
		{"sword_swing": {"id": "sword_swing"}},
		{"altar": {"id": "altar"}},
		{"heartwood_ground": {"id": "heartwood_ground"}})
	var errors := ContentRegistry.validate(registry)
	if not errors.is_empty():
		push_error("Asset content categories rejected valid records: %s" % errors)
		quit(1)
		return
	if not ContentRegistry.lookup(registry, "npc", "merchant").has("id"):
		push_error("NPC stable-ID lookup failed")
		quit(1)
		return
	var duplicate := registry.duplicate(true)
	duplicate["animal"]["hushling"] = {"id": "hushling"}
	if ContentRegistry.validate(duplicate).is_empty():
		push_error("Cross-category duplicate was not rejected")
		quit(1)
		return
	print("ALL CONTENT REGISTRY ASSET CATEGORY TESTS PASSED")
	quit()
