extends SceneTree

## Headless test: TerrainWear — splat math, UV mapping, upload throttle,
## reset. The image is the source of truth; the texture just mirrors it.

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var failures := 0

	var wear := TerrainWear.new()
	root.add_child(wear)
	await process_frame
	await process_frame

	# --- Ready state: blank map published ---
	if wear.image == null or wear.texture == null:
		failures += 1
		print("FAIL: TerrainWear did not initialize its image/texture")
		quit(1)
		return
	if not is_equal_approx(wear.image.get_pixel(128, 128).r, 0.0):
		failures += 1
		print("FAIL: fresh wear map should be pristine")

	# --- Splat darkens around the recorded position ---
	var center := Vector3(-76.0 + 76.0, 0, -76.0 + 76.0)  # world center of bounds
	wear.record(center, 2.0, 1.0)
	if wear.image.get_pixel(128, 128).r <= 0.0:
		failures += 1
		print("FAIL: splat should darken the center pixel")
	if wear._dirty == false:
		failures += 1
		print("FAIL: record() must mark the map dirty")

	# --- Upload throttle holds then releases ---
	wear._since_upload = 0.0
	wear._process(0.05)
	if not wear._dirty:
		failures += 1
		print("FAIL: dirty map should survive a sub-threshold tick")
	wear._process(0.15)
	if wear._dirty:
		failures += 1
		print("FAIL: dirty map should upload (clear) past the threshold")

	# --- Out-of-bounds records clamp instead of crashing ---
	wear.record(Vector3(-500.0, 0, -500.0), 1.5, 1.0)
	wear.record(Vector3(900.0, 0, 900.0), 1.5, 1.0)

	# --- UV mapping hits the corners ---
	var uv := TerrainWear.world_to_uv(Vector2(TerrainWear.BOUNDS_MIN, TerrainWear.BOUNDS_MIN))
	if uv.distance_to(Vector2.ZERO) > 0.001:
		failures += 1
		print("FAIL: min corner maps to (0,0), got ", uv)
	uv = TerrainWear.world_to_uv(Vector2(
		TerrainWear.BOUNDS_MIN + TerrainWear.BOUNDS_SIZE,
		TerrainWear.BOUNDS_MIN + TerrainWear.BOUNDS_SIZE))
	if uv.distance_to(Vector2.ONE) > 0.001:
		failures += 1
		print("FAIL: max corner maps to (1,1), got ", uv)

	# --- Reset returns to pristine ---
	wear.reset()
	if wear.image.get_pixel(128, 128).r != 0.0:
		failures += 1
		print("FAIL: reset must clear all wear")

	if failures == 0:
		wear.free()
		print("ALL TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(failures if failures > 0 else 0)
