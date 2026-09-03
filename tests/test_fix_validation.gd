extends SceneTree

## Headless validation for the combat polish pass:
## 1. Ground impact marks must use the clipped procedural shader, never an
##    unmasked material quad that can render as a hard-edged square.
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

	# --- 1) Decal: clipped procedural shader, no square boundary ---
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage

	var decal_mat: Material = null
	var decal_mi: MeshInstance3D = null
	CombatFx.spawn_decal(stage, Vector3(2, 0, 0), 0.9)
	for child in stage.get_children():
		if child is MeshInstance3D and child.global_position.x > 1.0:
			decal_mi = child
			decal_mat = child.mesh.surface_get_material(0) if child.mesh else null
			break
	if decal_mat == null:
		failures += 1
		print("FAIL: spawn_decal should parent a MeshInstance3D")
	elif decal_mat is ShaderMaterial:
		var decal_material := decal_mat as ShaderMaterial
		if decal_material.shader == null \
				or not decal_material.shader.resource_path.ends_with("ground_impact.gdshader"):
			print("FAIL: spawn_decal must use clipped ground impact shader")
			failures += 1
		if ProjectSettings.get_setting(
				"rendering/scaling_3d/scale", 1.0) is float \
				and float(ProjectSettings.get_setting(
					"rendering/scaling_3d/scale", 1.0)) > 0.95:
			print("NOTE: project defaults are full-res; runtime QualityScaler "
				+ "owns upscaling — acceptable only when AUTO/HIGH is set")
	else:
		failures += 1
		print("FAIL: decal material is not the clipped ShaderMaterial")

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
