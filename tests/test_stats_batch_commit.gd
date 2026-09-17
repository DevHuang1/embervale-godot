extends SceneTree

var failures: Array[String] = []
var refresh_events := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game_state: Node = root.get_node("GameState")
	game_state.save_path = "/private/tmp/embervale_stats_batch_commit.cfg"
	game_state.reset()
	game_state.stat_points = 4
	game_state.stats_changed.connect(_on_stats_changed)
	var summary: Dictionary = game_state.call("commit_stat_allocation", {"str": 2, "vit": 1})
	if not bool(summary.get("success", false)):
		_fail("Valid batch stat commit failed")
	if refresh_events != 1:
		_fail("Batch stat commit emitted %d refreshes" % refresh_events)
	if game_state.stat_str != 2 or game_state.stat_vit != 1 or game_state.stat_points != 1:
		_fail("Batch stat commit did not apply the requested allocation")
	if game_state.get_base_auto_damage() <= game_state.equipped_weapon.get("atk", 0):
		_fail("Derived attack did not reflect the staged strength points")
	var before_str: int = int(game_state.get("stat_str"))
	var before_points: int = int(game_state.get("stat_points"))
	var invalid: Dictionary = game_state.call("commit_stat_allocation", {"not_a_stat": 1})
	if bool(invalid.get("success", false)) or game_state.stat_str != before_str or game_state.stat_points != before_points:
		_fail("Invalid stat allocation mutated state")
	var insufficient: Dictionary = game_state.call("commit_stat_allocation", {"dex": 99})
	if bool(insufficient.get("success", false)) or game_state.stat_dex != 0:
		_fail("Insufficient stat allocation mutated state")
	game_state.flush_save()
	if not game_state.load_game():
		_fail("Stat save/load round trip failed")
	if game_state.stat_str != 2 or game_state.stat_vit != 1 or game_state.stat_points != 1:
		_fail("Stat save/load did not preserve the batch commit")
	game_state.delete_save()
	if failures.is_empty():
		print("STATS BATCH COMMIT TESTS PASSED")
	else:
		print("STATS BATCH COMMIT TESTS FAILED: ", failures)
	quit(1 if not failures.is_empty() else 0)

func _on_stats_changed() -> void:
	refresh_events += 1

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL: ", message)
