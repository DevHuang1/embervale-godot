extends Hushling
class_name RealmArchetypeEnemy

## Scene-backed versions of the reusable realm combat profiles. Keeping one
## behavior implementation avoids five near-identical AI scripts while each
## scene still has an explicit identity, stats, silhouette accent and spawn id.

@export var display_name := "Realm Creature"
@export var accent_color := Color(0.7, 0.8, 0.6)
@export var silhouette_kind := "horns"
@export var profile_sfx := "grave_moss"

func _ready() -> void:
	var selected_profile := archetype
	configure_archetype(selected_profile)
	sfx_profile = profile_sfx
	super._ready()
	_build_identity_silhouette()
	var health_bar := get_node_or_null("EnemyHealthBar")
	if health_bar != null and "display_name" in health_bar:
		health_bar.set("display_name", display_name)

func _build_identity_silhouette() -> void:
	if visual == null:
		return
	var material := (preload("res://assets/materials/entity_hushling.tres") as ShaderMaterial).duplicate(false)
	material.set_shader_parameter("base_color", accent_color.darkened(0.58))
	material.set_shader_parameter("rim_color", accent_color)
	material.set_shader_parameter("emission_color", accent_color)
	material.set_shader_parameter("emission_energy", 0.38)
	material.set_shader_parameter("roughness", 0.76)
	material.set_shader_parameter("normal_mix", 0.48)
	material.set_shader_parameter("variation_seed", randf())
	match silhouette_kind:
		"horns":
			for side in [-1.0, 1.0]:
				_add_cone(Vector3(0.27 * side, 0.52, -0.02), Vector3(0, 0, -0.35 * side), material, 0.48)
		"fins":
			for side in [-1.0, 1.0]:
				var fin := MeshInstance3D.new()
				var prism := PrismMesh.new()
				prism.size = Vector3(0.5, 0.12, 0.42)
				fin.mesh = prism
				fin.position = Vector3(0.42 * side, 0.05, 0)
				fin.rotation.z = 0.55 * side
				fin.material_override = material
				visual.add_child(fin)
		"shield":
			var shield := MeshInstance3D.new()
			var shield_mesh := CylinderMesh.new()
			shield_mesh.top_radius = 0.34
			shield_mesh.bottom_radius = 0.34
			shield_mesh.height = 0.10
			shield_mesh.radial_segments = 7
			shield.mesh = shield_mesh
			shield.position = Vector3(0.46, 0.05, 0.28)
			shield.rotation.z = PI * 0.5
			shield.material_override = material
			visual.add_child(shield)
		"crown":
			for i in 5:
				var angle := lerpf(-0.9, 0.9, float(i) / 4.0)
				_add_cone(Vector3(sin(angle) * 0.28, 0.48, cos(angle) * 0.12), Vector3.ZERO, material, 0.38)
		"maw":
			for side in [-1.0, 1.0]:
				_add_cone(Vector3(0.16 * side, 0.2, 0.42), Vector3(PI * 0.5, 0, 0), material, 0.32)

func _add_cone(pos: Vector3, rot: Vector3, material: Material, height: float) -> void:
	var spike := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.07
	mesh.height = height
	mesh.radial_segments = 5
	spike.mesh = mesh
	spike.position = pos
	spike.rotation = rot
	spike.material_override = material
	visual.add_child(spike)
