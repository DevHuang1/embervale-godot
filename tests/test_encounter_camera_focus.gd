extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var grove_scene := load("res://scenes/world/grove.tscn") as PackedScene
	if grove_scene == null:
		_fail("Grove scene missing")
		quit(1)
		return
	var grove := grove_scene.instantiate()
	root.add_child(grove)
	await _frames(4)
	var camera := grove.get_node_or_null("CameraRig")
	if camera == null:
		_fail("Grove CameraRig missing")
	else:
		var focus := Node3D.new()
		focus.name = "FocusProbe"
		grove.add_child(focus)
		camera.play_focus_moment(focus, Vector3(0.0, 4.0, 6.0), Vector3.UP, 0.8)
		if not bool(camera.get("_cinematic")):
			_fail("Focus moment did not enter cinematic state")
		camera.cancel_cinematic()
		if bool(camera.get("_cinematic")):
			_fail("Focus cancellation left cinematic ownership active")
		camera.play_focus_moment(focus, Vector3(0.0, 4.0, 6.0), Vector3.UP, 0.6)
		await create_timer(0.9).timeout
		if bool(camera.get("_cinematic")):
			_fail("Focus moment did not auto-release after its bounded duration")
		# A look press during a focus beat hands control back immediately: an
		# intro camera must never stay deaf to the player who grabs the view.
		camera.play_focus_moment(focus, Vector3(0.0, 4.0, 6.0), Vector3.UP, 2.0)
		var look_touch := InputEventScreenTouch.new()
		look_touch.index = 5
		look_touch.position = Vector2(900.0, 900.0)
		look_touch.pressed = true
		root.push_input(look_touch)
		await process_frame
		if bool(camera.get("_cinematic")):
			_fail("Player look press did not release the focus moment")
		var look_release := InputEventScreenTouch.new()
		look_release.index = 5
		look_release.position = Vector2(900.0, 900.0)
		look_release.pressed = false
		root.push_input(look_release)
		await process_frame
		focus.queue_free()
	grove.queue_free()
	await process_frame
	if failures.is_empty():
		print("ALL ENCOUNTER CAMERA FOCUS TESTS PASSED")
		quit(0)
	else:
		print("ENCOUNTER CAMERA FOCUS TESTS FAILED: ", failures)
		quit(1)

func _frames(count: int) -> void:
	for _i in count:
		await process_frame

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL: ", message)
