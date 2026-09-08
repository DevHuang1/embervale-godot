extends SceneTree

const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")

func _initialize() -> void:
	var state := GAME_STATE_SCRIPT.new()
	for i in 30:
		state.record_activity("EVENT %d" % i)
	if state.get_activity_history().size() != state.ACTIVITY_HISTORY_CAP:
		push_error("Activity history cap was not enforced")
		quit(1)
		return
	if state.get_activity_history()[0] != "EVENT 29" \
			or state.get_activity_history()[-1] != "EVENT 6":
		push_error("Activity history ordering/cap is incorrect")
		quit(1)
		return
	print("ALL ACTIVITY HISTORY TESTS PASSED")
	state.free()
	quit(0)
