extends BossBase
class_name HushlingMatriarch

## === Hushling Matriarch ===
## Phase 1: Bramble Queen - summons hushlings
## Phase 2: Thorn Cascade - area denial
## Phase 3: Root Prison - crowd control
## Enrage: Endless Bramble Storm

@onready var summon_points: Array[Marker3D] = []

var summoned_hushlings: Array[Node3D] = []
var max_summons: int = 4
var bramble_wall_cooldown: float = 0.0

# Breakable crown guard: incoming hits still deal their normal damage while
# building a readable break. Breaking it opens a short skill window rather
# than permanently inflating boss health.
@export var thorn_guard_max: int = 120
@export var vulnerability_duration: float = 4.0
@export var vulnerability_damage_mult: float = 1.25
var thorn_guard: int = 120
var vulnerability_timer: float = 0.0
var _guard_rearm_pending := false
var _guard_visuals: Array[MeshInstance3D] = []
var _arena_transform_root: Node3D = null
var _arena_growths: Array[MeshInstance3D] = []

func _ready() -> void:
	# Configure derived stats before BossBase calculates phase thresholds and
	# initializes the boss combat camera profile.
	max_hp = 1100
	hp = max_hp
	diamond_reward = 5
	base_atk = 15
	move_speed = 4.0
	arena_radius = 25.0
	# Thorn Guard IS the matriarch's armor identity; stage armor stays zero so
	# the crown-break vulnerability contract (exact 125-damage window) holds.
	stage_armor = [0, 0, 0, 0]
	# She already mends through Spore Bloom; the base mend channel stays off.
	mend_max_uses = 0
	mend_uses_left = 0
	super._ready()
	_setup_attacks()
	_build_thorn_guard()
	_build_arena_transform()
	
	# Find summon points
	for child in get_parent().get_children():
		if child is Marker3D and child.name.begins_with("SummonPoint"):
			summon_points.append(child)
	
	_refresh_boss_bar()

func _process(delta: float) -> void:
	super._process(delta)
	if is_defeated or vulnerability_timer <= 0.0:
		return
	vulnerability_timer = maxf(0.0, vulnerability_timer - delta)
	if boss_phase_label:
		boss_phase_label.text = "CROWN EXPOSED %.1fs" % vulnerability_timer
	if vulnerability_timer <= 0.0:
		_rearm_thorn_guard()

func _setup_attacks() -> void:
	super._setup_attacks()
	attack_cooldowns = {
		"basic": 0.0,
		"summon": 0.0,
		"realm_skill": 0.0,
		"root_prison": 0.0,
		"bramble_storm": 0.0
	}

func _on_phase_transition() -> void:
	super._on_phase_transition()
	_set_arena_phase(int(current_phase))
	# Crossing a phase during a successful break never steals the reward
	# window. The next crown grows only after vulnerability ends.
	if vulnerability_timer > 0.0:
		_guard_rearm_pending = true
	else:
		_rearm_thorn_guard()
	
	match current_phase:
		BossPhase.PHASE_2:
			# Summon initial pack
			_summon_hushlings(3)
			attack_cooldowns["summon"] = 0.0
			
		BossPhase.PHASE_3:
			# The realm rite begins (custom skill or default thorn rain)
			attack_cooldowns["realm_skill"] = 0.0
			
		BossPhase.ENRAGE:
			enrage_active = true
			attack_cooldowns["bramble_storm"] = 0.0
			# Visual enrage
			body.material_override.set_shader_parameter("emissive_color", Color(1, 0.3, 0.1))

func _try_attacks(player: Node3D, dist: float) -> void:
	if is_action_locked():
		return
	super._try_attacks(player, dist)
	if is_action_locked(): # the basic slam won this decision tick
		return
	# Priority creates escalating combinations over successive decisions while
	# guaranteeing only one new attack family starts per AI tick.
	if current_phase == BossPhase.ENRAGE \
			and float(attack_cooldowns.get("bramble_storm", 0.0)) <= 0.0:
		lock_action(1.7)
		_bramble_storm()
		attack_cooldowns["bramble_storm"] = 25.0
		return
	if current_phase >= BossPhase.PHASE_3 \
			and float(attack_cooldowns.get("root_prison", 0.0)) <= 0.0 and dist < 8.0:
		lock_action(1.0)
		_root_prison(player)
		attack_cooldowns["root_prison"] = 18.0
		return
	if current_phase >= BossPhase.PHASE_3 \
			and float(attack_cooldowns.get("realm_skill", 0.0)) <= 0.0:
		lock_action(1.0)
		_run_realm_skill(player)
		attack_cooldowns["realm_skill"] = _realm_skill_cooldown()
		return
	if current_phase >= BossPhase.PHASE_2 \
			and float(attack_cooldowns.get("summon", 0.0)) <= 0.0 \
			and summoned_hushlings.size() < max_summons:
		lock_action(0.65)
		_summon_hushlings(1)
		attack_cooldowns["summon"] = 15.0

## === Realm skill slot (the ONE customizable rite) ===
## Default: Thorn Cascade. A chosen pool skill reroutes this slot; the
## ultimate, summons cadence, Root Prison and stingers stay locked.
func _realm_skill_cooldown() -> float:
	if customization != null and not customization.skill.is_empty():
		return float(customization.skill.get("cooldown", 12.0))
	return 12.0

func _run_realm_skill(player: Node3D) -> void:
	var sk: Dictionary = customization.skill if customization != null else {}
	match str(sk.get("type", "")):
		"lattice":
			_skill_thorn_lattice(player)
		"bloom":
			_skill_spore_bloom()
		"legion":
			_skill_husk_legion()
		"snare":
			_skill_root_snare(player)
		_:
			_thorn_rain(player)

## Twin expanding bramble rings — lighter than thorn rain but doubled.
func _skill_thorn_lattice(player: Node3D) -> void:
	if sfx_profile == "vanilla":
		audio.play_enemy_special()
	else:
		audio.play_profile_cue(sfx_profile, "cast")
	_shake_camera(0.4)
	var generation := encounter_generation
	for ring in 2:
		var radius := 5.0 + ring * 6.0
		CombatFx.spawn_ground_telegraph(self,
			Vector3(player.global_position.x, 0, player.global_position.z),
			radius, Color(1, 0.45, 0.2), 1.1 + ring * 0.3)
		for i in 10:
			var angle := (i / 10.0) * TAU
			var pos: Vector3 = player.global_position \
				+ Vector3(cos(angle) * radius, 0, sin(angle) * radius)
			var timer := get_tree().create_timer(0.7 + ring * 0.35, false)
			timer.timeout.connect(_deal_thorn_damage.bind(pos, 2.2, 12, generation))

## Rot-blooms knit her wounds while they hiss.
func _skill_spore_bloom() -> void:
	if sfx_profile == "vanilla":
		audio.play_enemy_telegraph()
	else:
		audio.play_profile_cue(sfx_profile, "cast")
	var generation := encounter_generation
	for tick in 3:
		var timer := get_tree().create_timer(0.5 + tick * 0.7, false)
		timer.timeout.connect(_bloom_heal_tick.bind(16, generation))

func _bloom_heal_tick(amount: int, generation: int = -1) -> void:
	if is_defeated or hp >= max_hp \
			or (generation >= 0 and generation != encounter_generation):
		return
	hp = mini(hp + amount, max_hp)
	if boss_hp_bar:
		boss_hp_bar.value = hp
	CombatFx.spawn_burst(self, global_position + Vector3(0, 2.0, 0),
		Color(0.56, 0.67, 0.33, 0.85), 14, 3.0, 0.6, 0.18)

## Three elders rise at once to shield her.
func _skill_husk_legion() -> void:
	if sfx_profile == "vanilla":
		audio.play_enemy_special()
	else:
		audio.play_profile_cue(sfx_profile, "vocal")
	_summon_hushlings(3, true)

## Roots leap the distance and cage the player wherever they stand.
func _skill_root_snare(player: Node3D) -> void:
	if sfx_profile == "vanilla":
		audio.play_enemy_telegraph()
	else:
		audio.play_profile_cue(sfx_profile, "telegraph")
	_root_prison(player)

func _summon_hushlings(count: int, force_elder: bool = false) -> void:
	for i in range(count):
		if summoned_hushlings.size() >= max_summons:
			break
		
		var spawn_point = summon_points.pick_random() if summon_points else null
		var spawn_pos = spawn_point.global_position if spawn_point else global_position + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		
		var hushling_scene = load("res://scenes/entities/hushling.tscn")
		var hushling = hushling_scene.instantiate()
		get_parent().add_child(hushling)
		hushling.global_position = spawn_pos
		hushling.call("set_max_hp", 35)
		hushling.call("set_base_atk", 4)
		
		# Data-driven variant: elders emerge as the fight drags on
		var elder_chance := 0.15 if current_phase < BossPhase.ENRAGE else 0.4
		if force_elder or randf() < elder_chance:
			CharacterModelData.elder_hushling().configure_entity(hushling)
		
		summoned_hushlings.append(hushling)
		
		# Clean up dead references
		summoned_hushlings = summoned_hushlings.filter(func(h): return is_instance_valid(h))

func _thorn_rain(target: Node3D) -> void:
	# Rain thorns in expanding circles
	var circles = 3
	var thorns_per_circle = 8
	
	# Telegraph shake so players feel it coming before damage lands
	_shake_camera(0.35)
	
	var generation := encounter_generation
	for c in range(circles):
		var radius = 4.0 + c * 5.0
		
		# Danger-red warning ring for each incoming wave (protected layer)
		CombatFx.spawn_ground_telegraph(self,
			Vector3(target.global_position.x, 0, target.global_position.z),
			radius, Color(1.0, 0.16, 0.08), 1.2 + c * 0.3)
		
		for i in range(thorns_per_circle):
			var angle = (i / float(thorns_per_circle)) * TAU
			var pos = target.global_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
			
			# Delayed damage
			var timer = get_tree().create_timer(0.8 + c * 0.3, false)
			timer.timeout.connect(_deal_thorn_damage.bind(pos, 2.5, 18, generation))

func _root_prison(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var center := target.global_position
	var radius := 3.5
	var anticipation := 0.78
	attack_telegraphed.emit("root_prison", radius, anticipation)
	CombatFx.spawn_ground_telegraph(self, center, radius,
		Color(1.0, 0.16, 0.08), anticipation)
	var timer := get_tree().create_timer(anticipation, false)
	timer.timeout.connect(_resolve_root_prison.bind(target, center, radius,
		encounter_generation))

func _resolve_root_prison(target: Node3D, center: Vector3, radius: float,
		generation: int = -1) -> void:
	if is_defeated or target == null or not is_instance_valid(target) \
			or (generation >= 0 and generation != encounter_generation):
		return
	# Root cage around the committed location. Leaving the readable circle
	# before eruption avoids the control effect.
	var roots = 8
	for i in range(roots):
		var angle = (i / float(roots)) * TAU
		var root_pos = center + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		CombatFx.spawn_burst(self, root_pos + Vector3(0, 0.5, 0),
			Color(0.3, 0.2, 0.1, 0.9), 8, 4.5, 1.2, 0.2)
	if target.global_position.distance_to(center) <= radius \
			and target.has_method("stun"):
		target.stun(2.5)
	
	audio.play_hit()

func _bramble_storm() -> void:
	# Massive brambles erupt across arena
	var center = global_position
	var radius = arena_radius
	var count = 20
	
	_shake_camera(0.6)
	
	var generation := encounter_generation
	for i in range(count):
		var angle = randf() * TAU
		var r = randf() * radius
		var pos = center + Vector3(cos(angle) * r, 0, sin(angle) * r)
		
		var delay := randf_range(0.65, 1.55)
		attack_telegraphed.emit("bramble_storm", 4.0, delay)
		CombatFx.spawn_ground_telegraph(self, pos, 4.0,
			Color(1.0, 0.16, 0.08), delay)
		var timer = get_tree().create_timer(delay, false)
		timer.timeout.connect(_deal_thorn_damage.bind(pos, 4.0, 25, generation))
	
	# Screen shake at the peak of the storm
	var peak = get_tree().create_timer(1.2)
	peak.timeout.connect(_resolve_storm_peak.bind(generation))

func _resolve_storm_peak(generation: int) -> void:
	if is_defeated or generation != encounter_generation:
		return
	_shake_camera(1.2)

func take_damage(amount: int, knockback_dir: Vector3, critical: bool = false) -> void:
	if is_defeated:
		return
	var applied := amount
	if vulnerability_timer > 0.0:
		applied = maxi(1, int(round(float(amount) * vulnerability_damage_mult)))
	super.take_damage(applied, knockback_dir, critical)
	if is_defeated or vulnerability_timer > 0.0:
		return
	thorn_guard = maxi(0, thorn_guard - maxi(amount, 0))
	_update_guard_visuals()
	if thorn_guard <= 0:
		_break_thorn_guard()

func _build_thorn_guard() -> void:
	thorn_guard = thorn_guard_max
	var host := Node3D.new()
	host.name = "ArmorGear_MatriarchCrown"
	var visual := visual_root_or_body_parent()
	if visual == null:
		return
	visual.add_child(host)
	for i in 4:
		var thorn := MeshInstance3D.new()
		thorn.name = "ThornGuard_%d" % i
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = 0.16
		mesh.height = 0.85
		mesh.radial_segments = 7
		thorn.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.10, 0.07)
		mat.roughness = 0.92
		mat.emission_enabled = true
		mat.emission = Color(0.76, 0.18, 0.06)
		mat.emission_energy_multiplier = 0.35
		thorn.material_override = mat
		var angle := TAU * float(i) / 4.0
		thorn.position = crit_zone_center + Vector3(cos(angle) * 0.72, 0.15,
			sin(angle) * 0.72)
		thorn.rotation = Vector3(sin(angle) * 0.35, 0.0, -cos(angle) * 0.35)
		host.add_child(thorn)
		_guard_visuals.append(thorn)
	_update_guard_visuals()

func _update_guard_visuals() -> void:
	var visible_count := ceili(float(thorn_guard) / maxf(float(thorn_guard_max), 1.0)
		* float(_guard_visuals.size()))
	for i in _guard_visuals.size():
		if is_instance_valid(_guard_visuals[i]):
			_guard_visuals[i].visible = i < visible_count
	if boss_phase_label and vulnerability_timer <= 0.0:
		boss_phase_label.text = "THORN GUARD %d%%" % int(round(
			100.0 * float(thorn_guard) / maxf(float(thorn_guard_max), 1.0)))

func _break_thorn_guard() -> void:
	vulnerability_timer = vulnerability_duration
	_guard_rearm_pending = true
	_update_guard_visuals()
	CombatFx.spawn_shockwave(self, global_position + Vector3.UP * 2.2, 3.4,
		Color(0.95, 0.32, 0.10, 0.86), 0.55)
	CombatFx.spawn_burst(self, global_position + Vector3.UP * 2.8,
		Color(0.55, 0.22, 0.10, 0.9), 18, 5.0, 0.55, 0.16)
	ImpactDirector.apply_feedback(self, "heavy", global_position + Vector3.UP * 2.4,
		Vector3.DOWN, 0.8)
	FloatingText.spawn_on_entity(self, "CROWN BROKEN — STRIKE NOW",
		Color(1.0, 0.72, 0.28), 1.6)

func _rearm_thorn_guard() -> void:
	if is_defeated:
		return
	vulnerability_timer = 0.0
	thorn_guard = thorn_guard_max
	_guard_rearm_pending = false
	_update_guard_visuals()

## Twelve collision-free silhouettes reshape the arena read across phases.
## Gameplay space remains unchanged; protected attack telegraphs stay primary.
func _build_arena_transform() -> void:
	_arena_transform_root = Node3D.new()
	_arena_transform_root.name = "ArenaTransformation"
	add_child(_arena_transform_root)
	for i in 12:
		var growth := MeshInstance3D.new()
		growth.name = "ArenaThorn_%02d" % i
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = 0.32 if i < 6 else 0.22
		mesh.height = 2.8 if i < 6 else 1.8
		mesh.radial_segments = 7
		growth.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.08, 0.06)
		mat.roughness = 0.95
		mat.emission_enabled = true
		mat.emission = Color(0.74, 0.16, 0.06)
		mat.emission_energy_multiplier = 0.22
		growth.material_override = mat
		var ring_index := i if i < 6 else i - 6
		var angle := TAU * float(ring_index) / 6.0 \
			+ (0.0 if i < 6 else PI / 6.0)
		var radius := arena_radius * (0.76 if i < 6 else 0.48)
		growth.position = Vector3(cos(angle) * radius, mesh.height * 0.5,
			sin(angle) * radius)
		growth.visible = false
		_arena_transform_root.add_child(growth)
		_arena_growths.append(growth)

func _set_arena_phase(phase: int) -> void:
	var visible_count := 0
	if phase >= int(BossPhase.PHASE_2):
		visible_count = 6
	if phase >= int(BossPhase.PHASE_3):
		visible_count = 12
	for i in _arena_growths.size():
		var growth := _arena_growths[i]
		if not is_instance_valid(growth):
			continue
		var should_show := i < visible_count
		if should_show and not growth.visible:
			growth.scale = Vector3.ONE * 0.05
			growth.visible = true
			var rise := growth.create_tween()
			rise.tween_property(growth, "scale", Vector3.ONE, 0.55) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif not should_show:
			growth.visible = false
		if growth.material_override is StandardMaterial3D:
			(growth.material_override as StandardMaterial3D).emission_energy_multiplier = \
				0.55 if phase >= int(BossPhase.ENRAGE) else 0.22

func reset_encounter() -> void:
	for summon in summoned_hushlings:
		if is_instance_valid(summon):
			summon.queue_free()
	summoned_hushlings.clear()
	bramble_wall_cooldown = 0.0
	vulnerability_timer = 0.0
	_guard_rearm_pending = false
	super.reset_encounter()
	_rearm_thorn_guard()
	_set_arena_phase(int(BossPhase.PHASE_1))

func _deal_thorn_damage(pos: Vector3, radius: float, damage: int,
		generation: int = -1) -> void:
	if is_defeated or not is_inside_tree() \
			or (generation >= 0 and generation != encounter_generation):
		return
	_deal_area_damage(pos, radius,
		maxi(1, int(round(float(damage) * stage_dmg_mult()))))
	
	# Impact visual
	CombatFx.spawn_burst(self, pos + Vector3(0, 0.5, 0),
		Color(1, 0.3, 0.2, 0.8), 12, 5.0, 0.5, 0.15)
	CombatFx.spawn_decal(self, pos, 0.9)

func _show_warning_ring(pos: Vector3, radius: float, duration: float) -> void:
	CombatFx.spawn_ground_telegraph(self,
		Vector3(pos.x, 0, pos.z), radius, Color(1.0, 0.16, 0.08), duration)

func _spawn_rewards() -> void:
	if is_practice:
		return
	super._spawn_rewards()
	
	# Unique rewards
	game_state.grant_xp(500)
	game_state.add_loot("hushling_thorn", 5, "Matriarch's thorns — ancient bramble essence.", 5)
	game_state.add_loot("moss_tonic", 3, "Concentrated moss draught.", 3)
	
	# Guaranteed build-changing weapon. Repeat victories never replace a saved
	# upgraded copy with the base definition.
	game_state.grant_unique_weapon("matriarch_scepter", false,
		"Crown of the Old Root claimed — every second strike now blooms.")

	# First-clear bridge: the boss victory now leads directly into a visible
	# upgrade and exploration goal. Repeat kills retain their ordinary loot but
	# cannot duplicate this material bundle.
	if was_first_kill:
		game_state.add_material("bramble_wood", 3)
		game_state.add_material("beast_hide", 2)
		game_state.add_material("iron_shard", 4)
		game_state.add_objective("upgrade_matriarch_scepter",
			"Equip and strengthen the Crown of the Old Root", "upgrade", 1)
		var newly_unlocked: bool = game_state.unlock_realm("moonfen")
		var route_note := "Moonfen unlocked. Equip the Crown, strengthen it, then follow the cyan marsh-lights."
		if not newly_unlocked:
			route_note = "The Moonfen path brightens. Forge an upgrade before the next expedition."
		game_state.quest_progress.emit(route_note)
