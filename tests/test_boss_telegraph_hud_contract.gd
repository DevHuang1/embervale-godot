extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	if not source.contains("attack_telegraphed.connect(_on_boss_attack_telegraphed)") \
			or not source.contains("INCOMING") \
			or not source.contains("_boss_telegraph_until_ms") \
			or not source.contains("SAFE  ·"):
		push_error("HUD does not expose a bounded boss telegraph intent readout")
		quit(1)
		return
	var boss_source := FileAccess.get_file_as_string("res://scripts/entities/boss_base.gd")
	if not boss_source.contains("signal attack_telegraphed(kind: String, radius: float, delay: float)"):
		push_error("Boss telegraph signal contract missing")
		quit(1)
		return
	print("ALL BOSS TELEGRAPH HUD CONTRACT TESTS PASSED")
	quit()
