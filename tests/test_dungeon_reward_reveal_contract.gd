extends SceneTree

func _init() -> void:
	var hud := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	var selector := FileAccess.get_file_as_string("res://scripts/ui/dungeon_select.gd")
	_assert_true(hud.contains("_connect_dungeon_completion"), "HUD listens for dungeon completion")
	_assert_true(hud.contains("_show_reward_reveal_entries"), "completion opens reward reveal")
	_assert_true(selector.contains("dungeon_%s_complete"), "selector reads saved completion")
	print("ALL DUNGEON REWARD REVEAL TESTS PASSED")
	quit()

func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		push_error("FAIL: %s" % label)
		quit(1)
