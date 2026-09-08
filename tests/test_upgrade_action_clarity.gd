extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/satchel.gd")
	if not source.contains("+%d ATK") or not source.contains("+%d DEF"):
		push_error("Upgrade actions do not explain their practical stat gain")
		quit(1)
		return
	var game_source := FileAccess.get_file_as_string("res://scripts/autoload/game_state.gd")
	if not game_source.contains("\"stat_gain\""):
		push_error("Upgrade cost contract does not expose stat gain")
		quit(1)
		return
	print("ALL UPGRADE ACTION CLARITY TESTS PASSED")
	quit()
