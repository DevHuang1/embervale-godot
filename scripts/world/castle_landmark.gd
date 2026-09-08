extends Node3D
class_name CastleLandmark

## One authored-feeling, mobile-safe exterior landmark for the first vertical
## slice. The interior remains owned by RealmExpansion; this node owns only
## the readable approach, entrance, and castle silhouette.

const INTERACTION_PROP := preload("res://scripts/world/interaction_prop.gd")
const DUNGEON_MODULES: Dictionary = {
	"wall": "res://assets/models/kenney_mini_dungeon/Models/wall.fbx",
	"column": "res://assets/models/kenney_mini_dungeon/Models/column.fbx",
	"banner": "res://assets/models/kenney_mini_dungeon/Models/banner.fbx",
}

var _dungeon_handler: Node = null
var _terrain: Node = null
var _built := false

func setup(dungeon_handler: Node, terrain: Node, world_position: Vector3) -> void:
	_dungeon_handler = dungeon_handler
	_terrain = terrain
	position = world_position
	if not _built:
		_build_castle()
		_built = true

func _surface_y(point: Vector3) -> float:
	if _terrain != null and _terrain.has_method("sample_surface_height"):
		return float(_terrain.call("sample_surface_height", point))
	return point.y

func _material(color: Color, metallic := 0.0, roughness := 0.82) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat

func _box(name: String, size: Vector3, local_position: Vector3, mat: Material,
		collision := true) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_node.mesh = mesh
	mesh_node.material_override = mat
	mesh_node.position = local_position
	add_child(mesh_node)
	if collision:
		var body := StaticBody3D.new()
		body.name = name + "Collision"
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		shape_node.shape = shape
		body.position = local_position
		body.add_child(shape_node)
		add_child(body)
	return mesh_node

func _tower(name: String, local_position: Vector3, stone: Material,
		accent: Material) -> void:
	_box(name + "Base", Vector3(4.2, 5.0, 4.2), local_position + Vector3.UP * 2.5, stone)
	_box(name + "Crown", Vector3(4.8, 0.55, 4.8), local_position + Vector3.UP * 5.15, accent)
	for side in [-1.0, 1.0]:
		_box(name + "Merlon", Vector3(0.65, 0.9, 0.65),
			local_position + Vector3(side * 1.55, 5.82, -1.55), accent)
		_box(name + "Merlon", Vector3(0.65, 0.9, 0.65),
			local_position + Vector3(side * 1.55, 5.82, 1.55), accent)

func _build_castle() -> void:
	add_to_group("structure")
	add_to_group("landmark")
	var stone := _material(Color(0.16, 0.18, 0.19), 0.18, 0.76)
	var trim := _material(Color(0.46, 0.28, 0.10), 0.52, 0.42)
	var ember := _material(Color(0.72, 0.24, 0.06), 0.18, 0.56)
	_box("Courtyard", Vector3(22.0, 0.35, 18.0), Vector3(0, 0.18, 0), stone, false)
	_box("NorthWall", Vector3(22.0, 4.5, 1.2), Vector3(0, 2.25, -8.5), stone)
	_box("SouthWall", Vector3(22.0, 4.5, 1.2), Vector3(0, 2.25, 8.5), stone)
	_box("WestWall", Vector3(1.2, 4.5, 15.8), Vector3(-10.4, 2.25, -0.7), stone)
	_box("EastWall", Vector3(1.2, 4.5, 15.8), Vector3(10.4, 2.25, -0.7), stone)
	_tower("NorthWestTower", Vector3(-9.8, 0, -8.0), stone, trim)
	_tower("NorthEastTower", Vector3(9.8, 0, -8.0), stone, trim)
	_tower("SouthWestTower", Vector3(-9.8, 0, 7.2), stone, trim)
	_tower("SouthEastTower", Vector3(9.8, 0, 7.2), stone, trim)
	_box("Gatehouse", Vector3(6.0, 6.8, 2.0), Vector3(0, 3.4, 8.0), stone)
	_box("GateOpening", Vector3(2.4, 3.8, 2.15), Vector3(0, 1.9, 8.05), ember, false)
	_box("GateHeader", Vector3(7.0, 0.55, 2.5), Vector3(0, 6.7, 8.0), trim)

	var entrance := INTERACTION_PROP.new()
	entrance.name = "EmbervaultCastleEntrance"
	entrance.position = Vector3(0, 0.2, 10.0)
	entrance.configure(_dungeon_handler, "dungeon", "embervault_castle", "ENTER CASTLE")
	add_child(entrance)
	var entrance_shape := CollisionShape3D.new()
	var entrance_box := BoxShape3D.new()
	entrance_box.size = Vector3(3.4, 2.0, 3.0)
	entrance_shape.shape = entrance_box
	entrance.add_child(entrance_shape)

	var label := Label3D.new()
	label.name = "CastleName"
	label.text = "EMBERVAULT CASTLE\nENTER THE ROOT CITADEL"
	label.font_size = 30
	label.outline_size = 8
	label.modulate = Color(1.0, 0.78, 0.38)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 8.2, 7.7)
	add_child(label)

	for module_id in ["column", "banner"]:
		var path := str(DUNGEON_MODULES[module_id])
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var prop := packed.instantiate() as Node3D
		if prop == null:
			continue
		prop.name = "CastleImported_" + module_id
		prop.position = Vector3(-3.5 if module_id == "column" else 0.0,
			0.3 if module_id == "column" else 4.9, 6.5)
		prop.scale = Vector3.ONE * (1.25 if module_id == "column" else 1.0)
		add_child(prop)
