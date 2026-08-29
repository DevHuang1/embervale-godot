class_name TargetMarker
extends Node3D

## === Lantern Mark Indicator ===
## The "marked by your lantern" combat lock, made legible:
##  - a tall beacon of light + ring + foe-flash when a foe is claimed,
##  - a pulsing ground ring + foe-halo while the lock is held,
##  - a thin light-tether from the hero's lantern to the marked foe,
##  - a soft "mark forgotten" cue the moment the lock drops.
## The mark flag itself lives on GameState.enemy_target; every other
## combat refusal copy points here so the state is never invisible.

const MARK_COLOR := Color(1.0, 0.74, 0.30)
const GROUND_LIFT := 0.07
const RAY_UP := 2.0
const RAY_DOWN := 8.0
const RING_INNER := 0.75
const RING_OUTER := 0.95
const GLOW_SIZE := 3.0
const FADE_SPEED := 7.0
const PULSE_HZ := 1.6
const TETHER_THICKNESS := 0.045
const TETHER_TAPER := 0.55   # fires fade toward the foe tip

static var _instance: TargetMarker = null
static var _lantern: Node3D = null

var _ring_mat: StandardMaterial3D
var _ring_mat2: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _halo_quad: MeshInstance3D
var _tether: MeshInstance3D
var _tether_mat: StandardMaterial3D
var _tracked_id := 0
var _fade := 0.0          # 0 hidden .. 1 fully shown
var _pop_t := 1.0         # 0..1 engage pop animation progress
var _was_locked := false  # one-shot release cue guard


## Point the tether at the bearer lantern (hero binds this in _ready).
static func bind_lantern(lantern: Node3D) -> void:
	_lantern = lantern


static func ensure(context: Node) -> TargetMarker:
	if _instance != null and is_instance_valid(_instance) \
			and _instance.is_inside_tree():
		return _instance
	if _instance == null or not is_instance_valid(_instance):
		_instance = TargetMarker.new()
		_instance.name = "LanternTargetMarker"
	if context == null or not context.is_inside_tree():
		return _instance
	var root: Node = context.get_tree().current_scene
	if root == null or _instance.get_parent() == root:
		return _instance
	if _instance.get_parent() != null:
		# Already parented (stale scene): move it under the live one.
		_instance.reparent.call_deferred(root)
	else:
		# Deferred: hero._ready() runs while the world scene is mid
		# instantiation, where an immediate add_child() throws "Parent node
		# is busy setting up children" and the mark ring would never exist.
		root.add_child.call_deferred(_instance)
	return _instance


func _ready() -> void:
	visible = false
	top_level = true  # world-anchored, never inherits a parent transform
	_build_ring()
	_build_ring_second()
	_build_glow()
	_build_halo()
	_build_tether()
	GameState.mark_released.connect(_on_mark_released)


func _build_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = RING_INNER
	torus.outer_radius = RING_OUTER
	torus.rings = 48
	torus.ring_segments = 12
	_ring_mat = _mark_material()
	torus.material = _ring_mat
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Counter-rotating inner ring so the mark reads as "spinning lock".
func _build_ring_second() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = RING_INNER * 0.42
	torus.outer_radius = RING_INNER * 0.52
	torus.rings = 32
	torus.ring_segments = 10
	_ring_mat2 = _mark_material()
	_ring_mat2.albedo_color = Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b, 0.55)
	torus.material = _ring_mat2
	var mi := MeshInstance3D.new()
	mi.name = "RingSpinner"
	mi.mesh = torus
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0.03, 0)
	add_child(mi)


func _mark_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = MARK_COLOR
	mat.disable_receive_shadows = true
	return mat


func _build_glow() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(GLOW_SIZE, GLOW_SIZE)
	_glow_mat = _mark_material()
	_glow_mat.albedo_color = Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b, 0.34)
	_glow_mat.albedo_texture = CombatFx.radial_glow_texture()
	quad.material = _glow_mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.x = -PI / 2.0
	add_child(mi)


## Foe-halo: a billboard flare that rides the marked enemy's chest so the
## lock stays legible even when the ground ring is hidden behind a slope.
func _build_halo() -> void:
	_halo_quad = MeshInstance3D.new()
	_halo_quad.name = "FoeHalo"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_halo_mat = _mark_material()
	_halo_mat.albedo_color = Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b, 0.42)
	_halo_mat.albedo_texture = CombatFx.radial_glow_texture()
	quad.material = _halo_mat
	_halo_quad.mesh = quad
	_halo_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo_quad.visible = false
	add_child(_halo_quad)


## Thin lantern->foe light tether. One tapered cylinder, re-oriented every
## frame; hidden while nothing is marked.
func _build_tether() -> void:
	_tether = MeshInstance3D.new()
	_tether.name = "LanternTether"
	var cyl := CylinderMesh.new()
	cyl.top_radius = TETHER_THICKNESS * TETHER_TAPER
	cyl.bottom_radius = TETHER_THICKNESS
	cyl.height = 1.0
	cyl.radial_segments = 10
	_tether_mat = _mark_material()
	_tether_mat.albedo_color = Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b, 0.34)
	cyl.material = _tether_mat
	_tether.mesh = cyl
	_tether.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tether.visible = false
	add_child(_tether)


func _process(delta: float) -> void:
	var target := _resolve_target()
	if target != null:
		if target.get_instance_id() != _tracked_id:
			_on_target_acquired(target)
		_track(target, delta)
		if not _was_locked:
			_was_locked = true
	else:
		if _was_locked:
			_on_mark_released()
		_tracked_id = 0
		_fade = maxf(0.0, _fade - FADE_SPEED * delta)
	_apply_fade()


func _resolve_target() -> Node3D:
	var t := GameState.enemy_target
	if t == null or not is_instance_valid(t) or not t.is_inside_tree():
		return null
	if t.has_method("is_dead") and t.is_dead():
		return null
	return t


func _on_target_acquired(target: Node3D) -> void:
	_tracked_id = target.get_instance_id()
	_pop_t = 0.0
	_was_locked = true
	var foot := _ground_point(target)
	var chest: Vector3 = target.global_position + Vector3(0, 0.9, 0)
	global_position = foot

	# 1) Beacon of claimed light: a tall lantern column + pop + ground ring.
	CombatFx.spawn_pillar(self, foot, 8.0,
		Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b, 0.68), 0.9, 1.5)
	CombatFx.spawn_core_flash(self, chest,
		Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b, 0.96), 2.1)
	CombatFx.spawn_ring(self, foot, RING_OUTER * 3.2,
		Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b, 0.8), 0.7)
	CombatFx.spawn_shockwave(self, foot, 4.6,
		Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b, 0.7), 0.75)
	CombatFx.spawn_motes(self, chest,
		Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b, 0.85),
		14, 0.8, 1.1, 2.6)

	# 2) Ember spray off the bearer lantern; the swell of the light itself
	# is handled by Hero._on_mark_locked (flare multiplies every frame).
	if _lantern != null and is_instance_valid(_lantern):
		CombatFx.spawn_burst(_lantern, _lantern.global_position,
			Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b, 0.7), 8, 3.2, 0.35, 0.12)

	# 3) Foe flash + announce so the acquire moment is unambiguous.
	_flash_foe_skin(target)
	FloatingText.spawn_on_entity(target, "✦ LIT BY YOUR LANTERN",
		Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b), 1.2)

	# 4) Screen + camera + audio confirmation.
	get_tree().call_group("screen_fx", "pulse_vignette", 0.30)
	CombatFx.impact(self, 0.16, 0.0, 0.5, 0.22)
	AudioManager.play_lantern_lock(target)


func _track(target: Node3D, delta: float) -> void:
	_fade = minf(1.0, _fade + FADE_SPEED * delta)
	_pop_t = minf(1.0, _pop_t + delta / 0.28)
	global_position = _ground_point(target)
	var t := float(Time.get_ticks_msec()) * 0.001
	var breathe := 1.0 + 0.06 * sin(t * TAU * PULSE_HZ)
	var pop := 1.0 + 0.55 * pow(1.0 - _pop_t, 2.0)
	scale = Vector3.ONE * breathe * pop
	rotation.y = t * 0.9
	var spin := 1.0 - t * 2.1
	for child in get_children():
		if child.name == "RingSpinner":
			child.rotation.y = spin
			break
	_track_halo(target, breathe * pop, t)
	_track_tether(target, t)


func _track_halo(target: Node3D, pulse: float, _t: float) -> void:
	_halo_quad.visible = true
	_halo_quad.global_position = target.global_position + Vector3(0, 1.1, 0)
	_halo_quad.scale = Vector3.ONE * pulse
	_halo_mat.albedo_color = Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b,
		0.30 + 0.13 * pulse)


func _track_tether(target: Node3D, t: float) -> void:
	if _lantern == null or not is_instance_valid(_lantern):
		_tether.visible = false
		return
	var a: Vector3 = _lantern.global_position + Vector3(0, -0.1, 0)
	var b: Vector3 = target.global_position + Vector3(0, 0.85, 0)
	var dir := b - a
	var length := dir.length()
	if length < 0.15:
		_tether.visible = false
		return
	_tether.visible = true
	var mid := (a + b) * 0.5
	var y_axis := dir / length
	var ref := Vector3.UP if absf(y_axis.dot(Vector3.UP)) < 0.99 \
		else Vector3.FORWARD
	var z_axis := y_axis.cross(ref).normalized()
	var x_axis := z_axis.cross(y_axis).normalized()
	_tether.global_transform = Transform3D(
		Basis(x_axis, y_axis, z_axis), mid)
	var thrum := 0.9 + 0.15 * (0.5 + 0.5 * sin(t * TAU * PULSE_HZ * 1.5))
	_tether.scale = Vector3(thrum, length, thrum)
	_tether_mat.albedo_color = Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b,
		0.26 + 0.14 * (0.5 + 0.5 * sin(t * TAU * PULSE_HZ)))


## Briefly set any shader-driven enemy skin to lantern-orange flash params
## (silent no-op for enemies without flash shaders).
func _flash_foe_skin(target: Node3D) -> void:
	for mesh in _collect_meshes(target, 6):
		var mat := mesh.material_override as ShaderMaterial
		if mat == null or not mat.shader:
			continue
		if not mat.shader.has_code() \
				or not mat.shader.code.contains("flash_intensity"):
			continue
		mat.set_shader_parameter("flash_color", MARK_COLOR)
		mat.set_shader_parameter("flash_intensity", 1.0)
		var tw := create_tween()
		var m: MeshInstance3D = mesh
		tw.tween_property(mat, "shader_parameter/flash_intensity", 0.0, 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _collect_meshes(node: Node, max_count: int) -> Array:
	var out: Array = []
	var stack: Array = [node]
	var guard := 0
	while not stack.is_empty() and out.size() < max_count and guard < 80:
		guard += 1
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.material_override != null:
			out.append(n)
		for child in n.get_children():
			stack.append(child)
	return out


## Drop a ground probe so the ring hugs terrain relief instead of floating
## when the foe stands on a slope. Falls back to the foe's own origin.
func _ground_point(target: Node3D) -> Vector3:
	var origin: Vector3 = target.global_position + Vector3(0, RAY_UP, 0)
	var space := get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(
				origin, origin - Vector3(0, RAY_DOWN, 0))
		query.collision_mask = 1 << 5  # Environment
		if target is CollisionObject3D:
			query.exclude = [target.get_rid()]
		var hit := space.intersect_ray(query)
		if hit and hit.has("position"):
			return hit.position + Vector3(0, GROUND_LIFT, 0)
	return target.global_position + Vector3(0, GROUND_LIFT, 0)


func _on_mark_released() -> void:
	if not _was_locked:
		return
	_was_locked = false
	_tracked_id = 0
	# Hear + see the lock drop (the ring fade is handled by _process).
	AudioManager.play_lantern_release(_lantern)
	if _lantern != null and is_instance_valid(_lantern):
		FloatingText.spawn(_lantern, _lantern.global_position + Vector3(0, 0.7, 0),
			"Mark lifted", Color(0.85, 0.85, 0.85, 0.8), 0.7)


func _apply_fade() -> void:
	visible = _fade > 0.01
	if not visible:
		if _halo_quad != null:
			_halo_quad.visible = false
		if _tether != null:
			_tether.visible = false
		return
	var t := float(Time.get_ticks_msec()) * 0.001
	var pulse := 0.78 + 0.22 * sin(t * TAU * PULSE_HZ)
	_ring_mat.albedo_color = Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b,
		(0.60 + 0.32 * pulse) * _fade)
	_glow_mat.albedo_color = Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b,
		0.32 * pulse * _fade)
	_ring_mat2.albedo_color = Color(MARK_COLOR.r, MARK_COLOR.g, MARK_COLOR.b,
		0.42 * _fade)