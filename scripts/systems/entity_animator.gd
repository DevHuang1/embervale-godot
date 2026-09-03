extends Node
class_name EntityAnimator

## === EntityAnimator — Procedural Combat Animation Controller ===
## Drives squash-stretch, attack swings, hit-react, death tumble and gait
## entirely in GDScript (no AnimationPlayer required).
##
## Works with the procedural silhouette bodies (no .glb needed).
## When an authored rig mounts, its AnimationPlayer takes priority and this
## node's tweens are suppressed so they don't fight the authored clips.
##
## Signals (connected by parent entities):
##   attack_impact(serial: int)   — emit at visual hit frame
##   anim_event(name: String)     — generic event for footsteps, SFX cues
##   footfall(strength: float)    — boss footstep weight
##
## Public API:
##   trigger_attack()       — play attack swing
##   trigger_hit()          — play hit-react flash
##   trigger_death(dir)     — play death fall
##   trigger_spin(dir)      — play direction-change micro-spin
##   set_move_ratio(r)      — set 0–1 locomotion blend
##   set_gait_ramp(r)       — set 0–1 stride-out ramp
##   set_air_target(b)      — airborne blend
##   notify_land(hard)      — landing squash
##   cancel_recovery()      — cancel post-attack recovery
##   is_recovering() -> bool
##   get_attack_window() -> bool  — true during committed swing frames
##   set_visual_root(node)  — override which node gets transformed

signal attack_impact(serial: int)
signal anim_event(name: String)
signal footfall(strength: float)

## Visual node to drive. Set automatically from parent if not overridden.
var visual_root : Node3D = null

# Internal animation state
var _move_ratio      : float = 0.0
var _gait_ramp       : float = 0.0
var _airborne        : bool  = false
var _in_attack       : bool  = false
var _in_recovery     : bool  = false
var _attack_serial   : int   = 0
var _attack_window   : bool  = false
var _attack_tween    : Tween = null
var _hit_tween       : Tween = null
var _authored_rig    : bool  = false  # suppresses procedural tweens when true
var _t               : float = 0.0

# Squash-stretch baseline scale
var _base_scale : Vector3 = Vector3.ONE

func _ready() -> void:
	# Auto-discover visual root from parent
	var p := get_parent()
	if p == null:
		return
	# Try standard paths
	visual_root = p.get_node_or_null("Visual/Rig")
	if visual_root == null:
		visual_root = p.get_node_or_null("Visual")
	if visual_root == null:
		visual_root = p  # fallback — drive the parent itself

func _process(delta: float) -> void:
	_t += delta
	if visual_root == null or not is_instance_valid(visual_root):
		return
	if _authored_rig:
		return
	_apply_idle_breath(delta)
	_apply_locomotion_squash(delta)

# ─────────────────────────────────────────────────────────────────────────────
# Public setters (called every frame by entities)
# ─────────────────────────────────────────────────────────────────────────────

func set_move_ratio(r: float) -> void:
	_move_ratio = clampf(r, 0.0, 1.0)

func set_gait_ramp(r: float) -> void:
	_gait_ramp = clampf(r, 0.0, 1.0)

func set_air_target(airborne: bool) -> void:
	_airborne = airborne

func get_attack_window() -> bool:
	return _attack_window

func is_recovering() -> bool:
	return _in_recovery

func set_visual_root(node: Node3D) -> void:
	visual_root = node
	if visual_root != null:
		_base_scale = visual_root.scale
		# Check if an authored AnimationPlayer is present
		_authored_rig = visual_root.find_child("AnimationPlayer", true, false) != null

# ─────────────────────────────────────────────────────────────────────────────
# Attack swing
# ─────────────────────────────────────────────────────────────────────────────

func trigger_attack() -> void:
	if visual_root == null or _authored_rig:
		return
	if _attack_tween != null and _attack_tween.is_valid():
		_attack_tween.kill()
	_in_attack   = true
	_attack_window = false
	_in_recovery = false
	_attack_serial += 1
	var serial := _attack_serial

	_attack_tween = visual_root.create_tween()
	# Wind-up: scale back
	_attack_tween.tween_property(visual_root, "scale",
		_base_scale * Vector3(0.85, 1.18, 0.85), 0.10).set_trans(Tween.TRANS_EXPO)
	_attack_tween.tween_callback(func():
		_attack_window = true
		attack_impact.emit(serial)
		anim_event.emit("swing"))
	# Strike: slam forward
	_attack_tween.tween_property(visual_root, "scale",
		_base_scale * Vector3(1.22, 0.82, 1.22), 0.08).set_trans(Tween.TRANS_BACK)
	_attack_tween.tween_callback(func():
		_attack_window = false
		_in_recovery = true)
	# Recover
	_attack_tween.tween_property(visual_root, "scale", _base_scale, 0.25) \
		.set_trans(Tween.TRANS_SPRING)
	_attack_tween.tween_callback(func():
		_in_attack   = false
		_in_recovery = false)

func cancel_recovery() -> void:
	if not _in_recovery:
		return
	if _attack_tween != null and _attack_tween.is_valid():
		_attack_tween.kill()
	_in_attack   = false
	_in_recovery = false
	_attack_window = false
	if visual_root != null:
		var tw := visual_root.create_tween()
		tw.tween_property(visual_root, "scale", _base_scale, 0.12).set_trans(Tween.TRANS_SPRING)

# ─────────────────────────────────────────────────────────────────────────────
# Hit react
# ─────────────────────────────────────────────────────────────────────────────

func trigger_hit() -> void:
	if visual_root == null or _authored_rig:
		return
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_hit_tween = visual_root.create_tween()
	_hit_tween.set_parallel(true)
	# Flash-scale flinch
	_hit_tween.tween_property(visual_root, "scale",
		_base_scale * Vector3(1.12, 0.90, 1.12), 0.06).set_trans(Tween.TRANS_EXPO)
	_hit_tween.chain().tween_property(visual_root, "scale",
		_base_scale, 0.18).set_trans(Tween.TRANS_SPRING)
	# Drive hit-flash shader parameter on all body meshes
	_flash_body_material(1.0, 0.25)

func _flash_body_material(intensity: float, duration: float) -> void:
	if visual_root == null:
		return
	for child in visual_root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var mat := mi.material_override as ShaderMaterial
		if mat == null:
			continue
		var tw := mi.create_tween()
		tw.tween_method(func(v): mat.set_shader_parameter("flash_intensity", v),
			intensity, 0.0, duration)

# ─────────────────────────────────────────────────────────────────────────────
# Death
# ─────────────────────────────────────────────────────────────────────────────

func trigger_death(knockback_dir: float = -1.0) -> void:
	if visual_root == null:
		return
	var dir_sign := 1.0 if knockback_dir >= 0.0 else -1.0
	var tw := visual_root.create_tween()
	tw.tween_property(visual_root, "rotation",
		Vector3(dir_sign * PI * 0.5, visual_root.rotation.y, 0.0), 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(visual_root, "scale",
		_base_scale * Vector3(1.0, 0.0, 1.0), 0.35) \
		.set_trans(Tween.TRANS_EXPO)
	anim_event.emit("death")

# ─────────────────────────────────────────────────────────────────────────────
# Direction-change micro-spin (Hushling orbit reversal)
# ─────────────────────────────────────────────────────────────────────────────

func trigger_spin(direction: int) -> void:
	if visual_root == null or _authored_rig:
		return
	var tw := visual_root.create_tween()
	tw.tween_property(visual_root, "scale",
		_base_scale * Vector3(0.78, 1.22, 0.78), 0.08).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(visual_root, "scale", _base_scale, 0.22).set_trans(Tween.TRANS_SPRING)
	tw.parallel().tween_property(visual_root, "rotation:y",
		visual_root.rotation.y + direction * PI, 0.22).set_trans(Tween.TRANS_CUBIC)

# ─────────────────────────────────────────────────────────────────────────────
# Landing
# ─────────────────────────────────────────────────────────────────────────────

func notify_land(hard: float) -> void:
	if visual_root == null or _authored_rig:
		return
	var squash := 1.0 + hard * 0.35
	var tw := visual_root.create_tween()
	tw.tween_property(visual_root, "scale",
		_base_scale * Vector3(squash, 1.0 - hard * 0.28, squash), 0.10) \
		.set_trans(Tween.TRANS_EXPO)
	tw.tween_property(visual_root, "scale", _base_scale, 0.28).set_trans(Tween.TRANS_SPRING)
	if hard > 0.5:
		footfall.emit(hard)
		anim_event.emit("land_hard")

# ─────────────────────────────────────────────────────────────────────────────
# Procedural idle + locomotion (runs in _process when no authored rig)
# ─────────────────────────────────────────────────────────────────────────────

func _apply_idle_breath(delta: float) -> void:
	if _in_attack or _move_ratio > 0.05 or _airborne:
		return
	var breath := 1.0 + sin(_t * 1.8) * 0.018
	if visual_root != null:
		visual_root.scale = _base_scale * Vector3(1.0 / breath, breath, 1.0 / breath)

func _apply_locomotion_squash(delta: float) -> void:
	if not _in_attack and _move_ratio > 0.05:
		# Running hop: alternate squash on a per-step timer
		var step := sin(_t * 8.5 * _move_ratio) * 0.06 * _move_ratio
		if visual_root != null:
			visual_root.scale = _base_scale * Vector3(
				1.0 + step * 0.5 + _gait_ramp * 0.06,
				1.0 - step,
				1.0 + step * 0.5)
		if abs(step) > 0.055 and absf(sin(_t * 8.5 * _move_ratio - PI * 0.5)) < 0.1:
			anim_event.emit("footstep")
