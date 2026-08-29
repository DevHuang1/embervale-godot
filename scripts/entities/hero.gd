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
@onready var visual: Node3D = $Visual/Rig
@onready var body: MeshInstance3D = $Visual/Rig/Body
@onready var lantern: Node3D = $Visual/Rig/ArmR/Lantern
@onready var lantern_light: OmniLight3D = $Visual/Rig/ArmR/Lantern/LanternLight
@onready var lantern_mesh: MeshInstance3D = $Visual/Rig/ArmR/Lantern/LanternMesh
@onready var lantern_particles: GPUParticles3D = $Visual/Rig/ArmR/Lantern/LanternParticles
@onready var animator: EntityAnimator = $Animator
@onready var hitbox: Area3D = $Hitbox
@onready var attack_area: Area3D = $AttackArea
@onready var collision_shape: CollisionShape3D = $CollisionShape

# Movement
## Visual-only shrink applied to the Rig wrapper — never collision, ranges
## or camera. Characters read smaller; bosses keep their authored size.
@export var visual_scale: float = 0.78
@export var move_speed: float = 3.4
@export var turn_speed: float = 12.0
@export var accel_rate: float = 11.0
@export var decel_rate: float = 15.0

# Dodge roll
@export var dodge_duration: float = 0.36
@export var dodge_speed_mult: float = 1.9
@export var dodge_cooldown_time: float = 1.20
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
# Drive-hand tracking so the held weapon can be swung visibly on strikes,
# independent of whether the authored rig animates its bones.
var _drive_socket: AttachmentSocket = null
var _drive_swing: Node3D = null
var _swing_base_rot := Vector3.ZERO
var _swing_tween: Tween = null
# Instance id of the enemy we glide toward after pressing attack; -1 = none
var _attack_run_target := -1
var auto_strike_cooldown: float = 1.15
var approach_distance: float = 1.42
var hit_flash_timer: float = 0.0
var invulnerable_timer: float = 0.0
var stun_timer: float = 0.0

# Dodge state
var dodge_timer: float = 0.0
var dodge_cooldown: float = 0.0
var dodge_dir: Vector3 = Vector3.ZERO
var _chain_dodge := false

# Perfect-dodge reward: grazing a telegraphed enemy strike mid-dodge grants a
# brief slow-mo breath and a window where the next auto-strike lands boosted.
var counter_window_timer: float = 0.0
const PERFECT_DODGE_COUNTER_WINDOW := 1.7
const PERFECT_DODGE_SLOWMO_SCALE := 0.35
const PERFECT_DODGE_SLOWMO_REALTIME := 0.14
const COUNTER_STRIKE_MULT := 1.5

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

## Grip calibration (world units) applied along the palm bone's axes after
## the authored rig mounts: X across the knuckles, Y down the wrist, Z out
## of the palm. Tune per-rig so weapon handles sit inside the fist.
@export var grip_offset_l: Vector3 = Vector3(0.0, 0.06, 0.03)
@export var grip_offset_r: Vector3 = Vector3(0.0, 0.06, 0.03)
var _base_body_shader := {}   # original entity shader params for armor restore
var _aura_base_energy: float = 0.18   # cosmetics baseline; magic pulses it
var _base_move_speed: float = 5.0

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
var _armor_gear_root: Node3D = null
var _cloak_base_mat: Material = null
var _slope_pitch := 0.0
var _slope_roll := 0.0
var _prev_phase_sin := 0.0
var _anim_impact_serial := 0
# Lantern lock-on flare (0..1), driven by GameState.mark_locked so the
# per-frame light pulse below never fights the spike.
var lantern_flare := 0.0
var _flare_tween: Tween = null
# One-off clarity tip: the flame is cosmetic (burns only after dusk), so the
# player learns once that combat comes from marking a foe, not the lantern.
var _lantern_tip_shown := false
var _lantern_was_lit := false

func _ready() -> void:
	target_position = global_position
	
	# Setup collision
	collision_layer = 1 << 0  # Player layer
	collision_mask = 1 << 1 | 1 << 5 | 1 << 6  # Enemy + Environment + Prop
	# Snap to the ground on slopes so climbing reads smooth, not bouncy
	floor_snap_length = 0.5
	
	# Hitbox for enemy attacks
	hitbox.area_entered.connect(_on_hitbox_entered)

	# Attack area for auto-strikes
	attack_area.area_entered.connect(_on_attack_area_entered)

	# Proportion shrink: the whole figure scales, capsule/collision do not.
	visual.scale = Vector3.ONE * visual_scale

	# Load equipped weapon
	_load_default_weapon()
	# World-visible lantern mark: keeps GameState.enemy_target legible.
	TargetMarker.ensure(self)
	TargetMarker.bind_lantern(lantern)
	GameState.mark_locked.connect(_on_mark_locked)
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
	$Visual/Rig/ArmL.add_child(hand_socket_l)
	hand_socket_r = AttachmentSocket.new()
	hand_socket_r.name = "HandSocketR"
	hand_socket_r.socket_id = "hand_r"
	hand_socket_r.position = Vector3(0, -0.48, 0.1)
	$Visual/Rig/ArmR.add_child(hand_socket_r)
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
	InputManager.tap_foe.connect(_on_foe_tap)

	# Combo finisher feedback (slash kits only; casts never combo)
	animator.attack_impact.connect(_on_attack_impact)
	animator.attack_impact.connect(_on_animator_impact)
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
	# The pose-preserving reparent leaves the ghost-rig offsets baked into
	# the socket, which reads as the weapon floating OUT of the fist on the
	# authored rig (unit-scaled x100 armature: local offsets don't map 1:1).
	# Snap each hand socket onto its palm-bone origin, then apply a small
	# world-unit grip offset along the bone's orthonormalized axes so the
	# handle sits inside the fingers. Bone animation still carries the socket.
	_snap_hand_socket(hand_socket_l, grip_offset_l)
	_snap_hand_socket(hand_socket_r, grip_offset_r)
	# The rig mounted after the initial armor pass, so re-apply body tint to
	# the authored silhouette (armor gear survives the mount via keep-prefix).
	_apply_armor_visual()
	if CharacterRigLoader.has_model("hero"):
		var pr := "none"
		var pl := "none"
		if hand_socket_r:
			pr = hand_socket_r.get_parent().name
		if hand_socket_l:
			pl = hand_socket_l.get_parent().name
		print("[hero] rig mounted=", get_node_or_null("Visual/Rig/AuthoredRig") != null,
			" | r hand sock->", pr, " | l hand sock->", pl)

func _physics_process(delta: float) -> void:
	_update_swing_trail()
	_handle_movement(delta)
	_update_timers(delta)
	_update_attack_approach(delta)
	# Safety net: never stay hard-locked onto a foe that died/freed mid-cast.
	# If combat state still references a dead/invalid target, drop the lock so
	# the player can immediately mark a fresh one (and no skill ever touches a
	# freed instance because nothing lingers on it).
	if game_state.combat_state == GameState.CombatState.COMBAT:
		var target := game_state.enemy_target
		if target == null or not is_instance_valid(target) \
				or (target.has_method("is_dead") and target.is_dead()):
			game_state.disengage_enemy()
			_attack_run_target = -1
			has_move_target = false
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
	# Hard impacts bounce physical pebbles off the ground
	if hard > 0.25:
		ImpactDirector.spawn_impact_debris(self,
			global_position + Vector3(0, 0.1, 0), "rock",
			1 + int(2.0 * hard))

## Destructible props shatter under strikes and skill slams.
func _damage_props_near(pos: Vector3, radius: float = 2.2) -> void:
	for prop in get_tree().get_nodes_in_group("destructible"):
		if prop is Node3D and is_instance_valid(prop) \
				and prop.has_method("take_hit") \
				and pos.distance_to(prop.global_position) <= radius:
			prop.take_hit(1, global_position.direction_to(prop.global_position))

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
	
	if counter_window_timer > 0:
		counter_window_timer -= delta
	
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
	_cloak_base_mat = cloak_material
	visual.add_child(cloak)

	# Cloak trim: a bronze band ringing the mantle's lower hem
	var trim := MeshInstance3D.new()
	trim.name = "CloakTrim"
	var trim_mesh := TorusMesh.new()
	trim_mesh.inner_radius = 0.47
	trim_mesh.outer_radius = 0.52
	trim.mesh = trim_mesh
	var trim_material := StandardMaterial3D.new()
	trim_material.albedo_color = Color(0.55, 0.40, 0.18)
	trim_material.metallic = 0.7
	trim_material.roughness = 0.45
	trim.material_override = trim_material
	trim.position = Vector3(0, 0.30, 0)
	visual.add_child(trim)

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

	# Hood rim: a bronze ring bracing the cowl's opening
	var hood_rim := MeshInstance3D.new()
	hood_rim.name = "HoodRim"
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 0.25
	rim_mesh.outer_radius = 0.30
	rim_mesh.rings = 10
	rim_mesh.ring_segments = 5
	hood_rim.mesh = rim_mesh
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = Color(0.55, 0.40, 0.18)
	rim_material.metallic = 0.7
	rim_material.roughness = 0.45
	hood_rim.material_override = rim_material
	hood_rim.position = Vector3(0, 1.49, 0)
	visual.add_child(hood_rim)

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

	# Belt buckle: a small bronze plate seating the belt's front seam
	var buckle := MeshInstance3D.new()
	var buckle_mesh := BoxMesh.new()
	buckle_mesh.size = Vector3(0.09, 0.09, 0.03)
	buckle.mesh = buckle_mesh
	buckle.material_override = bronze
	buckle.position = Vector3(0, 0.78, 0.25)
	visual.add_child(buckle)

	# Tabard: a cloth panel falling from the chest gem, gold-bordered
	var tabard := MeshInstance3D.new()
	var tabard_mesh := BoxMesh.new()
	tabard_mesh.size = Vector3(0.30, 0.46, 0.03)
	tabard.mesh = tabard_mesh
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.05, 0.10, 0.08)
	cloth.roughness = 0.9
	tabard.material_override = cloth
	tabard.position = Vector3(0, 0.84, 0.34)
	visual.add_child(tabard)
	for side in [-1.0, 1.0]:
		var border := MeshInstance3D.new()
		var border_mesh := BoxMesh.new()
		border_mesh.size = Vector3(0.03, 0.44, 0.034)
		border.mesh = border_mesh
		border.material_override = bronze
		border.position = Vector3(0.13 * side, 0.84, 0.34)
		visual.add_child(border)

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

	# Knee plates: iron guards riding the single-bone legs
	for leg in [leg_l, leg_r]:
		if leg:
			var knee_plate := MeshInstance3D.new()
			var kpm := BoxMesh.new()
			kpm.size = Vector3(0.15, 0.11, 0.05)
			knee_plate.mesh = kpm
			knee_plate.material_override = iron
			knee_plate.position = Vector3(0, -0.24, 0.09)
			leg.add_child(knee_plate)

	# Lantern-arm guard: angled iron plate shielding the lantern forearm
	var guard_arm := visual.get_node_or_null("ArmR/Forearm")
	if guard_arm:
		var arm_guard := MeshInstance3D.new()
		var agm := BoxMesh.new()
		agm.size = Vector3(0.13, 0.22, 0.04)
		arm_guard.mesh = agm
		arm_guard.material_override = iron
		arm_guard.position = Vector3(0, -0.28, 0.06)
		arm_guard.rotation.x = -0.25
		guard_arm.add_child(arm_guard)

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
	# Clarity: the flame is purely atmospheric (wakes as night settles in).
	# It does NOT gate combat — marking a foe does. Show this once.
	if active and not _lantern_was_lit and not _lantern_tip_shown:
		_lantern_tip_shown = true
		FloatingText.spawn_on_entity(self,
			"The lantern wakes at dusk — tap a foe to mark & strike",
			Color(1.0, 0.85, 0.55), 2.0)
	_lantern_was_lit = active

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
	var lantern_fx := get_node_or_null("Visual/Rig/ArmR/Lantern/LanternParticles") as GPUParticles3D
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
			# Trodden paths: every planted step wears the persistent map
			var ws := get_node_or_null("/root/WorldState")
			if ws != null and ws.wear != null:
				ws.wear.record(global_position, 1.1, 0.55)
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

## Swing the held weapon visibly through a slash arc. Works on the authored
## rig too (sockets sit on the model bones), so a strike always reads even
## when the rig's own bones don't animate a combat clip.
func _animate_weapon_swing() -> void:
	if _drive_swing == null or not is_instance_valid(_drive_swing):
		return
	var style := weapon_style()
	var total := float(current_weapon.get("swing_time", 0.36))
	var amp := 1.0 if style == "slash" else (0.9 if style != "magic" else 0.5)
	var base := _swing_base_rot
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	# Snap home first so rapid taps never accumulate drift.
	_drive_swing.rotation = base
	_swing_tween = create_tween()
	# Draw back, then whip through to the opposite side, then settle home.
	_swing_tween.tween_property(_drive_swing, "rotation",
		base + Vector3(0, -0.65 * amp, 0.25 * amp), total * 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(_drive_swing, "rotation",
		base + Vector3(0.15, 0.85 * amp, -0.15 * amp), total * 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_swing_tween.tween_property(_drive_swing, "rotation", base, total * 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _perform_auto_strike(enemy: Node3D) -> void:
	var strike_data = game_state.perform_auto_strike()
	if strike_data.is_empty():
		return
	
	auto_strike_timer = auto_strike_cooldown / game_state.attack_speed_mult()
	animator.attack_style = weapon_style()
	animator.trigger_attack()
	# Swing the held weapon through a visible slash arc (melee reads even on
	# rigs whose bones don't animate combat; magic gets a smaller gesture).
	_animate_weapon_swing()
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
			await _fire_magic_bolt(cast_origin,
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
		# Resolve the payload on the animator’s actual contact frame. This keeps
		# authored FBX swings, proxy swings, VFX, SFX, and damage together.
		await _wait_for_animator_impact()
		if not is_instance_valid(enemy) or enemy.is_dead():
			return
	
	# Impact director: surface-aware cue + coordinated shake/hitstop/chroma.
	# Bloom strikes route through the heavy path so they read heavier.
	var hit_pos: Vector3 = enemy.global_position + Vector3(0, 0.85, 0)
	ImpactDirector.apply_strike(self, weapon_style(),
		ImpactDirector.surface_for(enemy), hit_pos,
		strike_data.is_bloom, _equipped_element())
	if strike_data.is_bloom:
		CombatFx.impact(self, 0.0, 0.0, 1.0, 0.25)
	if magic:
		# Magic basic attack: a small detonation blooms on the target
		audio.play_explosion()
		CombatFx.spawn_explosion(self, enemy.global_position,
			Color(0.62, 0.55, 0.96), 2.4)
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
	
	var damage: int = strike_data.damage
	# Perfect-dodge counter window: the next strike lands boosted (consumed)
	var countered := counter_window_timer > 0.0
	if countered:
		counter_window_timer = 0.0
		damage = int(round(damage * COUNTER_STRIKE_MULT))
	# Crit zones (e.g. Matriarch crown) + lucky crits from LUK both amplify
	var crit_mult := _crit_multiplier_at(enemy)
	if randf() < game_state.crit_chance():
		crit_mult *= game_state.crit_damage()
	if crit_mult > 1.0:
		damage = int(round(damage * crit_mult))
		FloatingText.spawn_damage_on_entity(enemy, damage, true,
			Color(0.62, 0.92, 1.0) if countered else Color(1, 0.55, 0.25))
		# Crit breath: a short slow-mo dip sells heavy critical strikes
		if crit_mult >= 1.4:
			CombatFx.hit_stop(self, 0.10, 0.30)
	
	# Apply damage
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage, global_position.direction_to(enemy.global_position), crit_mult > 1.0)
		_apply_elemental_status(enemy)
		if crit_mult <= 1.0:
			FloatingText.spawn_damage_on_entity(enemy, damage, false,
				Color(0.62, 0.92, 1.0) if countered else Color(1, 0.92, 0.72))
	# Swings also chip destructible props near the impact point
	_damage_props_near(hit_pos)
	
	# Log
	print(strike_data.log)
	
	# Check for kill
	if enemy.has_method("is_dead") and enemy.is_dead():
		CombatFx.impact(self, 0.28, 0.07, 0.15, 0.7)
		_on_enemy_killed(enemy)
		return
	
	# No instant retaliation here: the struck enemy answers with its own
	# telegraphed counter-strike (Hushling._begin_counter_windup). Dodge
	# through it for a perfect-dodge reward.

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
	sphere.radius = 0.16
	sphere.height = 0.32
	sphere.radial_segments = 10
	sphere.rings = 5
	orb.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.62, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.62, 0.55, 0.96)
	mat.emission_energy_multiplier = 3.4
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(orb)
	orb.global_position = from_pos
	var flight := create_tween()
	flight.tween_property(orb, "global_position", to_pos, 0.24) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await flight.finished
	if is_instance_valid(orb):
		CombatFx.spawn_burst(self, orb.global_position,
			Color(0.72, 0.62, 1.0, 0.9), 10, 3.0, 0.24, 0.12)
		CombatFx.spawn_ring(self, orb.global_position, 0.42,
			Color(0.62, 0.82, 1.0, 0.7), 0.22)
		orb.queue_free()

func _on_animator_impact() -> void:
	_anim_impact_serial += 1

func _on_authored_impact(_cue: String) -> void:
	# Authored FBX clips share the same gameplay payload timing as the
	# procedural animator, so skills need only listen to one serial.
	_anim_impact_serial += 1

## Wait for the animator’s authoritative impact frame. The serial check prevents
## a late-await race, while the timeout keeps old/custom rigs playable.
func _wait_for_animator_impact(max_wait: float = 1.25, baseline: int = -1) -> bool:
	var serial := _anim_impact_serial if baseline < 0 else baseline
	var elapsed := 0.0
	while elapsed < max_wait:
		if _anim_impact_serial != serial:
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return false

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
	var reward := 40 if enemy.is_in_group("boss") else (18 if enemy.is_in_group("elite") else 12)
	var loot_drop := preload("res://scripts/systems/loot_drop.gd")
	loot_drop.spawn_gold(self, enemy.global_position + Vector3(0, 0.25, 0), reward)
	
	# Loot drops: physical pickups persist through GameState when collected.
	if game_state.level == 1:
		loot_drop.spawn_item(self, enemy.global_position + Vector3(0.24, 0.2, 0.0), "hushling_thorn", 1)
		loot_drop.spawn_item(self, enemy.global_position + Vector3(-0.24, 0.2, 0.0), "moss_tonic", 1)
	else:
		if randf() < 0.35:
			loot_drop.spawn_item(self, enemy.global_position + Vector3(0.0, 0.2, 0.24), "moss_tonic", 1)
	
	audio.play_victory()

func weapon_style() -> String:
	return str(game_state.equipped_weapon.get("style", "slash"))

## Relic-forged kits carry an elemental payload ("" for vanilla weapons).
func _equipped_element() -> String:
	return ImpactDirector.element_for_weapon(game_state.equipped_weapon)

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
	_pulse_aura_with_magic()
	
	# Dodge roll feeds the animator's limb tuck (1 at launch -> 0 at end)
	animator.set_dodge_ratio(
		clampf(dodge_timer / dodge_duration, 0.0, 1.0) if dodge_timer > 0.0 else 0.0)
	
	_apply_slope_tilt(delta)
	_apply_turn_lean(delta)
	
	# Lantern light pulse, slightly brighter while moving; multiplies up by
	# the lock-on flare so claiming a foe makes the lantern swell visibly.
	lantern_light.light_energy = (1.8 + speed_ratio * 0.18
		+ sin(animator.phase * 1.7) * 0.15) * (1.0 + lantern_flare)
	
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
	# A ground tap only drops the lantern lock when the player is genuinely
	# leaving the fight; a short reposition nearby keeps the mark alive.
	var locked: Node3D = game_state.enemy_target
	if locked == null or not is_instance_valid(locked) \
			or (locked.has_method("is_dead") and locked.is_dead()) \
			or locked.global_position.distance_to(world_pos) > 6.0:
		game_state.disengage_enemy()  # Moving cancels combat lock

## Tapping a foe lights it with the lantern: engage + mark + approach,
## identical to pressing Attack beside it.
func _on_foe_tap(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy) \
			or not enemy.is_in_group("enemy") \
			or (enemy.has_method("is_dead") and enemy.is_dead()):
		return
	_begin_attack_target(enemy)

## The lantern swells a beat the instant it claims a foe (mark_locked),
## layered on the per-frame light pulse so the lock reads on the bearer.
func _on_mark_locked(_enemy: Node3D) -> void:
	if _flare_tween and _flare_tween.is_valid():
		_flare_tween.kill()
	lantern_flare = 1.0
	_flare_tween = create_tween()
	_flare_tween.tween_property(self, "lantern_flare", 1.0, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flare_tween.tween_property(self, "lantern_flare", 0.0, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

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
		FloatingText.spawn_on_entity(self, "NO FOE IN YOUR LIGHT",
			Color(1.0, 0.62, 0.30), 1.4)
		audio.play_lantern_refuse()
		get_tree().call_group("screen_fx", "pulse_vignette", 0.18)
		CombatFx.impact(self, 0.06, 0.0, 0.5, 0.15)
		_show_refuse_hint("Tap a foe to light it, or step closer to one")

## Second-beat hint below a refusal: what to DO next, spelled out so the
## "not marked" state always teaches the recovery instead of dead-ending.
func _show_refuse_hint(text: String) -> void:
	var tw := create_tween()
	tw.tween_interval(0.55)
	tw.tween_callback(func() -> void:
		if is_instance_valid(self):
			FloatingText.spawn_on_entity(self, text,
				Color(0.95, 0.85, 0.70), 0.92))

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
	_animate_weapon_swing()
	await _wait_for_animator_impact()
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
	# marks get an unmissable cue — bigger text, a screen pulse and a
	# lantern tone — because the mark is otherwise invisible state.
	var msg := str(result.get("message", ""))
	if msg.to_lower().contains("target") or msg.to_lower().contains("mark"):
		FloatingText.spawn_on_entity(self, "NO TARGET LIT",
			Color(1.0, 0.62, 0.30), 1.5)
		audio.play_lantern_refuse()
		get_tree().call_group("screen_fx", "pulse_vignette", 0.22)
		CombatFx.impact(self, 0.07, 0.0, 0.5, 0.18)
		_show_refuse_hint("Tap the foe to light it — then cast again")
	else:
		_skill_buffer_until[slot] = Time.get_ticks_msec() + SKILL_BUFFER_MS
		if msg != "":
			FloatingText.spawn_on_entity(self, msg, Color(0.9, 0.9, 0.9))

## Wind-up seconds per rite family — charge glow + audio sync to these.
const SKILL_WINDUP := {
	"strike": 0.10, "whirl": 0.12, "dash_strike": 0.10,
	"explosion": 0.16, "comet": 0.26, "heal_bloom": 0.26, "aoe": 0.16,
}

## Rite-family charge tints (match the payload palette).
func _skill_tint(kind: String) -> Color:
	var base := Color(1.0, 0.90, 0.72)
	match kind:
		"explosion", "aoe":
			base = Color(0.96, 0.62, 0.22)
		"comet":
			base = Color(0.72, 0.60, 1.00)
		"heal_bloom":
			base = Color(0.62, 0.85, 0.45)
	var element := _equipped_element()
	if element in ImpactDirector.ELEMENT_COLORS:
		base = base.lerp(ImpactDirector.ELEMENT_COLORS[element], 0.55)
	return base

## Cast preface shared by every rite: announce the skill name, gather a
## charge glow at the casting hand, telegraph the target, and play the
## family's signature cue — so a press always reads before the payload
## lands, even on rigs whose only combat clips are swings.
func _begin_skill_cast(sk: Dictionary, target: Node3D) -> void:
	var kind := str(sk.get("type", ""))
	# Every rite announces itself over the HERO, enlarged — eyes are usually
	# on your own character mid-fight, so the cast reads at a glance.
	FloatingText.spawn_on_entity(self, "✦ %s" % str(sk.get("name", "RITE")),
		Color(1, 0.9, 0.72), 1.6)
	# Melee rites keep their weapon swings but still get their signature cue.
	if kind in ["strike", "whirl"]:
		animator.attack_style = weapon_style()
		audio.play_skill_cast(kind)
		return
	animator.attack_style = "magic"
	audio.play_skill_cast(kind)
	var hand_pos := hand_socket_r.global_position if hand_socket_r else lantern.global_position
	var tint := _skill_tint(kind)
	var highlight := tint.lerp(Color(1.0, 0.97, 0.86), 0.42)
	# Sustained charge orb that swells through the wind-up and pops at release.
	CombatFx.spawn_charge_glow(self, hand_pos, tint,
		float(SKILL_WINDUP.get(kind, 0.3)), 2.6)
	CombatFx.spawn_motes(self, hand_pos, Color(highlight.r, highlight.g, highlight.b, 0.52),
		10, 0.38, 0.55, 1.35)
	if target != null and is_instance_valid(target) and kind != "heal_bloom":
		CombatFx.spawn_ring(self, target.global_position, 1.8,
			Color(tint.r, tint.g, tint.b, 0.82), 0.4)

func _execute_skill(slot: int, sk: Dictionary) -> void:
	var enemy = game_state.enemy_target
	_begin_skill_cast(sk, enemy)
	match str(sk.get("type", "")):
		"strike":
			animator.attack_style = weapon_style()
			animator.trigger_attack()
			await _wait_for_animator_impact(0.30)
			if enemy == null or not is_instance_valid(enemy):
				return
			audio.play_slash()
			var hit_pos: Vector3 = enemy.global_position + Vector3(0, 0.85, 0)
			var skill_tint := _skill_tint("strike")
			CombatFx.spawn_telegraph(self, hit_pos, Color(skill_tint.r, skill_tint.g, skill_tint.b, 0.9))
			CombatFx.spawn_slash(self, hit_pos, Color(skill_tint.r, skill_tint.g, skill_tint.b, 0.95))
			CombatFx.spawn_slash(self, hit_pos + Vector3(0, 0.25, 0),
				Color(skill_tint.r, skill_tint.g, skill_tint.b, 0.72))
			CombatFx.spawn_stretched_burst(self, hit_pos,
				Color(skill_tint.r, skill_tint.g, skill_tint.b, 0.85), 10, 7.5, 0.26)
			CombatFx.spawn_core_flash(self, hit_pos)
			_deal_skill_damage(enemy, float(sk.get("dmg_mult", 1.5)))
			CombatFx.impact(self, 0.32, 0.06, 0.10, 0.65)
		"whirl":
			animator.attack_style = weapon_style()
			animator.trigger_attack("spin")
			_animate_weapon_swing()
			var radius := float(sk.get("radius", 3.5))
			var skill_tint := _skill_tint("whirl")
			# One short readable wind-up; petals, damage, sound and screen
			# feedback all resolve together right after it.
			await get_tree().create_timer(0.12, false).timeout
			CombatFx.spawn_telegraph(self, global_position,
				Color(skill_tint.r, skill_tint.g, skill_tint.b, 0.9))
			for i in 5:
				var ang := TAU * i / 5.0
				CombatFx.spawn_slash(self,
					global_position + Vector3(cos(ang) * radius * 0.55, 0.9,
						sin(ang) * radius * 0.55),
					Color(skill_tint.r, skill_tint.g, skill_tint.b, 0.9))
			audio.play_slash()
			CombatFx.spawn_ring(self, global_position, radius,
				Color(skill_tint.r, skill_tint.g, skill_tint.b, 0.7), 0.7)
			CombatFx.spawn_shockwave(self, global_position, radius,
				Color(skill_tint.r, skill_tint.g, skill_tint.b, 0.78), 0.4)
			CombatFx.spawn_motes(self, global_position + Vector3(0, 0.3, 0),
				Color(skill_tint.r, skill_tint.g, skill_tint.b, 0.6), 14, radius * 0.5, 0.7, 2.2)
			CombatFx.spawn_core_flash(self, global_position + Vector3(0, 0.9, 0),
				Color(1.0, 0.96, 0.86, 0.95), 1.8)
			for foe in get_tree().get_nodes_in_group("enemy"):
				if foe is Node3D and is_instance_valid(foe) \
						and global_position.distance_to(foe.global_position) <= radius:
					if foe.has_method("is_dead") and foe.is_dead():
						continue
					_deal_skill_damage(foe, float(sk.get("dmg_mult", 1.5)), true)
			CombatFx.impact(self, 0.30, 0.06, 0.10, 0.6)
		"dash_strike":
			# A real dash — iframe the lunge, rain after-image sparks along
			# the path, strike at the moment of arrival.
			animator.attack_style = "magic"
			animator.trigger_attack("hurl")
			if enemy and is_instance_valid(enemy):
				invulnerable_timer = maxf(invulnerable_timer, 0.4)
				var dir := global_position.direction_to(enemy.global_position)
				dir.y = 0.0
				velocity += dir.normalized() * 16.0
				var dash_tint := _skill_tint("dash_strike")
				CombatFx.spawn_skill_ribbon(self, global_position + Vector3(0, 0.55, 0),
				enemy.global_position + Vector3(0, 0.55, 0),
					Color(dash_tint.r, dash_tint.g, dash_tint.b, 0.78), 0.42, 0.36)
				CombatFx.spawn_vibrant_trail(self,
					global_position + Vector3(0, 0.55, 0),
				enemy.global_position + Vector3(0, 0.55, 0), dash_tint,
					Color(1.0, 0.92, 0.54, 0.92), 5)
				# After-image trail: sparks shed behind the lunge line
				for k in 4:
					var trail_pos := global_position.lerp(enemy.global_position,
						0.18 + 0.2 * k) + Vector3(0, 0.45, 0)
					CombatFx.spawn_stretched_burst(self, trail_pos,
						Color(dash_tint.r, dash_tint.g, dash_tint.b, 0.55), 4, 3.0, 0.3)
			await _wait_for_animator_impact(0.35)
			if enemy == null or not is_instance_valid(enemy):
				return
			audio.play_slash()
			var dash_hit: Vector3 = enemy.global_position + Vector3(0, 0.85, 0)
			CombatFx.spawn_slash(self, dash_hit)
			CombatFx.spawn_stretched_burst(self, dash_hit,
				Color(1, 0.84, 0.47, 0.9), 16, 9.0, 0.32)
			CombatFx.spawn_shockwave(self, enemy.global_position, 1.6,
				Color(1, 0.84, 0.47, 0.7), 0.35)
			CombatFx.spawn_core_flash(self, dash_hit)
			_deal_skill_damage(enemy, float(sk.get("dmg_mult", 1.8)))
			CombatFx.impact(self, 0.34, 0.07, 0.10, 0.65)
		"explosion":
			animator.attack_style = "magic"
			animator.trigger_attack("hurl")
			# Capture the detonation point up front so the cast survives the
			# target dying/freeing during the wind-up without touching a dead
			# instance after the await below.
			var from_pos: Vector3 = hand_socket_r.global_position \
				if hand_socket_r else global_position + Vector3(0, 1.2, 0)
			var to_pos: Vector3 = global_position + Vector3(0, 0.6, 0)
			if enemy != null and is_instance_valid(enemy):
				to_pos = enemy.global_position + Vector3(0, 0.6, 0)
			# Launch the burning bolt as soon as the charge orb pops.
			await get_tree().create_timer(
				float(SKILL_WINDUP.get("explosion", 0.16)), false).timeout
			audio.play_skill_release("explosion")
			CombatFx.spawn_bolt(self, from_pos, to_pos,
				Color(0.98, 0.60, 0.20), 0.26, 0.34)
			await get_tree().create_timer(0.12, false).timeout
			audio.play_explosion()
			var color := Color(0.96, 0.62, 0.22)
			CombatFx.spawn_explosion(self, to_pos, color,
				float(sk.get("radius", 3.0)))
			CombatFx.spawn_core_flash(self, to_pos, Color(1.0, 0.9, 0.75), 2.2)
			CombatFx.spawn_shockwave(self, to_pos, float(sk.get("radius", 3.0)),
				Color(color.r, color.g, color.b, 0.85), 0.45)
			CombatFx.spawn_decal(self, to_pos, 1.3)
			# Relic elements leave their payload on AoE detonations
			if _equipped_element() != "":
				ImpactDirector.apply_element(self, _equipped_element(),
					to_pos, float(sk.get("radius", 3.0)) * 0.6)
			CombatFx.spawn_motes(self, to_pos + Vector3(0, 0.3, 0),
				Color(0.98, 0.55, 0.18, 0.7), 16, 1.2, 0.8, 2.6)
			if enemy and is_instance_valid(enemy):
				_deal_skill_damage(enemy, float(sk.get("dmg_mult", 1.9)))
			CombatFx.impact(self, 0.26, 0.06, 0.10, 0.65)
		"comet":
			animator.attack_style = "magic"
			animator.trigger_attack("sky")
			if world and world.camera_rig:
				world.camera_rig.punch_fov(4.0)
			# Sky telegraph, then a falling star that detonates wide on landing
			var ground_pos: Vector3 = enemy.global_position if enemy and is_instance_valid(enemy) else global_position
			CombatFx.spawn_ring(self, ground_pos, 2.0,
				Color(0.62, 0.55, 0.96, 0.9), 0.5)
			CombatFx.spawn_pillar(self, ground_pos, 9.0,
				Color(0.72, 0.60, 1.0, 0.35), 0.6, 1.4)
			# Release the meteor the instant the charge orb pops.
			await get_tree().create_timer(
				float(SKILL_WINDUP.get("comet", 0.26)), false).timeout
			audio.play_skill_release("comet")
			CombatFx.spawn_bolt(self, ground_pos + Vector3(0, 15.0, -2.0),
				ground_pos, Color(0.72, 0.60, 1.0), 0.30, 0.55)
			await get_tree().create_timer(0.30, false).timeout
			audio.play_explosion()
			CombatFx.spawn_explosion(self, ground_pos, Color(0.72, 0.60, 1.0),
				float(sk.get("radius", 4.0)))
			CombatFx.spawn_core_flash(self, ground_pos,
				Color(0.92, 0.88, 1.0), 2.4)
			CombatFx.spawn_shockwave(self, ground_pos, float(sk.get("radius", 4.0)),
				Color(0.80, 0.70, 1.0, 0.85), 0.5)
			CombatFx.spawn_burst(self, ground_pos + Vector3(0, 1.2, 0),
				Color(0.85, 0.75, 1.0, 0.9), 30, 8.0, 0.5, 0.2)
			CombatFx.spawn_motes(self, ground_pos + Vector3(0, 0.4, 0),
				Color(0.72, 0.60, 1.0, 0.65), 20, 1.6, 1.0, 3.0)
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
			await get_tree().create_timer(
				float(SKILL_WINDUP.get("heal_bloom", 0.26)), false).timeout
			audio.play_heal()
			var restored: int = game_state.heal(int(sk.get("heal", 14)))
			FloatingText.spawn_on_entity(self, "+%d" % restored,
				Color(0.62, 0.85, 0.45), 1.6)
			CombatFx.spawn_core_flash(self, global_position + Vector3(0, 1.0, 0),
				Color(0.80, 0.95, 0.65), 1.8)
			# Bloom: light pillar + rising petal motes + soft pulse rings
			CombatFx.spawn_pillar(self, global_position, 3.2,
				Color(0.75, 0.95, 0.55, 0.55), 0.8, 1.1)
			CombatFx.spawn_motes(self, global_position + Vector3(0, 0.2, 0),
				Color(0.62, 0.85, 0.45, 0.8), 26, 0.9, 1.1, 2.4)
			CombatFx.spawn_ring(self, global_position, 1.6,
				Color(0.62, 0.85, 0.45, 0.7), 0.9)
			CombatFx.spawn_ring(self, global_position + Vector3(0, 1.4, 0), 1.1,
				Color(0.75, 0.95, 0.55, 0.5), 0.7)
			_flash_body(Color(0.62, 0.85, 0.45))
		"aoe":
			# Legacy kit slot (Mug Slam): heavy area slam around the hero —
			# a committed spin with a shockwave carrying the payload.
			animator.attack_style = "magic"
			animator.trigger_attack("spin")
			await get_tree().create_timer(
				float(SKILL_WINDUP.get("aoe", 0.16)), false).timeout
			audio.play_skill_release("aoe")
			audio.play_explosion()
			var slam_radius := float(sk.get("radius", 13.0)) * 0.35
			CombatFx.spawn_core_flash(self, global_position + Vector3(0, 0.8, 0))
			CombatFx.spawn_impact_light(self, global_position,
				Color(1.0, 0.72, 0.35), 3.2, slam_radius * 0.9, 0.30)
			CombatFx.spawn_shockwave(self, global_position, slam_radius,
				Color(1.0, 0.84, 0.47, 0.85), 0.45)
			CombatFx.spawn_ring(self, global_position, slam_radius * 0.9,
				Color(1, 0.84, 0.47, 0.6), 0.6)
			CombatFx.spawn_burst(self, global_position + Vector3(0, 0.4, 0),
				Color(0.42, 0.33, 0.2, 0.75), 22, 6.0, 0.45, 0.16)
			CombatFx.spawn_decal(self, global_position, slam_radius * 0.45)
			for foe in get_tree().get_nodes_in_group("enemy"):
				if foe is Node3D and is_instance_valid(foe) \
						and global_position.distance_to(foe.global_position) <= slam_radius:
					if foe.has_method("is_dead") and foe.is_dead():
						continue
					_deal_skill_damage(foe, float(sk.get("dmg_mult", 1.5)), true)
			_damage_props_near(global_position, slam_radius)
			var ws := get_node_or_null("/root/WorldState")
			if ws != null and ws.has_method("gust"):
				ws.gust(0.8)   # ground pound surges the canopy
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
		enemy.take_damage(damage, global_position.direction_to(enemy.global_position), crit > 1.0)
		_apply_elemental_status(enemy)
		if not silent_text or crit > 1.0:
			FloatingText.spawn_damage_on_entity(enemy, damage, crit > 1.0)
	if enemy.has_method("is_dead") and enemy.is_dead():
		CombatFx.impact(self, 0.28, 0.08, 0.12, 0.7)
		_on_enemy_killed(enemy)

func _apply_elemental_status(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_method("apply_elemental_status"):
		return
	var element := _equipped_element()
	if not element.is_empty():
		enemy.apply_elemental_status(element, 1)

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

## Enemies call this when one of their telegraphed strikes resolves against
## us (see Hushling._resolve_counter_strike). Mid-dodge or i-framed inside
## the ring = perfect dodge: slow-mo breath, spark burst and a boosted
## counter window. Otherwise the hit lands normally.
func notify_enemy_strike(from_enemy: Node3D, damage: int) -> void:
	if game_state.combat_state == GameState.CombatState.DEFEATED:
		return
	if dodge_timer > 0.0 or invulnerable_timer > 0.0:
		_trigger_perfect_dodge(from_enemy)
		return
	take_damage(damage, from_enemy.global_position.direction_to(global_position))

func _trigger_perfect_dodge(_source: Node3D) -> void:
	counter_window_timer = PERFECT_DODGE_COUNTER_WINDOW
	FloatingText.spawn_on_entity(self, "Perfect!", Color(0.62, 0.92, 1.0))
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.6, 0),
		Color(0.65, 0.92, 1.0, 0.85), 16, 4.5, 0.4, 0.14)
	CombatFx.spawn_ring(self, global_position + Vector3(0, 0.1, 0), 1.8,
		Color(0.6, 0.9, 1.0, 0.7), 0.5)
	CombatFx.impact(self, 0.18, 0.04, 0.4, 0.3)
	audio.play_dash()
	# Brief slow-mo breath — the restore timer runs in real time so it
	# survives its own time_scale change.
	Engine.time_scale = PERFECT_DODGE_SLOWMO_SCALE
	var t := get_tree().create_timer(PERFECT_DODGE_SLOWMO_REALTIME, true, false, true)
	t.timeout.connect(func() -> void: Engine.time_scale = 1.0)

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
		holder.scale = Vector3.ONE * 0.75
		weapon_socket.attach_node(holder)
	else:
		var rarity := int(current_weapon.get("rarity", 0))
		if rarity < 3:
			weapon_socket.detach()
		else:
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
	_play_weapon_equip_feedback.call_deferred()

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
			_drive_socket = hand_socket_r
			_has_hand_weapon = true
		"ember_sword":
			hand_socket_r.detach()
			hand_socket_l.attach_node(_build_sword_visual())
			_drive_socket = hand_socket_l
			_has_hand_weapon = true
		"arcane_staff":
			hand_socket_l.detach()
			hand_socket_r.attach_node(_build_staff_visual())
			_drive_socket = hand_socket_r
			_has_hand_weapon = true
		"pocket_blade":
			hand_socket_r.detach()
			hand_socket_l.attach_node(_build_pocket_blade_visual())
			_drive_socket = hand_socket_l
			_has_hand_weapon = true
		"snip_twins":
			hand_socket_l.detach()
			hand_socket_r.attach_node(_build_snip_twins_visual())
			_drive_socket = hand_socket_r
			_has_hand_weapon = true
		"soda_cannon":
			hand_socket_l.detach()
			hand_socket_r.attach_node(_build_soda_cannon_visual())
			_drive_socket = hand_socket_r
			_has_hand_weapon = true
		"slab_hammer":
			hand_socket_l.detach()
			hand_socket_r.attach_node(_build_slab_hammer_visual())
			_drive_socket = hand_socket_r
			_has_hand_weapon = true
		_:
			hand_socket_l.detach()
			hand_socket_r.detach()
			_drive_socket = null
			_has_hand_weapon = bool(current_weapon.get("relic", false)) \
				and current_relic != null and current_relic.mesh != null
			if _has_hand_weapon:
				hand_socket_r.attach_node(_build_relic_hand_visual())
				_drive_socket = hand_socket_r
	# Track the attached holder so strikes can swing it (works on the FBX
	# rig too — sockets get re-parented to the model bones, not rebuilt).
	if _drive_socket != null and _drive_socket.is_occupied():
		_drive_swing = _drive_socket.get_attachment()
		_swing_base_rot = _drive_swing.rotation if _drive_swing else Vector3.ZERO
	else:
		_drive_swing = null

func _play_weapon_equip_feedback() -> void:
	if _drive_swing == null or not is_instance_valid(_drive_swing):
		return
	var base_scale := _drive_swing.scale
	var base_rot := _drive_swing.rotation
	_drive_swing.scale = base_scale * 0.08
	_drive_swing.rotation = base_rot + Vector3(0.0, 0.0, 0.32)
	var settle := create_tween()
	settle.set_parallel(true)
	settle.tween_property(_drive_swing, "scale", base_scale, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	settle.tween_property(_drive_swing, "rotation", base_rot, 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var element := str(current_weapon.get("element", ""))
	var glow: Color = ImpactDirector.ELEMENT_COLORS.get(element, Color(1.0, 0.74, 0.30)) as Color
	CombatFx.spawn_motes(self, global_position + Vector3(0.0, 1.0, 0.0),
		Color(glow.r, glow.g, glow.b, 0.55), 5, 0.35, 0.42, 1.8)
	if AudioManager != null and AudioManager.has_method("play_ui_blip"):
		AudioManager.play_ui_blip()

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
	rig.scale = Vector3.ONE * 0.9

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.30, 0.20, 0.11)
	wood.roughness = 0.85
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.19, 0.13, 0.08)
	leather.roughness = 0.95
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.58, 0.61, 0.66)
	steel.metallic = 0.92
	steel.roughness = 0.26

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
	rig.scale = Vector3.ONE * 0.75
	return rig

## CC0 weapon models dropped into assets/models/weapons override the
## procedural props when present (same silent-fallback pattern as rigs).
func _mount_weapon_model(weapon_id: String) -> Node3D:
	var path := ""
	match weapon_id:
		"ember_sword":
			path = "res://assets/models/weapons/ember_sword.glb"
		"arcane_staff":
			path = "res://assets/models/weapons/arcane_staff.glb"
		"mug_mace":
			path = "res://assets/models/weapons/mug_mace.glb"
		_:
			return null
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var model := ps.instantiate() as Node3D
	if model == null:
		return null
	var holder := Node3D.new()
	holder.name = "WeaponModel"
	holder.add_child(model)
	match weapon_id:
		"ember_sword":
			model.rotation_degrees = Vector3(90, 0, 0)
			holder.scale = Vector3.ONE * 0.95
		"arcane_staff":
			model.position = Vector3(0, 0.4, 0)
			holder.scale = Vector3.ONE * 1.0
		"mug_mace":
			model.rotation_degrees = Vector3(90, 0, 0)
			holder.scale = Vector3.ONE * 0.9
	return holder

func _build_sword_visual() -> Node3D:
	var mounted := _mount_weapon_model("ember_sword")
	if mounted != null:
		mounted.rotation_degrees = Vector3(-84, 0, 0)
		return mounted
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
	steel.metallic = 0.9
	steel.roughness = 0.22
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
	var mounted := _mount_weapon_model("arcane_staff")
	if mounted != null:
		mounted.rotation_degrees = Vector3(-12, 0, -8)
		return mounted
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

## Scanned kit: POCKET BLADE — a dead phone reforged into a short blade,
## its screen still glowing along the cutting edge.
func _build_pocket_blade_visual() -> Node3D:
	var rig := Node3D.new()
	rig.name = "PocketBladeVisual"
	rig.rotation_degrees = Vector3(-84, 0, 0)
	rig.scale = Vector3.ONE * 0.9
	var slab := StandardMaterial3D.new()
	slab.albedo_color = Color(0.10, 0.11, 0.13)
	slab.metallic = 0.6
	slab.roughness = 0.45
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color(0.55, 0.90, 1.0)
	screen.emission_enabled = true
	screen.emission = Color(0.45, 0.85, 1.0)
	screen.emission_energy_multiplier = 1.6
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.19, 0.13, 0.08)
	leather.roughness = 0.95

	var body_m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.085, 0.58, 0.024)
	body_m.mesh = bm
	body_m.position = Vector3(0, 0.40, 0)
	body_m.material_override = slab
	rig.add_child(body_m)

	var edge := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.02, 0.52, 0.03)
	edge.mesh = em
	edge.position = Vector3(0.044, 0.44, 0)
	edge.material_override = screen
	rig.add_child(edge)

	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.0
	tm.bottom_radius = 0.05
	tm.height = 0.12
	tm.radial_segments = 4
	tip.mesh = tm
	tip.position = Vector3(0, 0.74, 0)
	tip.rotation.y = PI / 4.0
	tip.material_override = slab
	rig.add_child(tip)

	var grip_wrap := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.028
	gm.bottom_radius = 0.028
	gm.height = 0.16
	gm.radial_segments = 6
	grip_wrap.mesh = gm
	grip_wrap.position = Vector3(0, 0.02, 0)
	grip_wrap.material_override = leather
	rig.add_child(grip_wrap)
	return rig

## Scanned kit: SNIP TWINS — heavy tailor's shears held open like a
## splayed V of steel, pivot ring at the fist.
func _build_snip_twins_visual() -> Node3D:
	var rig := Node3D.new()
	rig.name = "SnipTwinsVisual"
	rig.rotation_degrees = Vector3(-84, 0, 0)
	rig.scale = Vector3.ONE * 0.9
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.66, 0.70, 0.74)
	steel.metallic = 0.85
	steel.roughness = 0.30
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.55, 0.24)
	brass.metallic = 0.8
	brass.roughness = 0.42

	for side in [-1.0, 1.0]:
		var arm_m := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.05, 0.62, 0.02)
		arm_m.mesh = am
		arm_m.position = Vector3(0.07 * side, 0.42, 0)
		arm_m.rotation.z = -0.20 * side
		arm_m.material_override = steel
		rig.add_child(arm_m)

		var tip := MeshInstance3D.new()
		var tmm := CylinderMesh.new()
		tmm.top_radius = 0.0
		tmm.bottom_radius = 0.035
		tmm.height = 0.10
		tmm.radial_segments = 4
		tip.mesh = tmm
		tip.position = Vector3(0.132 * side, 0.76, 0)
		tip.rotation.y = PI / 4.0
		tip.rotation.z = -0.20 * side
		tip.material_override = steel
		rig.add_child(tip)

	var pivot := MeshInstance3D.new()
	var pm := TorusMesh.new()
	pm.inner_radius = 0.045
	pm.outer_radius = 0.075
	pivot.mesh = pm
	pivot.position = Vector3(0, 0.12, 0)
	pivot.material_override = brass
	rig.add_child(pivot)

	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.024
	gm.bottom_radius = 0.024
	gm.height = 0.14
	gm.radial_segments = 6
	grip.mesh = gm
	grip.position = Vector3(0, -0.02, 0)
	grip.material_override = brass
	rig.add_child(grip)
	return rig

## Scanned kit: SODA CANNON — a party bottle gripped club-wise, cap fizzing.
func _build_soda_cannon_visual() -> Node3D:
	var rig := Node3D.new()
	rig.name = "SodaCannonVisual"
	rig.rotation_degrees = Vector3(-78, 0, 0)
	rig.scale = Vector3.ONE * 0.9
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.16, 0.38, 0.18)
	glass.roughness = 0.15
	glass.metallic = 0.2
	var fizz := StandardMaterial3D.new()
	fizz.albedo_color = Color(0.85, 0.95, 1.0)
	fizz.emission_enabled = true
	fizz.emission = Color(0.75, 0.92, 1.0)
	fizz.emission_energy_multiplier = 1.3

	var bottle := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.075
	bm.bottom_radius = 0.115
	bm.height = 0.72
	bm.radial_segments = 9
	bottle.mesh = bm
	bottle.position = Vector3(0, 0.36, 0)
	bottle.material_override = glass
	rig.add_child(bottle)

	var neck := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.042
	nm.bottom_radius = 0.075
	nm.height = 0.14
	nm.radial_segments = 9
	neck.mesh = nm
	neck.position = Vector3(0, 0.79, 0)
	neck.material_override = glass
	rig.add_child(neck)

	var cap := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.048
	cm.height = 0.096
	cm.radial_segments = 8
	cm.rings = 3
	cap.mesh = cm
	cap.position = Vector3(0, 0.88, 0)
	cap.material_override = fizz
	rig.add_child(cap)
	return rig

## Scanned kit: SLAB HAMMER — a laptop lashed to a haft, hinge light still on.
func _build_slab_hammer_visual() -> Node3D:
	var rig := Node3D.new()
	rig.name = "SlabHammerVisual"
	rig.rotation_degrees = Vector3(-84, 0, 0)
	rig.scale = Vector3.ONE * 0.9
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.19, 0.11)
	wood.roughness = 0.85
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.23, 0.26)
	metal.metallic = 0.7
	metal.roughness = 0.4
	var hinge := StandardMaterial3D.new()
	hinge.albedo_color = Color(0.55, 0.75, 1.0)
	hinge.emission_enabled = true
	hinge.emission = Color(0.45, 0.65, 1.0)
	hinge.emission_energy_multiplier = 1.5

	var haft := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.032
	hm.bottom_radius = 0.042
	hm.height = 0.66
	hm.radial_segments = 7
	haft.mesh = hm
	haft.position = Vector3(0, 0.24, 0)
	haft.material_override = wood
	rig.add_child(haft)

	var lid := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.38, 0.26, 0.045)
	lid.mesh = lm
	lid.position = Vector3(0, 0.72, -0.05)
	lid.rotation.x = 0.18
	lid.material_override = metal
	rig.add_child(lid)

	var base := MeshInstance3D.new()
	var sem := BoxMesh.new()
	sem.size = Vector3(0.38, 0.05, 0.26)
	base.mesh = sem
	base.position = Vector3(0, 0.60, 0.08)
	base.material_override = metal
	rig.add_child(base)

	var glow := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.34, 0.015, 0.015)
	glow.mesh = gm
	glow.position = Vector3(0, 0.625, 0.205)
	glow.material_override = hinge
	rig.add_child(glow)
	return rig

## Snap a hand socket onto its palm bone (after CharacterRigLoader.bind_sockets
## re-parents it): origin exactly at the bone, orientation kept, plus a small
## world-unit grip offset along the bone's orthonormalized axes. Works in
## world space so the x100 armature scale can't collapse the offset.
func _snap_hand_socket(sock: AttachmentSocket, grip_offset: Vector3) -> void:
	if sock == null:
		return
	var bone := sock.get_parent() as Node3D
	if bone == null:
		return
	var bone_basis := bone.global_transform.basis.orthonormalized()
	var grip_pos: Vector3 = bone.global_position + (bone_basis * grip_offset)
	sock.global_transform = Transform3D(
		sock.global_transform.basis.orthonormalized(), grip_pos)

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
	_refresh_armor_gear()
	_apply_armor_tint()

## Tint every body mesh (the procedural ghost and, when mounted, the
## authored rig) to the equipped armor palette, or restore the defaults.
func _apply_armor_tint() -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var armor: Dictionary = game_state.equipped_armor
	var use_default := armor.is_empty()
	var tint: Color = armor.get("tint", Color(0.2, 0.2, 0.2))
	var rough := float(armor.get("roughness", 0.66))
	var metal := float(armor.get("metallic", 0.0))
	for mi in visual.find_children("*", "MeshInstance3D", true, false):
		var mat: Material = mi.material_override
		if mat is ShaderMaterial and mat.shader != null \
				and mat.shader.resource_path.ends_with("entity_body.gdshader"):
			mat = mat.duplicate()
			mi.material_override = mat
			if use_default:
				mat.set_shader_parameter("base_color",
					_base_body_shader.get("base_color", Color(0.086, 0.23, 0.165)))
				mat.set_shader_parameter("roughness",
					_base_body_shader.get("roughness", 0.66))
				mat.set_shader_parameter("metallic",
					_base_body_shader.get("metallic", 0.0))
			else:
				mat.set_shader_parameter("base_color", tint)
				mat.set_shader_parameter("roughness", rough)
				mat.set_shader_parameter("metallic", metal)

## Armor gear beyond the shader tint: additive geometry rebuilt on every
## change, so equipping/unequipping never leaves stale meshes behind.
func _refresh_armor_gear() -> void:
	if visual == null or not is_instance_valid(visual):
		return
	if _armor_gear_root != null and is_instance_valid(_armor_gear_root):
		_armor_gear_root.queue_free()
	_armor_gear_root = Node3D.new()
	_armor_gear_root.name = "ArmorGear"
	visual.add_child(_armor_gear_root)
	if cloak_node != null and is_instance_valid(cloak_node) \
			and _cloak_base_mat != null:
		cloak_node.material_override = _cloak_base_mat
	match str(game_state.equipped_armor.get("id", "")):
		"warden_plate":
			_build_warden_plate_gear()
		"emberweave_cloak":
			_build_emberweave_gear()
		_:
			pass

## WARDEN PLATE: iron chest plate with a brass emblem + heavier pauldrons.
func _build_warden_plate_gear() -> void:
	if _armor_gear_root == null:
		return
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.40, 0.43, 0.47)
	iron.metallic = 0.85
	iron.roughness = 0.35
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.72, 0.55, 0.24)
	trim.metallic = 0.8
	trim.roughness = 0.42
	var trim_glow := StandardMaterial3D.new()
	trim_glow.albedo_color = Color(1.0, 0.72, 0.29)
	trim_glow.emission_enabled = true
	trim_glow.emission = Color(1.0, 0.55, 0.15)
	trim_glow.emission_energy_multiplier = 2.2

	var chest := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.62, 0.62, 0.10)
	chest.mesh = cm
	chest.material_override = iron
	chest.position = Vector3(0, 1.0, 0.32)
	_armor_gear_root.add_child(chest)

	# Glowing brass emblem so the plate reads at a distance.
	var emblem := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.14, 0.14, 0.02)
	emblem.mesh = em
	emblem.material_override = trim_glow
	emblem.position = Vector3(0, 1.08, 0.385)
	_armor_gear_root.add_child(emblem)

	for side in [-1.0, 1.0]:
		var pad := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.24
		pm.height = 0.34
		pad.mesh = pm
		pad.material_override = iron
		pad.position = Vector3(0.34 * side, 1.38, 0)
		pad.scale = Vector3(1.0, 0.7, 1.15)
		_armor_gear_root.add_child(pad)
		# Emissive pauldron trim — iron catches the grove light.
		var trim_pad := MeshInstance3D.new()
		var tp := SphereMesh.new()
		tp.radius = 0.16
		tp.height = 0.24
		trim_pad.mesh = tp
		trim_pad.material_override = trim_glow
		trim_pad.position = Vector3(0.44 * side, 1.44, 0)
		trim_pad.scale = Vector3(1.0, 0.3, 1.0)
		_armor_gear_root.add_child(trim_pad)

## EMBERWEAVE CLOAK: recolored mantle with a glowing ember hem.
func _build_emberweave_gear() -> void:
	if _armor_gear_root == null:
		return
	var weave := StandardMaterial3D.new()
	weave.albedo_color = Color(0.30, 0.09, 0.05)
	weave.roughness = 0.8
	if cloak_node != null and is_instance_valid(cloak_node):
		cloak_node.material_override = weave
	var ember := StandardMaterial3D.new()
	ember.albedo_color = Color(1.0, 0.45, 0.15)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.35, 0.08)
	ember.emission_energy_multiplier = 2.2
	var hem := MeshInstance3D.new()
	var hm := TorusMesh.new()
	hm.inner_radius = 0.58
	hm.outer_radius = 0.68
	hem.mesh = hm
	hem.position = Vector3(0, 0.16, 0)
	hem.material_override = ember
	_armor_gear_root.add_child(hem)
	# A second brighter collar ring so the cloak silhouette reads head-on.
	var collar := MeshInstance3D.new()
	var cm := TorusMesh.new()
	cm.inner_radius = 0.30
	cm.outer_radius = 0.36
	collar.mesh = cm
	collar.position = Vector3(0, 1.30, 0.12)
	collar.rotation.x = 1.4
	collar.material_override = ember
	_armor_gear_root.add_child(collar)

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
		_aura_base_energy = 0.85 if aura.a > 0.05 else 0.18
		mat.set_shader_parameter("emission_energy", _aura_base_energy)

## Ambient magic breathes through the bearer's glow: owned auras pulse
## brighter on high-magic nights (WorldState-driven, cheap uniform write).
func _pulse_aura_with_magic() -> void:
	if body == null or not (body.material_override is ShaderMaterial) \
			or _aura_base_energy <= 0.0:
		return
	var ws := get_node_or_null("/root/WorldState")
	var magic: float = ws.magic_level if ws != null else 0.35
	body.material_override.set_shader_parameter("emission_energy",
		_aura_base_energy * (1.0 + magic * 0.2))

## Cosmetic combat voice: layers the owned SFX profile over vanilla cues.
func _cosmetic_cue(kind: String) -> void:
	if game_state.active_sfx_profile != "vanilla":
		audio.play_profile_cue(game_state.active_sfx_profile, kind)


## DEX move-speed and future stat hooks re-derive on allocation.
func _apply_stat_multipliers() -> void:
	_apply_armor_visual()
