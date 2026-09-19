extends SceneTree

const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")

func _init() -> void:
	var failures := 0
	for step in GAME_STATE_SCRIPT.ONBOARDING_STEPS:
		if str(step.get("signal", "")).is_empty():
			failures += 1
			print("FAIL: onboarding step lacks a diegetic signal: ", step.get("id", ""))
		if bool(step.get("blocking", true)):
			failures += 1
			print("FAIL: onboarding step is blocking: ", step.get("id", ""))
	if GAME_STATE_SCRIPT.ONBOARDING_STEPS.size() < 6:
		failures += 1
		print("FAIL: onboarding route is missing a core teaching beat")
	if failures == 0:
		print("ALL ONBOARDING TEACHING CONTRACT TESTS PASSED")
	else:
		push_error("%d onboarding teaching contract failures" % failures)
	quit(1 if failures > 0 else 0)
