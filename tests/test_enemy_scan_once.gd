extends SceneTree

func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	if not source.contains("_analyzed_enemy_id") or not source.contains("analyzed or game_state.scans_remaining <= 0"):
		print("FAIL: enemy analysis repeat guard missing")
		quit(1)
		return
	print("ALL ENEMY SCAN ONCE TESTS PASSED")
	quit(0)
