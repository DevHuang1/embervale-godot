extends Node3D
class_name EntityAnimator

## === Procedural Entity Animator ===
## Code-driven animation states for primitive-rigged characters.
## Modes: BIPED (hero limb cycle), BLOB (hushling squash-hop),
## BRUTE (matriarch lumber + slam). Layered one-shots: attack, hit, death.
## BIPED extras: foot planting IK, head look-at, dodge limb tuck,
## alternating attack swings, gait-ramp stride, idle fidgets.

enum Mode { BIPED, BLOB, BRUTE }
enum AnimState { IDLE, MOVE, ATTACK, HIT, DEAD }

signal attack_impact
signal footfall(strength: float)
## Generic VFX/SFX hook: "heavy_impact", "aura", "trail_start", "trail_end"
signal anim_event(event_name: String)

@export var mode: Mode = Mode.BIPED
@export var visual_root: Node3D
@export var torso: Node3D
@export var head: Node3D
@export var arm_l: Node3D
@export var arm_r: Node3D
@export var forearm_l: Node3D
@export var forearm_r: Node3D
@export var leg_l: Node3D
@export var leg_r: Node3D
@export var foot_l: Node3D
@export var foot_r: Node3D
@export var lantern: Node3D

@export var walk_frequency: float = 8.0
@export var stride_amplitude: float = 0.8
@export var arm_amplitude: float = 0.45
@export var bob_amplitude: float = 0.045
@export var hop_height: float = 0.16

var anim_state: AnimState = AnimState.IDLE
var move_ratio: float = 0.0
var phase: float = randf() * TAU

var _time: float = 0.0
var _attack_tween: Tween
var _hit_tween: Tween
var _base_arm_l_rot := Vector3.ZERO
var _base_arm_r_rot := Vector3.ZERO
var _base_visual_pos := Vector3.ZERO

# Lantern pendulum spring state
var _pend_angle := Vector2.ZERO
var _pend_vel := Vector2.ZERO
var _last_velocity := Vector3.ZERO

# Idle fidgets
var _idle_clock := 0.0
var _next_fidget_at := randf_range(6.0, 10.0)
var _fidget_active := false
var _fidget_tween: Tween

# Animation LOD: level 0 full, 1 reduced (no springs/fidgets), 2 silhouette
@export var lod_distance: float = 30.0
var _lod_active := false
var _lod_level := 0
# Optional flat-colour material swapped in at LOD2 for a clean far silhouette.
@export var silhouette_material: Material
var _silhouette_swap := {}   # MeshInstance3D -> original material

# Boss heart emissive pulse (BRUTE torso doubles as the body mesh)
var _heart_base_energy := -1.0
var _prev_stomp_sin := 0.0

# Airborne blending (jump pose)
var _air_ratio := 0.0
var _air_target := 0.0

# Gait ramp ("striding out"): sustained direction lengthens the stride
var gait_ramp := 0.0

# Dodge limb tuck (0..1 fed from hero.dodge_timer)
var dodge_ratio := 0.0

# Foot planting: per-foot ground correction fed by hero raycasts
var _foot_dy := Vector2.ZERO       # x = left, y = right
var _foot_pitch := Vector2.ZERO    # slope-matched pitch per foot
var _ik_blend := 0.0
var _base_foot_pos := {}

# Head look-at smoothing
var _head_yaw := 0.0
var _head_pitch := 0.0

# Attack variety: alternate swing sides
var _swing_right := true

# 3-hit melee combo (BIPED slash only): strike -> reverse strike -> overhead
# finisher. Chaining requires the next swing to start within COMBO_WINDOW
# seconds after the previous recovery ends; the finisher always resets.
var combo_step := 0
const COMBO_WINDOW := 0.6
var _combo_clock := 0.0
var _impact_emitted := false
var _in_recovery := false

# Weapon style drives the one-shot pose kit: "slash" swings a blade,
# "magic" raises and snaps a casting arm for detonations
var attack_style := "slash"

func _ready() -> void:
	if arm_l:
		_base_arm_l_rot = arm_l.rotation
	if arm_r:
		_base_arm_r_rot = arm_r.rotation
	if visual_root:
		_base_visual_pos = visual_root.position
	if foot_l:
		_base_foot_pos[foot_l] = foot_l.position
	if foot_r:
		_base_foot_pos[foot_r] = foot_r.position

func _process(delta: float) -> void:
	if _dead_check():
		return
	_update_lod()
	_apply_scan_reveal()
	if _lod_level >= 2:
		_animate_silhouette(delta)
		return
	if _lod_active and _fidget_active:
		_cancel_fidget()
	_time += delta
	_tick_combo_window(delta)
	_air_ratio = lerpf(_air_ratio, _air_target, minf(delta * 10.0, 1.0))
	match mode:
		Mode.BIPED:
			if _lod_active:
				_animate_lod(delta)
				return
			_animate_biped(delta)
			_update_head(delta)
			_update_pendulum(delta)
		Mode.BLOB:
			if _lod_active:
				return
			_animate_blob(delta)
		Mode.BRUTE:
			if _lod_active:
				return
			_animate_brute(delta)

func _update_lod() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		_lod_active = false
		_set_lod_level(0)
		return
	var dist := global_position.distance_to(cam.global_position)
	_lod_active = dist > lod_distance
	_set_lod_level(2 if dist > lod_distance * 1.9 else (1 if _lod_active else 0))

## LOD2: flat-colour silhouette (when a material is assigned) + simple bob.
func _set_lod_level(level: int) -> void:
	if level == _lod_level:
		return
	_lod_level = level
	if not visual_root or silhouette_material == null:
		return
	if level >= 2:
		for mi in visual_root.find_children("*", "MeshInstance3D", true, false):
			if not _silhouette_swap.has(mi):
				_silhouette_swap[mi] = mi.material_override
			mi.material_override = silhouette_material
	else:
		for mi in _silhouette_swap.keys():
			if is_instance_valid(mi):
				mi.material_override = _silhouette_swap[mi]
		_silhouette_swap.clear()

func _animate_silhouette(delta: float) -> void:
	_time += delta
	if visual_root:
		visual_root.position.y = _base_visual_pos.y + sin(_time * 1.6) * 0.03

## Pushes the Divining Lens dirt-scanline through the v2 entity shader for a
## short window after each reveal. Only near-camera entities pay the cost.
func _apply_scan_reveal() -> void:
	if visual_root == null or _lod_level > 0 or mode != Mode.BIPED:
		return
	var since := float(Time.get_ticks_msec() - ScanManager.reveal_stamp_msec) / 1000.0
	if since > 1.3:
		return
	var v := clampf(1.0 - since / 1.3, 0.0, 1.0)
	for mi in visual_root.find_children("*", "MeshInstance3D", true, false):
		var m: Material = mi.material_override
		if m is ShaderMaterial and m.shader != null \
				and m.shader.resource_path.ends_with("entity_body.gdshader"):
			m.set_shader_parameter("scan_reveal", v)

## Pendulum energy for lantern creaks (read by Hero).
func pendulum_speed() -> float:
	return _pend_vel.length()

## Torso lean (0..1 scale) for secondary-motion hooks like cloak sway.
func phase_lean() -> float:
	return 0.10 * move_ratio - 0.14 * _air_ratio

## BLOB micro-spin on direction changes.
func trigger_spin(dir: int) -> void:
	if mode != Mode.BLOB or _dead_check() or visual_root == null:
		return
	var tw := create_tween()
	tw.tween_property(visual_root, "rotation:y",
		visual_root.rotation.y + dir * TAU * 0.4, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Combo window ticks only between swings; any new attack pauses the decay.
func _tick_combo_window(delta: float) -> void:
	if mode != Mode.BIPED or attack_style == "magic":
		return
	if combo_step <= 0 or anim_state != AnimState.IDLE:
		return
	_combo_clock += delta
	if _combo_clock >= COMBO_WINDOW:
		combo_step = 0
		_combo_clock = 0.0

func _animate_lod(_delta: float) -> void:
	# Distant: cheap idle breathing only, no limb cycles or springs
	if visual_root:
		visual_root.position.y = _base_visual_pos.y + sin(_time * 1.6) * 0.02

# === Data-driven tuning (CharacterModelData) ===
func apply_model_data(data: Resource) -> void:
	var d := data as CharacterModelData
	if d == null:
		return
	walk_frequency = d.walk_frequency
	stride_amplitude = d.stride_amplitude
	hop_height = d.hop_height
	lod_distance = d.lod_distance

func _dead_check() -> bool:
	return anim_state == AnimState.DEAD

func set_move_ratio(ratio: float) -> void:
	move_ratio = clampf(ratio, 0.0, 1.0)
	if anim_state != AnimState.ATTACK and anim_state != AnimState.HIT and not _dead_check():
		var next := AnimState.MOVE if move_ratio > 0.08 else AnimState.IDLE
		if next == AnimState.MOVE and anim_state == AnimState.IDLE:
			_cancel_fidget()
		anim_state = next

func set_air_target(airborne: bool) -> void:
	if airborne:
		_cancel_fidget()
	_air_target = 1.0 if airborne else 0.0

func set_gait_ramp(ramp: float) -> void:
	gait_ramp = clampf(ramp, 0.0, 1.0)

func set_dodge_ratio(ratio: float) -> void:
	dodge_ratio = clampf(ratio, 0.0, 1.0)
	if dodge_ratio > 0.05:
		_cancel_fidget()

## Ground corrections from hero-side raycasts (world-space deltas resolved
## against the live foot nodes before feeding in).
func set_foot_ground(left_dy: float, right_dy: float,
		left_pitch: float, right_pitch: float) -> void:
	_foot_dy = Vector2(left_dy, right_dy)
	_foot_pitch = Vector2(left_pitch, right_pitch)

func notify_land(impact: float = 0.0) -> void:
	if _dead_check() or not visual_root or mode != Mode.BIPED:
		return
	impact = clampf(impact, 0.0, 1.0)
	var squash_y := 0.84 - 0.16 * impact
	var spread := 1.08 + 0.07 * impact
	var tween := create_tween()
	tween.tween_property(visual_root, "scale",
		Vector3(spread, squash_y, spread), 0.05 + 0.03 * impact)
	tween.tween_property(visual_root, "scale", Vector3.ONE, 0.16 + 0.10 * impact) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Landing recovery: knees fold under the weight, then straighten
	if anim_state != AnimState.ATTACK and anim_state != AnimState.DEAD \
			and leg_l and leg_r:
		var bend := 0.38 + 0.30 * impact
		var knees := create_tween()
		knees.tween_property(leg_l, "rotation:x", bend, 0.07) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		knees.parallel().tween_property(leg_r, "rotation:x", bend * 0.85, 0.07) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		knees.tween_property(leg_l, "rotation:x", 0.0, 0.26) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		knees.parallel().tween_property(leg_r, "rotation:x", 0.0, 0.26) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func trigger_attack(kind: String = "") -> void:
	_cancel_fidget()
	if _dead_check():
		return
	anim_state = AnimState.ATTACK
	_impact_emitted = false
	if _attack_tween and _attack_tween.is_valid():
		_attack_tween.kill()
	match mode:
		Mode.BIPED:
			match kind:
				"heavy":
					_play_heavy()
				"buff":
					_play_buff()
				_:
					if attack_style == "magic":
						_play_cast()
					else:
						_play_swing()
		Mode.BLOB:
			_play_pounce()
		Mode.BRUTE:
			_play_slam()

func trigger_hit() -> void:
	_cancel_fidget()
	if _dead_check() or not visual_root:
		return
	anim_state = AnimState.HIT
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	visual_root.rotation.x = -0.28
	_hit_tween = create_tween()
	_hit_tween.tween_property(visual_root, "rotation:x", 0.0, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_callback(func(): 
		if anim_state == AnimState.HIT:
			anim_state = AnimState.IDLE)

func trigger_death(fall_dir: float = 1.0) -> void:
	_cancel_fidget()
	if _attack_tween and _attack_tween.is_valid():
		_attack_tween.kill()
	anim_state = AnimState.DEAD
	_in_recovery = false
	combo_step = 0
	if not visual_root:
		return
	if mode == Mode.BLOB:
		# Pop: squash outward, then collapse inward with a burst
		var owner_node := get_parent()
		if owner_node is Node3D:
			CombatFx.spawn_burst(owner_node,
				owner_node.global_position + Vector3(0, 0.5, 0),
				Color(0.55, 0.72, 0.38, 0.8), 16, 4.0, 0.45, 0.14)
		var tween := create_tween()
		tween.tween_property(visual_root, "scale", Vector3(1.3, 0.55, 1.3), 0.08)
		tween.tween_property(visual_root, "scale", Vector3(0.06, 0.02, 0.06), 0.42) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual_root, "rotation:x", -1.35 * fall_dir, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(visual_root, "position:y", _base_visual_pos.y - 0.25, 0.55)

# === BIPED: hero limb cycle with secondary motion ===
func _animate_biped(delta: float) -> void:
	var moving := move_ratio > 0.08 and _air_ratio < 0.4
	if moving:
		phase += delta * walk_frequency * (0.55 + 0.45 * move_ratio) \
			* (1.0 + 0.22 * gait_ramp)
	var s := sin(phase)
	var swing := stride_amplitude * move_ratio * (1.0 + 0.18 * gait_ramp) \
		* (1.0 - _air_ratio)
	var tuck := dodge_ratio
	# Run-vs-walk: past 65% of stride the cycle snaps into a committed
	# run — higher knees, toe push, bigger pump, deeper torso lean.
	var run := 1.0 if move_ratio > 0.65 else 0.0
	# While a swing/cast/heavy owns the body, the per-frame locomotion
	# writes below must stand down or they visually cancel the tween.
	var acting := (_attack_tween != null and _attack_tween.is_valid()) or _in_recovery

	# Dodge-roll squash→stretch: compress through the mid-roll, ease out clean
	if visual_root:
		var sq := sin(clampf(tuck, 0.0, 1.0) * PI) if tuck > 0.001 else 0.0
		var sq_target := Vector3(1.0 + 0.13 * sq, 1.0 - 0.17 * sq, 1.0 + 0.13 * sq)
		visual_root.scale = visual_root.scale.lerp(sq_target, minf(delta * 14.0, 1.0))
	
	# Legs: stride in air blends into a tuck. Running snaps the knee up.
	var leg_pose := -0.95 * _air_ratio if _air_ratio > 0.05 else 0.0
	var run_lift := 1.0 + 0.35 * run
	if leg_l:
		leg_l.rotation.x = lerpf(lerpf(s * swing * run_lift, leg_pose, _air_ratio), -1.15, tuck)
	if leg_r:
		leg_r.rotation.x = lerpf(lerpf(-s * swing * run_lift, leg_pose - 0.35, _air_ratio), -1.45, tuck)
	
	# Feet: heel-toe roll on the planted foot, droop when airborne
	if foot_l:
		var toe_l: float = clampf(sin(phase + PI * 0.5), 0.0, 1.0) * 0.5 * move_ratio - 0.45 * run
		foot_l.rotation.x = lerpf(lerpf(toe_l, -0.5, _air_ratio), -0.9, tuck)
	if foot_r:
		var toe_r: float = clampf(sin(phase + PI * 1.5), 0.0, 1.0) * 0.5 * move_ratio - 0.45 * run
		foot_r.rotation.x = lerpf(lerpf(toe_r, -0.5, _air_ratio), -0.9, tuck)
	
	if moving:
		var pump := 1.0 + 0.5 * run
		var arm_swing := -s * arm_amplitude * move_ratio * pump
		if arm_l and not acting:
			arm_l.rotation.x = arm_swing
		if forearm_l and not acting:
			# Forearm lags a quarter-beat behind the upper arm
			forearm_l.rotation.x = sin(phase - 0.6) * arm_amplitude * 0.75 * move_ratio
		if arm_r and not acting:
			arm_r.rotation.x = -arm_swing
		if forearm_r and not acting:
			forearm_r.rotation.x = sin(phase + PI - 0.6) * arm_amplitude * 0.75 * move_ratio
	else:
		_idle_clock += delta
		if _idle_clock >= _next_fidget_at and not _fidget_active:
			_idle_clock = 0.0
			_next_fidget_at = randf_range(6.0, 10.0)
			_play_fidget()
		if not _fidget_active and not acting:
			var breathe := sin(_time * 2.1) * 0.05
			if arm_l:
				arm_l.rotation.x = lerpf(arm_l.rotation.x, breathe * 0.5, delta * 6.0)
				# Release any leftover dodge-tuck hug
				arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.0, delta * 6.0)
			if arm_r and not (_attack_tween and _attack_tween.is_valid()):
				arm_r.rotation.x = lerpf(arm_r.rotation.x, -breathe * 0.5, delta * 6.0)
				arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.0, delta * 6.0)
			if forearm_l:
				forearm_l.rotation.x = lerpf(forearm_l.rotation.x, breathe * 0.3, delta * 6.0)
			if forearm_r:
				forearm_r.rotation.x = lerpf(forearm_r.rotation.x, -breathe * 0.3, delta * 6.0)
		# Weight-shift settle: after ~2s standing, weight drifts hip to hip
		var shift := clampf((_idle_clock - 2.0) / 2.5, 0.0, 1.0) \
			* (0.0 if (_fidget_active or acting) else 1.0)
		if shift > 0.001:
			if torso:
				torso.rotation.z = lerpf(torso.rotation.z,
					sin(_time * 0.85) * 0.055 * shift, delta * 2.2)
			if visual_root:
				visual_root.position.x = lerpf(visual_root.position.x,
					_base_visual_pos.x + sin(_time * 0.85 + PI * 0.5) * 0.02 * shift,
					delta * 2.2)
	
	# Dodge tuck overlay: limbs fold close while the body spins
	if tuck > 0.001:
		if arm_l:
			arm_l.rotation.x = lerpf(arm_l.rotation.x, -0.85, tuck)
			arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.5, tuck)
		if arm_r and not (_attack_tween and _attack_tween.is_valid()):
			arm_r.rotation.x = lerpf(arm_r.rotation.x, -0.85, tuck)
			arm_r.rotation.z = lerpf(arm_r.rotation.z, -0.5, tuck)
		if forearm_l:
			forearm_l.rotation.x = lerpf(forearm_l.rotation.x, -1.15, tuck)
		if forearm_r:
			forearm_r.rotation.x = lerpf(forearm_r.rotation.x, -1.15, tuck)
	elif moving:
		# Release the tuck hug cleanly once the roll ends
		if arm_l:
			arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.0, delta * 10.0)
		if arm_r:
			arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.0, delta * 10.0)
	if torso and not acting:
		torso.rotation.y = s * 0.07 * move_ratio
		# Lean forward into speed, back at the apex of a jump
		torso.rotation.x = lerpf(torso.rotation.x,
			0.10 * move_ratio - 0.14 * _air_ratio - 0.13 * run, delta * 8.0)
	if visual_root and not acting:
		var bob := absf(sin(phase)) * bob_amplitude * move_ratio * (1.0 + 0.22 * run)
		bob += sin(_time * 2.1) * 0.008
		visual_root.position.y = _base_visual_pos.y + bob
	
	_update_foot_ik(delta)

func _update_foot_ik(delta: float) -> void:
	# Blend out at speed, in the air or mid-roll
	var ik_target := 1.0
	if move_ratio > 0.65 or _air_ratio > 0.25 or dodge_ratio > 0.05:
		ik_target = 0.0
	_ik_blend = lerpf(_ik_blend, ik_target, minf(delta * 9.0, 1.0))
	if _ik_blend <= 0.01:
		return
	# Stance gating: idle plants both feet; walking plants the back-swing leg
	var step_move := clampf(move_ratio * 7.0, 0.0, 1.0)
	var s_l := sin(phase)
	var s_r := sin(phase + PI)
	var st_l := maxf(clampf(s_l, 0.0, 1.0), 1.0 - step_move)
	var st_r := maxf(clampf(s_r, 0.0, 1.0), 1.0 - step_move)
	var k := minf(delta * 14.0, 1.0)
	if foot_l and _base_foot_pos.has(foot_l):
		var ty: float = _base_foot_pos[foot_l].y + clampf(_foot_dy.x, -0.28, 0.28)
		foot_l.position.y = lerpf(foot_l.position.y, ty, _ik_blend * st_l * k)
		foot_l.rotation.x += _foot_pitch.x * _ik_blend * st_l
	if foot_r and _base_foot_pos.has(foot_r):
		var tyr: float = _base_foot_pos[foot_r].y + clampf(_foot_dy.y, -0.28, 0.28)
		foot_r.position.y = lerpf(foot_r.position.y, tyr, _ik_blend * st_r * k)
		foot_r.rotation.x += _foot_pitch.y * _ik_blend * st_r

func _update_head(delta: float) -> void:
	if not head:
		return
	var busy := anim_state == AnimState.ATTACK or anim_state == AnimState.HIT \
		or _lod_active or dodge_ratio > 0.4 or _fidget_active
	var ty := 0.0
	var tp := 0.0
	if not busy:
		var look_dir := Vector3.ZERO
		var enemy: Node3D = GameState.enemy_target
		if enemy != null and is_instance_valid(enemy):
			look_dir = (enemy.global_position + Vector3(0, 0.6, 0)
				- head.global_position).normalized()
		elif move_ratio <= 0.08:
			var cam := get_viewport().get_camera_3d()
			if cam:
				look_dir = -cam.global_transform.basis.z
				look_dir.y *= 0.6
				look_dir = look_dir.normalized()
		if look_dir != Vector3.ZERO and visual_root:
			var ld := visual_root.global_transform.basis.inverse() * look_dir
			ty = clampf(atan2(ld.x, ld.z), -0.6, 0.6)
			tp = clampf(-asin(clampf(ld.y, -1.0, 1.0)), -0.35, 0.35)
	var k := minf(delta * 6.0, 1.0)
	_head_yaw = lerpf(_head_yaw, ty, k)
	_head_pitch = lerpf(_head_pitch, tp, k)
	head.rotation = Vector3(_head_pitch, _head_yaw, 0.0)

# === Idle fidgets: short one-shot twitches between quests ===
func _play_fidget() -> void:
	if not visual_root:
		return
	_fidget_active = true
	_fidget_tween = create_tween()
	var variant := randi() % 3
	match variant:
		0:
			# Lantern raise glance
			if arm_r:
				_fidget_tween.tween_property(arm_r, "rotation:x",
					_base_arm_r_rot.x - 0.9, 0.45) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				_fidget_tween.parallel().tween_property(arm_r, "rotation:z",
					_base_arm_r_rot.z - 0.35, 0.45)
				_fidget_tween.tween_interval(randf_range(0.5, 0.9))
				_fidget_tween.tween_property(arm_r, "rotation:x",
					_base_arm_r_rot.x, 0.55) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
				_fidget_tween.parallel().tween_property(arm_r, "rotation:z",
					_base_arm_r_rot.z, 0.55)
			else:
				_fidget_active = false
		1:
			# Weight shift
			var side := 1.0 if randf() < 0.5 else -1.0
			_fidget_tween.tween_property(visual_root, "position:x",
				_base_visual_pos.x + 0.035 * side, 0.5) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			if torso:
				_fidget_tween.parallel().tween_property(torso, "rotation:z",
					-0.06 * side, 0.5)
			_fidget_tween.tween_interval(randf_range(0.4, 0.8))
			_fidget_tween.tween_property(visual_root, "position:x",
				_base_visual_pos.x, 0.55)
			if torso:
				_fidget_tween.parallel().tween_property(torso, "rotation:z", 0.0, 0.55)
		2:
			# Shoulder roll
			if arm_l and arm_r:
				_fidget_tween.tween_property(arm_l, "rotation:z",
					_base_arm_l_rot.z + 0.22, 0.22).set_trans(Tween.TRANS_SINE)
				_fidget_tween.parallel().tween_property(arm_r, "rotation:z",
					_base_arm_r_rot.z - 0.22, 0.22).set_trans(Tween.TRANS_SINE)
				_fidget_tween.tween_property(arm_l, "rotation:z",
					_base_arm_l_rot.z, 0.35)
				_fidget_tween.parallel().tween_property(arm_r, "rotation:z",
					_base_arm_r_rot.z, 0.35)
			else:
				_fidget_active = false
	_fidget_tween.tween_callback(func(): _fidget_active = false)

func _cancel_fidget() -> void:
	_idle_clock = 0.0
	if not _fidget_active and (_fidget_tween == null or not _fidget_tween.is_valid()):
		return
	_fidget_active = false
	if _fidget_tween and _fidget_tween.is_valid():
		_fidget_tween.kill()
	_fidget_tween = null
	# Restore props no other writer owns (head/arm poses are re-lerped
	# by their regular writers; position.x is not)
	if visual_root and mode == Mode.BIPED:
		var cleanup := create_tween()
		cleanup.tween_property(visual_root, "position:x", _base_visual_pos.x, 0.2)

## Heavy charged strike: long two-handed wind-up with a torso coil, a
## committed hold, then an overhead crash. Damage windows hook the
## "heavy_impact" event, not the wind-up.
func _play_heavy() -> void:
	if not arm_l or not arm_r:
		attack_impact.emit()
		return
	var bl := _base_arm_l_rot
	var br := _base_arm_r_rot
	_attack_tween = create_tween()
	_attack_tween.set_parallel(true)
	# Wind-up: both arms coil high, torso twists back, weight drops
	_attack_tween.tween_property(arm_r, "rotation:x", br.x - 3.0, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(arm_l, "rotation:x", bl.x - 2.7, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if torso:
		_attack_tween.tween_property(torso, "rotation:y", 0.35, 0.30) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_attack_tween.tween_property(torso, "rotation:x", -0.16, 0.30)
	if visual_root:
		_attack_tween.tween_property(visual_root, "position:y",
			_base_visual_pos.y - 0.05, 0.30)
	_attack_tween.chain().tween_interval(0.09)
	# Crash: full-body overhead slam
	_attack_tween.chain().tween_property(arm_r, "rotation:x", br.x + 1.05, 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_attack_tween.parallel().tween_property(arm_l, "rotation:x", bl.x + 0.95, 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if torso:
		_attack_tween.parallel().tween_property(torso, "rotation:y", -0.18, 0.09)
		_attack_tween.parallel().tween_property(torso, "rotation:x", 0.26, 0.09)
	if visual_root:
		_attack_tween.parallel().tween_property(visual_root, "position:z",
			_base_visual_pos.z + 0.28, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_attack_tween.chain().tween_callback(func():
		_in_recovery = true
		_emit_impact()
		anim_event.emit("heavy_impact"))
	# Long committed recovery
	_attack_tween.tween_property(arm_r, "rotation:x", br.x, 0.42) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.parallel().tween_property(arm_l, "rotation:x", bl.x, 0.42)
	if torso:
		_attack_tween.parallel().tween_property(torso, "rotation", Vector3.ZERO, 0.40)
	if visual_root:
		_attack_tween.parallel().tween_property(visual_root, "position:z",
			_base_visual_pos.z, 0.34)
	_attack_tween.chain().tween_callback(func():
		_in_recovery = false
		combo_step = 0
		if anim_state == AnimState.ATTACK:
			anim_state = AnimState.IDLE)

## Buff/self-cast: arms sweep out and up, chest opens to the sky while an
## aura blooms (hooked via the "aura" event), then settles.
func _play_buff() -> void:
	if not arm_l or not arm_r:
		anim_event.emit("aura")
		attack_impact.emit()
		return
	var bl := _base_arm_l_rot
	var br := _base_arm_r_rot
	_attack_tween = create_tween()
	_attack_tween.set_parallel(true)
	_attack_tween.tween_property(arm_l, "rotation:x", bl.x - 2.2, 0.32) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_attack_tween.tween_property(arm_l, "rotation:z", bl.z + 0.85, 0.32) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_attack_tween.tween_property(arm_r, "rotation:x", br.x - 2.2, 0.32) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_attack_tween.tween_property(arm_r, "rotation:z", br.z - 0.85, 0.32) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if torso:
		_attack_tween.tween_property(torso, "rotation:x", -0.22, 0.32) \
			.set_trans(Tween.TRANS_SINE)
	if visual_root:
		_attack_tween.tween_property(visual_root, "position:y",
			_base_visual_pos.y + 0.03, 0.32)
	_attack_tween.chain().tween_callback(func(): anim_event.emit("aura"))
	_attack_tween.chain().tween_interval(0.42)
	_attack_tween.chain().tween_callback(func(): attack_impact.emit())
	# Settle home
	_attack_tween.tween_property(arm_l, "rotation", bl, 0.38) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_attack_tween.parallel().tween_property(arm_r, "rotation", br, 0.38) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if torso:
		_attack_tween.parallel().tween_property(torso, "rotation:x", 0.0, 0.36)
	if visual_root:
		_attack_tween.parallel().tween_property(visual_root, "position:y",
			_base_visual_pos.y, 0.36)
	_attack_tween.chain().tween_callback(func():
		if anim_state == AnimState.ATTACK:
			anim_state = AnimState.IDLE)

## Slash dispatcher: the current combo step picks the swing variant.
## Magic casts and BLOB/BRUTE one-shots never enter this path.
func _play_swing() -> void:
	match combo_step:
		1:
			_play_swing_reverse()
		2:
			_play_overhead_finisher()
		_:
			_play_swing_opening()

func _play_swing_opening() -> void:
	var drive := arm_r if _swing_right else arm_l
	var guard := arm_l if _swing_right else arm_r
	if not drive:
		_emit_impact()
		return
	var base_drive := _base_arm_r_rot if _swing_right else _base_arm_l_rot
	var base_guard := _base_arm_l_rot if _swing_right else _base_arm_r_rot
	var twist := 0.22 if _swing_right else -0.22
	# Telegraphed three-phase swing: anticipation -> impact -> recovery,
	# alternating sides, with a small root lunge synced to the impact frame
	_attack_tween = create_tween()
	if visual_root:
		_attack_tween.parallel().tween_property(visual_root, "rotation:y", twist, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(drive, "rotation:x", base_drive.x - 2.5, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if guard:
		_attack_tween.parallel().tween_property(guard, "rotation:x",
			base_guard.x - 0.55, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(drive, "rotation:x", base_drive.x + 1.15, 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_attack_tween.tween_callback(_swing_impact.bind(twist, 0.14))
	_finish_swing(base_drive, base_guard, drive, guard, 0.22)
	_swing_right = not _swing_right

## Combo step 1: mirrored reverse diagonal — opposite torso twist, deeper
## coil, longer lunge into the target.
func _play_swing_reverse() -> void:
	var drive := arm_r if _swing_right else arm_l
	var guard := arm_l if _swing_right else arm_r
	if not drive:
		_emit_impact()
		return
	var base_drive := _base_arm_r_rot if _swing_right else _base_arm_l_rot
	var base_guard := _base_arm_l_rot if _swing_right else _base_arm_r_rot
	var twist := -0.30 if _swing_right else 0.30
	_attack_tween = create_tween()
	if visual_root:
		_attack_tween.parallel().tween_property(visual_root, "rotation:y", twist, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(drive, "rotation:x", base_drive.x - 2.8, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if guard:
		_attack_tween.parallel().tween_property(guard, "rotation:x",
			base_guard.x - 0.70, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(drive, "rotation:x", base_drive.x + 1.25, 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_attack_tween.tween_callback(_swing_impact.bind(twist, 0.20))
	_finish_swing(base_drive, base_guard, drive, guard, 0.24)
	_swing_right = not _swing_right

## Combo step 2 finisher: both arms coil overhead (~0.22s), then slam down
## together with a torso dip on the snap. Long recovery; always resets.
func _play_overhead_finisher() -> void:
	if not arm_l or not arm_r:
		_emit_impact()
		return
	var bl := _base_arm_l_rot
	var br := _base_arm_r_rot
	_attack_tween = create_tween()
	_attack_tween.set_parallel(true)
	_attack_tween.tween_property(arm_r, "rotation:x", br.x - 2.9, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(arm_l, "rotation:x", bl.x - 2.9, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if torso:
		_attack_tween.tween_property(torso, "rotation:x", -0.14, 0.22)
	if visual_root:
		_attack_tween.tween_property(visual_root, "position:y",
			_base_visual_pos.y - 0.04, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.chain().tween_property(arm_r, "rotation:x", br.x + 0.95, 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_attack_tween.parallel().tween_property(arm_l, "rotation:x", bl.x + 0.95, 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if torso:
		_attack_tween.parallel().tween_property(torso, "rotation:x", 0.20, 0.07)
	if visual_root:
		_attack_tween.parallel().tween_property(visual_root, "position:y",
			_base_visual_pos.y, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_attack_tween.chain().tween_callback(_finisher_snap)
	_attack_tween.tween_property(arm_r, "rotation:x", br.x, 0.34) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.parallel().tween_property(arm_l, "rotation:x", bl.x, 0.34) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if torso:
		_attack_tween.parallel().tween_property(torso, "rotation:x", 0.0, 0.30)
	_attack_tween.tween_callback(func():
		_in_recovery = false
		_on_swing_completed())

## Impact frame bookkeeping shared by slash swings: open the cancel window,
## emit attack_impact exactly once, then unwind the root lunge.
func _swing_impact(twist: float, lunge: float) -> void:
	_in_recovery = true
	_emit_impact()
	if visual_root:
		var back := create_tween()
		back.tween_property(visual_root, "rotation:y", 0.0, 0.24) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		back.parallel().tween_property(visual_root, "position:z",
			_base_visual_pos.z + lunge, 0.07) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		back.chain().tween_property(visual_root, "position:z",
			_base_visual_pos.z, 0.20) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Finisher snap: deeper committed lunge than a normal swing.
func _finisher_snap() -> void:
	_in_recovery = true
	_emit_impact()
	if visual_root:
		var back := create_tween()
		back.tween_property(visual_root, "position:z",
			_base_visual_pos.z + 0.24, 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		back.chain().tween_property(visual_root, "position:z",
			_base_visual_pos.z, 0.26) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _emit_impact() -> void:
	if _impact_emitted:
		return
	_impact_emitted = true
	attack_impact.emit()

## Shared tail for slash variants: settle both arms home over `recovery`
## seconds, then close the swing out.
func _finish_swing(base_drive: Vector3, base_guard: Vector3, drive: Node3D,
		guard: Node3D, recovery: float) -> void:
	_attack_tween.tween_property(drive, "rotation:x", base_drive.x, recovery) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if guard:
		_attack_tween.parallel().tween_property(guard, "rotation:x",
			base_guard.x, recovery).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_callback(func():
		_in_recovery = false
		_on_swing_completed())

func _on_swing_completed() -> void:
	if anim_state == AnimState.ATTACK:
		anim_state = AnimState.IDLE
	_advance_combo()

func _advance_combo() -> void:
	if mode != Mode.BIPED or attack_style == "magic":
		return
	if combo_step >= 2:
		combo_step = 0  # the finisher always closes the chain
	else:
		combo_step += 1
	_combo_clock = 0.0

## True while a swing's impact has landed but the follow-through is still
## playing — the phase a dodge roll may cancel.
func is_recovering() -> bool:
	return anim_state == AnimState.ATTACK and _in_recovery

## Dodge-cancel: cut the follow-through dead and blend the arms home fast.
func cancel_recovery() -> void:
	if not is_recovering():
		return
	if _attack_tween and _attack_tween.is_valid():
		_attack_tween.kill()
	_attack_tween = null
	_in_recovery = false
	var blend := create_tween()
	blend.set_parallel(true)
	if arm_l:
		blend.tween_property(arm_l, "rotation", _base_arm_l_rot, 0.15) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if arm_r:
		blend.tween_property(arm_r, "rotation", _base_arm_r_rot, 0.15) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if visual_root:
		blend.tween_property(visual_root, "rotation:y", 0.0, 0.15)
		blend.tween_property(visual_root, "position:z", _base_visual_pos.z, 0.15)
	anim_state = AnimState.IDLE
	_advance_combo()

## Staff/magic one-shot: raise the drive arm overhead with a charge,
## snap down on the impact frame, settle back. Alternates arms like swings.
func _play_cast() -> void:
	var drive := arm_r if _swing_right else arm_l
	var guard := arm_l if _swing_right else arm_r
	if not drive:
		attack_impact.emit()
		return
	var base_drive := _base_arm_r_rot if _swing_right else _base_arm_l_rot
	var base_guard := _base_arm_l_rot if _swing_right else _base_arm_r_rot
	var twist := -0.14 if _swing_right else 0.14
	_attack_tween = create_tween()
	if visual_root:
		_attack_tween.parallel().tween_property(visual_root, "rotation:y", twist, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Charge: arm sweeps overhead, torso leans back to gather
	_attack_tween.tween_property(drive, "rotation:x", base_drive.x - 2.7, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if guard:
		_attack_tween.parallel().tween_property(guard, "rotation:x",
			base_guard.x - 1.2, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if torso:
		_attack_tween.parallel().tween_property(torso, "rotation:x", -0.10, 0.18)
	_attack_tween.tween_interval(0.07)
	# Snap: cast arm whips forward, detonation lands here
	_attack_tween.tween_property(drive, "rotation:x", base_drive.x - 0.55, 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if torso:
		_attack_tween.parallel().tween_property(torso, "rotation:x", 0.12, 0.07)
	_attack_tween.tween_callback(func():
		attack_impact.emit()
		if visual_root:
			var back := create_tween()
			back.tween_property(visual_root, "rotation:y", 0.0, 0.26) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	# Settle
	_attack_tween.tween_property(drive, "rotation:x", base_drive.x, 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if guard:
		_attack_tween.parallel().tween_property(guard, "rotation:x", base_guard.x, 0.24) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if torso:
		_attack_tween.parallel().tween_property(torso, "rotation:x", 0.0, 0.24)
	_attack_tween.tween_callback(func():
		if anim_state == AnimState.ATTACK:
			anim_state = AnimState.IDLE)
	_swing_right = not _swing_right

# === BLOB: hushling squash-and-stretch hop with anticipation ===
func _animate_blob(delta: float) -> void:
	if not visual_root:
		return
	phase += delta * (2.2 + move_ratio * 4.0)
	var hop := absf(sin(phase)) * hop_height * (0.4 + move_ratio)
	# Anticipation: squash dips just before the launch instead of at the apex
	var squash := 1.0 + sin(phase * 2.0 - 0.9) * 0.09
	visual_root.position.y = _base_visual_pos.y + hop
	visual_root.scale = Vector3(
		lerpf(visual_root.scale.x, 2.0 - squash, delta * 10.0),
		lerpf(visual_root.scale.y, squash, delta * 10.0),
		lerpf(visual_root.scale.z, 2.0 - squash, delta * 10.0))

func _play_pounce() -> void:
	if not visual_root:
		attack_impact.emit()
		return
	_attack_tween = create_tween()
	_attack_tween.tween_property(visual_root, "scale:y", 1.45, 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.parallel().tween_property(visual_root, "scale:x", 0.72, 0.10)
	# Quick committed lunge of the root under the squash
	_attack_tween.parallel().tween_property(visual_root, "position:z",
		_base_visual_pos.z + 0.22, 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	attack_impact.emit()
	_attack_tween.tween_property(visual_root, "scale", Vector3.ONE, 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_attack_tween.parallel().tween_property(visual_root, "position:z",
		_base_visual_pos.z, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# === BRUTE: matriarch lumber with weight shift and arm sway ===
func _animate_brute(delta: float) -> void:
	if not visual_root:
		return
	# Slow lumber roll + alternating weight shift (stomp cadence)
	var stomp := sin(_time * 1.15)
	# Deliberate footfall on the downbeat: shake + dust + stomp cue
	if _prev_stomp_sin > 0.0 and stomp <= 0.0 and move_ratio > 0.12:
		footfall.emit(clampf(move_ratio, 0.0, 1.0))
	_prev_stomp_sin = stomp
	visual_root.rotation.z = lerpf(visual_root.rotation.z, stomp * 0.055, delta * 2.2)
	if torso:
		torso.position.y = lerpf(torso.position.y,
			_base_visual_pos.y + absf(stomp) * 0.09, delta * 3.0)
		# Shoulders counter-roll against the stomp for weight
		torso.rotation.z = lerpf(torso.rotation.z, -stomp * 0.035, delta * 2.5)
	
	# Idle arm sway in opposite phase; slam tween owns arms while active
	if not (_attack_tween and _attack_tween.is_valid()):
		if arm_l:
			arm_l.rotation.z = 0.06 + sin(_time * 1.15 + PI) * 0.04
		if arm_r:
			arm_r.rotation.z = -0.06 + sin(_time * 1.15) * 0.04
	
	var breathe := 1.0 + sin(_time * 1.7) * 0.018
	if torso and not (_attack_tween and _attack_tween.is_valid()):
		torso.scale = torso.scale.lerp(Vector3(breathe, 2.0 - breathe, breathe), delta * 4.0)
	
	# Hollow heart: emissive pulse breathing with the chest
	if torso and torso.material_override is ShaderMaterial:
		var mat: ShaderMaterial = torso.material_override
		if _heart_base_energy < 0.0:
			_heart_base_energy = float(mat.get_shader_parameter("emission_energy"))
		if _heart_base_energy > 0.0:
			mat.set_shader_parameter("emission_energy",
				_heart_base_energy * (0.80 + 0.34 * sin(_time * 2.0)))

func _play_slam() -> void:
	if not arm_l or not arm_r:
		attack_impact.emit()
		return
	var bl := arm_l.rotation
	var br := arm_r.rotation
	_attack_tween = create_tween()
	_attack_tween.set_parallel(true)
	_attack_tween.tween_property(arm_l, "rotation:x", -2.1, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(arm_r, "rotation:x", -2.1, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_attack_tween.chain().tween_property(arm_l, "rotation:x", 0.75, 0.11) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_attack_tween.parallel().tween_property(arm_r, "rotation:x", 0.75, 0.11) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_attack_tween.chain().tween_callback(func():
		attack_impact.emit()
		# Slam drives a fountain of dirt and bark debris upward
		var owner_node := get_parent()
		if owner_node is Node3D:
			CombatFx.spawn_burst(owner_node,
				owner_node.global_position + Vector3(0, 0.3, 0),
				Color(0.32, 0.24, 0.15, 0.85), 22, 7.0, 0.6, 0.2))
	_attack_tween.tween_property(arm_l, "rotation", bl, 0.4)
	_attack_tween.parallel().tween_property(arm_r, "rotation", br, 0.4)
	_attack_tween.chain().tween_callback(func():
		if anim_state == AnimState.ATTACK:
			anim_state = AnimState.IDLE)

# === Lantern pendulum (spring lag behind acceleration) ===
func _update_pendulum(delta: float) -> void:
	if not lantern or delta <= 0.0:
		return
	var body := get_parent()
	var vel := Vector3.ZERO
	if body is CharacterBody3D:
		vel = body.velocity
	var accel := (vel - _last_velocity) / delta
	_last_velocity = vel
	if visual_root:
		var inv := visual_root.global_transform.basis.inverse()
		var local_acc := inv * accel
		var target := Vector2(
			clampf(-local_acc.z * 0.010, -0.30, 0.30),
			clampf(local_acc.x * 0.010, -0.30, 0.30))
		var stiff := 42.0
		var damp := 7.5
		_pend_vel += (target - _pend_angle) * stiff * delta
		_pend_vel -= _pend_vel * damp * delta
		_pend_angle += _pend_vel * delta
		lantern.rotation.x = _pend_angle.x
		lantern.rotation.z = _pend_angle.y
