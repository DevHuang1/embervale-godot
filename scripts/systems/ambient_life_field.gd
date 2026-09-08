extends Node3D
class_name AmbientLifeField

## Small, non-gameplay ambient life field. It never participates in physics or
## targeting and is intentionally bounded for Android.

const REALM_COLORS: Dictionary = {
	"whispergrove": Color(1.0, 0.78, 0.34, 1.0),
	"bramblewood": Color(0.92, 0.67, 0.28, 1.0),
	"mistfen": Color(0.49, 0.88, 0.76, 1.0),
	"heartwood": Color(1.0, 0.42, 0.18, 1.0),
	"moonfen": Color(0.52, 0.72, 1.0, 1.0),
}

@export_range(0, 16, 1) var butterfly_cap: int = 8
@export var field_size: Vector3 = Vector3(34.0, 5.0, 34.0)
@export var realm_id: String = "whispergrove"
@export var seed_value: int = 1
var behavior_copy: String = ""
var life_kind: String = "butterflies"

func setup(p_realm_id: String, p_seed: int, p_cap: int = 8) -> void:
	realm_id = p_realm_id
	seed_value = p_seed
	butterfly_cap = clampi(p_cap, 0, 16)
	_apply_realm_behavior()
	_build()

func _ready() -> void:
	if get_child_count() == 0:
		_build()

func _build() -> void:
	for child in get_children():
		child.queue_free()
	if butterfly_cap <= 0:
		return
	var particles := GPUParticles3D.new()
	# Keep the legacy node name: tests and scene tooling use it as the stable
	# ambient-life anchor even when the realm changes the motion style.
	particles.name = "Butterflies"
	particles.amount = butterfly_cap
	particles.lifetime = 12.0
	particles.preprocess = 3.0
	particles.randomness = 0.65
	particles.visibility_aabb = AABB(-field_size * 0.5, field_size)
	particles.local_coords = true
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = field_size * 0.5
	process_material.gravity = Vector3(0.0, 0.05, 0.0)
	process_material.initial_velocity_min = 0.08
	process_material.initial_velocity_max = 0.18
	process_material.scale_min = 0.6
	process_material.scale_max = 1.0
	process_material.color = REALM_COLORS.get(realm_id, REALM_COLORS["whispergrove"])
	if life_kind == "fireflies":
		process_material.gravity = Vector3(0.0, -0.015, 0.0)
		process_material.initial_velocity_min = 0.02
		process_material.initial_velocity_max = 0.08
	particles.process_material = process_material
	var wing := SphereMesh.new()
	wing.radius = 0.14
	wing.height = 0.055
	wing.radial_segments = 5
	wing.rings = 2
	var wing_material := StandardMaterial3D.new()
	wing_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wing_material.albedo_color = REALM_COLORS.get(realm_id, REALM_COLORS["whispergrove"])
	wing_material.emission_enabled = true
	wing_material.emission = wing_material.albedo_color
	wing_material.emission_energy_multiplier = 0.35
	wing.material = wing_material
	particles.draw_pass_1 = wing
	particles.seed = seed_value
	add_child(particles)

func _apply_realm_behavior() -> void:
	var profile: Dictionary = RealmIdentityCatalog.for_realm(realm_id)
	behavior_copy = str(profile.get("ambient_behavior", "Ambient life drifts through the realm"))
	life_kind = "butterflies" if realm_id == "whispergrove" else "fireflies"

func get_behavior_copy() -> String:
	return behavior_copy
