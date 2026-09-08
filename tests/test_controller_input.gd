extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/autoload/input_manager.gd")
	if not source.contains("_handle_joypad_button") \
			or not source.contains("JOY_BUTTON_RIGHT_SHOULDER") \
			or not source.contains("JOY_AXIS_LEFT_X"):
		push_error("Controller input mapping is incomplete")
		quit(1)
		return
	print("CONTROLLER INPUT CONTRACT PASSED")
	quit(0)
