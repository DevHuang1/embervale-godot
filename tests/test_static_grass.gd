extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://assets/shaders/grass_blade.gdshader")
	for line in source.split("\n"):
		if line.strip_edges().begins_with("//"):
			source = source.replace(line, "")
	_assert(not source.contains("TIME"), "static grass shader must not use TIME")
	_assert(not source.contains("world_wind"), "static grass shader must not use world wind")
	_assert(not source.contains("world_hero_pos_radius"), "static grass shader must not use trample globals")
	_assert(not source.contains("world_pusher_1"), "static grass shader must not use pusher globals")
	quit()

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
