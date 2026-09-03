extends Node

var _failures: Array[String] = []

func _ready() -> void:
	var game_state := get_node("/root/GameState")
	game_state.save_path = "/tmp/embervale_boss_contract_test.cfg"
	game_state.delete_save()
	game_state.reset()
	var packed := load("res://scenes/entities/boss_matriarch.tscn") as PackedScene
	_assert_true(packed != null, "Matriarch scene loads")
	if packed == null:
		_finish()
		return
	var boss := packed.instantiate() as HushlingMatriarch
	boss.is_practice = true
	add_child(boss)
	await get_tree().process_frame

	var warnings: Array[Dictionary] = []
	boss.attack_telegraphed.connect(func(kind: String, radius: float, delay: float) -> void:
		warnings.append({"kind": kind, "radius": radius, "delay": delay}))
	boss._perform_basic_attack(null)
	_assert_warning(warnings, "basic_slam", 3.0, 0.5)

	var target := Node3D.new()
	add_child(target)
	target.global_position = Vector3(4.0, 0.0, 2.0)
	boss._root_prison(target)
	_assert_warning(warnings, "root_prison", 3.5, 0.7)

	# AI arbitration: even with every phase-three cooldown ready, one decision
	# tick can begin only one attack family.
	boss.action_lock_timer = 0.0
	boss.current_phase = BossBase.BossPhase.PHASE_3
	boss.attack_cooldowns["basic"] = 99.0
	boss.attack_cooldowns["root_prison"] = 0.0
	boss.attack_cooldowns["realm_skill"] = 0.0
	boss.attack_cooldowns["summon"] = 0.0
	var before_arbitration := warnings.size()
	boss._try_attacks(target, 5.0)
	_assert_true(warnings.size() == before_arbitration + 1 \
			and str(warnings[-1].kind) == "root_prison" \
			and boss.is_action_locked(),
		"boss arbitration starts one readable attack family per AI tick")

	var before_storm := warnings.size()
	boss._bramble_storm()
	var storm_count := 0
	for warning in warnings.slice(before_storm):
		if str(warning.kind) == "bramble_storm" \
				and float(warning.radius) == 4.0 and float(warning.delay) >= 0.6:
			storm_count += 1
	_assert_true(storm_count == 20,
		"every Bramble Storm damage position has a protected warning")

	var initial_hp := boss.hp
	boss.take_damage(boss.thorn_guard_max, Vector3.ZERO, false)
	_assert_true(boss.hp == initial_hp - boss.thorn_guard_max,
		"thorn guard does not secretly inflate boss health")
	_assert_true(boss.vulnerability_timer > 0.0 and boss.thorn_guard == 0,
		"guard break exposes the crown")
	var exposed_hp := boss.hp
	boss.take_damage(20, Vector3.ZERO, false)
	_assert_true(exposed_hp - boss.hp == 25,
		"crown vulnerability uses the documented multiplier")
	boss._process(boss.vulnerability_duration + 0.1)
	_assert_true(boss.vulnerability_timer == 0.0 \
			and boss.thorn_guard == boss.thorn_guard_max,
		"thorn guard rearms cleanly after its bounded window")
	_assert_true(boss._guard_visuals.size() == 4,
		"guard presentation has a fixed mobile-safe visual cap")

	target.queue_free()
	boss.is_defeated = true # scheduled test eruptions become inert
	boss.queue_free()
	game_state.delete_save()
	await get_tree().process_frame
	_finish()

func _assert_warning(warnings: Array[Dictionary], kind: String,
		radius: float, minimum_delay: float) -> void:
	for warning in warnings:
		if str(warning.kind) == kind and is_equal_approx(float(warning.radius), radius) \
				and float(warning.delay) >= minimum_delay:
			_assert_true(true, "%s warning matches its damage/control radius" % kind)
			return
	_assert_true(false, "%s warning matches its damage/control radius" % kind)

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures.append(message)
		print("FAILURE: ", message)

func _finish() -> void:
	if _failures.is_empty():
		print("RESULT: PASS")
		get_tree().quit(0)
	else:
		print("RESULT: FAIL — ", _failures)
		get_tree().quit(1)
