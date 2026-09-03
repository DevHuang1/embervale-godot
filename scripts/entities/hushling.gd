extends CharacterBody3D
class_name Hushling

## === Hushling / Bramble Sprite ===
## Pattern AI: orbit, feint, lunge, recover (ported from embervale)

signal died

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var body: MeshInstance3D = $Visual/Body
@onready var visual: Node3D = $Visual
@onready var eyes: Node3D = $Visual/Eyes
@onready var tendrils: Node3D = $Visual/Tendrils
@onready var animator: EntityAnimator = $Animator
@onready var hitbox: Area3D = $Hitbox
@onready var attack_area: Area3D = $AttackArea

enum Pattern { ORBIT, FEINT, LUNGE, WINDUP, RECOVER, BRAMBLE_BURST,
	CHARGE_TELEGRAPH, CHARGE_RUSH, HIDE, GUARD_SHIELD, RETREAT, DRAIN,
	SPECIAL_TELEGRAPH, SPECIAL_ACTIVE }

@export var max_hp: int = 28
@export var base_atk: int = 3
@export var move_speed: float = 2.3
@export var orbit_distance: float = 72.0 / 10.0  # 7.2 units (STANDOFF converted)
@export var lunge_speed: float = 9.0
@export var feint_speed: float = 5.5
@export var orbit_speed: float = 2.0
@export var recover_speed: float = 2.8
@export var burst_cooldown: float = 4.0
@export var burst_radius: float = 3.8
@export var burst_damage: int = 6
# Hard-tier flag: bursts become a tracking 3-spike thorn volley.
@export var thorn_volley: bool = false
@export var archetype: String = "hushling"

## Reusable behavior profiles keep memory low while making enemy silhouettes and
## combat rhythms distinct across realms. Movement multipliers are intentionally
## modest so every creature reads as slower than the hero while its attack
## cadence (lunge / burst / special cooldowns) stays aggressive.
func configure_archetype(profile: String) -> void:
	archetype = profile
	# Each archetype gets a unique special-skill cooldown (seconds).
	# Lower = more frequent special use.
	special_cooldown = 8.0
	match archetype:
		"charger":
			move_speed *= 1.05
			orbit_distance = 5.2
			lunge_speed = 11.5
			lunge_cooldown = 1.8
			counter_range = 2.8
			burst_damage += 2
			special_cooldown = 7.0
		"ambusher":
			move_speed *= 1.10
			orbit_distance = 4.6
			feint_speed = 7.4
			lunge_speed = 10.0
			lunge_cooldown = 1.6
			counter_windup = 0.48
			special_cooldown = 6.5
		"thorn_charger":
			move_speed *= 1.15
			orbit_distance = 8.0
			lunge_speed = 14.0
			lunge_cooldown = 2.4
			counter_range = 3.2
			base_atk += 2
			special_cooldown = 8.0
		"mire_stalker":
			move_speed *= 1.08
			orbit_distance = 5.0
			feint_speed = 8.0
			lunge_speed = 11.0
			lunge_cooldown = 2.0
			counter_windup = 0.4
			special_cooldown = 9.0
		"ember_warden":
			move_speed *= 0.85
			orbit_distance = 4.0
			burst_damage += 4
			burst_cooldown = 3.5
			counter_range = 3.5
			special_cooldown = 10.0
		"spore_weaver":
			move_speed *= 0.95
			orbit_distance = 6.5
			burst_damage += 1
			burst_cooldown = 3.0
			special_cooldown = 8.0
		"relic_leech":
			move_speed *= 0.9
			orbit_distance = 5.5
			burst_damage += 2
			burst_cooldown = 4.0
			special_cooldown = 9.0
		"fenling":
			# Mire sprite of the Mistfen: fast, low-skimming, corners on a
			# tighter orbit and spams its cold volley from cover.
			move_speed *= 1.08
			orbit_distance = 5.4
			feint_speed = 7.6
			lunge_speed = 10.6
			lunge_cooldown = 1.7
			burst_damage += 1
			burst_cooldown = 3.2
			counter_windup = 0.5
			special_cooldown = 7.5
		"moonfen_fenling":
			# Moonfen broodmother's dregs hit harder and strip the mire.
			move_speed *= 1.05
			orbit_distance = 5.6
			feint_speed = 8.2
			lunge_speed = 11.4
			lunge_cooldown = 1.6
			burst_damage += 3
			burst_cooldown = 2.8
			counter_windup = 0.42
			special_cooldown = 7.0

# Telegraphed counter-strike: after being struck in melee range the sprite
# winds up visibly before answering. Dodging through the strike is rewarded.
@export var counter_windup: float = 0.72
@export var counter_range: float = 2.3
@export var counter_cooldown: float = 2.0
var counter_timer: float = 0.0

# === Special Skill System ===
# Each archetype has a unique powerful ability on its own cooldown. Specials
# override the normal pattern flow: TELEGRAPH warns the player, ACTIVE resolves
# the effect, then control returns to RECOVER.
@export var special_cooldown: float = 8.0
var special_timer: float = 3.0
var _special_active: bool = false
var _cloak_active: bool = false  # mire_stalker stealth flag
var _shield_active: bool = false  # ember_warden shield flag
var _slow_field_pos: Vector3 = Vector3.ZERO  # spore_weaver cloud anchor
var _spore_timer: float = 0.0
# Special-skill internal state
var _soul_siphon_target: Node3D = null
var _soul_siphon_remaining: float = 0.0
var _bramble_charge_trail: bool = false
var _bramble_charge_start: Vector3 = Vector3.ZERO

# Realm/boss SFX preset id ("vanilla" keeps the original cues).
var sfx_profile: String = "vanilla"
var elemental_status: Node = null

var hp: int = 28
var current_pattern: Pattern = Pattern.ORBIT
var pattern_timer: float = 0.8
var lunge_cooldown: float = 2.0
var burst_timer: float = 2.0
var burst_active: bool = false
var lunge_hit: bool = false
var orbit_direction: int = 1
var stun_timer: float = 0.0
var knockback_velocity: Vector3 = Vector3.ZERO
var is_defeated: bool = false
var bob_timer: float = 0.0
var _charge_target_pos: Vector3 = Vector3.ZERO
var _hide_timer: float = 0.0
var _guard_active: bool = false
var _drain_target: Node3D = null
var _stagger_threshold: float = 30.0
var _stagger_cooldown: float = 0.0

## Creature detail pass: back thorns, stub root-legs, claw nubs.
## Parented under Visual so the squash-hop animator drives them free.
func _build_creature_details() -> void:
	if visual == null:
		return
	var dark_mat := _dark_thorn_mat()
	# All archetypes share the base legs — only claw/feature geometry differs
	_build_legs(dark_mat)
	# Archetype-specific overlay geometry
	match archetype:
		"charger", "thorn_charger":
			_build_ram_horns(dark_mat)
		"fenling", "moonfen_fenling":
			_build_fin_crest(dark_mat)
		"ember_warden":
			_build_shield_disc()
		"spore_weaver":
			_build_spore_sacs(dark_mat)
		"mire_stalker":
			_build_stalker_fins(dark_mat)
		"relic_leech":
			_build_leech_suckers(dark_mat)
		_:
			_build_default_claws(dark_mat)

func _ready() -> void:
	hp = max_hp
	var health_bar := preload("res://scripts/ui/enemy_health_bar.gd").new()
	health_bar.name = "EnemyHealthBar"
	add_child(health_bar)
	elemental_status = preload("res://scripts/systems/elemental_status.gd").new()
	elemental_status.name = "ElementalStatus"
	add_child(elemental_status)
	collision_layer = 1 << 1  # Enemy layer
	collision_mask = 1 << 0 | 1 << 5 | 1 << 6  # Player + Environment + Prop
	
	hitbox.area_entered.connect(_on_hitbox_entered)
	attack_area.area_entered.connect(_on_attack_area_entered)
	
	# Random initial orbit direction
	orbit_direction = 1 if randi() % 2 == 0 else -1
	bob_timer = randf() * TAU
	_build_hushling_silhouette()
	_build_creature_details()

	# Authored-model drop-in (silent no-op until the model ships).
	# Paint the mounted rig with the shared entity skin right after wiring:
	# the Animator's _apply_albedo_variation already ran (child _ready before
	# parent), so the rig would otherwise keep the FBX's flat placeholder mats.
	var wired := CharacterRigLoader.try_if_wire(self, _rig_profile())
	if wired:
		_paint_authored_rig()
	_apply_enemy_surface_profile()

## Realm identities share one mip-safe surface master but receive deliberate
## material palettes. This keeps enemies related while making their gameplay
## role readable without relying on emission or UI markers.
func _apply_enemy_surface_profile() -> void:
	var profiles := {
		"hushling": [Color(0.30, 0.25, 0.38), Color(0.42, 0.72, 0.50), 0.52, 0.68],
		"charger": [Color(0.25, 0.20, 0.29), Color(0.62, 0.74, 0.40), 0.42, 0.73],
		"ambusher": [Color(0.18, 0.26, 0.22), Color(0.36, 0.78, 0.56), 0.38, 0.76],
		"thorn_charger": [Color(0.30, 0.16, 0.11), Color(0.92, 0.36, 0.12), 0.44, 0.78],
		"mire_stalker": [Color(0.17, 0.28, 0.31), Color(0.32, 0.78, 0.82), 0.34, 0.60],
		"ember_warden": [Color(0.25, 0.12, 0.09), Color(1.0, 0.30, 0.08), 0.56, 0.82],
		"spore_weaver": [Color(0.25, 0.31, 0.17), Color(0.64, 0.88, 0.34), 0.40, 0.74],
		"relic_leech": [Color(0.20, 0.22, 0.34), Color(0.46, 0.76, 1.0), 0.48, 0.58],
		"fenling": [Color(0.15, 0.27, 0.34), Color(0.30, 0.82, 0.94), 0.38, 0.52],
		"moonfen_fenling": [Color(0.20, 0.18, 0.38), Color(0.32, 0.90, 1.0), 0.50, 0.48],
	}
	var profile: Array = profiles.get(archetype, profiles["hushling"])
	for candidate in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := candidate as MeshInstance3D
		var material := mesh.material_override as ShaderMaterial
		if material == null or material.shader == null \
				or not material.shader.resource_path.ends_with("entity_body.gdshader"):
			continue
		var local := material.duplicate(false) as ShaderMaterial
		local.set_shader_parameter("base_color", profile[0])
		local.set_shader_parameter("rim_color", profile[1])
		local.set_shader_parameter("emission_color", profile[1])
		local.set_shader_parameter("emission_energy", profile[2])
		local.set_shader_parameter("roughness", profile[3])
		local.set_shader_parameter("variation_seed", randf())
		mesh.material_override = local

## Apply the shared hand-painted skin (entity_body shader) to the mounted rig's
## meshes. Requires the model to carry real UVs (hushling.fbx was unwrapped in
## Blender for this). Each clone gets its own duplicate + variation seed, the
## same per-clone variety _apply_albedo_variation gives the procedural body.
func _paint_authored_rig() -> void:
	var rigs := visual.find_children("AuthoredRig", "Node3D", true, false)
	if rigs.is_empty():
		return
	var skin := preload("res://assets/materials/entity_hushling.tres") as ShaderMaterial
	if skin == null or skin.shader == null \
			or not skin.shader.resource_path.ends_with("entity_body.gdshader"):
		return
	for rig in rigs:
		for child in rig.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			var local := skin.duplicate(false)
			local.set_shader_parameter("variation_seed", randf())
			mi.material_override = local

## Which authored rig this creature wears (Fenling overrides to "fenling").
func _rig_profile() -> String:
	return "hushling"

func _build_hushling_silhouette() -> void:
	# Base body scale varies by archetype — charger reads bigger, ambusher flatter
	var body_scale := _archetype_body_scale()
	visual.scale = body_scale

	# Core gem — color and size reflect archetype element
	var core_col := _archetype_core_color()
	var core := MeshInstance3D.new()
	core.name = "BrambleCore"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.13 * body_scale.x
	core_mesh.height  = core_mesh.radius * 2.0
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color             = core_col
	core_mat.emission_enabled         = true
	core_mat.emission                 = core_col
	core_mat.emission_energy_multiplier = 2.8
	core.mesh              = core_mesh
	core.material_override = core_mat
	core.position          = Vector3(0, 0.04, 0.42)
	visual.add_child(core)

	var core_light := OmniLight3D.new()
	core_light.name         = "BrambleCoreLight"
	core_light.light_color  = core_col
	core_light.light_energy = 0.55
	core_light.omni_range   = 3.2
	core_light.position     = Vector3(0, 0.04, 0.40)
	visual.add_child(core_light)

	# Crown thorns — count and lean angle per archetype
	var crown_data := _archetype_crown_data()  # [count, lean, height, radius]
	var thorn_mat := StandardMaterial3D.new()
	thorn_mat.albedo_color = Color(0.20, 0.34, 0.22)
	thorn_mat.roughness    = 0.92
	for i in crown_data[0]:
		var thorn := MeshInstance3D.new()
		thorn.name = "CrownThorn%d" % i
		var tm := CylinderMesh.new()
		tm.top_radius      = 0.0
		tm.bottom_radius   = crown_data[3]
		tm.height          = crown_data[2]
		tm.radial_segments = 6
		thorn.mesh              = tm
		thorn.material_override = thorn_mat
		var spread := float(crown_data[0])
		thorn.position = Vector3((i - spread * 0.5 + 0.5) * 0.22, 0.42, 0.02)
		thorn.rotation.z = (i - spread * 0.5 + 0.5) * crown_data[1]
		visual.add_child(thorn)

func _physics_process(delta: float) -> void:
	if is_defeated:
		return
	
	_update_timers(delta)
	_update_pattern(delta)
	_update_movement(delta)
	_update_visuals(delta)
	
	move_and_slide()
	_snap_to_ground(delta)

## The rendered ground is heightmapped (TerrainRelief) while the collision
## floor stays flat, so follow the visible surface to stop the sprite
## hovering above dips and hollows in close 3rd-person framing.
func _snap_to_ground(delta: float) -> void:
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain == null or not terrain.has_method("height_at"):
		return
	var ground: float = terrain.height_at(global_position.x, global_position.z)
	var weight := 1.0 - exp(-delta * 14.0)
	global_position.y = lerpf(global_position.y, ground, weight)

func _update_timers(delta: float) -> void:
	if pattern_timer > 0:
		pattern_timer -= delta
	
	if lunge_cooldown > 0:
		lunge_cooldown -= delta
	if burst_timer > 0:
		burst_timer -= delta
	
	if counter_timer > 0:
		counter_timer -= delta
	
	if special_timer > 0:
		special_timer -= delta
	
	if stun_timer > 0:
		stun_timer -= delta
	
	if _spore_timer > 0:
		_spore_timer -= delta
		if _spore_timer <= 0.0:
			_slow_field_pos = Vector3.ZERO
	
	if knockback_velocity.length() > 0.1:
		velocity += knockback_velocity
		knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, pow(0.001, delta))

func _update_pattern(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	if stun_timer > 0:
		current_pattern = Pattern.RECOVER
		return
	
	var to_player = (player.global_position - global_position).normalized()
	var dist = global_position.distance_to(player.global_position)
	
	if pattern_timer <= 0:
		match current_pattern:
			Pattern.ORBIT:
				# Special skill takes priority when its cooldown is ready.
				if special_timer <= 0.0 and not _special_active:
					_begin_special_telegraph()
				elif archetype in ["thorn_charger"] and lunge_cooldown <= 0 and dist < orbit_distance + 4.0:
					_begin_charge()
				elif archetype in ["mire_stalker"] and dist < orbit_distance + 2.0 and lunge_cooldown <= 0:
					_begin_hide()
				elif archetype in ["ember_warden"] and burst_timer <= 0 and dist < burst_radius + 3.0:
					_begin_guard()
				elif archetype in ["spore_weaver"] and burst_timer <= 0 and dist < orbit_distance + 2.0:
					_begin_retreat()
				elif archetype in ["relic_leech"] and burst_timer <= 0 and dist < orbit_distance + 2.5:
					_begin_drain()
				elif dist < burst_radius + 2.0 and burst_timer <= 0:
					_begin_bramble_burst()
				elif dist < orbit_distance + 2.6 and lunge_cooldown <= 0:
					current_pattern = Pattern.LUNGE
					pattern_timer = 0.45
					lunge_cooldown = 3.0
					lunge_hit = false
					_modulate_eyes(Color(1, 0.3, 0.2))
					animator.trigger_attack("enemy")
					audio.play_enemy_telegraph()
				else:
					current_pattern = Pattern.FEINT
					pattern_timer = 0.35
				
			Pattern.FEINT, Pattern.LUNGE:
				current_pattern = Pattern.RECOVER
				pattern_timer = 0.90

			Pattern.WINDUP:
				_resolve_counter_strike()
				
			Pattern.BRAMBLE_BURST:
				_perform_bramble_burst(player)
				current_pattern = Pattern.RECOVER
				pattern_timer = 0.90

			Pattern.CHARGE_TELEGRAPH:
				_begin_charge_rush()

			Pattern.CHARGE_RUSH:
				current_pattern = Pattern.RECOVER
				pattern_timer = 1.2

			Pattern.HIDE:
				_resolve_hide()

			Pattern.GUARD_SHIELD:
				_resolve_guard()

			Pattern.RETREAT:
				current_pattern = Pattern.ORBIT
				pattern_timer = 0.5

			Pattern.DRAIN:
				_resolve_drain()

			Pattern.SPECIAL_TELEGRAPH:
				_resolve_special_telegraph()

			Pattern.SPECIAL_ACTIVE:
				_resolve_special_active()

			Pattern.RECOVER:
				current_pattern = Pattern.ORBIT
				pattern_timer = 0.9
				orbit_direction *= -1
				# Micro-spin sells the direction change
				animator.trigger_spin(orbit_direction)

func _begin_bramble_burst() -> void:
	current_pattern = Pattern.BRAMBLE_BURST
	pattern_timer = 0.72
	burst_active = true
	_modulate_eyes(Color(1.0, 0.58, 0.22))
	if sfx_profile == "vanilla":
		audio.play_enemy_telegraph()
	else:
		audio.play_profile_cue(sfx_profile, "telegraph")
	_spawn_burst_fx(Color(1.0, 0.45, 0.18, 0.45), 0.72, 18)

# === Thorn Charger: telegraph 0.8s → linear rush → wall stun ===
func _begin_charge() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	current_pattern = Pattern.CHARGE_TELEGRAPH
	pattern_timer = 0.8
	_charge_target_pos = player.global_position
	lunge_cooldown = 3.5
	_modulate_eyes(Color(1.0, 0.2, 0.1))
	audio.play_enemy_telegraph()
	CombatFx.spawn_ground_telegraph(self, global_position, 2.0,
		Color(1.0, 0.3, 0.1), 0.8)

func _begin_charge_rush() -> void:
	current_pattern = Pattern.CHARGE_RUSH
	pattern_timer = 0.6
	lunge_hit = false
	animator.trigger_attack("enemy")

func _resolve_charge() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null or is_defeated:
		return
	var dist := global_position.distance_to(player.global_position)
	if dist <= 2.5 and not lunge_hit:
		lunge_hit = true
		if player.has_method("notify_enemy_strike"):
			player.notify_enemy_strike(self, base_atk + 3, "charge_rush")
			CombatFx.spawn_slash(self, player.global_position + Vector3(0, 0.5, 0),
				Color(1.0, 0.3, 0.1, 0.9))
			CombatFx.impact(self, 0.25, 0.05, 0.18, 0.25)

# === Mire Stalker: hide → flank → emerge attack ===
func _begin_hide() -> void:
	current_pattern = Pattern.HIDE
	pattern_timer = 1.2
	_hide_timer = 1.2
	lunge_cooldown = 2.8
	visual.modulate.a = 0.3
	_modulate_eyes(Color(0.3, 0.8, 0.4))
	audio.play_enemy_telegraph()

func _resolve_hide() -> void:
	visual.modulate.a = 1.0
	var player = get_tree().get_first_node_in_group("player")
	if player == null or is_defeated:
		return
	# Flank to offset position
	var to_player: Vector3 = (player.global_position - global_position).normalized()
	var flank: Vector3 = Vector3(-to_player.z, 0, to_player.x) * orbit_direction * 3.0
	global_position = player.global_position + flank
	# Attack from flank
	if global_position.distance_to(player.global_position) <= 3.0:
		if player.has_method("notify_enemy_strike"):
			player.notify_enemy_strike(self, base_atk + 2, "melee_flank")
			CombatFx.spawn_slash(self, player.global_position + Vector3(0, 0.5, 0),
				Color(0.3, 0.8, 0.4, 0.9))
			CombatFx.impact(self, 0.20, 0.04, 0.15, 0.20)
	current_pattern = Pattern.RECOVER
	pattern_timer = 0.8

# === Ember Warden: frontal guard → zone hazard ===
func _begin_guard() -> void:
	current_pattern = Pattern.GUARD_SHIELD
	pattern_timer = 1.5
	burst_timer = burst_cooldown
	_guard_active = true
	_modulate_eyes(Color(1.0, 0.6, 0.2))
	audio.play_enemy_telegraph()
	CombatFx.spawn_ring(self, global_position + Vector3(0, 0.3, 0),
		3.0, Color(1.0, 0.5, 0.15, 0.5), 1.5)

func _resolve_guard() -> void:
	_guard_active = false
	var player = get_tree().get_first_node_in_group("player")
	if player == null or is_defeated:
		return
	if global_position.distance_to(player.global_position) <= burst_radius:
		if player.has_method("notify_enemy_strike"):
			player.notify_enemy_strike(self, burst_damage, "zone_hazard")
			CombatFx.spawn_burst(self, player.global_position + Vector3(0, 0.3, 0),
				Color(1.0, 0.5, 0.15, 0.8), 12, 4.0, 0.35, 0.14)
	current_pattern = Pattern.RECOVER
	pattern_timer = 0.8

# === Spore Weaver: place slow field → retreat ===
func _begin_retreat() -> void:
	current_pattern = Pattern.RETREAT
	pattern_timer = 0.6
	burst_timer = burst_cooldown
	_modulate_eyes(Color(0.5, 0.9, 0.3))
	audio.play_enemy_telegraph()
	CombatFx.spawn_ring(self, global_position + Vector3(0, 0.1, 0),
		4.0, Color(0.4, 0.8, 0.3, 0.4), 3.0)
	_spawn_burst_fx(Color(0.4, 0.8, 0.3, 0.5), 0.6, 10)

# === Relic Leech: drain heal from marked targets ===
func _begin_drain() -> void:
	current_pattern = Pattern.DRAIN
	pattern_timer = 1.0
	burst_timer = burst_cooldown
	_drain_target = get_tree().get_first_node_in_group("player")
	_modulate_eyes(Color(0.8, 0.3, 0.8))
	audio.play_enemy_telegraph()
	CombatFx.spawn_telegraph(self, global_position + Vector3(0, 0.4, 0),
		Color(0.8, 0.3, 0.8), true)

func _resolve_drain() -> void:
	var player = _drain_target
	_drain_target = null
	if player == null or is_defeated or not is_instance_valid(player):
		current_pattern = Pattern.RECOVER
		pattern_timer = 0.5
		return
	var dist := global_position.distance_to(player.global_position)
	if dist <= orbit_distance + 2.0:
		if player.has_method("notify_enemy_strike"):
			player.notify_enemy_strike(self, base_atk + 1, "draining_melee")
			CombatFx.spawn_slash(self, player.global_position + Vector3(0, 0.5, 0),
				Color(0.8, 0.3, 0.8, 0.9))
			CombatFx.impact(self, 0.18, 0.04, 0.14, 0.18)
		# Heal self
		var heal_amount := mini(5, max_hp - hp)
		hp += heal_amount
		FloatingText.spawn_on_entity(self, "+%d" % heal_amount, Color(0.4, 1.0, 0.4))
		current_pattern = Pattern.RECOVER
	pattern_timer = 0.6

# =====================================================================
# Special Skills — one unique ability per archetype
# Triggered when special_timer has elapsed while in ORBIT pattern.
# =====================================================================

## Begins the special-skill telegraph phase. Each archetype has its own
## telegraph VFX, audio cue, and eye-color flash.
func _begin_special_telegraph() -> void:
	current_pattern = Pattern.SPECIAL_TELEGRAPH
	pattern_timer = 0.9
	_special_active = true
	special_timer = special_cooldown
	_modulate_eyes(Color(1.0, 0.9, 0.2))
	animator.trigger_attack("enemy")
	if sfx_profile == "vanilla":
		audio.play_enemy_special()
	else:
		audio.play_profile_cue(sfx_profile, "cast")
	match archetype:
		"charger", "thorn_charger":
			CombatFx.spawn_ground_telegraph(self,
				global_position + Vector3(0, 0.1, 0), 6.0,
				Color(0.85, 0.45, 0.12, 0.55), 0.9)
		"ambusher":
			CombatFx.spawn_telegraph(self,
				global_position + Vector3(0, 0.3, 0),
				Color(0.9, 0.7, 0.2), true)
		"mire_stalker":
			CombatFx.spawn_ring(self, global_position + Vector3(0, 0.05, 0),
				5.0, Color(0.3, 0.9, 0.4, 0.35), 0.9)
		"ember_warden":
			CombatFx.spawn_ring(self, global_position + Vector3(0, 0.2, 0),
				4.5, Color(1.0, 0.45, 0.08, 0.5), 0.9)
		"spore_weaver":
			CombatFx.spawn_ring(self, global_position + Vector3(0, 0.1, 0),
				5.5, Color(0.55, 0.7, 0.3, 0.4), 0.9)
		"relic_leech":
			CombatFx.spawn_telegraph(self, global_position + Vector3(0, 0.2, 0),
				Color(0.55, 0.35, 0.95), true)
		"fenling":
			CombatFx.spawn_ground_telegraph(self,
				global_position + Vector3(0, 0.1, 0), 5.0,
				Color(0.4, 0.8, 1.0, 0.55), 0.9)
		"moonfen_fenling":
			CombatFx.spawn_ring(self, global_position + Vector3(0, 0.0, 0),
				6.5, Color(0.25, 0.6, 0.95, 0.45), 0.9)
		"elite":
			# Chain lightning arcs outward from the elite.
			var target := get_tree().get_first_node_in_group("player")
			if target is Node3D and is_instance_valid(target):
				var p3d := target as Node3D
				if global_position.distance_to(p3d.global_position) <= 6.0:
					CombatFx.spawn_vibrant_trail(self, global_position + Vector3(0, 0.3, 0),
						p3d.global_position + Vector3(0, 0.3, 0),
						Color(1.0, 0.4, 0.1, 0.95), Color(0.5, 0.85, 1.0, 0.85), 6)

## Resolves the telegraph into the actual special execution (per-archetype).
func _resolve_special_telegraph() -> void:
	current_pattern = Pattern.SPECIAL_ACTIVE
	pattern_timer = 0
	match archetype:
		"charger":
			_special_thorn_rush()
		"ambusher":
			_special_shadow_strike()
		"thorn_charger":
			_special_bramble_charge()
		"mire_stalker":
			_special_mire_cloak()
		"ember_warden":
			_special_inferno_shield()
		"spore_weaver":
			_special_spore_cloud()
		"relic_leech":
			_special_soul_siphon()
		"fenling":
			_special_frost_burst()
		"moonfen_fenling":
			_special_tidal_surge()
		"elite":
			_special_chain_lightning()
		_:
			# Default fallback: a simple AoE burst
			_perform_bramble_burst(get_tree().get_first_node_in_group("player"))
	_special_active = true

## Called each frame while the special is active; finishes the ability.
func _resolve_special_active() -> void:
	match archetype:
		"charger":
			_finish_thorn_rush()
		"thorn_charger":
			_finish_bramble_charge()
		"relic_leech":
			_finish_soul_siphon()
	# Other archetypes complete instantly on telegraph resolve — they just
	# need _resolve_special_active to flip back to RECOVER.
	current_pattern = Pattern.RECOVER
	pattern_timer = 0.85
	_special_active = false
	_cloak_active = false
	_shield_active = false

# =====================================================================
# Special Skills — one unique ability per archetype
# =====================================================================

## Charger: Thorn Rush — fast linear charge with knockback.
func _special_thorn_rush() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		current_pattern = Pattern.RECOVER
		pattern_timer = 0.85
		_special_active = false
		return
	_charge_target_pos = player.global_position
	velocity = Vector3.ZERO
	pattern_timer = 1.6
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.2, 0),
		Color(0.9, 0.5, 0.1, 0.9), 16, 4.0, 0.3, 0.14)

func _finish_thorn_rush() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player is Node3D and is_instance_valid(player):
		var p3d := player as Node3D
		var dist := global_position.distance_to(p3d.global_position)
		if dist <= 4.5:
			if p3d.has_method("notify_enemy_strike"):
				p3d.notify_enemy_strike(self, base_atk + 3, "charge_rush")
			if p3d.has_method("take_damage"):
				var knockback := global_position.direction_to(p3d.global_position)
				p3d.take_damage(base_atk + 3, knockback)
			if p3d.has_method("add_slow"):
				p3d.add_slow(0.30, 1.6)
			CombatFx.spawn_burst(self, p3d.global_position + Vector3(0, 0.4, 0),
				Color(1.0, 0.6, 0.15, 0.85), 12, 4.5, 0.4, 0.14)
			if sfx_profile == "vanilla":
				audio.play_enemy_hit()
			else:
				audio.play_profile_cue(sfx_profile, "bite")
	pattern_timer = 0

## Ambusher: Shadow Strike — teleport behind the player and crit-strike.
func _special_shadow_strike() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player is Node3D:
		var p3d := player as Node3D
		var target_pos := p3d.global_position
		var back_dir := -p3d.global_transform.basis.z
		target_pos += back_dir * 1.8
		target_pos.y = global_position.y
		global_position = target_pos
		if p3d.has_method("notify_enemy_strike"):
			p3d.notify_enemy_strike(self, base_atk + 4, "teleport_strike")
		if p3d.has_method("take_damage"):
			p3d.take_damage(base_atk + 4, target_pos.direction_to(p3d.global_position), true)
		if p3d.has_method("apply_elemental_status"):
			p3d.apply_elemental_status("shadow", 1)
		CombatFx.spawn_burst(self, global_position + Vector3(0, 0.2, 0),
			Color(0.9, 0.5, 0.2), 14, 4.0, 0.35, 0.12)
		CombatFx.impact(self, 0.22, 0.04, 0.18, 0.24)
		if sfx_profile == "vanilla":
			audio.play_enemy_attack()
		else:
			audio.play_profile_cue(sfx_profile, "attack")
		pattern_timer = 0

## Thorn Charger: Bramble Charge — heavy charge leaving a thorn trail.
func _special_bramble_charge() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player is Node3D:
		_charge_target_pos = (player as Node3D).global_position
	velocity = Vector3.ZERO
	_bramble_charge_trail = true
	_bramble_charge_start = global_position
	pattern_timer = 1.8
	CombatFx.spawn_ground_telegraph(self, global_position + Vector3(0, 0.1, 0),
		7.0, Color(0.8, 0.25, 0.08, 0.5), 1.4)

func _finish_bramble_charge() -> void:
	if not _bramble_charge_trail:
		return
	_bramble_charge_trail = false
	CombatFx.spawn_decal(self, global_position, 1.4,
		Color(0.6, 0.18, 0.06, 0.7), 4.0, 0.02, "crack")
	var player = get_tree().get_first_node_in_group("player")
	if player is Node3D and is_instance_valid(player):
		var p3d := player as Node3D
		var dist := global_position.distance_to(p3d.global_position)
		if dist <= 5.5:
			if p3d.has_method("notify_enemy_strike"):
				p3d.notify_enemy_strike(self, base_atk + 2, "charge_rush")
			if p3d.has_method("take_damage"):
				p3d.take_damage(base_atk + 2,
					global_position.direction_to(p3d.global_position))
			CombatFx.spawn_burst(self, p3d.global_position + Vector3(0, 0.4, 0),
				Color(0.85, 0.32, 0.08, 0.9), 14, 4.8, 0.4, 0.15)
	pattern_timer = 0

## Mire Stalker: Mire Cloak — brief invisibility + empowered next strike.
func _special_mire_cloak() -> void:
	_cloak_active = true
	visible = false
	attack_area.monitoring = false
	pattern_timer = 2.2
	CombatFx.spawn_ring(self, global_position + Vector3(0, 0.1, 0),
		4.0, Color(0.3, 0.9, 0.5, 0.3), 0.7)
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.2, 0),
		Color(0.28, 0.85, 0.45, 0.88), 10, 3.5, 0.6, 0.14)
	set_physics_process(false)
	var recloak := create_tween()
	recloak.tween_interval(2.2)
	recloak.tween_callback(_mire_cloak_expire)

func _mire_cloak_expire() -> void:
	_cloak_active = false
	visible = true
	attack_area.monitoring = true
	set_physics_process(true)
	CombatFx.spawn_ring(self, global_position + Vector3(0, 0.15, 0),
		3.0, Color(0.5, 1.0, 0.6), 0.35)

## Ember Warden: Inferno Shield — fire barrier for 3s that damages strikers.
func _special_inferno_shield() -> void:
	_shield_active = true
	pattern_timer = 3.0
	_modulate_eyes(Color(1.0, 0.35, 0.05))
	CombatFx.spawn_ring(self, global_position + Vector3(0, 0.15, 0),
		4.5, Color(1.0, 0.35, 0.08, 0.45), 3.0)
	var core_light := get_node_or_null("Visual/BrambleCoreLight")
	if core_light is OmniLight3D:
		core_light.light_energy = 3.0
		core_light.light_color = Color(1.0, 0.35, 0.06)
	var shield_tween := create_tween()
	shield_tween.tween_interval(3.0)
	shield_tween.tween_callback(_inferno_shield_expire)

func _inferno_shield_expire() -> void:
	_shield_active = false
	_modulate_eyes(Color(1.0, 0.6, 0.2))
	CombatFx.spawn_ring(self, global_position + Vector3(0, 0.15, 0),
		5.5, Color(1.0, 0.4, 0.1, 0.2), 0.5)

## Spore Weaver: Toxic Spore Cloud — lingering AoE poison cloud.
func _special_spore_cloud() -> void:
	_slow_field_pos = global_position
	_spore_timer = 5.0
	pattern_timer = 5.0
	CombatFx.spawn_ring(self, global_position + Vector3(0, 0.1, 0),
		5.5, Color(0.7, 0.45, 0.15, 0.35), 5.0)
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.25, 0),
		Color(0.55, 0.6, 0.18, 0.85), 12, 3.6, 0.25, 0.14)
	var tick := create_tween()
	tick.set_loops(5)
	tick.tween_interval(1.0)
	tick.tween_callback(_spore_tick)

func _spore_tick() -> void:
	if is_defeated:
		return
	CombatFx.spawn_ring(self, _slow_field_pos + Vector3(0, 0.05, 0),
		5.5, Color(0.65, 0.5, 0.2, 0.25), 0.9)
	var player = get_tree().get_first_node_in_group("player")
	if player is Node3D and is_instance_valid(player):
		var p3d := player as Node3D
		var dist := global_position.distance_to(p3d.global_position)
		if dist <= 5.5 and p3d.has_method("take_damage") \
				and not (p3d.has_method("is_airborne") and p3d.is_airborne()):
			p3d.take_damage(4, global_position.direction_to(p3d.global_position))
			FloatingText.spawn_on_entity(p3d, "-4", Color(0.7, 0.45, 0.15))

## Relic Leech: Soul Siphon — channel a life-drain beam for 2.4s.
func _special_soul_siphon() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player is Node3D:
		_soul_siphon_target = player as Node3D
		_soul_siphon_remaining = 2.4
		pattern_timer = 2.4
		_modulate_eyes(Color(0.8, 0.25, 0.95))
		CombatFx.spawn_telegraph(self, global_position + Vector3(0, 0.4, 0),
			Color(0.7, 0.45, 1.0), true)
		if sfx_profile == "vanilla":
			audio.play_enemy_special()
		else:
			audio.play_profile_cue(sfx_profile, "cast")
		_soul_siphon_tick()
	else:
		current_pattern = Pattern.RECOVER
		pattern_timer = 0.85
		_special_active = false

func _soul_siphon_tick() -> void:
	if _soul_siphon_target == null or not is_instance_valid(_soul_siphon_target) \
			or is_defeated:
		return
	_soul_siphon_remaining -= 0.4
	var tick_dmg := 3
	if _soul_siphon_target.has_method("take_damage"):
		_soul_siphon_target.take_damage(tick_dmg,
			global_position.direction_to(_soul_siphon_target.global_position))
	FloatingText.spawn_on_entity(self, "+%d" % tick_dmg, Color(0.7, 0.45, 1.0))
	if sfx_profile == "vanilla":
		audio.play_enemy_hit()
	else:
		audio.play_profile_cue(sfx_profile, "hit")
	if _soul_siphon_remaining > 0.0:
		var t := get_tree().create_timer(0.4, false)
		t.timeout.connect(_soul_siphon_tick)

func _finish_soul_siphon() -> void:
	_soul_siphon_target = null
	_soul_siphon_remaining = 0.0
	if is_inside_tree():
		CombatFx.spawn_ring(self, global_position + Vector3(0, 0.3, 0),
			4.0, Color(0.6, 0.35, 0.95, 0.3), 0.4)

## Fenling: Frost Burst — AoE frost nova that slows movement.
func _special_frost_burst() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player is Node3D and is_instance_valid(player):
		var p3d := player as Node3D
		var dist := global_position.distance_to(p3d.global_position)
		if dist <= 5.5:
			if not (p3d.has_method("is_airborne") and p3d.is_airborne()):
				if p3d.has_method("take_damage"):
					p3d.take_damage(8, global_position.direction_to(p3d.global_position))
				if p3d.has_method("add_slow"):
					p3d.add_slow(0.45, 2.5)
				if p3d.has_method("apply_elemental_status"):
					p3d.apply_elemental_status("frost", 2)
				FloatingText.spawn_on_entity(p3d, "-8", Color(0.5, 0.85, 1.0))
	CombatFx.spawn_ring(self, global_position + Vector3(0, 0.15, 0),
		5.5, Color(0.45, 0.88, 1.0, 0.6), 2.0)
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.25, 0),
		Color(0.35, 0.78, 1.0, 0.85), 14, 4.2, 0.5, 0.16)
	if sfx_profile == "vanilla":
		audio.play_enemy_telegraph()
	else:
		audio.play_profile_cue(sfx_profile, "telegraph")

## Moonfen Fenling: Tidal Surge — water blast that pushes the player back.
func _special_tidal_surge() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player is Node3D and is_instance_valid(player):
		var p3d := player as Node3D
		var to_player := (p3d.global_position - global_position).normalized()
		var dist := global_position.distance_to(p3d.global_position)
		if dist <= 5.0:
			if p3d.has_method("take_damage"):
				var knockback := to_player * 6.0
				p3d.take_damage(9, knockback)
				FloatingText.spawn_on_entity(p3d, "-9", Color(0.4, 0.78, 1.0))
			if p3d.has_method("apply_elemental_status"):
				p3d.apply_elemental_status("water", 1)
			if p3d.has_method("add_slow"):
				p3d.add_slow(0.25, 1.8)
		CombatFx.spawn_ring(self, global_position + Vector3(0, 0.1, 0),
		6.0, Color(0.25, 0.62, 0.95, 0.55), 0.8)
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.3, 0),
		Color(0.3, 0.7, 1.0, 0.85), 16, 5.0, 0.4, 0.15)
	if sfx_profile == "vanilla":
		audio.play_enemy_special()
	else:
		audio.play_profile_cue(sfx_profile, "cast")

## Elite: Chain Lightning — arcs between all enemies and the player,
## dealing moderate nature damage and applying shock.
func _special_chain_lightning() -> void:
	var targets: Array[Node3D] = []
	var player = get_tree().get_first_node_in_group("player")
	if player is Node3D and is_instance_valid(player):
		targets.append(player as Node3D)
	for foe in get_tree().get_nodes_in_group("enemy"):
		if foe == self or not is_instance_valid(foe) or not (foe is Node3D):
			continue
		var f3d := foe as Node3D
		if global_position.distance_to(f3d.global_position) <= 7.0:
			targets.append(f3d)
	if targets.is_empty():
		current_pattern = Pattern.RECOVER
		pattern_timer = 0.85
		_special_active = false
		return
	var arc_color := Color(1.0, 0.85, 0.25, 0.95)
	for i in range(targets.size() - 1):
		CombatFx.spawn_vibrant_trail(self,
			targets[i].global_position + Vector3(0, 0.35, 0),
			targets[i + 1].global_position + Vector3(0, 0.35, 0),
			arc_color, Color(0.5, 0.85, 1.0, 0.85), 5)
	for target in targets:
		if target.has_method("take_damage"):
			target.take_damage(9, global_position.direction_to(target.global_position))
		if target.has_method("apply_elemental_status"):
			target.apply_elemental_status("shock", 1)
		FloatingText.spawn_on_entity(target, "-9", Color(1.0, 0.85, 0.25))
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.35, 0),
		arc_color, 18, 4.5, 0.35, 0.14)
	if sfx_profile == "vanilla":
		audio.play_enemy_special()
	else:
		audio.play_profile_cue(sfx_profile, "cast")

func _perform_bramble_burst(player: Node3D) -> void:
	if not burst_active:
		return
	burst_active = false
	burst_timer = burst_cooldown
	if thorn_volley:
		_thorn_volley(player)
		return
	if sfx_profile == "vanilla":
		audio.play_enemy_special()
	else:
		audio.play_profile_cue(sfx_profile, "cast")
	_spawn_burst_fx(Color(0.72, 0.22, 0.12, 0.85), 0.48, 32)
	if global_position.distance_to(player.global_position) <= burst_radius:
		# Ground eruption can't touch an airborne target
		if player.has_method("is_airborne") and player.is_airborne():
			FloatingText.spawn_on_entity(player, "miss", Color(0.8, 0.8, 0.7))
			return
		if player.has_method("take_damage"):
			player.take_damage(burst_damage, global_position.direction_to(player.global_position))
			FloatingText.spawn_on_entity(player, str(burst_damage), Color(1.0, 0.35, 0.2))

## Hard-tier burst: three delayed spikes chase the player's position —
## same delayed-damage pattern the Matriarch's thorn rain uses.
func _thorn_volley(player: Node3D) -> void:
	if sfx_profile == "vanilla":
		audio.play_enemy_telegraph()
	else:
		audio.play_profile_cue(sfx_profile, "telegraph")
	for s in 3:
		# Lock each strike to the player’s telegraph position. The player can
		# dodge out before impact instead of being checked against its new position.
		var target_pos: Vector3 = player.global_position
		var timer := get_tree().create_timer(0.35 + 0.30 * s, false)
		timer.timeout.connect(_volley_spike.bind(player, target_pos,
			clampi(burst_damage - 2, 3, 6)))

func _volley_spike(player: Node3D, pos: Vector3, damage: int) -> void:
	if is_defeated or player == null or not is_instance_valid(player):
		return
	CombatFx.spawn_ring(self, pos, 2.2, Color(1, 0.45, 0.18, 0.6), 0.5)
	CombatFx.spawn_burst(self, pos + Vector3(0, 0.3, 0),
		Color(0.75, 0.22, 0.12, 0.85), 10, 4.5, 0.35, 0.16)
	if pos.distance_to(player.global_position) <= 2.2:
		if player.has_method("is_airborne") and player.is_airborne():
			return
		if player.has_method("take_damage"):
			player.take_damage(damage, pos.direction_to(player.global_position))

func _spawn_burst_fx(color: Color, lifetime: float, amount: int) -> void:
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.35, 0),
		color, amount, 3.8, lifetime, 0.18)

func _update_movement(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	var to_player = (player.global_position - global_position).normalized()
	var dist = global_position.distance_to(player.global_position)
	
	var dir_x: float = 0
	var dir_z: float = 0
	var speed: float = 0
	
	var side = Vector3(-to_player.z, 0, to_player.x) * orbit_direction
	
	match current_pattern:
		Pattern.ORBIT:
			dir_x = side.x * 0.8 + to_player.x * ((dist - orbit_distance) * 0.02)
			dir_z = side.z * 0.8 + to_player.z * ((dist - orbit_distance) * 0.02)
			speed = orbit_speed
			
		Pattern.FEINT:
			dir_x = side.x * 0.9 - to_player.x * 0.72
			dir_z = side.z * 0.9 - to_player.z * 0.72
			speed = feint_speed
			
		Pattern.LUNGE:
			dir_x = to_player.x
			dir_z = to_player.z
			speed = lunge_speed
			
		Pattern.WINDUP:
			pass  # planted feet while the strike charges

		Pattern.CHARGE_TELEGRAPH:
			pass  # planted during telegraph

		Pattern.CHARGE_RUSH:
			var rush_dir := (_charge_target_pos - global_position).normalized()
			dir_x = rush_dir.x
			dir_z = rush_dir.z
			speed = lunge_speed * 1.3

		Pattern.HIDE:
			pass  # stationary while hidden

		Pattern.GUARD_SHIELD:
			pass  # planted during guard

		Pattern.RETREAT:
			dir_x = -to_player.x * 0.8
			dir_z = -to_player.z * 0.8
			speed = feint_speed * 1.1

		Pattern.DRAIN:
			dir_x = to_player.x * 0.3
			dir_z = to_player.z * 0.3
			speed = orbit_speed * 0.5

		Pattern.SPECIAL_TELEGRAPH:
			pass  # planted during telegraph wind-up

		Pattern.SPECIAL_ACTIVE:
			match archetype:
				"charger":
					var rush_dir := (_charge_target_pos - global_position).normalized()
					dir_x = rush_dir.x
					dir_z = rush_dir.z
					speed = lunge_speed * 1.4
				"thorn_charger":
					var rush_dir := (_charge_target_pos - global_position).normalized()
					dir_x = rush_dir.x
					dir_z = rush_dir.z
					speed = lunge_speed * 1.2

		Pattern.RECOVER:
			dir_x = side.x * 0.45 + to_player.x * ((dist - orbit_distance) * 0.03)
			dir_z = side.z * 0.45 + to_player.z * ((dist - orbit_distance) * 0.03)
			speed = recover_speed
	
	if elemental_status != null and elemental_status.has_method("movement_multiplier"):
		speed *= float(elemental_status.movement_multiplier())
	velocity.x = lerp(velocity.x, dir_x * speed + knockback_velocity.x, 1.0 - exp(-delta * 10.0))
	velocity.z = lerp(velocity.z, dir_z * speed + knockback_velocity.z, 1.0 - exp(-delta * 10.0))
	velocity.y = 0

func _update_visuals(delta: float) -> void:
	# Move ratio drives squash-stretch
	animator.set_move_ratio(clampf(velocity.length() / max(lunge_speed, 0.01), 0.0, 1.0))

	# Eye glow: size + intensity respond to current combat pattern
	var base_pulse := 0.7 + sin(bob_timer * 3.0) * 0.25
	var pattern_scale := _eye_scale_for_pattern()
	for eye in eyes.get_children():
		if eye.material_override:
			eye.material_override.set_shader_parameter("glow_intensity", base_pulse * pattern_scale)
		# Scale eyes slightly per pattern so they visibly widen on lunge
		eye.scale = Vector3.ONE * lerpf(eye.scale.x, pattern_scale, delta * 8.0)

	# Tendrils: spiral drift with per-tendril phase offset
	var count := maxf(tendrils.get_child_count(), 1.0)
	for i in tendrils.get_child_count():
		var tendril = tendrils.get_child(i)
		var ph := bob_timer * 1.35 + float(i) * TAU / count
		tendril.rotation.x = -PI / 3 + cos(ph) * 0.15
		tendril.rotation.z = sin(ph) * 0.19
		tendril.rotation.y = sin(ph * 0.7 + float(i)) * 0.12

	# Shield disc visibility (ember_warden)
	var shield_disc := visual.get_node_or_null("ShieldDisc")
	if shield_disc != null:
		shield_disc.visible = _shield_active

	bob_timer += delta * 2.45

func _modulate_eyes(color: Color) -> void:
	for eye in eyes.get_children():
		if eye.material_override is ShaderMaterial:
			eye.material_override.set_shader_parameter("emission_color", color)
			eye.material_override.set_shader_parameter("flash_color", color)
			eye.material_override.set_shader_parameter("flash_intensity", 0.6)

func _on_hitbox_entered(area: Area3D) -> void:
	if area.is_in_group("player_attack"):
		# Only a committed swing can hurt — the hero's `AttackArea` body stays
		# live so we don't get hurt from just walking past.
		var hero := area.get_parent()
		if hero == null or not hero.has_method("get_attack_window") \
				or not hero.call("get_attack_window"):
			return
		var dmg = 0
		if hero.has_method("get_last_strike_damage"):
			dmg = hero.get_last_strike_damage()
		else:
			dmg = 8  # Default
		take_damage(dmg, area.global_position.direction_to(global_position))

func _on_attack_area_entered(area: Area3D) -> void:
	if area.is_in_group("player") and current_pattern == Pattern.LUNGE and not lunge_hit:
		lunge_hit = true
		var dmg = base_atk + 1
		var target := area.get_parent() as Node3D
		if target != null and target.has_method("notify_enemy_strike"):
			target.notify_enemy_strike(self, dmg, "lunge_thrust")
			var hit_pos := target.global_position + Vector3(0, 0.65, 0)
			CombatFx.spawn_slash(self, hit_pos, Color(1.0, 0.30, 0.16, 0.9))
			CombatFx.spawn_burst(self, hit_pos, Color(1.0, 0.48, 0.18, 0.75), 10, 4.2, 0.28, 0.12)
			CombatFx.impact(self, 0.16, 0.035, 0.16, 0.18)
			print("Bramble Skitter catches your flank for %d warmth." % dmg)
			if sfx_profile == "vanilla":
				audio.play_hit()
			else:
				audio.play_profile_cue(sfx_profile, "stomp")

func take_damage(amount: int, knockback_dir: Vector3, critical: bool = false) -> void:
	if is_defeated:
		return

	# Ember Warden: Inferno Shield reflects melee strikes as fire damage.
	if _shield_active:
		var hero = get_tree().get_first_node_in_group("player")
		if hero != null and hero is Node3D:
			if hero.has_method("take_damage"):
				hero.take_damage(5, global_position.direction_to(hero.global_position))
			if hero.has_method("apply_elemental_status"):
				hero.apply_elemental_status("fire", 1)
				CombatFx.spawn_burst(self, global_position + Vector3(0, 0.35, 0),
					Color(1.0, 0.4, 0.1, 0.9), 10, 3.5, 0.3, 0.14)
		_shield_active = false

	# Mire Stalker: Mire Cloak renders it untargetable while hidden.
	if _cloak_active:
		return

	# Guard blocks damage from front
	if _guard_active:
		var hero = get_tree().get_first_node_in_group("player")
		if hero != null:
			var to_hero: Vector3 = (hero.global_position - global_position).normalized()
			var forward: Vector3 = -global_transform.basis.z
			if to_hero.dot(forward) > 0.3:
				FloatingText.spawn_on_entity(self, "Blocked", Color(0.8, 0.8, 0.6))
				return
	
	hp -= amount
	FloatingText.spawn_damage_on_entity(self, amount, critical)
	var health_bar := get_node_or_null("EnemyHealthBar")
	if health_bar != null and health_bar.has_method("notify_damage"):
		health_bar.notify_damage()
	animator.trigger_hit()
	
	# Stagger check
	_stagger_cooldown -= 0.0
	if amount >= _stagger_threshold and _stagger_cooldown <= 0:
		_apply_stagger()
	
	# Visual feedback
	var tween = create_tween()
	tween.tween_property(body, "material_override:shader_parameter/flash_intensity", 1.0, 0.05)
	tween.tween_property(body, "material_override:shader_parameter/flash_intensity", 0.0, 0.15)
	# Battle wear: the creature visibly scuffs as it breaks down
	if body.material_override is ShaderMaterial:
		var ratio := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
		body.material_override.set_shader_parameter("hp_wear",
			clampf((0.45 - ratio) / 0.45, 0.0, 1.0) * 0.8)
	
	# Knockback — a firm nudge so the blob doesn't rocket across the arena
	knockback_velocity = knockback_dir * (amount * 3.5)
	
	# Pattern interrupt
	if current_pattern == Pattern.LUNGE:
		current_pattern = Pattern.RECOVER
		pattern_timer = 0.56
	elif current_pattern == Pattern.WINDUP:
		# Striking a winding-up sprite cancels its answer — aggression
		# suppresses counters but never stunlock-repeats them.
		current_pattern = Pattern.RECOVER
		pattern_timer = 0.4
	elif current_pattern in [Pattern.CHARGE_TELEGRAPH, Pattern.CHARGE_RUSH]:
		current_pattern = Pattern.RECOVER
		pattern_timer = 0.8
	elif current_pattern == Pattern.GUARD_SHIELD:
		_guard_active = false
		current_pattern = Pattern.RECOVER
		pattern_timer = 0.5
	elif current_pattern in [Pattern.HIDE, Pattern.SPECIAL_TELEGRAPH, Pattern.SPECIAL_ACTIVE]:
		# Mire Cloak / special telegraph cannot be interrupted mid-cast
		# (cloak is immune at the top of take_damage; specials self-heal
		# on interrupt by returning to RECOVER after their timer ends).
		current_pattern = Pattern.RECOVER
		pattern_timer = 0.4
	elif current_pattern == Pattern.BRAMBLE_BURST:
		current_pattern = Pattern.RECOVER
		pattern_timer = 0.5
	else:
		var hero2 = get_tree().get_first_node_in_group("player")
		var can_counter := counter_timer <= 0.0 and hp > 0 \
				and hero2 != null and is_instance_valid(hero2) \
				and global_position.distance_to(hero2.global_position) \
						<= counter_range * 1.4
		if can_counter:
			_begin_counter_windup()
		else:
			current_pattern = Pattern.RECOVER
			pattern_timer = 0.32
	
	if hp <= 0:
		die()

func _apply_stagger() -> void:
	_stagger_cooldown = 4.0
	current_pattern = Pattern.RECOVER
	pattern_timer = 0.8
	animator.trigger_hit()
	_modulate_eyes(Color(1.0, 1.0, 0.5))
	CombatFx.spawn_ring(self, global_position + Vector3(0, 0.3, 0),
		1.5, Color(1.0, 1.0, 0.5, 0.6), 0.4)
	FloatingText.spawn_on_entity(self, "Staggered", Color(1.0, 0.9, 0.3))

## Telegraphed answer to a melee strike: eyes flash red, a ground ring marks
## the blast radius, then a claw swipe resolves. Dodge through it for a
## perfect-dodge reward; leave the ring or stay airborne to whiff it.
func _begin_counter_windup() -> void:
	current_pattern = Pattern.WINDUP
	pattern_timer = counter_windup
	counter_timer = counter_cooldown
	lunge_hit = false
	burst_active = false
	_modulate_eyes(Color(1, 0.25, 0.15))
	animator.trigger_attack("enemy")
	if sfx_profile == "vanilla":
		audio.play_enemy_telegraph()
	else:
		audio.play_profile_cue(sfx_profile, "telegraph")
	CombatFx.spawn_telegraph(self, global_position + Vector3(0, 0.35, 0),
		Color(1.0, 0.32, 0.18), true)
	CombatFx.spawn_ground_telegraph(self, global_position, counter_range,
		Color(1.0, 0.45, 0.18), counter_windup)

func _resolve_counter_strike() -> void:
	current_pattern = Pattern.RECOVER
	pattern_timer = 0.56
	var player = get_tree().get_first_node_in_group("player")
	if is_defeated or player == null or not is_instance_valid(player):
		return
	CombatFx.spawn_slash(self, global_position + Vector3(0, 0.5, 0),
		Color(1.0, 0.4, 0.2, 0.9))
	var dist := global_position.distance_to(player.global_position)
	if dist > counter_range + 0.8:
		return  # dodged out of reach — strike whiffs
	if player.has_method("is_airborne") and player.is_airborne():
		return
	if player.has_method("notify_enemy_strike"):
		player.notify_enemy_strike(self, base_atk + 1, "counter_strike")
		CombatFx.impact(self, 0.20, 0.045, 0.14, 0.22)
		if sfx_profile == "vanilla":
			audio.play_hit()
		else:
			audio.play_profile_cue(sfx_profile, "stomp")

func die() -> void:
	is_defeated = true
	collision_layer = 0
	collision_mask = 0
	# Clean up special-skill state to prevent orphaned tweens / callbacks.
	_special_active = false
	_cloak_active = false
	_shield_active = false
	_soul_siphon_target = null
	_bramble_charge_trail = false
	_slow_field_pos = Vector3.ZERO
	_spore_timer = 0.0
	set_physics_process(false)
	# die() can run from inside the hitbox's own signal callback —
	# physics state changes must be deferred there.
	hitbox.set_deferred("monitoring", false)
	attack_area.set_deferred("monitoring", false)

	# Death: the husk becomes a physical tumble corpse right away — the
	# killing shove sends it bouncing while the kill flow completes.
	animator.anim_state = EntityAnimator.AnimState.DEAD
	_launch_death_corpse()
	var tween = create_tween()
	tween.tween_interval(0.72)
	tween.tween_callback(_on_death_animation_finished)

	audio.play_cue("hushling_death")
	audio.play_defeat()
	# Loot table drops
	_spawn_loot()
	# Rare elite glint: diamonds stay luck-independent by design
	if thorn_volley and randf() < 0.05:
		CombatFx.spawn_burst(self, global_position + Vector3(0, 0.6, 0),
			Color(0.55, 0.85, 1.0, 0.95), 18, 4.5, 0.7, 0.14)
		game_state.add_diamonds(1, "💎 +1 diamond — a rare glint settles in your palm.")

## Hand the bramble husk to the pooled tumble-corpse system: a killing
## shove away from the hero plus spin; the husk bounces, settles, sinks.
func _launch_death_corpse() -> void:
	_do_launch_death_corpse.call_deferred()

func _do_launch_death_corpse() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null or not is_inside_tree():
		return
	var killer := get_tree().get_first_node_in_group("player")
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	if killer is Node3D:
		dir = killer.global_position.direction_to(global_position)
		dir.y = 0.0
	TumbleCorpse.max_corpses = _corpse_budget()
	TumbleCorpse.launch(visual,
		dir * randf_range(3.0, 4.6) + Vector3.UP * randf_range(2.2, 3.2))

func _corpse_budget() -> int:
	var qs := get_node_or_null("/root/WorldState/QualityScaler")
	return qs.corpse_pool_size if qs != null else 6

func _spawn_loot() -> void:
	var archetype_key := "hushling"
	if thorn_volley:
		archetype_key = "elite"
	elif archetype == "charger":
		archetype_key = "charger"
	elif archetype == "ambusher":
		archetype_key = "ambusher"
	var result := LootTable.roll_enemy(archetype_key)
	var drop_pos := global_position + Vector3(0, 0.3, 0)
	if result.gold > 0:
		LootDrop.spawn_gold(self, drop_pos, result.gold)
	for mat in result.materials:
		game_state.add_material(mat.id, mat.qty)
		FloatingText.spawn_on_entity(self, "+%d %s" % [mat.qty, game_state.MATERIAL_DEFS.get(mat.id, {}).get("name", mat.id)],
			Color(0.52, 0.90, 1.0), 1.1)
	if result.gear != null:
		var gear: Dictionary = result.gear
		var item_id := "moss_tonic"
		LootDrop.spawn_item(self, drop_pos + Vector3(0.2, 0, 0), item_id, 1, gear.rarity)

func _on_death_animation_finished() -> void:
	var sm := get_node_or_null("/root/StoryManager")
	if sm != null and sm.has_method("notify_objective"):
		sm.notify_objective("kill", archetype, 1)
	died.emit()
	queue_free()

func is_dead() -> bool:
	return is_defeated

func apply_elemental_status(element: String, intensity: int = 1) -> void:
	if elemental_status != null and elemental_status.has_method("apply"):
		elemental_status.apply(element, intensity)

func get_elemental_status_snapshot() -> Dictionary:
	if elemental_status != null and elemental_status.has_method("status_snapshot"):
		return elemental_status.status_snapshot()
	return {}

func set_max_hp(value: int) -> void:
	max_hp = value
	hp = value

func set_base_atk(value: int) -> void:
	base_atk = value

func set_burst_cooldown(value: float) -> void:
	burst_cooldown = maxf(1.0, value)
	burst_timer = minf(burst_timer, burst_cooldown)

func get_last_strike_damage() -> int:
	# For auto-strike callbacks
	return 8  # Base damage

## === Archetype model helpers (added by model-improvements) ===

func _archetype_body_scale() -> Vector3:
	match archetype:
		"charger", "thorn_charger":
			return Vector3(1.18, 1.14, 1.18)   # bigger, more mass
		"ambusher", "mire_stalker":
			return Vector3(0.88, 0.78, 0.88)   # smaller, flatter silhouette
		"ember_warden":
			return Vector3(1.08, 1.20, 1.08)   # tall and wide
		"fenling", "moonfen_fenling":
			return Vector3(0.92, 0.70, 0.92)   # low-skimming
		"spore_weaver":
			return Vector3(1.04, 0.96, 1.04)   # round
		_:
			return Vector3.ONE

func _archetype_core_color() -> Color:
	match archetype:
		"charger", "thorn_charger":
			return Color(1.00, 0.28, 0.08)  # orange-red
		"ambusher":
			return Color(0.36, 0.78, 0.56)  # green
		"mire_stalker":
			return Color(0.32, 0.78, 0.82)  # cyan
		"ember_warden":
			return Color(1.00, 0.30, 0.08)  # deep orange
		"spore_weaver":
			return Color(0.64, 0.88, 0.34)  # acid green
		"relic_leech":
			return Color(0.46, 0.76, 1.00)  # blue
		"fenling", "moonfen_fenling":
			return Color(0.30, 0.82, 0.94)  # ice blue
		_:
			return Color(0.16, 1.00, 0.38)  # default bramble green

func _archetype_crown_data() -> Array:
	# [thorn_count, lean_per_unit, height, bottom_radius]
	match archetype:
		"charger", "thorn_charger":
			return [5, 0.38, 0.52, 0.10]  # more, shorter, thicker
		"ember_warden":
			return [4, 0.28, 0.60, 0.09]
		"fenling", "moonfen_fenling":
			return [2, 0.20, 0.28, 0.06]  # minimal crown, low profile
		"ambusher":
			return [3, 0.44, 0.44, 0.07]
		_:
			return [3, 0.34, 0.38, 0.075]

func _dark_thorn_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.13, 0.08)
	m.roughness    = 0.9
	return m

func _build_legs(mat: Material) -> void:
	var leg_mesh := CapsuleMesh.new()
	leg_mesh.radius = 0.055
	leg_mesh.height = 0.26
	for side in [-1.0, 1.0]:
		for row in 2:
			var leg := MeshInstance3D.new()
			leg.mesh              = leg_mesh
			leg.material_override = mat
			leg.position          = Vector3(0.2 * side, -0.24, -0.1 + row * 0.2)
			leg.rotation.x        = 0.35 if row == 0 else -0.35
			visual.add_child(leg)

func _build_default_claws(mat: Material) -> void:
	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.05
	arm_mesh.height = 0.3
	var claw_tip := CylinderMesh.new()
	claw_tip.top_radius      = 0.0
	claw_tip.bottom_radius   = 0.045
	claw_tip.height          = 0.2
	claw_tip.radial_segments = 5
	for side in [-1.0, 1.0]:
		var claw_arm := MeshInstance3D.new()
		claw_arm.name             = "ClawArm"
		claw_arm.mesh             = arm_mesh
		claw_arm.material_override = mat
		claw_arm.position         = Vector3(0.24 * side, 0.02, 0.28)
		claw_arm.rotation         = Vector3(-0.35, 0, -0.5 * side)
		visual.add_child(claw_arm)
		var claw := MeshInstance3D.new()
		claw.name              = "ClawTip"
		claw.mesh              = claw_tip
		claw.material_override = mat
		claw.position          = Vector3(0.38 * side, -0.08, 0.42)
		claw.rotation          = Vector3(-0.75, 0, -0.65 * side)
		visual.add_child(claw)

func _build_ram_horns(mat: Material) -> void:
	var horn_mesh := CylinderMesh.new()
	horn_mesh.top_radius      = 0.0
	horn_mesh.bottom_radius   = 0.065
	horn_mesh.height          = 0.58
	horn_mesh.radial_segments = 6
	for side in [-1.0, 1.0]:
		var horn := MeshInstance3D.new()
		horn.name              = "RamHorn"
		horn.mesh              = horn_mesh
		horn.material_override = mat
		# Angled forward and outward from the crown
		horn.position = Vector3(0.28 * side, 0.52, 0.18)
		horn.rotation = Vector3(-0.65, 0.0, -0.55 * side)
		visual.add_child(horn)
	# Extra back spine for mass
	var spine := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.0; sm.bottom_radius = 0.05; sm.height = 0.42; sm.radial_segments = 5
	spine.mesh = sm; spine.material_override = mat
	spine.position = Vector3(0, 0.34, -0.22)
	spine.rotation.x = 0.55
	visual.add_child(spine)

func _build_fin_crest(mat: Material) -> void:
	var fin_mesh := CapsuleMesh.new()
	fin_mesh.radius = 0.035
	fin_mesh.height = 0.62
	var fin := MeshInstance3D.new()
	fin.name              = "DorsalFin"
	fin.mesh              = fin_mesh
	fin.material_override = mat
	fin.position = Vector3(0.0, 0.38, -0.06)
	fin.rotation.x = 0.12   # slight forward lean
	fin.rotation.z = PI * 0.5   # lay the capsule flat = dorsal ridge
	visual.add_child(fin)
	# Two small side barbs
	for side in [-1.0, 1.0]:
		var barb := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.0; bm.bottom_radius = 0.025; bm.height = 0.26; bm.radial_segments = 4
		barb.mesh = bm; barb.material_override = mat
		barb.position = Vector3(0.18 * side, 0.30, -0.10)
		barb.rotation = Vector3(0.25, 0.0, -0.70 * side)
		visual.add_child(barb)

func _build_shield_disc() -> void:
	var shield_mat := StandardMaterial3D.new()
	shield_mat.albedo_color  = Color(0.55, 0.16, 0.05, 0.88)
	shield_mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_mat.emission_enabled = true
	shield_mat.emission      = Color(1.00, 0.30, 0.08)
	shield_mat.emission_energy_multiplier = 1.2
	var disc := MeshInstance3D.new()
	disc.name   = "ShieldDisc"
	var cm := CylinderMesh.new()
	cm.top_radius    = 0.55
	cm.bottom_radius = 0.55
	cm.height        = 0.06
	cm.radial_segments = 16
	disc.mesh              = cm
	disc.material_override = shield_mat
	disc.position          = Vector3(0.0, 0.08, 0.56)
	disc.rotation.x        = PI * 0.5
	disc.visible           = false   # activated by _shield_active logic
	visual.add_child(disc)
	# Pulse when visible
	var tw := disc.create_tween().set_loops()
	tw.tween_property(shield_mat, "emission_energy_multiplier", 2.2, 0.65).set_trans(Tween.TRANS_SINE)
	tw.tween_property(shield_mat, "emission_energy_multiplier", 0.8, 0.65).set_trans(Tween.TRANS_SINE)

func _build_spore_sacs(mat: Material) -> void:
	var sac_mat := StandardMaterial3D.new()
	sac_mat.albedo_color        = Color(0.36, 0.50, 0.18)
	sac_mat.emission_enabled    = true
	sac_mat.emission            = Color(0.52, 0.78, 0.24)
	sac_mat.emission_energy_multiplier = 0.55
	sac_mat.roughness           = 0.7
	for i in 3:
		var side := (i % 2) * 2.0 - 1.0
		var sac := MeshInstance3D.new()
		sac.name = "SporeSac_%d" % i
		var sm := SphereMesh.new()
		sm.radius = 0.10 + 0.04 * float(i % 2)
		sm.height  = sm.radius * 1.5
		sac.mesh              = sm
		sac.material_override = sac_mat
		sac.position = Vector3(0.30 * side, -0.08 + float(i) * 0.14, -0.12)
		visual.add_child(sac)
		# Gentle throb
		var tw := sac.create_tween().set_loops()
		tw.tween_property(sac, "scale", Vector3.ONE * 1.18, 0.9 + float(i) * 0.15).set_trans(Tween.TRANS_SINE)
		tw.tween_property(sac, "scale", Vector3.ONE * 0.90, 0.9 + float(i) * 0.15).set_trans(Tween.TRANS_SINE)

func _build_stalker_fins(mat: Material) -> void:
	for side in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		fin.name = "StalkerFin"
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0; cm.bottom_radius = 0.04; cm.height = 0.48; cm.radial_segments = 5
		fin.mesh = cm; fin.material_override = mat
		fin.position = Vector3(0.28 * side, 0.12, -0.15)
		fin.rotation = Vector3(0.30, 0.0, -1.05 * side)
		visual.add_child(fin)

func _build_leech_suckers(mat: Material) -> void:
	var sucker_mat := StandardMaterial3D.new()
	sucker_mat.albedo_color = Color(0.30, 0.22, 0.44)
	sucker_mat.emission_enabled = true
	sucker_mat.emission = Color(0.46, 0.76, 1.0)
	sucker_mat.emission_energy_multiplier = 0.7
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var sucker := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.06; sm.bottom_radius = 0.06; sm.height = 0.04; sm.radial_segments = 8
		sucker.mesh = sm; sucker.material_override = sucker_mat
		sucker.position = Vector3(cos(angle) * 0.20, sin(angle) * 0.20, 0.44)
		sucker.rotation.x = PI * 0.5
		visual.add_child(sucker)

func _eye_scale_for_pattern() -> float:
	match current_pattern:
		Pattern.LUNGE, Pattern.CHARGE_RUSH, Pattern.WINDUP:
			return 1.55   # wide, aggressive
		Pattern.FEINT, Pattern.SPECIAL_TELEGRAPH:
			return 1.25
		Pattern.HIDE:
			return 0.45   # narrowed/hidden
		Pattern.RECOVER:
			return 0.85
		_:
			return 1.0

