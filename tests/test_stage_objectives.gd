extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.reset()
	if not gs.get_active_objectives().is_empty():
		print("FAIL: reset changed legacy empty objective state")
		quit(1)
		return
	gs.advance_stage(gs.QuestStage.CLAIM_SHARD)
	var ids := {}
	for objective in gs.get_active_objectives():
		ids[str(objective.get("id", ""))] = true
	if not ids.has("chapter2_gather") or not ids.has("chapter2_craft"):
		print("FAIL: chapter objectives were not replaced")
		quit(1)
		return
	gs.advance_stage(gs.QuestStage.CLAIM_SHARD)
	if gs.get_active_objectives().size() != 2:
		print("FAIL: repeated stage entry duplicated objectives")
		quit(1)
		return
	print("ALL STAGE OBJECTIVE TESTS PASSED")
	quit(0)
