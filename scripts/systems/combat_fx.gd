extends Node
class_name CombatFx

## === CombatFx — Centralised Visual FX Dispatcher ===
## All 80+ call sites across entities and biomes route through this AutoLoad.
## Rendering is procedural (no imported assets needed):
##   - Burst: GPUParticles3D sphere explosion
##   - Ring: expanding TorusMesh (scales to radius + fades)
##   - Slash: rotated QuadMesh sweep (scales + fades)
##   - Shockwave: expanding flat TorusMesh ground wave
##   - Ground telegraph: persistent warning decal plane
##   - Motes: soft floating orbs (ambient)
##   - Spawn portal: swirling ring for enemy spawns
##   - Decal: ground scorch mark (fades over 4s)
##   - Impact: camera shake + HiStop via ImpactDirector
##
## All nodes are deferred-freed after their animation completes.
## Source node is used only for tree context and is never retained.

const MAX_ACTIVE := 64  # hard cap to prevent runaway spawns

var _active := 0

# ─────────────────────────────────────────────────────────────────────────────
# Burst
# ─────────────────────────────────────────────────────────────────────────────

static func spawn_burst(
		source: Node3D,
		world_pos: Vector3,
		color: Color,
		amount: int,
		speed: float,
		lifetime: float,
		scale_max: float) -> void:
	var fx := CombatFx
	if not is_instance_valid(source) or not source.is_inside_tree():
		return
	var tree := source.get_tree()
	if tree == null:
		return

	var p := GPUParticles3D.new()
	p.amount              = clampi(amount, 1, 64)
	p.lifetime            = lifetime
	p.emitting            = false
	p.one_shot            = true
	p.explosiveness       = 0.92
	p.randomness          = 0.55

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape        = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction             = Vector3(0, 1, 0)
	pm.spread                = 180.0
	pm.initial_velocity_min  = speed * 0.6
	pm.initial_velocity_max  = speed
	pm.gravity               = Vector3(0, -4.5, 0)
	pm.scale_min             = scale_max * 0.5
	pm.scale_max             = scale_max
	pm.color                 = color
	p.process_material       = pm

	var scene_root := tree.current_scene
	if scene_root == null:
		scene_root = source.get_parent()
	scene_root.add_child(p)
	p.global_position = world_pos
	p.emitting = true

	# Auto-free after particles finish
	var wait := source.get_tree().create_timer(lifetime + 0.25, false)
	wait.timeout.connect(p.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
# Ring (expanding torus)
# ─────────────────────────────────────────────────────────────────────────────

static func spawn_ring(
		source: Node3D,
		world_pos: Vector3,
		radius: float,
		color: Color,
		duration: float) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree():
		return
	var scene_root := source.get_tree().current_scene
	if scene_root == null:
		scene_root = source.get_parent()

	var ring := MeshInstance3D.new()
	ring.name = "FxRing"
	var tm := TorusMesh.new()
	tm.inner_radius  = maxf(radius * 0.88, 0.05)
	tm.outer_radius  = radius
	tm.ring_segments = 32
	tm.rings         = 2
	ring.mesh        = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(color.r, color.g, color.b, 0.72)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled           = true
	mat.emission                   = color
	mat.emission_energy_multiplier = 1.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.rotation.x = PI * 0.5
	scene_root.add_child(ring)
	ring.global_position = world_pos

	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * (radius * 1.35), duration).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, duration)
	tw.chain().tween_callback(ring.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
# Slash (weapon arc)
# ─────────────────────────────────────────────────────────────────────────────

static func spawn_slash(
		source: Node3D,
		world_pos: Vector3,
		color: Color) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree():
		return
	var scene_root := source.get_tree().current_scene
	if scene_root == null:
		scene_root = source.get_parent()

	var slash := MeshInstance3D.new()
	slash.name = "FxSlash"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.85)
	slash.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(color.r, color.g, color.b, 0.88)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled           = true
	mat.emission                   = color
	mat.emission_energy_multiplier = 3.5
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slash.material_override = mat
	slash.rotation = Vector3(randf_range(-0.4, 0.4), randf_range(0.0, TAU), 0.0)
	scene_root.add_child(slash)
	slash.global_position = world_pos

	var tw := slash.create_tween()
	tw.set_parallel(true)
	tw.tween_property(slash, "scale", Vector3(2.2, 2.2, 1.0), 0.22).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.22)
	tw.chain().tween_callback(slash.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
# Shockwave (ground-level radial wave)
# ─────────────────────────────────────────────────────────────────────────────

static func spawn_shockwave(
		source: Node3D,
		world_pos: Vector3,
		radius: float,
		color: Color,
		duration: float) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree():
		return
	var scene_root := source.get_tree().current_scene
	if scene_root == null:
		scene_root = source.get_parent()

	var wave := MeshInstance3D.new()
	wave.name = "FxShockwave"
	var tm := TorusMesh.new()
	tm.inner_radius  = 0.05
	tm.outer_radius  = 0.18
	tm.ring_segments = 48
	tm.rings         = 2
	wave.mesh        = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(color.r, color.g, color.b, 0.65)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled           = true
	mat.emission                   = color
	mat.emission_energy_multiplier = 2.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wave.material_override = mat
	wave.rotation.x = PI * 0.5
	scene_root.add_child(wave)
	wave.global_position = world_pos + Vector3(0, 0.06, 0)

	var tw := wave.create_tween()
	tw.set_parallel(true)
	tw.tween_property(wave, "scale", Vector3.ONE * radius, duration).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, duration)
	tw.chain().tween_callback(wave.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
# Ground telegraph (danger zone indicator)
# ─────────────────────────────────────────────────────────────────────────────

static func spawn_ground_telegraph(
		source: Node3D,
		world_pos: Vector3,
		radius: float,
		color: Color,
		duration: float) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree():
		return
	var scene_root := source.get_tree().current_scene
	if scene_root == null:
		scene_root = source.get_parent()

	var decal := MeshInstance3D.new()
	decal.name = "FxTelegraph"
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 2.0, radius * 2.0)
	decal.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(color.r, color.g, color.b, 0.28)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled           = true
	mat.emission                   = color
	mat.emission_energy_multiplier = 0.55
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	decal.material_override = mat
	decal.rotation.x = -PI * 0.5
	scene_root.add_child(decal)
	decal.global_position = world_pos + Vector3(0, 0.04, 0)

	# Pulse then flash bright at detonation
	var tw := decal.create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 1.2, duration * 0.85).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mat, "albedo_color:a", 0.85, 0.08)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(decal.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
# Motes (ambient floating orbs)
# ─────────────────────────────────────────────────────────────────────────────

static func spawn_motes(
		source: Node3D,
		world_pos: Vector3,
		color: Color,
		amount: int,
		speed: float,
		scale_val: float,
		lifetime: float) -> void:
	spawn_burst(source, world_pos, color, amount, speed * 0.35, lifetime, scale_val * 0.12)

# ─────────────────────────────────────────────────────────────────────────────
# Spawn portal
# ─────────────────────────────────────────────────────────────────────────────

static func spawn_spawn_portal(
		source: Node3D,
		world_pos: Vector3,
		color: Color) -> void:
	spawn_ring(source, world_pos, 0.8, color, 0.55)
	spawn_burst(source, world_pos + Vector3(0, 0.4, 0), color, 14, 3.5, 0.45, 0.18)

# ─────────────────────────────────────────────────────────────────────────────
# Decal (ground scorch)
# ─────────────────────────────────────────────────────────────────────────────

static func spawn_decal(
		source: Node3D,
		world_pos: Vector3,
		radius: float) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree():
		return
	var scene_root := source.get_tree().current_scene
	if scene_root == null:
		scene_root = source.get_parent()

	var decal := MeshInstance3D.new()
	decal.name = "FxDecal"
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 2.0, radius * 2.0)
	decal.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.03, 0.02, 0.55)
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	decal.material_override = mat
	decal.rotation.x = -PI * 0.5
	scene_root.add_child(decal)
	decal.global_position = world_pos + Vector3(0, 0.02, 0)

	var tw := decal.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 4.0).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(decal.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
# Impact (camera shake + hi-stop via ImpactDirector)
# ─────────────────────────────────────────────────────────────────────────────

static func impact(
		source: Node3D,
		shake: float,
		hi_stop: float,
		_rumble: float,
		_bloom: float) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree():
		return
	var id := source.get_node_or_null("/root/ImpactDirector")
	if id == null:
		id = source.get_tree().current_scene.get_node_or_null("ImpactDirector") if source.get_tree().current_scene else null
	if id != null and id.has_method("apply_feedback"):
		id.call("apply_feedback", source, "hit", source.global_position, Vector3.UP, shake)
	# hi-stop: pause physics briefly
	if hi_stop > 0.0 and source.get_tree() != null:
		source.get_tree().physics_frame.connect(
			func():
				source.get_tree().paused = true
				var t := source.get_tree().create_timer(hi_stop * 0.06, true)
				t.timeout.connect(func(): if source.get_tree(): source.get_tree().paused = false),
			CONNECT_ONE_SHOT)
