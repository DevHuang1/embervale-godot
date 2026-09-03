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

# === Redesigned Model Variables ===
const MAT_CHITIN    := Color(0.08, 0.06, 0.05)
const MAT_THORN     := Color(0.14, 0.10, 0.07)
const MAT_VEIN      := Color(0.76, 0.18, 0.06)
const MAT_CORE      := Color(0.42, 0.88, 0.30)
const MAT_EYE       := Color(0.95, 0.60, 0.12)
const MAT_SILK      := Color(0.60, 0.22, 0.06)
const MAT_CROWN     := Color(0.22, 0.14, 0.08)
const MAT_RIB       := Color(0.16, 0.11, 0.08)
var _carapace_host  : Node3D = null
var _rib_mats       : Array[StandardMaterial3D] = []
var _core_gem_mat   : StandardMaterial3D = null
var _eye_mats_new   : Array[StandardMaterial3D] = []
var _crown_horn_mats: Array[StandardMaterial3D] = []
var _limb_roots     : Array[Node3D] = []
var _silk_sbs       : SpringBoneSystem = null
var _core_light     : OmniLight3D = null
var _model_t        : float = 0.0


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
	_build_matriarch_body()
	
	# Find summon points
	for child in get_parent().get_children():
		if child is Marker3D and child.name.begins_with("SummonPoint"):
			summon_points.append(child)
	
	_refresh_boss_bar()

func _process(delta: float) -> void:
	super._process(delta)
	_animate_matriarch(delta)
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
	var visual_root := visual_root_or_body_parent()
	if visual_root == null:
		return
	visual_root.add_child(host)

	for i in 4:
		var spike_root := Node3D.new()
		spike_root.name = "ThornSpike_%d" % i
		host.add_child(spike_root)

		# Main spike mesh
		var thorn := MeshInstance3D.new()
		thorn.name = "ThornGuard_%d" % i
		var mesh := CylinderMesh.new()
		mesh.top_radius      = 0.0
		mesh.bottom_radius   = 0.16
		mesh.height          = 0.85
		mesh.radial_segments = 7
		thorn.mesh = mesh
		var mat := _pristine_crown_mat()
		thorn.material_override = mat
		var angle := TAU * float(i) / 4.0
		thorn.position = crit_zone_center + Vector3(
			cos(angle) * 0.72, 0.15, sin(angle) * 0.72)
		thorn.rotation = Vector3(sin(angle) * 0.35, 0.0, -cos(angle) * 0.35)
		spike_root.add_child(thorn)
		_guard_visuals.append(thorn)

		# Crack overlay — 3 thin crack-line meshes per spike, hidden at full health
		for c in 3:
			var crack := MeshInstance3D.new()
			crack.name = "CrownCrack_%d_%d" % [i, c]
			var cm := BoxMesh.new()
			cm.size = Vector3(0.025, 0.30 + float(c) * 0.12, 0.018)
			crack.mesh = cm
			var crack_mat := StandardMaterial3D.new()
			crack_mat.albedo_color = Color(0.05, 0.03, 0.02)
			crack_mat.emission_enabled = true
			crack_mat.emission         = Color(0.90, 0.22, 0.06)
			crack_mat.emission_energy_multiplier = 0.0  # hidden until damage
			crack_mat.roughness = 0.99
			crack.material_override = crack_mat
			crack.position = thorn.position + Vector3(
				sin(float(c) * 1.3 + angle) * 0.06,
				-0.12 + float(c) * 0.22,
				cos(float(c) * 0.9 + angle) * 0.06)
			crack.rotation = Vector3(
				sin(float(c)) * 0.4, angle + float(c) * 0.7, cos(float(c)) * 0.3)
			spike_root.add_child(crack)

	_update_guard_visuals()

func _update_guard_visuals() -> void:
	var ratio := clampf(float(thorn_guard) / maxf(float(thorn_guard_max), 1.0), 0.0, 1.0)

	# Phase 1 (ratio > 0.66) : pristine — full glow, no cracks
	# Phase 2 (0.33–0.66)    : stressed — darkening, 1st crack layer glows
	# Phase 3 (0–0.33)       : crumbling — very dark, all cracks bright, flicker
	var damage_t := 1.0 - ratio  # 0 = full HP, 1 = broken

	for i in _guard_visuals.size():
		var thorn := _guard_visuals[i]
		if not is_instance_valid(thorn):
			continue
		var mat := thorn.material_override as StandardMaterial3D
		if mat == null:
			continue

		# Darken body as guard breaks
		var base_brightness := lerpf(0.22, 0.08, damage_t)
		mat.albedo_color = Color(base_brightness, base_brightness * 0.45,
			base_brightness * 0.32)
		# Ember glow dims — becomes redder and dimmer as it cracks
		var glow_energy := lerpf(0.35, 0.06, damage_t)
		mat.emission     = Color(
			lerpf(0.76, 0.55, damage_t),
			lerpf(0.18, 0.06, damage_t),
			lerpf(0.06, 0.02, damage_t))
		mat.emission_energy_multiplier = glow_energy

		# Reveal crack overlays
		var spike_root := thorn.get_parent()
		for c in 3:
			var crack_node := spike_root.get_node_or_null("CrownCrack_%d_%d" % [i, c])
			if crack_node == null or not (crack_node is MeshInstance3D):
				continue
			var crack_mat := (crack_node as MeshInstance3D).material_override as StandardMaterial3D
			if crack_mat == null:
				continue
			# Each crack layer appears progressively
			var crack_threshold := float(c) / 3.0
			var crack_intensity := clampf((damage_t - crack_threshold) / 0.34, 0.0, 1.0)
			crack_mat.emission_energy_multiplier = lerpf(0.0, 3.2, crack_intensity)
			# Flicker near breaking point
			if ratio < 0.18:
				var flicker := 0.6 + sin(Time.get_ticks_msec() * 0.018 + float(i + c)) * 0.4
				crack_mat.emission_energy_multiplier *= flicker

	# Boss HP label
	if boss_phase_label and vulnerability_timer <= 0.0:
		boss_phase_label.text = "THORN GUARD %d%%" % int(round(ratio * 100.0))

func _break_thorn_guard() -> void:
	vulnerability_timer   = vulnerability_duration
	_guard_rearm_pending  = true
	_update_guard_visuals()

	# Per-spike fragment burst — each guard spike shatters independently
	for i in _guard_visuals.size():
		var thorn := _guard_visuals[i]
		if not is_instance_valid(thorn):
			continue
		var spike_pos := thorn.global_position
		CombatFx.spawn_burst(self, spike_pos,
			Color(0.90, 0.22, 0.06, 0.9), 8, 6.0, 0.4, 0.14)
		# Spawn 4 debris shards per spike
		var shard_mat := StandardMaterial3D.new()
		shard_mat.albedo_color = Color(0.16, 0.08, 0.05)
		shard_mat.emission_enabled = true
		shard_mat.emission = Color(0.76, 0.18, 0.06)
		shard_mat.emission_energy_multiplier = 1.6
		for s in 4:
			var shard := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(randf_range(0.04, 0.12), randf_range(0.03, 0.10),
				randf_range(0.04, 0.09))
			shard.mesh = bm
			shard.material_override = shard_mat
			shard.global_position = spike_pos + Vector3(
				randf_range(-0.15, 0.15), randf_range(0.1, 0.4),
				randf_range(-0.15, 0.15))
			shard.rotation = Vector3(
				randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU))
			add_child(shard)
			var vel := Vector3(
				randf_range(-4.0, 4.0), randf_range(1.5, 5.5),
				randf_range(-4.0, 4.0))
			var tw := shard.create_tween()
			tw.tween_property(shard, "global_position",
				shard.global_position + vel, 0.5).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(shard, "rotation",
				shard.rotation + Vector3(randf_range(-TAU, TAU), randf_range(-TAU, TAU), 0), 0.5)
			tw.tween_callback(shard.queue_free)
		# Hide the spike itself (it will be rebuilt by _rearm)
		thorn.visible = false

	# Crown-wide shockwave + feedback
	CombatFx.spawn_shockwave(self, global_position + Vector3.UP * 2.2, 3.4,
		Color(0.95, 0.32, 0.10, 0.86), 0.55)
	CombatFx.spawn_burst(self, global_position + Vector3.UP * 2.8,
		Color(0.55, 0.22, 0.10, 0.9), 24, 6.0, 0.55, 0.14)
	ImpactDirector.apply_feedback(self, "heavy",
		global_position + Vector3.UP * 2.4, Vector3.DOWN, 0.8)
	FloatingText.spawn_on_entity(self,
		"CROWN BROKEN — STRIKE NOW", Color(1.0, 0.72, 0.28), 1.6)

func _rearm_thorn_guard() -> void:
	if is_defeated:
		return
	vulnerability_timer  = 0.0
	thorn_guard          = thorn_guard_max
	_guard_rearm_pending = false

	# Restore spike visibility and reset materials to pristine state
	for thorn in _guard_visuals:
		if not is_instance_valid(thorn):
			continue
		thorn.visible = true
		thorn.material_override = _pristine_crown_mat()
		# Reset crack overlays to invisible
		var spike_root := thorn.get_parent()
		for c in 3:
			var crack_node := spike_root.get_node_or_null(
				"CrownCrack_%d_%d" % [_guard_visuals.find(thorn), c])
			if crack_node == null:
				continue
			var cm := (crack_node as MeshInstance3D).material_override as StandardMaterial3D
			if cm:
				cm.emission_energy_multiplier = 0.0

	# Regrowth burst — crown snaps back with a green bramble bloom
	CombatFx.spawn_burst(self, global_position + Vector3.UP * 2.5,
		Color(0.42, 0.72, 0.30, 0.8), 16, 4.0, 0.4, 0.16)
	_update_guard_visuals()

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

## === Crown model helpers (added by model-improvements) ===

func _pristine_crown_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.22, 0.10, 0.07)
	mat.roughness                  = 0.92
	mat.emission_enabled           = true
	mat.emission                   = Color(0.76, 0.18, 0.06)
	mat.emission_energy_multiplier = 0.35
	return mat

## === Redesigned Model Functions ===

func _build_matriarch_body() -> void:
	var visual := get_node_or_null("Visual")
	if visual == null:
		visual = Node3D.new(); visual.name = "Visual"; add_child(visual)
	_carapace_host = Node3D.new()
	_carapace_host.name = "MatriarchBody"
	visual.add_child(_carapace_host)

	_build_main_carapace()
	_build_ribcage_core()
	_build_limbs()
	_build_crown_horns()
	_build_eye_clusters()
	_build_silk_cloak()
	_build_matriarch_overkill()

# ─── Carapace ─────────────────────────────────────────────────────────────────

func _build_main_carapace() -> void:
	var host := _carapace_host
	# Main body segments (3 vertical bulbs — narrow at top, wide at waist)
	var segs := [
		[0.30, 0.82, Vector3(1.0, 0.68, 0.92)],  # lower abdomen
		[1.22, 0.75, Vector3(1.0, 0.85, 0.88)],  # thorax
		[2.28, 0.58, Vector3(0.90, 1.25, 0.85)], # thorax neck
		[3.18, 0.42, Vector3(0.80, 1.10, 0.78)], # head base
	]
	for d in segs:
		var seg := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = d[1]; sm.height = d[1] * 2.0; sm.radial_segments = 16; sm.rings = 10
		seg.mesh = sm
		seg.material_override = _chitin_mat(MAT_CHITIN, MAT_VEIN)
		seg.position.y = d[0]
		seg.scale = d[2]
		host.add_child(seg)

	# Back ridge of fused thorn spines (8)
	for i in 8:
		var t := float(i) / 7.0
		var spine := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0; cm.bottom_radius = 0.075 - t * 0.02; cm.height = 0.38 - t * 0.12; cm.radial_segments = 5
		spine.mesh = cm
		spine.material_override = _chitin_mat(MAT_THORN, MAT_VEIN)
		spine.position = Vector3(0.0, 0.45 + t * 2.7, -0.68 + t * 0.12)
		spine.rotation.x = 0.35 + t * 0.25
		host.add_child(spine)

	# Shoulder pauldrons (two fanned plate clusters)
	for side in [-1.0, 1.0]:
		var phost := Node3D.new()
		phost.position = Vector3(side * 0.82, 2.05, 0.0)
		host.add_child(phost)
		for f in 5:
			var fan := MeshInstance3D.new()
			var fm := CylinderMesh.new()
			var tf := float(f) / 4.0
			fm.top_radius = 0.0; fm.bottom_radius = 0.12 - tf * 0.04
			fm.height = 0.62 - tf * 0.18; fm.radial_segments = 6
			fan.mesh = fm
			fan.material_override = _chitin_mat(MAT_CHITIN, MAT_VEIN)
			fan.position = Vector3(side * tf * 0.28, 0, 0)
			fan.rotation = Vector3(0.0, 0.0, side * (0.4 + tf * 0.7))
			phost.add_child(fan)

# ─── Ribcage + Heart Core ─────────────────────────────────────────────────────

func _build_ribcage_core() -> void:
	var host := Node3D.new()
	host.name = "Ribcage"
	host.position = Vector3(0, 1.45, 0.55)
	_carapace_host.add_child(host)

	# Rib arches (8 curved bone arches forming a cage)
	var rib_mat := StandardMaterial3D.new()
	rib_mat.albedo_color = MAT_RIB
	rib_mat.roughness    = 0.92
	for i in 8:
		var ang := (TAU * float(i) / 8.0) + PI * 0.5
		var rib := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = 0.045; cm.top_radius = 0.020; cm.height = 0.78; cm.radial_segments = 5
		rib.mesh = cm
		rib.material_override = rib_mat
		_rib_mats.append(rib_mat)
		rib.position = Vector3(cos(ang) * 0.52, 0.0, sin(ang) * 0.42)
		rib.rotation = Vector3(cos(ang) * 0.55, 0.0, -sin(ang) * 0.45)
		host.add_child(rib)

	# Heart core (the breakable green gem visible through ribs)
	var heart := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.30; hm.height = 0.52; hm.radial_segments = 16
	heart.mesh = hm
	_core_gem_mat = StandardMaterial3D.new()
	_core_gem_mat.albedo_color = MAT_CORE
	_core_gem_mat.emission_enabled = true
	_core_gem_mat.emission = MAT_CORE
	_core_gem_mat.emission_energy_multiplier = 5.5
	_core_gem_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	heart.material_override = _core_gem_mat
	host.add_child(heart)

	# Core point light
	_core_light = OmniLight3D.new()
	_core_light.light_color  = MAT_CORE
	_core_light.light_energy = 2.8
	_core_light.omni_range   = 7.0
	host.add_child(_core_light)

	# Lens-flare billboard
	var flare := MeshInstance3D.new()
	var qm := QuadMesh.new(); qm.size = Vector2(0.55, 0.55)
	flare.mesh = qm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(MAT_CORE.r, MAT_CORE.g, MAT_CORE.b, 0.55)
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.emission_enabled = true; fmat.emission = MAT_CORE
	fmat.emission_energy_multiplier = 3.5
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flare.material_override = fmat
	flare.position.z = 0.30
	host.add_child(flare)

# ─── Insectoid Limbs ──────────────────────────────────────────────────────────

func _build_limbs() -> void:
	var positions := [
		Vector3( 0.92, 2.10,  0.30), Vector3(-0.92, 2.10,  0.30),
		Vector3( 1.00, 1.30, -0.10), Vector3(-1.00, 1.30, -0.10),
		Vector3( 0.88, 0.55, -0.30), Vector3(-0.88, 0.55, -0.30),
	]
	for i in 6:
		var lr := Node3D.new()
		lr.name = "Limb_%d" % i
		lr.position = positions[i]
		_carapace_host.add_child(lr)
		_limb_roots.append(lr)
		var side := 1.0 if positions[i].x > 0 else -1.0
		_build_insect_limb(lr, side, float(i))

func _build_insect_limb(parent: Node3D, side: float, phase_off: float) -> void:
	var mat := _chitin_mat(MAT_CHITIN, MAT_VEIN)
	# Coxa (hip)
	var coxa := MeshInstance3D.new()
	var c1 := CylinderMesh.new()
	c1.bottom_radius = 0.09; c1.top_radius = 0.06; c1.height = 0.42; c1.radial_segments = 7
	coxa.mesh = c1; coxa.material_override = mat
	coxa.position = Vector3(side * 0.22, -0.08, 0.0)
	coxa.rotation = Vector3(0.15, 0.0, side * 0.55)
	parent.add_child(coxa)
	# Femur
	var femur := MeshInstance3D.new()
	var c2 := CylinderMesh.new()
	c2.bottom_radius = 0.07; c2.top_radius = 0.045; c2.height = 0.62; c2.radial_segments = 6
	femur.mesh = c2; femur.material_override = mat
	femur.position = Vector3(side * 0.50, -0.34, 0.12)
	femur.rotation = Vector3(0.55, 0.0, side * 0.42)
	parent.add_child(femur)
	# Tibia
	var tibia := MeshInstance3D.new()
	var c3 := CylinderMesh.new()
	c3.bottom_radius = 0.050; c3.top_radius = 0.022; c3.height = 0.58; c3.radial_segments = 5
	tibia.mesh = c3; tibia.material_override = mat
	tibia.position = Vector3(side * 0.82, -0.75, 0.28)
	tibia.rotation = Vector3(0.90, 0.0, side * 0.32)
	parent.add_child(tibia)
	# Claw (emissive tip)
	var claw := MeshInstance3D.new()
	var c4 := CylinderMesh.new()
	c4.top_radius = 0.0; c4.bottom_radius = 0.030; c4.height = 0.26; c4.radial_segments = 5
	claw.mesh = c4
	claw.material_override = _chitin_mat(MAT_THORN, MAT_EYE)
	claw.position = Vector3(side * 1.05, -1.05, 0.40)
	claw.rotation = Vector3(1.10, 0.0, side * 0.22)
	parent.add_child(claw)
	# Idle leg sway
	var tw := parent.create_tween().set_loops()
	tw.tween_property(parent, "rotation:z", parent.rotation.z + side * 0.10, 1.4 + phase_off * 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_property(parent, "rotation:z", parent.rotation.z - side * 0.04, 1.4 + phase_off * 0.06).set_trans(Tween.TRANS_SINE)

# ─── Crown Horns ─────────────────────────────────────────────────────────────

func _build_crown_horns() -> void:
	# 12 asymmetric crown horns replacing the simple thorn guard visuals
	var host := Node3D.new()
	host.name = "CrownHorns"
	host.position.y = 3.65
	_carapace_host.add_child(host)

	# Each horn: [angle, radius, height, lean, twist, tip_emit]
	var horn_defs := [
		[0.00,   0.55, 1.15, 0.18, 0.00, true],
		[TAU/12, 0.62, 0.88, 0.30, 0.20, false],
		[2*TAU/12, 0.58, 1.02, 0.25, -0.18, true],
		[3*TAU/12, 0.50, 0.78, 0.35, 0.15, false],
		[4*TAU/12, 0.60, 0.96, 0.22, 0.28, true],
		[5*TAU/12, 0.55, 0.85, 0.30, -0.12, false],
		[6*TAU/12, 0.52, 1.08, 0.20, 0.0,  true],
		[7*TAU/12, 0.58, 0.82, 0.28, 0.22, false],
		[8*TAU/12, 0.62, 1.00, 0.24, -0.20, true],
		[9*TAU/12, 0.50, 0.88, 0.32, 0.18, false],
		[10*TAU/12, 0.56, 0.94, 0.26, 0.0,  true],
		[11*TAU/12, 0.54, 0.80, 0.30, -0.15, false],
	]
	for d in horn_defs:
		var ang : float = d[0]
		var hr  : Node3D = Node3D.new()
		hr.position = Vector3(cos(ang) * d[1], 0.0, sin(ang) * d[1])
		hr.rotation = Vector3(d[3], ang + d[4], 0.0)
		host.add_child(hr)
		# 3-segment stacked horn
		var seg_count := 3
		var y_off := 0.0
		for s in seg_count:
			var seg := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			var tf := float(s) / float(seg_count)
			cm.top_radius = 0.0
			cm.bottom_radius = 0.085 * (1.0 - tf * 0.55)
			cm.height = d[2] * (0.48 - tf * 0.12)
			cm.radial_segments = 6
			seg.mesh = cm
			var hmat := StandardMaterial3D.new()
			hmat.albedo_color = MAT_CROWN
			hmat.roughness    = 0.94
			hmat.emission_enabled = true
			hmat.emission = MAT_VEIN
			hmat.emission_energy_multiplier = 0.15 + float(s) * 0.08
			seg.material_override = hmat
			_crown_horn_mats.append(hmat)
			seg.position.y = y_off + cm.height * 0.5
			seg.rotation.y = d[4] * float(s) * 0.6
			hr.add_child(seg)
			y_off += cm.height
		# Emissive tip shard on every other horn
		if bool(d[5]):
			var tip := MeshInstance3D.new()
			var ttsm := SphereMesh.new()
			ttsm.radius = 0.040; ttsm.height = 0.068
			tip.mesh = ttsm
			var tmat := StandardMaterial3D.new()
			tmat.albedo_color = MAT_VEIN
			tmat.emission_enabled = true; tmat.emission = MAT_VEIN
			tmat.emission_energy_multiplier = 3.8
			tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			tip.material_override = tmat
			tip.position.y = y_off
			hr.add_child(tip)

# ─── Eye Clusters ─────────────────────────────────────────────────────────────

func _build_eye_clusters() -> void:
	# 8 eye clusters arranged in a crown arc on the head section
	var host := Node3D.new()
	host.name = "EyeClusters"
	host.position = Vector3(0, 3.22, 0.60)
	_carapace_host.add_child(host)

	for i in 8:
		var ang := (TAU * float(i) / 8.0) - PI * 0.15
		var cluster := Node3D.new()
		cluster.position = Vector3(cos(ang) * 0.58, sin(ang) * 0.28, 0.0)
		host.add_child(cluster)
		# 3 small eyes per cluster
		for e in 3:
			var eye := MeshInstance3D.new()
			var esm := SphereMesh.new()
			esm.radius = 0.038 - e * 0.008; esm.height = esm.radius * 2.0
			eye.mesh = esm
			var emat := StandardMaterial3D.new()
			emat.albedo_color = MAT_EYE
			emat.emission_enabled = true; emat.emission = MAT_EYE
			emat.emission_energy_multiplier = 3.5 + float(e) * 0.5
			emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			eye.material_override = emat
			_eye_mats_new.append(emat)
			eye.position = Vector3((e - 1.0) * 0.055, float(e % 2) * 0.04, 0.04)
			cluster.add_child(eye)
		# Glow light per cluster
		var el := OmniLight3D.new()
		el.light_color  = MAT_EYE
		el.light_energy = 0.42
		el.omni_range   = 1.8
		cluster.add_child(el)

# ─── Silk Cloak (Verlet physics tendrils) ─────────────────────────────────────

func _build_silk_cloak() -> void:
	_silk_sbs = SpringBoneSystem.new()
	_silk_sbs.name = "SilkCloak"
	_silk_sbs.gravity        = Vector3(0.0, -5.2, 0.0)
	_silk_sbs.damping        = 0.92
	_silk_sbs.stiffness      = 0.08
	_silk_sbs.wind_strength  = 0.15
	_silk_sbs.wind_frequency = 0.48
	_carapace_host.add_child(_silk_sbs)

	# 12 trailing silk tendrils from the back of the abdomen
	var base_pos := _carapace_host.global_position + Vector3(0, 1.2, -0.65) \
		if _carapace_host.is_inside_tree() else Vector3(0, 1.2, -0.65)
	for i in 12:
		var ang := (TAU * float(i) / 12.0) - PI * 0.3
		var spread := 0.62
		var anchor := base_pos + Vector3(cos(ang) * spread * 0.6, 0.0, sin(ang) * spread)
		_silk_sbs.add_chain_at(
			anchor,
			randi_range(5, 9),
			randf_range(0.14, 0.22),
			randf_range(0.018, 0.032),
			MAT_SILK.lerp(MAT_VEIN, randf_range(0.0, 0.45)))

# ─── OverkillGraphicsBoss layer ───────────────────────────────────────────────

func _build_matriarch_overkill() -> void:
	var og := OverkillGraphicsBoss.new()
	og.name        = "OverkillMatriarch"
	og.torso_tint  = MAT_CHITIN
	og.crack_tint  = MAT_VEIN
	og.horn_tint   = MAT_THORN
	og.tendril_tint = MAT_SILK
	og.rune_tint   = MAT_EYE
	og.scale_factor = 1.12
	add_child(og)
	og.setup(self)

# ─── Per-frame animation ──────────────────────────────────────────────────────

func _animate_matriarch(delta: float) -> void:
	_model_t += delta

	# Core heartbeat (faster each phase)
	if _core_gem_mat != null:
		var rate := 1.4 + float(int(current_phase)) * 0.6
		var breathe := 0.82 + 0.18 * sin(_model_t * rate) + 0.06 * sin(_model_t * rate * 2.8)
		var phase_boost := 1.0 + float(int(current_phase)) * 0.4
		_core_gem_mat.emission_energy_multiplier = breathe * 5.5 * phase_boost
		if _core_light != null:
			_core_light.light_energy = breathe * 2.8 * phase_boost

	# Crown horn glow escalates each phase
	var phase_col := MAT_VEIN.lerp(Color(0.95, 0.12, 0.04), float(int(current_phase)) / 3.0)
	var horn_energy := 0.15 + float(int(current_phase)) * 0.55
	for hmat in _crown_horn_mats:
		if is_instance_valid(hmat):
			hmat.emission = phase_col
			hmat.emission_energy_multiplier = horn_energy + sin(_model_t * 2.5) * 0.12

	# Eye pulse pattern + aggro
	var eye_base := 3.5 + sin(_model_t * 4.2) * 1.8
	var eye_mult := 1.0 + float(int(current_phase)) * 0.45
	for emat in _eye_mats_new:
		if is_instance_valid(emat):
			emat.emission_energy_multiplier = eye_base * eye_mult

# ─── Material helpers ─────────────────────────────────────────────────────────

func _chitin_mat(base: Color, emit: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.roughness    = 0.88
	m.metallic     = 0.12
	m.emission_enabled = true
	m.emission = emit
	m.emission_energy_multiplier = 0.10
	return m

