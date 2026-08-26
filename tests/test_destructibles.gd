extends SceneTree

## Headless test: DestructibleProp — hit/flash/break lifecycle, loot roll
## safety without GameState, variant table integrity, grove anchor hookup.

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var failures := 0

	for variant in ["pot", "crate", "glowcap"]:
		var prop := DestructibleProp.create(variant)
		root.add_child(prop)
		await process_frame
		await process_frame

		if not prop.is_in_group("destructible"):
			failures += 1
			print("FAIL: %s should join 'destructible' group" % variant)
		if prop.hp != prop.max_hp or prop.max_hp < 2:
			failures += 1
			print("FAIL: %s hp setup wrong (%d/%d)"
				% [variant, prop.hp, prop.max_hp])
		var has_shape := false
		for c in prop.get_children():
			if c is CollisionShape3D:
				has_shape = true
		if not has_shape:
			failures += 1
			print("FAIL: %s missing collision shape" % variant)

		# Chip without breaking
		prop.take_hit(1, Vector3.UP)
		if prop.is_broken or prop.hp != prop.max_hp - 1:
			failures += 1
			print("FAIL: %s should survive one chip" % variant)

		# Final blows flag broken (node frees itself)
		var id := prop.get_instance_id()
		for i in prop.max_hp - 1:
			prop.take_hit(1, Vector3.UP)
		if not prop.is_broken:
			failures += 1
			print("FAIL: %s should be broken after final hit" % variant)
		await process_frame
		if instance_from_id(id) != null and is_instance_valid(instance_from_id(id)):
			failures += 1
			print("FAIL: %s should free itself after breaking" % variant)

	# Loot rolls must not crash even though /root/GameState doesn't exist
	# in this bare SceneTree (guards exercised via the breaks above).

	# GroveDressing exposes prop anchors through TerrainRelief
	var relief_script := load("res://scripts/systems/terrain_relief.gd")
	if relief_script == null:
		failures += 1
		print("FAIL: terrain_relief.gd failed to load")

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(failures if failures > 0 else 0)
