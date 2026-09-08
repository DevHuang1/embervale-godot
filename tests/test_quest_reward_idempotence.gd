extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := root.get_node_or_null("/root/GameState")
	var rewards := root.get_node_or_null("/root/RewardManager")
	if state == null or rewards == null:
		push_error("Required reward autoloads are missing")
		quit(1)
		return
	state.reset()
	var before := int(state.gold)
	rewards.grant_quest_stage(1)
	var after_first := int(state.gold)
	rewards.grant_quest_stage(1)
	if after_first <= before or int(state.gold) != after_first:
		push_error("Repeated quest-stage reward was not idempotent")
		quit(1)
		return
	print("ALL QUEST REWARD IDEMPOTENCE TESTS PASSED")
	quit(0)
