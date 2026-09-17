extends EntityAnimator
class_name ArticulatedBossAnimator

## Shared animator for the procedural boss family. EntityAnimator owns the
## established attack clock and LOD behavior; this layer adds extra limb,
## wing, weapon, and roll motion for boss-specific silhouettes.

@export var wing_l: Node3D
@export var wing_r: Node3D
@export var hand_l: Node3D
@export var hand_r: Node3D
@export var weapon_l: Node3D
@export var weapon_r: Node3D

var boss_can_fly := false
var boss_can_roll := false
var boss_limb_style := "default"
var authored_bridge: AnimTreeBridge = null
var _skill_kind := ""
var _base_wing_l := Vector3.ZERO
var _base_wing_r := Vector3.ZERO
var _base_hand_l := Vector3.ZERO
var _base_hand_r := Vector3.ZERO
var _base_weapon_l := Vector3.ZERO
var _base_weapon_r := Vector3.ZERO
var _identity_parts: Array[Node3D] = []
var _identity_base_rot: Dictionary = {}
var _identity_base_pos: Dictionary = {}

func configure_rig(root: Node3D, can_fly: bool, can_roll: bool,
		limb_style: String) -> void:
	visual_root = root
	torso = root.get_node_or_null("Body") as Node3D
	head = root.get_node_or_null("Head") as Node3D
	arm_l = root.get_node_or_null("ArmL") as Node3D
	arm_r = root.get_node_or_null("ArmR") as Node3D
	forearm_l = root.get_node_or_null("ArmL/ForearmL") as Node3D
	forearm_r = root.get_node_or_null("ArmR/ForearmR") as Node3D
	hand_l = root.get_node_or_null("ArmL/ForearmL/HandL") as Node3D
	hand_r = root.get_node_or_null("ArmR/ForearmR/HandR") as Node3D
	leg_l = root.get_node_or_null("LegL") as Node3D
	leg_r = root.get_node_or_null("LegR") as Node3D
	foot_l = root.get_node_or_null("LegL/FootL") as Node3D
	foot_r = root.get_node_or_null("LegR/FootR") as Node3D
	wing_l = root.get_node_or_null("WingL") as Node3D
	wing_r = root.get_node_or_null("WingR") as Node3D
	weapon_l = root.get_node_or_null("ArmL/ForearmL/HandL/WeaponL") as Node3D
	weapon_r = root.get_node_or_null("ArmR/ForearmR/HandR/WeaponR") as Node3D
	boss_can_fly = can_fly
	boss_can_roll = can_roll
	boss_limb_style = limb_style
	_capture_pose()
	_capture_identity_parts(root)

func configure_authored_bridge(bridge: AnimTreeBridge, skill_ids: Array) -> void:
	authored_bridge = bridge
	if authored_bridge == null:
		return
	for skill_value in skill_ids:
		var skill_id := str(skill_value)
		if not skill_id.is_empty():
			authored_bridge.register_skill_alias(skill_id, "BOSS_%s" % skill_id)
	authored_bridge.register_skill_alias("phase_shift", "BOSS_PhaseShift")
	if authored_bridge.has_cue("idle"):
		authored_bridge.play_cue("idle", 0.0, true)

func set_authored_movement(state: String) -> void:
	if authored_bridge == null or not authored_bridge.is_active():
		return
	var cue := "run" if state == "move" else ("run" if state == "fly" else "idle")
	authored_bridge.play_cue(cue, 0.16, false)

func _capture_pose() -> void:
	_base_visual_pos = visual_root.position if visual_root != null else Vector3.ZERO
	_base_visual_scale = visual_root.scale if visual_root != null else Vector3.ONE
	_base_arm_l_rot = arm_l.rotation if arm_l != null else Vector3.ZERO
	_base_arm_r_rot = arm_r.rotation if arm_r != null else Vector3.ZERO
	_base_forearm_l_rot = forearm_l.rotation if forearm_l != null else Vector3.ZERO
	_base_forearm_r_rot = forearm_r.rotation if forearm_r != null else Vector3.ZERO
	_base_wing_l = wing_l.rotation if wing_l != null else Vector3.ZERO
	_base_wing_r = wing_r.rotation if wing_r != null else Vector3.ZERO
	_base_hand_l = hand_l.rotation if hand_l != null else Vector3.ZERO
	_base_hand_r = hand_r.rotation if hand_r != null else Vector3.ZERO
	_base_weapon_l = weapon_l.rotation if weapon_l != null else Vector3.ZERO
	_base_weapon_r = weapon_r.rotation if weapon_r != null else Vector3.ZERO

func _capture_identity_parts(root: Node3D) -> void:
	_identity_parts.clear()
	_identity_base_rot.clear()
	_identity_base_pos.clear()
	if root == null:
		return
	var tokens: Array[String] = []
	match boss_limb_style:
		"spider_needles":
			tokens = ["Needle", "Web", "Claw"]
		"jaw_wheel":
			tokens = ["FogWheel", "Muzzle", "Claw"]
		"magma_fists":
			tokens = ["MagmaFist", "Claw", "Core"]
		"bell_caster":
			tokens = ["AshBell", "Claw", "Core"]
		"floating_tide":
			tokens = ["TideOrb", "Focus", "Claw"]
		"leviathan_wings":
			tokens = ["Wing", "MoonHalo", "Weapon", "Claw"]
		_:
			tokens = ["ShoulderPlate", "RootBlade", "Weapon", "Claw"]
	for child_value in root.find_children("*", "Node3D", true, false):
		var child := child_value as Node3D
		if child == null:
			continue
		var child_name := str(child.name)
		if not tokens.any(func(token: String) -> bool: return child_name.contains(token)):
			continue
		_identity_parts.append(child)
		_identity_base_rot[child] = child.rotation
		_identity_base_pos[child] = child.position

func trigger_skill(skill_kind: String) -> void:
	_skill_kind = skill_kind
	trigger_skill_with_id(skill_kind, "")

func trigger_skill_with_id(skill_kind: String, skill_id: String) -> void:
	_skill_kind = skill_kind
	if authored_bridge != null and authored_bridge.is_active():
		var fallback := "cast"
		match skill_kind:
			"sword", "slam": fallback = "heavy"
			"roll": fallback = "dodge"
			"regen": fallback = "buff"
		if authored_bridge.play_skill(skill_id, fallback, 0.05, true) \
				and not skill_id.is_empty():
			# The imported clip owns the visible limb motion. Parent state and
			# procedural timing still continue to drive the gameplay contract.
			super.trigger_attack(fallback)
			return
	match skill_kind:
		"sword":
			trigger_attack("heavy")
		"roll":
			trigger_attack("spin")
		"regen", "cast", "projectile":
			trigger_attack("hurl")
		"slam":
			trigger_attack("heavy")
		"burrow":
			trigger_attack("slam")
		_: 
			trigger_attack("enemy")

func trigger_attack(kind: String = "") -> void:
	super.trigger_attack(kind)
	if authored_bridge != null and authored_bridge.is_active():
		var cue := "heavy" if kind == "heavy" else ("dodge" if kind == "spin" else "light_1")
		authored_bridge.play_cue(cue, 0.05, true)

func trigger_hit() -> void:
	super.trigger_hit()
	if authored_bridge != null and authored_bridge.is_active():
		authored_bridge.play_cue("hit", 0.04, true)

func trigger_death(fall_dir: float = 1.0) -> void:
	super.trigger_death(fall_dir)
	if authored_bridge != null and authored_bridge.is_active():
		authored_bridge.play_cue("death", 0.04, true)

func _animate_biped(delta: float) -> void:
	super._animate_biped(delta)
	if visual_root == null:
		return
	# Flying silhouettes never look planted. Wings and body bob use the same
	# animator clock, while the gameplay body remains controlled by the boss.
	if boss_can_fly:
		var wing_wave := sin(_time * 3.2) * 0.16
		if wing_l != null and anim_state != AnimState.ATTACK:
			wing_l.rotation.z = _base_wing_l.z + wing_wave
		if wing_r != null and anim_state != AnimState.ATTACK:
			wing_r.rotation.z = _base_wing_r.z - wing_wave
		visual_root.position.y = _base_visual_pos.y + sin(_time * 2.0) * 0.08
	# The rolling boss rotates its silhouette while its CharacterBody3D moves.
	# The controller clears this state before reset/death, so no stale spin can
	# survive a failed encounter.
	if boss_can_roll and _skill_kind == "roll" and anim_state == AnimState.ATTACK:
		visual_root.rotation.z += delta * 12.0
	# Weapon tips trail the hands slightly, making the procedural limbs read as
	# connected equipment rather than independent primitive meshes.
	if weapon_l != null and anim_state != AnimState.ATTACK:
		weapon_l.rotation.z = lerpf(weapon_l.rotation.z, _base_weapon_l.z, delta * 5.0)
	if weapon_r != null and anim_state != AnimState.ATTACK:
		weapon_r.rotation.z = lerpf(weapon_r.rotation.z, _base_weapon_r.z, delta * 5.0)
	_animate_identity(delta, anim_state == AnimState.ATTACK or _in_recovery)

func _animate_identity(delta: float, acting: bool) -> void:
	if _identity_parts.is_empty():
		return
	# Decorative detail only: authored GLB clips remain the primary pose source
	# when mounted, while this bounded layer keeps the procedural fallback alive.
	var motion_scale := 0.32 if acting else 1.0
	for index in _identity_parts.size():
		var part := _identity_parts[index]
		if not is_instance_valid(part):
			continue
		var base_rot: Vector3 = _identity_base_rot.get(part, part.rotation)
		var base_pos: Vector3 = _identity_base_pos.get(part, part.position)
		var wave := sin(_time * 2.0 + float(index) * 0.67) * motion_scale
		if boss_limb_style == "floating_tide" and part.name.begins_with("TideOrb"):
			var orbit := _time * 0.72 + float(index) * 1.57
			part.position = base_pos + Vector3(cos(orbit) * 0.07,
				sin(orbit * 1.7) * 0.045, sin(orbit) * 0.07)
		elif boss_limb_style == "jaw_wheel" and part.name.contains("FogWheel"):
			part.rotation.y = base_rot.y + _time * 0.42
		elif boss_limb_style == "leviathan_wings" and part.name.contains("Wing"):
			part.rotation.z = base_rot.z + wave * 0.12
			part.rotation.x = base_rot.x + sin(_time * 1.6 + float(index)) * 0.06 * motion_scale
		elif boss_limb_style == "bell_caster" and part.name.contains("AshBell"):
			part.rotation.z = base_rot.z + wave * 0.08
		else:
			part.rotation.z = lerpf(part.rotation.z, base_rot.z + wave * 0.055,
				minf(delta * 5.0, 1.0))
		if part.name.contains("Claw") or part.name.contains("Weapon"):
			part.rotation.y = base_rot.y + sin(_time * 2.8 + float(index)) * 0.08 * motion_scale

	# Small elbow/wrist counter-rotation keeps hands visually connected during
	# the slower travel cycle without changing attack timings or hitboxes.
	if not _in_recovery:
		var counter := sin(_time * 2.4) * 0.035
		if hand_l != null:
			hand_l.rotation.y = _base_hand_l.y - counter
		if hand_r != null:
			hand_r.rotation.y = _base_hand_r.y + counter
		if forearm_l != null:
			forearm_l.rotation.z = lerpf(forearm_l.rotation.z,
				_base_forearm_l_rot.z - counter * 0.7, minf(delta * 5.0, 1.0))
		if forearm_r != null:
			forearm_r.rotation.z = lerpf(forearm_r.rotation.z,
				_base_forearm_r_rot.z + counter * 0.7, minf(delta * 5.0, 1.0))

func reset_to_idle() -> void:
	super.reset_to_idle()
	if authored_bridge != null:
		authored_bridge.stop()
	_skill_kind = ""
	if visual_root != null:
		visual_root.rotation = Vector3.ZERO
		visual_root.position = _base_visual_pos
	if wing_l != null:
		wing_l.rotation = _base_wing_l
	if wing_r != null:
		wing_r.rotation = _base_wing_r
	if hand_l != null:
		hand_l.rotation = _base_hand_l
	if hand_r != null:
		hand_r.rotation = _base_hand_r
	if weapon_l != null:
		weapon_l.rotation = _base_weapon_l
	if weapon_r != null:
		weapon_r.rotation = _base_weapon_r
	for part in _identity_parts:
		if not is_instance_valid(part):
			continue
		part.rotation = _identity_base_rot.get(part, part.rotation)
		part.position = _identity_base_pos.get(part, part.position)
