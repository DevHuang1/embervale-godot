extends BossBase
class_name ArticulatedBoss

const ROSTER := preload("res://scripts/systems/boss_roster_catalog.gd")
const PROJECTILE := preload("res://scripts/entities/boss_projectile.gd")
const ASSET_MANIFEST := preload("res://scripts/systems/boss_asset_manifest.gd")
const BOSS_VFX := preload("res://scripts/systems/boss_skill_vfx.gd")

## Shared playable controller for the canonical boss family. Authored V2 GLBs
## replace the procedural silhouette when present; the latter remains a safe
## fallback while BossBase owns health, phases, rewards, and reset semantics.

signal skill_started(skill_id: String)
signal skill_impact(skill_id: String)
signal skill_finished(skill_id: String)
signal form_changed(form_index: int)
signal movement_state_changed(state: String)

@export var def_id := "whispergrove_root_harrow"

var _def: Dictionary = {}
var canonical_id := ""
var current_form := 1
var _skill_cursor := 0
var _roll_time_left := 0.0
var _roll_direction := Vector3.ZERO
var _roll_speed := 10.0
var _movement_state := "idle"
var _dynamic_materials: Array[StandardMaterial3D] = []
var _muzzle_points: Array[Node3D] = []

func _ready() -> void:
	_def = ROSTER.definition_for(def_id)
	canonical_id = ROSTER.canonical_id_for(def_id)
	if _def.is_empty():
		push_error("ArticulatedBoss: unknown def_id '%s'" % def_id)
		return
	max_hp = int(_def.get("hp", 500))
	hp = max_hp
	base_atk = int(_def.get("atk", 12))
	diamond_reward = int(_def.get("diamond_reward", 3))
	move_speed = float(_def.get("speed", 3.5)) \
		* ROSTER.BOSS_TRAVEL_SPEED_MULTIPLIER
	arena_radius = 20.0
	authored_model_profile = ASSET_MANIFEST.model_profile_for(canonical_id)
	if authored_model_profile.is_empty():
		authored_model_profile = "procedural_%s" % canonical_id
	authored_model_mounted = false
	sfx_profile = str(_def.get("sfx_profile", "vanilla"))
	var scale_value := float(_def.get("scale", 1.0))
	phase_thresholds = _phase_thresholds_for(int(_def.get("form_count", 1)))
	stage_armor = _stage_array(_def.get("armor_profile", [0, 3, 5, 8]), 0)
	stage_damage_mult = [1.0, 1.15, 1.30, 1.50]
	stage_scale_mult = [1.0, 1.04, 1.09, 1.16]
	stage_tints = _stage_tints(_def.get("palette", []))
	var regen: Dictionary = _def.get("regen", {})
	mend_max_uses = int(regen.get("uses", 0))
	mend_uses_left = mend_max_uses
	mend_amount_pct = float(regen.get("amount_pct", 0.08))
	mend_below_pct = float(regen.get("below_pct", 0.5))
	mend_cooldown = float(regen.get("cooldown", 22.0))
	var visual := get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.scale = Vector3.ONE * scale_value
		_build_articulated_visual(visual)
	var articulated_animator := animator as ArticulatedBossAnimator
	if articulated_animator != null and visual != null:
		articulated_animator.configure_rig(visual,
			bool(_def.get("can_fly", false)), bool(_def.get("can_roll", false)),
			str(_def.get("limb_style", "default")))
	super._ready()
	_bind_authored_visual()
	_apply_collision_profile()
	_refresh_boss_bar()

func _exit_tree() -> void:
	# Skill visuals are owned by this encounter context; scene teardown must
	# cancel them even when the host exits without a gameplay reset.
	CombatFx.cancel_context_effects(self)

func _bind_authored_visual() -> void:
	if not authored_model_mounted:
		return
	var authored_rig := get_node_or_null("Visual/AuthoredRig") as Node3D
	if authored_rig != null:
		# Damage flash, stage tint, wear, and customization follow the
		# imported surfaces the player actually sees once the GLB mounts.
		adopt_authored_surfaces(authored_rig)
	CharacterRigLoader.bind_sockets(self, ASSET_MANIFEST.socket_map_for(canonical_id))
	var bridge := get_meta("anim_bridge", null) as AnimTreeBridge
	var authored_animator := animator as ArticulatedBossAnimator
	if bridge == null or authored_animator == null:
		return
	var skill_ids: Array = []
	for skill_value in _def.get("skills", []):
		if skill_value is Dictionary:
			skill_ids.append(str((skill_value as Dictionary).get("id", "")))
	authored_animator.configure_authored_bridge(bridge, skill_ids)
	_muzzle_points.clear()
	for socket_name in ["SOCKET_VFX_Muzzle_L", "SOCKET_VFX_Muzzle_R"]:
		var socket := find_child(socket_name, true, false) as Node3D
		if socket != null:
			_muzzle_points.append(socket)

func _phase_thresholds_for(form_count: int) -> Array:
	match clampi(form_count, 1, 4):
		1:
			return [0.0, 0.0, 0.0]
		2:
			return [0.55, 0.0, 0.0]
		3:
			return [0.67, 0.34, 0.0]
		_:
			return [0.75, 0.50, 0.25]

func _stage_array(value: Variant, fallback: int) -> Array:
	var source: Array = value if value is Array else []
	var result: Array = []
	for index in 4:
		result.append(int(source[index]) if index < source.size() else fallback)
	return result

func _stage_tints(value: Variant) -> Array:
	var palette: Array = value if value is Array else []
	var accent: Color = palette[1] if palette.size() > 1 and palette[1] is Color \
		else Color(1.0, 0.45, 0.12)
	return [accent, accent.lightened(0.10), accent.lightened(0.20), accent.lightened(0.32)]

func _apply_collision_profile() -> void:
	var scale_value := float(_def.get("scale", 1.0))
	var root_shape := get_node_or_null("CollisionShape") as CollisionShape3D
	if root_shape != null:
		root_shape.scale = Vector3.ONE * scale_value
	var hit_shape := get_node_or_null("Hitbox/HitboxShape") as CollisionShape3D
	if hit_shape != null:
		hit_shape.scale = Vector3.ONE * scale_value

func _setup_attacks() -> void:
	super._setup_attacks()
	for skill_value in _def.get("skills", []):
		if skill_value is Dictionary:
			attack_cooldowns["skill_%s" % str(skill_value.get("id", ""))] = 0.0

func _physics_process(delta: float) -> void:
	if is_defeated:
		return
	_update_timers(delta)
	_check_phase_transition()
	_update_ai(delta)
	move_and_slide()
	_keep_inside_arena()

func _update_ai(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(player):
		return
	var articulated_animator := animator as ArticulatedBossAnimator
	var to_player := global_position.direction_to(player.global_position)
	var flat_to_player := Vector3(to_player.x, 0.0, to_player.z)
	if flat_to_player.length_squared() < 0.001:
		flat_to_player = -global_transform.basis.z
	flat_to_player = flat_to_player.normalized()
	var distance := global_position.distance_to(player.global_position)
	var movement_mode := str(_def.get("movement_mode", "chase"))
	var can_chase := bool(_def.get("chase_player", true))
	var is_flying := bool(_def.get("can_fly", false))
	var status_speed := 1.0
	if elemental_status != null and elemental_status.has_method("movement_multiplier"):
		status_speed = float(elemental_status.movement_multiplier())
	if _roll_time_left > 0.0:
		_roll_time_left = maxf(0.0, _roll_time_left - delta)
		velocity = _roll_direction * _roll_speed
		velocity.y = 0.0
		if _roll_time_left <= 0.0:
			velocity = Vector3.ZERO
	elif can_chase and movement_mode not in ["stationary", "fly_stationary"] \
			and distance > float(_def.get("attack_range", 4.0)) * 0.72:
		var speed := move_speed * status_speed
		var travel_direction := flat_to_player
		if movement_mode == "fly_chase":
			# The Leviathan closes distance on a shallow orbit so its aerial
			# silhouette keeps changing angle instead of beelining like a ground
			# bruiser. The player remains the authoritative target.
			var orbit_direction := Vector3(-flat_to_player.z, 0.0, flat_to_player.x)
			travel_direction = flat_to_player.lerp(orbit_direction, 0.48).normalized()
		velocity.x = lerpf(velocity.x, travel_direction.x * speed, minf(delta * 5.0, 1.0))
		velocity.z = lerpf(velocity.z, travel_direction.z * speed, minf(delta * 5.0, 1.0))
	else:
		velocity.x = lerpf(velocity.x, 0.0, minf(delta * 7.0, 1.0))
		velocity.z = lerpf(velocity.z, 0.0, minf(delta * 7.0, 1.0))
	if is_flying:
		var hover_height := 2.2 + 0.35 * float(stage_rank())
		var desired_y := encounter_origin.y + hover_height + sin(mechanics_timer * 1.8) * 0.35
		velocity.y = lerpf(velocity.y, (desired_y - global_position.y) * 2.0,
			minf(delta * 3.0, 1.0))
	else:
		velocity.y = 0.0
	if movement_mode != "stationary" and movement_mode != "fly_stationary":
		rotation.y = lerp_angle(rotation.y, atan2(flat_to_player.x, flat_to_player.z),
			minf(delta * 4.0, 1.0))
	var next_state := "fly" if is_flying else ("roll" if _roll_time_left > 0.0 else
		("move" if Vector2(velocity.x, velocity.z).length() > 0.25 else "idle"))
	if next_state != _movement_state:
		_movement_state = next_state
		movement_state_changed.emit(next_state)
		if articulated_animator != null:
			articulated_animator.set_authored_movement(next_state)
		if audio != null and audio.has_method("play_boss_skill_event") \
				and next_state in ["fly", "roll"]:
			audio.play_boss_skill_event(canonical_id, next_state, "movement",
				next_state, self)
	if articulated_animator != null:
		articulated_animator.set_move_ratio(clampf(
			Vector2(velocity.x, velocity.z).length() / maxf(move_speed, 0.1), 0.0, 1.0))
		articulated_animator.set_air_target(is_flying)
	_try_attacks(player, distance)

func _keep_inside_arena() -> void:
	var offset := global_position - encounter_origin
	offset.y = 0.0
	var limit := maxf(4.0, arena_radius - 2.0)
	if offset.length() <= limit:
		return
	var clamped := offset.normalized() * limit
	global_position.x = encounter_origin.x + clamped.x
	global_position.z = encounter_origin.z + clamped.z

func _try_attacks(player: Node3D, distance: float) -> void:
	if is_action_locked():
		return
	if _should_mend():
		_perform_mend()
		return
	var skills: Array = _def.get("skills", [])
	if not skills.is_empty():
		for attempt in skills.size():
			var index := (_skill_cursor + attempt) % skills.size()
			var skill := skills[index] as Dictionary
			if skill.is_empty() or str(skill.get("kind", "")) == "regen":
				continue
			if stage_rank() + 1 < int(skill.get("min_form", 0)) + 1:
				continue
			var skill_range := float(skill.get("range", _def.get("attack_range", 4.0)))
			var in_range := distance <= skill_range
			if not in_range and bool(_def.get("chase_player", true)):
				continue
			var cooldown_key := "skill_%s" % str(skill.get("id", ""))
			if float(attack_cooldowns.get(cooldown_key, 0.0)) > 0.0:
				continue
			_skill_cursor = (index + 1) % skills.size()
			_perform_skill(skill, player)
			return
	var basic_range := float(_def.get("attack_range", 4.0))
	if float(attack_cooldowns.get("basic", 0.0)) <= 0.0 and distance <= basic_range:
		_perform_basic_attack(player)

func _perform_basic_attack(player: Node3D) -> void:
	super._perform_basic_attack(player)
	if audio != null:
		audio.play_swing_stage(0)

func _perform_mend() -> void:
	var regen_skill := _regen_skill_definition()
	skill_started.emit("regen")
	var articulated_animator := animator as ArticulatedBossAnimator
	if articulated_animator != null:
		articulated_animator.trigger_skill_with_id("regen", str(regen_skill.get("id", "regen")))
	BOSS_VFX.start(self, regen_skill, global_position)
	if audio != null:
		if audio.has_method("play_boss_skill_event"):
			audio.play_boss_skill_event(canonical_id, "regen", "start", "regen", self)
		else:
			audio.play_skill_cast("heal_bloom")
	var generation := encounter_generation
	super._perform_mend()
	var timing := BossBase.attack_timing("mend")
	var impact_timer := get_tree().create_timer(float(timing.get("anticipation", 1.4)), false)
	impact_timer.timeout.connect(func() -> void:
		if generation == encounter_generation and not is_defeated:
			skill_impact.emit("regen")
			BOSS_VFX.impact(self, regen_skill, global_position)
			if audio != null and audio.has_method("play_boss_skill_event"):
				audio.play_boss_skill_event(canonical_id, "regen", "impact", "regen", self))
	var finish_timer := get_tree().create_timer(float(timing.get("total_lock", 1.85)), false)
	finish_timer.timeout.connect(func() -> void:
		if generation == encounter_generation and not is_defeated:
			skill_finished.emit("regen"))

func _perform_skill(skill: Dictionary, player: Node3D) -> void:
	var skill_id := str(skill.get("id", "boss_skill"))
	var cooldown_key := "skill_%s" % skill_id
	attack_cooldowns[cooldown_key] = float(skill.get("cooldown", 8.0))
	var timing := _skill_timing(skill)
	var anticipation := float(timing.get("anticipation", 0.6))
	var total_lock := float(timing.get("total_lock", anticipation + 0.5))
	var target := player.global_position if player != null else global_position
	var radius := float(skill.get("radius", 2.6))
	lock_action(total_lock)
	attack_telegraphed.emit(skill_id, radius, anticipation)
	skill_started.emit(skill_id)
	var color: Color = skill.get("color", _fx_tint())
	BOSS_VFX.start(self, skill, target)
	var articulated_animator := animator as ArticulatedBossAnimator
	if articulated_animator != null:
		articulated_animator.trigger_skill_with_id(
			str(skill.get("sfx", "cast")), skill_id)
	if audio != null:
		var skill_kind := str(skill.get("kind", "area"))
		if audio.has_method("play_boss_skill_event"):
			audio.play_boss_skill_event(canonical_id, skill_id, "start", skill_kind, self)
		else:
			audio.play_skill_cast(str(skill.get("sfx", "cast")))
	var generation := encounter_generation
	var impact_timer := get_tree().create_timer(anticipation, false)
	impact_timer.timeout.connect(_resolve_skill.bind(skill.duplicate(true), target, generation))
	var finish_timer := get_tree().create_timer(total_lock, false)
	finish_timer.timeout.connect(_finish_skill.bind(skill_id, generation))

func _skill_timing(skill: Dictionary) -> Dictionary:
	var anticipation := maxf(0.1, float(skill.get("anticipation", 0.6)))
	var active := maxf(0.08, float(skill.get("active", 0.2)))
	var recovery := maxf(0.12, float(skill.get("recovery", 0.35)))
	var roll_extra := float(skill.get("active", 0.0)) if str(skill.get("kind", "")) == "roll" else 0.0
	return {"anticipation": anticipation, "active": active, "recovery": recovery,
		"total_lock": anticipation + active + recovery + roll_extra}

func _resolve_skill(skill: Dictionary, target: Vector3, generation: int) -> void:
	if is_defeated or generation != encounter_generation or not is_inside_tree():
		return
	var skill_id := str(skill.get("id", "boss_skill"))
	var kind := str(skill.get("kind", "area"))
	var damage := maxi(1, int(round(float(skill.get("damage", effective_atk())) * stage_dmg_mult())))
	var radius := float(skill.get("radius", 2.6))
	var color: Color = skill.get("color", _fx_tint())
	skill_impact.emit(skill_id)
	BOSS_VFX.impact(self, skill, target)
	if audio != null:
		if audio.has_method("play_boss_skill_event"):
			audio.play_boss_skill_event(canonical_id, skill_id, "impact",
				str(skill.get("sfx", kind)), self)
		else:
			if kind == "sword":
				audio.play_slash()
			elif kind == "regen":
				audio.play_skill_release("heal_bloom")
			elif kind == "roll":
				audio.play_skill_release("aoe")
			else:
				audio.play_skill_release("explosion")
	match kind:
		"projectile":
			_spawn_projectile_pattern(skill, target, damage, color)
		"roll":
			_roll_direction = global_position.direction_to(target)
			_roll_direction.y = 0.0
			if _roll_direction.length_squared() < 0.001:
				_roll_direction = -global_transform.basis.z
			_roll_direction = _roll_direction.normalized()
			_roll_speed = clampf(float(skill.get("roll_speed", 10.0)), 4.0, 18.0)
			_roll_time_left = maxf(0.25, float(skill.get("active", 0.9)))
			CombatFx.spawn_vibrant_trail(self, global_position,
				global_position + _roll_direction * 8.0, color, color.lightened(0.35), 6)
			var roll_timer := get_tree().create_timer(_roll_time_left, false)
			roll_timer.timeout.connect(_finish_roll.bind(skill, generation))
		"sword":
			var forward := -global_transform.basis.z
			var center := global_position + forward * minf(radius * 0.7, 2.8)
			_deal_area_damage(center, radius, damage)
			CombatFx.spawn_shockwave(self, center, radius, color, 0.42)
			_shake_camera(0.24)
		_:
			var center := target if bool(_def.get("chase_player", true)) else target
			_deal_area_damage(center, radius, damage)
			CombatFx.spawn_shockwave(self, center, radius, color, 0.5)
			_shake_camera(0.28 if float(_def.get("flash_level", 0.0)) < 0.8 else 0.38)

func _spawn_projectile_pattern(skill: Dictionary, target: Vector3,
		damage: int, color: Color) -> void:
	var count := clampi(int(skill.get("projectile_count", 1)), 1, 8)
	var spread := clampf(float(skill.get("spread", 0.0)), 0.0, 1.2)
	var origin := _muzzle_position()
	var direction := origin.direction_to(target)
	if direction.length_squared() < 0.001:
		direction = -global_transform.basis.z
	for index in count:
		var centered := float(index) - float(count - 1) * 0.5
		var shot_direction := direction.rotated(Vector3.UP, centered * spread)
		var destination := origin + shot_direction * 26.0
		PROJECTILE.spawn(get_parent(), self, origin, destination, damage, color,
			str(skill.get("element", "")), 10.0, 4.0,
			str(skill.get("id", "projectile")), BOSS_VFX.family_for(skill))
	CombatFx.spawn_burst(self, origin, color, 10, 5.0, 0.34, 0.16)

func _muzzle_position() -> Vector3:
	_muzzle_points = _muzzle_points.filter(func(point: Node3D) -> bool:
		return is_instance_valid(point))
	if not _muzzle_points.is_empty():
		var point := _muzzle_points[mini(_skill_cursor, _muzzle_points.size() - 1)]
		return point.global_position
	return global_position + Vector3.UP * 2.0 + -global_transform.basis.z * 1.2

func _finish_roll(skill: Dictionary, generation: int) -> void:
	if generation != encounter_generation or is_defeated:
		return
	_roll_time_left = 0.0
	_roll_speed = 10.0
	velocity = Vector3.ZERO
	_deal_area_damage(global_position, float(skill.get("radius", 2.8)),
		maxi(1, int(round(float(skill.get("damage", 20)) * stage_dmg_mult()))))
	CombatFx.spawn_shockwave(self, global_position, float(skill.get("radius", 2.8)),
		 skill.get("color", _fx_tint()), 0.45)
	_shake_camera(0.32)

func _finish_skill(skill_id: String, generation: int) -> void:
	if generation != encounter_generation or is_defeated:
		return
	skill_finished.emit(skill_id)
	var articulated_animator := animator as ArticulatedBossAnimator
	if articulated_animator != null:
		articulated_animator.set_authored_movement(_movement_state)

func _current_skill() -> Dictionary:
	var skills: Array = _def.get("skills", [])
	if skills.is_empty():
		return {}
	return skills[clampi(_skill_cursor, 0, skills.size() - 1)] as Dictionary

func _regen_skill_definition() -> Dictionary:
	for skill_value in _def.get("skills", []):
		if skill_value is Dictionary and str((skill_value as Dictionary).get("kind", "")) == "regen":
			return (skill_value as Dictionary).duplicate(true)
	return {"id": "regen", "kind": "regen", "radius": 3.2,
		"anticipation": 1.4, "active": 0.25, "color": _fx_tint(),
		"vfx_family": "boss_regen_aura"}

func _fx_tint() -> Color:
	var palette: Array = _def.get("palette", [])
	return palette[1] if palette.size() > 1 and palette[1] is Color else Color(1, 0.45, 0.12)

func _on_phase_transition() -> void:
	super._on_phase_transition()
	current_form = mini(stage_rank() + 1, int(_def.get("form_count", 1)))
	form_changed.emit(current_form)
	var articulated_animator := animator as ArticulatedBossAnimator
	if articulated_animator != null:
		articulated_animator.trigger_skill_with_id("cast", "phase_shift")
	if audio != null:
		audio.play_skill_cast("cast")
	CombatFx.spawn_pillar(self, global_position, 3.2,
		 stage_tints[stage_rank()], 0.7, 1.0)

func _spawn_rewards() -> void:
	if is_practice:
		return
	var rewards: Dictionary = _def.get("rewards", {})
	game_state.grant_xp(int(rewards.get("xp", 200)))
	var materials: Dictionary = rewards.get("materials", {})
	for material_id in materials:
		game_state.add_material(str(material_id), int(materials[material_id]))
	if was_first_kill:
		var first_materials: Dictionary = rewards.get("first_kill_materials", {})
		for material_id in first_materials:
			game_state.add_material(str(material_id), int(first_materials[material_id]))
	var loot: Dictionary = rewards.get("loot", {})
	for item_id in loot:
		game_state.add_loot(str(item_id), int(loot[item_id]),
			"%s essence seeps into the satchel." % str(_def.get("name", "Boss")).capitalize())
	var weapon: Dictionary = rewards.get("weapon", {})
	if not weapon.is_empty():
		game_state.add_weapon(weapon.duplicate(true), false,
			"%s's trophy hums with realm power." % str(_def.get("name", "Boss")))

func _boss_key() -> String:
	return ROSTER.gameplay_key_for(canonical_id)

func apply_customization(c: BossCustomization) -> void:
	super.apply_customization(c)
	if c == null:
		return
	for material in _dynamic_materials:
		if material == null or not is_instance_valid(material):
			continue
		if c.palette.size() >= 1:
			material.albedo_color = c.palette[0]
		if c.palette.size() >= 2:
			material.emission = c.palette[1]

func reset_encounter() -> void:
	CombatFx.cancel_context_effects(self)
	for projectile in get_tree().get_nodes_in_group(PROJECTILE.PROJECTILE_GROUP):
		if projectile is BossProjectile and projectile.owner_boss == self:
			(projectile as BossProjectile).queue_free()
	_roll_time_left = 0.0
	_roll_direction = Vector3.ZERO
	_roll_speed = 10.0
	current_form = 1
	_movement_state = "idle"
	super.reset_encounter()
	var visual := get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.scale = Vector3.ONE * float(_def.get("scale", 1.0))
	var palette: Array = _def.get("palette", [])
	var base_tint: Color = palette[1] if palette.size() > 1 else _fx_tint()
	if customization != null and customization.palette.size() > 1:
		base_tint = customization.palette[1]
	if body != null and body.material_override is ShaderMaterial:
		(body.material_override as ShaderMaterial).set_shader_parameter(
			"emissive_color", base_tint)
	set_surface_tint(base_tint)
	if _boss_core_mat != null:
		_boss_core_mat.emission = base_tint
	form_changed.emit(current_form)
	movement_state_changed.emit("idle")

## === Procedural visual authoring ===

func _build_articulated_visual(visual: Node3D) -> void:
	var palette: Array = _def.get("palette", [])
	var base_color: Color = palette[0] if palette.size() > 0 else Color(0.16, 0.20, 0.15)
	var accent: Color = palette[1] if palette.size() > 1 else Color(0.9, 0.35, 0.1)
	var glow: Color = palette[2] if palette.size() > 2 else accent.lightened(0.25)
	var body_material := _material(base_color, accent, 0.82)
	var armor_material := _material(base_color.lightened(0.12), glow, 0.9)
	var glow_material := _material(accent, glow, 0.48)
	_dynamic_materials.append(body_material)
	_dynamic_materials.append(armor_material)
	_dynamic_materials.append(glow_material)
	var body_height := float(_def.get("body_height", 4.0))
	var body_width := float(_def.get("body_width", 1.6))
	if body != null:
		body.position = Vector3(0.0, body_height * 0.50, 0.0)
		body.scale = Vector3(body_width, body_height / 3.0, body_width * 0.82)
		# BossBase.take_damage() owns the hit-flash shader parameter on the
		# shared entity_boss material. Keep that ShaderMaterial on the gameplay
		# body and use the generated StandardMaterial3D on the articulated parts.
		# Replacing it here would make damage feedback call an invalid shader
		# parameter and would also break phase tinting.
		if body.material_override == null:
			body.material_override = load("res://assets/materials/entity_boss.tres")
	var head := _node(visual, "Head", Vector3(0.0, body_height + 0.45, 0.0))
	_add_mesh(head, "HeadShell", _sphere(body_width * 0.62, 12, 8),
		Vector3.ZERO, armor_material)
	_add_mesh(head, "CoreEye", _sphere(body_width * 0.18, 10, 6),
		Vector3(0.0, -0.03, -body_width * 0.52), glow_material)
	_build_arms(visual, body_height, body_width, body_material, armor_material, glow_material)
	_build_legs(visual, body_width, body_material, armor_material)
	if bool(_def.get("can_fly", false)):
		_build_wings(visual, body_height, body_width, armor_material, glow_material)
	_build_identity(visual, body_height, body_width, armor_material, glow_material)

func _build_arms(visual: Node3D, body_height: float, body_width: float,
		body_material: Material, armor_material: Material, glow_material: Material) -> void:
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0.0 else "R"
		var shoulder := _node(visual, "Arm%s" % suffix,
			Vector3(side * (body_width + 0.42), body_height * 0.78, 0.0))
		shoulder.rotation.z = -side * 0.16
		_add_mesh(shoulder, "UpperArm%s" % suffix, _capsule(0.34, 1.55),
			Vector3(0.0, -0.70, 0.0), body_material)
		var forearm := _node(shoulder, "Forearm%s" % suffix, Vector3(0.0, -1.34, 0.0))
		_add_mesh(forearm, "ForearmMesh%s" % suffix, _capsule(0.30, 1.30),
			Vector3(0.0, -0.58, -0.06), armor_material)
		var hand := _node(forearm, "Hand%s" % suffix, Vector3(0.0, -1.16, -0.08))
		_add_mesh(hand, "Claw%s" % suffix, _sphere(0.33, 10, 6),
			Vector3.ZERO, glow_material)
		var muzzle := _node(hand, "Muzzle%s" % suffix, Vector3(0.0, -0.28, -0.36))
		_muzzle_points.append(muzzle)
		var style := str(_def.get("limb_style", "default"))
		if style in ["thorn_blades", "greatsword_guard", "leviathan_wings"]:
			var weapon := _node(hand, "Weapon%s" % suffix, Vector3(0.0, -0.52, -0.05))
			_add_mesh(weapon, "Blade", _box(Vector3(0.16, 1.9, 0.34)),
				Vector3(0.0, -0.86, -0.10), glow_material)
			weapon.rotation.z = side * 0.18
		else:
			var weapon := _node(hand, "Weapon%s" % suffix, Vector3(0.0, -0.44, -0.12))
			_add_mesh(weapon, "Focus", _sphere(0.22, 8, 5), Vector3.ZERO, glow_material)

func _build_legs(visual: Node3D, body_width: float,
		body_material: Material, armor_material: Material) -> void:
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0.0 else "R"
		var leg := _node(visual, "Leg%s" % suffix,
			Vector3(side * body_width * 0.46, 0.95, 0.0))
		_add_mesh(leg, "Thigh%s" % suffix, _capsule(0.34, 1.55),
			Vector3(0.0, -0.62, 0.0), body_material)
		var foot := _node(leg, "Foot%s" % suffix, Vector3(0.0, -1.24, -0.12))
		_add_mesh(foot, "Boot%s" % suffix, _capsule(0.30, 0.85),
			Vector3(0.0, -0.35, -0.15), armor_material)

func _build_wings(visual: Node3D, body_height: float, body_width: float,
		armor_material: Material, glow_material: Material) -> void:
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0.0 else "R"
		var wing := _node(visual, "Wing%s" % suffix,
			Vector3(side * body_width * 1.1, body_height * 0.72, 0.18))
		wing.rotation.z = side * 0.32
		_add_mesh(wing, "WingBlade%s" % suffix, _box(Vector3(0.16, 2.6, 1.2)),
			Vector3(side * 0.62, 0.0, 0.0), armor_material)
		for feather in 3:
			_add_mesh(wing, "Feather%s_%d" % [suffix, feather], _box(Vector3(0.11, 1.6, 0.38)),
				Vector3(side * (0.35 + feather * 0.28), -0.42 + feather * 0.24, -0.18), glow_material)

func _build_identity(visual: Node3D, body_height: float, body_width: float,
		armor_material: Material, glow_material: Material) -> void:
	var style := str(_def.get("limb_style", "default"))
	match style:
		"spider_needles":
			for index in 4:
				var side := -1.0 if index % 2 == 0 else 1.0
				var leg := _node(visual, "NeedleLeg_%d" % index,
					Vector3(side * (body_width + 0.55), 1.6 - (index / 2) * 0.36,
						0.32 + (index / 2) * 0.22))
				leg.rotation.z = side * 0.62
				_add_mesh(leg, "Needle", _capsule(0.14, 2.2), Vector3(0, -0.9, 0), armor_material)
		"jaw_wheel":
			var wheel := _add_mesh(visual, "FogWheel", _torus(1.0, 1.22, 18, 5),
				Vector3(0.0, body_height * 0.52, 0.0), glow_material)
			wheel.rotation.x = PI * 0.5
		"bell_caster":
			_add_mesh(visual, "AshBell", _cylinder(0.72, 1.25, 12),
				Vector3(0.0, body_height + 0.9, 0.0), armor_material)
		"magma_fists":
			for side in [-1.0, 1.0]:
				_add_mesh(visual, "MagmaFist", _sphere(0.58, 10, 6),
					Vector3(side * (body_width + 0.76), 1.12, -0.42), glow_material)
		"floating_tide":
			for index in 4:
				var angle := TAU * float(index) / 4.0
				var orb := _add_mesh(visual, "TideOrb_%d" % index, _sphere(0.28, 8, 5),
					Vector3(cos(angle) * 1.55, body_height * 0.72 + sin(angle) * 0.42,
						sin(angle) * 1.55), glow_material)
				orb.set_meta("orbit_index", index)
		"leviathan_wings":
			var halo := _add_mesh(visual, "MoonHalo", _torus(1.15, 1.32, 24, 5),
				Vector3(0.0, body_height + 0.72, 0.0), glow_material)
			halo.rotation.x = PI * 0.5
		_:
			for side in [-1.0, 1.0]:
				_add_mesh(visual, "ShoulderPlate", _sphere(0.46, 10, 6),
					Vector3(side * (body_width + 0.22), body_height * 0.82, 0.0), armor_material)

func _node(parent: Node3D, node_name: String, position: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = position
	parent.add_child(node)
	return node

func _add_mesh(parent: Node3D, node_name: String, mesh: Mesh,
		position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance

func _material(base: Color, emission: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = base
	material.roughness = roughness
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 0.9
	return material

func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh

func _sphere(radius: float, radial_segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	return mesh

func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _cylinder(radius: float, height: float, segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.76
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	return mesh

func _torus(inner: float, outer: float, ring_segments: int, rings: int) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.ring_segments = ring_segments
	mesh.rings = rings
	return mesh
