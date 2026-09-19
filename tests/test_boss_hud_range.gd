extends SceneTree

## === Boss HUD Range Contract ===
## The top boss health bar, its phase/telegraph guidance, the boss-combat
## camera frame and the boss's own floating plate are encounter-scoped: they
## appear while the player is near the fight and retire when the player walks
## out of the boss's reach, then return on the way back.

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(60.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — boss HUD range test hung")
		quit(2))

func _run() -> void:
	var failures := 0
	root.size = Vector2i(1080, 1920)
	var gs := root.get_node("/root/GameState")
	gs.save_path = "/tmp/embervale_boss_hud_range_%d.cfg" % OS.get_process_id()
	gs.delete_save()
	gs.reset()
	gs.set_current_realm("bramblewood")
	var scene: Node = (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 6:
		await process_frame
	var hero := scene.find_child("Hero", true, false) as Node3D
	var hud := scene.get_node_or_null("HUD")
	var rig := scene.find_child("CameraRig", true, false)
	var bar := hud.get_node_or_null("Root/BossHealthBar") as Control
	if hero == null or hud == null or rig == null or bar == null:
		print("FAIL: grove is missing Hero/HUD/CameraRig/BossHealthBar")
		quit(1)
		return

	var boss := (load("res://scenes/entities/boss_biome.tscn") as PackedScene).instantiate()
	boss.def_id = "thornhide_alpha"
	scene.add_child(boss)
	boss.global_position = hero.global_position + Vector3(6.0, 0.0, 0.0)
	await _frames(20)

	if not bar.visible:
		failures += 1
		print("FAIL: boss bar did not appear while the player is beside the boss")
	if not bool(rig.get("_boss_combat")):
		failures += 1
		print("FAIL: boss-combat camera frame did not engage beside the boss")
	var floating := boss.get_node_or_null("EnemyHealthBar")
	if floating != null and not bool(floating.get("_range_visible")):
		failures += 1
		print("FAIL: boss plate retired while the player is beside the boss")

	# Walk out of the encounter.
	var home := hero.global_position
	hero.global_position = home + Vector3(90.0, 0.0, 0.0)
	await _frames(30)
	if bar.visible:
		failures += 1
		print("FAIL: boss bar stayed after the player left the boss range")
	if bool(rig.get("_boss_combat")):
		failures += 1
		print("FAIL: boss-combat camera frame stayed after the player left")
	if floating != null and bool(floating.get("_range_visible")):
		failures += 1
		print("FAIL: boss plate stayed after the player left the boss range")

	# Return: the encounter HUD comes back.
	hero.global_position = home
	await _frames(30)
	if not bar.visible:
		failures += 1
		print("FAIL: boss bar did not return when the player re-entered range")
	if not bool(rig.get("_boss_combat")):
		failures += 1
		print("FAIL: boss-combat camera frame did not return on re-entry")

	boss.queue_free()
	scene.queue_free()
	await process_frame
	if failures == 0:
		print("ALL BOSS HUD RANGE TESTS PASSED")
		quit(0)
	else:
		print("%d BOSS HUD RANGE FAILURES" % failures)
		quit(1)

func _frames(count: int) -> void:
	for _i in count:
		await process_frame
