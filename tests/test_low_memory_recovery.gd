extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/autoload/game_state.gd")
	for token in ["NOTIFICATION_OS_MEMORY_WARNING", "handle_low_memory_warning", "QualityScaler"]:
		if not source.contains(token):
			push_error("Low-memory recovery hook missing: %s" % token)
			quit(1)
			return
	print("LOW MEMORY RECOVERY CONTRACT PASSED")
	quit(0)
