extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/entities/hushling.gd")
	var settings := FileAccess.get_file_as_string("res://scripts/ui/settings_menu.gd")
	var button := FileAccess.get_file_as_string("res://scripts/ui/fight_button.gd")
	var input_manager := FileAccess.get_file_as_string("res://scripts/autoload/input_manager.gd")
	var combat_fx := FileAccess.get_file_as_string("res://scripts/systems/combat_fx.gd")
	if not source.contains("_telegraph_duration") or not source.contains("3.0") \
			or not settings.contains("TelegraphAssistOption") \
			or not settings.contains("TouchTargetSizeOption") \
			or not button.contains("accessibility_touch_scale") \
			or not input_manager.contains("set_key_binding") \
			or not settings.contains("_build_key_bindings_section_refresh(_binding_section"):
		push_error("Accessibility control contract is incomplete")
		quit(1)
		return
	if not settings.contains("ColorSafeTelegraphOption") \
			or not settings.contains("TextScaleOption") \
			or not settings.contains("_apply_text_scale") \
			or not combat_fx.contains("TelegraphDangerCue"):
		push_error("Accessibility telegraph assist contract is incomplete")
		quit(1)
		return
	print("ACCESSIBILITY ASSISTS PASSED")
	quit(0)
