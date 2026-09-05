extends Node

## === Combat FX Toolkit ===
class_name CombatFx
## Hit-stop, pooled one-shot GPU particle bursts, scorch decals and
## telegraph rings. All effects parent to the current scene so entity
## transforms never distort them.

static var _pool: Array[GPUParticles3D] = []
static var _quad_mesh: QuadMesh = null
static var _hit_stop_token := 0

# === Centralized quality/budget center ===
# Every pooled emitter, ribbon trail and transient light reads live budget
# knobs from the active QualityScaler at spawn time, so existing hero,
# enemy, boss, elemental-status and skill call sites inherit tier budgets
# automatically without touching their call sites. LOW keeps the same
# anticipation/hit timing with fewer transparent layers.

static var _qual_scaler: QualityScaler = null
static var _transient_lights: Array[Node] = []
static var _vfx_sprite_cache: Dictionary = {}

static func _quality() -> QualityScaler:
	if _qual_scaler == null or not is_instance_valid(_qual_scaler):
		var loop := Engine.get_main_loop() as SceneTree
		if loop == null or loop.root == null:
			return null
		_qual_scaler = loop.root.get_node_or_null(
			"/root/WorldState/QualityScaler") as QualityScaler
	return _qual_scaler

## Particle-count multiplier per tier (LOW 0.45 / MEDIUM 0.72 / HIGH 1.0).
static func _density() -> float:
	var q := _quality()
	return q.vfx_density if q else 1.0

## Density-scaled emitter amount with a hard floor so LOW hits still read.
static func _budget_amount(amount: int) -> int:
	return maxi(3, int(round(float(amount) * _density())))

## Pooled emitter cap (QualityScaler.vfx_pool_limit; 24 HIGH, 10 LOW).
static func _pool_limit() -> int:
	var q := _quality()
	return q.vfx_pool_limit if q else 24

## Live ribbon/trail cap (QualityScaler.vfx_trail_limit; 12 HIGH, 6 LOW).
static func _trail_limit() -> int:
	var q := _quality()
	return q.vfx_trail_limit if q else MAX_TRAIL_RIBBONS

## Transient impact-light budget (3 HIGH, 0 medium/low).
static func _transient_budget() -> int:
	var q := _quality()
	return q.transient_light_budget if q else 0

## Renderer-neutral sprite lookup for the generated vfx set (spark, smoke,
## crescent, impact_star, distortion, ring). Kept in a static cache.
static func sprite_texture(name: String) -> Texture2D:
	if _vfx_sprite_cache.has(name):
		var cached = _vfx_sprite_cache[name]
		if is_instance_valid(cached):
			return cached
	var tex: Texture2D = load("res://assets/textures/generated/vfx/%s.png" % name)
	if tex != null:
		_vfx_sprite_cache[name] = tex
	return tex

## Short-lived local impact light, High-tier garnish only. Returns null when
## the tier budget is exhausted (LOW/MEDIUM set transient_light_budget = 0),
## keeping transient lights capped and self-cleaning on every platform.
static func spawn_impact_light(context: Node, pos: Vector3,
		color: Color = Color(1.0, 0.9, 0.7), energy: float = 2.2,
		range_radius: float = 4.0, duration: float = 0.22) -> OmniLight3D:
	if context == null or not context.is_inside_tree():
		return null
	var budget := _transient_budget()
	if budget <= 0:
		return null
	_transient_lights = _transient_lights.filter(
		func(n): return is_instance_valid(n))
	if _transient_lights.size() >= budget:
		return null
	var light := OmniLight3D.new()
	light.name = "ImpactLight"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_radius
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	_fx_root(context).add_child(light)
	light.global_position = pos
	_transient_lights.append(light)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(light.queue_free)
	return light

# === Hit-stop ===
static func hit_stop(context: Node, duration: float = 0.06, time_scale: float = 0.05) -> void:
	if context == null or not context.is_inside_tree():
		return
	if Engine.time_scale < 0.99:
		return  # kill-cam or another stop owns the clock
	_hit_stop_token += 1
	var token := _hit_stop_token
	Engine.time_scale = time_scale
	var timer := context.get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(func():
		if token == _hit_stop_token:
			Engine.time_scale = 1.0)

# === Pooled GPU burst ===
static func spawn_burst(context: Node, pos: Vector3, color: Color, amount: int = 16,
		speed: float = 5.0, lifetime: float = 0.45, size: float = 0.14,
		stretch: bool = false, gravity: Vector3 = Vector3(0, -3.5, 0)) -> void:
	if context == null or not context.is_inside_tree():
		return
	var fx := _acquire_particle(context)
	fx.amount = _budget_amount(amount)
	fx.lifetime = lifetime
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.local_coords = false
	# Velocity-aligned quads read as directional sparks when elongated
	if stretch:
		fx.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	else:
		fx.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.17
	mat.direction = Vector3.UP
	mat.spread = 70.0 if not stretch else 34.0
	mat.initial_velocity_min = speed * 0.4
	mat.initial_velocity_max = speed
	mat.gravity = gravity
	mat.scale_min = 0.75
	mat.scale_max = 1.5
	mat.color = color
	mat.color_ramp = _fade_ramp(color)
	fx.process_material = mat
	fx.global_position = pos
	fx.restart()
	fx.emitting = true

static func spawn_stretched_burst(context: Node, pos: Vector3, color: Color,
		amount: int = 14, speed: float = 8.0, lifetime: float = 0.35) -> void:
	spawn_burst(context, pos, color, amount, speed, lifetime, 0.14, true)

# === Slash arc ===
static var _slash_tex_cache: GradientTexture2D = null

static func _slash_texture() -> GradientTexture2D:
	if _slash_tex_cache == null or not is_instance_valid(_slash_tex_cache):
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0))
		grad.add_point(0.28, Color(1, 1, 1, 0.9))
		grad.add_point(0.5, Color(1, 1, 1, 1))
		grad.add_point(0.72, Color(1, 1, 1, 0.9))
		grad.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill_from = Vector2(0.0, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 16
		_slash_tex_cache = tex
	return _slash_tex_cache

## A bright sword-slash beam that flares and fades at the impact point.
static func spawn_slash(context: Node, pos: Vector3,
		color: Color = Color(1.0, 0.92, 0.7, 0.95)) -> void:
	if context == null or not context.is_inside_tree():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(1.8, 0.26)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = sprite_texture("crescent")
	material.albedo_color = color
	material.disable_receive_shadows = true
	quad.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root(context).add_child(mi)
	mi.global_position = pos
	# Face the camera so the arc always reads, then tilt it like a swing
	var cam := context.get_viewport().get_camera_3d()
	if cam:
		mi.look_at(cam.global_position)
	mi.rotate_object_local(Vector3(0, 0, 1), randf_range(-0.7, 0.7) + (PI * 0.25 if randf() < 0.5 else -PI * 0.25))
	var tween := mi.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3(1.7, 1.8, 1.0), 0.20)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(mi.queue_free)

## Pre-impact telegraph at a strike origin during wind-up. Friendly
## anticipation uses the warm additive glow; `protected` switches to a
## non-blooming, high-contrast ring sprite (MIX blend, elevated render
## priority) so enemy danger cues stay readable beneath friendly FX, fog and
## screen post-processing. Exempt from density budgeting — must always spawn.
## Returns the mesh so callers/tests can inspect the readability layer.
static func spawn_telegraph(context: Node, pos: Vector3,
		color: Color = Color(1.0, 0.84, 0.47),
		protected: bool = false) -> MeshInstance3D:
	if context == null or not context.is_inside_tree():
		return null
	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 0.85)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if protected:
		# Non-blooming readability layer: MIX blend ring sprite at elevated
		# render priority, exempt from the additive spectacle stack.
		material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		material.albedo_texture = sprite_texture("ring")
		material.render_priority = 48
	else:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.albedo_texture = radial_glow_texture()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = color
	material.disable_receive_shadows = true
	quad.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.name = "TelegraphProtected" if protected else "Telegraph"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root(context).add_child(mi)
	mi.global_position = pos
	var tween := mi.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3.ONE * 1.9, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(mi.queue_free)
	return mi


## Ground-hugging danger telegraph ring for enemy/boss AoE warnings. MIX
## blend, unshaded, near-solid and elevated render priority so it never
## blooms into the additive spectacle layers or gets lost behind fog. Pulsing
## scale + fade-out at the end of the warning window (hit timing unchanged).
static func spawn_ground_telegraph(context: Node, pos: Vector3, radius: float,
		color: Color = Color(1.0, 0.16, 0.08),
		duration: float = 0.6, thickness: float = 0.14) -> MeshInstance3D:
	if context == null or not context.is_inside_tree():
		return null
	var torus := TorusMesh.new()
	torus.inner_radius = radius
	torus.outer_radius = radius + thickness
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, 0.62)
	material.render_priority = 48
	material.disable_receive_shadows = true
	torus.material = material
	var mi := MeshInstance3D.new()
	mi.name = "GroundTelegraph"
	mi.mesh = torus
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root(context).add_child(mi)
	mi.global_position = pos + Vector3(0, 0.10, 0)
	mi.rotation.x = -PI / 2.0
	# Breathe without blinking: a gentle pulse that never passes visual
	# blackout, then a clean fade + free at the end of the warning window.
	var pulse := mi.create_tween().set_loops()
	pulse.tween_property(mi, "scale", Vector3.ONE * 1.05, duration * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(mi, "scale", Vector3.ONE, duration * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	var fade := mi.create_tween()
	fade.tween_interval(duration * 0.7)
	fade.tween_property(material, "albedo_color:a", 0.0, duration * 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade.chain().tween_callback(mi.queue_free)
	return mi

## Weapon trail ribbon: a slash gradient quad that sweeps wide and fades at
## the impact frame of melee hits.
static func spawn_arc_trail(context: Node, pos: Vector3,
		color: Color = Color(1.0, 0.92, 0.7, 0.95)) -> void:
	if context == null or not context.is_inside_tree():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 0.6)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _slash_texture()
	material.albedo_color = color
	material.disable_receive_shadows = true
	quad.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root(context).add_child(mi)
	mi.global_position = pos
	var cam := context.get_viewport().get_camera_3d()
	if cam:
		mi.look_at(cam.global_position)
	mi.rotate_object_local(Vector3(0, 0, 1), randf_range(-0.9, 0.9))
	mi.scale = Vector3(0.5, 0.5, 1.0)
	var tween := mi.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3(1.6, 1.6, 1.0), 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.28)
	tween.chain().tween_callback(mi.queue_free)

# === Skill ribbon trails ===
# A tapered additive ribbon is cheaper than a trail of individual MeshInstance3D
# segments, while still giving bolts and dashes a readable motion silhouette.
const MAX_TRAIL_RIBBONS := 12
static var _trail_ribbons: Array = []

static func _track_trail_ribbon(node: Node3D) -> void:
	_trail_ribbons = _trail_ribbons.filter(func(item): return is_instance_valid(item))
	if _trail_ribbons.size() >= _trail_limit():
		var oldest = _trail_ribbons.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	_trail_ribbons.append(node)

static func spawn_skill_ribbon(context: Node, from_pos: Vector3, to_pos: Vector3,
		color: Color, width: float = 0.34, duration: float = 0.28) -> void:
	if context == null or not context.is_inside_tree():
		return
	var travel := to_pos - from_pos
	var length := travel.length()
	if length < 0.12:
		return
	var direction := travel / length
	var side := Vector3.UP.cross(direction)
	if side.length_squared() < 0.01:
		var camera := context.get_viewport().get_camera_3d()
		side = camera.global_transform.basis.x if camera else Vector3.RIGHT
	side = side.normalized()
	var half_length := length * 0.5
	var half_width := width * 0.5
	var vertices := PackedVector3Array([
		-direction * half_length - side * half_width * 0.16,
		-direction * half_length + side * half_width * 0.16,
		direction * half_length - side * half_width,
		direction * half_length + side * half_width,
	])
	var indices := PackedInt32Array([0, 1, 2, 2, 1, 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var ribbon_mesh := ArrayMesh.new()
	ribbon_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.disable_receive_shadows = true
	ribbon_mesh.surface_set_material(0, material)
	var ribbon := MeshInstance3D.new()
	ribbon.name = "SkillRibbon"
	ribbon.mesh = ribbon_mesh
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ribbon.extra_cull_margin = 2.0
	_fx_root(context).add_child(ribbon)
	ribbon.global_position = (from_pos + to_pos) * 0.5
	ribbon.scale = Vector3(0.82, 0.82, 0.82)
	_track_trail_ribbon(ribbon)
	var tween := ribbon.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ribbon, "scale", Vector3.ONE, duration * 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ribbon.queue_free)

	# A narrower white-hot core improves readability without another particle pass.
	var core := MeshInstance3D.new()
	core.name = "SkillRibbonCore"
	core.mesh = ribbon_mesh.duplicate()
	var core_material := material.duplicate() as StandardMaterial3D
	core_material.albedo_color = Color(1.0, 0.96, 0.86, minf(color.a + 0.16, 1.0))
	(core.mesh as ArrayMesh).surface_set_material(0, core_material)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.scale = Vector3(0.72, 0.72, 0.72)
	_fx_root(context).add_child(core)
	core.global_position = (from_pos + to_pos) * 0.5
	_track_trail_ribbon(core)
	var core_tween := core.create_tween()
	core_tween.set_parallel(true)
	core_tween.tween_property(core, "scale", Vector3.ONE, duration * 0.24)
	core_tween.tween_property(core_material, "albedo_color:a", 0.0, duration * 0.72)
	core_tween.chain().tween_callback(core.queue_free)

# Vibrant trail accents: a short sequence of velocity-aligned bursts with
# a hot-to-colored gradient. Segment count stays deliberately small for mobile.
static func spawn_vibrant_trail(context: Node, from_pos: Vector3, to_pos: Vector3,
		primary: Color, secondary: Color, segments: int = 6) -> void:
	if context == null or not context.is_inside_tree():
		return
	var count := clampi(segments, 2, 8)
	for index in range(count):
		var t := float(index) / float(maxi(count - 1, 1))
		var point := from_pos.lerp(to_pos, t)
		var tint := primary.lerp(secondary, t)
		spawn_stretched_burst(context, point,
			Color(tint.r, tint.g, tint.b, 0.82 - t * 0.16), 3, 3.4 + t * 2.4, 0.28)
		if index % 2 == 0:
			spawn_motes(context, point, Color(secondary.r, secondary.g, secondary.b, 0.48),
				2, 0.14, 0.34, 1.1)

# === Magic bolt: a glowing orb that flies from→to with a spark trail ===
static func spawn_bolt(context: Node, from_pos: Vector3, to_pos: Vector3,
		color: Color = Color(0.96, 0.62, 0.22), flight_time: float = 0.28,
		size: float = 0.3) -> void:
	if context == null or not context.is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size * 0.5
	sphere.height = size
	sphere.radial_segments = 16
	sphere.rings = 8
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.disable_receive_shadows = true
	sphere.material = material
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root(context).add_child(mi)
	mi.global_position = from_pos
	spawn_vibrant_trail(context, from_pos, to_pos, color,
		Color(1.0, 0.96, 0.78, 0.95), 6)
	spawn_skill_ribbon(context, from_pos, to_pos,
		Color(color.r, color.g, color.b, minf(color.a + 0.12, 1.0)), size * 0.95, flight_time * 1.15)
	# Spark trail shed along the flight path
	var emit_tween := mi.create_tween()
	emit_tween.tween_method(func(t: float):
		if not is_instance_valid(mi):
			return
		spawn_burst(context, mi.global_position, Color(color.r, color.g, color.b, 0.55),
			2, 1.6, 0.24, size * 0.42, false, Vector3.ZERO),
		0.0, 1.0, flight_time)
	var tween := mi.create_tween()
	tween.tween_property(mi, "global_position", to_pos, flight_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(mi, "scale", Vector3.ONE * 0.4, flight_time)
	tween.tween_callback(func():
		if is_instance_valid(mi):
			spawn_burst(context, mi.global_position, color, 10, 4.5, 0.3, size * 0.4)
			mi.queue_free())

## Vertical light pillar: an additive billboard column that flares and thins.
static func spawn_pillar(context: Node, pos: Vector3, height: float = 2.6,
		color: Color = Color(0.75, 0.95, 0.55, 0.7), duration: float = 0.6,
		width: float = 0.9) -> void:
	if context == null or not context.is_inside_tree():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = _pillar_texture()
	material.albedo_color = color
	material.disable_receive_shadows = true
	quad.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root(context).add_child(mi)
	mi.global_position = pos + Vector3(0, height * 0.5, 0)
	mi.scale = Vector3(0.25, 0.7, 1.0)
	var tween := mi.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3(1.0, 1.0, 1.0), duration * 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(mi.queue_free)

static var _pillar_tex_cache: GradientTexture2D = null

## Tall soft-edged gradient for light pillars (bright core, feathered sides).
static func _pillar_texture() -> GradientTexture2D:
	if _pillar_tex_cache == null or not is_instance_valid(_pillar_tex_cache):
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 0))
		grad.add_point(0.35, Color(1, 1, 1, 0.85))
		grad.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill_from = Vector2(0.5, 0.0)
		tex.fill_to = Vector2(0.5, 1.0)
		tex.width = 32
		tex.height = 128
		_pillar_tex_cache = tex
	return _pillar_tex_cache

# === Rising motes: weightless sparks drifting upward (heals, auras, embers)
static func spawn_motes(context: Node, pos: Vector3, color: Color,
		amount: int = 20, radius: float = 1.0, lifetime: float = 0.9,
		rise_speed: float = 1.6) -> void:
	if context == null or not context.is_inside_tree():
		return
	var fx := _acquire_particle(context)
	fx.amount = _budget_amount(amount)
	fx.lifetime = lifetime
	fx.one_shot = true
	fx.explosiveness = 0.0   # gentle stream, not a pop
	fx.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = radius
	mat.direction = Vector3.UP
	mat.spread = 18.0
	mat.initial_velocity_min = rise_speed * 0.6
	mat.initial_velocity_max = rise_speed
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.45
	mat.scale_max = 1.0
	mat.color = color
	mat.color_ramp = _fade_ramp(color)
	fx.process_material = mat
	fx.global_position = pos
	fx.restart()
	fx.emitting = true

## Treasure reveal: a short gold-and-element burst for one-shot chest rewards.
static func spawn_chest_open(context: Node, pos: Vector3, color: Color) -> void:
	if context == null or not context.is_inside_tree():
		return
	spawn_core_flash(context, pos + Vector3(0, 0.8, 0), Color(1.0, 0.92, 0.62, 0.96), 1.4)
	spawn_burst(context, pos + Vector3(0, 0.5, 0), Color(1.0, 0.72, 0.24, 0.9), 20, 5.8, 0.55, 0.18)
	spawn_motes(context, pos + Vector3(0, 0.7, 0), Color(color.r, color.g, color.b, 0.78), 12, 0.65, 0.9, 2.2)
	spawn_ring(context, pos, 1.15, Color(color.r, color.g, color.b, 0.7), 0.55)

## Elemental status pulse: small, local, and visually distinct from a damage hit.

static func spawn_status_pulse(context: Node3D, element: String, applied: bool = true) -> void:
	if context == null or not context.is_inside_tree():
		return
	var colors := {
		"fire": Color(1.0, 0.25, 0.06, 0.9),
		"frost": Color(0.34, 0.82, 1.0, 0.9),
		"shock": Color(0.72, 0.44, 1.0, 0.9),
		"nature": Color(0.30, 1.0, 0.42, 0.9),
	}
	var tint: Color = colors.get(element, Color.WHITE)
	var pos := context.global_position + Vector3(0, 0.45, 0)
	spawn_ring(context, context.global_position, 0.72 if applied else 0.52,
		Color(tint.r, tint.g, tint.b, 0.68), 0.34)
	spawn_motes(context, pos, Color(tint.r, tint.g, tint.b, 0.72),
		6 if applied else 3, 0.32, 0.42, 1.4)
	if applied:
		spawn_core_flash(context, pos, Color(1.0, 0.96, 0.82, 0.78), 0.62)

## Elemental reaction: a stronger one-shot flash when two statuses collide.
static func spawn_status_reaction(context: Node3D, reaction: String, color: Color) -> void:
	if context == null or not context.is_inside_tree():
		return
	var pos := context.global_position + Vector3(0, 0.65, 0)
	spawn_shockwave(context, context.global_position, 1.2, Color(color.r, color.g, color.b, 0.82), 0.36)
	spawn_burst(context, pos, Color(color.r, color.g, color.b, 0.92), 18, 5.8, 0.42, 0.16)
	spawn_core_flash(context, pos, Color(1.0, 0.98, 0.88, 0.92), 1.25)
	FloatingText.spawn_on_entity(context, reaction.to_upper(), color, 0.88)

## Expanding shockwave: a ground-hugging ring of light that races outward.
static func spawn_shockwave(context: Node, pos: Vector3, radius: float = 4.0,
		color: Color = Color(1.0, 0.84, 0.47, 0.9), duration: float = 0.5) -> void:
	if context == null or not context.is_inside_tree():
		return
	var inner := TorusMesh.new()
	inner.inner_radius = 0.86
	inner.outer_radius = 1.0
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.disable_receive_shadows = true
	inner.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = inner
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root(context).add_child(mi)
	mi.global_position = pos + Vector3(0, 0.12, 0)
	mi.scale = Vector3(0.15, 1.0, 0.15)
	var tween := mi.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3(radius, 1.0, radius), duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(mi.queue_free)

## Sustained charge glow at a cast origin: swells over `charge_time` then pops.
## Returns the MeshInstance3D so callers can free it early on interrupt.
static func spawn_charge_glow(context: Node, pos: Vector3,
		color: Color = Color(1.0, 0.9, 0.72), charge_time: float = 0.4,
		end_scale: float = 1.6) -> MeshInstance3D:
	if context == null or not context.is_inside_tree():
		return null
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	sphere.radial_segments = 12
	sphere.rings = 6
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, 0.75)
	material.disable_receive_shadows = true
	sphere.material = material
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root(context).add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tween := mi.create_tween()
	tween.tween_property(mi, "scale", Vector3.ONE * end_scale, charge_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(mi, "global_position",
		pos + Vector3(0, 0.12, 0), charge_time)
	tween.tween_callback(func():
		if is_instance_valid(mi):
			spawn_burst(context, mi.global_position, color, 8, 3.0, 0.26, 0.11)
			mi.queue_free())
	return mi

# === Magic explosion ===
## Staff-style detonation: flash burst + expanding ground ring.
static func spawn_explosion(context: Node, pos: Vector3, color: Color,
		radius: float = 2.6) -> void:
	spawn_burst(context, pos + Vector3(0, 0.6, 0), color, 26, radius * 2.2, 0.45, 0.18)
	spawn_ring(context, pos, radius, Color(color.r, color.g, color.b, 0.8), 0.9)

## Spawn portal: a flat churning glyph (double ring) with a quick vertical
## light pillar, so an enemy materializing in reads clearly before it acts.
static func spawn_spawn_portal(context: Node, pos: Vector3, color: Color,
		duration: float = 0.6, height: float = 2.2) -> void:
	if context == null or not context.is_inside_tree():
		return
	spawn_ring(context, pos, 1.5, Color(color.r, color.g, color.b, 0.85), duration)
	spawn_ring(context, pos, 0.55, Color(color.r, color.g, color.b, 0.9), duration * 0.5)
	spawn_pillar(context, pos, height, Color(color.r, color.g, color.b, 0.4),
		duration * 0.7, 1.0)
	spawn_burst(context, pos + Vector3(0, 0.3, 0),
		Color(color.r, color.g, color.b, 0.7), 16, 3.2, duration, 0.16)

# === Impact director: coordinates shake + hit-stop + screen chroma ===
static func impact(context: Node, shake: float = 0.0, hitstop_duration: float = 0.0,
		hitstop_scale: float = 0.08, chroma: float = 0.0) -> void:
	if shake > 0.0:
		var rig := _find_camera_rig(context)
		if rig and rig.has_method("add_shake"):
			rig.add_shake(shake)
	if hitstop_duration > 0.0:
		hit_stop(context, hitstop_duration, hitstop_scale)
	if chroma > 0.0:
		var sfx := _find_screen_fx(context)
		if sfx and sfx.has_method("punch_chroma"):
			sfx.punch_chroma(chroma)
	# Single choke point: every coordinated hit feeds the world's tension
	if context != null and context.is_inside_tree():
		var ws := context.get_node_or_null("/root/WorldState")
		if ws != null and ws.has_method("notify_impact"):
			ws.notify_impact(0.10 + chroma * 0.3)

static func _find_camera_rig(context: Node) -> Node:
	var scene := _fx_root(context)
	return scene.get_node_or_null("CameraRig") if scene else null

static func _find_screen_fx(context: Node) -> Node:
	return _fx_root(context).get_tree().get_first_node_in_group("screen_fx")

static func spawn_ring(context: Node, pos: Vector3, radius: float, color: Color,
		duration: float = 1.2) -> void:
	if context == null or not context.is_inside_tree():
		return
	var fx := _acquire_particle(context)
	fx.amount = _budget_amount(40)
	fx.lifetime = duration
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3.UP
	mat.emission_ring_radius = radius
	mat.emission_ring_inner_radius = maxf(radius - 0.25, 0.0)
	mat.emission_ring_height = 0.05
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.7
	mat.scale_max = 1.5
	mat.color = color
	mat.color_ramp = _fade_ramp(color)
	fx.process_material = mat
	fx.global_position = pos + Vector3(0, 0.08, 0)
	fx.restart()
	fx.emitting = true

# === Core flash: a white-hot pop at the payload point so EVERY rite's
# moment-of-execution reads instantly, even at the zoomed-out camera ===
static func spawn_core_flash(context: Node, pos: Vector3,
		color: Color = Color(1.0, 0.97, 0.90), size: float = 1.6) -> void:
	if context == null or not context.is_inside_tree():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = sprite_texture("impact_star")
	material.albedo_color = color
	material.disable_receive_shadows = true
	quad.material = material
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root(context).add_child(mi)
	mi.global_position = pos
	var tween := mi.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3.ONE * 2.3, 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.30) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(mi.queue_free)

static func _acquire_particle(context: Node) -> GPUParticles3D:
	_pool = _pool.filter(func(p): return is_instance_valid(p))
	for p in _pool:
		if not p.emitting:
			p.global_position = Vector3.ZERO
			return p
	# Pool hygiene: tier cap so burst-heavy fights never grow unbounded
	if _pool.size() >= _pool_limit():
		var steal: GPUParticles3D = _pool[0]
		_pool.append(_pool.pop_front())
		return steal
	var fx := GPUParticles3D.new()
	fx.draw_pass_1 = _get_quad_mesh()
	fx.visibility_aabb = AABB(Vector3(-24, -8, -24), Vector3(48, 16, 48))
	_fx_root(context).add_child(fx)
	_pool.append(fx)
	return fx

static func _get_quad_mesh() -> QuadMesh:
	if _quad_mesh == null or not is_instance_valid(_quad_mesh):
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2(0.14, 0.14)
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.disable_receive_shadows = true
		material.albedo_texture = sprite_texture("spark")
		_quad_mesh.material = material
	return _quad_mesh

static var _ramp_cache: Dictionary = {}

static var _glow_tex: GradientTexture2D = null

## Soft radial sprite shared by every quad-based particle (fireflies,
## mist, sparks). Replaces the hard-edged square quads.
static func radial_glow_texture(size: int = 64) -> Texture2D:
	if _glow_tex == null or not is_instance_valid(_glow_tex):
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.add_point(0.45, Color(1, 1, 1, 0.55))
		grad.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = size
		tex.height = size
		_glow_tex = tex
	return _glow_tex

static func _fade_ramp(color: Color) -> GradientTexture1D:
	var key := color.to_html()
	if _ramp_cache.has(key):
		return _ramp_cache[key]
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.9))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	_ramp_cache[key] = tex
	return tex

static func _fx_root(node: Node) -> Node:
	var scene := node.get_tree().current_scene
	return scene if scene else node.get_tree().root

# === Ground impact mark ===
# Procedural clipped scorch + branching fissures. The shader discards outside
# its irregular radial boundary, so the supporting quad cannot appear as a
# square on compatibility/mobile renderers.
static func spawn_decal(context: Node, pos: Vector3, radius: float = 0.8,
		color: Color = Color(0.92, 0.5, 0.2, 0.55), duration: float = 2.4,
		ground_y: float = 0.06, style: String = "burn") -> void:
	if context == null or not context.is_inside_tree():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/ground_impact.gdshader")
	material.set_shader_parameter("impact_color", color)
	material.set_shader_parameter("char_color", Color(0.045, 0.022, 0.015, 0.82))
	material.set_shader_parameter("seed", fmod(absf(pos.x * 1.73 + pos.z * 2.41), 17.0) + 1.0)
	material.set_shader_parameter("crack_amount", 1.0 if style == "crack" else 0.72)
	material.set_shader_parameter("burn_amount", 0.28 if style == "crack" else 0.88)
	quad.material = material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = quad
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root(context).add_child(mesh_instance)
	mesh_instance.global_position = Vector3(pos.x, pos.y + ground_y, pos.z)
	# Lay flat just above terrain; random rotation makes repeated hits distinct.
	mesh_instance.rotation.x = -PI / 2.0
	mesh_instance.rotation.z = randf() * TAU
	mesh_instance.scale = Vector3(0.6, 0.6, 1.0)
	var tween := mesh_instance.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh_instance, "scale",
		Vector3(1.0, 1.0, 1.0), duration * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(value: float):
		if is_instance_valid(material):
			material.set_shader_parameter("fade", value), 1.0, 0.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(mesh_instance.queue_free)

static var _blob_tex_cache: Dictionary = {}

static func _blob_texture(color: Color) -> ImageTexture:
	var key := color.to_html()
	if _blob_tex_cache.has(key):
		return _blob_tex_cache[key]
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - center, y - center).length() / center
			var a := clampf(1.0 - smoothstep(0.35, 1.0, d + randf_range(-0.08, 0.08)), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	var tex := ImageTexture.create_from_image(img)
	_blob_tex_cache[key] = tex
	return tex
