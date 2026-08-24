extends Node3D
class_name CameraRig

## === ArcRotate Camera Rig (embervale style) ===
## Top-down arc-follow with velocity look-ahead, hit-reaction shake,
## cinematic depth of field and tighter top-down framing

@export var distance: float = 17.5
@export var min_distance: float = 11.0
@export var max_distance: float = 28.0
@export var height: float = 18.0
@export var rotation_speed: float = 2.2
@export var follow_speed: float = 10.0
@export var look_ahead_factor: float = 0.22
@export var shake_decay: float = 3.0

# Framing & focus
@export var fov: float = 40.0
@export var dof_enabled: bool = true
@export var dof_far_offset: float = 7.0
@export var dof_far_transition: float = 7.0
@export var dof_blur_amount: float = 0.07

@onready var camera: Camera3D = $SpringArm/Camera3D
@onready var spring_arm: SpringArm3D = $SpringArm

var target: Node3D = null
var target_velocity: Vector3 = Vector3.ZERO
var current_shake: Vector3 = Vector3.ZERO
var target_angle_h: float = 0.0  # Horizontal (yaw)
var target_angle_v: float = -0.95  # Vertical (pitch, ~-54 deg top-down)
var cam_attributes: CameraAttributesPractical = null
var camera_base_position: Vector3 = Vector3.ZERO

# Cinematics (boss intro / kill-cam)
var _cinematic := false
var _cine_t := 0.0
var _cine_dur := 2.6
var _cine_focus := Vector3.ZERO
var _cine_anchor := Vector3.ZERO
var _restore_distance: float = 17.5

# Drag-release orbital inertia
@export var inertia_strength: float = 1.15
@export var inertia_decay: float = 4.0
var _drag_ang_vel := Vector2.ZERO  # (yaw, pitch) rad/s

func _ready() -> void:
	# Find hero
	target = get_parent().get_node_or_null("Hero")
	if not target:
		push_error("CameraRig: No Hero found!")
	
	# Initialize spring arm
	spring_arm.spring_length = distance
	spring_arm.margin = 0.5
	
	# Snap to default top-down framing on first frame
	rotation.y = target_angle_h
	rotation.x = target_angle_v
	
	camera.fov = fov
	camera_base_position = camera.position
	InputManager.set_active_camera(camera)
	if dof_enabled:
		cam_attributes = CameraAttributesPractical.new()
		cam_attributes.dof_blur_far_enabled = true
		cam_attributes.dof_blur_far_distance = distance + dof_far_offset
		cam_attributes.dof_blur_far_transition = dof_far_transition
		cam_attributes.dof_blur_amount = dof_blur_amount
		camera.attributes = cam_attributes

func _physics_process(delta: float) -> void:
	if not target or not is_instance_valid(target):
		return
	
	if _cinematic:
		_update_cinematic(delta)
		_apply_shake(delta)
		return
	
	_apply_drag_inertia(delta)
	_apply_idle_drift(delta)
	_update_camera_position(delta)
	_apply_shake(delta)

func _is_user_rotating() -> bool:
	return _drag_rotate or _touch_pos.size() >= 2

func _apply_drag_inertia(delta: float) -> void:
	if _is_user_rotating() or _drag_ang_vel.length_squared() < 0.0004:
		if not _is_user_rotating():
			_drag_ang_vel = Vector2.ZERO
		return
	target_angle_h += _drag_ang_vel.x * inertia_strength * delta
	target_angle_v = clampf(
		target_angle_v + _drag_ang_vel.y * inertia_strength * delta, -1.35, -0.25)
	_drag_ang_vel *= exp(-inertia_decay * delta)

func _apply_idle_drift(delta: float) -> void:
	# Barely-there orbit so the scene breathes when the player stands still
	var player_speed := target_velocity.length() if target_velocity else 0.0
	if _is_user_rotating() or _cinematic or player_speed > 0.4:
		return
	target_angle_h += sin(Time.get_ticks_msec() / 1000.0 * 0.15) * 0.00035

func _update_camera_position(delta: float) -> void:
	var target_pos = target.global_position
	
	# Velocity look-ahead
	if target.has_method("get_body_velocity"):
		target_velocity = target.get_body_velocity()
		target_pos += target_velocity * look_ahead_factor
	
	# Smooth follow
	global_position = global_position.lerp(target_pos, follow_speed * delta)
	
	# Apply rotation
	rotation.y = lerp(rotation.y, target_angle_h, rotation_speed * delta)
	rotation.x = lerp(rotation.x, target_angle_v, rotation_speed * delta)
	
	# Update spring arm length
	spring_arm.spring_length = lerp(spring_arm.spring_length, distance, 5.0 * delta)
	
	# Keep focus plane on the player as zoom changes
	if cam_attributes:
		cam_attributes.dof_blur_far_distance = spring_arm.spring_length + dof_far_offset

func _apply_shake(delta: float) -> void:
	current_shake = current_shake.lerp(Vector3.ZERO, shake_decay * delta)
	if current_shake.length() <= 0.01:
		current_shake = Vector3.ZERO
	camera.position = camera_base_position + current_shake

func add_shake(intensity: float) -> void:
	current_shake += Vector3(
		randf_range(-1, 1),
		randf_range(-1, 1) * 0.5,
		randf_range(-1, 1)
	).normalized() * intensity

# === FOV punch ===
func punch_fov(amount: float, recover: float = 0.35) -> void:
	if not camera:
		return
	var tween := create_tween()
	tween.tween_property(camera, "fov", fov + amount, 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "fov", fov, recover) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# === Boss intro sweep ===
func play_boss_intro(boss: Node3D) -> void:
	if _cinematic or boss == null or not is_instance_valid(boss):
		return
	_cinematic = true
	_cine_t = 0.0
	_cine_dur = 2.6
	_restore_distance = distance
	_cine_focus = boss.global_position + Vector3(0, 2.2, 0)
	_cine_anchor = boss.global_position + Vector3(-6.0, 7.5, 8.0)
	set_distance(13.0)

# === Kill-cam slow-mo ===
func play_kill_cam(focus: Node3D) -> void:
	if _cinematic or focus == null or not is_instance_valid(focus):
		return
	_cinematic = true
	_cine_t = 0.0
	_cine_dur = 2.2
	_restore_distance = distance
	_cine_focus = focus.global_position + Vector3(0, 1.8, 0)
	_cine_anchor = focus.global_position + Vector3(0, 4.5, 6.5)
	set_distance(9.0)
	Engine.time_scale = 0.25
	var timer := get_tree().create_timer(0.9, true, false, true)
	timer.timeout.connect(func():
		if Engine.time_scale < 0.99:
			Engine.time_scale = 1.0)

func _update_cinematic(delta: float) -> void:
	_cine_t += delta
	global_position = global_position.lerp(_cine_anchor, minf(delta * 3.0, 1.0))
	
	# Aim the rig at the cinematic focus
	var dir := (_cine_focus - global_position).normalized()
	target_angle_h = atan2(-dir.x, -dir.z)
	target_angle_v = clampf(asin(clampf(dir.y, -1.0, 1.0)), -1.35, -0.25)
	
	if _cine_t >= _cine_dur:
		_cinematic = false
		target_angle_h = 0.0
		target_angle_v = -0.95
		distance = _restore_distance

func set_target(node: Node3D) -> void:
	target = node

func set_distance(new_distance: float) -> void:
	distance = clamp(new_distance, min_distance, max_distance)

func set_angles(h: float, v: float) -> void:
	target_angle_h = h
	target_angle_v = clamp(v, -1.35, -0.25)  # Clamp vertical angle

func get_angles() -> Vector2:
	return Vector2(target_angle_h, target_angle_v)

# === Input: drag rotate, pinch zoom, wheel zoom ===
@export var rotate_sensitivity: float = 0.005
@export var pinch_zoom_scale: float = 0.035
@export var wheel_zoom_step: float = 2.0

var _drag_rotate: bool = false
var _touch_pos := {}
var _touch_prev := {}

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _drag_rotate:
		var dh: float = -event.relative.x * rotate_sensitivity
		var dv: float = clampf(
			target_angle_v - event.relative.y * rotate_sensitivity, -1.35, -0.25) - target_angle_v
		target_angle_h += dh
		target_angle_v = clampf(target_angle_v + dv, -1.35, -0.25)
		_drag_ang_vel = _drag_ang_vel.lerp(Vector2(dh, dv) * 60.0, 0.4)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_drag_rotate = event.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				set_distance(distance - wheel_zoom_step)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				set_distance(distance + wheel_zoom_step)

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_pos[event.index] = event.position
		_touch_prev[event.index] = event.position
	else:
		_touch_pos.erase(event.index)
		_touch_prev.erase(event.index)
	InputManager.world_gesture_active = _touch_pos.size() >= 2

func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if _touch_pos.size() < 2 or not _touch_pos.has(event.index):
		return
	
	var other_index := -1
	for idx in _touch_pos:
		if idx != event.index:
			other_index = idx
			break
	if other_index == -1:
		return
	
	# Two-finger orbit from the pair's average motion
	var dh := -event.relative.x * 0.5 * rotate_sensitivity
	var dv := clampf(
		target_angle_v - event.relative.y * 0.5 * rotate_sensitivity, -1.35, -0.25) - target_angle_v
	target_angle_h += dh
	target_angle_v = clampf(target_angle_v + dv, -1.35, -0.25)
	_drag_ang_vel = _drag_ang_vel.lerp(Vector2(dh, dv) * 60.0, 0.4)
	
	# Pinch zoom from the pair's distance delta
	var d_now := event.position.distance_to(_touch_pos[other_index])
	var d_prev: float = _touch_prev[event.index].distance_to(_touch_prev[other_index])
	set_distance(distance - (d_now - d_prev) * pinch_zoom_scale)
	
	_touch_pos[event.index] = event.position
	_touch_prev[event.index] = event.position
	_touch_prev[other_index] = _touch_pos[other_index]

func zoom(delta: float) -> void:
	set_distance(distance - delta)

func reset_shake() -> void:
	current_shake = Vector3.ZERO