extends SceneTree

## Headless regression: kill -> stage advance -> defeat loop.
## Verifies no script errors, combat stays functional, screen fx resets,
## tree never left paused, and hero strikes still land afterwards.

var _errors := 0

func _initialize() -> void:
	_run.call_deferred()

func _seconds(s: float) -> void:
	await create_timer(s).timeout

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	var scene: Node = (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(10)

	var hero := scene.get_node("Hero")
	var hushling := scene.get_node_or_null("Hushling")
	var failures := 0
	if hero == null or hushling == null:
		print("FAIL: hero/hushling missing")
		quit(1)
		return

	# --- Kill the starter hushling (death anim runs ~0.75s before quest advances) ---
	hushling.take_damage(999, Vector3.FORWARD)
	await _seconds(1.5)
	if gs.current_stage != 1:
		failures += 1
		print("FAIL: stage did not advance after kill -> ", gs.current_stage)

	# --- Tree must not be paused; hero must process ---
	if paused:
		failures += 1
		print("FAIL: tree paused after kill")

	# --- Hero strike still lands on a spawned pack enemy ---
	var enemies := get_nodes_in_group("enemy")
	var target: Node = null
	for e in enemies:
		if is_instance_valid(e) and not e.is_dead():
			target = e
			break
	if target == null:
		failures += 1
		print("FAIL: no pack enemy alive to strike")
	else:
		gs.enemy_target = target
		gs.engage_enemy(target)
		hero.global_position = target.global_position + Vector3(1.2, 0, 0)
		var hp_before: int = target.hp
		hero._perform_auto_strike(target)
		await _seconds(0.4)
		await _frames(5)
		if is_instance_valid(target) and target.hp >= hp_before and not target.is_dead():
			failures += 1
			print("FAIL: hero strike dealt no damage (hp still ", target.hp, ")")

	# --- Defeat loop: player dies twice, state must recover cleanly ---
	for i in 2:
		gs.hp = 1
		gs.take_damage(50)
		await _frames(5)
		if gs.combat_state != gs.CombatState.EXPLORING:
			failures += 1
			print("FAIL: combat_state stuck after defeat ", i)
		if gs.hp < gs.max_hp:
			failures += 1
			print("FAIL: hp not restored on defeat ", i)
	await _frames(30)

	# --- ScreenFX saturation restored ---
	var sfx := get_first_node_in_group("screen_fx")
	if sfx != null:
		var sat: float = sfx._mat.get_shader_parameter("saturation")
		if sat < 0.99:
			failures += 1
			print("FAIL: screen saturation stuck dark -> ", sat)

	# --- Skills route through InputManager without dying ---
	var input_mgr := root.get_node("/root/InputManager")
	input_mgr.skill_slot_pressed.emit(0)
	await _frames(10)
	input_mgr.attack_pressed.emit()
	await _frames(10)

	if paused:
		failures += 1
		print("FAIL: tree ended paused")

	gs.delete_save()
	if failures == 0:
		print("ALL COMBAT RECOVERY TESTS PASSED")
	else:
		print("COMBAT RECOVERY TESTS FAILED: ", failures)
	quit(1 if failures > 0 else 0)
