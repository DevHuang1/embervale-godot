extends SceneTree

## Headless test: TargetMarker — the world-visible lantern mark.
## Covers: ensure() singleton behavior, ring appears when gs.enemy_target
## is engaged, tracks target swaps, hides when the lock drops, ground-probe
## fallback, and the actionable skill-refusal copy in gs.use_skill.

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var failures := 0
	var gs = root.get_node("/root/GameState")

	# --- Scripts compile ---
	var marker_script := load("res://scripts/systems/target_marker.gd")
	if marker_script == null:
		print("FAIL: target_marker.gd failed to load")
		quit(1)
		return
	if load("res://scripts/entities/hero.gd") == null:
		failures += 1
		print("FAIL: hero.gd failed to load")

	# --- Scene scaffold (ensure() parents into current_scene) ---
	var scene_root := Node3D.new()
	scene_root.name = "TestScene"
	root.add_child(scene_root)
	current_scene = scene_root
	await process_frame

	# --- Dummy foe on the world layer ---
	var enemy := Node3D.new()
	enemy.name = "FoeA"
	enemy.position = Vector3(2.0, 0.0, -1.0)
	enemy.add_to_group("enemy")
	scene_root.add_child(enemy)

	# --- Engaging marks the foe ---
	if not gs.engage_enemy(enemy):
		failures += 1
		print("FAIL: engage_enemy should succeed from EXPLORING")

	var marker: Node3D = marker_script.ensure(scene_root)
	if marker == null:
		failures += 1
		print("FAIL: TargetMarker.ensure returned null")
	else:
		# ensure() parents the ring deferred (safe during scene instantiation)
		await process_frame
		if marker.get_parent() != scene_root:
			failures += 1
			print("FAIL: marker should parent into current_scene")
		# Idempotent ensure
		if marker_script.ensure(scene_root) != marker:
			failures += 1
			print("FAIL: ensure should return the same singleton instance")
		await create_timer(0.25).timeout
		if not marker.visible:
			failures += 1
			print("FAIL: marker should be visible while a foe is marked")
		if marker.global_position.distance_to(enemy.global_position + Vector3(0, 0.07, 0)) > 0.5:
			failures += 1
			print("FAIL: marker should hug the marked foe (got %s)" % marker.global_position)

	# --- Skill refusal copy is actionable (no target engaged) ---
	gs.disengage_enemy()
	var result: Dictionary = gs.use_skill(0)
	if result.get("success", true):
		failures += 1
		print("FAIL: targeted rite should refuse with no valid target state")
	elif not str(result.get("message", "")).to_lower().contains("mark"):
		failures += 1
		print("FAIL: refusal message should mention marking: %s" % result.get("message"))

	# --- Target swap re-tracks ---
	var enemy_b := Node3D.new()
	enemy_b.name = "FoeB"
	enemy_b.position = Vector3(-3.0, 0.0, 2.0)
	enemy_b.add_to_group("enemy")
	scene_root.add_child(enemy_b)
	if not gs.engage_enemy(enemy_b):
		failures += 1
		print("FAIL: re-engage after disengage should succeed")
	await create_timer(0.2).timeout
	if is_instance_valid(marker) and marker.visible \
			and marker.global_position.distance_to(enemy_b.global_position) > 0.6:
		failures += 1
		print("FAIL: marker should follow the newly marked foe (got %s)" % marker.global_position)

	# --- Dropping the lock fades the ring out ---
	gs.disengage_enemy()
	await create_timer(0.35).timeout
	if is_instance_valid(marker) and marker.visible:
		failures += 1
		print("FAIL: marker should hide once the mark is dropped")

	# --- Persistent lock visuals: halo follows, tether spans lantern->foe ---
	var halo := marker.get_node_or_null("FoeHalo")
	if halo == null:
		failures += 1
		print("FAIL: marker should build a FoeHalo child for lock legibility")
	if marker.get_node_or_null("LanternTether") == null:
		failures += 1
		print("FAIL: marker should build a LanternTether child")
	var lantern := Node3D.new()
	lantern.name = "TestLantern"
	lantern.position = Vector3(3.0, 1.0, 1.0)
	scene_root.add_child(lantern)
	marker_script.bind_lantern(lantern)
	# Signal choreography: mark_locked on engage, mark_released on drop.
	# GDScript lambdas capture locals by value, so count through a Dictionary
	# (captured by reference) or the counters would stay 0 forever.
	var seen := {"locked": 0, "released": 0}
	gs.mark_locked.connect(func(_e): seen.locked += 1)
	gs.mark_released.connect(func(): seen.released += 1)
	if not gs.engage_enemy(enemy):
		failures += 1
		print("FAIL: re-engage for tether test should succeed")
	await create_timer(0.3).timeout
	var tether := marker.get_node_or_null("LanternTether")
	if is_instance_valid(marker):
		if tether == null or not tether.visible:
			failures += 1
			print("FAIL: tether should be visible once bound + marked")
		elif is_instance_valid(enemy):
			var mid_expect := (lantern.global_position + enemy.global_position + Vector3(0, 0.375, 0)) * 0.5
			if tether.global_position.distance_to(mid_expect) > 1.2:
				failures += 1
				print("FAIL: tether should span lantern->foe midpoint (got %s)" % tether.global_position)
		if halo != null and not halo.visible:
			failures += 1
			print("FAIL: foe halo should be visible while the mark is held")
	gs.disengage_enemy()
	await create_timer(0.4).timeout
	if tether != null and tether.visible:
		failures += 1
		print("FAIL: tether should hide once the mark drops")
	if seen.locked != 1 or seen.released != 1:
		failures += 1
		print("FAIL: expected 1 mark_locked + 1 mark_released (got %d/%d)"
			% [seen.locked, seen.released])

	# --- Dead foes never hold a stale ring ---
	gs.engage_enemy(enemy)
	enemy.set_script(null)
	scene_root.remove_child(enemy)
	await create_timer(0.35).timeout
	if is_instance_valid(marker) and marker.visible:
		failures += 1
		print("FAIL: marker should hide when the marked foe leaves the tree")
	# The foe was removed from the tree above; free it so the test itself
	# does not leak an ObjectDB instance at exit.
	if is_instance_valid(enemy):
		enemy.free()

	if failures == 0:
		print("ALL TARGET MARKER TESTS PASSED")
		quit(0)
	else:
		print("%d TARGET MARKER TEST(S) FAILED" % failures)
		quit(1)
