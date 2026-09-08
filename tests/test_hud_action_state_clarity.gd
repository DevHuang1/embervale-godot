extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	if not source.contains("auto-mark when needed"):
		push_error("Primary attack action does not explain target acquisition")
		quit(1)
		return
	if not source.contains("set_action_state(\"available\""):
		push_error("Primary attack action is missing semantic state")
		quit(1)
		return
	print("ALL HUD ACTION STATE CLARITY TESTS PASSED")
	quit()
