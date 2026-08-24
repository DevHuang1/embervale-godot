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

func _ready() -> void:
	super._ready()
	max_hp = 800
	hp = max_hp
	diamond_reward = 5
	base_atk = 15
	move_speed = 4.0
	arena_radius = 25.0
	
	_setup_attacks()
	
	# Find summon points
	for child in get_parent().get_children():
		if child is Marker3D and child.name.begins_with("SummonPoint"):
			summon_points.append(child)
	
	_refresh_boss_bar()

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
	super._try_attacks(player, dist)
	
	if current_phase >= BossPhase.PHASE_2:
		if attack_cooldowns["summon"] <= 0 and summoned_hushlings.size() < max_summons:
			_summon_hushlings(1)
			attack_cooldowns["summon"] = 15.0
	
	if current_phase >= BossPhase.PHASE_3:
		if attack_cooldowns["realm_skill"] <= 0:
			_run_realm_skill(player)
			attack_cooldowns["realm_skill"] = _realm_skill_cooldown()
		
		if attack_cooldowns["root_prison"] <= 0 and dist < 8.0:
			_root_prison(player)
			attack_cooldowns["root_prison"] = 18.0
	
	if current_phase == BossPhase.ENRAGE:
		if attack_cooldowns["bramble_storm"] <= 0:
			_bramble_storm()
			attack_cooldowns["bramble_storm"] = 25.0

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
	for ring in 2:
		var radius := 5.0 + ring * 6.0
		CombatFx.spawn_ring(self, player.global_position, radius,
			Color(1, 0.45, 0.2, 0.55), 1.1 + ring * 0.3)
		for i in 10:
			var angle := (i / 10.0) * TAU
			var pos: Vector3 = player.global_position \
				+ Vector3(cos(angle) * radius, 0, sin(angle) * radius)
			var timer := get_tree().create_timer(0.7 + ring * 0.35, false)
			timer.timeout.connect(_deal_thorn_damage.bind(pos, 2.2, 12))

## Rot-blooms knit her wounds while they hiss.
func _skill_spore_bloom() -> void:
	if sfx_profile == "vanilla":
		audio.play_enemy_telegraph()
	else:
		audio.play_profile_cue(sfx_profile, "cast")
	for tick in 3:
		var timer := get_tree().create_timer(0.5 + tick * 0.7, false)
		timer.timeout.connect(_bloom_heal_tick.bind(16))

func _bloom_heal_tick(amount: int) -> void:
	if is_defeated or hp >= max_hp:
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
	
	for c in range(circles):
		var radius = 4.0 + c * 5.0
		
		# Danger-red warning ring for each incoming wave
		CombatFx.spawn_ring(self, target.global_position, radius,
			Color(1.0, 0.16, 0.08, 0.65), 1.2 + c * 0.3)
		
		for i in range(thorns_per_circle):
			var angle = (i / float(thorns_per_circle)) * TAU
			var pos = target.global_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
			
			# Delayed damage
			var timer = get_tree().create_timer(0.8 + c * 0.3, false)
			timer.timeout.connect(_deal_thorn_damage.bind(pos, 2.5, 18))

func _root_prison(target: Node3D) -> void:
	# Root cage around player
	var roots = 8
	for i in range(roots):
		var angle = (i / float(roots)) * TAU
		var root_pos = target.global_position + Vector3(cos(angle) * 3.0, 0, sin(angle) * 3.0)
		CombatFx.spawn_burst(self, root_pos + Vector3(0, 0.5, 0),
			Color(0.3, 0.2, 0.1, 0.9), 8, 4.5, 1.2, 0.2)
	
	# Stun player
	if target.has_method("stun"):
		target.stun(2.5)
	
	audio.play_hit()

func _bramble_storm() -> void:
	# Massive brambles erupt across arena
	var center = global_position
	var radius = arena_radius
	var count = 20
	
	_shake_camera(0.6)
	
	for i in range(count):
		var angle = randf() * TAU
		var r = randf() * radius
		var pos = center + Vector3(cos(angle) * r, 0, sin(angle) * r)
		
		var timer = get_tree().create_timer(randf_range(0.5, 1.5), false)
		timer.timeout.connect(_deal_thorn_damage.bind(pos, 4.0, 25))
	
	# Screen shake at the peak of the storm
	var peak = get_tree().create_timer(1.2)
	peak.timeout.connect(func(): _shake_camera(1.2))

func _deal_thorn_damage(pos: Vector3, radius: float, damage: int) -> void:
	_deal_area_damage(pos, radius, damage)
	
	# Impact visual
	CombatFx.spawn_burst(self, pos + Vector3(0, 0.5, 0),
		Color(1, 0.3, 0.2, 0.8), 12, 5.0, 0.5, 0.15)
	CombatFx.spawn_decal(self, pos, 0.9)

func _show_warning_ring(pos: Vector3, radius: float, duration: float) -> void:
	CombatFx.spawn_ring(self, pos, radius, Color(1.0, 0.16, 0.08, 0.7), duration)

func _spawn_rewards() -> void:
	if is_practice:
		return
	super._spawn_rewards()
	
	# Unique rewards
	game_state.grant_xp(500)
	game_state.add_loot("hushling_thorn", 5, "Matriarch's thorns — ancient bramble essence.", 5)
	game_state.add_loot("moss_tonic", 3, "Concentrated moss draught.", 3)
	
	# Guaranteed legendary weapon drop
	var legendary = {"id": "matriarch_scepter", "name": "MATRIARCH'S SCEPTER", "glyph": "👑", "atk": 25, "swing_time": 0.6, "range": 10.0, "skill": {"name": "Bramble Dominion", "type": "heavy_aoe", "cooldown": 8.0, "radius": 20.0, "dmg_mult": 2.0}, "rarity": 4}
	game_state.add_weapon(legendary, false, "The Matriarch's scepter hums with dormant bramble power.")