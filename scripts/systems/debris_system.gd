class_name DebrisSystem
extends Node

## === Chaos-style impact debris ===
## Pooled RigidBody3D shards that burst from impacts, bounce off the
## environment, settle, then shrink back into the pool. Tier-capped by
## QualityScaler.debris_max (HIGH 24 / MEDIUM 12 / LOW 6). Bodies collide
## ONLY with the environment layer so they never shove characters.

enum Style { ROCK, WOOD, LEAF, CRYSTAL, CERAMIC }

const STYLE_NAMES := {
	"rock": Style.ROCK,
	"wood": Style.WOOD,
	"leaf": Style.LEAF,
	"crystal": Style.CRYSTAL,
	"ceramic": Style.CERAMIC,
}

const LIFETIME := 3.2
const FADE_TIME := 0.38
const POOL_WARM := 8

# Environment layer is bit 6 (value 32) in project.godot layer names;
# debris lives on an unnamed spare layer and masks only environment.
const LAYER_DEBRIS := 1 << 6
const MASK_ENVIRONMENT := 1 << 5

var _pool: Array[RigidBody3D] = []
var _active: Array[Dictionary] = []   # [{body, age, style}]
var _meshes: Array[Mesh] = []
var _mats: Array[StandardMaterial3D] = []
var _phys: PhysicsMaterial
var _warmed := false
## Tests inject a scaler here; production resolves via the parent WorldState.
var quality_override: QualityScaler


func _ready() -> void:
	_phys = PhysicsMaterial.new()
	_phys.bounce = 0.34
	_phys.friction = 0.85
	_build_style_assets()


func _build_style_assets() -> void:
	var prism := PrismMesh.new()
	prism.size = Vector3(0.14, 0.1, 0.12)
	var splinter := BoxMesh.new()
	splinter.size = Vector3(0.05, 0.05, 0.26)
	var leaf := BoxMesh.new()
	leaf.size = Vector3(0.13, 0.012, 0.09)
	var shard := PrismMesh.new()
	shard.size = Vector3(0.07, 0.2, 0.07)
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.09, 0.06, 0.08)
	_meshes = [prism, splinter, leaf, shard, chunk]

	_mats = [
		_std_mat(Color(0.36, 0.33, 0.28)),          # rock chip
		_std_mat(Color(0.42, 0.30, 0.17)),          # wood splinter
		_std_mat(Color(0.22, 0.34, 0.13), 0.9),     # leaf bit
		_glow_mat(Color(0.5, 0.85, 1.0)),           # crystal shard
		_std_mat(Color(0.62, 0.45, 0.32)),          # ceramic chunk
	]


func _std_mat(color: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _glow_mat(color: Color) -> StandardMaterial3D:
	var m := _std_mat(color.darkened(0.25))
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.6
	return m


func quality() -> QualityScaler:
	if quality_override != null:
		return quality_override
	var ws := get_parent()
	return ws.quality if ws != null and "quality" in ws else null


func _cap() -> int:
	var q := quality()
	return q.debris_max if q != null else 24


## Burst of shards at a world position. dir biases the spray (UP works
## well when no hit normal is known); count clamps to the tier cap.
func spawn_burst(origin: Vector3, dir: Vector3, style: String,
		count: int) -> void:
	if not _warmed:
		_warm_pool()
	var kind: int = STYLE_NAMES.get(style, Style.ROCK)
	count = clampi(count, 0, maxi(_cap() - _active.size(), 0))
	for i in count:
		var body := _acquire()
		if body == null:
			return
		_apply_style(body, kind)
		body.global_position = origin \
			+ Vector3(randf_range(-0.14, 0.14), randf_range(0.02, 0.16),
				randf_range(-0.14, 0.14))
		var spread := Vector3(randf_range(-1.4, 1.4), randf_range(0.4, 1.6),
			randf_range(-1.4, 1.4))
		body.linear_velocity = dir.normalized() * randf_range(2.0, 3.6) \
			+ spread + Vector3.UP * randf_range(0.8, 2.0)
		body.angular_velocity = Vector3(
			randf_range(-11.0, 11.0), randf_range(-11.0, 11.0),
			randf_range(-11.0, 11.0))
		_active.append({"body": body, "age": 0.0})


func _warm_pool() -> void:
	_warmed = true
	for i in POOL_WARM:
		_pool.append(_make_body())


func _make_body() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = LAYER_DEBRIS
	body.collision_mask = MASK_ENVIRONMENT
	body.physics_material_override = _phys
	body.gravity_scale = 1.45
	body.continuous_cd = false
	body.contact_monitor = false
	body.visible = false
	var mi := MeshInstance3D.new()
	mi.name = "Shard"
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 0.055
	body.add_child(shape)
	add_child(body)
	return body


func _apply_style(body: RigidBody3D, kind: int) -> void:
	var mi := body.get_node("Shard") as MeshInstance3D
	if mi != null:
		mi.mesh = _meshes[kind]
		mi.material_override = _mats[kind]
		mi.scale = Vector3.ONE


func _acquire() -> RigidBody3D:
	for i in _pool.size():
		var cand := _pool[i]
		if not cand.visible:
			_set_shard_scale(cand, 1.0)
			cand.show()
			return cand
	if _pool.size() < _cap():
		var fresh := _make_body()
		_pool.append(fresh)
		fresh.show()
		return fresh
	# Pool exhausted at cap: recycle the oldest active shard
	while not _active.is_empty():
		var oldest: Dictionary = _active.pop_front()
		var body := oldest.body as RigidBody3D
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		_set_shard_scale(body, 1.0)
		return body
	return null


func _process(delta: float) -> void:
	if _active.is_empty():
		return
	var cap := maxi(_cap(), 1)
	var keep: Array[Dictionary] = []
	for entry in _active:
		var body := entry.body as RigidBody3D
		entry.age = float(entry.age) + delta
		var age := float(entry.age)
		# Oldest-first overflow retires early when the tier cap shrinks
		if age >= LIFETIME or (keep.size() >= cap and age > 0.6):
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			_set_shard_scale(body, 1.0)
			body.hide()
			continue
		if LIFETIME - age < FADE_TIME:
			_set_shard_scale(body, maxf((LIFETIME - age) / FADE_TIME, 0.01))
		keep.append(entry)
	_active = keep


func _set_shard_scale(body: RigidBody3D, s: float) -> void:
	var mi := body.get_node_or_null("Shard") as MeshInstance3D
	if mi != null:
		mi.scale = Vector3.ONE * s


## Scene teardown: park every shard instantly (called by WorldState).
func reset() -> void:
	for entry in _active:
		var body := entry.body as RigidBody3D
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.hide()
	_active.clear()
