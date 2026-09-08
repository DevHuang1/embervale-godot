extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/realm_modular_kit_catalog.gd")
	var errors: Array[String] = catalog.validate()
	if not errors.is_empty():
		push_error("Realm modular kit validation failed: %s" % "; ".join(errors))
		quit(1)
		return
	if catalog.KITS.size() != 5:
		push_error("Expected five authored realm kits")
		quit(1)
		return
	print("REALM MODULAR KIT CATALOG PASSED")
	quit(0)
