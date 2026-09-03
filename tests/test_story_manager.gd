extends SceneTree
## Headless validation for the StoryManager data-driven quest layer:
## registry integrity, gate evaluation, auto-grant on stage/realm progress,
## objective completion with exactly-once rewards, and save/load round-trip.

var gs
var sm

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	gs = root.get_node("/root/GameState")
	sm = root.get_node("/root/StoryManager")
	gs.save_path = "/tmp/embervale_story_test.cfg"
	gs.delete_save()
	gs.reset()

	# --- Registry loaded from JSON ---
	if sm.quest_count() != 8:
		failures += 1
		print("FAIL: expected 8 quests, got ", sm.quest_count())
	if sm.main_stage_count() != 4:
		failures += 1
		print("FAIL: expected 4 main stages, got ", sm.main_stage_count())
	var reg: Dictionary = sm.validate_registry()
	if reg.get("problems", []).size() > 0:
		failures += 1
		print("FAIL: registry problems: ", reg.get("problems"))

	# --- Fresh save: rank-0 stage means side quests stay dormant ---
	if sm.active_quest_count() != 0:
		failures += 1
		print("FAIL: fresh save should have 0 active quests, got ", sm.active_quest_count())
# --- Reaching CLAIM_SHARD auto-grants quest uses rank stage gates ---
	gs.advance_stage(GameState.QuestStage.CLAIM_SHARD)
	var active_ids := _active_ids()
	if "bramblewood.kindling_wood" not in active_ids:
		failures +=  1
		print("FAIL: kindling quest not granted after stage advance: ", active_ids)

	# --- Gather objectives complete the kindling quest; reward lands exactly once ---
	sm.notify_objective("gather", "bramble_wood", 5)
	sm.notify_objective("gather", "moss_fiber",  4)
	if not sm.is_completed("bramblewood.kindling_wood"):
		failures +=  1
		print("FAIL: kindling quest should complete after gathers")
	var gold_after: int = gs.gold
	if not sm.has_flag("quest.bramblewood.kindling_wood.done"):
		failures += 1
		print("FAIL: completion flag not set")
	var xp_after: int = gs.xp
	sm.notify_objective("gather", "bramble_wood",  5)
	if gs.gold != gold_after:
		failures +=  1
		print("FAIL: reward granted twice")
	if gs.xp != xp_after:
		failures +=  1
		print("FAIL: xp reward granted twice")

	# --- Completing kindling unlocks the gated pack-quest via quest flag ---
	if "bramblewood.thinning_pack" not in _active_ids():
		failures +=  1
		print("FAIL: thin_pack not granted after kindling done: ", _active_ids())
	sm.notify_objective("kill", "hushling", 5)
	sm.notify_objective("kill", "charger", 2)
	if not sm.is_completed("bramblewood.thinning_pack"):
		failures +=  1
		print("FAIL: thin_pack should complete after kills")

	# --- Realm gates: entering Moonfen grants its quests ---
	gs.set_current_realm("moonfen")
	sm._on_flow_signal("moonfen")
	if "moonfen.oracle_still" not in _active_ids():
		failures +=  1
		print("FAIL: oracle_still not granted in Moonfen", _active_ids())
	sm.notify_objective("kill", "fenling", 6)
	sm.notify_objective("kill", "relic_leech", 2)
	if not sm.is_completed("moonfen.oracle_still"):
		failures +=  1
		print("FAIL: oracle_still should complete after fen/leech kills")

	# --- Boss/archetype kills match via substring: biome boss key contains quest target ---
	gs.set_current_realm("heartwood")
	sm._on_flow_signal("heartwood")
	sm.notify_objective("upgrade", "", 1)
	if not sm.is_completed("heartwood.forge_fire"):
		failures +=  1
		print("FAIL: forge_fire should complete after an upgrade")
	if "heartwood.cinderhart" not in _active_ids():
		failures +=  1
		print("FAIL: cinderhart quest not granted after forge fire: ", _active_ids())
	sm.notify_objective("kill", "biome_cinderhart_colossus", 1)
	if not sm.is_completed("heartwood.cinderhart"):
		failures +=  1
		print("FAIL: cinderhart should complete via boss kill key")

	# --- Save/load round-trip keeps story state ---
	gs.save_game()
	gs.reset()
	if not gs.load_game():
		failures +=  1
		print("FAIL: story save did not load")
	if not sm.has_flag("quest.bramblewood.kindling_wood.done"):
		failures +=  1
		print("FAIL: flag lost after save/load")
	if not sm.is_completed("heartwood.cinderhart"):
		failures +=  1
		print("FAIL: story completion lost after save/load")

	gs.delete_save()
	if failures ==  0:
		print("ALL STORY MANAGER TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(1 if failures > 0 else 0)

func _active_ids() -> Array:
	var out := []
	for q in sm.active_quests():
		out.append(q.get("id", ""))
	return out
