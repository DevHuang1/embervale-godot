extends BossBase
class_name HeartwoodCinderColossus

## === Heartwood Cinder Colossus ===
## Realm: The Heartwood
## Element: Fire / Magma
## Visual identity: towering bipedal lava golem — cracked volcanic
##   obsidian body with exposed magma veins, 4 massive pillar arms
##   ending in clenched fist clusters, a volcanic crown of erupting
##   spires, and a hollow chest crater housing a churning lava core.
##   Magma "drips" fall from the body as particle trails when moving.
##
## Combat mechanics:
##   Phase 1 — Ground pound (AoE ring), magma fist slam, magma trail
##   Phase 2 — Lava pillar barrage (random ground eruptions), shell shed
##   Phase 3 — Volcanic crown eruption (8-direction spike launch), heat wave
##   Enrage  — Body ignites fully, continuous magma rain, massive speed

const COL_OBSIDIAN := Color(0.10, 0.07, 0.06)
const COL_MAGMA    := Color(1.00, 0.38, 0.06)
const COL_LAVA     := Color(1.00, 0.65, 0.12)
const COL_ASH      := Color(0.48, 0.38, 0.32, 0.70)

var _body_seam_mats : Array[StandardMaterial3D] = []
var _core_mat       : StandardMaterial3D = null
var _crown_spires   : Array[MeshInstance3D] = []
var _fist_roots     : Array[Node3D] = []
var _drip_particles : Array[GPUParticles3D] = []
var _shell_visible  : bool = true

func _ready() -> void:
	authored_model_profile = "boss_cindercolossus"
	max_hp     = 1400
	hp         = max_hp
	base_atk   = 22
	move_speed  = 2.8
	arena_radius = 26.0
	diamond_reward = 8
	stage_tints = [
		Color(1.0, 0.38, 0.06),
		Color(1.0, 0.22, 0.04),
		Color(0.90, 0.10, 0.03),
		Color(0.75, 0.05, 0.02),
	]
	stage_armor = [0, 5, 9, 14]
	mend_max_uses = 2
	super._ready()
	_setup_attacks()
	_build_colossus_model()
	_build_overkill_layer()

func _setup_attacks() -> void:
	super._setup_attacks()
	attack_cooldowns = {
		"basic": 0.0,
		"ground_pound": 0.0,
		"magma_fist": 0.0,
		"lava_pillars": 0.0,
		"shell_shed": 0.0,
		"crown_eruption": 0.0,
		"heat_wave": 0.0,
		"magma_rain": 0.0,
	}

func _build_colossus_model() -> void:
	var visual := _get_or_create_visual()

	# ── Main torso (3 stacked boulders) ───────────────────────────────────
	var torso_data := [
		[0.35, 1.10, 1.05], [1.20, 0.88, 1.00], [2.25, 0.72, 0.88],
	]
	for d in torso_data:
		var seg := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = d[1]; sm.height = d[1] * 2.0; sm.radial_segments = 14
		seg.mesh = sm
		seg.material_override = _volcanic_mat()
		seg.position.y = d[0]
		seg.scale = Vector3(d[2], 1.0, d[2])
		visual.add_child(seg)
		# Lava seams on each torso segment
		for i in 4:
			var ang := TAU * float(i) / 4.0 + randf_range(-0.2, 0.2)
			_add_lava_seam(visual, Vector3(cos(ang)*d[1]*0.85, d[0], sin(ang)*d[1]*0.85))

	# ── Chest crater + lava core ─────────────────────────────────────────
	var crater_host := Node3D.new()
	crater_host.position = Vector3(0, 1.8, 0.85)
	visual.add_child(crater_host)
	var crater := MeshInstance3D.new()
	var ctm := TorusMesh.new()
	ctm.inner_radius = 0.28; ctm.outer_radius = 0.55; ctm.ring_segments = 24; ctm.rings = 4
	crater.mesh = ctm
	crater.material_override = _volcanic_mat()
	crater.rotation.x = PI * 0.5
	crater_host.add_child(crater)
	var core := MeshInstance3D.new()
	var csm := SphereMesh.new()
	csm.radius = 0.28; csm.height = 0.55
	core.mesh = csm
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color = COL_LAVA
	_core_mat.emission_enabled = true
	_core_mat.emission = COL_MAGMA
	_core_mat.emission_energy_multiplier = 7.5
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = _core_mat
	crater_host.add_child(core)
	var cl := OmniLight3D.new()
	cl.light_color = COL_MAGMA; cl.light_energy = 4.2; cl.omni_range = 9.0
	crater_host.add_child(cl)

	# ── Four massive arms ─────────────────────────────────────────────────
	var arm_defs := [
		Vector3( 1.25, 1.85,  0.30), Vector3(-1.25, 1.85,  0.30),
		Vector3( 1.10, 0.85, -0.20), Vector3(-1.10, 0.85, -0.20),
	]
	for i in 4:
		_build_colossus_arm(visual, arm_defs[i], 1.0 if i % 2 == 0 else -1.0)

	# ── Volcanic crown ────────────────────────────────────────────────────
	var crown := Node3D.new()
	crown.name = "VolcanicCrown"
	crown.position.y = 3.35
	visual.add_child(crown)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var spire := MeshInstance3D.new()
		var spm := CylinderMesh.new()
		spm.top_radius = 0.0
		spm.bottom_radius = 0.10 + (i % 3) * 0.04
		spm.height = 0.65 + (i % 4) * 0.18
		spm.radial_segments = 6
		spire.mesh = spm
		spire.material_override = _volcanic_mat()
		spire.position = Vector3(cos(ang) * 0.62, spm.height * 0.5, sin(ang) * 0.62)
		spire.rotation.z = cos(ang) * 0.25
		crown.add_child(spire)
		_crown_spires.append(spire)

	# ── Legs ─────────────────────────────────────────────────────────────
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.bottom_radius = 0.38; lm.top_radius = 0.28; lm.height = 1.05; lm.radial_segments = 9
		leg.mesh = lm
		leg.material_override = _volcanic_mat()
		leg.position = Vector3(side * 0.65, -0.22, 0.0)
		visual.add_child(leg)
		var foot := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.bottom_radius = 0.52; fm.top_radius = 0.38; fm.height = 0.32; fm.radial_segments = 9
		foot.mesh = fm
		foot.material_override = _volcanic_mat()
		foot.position = Vector3(side * 0.65, -0.78, 0.0)
		visual.add_child(foot)

	# ── Magma drip particles ───────────────────────────────────────────────
	for i in 4:
		var dp := GPUParticles3D.new()
		dp.amount = 18; dp.lifetime = 1.0; dp.emitting = true
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.65
		pm.direction = Vector3(0, -1, 0); pm.spread = 30.0
		pm.initial_velocity_min = 0.5; pm.initial_velocity_max = 1.8
		pm.gravity = Vector3(0, -3.5, 0)
		pm.scale_min = 0.06; pm.scale_max = 0.18; pm.color = COL_MAGMA
		dp.process_material = pm
		dp.position.y = 1.5
		visual.add_child(dp)
		_drip_particles.append(dp)

func _build_colossus_arm(parent: Node3D, attach: Vector3, side: float) -> void:
	var arm_root := Node3D.new()
	arm_root.position = attach
	parent.add_child(arm_root)
	_fist_roots.append(arm_root)
	# Upper arm
	var upper := MeshInstance3D.new()
	var um := CylinderMesh.new()
	um.bottom_radius = 0.30; um.top_radius = 0.22; um.height = 0.85; um.radial_segments = 8
	upper.mesh = um; upper.material_override = _volcanic_mat()
	upper.position = Vector3(0, -0.3, 0)
	upper.rotation = Vector3(0.2, 0, side * 0.55)
	arm_root.add_child(upper)
	# Lower arm
	var lower := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.bottom_radius = 0.25; lm.top_radius = 0.18; lm.height = 0.70; lm.radial_segments = 8
	lower.mesh = lm; lower.material_override = _volcanic_mat()
	lower.position = Vector3(side * 0.32, -0.85, 0.18)
	lower.rotation = Vector3(0.6, 0, side * 0.4)
	arm_root.add_child(lower)
	# Fist cluster (3 boulders)
	var fist_anchor := Vector3(side * 0.52, -1.3, 0.32)
	for k in 3:
		var knuckle := MeshInstance3D.new()
		var km := SphereMesh.new()
		km.radius = 0.18 - k * 0.04; km.height = km.radius * 2.0; km.radial_segments = 8
		knuckle.mesh = km; knuckle.material_override = _volcanic_mat()
		knuckle.position = fist_anchor + Vector3((k - 1) * 0.14, 0, (k % 2) * 0.10)
		arm_root.add_child(knuckle)
	# Idle sway
	var tw := arm_root.create_tween().set_loops()
	tw.tween_property(arm_root, "rotation:z", arm_root.rotation.z + side * 0.08, 1.6 + randf() * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(arm_root, "rotation:z", arm_root.rotation.z, 1.6 + randf() * 0.5).set_trans(Tween.TRANS_SINE)

func _add_lava_seam(parent: Node3D, pos: Vector3) -> void:
	var seam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(randf_range(0.04, 0.10), randf_range(0.18, 0.55), 0.035)
	seam.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.02, 0.01)
	mat.emission_enabled = true
	mat.emission = COL_MAGMA
	mat.emission_energy_multiplier = randf_range(1.6, 3.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	seam.material_override = mat
	_body_seam_mats.append(mat)
	seam.global_position = parent.global_position + pos if parent.is_inside_tree() else pos
	seam.position = pos
	seam.rotation = Vector3(randf_range(-0.5, 0.5), randf_range(0.0, TAU), 0.0)
	parent.add_child(seam)

func _volcanic_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = COL_OBSIDIAN
	m.roughness    = 0.88; m.metallic = 0.08
	m.emission_enabled = true
	m.emission = COL_MAGMA
	m.emission_energy_multiplier = 0.12
	return m

func _build_overkill_layer() -> void:
	var og := OverkillGraphicsBoss.new()
	og.torso_tint = COL_OBSIDIAN; og.crack_tint = COL_MAGMA
	og.rune_tint  = COL_LAVA;     og.tendril_tint = COL_ASH
	og.scale_factor = 1.18
	add_child(og); og.setup(self)

func _get_or_create_visual() -> Node3D:
	var v := get_node_or_null("Visual")
	if v != null: return v
	v = Node3D.new(); v.name = "Visual"; add_child(v); return v

# ─── Attacks ─────────────────────────────────────────────────────────────────

func _on_phase_transition() -> void:
	super._on_phase_transition()
	match current_phase:
		BossPhase.PHASE_2:
			attack_cooldowns["lava_pillars"] = 0.0
			attack_cooldowns["shell_shed"]   = 0.0
		BossPhase.PHASE_3:
			attack_cooldowns["crown_eruption"] = 0.0
		BossPhase.ENRAGE:
			enrage_active = true
			attack_cooldowns["magma_rain"] = 0.0
			if _core_mat != null:
				_core_mat.emission_energy_multiplier = 18.0

func _try_attacks(player: Node3D, dist: float) -> void:
	if is_action_locked(): return
	super._try_attacks(player, dist)
	if is_action_locked(): return

	if current_phase == BossPhase.ENRAGE and float(attack_cooldowns.get("magma_rain",0.0)) <= 0.0:
		lock_action(2.5); _attack_magma_rain(player)
		attack_cooldowns["magma_rain"] = 8.0; return

	if current_phase >= BossPhase.PHASE_3 and float(attack_cooldowns.get("crown_eruption",0.0)) <= 0.0:
		lock_action(1.8); _attack_crown_eruption()
		attack_cooldowns["crown_eruption"] = 22.0; return

	if current_phase >= BossPhase.PHASE_3 and float(attack_cooldowns.get("heat_wave",0.0)) <= 0.0:
		lock_action(1.2); _attack_heat_wave(player)
		attack_cooldowns["heat_wave"] = 14.0; return

	if current_phase >= BossPhase.PHASE_2 and float(attack_cooldowns.get("lava_pillars",0.0)) <= 0.0:
		lock_action(2.0); _attack_lava_pillars(player)
		attack_cooldowns["lava_pillars"] = 18.0; return

	if float(attack_cooldowns.get("ground_pound",0.0)) <= 0.0:
		lock_action(1.1); _attack_ground_pound(player)
		attack_cooldowns["ground_pound"] = 6.0; return

	if float(attack_cooldowns.get("magma_fist",0.0)) <= 0.0 and dist < 5.0:
		lock_action(0.9); _attack_magma_fist(player)
		attack_cooldowns["magma_fist"] = 4.0

func _attack_ground_pound(_player: Node3D) -> void:
	_shake_camera(0.55)
	animator.trigger_attack() if animator else null
	CombatFx.spawn_shockwave(self, global_position, arena_radius * 0.55, COL_MAGMA, 0.65)
	_deal_area_damage(global_position, 4.5, int(base_atk * 1.4))
	ImpactDirector.apply_feedback(self, "heavy", global_position, Vector3.UP, 0.8) \
		if get_node_or_null("/root/ImpactDirector") != null else null

func _attack_magma_fist(player: Node3D) -> void:
	_shake_camera(0.38)
	CombatFx.spawn_slash(self, player.global_position + Vector3(0, 1.2, 0), COL_MAGMA)
	CombatFx.spawn_burst(self, player.global_position + Vector3(0, 0.8, 0), COL_LAVA, 18, 6.0, 0.4, 0.18)
	_deal_area_damage(player.global_position, 3.5, int(base_atk * 1.6))
	if player.has_method("notify_enemy_strike"):
		player.call("notify_enemy_strike", self, int(base_atk * 1.6))

func _attack_lava_pillars(player: Node3D) -> void:
	_shake_camera(0.45)
	var gen := encounter_generation
	for i in 10:
		var ang  := randf() * TAU
		var dist := randf_range(2.0, arena_radius * 0.65)
		var pos  := player.global_position + Vector3(cos(ang)*dist, 0, sin(ang)*dist)
		var dl   := randf_range(0.4, 1.8)
		CombatFx.spawn_ground_telegraph(self, pos, 2.8, COL_MAGMA, dl)
		var t := get_tree().create_timer(dl, false)
		t.timeout.connect(func():
			if is_defeated or gen != encounter_generation: return
			CombatFx.spawn_burst(self, pos + Vector3(0, 1.0, 0), COL_LAVA, 20, 7.0, 0.45, 0.18)
			_deal_area_damage(pos, 2.8, int(base_atk * 1.2)))

func _attack_crown_eruption() -> void:
	_shake_camera(0.65)
	var gen := encounter_generation
	# Flash crown spires
	for spire in _crown_spires:
		if is_instance_valid(spire) and spire.material_override is StandardMaterial3D:
			var mat := spire.material_override as StandardMaterial3D
			mat.emission = COL_LAVA
			mat.emission_energy_multiplier = 8.5
	var t := get_tree().create_timer(0.85, false)
	t.timeout.connect(func():
		if is_defeated or gen != encounter_generation: return
		for i in 8:
			var ang := TAU * float(i) / 8.0
			var dir := Vector3(cos(ang), 0.55, sin(ang)).normalized()
			var end := global_position + dir * (arena_radius * 0.75)
			CombatFx.spawn_ring(self, end, 3.5, COL_MAGMA, 0.55)
			_deal_area_damage(end, 3.5, int(base_atk * 1.8)))

func _attack_heat_wave(player: Node3D) -> void:
	var gen := encounter_generation
	for w in 3:
		var r  := 5.0 + w * 7.0
		var dl := 0.5 + w * 0.5
		CombatFx.spawn_ground_telegraph(self, global_position, r, Color(0.85, 0.28, 0.06), dl)
		var t := get_tree().create_timer(dl, false)
		t.timeout.connect(func():
			if is_defeated or gen != encounter_generation: return
			CombatFx.spawn_ring(self, global_position, r, COL_MAGMA, 0.55)
			_deal_area_damage(global_position, r * 0.45, int(base_atk * 0.9)))

func _attack_magma_rain(_player: Node3D) -> void:
	var gen := encounter_generation
	for i in 16:
		var ang := randf() * TAU
		var r   := randf_range(1.0, arena_radius * 0.8)
		var pos := global_position + Vector3(cos(ang)*r, 0, sin(ang)*r)
		var dl  := randf_range(0.2, 1.2)
		var t := get_tree().create_timer(dl, false)
		t.timeout.connect(func():
			if is_defeated or gen != encounter_generation: return
			CombatFx.spawn_burst(self, pos + Vector3(0, 0.6, 0), COL_MAGMA, 12, 5.5, 0.38, 0.14)
			_deal_area_damage(pos, 2.4, int(base_atk * 0.75)))

func _process(delta: float) -> void:
	super._process(delta)
	if is_defeated: return
	var t := Time.get_ticks_msec() * 0.003
	var breathe := 0.85 + 0.15 * sin(t) + 0.06 * sin(t * 2.7)
	var phase_mult := 1.0 + float(int(current_phase)) * 0.4
	if _core_mat != null:
		_core_mat.emission_energy_multiplier = breathe * 7.5 * phase_mult
	for smat in _body_seam_mats:
		if is_instance_valid(smat):
			smat.emission_energy_multiplier = 1.4 + sin(t * 1.5) * 0.8

func _spawn_rewards() -> void:
	if is_practice: return
	var rm := get_node_or_null("/root/RewardManager")
	if rm != null:
		rm.call("grant_boss_kill", "heartwood_cindercolossus", was_first_kill, "heartwood")
