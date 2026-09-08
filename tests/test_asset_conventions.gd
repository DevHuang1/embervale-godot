extends SceneTree

func _init() -> void:
	var conventions := preload("res://scripts/systems/asset_conventions.gd")
	var catalog := preload("res://scripts/systems/asset_intake_catalog.gd")
	for entry in catalog.ENTRIES:
		var errors: Array[String] = conventions.validate_intake_entry(entry)
		if not errors.is_empty():
			push_error("Asset convention failure: %s" % "; ".join(errors))
			quit(1)
			return
	for socket_id in ["hand_l", "hand_r", "back"]:
		if not conventions.validate_socket(socket_id):
			push_error("Known equipment socket rejected: %s" % socket_id)
			quit(1)
			return
	if conventions.validate_socket("head") or conventions.validate_stable_id("Bad ID"):
		push_error("Asset convention negative cases were accepted")
		quit(1)
		return
	print("ASSET CONVENTIONS PASSED")
	quit(0)
