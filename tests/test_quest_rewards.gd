extends SceneTree

## Runtime contract for automatic quest-stage and objective rewards.

var _failures := 0
var _quest_events: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(20.0)
	watchdog.timeout.connect(func() -> void:
		print("WATCHDOG TIMEOUT — quest rewards test hung")
		quit(2))

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	var rewards := root.get_node_or_null("/root/RewardManager")
	if gs == null or rewards == null:
		_fail("required reward autoloads are missing")
		quit(_failures)
		return
	gs.save_path = "/tmp/embervale_quest_rewards_%d.cfg" % OS.get_process_id()
	gs.delete_save()
	gs.reset()
	rewards.quest_reward_granted.connect(func(completion_id: String, title: String,
			summary: Dictionary) -> void:
		_quest_events.append({"id": completion_id, "title": title, "summary": summary}))

	var before_gold := int(gs.gold)
	gs.advance_stage(GameState.QuestStage.CLAIM_SHARD)
	_assert(int(gs.gold) - before_gold == 25, "stage 1 grants 25 gold automatically")
	_assert(_quest_events.size() == 1, "stage 1 emits one quest reward event")
	_assert(str(_quest_events[0].get("summary", {}).get("source", "")) == "quest_stage",
		"stage reward carries quest-stage source metadata")
	_assert(bool(gs.quest_reward_claims.get("1", false)), "stage 1 claim is persisted")
	var stage_event_count := _quest_events.size()
	gs.advance_stage(GameState.QuestStage.CLAIM_SHARD)
	_assert(_quest_events.size() == stage_event_count, "repeating a stage emits no duplicate reward")

	var objective_before_gold := int(gs.gold)
	gs.update_objective("gather", "moss_fiber", 1)
	await process_frame
	_assert(bool(gs.get_objective("chapter2_gather").get("completed", false)),
		"unpinned gather objective completes from a matching gather event")
	_assert(int(gs.gold) - objective_before_gold == 12,
		"completed objective grants its configured gold reward")
	_assert(_quest_events.size() == stage_event_count + 1,
		"objective completion emits one quest reward event")
	_assert(bool(gs.quest_reward_claims.get("objective:chapter2_gather", false)),
		"objective claim uses a namespaced persistent key")
	var objective_event_count := _quest_events.size()
	var after_objective_gold := int(gs.gold)
	gs.update_objective("gather", "moss_fiber", 1)
	await process_frame
	_assert(_quest_events.size() == objective_event_count,
		"repeating a completed objective emits no duplicate reward")
	_assert(int(gs.gold) == after_objective_gold,
		"repeating a completed objective does not pay twice")

	var stage_two_gold := int(gs.gold)
	var stage_two_diamonds := int(gs.diamonds)
	gs.advance_stage(GameState.QuestStage.LIGHT_BEACON)
	_assert(int(gs.gold) - stage_two_gold == 50, "stage 2 grants 50 gold automatically")
	_assert(int(gs.diamonds) - stage_two_diamonds == 2, "stage 2 grants 2 diamonds automatically")
	gs.advance_stage(GameState.QuestStage.COMPLETE)
	_assert(bool(gs.quest_reward_claims.get("3", false)), "stage 3 claim is persisted")
	_assert(_quest_events.size() == objective_event_count + 2,
		"stage 2 and stage 3 each emit one reward event")

	gs.flush_save()
	var claims_before_load: Dictionary = gs.quest_reward_claims.duplicate(true)
	_assert(gs.load_game(), "quest reward claims round-trip through save/load")
	_assert(gs.quest_reward_claims == claims_before_load,
		"stage and objective claims survive save/load")

	quit(_failures)

func _assert(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_fail(message)

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: %s" % message)
