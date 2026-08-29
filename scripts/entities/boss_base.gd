extends CharacterBody3D
class_name BossBase

## === Boss Base Class ===
## Multi-phase, mechanics, arena control, unique rewards

signal phase_changed(phase: int)
signal died

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var body: MeshInstance3D = $Visual/Body
@onready var animator: EntityAnimator = $Animator
@onready var hitbox: Area3D = $Hitbox
@onready var attack_areas: Node3D = $AttackAreas

enum BossPhase { PHASE_1, PHASE_2, PHASE_3, ENRAGE }

@export var max_hp: int = 500
@export var phase_thresholds: Array = [0.7, 0.3, 0.1]  # HP percentages for phase transitions
@export var base_atk: int = 12
@export var move_speed: float = 3.6
@export var arena_radius: float = 20.0

# Critical zone (exposed head/crown): strikes landing here hit harder
@export var crit_zone_center := Vector3(0, 3.3, 0)
@export var crit_zone_radius: float = 1.2
@export var crit_multiplier: float = 1.5

var hp: int = 500
var current_phase: BossPhase = BossPhase.PHASE_1
var phase_hp_thresholds: Array = []
var is_defeated: bool = false
var stun_timer: float = 0.0
var knockback_velocity: Vector3 = Vector3.ZERO
var attack_cooldowns: Dictionary = {}
var mechanics_timer: float = 0.0
var enrage_active: bool = false
var boss_bar_root = null
var boss_hp_bar: ProgressBar = null
var boss_phase_label: Label = null
var _boss_core: MeshInstance3D = null
var _boss_core_mat: StandardMaterial3D = null
var _enrage_ring: MeshInstance3D = null
var _menace_t := 0.0

# Player personalization (idol mesh, palette, one pool skill, SFX preset).
# Null = the untouched default boss.
var customization: BossCustomization = null
var sfx_profile: String = "vanilla"
var elemental_status: Node = null
# Practice respawns skip rewards and the scan-earn loop.
@export var is_practice: bool = false
## Diamonds granted on the FIRST kill of this boss per save (cosmetic only).
@export var diamond_reward: int = 0

func _ready() -> void:
	hp = max_hp
	var health_bar := preload("res://scripts/ui/enemy_health_bar.gd").new()
	health_bar.name = "EnemyHealthBar"
	add_child(health_bar)
	elemental_status = preload("res://scripts/systems/elemental_status.gd").new()
	elemental_status.name = "ElementalStatus"
	add_child(elemental_status)
	_calculate_phase_thresholds()
	
	collision_layer = 1 << 4  # Boss layer
	collision_mask = 1 << 0 | 1 << 5 | 1 << 6  # Player + Environment + Prop
	
	hitbox.area_entered.connect(_on_hitbox_entered)
	
	# Lumber footfalls drive shake, dust and the stomp cue
	if animator != null and animator.has_signal("footfall"):
		animator.footfall.connect(_on_footfall)
	
	# Initialize attack cooldowns
	_setup_attacks()

	# Boss UI
	_show_boss_health_bar()

	# Use a bounded wider frame for arena-scale attacks while preserving the
	# player-centered follow camera and mobile-safe spring-arm behavior.
	var camera_rig := get_parent().get_node_or_null("CameraRig")
	if camera_rig != null and camera_rig.has_method("set_boss_combat"):
		camera_rig.set_boss_combat(true, arena_radius)

	_build_boss_details()

	# Authored-model drop-in (silent no-op until assets/models/boss_*.glb ships)
	CharacterRigLoader.try_if_wire(self, "boss_matriarch")

## Menace pass: burning eyes and a molten chest core. Colors follow the
## body shader's current emissive so customization re-themes them too.
func _build_boss_details() -> void:
	var body_mat := body.material_override if body != null else null
	var glow := Color(1.0, 0.45, 0.12)
	if body_mat is ShaderMaterial:
		var c: Variant = body_mat.get_shader_parameter("emissive_color")
		if c is Color and (c as Color) != Color.BLACK:
			glow = c
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = glow
	eye_mat.emission_enabled = true
	eye_mat.emission = glow
	eye_mat.emission_energy_multiplier = 2.4
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.14
		em.height = 0.26
		eye.mesh = em
		eye.material_override = eye_mat
		eye.position = Vector3(0.42 * side, crit_zone_center.y - 0.55,
			crit_zone_center.z + 1.15)
		if visual_root_or_body_parent() != null:
			visual_root_or_body_parent().add_child(eye)
	if body != null:
		var core := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = 0.34
		cm.height = 0.6
		core.mesh = cm
		core.material_override = eye_mat
		core.position = Vector3(0, crit_zone_center.y - 1.7, 1.05)
		body.add_child(core)
		_boss_core = core
		_boss_core_mat = core.material_override as StandardMaterial3D
		var pulse := core.create_tween().set_loops()
		pulse.tween_property(core, "scale", Vector3.ONE * 1.25, 1.4) \
			.set_trans(Tween.TRANS_SINE)
		pulse.tween_property(core, "scale", Vector3.ONE * 0.9, 1.4) \
			.set_trans(Tween.TRANS_SINE)

	# Enrage floor ring: invisible until the rage phase flips it on
	var ring := MeshInstance3D.new()
	ring.name = "EnrageRing"
	var rm := TorusMesh.new()
	rm.inner_radius = maxf(2.0, arena_radius * 0.72)
	rm.outer_radius = arena_radius
	rm.ring_segments = 48
	rm.rings = 3
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.16, 0.08, 0.28)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.18, 0.06)
	ring_mat.emission_energy_multiplier = 0.45
	ring.mesh = rm
	ring.material_override = ring_mat
	ring.rotation.x = PI / 2.0
	ring.position = Vector3(0, 0.07, 0)
	ring.visible = false
	add_child(ring)
	_enrage_ring = ring

## Idle menace: the chest core breathes a slow heartbeat (faster in enrage)
## and the enrage floor ring fades in behind it when the rage phase lands.
func _process(delta: float) -> void:
	if is_defeated or not is_inside_tree():
		return
	_menace_t += delta
	if _boss_core_mat != null:
		var rate := 2.6 if enrage_active else 1.4
		var breathe := 0.86 + 0.14 * sin(_menace_t * rate) \
			+ 0.06 * sin(_menace_t * rate * 2.7)
		_boss_core_mat.emission_energy_multiplier = breathe * 2.4
	if _enrage_ring != null:
		var show := enrage_active and not is_defeated
		if _enrage_ring.visible != show:
			_enrage_ring.visible = show
		elif show:
			var s := 1.0 + 0.06 * sin(_menace_t * 1.7)
			_enrage_ring.scale = Vector3.ONE * s

func visual_root_or_body_parent() -> Node3D:
	var v := get_node_or_null("Visual")
	return v if v != null else null

var _foot_side := 1.0

func _on_footfall(strength: float) -> void:
	_foot_side *= -1.0
	_shake_camera(0.09 + 0.08 * strength)
	CombatFx.spawn_burst(self,
		global_position + Vector3(0.9 * _foot_side, 0.15, 0),
		Color(0.30, 0.22, 0.14, 0.7), 10, 2.6, 0.45, 0.16)
	if sfx_profile != "vanilla":
		audio.play_profile_cue(sfx_profile, "stomp")
	else:
		audio.play_boss_stomp(self)

func _calculate_phase_thresholds() -> void:
	phase_hp_thresholds = []
	for threshold in phase_thresholds:
		phase_hp_thresholds.append(int(max_hp * threshold))

func _setup_attacks() -> void:
	# Override in derived classes
	attack_cooldowns = {
		"basic": 0.0,
		"special_1": 0.0,
		"special_2": 0.0,
		"ultimate": 0.0
	}

func _physics_process(delta: float) -> void:
	if is_defeated:
		return
	
	_update_timers(delta)
	_check_phase_transition()
	_update_ai(delta)
	
	move_and_slide()

func _update_timers(delta: float) -> void:
	if stun_timer > 0:
		stun_timer -= delta
	
	for attack in attack_cooldowns:
		if attack_cooldowns[attack] > 0:
			attack_cooldowns[attack] -= delta
	
	mechanics_timer += delta

func _check_phase_transition() -> void:
	var hp_percent = hp / float(max_hp)
	var new_phase = current_phase
	
	if hp_percent <= phase_thresholds[2]:
		new_phase = BossPhase.ENRAGE
	elif hp_percent <= phase_thresholds[1]:
		new_phase = BossPhase.PHASE_3
	elif hp_percent <= phase_thresholds[0]:
		new_phase = BossPhase.PHASE_2
	else:
		new_phase = BossPhase.PHASE_1
	
	if new_phase != current_phase:
		current_phase = new_phase
		phase_changed.emit(int(current_phase))
		_on_phase_transition()

func _on_phase_transition() -> void:
	# Override in derived classes
	audio.play_victory()  # Phase transition sound (locked stinger)
	if sfx_profile != "vanilla":
		audio.play_profile_cue(sfx_profile, "stomp")
	print("Boss entered phase: %s" % current_phase)
	_evolve_for_phase(int(current_phase))
	if boss_phase_label:
		var phase_names = {
			BossPhase.PHASE_1: "PHASE 1",
			BossPhase.PHASE_2: "PHASE 2",
			BossPhase.PHASE_3: "PHASE 3",
			BossPhase.ENRAGE: "ENRAGE"
		}
		boss_phase_label.text = phase_names.get(current_phase, "PHASE ?")

func _update_ai(delta: float) -> void:
	if stun_timer > 0:
		return
	
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	# Basic movement toward player
	var to_player = (player.global_position - global_position).normalized()
	var dist = global_position.distance_to(player.global_position)
	
	var status_speed := 1.0
	if elemental_status != null and elemental_status.has_method("movement_multiplier"):
		status_speed = float(elemental_status.movement_multiplier())
	if dist > 3.0:
		velocity.x = lerp(velocity.x, to_player.x * move_speed * status_speed, 0.1)
		velocity.z = lerp(velocity.z, to_player.z * move_speed * status_speed, 0.1)
	else:
		velocity.x = lerp(velocity.x, 0.0, 0.2)
		velocity.z = lerp(velocity.z, 0.0, 0.2)
	
	# Face player
	var target_rot = atan2(to_player.x, to_player.z)
	rotation.y = lerp_angle(rotation.y, target_rot, 3.0 * delta)
	
	# Attack logic
	_try_attacks(player, dist)

func _try_attacks(player: Node3D, dist: float) -> void:
	# Basic attack
	if attack_cooldowns["basic"] <= 0 and dist < 4.0:
		_perform_basic_attack(player)
	
	# Phase-specific attacks
	match current_phase:
		BossPhase.PHASE_2:
			if attack_cooldowns["special_1"] <= 0 and dist < 8.0:
				_perform_special_1(player)
		BossPhase.PHASE_3:
			if attack_cooldowns["special_2"] <= 0 and dist < 12.0:
				_perform_special_2(player)
		BossPhase.ENRAGE:
			if attack_cooldowns["ultimate"] <= 0:
				_perform_ultimate(player)

func _perform_basic_attack(player: Node3D) -> void:
	attack_cooldowns["basic"] = 2.8
	# Melee slam animation + ember shockwave at impact
	if animator:
		animator.trigger_attack()
	var swing_pos: Vector3 = global_position + Vector3(0, 1.6, 0) + -global_transform.basis.z * 2.0
	CombatFx.spawn_burst(self, swing_pos, Color(1, 0.3, 0.2, 0.8), 18, 7.0, 0.35, 0.16)
	
	# Damage in area
	_deal_area_damage(global_position, 3.0, base_atk)
	_shake_camera(0.22)

func _shake_camera(intensity: float) -> void:
	var tier := "major" if intensity >= 0.45 else ("heavy" if intensity >= 0.25 else "medium")
	var base := float(ImpactDirector.FEEDBACK_TIERS[tier].shake)
	ImpactDirector.apply_feedback(self, tier, global_position + Vector3.UP * 1.0,
		Vector3.FORWARD, intensity / maxf(base, 0.001))

func _perform_special_1(player: Node3D) -> void:
	attack_cooldowns["special_1"] = 10.0
	# Override in derived classes

func _perform_special_2(player: Node3D) -> void:
	attack_cooldowns["special_2"] = 15.0
	# Override in derived classes

func _perform_ultimate(player: Node3D) -> void:
	attack_cooldowns["ultimate"] = 24.0
	# Override in derived classes - massive attack

func _deal_area_damage(center: Vector3, radius: float, damage: int) -> void:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(center, center)
	query.collision_mask = 1 << 0  # Player layer
	# Actually use sphere overlap
	var shape = SphereShape3D.new()
	shape.radius = radius
	var params = PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = 1 << 0
	var results = space_state.intersect_shape(params)
	
	for result in results:
		var collider = result.collider
		if collider and collider.has_method("take_damage"):
			# Ground eruptions whiff on airborne targets
			if collider.has_method("is_airborne") and collider.is_airborne():
				FloatingText.spawn_on_entity(collider, "miss", Color(0.8, 0.8, 0.7))
				continue
			collider.take_damage(damage, (collider.global_position - center).normalized())

func _on_hitbox_entered(area: Area3D) -> void:
	if area.is_in_group("player_attack"):
		# Guard: only a mid-swing/cast hero deals contact damage, so walking
		# past never hurts the boss — pressing Attack (or a skill) does.
		var hero := area.get_parent()
		if hero == null or not hero.has_method("get_attack_window") \
				or not hero.call("get_attack_window"):
			return
		var dmg = 0
		if hero.has_method("get_last_strike_damage"):
			dmg = hero.get_last_strike_damage()
		else:
			dmg = 10
		take_damage(dmg, area.global_position.direction_to(global_position))

func take_damage(amount: int, knockback_dir: Vector3, critical: bool = false) -> void:
	if is_defeated:
		return
	
	hp -= amount
	FloatingText.spawn_damage_on_entity(self, amount, critical)
	var health_bar := get_node_or_null("EnemyHealthBar")
	if health_bar != null and health_bar.has_method("notify_damage"):
		health_bar.notify_damage()
	
	# Visual
	if animator:
		animator.trigger_hit()
	var tween = create_tween()
	tween.tween_property(body, "material_override:shader_parameter/flash_intensity", 1.0, 0.05)
	tween.tween_property(body, "material_override:shader_parameter/flash_intensity", 0.0, 0.2)
	# Battle wear: bark dulls and darkens as the boss breaks down
	if body.material_override is ShaderMaterial:
		var ratio := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
		body.material_override.set_shader_parameter("hp_wear",
			clampf((0.45 - ratio) / 0.45, 0.0, 1.0) * 0.75)
	
	if boss_hp_bar:
		boss_hp_bar.value = max(hp, 0)
	
	knockback_velocity = knockback_dir * (amount * 3.0)
	
	if hp <= 0:
		die()

## === Cosmetic-first evolution: each phase visibly changes the body ===
## Heart core flares hotter, growth attachments sprout, and the transition
## lands with a shockwave + camera rumble (no combat-stat changes).
func _evolve_for_phase(phase: int) -> void:
	# Molten core burns brighter with every phase
	if _boss_core_mat != null:
		_boss_core_mat.emission_energy_multiplier = 2.4 + float(phase) * 1.2
	# Sprout growths at deterministic anchor points on the torso
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id() + phase * 131
	var growth_count := mini(phase + 1, 4)
	for i in growth_count:
		var pod := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.16 + 0.05 * float(i % 3)
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 10
		mesh.rings = 6
		pod.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.32, 0.16, 0.10)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.45, 0.12)
		mat.emission_energy_multiplier = 1.1
		pod.material_override = mat
		pod.position = Vector3(
			rng.randf_range(-0.7, 0.7),
			crit_zone_center.y - rng.randf_range(1.0, 2.2),
			rng.randf_range(-0.5, 0.9))
		body.add_child(pod)
		var pop := pod.create_tween()
		pod.scale = Vector3.ONE * 0.05
		pop.tween_property(pod, "scale", Vector3.ONE, 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Transition shockwave + rumble sells the shift physically
	CombatFx.spawn_shockwave(self, global_position - Vector3(0, 0.3, 0), 4.2,
		Color(1.0, 0.42, 0.15, 0.8), 0.8)
	CombatFx.spawn_impact_light(self, global_position,
		Color(1.0, 0.55, 0.25), 3.6, 6.0, 0.42)
	CombatFx.spawn_motes(self, global_position + Vector3(0, 1.2, 0),
		Color(1.0, 0.55, 0.25, 0.7), 18, 1.4, 1.1, 2.4)
	ImpactDirector.apply_feedback(self, "major", global_position + Vector3.UP * 1.4,
		Vector3.FORWARD, 1.0)

func die() -> void:
	var camera_rig := get_parent().get_node_or_null("CameraRig")
	if camera_rig != null and camera_rig.has_method("set_boss_combat"):
		camera_rig.set_boss_combat(false)
	is_defeated = true
	collision_layer = 0
	collision_mask = 0
	hitbox.monitoring = false
	for attack_area in attack_areas.get_children():
		if attack_area is Area3D:
			attack_area.monitoring = false
	
	_hide_boss_health_bar()
	
	# Death: physical collapse — ragdoll when the authored rig allows,
	# otherwise a heavy tumble corpse. Deferred: die() can fire inside a
	# physics callback where reparenting is illegal.
	if animator != null \
			and (animator.visual_root == null or not is_instance_valid(animator.visual_root)):
		animator.trigger_death(-1.0)
	else:
		_launch_death_physics.call_deferred()
	var tween = create_tween()
	tween.tween_interval(2.6)
	tween.tween_callback(_on_death_finished)
	
	# Crumbling bark groan under the locked victory sting
	audio.play_boss_death()
	audio.play_victory()
	var ws := get_node_or_null("/root/WorldState")
	if ws != null and ws.has_method("gust"):
		ws.gust(1.0)   # the grove recoils as the Matriarch falls

## Ragdoll-or-tumble for the boss body (deferred context).
func _launch_death_physics() -> void:
	var visual := animator.visual_root if animator != null else null
	if visual == null or not is_instance_valid(visual) or not is_inside_tree():
		return
	TumbleCorpse.max_corpses = maxi(_corpse_budget(), 2)
	var killer := get_tree().get_first_node_in_group("player")
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	if killer is Node3D:
		dir = global_position.direction_to((killer as Node3D).global_position)
		dir.y = 0.0
	var shove := dir * randf_range(4.0, 5.5) + Vector3.UP * randf_range(3.0, 4.0)
	if TumbleCorpse.try_ragdoll(visual, shove):
		return
	TumbleCorpse.launch(visual, shove, 3.4)

func _corpse_budget() -> int:
	var qs := get_node_or_null("/root/WorldState/QualityScaler")
	return qs.corpse_pool_size if qs != null else 6

func _on_death_finished() -> void:
	if not is_practice:
		game_state.earn_scan()
		if game_state.mark_boss_killed(_boss_key()) and diamond_reward > 0:
			var amount := diamond_reward + randi_range(0, 2)
			game_state.add_diamonds(amount,
				"💎 +%d diamonds — a glint from the old world remains." % amount)
	_spawn_rewards()
	died.emit()
	queue_free()

## Identity used for first-kill rewards; data-driven bosses (one shared
## script) override this so each def records its own first kill.
func _boss_key() -> String:
	var scr: Script = get_script()
	if scr != null and scr.resource_path != null:
		return str(scr.resource_path)
	return str(name)

func _spawn_rewards() -> void:
	if is_practice:
		return
	# Override in derived classes
	# Drop legendary weapon, massive XP, unique relic
	game_state.grant_xp(200)
	game_state.add_loot("ember_shard", 3, "Boss essence crystallized into Ember Shards.", 3)

func _show_boss_health_bar() -> void:
	var hud = get_tree().root.find_child("HUD", true, false)
	if hud == null:
		return
	boss_bar_root = hud.get_node_or_null("Root/BossHealthBar")
	boss_hp_bar = hud.get_node_or_null("Root/BossHealthBar/BossHPBar")
	boss_phase_label = hud.get_node_or_null("Root/BossHealthBar/PhaseIndicator")
	if boss_bar_root:
		boss_bar_root.visible = true
	_refresh_boss_bar()

func _refresh_boss_bar() -> void:
	if boss_hp_bar:
		boss_hp_bar.max_value = max_hp
		boss_hp_bar.value = hp

func _hide_boss_health_bar() -> void:
	if boss_bar_root:
		boss_bar_root.visible = false

func is_dead() -> bool:
	return is_defeated

func apply_elemental_status(element: String, intensity: int = 1) -> void:
	if elemental_status != null and elemental_status.has_method("apply"):
		elemental_status.apply(element, intensity)

func get_elemental_status_snapshot() -> Dictionary:
	if elemental_status != null and elemental_status.has_method("status_snapshot"):
		return elemental_status.status_snapshot()
	return {}

func get_crit_multiplier_at(point: Vector3) -> float:
	var world_center := global_position + global_transform.basis * crit_zone_center
	return crit_multiplier if world_center.distance_to(point) <= crit_zone_radius else 1.0

## === Player personalization ===
## Applies the scanned idol-crown, extracted palette and SFX preset. The
## skill override lives in `customization.skill`; subclasses decide how (and
## whether) their pool slot routes through it. Core identity stays locked.
func apply_customization(c: BossCustomization) -> void:
	if c == null:
		return
	customization = c
	sfx_profile = c.sfx_preset
	_apply_palette(c)
	_spawn_idol_crown(c)

func _apply_palette(c: BossCustomization) -> void:
	if body == null or not (body.material_override is ShaderMaterial):
		return
	var mat: ShaderMaterial = body.material_override
	if c.palette.size() >= 1:
		mat.set_shader_parameter("base_color", c.palette[0])
	if c.palette.size() >= 2:
		mat.set_shader_parameter("emissive_color", c.palette[1])

## The scanned object hovers above the boss as a slowly turning idol —
## paper-craft silhouette kept intact, no rigging required.
func _spawn_idol_crown(c: BossCustomization) -> void:
	if c.idol_mesh == null:
		return
	var rig := Node3D.new()
	rig.name = "IdolCrown"
	var mi := MeshInstance3D.new()
	mi.mesh = c.idol_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(mi)
	rig.position = crit_zone_center + Vector3(0, 0.9, 0)
	rig.scale = Vector3.ONE * 0.6
	add_child(rig)
	var glow := OmniLight3D.new()
	glow.light_color = c.palette[2] if c.palette.size() >= 3 \
		else Color(1.0, 0.72, 0.29)
	glow.light_energy = 1.4
	glow.omni_range = 5.0
	glow.omni_attenuation = 1.6
	rig.add_child(glow)
	var spin := rig.create_tween().set_loops()
	spin.tween_property(rig, "rotation:y", TAU, 7.0).from(0.0)