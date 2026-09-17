extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/settings_menu.gd")
	_assert(source.contains("get_visible_rect().size"), "settings must read viewport size")
	_assert(source.contains("clampf(viewport_size.x - margin * 2.0"), "settings width must be responsive")
	_assert(source.contains("add_theme_constant_override"), "settings compact spacing override missing")
	_assert(source.contains("var vbox: VBoxContainer = rows_box"), "dynamic rows need a valid container")
	_assert(source.contains("_build_world_view_row"), "world view distance option missing")
	quit()

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
