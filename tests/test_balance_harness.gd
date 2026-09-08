extends SceneTree

const Harness = preload("res://scripts/systems/balance_harness.gd")

func _initialize() -> void:
	var sword: Dictionary = Harness.evaluate_weapon(
		{"id": "sword", "atk": 10, "swing_time": 0.5}, 100, 2)
	var fast: Dictionary = Harness.evaluate_weapon(
		{"id": "dagger", "atk": 7, "swing_time": 0.25}, 100, 2)
	var crit: Dictionary = Harness.evaluate_weapon(
		{"id": "crit", "atk": 10, "swing_time": 0.5}, 100, 2, 1.0, 0.5, 2.0)
	var survival: Dictionary = Harness.evaluate_survivability(100, 24, 4, 1.5)
	var failures := 0
	if int(sword.hits_to_kill) != 13:
		failures += 1
		print("FAIL: armor-adjusted hit count changed -> ", sword)
	if float(fast.seconds_to_kill) >= float(sword.seconds_to_kill):
		failures += 1
		print("FAIL: fast weapon should clear the target sooner")
	if float(crit.damage_per_second) <= float(sword.damage_per_second):
		failures += 1
		print("FAIL: deterministic crit projection did not increase DPS")
	if int(survival.incoming_hit) != 20 or int(survival.hits_to_defeat) != 5:
		failures += 1
		print("FAIL: incoming damage projection changed -> ", survival)
	if failures == 0:
		print("ALL BALANCE HARNESS TESTS PASSED")
	quit(failures)
