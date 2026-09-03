extends Node3D
class_name WorldGroundComposition

## Mobile-safe secondary environment layer. It composes broad terrain patches,
## shallow ponds, shoreline stones, tree silhouettes, rock clusters and fallen
## wood from a handful of opaque MultiMesh batches. Everything is visual-only:
## navigation and gameplay collision remain owned by the authored world scene.

var realm_id := "bramblewood"
var radius := 60.0
var terrain: Node = null
var rng := RandomNumberGenerator.new()

const PONDS := {
	"whispergrove": [Vector2(25, 14), Vector2(-28, -16)],
	"bramblewood": [Vector2(27, 16), Vector2(-30, -18)],
	"mistfen": [Vector2(-25, 13), Vector2(25, -25), Vector2(28, 11)],
	"heartwood": [],
	"moonfen": [Vector2(-20, 10), Vector2(18, -14), Vector2(2, -24)],
}

func setup(new_realm_id: String, new_seed: int, new_radius: float) -> void:
	realm_id = new_realm_id
	radius = new_radius
	rng.seed = new_seed
	var world := get_parent().get_parent()
	terrain = world.get_node_or_null("Terrain") if world != null else null
	_build_ground_patches()
	_build_ponds_and_shores()
	_build_tree_variety()
	_build_rock_fields()
	_build_deadwood_and_small_props()

static func pond_centers(for_realm: String) -> Array:
	return (PONDS.get(for_realm, []) as Array).duplicate()

func _ground(point: Vector2) -> float:
	if terrain != null and terrain.has_method("height_at"):
		return float(terrain.call("height_at", point.x, point.y))
	return 0.0

func _gameplay_clear(point: Vector2, padding := 0.0) -> bool:
	var profile := RealmLayoutData.profile(realm_id)
	for key in ["checkpoint", "cave", "arena"]:
		var anchor := profile.get(key, Vector3.ZERO) as Vector3
		var clearance := 6.0 if key == "arena" else 3.2
		if point.distance_to(Vector2(anchor.x, anchor.z)) < clearance + padding:
			return false
	for chest_value in profile.get("chests", []):
		var chest := chest_value as Dictionary
		var anchor := chest.get("pos", Vector3.ZERO) as Vector3
		if point.distance_to(Vector2(anchor.x, anchor.z)) < 2.3 + padding:
			return false
	return true

func _build_ground_patches() -> void:
	var patch_mesh := CylinderMesh.new()
	patch_mesh.top_radius = 1.0
	patch_mesh.bottom_radius = 1.0
	patch_mesh.height = 0.035
	patch_mesh.radial_segments = 18
	var sand: Array[Transform3D] = []
	var mud: Array[Transform3D] = []
	var dirt: Array[Transform3D] = []
	var type_order := _patch_type_order()
	for i in 15:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(radius * 0.22, radius * 0.86)
		var point := Vector2(cos(angle), sin(angle)) * distance
		if not _gameplay_clear(point, 1.0):
			continue
		var sx := rng.randf_range(2.4, 5.8)
		var sz := sx * rng.randf_range(0.55, 1.15)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sx, 1.0, sz))
		var transform := Transform3D(basis, Vector3(point.x, _ground(point) + 0.018, point.y))
		match str(type_order[i % type_order.size()]):
			"sand": sand.append(transform)
			"mud": mud.append(transform)
			_: dirt.append(transform)
	_batch("SandPatches", patch_mesh, _surface_material("sand", _sand_tint()), sand, false, radius + 4.0)
	_batch("MudPatches", patch_mesh, _surface_material("clay", _mud_tint(), true), mud, false, radius + 4.0)
	_batch("DirtPatches", patch_mesh, _surface_material("dirt", _dirt_tint()), dirt, false, radius + 4.0)

func _patch_type_order() -> Array[String]:
	match realm_id:
		"mistfen", "moonfen": return ["mud", "mud", "sand", "dirt"]
		"heartwood": return ["dirt", "sand", "dirt", "mud"]
		_: return ["dirt", "sand", "dirt", "mud"]

func _build_ponds_and_shores() -> void:
	var centers := pond_centers(realm_id)
	if centers.is_empty():
		return
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 1.0
	water_mesh.bottom_radius = 1.0
	water_mesh.height = 0.025
	water_mesh.radial_segments = 24
	var shore_mesh := TorusMesh.new()
	shore_mesh.inner_radius = 0.84
	shore_mesh.outer_radius = 1.08
	shore_mesh.rings = 18
	shore_mesh.ring_segments = 5
	var waters: Array[Transform3D] = []
	var shores: Array[Transform3D] = []
	for i in centers.size():
		var point := centers[i] as Vector2
		if point.length() > radius * 0.94 or not _gameplay_clear(point, 0.5):
			continue
		var scale := 2.6 + float(i % 2) * 1.1
		var y := _ground(point)
		var basis := Basis(Vector3.UP, float(i) * 0.83).scaled(Vector3(scale, 1.0, scale * 0.72))
		waters.append(Transform3D(basis, Vector3(point.x, y + 0.055, point.y)))
		shores.append(Transform3D(basis, Vector3(point.x, y + 0.045, point.y)))
	_batch("ShallowPonds", water_mesh, _water_material(), waters, false, radius + 4.0)
	_batch("PondShorelines", shore_mesh, _surface_material("sand", _sand_tint()), shores, false, radius + 4.0)

func _build_tree_variety() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.14
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 3.0
	trunk_mesh.radial_segments = 7
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.0
	crown_mesh.height = 1.35
	crown_mesh.radial_segments = 7
	crown_mesh.rings = 4
	var trunks: Array[Transform3D] = []
	var lower_crowns: Array[Transform3D] = []
	var upper_crowns: Array[Transform3D] = []
	var target_count := 34 if radius < 35.0 else 58
	var attempts := 0
	while trunks.size() < target_count and attempts < target_count * 8:
		attempts += 1
		var point := _random_point(radius * 0.92)
		if point.length() < 13.0 or not _gameplay_clear(point, 1.5) or _near_pond(point, 3.5):
			continue
		var scale := rng.randf_range(0.72, 1.42)
		var lean := rng.randf_range(-0.13, 0.13)
		var rotation := rng.randf() * TAU
		var y := _ground(point)
		var trunk_basis := Basis.from_euler(Vector3(lean, rotation, -lean * 0.55)).scaled(Vector3(scale, scale, scale))
		trunks.append(Transform3D(trunk_basis, Vector3(point.x, y + 1.48 * scale, point.y)))
		var crown_basis := Basis(Vector3.UP, rotation).scaled(Vector3(scale * 1.15, scale, scale * 1.15))
		lower_crowns.append(Transform3D(crown_basis, Vector3(point.x, y + 3.15 * scale, point.y)))
		if attempts % 3 != 0:
			upper_crowns.append(Transform3D(crown_basis.scaled(Vector3(0.72, 0.76, 0.72)),
				Vector3(point.x + lean * 2.0, y + 4.05 * scale, point.y)))
	_batch("VariedTreeTrunks", trunk_mesh, _surface_material("bark", _bark_tint()), trunks, true, radius + 12.0)
	var canopy_mat := _canopy_material()
	_batch("VariedTreeLowerCrowns", crown_mesh, canopy_mat, lower_crowns, true, radius + 12.0)
	_batch("VariedTreeUpperCrowns", crown_mesh, canopy_mat, upper_crowns, true, radius + 12.0)

func _build_rock_fields() -> void:
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.55
	rock_mesh.height = 0.72
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 4
	var rocks: Array[Transform3D] = []
	for cluster in 12:
		var center := _random_point(radius * 0.88)
		if not _gameplay_clear(center, 1.0) or _near_pond(center, 1.0):
			continue
		for item in rng.randi_range(3, 7):
			var point := center + _random_point(rng.randf_range(1.1, 3.2))
			var scale := rng.randf_range(0.45, 1.55)
			var basis := Basis.from_euler(Vector3(rng.randf_range(-0.2, 0.2),
				rng.randf() * TAU, rng.randf_range(-0.2, 0.2))).scaled(
					Vector3(scale, scale * rng.randf_range(0.45, 0.8), scale))
			rocks.append(Transform3D(basis,
				Vector3(point.x, _ground(point) - 0.08 * scale, point.y)))
	_batch("AuthoredRockFields", rock_mesh, _surface_material("rock", _rock_tint()), rocks, true, radius + 8.0)

func _build_deadwood_and_small_props() -> void:
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 0.16
	log_mesh.bottom_radius = 0.22
	log_mesh.height = 2.3
	log_mesh.radial_segments = 7
	var logs: Array[Transform3D] = []
	for i in 22:
		var point := _random_point(radius * 0.9)
		if point.length() < 10.0 or not _gameplay_clear(point, 0.8):
			continue
		var basis := Basis.from_euler(Vector3(PI * 0.5 + rng.randf_range(-0.14, 0.14),
			rng.randf() * TAU, rng.randf_range(-0.12, 0.12))).scaled(
				Vector3.ONE * rng.randf_range(0.7, 1.25))
		logs.append(Transform3D(basis, Vector3(point.x, _ground(point) + 0.16, point.y)))
	_batch("FallenDeadwood", log_mesh, _surface_material("wood", _bark_tint().lightened(0.08)), logs, true, radius + 8.0)

func _batch(batch_name: String, mesh: Mesh, material: Material, transforms: Array[Transform3D],
		shadows: bool, visible_to: float) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	multimesh.custom_aabb = AABB(Vector3(-radius - 8, -3, -radius - 8),
		Vector3((radius + 8) * 2, 14, (radius + 8) * 2))
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = batch_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = visible_to
	add_child(instance)

func _surface_material(family: String, tint: Color, wet := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var root := "res://assets/textures/stylized/%s" % family
	material.albedo_texture = load("%s/albedo.png" % root)
	material.normal_enabled = true
	material.normal_texture = load("%s/normal.png" % root)
	material.roughness_texture = load("%s/roughness.png" % root)
	material.albedo_color = tint
	material.roughness = 0.44 if wet else 0.88
	material.uv1_scale = Vector3(1.8, 1.8, 1.8)
	return material

func _water_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = _water_tint()
	material.metallic = 0.18
	material.roughness = 0.12
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _canopy_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = _canopy_tint()
	material.roughness = 0.92
	return material

func _random_point(max_radius: float) -> Vector2:
	var angle := rng.randf() * TAU
	var distance := sqrt(rng.randf()) * max_radius
	return Vector2(cos(angle), sin(angle)) * distance

func _near_pond(point: Vector2, padding: float) -> bool:
	for center_value in pond_centers(realm_id):
		if point.distance_to(center_value as Vector2) < 4.8 + padding:
			return true
	return false

func _sand_tint() -> Color:
	return Color(0.72, 0.64, 0.44) if realm_id != "moonfen" else Color(0.38, 0.34, 0.52)

func _mud_tint() -> Color:
	return {"mistfen": Color(0.36, 0.43, 0.45), "moonfen": Color(0.22, 0.20, 0.36),
		"heartwood": Color(0.34, 0.16, 0.09)}.get(realm_id, Color(0.34, 0.28, 0.18))

func _dirt_tint() -> Color:
	return {"heartwood": Color(0.28, 0.12, 0.06), "moonfen": Color(0.20, 0.14, 0.30),
		"mistfen": Color(0.25, 0.30, 0.29)}.get(realm_id, Color(0.34, 0.25, 0.14))

func _rock_tint() -> Color:
	return {"mistfen": Color(0.48, 0.55, 0.57), "heartwood": Color(0.30, 0.22, 0.18),
		"moonfen": Color(0.28, 0.24, 0.40)}.get(realm_id, Color(0.43, 0.45, 0.38))

func _bark_tint() -> Color:
	return {"heartwood": Color(0.20, 0.10, 0.07), "moonfen": Color(0.20, 0.14, 0.28),
		"mistfen": Color(0.23, 0.27, 0.27)}.get(realm_id, Color(0.29, 0.20, 0.12))

func _canopy_tint() -> Color:
	return {"whispergrove": Color(0.16, 0.38, 0.20), "bramblewood": Color(0.12, 0.26, 0.13),
		"mistfen": Color(0.15, 0.28, 0.26), "heartwood": Color(0.30, 0.15, 0.07),
		"moonfen": Color(0.18, 0.13, 0.38)}.get(realm_id, Color(0.14, 0.28, 0.15))

func _water_tint() -> Color:
	return {"mistfen": Color(0.30, 0.45, 0.50, 0.74), "moonfen": Color(0.18, 0.38, 0.58, 0.78)}.get(
		realm_id, Color(0.25, 0.42, 0.38, 0.70))
