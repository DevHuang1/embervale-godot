extends SceneTree

func _initialize() -> void:
	var game_state_source := FileAccess.get_file_as_string("res://scripts/autoload/game_state.gd")
	var source := FileAccess.get_file_as_string("res://scripts/ui/satchel.gd")
	for field in ["game_state.stat_str", "game_state.stat_dex", "game_state.stat_luk", "game_state.stat_end"]:
		if not source.contains(field):
			print("FAIL: missing visible player stat ", field)
			quit(1)
			return
	var stats_screen_source := FileAccess.get_file_as_string("res://scripts/ui/stats_screen.gd")
	if not stats_screen_source.contains("BUILD GUIDE") \
			or not stats_screen_source.contains("PREVIEW ONLY") \
			or not stats_screen_source.contains("CURRENT") \
			or not stats_screen_source.contains("PREVIEW"):
		print("FAIL: stat presets are not exposed as preview-only UI")
		quit(1)
		return
	if not game_state_source.contains("project_stat_preset"):
		print("FAIL: stat preset projection helper is missing")
		quit(1)
		return
	for preset in ["vanguard", "skirmisher", "warden", "arcanist"]:
		if not game_state_source.contains('"%s"' % preset):
			print("FAIL: missing readable stat preset ", preset)
			quit(1)
			return
	print("ALL PLAYER STAT PROJECTION TESTS PASSED")
	quit(0)
