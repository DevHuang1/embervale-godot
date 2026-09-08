extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/enemy_health_bar.gd")
	var required := ["func set_values", "func notify_damage", "clampi", "clampf",
		"_damage_trail", "_poise_fill", "no_depth_test"]
	var failures: Array[String] = []
	if source.is_empty():
		failures.append("health-bar source is unavailable")
	for token in required:
		if not source.contains(token):
			failures.append("missing health-bar contract: %s" % token)
	print("ENEMY HEALTH BAR CONTRACT PASSED" if failures.is_empty() else "FAILURES: ", failures)
	quit(1 if not failures.is_empty() else 0)
