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

const HITSTOP_LEASE := "camera_hitstop"
const KILLCAM_LEASE := "camera_killcam"

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
## Keep combat readability deterministic: depth-of-field blurs world-space
## damage numbers and health plates at different distances from the focus
## plane. Atmospheric fog already supplies depth separation on mobile.
@export var dof_enabled: bool = false
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
## Indoor orbit band. A structure room is a few metres tall, so the outdoor
## third-person pitch (-35 deg) puts the camera above the roofline looking down
## at floor and roof tops. Indoors the same distance is kept and the pitch
## flattens, which frames the room and the fight ahead; the spring arm's own
## collision against the walls keeps the camera inside the building.
@export var indoor_pitch_min: float = -0.26
@export var indoor_pitch_max: float = -0.05
@export var mode_lerp_speed: float = 3.0
# First-person free-look: turn the view left/right to look around on any
# device (mouse motion on desktop, a one-finger drag elsewhere). The orbit
# modes keep their wide arc; first person stays near level with this band.
@export var first_person_look_sensitivity: float = 0.004
@export var first_person_invert_y: bool = false
@export var first_person_smoothing: float = 0.0
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
var _ts_guard: Node = null
## The realm expansion owns whether the player is inside a structure; the rig
## only reads it, so there is a single owner of the indoor state.
var _expansion: Node = null
var _indoor := false

func _ready() -> void:
	# Hit-stop recovery is wall-clock driven. This node must continue polling
	# while gameplay is slowed, otherwise a heavy kill/spell impact can leave
	# the whole game running at the temporary Engine.time_scale indefinitely.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ts_guard = get_tree().root.get_node_or_null("/root/TimeScaleGuard")
	# Find hero
	target = get_parent().get_node_or_null("Hero")
	if not target:
		push_error("CameraRig: No Hero found!")
	_expansion = get_parent().get_node_or_null("RealmExpansion")
	
	# Initialize spring arm
	spring_arm.spring_length = distance
	spring_arm.margin = 0.5
	
	# Third person is the new default. Existing top-down callers remain valid
	# through set_camera_mode(), while the persisted player choice uses the
	# explicit first/third-person interface.
	view_mode = _load_view_mode()
	feedback_mode = _load_feedback_mode()
	set_view_mode(view_mode, true, false)
	
	# Snap to default framing on first frame
	rotation.y = target_angle_h
	rotation.x = target_angle_v
	
	camera.fov = fov
	camera_base_position = camera.position
	InputManager.set_active_camera(camera, self)
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
		var cancel_pressed := InputMap.has_action("ui_cancel") \
			and Input.is_action_just_pressed("ui_cancel")
		var attack_pressed := InputMap.has_action("attack") \
			and Input.is_action_just_pressed("attack")
		if cancel_pressed or attack_pressed:
			cancel_cinematic()
			return
		_update_cinematic(delta)
		_apply_shake(delta)
		return
	
	_update_camera_position(delta)
	_apply_shake(delta)

func _process(_delta: float) -> void:
	# Unlike physics, idle processing remains responsive while time_scale is
	# reduced. Keep this separate from movement/camera simulation so recovery
	# cannot depend on the slowed gameplay clock.
	_poll_hit_stop()

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
	if view_mode == VIEW_FIRST_PERSON:
		# Keep the near camera above the authoritative relief surface. This is a
		# presentation guard only; collision and hero movement remain unchanged.
		var terrain := get_tree().get_first_node_in_group("terrain_relief")
		if terrain != null and terrain.has_method("sample_surface_height"):
			var floor_y := float(terrain.call("sample_surface_height", global_position))
			global_position.y = maxf(global_position.y, floor_y + 0.65)
	
	_refresh_indoor_pitch()
	# Smooth lerp distance, pitch, and FOV toward mode targets
	var lerp_rate := mode_lerp_speed * delta
	distance = lerpf(distance, _target_distance, lerp_rate)
	target_angle_v = lerpf(target_angle_v, _target_angle_v, lerp_rate)
	if camera:
		camera.fov = lerpf(camera.fov, _target_fov, lerp_rate)
	
	# Apply rotation
	if view_mode == VIEW_FIRST_PERSON:
		# Free-look is input-owned: once the drag ends, the camera must stop
		# exactly where the player left it instead of continuing to ease or drift.
		rotation.y = target_angle_h
		rotation.x = target_angle_v
	else:
		var rotation_lerp := clampf(rotation_speed * delta, 0.0, 1.0)
		rotation.y = lerp_angle(rotation.y, target_angle_h, rotation_lerp)
		rotation.x = lerpf(rotation.x, target_angle_v, rotation_lerp)
	
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
	# Global hit-stop is disabled. Keeping this method as a no-op preserves the
	# feedback contract while guaranteeing skills cannot slow the simulation.
	_hit_stop_until_msec = 0

func _poll_hit_stop() -> void:
	if _hit_stop_until_msec == 0:
		return
	if Time.get_ticks_msec() >= _hit_stop_until_msec:
		_hit_stop_until_msec = 0
		if _ts_guard != null and _ts_guard.has_method("cancel"):
			_ts_guard.call("cancel", HITSTOP_LEASE)

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

## Short, skippable framing beat for arrivals, rewards, landmarks, and unlocks.
## The focus and anchor are world-space offsets so callers can keep the shot
## authored around a node without taking control away from the player.
func play_focus_moment(focus: Node3D, anchor_offset: Vector3 = Vector3(0.0, 4.5, 7.0),
		focus_offset: Vector3 = Vector3(0.0, 1.2, 0.0), duration: float = 1.8) -> void:
	if _cinematic or focus == null or not is_instance_valid(focus):
		return
	_cinematic = true
	_cine_t = 0.0
	_cine_dur = clampf(duration, 0.6, 4.0)
	_restore_distance = _target_distance
	_cine_focus = focus.global_position + focus_offset
	_cine_anchor = focus.global_position + anchor_offset
	set_distance(clampf(_target_distance * 0.72, _target_min_dist, _target_max_dist))

## Restore player control immediately. This is safe for both ordinary focus
## moments and kill-cams, including interruption before their timer expires.
func cancel_cinematic() -> void:
	if not _cinematic:
		return
	_cinematic = false
	_cine_t = 0.0
	if _ts_guard != null and _ts_guard.has_method("cancel"):
		_ts_guard.call("cancel", KILLCAM_LEASE)
	_target_distance = _restore_distance
	_apply_view_targets(view_mode)
	if camera:
		camera.position = camera_base_position

# === Kill-cam slow-mo ===
func play_kill_cam(focus: Node3D) -> void:
	if _cinematic or focus == null or not is_instance_valid(focus) \
			or OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]:
		return
	_cinematic = true
	_cine_t = 0.0
	_cine_dur = 2.2
	_restore_distance = _target_distance
	_cine_focus = focus.global_position + Vector3(0, 1.8, 0)
	_cine_anchor = focus.global_position + Vector3(0, 4.5, 6.5)
	set_distance(9.0)
	# Kill-cam slow-mo as a wall-clock lease: the watchdog guarantees the
	# world returns to full speed even if the rig is freed mid-camera.
	if _ts_guard != null and _ts_guard.has_method("slow_motion"):
		_ts_guard.call("slow_motion", KILLCAM_LEASE, 0.25, 0.9)

func _update_cinematic(delta: float) -> void:
	_cine_t += delta
	global_position = global_position.lerp(_cine_anchor, minf(delta * 3.0, 1.0))
	
	# Aim the rig at the cinematic focus
	var dir := (_cine_focus - global_position).normalized()
	target_angle_h = atan2(-dir.x, -dir.z)
	target_angle_v = clampf(asin(clampf(dir.y, -1.0, 1.0)), -1.35, -0.18)
	
	if _cine_t >= _cine_dur:
		cancel_cinematic()
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
	target_angle_h = wrapf(h, -PI, PI)
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
	_touch_pos.clear()
	_touch_prev.clear()
	InputManager.world_gesture_active = false
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
	if view_mode != VIEW_FIRST_PERSON:
		InputManager.end_first_person_look(-1)
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
		# Keep the authored hero visible across camera modes. Hiding the whole
		# visual tree made the player appear deleted on mobile and also removed
		# the first-person hand/weapon feedback.
		target_visual.visible = true

func _load_view_mode() -> String:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return VIEW_THIRD_PERSON
	var stored := str(config.get_value("gameplay", "camera_view", VIEW_THIRD_PERSON))
	return stored if stored in [VIEW_FIRST_PERSON, VIEW_THIRD_PERSON] else VIEW_THIRD_PERSON

func _load_feedback_mode() -> String:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return feedback_mode
	var stored := str(config.get_value("gameplay", "motion_feedback", feedback_mode))
	return stored if stored in ["full", "mobile", "reduced", "off"] else feedback_mode

func _save_view_mode() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value("gameplay", "camera_view", view_mode)
	config.save(settings_path)

# === Input: drag rotate, pinch zoom, wheel zoom ===
@export var rotate_sensitivity: float = 0.005
@export var pinch_zoom_scale: float = 0.035
@export var wheel_zoom_step: float = 2.0
@export var wheel_rotate_step: float = 0.22
## The right side of the playfield is reserved for camera orbit on mobile.
## The left side remains tap-to-move/joystick territory.
@export_range(0.0, 1.0, 0.01) var camera_drag_start_ratio: float = 0.35
@export var camera_drag_direction_bias: float = 1.15

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
		_apply_orbit_delta(event.relative)
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
		MOUSE_BUTTON_WHEEL_LEFT:
			if event.pressed:
				_apply_orbit_delta(Vector2(-wheel_rotate_step, 0.0))
		MOUSE_BUTTON_WHEEL_RIGHT:
			if event.pressed:
				_apply_orbit_delta(Vector2(wheel_rotate_step, 0.0))

## InputManager calls this before its normal tap-to-move drag path. This keeps
## the established left-side movement controls intact while making the
## camera-side horizontal swipe an unambiguous orbit gesture.
func wants_world_drag(start_position: Vector2, relative: Vector2) -> bool:
	if _cinematic or view_mode == VIEW_FIRST_PERSON or _touch_pos.size() >= 2:
		return false
	if relative.length_squared() < 16.0:
		return false
	if absf(relative.x) <= absf(relative.y) * camera_drag_direction_bias:
		return false
	var viewport_width := get_viewport().get_visible_rect().size.x
	if viewport_width <= 0.0:
		return false
	return start_position.x >= viewport_width * camera_drag_start_ratio

func consume_world_drag(start_position: Vector2, relative: Vector2) -> bool:
	if not wants_world_drag(start_position, relative):
		return false
	_apply_orbit_delta(relative)
	return true

func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if InputManager != null and InputManager.has_method("is_joystick_pointer_owned") \
			and InputManager.is_joystick_pointer_owned(event.index):
		return
	if event.pressed:
		if view_mode == VIEW_FIRST_PERSON and _touch_pos.is_empty():
			InputManager.begin_first_person_look(event.index)
		_touch_pos[event.index] = event.position
		_touch_prev[event.index] = event.position
	else:
		if view_mode == VIEW_FIRST_PERSON:
			InputManager.end_first_person_look(event.index)
		_touch_pos.erase(event.index)
		_touch_prev.erase(event.index)
	InputManager.world_gesture_active = _touch_pos.size() >= 2

func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if InputManager != null and InputManager.has_method("is_joystick_pointer_owned") \
			and InputManager.is_joystick_pointer_owned(event.index):
		return
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
	_apply_orbit_delta(event.relative * 0.5)
	if view_mode == VIEW_FIRST_PERSON:
		_target_angle_v = target_angle_v
	
	# Pinch zoom from the pair's distance delta
	var d_now := event.position.distance_to(_touch_pos[other_index])
	var d_prev: float = _touch_prev[event.index].distance_to(_touch_prev[other_index])
	set_distance(distance - (d_now - d_prev) * pinch_zoom_scale)
	
	_touch_pos[event.index] = event.position
	_touch_prev[event.index] = event.position
	_touch_prev[other_index] = _touch_pos[other_index]

func _apply_orbit_delta(relative: Vector2) -> void:
	var dh := -relative.x * rotate_sensitivity
	var next_pitch := _clamp_pitch(target_angle_v - relative.y * rotate_sensitivity)
	target_angle_h = wrapf(target_angle_h + dh, -PI, PI)
	target_angle_v = next_pitch

func _apply_first_person_look(relative: Vector2) -> void:
	target_angle_h = wrapf(target_angle_h
		- relative.x * first_person_look_sensitivity, -PI, PI)
	var pitch_delta := relative.y * first_person_look_sensitivity
	if first_person_invert_y:
		pitch_delta = -pitch_delta
	target_angle_v = _clamp_pitch(target_angle_v - pitch_delta)
	# Keep the first-person target aligned with the direct drag orientation.
	_target_angle_v = target_angle_v

func set_first_person_look_sensitivity(value: float) -> void:
	first_person_look_sensitivity = clampf(value, 0.001, 0.02)

func set_first_person_invert_y(enabled: bool) -> void:
	first_person_invert_y = enabled

func get_first_person_look_settings() -> Dictionary:
	return {"sensitivity": first_person_look_sensitivity,
		"invert_y": first_person_invert_y, "smoothing": first_person_smoothing}

## Pitch clamp for the current view: orbit modes use the whole [-1.35,-0.18]
## arc, while first person keeps the head near level so fights stay readable.
## Indoors the orbit band flattens so the camera cannot climb over the roofline.
func _clamp_pitch(v: float) -> float:
	if view_mode == VIEW_FIRST_PERSON:
		return clampf(v, first_person_pitch_min, first_person_pitch_max)
	if _indoor:
		return clampf(v, indoor_pitch_min, indoor_pitch_max)
	return clampf(v, -1.35, -0.18)

## Flattens the third-person pitch while the player is inside a structure so
## the camera looks along the room instead of down at floors and roof tops.
func _refresh_indoor_pitch() -> void:
	# The realm expansion is created at runtime, so it is resolved on first use
	# rather than cached in _ready.
	if _expansion == null or not is_instance_valid(_expansion):
		_expansion = get_parent().get_node_or_null("RealmExpansion")
	_indoor = _expansion != null and is_instance_valid(_expansion) \
		and bool(_expansion.get("in_dungeon"))
	if not _indoor or view_mode == VIEW_FIRST_PERSON:
		return
	_target_angle_v = clampf(_target_angle_v, indoor_pitch_min, indoor_pitch_max)
	target_angle_v = clampf(target_angle_v, indoor_pitch_min, indoor_pitch_max)

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
		_hit_stop_until_msec = 0
		if _ts_guard != null and _ts_guard.has_method("cancel"):
			_ts_guard.call("cancel", HITSTOP_LEASE)
