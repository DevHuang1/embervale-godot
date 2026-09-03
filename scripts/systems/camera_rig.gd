extends Node3D
class_name CameraRig

## === ArcRotate Camera Rig (embervale style) ===
## Top-down arc-follow with velocity look-ahead, hit-reaction shake,
## cinematic depth of field and tighter top-down framing.
## Also supports a cinematic 3rd-person mode for immersive close-up gameplay.

signal view_mode_changed(mode: String)

const VIEW_FIRST_PERSON := "first_person"
const VIEW_THIRD_PERSON := "third_person"
const VIEW_TOP_DOWN := "top_down"

@export var distance: float = 17.5
@export var min_distance: float = 11.0
@export var max_distance: float = 28.0
@export var height: float = 18.0
@export var rotation_speed: float = 2.2
@export var follow_speed: float = 10.0
@export var look_ahead_factor: float = 0.22
@export var shake_decay: float = 3.0
@export var shake_amplitude_cap: float = 0.65
@export var mobile_shake_multiplier: float = 0.72
@export var reduced_motion_multiplier: float = 0.35
@export_enum("full", "mobile", "reduced", "off") var feedback_mode: String = "full"

# Framing & focus
@export var fov: float = 40.0
@export var dof_enabled: bool = true
@export var dof_far_offset: float = 7.0
@export var dof_far_transition: float = 7.0
@export var dof_blur_amount: float = 0.07
@export var top_down_target_height: float = 0.65

# 3rd-person cinematic mode preset
@export var third_person: bool = false
@export var third_person_distance: float = 13.0
@export var third_person_angle_v: float = -0.62
@export var third_person_target_height: float = 1.15
@export var third_person_fov: float = 55.0
@export var third_person_min_distance: float = 8.0
@export var third_person_max_distance: float = 24.0
@export var first_person_distance: float = 0.12
@export var first_person_angle_v: float = -0.20
@export var first_person_target_height: float = 1.52
@export var first_person_fov: float = 68.0
@export var boss_distance: float = 15.5
@export var boss_min_distance: float = 12.0
@export var boss_max_distance: float = 22.0
@export var boss_fov: float = 46.0
@export var mode_lerp_speed: float = 3.0
# First-person free-look: turn the view left/right to look around on any
# device (mouse motion on desktop, a one-finger drag elsewhere). The orbit
# modes keep their wide arc; first person stays near level with this band.
@export var first_person_look_sensitivity: float = 0.004
@export var first_person_pitch_min: float = -0.65
@export var first_person_pitch_max: float = 0.10

@onready var camera: Camera3D = $SpringArm/Camera3D
@onready var spring_arm: SpringArm3D = $SpringArm

var target: Node3D = null
var target_velocity: Vector3 = Vector3.ZERO
var current_shake: Vector3 = Vector3.ZERO
var _shake_envelope: float = 0.0
var _shake_vector: Vector3 = Vector3.ZERO
var _shake_phase: float = 0.0
var _shake_priority: int = 0
var _shake_decay_rate: float = 8.0
var _hit_stop_until_msec: int = 0
var _hit_stop_restore_scale: float = 1.0
var target_angle_h: float = 0.0  # Horizontal (yaw)
var target_angle_v: float = -0.95  # Vertical (pitch, ~-54 deg top-down)
var cam_attributes: CameraAttributesPractical = null
var camera_base_position: Vector3 = Vector3.ZERO
var view_mode: String = VIEW_THIRD_PERSON
var settings_path: String = AudioManager.SETTINGS_PATH

# Mode switching state: lerps between top-down and 3rd-person
var _target_distance: float = 17.5
var _target_angle_v: float = -0.95
var _target_fov: float = 40.0
var _target_min_dist: float = 11.0
var _target_max_dist: float = 28.0

# Cinematics (boss intro / kill-cam)
var _cinematic := false
var _cine_t := 0.0
var _cine_dur := 2.6
var _cine_focus := Vector3.ZERO
var _cine_anchor := Vector3.ZERO
var _restore_distance: float = 17.5
var _boss_combat := false

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
	
	# Third person is the new default. Existing top-down callers remain valid
	# through set_camera_mode(), while the persisted player choice uses the
	# explicit first/third-person interface.
	view_mode = _load_view_mode()
	set_view_mode(view_mode, true, false)
	
	# Snap to default framing on first frame
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
	target_angle_v = _clamp_pitch(target_angle_v + _drag_ang_vel.y * inertia_strength * delta)
	_drag_ang_vel *= exp(-inertia_decay * delta)

func _apply_idle_drift(delta: float) -> void:
	# Barely-there orbit so the scene breathes when the player stands still
	var player_speed := target_velocity.length() if target_velocity else 0.0
	# A fixed-head self-orbit reads as motion sickness in first person; only
	# breathe the yaw in the over-the-shoulder views.
	if view_mode == VIEW_FIRST_PERSON or _is_user_rotating() or _cinematic or player_speed > 0.4:
		return
	target_angle_h += sin(Time.get_ticks_msec() / 1000.0 * 0.15) * 0.00035

func _update_camera_position(delta: float) -> void:
	var target_pos: Vector3 = target.global_position
	# Aim at the Hero’s torso rather than the feet. This keeps the ground
	# plane below the frame in third-person mode and prevents terrain/POM
	# textures from visually swallowing the lower body.
	var focus_height := first_person_target_height if view_mode == VIEW_FIRST_PERSON \
		else (third_person_target_height if third_person else top_down_target_height)
	target_pos.y += focus_height
		
	# Velocity look-ahead
	if target.has_method("get_body_velocity"):
		target_velocity = target.get_body_velocity()
		target_pos += target_velocity * look_ahead_factor
	
	# Smooth follow
	global_position = global_position.lerp(target_pos, follow_speed * delta)
	
	# Smooth lerp distance, pitch, and FOV toward mode targets
	var lerp_rate := mode_lerp_speed * delta
	distance = lerpf(distance, _target_distance, lerp_rate)
	target_angle_v = lerpf(target_angle_v, _target_angle_v, lerp_rate)
	if camera:
		camera.fov = lerpf(camera.fov, _target_fov, lerp_rate)
	
	# Apply rotation
	rotation.y = lerp(rotation.y, target_angle_h, rotation_speed * delta)
	rotation.x = lerp(rotation.x, target_angle_v, rotation_speed * delta)
	
	# Update spring arm length
	spring_arm.spring_length = lerp(spring_arm.spring_length, distance, 5.0 * delta)
	
	# Keep focus plane on the player as zoom changes
	if cam_attributes:
		cam_attributes.dof_blur_far_distance = spring_arm.spring_length + dof_far_offset

func _apply_shake(delta: float) -> void:
	_shake_phase += delta
	_shake_envelope *= exp(-_shake_decay_rate * delta)
	_shake_vector = _shake_vector.lerp(Vector3.ZERO,
		1.0 - exp(-18.0 * delta))
	var noise := Vector3(
		sin(_shake_phase * 31.0),
		cos(_shake_phase * 37.0) * 0.45,
		sin(_shake_phase * 43.0 + 0.7))
	current_shake = _clamp_vector(_shake_vector + noise * (_shake_envelope * 0.35),
		shake_amplitude_cap)
	camera.position = camera_base_position + current_shake
	if _shake_envelope <= 0.005:
		_shake_envelope = 0.0
		_shake_vector = Vector3.ZERO
		_shake_priority = 0
	_poll_hit_stop()

## Request one named impact. Lower-priority events never erase a stronger
## response; equal events merge gently; stronger events take ownership.
func request_feedback(tier: String, direction: Vector3 = Vector3.ZERO,
		weight: float = 1.0) -> void:
	var profile: Dictionary = ImpactDirector.FEEDBACK_TIERS.get(
		tier, ImpactDirector.FEEDBACK_TIERS["light"])
	weight = clampf(weight, 0.0, 1.5)
	var quality := 1.0
	match feedback_mode:
		"mobile":
			quality = mobile_shake_multiplier
		"reduced":
			quality = reduced_motion_multiplier
		"off":
			quality = 0.0
	var requested := clampf(float(profile.shake) * weight * quality,
		0.0, shake_amplitude_cap)
	var active := _shake_envelope > 0.01
	var priority := int(profile.priority)
	var merge := 1.0
	if active and priority < _shake_priority:
		merge = 0.25
	elif priority > _shake_priority:
		merge = 0.85
	elif active:
		merge = 0.55
	_shake_envelope = minf(shake_amplitude_cap,
		_shake_envelope + requested * merge)
	_shake_priority = maxi(_shake_priority, priority)
	_shake_decay_rate = maxf(_shake_decay_rate, float(profile.decay))

	var impulse_dir := direction
	if impulse_dir.length_squared() < 0.0001:
		impulse_dir = Vector3.FORWARD
	impulse_dir = impulse_dir.normalized()
	var transverse := Vector3(
		sin(_shake_phase * 1.71 + 1.3),
		cos(_shake_phase * 1.17 + 0.6) * 0.45,
		sin(_shake_phase * 0.83 + 2.4)).normalized()
	var impulse := (impulse_dir * 0.65 + transverse * 0.35).normalized()
	_shake_vector = _clamp_vector(
		_shake_vector + impulse * requested, shake_amplitude_cap)
	_apply_hit_stop(profile, quality, weight)
	var fov_amount := float(profile.fov) * quality
	if fov_amount > 0.0:
		punch_fov(fov_amount)

## Backward-compatible API used by existing gameplay effects.
func add_shake(intensity: float) -> void:
	var tier := "light"
	if intensity >= 0.45:
		tier = "major"
	elif intensity >= 0.25:
		tier = "heavy"
	elif intensity >= 0.14:
		tier = "medium"
	var base: float = float(ImpactDirector.FEEDBACK_TIERS[tier].shake)
	request_feedback(tier, Vector3.ZERO, intensity / maxf(base, 0.001))

func _apply_hit_stop(profile: Dictionary, quality: float, weight: float) -> void:
	var seconds := float(profile.hitstop) * clampf(weight, 0.5, 1.25)
	if quality <= 0.0 or seconds <= 0.001:
		return
	if _hit_stop_until_msec == 0 and Engine.time_scale < 0.99:
		return
	var now := Time.get_ticks_msec()
	if _hit_stop_until_msec <= now:
		_hit_stop_restore_scale = Engine.time_scale
	_hit_stop_until_msec = maxi(_hit_stop_until_msec,
		now + int(seconds * 1000.0))
	Engine.time_scale = minf(Engine.time_scale, float(profile.time_scale))

func _poll_hit_stop() -> void:
	if _hit_stop_until_msec == 0:
		return
	if Time.get_ticks_msec() >= _hit_stop_until_msec:
		Engine.time_scale = _hit_stop_restore_scale
		_hit_stop_until_msec = 0

func _clamp_vector(value: Vector3, cap: float) -> Vector3:
	var length := value.length()
	if length <= cap or length <= 0.0001:
		return value
	return value / length * cap

# === FOV punch ===
func punch_fov(amount: float, recover: float = 0.35) -> void:
	if not camera:
		return
	var tween := create_tween()
	tween.tween_property(camera, "fov", camera.fov + amount, 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "fov", _target_fov, recover) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# === Boss intro sweep ===
func play_boss_intro(boss: Node3D) -> void:
	if _cinematic or boss == null or not is_instance_valid(boss):
		return
	_cinematic = true
	_cine_t = 0.0
	_cine_dur = 2.6
	_restore_distance = _target_distance
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
	_restore_distance = _target_distance
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
	target_angle_v = clampf(asin(clampf(dir.y, -1.0, 1.0)), -1.35, -0.18)
	
	if _cine_t >= _cine_dur:
		_cinematic = false
		target_angle_h = 0.0
		target_angle_v = _target_angle_v
		distance = _target_distance

func set_target(node: Node3D) -> void:
	target = node

## Boss arenas need a wider readable combat frame without forcing a full
## cinematic camera. The distance is derived from the arena radius and clamped
## for mobile readability and stable spring-arm cost.
func set_boss_combat(active: bool, arena_radius: float = 20.0) -> void:
	_boss_combat = active
	if active:
		var arena_scale := maxf(arena_radius - 20.0, 0.0) * 0.35
		_target_distance = clampf(boss_distance + arena_scale, boss_min_distance, boss_max_distance)
		_target_min_dist = boss_min_distance
		_target_max_dist = boss_max_distance
		_target_fov = boss_fov
	else:
		_apply_view_targets(view_mode)

func set_distance(new_distance: float) -> void:
	distance = clamp(new_distance, _target_min_dist, _target_max_dist)

func set_angles(h: float, v: float) -> void:
	target_angle_h = h
	target_angle_v = clamp(v, -1.35, -0.18)  # Clamp vertical angle

func get_angles() -> Vector2:
	return Vector2(target_angle_h, target_angle_v)

## Switch between 3rd-person cinematic and top-down modes.
## When instant=true the rig snaps immediately; otherwise it lerps smoothly.
func set_camera_mode(new_third_person: bool, instant: bool = false) -> void:
	set_view_mode(VIEW_THIRD_PERSON if new_third_person else VIEW_TOP_DOWN,
		instant, false)

func set_view_mode(new_mode: String, instant: bool = false,
		persist: bool = true) -> void:
	if new_mode not in [VIEW_FIRST_PERSON, VIEW_THIRD_PERSON, VIEW_TOP_DOWN]:
		new_mode = VIEW_THIRD_PERSON
	view_mode = new_mode
	third_person = view_mode == VIEW_THIRD_PERSON
	_apply_view_targets(view_mode)
	if instant:
		distance = _target_distance
		target_angle_v = _target_angle_v
		spring_arm.spring_length = _target_distance
		if camera:
			camera.fov = _target_fov
		min_distance = _target_min_dist
		max_distance = _target_max_dist
	_set_target_first_person_visibility(view_mode == VIEW_FIRST_PERSON)
	# Route one-finger drags to the rig (free-look) instead of drag steering.
	InputManager.first_person_active = view_mode == VIEW_FIRST_PERSON
	if persist:
		_save_view_mode()
	view_mode_changed.emit(view_mode)

func toggle_first_third_person() -> void:
	set_view_mode(VIEW_THIRD_PERSON if view_mode == VIEW_FIRST_PERSON \
		else VIEW_FIRST_PERSON)

func _apply_view_targets(mode: String) -> void:
	match mode:
		VIEW_FIRST_PERSON:
			_target_distance = first_person_distance
			_target_angle_v = first_person_angle_v
			_target_fov = first_person_fov
			_target_min_dist = first_person_distance
			_target_max_dist = first_person_distance
		VIEW_TOP_DOWN:
			_target_distance = 17.5
			_target_angle_v = -0.95
			_target_fov = 40.0
			_target_min_dist = 11.0
			_target_max_dist = 28.0
		_:
			_target_distance = third_person_distance
			_target_angle_v = third_person_angle_v
			_target_fov = third_person_fov
			_target_min_dist = third_person_min_distance
			_target_max_dist = third_person_max_distance

func _set_target_first_person_visibility(first_person: bool) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_visual := target.get_node_or_null("Visual") as Node3D
	if target_visual != null:
		target_visual.visible = not first_person

func _load_view_mode() -> String:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return VIEW_THIRD_PERSON
	var stored := str(config.get_value("gameplay", "camera_view", VIEW_THIRD_PERSON))
	return stored if stored in [VIEW_FIRST_PERSON, VIEW_THIRD_PERSON] else VIEW_THIRD_PERSON

func _save_view_mode() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value("gameplay", "camera_view", view_mode)
	config.save(settings_path)

# === Input: drag rotate, pinch zoom, wheel zoom ===
@export var rotate_sensitivity: float = 0.005
@export var pinch_zoom_scale: float = 0.035
@export var wheel_zoom_step: float = 2.0

var _drag_rotate: bool = false
var _touch_pos := {}
var _touch_prev := {}

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_V:
		toggle_first_third_person()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _drag_rotate:
		var dh: float = -event.relative.x * rotate_sensitivity
		var dv: float = _clamp_pitch(
			target_angle_v - event.relative.y * rotate_sensitivity) - target_angle_v
		target_angle_h += dh
		target_angle_v = _clamp_pitch(target_angle_v + dv)
		_drag_ang_vel = _drag_ang_vel.lerp(Vector2(dh, dv) * 60.0, 0.4)
		if view_mode == VIEW_FIRST_PERSON:
			_target_angle_v = target_angle_v
	elif event is InputEventMouseMotion and not _drag_rotate and view_mode == VIEW_FIRST_PERSON:
		# Desktop free-look: moving the mouse turns the first-person view.
		_apply_first_person_look(event.relative)
		get_viewport().set_input_as_handled()
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
	# First-person free-look: a single finger turns the view left/right.
	# Movement keeps its own inputs (tap-to-move and the on-screen joystick),
	# so the drag never steers in first person.
	if view_mode == VIEW_FIRST_PERSON and _touch_pos.size() == 1 \
			and _touch_pos.has(event.index):
		_apply_first_person_look(event.relative)
		return
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
	var dv := _clamp_pitch(
		target_angle_v - event.relative.y * 0.5 * rotate_sensitivity) - target_angle_v
	target_angle_h += dh
	target_angle_v = _clamp_pitch(target_angle_v + dv)
	_drag_ang_vel = _drag_ang_vel.lerp(Vector2(dh, dv) * 60.0, 0.4)
	if view_mode == VIEW_FIRST_PERSON:
		_target_angle_v = target_angle_v
	
	# Pinch zoom from the pair's distance delta
	var d_now := event.position.distance_to(_touch_pos[other_index])
	var d_prev: float = _touch_prev[event.index].distance_to(_touch_prev[other_index])
	set_distance(distance - (d_now - d_prev) * pinch_zoom_scale)
	
	_touch_pos[event.index] = event.position
	_touch_prev[event.index] = event.position
	_touch_prev[other_index] = _touch_pos[other_index]

func _apply_first_person_look(relative: Vector2) -> void:
	target_angle_h -= relative.x * first_person_look_sensitivity
	target_angle_v = _clamp_pitch(target_angle_v - relative.y * first_person_look_sensitivity)
	# Tell the mode lerp our hand-picked pitch is the target so nothing eases
	# the head back to the authored first-person pitch mid-look.
	_target_angle_v = target_angle_v
	_drag_ang_vel = Vector2.ZERO

## Pitch clamp for the current view: orbit modes use the whole [-1.35,-0.18]
## arc, while first person keeps the head near level so fights stay readable.
func _clamp_pitch(v: float) -> float:
	if view_mode == VIEW_FIRST_PERSON:
		return clampf(v, first_person_pitch_min, first_person_pitch_max)
	return clampf(v, -1.35, -0.18)

func zoom(delta: float) -> void:
	set_distance(distance - delta)

func reset_shake() -> void:
	current_shake = Vector3.ZERO
	_shake_envelope = 0.0
	_shake_vector = Vector3.ZERO
	_shake_priority = 0
	_shake_decay_rate = shake_decay
	if camera:
		camera.position = camera_base_position
	if _hit_stop_until_msec != 0:
		Engine.time_scale = _hit_stop_restore_scale
	_hit_stop_until_msec = 0
