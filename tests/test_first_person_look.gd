extends SceneTree

## === First-Person Free-Look + Third-Person Camera Drag Validation ===
## First person must turn by mouse motion (desktop) or a one-finger drag
## (mobile) with a near-level pitch band that the mode lerp cannot fight.
## Third person must turn by dragging on the camera side of the screen: the
## gesture is claimed once and keeps turning yaw and pitch, a clean tap there
## still moves the hero, and the left side remains player steering. The HUD
## must never swallow world input, so the third-person half drives real touch
## events through a portrait viewport instead of calling handlers directly.

const VIEWPORT := Vector2i(1080, 1920)
const LOOK_ZONE_X := 760.0
const MOVE_ZONE_X := 120.0

var _failures: Array[String] = []
var _move_emits: int = 0
var _taps: int = 0

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(30.0)
	watchdog.timeout.connect(func() -> void:
		print("WATCHDOG TIMEOUT — camera look test hung")
		quit(2))

func _run() -> void:
	# A realistic portrait viewport is required: the HUD only covers the
	# screen at real sizes, and the look zone is a fraction of its width.
	root.size = VIEWPORT
	var scene := load("res://scenes/world/grove.tscn") as PackedScene
	if scene == null:
		_failures.append("Grove scene failed to load")
		_finish()
		return
	var world := scene.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	await process_frame

	var rig: Node = world.find_child("CameraRig", true, false)
	var hero: Node3D = world.find_child("Hero", true, false) as Node3D
	var input_man: Node = root.get_node_or_null("InputManager")
	if rig == null or hero == null or input_man == null:
		_failures.append("Grove is missing CameraRig/Hero, or InputManager autoload is missing")
		_finish()
		return
	input_man.set("is_mobile", true)
	input_man.move_input.connect(_count_move)
	input_man.tap_world.connect(func(_position: Vector3, _camera: Camera3D) -> void:
		_taps += 1)
	input_man.tap_foe.connect(func(_enemy: Node3D) -> void:
		_taps += 1)

	# Deterministic start: park in third person, then enter first person
	# (persist=false so the test never writes the player's saved choice).
	rig.set_view_mode("third_person", true, false)
	rig.set_view_mode("first_person", true, false)
	rig.cancel_cinematic()
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
	var drag_stopped_yaw: float = float(rig.target_angle_h)
	for _i in 6:
		rig._physics_process(0.1)
	_assert_true(is_equal_approx(float(rig.target_angle_h), drag_stopped_yaw),
		"first-person yaw stays fixed after the drag ends")
	rig._handle_screen_touch(_touch(0, false))

	# While first person is live, a drag must never emit movement steering.
	var moves_before_fp: int = _move_emits
	input_man.call("_handle_touch", _touch(9, true))
	input_man.call("_handle_drag", _drag(9, Vector2(8.0, 0.0)))
	input_man.call("_handle_drag", _drag(9, Vector2(8.0, 0.0)))
	input_man.call("_handle_touch", _touch(9, false))
	_assert_true(_move_emits == moves_before_fp,
		"one-finger drag is free-look, not steering, in first person")

	# === Third person: the HUD must pass world input through ===
	rig.set_view_mode("third_person", true, false)
	rig.cancel_cinematic()
	_assert_true(not bool(input_man.get("first_person_active")), "InputManager flag clears in third person")
	var hud_root := world.get_node_or_null("HUD/Root") as Control
	_assert_true(hud_root != null and hud_root.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"HUD root lets world taps and drags reach gameplay")

	# Direct left-side drag steers the hero instead of turning the camera.
	var world_camera_yaw: float = float(rig.target_angle_h)
	var moves_before_steer: int = _move_emits
	input_man.call("_handle_touch", _touch_at(11, true, Vector2(MOVE_ZONE_X, 900.0)))
	input_man.call("_handle_drag", _drag(11, Vector2(24.0, 2.0),
		Vector2(MOVE_ZONE_X + 24.0, 902.0)))
	input_man.call("_handle_touch", _touch_at(11, false, Vector2(MOVE_ZONE_X + 24.0, 902.0)))
	_assert_true(_move_emits > moves_before_steer,
		"left-side third-person drag remains player movement")
	_assert_true(is_equal_approx(float(rig.target_angle_h), world_camera_yaw),
		"left-side drag does not turn the camera")

	# The camera-side press is a look gesture driven through the real
	# viewport: it must turn yaw and pitch for the whole gesture, and it must
	# never order the hero to walk or steer.
	rig.cancel_cinematic()
	rig.set_angles(0.0, -0.62)
	input_man.set("last_tap_time", 0.0)
	_taps = 0
	var moves_before_look: int = _move_emits
	root.push_input(_touch_at(31, true, Vector2(LOOK_ZONE_X, 900.0)))
	await process_frame
	for step in 5:
		root.push_input(_drag(31, Vector2(24.0, 0.0),
			Vector2(LOOK_ZONE_X + (step + 1) * 24.0, 900.0)))
		await process_frame
	_assert_true(float(rig.target_angle_h) < -0.1,
		"right-side drag turns the third-person view")
	_assert_true(_move_emits == moves_before_look,
		"camera drag never steers the hero")
	_assert_true(_taps == 0, "camera drag never orders a hero move")
	var pitch_before: float = float(rig.target_angle_v)
	root.push_input(_drag(31, Vector2(0.0, -60.0), Vector2(LOOK_ZONE_X + 120.0, 840.0)))
	await process_frame
	_assert_true(float(rig.target_angle_v) > pitch_before + 0.1,
		"latched camera drag keeps turning when the finger moves vertically")
	root.push_input(_touch_at(31, false, Vector2(LOOK_ZONE_X + 120.0, 840.0)))
	await process_frame

	# A clean tap in the same zone still moves the hero, on release, without
	# turning the view.
	rig.cancel_cinematic()
	rig.set_angles(0.0, -0.62)
	input_man.set("last_tap_time", 0.0)
	_taps = 0
	root.push_input(_touch_at(32, true, Vector2(LOOK_ZONE_X, 900.0)))
	await process_frame
	root.push_input(_touch_at(32, false, Vector2(LOOK_ZONE_X, 900.0)))
	await process_frame
	_assert_true(_taps == 1, "look-zone tap still emits a world move tap")
	_assert_true(absf(float(rig.target_angle_h)) < 0.001,
		"look-zone tap does not turn the camera")

	# === Sensitivity multiplier ===
	# The persisted multiplier scales drag turning in both camera modes. A temp
	# settings path keeps the player's own preferences untouched.
	var real_settings_path: String = str(rig.get("settings_path"))
	rig.set("settings_path", "/tmp/embervale_camera_sensitivity_test.cfg")
	rig.cancel_cinematic()
	rig.set_angles(0.0, -0.62)
	rig.set_look_sensitivity(1.0, false)
	input_man.call("_handle_touch", _touch_at(41, true, Vector2(LOOK_ZONE_X, 900.0)))
	input_man.call("_handle_drag", _drag(41, Vector2(40.0, 0.0),
		Vector2(LOOK_ZONE_X + 40.0, 900.0)))
	input_man.call("_handle_touch", _touch_at(41, false, Vector2(LOOK_ZONE_X + 40.0, 900.0)))
	var base_delta: float = -float(rig.target_angle_h)
	rig.set_angles(0.0, -0.62)
	rig.set_look_sensitivity(2.0, false)
	input_man.call("_handle_touch", _touch_at(42, true, Vector2(LOOK_ZONE_X, 900.0)))
	input_man.call("_handle_drag", _drag(42, Vector2(40.0, 0.0),
		Vector2(LOOK_ZONE_X + 40.0, 900.0)))
	input_man.call("_handle_touch", _touch_at(42, false, Vector2(LOOK_ZONE_X + 40.0, 900.0)))
	var fast_delta: float = -float(rig.target_angle_h)
	_assert_true(fast_delta > base_delta * 1.7,
		"2x sensitivity turns the camera further per drag")
	_assert_true(is_equal_approx(float(rig.get("first_person_look_sensitivity")), 0.008),
		"the multiplier scales first-person look too")
	rig.set_angles(0.0, -0.62)
	rig.set_look_sensitivity(0.5, false)
	input_man.call("_handle_touch", _touch_at(43, true, Vector2(LOOK_ZONE_X, 900.0)))
	input_man.call("_handle_drag", _drag(43, Vector2(40.0, 0.0),
		Vector2(LOOK_ZONE_X + 40.0, 900.0)))
	input_man.call("_handle_touch", _touch_at(43, false, Vector2(LOOK_ZONE_X + 40.0, 900.0)))
	var slow_delta: float = -float(rig.target_angle_h)
	_assert_true(slow_delta < base_delta * 0.7,
		"half sensitivity turns the camera less per drag")

	# The value round-trips through the settings file and clamps to the slider.
	rig.set_look_sensitivity(1.7)
	var saved_settings := ConfigFile.new()
	var loaded := saved_settings.load("/tmp/embervale_camera_sensitivity_test.cfg")
	_assert_true(loaded == OK and is_equal_approx(float(saved_settings.get_value(
		"gameplay", "camera_sensitivity", 0.0)), 1.7),
		"camera sensitivity persists to the settings file")
	rig.set_look_sensitivity(9.0, false)
	_assert_true(is_equal_approx(float(rig.get_look_sensitivity()), 2.0),
		"sensitivity clamps to the slider maximum")

	# Settings exposes the slider and applies it to the live rig.
	var menu_scene := load("res://scenes/ui/settings_menu.tscn") as PackedScene
	if menu_scene == null:
		_failures.append("settings menu scene failed to load")
	else:
		var menu := menu_scene.instantiate()
		menu.visible = false
		world.add_child(menu)
		await process_frame
		var slider := menu.get_node_or_null(
			"Root/Panel/Margin/VBox/Scroll/Rows/CameraSensitivityRow/CameraSensitivitySlider") as HSlider
		_assert_true(slider != null, "settings exposes a camera sensitivity slider")
		if slider != null:
			rig.set_look_sensitivity(1.0, false)
			slider.value = 1.6
			_assert_true(is_equal_approx(float(rig.get_look_sensitivity()), 1.6),
				"moving the settings slider applies sensitivity live")
		menu.queue_free()
	rig.set("settings_path", real_settings_path)
	rig.set_look_sensitivity(1.0, false)

	# Horizontal mouse-wheel events are a second desktop fallback for trackpads
	# and mice that expose left/right scrolling.
	rig.set_angles(0.0, -0.62)
	rig._handle_mouse_button(_mouse_button(MOUSE_BUTTON_WHEEL_LEFT, true))
	var wheel_left_yaw: float = float(rig.target_angle_h)
	rig._handle_mouse_button(_mouse_button(MOUSE_BUTTON_WHEEL_RIGHT, true))
	_assert_true(wheel_left_yaw > 0.0 and float(rig.target_angle_h) < wheel_left_yaw,
		"horizontal mouse-wheel events rotate the camera in both directions")

	# Desktop left-button drag turns the camera after travel, while a plain
	# click keeps emitting a world move tap.
	rig.set_angles(0.0, -0.62)
	var mouse_yaw: float = float(rig.target_angle_h)
	rig._handle_mouse_button(_mouse_button(MOUSE_BUTTON_LEFT, true))
	rig._unhandled_input(_mouse_motion(Vector2(40.0, 0.0), Vector2(200.0, 300.0)))
	rig._handle_mouse_button(_mouse_button(MOUSE_BUTTON_LEFT, false))
	_assert_true(float(rig.target_angle_h) < mouse_yaw,
		"desktop left-drag turns the third-person camera")

	# Crossing +/- PI must use the short arc instead of visibly spinning the
	# camera almost a full revolution.
	rig.set_angles(PI - 0.01, -0.62)
	rig.rotation.y = -PI + 0.01
	rig._update_camera_position(0.1)
	_assert_true(absf(angle_difference(float(rig.rotation.y), float(rig.target_angle_h))) < 0.1,
		"camera yaw interpolates across the wrap boundary")

	_finish()

func _count_move(direction: Vector2) -> void:
	if direction.length() > 0.01:
		_move_emits += 1

func _motion(x: float, y: float) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(x, y)
	return e

func _mouse_motion(relative: Vector2, position: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = relative
	e.position = position
	return e

func _touch(index: int, pressed: bool) -> InputEventScreenTouch:
	return _touch_at(index, pressed, Vector2.ZERO)

func _touch_at(index: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = pressed
	e.position = position
	return e

func _drag(index: int, rel: Vector2, position: Vector2 = Vector2.INF) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.relative = rel
	e.position = position if position != Vector2.INF else rel
	return e

func _mouse_button(button: int, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
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
		print("=== First-Person Free-Look + Third-Person Camera Drag Validation ===")
		print("passes=1 failures=0")
		quit(0)
