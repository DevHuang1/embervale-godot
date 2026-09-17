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
	# === Safe-area inset math ===
	# A phone screen with a 48px notch band and a 60px gesture bar, rendered into
	# the same logical size: insets must scale 1:1 and never go negative.
	var inset_case: Dictionary = kit.insets_from_rects(
		Rect2i(0, 48, 1080, 2112), Vector2(1080.0, 2280.0), Vector2(1080.0, 2280.0))
	if absf(float(inset_case.get("top", -1.0)) - 48.0) > 0.01 \
			or absf(float(inset_case.get("bottom", -1.0)) - 120.0) > 0.01 \
			or float(inset_case.get("left", -1.0)) != 0.0:
		push_error("Safe-area insets are incorrect: %s" % str(inset_case))
		quit(1)
		return
	# Insets scale with a viewport that is smaller than the physical screen.
	var scaled_inset: Dictionary = kit.insets_from_rects(
		Rect2i(30, 60, 540, 1140), Vector2(600.0, 1200.0), Vector2(300.0, 600.0))
	if absf(float(scaled_inset.get("left", -1.0)) - 15.0) > 0.01 \
			or absf(float(scaled_inset.get("top", -1.0)) - 30.0) > 0.01:
		push_error("Safe-area insets do not scale to the viewport: %s" % str(scaled_inset))
		quit(1)
		return
	# A full-screen safe rect must produce no inset, and a degenerate one must be
	# ignored rather than producing negative margins.
	var full: Dictionary = kit.insets_from_rects(
		Rect2i(0, 0, 1080, 1920), Vector2(1080.0, 1920.0), Vector2(1080.0, 1920.0))
	if float(full.get("left", -1.0)) != 0.0 or float(full.get("top", -1.0)) != 0.0 \
			or float(full.get("right", -1.0)) != 0.0 or float(full.get("bottom", -1.0)) != 0.0:
		push_error("Full-screen safe rect produced phantom insets: %s" % str(full))
		quit(1)
		return
	var degenerate: Dictionary = kit.insets_from_rects(
		Rect2i(0, 0, 0, 0), Vector2(0.0, 0.0), Vector2(1080.0, 1920.0))
	if float(degenerate.get("left", -1.0)) != 0.0 or float(degenerate.get("top", -1.0)) != 0.0:
		push_error("Degenerate safe rect should yield no insets: %s" % str(degenerate))
		quit(1)
		return
	# === Menu frame: authored margins hold on large viewports, tighten on small ===
	var big_panel := Control.new()
	big_panel.anchor_right = 1.0
	big_panel.anchor_bottom = 1.0
	kit.apply_menu_frame(big_panel, Vector2(1080.0, 1920.0), 60.0, 60.0)
	if absf(big_panel.offset_left - 60.0) > 0.01 or absf(big_panel.offset_top - 60.0) > 0.01 \
			or absf(big_panel.offset_right + 60.0) > 0.01:
		push_error("Menu frame changed the authored desktop margin: %s" % str(big_panel.offset_left))
		quit(1)
		return
	var small_panel := Control.new()
	small_panel.anchor_right = 1.0
	small_panel.anchor_bottom = 1.0
	kit.apply_menu_frame(small_panel, Vector2(480.0, 800.0), 80.0, 180.0)
	if small_panel.offset_left >= 80.0 or small_panel.offset_top >= 180.0:
		push_error("Menu frame did not tighten on a small portrait screen: %s"
			% str(small_panel.offset_left))
		quit(1)
		return
	if small_panel.offset_left + (-small_panel.offset_right) >= 480.0:
		push_error("Menu frame left no usable content width on a small screen")
		quit(1)
		return
	big_panel.free()
	small_panel.free()
	print("ALL UI TOKEN TESTS PASSED")
	button.free()
	quit()
