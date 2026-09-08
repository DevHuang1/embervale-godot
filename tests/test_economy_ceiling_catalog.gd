extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/economy_ceiling_catalog.gd")
	var errors: Array[String] = catalog.validate()
	if not errors.is_empty() or catalog.RULES.size() != 3:
		push_error("Economy ceiling invalid: %s" % "; ".join(errors))
		quit(1)
		return
	print("ECONOMY CEILING CATALOG PASSED")
	quit(0)
