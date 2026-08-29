extends SceneTree

## Headless test: CombatFx tier budgets + telegraph readability layer.
## Asserts every spawned emitter, ribbon trail and transient light respects
## the live QualityScaler budget (density, pool, trail, light caps), that
## protected telegraphs use the non-blooming high-contrast layer even at LOW,
## and that transient impacts stay capped and self-clean.

const BURST_AMOUNT := 40

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var failures := 0
	await process_frame

	var ws := root.get_node_or_null("/root/WorldState")
	if ws == null:
		print("FAIL: WorldState autoload missing")
		quit(1)
		return
	var qs := ws.get_node_or_null("QualityScaler") as QualityScaler
	if qs == null:
		print("FAIL: WorldState/QualityScaler missing")
		quit(1)
		return

	var host := Node3D.new()
	host.name = "FxHost"
	root.add_child(host)
	await process_frame

	# --- LOW tier: density floors + hard pool cap ---
	qs.set_mode(QualityScaler.Mode.LOW)
	host.get_tree().paused = true  # stop real-time tweens from expiring FX mid-check
	var expected_low := maxi(3, int(round(float(BURST_AMOUNT) * 0.45)))
	for i in 30:
		CombatFx.spawn_burst(host, Vector3.ZERO, Color.WHITE, BURST_AMOUNT, 5.0, 0.4)
	var pool := CombatFx._pool.filter(func(p): return p != null and is_instance_valid(p))
	if pool.size() > qs.vfx_pool_limit:
		failures += 1
		print("FAIL: pooled emitters exceed vfx_pool_limit (LOW=%d, live=%d)"
			% [qs.vfx_pool_limit, pool.size()])
	var newest: GPUParticles3D = pool.back()
	if newest != null and newest.amount != expected_low:
		failures += 1
		print("FAIL: LOW burst amount %d should be density-scaled to %d"
			% [newest.amount, expected_low])
	CombatFx.spawn_ring(host, Vector3.ZERO, 2.0, Color.WHITE, 0.4)
	pool = CombatFx._pool.filter(func(p): return p != null and is_instance_valid(p))
	newest = pool.back()
	if newest != null and newest.amount != expected_low:
		failures += 1
		print("FAIL: ring should density-scale to %d at LOW" % expected_low)

	# --- LOW tier: no transient lights, protected telegraph still readable ---
	var low_light := CombatFx.spawn_impact_light(host, Vector3.ZERO,
		Color.WHITE, 2.0, 3.0, 0.1)
	if low_light != null:
		failures += 1
		print("FAIL: LOW tier must not spawn transient lights")
	var proto := CombatFx.spawn_telegraph(host, Vector3.ZERO,
		Color(1.0, 0.2, 0.08), true)
	if proto == null or not is_instance_valid(proto):
		failures += 1
		print("FAIL: protected telegraph should spawn even at LOW")
	else:
		if proto.name != "TelegraphProtected":
			failures += 1
			print("FAIL: protected telegraph must use the dedicated layer")
		var mat := proto.material_override as StandardMaterial3D
		var mesh_mat: StandardMaterial3D = null
		if proto.mesh != null and proto.mesh.get_surface_count() > 0:
			mesh_mat = proto.mesh.surface_get_material(0) as StandardMaterial3D
		var used := mat if mat != null else mesh_mat
		if used == null or used.blend_mode != StandardMaterial3D.BLEND_MODE_MIX \
				or used.render_priority <= 0:
			failures += 1
			print("FAIL: protected telegraph must be MIX-blend, non-blooming, high-priority")
	host.get_tree().paused = false

	# --- LOW tier: ribbon trail cap ---
	for i in 12:
		CombatFx.spawn_skill_ribbon(host, Vector3.ZERO, Vector3(3, 0, 0),
			Color.WHITE, 0.3, 0.2)
	CombatFx._trail_ribbons = CombatFx._trail_ribbons.filter(
		func(n): return n != null and is_instance_valid(n))
	if CombatFx._trail_ribbons.size() > qs.vfx_trail_limit:
		failures += 1
		print("FAIL: live ribbons exceed vfx_trail_limit (LOW=%d, live=%d)"
			% [qs.vfx_trail_limit, CombatFx._trail_ribbons.size()])

	# --- HIGH tier: full budgets, transient lights capped + self-cleaning ---
	qs.set_mode(QualityScaler.Mode.HIGH)
	var expected_high := maxi(3, int(round(float(BURST_AMOUNT) * 1.0)))
	CombatFx.spawn_burst(host, Vector3.ZERO, Color.WHITE, BURST_AMOUNT, 5.0, 0.4)
	pool = CombatFx._pool.filter(func(p): return p != null and is_instance_valid(p))
	newest = pool.back()
	if newest != null and newest.amount != expected_high:
		failures += 1
		print("FAIL: HIGH burst amount %d should be full %d"
			% [newest.amount, expected_high])
	var lights: Array = []
	for i in 5:
		CombatFx.spawn_impact_light(host, Vector3.ZERO + Vector3(i, 0, 0),
			Color.WHITE, 2.0, 3.0, 0.12)
		await process_frame
		lights = CombatFx._transient_lights.filter(
			func(n): return n != null and is_instance_valid(n))
	if lights.size() > qs.transient_light_budget:
		failures += 1
		print("FAIL: transient lights exceed budget (HIGH=%d, live=%d)"
			% [qs.transient_light_budget, lights.size()])
	await create_timer(0.5).timeout
	lights = CombatFx._transient_lights.filter(
		func(n): return n != null and is_instance_valid(n))
	if lights.size() > 0:
		failures += 1
		print("FAIL: transient lights should self-clean after their duration")

	# --- Ground telegraph reads as a torus ring on the protected layer ---
	var ground := CombatFx.spawn_ground_telegraph(host, Vector3(0, 0, 2),
		2.5, Color(1.0, 0.12, 0.08), 0.25)
	if ground == null or not (ground.mesh is TorusMesh):
		failures += 1
		print("FAIL: ground telegraph should spawn a flat ring mesh")

	host.queue_free()
	if failures == 0:
		print("ALL VFX BUDGET TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)