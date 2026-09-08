extends SceneTree

## Structural route contract for a fresh save. This does not claim rendered
## or device acceptance; it protects the save-safe progression spine.

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState") as GameState
	if gs == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	gs.save_path = "/tmp/embervale_clean_route_contract.cfg"
	gs.delete_save()
	gs.reset()
	var stages := [gs.QuestStage.SEEK_SPRITE, gs.QuestStage.CLAIM_SHARD,
		gs.QuestStage.LIGHT_BEACON, gs.QuestStage.COMPLETE]
	var checkpoints := ["grove_arrival", "hushling_cleared", "shard_claimed", "beacon_relit"]
	for i in stages.size():
		gs.begin_activity("route_probe_%d" % i, gs.route_checkpoint_id)
		gs.advance_stage(stages[i])
		if gs.route_checkpoint_id != checkpoints[i]:
			push_error("Route checkpoint mismatch at stage %d" % i)
			quit(1)
			return
		if gs.get_active_objectives().is_empty() and i < 3:
			push_error("Route stage %d has no active objective" % i)
			quit(1)
			return
		if not gs.get_activity_recovery().is_empty():
			push_error("Stage progression retained stale activity recovery at stage %d" % i)
			quit(1)
			return
	gs.save_game()
	gs.reset()
	if not gs.load_game() or gs.route_checkpoint_id != "beacon_relit":
		push_error("Completed route did not survive save/load")
		quit(1)
		return
	if gs.set_route_checkpoint("beacon_relit", false):
		push_error("Repeated route checkpoint was not idempotent")
		quit(1)
		return
	gs.delete_save()
	print("ALL CLEAN ROUTE CONTRACT TESTS PASSED")
	quit()
