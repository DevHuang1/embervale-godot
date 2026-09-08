extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/autoload/game_state.gd")
	for token in ["NOTIFICATION_APPLICATION_PAUSED", "handle_application_paused",
			"handle_application_resumed", "application_paused", "application_resumed"]:
		if not source.contains(token):
			push_error("Application lifecycle hook missing: %s" % token)
			quit(1)
			return
	print("APPLICATION LIFECYCLE CONTRACT PASSED")
	quit(0)
