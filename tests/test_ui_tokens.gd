extends SceneTree

func _init() -> void:
	var kit := preload("res://scripts/ui/ui_kit.gd")
	var button := Button.new()
	button.custom_minimum_size = Vector2(12.0, 72.0)
	kit.ensure_touch_target(button)
	if button.custom_minimum_size.x < kit.TOUCH_TARGET_MIN \
			or button.custom_minimum_size.y < kit.TOUCH_TARGET_MIN:
		push_error("UI token touch target fell below Android minimum")
		quit(1)
		return
	if button.custom_minimum_size.y != 72.0:
		push_error("Touch target helper should preserve larger authored dimensions")
		quit(1)
		return
	var compact: Dictionary = kit.responsive_metrics(Vector2(480.0, 800.0))
	if not bool(compact.get("compact", false)) or int(compact.get("columns", 0)) != 2:
		push_error("Compact responsive UI metrics are incorrect")
		quit(1)
		return
	var expanded: Dictionary = kit.responsive_metrics(Vector2(1280.0, 800.0))
	if bool(expanded.get("compact", true)) or int(expanded.get("columns", 0)) != 4:
		push_error("Expanded responsive UI metrics are incorrect")
		quit(1)
		return
	var tokens: Dictionary = kit.theme_tokens()
	var spacing: Dictionary = tokens.get("spacing", {})
	var typography: Dictionary = tokens.get("typography", {})
	var rarity: Dictionary = tokens.get("rarity", {})
	var focus: Dictionary = tokens.get("focus", {})
	if float(spacing.get("sm", 0.0)) != 8.0 \
		or float(spacing.get("lg", 0.0)) != 18.0:
		push_error("Shared spacing tokens are incomplete")
		quit(1)
		return
	if int(typography.get("body", 0)) < 18 \
		or int(typography.get("button", 0)) < int(typography.get("body", 0)):
		push_error("Shared typography tokens are not readable")
		quit(1)
		return
	if rarity.size() < 5 or not rarity.has("legendary"):
		push_error("Rarity token family is incomplete")
		quit(1)
		return
	if float(focus.get("minimum_touch", 0.0)) < kit.TOUCH_TARGET_MIN:
		push_error("Focus tokens lost the Android touch minimum")
		quit(1)
		return
	if kit.TOUCH_TARGET_MIN < 48.0:
		push_error("Accessibility touch target minimum regressed")
		quit(1)
		return
	var stats_source := FileAccess.get_file_as_string("res://scripts/ui/stats_screen.gd")
	if not stats_source.contains("_apply_responsive_layout") or not stats_source.contains("size_changed"):
		push_error("Stats screen is missing responsive viewport handling")
		quit(1)
		return
	var locked: Dictionary = kit.action_state("locked", "Complete the chapter")
	var equipped: Dictionary = kit.action_state("equipped")
	if str(locked.get("label", "")) != "LOCKED" or not bool(locked.get("disabled", false)) \
		or str(equipped.get("label", "")) != "EQUIPPED" \
		or bool(equipped.get("disabled", true)):
		push_error("Semantic action-state contract is incorrect")
		quit(1)
		return
	print("ALL UI TOKEN TESTS PASSED")
	button.free()
	quit()
