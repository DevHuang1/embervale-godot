extends SceneTree

func _init() -> void:
	var p := "res://scripts/systems/terrain_relief.gd"
	var s = load(p)
	if s == null:
		print("FAIL:", p)
	else:
		print("OK:", p)
	quit(0)

