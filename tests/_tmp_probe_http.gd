extends SceneTree
func _init() -> void:
	for prop in ClassDB.class_get_property_list("HTTPRequest"):
		if str(prop.name).contains("redirect") or str(prop.name) == "timeout":
			print("PROP ", prop.name, " = ", prop.default_value)
	quit(0)
