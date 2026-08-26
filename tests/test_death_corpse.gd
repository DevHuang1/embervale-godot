extends SceneTree

## Headless test: TumbleCorpse — visual reparenting, impulse, concurrent
## corpse budget enforcement, cleanup, ragdoll rejection without a skeleton.

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var failures := 0

	# --- Launch reparents the visual into the rigid shell ---
	var visual := Node3D.new()
	visual.name = "Visual"
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	visual.add_child(mesh)
	root.add_child(visual)
	await process_frame

	TumbleCorpse.max_corpses = 6
	var corpse := TumbleCorpse.launch(visual,
		Vector3(3.0, 3.0, 0.0))
	if corpse == null:
		failures += 1
		print("FAIL: launch should return the corpse body")
	else:
		await process_frame
		if not TumbleCorpse._live.has(corpse):
			failures += 1
			print("FAIL: launched corpse should register in _live")
		if visual.get_parent() != corpse:
			failures += 1
			print("FAIL: visual should be reparented under the corpse")
		if corpse.linear_velocity.length() < 1.0:
			failures += 1
			print("FAIL: corpse should inherit the killing impulse")

	# --- Budget: oldest corpse retires when the cap is exceeded ---
	TumbleCorpse.max_corpses = 2
	var extras: Array = []
	for i in 3:
		var v := Node3D.new()
		var m := MeshInstance3D.new()
		m.mesh = BoxMesh.new()
		v.add_child(m)
		root.add_child(v)
		extras.append(TumbleCorpse.launch(v, Vector3.ONE))
		await process_frame
	if TumbleCorpse._live.size() > 2:
		failures += 1
		print("FAIL: corpse budget exceeded: ", TumbleCorpse._live.size())
	for c in extras:
		if c != null and is_instance_valid(c):
			c.finish()
	if corpse != null and is_instance_valid(corpse):
		corpse.finish()
	await process_frame
	if not TumbleCorpse._live.is_empty():
		failures += 1
		print("FAIL: finish() should clear the registry")

	# --- Ragdoll attempt rejects rigs without a usable skeleton ---
	var plain := Node3D.new()
	root.add_child(plain)
	await process_frame
	if TumbleCorpse.try_ragdoll(plain, Vector3.UP):
		failures += 1
		print("FAIL: try_ragdoll must reject skeleton-less rigs")

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(failures if failures > 0 else 0)
