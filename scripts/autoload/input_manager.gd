extends Node

## === Centralized Input Handling ===
## Maps actions to game logic, handles mobile touch + desktop

signal move_input(direction: Vector2)
signal interact_pressed
signal interact_released
signal attack_pressed
signal attack_released
signal skill_slot_pressed(slot: int)
signal scan_pressed
signal pause_pressed
signal dodge_pressed(direction: Vector2)
signal jump_pressed
signal tap_world(position: Vector3, camera: Camera3D)
signal tap_foe(enemy: Node3D)

@export var touch_deadzone: float = 0.15
@export var flick_threshold: float = 1600.0
var is_mobile: bool = OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]
var last_tap_time: float = 0.0
var tap_threshold: float = 0.3
var world_gesture_active: bool = false  # true while two-finger camera gesture
var first_person_active: bool = false   # true while CameraRig drives a 1-finger free-look
var active_camera: Camera3D = null
var active_camera_controller: Node = null
var held_move_keys: Dictionary = {}
const MOVEMENT_KEYCODES: Array[int] = [
	KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
]
var _was_paused: bool = false
var _drag_samples: Dictionary = {}  # index -> {speed: float, dir: Vector2}
var _drag_start_positions: Dictionary = {}  # pointer id -> screen position
var _joystick_pointer_ids: Dictionary = {}
var _first_person_look_pointer: int = -1
## Look-zone presses are held until release: if the gesture becomes a camera
## drag it must not also order the hero to walk, and a clean tap still moves.
var _deferred_world_taps: Dictionary = {}  # pointer id -> press position
var _camera_gesture_pointers: Dictionary = {}  # pointer ids owned by the camera
var _camera_zone_pointers: Dictionary = {}  # pointer ids that began in the look zone
var _mouse_tap_pending: bool = false
var _mouse_press_position: Vector2 = Vector2.ZERO
## Fallback tap travel when no CameraRig is registered. The rig owns the
## authoritative threshold through camera_drag_threshold().
const CAMERA_TAP_SLOP := 6.0
const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_KEY_BINDINGS: Dictionary = {
	"scan": KEY_F, "skill_0": KEY_Q, "skill_1": KEY_E, "skill_2": KEY_R,
	"interact": KEY_SPACE, "pause": KEY_ESCAPE, "dodge": KEY_SHIFT, "jump": KEY_C,
}
var key_bindings: Dictionary = DEFAULT_KEY_BINDINGS.duplicate()

func _ready() -> void:
	Input.set_use_accumulated_input(false)
	add_to_group("input_manager")
	_load_key_bindings()
	# Stay subscribed while the tree is paused so a key or touch release that
	# happens over an open menu is still observed (see _recover_input_state).
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	var paused := get_tree().paused
	if _was_paused and not paused:
		_recover_input_state()
	_was_paused = paused

## Menus freeze the world and take ownership of input while they are open, so a
## release that lands during the pause may never reach this node (and arrow keys
## are consumed by focused controls even when it does). Rebuild the held state
## from the engine, which keeps tracking keys regardless of pause, so the hero
## cannot resume with a stale direction, and drop any touch gesture that the
## menu swallowed for the same reason.
func _recover_input_state() -> void:
	clear_joystick_pointers()
	_drag_start_positions.clear()
	_first_person_look_pointer = -1
	_cancel_deferred_taps()
	_camera_gesture_pointers.clear()
	_camera_zone_pointers.clear()
	_mouse_tap_pending = false
	world_gesture_active = false
	for keycode in MOVEMENT_KEYCODES:
		if Input.is_key_pressed(keycode):
			held_move_keys[keycode] = true
		else:
			held_move_keys.erase(keycode)
	_emit_keyboard_move()

func get_key_binding(action: String) -> int:
	return int(key_bindings.get(action, DEFAULT_KEY_BINDINGS.get(action, -1)))

func set_key_binding(action: String, keycode: int) -> bool:
	if not DEFAULT_KEY_BINDINGS.has(action) or keycode <= 0:
		return false
	for other_action in key_bindings:
		if str(other_action) != action and int(key_bindings[other_action]) == keycode:
			return false
	key_bindings[action] = keycode
	_save_key_bindings()
	return true

func reset_key_bindings() -> void:
	key_bindings = DEFAULT_KEY_BINDINGS.duplicate()
	_save_key_bindings()

func _load_key_bindings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for action in DEFAULT_KEY_BINDINGS:
		var saved := int(config.get_value("key_bindings", str(action), DEFAULT_KEY_BINDINGS[action]))
		if saved > 0:
			key_bindings[action] = saved
	# Invalid/duplicate saved layouts are discarded atomically.
	if not _bindings_are_valid(key_bindings):
		key_bindings = DEFAULT_KEY_BINDINGS.duplicate()

func _save_key_bindings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	for action in DEFAULT_KEY_BINDINGS:
		config.set_value("key_bindings", str(action), get_key_binding(str(action)))
	config.save(SETTINGS_PATH)

func _bindings_are_valid(bindings: Dictionary) -> bool:
	var used: Dictionary = {}
	for action in DEFAULT_KEY_BINDINGS:
		var keycode := int(bindings.get(action, -1))
		if keycode <= 0 or used.has(keycode):
			return false
		used[keycode] = true
	return true

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		# A frozen world means a menu owns input. Gameplay actions must not fire
		# here, but held movement keys still have to be tracked: a release that
		# lands while the menu is open would otherwise be lost and the hero
		# would resume walking in that direction on its own.
		if event is InputEventKey and not event.echo:
			if event.pressed:
				held_move_keys[event.keycode] = true
			else:
				held_move_keys.erase(event.keycode)
		return
	if event is InputEventKey:
		_handle_key(event)
	elif event is InputEventScreenTouch and is_mobile:
		if _is_joystick_pointer(event.index):
			_handle_joystick_pointer(event.index, event.pressed)
			return
		_handle_touch(event)
	elif event is InputEventScreenDrag and is_mobile:
		if _is_joystick_pointer(event.index):
			return
		_handle_drag(event)
	elif event is InputEventMouseButton and not is_mobile:
		_handle_mouse(event)
	elif event is InputEventMouseMotion and not is_mobile:
		_handle_mouse_motion(event)
	elif event is InputEventJoypadButton:
		_handle_joypad_button(event)
	elif event is InputEventJoypadMotion:
		_handle_joypad_motion(event)

func set_joystick_pointer(pointer_id: int, owned: bool) -> void:
	if pointer_id < 0:
		return
	if owned:
		_joystick_pointer_ids[pointer_id] = true
	else:
		_joystick_pointer_ids.erase(pointer_id)

func clear_joystick_pointers() -> void:
	_joystick_pointer_ids.clear()
	_drag_samples.clear()

func _is_joystick_pointer(pointer_id: int) -> bool:
	return _joystick_pointer_ids.has(pointer_id)

## Camera and world gesture owners use this guard so a HUD joystick touch can
## never become an orbit gesture when a second finger is added.
func is_joystick_pointer_owned(pointer_id: int) -> bool:
	return _is_joystick_pointer(pointer_id)

func begin_first_person_look(pointer_id: int) -> void:
	if pointer_id < 0 or _is_joystick_pointer(pointer_id):
		return
	_first_person_look_pointer = pointer_id
	_drag_samples.erase(pointer_id)

func end_first_person_look(pointer_id: int) -> void:
	if pointer_id == -1 or _first_person_look_pointer == pointer_id:
		_first_person_look_pointer = -1
	if pointer_id >= 0:
		_drag_samples.erase(pointer_id)

func _handle_joystick_pointer(pointer_id: int, pressed: bool) -> void:
	if not pressed:
		_joystick_pointer_ids.erase(pointer_id)
		_drag_samples.erase(pointer_id)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear_joystick_pointers()
		_drag_start_positions.clear()
		_first_person_look_pointer = -1
		_cancel_deferred_taps()
		_camera_gesture_pointers.clear()
		_camera_zone_pointers.clear()
		_mouse_tap_pending = false
		world_gesture_active = false

func _handle_key(event: InputEventKey) -> void:
	if event.pressed and event.echo:
		return
	if event.pressed:
		held_move_keys[event.keycode] = true
		if event.keycode == get_key_binding("scan"):
			scan_pressed.emit()
		elif event.keycode == get_key_binding("skill_0"):
			skill_slot_pressed.emit(0)
		elif event.keycode == get_key_binding("skill_1"):
			skill_slot_pressed.emit(1)
		elif event.keycode == get_key_binding("skill_2"):
			skill_slot_pressed.emit(2)
		elif event.keycode == get_key_binding("interact") or event.keycode == KEY_ENTER:
			interact_pressed.emit()
		elif event.keycode == get_key_binding("pause"):
			pause_pressed.emit()
		elif event.keycode == get_key_binding("dodge"):
			dodge_pressed.emit(Vector2.ZERO)
		elif event.keycode == get_key_binding("jump") or event.keycode == KEY_CTRL:
			jump_pressed.emit()
	else:
		held_move_keys.erase(event.keycode)
		if event.keycode == get_key_binding("interact") or event.keycode == KEY_ENTER:
			interact_released.emit()
	_emit_keyboard_move()

func _emit_keyboard_move() -> void:
	var direction := Vector2.ZERO
	if held_move_keys.has(KEY_W) or held_move_keys.has(KEY_UP):
		direction.y -= 1.0
	if held_move_keys.has(KEY_S) or held_move_keys.has(KEY_DOWN):
		direction.y += 1.0
	if held_move_keys.has(KEY_A) or held_move_keys.has(KEY_LEFT):
		direction.x -= 1.0
	if held_move_keys.has(KEY_D) or held_move_keys.has(KEY_RIGHT):
		direction.x += 1.0
	move_input.emit(direction.normalized() if direction.length() > 0 else Vector2.ZERO)

func _handle_touch(event: InputEventScreenTouch) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if event.pressed:
		if first_person_active:
			# CameraRig owns this gesture. Do not turn it into tap-to-move,
			# interaction, or a dodge flick.
			begin_first_person_look(event.index)
			return
		_drag_start_positions[event.index] = event.position
		_drag_samples[event.index] = {"speed": 0.0, "dir": Vector2.ZERO, "time": Time.get_ticks_msec() / 1000.0}
		if _drag_start_positions.size() >= 2:
			# Two fingers are a camera orbit/pinch gesture: neither pointer is
			# a world tap, and any pending look-zone tap is cancelled.
			for index in _drag_start_positions:
				_camera_gesture_pointers[index] = true
			_cancel_deferred_taps()
			return
		if _is_camera_touch_zone(event.position):
			# Decided on release: a drag turns the camera, a clean tap moves.
			_camera_zone_pointers[event.index] = true
			_deferred_world_taps[event.index] = event.position
			return
		_emit_touch_tap(now, event.position)
	else:
		var start_position: Vector2 = _drag_start_positions.get(event.index, Vector2.INF)
		_drag_start_positions.erase(event.index)
		if first_person_active:
			end_first_person_look(event.index)
			return
		if not world_gesture_active and not _camera_zone_pointers.has(event.index) \
				and _drag_samples.has(event.index):
			var sample: Dictionary = _drag_samples[event.index]
			if sample.speed > flick_threshold:
				dodge_pressed.emit(sample.dir)
		_drag_samples.erase(event.index)
		var deferred: Vector2 = _deferred_world_taps.get(event.index, Vector2.INF)
		var claimed := _camera_gesture_pointers.has(event.index)
		_deferred_world_taps.erase(event.index)
		_camera_gesture_pointers.erase(event.index)
		_camera_zone_pointers.erase(event.index)
		if deferred != Vector2.INF and start_position != Vector2.INF and not claimed \
				and event.position.distance_to(start_position) <= _camera_tap_slop():
			_emit_touch_tap(now, start_position)

## Shared tap decision: a second tap inside the window is the interact gesture,
## otherwise the tap commands a move. Look-zone taps reach this on release so a
## camera drag can drop them before they ever move the hero.
func _emit_touch_tap(now: float, position: Vector2) -> void:
	if now - last_tap_time < tap_threshold:
		interact_pressed.emit()
		last_tap_time = 0.0
	elif active_camera:
		last_tap_time = now
		emit_world_tap(position, active_camera)
	else:
		last_tap_time = now

func _cancel_deferred_taps() -> void:
	_deferred_world_taps.clear()

func _is_camera_touch_zone(position: Vector2) -> bool:
	if active_camera_controller == null or not is_instance_valid(active_camera_controller):
		return false
	if not active_camera_controller.has_method("is_camera_touch_zone"):
		return false
	return bool(active_camera_controller.call("is_camera_touch_zone", position))

func _camera_tap_slop() -> float:
	if active_camera_controller != null and is_instance_valid(active_camera_controller) \
			and active_camera_controller.has_method("camera_drag_threshold"):
		return float(active_camera_controller.call("camera_drag_threshold"))
	return CAMERA_TAP_SLOP

func _handle_joypad_button(event: InputEventJoypadButton) -> void:
	if not event.pressed:
		if event.button_index == JOY_BUTTON_A:
			interact_released.emit()
		return
	match event.button_index:
		JOY_BUTTON_A: interact_pressed.emit()
		JOY_BUTTON_B: dodge_pressed.emit(Vector2.ZERO)
		JOY_BUTTON_X: skill_slot_pressed.emit(0)
		JOY_BUTTON_Y: skill_slot_pressed.emit(1)
		JOY_BUTTON_LEFT_SHOULDER: skill_slot_pressed.emit(2)
		JOY_BUTTON_RIGHT_SHOULDER: scan_pressed.emit()
		JOY_BUTTON_START: pause_pressed.emit()

func _handle_joypad_motion(event: InputEventJoypadMotion) -> void:
	if event.axis != JOY_AXIS_LEFT_X and event.axis != JOY_AXIS_LEFT_Y:
		return
	var direction := Vector2(
		Input.get_joy_axis(event.device, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(event.device, JOY_AXIS_LEFT_Y))
	move_input.emit(direction.limit_length(1.0) if direction.length() > touch_deadzone else Vector2.ZERO)

func _handle_drag(event: InputEventScreenDrag) -> void:
	if world_gesture_active:
		move_input.emit(Vector2.ZERO)
		return
	# In first-person view a one-finger drag is camera free-look (consumed by
	# CameraRig). Keep tracking the sample so fast flicks still dodge.
	if first_person_active:
		# CameraRig consumes this pointer. It must never become movement or
		# dodge input, even when the drag is fast.
		return
	var relative := event.relative
	if _camera_consumes_world_drag(event):
		# A horizontal drag on the camera side of the world is an orbit gesture,
		# not player steering. Emit a stop so an earlier movement sample cannot
		# keep the hero sliding while the player pans the view.
		move_input.emit(Vector2.ZERO)
		return
	if _camera_zone_pointers.has(event.index):
		# A press in the look zone is either a camera drag or a tap. Until it
		# passes the camera deadzone it must not steer the hero.
		move_input.emit(Vector2.ZERO)
		return
	if relative.length() > touch_deadzone:
		move_input.emit(relative.normalized())
		_track_drag_sample(event, relative)
	else:
		move_input.emit(Vector2.ZERO)

func _camera_consumes_world_drag(event: InputEventScreenDrag) -> bool:
	if active_camera_controller == null or not is_instance_valid(active_camera_controller):
		return false
	if not active_camera_controller.has_method("consume_world_drag"):
		return false
	var start_position := event.position
	if _drag_start_positions.has(event.index):
		start_position = _drag_start_positions[event.index]
	var consumed := bool(active_camera_controller.call("consume_world_drag",
		start_position, event.relative, event.index, event.position))
	if consumed:
		_camera_gesture_pointers[event.index] = true
		_deferred_world_taps.erase(event.index)
	return consumed

func _track_drag_sample(event: InputEventScreenDrag, relative: Vector2) -> void:
	if relative.length() <= touch_deadzone:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _drag_samples.has(event.index):
		var sample: Dictionary = _drag_samples[event.index]
		var dt: float = max(now - float(sample.get("time", now)), 0.001)
		var speed := relative.length() / dt
		var dir := relative.normalized() if relative.length() > 0.0001 else Vector2.ZERO
		sample.speed = lerpf(float(sample.speed), speed, 0.45)
		sample.dir = dir
		sample.time = now

func _handle_mouse(event: InputEventMouseButton) -> void:
	if event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				# Desktop "attack" lives on the Attack button only; an
				# empty-world click is a movement tap (mirrors mobile). The
				# tap waits for release so a left-drag can turn the camera.
				_mouse_tap_pending = true
				_mouse_press_position = event.position
			MOUSE_BUTTON_RIGHT: interact_pressed.emit()
	else:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _mouse_tap_pending and active_camera \
						and event.position.distance_to(_mouse_press_position) <= _camera_tap_slop():
					emit_world_tap(_mouse_press_position, active_camera)
				_mouse_tap_pending = false
			MOUSE_BUTTON_RIGHT: interact_released.emit()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _mouse_tap_pending \
			and event.position.distance_to(_mouse_press_position) > _camera_tap_slop():
		_mouse_tap_pending = false

func set_active_camera(camera: Camera3D, controller: Node = null) -> void:
	active_camera = camera
	active_camera_controller = controller

func emit_world_tap(screen_pos: Vector2, camera: Camera3D) -> void:
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000.0
	var space_state = get_tree().get_root().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	# Enemy layer + Environment: a tap that lands on a foe LIGHTS IT UP
	# (engage + mark) instead of moving — that's the discoverable gesture.
	query.collision_mask = 1 << 1 | 1 << 5 | 1 << 6
	query.exclude = [get_tree().current_scene.find_child("Hero")] if get_tree().current_scene and get_tree().current_scene.has_node("Hero") else []
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.get("collider")
		if collider != null and collider.is_in_group("enemy"):
			tap_foe.emit(collider)
			return
		tap_world.emit(result.position, camera)
