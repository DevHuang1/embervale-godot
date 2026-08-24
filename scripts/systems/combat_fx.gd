class_name CombatFx
extends Object

## === Combat FX Toolkit ===
## Hit-stop, pooled one-shot GPU particle bursts, scorch decals and
## telegraph rings. All effects parent to the current scene so entity
## transforms never distort them.

static var _pool: Array[GPUParticles3D] = []
static var _quad_mesh: QuadMesh = null
static var _hit_stop_token := 0

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
	fx.amount = amount
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
	mat.emission_sphere_radius = 0.12
	mat.direction = Vector3.UP
	mat.spread = 70.0 if not stretch else 34.0
	mat.initial_velocity_min = speed * 0.4
	mat.initial_velocity_max = speed
	mat.gravity = gravity
	mat.scale_min = 0.55
	mat.scale_max = 1.15
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
	quad.size = Vector2(1.15, 0.17)
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
	# Face the camera so the arc always reads, then tilt it like a swing
	var cam := context.get_viewport().get_camera_3d()
	if cam:
		mi.look_at(cam.global_position)
	mi.rotate_object_local(Vector3(0, 0, 1), randf_range(-0.7, 0.7) + (PI * 0.25 if randf() < 0.5 else -PI * 0.25))
	var tween := mi.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3(1.25, 1.4, 1.0), 0.18)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.22)
	tween.chain().tween_callback(mi.queue_free)

## Pre-impact telegraph: an additive glow shimmer that flares at the strike
## origin during wind-up (~0.25s), warning the eye before the hit lands.
static func spawn_telegraph(context: Node, pos: Vector3,
		color: Color = Color(1.0, 0.84, 0.47)) -> void:
	if context == null or not context.is_inside_tree():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = radial_glow_texture()
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
	tween.tween_property(mi, "scale", Vector3.ONE * 1.45, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(mi.queue_free)

## Weapon trail ribbon: a slash gradient quad that sweeps wide and fades at
## the impact frame of melee hits.
static func spawn_arc_trail(context: Node, pos: Vector3,
		color: Color = Color(1.0, 0.92, 0.7, 0.95)) -> void:
	if context == null or not context.is_inside_tree():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(1.3, 0.42)
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
	mi.scale = Vector3(0.4, 0.4, 1.0)
	var tween := mi.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mi, "scale", Vector3(1.2, 1.2, 1.0), 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.2)
	tween.chain().tween_callback(mi.queue_free)

# === Magic explosion ===
## Staff-style detonation: flash burst + expanding ground ring.
static func spawn_explosion(context: Node, pos: Vector3, color: Color,
		radius: float = 2.6) -> void:
	spawn_burst(context, pos + Vector3(0, 0.6, 0), color, 26, radius * 2.2, 0.45, 0.18)
	spawn_ring(context, pos, radius, Color(color.r, color.g, color.b, 0.8), 0.9)

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
	fx.amount = 40
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
	mat.scale_max = 1.3
	mat.color = color
	mat.color_ramp = _fade_ramp(color)
	fx.process_material = mat
	fx.global_position = pos + Vector3(0, 0.08, 0)
	fx.restart()
	fx.emitting = true

static func _acquire_particle(context: Node) -> GPUParticles3D:
	_pool = _pool.filter(func(p): return is_instance_valid(p))
	for p in _pool:
		if not p.emitting:
			p.global_position = Vector3.ZERO
			return p
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
		material.albedo_texture = radial_glow_texture()
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

# === Scorch decal ===
static func spawn_decal(context: Node, pos: Vector3, radius: float = 0.8,
		color: Color = Color(0.12, 0.07, 0.04, 0.75), duration: float = 6.0,
		ground_y: float = 0.02) -> void:
	if context == null or not context.is_inside_tree():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.albedo_texture = _blob_texture(color)
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	material.disable_receive_shadows = true
	quad.material = material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = quad
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root(context).add_child(mesh_instance)
	mesh_instance.global_position = Vector3(pos.x, pos.y + ground_y, pos.z)
	mesh_instance.rotation.x = -PI / 2.0
	mesh_instance.rotation.z = randf() * TAU
	var tween := mesh_instance.create_tween()
	tween.tween_interval(duration * 0.6)
	tween.tween_property(material, "albedo_color:a", 0.0, duration * 0.4)
	tween.tween_callback(mesh_instance.queue_free)

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