extends Area3D
class_name BossProjectile

## Authoritative boss projectile. CombatFx remains presentation-only; this
## node owns the collision, damage, lifetime, and cleanup contract.

const PROJECTILE_GROUP := "boss_projectile"
const MAX_ACTIVE := 24
const DEFAULT_LIFETIME := 4.0

var owner_boss: Node3D = null
var damage := 1
var element := ""
var ability_id := "boss_projectile"
var visual_family := "boss_projectile_trail"
var _direction := Vector3.FORWARD
var _speed := 9.0
var _life_left := DEFAULT_LIFETIME
var _spent := false
var _color := Color(1.0, 0.45, 0.12)
var _radius := 0.22

static func spawn(parent: Node, boss: Node3D, from_pos: Vector3,
		to_pos: Vector3, payload_damage: int, color: Color,
		payload_element: String = "", payload_speed: float = 9.0,
		payload_lifetime: float = DEFAULT_LIFETIME,
		payload_ability_id: String = "boss_projectile",
		payload_vfx_family: String = "boss_projectile_trail") -> BossProjectile:
	if parent == null or not parent.is_inside_tree():
		return null
	var active := parent.get_tree().get_nodes_in_group(PROJECTILE_GROUP).size()
	if active >= MAX_ACTIVE:
		return null
	var projectile := BossProjectile.new()
	projectile.owner_boss = boss
	projectile.visual_family = payload_vfx_family if not payload_vfx_family.is_empty() \
		else "boss_projectile_trail"
	parent.add_child(projectile)
	projectile.global_position = from_pos
	projectile._configure(to_pos, payload_damage, color, payload_element,
		payload_speed, payload_lifetime, payload_ability_id, payload_vfx_family)
	return projectile

func _ready() -> void:
	add_to_group(PROJECTILE_GROUP)
	collision_layer = 1 << 2
	collision_mask = 1 << 0
	monitoring = true
	monitorable = true
	var shape_node := CollisionShape3D.new()
	shape_node.name = "ProjectileShape"
	var shape := SphereShape3D.new()
	shape.radius = _radius
	shape_node.shape = shape
	add_child(shape_node)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_build_visual()
	if owner_boss != null and is_instance_valid(owner_boss):
		owner_boss.tree_exiting.connect(_on_owner_exiting)

func _configure(to_pos: Vector3, payload_damage: int, color: Color,
		payload_element: String, payload_speed: float, payload_lifetime: float,
		payload_ability_id: String, payload_vfx_family: String) -> void:
	damage = maxi(1, payload_damage)
	element = payload_element
	ability_id = payload_ability_id
	visual_family = payload_vfx_family if not payload_vfx_family.is_empty() \
		else "boss_projectile_trail"
	_color = color
	_speed = clampf(payload_speed, 2.0, 24.0)
	_life_left = clampf(payload_lifetime, 0.20, 6.0)
	_direction = global_position.direction_to(to_pos)
	if _direction.length_squared() < 0.001:
		_direction = -global_transform.basis.z
	_direction = _direction.normalized()
	look_at(global_position + _direction, Vector3.UP)
	_update_visual_color()

func _build_visual() -> void:
	var profile: Dictionary = _visual_profile()
	var core_scale := float(profile.get("core_scale", 1.0))
	var trail_scale := float(profile.get("trail_scale", 1.0))
	var trail_length := float(profile.get("trail_length", 3.2))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "ProjectileVisual"
	var sphere := SphereMesh.new()
	sphere.radius = _radius * core_scale
	sphere.height = _radius * 2.0 * core_scale
	sphere.radial_segments = 10
	sphere.rings = 5
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = _color
	material.emission_enabled = true
	material.emission = _color
	material.emission_energy_multiplier = 1.8
	sphere.material = material
	mesh_instance.mesh = sphere
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	var trail := MeshInstance3D.new()
	trail.name = "ProjectileTrailCore"
	var trail_mesh := SphereMesh.new()
	trail_mesh.radius = _radius * 0.30 * trail_scale
	trail_mesh.height = _radius * trail_length
	trail_mesh.radial_segments = 8
	trail_mesh.rings = 4
	var trail_material := material.duplicate() as StandardMaterial3D
	trail_material.albedo_color = Color(_color.r, _color.g, _color.b, 0.58)
	trail_material.emission = _color
	trail_material.emission_energy_multiplier = 1.25
	trail_mesh.material = trail_material
	trail.mesh = trail_mesh
	trail.rotation.x = PI * 0.5
	trail.position = Vector3(0, 0, 0.26)
	trail.scale = Vector3(0.72, 0.72, 1.0)
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)
	_add_family_detail(profile, material)
	_update_visual_color()

func _visual_profile() -> Dictionary:
	match visual_family:
		"boss_seed_spiral":
			return {"core_scale": 0.78, "trail_scale": 0.72, "trail_length": 2.8,
				"ring_radius": 0.34, "ring_tube": 0.035, "orbit_count": 2}
		"boss_magma_mortar":
			return {"core_scale": 1.24, "trail_scale": 1.20, "trail_length": 4.8,
				"ring_radius": 0.26, "ring_tube": 0.055, "orbit_count": 0}
		"boss_ash_mortar":
			return {"core_scale": 0.92, "trail_scale": 1.42, "trail_length": 5.6,
				"ring_radius": 0.42, "ring_tube": 0.032, "orbit_count": 0}
		"boss_tide_bolt":
			return {"core_scale": 0.88, "trail_scale": 0.64, "trail_length": 3.6,
				"ring_radius": 0.46, "ring_tube": 0.028, "orbit_count": 0}
		"boss_oracle_split":
			return {"core_scale": 0.70, "trail_scale": 0.54, "trail_length": 2.4,
				"ring_radius": 0.24, "ring_tube": 0.03, "orbit_count": 2}
		"boss_lunar_breath":
			return {"core_scale": 1.34, "trail_scale": 1.55, "trail_length": 5.8,
				"ring_radius": 0.58, "ring_tube": 0.07, "orbit_count": 0}
		"boss_orbit_barrage":
			return {"core_scale": 0.82, "trail_scale": 0.90, "trail_length": 4.0,
				"ring_radius": 0.66, "ring_tube": 0.035, "orbit_count": 2}
		_:
			return {"core_scale": 1.0, "trail_scale": 1.0, "trail_length": 3.2,
				"ring_radius": 0.0, "ring_tube": 0.0, "orbit_count": 0}

func _add_family_detail(profile: Dictionary, base_material: StandardMaterial3D) -> void:
	var ring_radius := float(profile.get("ring_radius", 0.0))
	if ring_radius > 0.0:
		var ring := MeshInstance3D.new()
		ring.name = "ProjectileFamilyRing"
		var torus := TorusMesh.new()
		torus.inner_radius = ring_radius * 0.78
		torus.outer_radius = ring_radius
		torus.ring_segments = 10
		torus.rings = 4
		torus.material = base_material.duplicate() as StandardMaterial3D
		ring.mesh = torus
		ring.rotation.x = PI * 0.5
		ring.scale = Vector3(1.0, 1.0, 0.72)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
	var satellite_count := int(profile.get("orbit_count", 0))
	for index in range(satellite_count):
		var satellite := MeshInstance3D.new()
		satellite.name = "ProjectileFamilyOrb_%d" % index
		var orb := SphereMesh.new()
		orb.radius = _radius * 0.18
		orb.height = _radius * 0.36
		orb.radial_segments = 6
		orb.rings = 3
		orb.material = base_material.duplicate() as StandardMaterial3D
		satellite.mesh = orb
		var angle := TAU * float(index) / float(maxi(1, satellite_count))
		satellite.position = Vector3(cos(angle), sin(angle), 0.0) * _radius * 1.10
		satellite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(satellite)

func _update_visual_color() -> void:
	var visual := get_node_or_null("ProjectileVisual") as MeshInstance3D
	if visual != null and visual.mesh is SphereMesh:
		var sphere := visual.mesh as SphereMesh
		sphere.material.albedo_color = _color
		sphere.material.emission = _color
	var trail := get_node_or_null("ProjectileTrailCore") as MeshInstance3D
	if trail != null and trail.mesh is SphereMesh:
		var trail_mesh := trail.mesh as SphereMesh
		var trail_material := trail_mesh.material as StandardMaterial3D
		if trail_material != null:
			trail_material.albedo_color = Color(_color.r, _color.g, _color.b, 0.58)
			trail_material.emission = _color
	for detail in get_children():
		var mesh_detail := detail as MeshInstance3D
		if mesh_detail == null or mesh_detail.mesh == null:
			continue
		var detail_material := mesh_detail.get_active_material(0) as StandardMaterial3D
		if detail_material != null:
			detail_material.albedo_color = Color(_color.r, _color.g, _color.b, 0.72)
			detail_material.emission = _color

func _physics_process(delta: float) -> void:
	if _spent or not is_inside_tree():
		return
	_life_left -= delta
	if _life_left <= 0.0:
		_expire()
		return
	global_position += _direction * _speed * delta

func _on_body_entered(body: Node3D) -> void:
	_hit_target(body)

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("player_hitbox"):
		_hit_target(area.get_parent() as Node3D)

func _hit_target(target: Node3D) -> void:
	if _spent or target == null or not is_instance_valid(target) \
			or target == owner_boss:
		return
	if not target.is_in_group("player") and not target.has_method("take_damage"):
		return
	_spent = true
	set_deferred("monitoring", false)
	var knockback := global_position.direction_to(target.global_position)
	if target.has_method("notify_enemy_strike"):
		target.notify_enemy_strike(owner_boss, damage, ability_id)
	else:
		target.take_damage(damage, knockback)
	if target.has_method("apply_elemental_status") and not element.is_empty():
		target.apply_elemental_status(element, 1)
	CombatFx.spawn_burst(self, global_position, _color, 8, 3.5, 0.28, 0.14)
	_expire()

func _on_owner_exiting() -> void:
	_expire()

func _expire() -> void:
	if not _spent:
		_spent = true
	queue_free()
