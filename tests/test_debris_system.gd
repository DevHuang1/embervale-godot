extends SceneTree

## Headless test: DebrisSystem — pool recycling, tier caps, burst clamping,
## scene reset. Runs against a fake WorldState shell carrying a real
## QualityScaler so tier knobs are exercised end-to-end.

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var failures := 0

	var shell := Node.new()
	shell.name = "WorldState"
	root.add_child(shell)
	var scaler := QualityScaler.new()
	scaler.name = "QualityScaler"
	shell.add_child(scaler)
	var debris := DebrisSystem.new()
	debris.name = "DebrisSystem"
	debris.quality_override = scaler
	shell.add_child(debris)
	await process_frame
	await process_frame

	# --- HIGH tier: cap 24, bursts clamp to remaining capacity ---
	scaler.set_mode(QualityScaler.Mode.HIGH)
	if scaler.debris_max != 24 or scaler.pom_mode != 2 \
			or scaler.vegetation_pushers != 4 or scaler.corpse_pool_size != 6 \
			or not scaler.contact_shadows:
		failures += 1
		print("FAIL: HIGH tier knobs wrong: debris=%d pom=%d veg=%d corpses=%d shadows=%s"
			% [scaler.debris_max, scaler.pom_mode, scaler.vegetation_pushers,
				scaler.corpse_pool_size, str(scaler.contact_shadows)])
	debris.spawn_burst(Vector3.ZERO, Vector3.UP, "rock", 10)
	if debris._active.size() != 10:
		failures += 1
		print("FAIL: expected 10 active shards, got ", debris._active.size())
	debris.spawn_burst(Vector3.ZERO, Vector3.UP, "wood", 100)
	if debris._active.size() > 24:
		failures += 1
		print("FAIL: active shards exceeded HIGH cap: ", debris._active.size())

	# --- LOW tier: overflow shards retire early ---
	scaler.set_mode(QualityScaler.Mode.LOW)
	if scaler.debris_max != 6 or scaler.pom_mode != 0 \
			or scaler.vegetation_pushers != 1 or scaler.corpse_pool_size != 2 \
			or scaler.contact_shadows:
		failures += 1
		print("FAIL: LOW tier knobs wrong")
	# Simulate aging past the early-retire threshold
	for entry in debris._active:
		entry.age = 0.7
	await process_frame
	await process_frame
	if debris._active.size() > 6:
		failures += 1
		print("FAIL: LOW cap not enforced after aging: ", debris._active.size())

	# --- Reset parks everything ---
	debris.reset()
	if not debris._active.is_empty():
		failures += 1
		print("FAIL: reset should clear active list")

	# --- Unknown style falls back safely ---
	debris.spawn_burst(Vector3.ZERO, Vector3.UP, "unobtainium", 3)
	if debris._active.size() > 3:
		failures += 1
		print("FAIL: unknown style should clamp like a normal burst")

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(failures if failures > 0 else 0)
