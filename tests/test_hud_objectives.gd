extends SceneTree

func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	if not source.contains("_refresh_lesson_action()") \
		or not source.contains("if objective_label == null:\n\t\treturn"):
		print("FAIL: lesson refresh remains coupled to objective label rendering")
		quit(1)
		return
	if not source.contains("WHY") or not source.contains("RISK") \
			or not source.contains("REWARD") or not source.contains("NEXT"):
		print("FAIL: quest journal lacks why/risk/reward/next context")
		quit(1)
		return
	if not source.contains("ROUTE MAP  ·  LAST SAFE PATH") or not source.contains("ActivityRecovery"):
		print("FAIL: quest journal lacks route map or recovery context")
		quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	var gs = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.quest_objectives.clear()
	gs.add_objective("test_gather", "Gather test moss", "gather", 3)
	if not gs.pin_objective("test_gather") or gs.get_pinned_objective().is_empty():
		print("FAIL: objective could not be pinned")
		quit(1)
		return
	if not gs.unpin_objective("test_gather") or not gs.get_pinned_objective().is_empty():
		print("FAIL: objective could not be unpinned")
		quit(1)
		return
	if not gs.pin_objective("test_gather"):
		print("FAIL: objective could not be re-pinned")
		quit(1)
		return
	var active: Array = gs.get_active_objectives()
	if active.size() != 1 or int(active[0].get("target_qty", 0)) != 3:
		print("FAIL: objective contract not save-backed")
		quit(1)
		return
	gs.update_objective("gather", "test_gather", 2)
	if int(gs.quest_objectives[0].get("current_qty", 0)) != 2:
		print("FAIL: objective progress did not update")
		quit(1)
		return
	print("ALL HUD OBJECTIVE TESTS PASSED")
	quit(0)
