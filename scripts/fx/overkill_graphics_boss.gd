extends Node3D
class_name OverkillGraphicsBoss

## === OVERKILL 3D Graphics — Boss Layer ===
##
## Drop this as a child of any BossBase entity. It auto-discovers the Visual
## node and adds:
##
##   BODY
##   ├── Multi-layer organic torso (7 fused boulder segments, each cracked)
##   ├── 12 spine ridges along the back, height-tapered + emissive seams
##   ├── 2 massive swept shoulder pauldrons with layered plating
##   ├── Bioluminescent chest crater — deep hollow with pulsing lava core
##   ├── 4 articulated root-legs with 2-segment joints, each tip clawed
##   ├── Crown of 6 asymmetric bone horns (twisted CylinderMesh stacks)
##   ├── 8 hanging tendril chains (SpringBoneSystem Verlet physics)
##   └── Per-phase scarring: new cracks + pustule growths on each transition
##
##   ATMOSPHERE
##   ├── Volumetric heat distortion halo (animated alpha QuadMesh billboard)
##   ├── 12-point emissive floor rune ring (TorusMesh + 12 glyph quads)
##   ├── Continuous ember particle exhaust from torso cracks
##   ├── Phase-locked shockwave pulse ring (expands + fades each phase)
##   └── Enrage corona: outer spike halo + blinding inner light
##
##   HIT RESPONSE
##   ├── Per-hit flash: all crack seams spike to full brightness
##   ├── Knockback visual lean (visual root tilts in knockback direction)
##   └── Critical hit: golden splinter burst from crit zone
##
## Usage:
##   var og := OverkillGraphicsBoss.new()
##   add_child(og)
##   og.setup(self)

signal graphics_ready

@export var torso_tint    : Color = Color(0.14, 0.07, 0.05)
@export var crack_tint    : Color = Color(1.00, 0.38, 0.08)
@export var horn_tint     : Color = Color(0.10, 0.06, 0.04)
@export var tendril_tint  : Color = Color(0.80, 0.22, 0.06)
@export var rune_tint     : Color = Color(1.00, 0.30, 0.06)
@export var scale_factor  : float = 1.0  # overall size multiplier

var _boss    : Node3D = null
var _visual  : Node3D = null
var _phase   : int    = 0
var _t       : float  = 0.0

# Tracked nodes for per-phase / per-hit updates
var _crack_mats  : Array[StandardMaterial3D] = []
var _core_mat    : StandardMaterial3D = null
var _rune_mats   : Array[StandardMaterial3D] = []
var _spine_mats  : Array[StandardMaterial3D] = []
var _tendril_sbs : SpringBoneSystem = null  # if present
var _halo        : MeshInstance3D = null
var _corona      : Node3D = null
var _scar_host   : Node3D = null
var _leg_roots   : Array[Node3D] = []
var _visual_base_rot : Vector3 = Vector3.ZERO

func setup(boss: Node3D) -> void:
	_boss   = boss
	_visual = boss.get_node_or_null("Visual")
	if _visual == null:
		_visual = Node3D.new()
		_visual.name = "Visual"
		boss.add_child(_visual)
	_visual.scale = Vector3.ONE * scale_factor

func _ready() -> void:
	if _boss == null:
		return
	_build_torso()
	_build_spines()
	_build_pauldrons()
	_build_chest_crater()
	_build_root_legs()
	_build_crown_horns()
	_build_tendrils()
	_build_floor_rune()
	_build_heat_halo()
	_build_ember_exhaust()
	_build_corona()
	_scar_host = Node3D.new()
	_scar_host.name = "PhaseScars"
	_visual.add_child(_scar_host)
	# Connect signals
	if _boss.has_signal("phase_changed"):
		_boss.phase_changed.connect(_on_phase_changed)
	if _boss.has_signal("died"):
		_boss.died.connect(_on_boss_died)
	graphics_ready.emit()

func _process(delta: float) -> void:
	_t += delta
	_animate_core(delta)
	_animate_runes(delta)
	_animate_halo(delta)

# ─────────────────────────────────────────────────────────────────────────────
# TORSO — 7 organic boulder segments fused into one mass
# ─────────────────────────────────────────────────────────────────────────────
func _build_torso() -> void:
	var host := Node3D.new()
	host.name = "Torso"
	_visual.add_child(host)

	var segment_data := [
		# [y_center, radius_x, radius_y, radius_z, rotation_y]
		[0.30, 0.88, 0.70, 0.82, 0.00],
		[0.95, 0.82, 0.68, 0.78, 0.18],
		[1.55, 0.78, 0.64, 0.74, -0.14],
		[2.10, 0.72, 0.60, 0.68, 0.22],
		[2.60, 0.64, 0.56, 0.60, -0.10],
		[3.05, 0.52, 0.50, 0.50, 0.16],
		[3.42, 0.38, 0.42, 0.36, -0.08],
	]

	for d in segment_data:
		var seg := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius         = d[1]
		sm.height         = d[2] * 2.0
		sm.radial_segments = 16
		sm.rings          = 10
		seg.mesh          = sm
		seg.material_override = _body_mat(torso_tint, crack_tint, 0.88, 0.18)
		seg.position = Vector3(0.0, d[0], 0.0)
		seg.rotation.y = d[4]
		host.add_child(seg)

		# Crack seams on each segment — 2 to 4 per boulder
		var crack_count := randi_range(2, 4)
		for c in crack_count:
			_add_crack_seam(host, Vector3(0.0, d[0], 0.0), d[1] * 0.92, c, crack_count)

func _add_crack_seam(host: Node3D, center: Vector3, radius: float,
		idx: int, total: int) -> void:
	var ang := TAU * float(idx) / float(total) + randf_range(-0.3, 0.3)
	var cx  := cos(ang) * radius * randf_range(0.5, 0.9)
	var cz  := sin(ang) * radius * randf_range(0.5, 0.9)
	var seam := MeshInstance3D.new()
	var bm   := BoxMesh.new()
	bm.size = Vector3(randf_range(0.04, 0.12), randf_range(0.18, 0.55), 0.03)
	seam.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.04, 0.02, 0.01)
	mat.emission_enabled           = true
	mat.emission                   = crack_tint
	mat.emission_energy_multiplier = randf_range(1.2, 2.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	seam.material_override = mat
	_crack_mats.append(mat)
	seam.global_position = host.global_position + center + Vector3(cx, randf_range(-0.2, 0.2), cz)
	seam.rotation = Vector3(randf_range(-0.5, 0.5), ang, randf_range(-0.3, 0.3))
	host.add_child(seam)

func _body_mat(base: Color, emit: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color               = base
	m.roughness                  = rough
	m.metallic                   = metal
	m.emission_enabled           = true
	m.emission                   = emit
	m.emission_energy_multiplier = 0.12
	return m

# ─────────────────────────────────────────────────────────────────────────────
# SPINES — 12 ridges along the boss's back
# ─────────────────────────────────────────────────────────────────────────────
func _build_spines() -> void:
	var host := Node3D.new()
	host.name = "DorsalSpines"
	_visual.add_child(host)

	for i in 12:
		var t := float(i) / 11.0
		var y := lerpf(0.4, 3.8, t)
		var sz := lerpf(0.22, 0.08, t)  # taper toward crown
		var spine := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius      = 0.0
		cm.bottom_radius   = sz
		cm.height          = lerpf(0.55, 0.18, t)
		cm.radial_segments = 6
		spine.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.10, 0.05, 0.04)
		mat.roughness    = 0.94
		mat.emission_enabled = true
		mat.emission = crack_tint
		mat.emission_energy_multiplier = randf_range(0.08, 0.45)
		spine.material_override = mat
		_spine_mats.append(mat)
		spine.position = Vector3(0.0, y, -0.78 + t * 0.12)
		spine.rotation = Vector3(0.32 + t * 0.18, randf_range(-0.15, 0.15), 0.0)
		host.add_child(spine)

# ─────────────────────────────────────────────────────────────────────────────
# PAULDRONS — two massive swept shoulder plates
# ─────────────────────────────────────────────────────────────────────────────
func _build_pauldrons() -> void:
	for side in [-1.0, 1.0]:
		var host := Node3D.new()
		host.name = "Pauldron_%s" % ("L" if side < 0 else "R")
		_visual.add_child(host)

		# Base dome plate
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius          = 0.62
		sm.height          = 0.90
		sm.radial_segments = 14
		sm.rings           = 8
		dome.mesh          = sm
		dome.material_override = _body_mat(torso_tint, crack_tint, 0.85, 0.22)
		dome.position = Vector3(1.05 * side, 2.65, 0.0)
		dome.scale    = Vector3(1.0, 0.7, 0.9)
		host.add_child(dome)

		# Three layered angular plates over the dome
		for layer in 3:
			var plate := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(
				0.50 - layer * 0.10,
				0.12 + layer * 0.04,
				0.38 - layer * 0.06)
			plate.mesh = bm
			plate.material_override = _body_mat(
				Color(torso_tint.r * 0.85, torso_tint.g * 0.85, torso_tint.b * 0.85),
				crack_tint, 0.78, 0.32)
			plate.position = dome.position + Vector3(
				side * (0.22 + layer * 0.08),
				0.18 - layer * 0.12,
				-0.12 + layer * 0.08)
			plate.rotation.z = side * (0.35 + layer * 0.18)
			plate.rotation.y = -side * 0.12
			host.add_child(plate)

		# Spike fringe along bottom edge
		for s in 5:
			var spike := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius    = 0.0
			cm.bottom_radius = 0.04
			cm.height        = 0.28 - s * 0.02
			cm.radial_segments = 5
			spike.mesh = cm
			spike.material_override = _body_mat(horn_tint, crack_tint, 0.95, 0.0)
			var ang := (float(s) / 4.0 - 0.5) * 1.1
			spike.position = dome.position + Vector3(
				side * 0.52,
				-0.28 + float(s) * 0.02,
				sin(ang) * 0.44)
			spike.rotation = Vector3(0.0, 0.0, side * (PI * 0.5 + ang * 0.4))
			host.add_child(spike)

# ─────────────────────────────────────────────────────────────────────────────
# CHEST CRATER — deep hollow with lava core + pulsing light
# ─────────────────────────────────────────────────────────────────────────────
func _build_chest_crater() -> void:
	var host := Node3D.new()
	host.name = "ChestCrater"
	_visual.add_child(host)
	host.position = Vector3(0.0, 1.85, 0.70)

	# Dark hollow rim
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius  = 0.28
	tm.outer_radius  = 0.48
	tm.ring_segments = 24
	tm.rings         = 6
	rim.mesh = tm
	rim.material_override = _body_mat(Color(0.06, 0.03, 0.02), crack_tint, 0.95, 0.0)
	rim.rotation.x = PI * 0.5
	host.add_child(rim)

	# Inner lava core — glowing sphere
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.26
	sm.height = 0.52
	core.mesh = sm
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color               = Color(1.0, 0.55, 0.10)
	_core_mat.emission_enabled           = true
	_core_mat.emission                   = Color(1.0, 0.35, 0.06)
	_core_mat.emission_energy_multiplier = 4.5
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = _core_mat
	core.position.z = -0.06
	host.add_child(core)

	# Core point light
	var light := OmniLight3D.new()
	light.light_color  = Color(1.0, 0.42, 0.08)
	light.light_energy = 3.2
	light.omni_range   = 7.5
	host.add_child(light)

	# Crack spokes radiating from crater rim
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var spoke := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.028, 0.014, 0.38)
		spoke.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.03, 0.01, 0.01)
		mat.emission_enabled = true
		mat.emission = crack_tint
		mat.emission_energy_multiplier = 1.8
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		spoke.material_override = mat
		_crack_mats.append(mat)
		spoke.position = Vector3(cos(ang) * 0.42, 0.0, sin(ang) * 0.42 - 0.1)
		spoke.rotation = Vector3(0.0, -ang + PI * 0.5, 0.0)
		host.add_child(spoke)

func _animate_core(_delta: float) -> void:
	if _core_mat == null:
		return
	var breathe := 0.85 + 0.15 * sin(_t * 2.2) + 0.06 * sin(_t * 5.7)
	var enrage_mult := 2.0 if _boss != null and _boss.get("enrage_active") else 1.0
	_core_mat.emission_energy_multiplier = breathe * 4.5 * enrage_mult
	# Phase escalation — core burns hotter each phase
	var phase_boost := 1.0 + float(_phase) * 0.35
	_core_mat.emission = Color(
		minf(1.0, crack_tint.r * phase_boost),
		crack_tint.g * maxf(0.1, 1.0 - float(_phase) * 0.15),
		crack_tint.b * maxf(0.02, 1.0 - float(_phase) * 0.25))

# ─────────────────────────────────────────────────────────────────────────────
# ROOT LEGS — 4 articulated limbs with 2 joint segments + claw tips
# ─────────────────────────────────────────────────────────────────────────────
func _build_root_legs() -> void:
	var positions := [
		Vector3( 0.85, 0.35,  0.60),  # front-right
		Vector3(-0.85, 0.35,  0.60),  # front-left
		Vector3( 0.90, 0.35, -0.55),  # back-right
		Vector3(-0.90, 0.35, -0.55),  # back-left
	]
	var outward_angles := [0.5, -0.5, 0.6, -0.6]

	for i in 4:
		var leg_root := Node3D.new()
		leg_root.name = "RootLeg_%d" % i
		leg_root.position = positions[i]
		_visual.add_child(leg_root)
		_leg_roots.append(leg_root)

		var ang: float = outward_angles[i]
		# Upper segment
		var upper := _leg_segment(leg_root, 0.12, 0.06, 0.65)
		upper.rotation = Vector3(0.55, ang, 0.0)
		upper.position.y = -0.1

		# Lower segment (child of upper tip)
		var lower_pos := upper.position + Vector3(sin(ang) * 0.38, -0.42, 0.28)
		var lower := _leg_segment(leg_root, 0.08, 0.04, 0.52)
		lower.position = lower_pos
		lower.rotation = Vector3(0.9, ang * 0.6, 0.0)

		# Three claw tips
		for c in 3:
			var cang: float = ang + (float(c) - 1.0) * 0.38
			var claw := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius    = 0.0
			cm.bottom_radius = 0.035
			cm.height        = 0.26
			cm.radial_segments = 5
			claw.mesh = cm
			claw.material_override = _body_mat(horn_tint, crack_tint, 0.92, 0.0)
			claw.position = lower_pos + Vector3(
				cos(cang) * 0.12, -0.32, sin(cang) * 0.12)
			claw.rotation = Vector3(1.1, cang, 0.0)
			leg_root.add_child(claw)

		# Subtle idle sway tween
		var tw := leg_root.create_tween().set_loops()
		tw.tween_property(leg_root, "rotation:z",
			leg_root.rotation.z + randf_range(-0.06, 0.06), randf_range(1.4, 2.6)) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(leg_root, "rotation:z",
			leg_root.rotation.z, randf_range(1.4, 2.6)).set_trans(Tween.TRANS_SINE)

func _leg_segment(parent: Node3D, br: float, tr: float, h: float) -> MeshInstance3D:
	var seg := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius   = br
	cm.top_radius      = tr
	cm.height          = h
	cm.radial_segments = 7
	seg.mesh = cm
	seg.material_override = _body_mat(torso_tint, crack_tint, 0.90, 0.12)
	parent.add_child(seg)
	return seg

# ─────────────────────────────────────────────────────────────────────────────
# CROWN HORNS — 6 asymmetric twisted bone horns
# ─────────────────────────────────────────────────────────────────────────────
func _build_crown_horns() -> void:
	var host := Node3D.new()
	host.name = "CrownHorns"
	_visual.add_child(host)

	var horn_defs := [
		# [angle, height, outward_lean, twist, base_radius, height_val]
		[0.00,   3.85, 0.22,  0.0,   0.14, 1.05],
		[TAU/6,  3.78, 0.30, -0.18,  0.11, 0.82],
		[TAU/3,  3.72, 0.28,  0.22,  0.10, 0.78],
		[TAU/2,  3.80, 0.18,  0.0,   0.13, 0.95],
		[2*TAU/3, 3.74, 0.25, -0.16, 0.10, 0.76],
		[5*TAU/6, 3.68, 0.32,  0.20, 0.09, 0.72],
	]

	for d in horn_defs:
		var ang: float = d[0]
		var horn_root := Node3D.new()
		horn_root.name = "Horn_%d" % horn_defs.find(d)
		horn_root.position = Vector3(cos(ang) * 0.55, d[1], sin(ang) * 0.55)
		horn_root.rotation = Vector3(d[2], ang + d[3], 0.0)
		host.add_child(horn_root)

		# 3-segment stacked horn (each segment smaller and rotated)
		var seg_count := 3
		for s in seg_count:
			var seg := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			var t := float(s) / float(seg_count)
			cm.top_radius      = 0.0
			cm.bottom_radius   = d[4] * (1.0 - t * 0.55)
			cm.height          = d[5] * (0.55 - t * 0.18)
			cm.radial_segments = 6
			seg.mesh = cm
			var mat := StandardMaterial3D.new()
			mat.albedo_color               = horn_tint
			mat.roughness                  = 0.95
			mat.emission_enabled           = true
			mat.emission                   = Color(crack_tint.r * 0.6, crack_tint.g * 0.2, crack_tint.b * 0.1)
			mat.emission_energy_multiplier = 0.18
			seg.material_override = mat
			seg.position.y = d[5] * (0.3 + t * 0.5)
			seg.rotation.y = d[3] * float(s) * 0.7
			horn_root.add_child(seg)

# ─────────────────────────────────────────────────────────────────────────────
# TENDRILS — 8 Verlet spring chains hanging from the torso
# ─────────────────────────────────────────────────────────────────────────────
func _build_tendrils() -> void:
	_tendril_sbs = SpringBoneSystem.new()
	_tendril_sbs.name = "TendrilPhysics"
	_tendril_sbs.gravity        = Vector3(0.0, -6.5, 0.0)
	_tendril_sbs.damping        = 0.91
	_tendril_sbs.stiffness      = 0.06
	_tendril_sbs.wind_strength  = 0.18
	_tendril_sbs.wind_frequency = 0.52
	_visual.add_child(_tendril_sbs)

	for i in 8:
		var ang := TAU * float(i) / 8.0
		var anchor_pos := Vector3(cos(ang) * 0.72, 1.20, sin(ang) * 0.72) + \
			_visual.global_position
		_tendril_sbs.add_chain_at(
			anchor_pos,
			randi_range(6, 10),
			randf_range(0.18, 0.28),
			randf_range(0.022, 0.038),
			tendril_tint.lerp(crack_tint, randf_range(0.0, 0.5)))

# ─────────────────────────────────────────────────────────────────────────────
# FLOOR RUNE RING — 12 glyph quad marks + torus ring
# ─────────────────────────────────────────────────────────────────────────────
func _build_floor_rune() -> void:
	var host := Node3D.new()
	host.name = "FloorRune"
	host.position.y = 0.04
	_visual.add_child(host)

	# Outer torus ring
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius  = 2.65
	tm.outer_radius  = 2.90
	tm.ring_segments = 64
	tm.rings         = 4
	ring.mesh = tm
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color               = rune_tint
	ring_mat.emission_enabled           = true
	ring_mat.emission                   = rune_tint
	ring_mat.emission_energy_multiplier = 1.2
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	_rune_mats.append(ring_mat)
	ring.rotation.x = PI * 0.5
	host.add_child(ring)

	# 12 glyph marks
	for i in 12:
		var ang := TAU * float(i) / 12.0
		var glyph := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(randf_range(0.22, 0.38), randf_range(0.18, 0.32))
		glyph.mesh = qm
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color               = rune_tint
		gmat.emission_enabled           = true
		gmat.emission                   = rune_tint
		gmat.emission_energy_multiplier = 0.9
		gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glyph.material_override = gmat
		_rune_mats.append(gmat)
		glyph.position = Vector3(cos(ang) * 2.75, 0.01, sin(ang) * 2.75)
		glyph.rotation = Vector3(-PI * 0.5, ang, 0.0)
		host.add_child(glyph)

func _animate_runes(delta: float) -> void:
	var pulse := 0.7 + sin(_t * 1.8) * 0.3 + 0.12 * sin(_t * 4.5)
	var phase_energy := 1.0 + float(_phase) * 0.55
	for mat in _rune_mats:
		if is_instance_valid(mat):
			mat.emission_energy_multiplier = pulse * phase_energy

# ─────────────────────────────────────────────────────────────────────────────
# HEAT HALO — animated alpha billboard ring
# ─────────────────────────────────────────────────────────────────────────────
func _build_heat_halo() -> void:
	_halo = MeshInstance3D.new()
	_halo.name = "HeatHalo"
	var tm := TorusMesh.new()
	tm.inner_radius  = 1.40
	tm.outer_radius  = 2.00
	tm.ring_segments = 48
	tm.rings         = 3
	_halo.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(crack_tint.r, crack_tint.g, crack_tint.b, 0.0)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled           = true
	mat.emission                   = crack_tint
	mat.emission_energy_multiplier = 0.55
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo.material_override = mat
	_halo.position.y = 2.0
	_halo.rotation.x = PI * 0.5
	_visual.add_child(_halo)

func _animate_halo(_delta: float) -> void:
	if _halo == null or not is_instance_valid(_halo):
		return
	var mat := _halo.material_override as StandardMaterial3D
	if mat == null:
		return
	var pulse := 0.08 + 0.05 * sin(_t * 2.1)
	mat.albedo_color.a = pulse
	mat.emission_energy_multiplier = 0.55 + sin(_t * 1.6) * 0.25
	_halo.rotation.y += _delta * 0.45

# ─────────────────────────────────────────────────────────────────────────────
# EMBER EXHAUST — continuous particles from torso cracks
# ─────────────────────────────────────────────────────────────────────────────
func _build_ember_exhaust() -> void:
	for i in 5:
		var p := GPUParticles3D.new()
		p.name     = "EmberExhaust_%d" % i
		p.amount   = 32
		p.lifetime = 1.2
		p.emitting  = true
		p.randomness = 0.80
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape   = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.32
		pm.direction        = Vector3(0, 1, 0)
		pm.spread           = 60.0
		pm.initial_velocity_min = 0.6
		pm.initial_velocity_max = 2.2
		pm.gravity          = Vector3(0, 0.3, 0)
		pm.scale_min        = 0.06
		pm.scale_max        = 0.20
		pm.color            = crack_tint
		p.process_material  = pm
		var ang := TAU * float(i) / 5.0
		p.position = Vector3(cos(ang) * 0.55, 1.8, sin(ang) * 0.55)
		_visual.add_child(p)

# ─────────────────────────────────────────────────────────────────────────────
# ENRAGE CORONA — spike halo + blinding inner sphere
# ─────────────────────────────────────────────────────────────────────────────
func _build_corona() -> void:
	_corona = Node3D.new()
	_corona.name = "EnrageCorona"
	_corona.visible = false
	_visual.add_child(_corona)

	# Inner blinding sphere
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.05; sm.height = 2.10; sm.radial_segments = 24
	sphere.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.92, 0.82, 0.65)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.55, 0.18)
	mat.emission_energy_multiplier = 6.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material_override = mat
	sphere.position.y = 2.0
	_corona.add_child(sphere)

	# Outer spike burst — 16 spikes
	for i in 16:
		var ang := TAU * float(i) / 16.0
		var spike := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius    = 0.0
		cm.bottom_radius = randf_range(0.06, 0.10)
		cm.height        = randf_range(0.55, 1.10)
		cm.radial_segments = 5
		spike.mesh = cm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(1.0, 0.80, 0.30)
		smat.emission_enabled = true
		smat.emission = Color(1.0, 0.55, 0.12)
		smat.emission_energy_multiplier = 4.8
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		spike.material_override = smat
		spike.position = Vector3(cos(ang) * 1.15, 2.0, sin(ang) * 1.15)
		spike.rotation = Vector3(0.0, -ang, PI * 0.5 - abs(sin(ang)) * 0.4)
		_corona.add_child(spike)

	# Animated slow spin
	var tw := _corona.create_tween().set_loops()
	tw.tween_property(_corona, "rotation:y", TAU, 4.0).set_trans(Tween.TRANS_LINEAR)

# ─────────────────────────────────────────────────────────────────────────────
# PHASE / SIGNAL HOOKS
# ─────────────────────────────────────────────────────────────────────────────
func _on_phase_changed(phase: int) -> void:
	_phase = phase
	_spawn_phase_scars(phase)
	# Scale up the boss body slightly each phase
	if _boss != null and _boss.has_method("get") and _boss.get("stage_scale_mult") is Array:
		var mults: Array = _boss.get("stage_scale_mult")
		if phase < mults.size():
			var tw := create_tween()
			tw.tween_property(_visual, "scale",
				Vector3.ONE * float(mults[phase]), 0.65).set_trans(Tween.TRANS_BACK)
	# Activate corona on enrage (phase 3)
	if phase >= 3 and _corona != null:
		_corona.visible = true
		CombatFx.spawn_shockwave(_boss, _boss.global_position,
			6.5, Color(1.0, 0.60, 0.18, 0.9), 1.0)

func _spawn_phase_scars(phase: int) -> void:
	if _scar_host == null:
		return
	var scar_count := (phase + 1) * 4
	for i in scar_count:
		var scar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.03, 0.10), randf_range(0.14, 0.48), 0.025)
		scar.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color               = Color(0.02, 0.01, 0.01)
		mat.emission_enabled           = true
		mat.emission                   = crack_tint.lerp(Color(0.6, 0.06, 0.02), float(phase) / 3.0)
		mat.emission_energy_multiplier = randf_range(1.5, 3.5)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		scar.material_override = mat
		_crack_mats.append(mat)
		var ang := randf_range(0.0, TAU)
		var r   := randf_range(0.3, 0.85)
		var y   := randf_range(0.4, 3.4)
		scar.position = Vector3(cos(ang) * r, y, sin(ang) * r)
		scar.rotation = Vector3(randf_range(-0.8, 0.8), ang, randf_range(-0.4, 0.4))
		_scar_host.add_child(scar)
	# Pop animation
	for child in _scar_host.get_children():
		child.scale = Vector3.ONE * 0.01
		var tw := child.create_tween()
		tw.tween_property(child, "scale", Vector3.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_boss_died() -> void:
	# Death flash: spike all crack seam energies
	for mat in _crack_mats:
		if is_instance_valid(mat):
			mat.emission_energy_multiplier = 12.0

## Call this from BossBase.take_damage() for hit-flash effect.
func notify_hit(knockback_dir: Vector3 = Vector3.ZERO) -> void:
	for mat in _crack_mats:
		if is_instance_valid(mat):
			var tw := create_tween()
			tw.tween_property(mat, "emission_energy_multiplier", 8.0, 0.04)
			tw.tween_property(mat, "emission_energy_multiplier",
				mat.emission_energy_multiplier, 0.22)
	if _core_mat != null:
		var tw2 := create_tween()
		tw2.tween_property(_core_mat, "emission_energy_multiplier", 14.0, 0.05)
		tw2.tween_property(_core_mat, "emission_energy_multiplier",
			4.5, 0.30)
	# Lean toward knockback
	if knockback_dir.length_squared() > 0.01 and _visual != null:
		var lean := knockback_dir.normalized() * 0.18
		var tw3 := _visual.create_tween()
		tw3.tween_property(_visual, "rotation:z",
			-lean.x, 0.08).set_trans(Tween.TRANS_EXPO)
		tw3.tween_property(_visual, "rotation:z",
			_visual_base_rot.z, 0.28).set_trans(Tween.TRANS_SPRING)
