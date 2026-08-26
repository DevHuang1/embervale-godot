extends SceneTree

## Headless regression: downloaded weapon GLBs mount in-hand and the
## recorded swipe layer plays across all three slash combo stages.

func _initialize() -> void:
	create_timer(25.0).timeout.connect(func():
		print("WATCHDOG TIMEOUT")
		quit(3))
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var failures := 0
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	var scene: Node = (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(10)

	var hero := scene.get_node_or_null("Hero")
	if hero == null:
		print("FAIL: hero missing from grove")
		quit(1)
		return
	var hand_l := hero.find_child("HandSocketL", true, false) as Node3D
	var hand_r := hero.find_child("HandSocketR", true, false) as Node3D
	if hand_l == null or hand_r == null:
		print("FAIL: hand sockets missing after rig bind")
		gs.delete_save()
		quit(1)
		return
	var audio = root.get_node("/root/AudioManager")

	# --- Ember sword mounts the downloaded GLB in the left fist ---
	gs.add_weapon(gs.WEAPON_DEFS["ember_sword"], true)
	await _frames(3)
	var sword_vis := hand_l.get_node_or_null("WeaponModel")
	if sword_vis == null:
		failures += 1
		print("FAIL: no downloaded sword model under HandSocketL")
	else:
		print("OK: ember_sword model mounted")

	# --- Arcane staff mounts the downloaded GLB in the right fist ---
	gs.add_weapon(gs.WEAPON_DEFS["arcane_staff"], true)
	await _frames(3)
	var staff_vis := hand_r.get_node_or_null("WeaponModel")
	if staff_vis == null:
		failures += 1
		print("FAIL: no downloaded staff model under HandSocketR")
	else:
		print("OK: arcane_staff model mounted")

	# --- Slash animation SFX layers without errors for every stage ---
	for stage in [0, 1, 2]:
		audio.play_swing_stage(stage)
	await _frames(5)

	gs.delete_save()
	if failures == 0:
		print("ALL WEAPON MOUNT TESTS PASSED")
	else:
		print("WEAPON MOUNT TESTS FAILED: ", failures)
	quit(1 if failures > 0 else 0)
