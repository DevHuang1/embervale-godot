extends Node3D
class_name OverkillGraphicsHushling

## === OVERKILL 3D Graphics — Small Enemy (Hushling) Layer ===
##
## Drop this as a child of any Hushling entity after _ready().
## It reads the `archetype` property to customise the silhouette.
##
## What it adds on top of the base procedural body:
##
##   EVERY ARCHETYPE
##   ├── Subsurface scattering-style body gradient (dark → vivid rim emission)
##   ├── Animated core gem with deep-focus pulsing light + lens flare quad
##   ├── 6 micro-spine ridge clusters along the back (size varies by archetype)
##   ├── 2 articulated claw arms — 3 segments each, final claw tip emissive
##   ├── Jaw / mandible geometry (open/close driven by attack pattern)
##   ├── Eye sockets (deep hollow + floating iris sphere + glow light)
##   ├── 4–6 hanging micro-tendril chains (Verlet physics)
##   └── Continuous micro-ember exhaust from body cracks
##
##   PER-ARCHETYPE SIGNATURE PIECES (bolted on top)
##   ├── charger / thorn_charger : ramming brow plate + gore spurs
##   ├── fenling                  : swept lateral fin array + cold breath particles
##   ├── ember_warden             : shield boss disc + 6 shoulder ember pods
##   ├── spore_weaver             : 5 pulsing spore belly sacs + spore cloud exhaust
##   ├── mire_stalker             : chameleon chromatophore patches + cloak flicker
##   ├── relic_leech              : 7-ring sucker collar + drain beam socket
##   └── ambusher                 : blade-fin array + venom drip particles
##
## Usage:
##   var og := OverkillGraphicsHushling.new()
##   hushling.add_child(og)
##   og.setup(hushling)

signal graphics_ready

var _enemy   : Node3D = null
var _visual  : Node3D = null
var _archetype : String = "hushling"
var _t       : float = 0.0

var _core_mat   : StandardMaterial3D = null
var _iris_mats  : Array[StandardMaterial3D] = []
var _jaw_root   : Node3D = null
var _jaw_open   : bool = false
var _sbs        : SpringBoneSystem = null

func setup(enemy: Node3D) -> void:
	_enemy     = enemy
	_archetype = str(enemy.get("archetype") if enemy.get("archetype") != null else "hushling")
	_visual    = enemy.get_node_or_null("Visual")
	if _visual == null:
		_visual = Node3D.new()
		_visual.name = "Visual"
		enemy.add_child(_visual)

func _ready() -> void:
	if _enemy == null:
		return
	_build_body_gradient()
	_build_core_gem()
	_build_spine_ridges()
	_build_articulated_claws()
	_build_jaw()
	_build_eye_sockets()
	_build_micro_tendrils()
	_build_ember_exhaust()
	_build_archetype_signature()
	graphics_ready.emit()

func _process(delta: float) -> void:
	_t += delta
	_animate_core(delta)
	_animate_eyes(delta)
	_animate_jaw(delta)

# ─────────────────────────────────────────────────────────────────────────────
# BODY GRADIENT — dark body → vivid rim glow driven by emission
# ─────────────────────────────────────────────────────────────────────────────
func _build_body_gradient() -> void:
	# Two concentric shells — inner dark, outer translucent rim glow
	var palette := _archetype_palette()
	var outer := MeshInstance3D.new()
	outer.name = "RimGlow"
	var sm := SphereMesh.new()
	sm.radius          = 0.44
	sm.height          = 0.72
	sm.radial_segments = 16
	sm.rings           = 10
	outer.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(palette[0].r, palette[0].g, palette[0].b, 0.0)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled           = true
	mat.emission                   = palette[0]
	mat.emission_energy_multiplier = 1.6
	mat.cull_mode = BaseMaterial3D.CULL_FRONT   # show inside surface only
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer.material_override = mat
	outer.position.y = 0.22
	outer.scale = Vector3.ONE * 1.12
	_visual.add_child(outer)

func _archetype_palette() -> Array:
	# [rim_glow_color, core_color]
	match _archetype:
		"charger","thorn_charger": return [Color(0.95,0.30,0.08), Color(1.00,0.40,0.10)]
		"fenling","moonfen_fenling": return [Color(0.28,0.82,0.94), Color(0.50,0.96,1.00)]
		"ember_warden":  return [Color(1.00,0.28,0.06), Color(1.00,0.45,0.12)]
		"spore_weaver":  return [Color(0.60,0.88,0.28), Color(0.80,1.00,0.40)]
		"mire_stalker":  return [Color(0.28,0.78,0.82), Color(0.40,0.90,0.94)]
		"relic_leech":   return [Color(0.44,0.72,1.00), Color(0.60,0.88,1.00)]
		"ambusher":      return [Color(0.32,0.76,0.50), Color(0.48,0.90,0.64)]
		_:               return [Color(0.16,1.00,0.38), Color(0.32,1.00,0.55)]

# ─────────────────────────────────────────────────────────────────────────────
# CORE GEM — deep radiant crystal with lens-flare quad + pulsing light
# ─────────────────────────────────────────────────────────────────────────────
func _build_core_gem() -> void:
	var palette := _archetype_palette()
	var host := Node3D.new()
	host.name = "CoreGem"
	host.position = Vector3(0.0, 0.22, 0.40)
	_visual.add_child(host)

	# Main gem
	var gem := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.10
	sm.height  = 0.16
	gem.mesh = sm
	_core_mat = StandardMaterial3D.new()
	_core_mat.albedo_color               = palette[1]
	_core_mat.emission_enabled           = true
	_core_mat.emission                   = palette[1]
	_core_mat.emission_energy_multiplier = 5.5
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gem.material_override = _core_mat
	host.add_child(gem)

	# Point light
	var light := OmniLight3D.new()
	light.light_color  = palette[1]
	light.light_energy = 1.8
	light.omni_range   = 3.5
	host.add_child(light)

	# Lens flare quad (camera-facing billboard plane)
	var flare := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.28, 0.28)
	flare.mesh = qm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color               = Color(palette[1].r, palette[1].g, palette[1].b, 0.55)
	fmat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.emission_enabled           = true
	fmat.emission                   = palette[1]
	fmat.emission_energy_multiplier = 3.2
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	flare.material_override = fmat
	flare.position.z = 0.06
	host.add_child(flare)

func _animate_core(_delta: float) -> void:
	if _core_mat == null:
		return
	var pattern_mult := 1.0
	if _enemy != null and _enemy.get("current_pattern") != null:
		var p := int(_enemy.get("current_pattern"))
		# Pattern enum: LUNGE=2, WINDUP=3, CHARGE_RUSH=7
		if p in [2, 3, 7]:
			pattern_mult = 2.4
		elif p in [1, 4]:
			pattern_mult = 0.65
	_core_mat.emission_energy_multiplier = (3.8 + sin(_t * 4.5) * 1.8) * pattern_mult

# ─────────────────────────────────────────────────────────────────────────────
# SPINE RIDGES — 6 micro clusters along the dorsal line
# ─────────────────────────────────────────────────────────────────────────────
func _build_spine_ridges() -> void:
	var host := Node3D.new()
	host.name = "SpineRidges"
	_visual.add_child(host)

	for i in 6:
		var t := float(i) / 5.0
		var y := lerpf(0.05, 0.55, t)
		var z := lerpf(-0.06, -0.42, t)
		var h := lerpf(0.18, 0.08, t)
		var r := lerpf(0.055, 0.028, t)
		var spine := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius    = 0.0
		cm.bottom_radius = r
		cm.height        = h
		cm.radial_segments = 5
		spine.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.08, 0.06)
		mat.roughness    = 0.92
		mat.emission_enabled = true
		mat.emission = _archetype_palette()[0]
		mat.emission_energy_multiplier = 0.22 + t * 0.18
		spine.material_override = mat
		spine.position = Vector3(0.0, y, z)
		spine.rotation.x = 0.30 + t * 0.25
		host.add_child(spine)

# ─────────────────────────────────────────────────────────────────────────────
# ARTICULATED CLAWS — 2 arms × 3 segments, emissive claw tips
# ─────────────────────────────────────────────────────────────────────────────
func _build_articulated_claws() -> void:
	for side in [-1.0, 1.0]:
		var arm_root := Node3D.new()
		arm_root.name = "ClawArm_%s" % ("L" if side < 0 else "R")
		arm_root.position = Vector3(0.28 * side, 0.02, 0.20)
		arm_root.rotation = Vector3(-0.28, 0.0, -0.45 * side)
		_visual.add_child(arm_root)

		# 3-segment arm
		var seg_data := [[0.038, 0.022, 0.24], [0.026, 0.016, 0.18], [0.018, 0.010, 0.14]]
		var y_off := 0.0
		for sd in seg_data:
			var seg := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.bottom_radius = sd[0]; cm.top_radius = sd[1]; cm.height = sd[2]; cm.radial_segments = 5
			seg.mesh = cm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.14, 0.10, 0.08); mat.roughness = 0.88
			seg.material_override = mat
			seg.position.y = y_off + sd[2] * 0.5
			seg.rotation.x = -0.20 - float(seg_data.find(sd)) * 0.25
			arm_root.add_child(seg)
			y_off += sd[2]

		# Emissive claw tip
		var tip := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.0; tm.bottom_radius = 0.022; tm.height = 0.16; tm.radial_segments = 5
		tip.mesh = tm
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = _archetype_palette()[0]
		tmat.emission_enabled = true
		tmat.emission = _archetype_palette()[0]
		tmat.emission_energy_multiplier = 1.8
		tip.material_override = tmat
		tip.position = Vector3(0.0, y_off + 0.08, 0.0)
		tip.rotation.x = -0.90
		arm_root.add_child(tip)

# ─────────────────────────────────────────────────────────────────────────────
# JAW / MANDIBLES — opens on attack telegraphs
# ─────────────────────────────────────────────────────────────────────────────
func _build_jaw() -> void:
	_jaw_root = Node3D.new()
	_jaw_root.name = "JawMandibles"
	_jaw_root.position = Vector3(0.0, -0.14, 0.46)
	_visual.add_child(_jaw_root)

	var jaw_mat := StandardMaterial3D.new()
	jaw_mat.albedo_color = Color(0.10, 0.07, 0.05); jaw_mat.roughness = 0.90

	# Two mandible halves
	for side in [-1.0, 1.0]:
		var mandible := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0; cm.bottom_radius = 0.06; cm.height = 0.24; cm.radial_segments = 5
		mandible.mesh = cm
		mandible.material_override = jaw_mat
		mandible.position = Vector3(0.12 * side, 0.0, 0.0)
		mandible.rotation = Vector3(-0.35, 0.0, 0.25 * side)
		_jaw_root.add_child(mandible)

func _animate_jaw(_delta: float) -> void:
	if _jaw_root == null or _enemy == null:
		return
	var pattern := int(_enemy.get("current_pattern") if _enemy.get("current_pattern") != null else 0)
	var should_open := pattern in [2, 3, 6, 7, 13]  # LUNGE, WINDUP, BRAMBLE_BURST, etc.
	if should_open != _jaw_open:
		_jaw_open = should_open
		var tw := _jaw_root.create_tween()
		tw.tween_property(_jaw_root, "rotation:x",
			-0.55 if should_open else 0.0, 0.12).set_trans(Tween.TRANS_EXPO)

# ─────────────────────────────────────────────────────────────────────────────
# EYE SOCKETS — deep hollows + floating iris spheres
# ─────────────────────────────────────────────────────────────────────────────
func _build_eye_sockets() -> void:
	var pal := _archetype_palette()
	for side in [-1.0, 1.0]:
		var socket_root := Node3D.new()
		socket_root.name = "EyeSocket_%s" % ("L" if side < 0 else "R")
		socket_root.position = Vector3(0.18 * side, 0.35, 0.38)
		_visual.add_child(socket_root)

		# Dark hollow
		var hollow := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.08; sm.height = 0.12
		hollow.mesh = sm
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color(0.02, 0.01, 0.01); hmat.roughness = 0.98
		hollow.material_override = hmat
		socket_root.add_child(hollow)

		# Floating iris
		var iris := MeshInstance3D.new()
		var ism := SphereMesh.new()
		ism.radius = 0.052; ism.height = 0.09
		iris.mesh = ism
		var imat := StandardMaterial3D.new()
		imat.albedo_color               = pal[1]
		imat.emission_enabled           = true
		imat.emission                   = pal[1]
		imat.emission_energy_multiplier = 4.5
		imat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		iris.material_override = imat
		_iris_mats.append(imat)
		iris.position.z = 0.04
		socket_root.add_child(iris)

		# Eye glow light
		var light := OmniLight3D.new()
		light.light_color  = pal[1]
		light.light_energy = 0.65
		light.omni_range   = 2.0
		socket_root.add_child(light)

func _animate_eyes(_delta: float) -> void:
	var base := 3.5 + sin(_t * 3.8) * 1.4
	var pattern := int(_enemy.get("current_pattern") if _enemy != null and _enemy.get("current_pattern") != null else 0)
	var mult := 2.2 if pattern in [2, 3, 7] else (0.4 if pattern == 8 else 1.0)
	for imat in _iris_mats:
		if is_instance_valid(imat):
			imat.emission_energy_multiplier = base * mult

# ─────────────────────────────────────────────────────────────────────────────
# MICRO TENDRILS — Verlet physics chains
# ─────────────────────────────────────────────────────────────────────────────
func _build_micro_tendrils() -> void:
	_sbs = SpringBoneSystem.new()
	_sbs.name = "MicroTendrils"
	_sbs.gravity        = Vector3(0.0, -4.5, 0.0)
	_sbs.damping        = 0.88
	_sbs.stiffness      = 0.04
	_sbs.wind_strength  = 0.14
	_sbs.wind_frequency = 0.70
	_visual.add_child(_sbs)

	var tendril_count := 4 if _archetype in ["ambusher","mire_stalker"] else 6
	var pal := _archetype_palette()
	for i in tendril_count:
		var ang := TAU * float(i) / float(tendril_count)
		var anchor := _visual.global_position + Vector3(
			cos(ang) * 0.32, 0.38, sin(ang) * 0.32)
		_sbs.add_chain_at(anchor, randi_range(3, 6),
			randf_range(0.08, 0.14),
			randf_range(0.012, 0.022),
			pal[0].lerp(pal[1], randf_range(0.0, 0.6)))

# ─────────────────────────────────────────────────────────────────────────────
# EMBER EXHAUST — micro particle stream
# ─────────────────────────────────────────────────────────────────────────────
func _build_ember_exhaust() -> void:
	var p := GPUParticles3D.new()
	p.name = "MicroEmbers"
	p.amount = 18; p.lifetime = 0.8; p.emitting = true; p.randomness = 0.75
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape        = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.22
	pm.direction             = Vector3(0, 1, 0)
	pm.spread                = 55.0
	pm.initial_velocity_min  = 0.4
	pm.initial_velocity_max  = 1.5
	pm.gravity               = Vector3(0, 0.2, 0)
	pm.scale_min             = 0.03
	pm.scale_max             = 0.10
	pm.color                 = _archetype_palette()[0]
	p.process_material = pm
	p.position.y = 0.25
	_visual.add_child(p)

# ─────────────────────────────────────────────────────────────────────────────
# ARCHETYPE SIGNATURE PIECES
# ─────────────────────────────────────────────────────────────────────────────
func _build_archetype_signature() -> void:
	match _archetype:
		"charger","thorn_charger": _sig_charger()
		"fenling","moonfen_fenling": _sig_fenling()
		"ember_warden": _sig_ember_warden()
		"spore_weaver": _sig_spore_weaver()
		"mire_stalker": _sig_mire_stalker()
		"relic_leech": _sig_relic_leech()
		"ambusher": _sig_ambusher()

## CHARGER: wide ramming brow plate + paired gore spurs
func _sig_charger() -> void:
	var brow := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.68, 0.16, 0.22)
	brow.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.09, 0.07); mat.roughness = 0.88
	brow.material_override = mat
	brow.position = Vector3(0.0, 0.50, 0.44); brow.rotation.x = -0.25
	_visual.add_child(brow)
	for side in [-1.0, 1.0]:
		var spur := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0; cm.bottom_radius = 0.05; cm.height = 0.38; cm.radial_segments = 5
		spur.mesh = cm
		spur.material_override = mat
		spur.position = Vector3(0.28 * side, 0.48, 0.40)
		spur.rotation = Vector3(-0.55, 0.0, 0.30 * side)
		_visual.add_child(spur)

## FENLING: swept lateral fin array + cold breath particles
func _sig_fenling() -> void:
	var pal := _archetype_palette()
	for side in [-1.0, 1.0]:
		for i in 3:
			var fin := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0; cm.bottom_radius = 0.032; cm.height = 0.36 - float(i) * 0.06; cm.radial_segments = 4
			fin.mesh = cm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.10, 0.20, 0.28); mat.roughness = 0.75
			mat.emission_enabled = true; mat.emission = pal[0]; mat.emission_energy_multiplier = 0.35
			fin.material_override = mat
			fin.position = Vector3(0.30 * side, 0.20 + float(i) * 0.12, -0.10 - float(i) * 0.08)
			fin.rotation = Vector3(0.18, 0.0, -1.20 * side - float(i) * 0.15 * side)
			_visual.add_child(fin)
	var breath := GPUParticles3D.new()
	breath.amount = 12; breath.lifetime = 0.55; breath.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1); pm.spread = 22.0
	pm.initial_velocity_min = 0.5; pm.initial_velocity_max = 1.4
	pm.scale_min = 0.08; pm.scale_max = 0.22; pm.color = pal[0]
	breath.process_material = pm; breath.position = Vector3(0.0, 0.12, 0.46)
	_visual.add_child(breath)

## EMBER WARDEN: shoulder ember pod clusters + larger shield disc
func _sig_ember_warden() -> void:
	var pal := _archetype_palette()
	for side in [-1.0, 1.0]:
		for i in 3:
			var pod := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.065 + float(i) * 0.012
			pod.mesh = sm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.30, 0.12, 0.06)
			mat.emission_enabled = true; mat.emission = pal[0]
			mat.emission_energy_multiplier = 1.4
			pod.material_override = mat
			pod.position = Vector3(0.30 * side, 0.30 + float(i) * 0.14, -0.05)
			_visual.add_child(pod)
			var tw := pod.create_tween().set_loops()
			tw.tween_property(pod, "scale", Vector3.ONE * 1.20, 0.7 + float(i) * 0.1)
			tw.tween_property(pod, "scale", Vector3.ONE * 0.88, 0.7 + float(i) * 0.1)

## SPORE WEAVER: 5 belly sacs + spore cloud exhaust
func _sig_spore_weaver() -> void:
	var pal := _archetype_palette()
	for i in 5:
		var ang := TAU * float(i) / 5.0 + PI
		var sac := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.07, 0.11)
		sac.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.30, 0.42, 0.16)
		mat.emission_enabled = true; mat.emission = pal[0]; mat.emission_energy_multiplier = 0.6
		sac.material_override = mat
		sac.position = Vector3(cos(ang) * 0.28, -0.10, sin(ang) * 0.20)
		_visual.add_child(sac)
		var tw := sac.create_tween().set_loops()
		tw.tween_property(sac, "scale", Vector3.ONE * 1.25, randf_range(0.8, 1.4))
		tw.tween_property(sac, "scale", Vector3.ONE * 0.85, randf_range(0.8, 1.4))
	var cloud := GPUParticles3D.new()
	cloud.amount = 20; cloud.lifetime = 1.2; cloud.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.24; pm.gravity = Vector3(0, 0.1, 0)
	pm.initial_velocity_min = 0.2; pm.initial_velocity_max = 0.7
	pm.scale_min = 0.12; pm.scale_max = 0.38; pm.color = pal[0]
	cloud.process_material = pm; cloud.position.y = 0.0
	_visual.add_child(cloud)

## MIRE STALKER: chromatophore patches (colour-shift quads)
func _sig_mire_stalker() -> void:
	var pal := _archetype_palette()
	for i in 5:
		var ang := TAU * float(i) / 5.0
		var patch := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(randf_range(0.12, 0.22), randf_range(0.08, 0.16))
		patch.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(pal[0].r, pal[0].g, pal[0].b, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true; mat.emission = pal[0]; mat.emission_energy_multiplier = 0.4
		patch.material_override = mat
		patch.position = Vector3(cos(ang) * 0.36, 0.18, sin(ang) * 0.36)
		patch.rotation.y = ang
		_visual.add_child(patch)
		# Shimmer cycle
		var tw := mat.create_tween().set_loops()
		tw.tween_property(mat, "emission_energy_multiplier", 1.4, randf_range(0.5, 1.2))
		tw.tween_property(mat, "emission_energy_multiplier", 0.0, randf_range(0.5, 1.2))

## RELIC LEECH: sucker collar ring + drain beam socket
func _sig_relic_leech() -> void:
	var pal := _archetype_palette()
	for i in 7:
		var ang := TAU * float(i) / 7.0
		var sucker := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.048; cm.bottom_radius = 0.048; cm.height = 0.035; cm.radial_segments = 8
		sucker.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.16, 0.32)
		mat.emission_enabled = true; mat.emission = pal[0]; mat.emission_energy_multiplier = 0.8
		sucker.material_override = mat
		sucker.position = Vector3(cos(ang) * 0.38, 0.12, sin(ang) * 0.38)
		sucker.rotation = Vector3(PI * 0.5, ang, 0.0)
		_visual.add_child(sucker)

## AMBUSHER: blade fins + venom drip particles
func _sig_ambusher() -> void:
	var pal := _archetype_palette()
	for side in [-1.0, 1.0]:
		for b in 4:
			var blade := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.025, 0.28 - float(b) * 0.04, 0.10 - float(b) * 0.015)
			blade.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.08, 0.18, 0.12); mat.roughness = 0.55; mat.metallic = 0.55
			mat.emission_enabled = true; mat.emission = pal[0]; mat.emission_energy_multiplier = 0.5
			blade.material_override = mat
			blade.position = Vector3(0.26 * side, 0.18 + float(b) * 0.08, -0.08 - float(b) * 0.04)
			blade.rotation = Vector3(0.15 + float(b) * 0.08, 0.0, -0.80 * side)
			_visual.add_child(blade)
	var venom := GPUParticles3D.new()
	venom.amount = 10; venom.lifetime = 0.6; venom.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0); pm.spread = 15.0; pm.gravity = Vector3(0, -1.5, 0)
	pm.initial_velocity_min = 0.2; pm.initial_velocity_max = 0.6
	pm.scale_min = 0.04; pm.scale_max = 0.10; pm.color = pal[0]
	venom.process_material = pm; venom.position = Vector3(0.0, -0.25, 0.32)
	_visual.add_child(venom)
