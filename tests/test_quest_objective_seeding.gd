extends SceneTree

## The first 15 minutes must show a goal: a fresh route seeds its chapter
## objectives before any kill, stage advances replace them without duplicates,
## and saves written before seeding existed are healed on load.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var gs = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.save_path = "/tmp/embervale_objective_seed.cfg"
	gs.delete_save()
	gs.reset()

	var seeded: Array = gs.get_active_objectives()
	if seeded.size() < 2:
		failures += 1
		print("FAIL: fresh route seeds no visible chapter goals")
	if gs.get_objective("chapter1_hushling").is_empty():
		failures += 1
		print("FAIL: opening kill objective missing from a fresh route")
	if gs.get_objective("chapter1_gather").is_empty():
		failures += 1
		print("FAIL: opening gather objective missing from a fresh route")

	gs.update_objective("gather", "bramble_wood", 1)
	if int(gs.get_objective("chapter1_gather").get("current_qty", 0)) != 1:
		failures += 1
		print("FAIL: seeded gather objective does not track progress")

	gs.advance_stage(gs.QuestStage.CLAIM_SHARD)
	if not gs.get_objective("chapter1_hushling").is_empty():
		failures += 1
		print("FAIL: previous chapter objectives survived a stage advance")
	if gs.get_objective("chapter2_gather").is_empty() \
			or gs.get_objective("chapter2_craft").is_empty():
		failures += 1
		print("FAIL: stage advance did not seed the next chapter goals")

	# Legacy save: same stage, objectives array empty (written before seeding).
	gs.quest_objectives.clear()
	gs.save_game()
	gs.reset()
	if not gs.load_game():
		failures += 1
		print("FAIL: legacy save did not load")
	else:
		if gs.get_objective("chapter2_gather").is_empty() \
				or gs.get_objective("chapter2_craft").is_empty():
			failures += 1
			print("FAIL: load did not heal a save without seeded objectives")
		var count: int = gs.get_active_objectives().size()
		gs.save_game()
		gs.reset()
		gs.load_game()
		if gs.get_active_objectives().size() != count:
			failures += 1
			print("FAIL: re-seeding duplicated objectives across loads (%d -> %d)"
				% [count, gs.get_active_objectives().size()])

	gs.delete_save()
	if failures == 0:
		print("ALL QUEST OBJECTIVE SEEDING TESTS PASSED")
	else:
		print("QUEST OBJECTIVE SEEDING TESTS FAILED: ", failures)
	quit(1 if failures > 0 else 0)
