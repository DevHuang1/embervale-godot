extends Node3D
class_name RealmMistfen

## === Mistfen Biome Builder ===
## Procedurally generates the Mistfen realm at runtime:
##   - Dead willow trees with recursive branching + Verlet spring tendril chains
##   - Waterlogged ground patches (animated shimmer)
##   - Reed beds with wind-sway
##   - Spore slow-field Area3D hazards (movement debuff + visual cloud)
##   - Rising cold mist particle columns
##   - Ambient fog layer plane
##
## Usage: instantiate and add_child() to the world scene when realm == "mistfen".
##        Call setup(world_manager) once after add_child.

signal hazard_triggered(hazard_type: String, position: Vector3)

@export var rng_seed: int = 42
@export var willow_count: int = 14
@export var reed_cluster_count: int = 9
@export var water_patch_count: int = 7
@export var slow_field_count: int = 4
@export var arena_radius: float = 30.0

# === Biome palette ===
const COL_BARK        := Color(0.13, 0.17, 0.15)
const COL_WATER       := Color(0.05, 0.13, 0.22, 0.70)
const COL_MIST        := Color(0.52, 0.68, 0.78)
const COL_SPORE       := Color(0.38, 0.58, 0.32, 0.42)
const COL_REED        := Color(0.34, 0.43, 0.26)
const SLOW_MULT       := 0.42   # hero move_speed multiplier inside field

var _rng: RandomNumberGenerator
var _spring_chains: Array = []   # Array of Arrays of Dictionaries

var _world: Node3D = null

func setup(world_manager: Node3D) -> void:
	_world = world_manager

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = rng_seed
	_build_dead_willows()
	_build_water_patches()
	_build_reed_beds()
	_build_slow_fields()
	_build_mist_columns()
	_build_ambient_fog_layer()

func _process(delta: float) -> void:
	_update_spring_chains(delta)

# ─────────────────────────────────────────────────────────────────────────────
# Dead Willow Trees
# Each tree = tapered trunk + recursive sub-branches + hanging Verlet tendril chains.
# ─────────────────────────────────────────────────────────────────────────────
func _build_dead_willows() -> void:
	var bark := _make_mat(COL_BARK, 0.95, 0.0)
	for i in willow_count:
		var angle := _rng.randf_range(0.0, TAU)
		var dist  := _rng.randf_range(7.0, arena_radius * 0.88)
		var root  := Node3D.new()
		root.name = "Willow_%d" % i
		root.position = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		root.rotation.y = _rng.randf_range(0.0, TAU)
		add_child(root)

		var trunk_h := _rng.randf_range(4.0, 7.6)
		var trunk := _cylinder_mesh(root, bark,
			_rng.randf_range(0.12, 0.22), _rng.randf_range(0.04, 0.09),
			trunk_h, 7)
		trunk.position.y = trunk_h * 0.5
		trunk.rotation.z = _rng.randf_range(-0.14, 0.14)

		var branch_count := _rng.randi_range(3, 7)
		for b in branch_count:
			_add_branch(root, bark,
				Vector3(0, trunk_h * _rng.randf_range(0.45, 0.88), 0),
				_rng.randf_range(0.65, 1.5), 0)

		var tendril_count := _rng.randi_range(4, 11)
		for t in tendril_count:
			var crown := root.position + Vector3(
				_rng.randf_range(-0.7, 0.7), trunk_h * 0.91,
				_rng.randf_range(-0.7, 0.7))
			_build_spring_tendril(crown, _rng.randf_range(1.2, 3.2),
				_rng.randi_range(4, 9), bark)

func _add_branch(parent: Node3D, mat: Material,
		attach: Vector3, length: float, depth: int) -> void:
	if depth > 2 or length < 0.22:
		return
	var b := _cylinder_mesh(parent, mat,
		maxf(0.025 - depth * 0.006, 0.008),
		maxf(0.012 - depth * 0.003, 0.004),
		length, 5)
	b.position = attach + Vector3(
		_rng.randf_range(-0.5, 0.5) * length,
		length * 0.5 + _rng.randf_range(-0.08, 0.18),
		_rng.randf_range(-0.5, 0.5) * length)
	b.rotation = Vector3(
		_rng.randf_range(-0.9, 0.9),
		_rng.randf_range(0.0, TAU),
		_rng.randf_range(-0.55, 0.55))
	if depth < 2:
		_add_branch(parent, mat,
			b.position + Vector3(0, length * 0.42, 0),
			length * _rng.randf_range(0.38, 0.62), depth + 1)

# ─────────────────────────────────────────────────────────────────────────────
# Verlet Spring Tendril Chains
# Gravity + wind turbulence, distance constraints walked backwards each frame.
# ─────────────────────────────────────────────────────────────────────────────
func _build_spring_tendril(world_anchor: Vector3, total_len: float,
		segments: int, mat: Material) -> void:
	var seg_len := total_len / float(segments)
	var chain: Array = []
	for s in segments + 1:
		var link := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = maxf(0.024 - s * 0.002, 0.007)
		sm.height  = sm.radius * 2.0
		link.mesh  = sm
		link.material_override = mat
		link.global_position = world_anchor + Vector3(0.0, -s * seg_len, 0.0)
		add_child(link)
		chain.append({
			"node":   link,
			"pos":    link.global_position,
			"prev":   link.global_position,
			"anchor": s == 0,
			"anchor_world": world_anchor,
			"seg_len": seg_len,
		})
	_spring_chains.append(chain)

func _update_spring_chains(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var gravity := Vector3(0.0, -4.2, 0.0)
	for chain in _spring_chains:
		var anchor_x: float = chain[0]["anchor_world"].x
		var anchor_z: float = chain[0]["anchor_world"].z
		var wind := Vector3(
			sin(t * 0.65 + anchor_x * 0.38) * 0.20,
			0.0,
			cos(t * 0.48 + anchor_z * 0.28) * 0.15)
		# Verlet integrate
		for i in chain.size():
			var lnk: Dictionary = chain[i]
			if lnk["anchor"]:
				lnk["pos"]  = lnk["anchor_world"]
				lnk["prev"] = lnk["anchor_world"]
				lnk["node"].global_position = lnk["anchor_world"]
				continue
			var vel := (lnk["pos"] - lnk["prev"]) * 0.88
			var new_pos := lnk["pos"] + vel + (gravity + wind) * (delta * delta)
			# Floor clamp so tendrils don't clip into terrain
			new_pos.y = maxf(new_pos.y, lnk["anchor_world"].y - lnk["seg_len"] * chain.size())
			lnk["prev"] = lnk["pos"]
			lnk["pos"]  = new_pos
		# Distance constraint backward pass
		for i in range(chain.size() - 1, 0, -1):
			var a: Dictionary = chain[i - 1]
			var b: Dictionary = chain[i]
			var diff := b["pos"] - a["pos"]
			var dist := diff.length()
			if dist < 0.0001:
				continue
			var corr := diff * (1.0 - b["seg_len"] / dist) * 0.5
			if not a["anchor"]:
				a["pos"] += corr
			b["pos"] -= corr
			b["node"].global_position = b["pos"]
		chain[0]["node"].global_position = chain[0]["pos"]

# ─────────────────────────────────────────────────────────────────────────────
# Water Patches
# ─────────────────────────────────────────────────────────────────────────────
func _build_water_patches() -> void:
	for i in water_patch_count:
		var angle := _rng.randf_range(0.0, TAU)
		var dist  := _rng.randf_range(3.0, arena_radius * 0.74)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COL_WATER
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness    = 0.04
		mat.metallic     = 0.35
		mat.emission_enabled = true
		mat.emission         = Color(0.04, 0.10, 0.20)
		mat.emission_energy_multiplier = 0.45
		var patch := MeshInstance3D.new()
		patch.name = "WaterPatch_%d" % i
		var qm := QuadMesh.new()
		qm.size = Vector2(_rng.randf_range(2.8, 6.8), _rng.randf_range(2.2, 5.4))
		patch.mesh = qm
		patch.material_override = mat
		patch.position = Vector3(cos(angle) * dist, 0.03, sin(angle) * dist)
		patch.rotation.x = -PI * 0.5
		patch.rotation.z = _rng.randf_range(0.0, TAU)
		add_child(patch)
		var tw := patch.create_tween().set_loops()
		tw.tween_property(patch, "position:y", 0.06, _rng.randf_range(1.5, 2.9)) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(patch, "position:y", 0.02, _rng.randf_range(1.5, 2.9)) \
			.set_trans(Tween.TRANS_SINE)
		# Ripple light
		var light := OmniLight3D.new()
		light.light_color = COL_MIST
		light.light_energy = 0.28
		light.omni_range   = 3.5
		light.position.y   = 0.1
		patch.add_child(light)

# ─────────────────────────────────────────────────────────────────────────────
# Reed Beds
# ─────────────────────────────────────────────────────────────────────────────
func _build_reed_beds() -> void:
	var mat := _make_mat(COL_REED, 0.85, 0.0)
	for cluster in reed_cluster_count:
		var angle := _rng.randf_range(0.0, TAU)
		var dist  := _rng.randf_range(4.0, arena_radius * 0.80)
		var center := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var count  := _rng.randi_range(9, 20)
		for r in count:
			var h  := _rng.randf_range(0.9, 2.4)
			var cm := _cylinder_mesh(self, mat, 0.012, 0.022, h, 4)
			cm.position = center + Vector3(
				_rng.randf_range(-1.4, 1.4), h * 0.5,
				_rng.randf_range(-1.4, 1.4))
			cm.rotation = Vector3(
				_rng.randf_range(-0.18, 0.18),
				_rng.randf_range(0.0, TAU),
				_rng.randf_range(-0.18, 0.18))

# ─────────────────────────────────────────────────────────────────────────────
# Spore Slow-Field Hazards
# ─────────────────────────────────────────────────────────────────────────────
func _build_slow_fields() -> void:
	for i in slow_field_count:
		var angle := _rng.randf_range(0.0, TAU)
		var dist  := _rng.randf_range(5.0, arena_radius * 0.65)
		var field := Area3D.new()
		field.name = "SporeField_%d" % i
		field.position = Vector3(cos(angle) * dist, 0.3, sin(angle) * dist)
		field.collision_layer = 0
		field.collision_mask  = 1 << 0
		var cshape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = _rng.randf_range(2.2, 4.0)
		cshape.shape  = sphere
		field.add_child(cshape)
		# Visual cloud
		var cloud := MeshInstance3D.new()
		var cm2 := SphereMesh.new()
		cm2.radius = sphere.radius
		cm2.height = sphere.radius * 1.5
		cloud.mesh = cm2
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = COL_SPORE
		cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cmat.emission_enabled = true
		cmat.emission = Color(0.30, 0.52, 0.24)
		cmat.emission_energy_multiplier = 0.30
		cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		cloud.material_override = cmat
		field.add_child(cloud)
		add_child(field)
		field.body_entered.connect(_on_spore_entered)
		field.body_exited.connect(_on_spore_exited)
		# Opacity pulse
		var tw := cmat.create_tween().set_loops()
		tw.tween_property(cmat, "albedo_color:a", 0.16, _rng.randf_range(1.4, 2.2)) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(cmat, "albedo_color:a", 0.52, _rng.randf_range(1.4, 2.2)) \
			.set_trans(Tween.TRANS_SINE)

func _on_spore_entered(body: Node3D) -> void:
	if body.has_method("apply_move_slow"):
		body.call("apply_move_slow", SLOW_MULT, 0.0)
	hazard_triggered.emit("spore_slow", body.global_position)

func _on_spore_exited(body: Node3D) -> void:
	if body.has_method("remove_move_slow"):
		body.call("remove_move_slow")

# ─────────────────────────────────────────────────────────────────────────────
# Mist Columns
# ─────────────────────────────────────────────────────────────────────────────
func _build_mist_columns() -> void:
	for i in 7:
		var angle := _rng.randf_range(0.0, TAU)
		var dist  := _rng.randf_range(2.0, arena_radius * 0.85)
		var p := GPUParticles3D.new()
		p.name     = "MistColumn_%d" % i
		p.position = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		p.amount   = 28
		p.lifetime = 3.4
		p.emitting  = true
		p.randomness = 0.65
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape   = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.55
		pm.direction        = Vector3(0, 1, 0)
		pm.spread           = 20.0
		pm.initial_velocity_min = 0.35
		pm.initial_velocity_max = 1.05
		pm.gravity          = Vector3(0, 0.02, 0)
		pm.scale_min        = 0.45
		pm.scale_max        = 1.5
		pm.color            = COL_MIST
		p.process_material  = pm
		add_child(p)

# ─────────────────────────────────────────────────────────────────────────────
# Ambient Fog Layer
# ─────────────────────────────────────────────────────────────────────────────
func _build_ambient_fog_layer() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(COL_MIST.r, COL_MIST.g, COL_MIST.b, 0.07)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var plane := MeshInstance3D.new()
	plane.name = "AmbientFogLayer"
	var qm2 := QuadMesh.new()
	qm2.size = Vector2(arena_radius * 2.6, arena_radius * 2.6)
	plane.mesh = qm2
	plane.material_override = mat
	plane.position.y  = 6.0
	plane.rotation.x  = PI * 0.5
	add_child(plane)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
func _make_mat(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness    = rough
	m.metallic     = metal
	return m

func _cylinder_mesh(parent: Node3D, mat: Material,
		bottom_r: float, top_r: float, height: float, segs: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius  = bottom_r
	cm.top_radius     = top_r
	cm.height         = height
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = mat
	parent.add_child(mi)
	return mi
