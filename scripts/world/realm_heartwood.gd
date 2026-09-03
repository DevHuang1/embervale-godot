extends Node3D
class_name RealmHeartwood

## === Heartwood Biome Builder ===
## Procedurally generates the Heartwood realm at runtime:
##   - Petrified ember stone pillars (with crack geometry + emissive seams)
##   - Destructible columns: shatter into debris shards on boss stomp/AoE
##   - Erupting ash vents: periodic GPUParticles3D bursts + heat shimmer
##   - Heat shimmer proxy (animated WorldEnvironment fog density pulses)
##   - Growing terrain per boss phase: root-like extrusions push out of the ground
##   - Arena boundary wall of fused ember rock
##
## Usage: instantiate and add_child() to the world scene when realm == "heartwood".
##        Call setup(world_manager, boss_node) once.

signal vent_erupted(position: Vector3)
signal column_shattered(position: Vector3)

@export var rng_seed: int = 7
@export var pillar_count: int = 12
@export var vent_count: int = 6
@export var arena_radius: float = 28.0
@export var destructible_columns: int = 8

const COL_EMBER_ROCK := Color(0.20, 0.12, 0.09)
const COL_SEAM       := Color(1.00, 0.38, 0.08)
const COL_ASH        := Color(0.52, 0.44, 0.38, 0.65)
const COL_HEAT       := Color(0.95, 0.42, 0.12)
const COL_BOUNDARY   := Color(0.17, 0.09, 0.07)

var _rng: RandomNumberGenerator
var _destructibles: Array[Node3D] = []
var _vents: Array[GPUParticles3D] = []
var _vent_timers: Array[float] = []
var _phase_roots: Array[Node3D] = []
var _world: Node3D = null
var _boss: Node3D = null
var _current_phase: int = 0

func setup(world_manager: Node3D, boss_node: Node3D = null) -> void:
	_world = world_manager
	_boss  = boss_node
	if _boss != null and _boss.has_signal("phase_changed"):
		_boss.phase_changed.connect(_on_boss_phase_changed)

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = rng_seed
	_build_arena_boundary()
	_build_ember_pillars()
	_build_destructible_columns()
	_build_ash_vents()
	_build_heat_floor()

func _process(delta: float) -> void:
	_update_vents(delta)

# ─────────────────────────────────────────────────────────────────────────────
# Arena Boundary Wall
# ─────────────────────────────────────────────────────────────────────────────
func _build_arena_boundary() -> void:
	var mat := _seam_mat(COL_BOUNDARY, Color(0.60, 0.10, 0.03), 0.85)
	var segment_count := 32
	var seg_angle := TAU / float(segment_count)
	for i in segment_count:
		var angle := seg_angle * float(i)
		var mb := MeshInstance3D.new()
		mb.name = "BoundaryWall_%d" % i
		var bm := BoxMesh.new()
		var h  := _rng.randf_range(2.2, 4.8)
		bm.size = Vector3(_rng.randf_range(1.6, 3.0), h, _rng.randf_range(0.8, 1.6))
		mb.mesh = bm
		mb.material_override = mat
		mb.position = Vector3(
			cos(angle) * arena_radius, h * 0.5,
			sin(angle) * arena_radius)
		mb.rotation.y = angle + PI * 0.5
		mb.rotation.x = _rng.randf_range(-0.05, 0.05)
		mb.rotation.z = _rng.randf_range(-0.06, 0.06)
		add_child(mb)

# ─────────────────────────────────────────────────────────────────────────────
# Ember Stone Pillars
# Each pillar = stacked BoxMesh segments with emissive crack seams.
# ─────────────────────────────────────────────────────────────────────────────
func _build_ember_pillars() -> void:
	var rock_mat := _seam_mat(COL_EMBER_ROCK, COL_SEAM, 0.88)
	for i in pillar_count:
		var angle := _rng.randf_range(0.0, TAU)
		var dist  := _rng.randf_range(5.5, arena_radius * 0.82)
		var root  := Node3D.new()
		root.name = "Pillar_%d" % i
		root.position = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		root.rotation.y = _rng.randf_range(0.0, TAU)
		add_child(root)

		var pillar_h := _rng.randf_range(3.5, 9.0)
		var segments := _rng.randi_range(3, 7)
		var y_cursor := 0.0
		for s in segments:
			var seg_h := pillar_h / float(segments) * _rng.randf_range(0.75, 1.25)
			var seg_r := _rng.randf_range(0.22, 0.68) * (1.0 - float(s) / float(segments) * 0.4)
			var seg := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.bottom_radius   = seg_r * _rng.randf_range(0.88, 1.12)
			cm.top_radius      = seg_r * _rng.randf_range(0.72, 0.98)
			cm.height          = seg_h
			cm.radial_segments = _rng.randi_range(5, 9)
			seg.mesh            = cm
			seg.material_override = rock_mat
			seg.position.y      = y_cursor + seg_h * 0.5
			seg.rotation.y      = _rng.randf_range(0.0, PI * 0.5)
			root.add_child(seg)
			# Crack seam strip
			_add_seam(root, y_cursor + seg_h, _rng.randf_range(0.035, 0.06))
			y_cursor += seg_h

		# Ember glow at base
		var glow := OmniLight3D.new()
		glow.light_color  = COL_HEAT
		glow.light_energy = _rng.randf_range(0.7, 1.9)
		glow.omni_range   = _rng.randf_range(3.5, 7.5)
		glow.position.y   = 0.25
		root.add_child(glow)
		var tw := glow.create_tween().set_loops()
		tw.tween_property(glow, "light_energy",
			glow.light_energy * 1.55, _rng.randf_range(0.8, 1.6)) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(glow, "light_energy",
			glow.light_energy * 0.60, _rng.randf_range(0.8, 1.6)) \
			.set_trans(Tween.TRANS_SINE)

func _add_seam(parent: Node3D, y: float, half_w: float) -> void:
	var sm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(_rng.randf_range(0.6, 1.4), half_w * 2.0, half_w)
	sm.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COL_SEAM
	mat.emission_enabled = true
	mat.emission = COL_SEAM
	mat.emission_energy_multiplier = _rng.randf_range(1.4, 3.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material_override = mat
	sm.position = Vector3(_rng.randf_range(-0.3, 0.3), y, 0)
	sm.rotation.y = _rng.randf_range(0.0, TAU)
	parent.add_child(sm)

# ─────────────────────────────────────────────────────────────────────────────
# Destructible Columns
# Shatter into ~12 debris shards on call_shatter(). Collision disabled after.
# ─────────────────────────────────────────────────────────────────────────────
func _build_destructible_columns() -> void:
	var mat := _seam_mat(Color(0.24, 0.14, 0.10), COL_SEAM, 0.90)
	for i in destructible_columns:
		var angle := _rng.randf_range(0.0, TAU)
		var dist  := _rng.randf_range(4.0, arena_radius * 0.55)
		var col_root := Node3D.new()
		col_root.name = "DestructibleColumn_%d" % i
		col_root.position = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		add_child(col_root)

		var h := _rng.randf_range(2.0, 5.5)
		var body := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = _rng.randf_range(0.28, 0.52)
		cm.top_radius    = cm.bottom_radius * _rng.randf_range(0.65, 0.92)
		cm.height        = h
		cm.radial_segments = 6
		body.mesh = cm
		body.material_override = mat
		body.position.y = h * 0.5
		col_root.add_child(body)
		_destructibles.append(col_root)

## Call this externally (e.g. from BossBase._on_footfall) when a stomp lands
## near a destructible column.
func shatter_near(world_pos: Vector3, radius: float = 5.5) -> void:
	for col in _destructibles.duplicate():
		if not is_instance_valid(col):
			continue
		if col.global_position.distance_to(world_pos) > radius:
			continue
		_do_shatter(col)

func _do_shatter(col: Node3D) -> void:
	_destructibles.erase(col)
	var origin := col.global_position
	column_shattered.emit(origin)
	CombatFx.spawn_burst(self, origin + Vector3(0, 1.2, 0),
		COL_SEAM, 24, 8.0, 0.5, 0.18)
	CombatFx.spawn_shockwave(self, origin, 3.5, Color(COL_HEAT.r, COL_HEAT.g, COL_HEAT.b, 0.8), 0.6)
	# Spawn debris shards
	var shard_mat := _seam_mat(COL_EMBER_ROCK, COL_SEAM, 0.85)
	for s in 14:
		var shard := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(
			_rng.randf_range(0.08, 0.28),
			_rng.randf_range(0.05, 0.22),
			_rng.randf_range(0.06, 0.20))
		shard.mesh = bm
		shard.material_override = shard_mat
		shard.global_position = origin + Vector3(
			_rng.randf_range(-0.3, 0.3), _rng.randf_range(0.5, 1.8),
			_rng.randf_range(-0.3, 0.3))
		shard.rotation = Vector3(
			_rng.randf_range(0.0, TAU), _rng.randf_range(0.0, TAU),
			_rng.randf_range(0.0, TAU))
		add_child(shard)
		var vel := Vector3(
			_rng.randf_range(-5.5, 5.5), _rng.randf_range(2.0, 7.5),
			_rng.randf_range(-5.5, 5.5))
		var tw := shard.create_tween()
		tw.tween_property(shard, "global_position",
			shard.global_position + vel, 0.55).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(shard, "rotation",
			shard.rotation + Vector3(
				_rng.randf_range(-TAU, TAU), _rng.randf_range(-TAU, TAU),
				_rng.randf_range(-TAU, TAU)), 0.55)
		tw.tween_callback(shard.queue_free)
	col.queue_free()

# ─────────────────────────────────────────────────────────────────────────────
# Ash Vents
# ─────────────────────────────────────────────────────────────────────────────
func _build_ash_vents() -> void:
	for i in vent_count:
		var angle := _rng.randf_range(0.0, TAU)
		var dist  := _rng.randf_range(3.0, arena_radius * 0.72)
		var origin := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		# Vent mouth geometry
		var mouth := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.bottom_radius = 0.55
		cm.top_radius    = 0.38
		cm.height        = 0.32
		cm.radial_segments = 8
		mouth.mesh = cm
		mouth.material_override = _make_mat(COL_EMBER_ROCK, 0.90)
		mouth.position = origin
		add_child(mouth)
		# Particles
		var p := GPUParticles3D.new()
		p.name     = "AshVent_%d" % i
		p.position = origin + Vector3(0, 0.2, 0)
		p.amount   = 48
		p.lifetime = 1.8
		p.emitting  = true
		p.randomness = 0.70
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape   = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.22
		pm.direction        = Vector3(0, 1, 0)
		pm.spread           = 18.0
		pm.initial_velocity_min = 1.4
		pm.initial_velocity_max = 4.0
		pm.gravity          = Vector3(0, -0.6, 0)
		pm.scale_min        = 0.12
		pm.scale_max        = 0.45
		pm.color            = COL_ASH
		p.process_material  = pm
		add_child(p)
		_vents.append(p)
		_vent_timers.append(_rng.randf_range(3.5, 9.0))
		# Heat light at vent base
		var gl := OmniLight3D.new()
		gl.light_color  = COL_HEAT
		gl.light_energy = 0.0
		gl.omni_range   = 4.5
		p.add_child(gl)

func _update_vents(delta: float) -> void:
	for i in _vent_timers.size():
		_vent_timers[i] -= delta
		if _vent_timers[i] <= 0.0:
			_erupt_vent(i)
			_vent_timers[i] = _rng.randf_range(4.0, 11.0)

func _erupt_vent(i: int) -> void:
	if i >= _vents.size():
		return
	var p := _vents[i]
	if not is_instance_valid(p):
		return
	vent_erupted.emit(p.global_position)
	var gl: OmniLight3D = p.get_node_or_null("OmniLight3D")
	if gl:
		var tw := p.create_tween()
		tw.tween_property(gl, "light_energy", 2.4, 0.15).set_trans(Tween.TRANS_EXPO)
		tw.tween_property(gl, "light_energy", 0.0, 0.8).set_trans(Tween.TRANS_QUAD)
	CombatFx.spawn_burst(self, p.global_position + Vector3(0, 0.5, 0),
		COL_HEAT, 18, 5.5, 0.4, 0.14)

# ─────────────────────────────────────────────────────────────────────────────
# Heat Floor (glowing ground plane + shimmer)
# ─────────────────────────────────────────────────────────────────────────────
func _build_heat_floor() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.09, 0.06, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.15, 0.04)
	mat.emission_energy_multiplier = 0.18
	mat.roughness = 0.95
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "HeatFloor"
	var qm := QuadMesh.new()
	qm.size = Vector2(arena_radius * 2.2, arena_radius * 2.2)
	floor_mesh.mesh = qm
	floor_mesh.material_override = mat
	floor_mesh.position.y = 0.015
	floor_mesh.rotation.x = -PI * 0.5
	add_child(floor_mesh)
	var tw := mat.create_tween().set_loops()
	tw.tween_property(mat, "emission_energy_multiplier", 0.38, 1.3).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mat, "emission_energy_multiplier", 0.08, 1.6).set_trans(Tween.TRANS_SINE)

# ─────────────────────────────────────────────────────────────────────────────
# Phase-driven terrain growth
# Called by boss phase_changed signal. Root-like extrusions push up.
# ─────────────────────────────────────────────────────────────────────────────
func _on_boss_phase_changed(phase: int) -> void:
	_current_phase = phase
	_grow_terrain_for_phase(phase)

func _grow_terrain_for_phase(phase: int) -> void:
	var growth_count := (phase + 1) * 5
	var mat := _seam_mat(Color(0.16, 0.08, 0.05), COL_SEAM, 0.92)
	for i in growth_count:
		var angle := _rng.randf_range(0.0, TAU)
		var dist  := _rng.randf_range(1.5, arena_radius * 0.6)
		var root_pos := Vector3(cos(angle) * dist, -0.5, sin(angle) * dist)
		var root_node := MeshInstance3D.new()
		root_node.name = "TerrainRoot_P%d_%d" % [phase, i]
		var cm := CylinderMesh.new()
		cm.bottom_radius = _rng.randf_range(0.06, 0.18)
		cm.top_radius    = _rng.randf_range(0.02, 0.06)
		cm.height        = _rng.randf_range(0.6, 1.8) + phase * 0.4
		cm.radial_segments = 5
		root_node.mesh = cm
		root_node.material_override = mat
		root_node.global_position = root_pos
		root_node.rotation = Vector3(
			_rng.randf_range(-0.4, 0.6), _rng.randf_range(0.0, TAU), 0)
		add_child(root_node)
		_phase_roots.append(root_node)
		# Animate push up from ground
		var target_y := _rng.randf_range(0.3, 1.1 + phase * 0.3)
		var tw := root_node.create_tween()
		root_node.scale = Vector3.ONE * 0.01
		tw.tween_property(root_node, "position:y", target_y, 0.7) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(root_node, "scale",
			Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Flash the floor brighter on phase change
	CombatFx.spawn_shockwave(self, Vector3.ZERO, arena_radius * 0.8,
		Color(COL_HEAT.r, COL_HEAT.g, COL_HEAT.b, 0.6), 0.9)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
func _seam_mat(base: Color, seam: Color, rough: float) -> ShaderMaterial:
	# Inline GDScript-driven StandardMaterial that approximates seams via emission
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base
	mat.roughness    = rough
	mat.metallic     = 0.12
	mat.emission_enabled = true
	mat.emission = seam
	mat.emission_energy_multiplier = _rng.randf_range(0.55, 1.80)
	return mat

func _make_mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness    = rough
	return m
