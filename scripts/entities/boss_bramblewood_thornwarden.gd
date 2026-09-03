extends BossBase
class_name BrambleThornWarden

## === Bramblewood Thorn Warden ===
## Realm: Whispergrove / Bramblewood (second boss)
## Element: Nature / Earth
## Visual identity: ancient forest golem — body composed of fused
##   oak roots and mossy stone, crowned with a living antler rack
##   entwined with glowing amber sap veins, massive club fists
##   wrapped in thorn vines, eyes are two burning amber orbs
##   embedded in bark, bark plates crack to reveal soft bioluminescent
##   heartwood as phases progress.
##
## Combat mechanics:
##   Phase 1 — Root slam (ground shockwave), vine grab, bark armor (absorbs hits)
##   Phase 2 — Thorn hurricane (spinning AoE), grove call (summon Hushlings),
##              sap snare (slow field)
##   Phase 3 — Heartwood pulse (proximity nova), bark shed + vulnerability,
##              wandering boulders
##   Enrage  — Bark fully stripped, heartwood exposed, massive nova spam,
##              arena-wide thorn eruption

const COL_BARK      := Color(0.18, 0.12, 0.08)
const COL_MOSS      := Color(0.22, 0.38, 0.16)
const COL_SAP       := Color(1.00, 0.72, 0.18)
const COL_HEARTWOOD := Color(0.88, 0.48, 0.12)
const COL_THORN     := Color(0.12, 0.10, 0.07)
const COL_AMBER_EYE := Color(1.00, 0.65, 0.12)

var _bark_plates    : Array[MeshInstance3D] = []
var _sap_mats       : Array[StandardMaterial3D] = []
var _eye_mats       : Array[StandardMaterial3D] = []
var _heartwood_mat  : StandardMaterial3D = null
var _antler_root    : Node3D = null
var _bark_hp        : int = 60   # Bark absorbs this much before shedding
var _bark_active    : bool = true
var _summoned_pack  : Array[Node3D] = []

func _ready() -> void:
	authored_model_profile = "boss_thornwarden"
	max_hp     = 1200
	hp         = max_hp
	base_atk   = 19
	move_speed  = 3.0
	arena_radius = 24.0
	diamond_reward = 7
	stage_tints = [
		Color(1.00, 0.72, 0.18),
		Color(0.95, 0.55, 0.12),
		Color(0.88, 0.38, 0.08),
		Color(0.80, 0.20, 0.04),
	]
	stage_armor = [0, 4, 8, 12]
	mend_max_uses = 2
	super._ready()
	_setup_attacks()
	_build_thornwarden_model()
	_build_overkill_layer()

func _setup_attacks() -> void:
	super._setup_attacks()
	attack_cooldowns = {
		"basic": 0.0,
		"root_slam": 0.0,
		"vine_grab": 0.0,
		"thorn_hurricane": 0.0,
		"grove_call": 0.0,
		"sap_snare": 0.0,
		"heartwood_pulse": 0.0,
		"boulder_roll": 0.0,
		"thorn_eruption": 0.0,
	}

func _build_thornwarden_model() -> void:
	var visual := _get_or_create_visual()

	# ── Root-fused torso ───────────────────────────────────────────────────
	for i in 5:
		var seg := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.85 - i * 0.06; sm.height = sm.radius * 2.0; sm.radial_segments = 12
		seg.mesh = sm
		seg.material_override = _bark_mat()
		seg.position.y = float(i) * 0.52
		seg.scale = Vector3(1.05 - i * 0.04, 1.0, 1.0)
		visual.add_child(seg)

	# ── Heartwood core (exposed on shed) ──────────────────────────────────
	var hw := MeshInstance3D.new()
	var hwm := SphereMesh.new()
	hwm.radius = 0.52; hwm.height = 0.95
	hw.mesh = hwm
	_heartwood_mat = StandardMaterial3D.new()
	_heartwood_mat.albedo_color = COL_HEARTWOOD
	_heartwood_mat.emission_enabled = true
	_heartwood_mat.emission = COL_SAP
	_heartwood_mat.emission_energy_multiplier = 0.0   # hidden until shed
	hw.material_override = _heartwood_mat
	hw.position.y = 1.2
	visual.add_child(hw)

	# ── Bark plate armour (8 plates) ──────────────────────────────────────
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var plate := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.0; pm.bottom_radius = 0.32; pm.height = 0.55; pm.radial_segments = 6
		plate.mesh = pm
		plate.material_override = _bark_mat()
		plate.position = Vector3(cos(ang)*0.78, 1.25, sin(ang)*0.72)
		plate.rotation = Vector3(sin(ang)*0.4, ang, cos(ang)*0.3)
		visual.add_child(plate)
		_bark_plates.append(plate)

	# ── Sap vein cracks ───────────────────────────────────────────────────
	for i in 8:
		var vein := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.028, randf_range(0.18, 0.55), 0.025)
		vein.mesh = bm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = COL_SAP
		smat.emission_enabled = true
		smat.emission = COL_SAP
		smat.emission_energy_multiplier = 1.2
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		vein.material_override = smat
		_sap_mats.append(smat)
		var ang := TAU * float(i) / 8.0 + randf_range(-0.3, 0.3)
		vein.position = Vector3(cos(ang)*0.82, randf_range(0.4, 2.2), sin(ang)*0.76)
		vein.rotation = Vector3(randf_range(-0.5, 0.5), ang, 0)
		visual.add_child(vein)

	# ── Antler crown ──────────────────────────────────────────────────────
	_antler_root = Node3D.new()
	_antler_root.name = "AntlerCrown"
	_antler_root.position.y = 2.95
	visual.add_child(_antler_root)
	for side in [-1.0, 1.0]:
		_build_antler(_antler_root, side)

	# ── Amber eyes ────────────────────────────────────────────────────────
	for side in [-1.0, 1.0]:
		var eye_root := Node3D.new()
		eye_root.position = Vector3(0.32 * side, 2.55, 0.72)
		visual.add_child(eye_root)
		var eye := MeshInstance3D.new()
		var esm := SphereMesh.new()
		esm.radius = 0.10; esm.height = 0.18
		eye.mesh = esm
		var emat := StandardMaterial3D.new()
		emat.albedo_color = COL_AMBER_EYE
		emat.emission_enabled = true
		emat.emission = COL_AMBER_EYE
		emat.emission_energy_multiplier = 4.0
		emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		eye.material_override = emat
		_eye_mats.append(emat)
		eye_root.add_child(eye)
		var el := OmniLight3D.new()
		el.light_color = COL_SAP; el.light_energy = 0.9; el.omni_range = 3.5
		eye_root.add_child(el)

	# ── Club fists ────────────────────────────────────────────────────────
	for side in [-1.0, 1.0]:
		var arm_root := Node3D.new()
		arm_root.position = Vector3(1.0 * side, 1.5, 0.0)
		visual.add_child(arm_root)
		# Arm
		var arm := MeshInstance3D.new()
		var acm := CylinderMesh.new()
		acm.bottom_radius = 0.28; acm.top_radius = 0.20; acm.height = 0.90; acm.radial_segments = 8
		arm.mesh = acm; arm.material_override = _bark_mat()
		arm.position.y = -0.28
		arm.rotation = Vector3(0.18, 0, side * 0.45)
		arm_root.add_child(arm)
		# Club
		var club := MeshInstance3D.new()
		var clm := SphereMesh.new()
		clm.radius = 0.38; clm.height = 0.62; clm.radial_segments = 10
		club.mesh = clm; club.material_override = _bark_mat()
		club.position = Vector3(side * 0.30, -0.98, 0.18)
		club.scale = Vector3(1.0, 0.85, 0.9)
		arm_root.add_child(club)
		# Thorn wrap
		for t in 6:
			var thorn := MeshInstance3D.new()
			var tm := CylinderMesh.new()
			tm.top_radius = 0.0; tm.bottom_radius = 0.028; tm.height = 0.22; tm.radial_segments = 4
			thorn.mesh = tm
			thorn.material_override = _bark_mat_dark()
			var tang := TAU * float(t) / 6.0
			thorn.position = club.position + Vector3(cos(tang)*0.32, 0.08, sin(tang)*0.30)
			thorn.rotation = Vector3(sin(tang)*0.6, tang, cos(tang)*0.5)
			arm_root.add_child(thorn)
		# Idle sway
		var tw := arm_root.create_tween().set_loops()
		tw.tween_property(arm_root, "rotation:z", arm_root.rotation.z + side * 0.10, 1.8).set_trans(Tween.TRANS_SINE)
		tw.tween_property(arm_root, "rotation:z", arm_root.rotation.z - side * 0.05, 1.8).set_trans(Tween.TRANS_SINE)

func _build_antler(parent: Node3D, side: float) -> void:
	var mat := _bark_mat_dark()
	var base_ang := side * 0.45
	var points := [
		[Vector3(side * 0.35, 0.0, 0.0), Vector3(side * 0.22, 0.72, -0.18)],
		[Vector3(side * 0.48, 0.38, -0.08), Vector3(side * 0.65, 0.95, 0.12)],
		[Vector3(side * 0.62, 0.65, 0.15), Vector3(side * 0.75, 1.15, -0.22)],
	]
	for p in points:
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = randf_range(0.045, 0.075)
		cm.height = p[0].distance_to(p[1])
		cm.radial_segments = 5
		seg.mesh = cm; seg.material_override = mat
		seg.global_position = parent.global_position + p[0] if parent.is_inside_tree() else p[0]
		seg.position = p[0]
		seg.look_at_from_position(p[0], p[1], Vector3.UP) if p[0] != p[1] else null
		parent.add_child(seg)
		# Sap glow on antler tips
		if points.find(p) == points.size() - 1:
			var glow := OmniLight3D.new()
			glow.light_color = COL_SAP; glow.light_energy = 0.55; glow.omni_range = 2.2
			glow.position = p[1]
			parent.add_child(glow)

func _bark_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = COL_BARK; m.roughness = 0.92; m.metallic = 0.0
	m.emission_enabled = true; m.emission = COL_SAP; m.emission_energy_multiplier = 0.08
	return m

func _bark_mat_dark() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = COL_THORN; m.roughness = 0.96; return m

func _build_overkill_layer() -> void:
	var og := OverkillGraphicsBoss.new()
	og.torso_tint = COL_BARK; og.crack_tint = COL_SAP
	og.horn_tint  = COL_THORN; og.tendril_tint = COL_MOSS
	og.rune_tint  = COL_AMBER_EYE; og.scale_factor = 1.10
	add_child(og); og.setup(self)

func _get_or_create_visual() -> Node3D:
	var v := get_node_or_null("Visual"); if v: return v
	v = Node3D.new(); v.name = "Visual"; add_child(v); return v

# ─── Attacks ─────────────────────────────────────────────────────────────────

func _on_phase_transition() -> void:
	super._on_phase_transition()
	match current_phase:
		BossPhase.PHASE_2:
			attack_cooldowns["thorn_hurricane"] = 0.0
			attack_cooldowns["grove_call"]      = 0.0
		BossPhase.PHASE_3:
			attack_cooldowns["heartwood_pulse"] = 0.0
			attack_cooldowns["boulder_roll"]    = 0.0
			_shed_bark()
		BossPhase.ENRAGE:
			enrage_active = true
			attack_cooldowns["thorn_eruption"] = 0.0
			if _heartwood_mat != null:
				_heartwood_mat.emission_energy_multiplier = 12.0

func _shed_bark() -> void:
	_bark_active = false
	for plate in _bark_plates:
		if is_instance_valid(plate):
			var tw := plate.create_tween()
			tw.tween_property(plate, "position:y", plate.position.y - 2.5, 0.65).set_trans(Tween.TRANS_QUAD)
			tw.tween_callback(plate.queue_free)
	_bark_plates.clear()
	if _heartwood_mat != null:
		var tw := create_tween()
		tw.tween_property(_heartwood_mat, "emission_energy_multiplier", 6.5, 0.8)
	CombatFx.spawn_burst(self, global_position + Vector3(0, 1.5, 0), COL_SAP, 24, 7.0, 0.55, 0.20)
	FloatingText.spawn_on_entity(self, "HEARTWOOD EXPOSED", Color(1.0, 0.75, 0.25), 0.07)

func take_damage(amount: int, knockback_dir: Vector3, critical: bool = false) -> void:
	if is_defeated: return
	var applied := amount
	if _bark_active and _bark_hp > 0:
		_bark_hp -= amount
		if _bark_hp <= 0:
			_bark_active = false
			_shed_bark()
		else:
			# Bark absorbs but show reduced damage
			applied = maxi(1, amount / 4)
	super.take_damage(applied, knockback_dir, critical)

func _try_attacks(player: Node3D, dist: float) -> void:
	if is_action_locked(): return
	super._try_attacks(player, dist)
	if is_action_locked(): return

	if current_phase == BossPhase.ENRAGE and float(attack_cooldowns.get("thorn_eruption",0.0)) <= 0.0:
		lock_action(2.5); _attack_thorn_eruption(player)
		attack_cooldowns["thorn_eruption"] = 10.0; return

	if current_phase >= BossPhase.PHASE_3 and float(attack_cooldowns.get("heartwood_pulse",0.0)) <= 0.0 and dist < 6.0:
		lock_action(1.0); _attack_heartwood_pulse()
		attack_cooldowns["heartwood_pulse"] = 12.0; return

	if current_phase >= BossPhase.PHASE_3 and float(attack_cooldowns.get("boulder_roll",0.0)) <= 0.0:
		lock_action(1.4); _attack_boulder_roll(player)
		attack_cooldowns["boulder_roll"] = 16.0; return

	if current_phase >= BossPhase.PHASE_2 and float(attack_cooldowns.get("thorn_hurricane",0.0)) <= 0.0:
		lock_action(2.0); _attack_thorn_hurricane()
		attack_cooldowns["thorn_hurricane"] = 20.0; return

	if current_phase >= BossPhase.PHASE_2 and float(attack_cooldowns.get("grove_call",0.0)) <= 0.0:
		lock_action(0.8); _attack_grove_call()
		attack_cooldowns["grove_call"] = 28.0; return

	if current_phase >= BossPhase.PHASE_2 and float(attack_cooldowns.get("sap_snare",0.0)) <= 0.0 and dist < 9.0:
		lock_action(0.9); _attack_sap_snare(player)
		attack_cooldowns["sap_snare"] = 12.0; return

	if float(attack_cooldowns.get("root_slam",0.0)) <= 0.0:
		lock_action(1.2); _attack_root_slam(player)
		attack_cooldowns["root_slam"] = 6.0; return

	if float(attack_cooldowns.get("vine_grab",0.0)) <= 0.0 and dist < 6.0:
		lock_action(0.8); _attack_vine_grab(player)
		attack_cooldowns["vine_grab"] = 7.0

func _attack_root_slam(_player: Node3D) -> void:
	animator.trigger_attack() if animator else null
	_shake_camera(0.60)
	CombatFx.spawn_shockwave(self, global_position, 5.5, COL_SAP, 0.55)
	_deal_area_damage(global_position, 5.5, int(base_atk * 1.5))

func _attack_vine_grab(player: Node3D) -> void:
	var gen := encounter_generation
	CombatFx.spawn_ground_telegraph(self, player.global_position, 2.5, COL_SAP, 0.7)
	var t := get_tree().create_timer(0.7, false)
	t.timeout.connect(func():
		if is_defeated or gen != encounter_generation: return
		_deal_area_damage(player.global_position, 2.5, int(base_atk * 1.1))
		if player.global_position.distance_to(player.global_position) < 2.5:
			if player.has_method("stun"): player.call("stun", 1.8))

func _attack_thorn_hurricane() -> void:
	_shake_camera(0.45)
	var gen := encounter_generation
	for i in 12:
		var ang := TAU * float(i) / 12.0
		var delay := float(i) * 0.12
		var pos := global_position + Vector3(cos(ang) * 4.5, 0, sin(ang) * 4.5)
		var t := get_tree().create_timer(delay, false)
		t.timeout.connect(func():
			if is_defeated or gen != encounter_generation: return
			CombatFx.spawn_burst(self, pos + Vector3(0, 0.8, 0), COL_SAP, 10, 5.5, 0.38, 0.14)
			_deal_area_damage(pos, 2.2, int(base_atk * 1.0)))

func _attack_grove_call() -> void:
	for h in _summoned_pack:
		if is_instance_valid(h): h.queue_free()
	_summoned_pack.clear()
	var scene_path := "res://scenes/entities/hushling.tscn"
	if not ResourceLoader.exists(scene_path): return
	var scn : PackedScene = load(scene_path)
	for i in 3:
		var h := scn.instantiate()
		if get_parent(): get_parent().add_child(h)
		var ang := TAU * float(i) / 3.0
		h.global_position = global_position + Vector3(cos(ang)*5.0, 0, sin(ang)*5.0)
		_summoned_pack.append(h)
		CombatFx.spawn_spawn_portal(self, h.global_position, COL_MOSS)

func _attack_sap_snare(player: Node3D) -> void:
	CombatFx.spawn_ring(self, player.global_position, 3.5, Color(0.68, 0.52, 0.12, 0.7), 0.65)
	if player.has_method("apply_move_slow"):
		player.call("apply_move_slow", 0.40, 5.0)
	_deal_area_damage(player.global_position, 3.5, int(base_atk * 0.7))

func _attack_heartwood_pulse() -> void:
	_shake_camera(0.70)
	CombatFx.spawn_shockwave(self, global_position, 7.5, COL_SAP, 0.55)
	CombatFx.spawn_burst(self, global_position + Vector3(0, 1.5, 0), COL_AMBER_EYE, 28, 9.0, 0.55, 0.20)
	_deal_area_damage(global_position, 7.5, int(base_atk * 2.0))
	if _heartwood_mat != null:
		var tw := create_tween()
		tw.tween_property(_heartwood_mat, "emission_energy_multiplier", 16.0, 0.12)
		tw.tween_property(_heartwood_mat, "emission_energy_multiplier", 5.5, 0.55)

func _attack_boulder_roll(player: Node3D) -> void:
	var gen := encounter_generation
	for i in 4:
		var ang := randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		var start := global_position + dir * -2.0
		CombatFx.spawn_ground_telegraph(self, start, 3.5, Color(0.35, 0.22, 0.14), 0.8)
		var t := get_tree().create_timer(0.8 + float(i) * 0.3, false)
		t.timeout.connect(func():
			if is_defeated or gen != encounter_generation: return
			for step in 5:
				var pos := start + dir * step * 2.5
				var t2 := get_tree().create_timer(float(step) * 0.12, false)
				t2.timeout.connect(func():
					CombatFx.spawn_burst(self, pos + Vector3(0, 0.5, 0), COL_BARK, 8, 4.5, 0.3, 0.14)
					_deal_area_damage(pos, 2.5, int(base_atk * 1.3))))

func _attack_thorn_eruption(_player: Node3D) -> void:
	_shake_camera(0.80)
	var gen := encounter_generation
	for i in 24:
		var ang := TAU * float(i) / 24.0
		var r   := randf_range(2.0, arena_radius * 0.75)
		var pos := global_position + Vector3(cos(ang)*r, 0, sin(ang)*r)
		var dl  := randf_range(0.0, 1.5)
		CombatFx.spawn_ground_telegraph(self, pos, 2.0, COL_SAP, dl + 0.5)
		var t := get_tree().create_timer(dl + 0.5, false)
		t.timeout.connect(func():
			if is_defeated or gen != encounter_generation: return
			CombatFx.spawn_burst(self, pos + Vector3(0, 1.0, 0), COL_SAP, 12, 6.0, 0.42, 0.15)
			_deal_area_damage(pos, 2.0, int(base_atk * 1.1)))

func _process(delta: float) -> void:
	super._process(delta)
	if is_defeated: return
	var t := Time.get_ticks_msec() * 0.003
	var pulse := 1.0 + sin(t * 1.6) * 0.5
	for smat in _sap_mats:
		if is_instance_valid(smat):
			smat.emission_energy_multiplier = pulse * (1.2 + float(int(current_phase)) * 0.4)
	for emat in _eye_mats:
		if is_instance_valid(emat):
			emat.emission_energy_multiplier = 3.0 + sin(t * 3.5) * 1.2
	if _antler_root != null:
		_antler_root.rotation.y = sin(t * 0.4) * 0.06

func _spawn_rewards() -> void:
	if is_practice: return
	var rm := get_node_or_null("/root/RewardManager")
	if rm != null:
		rm.call("grant_boss_kill", "bramblewood_thornwarden", was_first_kill, "bramblewood")
