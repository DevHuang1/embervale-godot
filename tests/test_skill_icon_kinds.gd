extends SceneTree

func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/fight_button.gd")
	if not source.contains('"bleed":') or not source.contains("descending cuts"):
		print("FAIL: bleed skill icon treatment missing")
		quit(1)
		return
	print("ALL SKILL ICON KIND TESTS PASSED")
	quit(0)
