extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node("GameState")
	gs.reset()
	gs.stat_str = 20
	gs.stat_dex = 20
	gs.stat_luk = 20
	gs.stat_end = 20
	gs.stat_vit = 20
	if gs.attack_damage_bonus() != 20 or not is_equal_approx(gs.attack_speed_mult(), 1.6) \
			or not is_equal_approx(gs.crit_chance(), 0.25):
		push_error("early stat values changed unexpectedly")
		quit(1)
		return
	gs.stat_str = 40
	gs.stat_dex = 40
	gs.stat_luk = 40
	if gs.attack_damage_bonus() != 30 or not is_equal_approx(gs.attack_speed_mult(), 1.9) \
			or not is_equal_approx(gs.crit_chance(), 0.35):
		push_error("soft cap projection failed")
		quit(1)
		return
	print("ALL STAT SOFT CAP TESTS PASSED")
	quit()
