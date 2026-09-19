extends CharacterBody3D
class_name BossBase

const BOSS_LESSONS := preload("res://scripts/systems/boss_lesson_catalog.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")

## === Boss Base Class ===
## Multi-phase, mechanics, arena control, unique rewards

signal phase_changed(phase: int)
signal died
signal death_sequence_started(boss: Node3D)
signal attack_telegraphed(kind: String, radius: float, delay: float)
signal encounter_reset
signal phase_guidance_changed(phase: int, pattern: String, safe_zone: String)

## Autoload scripts are not class_name types in this project. Keep these
## handles dynamically resolved so standalone boss tests compile while the
## singleton call sites remain backward compatible.
@onready var game_state: Variant = get_node_or_null("/root/GameState")
@onready var audio: Variant = get_node_or_null("/root/AudioManager")
@onready var body: MeshInstance3D = $Visual/Body
@onready var animator: EntityAnimator = $Animator
@onready var hitbox: Area3D = $Hitbox
@onready var attack_areas: Node3D = $AttackAreas

enum BossPhase { PHASE_1, PHASE_2, PHASE_3, ENRAGE }

## Shared encounter timing contract. Subclasses may change presentation, but
## the authored default keeps warning, collision, and recovery values reviewable
## in one place. Damage remains phase/data driven below.
const ATTACK_PROFILES: Dictionary = {
	"mend": {"radius": 2.6, "anticipation": 1.4, "active": 0.2, "recovery": 0.25},
	"basic_slam": {"radius": 3.0, "anticipation": 0.68, "active": 0.18, "recovery": 0.32},
	"ultimate": {"anticipation": 1.25, "active": 0.35, "recovery": 0.4},
	"root_prison": {"radius": 3.5, "anticipation": 0.78, "active": 0.25, "recovery": 0.45},
	"thorn_rain": {"radius": 2.5, "anticipation": 0.8, "active": 0.25, "recovery": 0.5},
	"bramble_storm": {"radius": 4.0, "anticipation": 0.65, "active": 0.3, "recovery": 0.6},
	"thorn_lattice": {"radius": 5.0, "anticipation": 1.1, "active": 0.3, "recovery": 0.55},
	"spore_bloom": {"anticipation": 0.5, "active": 2.1, "recovery": 0.45},
}

## Player-facing phase grammar. Specific bosses may override this method, but
## every phase has a readable pattern and safe-space rule before bespoke arena
## effects are added. Collision remains owned by the attack profiles/callbacks.
const PHASE_GUIDANCE: Dictionary = {
	0: {"pattern": "Learn the rhythm", "safe_zone": "Step out of the marked attack area."},
	1: {"pattern": "Pressure rises", "safe_zone": "Use the open edge after the warning appears."},
	2: {"pattern": "Punish the opening", "safe_zone": "Create space during the cast; strike after recovery."},
	3: {"pattern": "Survive the enrage", "safe_zone": "Stay beyond the final impact ring until it fades."},
}

static func phase_guidance_for(phase: int) -> Dictionary:
	return (PHASE_GUIDANCE.get(clampi(phase, 0, 3), {}) as Dictionary).duplicate(true)

func phase_guidance() -> Dictionary:
	return phase_guidance_for(int(current_phase))

func boss_lesson() -> Dictionary:
	var index := clampi(stage_rank(), 0, BOSS_LESSONS.LESSON.size() - 1)
	return BOSS_LESSONS.LESSON[index].duplicate(true)

static func attack_profile(kind: String) -> Dictionary:
	return (ATTACK_PROFILES.get(kind, {}) as Dictionary).duplicate(true)

## One reviewable timing contract for warning, impact, and recovery. Callers
## may use the returned values for presentation, while collision resolution
## remains owned by the existing delayed callbacks.
static func attack_timing(kind: String) -> Dictionary:
	var profile := attack_profile(kind)
	var anticipation := maxf(0.0, float(profile.get("anticipation", 0.0)))
	var active := maxf(0.0, float(profile.get("active", 0.0)))
	var recovery := maxf(0.0, float(profile.get("recovery", 0.0)))
	return {
		"anticipation": anticipation,
		"impact_at": anticipation,
		"active": active,
		"impact_window": active,
		"recovery": recovery,
		"total_lock": anticipation + active + recovery,
	}

@export var max_hp: int = 500
# NOTE: `velocity` is the native CharacterBody3D property — do NOT redeclare
# it here; shadowing it is a parse error that kills the whole BossBase class.
@export var phase_thresholds: Array = [0.7, 0.3, 0.1]  # HP percentages for phase transitions
@export var base_atk: int = 12
@export var move_speed: float = 3.6
@export var arena_radius: float = 20.0
## Boss presentation (top health bar, phase guidance, boss-combat framing) is
## an encounter-scoped layer: it only exists while the player is near the
## fight. The margin is hysteresis so a knockback at the arena edge cannot
## flicker the bar on and off.
@export var hud_range_margin: float = 8.0
const HUD_RANGE_POLL_SECONDS := 0.2
var _hud_range_in := true
var _hud_range_poll_in := 0.0

## === Stage escalation ===
## Every phase makes the boss meaningfully stronger and visibly different.
## Armor is a flat reduction; damage multiplies; visuals + SFX escalate.
@export var stage_armor: Array = [0, 3, 5, 8]
@export var stage_damage_mult: Array = [1.0, 1.15, 1.3, 1.5]
@export var stage_scale_mult: Array = [1.0, 1.04, 1.09, 1.16]
## Emissive tint per stage; the body, growth pods and shockwave follow it.
@export var stage_tints: Array = [Color(1.0, 0.45, 0.12), Color(1.0, 0.28, 0.08),
	Color(0.92, 0.12, 0.05), Color(0.78, 0.05, 0.03)]
## Mend (heal) ability: hard-capped so the fight can never stall.
@export var mend_max_uses: int = 2
@export var mend_cooldown: float = 22.0
@export var mend_amount_pct: float = 0.08
@export var mend_below_pct: float = 0.5
var mend_uses_left: int = 2
var mend_cooldown_left: float = 0.0

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
var action_lock_timer := 0.0
var encounter_origin := Vector3.ZERO
var encounter_generation: int = 1
var _death_finalized := false
var _death_tween: Tween = null
# Optional compound leash: a bounded ruin the boss cannot leave. The quest
# Matriarch and standalone bosses leave this off; compound-spawned bosses set it
# so "the boss cannot leave its compound" is enforced at the movement source.
var _leash_active := false
var _leash_center := Vector3.ZERO
var _leash_radius := 0.0

# Player personalization (idol mesh, palette, one pool skill, SFX preset).
# Null = the untouched default boss.
var customization: BossCustomization = null
var sfx_profile: String = "vanilla"
## Realm bosses select a Blender profile before calling super._ready().
var authored_model_profile: String = "boss_matriarch"
## Optional world-space height for the mounted authored model; 0 keeps the
## model's own scale. Structure bosses set this so a borrowed CC0 rig matches
## the fight's silhouette instead of the exporter's units.
var authored_rig_height: float = 0.0
@export_range(0, 1) var authored_visual_variant: int = 0
## True when an authored glowing model actually mounted this boot. Derived
## bosses skip procedural identity builds (spikes/halo) that would otherwise
## double-render on top of the authored silhouette.
var authored_model_mounted: bool = false
var elemental_status: Node = null
# Practice respawns skip rewards and the scan-earn loop.
@export var is_practice: bool = false
## Diamonds granted on the FIRST kill of this boss per save (cosmetic only).
@export var diamond_reward: int = 0
## Set during the death transaction so derived bosses can safely gate their
## one-time route rewards without marking or saving the kill a second time.
var was_first_kill: bool = false

func _ready() -> void:
	hp = max_hp
	encounter_origin = global_position
	var health_bar := preload("res://scripts/ui/enemy_health_bar.gd").new()
	health_bar.name = "EnemyHealthBar"
	add_child(health_bar)
	elemental_status = preload("res://scripts/systems/elemental_status.gd").new()
	elemental_status.name = "ElementalStatus"
	elemental_status.process_mode = Node.PROCESS_MODE_ALWAYS
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

	# Authored-model drop-in. Whispergrove Matriarchs now have two authored
	# silhouettes; the save layer canonicalizes the historical whispergrove
	# alias to bramblewood, so the dedicated Matriarch scene is the stable
	# selection boundary rather than a realm-string comparison.
	if authored_model_profile == "boss_matriarch":
		var grove_variants := ["boss_whispergrove_rootwarden", "boss_whispergrove_dewseer"]
		authored_model_profile = grove_variants[clampi(authored_visual_variant, 0, 1)]
	authored_model_mounted = CharacterRigLoader.try_if_wire(self, authored_model_profile)

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
	_update_hud_range(delta)
	_menace_t += delta
	if _boss_core_mat != null:
		var rate := 2.6 if enrage_active else 1.4
		var breathe := 0.86 + 0.14 * sin(_menace_t * rate) \
			+ 0.06 * sin(_menace_t * rate * 2.7)
		_boss_core_mat.emission_energy_multiplier = breathe * 2.4
		# The authored rig's glow family breathes on the same clock, so the
		# visible model keeps the procedural menace pulse.
		if not _authored_surfaces.is_empty():
			_surface_pulse = breathe
			_refresh_authored_surfaces()
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
	_enforce_leash()

func _update_timers(delta: float) -> void:
	if stun_timer > 0:
		stun_timer -= delta
	if action_lock_timer > 0.0:
		action_lock_timer = maxf(0.0, action_lock_timer - delta)
	
	for attack in attack_cooldowns:
		if attack_cooldowns[attack] > 0:
			attack_cooldowns[attack] -= delta
	
	mechanics_timer += delta
	if mend_cooldown_left > 0.0:
		mend_cooldown_left = maxf(0.0, mend_cooldown_left - delta)

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
	var rank := stage_rank()
	audio.play_boss_phase_roar(rank)  # escalating stage stinger
	var state := get_node_or_null("/root/GameState")
	if state != null and state.has_method("record_activity"):
		state.call("record_activity", "BOSS PHASE %d · %s" % [rank + 1, name])
	if sfx_profile != "vanilla":
		audio.play_profile_cue(sfx_profile, "vocal")
	print("Boss entered stage: %s" % current_phase)
	_evolve_for_phase(int(current_phase))
	var guidance := phase_guidance()
	phase_guidance_changed.emit(int(current_phase), str(guidance.get("pattern", "")),
		str(guidance.get("safe_zone", "")))
	if boss_phase_label:
		var phase_names = {
			BossPhase.PHASE_1: "PHASE 1 · AWAKENED",
			BossPhase.PHASE_2: "PHASE 2 · HARDENED",
			BossPhase.PHASE_3: "PHASE 3 · FURIOUS",
			BossPhase.ENRAGE: "ENRAGE"
		}
		_set_phase_guidance_label(str(phase_names.get(current_phase, "PHASE ?")))

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
	
	# Vertical movement: adjust height toward player
	if dist > 3.0:
		velocity.y = lerp(velocity.y, (player.global_position.y - global_position.y) * 0.5, 0.1)
	else:
		velocity.y = lerp(velocity.y, 0.0, 0.2)
	
	# Face player
	var target_rot = atan2(to_player.x, to_player.z)
	rotation.y = lerp_angle(rotation.y, target_rot, 3.0 * delta)
	
	# Attack logic
	_try_attacks(player, dist)

func _try_attacks(player: Node3D, dist: float) -> void:
	if is_action_locked():
		return
	# Mend first: a wounded boss breaks off to heal if it still can. The
	# channel is fully telegraphed and the uses are hard-capped.
	if _should_mend():
		_perform_mend()
		return
	# Basic attack
	if float(attack_cooldowns.get("basic", 0.0)) <= 0.0 and dist < 4.0:
		_perform_basic_attack(player)
		return
	
	# Phase-specific attacks
	match current_phase:
		BossPhase.PHASE_2:
			if float(attack_cooldowns.get("special_1", INF)) <= 0.0 and dist < 8.0:
				_perform_special_1(player)
		BossPhase.PHASE_3:
			if float(attack_cooldowns.get("special_2", INF)) <= 0.0 and dist < 12.0:
				_perform_special_2(player)
			elif float(attack_cooldowns.get("ultimate", INF)) <= 0.0:
				_perform_ultimate(player)  # first tier: stage-3 ult
		BossPhase.ENRAGE:
			if float(attack_cooldowns.get("ultimate", INF)) <= 0.0:
				_perform_ultimate(player)  # full-power enrage ult

## === Mend: telegraphed heal with hard caps ===
func _should_mend() -> bool:
	if mend_max_uses <= 0 or mend_uses_left <= 0 or mend_cooldown_left > 0.0:
		return false
	var hp_pct := float(hp) / float(maxi(max_hp, 1))
	return hp_pct <= mend_below_pct and hp_pct < 1.0

func _perform_mend() -> void:
	mend_uses_left -= 1
	mend_cooldown_left = mend_cooldown
	var center := global_position
	var profile := attack_profile("mend")
	var timing := attack_timing("mend")
	var radius := float(profile.radius)
	var channel := float(timing.anticipation)
	lock_action(float(timing.total_lock))
	attack_telegraphed.emit("mend", radius, channel)
	# Verdant telegraph reads as restoration, not danger.
	CombatFx.spawn_ground_telegraph(self, center, radius,
		Color(0.45, 0.85, 0.3), channel)
	if sfx_profile != "vanilla":
		audio.play_profile_cue(sfx_profile, "vocal")
	else:
		audio.play_heal()
	var generation := encounter_generation
	var timer := get_tree().create_timer(channel, false)
	timer.timeout.connect(_resolve_mend.bind(generation))

func _resolve_mend(generation: int = -1) -> void:
	if is_defeated or not is_inside_tree() \
			or (generation >= 0 and generation != encounter_generation):
		return
	var healed := maxi(1, int(round(float(max_hp) * mend_amount_pct)))
	hp = mini(hp + healed, max_hp)
	if boss_hp_bar != null:
		boss_hp_bar.value = hp
	FloatingText.spawn_on_entity(self, "+%d" % healed, Color(0.55, 0.9, 0.4))
	CombatFx.spawn_burst(self, global_position + Vector3(0, 1.6, 0),
		Color(0.5, 0.9, 0.35, 0.85), 20, 4.0, 0.6, 0.18)
	CombatFx.spawn_motes(self, global_position + Vector3(0, 1.2, 0),
		Color(0.5, 0.9, 0.35, 0.7), 14, 1.6, 1.0, 1.8)

func is_action_locked() -> bool:
	return action_lock_timer > 0.0

func lock_action(duration: float) -> void:
	action_lock_timer = maxf(action_lock_timer, maxf(duration, 0.0))

func _perform_basic_attack(player: Node3D) -> void:
	attack_cooldowns["basic"] = 2.8
	# The warning and damage share one center/radius contract. Damage resolves
	# after anticipation, never on the frame the boss chooses the attack.
	var center := global_position
	var profile := attack_profile("basic_slam")
	var timing := attack_timing("basic_slam")
	var radius := float(profile.radius)
	var anticipation := float(timing.anticipation)
	lock_action(float(timing.total_lock))
	attack_telegraphed.emit("basic_slam", radius, anticipation)
	CombatFx.spawn_ground_telegraph(self, center, radius,
		Color(1.0, 0.16, 0.08), anticipation)
	if animator:
		animator.trigger_attack()
	var generation := encounter_generation
	var timer := get_tree().create_timer(anticipation, false)
	timer.timeout.connect(_resolve_basic_attack.bind(center, radius, generation))

func stage_rank() -> int:
	return clampi(int(current_phase), 0, 3)

func stage_dmg_mult() -> float:
	return float(stage_damage_mult[stage_rank()])

func stage_armor_value() -> int:
	return maxi(0, int(stage_armor[stage_rank()]))

func effective_atk() -> int:
	return maxi(1, int(round(float(base_atk) * stage_dmg_mult())))

func _resolve_basic_attack(center: Vector3, radius: float, generation: int = -1) -> void:
	if is_defeated or not is_inside_tree() \
			or (generation >= 0 and generation != encounter_generation):
		return
	var swing_pos: Vector3 = center + Vector3(0, 1.6, 0) \
		+ -global_transform.basis.z * 2.0
	CombatFx.spawn_burst(self, swing_pos, Color(1, 0.3, 0.2, 0.8), 18, 7.0, 0.35, 0.16)
	_deal_area_damage(center, radius, effective_atk())
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

func _perform_ultimate(player: Node3D = null) -> void:
	# Stage-scaled arena eruption: the telegraph radius, damage and recast
	# rate all grow with the boss's current stage. Subclasses may override
	# for flavor, but the escalation contract lives here.
	var rank := stage_rank()
	var ult_radius := 5.0 + 1.5 * float(rank)
	var ult_damage := maxi(1, int(round(effective_atk() * (1.2 + 0.25 * float(rank)))))
	var ult_timing := attack_timing("ultimate")
	var ult_delay := float(ult_timing.anticipation)
	attack_cooldowns["ultimate"] = 27.0 - 3.0 * float(rank)  # enrage recasts faster
	var center := global_position
	lock_action(float(ult_timing.total_lock))
	attack_telegraphed.emit("ultimate", ult_radius, ult_delay)
	var tint: Color = stage_tints[rank]
	CombatFx.spawn_ground_telegraph(self, center, ult_radius, tint, ult_delay)
	CombatFx.spawn_motes(self, center + Vector3(0, 1.4, 0),
		Color(tint.r, tint.g, tint.b, 0.75), 12 + 4 * rank, 1.2, 1.4, 2.2)
	if sfx_profile != "vanilla":
		audio.play_profile_cue(sfx_profile, "cast")
	else:
		audio.play_explosion()
	var generation := encounter_generation
	var timer := get_tree().create_timer(ult_delay, false)
	timer.timeout.connect(_resolve_ultimate.bind(center, ult_radius, ult_damage, generation))

func _resolve_ultimate(center: Vector3, radius: float, damage: int, generation: int = -1) -> void:
	if is_defeated or not is_inside_tree() \
			or (generation >= 0 and generation != encounter_generation):
		return
	var tint: Color = stage_tints[stage_rank()]
	CombatFx.spawn_shockwave(self, center - Vector3(0, 0.3, 0),
		radius * 0.5, Color(tint.r, tint.g, tint.b, 0.85), 0.9)
	_deal_area_damage(center, radius, damage)
	_shake_camera(0.5)

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

## === Visible-surface feedback ===
## The authored V2 GLBs replace the procedural body, so damage flash, stage
## tint, wear, and customization must land on the imported materials the
## player actually sees. Surfaces are duplicated per boss instance so one
## encounter can never re-theme another instance's shared GLB resource, and
## the count is capped so a future asset cannot grow this loop without bound.
const MAX_AUTHORED_SURFACES := 8
const SURFACE_FLASH_COLOR := Color(1.0, 0.84, 0.47)
var _authored_surfaces: Array[StandardMaterial3D] = []
var _surface_is_glow: Dictionary = {}
var _surface_base_albedo: Dictionary = {}
var _surface_base_emission: Dictionary = {}
var _surface_base_energy: Dictionary = {}
var _surface_tint := Color.WHITE
var _surface_flash := 0.0
var _surface_wear := 0.0
var _surface_pulse := 1.0
var _surface_flash_tween: Tween = null

## Adopt the mounted model's materials as the visible feedback targets.
## Returns the number of material families adopted (0 when the procedural
## silhouette is still the visible body, which keeps that path untouched).
func adopt_authored_surfaces(rig: Node3D) -> int:
	if rig == null:
		return 0
	var copies: Dictionary = {}
	for mesh_value in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_value as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			if copies.size() >= MAX_AUTHORED_SURFACES:
				break
			var source := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			if not copies.has(source):
				var copy := source.duplicate() as StandardMaterial3D
				if copy == null:
					continue
				# Emission is enabled once, here, so the per-hit flash never
				# toggles a shader define (which would trigger a mobile shader
				# recompile mid-fight). Resting energy stays at the imported
				# value, which is zero for every non-glow family.
				if not copy.emission_enabled:
					copy.emission_enabled = true
					copy.emission = Color.BLACK
					copy.emission_energy_multiplier = 0.0
				copies[source] = copy
				_authored_surfaces.append(copy)
				_surface_is_glow[copy] = source.emission_enabled
				_surface_base_albedo[copy] = copy.albedo_color
				_surface_base_emission[copy] = copy.emission
				_surface_base_energy[copy] = copy.emission_energy_multiplier
			mesh_instance.set_surface_override_material(surface, copies[source])
	_refresh_authored_surfaces()
	return _authored_surfaces.size()

func _refresh_authored_surfaces() -> void:
	if _authored_surfaces.is_empty():
		return
	for material in _authored_surfaces:
		if not is_instance_valid(material):
			continue
		var base_albedo: Color = _surface_base_albedo.get(material, material.albedo_color)
		var albedo := base_albedo.lerp(_surface_tint, _surface_wear * 0.45)
		albedo = albedo.darkened(_surface_wear * 0.45).lerp(
			SURFACE_FLASH_COLOR, _surface_flash * 0.85)
		material.albedo_color = albedo
		var is_glow := bool(_surface_is_glow.get(material, false))
		var base_emission: Color = _surface_base_emission.get(material, Color.BLACK)
		var emission := base_emission.lerp(_surface_tint, 0.65) if is_glow else base_emission
		material.emission = emission.lerp(SURFACE_FLASH_COLOR, _surface_flash)
		var energy: float = float(_surface_base_energy.get(material, 0.0))
		if is_glow:
			energy *= _surface_pulse
		material.emission_energy_multiplier = energy + 1.8 * _surface_flash

func set_surface_flash(value: float) -> void:
	_surface_flash = clampf(value, 0.0, 1.0)
	_refresh_authored_surfaces()

func set_surface_tint(color: Color) -> void:
	if color == Color.BLACK:
		return
	_surface_tint = color
	_refresh_authored_surfaces()

## Battle wear dulls the authored surfaces as the boss breaks down, matching
## the procedural body's hp_wear band.
func set_surface_wear(value: float) -> void:
	_surface_wear = clampf(value, 0.0, 1.0)
	_refresh_authored_surfaces()

func _flash_authored_surfaces() -> void:
	if _authored_surfaces.is_empty():
		return
	if _surface_flash_tween != null and _surface_flash_tween.is_valid():
		_surface_flash_tween.kill()
	_surface_flash_tween = create_tween()
	_surface_flash_tween.tween_method(set_surface_flash, 0.0, 1.0, 0.05)
	_surface_flash_tween.tween_method(set_surface_flash, 1.0, 0.0, 0.2)

func _reset_authored_surfaces() -> void:
	_surface_flash = 0.0
	_surface_wear = 0.0
	_surface_pulse = 1.0
	_surface_tint = Color.WHITE
	_refresh_authored_surfaces()

func take_damage(amount: int, knockback_dir: Vector3, critical: bool = false) -> void:
	if is_defeated:
		return
	
	# Stage armor: higher stages shrug off more of every hit (min 1 gets through).
	var applied := maxi(1, amount - stage_armor_value())
	hp -= applied
	var state := get_node_or_null("/root/GameState")
	if state != null and state.has_method("record_activity"):
		state.call("record_activity", "BOSS HIT · %d%s" % [applied, " · CRIT" if critical else ""])
	ImpactDirector.dispatch_damage_event(self, applied, critical, knockback_dir)
	var health_bar := get_node_or_null("EnemyHealthBar")
	if health_bar != null and health_bar.has_method("notify_damage"):
		health_bar.notify_damage()
	
	# Visual
	if animator:
		animator.trigger_hit()
	var tween = create_tween()
	tween.tween_property(body, "material_override:shader_parameter/flash_intensity", 1.0, 0.05)
	tween.tween_property(body, "material_override:shader_parameter/flash_intensity", 0.0, 0.2)
	_flash_authored_surfaces()
	# Battle wear: bark dulls and darkens as the boss breaks down
	if body.material_override is ShaderMaterial:
		var ratio := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
		body.material_override.set_shader_parameter("hp_wear",
			clampf((0.45 - ratio) / 0.45, 0.0, 1.0) * 0.75)
	if not _authored_surfaces.is_empty():
		set_surface_wear(clampf((0.45 - float(hp) / float(maxi(max_hp, 1))) / 0.45,
			0.0, 1.0) * 0.75)
	
	if boss_hp_bar:
		boss_hp_bar.value = max(hp, 0)
	
	knockback_velocity = knockback_dir * (amount * 3.0)
	
	if hp <= 0:
		die()

## === Stage escalation: each phase visibly rebuilds the boss ===
## Heart core flares hotter in the stage tint, growth attachments sprout,
## the whole silhouette swells, and the transition lands with a shockwave.
func _evolve_for_phase(phase: int) -> void:
	var rank := clampi(phase, 0, 3)
	var tint: Color = stage_tints[rank]
	# Molten core burns brighter and hotter-hued with every stage
	if _boss_core_mat != null:
		_boss_core_mat.emission = tint
		_boss_core_mat.emission_energy_multiplier = 2.4 + float(rank) * 1.2
	# Body emissive follows the stage tint so the silhouette re-themes
	if body != null and body.material_override is ShaderMaterial:
		var body_mat: ShaderMaterial = body.material_override
		body_mat.set_shader_parameter("emissive_color", tint)
	set_surface_tint(tint)
	# The whole frame swells a little each stage
	var vroot := visual_root_or_body_parent()
	if vroot != null:
		vroot.scale = Vector3.ONE * float(stage_scale_mult[rank])
	# Sprout growths at deterministic anchor points on the torso
	var rng := RandomNumberGenerator.new()
	rng.seed = get_instance_id() + phase * 131
	var growth_count := mini(rank + 1, 4)
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
		mat.emission = tint
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
	if _enrage_ring != null and _enrage_ring.material_override is StandardMaterial3D:
		(_enrage_ring.material_override as StandardMaterial3D).emission = tint
	# Transition shockwave + rumble sells the shift physically
	CombatFx.spawn_shockwave(self, global_position - Vector3(0, 0.3, 0), 4.2,
		Color(tint.r, tint.g, tint.b, 0.8), 0.8)
	CombatFx.spawn_impact_light(self, global_position,
		tint.lightened(0.15), 3.6, 6.0, 0.42)
	CombatFx.spawn_motes(self, global_position + Vector3(0, 1.2, 0),
		Color(tint.r, tint.g, tint.b, 0.7), 18, 1.4, 1.1, 2.4)
	ImpactDirector.apply_feedback(self, "major", global_position + Vector3.UP * 1.4,
		Vector3.FORWARD, 1.0)

func die() -> void:
	if is_defeated:
		return
	encounter_generation += 1 # invalidate every delayed attack callback
	death_sequence_started.emit(self)
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
	var death_generation := encounter_generation
	_death_tween = create_tween()
	_death_tween.tween_interval(2.6)
	_death_tween.tween_callback(_on_death_finished.bind(death_generation))
	
	# Crumbling bark groan under the locked victory sting
	audio.play_boss_death()
	# A synchronized boss score owns its victory cadence. Generic bosses retain
	# the original stinger when no reactive score is running.
	if not audio.boss_score_active:
		audio.play_victory()
	var ws := get_node_or_null("/root/WorldState")
	if ws != null and ws.has_method("gust"):
		ws.gust(Vector2.ZERO, 1.0)   # the grove recoils as the Matriarch falls

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

func _on_death_finished(expected_generation: int = -1) -> void:
	# A retry can reset the same boss while its death presentation is still
	# winding down. The generation token makes any stale callback harmless even
	# if the tween was already queued by the engine; reset_encounter() also kills
	# the active tween below.
	if expected_generation >= 0 and expected_generation != encounter_generation:
		return
	_death_tween = null
	if _death_finalized:
		return
	_death_finalized = true
	var sm := get_node_or_null("/root/StoryManager")
	if sm != null and sm.has_method("notify_objective"):
		sm.notify_objective("kill", _boss_key(), 1)
	if not is_practice:
		game_state.earn_scan()
		was_first_kill = game_state.mark_boss_killed(_boss_key())
		if was_first_kill and diamond_reward > 0:
			var amount := diamond_reward + randi_range(0, 2)
			game_state.add_diamonds(amount,
				"+%d DIAMONDS — a glint from the old world remains." % amount)
	_spawn_rewards()
	_announce_repeat_reward_choice()
	# Boss victory is a critical progression boundary: persist the complete
	# reward/checkpoint state before the defeated entity leaves the scene.
	if game_state != null and game_state.has_method("flush_save"):
		game_state.flush_save()
	died.emit()
	queue_free()

func _announce_repeat_reward_choice() -> void:
	if was_first_kill:
		return
	var boss_id := _boss_key().get_file().get_basename()
	if boss_id.begins_with("boss_"):
		boss_id = boss_id.trim_prefix("boss_")
	var catalog := preload("res://scripts/systems/boss_reward_catalog.gd")
	var choices: Array[Dictionary] = catalog.choices_for(boss_id)
	if choices.is_empty():
		return
	var reward_manager := get_node_or_null("/root/RewardManager")
	if reward_manager != null and reward_manager.has_signal("boss_reward_choice_available"):
		reward_manager.boss_reward_choice_available.emit(boss_id, choices)

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
	var boss_id := _boss_key().get_file().get_basename()
	var result := LootTable.roll_boss(boss_id)
	game_state.grant_xp(200)
	if result.gold > 0:
		game_state.add_gold(result.gold, " +%d gold from the boss hoard." % result.gold)
	for mat in result.materials:
		game_state.add_material(mat.id, mat.qty)
		FloatingText.spawn_on_entity(self, "+%d %s" % [mat.qty, GAME_STATE_SCRIPT.MATERIAL_DEFS.get(mat.id, {}).get("name", mat.id)],
			Color(0.52, 0.90, 1.0), 1.2)
	if result.gear != null:
		var gear: Dictionary = result.gear
		var item_id: String = str(gear.get("id", "")) if not str(gear.get("id", "")).is_empty() else "moss_tonic"
		LootDrop.spawn_item(self, global_position + Vector3(0, 0.5, 0), item_id, 1, gear.rarity)

func set_encounter_origin(origin: Vector3) -> void:
	encounter_origin = origin

## === Compound leash ===
## The boss is confined to a circular compound. Horizontal only, so vertical
## attacks (jumps, burrows) are unaffected; the clamp runs after move_and_slide
## so no attack or telegraph timing changes.
func set_leash(center: Vector3, radius: float) -> void:
	_leash_active = true
	_leash_center = center
	_leash_radius = maxf(radius, 1.0)

func clear_leash() -> void:
	_leash_active = false
	_leash_radius = 0.0

func _enforce_leash() -> void:
	if not _leash_active or _leash_radius <= 0.0:
		return
	var offset := Vector3(global_position.x - _leash_center.x, 0.0,
		global_position.z - _leash_center.z)
	if offset.length() <= _leash_radius:
		return
	var clamped := _leash_center + offset.normalized() * _leash_radius
	clamped.y = global_position.y
	global_position = clamped

## Player-facing identity used by the HUD nameplate and title cards. Derived
## bosses override these with roster name/title; the base falls back to the node
## name so standalone/legacy bosses still show something readable.
func boss_display_name() -> String:
	return str(name).to_upper()

func boss_display_title() -> String:
	return ""

## Full retry transaction used by WorldManager after player defeat. Derived
## bosses extend this to clear summons/phase props but must call super.
func reset_encounter() -> void:
	var state := get_node_or_null("/root/GameState")
	if state != null and state.has_method("record_activity"):
		state.call("record_activity", "BOSS RESET · %s" % name)
	if _death_tween != null:
		_death_tween.kill()
		_death_tween = null
	encounter_generation += 1
	_death_finalized = false
	is_defeated = false
	was_first_kill = false
	hp = max_hp
	current_phase = BossPhase.PHASE_1
	stun_timer = 0.0
	action_lock_timer = 0.0
	mend_uses_left = mend_max_uses
	mend_cooldown_left = 0.0
	mechanics_timer = 0.0
	enrage_active = false
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	global_position = encounter_origin
	_setup_attacks()
	collision_layer = 1 << 4
	collision_mask = 1 << 0 | 1 << 5 | 1 << 6
	if hitbox:
		hitbox.set_deferred("monitoring", true)
	for attack_area in attack_areas.get_children():
		if attack_area is Area3D:
			attack_area.set_deferred("monitoring", true)
	if animator and animator.has_method("reset_to_idle"):
		animator.reset_to_idle()
	if body and body.material_override is ShaderMaterial:
		body.material_override.set_shader_parameter("flash_intensity", 0.0)
		body.material_override.set_shader_parameter("hp_wear", 0.0)
	if _surface_flash_tween != null and _surface_flash_tween.is_valid():
		_surface_flash_tween.kill()
	_reset_authored_surfaces()
	if boss_hp_bar:
		boss_hp_bar.max_value = max_hp
		boss_hp_bar.value = hp
	if boss_bar_root:
		boss_bar_root.visible = true
	if _enrage_ring:
		_enrage_ring.visible = false
	encounter_reset.emit()

func _show_boss_health_bar() -> void:
	var hud = get_tree().root.find_child("HUD", true, false)
	if hud == null:
		return
	boss_bar_root = hud.get_node_or_null("Root/BossHealthBar")
	boss_hp_bar = hud.get_node_or_null("Root/BossHealthBar/BossHPBar")
	boss_phase_label = hud.get_node_or_null("Root/BossHealthBar/PhaseIndicator")
	var name_label := hud.get_node_or_null("Root/BossHealthBar/BossName") as Label
	if name_label != null:
		name_label.text = boss_display_name()
	if boss_bar_root:
		boss_bar_root.visible = true
	_refresh_boss_bar()

func _refresh_boss_bar() -> void:
	if boss_hp_bar:
		boss_hp_bar.max_value = max_hp
		boss_hp_bar.value = hp
	if boss_phase_label:
		var phase_names := {
			BossPhase.PHASE_1: "PHASE 1 · AWAKENED",
			BossPhase.PHASE_2: "PHASE 2 · HARDENED",
			BossPhase.PHASE_3: "PHASE 3 · FURIOUS",
			BossPhase.ENRAGE: "ENRAGE",
		}
		_set_phase_guidance_label(str(phase_names.get(current_phase, "PHASE ?")))

func _set_phase_guidance_label(phase_name: String) -> void:
	if boss_phase_label == null:
		return
	var guidance := phase_guidance()
	var lesson := boss_lesson()
	boss_phase_label.text = "%s\n%s · %s" % [phase_name,
		str(guidance.get("pattern", "")), str(guidance.get("safe_zone", ""))]
	if not lesson.is_empty():
		boss_phase_label.text += "\nLESSON · %s" % str(lesson.get("rule", ""))

func _hide_boss_health_bar() -> void:
	if boss_bar_root:
		boss_bar_root.visible = false

## Encounter-scoped HUD: walking out of the boss's reach retires the top bar,
## its phase/telegraph guidance and the wider boss-combat framing; walking back
## restores them. Polled so the distance check never runs inside an attack
## callback and the fight's timing is untouched.
func _update_hud_range(delta: float) -> void:
	_hud_range_poll_in -= delta
	if _hud_range_poll_in > 0.0:
		return
	_hud_range_poll_in = HUD_RANGE_POLL_SECONDS
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not is_instance_valid(player):
		return
	var flat_offset := Vector3(global_position.x - player.global_position.x, 0.0,
		global_position.z - player.global_position.z)
	var in_range := flat_offset.length() \
		<= maxf(arena_radius, 12.0) + hud_range_margin
	if in_range == _hud_range_in:
		return
	_hud_range_in = in_range
	if in_range:
		_show_boss_health_bar()
		_apply_boss_combat_camera(true)
	else:
		_hide_boss_health_bar()
		_apply_boss_combat_camera(false)
	# The boss's own floating plate leaves with the top bar so the retired
	# encounter does not leave a health bar floating over the horizon.
	var floating := get_node_or_null("EnemyHealthBar")
	if floating != null and floating.has_method("set_range_visible"):
		floating.call("set_range_visible", in_range)

func _apply_boss_combat_camera(active: bool) -> void:
	var camera_rig := get_parent().get_node_or_null("CameraRig")
	if camera_rig != null and camera_rig.has_method("set_boss_combat"):
		camera_rig.set_boss_combat(active, arena_radius)

func is_dead() -> bool:
	return is_defeated

func apply_elemental_status(element: String, intensity: int = 1) -> void:
	if elemental_status != null and elemental_status.has_method("apply"):
		var applications: int = maxi(1, intensity)
		for _index in applications:
			elemental_status.apply(element, 4.0)

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
	if c.palette.size() >= 2:
		set_surface_tint(c.palette[1])
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
	mi.mesh = c.idol_mesh.mesh
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
