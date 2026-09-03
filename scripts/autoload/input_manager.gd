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
var is_mobile: bool = OS.has_feature("mobile")
var last_tap_time: float = 0.0
var tap_threshold: float = 0.3
var world_gesture_active: bool = false  # true while two-finger camera gesture
var first_person_active: bool = false   # true while CameraRig drives a 1-finger free-look
var active_camera: Camera3D = null
var held_move_keys: Dictionary = {}
var _drag_samples: Dictionary = {}  # index -> {speed: float, dir: Vector2}

func _ready() -> void:
	Input.set_use_accumulated_input(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_key(event)
	elif event is InputEventScreenTouch and is_mobile:
		_handle_touch(event)
	elif event is InputEventScreenDrag and is_mobile:
		_handle_drag(event)
	elif event is InputEventMouseButton and not is_mobile:
		_handle_mouse(event)
	elif event is InputEventMouseMotion and not is_mobile:
		_handle_mouse_motion(event)

func _handle_key(event: InputEventKey) -> void:
	if event.pressed and event.echo:
		return
	if event.pressed:
		held_move_keys[event.keycode] = true
		match event.keycode:
			KEY_F: scan_pressed.emit()
			KEY_Q: skill_slot_pressed.emit(0)
			KEY_E: skill_slot_pressed.emit(1)
			KEY_R: skill_slot_pressed.emit(2)
			KEY_SPACE, KEY_ENTER: interact_pressed.emit()
			KEY_ESCAPE: pause_pressed.emit()
			KEY_SHIFT: dodge_pressed.emit(Vector2.ZERO)
			KEY_C, KEY_CTRL: jump_pressed.emit()
	else:
		held_move_keys.erase(event.keycode)
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
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
		_drag_samples[event.index] = {"speed": 0.0, "dir": Vector2.ZERO, "time": Time.get_ticks_msec() / 1000.0}
		if now - last_tap_time < tap_threshold:
			interact_pressed.emit()
			last_tap_time = 0.0
		elif active_camera:
			last_tap_time = now
			emit_world_tap(event.position, active_camera)
		else:
			last_tap_time = now
	else:
		if not world_gesture_active and _drag_samples.has(event.index):
			var sample: Dictionary = _drag_samples[event.index]
			if sample.speed > flick_threshold:
				dodge_pressed.emit(sample.dir)
		_drag_samples.erase(event.index)

func _handle_drag(event: InputEventScreenDrag) -> void:
	if world_gesture_active:
		move_input.emit(Vector2.ZERO)
		return
	# In first-person view a one-finger drag is camera free-look (consumed by
	# CameraRig). Keep tracking the sample so fast flicks still dodge.
	if first_person_active:
		_track_drag_sample(event, event.relative)
		return
	var relative := event.relative
	if relative.length() > touch_deadzone:
		move_input.emit(relative.normalized())
		_track_drag_sample(event, relative)
	else:
		move_input.emit(Vector2.ZERO)

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
				# empty-world click is a movement tap (mirrors mobile).
				if active_camera:
					emit_world_tap(event.position, active_camera)
			MOUSE_BUTTON_RIGHT: interact_pressed.emit()
	else:
		match event.button_index:
			MOUSE_BUTTON_RIGHT: interact_released.emit()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	pass

func set_active_camera(camera: Camera3D) -> void:
	active_camera = camera

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
