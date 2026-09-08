extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var game_state := get_root().get_node_or_null("GameState")
	if game_state == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	game_state.save_path = "/tmp/embervale_route_checkpoint_test.cfg"
	game_state.delete_save()
	game_state.reset()
	if game_state.route_checkpoint_id != "grove_arrival":
		push_error("reset checkpoint mismatch")
		quit(1)
		return
	if not game_state.set_route_checkpoint("Hushling_Cleared", false):
		push_error("first checkpoint was not accepted")
		quit(1)
		return
	if game_state.set_route_checkpoint("hushling_cleared", false):
		push_error("duplicate checkpoint changed state")
		quit(1)
		return
	game_state.save_game()
	game_state.reset()
	if not game_state.load_game() or game_state.route_checkpoint_id != "hushling_cleared":
		push_error("checkpoint did not survive save/load")
		quit(1)
		return
	if game_state._checkpoint_for_stage(GameState.QuestStage.COMPLETE) != "beacon_relit":
		push_error("stage checkpoint mapping mismatch")
		quit(1)
		return
	game_state.set_route_checkpoint_for_stage(GameState.QuestStage.CLAIM_SHARD, false)
	if game_state.route_respawn_position != Vector2(-5, -5):
		push_error("checkpoint respawn position mismatch")
		quit(1)
		return
	game_state.delete_save()
	print("ALL ROUTE CHECKPOINT TESTS PASSED")
	quit()
