extends SceneTree

## === First-Person Free-Look Validation ===
## The first-person view must be able to turn left/right by changing the
## viewpoint: mouse motion on desktop, a one-finger drag on mobile, and a
## near-level pitch band that the mode lerp cannot fight. Drag steering must
## be handed over to the rig while first person is active, then restored.

var _failures: Array[String] = []
var _move_emits: int = 0

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(30.0)
	watchdog.timeout.connect(func() -> void:
		print("WATCHDOG TIMEOUT — first-person look test hung")
		quit(2))

func _run() -> void:
	var scene := load("res://scenes/world/grove.tscn") as PackedScene
	if scene == null:
		_failures.append("Grove scene failed to load")
		_finish()
		return
	var world := scene.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame

	var rig: Node = world.find_child("CameraRig", true, false)
	var hero: Node3D = world.find_child("Hero", true, false) as Node3D
	var input_man: Node = root.get_node_or_null("InputManager")
	if rig == null or hero == null or input_man == null:
		_failures.append("Grove is missing CameraRig/Hero, or InputManager autoload is missing")
		_finish()
		return

	# Deterministic start: park in third person, then enter first person
	# (persist=false so the test never writes the player's saved choice).
	rig.set_view_mode("third_person", true, false)
	rig.set_view_mode("first_person", true, false)
	_assert_true(str(rig.view_mode) == "first_person", "view_mode switches to first_person")
	_assert_true(input_man.get("first_person_active"), "InputManager is told first-person free-look is active")

	# Desktop: plain mouse motion (no buttons) turns the view left/right.
	var yaw0: float = float(rig.target_angle_h)
	rig._unhandled_input(_motion(12.0, 0.0))
	_assert_true(float(rig.target_angle_h) < yaw0, "mouse right turns the first-person view right")
	var pitch0: float = float(rig.target_angle_v)
	rig._unhandled_input(_motion(0.0, 6.0))
	_assert_true(float(rig.target_angle_v) < pitch0, "mouse down tilts the first-person view down")

	# Pitch band: violent vertical input still clamps inside the FP range.
	for _i in 60:
		rig._apply_first_person_look(Vector2(0.0, 8000.0))
	_assert_true(float(rig.target_angle_v) >= float(rig.first_person_pitch_min) - 0.0001,
		"first-person pitch clamps at the lower bound")
	for _i in 60:
		rig._apply_first_person_look(Vector2(0.0, -8000.0))
	_assert_true(float(rig.target_angle_v) <= float(rig.first_person_pitch_max) + 0.0001,
		"first-person pitch clamps at the upper bound")

	# Mobile: a one-finger drag turns the view left/right instead of steering.
	var look_before: float = float(rig.target_angle_h)
	rig._handle_screen_touch(_touch(0, true))
	rig._handle_screen_drag(_drag(0, Vector2(10.0, 0.0)))
	rig._handle_screen_drag(_drag(0, Vector2(10.0, 0.0)))
	_assert_true(float(rig.target_angle_h) < look_before,
		"one-finger drag right looks right in first person")
	rig._handle_screen_touch(_touch(0, false))

	# While first person is live, a drag must never emit movement steering.
	var counter := func(_dir: Vector2) -> void: _move_emits += 1
	var move_signal: Signal = input_man.get("move_input")
	move_signal.connect(counter)
	input_man.call("_handle_touch", _touch(9, true))
	input_man.call("_handle_drag", _drag(9, Vector2(8.0, 0.0)))
	input_man.call("_handle_drag", _drag(9, Vector2(8.0, 0.0)))
	input_man.call("_handle_touch", _touch(9, false))
	_assert_true(_move_emits == 0, "one-finger drag is free-look, not steering, in first person")

	# Leaving first person restores drag steering and clears the shared flag.
	rig.set_view_mode("third_person", true, false)
	_assert_true(not bool(input_man.get("first_person_active")), "InputManager flag clears in third person")
	input_man.call("_handle_touch", _touch(11, true))
	input_man.call("_handle_drag", _drag(11, Vector2(8.0, 0.0)))
	input_man.call("_handle_touch", _touch(11, false))
	_assert_true(_move_emits >= 1, "third-person one-finger drag steers again")

	_finish()

func _motion(x: float, y: float) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(x, y)
	return e

func _touch(index: int, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = pressed
	return e

func _drag(index: int, rel: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.relative = rel
	return e

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures.append(message)
		print("FAILURE: ", message)

func _finish() -> void:
	if not _failures.is_empty():
		for failure in _failures:
			print("FAILURE: ", failure)
		quit(1)
	else:
		print("=== First-Person Free-Look Validation ===")
		print("passes=1 failures=0")
		quit(0)