extends SceneTree

## Headless validation for the combat polish pass:
## 1. Ember scorch decal must be a bright ADD-blend glow (never a dark MUL
##    quad that can render as a hard-edged black square).
## 2. QualityScaler must drive 3D render resolution scaling per tier so the
##    game trades detail for smoothness on weak hardware.

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var failures := 0

	# --- 1) Decal: ADD-blend, warm albedo, no black-square ingredients ---
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage

	var decal_mat: BaseMaterial3D = null
	var decal_mi: MeshInstance3D = null
	CombatFx.spawn_decal(stage, Vector3(2, 0, 0), 0.9)
	for child in stage.get_children():
		if child is MeshInstance3D and child.global_position.x > 1.0:
			decal_mi = child
			decal_mat = child.mesh.material if child.mesh else null
			break
	if decal_mat == null:
		failures += 1
		print("FAIL: spawn_decal should parent a MeshInstance3D")
	elif decal_mat is StandardMaterial3D:
		var sm: StandardMaterial3D = decal_mat
		if sm.blend_mode != BaseMaterial3D.BLEND_MODE_ADD:
			failures += 1
			print("FAIL: decal must be ADD blend, got ", str(sm.blend_mode))
		if sm.albedo_color.r < 0.5:
			failures += 1
			print("FAIL: decal albedo went dark again (black-square risk): ",
				str(sm.albedo_color))
		if sm.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			failures += 1
			print("FAIL: decal should be unshaded for a clean additive glow")
		if ProjectSettings.get_setting(
				"rendering/scaling_3d/scale", 1.0) is float \
				and float(ProjectSettings.get_setting(
					"rendering/scaling_3d/scale", 1.0)) > 0.95:
			print("NOTE: project defaults are full-res; runtime QualityScaler "
				+ "owns upscaling — acceptable only when AUTO/HIGH is set")
	else:
		failures += 1
		print("FAIL: decal material is not a StandardMaterial3D")

	# --- 2) QualityScaler drives 3D scaling (0.6 LOW / 0.75 MID / 1.0 HIGH) ---
	var scaler := QualityScaler.new()
	scaler.name = "QualityScaler"
	root.add_child(scaler)
	await process_frame
	await process_frame

	scaler.set_mode(QualityScaler.Mode.LOW)
	await process_frame
	var s_low := float(root.scaling_3d_scale)
	scaler.set_mode(QualityScaler.Mode.HIGH)
	await process_frame
	var s_high := float(root.scaling_3d_scale)

	if not is_equal_approx(s_low, 0.6):
		failures += 1
		print("FAIL: LOW should render at 0.6 3D scale, got %.2f" % s_low)
	if not is_equal_approx(s_high, 1.0):
		failures += 1
		print("FAIL: HIGH should render at 1.0 3D scale, got %.2f" % s_high)
	if s_low >= s_high:
		failures += 1
		print("FAIL: scaling must rise with the quality tier")

	# Cleanup
	if decal_mi != null:
		decal_mi.queue_free()
	scaler.free()
	stage.free()
	current_scene = null

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(failures if failures > 0 else 0)