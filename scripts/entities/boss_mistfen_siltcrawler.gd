extends BossBase
class_name MistfenSiltCrawler

## === Mistfen Silt Crawler ===
## Realm: Mistfen Hollows
## Element: Ice / Water
## Visual identity: massive low-slung crustacean — flat carapace,
##   six articulated clawed legs, twin scorpion tail pincers,
##   iridescent chitin plates with bioluminescent vein cracks,
##   bulbous eye stalks that glow cyan on aggro.
##
## Combat mechanics:
##   Phase 1 — Burrow + slam (submerges, erupts under player), claw swipe, fen mist slow
##   Phase 2 — Dual-pincer whip, cold snap (freeze ground), ice shard volley
##   Phase 3 — Tidal surge (expanding ring waves), mud prison trap
##   Enrage  — Continuous burrowing, all attacks +50% speed, arena floods

# ─── Model ───────────────────────────────────────────────────────────────────

const COL_CHITIN   := Color(0.12, 0.22, 0.30)    # dark teal shell
const COL_VEIN     := Color(0.28, 0.82, 0.94)    # bioluminescent cyan
const COL_UNDERBEL := Color(0.22, 0.30, 0.38)    # soft pale underbelly
const COL_CLAW     := Color(0.08, 0.16, 0.24)    # deep blue-black claw
const COL_EYE      := Color(0.42, 0.92, 1.00)    # bright ice eye glow

var _eye_mats  : Array[StandardMaterial3D] = []
var _vein_mats : Array[StandardMaterial3D] = []
var _leg_roots : Array[Node3D] = []
var _tail_root : Node3D = null
var _carapace  : MeshInstance3D = null
var _submerged : bool = false
var _ice_field_active : bool = false

func _ready() -> void:
	authored_model_profile = "boss_siltcrawler"
	max_hp    = 950
	hp        = max_hp
	base_atk  = 18
	move_speed = 3.2
	arena_radius = 22.0
	diamond_reward = 6
	stage_tints = [
		Color(0.28, 0.82, 0.94),
		Color(0.20, 0.65, 0.88),
		Color(0.12, 0.45, 0.78),
		Color(0.06, 0.22, 0.60),
	]
	stage_armor = [0, 4, 7, 10]
	mend_max_uses = 1
	super._ready()
	_setup_attacks()
	_build_siltcrawler_model()
	_build_overkill_graphics()

func _setup_attacks() -> void:
	super._setup_attacks()
	attack_cooldowns = {
		"basic": 0.0,
		"burrow": 0.0,
		"claw_whip": 0.0,
		"cold_snap": 0.0,
		"shard_volley": 0.0,
		"tidal_surge": 0.0,
		"mud_prison": 0.0,
	}

# ─── Model Build ─────────────────────────────────────────────────────────────

func _build_siltcrawler_model() -> void:
	var visual := get_node_or_null("Visual")
	if visual == null:
		visual = Node3D.new(); visual.name = "Visual"; add_child(visual)

	# ── Carapace (main flat shell) ──────────────────────────────────────────
	var cara_mat := _chitin_mat(COL_CHITIN, COL_VEIN)
	_carapace = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 1.45; cm.height = 0.95; cm.radial_segments = 14
	_carapace.mesh = cm
	_carapace.material_override = cara_mat
	_carapace.scale = Vector3(1.0, 0.38, 1.22)   # flat & wide
	_carapace.position.y = 0.58
	visual.add_child(_carapace)

	# Chitin plate overlays (5 hexagonal-ish segments across top)
	for i in 5:
		var plate := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius    = 0.35 - i * 0.04
		pm.bottom_radius = 0.40 - i * 0.04
		pm.height        = 0.12
		pm.radial_segments = 6
		plate.mesh = pm
		plate.material_override = _chitin_mat(COL_CHITIN.lerp(COL_UNDERBEL, float(i) * 0.12), COL_VEIN)
		plate.position = Vector3((i - 2.0) * 0.42, 0.82, 0.0)
		plate.rotation.y = i * 0.22
		visual.add_child(plate)

	# Bioluminescent vein cracks (6 strips)
	for i in 6:
		var vein := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.08, 0.55 + float(i) * 0.08)
		vein.mesh = bm
		var vmat := StandardMaterial3D.new()
		vmat.albedo_color = COL_VEIN
		vmat.emission_enabled = true
		vmat.emission = COL_VEIN
		vmat.emission_energy_multiplier = 1.8
		vmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		vein.material_override = vmat
		_vein_mats.append(vmat)
		var ang := TAU * float(i) / 6.0
		vein.position = Vector3(cos(ang) * 0.85, 0.76, sin(ang) * 1.05)
		vein.rotation.y = ang
		visual.add_child(vein)

	# ── Eye stalks (2) ──────────────────────────────────────────────────────
	for side in [-1.0, 1.0]:
		var stalk_root := Node3D.new()
		stalk_root.position = Vector3(0.55 * side, 0.88, 0.72)
		visual.add_child(stalk_root)
		# Stalk
		var stalk := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.bottom_radius = 0.065; sm.top_radius = 0.04; sm.height = 0.42; sm.radial_segments = 7
		stalk.mesh = sm
		stalk.material_override = _chitin_mat(COL_CHITIN, COL_VEIN)
		stalk.position.y = 0.21
		stalk_root.add_child(stalk)
		# Bulb
		var bulb := MeshInstance3D.new()
		var bsm := SphereMesh.new()
		bsm.radius = 0.135; bsm.height = 0.26
		bulb.mesh = bsm
		var emat := StandardMaterial3D.new()
		emat.albedo_color = COL_EYE
		emat.emission_enabled = true
		emat.emission = COL_EYE
		emat.emission_energy_multiplier = 4.5
		emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bulb.material_override = emat
		_eye_mats.append(emat)
		bulb.position.y = 0.46
		stalk_root.add_child(bulb)
		# Eye light
		var el := OmniLight3D.new()
		el.light_color = COL_EYE; el.light_energy = 0.85; el.omni_range = 3.5
		el.position.y = 0.46
		stalk_root.add_child(el)

	# ── Six articulated legs ────────────────────────────────────────────────
	var leg_positions := [
		Vector3( 0.95, 0.35,  0.60), Vector3(-0.95, 0.35,  0.60),
		Vector3( 1.05, 0.30,  0.00), Vector3(-1.05, 0.30,  0.00),
		Vector3( 0.90, 0.35, -0.55), Vector3(-0.90, 0.35, -0.55),
	]
	for i in 6:
		var lr := Node3D.new()
		lr.position = leg_positions[i]
		visual.add_child(lr)
		_leg_roots.append(lr)
		var side_sgn := 1.0 if leg_positions[i].x > 0 else -1.0
		_build_crab_leg(lr, side_sgn, float(i))

	# ── Scorpion tails (twin pincers) ──────────────────────────────────────
	_tail_root = Node3D.new()
	_tail_root.name = "TailRoot"
	_tail_root.position = Vector3(0, 0.7, -1.35)
	visual.add_child(_tail_root)
	for side in [-1.0, 1.0]:
		var tail := Node3D.new()
		tail.position = Vector3(0.35 * side, 0, 0)
		_tail_root.add_child(tail)
		# 3-segment tail
		var y := 0.0
		for s in 3:
			var seg := MeshInstance3D.new()
			var tsm := CylinderMesh.new()
			tsm.bottom_radius = 0.10 - s * 0.025
			tsm.top_radius    = 0.085 - s * 0.02
			tsm.height        = 0.38 - s * 0.06
			tsm.radial_segments = 7
			seg.mesh = tsm
			seg.material_override = _chitin_mat(COL_CHITIN, COL_VEIN)
			seg.position.y = y + tsm.height * 0.5
			seg.rotation.z = side * (0.18 + s * 0.28)
			tail.add_child(seg)
			y += tsm.height
		# Pincer tip
		for p in 2:
			var pincer := MeshInstance3D.new()
			var pcm := CylinderMesh.new()
			pcm.top_radius = 0.0; pcm.bottom_radius = 0.055; pcm.height = 0.28; pcm.radial_segments = 5
			pincer.mesh = pcm
			pincer.material_override = _chitin_mat(COL_CLAW, COL_VEIN)
			pincer.position = Vector3(float(p) * 0.08 * side, y + 0.06, 0)
			pincer.rotation = Vector3(-0.35, 0, side * (0.5 + float(p) * 0.4))
			tail.add_child(pincer)

	# ── Underbelly ─────────────────────────────────────────────────────────
	var belly := MeshInstance3D.new()
	var bm2 := CapsuleMesh.new()
	bm2.radius = 1.35; bm2.height = 0.6; bm2.radial_segments = 12
	belly.mesh = bm2
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = COL_UNDERBEL; bmat.roughness = 0.75
	belly.material_override = bmat
	belly.scale = Vector3(1.0, 0.25, 1.15)
	belly.position.y = 0.22
	visual.add_child(belly)

func _build_crab_leg(parent: Node3D, side: float, phase_offset: float) -> void:
	var mat := _chitin_mat(COL_CHITIN, COL_VEIN)
	# Upper arm
	var upper := MeshInstance3D.new()
	var ucm := CylinderMesh.new()
	ucm.bottom_radius = 0.072; ucm.top_radius = 0.045; ucm.height = 0.50; ucm.radial_segments = 6
	upper.mesh = ucm; upper.material_override = mat
	upper.position = Vector3(0, -0.12, 0)
	upper.rotation = Vector3(0.28, 0, side * 0.52)
	parent.add_child(upper)
	# Lower arm
	var lower := MeshInstance3D.new()
	var lcm := CylinderMesh.new()
	lcm.bottom_radius = 0.055; lcm.top_radius = 0.028; lcm.height = 0.45; lcm.radial_segments = 5
	lower.mesh = lcm; lower.material_override = mat
	lower.position = Vector3(side * 0.28, -0.48, 0.22)
	lower.rotation = Vector3(0.65, 0, side * 0.45)
	parent.add_child(lower)
	# Claw tip
	var claw := MeshInstance3D.new()
	var ccm := CylinderMesh.new()
	ccm.top_radius = 0.0; ccm.bottom_radius = 0.035; ccm.height = 0.22; ccm.radial_segments = 5
	claw.mesh = ccm
	claw.material_override = _chitin_mat(COL_CLAW, COL_EYE)
	claw.position = Vector3(side * 0.42, -0.75, 0.38)
	claw.rotation = Vector3(1.0, 0, side * 0.3)
	parent.add_child(claw)
	# Idle leg-wave tween
	var tw := parent.create_tween().set_loops()
	tw.tween_property(parent, "rotation:z",
		parent.rotation.z + side * 0.12, 0.9 + phase_offset * 0.08).set_trans(Tween.TRANS_SINE)
	tw.tween_property(parent, "rotation:z",
		parent.rotation.z - side * 0.06, 0.9 + phase_offset * 0.08).set_trans(Tween.TRANS_SINE)

func _build_overkill_graphics() -> void:
	var og := OverkillGraphicsBoss.new()
	og.name = "OverkillGraphics"
	og.torso_tint   = COL_CHITIN
	og.crack_tint   = COL_VEIN
	og.horn_tint    = COL_CLAW
	og.tendril_tint = COL_VEIN
	og.rune_tint    = COL_EYE
	og.scale_factor = 1.05
	add_child(og)
	og.setup(self)

# ─── Helpers ─────────────────────────────────────────────────────────────────

func _chitin_mat(base: Color, emit: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.roughness    = 0.62
	m.metallic     = 0.25
	m.emission_enabled = true
	m.emission = emit
	m.emission_energy_multiplier = 0.22
	return m

# ─── Phase AI ────────────────────────────────────────────────────────────────

func _on_phase_transition() -> void:
	super._on_phase_transition()
	match current_phase:
		BossPhase.PHASE_2:
			attack_cooldowns["cold_snap"] = 0.0
		BossPhase.PHASE_3:
			attack_cooldowns["tidal_surge"] = 0.0
		BossPhase.ENRAGE:
			enrage_active = true
			# Eyes flash white on enrage
			for emat in _eye_mats:
				if is_instance_valid(emat):
					emat.emission = Color(1.0, 1.0, 1.0)
					emat.emission_energy_multiplier = 9.0

func _try_attacks(player: Node3D, dist: float) -> void:
	if is_action_locked():
		return
	super._try_attacks(player, dist)
	if is_action_locked():
		return

	# Enrage: burrow spam
	if current_phase == BossPhase.ENRAGE \
			and float(attack_cooldowns.get("burrow", 0.0)) <= 0.0:
		lock_action(2.2); _attack_burrow(player)
		attack_cooldowns["burrow"] = 5.0; return

	if current_phase >= BossPhase.PHASE_3 \
			and float(attack_cooldowns.get("tidal_surge", 0.0)) <= 0.0:
		lock_action(1.4); _attack_tidal_surge(player)
		attack_cooldowns["tidal_surge"] = 20.0; return

	if current_phase >= BossPhase.PHASE_3 \
			and float(attack_cooldowns.get("mud_prison", 0.0)) <= 0.0 and dist < 7.0:
		lock_action(1.0); _attack_mud_prison(player)
		attack_cooldowns["mud_prison"] = 16.0; return

	if current_phase >= BossPhase.PHASE_2 \
			and float(attack_cooldowns.get("cold_snap", 0.0)) <= 0.0:
		lock_action(1.2); _attack_cold_snap(player)
		attack_cooldowns["cold_snap"] = 12.0; return

	if current_phase >= BossPhase.PHASE_2 \
			and float(attack_cooldowns.get("shard_volley", 0.0)) <= 0.0:
		lock_action(1.1); _attack_shard_volley(player)
		attack_cooldowns["shard_volley"] = 9.0; return

	if float(attack_cooldowns.get("burrow", 0.0)) <= 0.0 and dist < 10.0:
		lock_action(2.2); _attack_burrow(player)
		attack_cooldowns["burrow"] = 18.0; return

	if float(attack_cooldowns.get("claw_whip", 0.0)) <= 0.0 and dist < 5.5:
		lock_action(0.8); _attack_claw_whip(player)
		attack_cooldowns["claw_whip"] = 4.5

# ─── Attacks ─────────────────────────────────────────────────────────────────

func _attack_burrow(player: Node3D) -> void:
	# Submerge, track player, erupt
	_submerged = true
	if _carapace != null:
		var tw := create_tween()
		tw.tween_property(_carapace.get_parent(), "position:y", -1.5, 0.55).set_trans(Tween.TRANS_EXPO)
	var gen := encounter_generation
	var target := player.global_position
	CombatFx.spawn_burst(self, global_position, COL_VEIN, 16, 4.5, 0.4, 0.16)
	var timer := get_tree().create_timer(1.4, false)
	timer.timeout.connect(func():
		if is_defeated or gen != encounter_generation: return
		global_position = target + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
		_submerged = false
		if _carapace != null:
			var tw2 := create_tween()
			tw2.tween_property(_carapace.get_parent(), "position:y", 0.0, 0.35).set_trans(Tween.TRANS_BACK)
		CombatFx.spawn_burst(self, global_position, COL_VEIN, 28, 7.5, 0.5, 0.20)
		attack_telegraphed.emit("burrow", 3.5, 0.0)
		_deal_area_damage(global_position, 3.5, int(base_atk * 1.8))
		_shake_camera(0.55)
		if player.has_method("apply_move_slow"):
			player.call("apply_move_slow", 0.55, 2.0)

func _attack_cold_snap(player: Node3D) -> void:
	# Flash freeze ground around player — expanding ice rings
	_shake_camera(0.35)
	var gen := encounter_generation
	for ring in 3:
		var radius := 3.5 + ring * 3.0
		var delay  := 0.55 + ring * 0.35
		CombatFx.spawn_ground_telegraph(self, player.global_position, radius,
			COL_VEIN, delay)
		var t := get_tree().create_timer(delay, false)
		t.timeout.connect(func():
			if is_defeated or gen != encounter_generation: return
			CombatFx.spawn_ring(self, player.global_position, radius, COL_EYE, 0.45)
			_deal_area_damage(player.global_position, radius * 0.55, int(base_atk * 0.85))
			if player.global_position.distance_to(player.global_position) <= radius:
				if player.has_method("stun"): player.call("stun", 1.2))

func _attack_shard_volley(player: Node3D) -> void:
	# 5 delayed ice spikes at player position
	var gen := encounter_generation
	for s in 5:
		var ang := (float(s) / 5.0) * TAU
		var target := player.global_position + Vector3(cos(ang) * 1.2, 0, sin(ang) * 1.2)
		var delay  := 0.25 + float(s) * 0.18
		CombatFx.spawn_ground_telegraph(self, target, 1.6, COL_VEIN, delay)
		var t := get_tree().create_timer(delay, false)
		t.timeout.connect(func():
			if is_defeated or gen != encounter_generation: return
			CombatFx.spawn_burst(self, target + Vector3(0, 1.2, 0), COL_EYE, 12, 5.5, 0.35, 0.14)
			_deal_area_damage(target, 1.6, int(base_atk * 1.1))
			if player.has_method("notify_enemy_strike"):
				player.call("notify_enemy_strike", self, int(base_atk * 1.1)))

func _attack_tidal_surge(player: Node3D) -> void:
	_shake_camera(0.55)
	var gen := encounter_generation
	for wave in 4:
		var r  := 4.0 + wave * 5.5
		var dl := 0.6 + wave * 0.45
		CombatFx.spawn_ground_telegraph(self, global_position, r, Color(0.22, 0.60, 0.90), dl)
		var t := get_tree().create_timer(dl, false)
		t.timeout.connect(func():
			if is_defeated or gen != encounter_generation: return
			CombatFx.spawn_ring(self, global_position, r, COL_VEIN, 0.55)
			_deal_area_damage(global_position, r * 0.45, int(base_atk * 1.2)))

func _attack_mud_prison(player: Node3D) -> void:
	var gen := encounter_generation
	var center := player.global_position
	CombatFx.spawn_ground_telegraph(self, center, 3.2, Color(0.28, 0.18, 0.12), 0.85)
	var t := get_tree().create_timer(0.85, false)
	t.timeout.connect(func():
		if is_defeated or gen != encounter_generation: return
		for i in 8:
			var ang := TAU * float(i) / 8.0
			CombatFx.spawn_burst(self, center + Vector3(cos(ang)*2.8, 0.6, sin(ang)*2.8),
				Color(0.35, 0.24, 0.14, 0.9), 8, 3.5, 0.8, 0.18)
		if player.global_position.distance_to(center) <= 3.2 and player.has_method("stun"):
			player.call("stun", 2.8))

func _attack_claw_whip(_player: Node3D) -> void:
	animator.trigger_attack() if animator else null
	_shake_camera(0.22)
	CombatFx.spawn_slash(self, global_position + Vector3(0, 1.0, 0), COL_VEIN)
	_deal_area_damage(global_position, 4.2, base_atk)

# ─── Process ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	super._process(delta)
	if is_defeated: return
	# Vein pulse
	var pulse := 0.9 + sin(Time.get_ticks_msec() * 0.004) * 0.6
	for vmat in _vein_mats:
		if is_instance_valid(vmat):
			vmat.emission_energy_multiplier = pulse * (1.8 + float(int(current_phase)) * 0.5)
	# Eye pulse faster in combat
	var eye_pulse := 3.0 + sin(Time.get_ticks_msec() * 0.008) * 1.5
	for emat in _eye_mats:
		if is_instance_valid(emat):
			emat.emission_energy_multiplier = eye_pulse

func _spawn_rewards() -> void:
	if is_practice: return
	super._spawn_rewards() if super.has_method("_spawn_rewards") else null
	var rm := get_node_or_null("/root/RewardManager")
	if rm != null:
		rm.call("grant_boss_kill", "mistfen_siltcrawler", was_first_kill, "mistfen")
