extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := get_root().get_node_or_null("/root/GameState") as GameState
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.reset()
	gs.advance_stage(gs.QuestStage.LIGHT_BEACON)
	var zone := EncounterZone.new()
	zone.tier = "elite"
	get_root().add_child(zone)
	await process_frame
	zone._on_pack_cleared()
	var complete := false
	for objective in gs.quest_objectives:
		if str(objective.get("id", "")) == "chapter3_elite":
			complete = bool(objective.get("completed", false))
	zone.queue_free()
	if not complete:
		print("FAIL: elite encounter did not complete chapter objective")
		quit(1)
		return
	print("ALL ENCOUNTER OBJECTIVE TESTS PASSED")
	quit(0)
