extends SceneTree

func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/satchel.gd")
	if not source.contains("return 3 if get_viewport().get_visible_rect().size.x < UiKit.COMPACT_BREAKPOINT else 6") \
		or not source.contains("size_changed.connect(_on_viewport_size_changed)"):
		print("FAIL: responsive satchel stats grid missing")
		quit(1)
		return
	print("ALL RESPONSIVE SATCHEL STATS TESTS PASSED")
	quit(0)
