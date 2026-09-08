extends SceneTree

func _init() -> void:
	var reward_script := preload("res://scripts/systems/reward_manager.gd")
	var manager: Node = reward_script.new()
	if not manager.has_signal("boss_reward_choice_available"):
		push_error("RewardManager does not expose the repeat-clear choice signal")
		quit(1)
		return
	print("ALL REWARD CHOICE WIRING TESTS PASSED")
	manager.free()
	quit()
