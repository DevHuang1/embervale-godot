extends Node

var _failures: Array[String] = []

func _ready() -> void:
	var game_state := get_node("/root/GameState")
	game_state.save_path = "/tmp/embervale_boss_lifecycle_test.cfg"
	game_state.delete_save()
	game_state.reset()

	var boss_scene := load("res://scenes/entities/boss_matriarch.tscn") as PackedScene
	_assert_true(boss_scene != null, "Matriarch scene loads for lifecycle validation")
	if boss_scene == null:
		_finish(game_state)
		return
	var boss := boss_scene.instantiate() as HushlingMatriarch
	boss.is_practice = true
	add_child(boss)
	boss.set_encounter_origin(Vector3(3.0, 0.0, -2.0))
	await get_tree().process_frame

	_assert_true(boss._arena_growths.size() == 12,
		"arena transformation has a fixed twelve-mesh cap")
	_assert_true(_visible_growths(boss) == 0,
		"phase one leaves the arena silhouette open")
	boss._set_arena_phase(int(BossBase.BossPhase.PHASE_2))
	_assert_true(_visible_growths(boss) == 6,
		"phase two raises only the outer arena ring")
	boss._set_arena_phase(int(BossBase.BossPhase.PHASE_3))
	_assert_true(_visible_growths(boss) == 12,
		"phase three completes the bounded arena transformation")
	_assert_true(boss._arena_transform_root.find_children(
		"*", "CollisionObject3D", true, false).is_empty(),
		"arena transformation adds no gameplay collision")

	var stale_generation := boss.encounter_generation
	var summon := Node3D.new()
	add_child(summon)
	boss.summoned_hushlings.append(summon)
	boss.hp = 123
	boss.current_phase = BossBase.BossPhase.ENRAGE
	boss.enrage_active = true
	boss.vulnerability_timer = 2.0
	boss.global_position = Vector3(18.0, 0.0, 11.0)
	boss.reset_encounter()
	_assert_true(boss.encounter_generation == stale_generation + 1,
		"reset invalidates every delayed callback from the failed attempt")
	_assert_true(boss.hp == boss.max_hp \
			and boss.current_phase == BossBase.BossPhase.PHASE_1,
		"reset restores full health and phase one")
	_assert_true(boss.global_position.is_equal_approx(Vector3(3.0, 0.0, -2.0)),
		"reset returns the boss to its authored arena origin")
	_assert_true(boss.summoned_hushlings.is_empty() \
			and boss.vulnerability_timer == 0.0 \
			and boss.thorn_guard == boss.thorn_guard_max,
		"reset clears summons and restores the crown guard")
	_assert_true(_visible_growths(boss) == 0,
		"reset removes all phase-transformation silhouettes")

	var death_sequence_events := {"count": 0}
	var death_events := {"count": 0}
	boss.death_sequence_started.connect(func(_dead_boss: Node3D) -> void:
		death_sequence_events.count += 1)
	boss.died.connect(func() -> void: death_events.count += 1)
	boss.die()
	boss.die()
	_assert_true(int(death_sequence_events.count) == 1,
		"boss kill presentation starts exactly once at lethal confirmation")
	boss._on_death_finished()
	boss._on_death_finished()
	_assert_true(int(death_events.count) == 1,
		"boss completion emits exactly one death event")
	await get_tree().process_frame

	# A completed save reconstructs aftermath instead of reopening the
	# first-clear encounter. This is the authoritative reload path.
	game_state.reset()
	game_state.current_stage = game_state.QuestStage.COMPLETE
	game_state.boss_first_kills[WorldManager.MATRIARCH_BOSS_KEY] = true
	var grove_scene := load("res://scenes/world/grove.tscn") as PackedScene
	_assert_true(grove_scene != null, "Grove scene loads for aftermath reconstruction")
	if grove_scene != null:
		var grove := grove_scene.instantiate()
		add_child(grove)
		await get_tree().process_frame
		await get_tree().process_frame
		var aftermath := grove.get_node_or_null("MatriarchAftermath")
		_assert_true(aftermath != null,
			"saved first clear reconstructs the Matriarch aftermath")
		_assert_true(grove.get("matriarch") == null,
			"saved first clear does not respawn the progression boss")
		if aftermath != null:
			_assert_true(aftermath.find_children(
				"CleansedSprout_*", "MeshInstance3D", true, false).size() == 8,
				"aftermath landmark has a fixed eight-mesh cap")
			_assert_true(aftermath.find_children(
				"*", "CollisionObject3D", true, false).is_empty(),
				"persistent aftermath adds no navigation collision")
		grove.queue_free()
		await get_tree().process_frame

	_finish(game_state)

func _visible_growths(boss: HushlingMatriarch) -> int:
	var count := 0
	for growth in boss._arena_growths:
		if is_instance_valid(growth) and growth.visible:
			count += 1
	return count

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures.append(message)
		print("FAILURE: ", message)

func _finish(game_state: Node) -> void:
	game_state.delete_save()
	if _failures.is_empty():
		print("RESULT: PASS")
		get_tree().quit(0)
	else:
		print("RESULT: FAIL — ", _failures)
		get_tree().quit(1)
