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

enum Pattern { ORBIT, FEINT, LUNGE, WINDUP, RECOVER, BRAMBLE_BURST }

@export var max_hp: int = 28
@export var base_atk: int = 3
@export var move_speed: float = 6.5
@export var orbit_distance: float = 72.0 / 10.0  # 7.2 units (STANDOFF converted)
@export var lunge_speed: float = 20.8
@export var feint_speed: float = 12.8
@export var orbit_speed: float = 5.0
@export var recover_speed: float = 6.2
@export var burst_cooldown: float = 5.5
@export var burst_radius: float = 3.8
@export var burst_damage: int = 6
# Hard-tier flag: bursts become a tracking 3-spike thorn volley.
@export var thorn_volley: bool = false

# Telegraphed counter-strike: after being struck in melee range the sprite
# winds up visibly before answering. Dodging through the strike is rewarded.
@export var counter_windup: float = 0.55
@export var counter_range: float = 2.3
@export var counter_cooldown: float = 2.5
var counter_timer: float = 0.0

# Realm/boss SFX preset id ("vanilla" keeps the original cues).
var sfx_profile: String = "vanilla"

var hp: int = 28
var current_pattern: Pattern = Pattern.ORBIT
var pattern_timer: float = 0.9
var lunge_cooldown: float = 2.7
var burst_timer: float = 2.5
var burst_active: bool = false
var lunge_hit: bool = false
var orbit_direction: int = 1
var stun_timer: float = 0.0
var knockback_velocity: Vector3 = Vector3.ZERO
var is_defeated: bool = false
var bob_timer: float = 0.0

## Creature detail pass: back thorns, stub root-legs, claw nubs.
## Parented under Visual so the squash-hop animator drives them free.
func _build_creature_details() -> void:
	if visual == null:
		return
	var thorn_mat := StandardMaterial3D.new()
	thorn_mat.albedo_color = Color(0.16, 0.13, 0.08)
	thorn_mat.roughness = 0.9
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.05
	spike.height = 0.3
	spike.radial_segments = 5
	for i in 6:
		var thorn := MeshInstance3D.new()
		thorn.mesh = spike
		thorn.material_override = thorn_mat
		var ang := TAU * float(i) / 6.0
		thorn.position = Vector3(cos(ang) * 0.22, 0.28, sin(ang) * 0.22)
		thorn.rotation = Vector3(sin(ang) * 0.7, 0.0, -cos(ang) * 0.7)
		visual.add_child(thorn)
	var leg_mesh := CapsuleMesh.new()
	leg_mesh.radius = 0.055
	leg_mesh.height = 0.26
	for side in [-1.0, 1.0]:
		for row in 2:
			var leg := MeshInstance3D.new()
			leg.mesh = leg_mesh
			leg.material_override = thorn_mat
			leg.position = Vector3(0.2 * side, -0.24, -0.1 + row * 0.2)
			leg.rotation.x = 0.35 if row == 0 else -0.35
			visual.add_child(leg)
	# Twin front claw-arms: gives the sprite an aggressive frontal line.
	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.05
	arm_mesh.height = 0.3
	var claw_tip := CylinderMesh.new()
	claw_tip.top_radius = 0.0
	claw_tip.bottom_radius = 0.045
	claw_tip.height = 0.2
	claw_tip.radial_segments = 5
	for side in [-1.0, 1.0]:
		var claw_arm := MeshInstance3D.new()
		claw_arm.name = "ClawArm"
		claw_arm.mesh = arm_mesh
		claw_arm.material_override = thorn_mat
		claw_arm.position = Vector3(0.24 * side, 0.02, 0.28)
		claw_arm.rotation = Vector3(-0.35, 0, -0.5 * side)
		visual.add_child(claw_arm)
		var claw := MeshInstance3D.new()
		claw.name = "ClawTip"
		claw.mesh = claw_tip
		claw.material_override = thorn_mat
		claw.position = Vector3(0.38 * side, -0.08, 0.42)
		claw.rotation = Vector3(-0.75, 0, -0.65 * side)
		visual.add_child(claw)

func _ready() -> void:
	hp = max_hp
	collision_layer = 1 << 1  # Enemy layer
	collision_mask = 1 << 0 | 1 << 5  # Player + Environment
	
	hitbox.area_entered.connect(_on_hitbox_entered)
	attack_area.area_entered.connect(_on_attack_area_entered)
	
	# Random initial orbit direction
	orbit_direction = 1 if randi() % 2 == 0 else -1
	bob_timer = randf() * TAU
	_build_hushling_silhouette()
	_build_creature_details()

	# Authored-model drop-in (silent no-op until the model ships)
	CharacterRigLoader.try_if_wire(self, _rig_profile())

## Which authored rig this creature wears (Fenling overrides to "fenling").
func _rig_profile() -> String:
	return "hushling"

func _build_hushling_silhouette() -> void:
	var core := MeshInstance3D.new()
	core.name = "BrambleCore"
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.13
	core_mesh.height = 0.26
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = Color(0.46, 1.0, 0.64, 1.0)
	core_material.emission_enabled = true
	core_material.emission = Color(0.16, 1.0, 0.38, 1.0)
	core_material.emission_energy_multiplier = 2.8
	core.mesh = core_mesh
	core.material_override = core_material
	core.position = Vector3(0, 0.04, 0.42)
	visual.add_child(core)

	var core_light := OmniLight3D.new()
	core_light.name = "BrambleCoreLight"
	core_light.light_color = Color(0.32, 1.0, 0.50, 1.0)
	core_light.light_energy = 0.55
	core_light.omni_range = 3.2
	core_light.position = Vector3(0, 0.04, 0.40)
	visual.add_child(core_light)

	for i in range(3):
		var thorn := MeshInstance3D.new()
		thorn.name = "CrownThorn%d" % i
		var thorn_mesh := CylinderMesh.new()
		thorn_mesh.top_radius = 0.0
		thorn_mesh.bottom_radius = 0.075
		thorn_mesh.height = 0.38
		thorn_mesh.radial_segments = 6
		var thorn_material := StandardMaterial3D.new()
		thorn_material.albedo_color = Color(0.20, 0.34, 0.22, 1.0)
		thorn_material.roughness = 0.92
		thorn.mesh = thorn_mesh
		thorn.material_override = thorn_material
		thorn.position = Vector3((i - 1) * 0.22, 0.42, 0.02)
		thorn.rotation.z = (i - 1) * 0.34
		visual.add_child(thorn)

func _physics_process(delta: float) -> void:
	if is_defeated:
		return
	
	_update_timers(delta)
	_update_pattern(delta)
	_update_movement(delta)
	_update_visuals(delta)
	
	move_and_slide()

func _update_timers(delta: float) -> void:
	if pattern_timer > 0:
		pattern_timer -= delta
	
	if lunge_cooldown > 0:
		lunge_cooldown -= delta
	if burst_timer > 0:
		burst_timer -= delta
	
	if counter_timer > 0:
		counter_timer -= delta
	
	if stun_timer > 0:
		stun_timer -= delta
	
	if knockback_velocity.length() > 0.1:
		velocity += knockback_velocity
		knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, pow(0.001, delta))

func _update_pattern(delta: float) -> void:
	var player = get_parent().get_node_or_null("Hero")
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
				if dist < burst_radius + 2.0 and burst_timer <= 0:
					_begin_bramble_burst()
				elif dist < orbit_distance + 2.6 and lunge_cooldown <= 0:
					current_pattern = Pattern.LUNGE
					pattern_timer = 0.34
					lunge_cooldown = 3.2
					lunge_hit = false
					_modulate_eyes(Color(1, 0.3, 0.2))
					animator.trigger_attack()
					audio.play_enemy_telegraph()
				else:
					current_pattern = Pattern.FEINT
					pattern_timer = 0.42
				
			Pattern.FEINT, Pattern.LUNGE:
				current_pattern = Pattern.RECOVER
				pattern_timer = 0.56

			Pattern.WINDUP:
				_resolve_counter_strike()
				
			Pattern.BRAMBLE_BURST:
				_perform_bramble_burst(player)
				current_pattern = Pattern.RECOVER
				pattern_timer = 0.56
				
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
	var player = get_parent().get_node_or_null("Hero")
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
			
		Pattern.RECOVER:
			dir_x = side.x * 0.45 + to_player.x * ((dist - orbit_distance) * 0.03)
			dir_z = side.z * 0.45 + to_player.z * ((dist - orbit_distance) * 0.03)
			speed = recover_speed
	
	velocity.x = lerp(velocity.x, dir_x * speed + knockback_velocity.x, 1.0 - exp(-delta * 10.0))
	velocity.z = lerp(velocity.z, dir_z * speed + knockback_velocity.z, 1.0 - exp(-delta * 10.0))
	velocity.y = 0

func _update_visuals(delta: float) -> void:
	# Animator drives the squash-stretch hop
	animator.set_move_ratio(clampf(velocity.length() / max(lunge_speed, 0.01), 0.0, 1.0))
	
	# Eye glow pulse
	var eye_pulse = 0.7 + sin(bob_timer * 3.0) * 0.25
	for eye in eyes.get_children():
		if eye.material_override:
			eye.material_override.set_shader_parameter("glow_intensity", eye_pulse)
	
	# Tendrils: slow hypnotic spiral — each tendril traces a small circle
	# with its own phase drift instead of a single-axis sine sway
	var count := maxf(tendrils.get_child_count(), 1.0)
	for i in tendrils.get_child_count():
		var tendril = tendrils.get_child(i)
		var ph := bob_timer * 1.35 + float(i) * TAU / count
		tendril.rotation.x = -PI/3 + cos(ph) * 0.15
		tendril.rotation.z = sin(ph) * 0.19
		tendril.rotation.y = sin(ph * 0.7 + float(i)) * 0.12
	
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
		if area.has_method("take_damage"):
			area.take_damage(dmg, global_position.direction_to(area.global_position))
			print("Bramble Skitter catches your flank for %d warmth." % dmg)
			audio.play_hit()

func take_damage(amount: int, knockback_dir: Vector3) -> void:
	if is_defeated:
		return
	
	hp -= amount
	FloatingText.spawn_on_entity(self, str(amount), Color(1, 0.84, 0.47))
	animator.trigger_hit()
	
	# Visual feedback
	var tween = create_tween()
	tween.tween_property(body, "material_override:shader_parameter/flash_intensity", 1.0, 0.05)
	tween.tween_property(body, "material_override:shader_parameter/flash_intensity", 0.0, 0.15)
	# Battle wear: the creature visibly scuffs as it breaks down
	if body.material_override is ShaderMaterial:
		var ratio := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
		body.material_override.set_shader_parameter("hp_wear",
			clampf((0.45 - ratio) / 0.45, 0.0, 1.0) * 0.8)
	
	# Knockback
	knockback_velocity = knockback_dir * (amount * 10.0)
	
	# Pattern interrupt
	if current_pattern == Pattern.LUNGE:
		current_pattern = Pattern.RECOVER
		pattern_timer = 0.56
	elif current_pattern == Pattern.WINDUP:
		# Striking a winding-up sprite cancels its answer — aggression
		# suppresses counters but never stunlock-repeats them.
		current_pattern = Pattern.RECOVER
		pattern_timer = 0.4
	else:
		var hero = get_parent().get_node_or_null("Hero")
		var can_counter := counter_timer <= 0.0 and hp > 0 \
				and hero != null and is_instance_valid(hero) \
				and global_position.distance_to(hero.global_position) \
						<= counter_range * 1.4
		if can_counter:
			_begin_counter_windup()
		else:
			current_pattern = Pattern.RECOVER
			pattern_timer = 0.32
	
	if hp <= 0:
		die()

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
	animator.trigger_attack()
	if sfx_profile == "vanilla":
		audio.play_enemy_telegraph()
	else:
		audio.play_profile_cue(sfx_profile, "telegraph")
	CombatFx.spawn_telegraph(self, global_position + Vector3(0, 0.35, 0),
		Color(1.0, 0.32, 0.18))
	CombatFx.spawn_ring(self, global_position, counter_range,
		Color(1.0, 0.45, 0.18, 0.55), counter_windup)

func _resolve_counter_strike() -> void:
	current_pattern = Pattern.RECOVER
	pattern_timer = 0.56
	var player = get_parent().get_node_or_null("Hero")
	if is_defeated or player == null or not is_instance_valid(player):
		return
	CombatFx.spawn_slash(self, global_position + Vector3(0, 0.5, 0),
		Color(1.0, 0.4, 0.2, 0.9))
	audio.play_hit()
	var dist := global_position.distance_to(player.global_position)
	if dist > counter_range + 0.8:
		return  # dodged out of reach — strike whiffs
	if player.has_method("is_airborne") and player.is_airborne():
		return
	if player.has_method("notify_enemy_strike"):
		player.notify_enemy_strike(self, base_atk + 1)

func die() -> void:
	is_defeated = true
	collision_layer = 0
	collision_mask = 0
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
	# Rare elite glint: diamonds stay luck-independent by design
	if thorn_volley and randf() < 0.05:
		CombatFx.spawn_burst(self, global_position + Vector3(0, 0.6, 0),
			Color(0.55, 0.85, 1.0, 0.95), 18, 4.5, 0.7, 0.14)
		GameState.add_diamonds(1, "💎 +1 diamond — a rare glint settles in your palm.")

## Hand the bramble husk to the pooled tumble-corpse system: a killing
## shove away from the hero plus spin; the husk bounces, settles, sinks.
func _launch_death_corpse() -> void:
	_do_launch_death_corpse.call_deferred()

func _do_launch_death_corpse() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null or not is_inside_tree():
		return
	var killer := get_parent().get_node_or_null("Hero")
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

func _on_death_animation_finished() -> void:
	died.emit()
	queue_free()

func is_dead() -> bool:
	return is_defeated

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