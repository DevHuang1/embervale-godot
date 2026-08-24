extends CharacterBody3D
class_name Hero

## === Lantern Bearer (Cinder Warden) ===
## Tap-to-move, auto-combat, skills (Cinder Lash / Mend Flame)
## Weighted movement, dodge roll, slope tilt, procedural animation.

signal position_changed(position: Vector3)
signal interact_pressed

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var world: WorldManager = get_parent()
@onready var visual: Node3D = $Visual
@onready var body: MeshInstance3D = $Visual/Body
@onready var lantern: Node3D = $Visual/ArmR/Lantern
@onready var lantern_light: OmniLight3D = $Visual/ArmR/Lantern/LanternLight
@onready var lantern_mesh: MeshInstance3D = $Visual/ArmR/Lantern/LanternMesh
@onready var lantern_particles: GPUParticles3D = $Visual/ArmR/Lantern/LanternParticles
@onready var animator: EntityAnimator = $Animator
@onready var hitbox: Area3D = $Hitbox
@onready var attack_area: Area3D = $AttackArea
@onready var collision_shape: CollisionShape3D = $CollisionShape

# Movement
@export var move_speed: float = 6.5
@export var turn_speed: float = 12.0
@export var accel_rate: float = 11.0
@export var decel_rate: float = 15.0

# Dodge roll
@export var dodge_duration: float = 0.30
@export var dodge_speed_mult: float = 2.5
@export var dodge_cooldown_time: float = 1.05
@export var dodge_iframes: float = 0.34

# Verticality
@export var jump_velocity: float = 7.2
@export var gravity: float = 22.0

const COYOTE_TIME := 0.12
const JUMP_BUFFER_MS := 180

var move_target: Vector3 = Vector3.ZERO
var has_move_target: bool = false
var desired_direction: Vector3 = Vector3.ZERO
var current_weapon: Dictionary = {}
var auto_strike_timer: float = 0.0
var swing_trail: GPUParticles3D = null
var _blade: MeshInstance3D = null
var _blade_mat: StandardMaterial3D = null
var _attack_holding := false
var _has_hand_weapon := false
# Instance id of the enemy we glide toward after pressing attack; -1 = none
var _attack_run_target := -1
var auto_strike_cooldown: float = 0.92
var approach_distance: float = 1.42
var hit_flash_timer: float = 0.0
var invulnerable_timer: float = 0.0
var stun_timer: float = 0.0

# Dodge state
var dodge_timer: float = 0.0
var dodge_cooldown: float = 0.0
var dodge_dir: Vector3 = Vector3.ZERO
var _chain_dodge := false

# Jump state
var _jump_buffered_until := 0
var _coyote_timer := 0.0
var _was_on_floor := true

# Skill input buffering per weapon slot (0.25s window)
const SKILL_BUFFER_MS := 250
## Hold the attack button this long on release for a heavy charged strike
const HEAVY_HOLD_MSEC := 380
var _attack_hold_msec := 0
var _skill_buffer_until := [0, 0, 0]

# Weapon visuals
var hand_socket_l: AttachmentSocket = null
var hand_socket_r: AttachmentSocket = null
var _base_body_shader := {}   # original entity shader params for armor restore
var _base_move_speed: float = 6.5

# Ground normal cache for slope-aware movement
var _ground_normal := Vector3.UP
var _has_ground_normal := false

# Gait ramp: sustained direction "strides out" (weight + grounding)
const GAIT_HOLD_TIME := 0.8
const GAIT_SPEED_MULT := 1.35
var _dir_hold := 0.0
var _gait_ramp := 0.0

# Turn-in-place weight lean
var _prev_yaw := 0.0
var _turn_roll := 0.0

# Hard landing
var _fall_speed_cached := 0.0

# Foot grounding raycast alternation (2 rays max every other physics frame)
var _ik_toggle := false

# Animation / fx
var target_position: Vector3 = Vector3.ZERO
var is_moving: bool = false
var input_active: bool = false
var lantern_audio_timer: float = 0.0
var lantern_is_active: bool = true
var movement_fx: GPUParticles3D = null
var ember_trail: GPUParticles3D = null
var weapon_socket: AttachmentSocket = null
var current_relic: RelicData = null
var _slope_pitch := 0.0
var _slope_roll := 0.0
var _prev_phase_sin := 0.0

func _ready() -> void:
	target_position = global_position
	
	# Setup collision
	collision_layer = 1 << 0  # Player layer
	collision_mask = 1 << 1 | 1 << 5  # Enemy + Environment
	
	# Hitbox for enemy attacks
	hitbox.area_entered.connect(_on_hitbox_entered)
	
	# Attack area for auto-strikes
	attack_area.area_entered.connect(_on_attack_area_entered)
	
	# Load equipped weapon
	_load_default_weapon()
	game_state.weapon_changed.connect(_on_weapon_changed)
	game_state.armor_changed.connect(_on_armor_changed)
	game_state.stats_changed.connect(_apply_stat_multipliers)
	game_state.cosmetics_changed.connect(_apply_cosmetics)
	_capture_body_shader_defaults()
	_movement_fx_setup()
	_build_hero_silhouette()
	_build_swing_trail()
	_build_blade()
	_apply_lantern_state()
	
	# Back socket: scanned rare+ gear and forged relics hang here
	weapon_socket = AttachmentSocket.new()
	weapon_socket.name = "BackSocket"
	weapon_socket.socket_id = "back"
	weapon_socket.position = Vector3(0, 0.95, -0.38)
	visual.add_child(weapon_socket)
	
	# Hand sockets: sword rides the left hand, staff the right
	hand_socket_l = AttachmentSocket.new()
	hand_socket_l.name = "HandSocketL"
	hand_socket_l.socket_id = "hand_l"
	hand_socket_l.position = Vector3(0, -0.5, 0.05)
	$Visual/ArmL.add_child(hand_socket_l)
	hand_socket_r = AttachmentSocket.new()
	hand_socket_r.name = "HandSocketR"
	hand_socket_r.socket_id = "hand_r"
	hand_socket_r.position = Vector3(0, -0.48, 0.1)
	$Visual/ArmR.add_child(hand_socket_r)
	_refresh_weapon_visual()
	_apply_armor_visual()
	
	# A forged relic overrides whatever hangs on the back.
	ScanManager.relic_forged.connect(_on_relic_forged)
	if ScanManager.last_relic != null:
		_on_relic_forged(ScanManager.last_relic)
	
	# Input
	InputManager.move_input.connect(_on_move_input)
	InputManager.attack_pressed.connect(_on_attack_pressed)
	InputManager.attack_released.connect(_on_attack_released)
	InputManager.skill_slot_pressed.connect(_on_skill_slot_pressed)
	InputManager.interact_pressed.connect(_on_interact_pressed)
	InputManager.dodge_pressed.connect(_on_dodge_pressed)
	InputManager.jump_pressed.connect(_on_jump_pressed)
	InputManager.tap_world.connect(_on_world_tap)

	# Combo finisher feedback (slash kits only; casts never combo)
	animator.attack_impact.connect(_on_attack_impact)
	animator.anim_event.connect(_on_anim_event)

	# Authored-model drop-in (silent no-op until assets/models/hero.glb ships)
	CharacterRigLoader.try_if_wire(self, "hero")
	# Mount the hand/back tools on the knight's own bones so the mace/sword/
	# staff ride his real fists (and sway on the walk) instead of floating on
	# the hidden ghost body's arms. No-op unless the rig is present.
	CharacterRigLoader.bind_sockets(self, {
		"hand_l": "Palm.L",
		"hand_r": "Palm.R",
		"back": "Hips",
	})
	if CharacterRigLoader.has_model("hero"):
		var pr := "none"
		var pl := "none"
		if hand_socket_r:
			pr = hand_socket_r.get_parent().name
		if hand_socket_l:
			pl = hand_socket_l.get_parent().name
		print("[hero] rig mounted=", get_node_or_null("Visual/AuthoredRig") != null,
			" | r hand sock->", pr, " | l hand sock->", pl)

func _physics_process(delta: float) -> void:
	_update_swing_trail()
	_handle_movement(delta)
	_update_timers(delta)
	_update_attack_approach(delta)
	_update_movement_audio(delta)
	_apply_lantern_state()
	_update_visuals(delta)
	
	# Foot grounding: 2 rays max, every other physics frame
	_ik_toggle = not _ik_toggle
	if _ik_toggle and dodge_timer <= 0.0:
		_update_foot_grounding()
	
	position_changed.emit(global_position)

func _camera_relative(dir2: Vector2) -> Vector3:
	var cam: Camera3D = InputManager.active_camera
	if not cam and world and world.camera_rig:
		cam = world.camera_rig.get_node_or_null("SpringArm/Camera3D")
	if not cam:
		return Vector3.ZERO
	var forward = -cam.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	var right = cam.global_transform.basis.x
	right.y = 0
	right = right.normalized()
	return (-forward * dir2.y + right * dir2.x).normalized()

func _slide_and_post() -> void:
	_fall_speed_cached = maxf(0.0, -velocity.y)
	move_and_slide()
	_post_move()

func _handle_movement(delta: float) -> void:
	if stun_timer > 0.0:
		stun_timer -= delta
		velocity = velocity.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
		velocity.y -= gravity * delta
		_dir_hold = 0.0
		_slide_and_post()
		animator.set_move_ratio(0.0)
		is_moving = false
		return
	
	var direction := Vector3.ZERO
	if has_move_target:
		var offset = target_position - global_position
		offset.y = 0.0
		if offset.length() > 0.12:
			direction = offset.normalized()
		else:
			has_move_target = false
			is_moving = false
			_check_auto_engage()
	elif input_active:
		direction = desired_direction
		is_moving = direction.length_squared() > 0.001
	else:
		is_moving = false
	
	# Verticality: gravity, coyote time and buffered jumps.
	# Runs before steering so a jump can cancel a dodge roll mid-way.
	if is_on_floor():
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer -= delta
		velocity.y -= gravity * delta
	var now_ms := Time.get_ticks_msec()
	if now_ms < _jump_buffered_until and _coyote_timer > 0.0:
		_jump_buffered_until = 0
		_coyote_timer = 0.0
		velocity.y = jump_velocity
		if dodge_timer > 0.0:  # hop cancels the roll
			dodge_timer = 0.0
			dodge_cooldown = minf(dodge_cooldown, 0.35)
			visual.rotation.x = _slope_pitch
		audio.play_footstep(1.2)
	
	# Dodge overrides steering (chain window near the end of a roll)
	if dodge_timer > 0.0:
		dodge_timer -= delta
		var falloff := lerpf(0.55, 1.0, dodge_timer / dodge_duration)
		velocity.x = dodge_dir.x * move_speed * dodge_speed_mult * falloff
		velocity.z = dodge_dir.z * move_speed * dodge_speed_mult * falloff
		# Reduced spin; the animator's limb tuck carries the readability
		visual.rotation.x -= (TAU / dodge_duration) * delta * 0.30
		if _chain_dodge and dodge_timer <= delta:
			_chain_dodge = false
			dodge_timer = 0.0
			_try_dodge(Vector2.ZERO)
			_slide_and_post()
			return
		_slide_and_post()
		animator.set_move_ratio(1.0)
		return
	
	var accelerating := direction.length_squared() > 0.001
	# Gait ramp: sustained direction strides out; stopping resets the hold
	if accelerating:
		_dir_hold = minf(_dir_hold + delta, GAIT_HOLD_TIME + 0.6)
	else:
		_dir_hold = 0.0
	var ramp_target := clampf((_dir_hold - GAIT_HOLD_TIME) / 0.35, 0.0, 1.0)
	_gait_ramp = lerpf(_gait_ramp, ramp_target, minf(delta * 5.0, 1.0))
	animator.set_gait_ramp(_gait_ramp)
	
	var target_velocity = direction * move_speed \
		* (1.0 + (GAIT_SPEED_MULT - 1.0) * _gait_ramp) \
		* _slope_speed_scale(direction)
	var rate := accel_rate if accelerating else decel_rate
	var t := 1.0 - exp(-rate * delta)
	velocity.x = lerpf(velocity.x, target_velocity.x, t)
	velocity.z = lerpf(velocity.z, target_velocity.z, t)
	
	if velocity.length_squared() > 0.04:
		var target_rot = atan2(velocity.x, velocity.z)
		var angle_diff = absf(wrapf(target_rot - rotation.y, -PI, PI))
		# Sharp direction changes pivot faster (turn-in-place weight)
		var turn_rate := turn_speed * (2.1 if angle_diff > 1.7 else 1.0)
		rotation.y = lerp_angle(rotation.y, target_rot, turn_rate * delta)
	_slide_and_post()

func _post_move() -> void:
	animator.set_air_target(not is_on_floor())
	if is_on_floor() and not _was_on_floor and velocity.y <= 0.0:
		_on_landed()
	_was_on_floor = is_on_floor()

func _on_landed() -> void:
	# Hard landings squash deeper and kick up more dust
	var hard := clampf((_fall_speed_cached - 6.0) / 7.0, 0.0, 1.0)
	animator.notify_land(hard)
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.08, 0),
		Color(0.42, 0.52, 0.34, 0.6), 8 + int(14.0 * hard), 2.4 + hard,
		0.32 + 0.12 * hard, 0.13 + 0.10 * hard)
	CombatFx.impact(self, 0.10 + 0.16 * hard, 0.0, 1.0, 0.0)
	audio.play_footstep(1.0 + hard * 0.6)

func is_airborne() -> bool:
	return not is_on_floor()

# === Slope-aware movement speed ===
func _slope_speed_scale(move_dir: Vector3) -> float:
	if not _has_ground_normal or move_dir.length_squared() < 0.01:
		return 1.0
	var n := _ground_normal
	var steep := clampf(1.0 - n.y, 0.0, 0.7)
	var n_h := Vector3(n.x, 0.0, n.z)
	if n_h.length_squared() < 0.0001:
		return 1.0
	# Uphill: moving against the horizontal component of the normal
	var grade := -n_h.normalized().dot(Vector3(move_dir.x, 0, move_dir.z).normalized())
	if grade > 0.0:
		# Climbing: slow with steepness and grade
		return lerpf(1.0, 0.55, clampf(steep * grade * 2.4, 0.0, 1.0))
	# Descending: slight speed gain
	return lerpf(1.0, 1.12, clampf(steep * -grade * 2.0, 0.0, 1.0))

# === Dodge roll ===
func _try_dodge(screen_dir: Vector2) -> void:
	if stun_timer > 0.0 or game_state.combat_state == GameState.CombatState.DEFEATED:
		return
	# Dodge-cancel: a roll mid-recovery snaps the swing shut immediately
	if animator.is_recovering():
		animator.cancel_recovery()
	# Chain window: queue a follow-up roll near the end of the current one
	if dodge_timer > 0.0:
		if dodge_timer < dodge_duration * 0.35:
			_chain_dodge = true
			dodge_cooldown = 0.0
		return
	if dodge_cooldown > 0.0:
		return
	if screen_dir.length_squared() > 0.01:
		dodge_dir = _camera_relative(screen_dir)
	elif is_moving or velocity.length_squared() > 1.0:
		dodge_dir = desired_direction if input_active else Vector3(velocity.x, 0, velocity.z).normalized()
	else:
		# Stationary: toward a nearby enemy if one threatens, else camera-forward
		var enemy := _nearest_enemy(9.0)
		if enemy:
			dodge_dir = (enemy.global_position - global_position)
			dodge_dir.y = 0.0
			dodge_dir = dodge_dir.normalized()
		else:
			dodge_dir = -global_transform.basis.z
			dodge_dir.y = 0.0
			dodge_dir = dodge_dir.normalized()
	dodge_dir.y = 0.0
	dodge_dir = dodge_dir.normalized()
	dodge_timer = dodge_duration
	dodge_cooldown = dodge_cooldown_time
	invulnerable_timer = maxf(invulnerable_timer, dodge_iframes)
	has_move_target = false
	audio.play_dash()
	CombatFx.impact(self, 0.12, 0.0, 1.0, 0.0)
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.15, 0),
		Color(0.42, 0.52, 0.34, 0.6), 14, 3.2, 0.4, 0.16)

func _nearest_enemy(max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is Node3D and is_instance_valid(enemy):
			var d: float = global_position.distance_to(enemy.global_position)
			if d < best_d:
				best_d = d
				best = enemy
	return best

func _on_dodge_pressed(screen_dir: Vector2) -> void:
	_try_dodge(screen_dir)

func _on_jump_pressed() -> void:
	_jump_buffered_until = Time.get_ticks_msec() + JUMP_BUFFER_MS

# === Crowd control (boss root prison) ===
func stun(seconds: float) -> void:
	stun_timer = maxf(stun_timer, seconds)
	has_move_target = false
	input_active = false
	is_moving = false

func _update_timers(delta: float) -> void:
	if hit_flash_timer > 0:
		hit_flash_timer -= delta
		var intensity = clampf(hit_flash_timer / 0.2, 0.0, 1.0)
		if body.material_override is ShaderMaterial:
			body.material_override.set_shader_parameter("flash_intensity", intensity)
	
	if invulnerable_timer > 0:
		invulnerable_timer -= delta
	
	if dodge_cooldown > 0:
		dodge_cooldown -= delta
		if dodge_cooldown < 0:
			dodge_cooldown = 0.0
	
	if auto_strike_timer > 0:
		auto_strike_timer -= delta
	
	# Buffered skill inputs fire as soon as their cooldown clears
	var now := Time.get_ticks_msec()
	for slot in 3:
		if now < _skill_buffer_until[slot]:
			if game_state.can_use_skill_slot(slot):
				_skill_buffer_until[slot] = 0
				_use_skill_slot(slot)
	
	# Recover visual roll after a dodge ends
	if dodge_timer <= 0.0:
		visual.rotation.x = lerpf(visual.rotation.x, _slope_pitch, minf(delta * 10.0, 1.0))

## Ember trail that streams off the striking hand while a swing plays —
## reads the animator state each physics frame, no per-swing wiring.
func _update_swing_trail() -> void:
	if swing_trail == null:
		return
	var attacking := animator != null and animator.anim_state == EntityAnimator.AnimState.ATTACK \
		and animator.attack_style != "magic"
	if swing_trail.emitting != attacking:
		swing_trail.emitting = attacking
	_update_blade(attacking)
	_update_cloak_sway()
	_update_charge_aura()

## Heavy-charge weave: while the attack button is held, the drawn blade
## drinks light — the aura ramps through the hold threshold, then fades
## back to its idle glow on release or when the strike is consumed.
func _update_charge_aura() -> void:
	if _blade_mat == null:
		return
	if _attack_holding and _blade != null and _blade.visible:
		var held := float(Time.get_ticks_msec() - _attack_hold_msec)
		var frac := clampf((held - HEAVY_HOLD_MSEC * 0.45) / float(HEAVY_HOLD_MSEC), 0.0, 1.0)
		_blade_mat.emission_energy_multiplier = lerpf(
			_blade_mat.emission_energy_multiplier, 0.4 + frac * 3.0, 0.12)
	else:
		_blade_mat.emission_energy_multiplier = lerpf(
			_blade_mat.emission_energy_multiplier, 0.4, 0.08)

## Animation event hooks: the animator emits these at the action's visual
## frame (not on a timer) so SFX/VFX land exactly with the strike.
func _on_anim_event(event_name: String) -> void:
	match event_name:
		"heavy_impact":
			audio.play_slash()
			if world and world.camera_rig:
				world.camera_rig.add_shake(0.28)
		"aura":
			audio.play_magic_cast()
		_:
			pass

## Drawn weapon in hand during swings; scabbarded (hidden) otherwise.
## Suppressed entirely while a real weapon model rides the fist.
func _update_blade(attacking: bool) -> void:
	if _blade == null:
		return
	var want := attacking and not _has_hand_weapon
	if _blade.visible != want:
		_blade.visible = want

var cloak_node: MeshInstance3D = null
var _cloak_sway := 0.0

## Cloak secondary motion: the mantle leans into motion and settles at rest.
func _update_cloak_sway() -> void:
	if cloak_node == null or animator == null:
		return
	var speed: float = clamp(velocity.length(), 0.0, 8.0)
	var target: float = clamp(speed * 0.06, -0.16, 0.16) + animator.phase_lean() * 0.5
	_cloak_sway = lerpf(_cloak_sway, target, minf(get_process_delta_time() * 6.0, 1.0))
	cloak_node.rotation.x = _cloak_sway

func _build_blade() -> void:
	if _blade != null:
		return
	var arm := visual.get_node_or_null("ArmR")
	if arm == null:
		return
	_blade = MeshInstance3D.new()
	_blade.name = "DrawnBlade"
	_blade.visible = false
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.07, 0.5, 0.02)
	_blade.mesh = blade_mesh
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.6, 0.63, 0.68)
	steel.metallic = 0.9
	steel.roughness = 0.25
	steel.emission_enabled = true
	steel.emission = Color(1.0, 0.72, 0.29)
	steel.emission_energy_multiplier = 0.4
	_blade_mat = steel
	_blade.material_override = steel
	# Off the forearm tip, blade projecting forward
	_blade.position = Vector3(0, -0.18, -0.34)
	arm.add_child(_blade)

func _build_swing_trail() -> void:
	swing_trail = GPUParticles3D.new()
	swing_trail.name = "SwingTrail"
	swing_trail.amount = 34
	swing_trail.lifetime = 0.28
	swing_trail.local_coords = false
	swing_trail.emitting = false
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.22
	proc.spread = 180.0
	proc.initial_velocity_min = 0.1
	proc.initial_velocity_max = 0.6
	proc.gravity = Vector3.ZERO
	proc.scale_min = 0.5
	proc.scale_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.82, 0.42, 0.9))
	ramp.set_color(1, Color(0.95, 0.4, 0.08, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	proc.color_ramp = ramp_tex
	swing_trail.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = CombatFx.radial_glow_texture()
	quad.material = mat
	swing_trail.draw_pass_1 = quad
	var hand := visual.get_node_or_null("ArmR")
	if hand:
		hand.add_child(swing_trail)
	else:
		visual.add_child(swing_trail)

func _build_hero_silhouette() -> void:
	var cloak := MeshInstance3D.new()
	cloak.name = "CloakMantle"
	var cloak_mesh := CylinderMesh.new()
	cloak_mesh.top_radius = 0.26
	cloak_mesh.bottom_radius = 0.50
	cloak_mesh.height = 0.78
	cloak_mesh.radial_segments = 8
	var cloak_material := StandardMaterial3D.new()
	cloak_material.albedo_color = Color(0.035, 0.12, 0.095, 1.0)
	cloak_material.roughness = 0.86
	cloak.mesh = cloak_mesh
	cloak.material_override = cloak_material
	cloak.position = Vector3(0, 0.52, 0)
	cloak_node = cloak
	visual.add_child(cloak)

	var hood := MeshInstance3D.new()
	hood.name = "Hood"
	var hood_mesh := CylinderMesh.new()
	hood_mesh.top_radius = 0.10
	hood_mesh.bottom_radius = 0.28
	hood_mesh.height = 0.30
	hood_mesh.radial_segments = 8
	var hood_material := StandardMaterial3D.new()
	hood_material.albedo_color = Color(0.045, 0.15, 0.12, 1.0)
	hood_material.roughness = 0.80
	hood.mesh = hood_mesh
	hood.material_override = hood_material
	hood.position = Vector3(0, 1.62, 0)
	visual.add_child(hood)

	var gem := MeshInstance3D.new()
	gem.name = "CinderChestGem"
	var gem_mesh := SphereMesh.new()
	gem_mesh.radius = 0.095
	gem_mesh.height = 0.19
	var gem_material := StandardMaterial3D.new()
	gem_material.albedo_color = Color(1.0, 0.48, 0.12, 1.0)
	gem_material.emission_enabled = true
	gem_material.emission = Color(1.0, 0.22, 0.04, 1.0)
	gem_material.emission_energy_multiplier = 1.8
	gem.mesh = gem_mesh
	gem.material_override = gem_material
	gem.position = Vector3(0, 1.02, 0.36)
	visual.add_child(gem)

	_build_hero_gear()
	_build_skeletal_finish()

## Skeletal finish: neck column + elbow/hand/knee joint spheres parented
## onto the rig nodes so the animator still carries them. They reuse the
## body material_override so armor re-theming covers them too.
func _build_skeletal_finish() -> void:
	if body == null or visual == null:
		return
	var skin := body.material_override

	# Neck — tapered column seating the head into the shoulder mass
	var neck := MeshInstance3D.new()
	neck.name = "Neck"
	var n_mesh := CylinderMesh.new()
	n_mesh.top_radius = 0.075
	n_mesh.bottom_radius = 0.115
	n_mesh.height = 0.2
	n_mesh.radial_segments = 8
	n_mesh.rings = 1
	neck.mesh = n_mesh
	neck.material_override = skin
	neck.position = Vector3(0, 1.26, 0)
	visual.add_child(neck)

	# Elbow rounding + hand spheres at the end of each forearm
	var joint := SphereMesh.new()
	joint.radius = 0.09
	joint.height = 0.18
	joint.radial_segments = 8
	joint.rings = 3
	for arm_path in ["ArmL", "ArmR"]:
		var arm := visual.get_node_or_null(arm_path)
		if arm == null:
			continue
		var elbow := MeshInstance3D.new()
		elbow.name = "ElbowCap"
		elbow.mesh = joint
		elbow.material_override = skin
		elbow.position = Vector3(0, -0.5, 0)
		arm.add_child(elbow)
		var fore := arm.get_node_or_null("Forearm")
		if fore:
			var hand := MeshInstance3D.new()
			hand.name = "HandFist"
			hand.mesh = joint
			hand.material_override = skin
			hand.scale = Vector3.ONE * 0.9
			hand.position = Vector3(0, -0.36, 0.02)
			fore.add_child(hand)

	# Knees on the single-bone legs (mid-stride around world y 0.27)
	var knee := SphereMesh.new()
	knee.radius = 0.12
	knee.height = 0.24
	knee.radial_segments = 8
	knee.rings = 3
	for leg_path in ["LegL", "LegR"]:
		var leg := visual.get_node_or_null(leg_path)
		if leg == null:
			continue
		var cap := MeshInstance3D.new()
		cap.name = "KneeCap"
		cap.mesh = knee
		cap.material_override = skin
		cap.position = Vector3(0, -0.26, 0)
		leg.add_child(cap)
func _build_hero_gear() -> void:
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.23, 0.15, 0.09)
	leather.roughness = 0.85
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.42, 0.44, 0.47)
	iron.metallic = 0.8
	iron.roughness = 0.38
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.55, 0.40, 0.18)
	bronze.metallic = 0.7
	bronze.roughness = 0.45
	bronze.emission_enabled = true
	bronze.emission = Color(1.0, 0.45, 0.10)
	bronze.emission_energy_multiplier = 0.35

	var arm_l := visual.get_node_or_null("ArmL")
	var arm_r := visual.get_node_or_null("ArmR")
	var leg_l := visual.get_node_or_null("LegL")
	var leg_r := visual.get_node_or_null("LegR")

	for side in [-1.0, 1.0]:
		# Pauldrons
		if side > 0 or arm_l != null:
			var pd := MeshInstance3D.new()
			var pdm := SphereMesh.new()
			pdm.radius = 0.14
			pdm.height = 0.2
			pd.mesh = pdm
			pd.material_override = iron
			pd.position = Vector3(0.26 * side, 1.28, 0)
			pd.scale = Vector3(1.0, 0.72, 1.15)
			visual.add_child(pd)
		# Bracers on forearms when present
		var forearm := visual.get_node_or_null(
			("ArmL/Forearm" if side < 0 else "ArmR/Forearm"))
		if forearm:
			var br := MeshInstance3D.new()
			var brm := CylinderMesh.new()
			brm.top_radius = 0.062
			brm.bottom_radius = 0.075
			brm.height = 0.22
			br.mesh = brm
			br.material_override = leather
			forearm.add_child(br)

	# Belt + hanging skirt plates
	var belt := MeshInstance3D.new()
	var belt_mesh := TorusMesh.new()
	belt_mesh.inner_radius = 0.21
	belt_mesh.outer_radius = 0.28
	belt.mesh = belt_mesh
	belt.material_override = leather
	belt.position = Vector3(0, 0.78, 0)
	visual.add_child(belt)
	for i in 5:
		var plate := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.11, 0.24, 0.03)
		plate.mesh = pm
		plate.material_override = bronze if i == 2 else iron
		var ang := PI * (0.35 + 0.075 * float(i))
		plate.position = Vector3(cos(ang) * 0.25, 0.62, sin(ang) * 0.25)
		plate.rotation.y = -ang + PI * 0.5
		visual.add_child(plate)

	# Boot cuffs
	for leg in [leg_l, leg_r]:
		if leg:
			var cuff := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.085
			cm.bottom_radius = 0.095
			cm.height = 0.16
			cuff.mesh = cm
			cuff.material_override = leather
			cuff.position = Vector3(0, -0.32, 0)
			leg.add_child(cuff)

	# Sword in shoulder scabbard (diagonal across the back)
	var scabbard := MeshInstance3D.new()
	var sc_mesh := CylinderMesh.new()
	sc_mesh.top_radius = 0.045
	sc_mesh.bottom_radius = 0.02
	sc_mesh.height = 0.95
	scabbard.mesh = sc_mesh
	scabbard.material_override = leather
	scabbard.rotation = Vector3(0.35, 0, 0.6)
	scabbard.position = Vector3(-0.12, 0.95, -0.24)
	visual.add_child(scabbard)
	var hilt := MeshInstance3D.new()
	var hilt_mesh := CylinderMesh.new()
	hilt_mesh.top_radius = 0.05
	hilt_mesh.bottom_radius = 0.05
	hilt_mesh.height = 0.16
	hilt.mesh = hilt_mesh
	hilt.material_override = bronze
	hilt.rotation = scabbard.rotation
	hilt.position = scabbard.position + Vector3(0.30, 0.17, 0.06)
	visual.add_child(hilt)

func _apply_lantern_state() -> void:
	var active := world != null and world.lantern_active
	if active and world.day_night != null:
		active = not world.day_night.is_daylight()
	lantern_is_active = active
	lantern_light.visible = active
	lantern_mesh.visible = active
	lantern_particles.emitting = active

func _movement_fx_setup() -> void:
	movement_fx = GPUParticles3D.new()
	movement_fx.name = "MovementDust"
	movement_fx.amount = 10
	movement_fx.lifetime = 0.4
	movement_fx.one_shot = true
	movement_fx.explosiveness = 1.0
	movement_fx.local_coords = false
	movement_fx.emitting = false
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.UP
	proc.spread = 38.0
	proc.initial_velocity_min = 0.5
	proc.initial_velocity_max = 1.4
	proc.gravity = Vector3(0, -2.2, 0)
	proc.scale_min = 0.5
	proc.scale_max = 1.3
	proc.color = Color(0.36, 0.46, 0.28, 0.65)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.36, 0.46, 0.28, 0.7))
	ramp.set_color(1, Color(0.36, 0.46, 0.28, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	proc.color_ramp = ramp_tex
	movement_fx.process_material = proc
	var puff := QuadMesh.new()
	puff.size = Vector2(0.18, 0.18)
	var puff_material := StandardMaterial3D.new()
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.vertex_color_use_as_albedo = true
	puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff_material.albedo_texture = CombatFx.radial_glow_texture()
	puff.material = puff_material
	movement_fx.draw_pass_1 = puff
	add_child(movement_fx)
	
	# Lantern ember trail while sprinting through the grove
	ember_trail = GPUParticles3D.new()
	ember_trail.name = "EmberTrail"
	ember_trail.amount = 26
	ember_trail.lifetime = 0.7
	ember_trail.local_coords = false
	ember_trail.emitting = false
	var trail_proc := ParticleProcessMaterial.new()
	trail_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	trail_proc.emission_sphere_radius = 0.08
	trail_proc.direction = Vector3.ZERO
	trail_proc.spread = 180.0
	trail_proc.initial_velocity_min = 0.05
	trail_proc.initial_velocity_max = 0.25
	trail_proc.gravity = Vector3(0, 0.6, 0)
	trail_proc.scale_min = 0.35
	trail_proc.scale_max = 0.8
	var trail_ramp := Gradient.new()
	trail_ramp.set_color(0, Color(1.0, 0.78, 0.32, 0.85))
	trail_ramp.set_color(1, Color(0.96, 0.45, 0.12, 0.0))
	var trail_ramp_tex := GradientTexture1D.new()
	trail_ramp_tex.gradient = trail_ramp
	trail_proc.color_ramp = trail_ramp_tex
	ember_trail.process_material = trail_proc
	var trail_quad := QuadMesh.new()
	trail_quad.size = Vector2(0.06, 0.06)
	var trail_mat := StandardMaterial3D.new()
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.vertex_color_use_as_albedo = true
	trail_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	trail_mat.albedo_texture = CombatFx.radial_glow_texture()
	trail_quad.material = trail_mat
	ember_trail.draw_pass_1 = trail_quad
	lantern.add_child(ember_trail)

	# Lantern sparks are scene sub-resource quads; soften them too
	var lantern_fx := get_node_or_null("Visual/ArmR/Lantern/LanternParticles") as GPUParticles3D
	if lantern_fx and lantern_fx.draw_pass_1 is QuadMesh:
		var spark_mesh := lantern_fx.draw_pass_1 as QuadMesh
		if spark_mesh.material is StandardMaterial3D:
			var spark_mat: StandardMaterial3D = spark_mesh.material.duplicate()
			spark_mat.albedo_texture = CombatFx.radial_glow_texture()
			spark_mesh.material = spark_mat

func _update_movement_audio(delta: float) -> void:
	var speed_ratio = clampf(velocity.length() / max(move_speed, 0.01), 0.0, 1.0)
	# Footsteps fire when the walk cycle's feet plant (phase crosses zero),
	# not on an arbitrary timer — dust and sound land with the stride
	if speed_ratio > 0.18 and is_on_floor():
		var s := sin(animator.phase)
		if (_prev_phase_sin < 0.0 and s >= 0.0) or (_prev_phase_sin > 0.0 and s <= 0.0):
			if movement_fx:
				movement_fx.global_position = global_position + Vector3(0, 0.04, 0)
				movement_fx.restart()
				movement_fx.emitting = true
			# Foliage-aware surface: the active realm sets the underfoot sound
			var surface := "grass"
			match Bestiary.realm_id_for_stage(game_state.current_stage):
				Bestiary.REALM_MISTFEN:
					surface = "mud"
				Bestiary.REALM_HEARTWOOD:
					surface = "stone"
			audio.play_footstep_surface(surface, speed_ratio)
		_prev_phase_sin = s
	else:
		_prev_phase_sin = 0.0
	
	if lantern_is_active:
		lantern_audio_timer -= delta
		if lantern_audio_timer <= 0.0:
			lantern_audio_timer = 2.8
			# Swinging lantern creaks; a settled one just hums
			if animator.pendulum_speed() > 1.3:
				audio.play_lantern_creak()
			else:
				audio.play_lantern_hum(speed_ratio)
	else:
		lantern_audio_timer = 0.0

func _flash_body(color: Color) -> void:
	if body.material_override is ShaderMaterial:
		body.material_override.set_shader_parameter("flash_color", color)
		body.material_override.set_shader_parameter("flash_intensity", 1.0)

## Attack-driven approach: the hero only travels toward a target the player
## just pressed attack on, then lands a SINGLE strike when the gap closes.
## No passive auto-combat loop anymore — every swing needs intent.
func _update_attack_approach(_delta: float) -> void:
	if _attack_run_target == -1:
		return
	var enemy := _enemy_by_id(_attack_run_target)
	if enemy == null or not is_instance_valid(enemy) \
			or (enemy.has_method("is_dead") and enemy.is_dead()):
		_attack_run_target = -1
		game_state.disengage_enemy()
		return
	if is_moving and global_position.distance_to(enemy.global_position) <= approach_distance:
		_attack_run_target = -1
		if game_state.can_auto_strike() and auto_strike_timer <= 0.0:
			_perform_auto_strike(enemy)

func _enemy_by_id(id: int) -> Node3D:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node3D and is_instance_valid(e) and e.get_instance_id() == id:
			return e
	return null

## Lock onto a target for a press-driven approach; one strike on arrival.
func _begin_attack_target(enemy: Node3D) -> void:
	game_state.engage_enemy(enemy)
	_attack_run_target = enemy.get_instance_id()
	target_position = enemy.global_position
	has_move_target = true
	input_active = false
	desired_direction = Vector3.ZERO
	is_moving = true

func _perform_auto_strike(enemy: Node3D) -> void:
	var strike_data = game_state.perform_auto_strike()
	if strike_data.is_empty():
		return
	
	auto_strike_timer = auto_strike_cooldown / game_state.attack_speed_mult()
	animator.attack_style = weapon_style()
	animator.trigger_attack()
	# Commit forward — the strike visibly lunges into the target even the
	# instant a press lands, so the swing reads without any glide-in wait.
	if enemy != null and is_instance_valid(enemy):
		var lunge := global_position.direction_to(enemy.global_position)
		lunge.y = 0.0
		velocity += lunge.normalized() * 3.4
	hit_flash_timer = 0.1
	_flash_body(Color(1, 0.84, 0.47))
	
	# Wind-up FX by weapon style, then damage lands on the impact frame
	var magic := weapon_style() == "magic"
	if magic:
		audio.play_magic_cast()
		var cast_origin := hand_socket_r.global_position if hand_socket_r \
			else lantern.global_position
		CombatFx.spawn_burst(self, cast_origin,
			Color(0.62, 0.55, 0.96, 0.7), 8, 2.2, 0.26, 0.11)
		# Ranged basic attack: a glowing bolt flies to the target so the
		# damage lands when the orb arrives, not before it leaves the staff.
		if enemy != null and is_instance_valid(enemy):
			_fire_magic_bolt(cast_origin,
				enemy.global_position + Vector3(0, 0.85, 0))
	else:
		audio.play_swing_stage(animator.combo_step)
		_cosmetic_cue("cast")
		# Pre-impact shimmer at the drive hand sells the incoming hit
		CombatFx.spawn_telegraph(self,
			hand_socket_r.global_position if hand_socket_r else lantern.global_position,
			Color(1.0, 0.84, 0.47))
		CombatFx.spawn_burst(self, lantern.global_position,
			Color(1, 0.84, 0.47, 0.55), 6, 2.5, 0.22, 0.09)
	await get_tree().create_timer(0.14 if magic else 0.10).timeout
	if not is_instance_valid(enemy) or enemy.is_dead():
		return
	
	# Impact director: shake + chroma coordinated (bloom hits read heavier)
	if strike_data.is_bloom:
		CombatFx.impact(self, 0.16, 0.05, 0.22, 0.45)
	else:
		CombatFx.impact(self, 0.09, 0.0, 1.0, 0.18)
	
	var hit_pos: Vector3 = enemy.global_position + Vector3(0, 0.85, 0)
	if magic:
		# Magic basic attack: a small detonation blooms on the target
		audio.play_explosion()
		CombatFx.spawn_explosion(self, enemy.global_position,
			Color(0.62, 0.55, 0.96), 1.9)
		CombatFx.spawn_burst(self, hit_pos,
			Color(0.72, 0.62, 1.0, 0.85), 12, 5.5, 0.32)
	else:
		audio.play_slash()
		CombatFx.spawn_slash(self, hit_pos)
		# Blade trail ribbon, colour-matched to the weapon element
		var trail_color := game_state.trail_color() if weapon_style() != "slash" \
			else game_state.trail_color().lightened(0.18)
		CombatFx.spawn_arc_trail(self, hit_pos, trail_color)
		CombatFx.spawn_arc_trail(self, hit_pos + Vector3(0, 0.14, 0), trail_color)
		CombatFx.spawn_stretched_burst(self, hit_pos,
			Color(1, 0.84, 0.47), 12, 6.5, 0.3)
	
	# Crit zones (e.g. Matriarch crown) + lucky crits from LUK both amplify
	var crit_mult := _crit_multiplier_at(enemy)
	if randf() < game_state.crit_chance():
		crit_mult *= game_state.crit_damage()
	var damage: int = strike_data.damage
	if crit_mult > 1.0:
		damage = int(round(damage * crit_mult))
		FloatingText.spawn_on_entity(enemy, "%d!" % damage, Color(1, 0.55, 0.25))
	
	# Apply damage
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, global_position.direction_to(enemy.global_position))
		if crit_mult <= 1.0:
			FloatingText.spawn_on_entity(enemy, str(damage), Color(1, 0.92, 0.72))
	
	# Log
	print(strike_data.log)
	
	# Check for kill
	if enemy.has_method("is_dead") and enemy.is_dead():
		CombatFx.impact(self, 0.28, 0.07, 0.15, 0.7)
		_on_enemy_killed(enemy)
		return
	
	# Enemy retaliation (on non-killing strikes)
	if game_state.combat_state == GameState.CombatState.COMBAT:
		var retal = game_state.apply_enemy_retaliation()
		take_damage(retal.damage, enemy.global_position.direction_to(global_position))
		print(retal.log)

func _crit_multiplier_at(enemy: Node3D) -> float:
	if enemy and enemy.has_method("get_crit_multiplier_at"):
		return maxf(1.0, enemy.call("get_crit_multiplier_at", global_position))
	return 1.0

## Staff basic-attack projectile: a glowing ember bolt that streaks to the
## marked target in ~0.18s (matching the damage window), trailing sparks.
func _fire_magic_bolt(from_pos: Vector3, to_pos: Vector3) -> void:
	var orb := MeshInstance3D.new()
	orb.name = "MagicBolt"
	var sphere := SphereMesh.new()
	sphere.radius = 0.11
	sphere.height = 0.22
	sphere.radial_segments = 10
	sphere.rings = 5
	orb.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.62, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.62, 0.55, 0.96)
	mat.emission_energy_multiplier = 2.8
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(orb)
	orb.global_position = from_pos
	var flight := create_tween()
	flight.tween_property(orb, "global_position", to_pos, 0.18) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	flight.tween_callback(func():
		if is_instance_valid(orb):
			CombatFx.spawn_burst(self, orb.global_position,
				Color(0.72, 0.62, 1.0, 0.8), 6, 2.4, 0.2, 0.1)
			orb.queue_free())

## Finisher feedback: the third chained slash lands with a shockwave ring,
## heavier coordinated impact and a committed physical lunge.
func _on_attack_impact() -> void:
	if weapon_style() == "magic" or animator.combo_step != 2:
		return
	CombatFx.spawn_ring(self, global_position, 2.2, Color(1.0, 0.78, 0.32, 0.8), 0.6)
	CombatFx.impact(self, 0.26, 0.10, 0.10, 0.55)
	velocity += -global_transform.basis.z * 2.2

func _check_auto_engage() -> void:
	# Check if we arrived at an enemy while in combat state
	if game_state.combat_state == GameState.CombatState.COMBAT and game_state.enemy_target:
		var enemy = game_state.enemy_target
		if is_instance_valid(enemy):
			var dist = global_position.distance_to(enemy.global_position)
			if dist <= approach_distance:
				# Already in range, will auto-strike next frame
				pass

func _on_enemy_killed(enemy: Node3D) -> void:
	game_state.disengage_enemy()
	game_state.grant_xp(GameState.FIRST_KILL_XP if game_state.level == 1 else GameState.SUBSEQUENT_KILL_XP)
	
	# A kill lifts the gloom: clear any low-warmth vignette so the world
	# brightens back instead of staying dark after the fight.
	get_tree().call_group("screen_fx", "comfort")
	
	# Gold spills from the fallen — the trader's currency
	var reward := 40 if enemy.is_in_group("boss") else 12
	game_state.add_gold(reward)
	FloatingText.spawn_on_entity(enemy, "+%d 🪙" % reward, Color(1.0, 0.84, 0.35))
	
	# Loot drops
	if game_state.level == 1:
		game_state.add_loot("hushling_thorn", 1)
		game_state.add_loot("moss_tonic", 1, "Hushling cache secured — Thorn and Moss Tonic added.", 2)
	else:
		if randf() < 0.35:
			game_state.add_loot("moss_tonic", 1, "A Moss Tonic rolls free of the bramble.")
	
	audio.play_victory()

func weapon_style() -> String:
	return str(game_state.equipped_weapon.get("style", "slash"))

func _update_foot_grounding() -> void:
	if animator == null or animator.foot_l == null or animator.foot_r == null:
		return
	var space_state := get_world_3d().direct_space_state
	var results := [Vector2.ZERO, Vector2.ZERO]  # per foot: (dy, pitch)
	var feet := [animator.foot_l, animator.foot_r]
	for i in 2:
		var query := PhysicsRayQueryParameters3D.create(
			global_position + global_transform.basis \
				* Vector3(-0.17 if i == 0 else 0.17, 1.0, 0.03),
			global_position + global_transform.basis \
				* Vector3(-0.17 if i == 0 else 0.17, -1.8, 0.03))
		query.collision_mask = 1 << 5  # Environment
		query.exclude = [get_rid()]
		var hit := space_state.intersect_ray(query)
		if hit and hit.has("position"):
			# Sole offset above the contact point
			var dy: float = (hit.position.y + 0.10) - feet[i].global_position.y
			var n: Vector3 = hit.normal
			var n_local := global_transform.basis.inverse() * n
			results[i] = Vector2(
				clampf(dy, -0.28, 0.28),
				clampf(atan2(n_local.z, maxf(n_local.y, 0.05)), -0.5, 0.5))
	animator.set_foot_ground(results[0].x, results[1].x,
		results[0].y, results[1].y)

func _update_visuals(delta: float) -> void:
	# Animator drives limb cycle, bob and pendulum
	var speed_ratio = clampf(velocity.length() / max(move_speed, 0.01), 0.0, 1.0)
	animator.set_move_ratio(speed_ratio)
	
	# Dodge roll feeds the animator's limb tuck (1 at launch -> 0 at end)
	animator.set_dodge_ratio(
		clampf(dodge_timer / dodge_duration, 0.0, 1.0) if dodge_timer > 0.0 else 0.0)
	
	_apply_slope_tilt(delta)
	_apply_turn_lean(delta)
	
	# Lantern light pulse, slightly brighter while moving
	lantern_light.light_energy = 1.8 + speed_ratio * 0.18 + sin(animator.phase * 1.7) * 0.15
	
	# Ember trail streams behind fast movement; striding out lowers the bar
	if ember_trail:
		ember_trail.emitting = speed_ratio > (0.55 - 0.15 * _gait_ramp)

func _apply_turn_lean(delta: float) -> void:
	# Turn-in-place weight: lean into the turn proportional to yaw rate
	var yaw_rate := wrapf(rotation.y - _prev_yaw, -PI, PI) / maxf(delta, 0.0001)
	_prev_yaw = rotation.y
	if dodge_timer <= 0.0:
		_turn_roll = lerpf(_turn_roll,
			clampf(-yaw_rate * 0.045, -0.12, 0.12), minf(delta * 8.0, 1.0))
	else:
		_turn_roll = lerpf(_turn_roll, 0.0, minf(delta * 8.0, 1.0))

func _apply_slope_tilt(delta: float) -> void:
	# Raycast down for ground normal; tilt the rig to match the terrain
	# and feed slope-aware movement speed
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.8, 0),
		global_position + Vector3(0, -1.5, 0))
	query.collision_mask = 1 << 5  # Environment
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	var target_pitch := 0.0
	var target_roll := 0.0
	if result and result.has("normal"):
		_ground_normal = result.normal
		_has_ground_normal = true
		var n: Vector3 = _ground_normal
		if n.y > 0.05:
			var local_n := visual.global_transform.basis.inverse() * n
			target_pitch = clampf(local_n.z * 0.9, -0.20, 0.20)
			target_roll = clampf(-local_n.x * 0.9, -0.20, 0.20)
	else:
		_has_ground_normal = false
	_slope_pitch = lerpf(_slope_pitch, target_pitch, minf(delta * 7.0, 1.0))
	_slope_roll = lerpf(_slope_roll, target_roll, minf(delta * 7.0, 1.0))
	if dodge_timer <= 0.0 and animator.anim_state != EntityAnimator.AnimState.HIT:
		visual.rotation.x = _slope_pitch
		# Turn lean sums with the slope tilt, never overwrites it
		visual.rotation.z = _slope_roll + _turn_roll

# === Input Handlers ===
func _on_move_input(direction: Vector2) -> void:
	if direction.length() > 0.1:
		var world_dir := _camera_relative(direction)
		if world_dir == Vector3.ZERO:
			return
		desired_direction = world_dir
		input_active = true
		has_move_target = false
		is_moving = true
	else:
		desired_direction = Vector3.ZERO
		input_active = false
		if not has_move_target:
			is_moving = false

func _on_world_tap(world_pos: Vector3, camera: Camera3D) -> void:
	target_position = world_pos
	has_move_target = true
	input_active = false
	desired_direction = Vector3.ZERO
	is_moving = true
	_attack_run_target = -1
	game_state.disengage_enemy()  # Moving cancels combat lock

func _on_attack_pressed() -> void:
	_attack_holding = true
	_attack_hold_msec = Time.get_ticks_msec()
	# Press = strike: immediate hit when a target is locked in range and
	# the swing cooldown is ready.
	if game_state.can_auto_strike():
		var enemy: Node3D = game_state.enemy_target
		if enemy != null and is_instance_valid(enemy) \
				and global_position.distance_to(enemy.global_position) <= approach_distance \
				and auto_strike_timer <= 0.0:
			_perform_auto_strike(enemy)
			return

	# Otherwise mark what the lantern faces (or the nearest foe) and glide
	# in - a single strike fires when the approach closes the gap.
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1, 0),
		global_position + Vector3(0, 1, 0) - global_transform.basis.z * 3.0
	)
	query.collision_mask = 1 << 1  # Enemy layer
	var result = space_state.intersect_ray(query)

	if result and result.collider and result.collider.is_in_group("enemy"):
		_begin_attack_target(result.collider)
		return
	var nearest := _nearest_enemy(14.0)
	if nearest:
		_begin_attack_target(nearest)
	else:
		FloatingText.spawn_on_entity(self, "No mark in your light",
			Color(1.0, 0.84, 0.47))

## Hold-to-charge: releasing after a long press lands a heavy overhead
## strike (2.2x, wide arc, dust + shockwave). Taps stay light combo hits.
func _on_attack_released() -> void:
	_attack_holding = false
	var held := Time.get_ticks_msec() - _attack_hold_msec
	if held < HEAVY_HOLD_MSEC:
		return
	if animator.is_recovering():
		animator.cancel_recovery()
	if not game_state.can_auto_strike() or auto_strike_timer > 0.0:
		return
	var enemy: Node3D = game_state.enemy_target
	if enemy == null or not is_instance_valid(enemy):
		return
	if global_position.distance_to(enemy.global_position) > approach_distance * 1.6:
		return
	auto_strike_timer = 1.35
	animator.attack_style = weapon_style()
	animator.trigger_attack("heavy")
	await get_tree().create_timer(0.44).timeout
	if not is_instance_valid(enemy) or (enemy.has_method("is_dead") and enemy.is_dead()):
		return
	audio.play_slash()
	audio.play_explosion()
	var hit_pos: Vector3 = enemy.global_position + Vector3(0, 0.85, 0)
	CombatFx.spawn_slash(self, hit_pos, Color(1.0, 0.55, 0.18, 0.95))
	CombatFx.spawn_ring(self, global_position + Vector3(0, 0.1, 0), 2.6,
		Color(1, 0.7, 0.3, 0.6), 0.5)
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.25, -0.8),
		Color(0.4, 0.32, 0.2, 0.7), 16, 3.5, 0.4, 0.18)
	_deal_skill_damage(enemy, 2.2)
	if world and world.camera_rig:
		world.camera_rig.add_shake(0.45)
	CombatFx.impact(self, 0.34, 0.07, 0.09, 0.8)

# === Weapon skill kits (slot 0..2 of the equipped weapon) ===
func _on_skill_slot_pressed(slot: int) -> void:
	# Targeted rites mark their own foe: if nothing is engaged yet, snap
	# onto the nearest enemy so Q/E/R always cast when something is close.
	var sk := game_state.get_skill(slot)
	if not sk.is_empty() and str(sk.get("type", "")) != "heal_bloom":
		var locked: Node3D = game_state.enemy_target
		if locked == null or not is_instance_valid(locked):
			var near := _nearest_enemy(14.0)
			if near != null:
				game_state.engage_enemy(near)
	_use_skill_slot(slot)

func _use_skill_slot(slot: int) -> void:
	var result := game_state.use_skill(slot)
	if result.success:
		_execute_skill(slot, result.skill)
		return
	# Surface WHY the rite refused: cooldowns buffer a retry, missing
	# marks just tell the player plainly (no silent console spam).
	var msg := str(result.get("message", ""))
	if msg.to_lower().contains("target") or msg.to_lower().contains("mark"):
		FloatingText.spawn_on_entity(self, msg, Color(1.0, 0.84, 0.47))
	else:
		_skill_buffer_until[slot] = Time.get_ticks_msec() + SKILL_BUFFER_MS
		if msg != "":
			FloatingText.spawn_on_entity(self, msg, Color(0.9, 0.9, 0.9))

## Cast preface shared by every rite: announce the skill name, flare the
## casting hand, telegraph the target, and play the cast voice — so a
## press always reads before the payload lands, even on rigs whose only
## combat clips are swings (the knight falls back to a cast stance).
func _begin_skill_cast(sk: Dictionary, target: Node3D) -> void:
	var kind := str(sk.get("type", ""))
	# Melee swings get no styled preface; ranged/area magic does.
	if kind in ["strike", "dash_strike", "whirl"]:
		animator.attack_style = weapon_style()
		return
	animator.attack_style = "magic"
	var name_str := str(sk.get("name", "RITE"))
	if target != null and is_instance_valid(target) and kind != "heal_bloom":
		FloatingText.spawn_on_entity(target, "✦ %s" % name_str, Color(1, 0.9, 0.72))
	else:
		FloatingText.spawn_on_entity(self, "✦ %s" % name_str, Color(1, 0.9, 0.72))
	var hand_pos := hand_socket_r.global_position if hand_socket_r else lantern.global_position
	CombatFx.spawn_telegraph(self, hand_pos, Color(1, 0.9, 0.72))
	CombatFx.spawn_burst(self, hand_pos, Color(1, 0.86, 0.5, 0.7), 10, 3.2, 0.3, 0.1)
	if target != null and is_instance_valid(target) and kind != "heal_bloom":
		CombatFx.spawn_ring(self, target.global_position, 1.8,
			Color(0.96, 0.86, 0.6, 0.8), 0.4)
	audio.play_fx(["magic1", "spell"], -12.0)

func _execute_skill(slot: int, sk: Dictionary) -> void:
	var enemy = game_state.enemy_target
	_begin_skill_cast(sk, enemy)
	match str(sk.get("type", "")):
		"strike":
			animator.attack_style = weapon_style()
			animator.trigger_attack()
			await get_tree().create_timer(0.16).timeout
			if enemy == null or not is_instance_valid(enemy):
				return
			audio.play_slash()
			var hit_pos: Vector3 = enemy.global_position + Vector3(0, 0.85, 0)
			CombatFx.spawn_slash(self, hit_pos, Color(1.0, 0.72, 0.29, 0.95))
			CombatFx.spawn_slash(self, hit_pos + Vector3(0, 0.25, 0))
			_deal_skill_damage(enemy, float(sk.get("dmg_mult", 1.5)))
			CombatFx.impact(self, 0.24, 0.05, 0.12, 0.6)
		"whirl":
			animator.attack_style = weapon_style()
			animator.trigger_attack()
			var radius := float(sk.get("radius", 3.5))
			await get_tree().create_timer(0.12).timeout
			audio.play_slash()
			for i in 4:
				CombatFx.spawn_slash(self,
					global_position + Vector3(cos(TAU * i / 4.0) * radius * 0.55,
						0.8, sin(TAU * i / 4.0) * radius * 0.55))
			CombatFx.spawn_ring(self, global_position, radius * 0.8,
				Color(1.0, 0.78, 0.35, 0.7), 0.7)
			for foe in get_tree().get_nodes_in_group("enemy"):
				if foe is Node3D and is_instance_valid(foe) \
						and global_position.distance_to(foe.global_position) <= radius:
					if foe.has_method("is_dead") and foe.is_dead():
						continue
					_deal_skill_damage(foe, float(sk.get("dmg_mult", 1.5)), true)
			CombatFx.impact(self, 0.22, 0.05, 0.12, 0.5)
		"dash_strike":
			# A real dash — iframe the lunge, rain after-image sparks, strike
			# at the moment of arrival. Cast stance (not the walk-swing clip).
			animator.attack_style = "magic"
			animator.trigger_attack()
			if enemy and is_instance_valid(enemy):
				invulnerable_timer = maxf(invulnerable_timer, 0.4)
				var dir := global_position.direction_to(enemy.global_position)
				dir.y = 0.0
				velocity += dir.normalized() * 15.0
				CombatFx.spawn_stretched_burst(self,
					global_position + Vector3(0, 0.4, 0),
					Color(1, 0.84, 0.47, 0.8), 12, 8.0, 0.35)
			await get_tree().create_timer(0.16).timeout
			if enemy == null or not is_instance_valid(enemy):
				return
			audio.play_slash()
			CombatFx.spawn_slash(self, enemy.global_position + Vector3(0, 0.85, 0))
			CombatFx.spawn_stretched_burst(self,
				enemy.global_position + Vector3(0, 0.85, 0),
				Color(1, 0.84, 0.47, 0.9), 16, 9.0, 0.32)
			_deal_skill_damage(enemy, float(sk.get("dmg_mult", 1.8)))
			CombatFx.impact(self, 0.26, 0.06, 0.10, 0.6)
		"explosion":
			animator.attack_style = "magic"
			animator.trigger_attack()
			await get_tree().create_timer(0.30).timeout
			if enemy == null or not is_instance_valid(enemy):
				return
			audio.play_explosion()
			var color := Color(0.96, 0.62, 0.22)
			CombatFx.spawn_explosion(self, enemy.global_position, color,
				float(sk.get("radius", 3.0)))
			CombatFx.spawn_decal(self, enemy.global_position, 1.3)
			_deal_skill_damage(enemy, float(sk.get("dmg_mult", 1.9)))
			CombatFx.impact(self, 0.26, 0.06, 0.10, 0.65)
		"comet":
			animator.attack_style = "magic"
			animator.trigger_attack()
			if world and world.camera_rig:
				world.camera_rig.punch_fov(4.0)
			# Long charge, then a wide delayed detonation on the target's spot
			var ground_pos: Vector3 = enemy.global_position if enemy and is_instance_valid(enemy) else global_position
			CombatFx.spawn_ring(self, ground_pos, 2.0,
				Color(0.62, 0.55, 0.96, 0.9), 0.5)
			await get_tree().create_timer(0.55).timeout
			audio.play_explosion()
			CombatFx.spawn_explosion(self, ground_pos, Color(0.72, 0.60, 1.0),
				float(sk.get("radius", 4.0)))
			CombatFx.spawn_burst(self, ground_pos + Vector3(0, 1.2, 0),
				Color(0.85, 0.75, 1.0, 0.9), 30, 8.0, 0.5, 0.2)
			CombatFx.impact(self, 0.34, 0.07, 0.08, 0.85)
			for foe in get_tree().get_nodes_in_group("enemy"):
				if foe is Node3D and is_instance_valid(foe) \
						and ground_pos.distance_to(foe.global_position) <= float(sk.get("radius", 4.0)):
					if foe.has_method("is_dead") and foe.is_dead():
						continue
					_deal_skill_damage(foe, float(sk.get("dmg_mult", 2.8)), true)
		"heal_bloom":
			animator.attack_style = "magic"
			animator.trigger_attack("buff")
			await get_tree().create_timer(0.55).timeout
			audio.play_heal()
			var restored: int = game_state.heal(int(sk.get("heal", 14)))
			FloatingText.spawn_on_entity(self, "+%d" % restored,
				Color(0.62, 0.85, 0.45))
			CombatFx.spawn_burst(self, global_position + Vector3(0, 1.0, 0),
				Color(0.56, 0.67, 0.33, 0.85), 26, 3.2, 0.8, 0.15)
			CombatFx.spawn_ring(self, global_position, 1.6,
				Color(0.62, 0.85, 0.45, 0.7), 0.9)
			CombatFx.spawn_ring(self, global_position + Vector3(0, 1.4, 0), 1.1,
				Color(0.75, 0.95, 0.55, 0.5), 0.7)
		"aoe":
			# Legacy kit slot (Mug Slam): heavy area slam around the hero.
			# Cast stance keeps the pose planted while the impact FX carry it.
			animator.attack_style = "magic"
			animator.trigger_attack()
			await get_tree().create_timer(0.44).timeout
			audio.play_explosion()
			CombatFx.spawn_burst(self, global_position + Vector3(0, 0.4, 0),
				Color(1, 0.84, 0.47, 0.8), 22, 6.0, 0.45, 0.16)
			for foe in get_tree().get_nodes_in_group("enemy"):
				if foe is Node3D and is_instance_valid(foe) \
						and global_position.distance_to(foe.global_position) <= float(sk.get("radius", 13.0)) * 0.35:
					if foe.has_method("is_dead") and foe.is_dead():
						continue
					_deal_skill_damage(foe, float(sk.get("dmg_mult", 1.5)), true)
			CombatFx.impact(self, 0.24, 0.06, 0.10, 0.55)
		_:
			pass

## Shared skill damage: scales off base auto damage, no retaliation provoked.
func _deal_skill_damage(enemy: Node3D, dmg_mult: float, silent_text: bool = false) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var damage := int(round(game_state.get_base_auto_damage() * dmg_mult))
	var crit := _crit_multiplier_at(enemy)
	if crit > 1.0:
		damage = int(round(damage * crit))
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, global_position.direction_to(enemy.global_position))
		if not silent_text or crit > 1.0:
			FloatingText.spawn_on_entity(enemy,
				"%d!" % damage if crit > 1.0 else str(damage),
				Color(1, 0.55, 0.25) if crit > 1.0 else Color(1, 0.92, 0.72))
	if enemy.has_method("is_dead") and enemy.is_dead():
		CombatFx.impact(self, 0.28, 0.08, 0.12, 0.7)
		_on_enemy_killed(enemy)

func _on_interact_pressed() -> void:
	interact_pressed.emit()

func _on_hitbox_entered(area: Area3D) -> void:
	if area.is_in_group("enemy_attack"):
		if invulnerable_timer <= 0:
			var dmg = 3  # Bramble Skitter
			take_damage(dmg, area.global_position.direction_to(global_position))

func _on_attack_area_entered(area: Area3D) -> void:
	# Auto-strike hit detection handled in _update_auto_combat
	pass

## True only while the hero is actually mid-swing/cast: enemies gate their
## contact-hit behind this so walking past never damages — only a committed
## press (or skill) can.
func get_attack_window() -> bool:
	if animator == null:
		return false
	return animator.anim_state == EntityAnimator.AnimState.ATTACK

func take_damage(amount: int, knockback_dir: Vector3) -> bool:
	if invulnerable_timer > 0:
		return false
	
	var died = game_state.take_damage(amount)
	FloatingText.spawn_on_entity(self, str(amount), Color(1, 0.42, 0.32))
	
	# Visual
	hit_flash_timer = 0.2
	invulnerable_timer = 0.5
	_flash_body(Color(1, 0.3, 0.2))
	animator.trigger_hit()
	
	# Knockback
	velocity += knockback_dir * 8.0
	
	# Camera shake
	if world and world.camera_rig:
		world.camera_rig.add_shake(0.35)
	audio.play_hurt()
	
	if died:
		world._on_player_defeated()
	
	return true

func get_body_velocity() -> Vector3:
	return velocity

func _on_weapon_changed(weapon: Dictionary) -> void:
	current_weapon = weapon.duplicate(true)
	_refresh_weapon_visual()

func _refresh_weapon_visual() -> void:
	if weapon_socket == null:
		return
	
	# A wielded relic-kit item carries its scanned mesh in-hand instead.
	var relic_wielded: bool = bool(current_weapon.get("relic", false)) \
		and current_relic != null and current_relic.mesh != null
	if relic_wielded:
		weapon_socket.detach()
	elif current_relic != null and current_relic.mesh != null:
		# A photo-forged relic takes priority over the rarity staff.
		var holder := Node3D.new()
		holder.name = "RelicVisual"
		var mi := MeshInstance3D.new()
		mi.mesh = current_relic.mesh
		holder.add_child(mi)
		holder.rotation_degrees = Vector3(6.0, 180.0, -8.0)
		holder.scale = Vector3.ONE * 0.55
		weapon_socket.attach_node(holder)
	else:
		var rarity := int(current_weapon.get("rarity", 0))
		if rarity < 3:
			weapon_socket.detach()
			return
		# Ember-tipped staff slung across the back for rare+ finds
		var staff := MeshInstance3D.new()
		staff.name = "WeaponVisual"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.028
		cyl.bottom_radius = 0.042
		cyl.height = 1.45
		cyl.radial_segments = 7
		staff.mesh = cyl
		staff.rotation.z = -0.5
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.16, 0.12, 0.08)
		wood.roughness = 0.85
		staff.material_override = wood
		
		var gem := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.07
		sphere.height = 0.14
		gem.mesh = sphere
		gem.position = Vector3(0, 0.78, 0)
		var gem_mat := StandardMaterial3D.new()
		gem_mat.albedo_color = Color(1, 0.72, 0.29)
		gem_mat.emission_enabled = true
		gem_mat.emission = Color(1, 0.72, 0.29)
		gem_mat.emission_energy_multiplier = 2.2
		gem.material_override = gem_mat
		staff.add_child(gem)
		
		weapon_socket.attach_node(staff)
	
	_refresh_hand_weapon()

## The equipped shop weapons read in-hand: sword in the left fist,
## staff in the right (it leads every cast). Relic-kit items wield the
## scanned mesh itself.
func _refresh_hand_weapon() -> void:
	if hand_socket_l == null or hand_socket_r == null:
		return
	# Strike reach follows the weapon: swords short and quick, maces
	# medium, staves long (their bolt closes the last gap).
	approach_distance = _weapon_reach()
	match str(current_weapon.get("id", "")):
		"mug_mace":
			hand_socket_l.detach()
			hand_socket_r.attach_node(_build_mug_mace_visual())
			_has_hand_weapon = true
		"ember_sword":
			hand_socket_r.detach()
			hand_socket_l.attach_node(_build_sword_visual())
			_has_hand_weapon = true
		"arcane_staff":
			hand_socket_l.detach()
			hand_socket_r.attach_node(_build_staff_visual())
			_has_hand_weapon = true
		_:
			hand_socket_l.detach()
			hand_socket_r.detach()
			_has_hand_weapon = bool(current_weapon.get("relic", false)) \
				and current_relic != null and current_relic.mesh != null
			if _has_hand_weapon:
				hand_socket_r.attach_node(_build_relic_hand_visual())

## Weapon-derived strike reach (also drives glide distance and FX scale):
## slash = short and fast, blunt = medium, magic staves reach farthest.
func _weapon_reach() -> float:
	var style := weapon_style()
	var wr := float(current_weapon.get("range", 8.0))
	match style:
		"magic":
			return clampf(wr * 0.24, 2.0, 2.7)
		"slash":
			return clampf(wr * 0.18, 1.35, 1.7)
		_:
			return clampf(wr * 0.22, 1.55, 2.05)

## The starter Mug Mace as a real held prop: ale-wet wooden haft wrapped
## in leather, a dented steel head and a bottom-heavy pommel counterweight.
func _build_mug_mace_visual() -> Node3D:
	var rig := Node3D.new()
	rig.name = "MugMaceVisual"
	rig.rotation_degrees = Vector3(-84, 0, 0)

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.30, 0.20, 0.11)
	wood.roughness = 0.85
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.19, 0.13, 0.08)
	leather.roughness = 0.95
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.58, 0.61, 0.66)
	steel.metallic = 0.85
	steel.roughness = 0.35

	var haft := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.032
	hm.bottom_radius = 0.042
	hm.height = 0.78
	hm.radial_segments = 7
	haft.mesh = hm
	haft.material_override = wood
	haft.position = Vector3(0, 0.28, 0)
	rig.add_child(haft)

	# Leather wrap around the grip
	for i in 3:
		var wrap := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.046
		wm.bottom_radius = 0.046
		wm.height = 0.045
		wm.radial_segments = 7
		wrap.mesh = wm
		wrap.material_override = leather
		wrap.position = Vector3(0, -0.02 + i * 0.09, 0)
		rig.add_child(wrap)

	# Dented steel head: main blade box + lighter edge strip + back spike
	var head := MeshInstance3D.new()
	var hd := BoxMesh.new()
	hd.size = Vector3(0.34, 0.17, 0.07)
	head.mesh = hd
	head.material_override = steel
	head.position = Vector3(0, 0.70, 0)
	rig.add_child(head)
	var edge := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.36, 0.05, 0.085)
	edge.mesh = em
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.78, 0.81, 0.86)
	edge_mat.metallic = 0.9
	edge_mat.roughness = 0.2
	edge.material_override = edge_mat
	edge.position = Vector3(0, 0.63, 0)
	rig.add_child(edge)
	var spike := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.0
	sm.bottom_radius = 0.045
	sm.height = 0.16
	sm.radial_segments = 4
	spike.mesh = sm
	spike.material_override = steel
	spike.position = Vector3(-0.22, 0.70, 0)
	spike.rotation.z = PI / 2.0
	rig.add_child(spike)

	# Pommel counterweight keeps the swing arc feeling weighty
	var pommel := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.055
	pm.height = 0.11
	pommel.mesh = pm
	pommel.material_override = steel
	pommel.position = Vector3(0, -0.12, 0)
	rig.add_child(pommel)
	return rig

func _build_relic_hand_visual() -> Node3D:
	var rig := Node3D.new()
	rig.name = "RelicHandVisual"
	var mi := MeshInstance3D.new()
	mi.mesh = current_relic.mesh
	rig.add_child(mi)
	# Tip the flat extrusion forward out of the fist like a blade
	rig.rotation_degrees = Vector3(-90, 0, -10)
	rig.scale = Vector3.ONE * 0.5
	return rig

func _build_sword_visual() -> Node3D:
	var rig := Node3D.new()
	rig.name = "SwordVisual"
	# Blade extends forward from the fist
	rig.rotation_degrees = Vector3(-84, 0, 0)
	
	var blade := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.075, 0.66, 0.02)
	blade.mesh = box
	blade.position = Vector3(0, 0.44, 0)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.66, 0.72)
	steel.metallic = 0.75
	steel.roughness = 0.32
	blade.material_override = steel
	rig.add_child(blade)
	
	var tip := MeshInstance3D.new()
	var tip_cone := CylinderMesh.new()
	tip_cone.top_radius = 0.0
	tip_cone.bottom_radius = 0.052
	tip_cone.height = 0.14
	tip_cone.radial_segments = 4
	tip.mesh = tip_cone
	tip.position = Vector3(0, 0.83, 0)
	tip.rotation.y = PI / 4.0
	tip.material_override = steel
	rig.add_child(tip)
	
	var guard := MeshInstance3D.new()
	var guard_box := BoxMesh.new()
	guard_box.size = Vector3(0.20, 0.035, 0.06)
	guard.mesh = guard_box
	guard.position = Vector3(0, 0.10, 0)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.55, 0.24)
	brass.metallic = 0.8
	brass.roughness = 0.42
	guard.material_override = brass
	rig.add_child(guard)
	
	var grip := MeshInstance3D.new()
	var grip_cyl := CylinderMesh.new()
	grip_cyl.top_radius = 0.022
	grip_cyl.bottom_radius = 0.026
	grip_cyl.height = 0.2
	grip_cyl.radial_segments = 6
	grip.mesh = grip_cyl
	grip.material_override = brass
	rig.add_child(grip)
	
	# Ember edge glows faintly along the fuller
	var ember := MeshInstance3D.new()
	var ember_box := BoxMesh.new()
	ember_box.size = Vector3(0.02, 0.58, 0.024)
	ember.mesh = ember_box
	ember.position = Vector3(0, 0.44, 0)
	var ember_mat := StandardMaterial3D.new()
	ember_mat.albedo_color = Color(1, 0.45, 0.15)
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1, 0.45, 0.15)
	ember_mat.emission_energy_multiplier = 1.4
	ember.material_override = ember_mat
	rig.add_child(ember)
	return rig

func _build_staff_visual() -> Node3D:
	var rig := Node3D.new()
	rig.name = "StaffVisual"
	rig.rotation_degrees = Vector3(-12, 0, -8)
	
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.026
	cyl.bottom_radius = 0.036
	cyl.height = 1.25
	cyl.radial_segments = 7
	shaft.mesh = cyl
	shaft.position = Vector3(0, 0.28, 0)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.19, 0.13, 0.22)
	wood.roughness = 0.85
	shaft.material_override = wood
	rig.add_child(shaft)
	
	var gem := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	gem.mesh = sphere
	gem.position = Vector3(0, 0.96, 0)
	var gem_mat := StandardMaterial3D.new()
	gem_mat.albedo_color = Color(0.62, 0.55, 0.96)
	gem_mat.emission_enabled = true
	gem_mat.emission = Color(0.62, 0.55, 0.96)
	gem_mat.emission_energy_multiplier = 2.0
	gem.material_override = gem_mat
	rig.add_child(gem)
	return rig

# === Armor visuals & stats ===
func _capture_body_shader_defaults() -> void:
	_base_move_speed = move_speed
	if body and body.material_override is ShaderMaterial:
		var mat: ShaderMaterial = body.material_override
		for key in ["base_color", "roughness", "metallic"]:
			_base_body_shader[key] = mat.get_shader_parameter(key)

func _on_armor_changed(_armor: Dictionary) -> void:
	_apply_armor_visual()

func _apply_armor_visual() -> void:
	# Speed: cloak lightens the stride
	move_speed = _base_move_speed * game_state.armor_speed_mult() \
		* game_state.move_speed_mult()
	_apply_cosmetics()
	if body == null or not (body.material_override is ShaderMaterial):
		return
	var mat: ShaderMaterial = body.material_override
	var armor: Dictionary = game_state.equipped_armor
	if armor.is_empty():
		mat.set_shader_parameter("base_color",
			_base_body_shader.get("base_color", Color(0.086, 0.23, 0.165)))
		mat.set_shader_parameter("roughness",
			_base_body_shader.get("roughness", 0.66))
		mat.set_shader_parameter("metallic",
			_base_body_shader.get("metallic", 0.0))
		return
	# Restyle the whole kit to the armor's palette
	var tint: Color = armor.get("tint", Color(0.2, 0.2, 0.2))
	mat.set_shader_parameter("base_color", tint)
	mat.set_shader_parameter("roughness",
		float(armor.get("roughness", 0.66)))
	mat.set_shader_parameter("metallic",
		float(armor.get("metallic", 0.0)))

func _on_relic_forged(relic: RelicData) -> void:
	current_relic = relic
	_refresh_weapon_visual()

func _load_default_weapon() -> void:
	current_weapon = game_state.equipped_weapon.duplicate(true)

## === Diamond cosmetics (visual only) ===
func _apply_cosmetics() -> void:
	if body != null and body.material_override is ShaderMaterial:
		var mat: ShaderMaterial = body.material_override
		var aura := Color(game_state.active_aura_color)
		mat.set_shader_parameter("emission_color", aura if aura.a > 0.05 			else Color(0.55, 0.36, 0.09))
		mat.set_shader_parameter("emission_energy", 0.85 if aura.a > 0.05 else 0.18)

## Cosmetic combat voice: layers the owned SFX profile over vanilla cues.
func _cosmetic_cue(kind: String) -> void:
	if game_state.active_sfx_profile != "vanilla":
		audio.play_profile_cue(game_state.active_sfx_profile, kind)


## DEX move-speed and future stat hooks re-derive on allocation.
func _apply_stat_multipliers() -> void:
	_apply_armor_visual()
