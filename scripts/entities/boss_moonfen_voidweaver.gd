extends BossBase
class_name MoonfenVoidWeaver

## === Moonfen Void Weaver ===
## Realm: Moonfen Drift
## Element: Arcane / Moon
## Visual identity: giant crystalline spider — eight translucent
##   moonstone legs radiating from a teardrop abdomen, fractal crystal
##   web spokes framing a pulsing void eye at the centre,
##   prismatic faceted carapace that refracts moonlight into ghost-blue
##   aurora, dripping silver silk strands from spinnerets.
##
## Combat mechanics:
##   Phase 1 — Web snare (root), crystal spike spread, phase dash
##   Phase 2 — Mirror clones (2 decoys), void rift tear, venom volley
##   Phase 3 — Full web blanket (arena slow), arcane storm, clone swarm
##   Enrage  — True form (carapace shatters to reveal void core),
##              teleport strike, gravity inversion field

const COL_CRYSTAL  := Color(0.62, 0.78, 1.00)
const COL_VOID     := Color(0.14, 0.06, 0.28)
const COL_MOON     := Color(0.82, 0.90, 1.00)
const COL_SILK     := Color(0.55, 0.65, 0.85, 0.65)
const COL_EYE_VOID := Color(0.42, 0.18, 0.88)

var _carapace_mats  : Array[StandardMaterial3D] = []
var _eye_mat        : StandardMaterial3D = null
var _leg_roots      : Array[Node3D] = []
var _silk_trails    : Array[MeshInstance3D] = []
var _clones         : Array[Node3D] = []
var _carapace_root  : Node3D = null
var _true_form      : bool = false

func _ready() -> void:
	authored_model_profile = "boss_voidweaver"
	max_hp     = 1100
	hp         = max_hp
	base_atk   = 20
	move_speed  = 4.5
	arena_radius = 20.0
	diamond_reward = 7
	stage_tints = [
		Color(0.62, 0.78, 1.00),
		Color(0.45, 0.55, 0.90),
		Color(0.28, 0.35, 0.78),
		Color(0.14, 0.06, 0.55),
	]
	stage_armor = [0, 3, 6, 9]
	mend_max_uses = 0
	super._ready()
	_setup_attacks()
	_build_voidweaver_model()
	_build_overkill_layer()

func _setup_attacks() -> void:
	super._setup_attacks()
	attack_cooldowns = {
		"basic": 0.0,
		"web_snare": 0.0,
		"crystal_spikes": 0.0,
		"phase_dash": 0.0,
		"mirror_clones": 0.0,
		"void_rift": 0.0,
		"venom_volley": 0.0,
		"web_blanket": 0.0,
		"arcane_storm": 0.0,
		"gravity_field": 0.0,
	}

func _build_voidweaver_model() -> void:
	var visual := _get_or_create_visual()

	# ── Abdomen (teardrop) ─────────────────────────────────────────────────
	_carapace_root = Node3D.new()
	_carapace_root.name = "Carapace"
	visual.add_child(_carapace_root)

	var abdomen := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = 0.95; am.height = 1.42; am.radial_segments = 16; am.rings = 10
	abdomen.mesh = am
	var amat := _crystal_mat(COL_CRYSTAL, COL_VOID)
	abdomen.material_override = amat
	_carapace_mats.append(amat)
	abdomen.scale = Vector3(1.0, 1.35, 0.90)
	abdomen.position.y = 1.15
	_carapace_root.add_child(abdomen)

	# Faceted crystal plates over abdomen
	for i in 6:
		var ang := TAU * float(i) / 6.0
		var plate := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.25; pm.bottom_radius = 0.30; pm.height = 0.16; pm.radial_segments = 6
		plate.mesh = pm
		var pmat := _crystal_mat(COL_CRYSTAL.lerp(COL_MOON, float(i) * 0.12), COL_VOID)
		plate.material_override = pmat
		_carapace_mats.append(pmat)
		plate.position = Vector3(cos(ang)*0.62, 1.55, sin(ang)*0.55)
		plate.rotation.y = ang
		_carapace_root.add_child(plate)

	# ── Void eye (centre of abdomen) ───────────────────────────────────────
	var eye := MeshInstance3D.new()
	var esm := SphereMesh.new()
	esm.radius = 0.28; esm.height = 0.52
	eye.mesh = esm
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = COL_EYE_VOID
	_eye_mat.emission_enabled = true
	_eye_mat.emission = COL_EYE_VOID
	_eye_mat.emission_energy_multiplier = 6.5
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.material_override = _eye_mat
	eye.position = Vector3(0, 1.22, 0.86)
	_carapace_root.add_child(eye)
	var el := OmniLight3D.new()
	el.light_color = COL_EYE_VOID; el.light_energy = 2.8; el.omni_range = 6.5
	el.position = Vector3(0, 1.22, 0.86)
	_carapace_root.add_child(el)

	# ── Crystal web spokes ─────────────────────────────────────────────────
	for i in 8:
		var spoke_ang := TAU * float(i) / 8.0
		var spoke := MeshInstance3D.new()
		var sbm := BoxMesh.new()
		sbm.size = Vector3(0.022, 0.016, 1.35)
		spoke.mesh = sbm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(COL_SILK.r, COL_SILK.g, COL_SILK.b, 0.45)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.emission_enabled = true
		smat.emission = COL_MOON
		smat.emission_energy_multiplier = 0.85
		spoke.material_override = smat
		spoke.position = Vector3(cos(spoke_ang)*0.55, 1.0, sin(spoke_ang)*0.52)
		spoke.rotation.y = -spoke_ang
		_carapace_root.add_child(spoke)

	# ── Eight crystal legs ─────────────────────────────────────────────────
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var lr := Node3D.new()
		lr.position = Vector3(cos(ang)*0.72, 0.85, sin(ang)*0.65)
		visual.add_child(lr)
		_leg_roots.append(lr)
		_build_spider_leg(lr, ang, float(i))

	# ── Silk drip particles from spinnerets ───────────────────────────────
	var spin := GPUParticles3D.new()
	spin.amount = 20; spin.lifetime = 1.4; spin.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	pm.direction = Vector3(0, -1, 0); pm.spread = 22.0
	pm.initial_velocity_min = 0.4; pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, -1.5, 0)
	pm.scale_min = 0.04; pm.scale_max = 0.12; pm.color = COL_SILK
	spin.process_material = pm
	spin.position = Vector3(0, 0.55, -0.85)
	visual.add_child(spin)

func _build_spider_leg(parent: Node3D, ang: float, phase_offset: float) -> void:
	var mat := _crystal_mat(COL_CRYSTAL, COL_MOON)
	# Femur
	var femur := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.bottom_radius = 0.068; fm.top_radius = 0.045; fm.height = 0.65; fm.radial_segments = 6
	femur.mesh = fm; femur.material_override = mat
	femur.position = Vector3(cos(ang)*0.25, -0.12, sin(ang)*0.22)
	femur.rotation = Vector3(0.32, -ang, 0)
	parent.add_child(femur)
	# Tibia
	var tibia := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.bottom_radius = 0.050; tm.top_radius = 0.028; tm.height = 0.58; tm.radial_segments = 5
	tibia.mesh = tm; tibia.material_override = mat
	tibia.position = Vector3(cos(ang)*0.55, -0.52, sin(ang)*0.48)
	tibia.rotation = Vector3(0.75, -ang, 0)
	parent.add_child(tibia)
	# Claw
	var claw := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0; cm.bottom_radius = 0.030; cm.height = 0.24; cm.radial_segments = 5
	claw.mesh = cm
	claw.material_override = _crystal_mat(COL_MOON, COL_EYE_VOID)
	claw.position = Vector3(cos(ang)*0.80, -0.82, sin(ang)*0.72)
	claw.rotation = Vector3(1.1, -ang, 0)
	parent.add_child(claw)
	# Idle leg drift
	var tw := parent.create_tween().set_loops()
	tw.tween_property(parent, "position:y",
		parent.position.y + 0.10, 0.8 + phase_offset * 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_property(parent, "position:y",
		parent.position.y, 0.8 + phase_offset * 0.06).set_trans(Tween.TRANS_SINE)

func _crystal_mat(base: Color, emit: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(base.r, base.g, base.b, 0.82)
	m.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness     = 0.08; m.metallic = 0.45
	m.emission_enabled = true
	m.emission = emit
	m.emission_energy_multiplier = 0.55
	return m

func _build_overkill_layer() -> void:
	var og := OverkillGraphicsBoss.new()
	og.torso_tint = COL_VOID; og.crack_tint = COL_CRYSTAL
	og.rune_tint  = COL_EYE_VOID; og.tendril_tint = COL_SILK
	og.scale_factor = 0.98
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
			attack_cooldowns["mirror_clones"] = 0.0
			attack_cooldowns["void_rift"]     = 0.0
		BossPhase.PHASE_3:
			attack_cooldowns["web_blanket"]  = 0.0
			attack_cooldowns["arcane_storm"] = 0.0
		BossPhase.ENRAGE:
			enrage_active = true
			_shatter_carapace()
			attack_cooldowns["gravity_field"] = 0.0

func _shatter_carapace() -> void:
	for mat in _carapace_mats:
		if is_instance_valid(mat):
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var tw := create_tween()
			tw.tween_property(mat, "albedo_color:a", 0.0, 0.65).set_trans(Tween.TRANS_EXPO)
	CombatFx.spawn_burst(self, global_position + Vector3(0, 1.5, 0), COL_CRYSTAL, 32, 9.0, 0.55, 0.22)
	_true_form = true
	if _eye_mat != null:
		_eye_mat.emission = COL_VOID
		_eye_mat.emission_energy_multiplier = 16.0

func _try_attacks(player: Node3D, dist: float) -> void:
	if is_action_locked(): return
	super._try_attacks(player, dist)
	if is_action_locked(): return

	if current_phase == BossPhase.ENRAGE and float(attack_cooldowns.get("gravity_field",0.0)) <= 0.0:
		lock_action(2.0); _attack_gravity_field(player)
		attack_cooldowns["gravity_field"] = 15.0; return

	if current_phase >= BossPhase.PHASE_3 and float(attack_cooldowns.get("arcane_storm",0.0)) <= 0.0:
		lock_action(2.2); _attack_arcane_storm(player)
		attack_cooldowns["arcane_storm"] = 22.0; return

	if current_phase >= BossPhase.PHASE_3 and float(attack_cooldowns.get("web_blanket",0.0)) <= 0.0:
		lock_action(1.5); _attack_web_blanket(player)
		attack_cooldowns["web_blanket"] = 18.0; return

	if current_phase >= BossPhase.PHASE_2 and float(attack_cooldowns.get("void_rift",0.0)) <= 0.0:
		lock_action(1.4); _attack_void_rift(player)
		attack_cooldowns["void_rift"] = 16.0; return

	if current_phase >= BossPhase.PHASE_2 and float(attack_cooldowns.get("mirror_clones",0.0)) <= 0.0:
		lock_action(0.8); _attack_mirror_clones()
		attack_cooldowns["mirror_clones"] = 24.0; return

	if float(attack_cooldowns.get("crystal_spikes",0.0)) <= 0.0:
		lock_action(1.0); _attack_crystal_spikes(player)
		attack_cooldowns["crystal_spikes"] = 7.0; return

	if float(attack_cooldowns.get("web_snare",0.0)) <= 0.0 and dist < 8.0:
		lock_action(0.9); _attack_web_snare(player)
		attack_cooldowns["web_snare"] = 10.0; return

	if float(attack_cooldowns.get("phase_dash",0.0)) <= 0.0:
		lock_action(0.6); _attack_phase_dash(player)
		attack_cooldowns["phase_dash"] = 8.0

func _attack_web_snare(player: Node3D) -> void:
	var gen := encounter_generation
	CombatFx.spawn_ground_telegraph(self, player.global_position, 2.8, COL_SILK, 0.75)
	var t := get_tree().create_timer(0.75, false)
	t.timeout.connect(func():
		if is_defeated or gen != encounter_generation: return
		CombatFx.spawn_ring(self, player.global_position, 2.8, COL_MOON, 0.5)
		if player.global_position.distance_to(player.global_position) < 2.8:
			if player.has_method("stun"): player.call("stun", 2.2)
		_deal_area_damage(player.global_position, 2.8, int(base_atk * 0.9)))

func _attack_crystal_spikes(player: Node3D) -> void:
	var gen := encounter_generation
	for s in 7:
		var ang := (float(s) / 7.0) * TAU
		var pos := player.global_position + Vector3(cos(ang)*1.8, 0, sin(ang)*1.8)
		var dl  := float(s) * 0.12
		var t := get_tree().create_timer(dl, false)
		t.timeout.connect(func():
			if is_defeated or gen != encounter_generation: return
			CombatFx.spawn_burst(self, pos + Vector3(0, 1.0, 0), COL_CRYSTAL, 10, 5.5, 0.35, 0.15)
			_deal_area_damage(pos, 1.8, int(base_atk * 1.05)))

func _attack_phase_dash(player: Node3D) -> void:
	CombatFx.spawn_burst(self, global_position, COL_MOON, 12, 4.5, 0.25, 0.12)
	global_position = player.global_position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	CombatFx.spawn_burst(self, global_position, COL_EYE_VOID, 14, 5.0, 0.3, 0.14)
	_deal_area_damage(global_position, 2.5, int(base_atk * 1.2))

func _attack_mirror_clones() -> void:
	for c in _clones:
		if is_instance_valid(c): c.queue_free()
	_clones.clear()
	for i in 2:
		var clone := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.85; sm.height = 1.25; sm.radial_segments = 12
		clone.mesh = sm
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(COL_CRYSTAL.r, COL_CRYSTAL.g, COL_CRYSTAL.b, 0.55)
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cmat.emission_enabled = true; cmat.emission = COL_MOON
		cmat.emission_energy_multiplier = 2.2
		clone.material_override = cmat
		var ang := randf() * TAU
		clone.global_position = global_position + Vector3(cos(ang)*5.0, 0, sin(ang)*5.0)
		if get_tree().current_scene: get_tree().current_scene.add_child(clone)
		_clones.append(clone)
		var tw := create_tween()
		tw.tween_interval(12.0)
		tw.tween_callback(func(): if is_instance_valid(clone): clone.queue_free())

func _attack_void_rift(player: Node3D) -> void:
	var gen := encounter_generation
	var center := (global_position + player.global_position) * 0.5
	CombatFx.spawn_ground_telegraph(self, center, 5.5, COL_EYE_VOID, 1.2)
	var t := get_tree().create_timer(1.2, false)
	t.timeout.connect(func():
		if is_defeated or gen != encounter_generation: return
		CombatFx.spawn_shockwave(self, center, 5.5, COL_VOID, 0.65)
		_deal_area_damage(center, 5.5, int(base_atk * 1.5))
		if player.global_position.distance_to(center) <= 5.5 and player.has_method("stun"):
			player.call("stun", 1.5))

func _attack_web_blanket(_player: Node3D) -> void:
	# Slow the entire arena with a giant web overlay
	CombatFx.spawn_ring(self, global_position, arena_radius, COL_SILK, 1.5)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.has_method("apply_move_slow"):
		player.call("apply_move_slow", 0.35, 6.0)

func _attack_arcane_storm(_player: Node3D) -> void:
	var gen := encounter_generation
	for i in 20:
		var ang := randf() * TAU
		var r   := randf_range(1.5, arena_radius * 0.7)
		var pos := global_position + Vector3(cos(ang)*r, 0, sin(ang)*r)
		var dl  := randf_range(0.1, 1.8)
		var t := get_tree().create_timer(dl, false)
		t.timeout.connect(func():
			if is_defeated or gen != encounter_generation: return
			CombatFx.spawn_burst(self, pos + Vector3(0, 0.8, 0), COL_EYE_VOID, 10, 5.5, 0.4, 0.15)
			_deal_area_damage(pos, 2.2, int(base_atk * 0.8)))

func _attack_gravity_field(player: Node3D) -> void:
	# Pull player toward boss then blast outward
	var gen := encounter_generation
	CombatFx.spawn_ring(self, global_position, 8.0, COL_EYE_VOID, 1.0)
	var t := get_tree().create_timer(1.0, false)
	t.timeout.connect(func():
		if is_defeated or gen != encounter_generation: return
		CombatFx.spawn_shockwave(self, global_position, 8.0, COL_VOID, 0.55)
		_deal_area_damage(global_position, 8.0, int(base_atk * 1.4))
		if player.has_method("notify_enemy_strike"):
			player.call("notify_enemy_strike", self, int(base_atk * 1.4)))

func _process(delta: float) -> void:
	super._process(delta)
	if is_defeated: return
	var t := Time.get_ticks_msec() * 0.004
	var pulse := 4.0 + sin(t) * 2.5
	if _eye_mat != null:
		_eye_mat.emission_energy_multiplier = pulse * (1.0 + float(int(current_phase)) * 0.5)
	# Rotate carapace slowly
	if _carapace_root != null:
		_carapace_root.rotation.y += delta * 0.18 * (1.0 + float(int(current_phase)) * 0.3)

func _spawn_rewards() -> void:
	if is_practice: return
	var rm := get_node_or_null("/root/RewardManager")
	if rm != null:
		rm.call("grant_boss_kill", "moonfen_voidweaver", was_first_kill, "moonfen")
