extends Node

var _failures: Array[String] = []

func _ready() -> void:
	Engine.time_scale = 1.0
	var packed := load("res://scenes/entities/boss_matriarch.tscn") as PackedScene
	_assert_true(packed != null, "boss scene loads")
	if packed == null:
		_finish()
		return
	var boss := packed.instantiate()
	boss.is_practice = true
	add_child(boss)
	await _wait_frames(8)
	var start_pos: Vector3 = boss.global_position
	var visual := boss.get_node_or_null("Visual") as Node3D
	_assert_true(visual != null, "boss Visual node exists before phase transition")
	_assert_true(boss.is_visible_in_tree(), "boss is visible before phase transition")
	boss.take_damage(460, Vector3.ZERO, false)
	await _wait_frames(4)
	_assert_phase_state(boss, visual, start_pos, 1, "phase two")

	boss.take_damage(100, Vector3.ZERO, false)
	await _wait_frames(4)
	_assert_phase_state(boss, visual, start_pos, 2, "phase three")

	boss.take_damage(160, Vector3.ZERO, false)
	await _wait_frames(4)
	_assert_phase_state(boss, visual, start_pos, 3, "enrage")
	print("phase probe start=", start_pos, " after=", boss.global_position,
		" phase=", boss.current_phase, " visible=", boss.is_visible_in_tree())
	boss.queue_free()
	await _wait_frames(2)
	_finish()

func _assert_phase_state(boss: Node3D, visual: Node3D, start_pos: Vector3,
		expected_phase: int, label: String) -> void:
	_assert_true(int(boss.current_phase) == expected_phase,
		"boss enters " + label + " at the expected HP threshold")
	_assert_true(boss.is_visible_in_tree(),
		"boss remains visible after " + label)
	_assert_true(absf(boss.global_position.y - start_pos.y) < 1.5,
		"boss remains grounded through " + label)
	_assert_true(visual != null and visual.is_visible_in_tree(),
		"boss Visual hierarchy remains visible after " + label)

func _wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures.append(message)
		print("FAILURE: ", message)

func _finish() -> void:
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("RESULT: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("FAILURE: ", failure)
		print("RESULT: FAIL")
		get_tree().quit(1)

func _exit_tree() -> void:
	Engine.time_scale = 1.0
