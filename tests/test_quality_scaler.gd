extends SceneTree

## Headless test: QualityScaler — level application, degradation ordering
## with hysteresis via feed_fps, mode persistence round-trip.

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var failures := 0

	var scaler := QualityScaler.new()
	scaler.name = "QualityScaler"
	scaler.settings_path = "/tmp/embervale_quality_scaler_test.cfg"
	root.add_child(scaler)
	await process_frame
	await process_frame

	# --- Locked High: full particle budget + full UE-look tier ---
	scaler.set_mode(QualityScaler.Mode.HIGH)
	if scaler.level != QualityScaler.Level.HIGH \
			or not is_equal_approx(scaler.particle_scale, 1.0):
		failures += 1
		print("FAIL: HIGH mode should apply full quality, got level=%s scale=%.2f"
			% [str(scaler.level), scaler.particle_scale])
	if scaler.debris_max != 24 or scaler.pom_mode != 2 \
			or scaler.vegetation_pushers != 4 \
			or scaler.corpse_pool_size != 6 or not scaler.contact_shadows:
		failures += 1
		print("FAIL: HIGH tier should max debris/pom/pushers/corpses/shadows")
	if not is_equal_approx(scaler.vfx_density, 1.0) \
			or scaler.vfx_pool_limit != 24 or scaler.vfx_trail_limit != 12 \
			or scaler.transient_light_budget != 3 \
			or not scaler.distortion_enabled \
			or scaler.material_detail_level != QualityScaler.Level.HIGH:
		failures += 1
		print("FAIL: HIGH tier should max vfx density/pool/trails/lights/distortion")
	if not is_equal_approx(scaler.grass_density_scale, 1.0):
		failures += 1
		print("FAIL: HIGH should use the full grass-carpet density")

	# --- Contact shadows are opt-in via the contact_shadow group ---
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var fill_light := OmniLight3D.new()
	stage.add_child(fill_light)
	var key_light := OmniLight3D.new()
	key_light.add_to_group(QualityScaler.CONTACT_SHADOW_GROUP)
	stage.add_child(key_light)
	scaler.set_mode(QualityScaler.Mode.HIGH)
	if not key_light.shadow_enabled or fill_light.shadow_enabled:
		failures += 1
		print("FAIL: HIGH should shadow only contact_shadow-group lights")
	scaler.set_mode(QualityScaler.Mode.LOW)
	if key_light.shadow_enabled:
		failures += 1
		print("FAIL: LOW must drop group-light shadows")
	current_scene = null
	stage.free()
	scaler.set_mode(QualityScaler.Mode.HIGH)

	# --- Locked Low: cheapest tier ---
	scaler.set_mode(QualityScaler.Mode.LOW)
	if scaler.level != QualityScaler.Level.LOW \
			or not is_equal_approx(scaler.particle_scale, 0.5):
		failures += 1
		print("FAIL: LOW mode should halve the particle budget")
	if scaler.debris_max != 6 or scaler.pom_mode != 0 \
			or scaler.vegetation_pushers != 1 \
			or scaler.corpse_pool_size != 2 or scaler.contact_shadows:
		failures += 1
		print("FAIL: LOW tier should minimize debris/pom/pushers/corpses/shadows")
	if not is_equal_approx(scaler.vfx_density, 0.45) \
			or scaler.vfx_pool_limit != 10 or scaler.vfx_trail_limit != 6 \
			or scaler.transient_light_budget != 0 \
			or scaler.distortion_enabled \
			or scaler.material_detail_level != QualityScaler.Level.LOW:
		failures += 1
		print("FAIL: LOW tier should minimize vfx density/pool/trails/lights/distortion")
	if not is_equal_approx(scaler.grass_density_scale, 0.65):
		failures += 1
		print("FAIL: LOW should retain a reduced grass carpet")

	# --- Auto degrades one step per sustained low reading ---
	scaler.set_mode(QualityScaler.Mode.AUTO)
	if scaler.level != QualityScaler.Level.HIGH:
		failures += 1
		print("FAIL: AUTO entry point should be HIGH, got ", str(scaler.level))
	var signals_fired := []
	scaler.level_changed.connect(func(level: int) -> void:
		signals_fired.append(level))
	scaler.feed_fps(30.0)
	if scaler.level != QualityScaler.Level.MEDIUM:
		failures += 1
		print("FAIL: first low reading should degrade to MEDIUM")
	scaler.feed_fps(30.0)
	if scaler.level != QualityScaler.Level.LOW:
		failures += 1
		print("FAIL: second low reading should floor at LOW")
	scaler.feed_fps(30.0)
	if scaler.level != QualityScaler.Level.LOW:
		failures += 1
		print("FAIL: LOW must not over-degrade")

	# --- Sustained headroom restores step by step back to HIGH ---
	scaler.feed_fps(60.0)
	if scaler.level != QualityScaler.Level.MEDIUM:
		failures += 1
		print("FAIL: sustained high fps should restore to MEDIUM")
	scaler.feed_fps(60.0)
	if scaler.level != QualityScaler.Level.HIGH:
		failures += 1
		print("FAIL: sustained high fps should restore to HIGH")
	scaler.feed_fps(60.0)
	if scaler.level != QualityScaler.Level.HIGH:
		failures += 1
		print("FAIL: HIGH must not over-restore")

	if signals_fired.size() < 4:
		failures += 1
		print("FAIL: level_changed should fire per applied level, fired ",
			signals_fired.size())

	# --- Mid readings reset both hysteresis timers (no flapping) ---
	var before := scaler.level
	scaler.feed_fps(52.0)
	if scaler.level != before:
		failures += 1
		print("FAIL: mid-band fps must not change level")

	# --- Mode persists into the shared settings cfg and loads back ---
	scaler.set_mode(QualityScaler.Mode.LOW)
	var reread := QualityScaler.new()
	reread.settings_path = scaler.settings_path
	reread._load_mode()
	if reread.mode != QualityScaler.Mode.LOW:
		failures += 1
		print("FAIL: mode should persist across instances")
	reread.free()
	scaler.set_mode(QualityScaler.Mode.AUTO)

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(failures if failures > 0 else 0)
