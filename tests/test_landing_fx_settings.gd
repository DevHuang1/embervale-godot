extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/entities/hero.gd")
	var settings := FileAccess.get_file_as_string("res://scripts/ui/settings_menu.gd")
	_assert(source.contains("func set_landing_fx_mode"), "hero landing setter missing")
	_assert(source.contains("func get_landing_fx_mode"), "hero landing getter missing")
	_assert(source.contains("_landing_fx_scale"), "landing FX scale missing")
	_assert(settings.contains("_build_landing_fx_row"), "settings landing row missing")
	_assert(settings.contains("_save_landing_fx_mode"), "settings landing persistence missing")
	quit()

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
