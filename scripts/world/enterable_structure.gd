extends Node3D
class_name EnterableStructure

## === EnterableStructure — the exterior that stands in the realm ===
## Builds one structure's outside from its StructureCatalog entry and owns the
## door the player interacts with. The silhouette differs per kind so a castle,
## a mushroom house and a pyramid never read as the same box, and every solid
## piece gets collision: the player walks up to these, not through them.

const INTERACTION_PROP := preload("res://scripts/world/interaction_prop.gd")

var entry: Dictionary = {}
var _handler: Node = null
var _body: StaticBody3D = null
var _stone: StandardMaterial3D = null
var _trim: StandardMaterial3D = null
var _accent: StandardMaterial3D = null
var _masonry: StandardMaterial3D = null
var _rock: StandardMaterial3D = null
var _thatch: StandardMaterial3D = null
var _door: StaticBody3D = null

func setup(handler: Node, structure: Dictionary, ground_y: float) -> void:
	_handler = handler
	entry = structure
	name = "Structure_%s" % str(structure.get("id", "structure"))
	position = (structure.get("approach", Vector3.ZERO) as Vector3) + Vector3(0.0, ground_y, 0.0)
	_build()

func _build() -> void:
	var palette: Dictionary = entry.get("palette", {})
	var wall_color: Color = palette.get("wall", Color(0.27, 0.25, 0.24))
	var accent_color: Color = palette.get("accent", Color(0.85, 0.45, 0.22))
	var kind := str(entry.get("kind", StructureCatalog.KIND_CASTLE))
	_stone = _material(wall_color.darkened(0.25), 0.08, 0.88)
	_trim = _material(wall_color, 0.10, 0.80)
	_accent = _material(accent_color, 0.30, 0.50)
	# Textured surfaces for the procedural geometry; every one falls back to the
	# flat palette material when the CC0 families are missing.
	_masonry = StructureSurfaces.tinted(StructureSurfaces.STONE, wall_color, 4.0)
	if _masonry == null:
		_masonry = _trim
	_rock = StructureSurfaces.tinted(StructureSurfaces.ROCK, wall_color, 5.0)
	if _rock == null:
		_rock = _stone
	_thatch = StructureSurfaces.tinted(StructureSurfaces.THATCH, accent_color.lightened(0.2), 5.0)
	if _thatch == null:
		_thatch = _accent
	_body = StaticBody3D.new()
	_body.name = "ExteriorCollision"
	add_child(_body)
	match kind:
		StructureCatalog.KIND_MUSHROOM_HOUSE:
			_build_mushroom_house()
		StructureCatalog.KIND_PYRAMID:
			_build_pyramid()
		_:
			_build_castle()
	_build_door()
	_build_nameplate()

func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat

## Castle: a square keep with corner towers, a battlement ring and a lit gate.
## The keep core is a single coherent masonry box: tiling the Kenney Castle Kit
## wall modules required non-uniform scaling that broke the silhouette into a
## scattered, stretched mess. Towers and roof pieces keep their proportions, and
## the collision stays the same single box and tower cylinders as before.
func _build_castle() -> void:
	var keep_size := Vector3(18.0, 10.0, 16.0)
	var keep_center := Vector3(0.0, 5.0, 0.0)
	# Collision first and unchanged: the visual rebuild can never change what the
	# player can walk into.
	_add_box_collision(keep_center, keep_size)
	_add_box("Keep", keep_center, keep_size, _masonry)
	_build_castle_towers()
	_build_castle_battlements()
	_build_castle_gate()

## Alternating merlons around the keep's rim.
func _build_castle_battlements() -> void:
	for index in 8:
		var x := -8.0 + float(index) * (16.0 / 7.0)
		for side in [-1.0, 1.0]:
			_add_box("Merlon_%d_%s" % [index, str(side)],
				Vector3(x, 10.7, side * 8.0), Vector3(1.6, 1.6, 0.9), _masonry)
	for index in 6:
		var z := -7.0 + float(index) * (14.0 / 5.0)
		for side in [-1.0, 1.0]:
			_add_box("MerlonS_%d_%s" % [index, str(side)],
				Vector3(side * 9.0, 10.7, z), Vector3(0.9, 1.6, 1.6), _masonry)

## Lit entry so the keep reads as enterable. The kit door scaled far beyond its
## authored proportions, so a procedural frame replaces it.
func _build_castle_gate() -> void:
	var door_size := Vector3(3.2, 3.4, 0.4)
	var door_center := Vector3(0.0, 1.7, 8.15)
	_add_box("Gate", door_center, door_size, _accent, false)
	# A recessed dark opening so the doorway has depth.
	_add_box("GateVoid", Vector3(0.0, 1.7, 8.25),
		Vector3(2.4, 2.6, 0.25), _stone, false)

## Corner towers stacked from real kit pieces: a base course, three mid courses,
## a top course and a roof, over the same cylinder collision as before.
func _build_castle_towers() -> void:
	for corner in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(1.0, 1.0)]:
		var tower_center := Vector3(corner.x * 8.4, 6.4, corner.y * 7.4)
		_add_cylinder_collision(tower_center, 2.2, 13.0)
		_build_castle_tower(Vector3(tower_center.x, 0.0, tower_center.z),
			"Tower_%s" % str(corner))

func _build_castle_tower(base: Vector3, node_name: String) -> void:
	var width := 2.2
	var course := 2.2
	var y := base.y
	var pieces: Array[Array] = [
		["castle_tower_base", course],
		["castle_tower_mid", course],
		["castle_tower_mid", course],
		["castle_tower_mid", course],
		["castle_tower_top", course * 0.3],
		["castle_tower_roof", course * 2.0],
	]
	for index in pieces.size():
		var piece := str(pieces[index][0])
		var piece_height := float(pieces[index][1])
		StructureKit.add(self, piece,
			Transform3D(Basis.IDENTITY, base + Vector3(0.0, y + piece_height * 0.5, 0.0)),
			Vector3(width, piece_height, width), "%s_%d" % [node_name, index])
		y += piece_height

## Mushroom house: a squat stem under a wide cap, with a lit round door.
func _build_mushroom_house() -> void:
	_add_cylinder("Stem", Vector3(0.0, 2.4, 0.0), 4.4, 4.8, _rock)
	var cap := SphereMesh.new()
	cap.radius = 6.2
	cap.height = 5.4
	cap.radial_segments = 16
	cap.rings = 8
	var cap_node := MeshInstance3D.new()
	cap_node.name = "Cap"
	cap_node.mesh = cap
	cap_node.material_override = _thatch
	cap_node.position = Vector3(0.0, 5.0, 0.0)
	add_child(cap_node)
	_add_sphere_collision(cap_node.position, 6.0)
	# Cap spots, so the silhouette reads as a mushroom and not a dome.
	for index in 7:
		var angle := TAU * float(index) / 7.0
		var spot := SphereMesh.new()
		spot.radius = 0.62
		spot.height = 0.6
		var spot_node := MeshInstance3D.new()
		spot_node.name = "CapSpot_%d" % index
		spot_node.mesh = spot
		spot_node.material_override = _trim
		spot_node.position = Vector3(cos(angle) * 4.2, 6.6, sin(angle) * 4.2)
		add_child(spot_node)
	# Gills: a ring of short posts under the cap edge.
	for index in 10:
		var angle := TAU * float(index) / 10.0
		_add_box("Gill_%d" % index, Vector3(cos(angle) * 4.9, 4.4, sin(angle) * 4.9),
			Vector3(0.7, 1.2, 0.7), _stone)

## Pyramid: stepped tiers shrinking to a capstone, with a sealed entry.
func _build_pyramid() -> void:
	var tiers := 5
	var base := 20.0
	for tier in tiers:
		var shrink := base - float(tier) * 3.2
		var height := 2.6
		_add_box("Tier_%d" % tier, Vector3(0.0, height * (float(tier) + 0.5), 0.0),
			Vector3(shrink, height, shrink), _masonry if tier % 2 == 0 else _rock)
	# Capstone
	_add_cone("Capstone", Vector3(0.0, 2.6 * float(tiers) + 1.1, 0.0), 2.6, 2.6, _accent)
	# A dark entry cut into the lowest tier, framed in accent stone.
	_add_box("EntryFrame", Vector3(0.0, 1.5, base * 0.5 - 0.2),
		Vector3(6.4, 3.0, 0.5), _accent, false)
	_add_box("EntryLeft", Vector3(-3.2, 1.5, base * 0.5 - 0.1), Vector3(1.0, 3.0, 0.6), _stone)
	_add_box("EntryRight", Vector3(3.2, 1.5, base * 0.5 - 0.1), Vector3(1.0, 3.0, 0.6), _stone)
	_add_box("EntryLintel", Vector3(0.0, 3.2, base * 0.5 - 0.1), Vector3(7.4, 0.9, 0.6), _stone)

## The door is its own interactable body in front of the structure, so the
## prompt is reachable without climbing onto the geometry.
func _build_door() -> void:
	_door = INTERACTION_PROP.new()
	_door.name = "StructureDoor"
	_door.position = Vector3(0.0, 0.0, 9.5)
	_door.configure(_handler, "structure", str(entry.get("id", "")),
		str(entry.get("tagline", "ENTER")))
	add_child(_door)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 2.0
	capsule.height = 3.0
	shape.shape = capsule
	shape.position = Vector3(0.0, 1.5, 0.0)
	_door.add_child(shape)
	var label := Label3D.new()
	label.text = str(entry.get("tagline", "ENTER"))
	label.font_size = 34
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 3.2, 0.0)
	label.modulate = Color(1.0, 0.86, 0.52)
	_door.add_child(label)
	# A threshold light so the door is findable at night in a dark realm.
	var glow := OmniLight3D.new()
	glow.name = "DoorGlow"
	glow.position = Vector3(0.0, 2.4, 0.0)
	glow.light_color = _accent.albedo_color
	glow.light_energy = 1.4
	glow.omni_range = 9.0
	_door.add_child(glow)

func _build_nameplate() -> void:
	var label := Label3D.new()
	label.name = "Nameplate"
	label.text = str(entry.get("name", "STRUCTURE"))
	label.font_size = 44
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 15.0, 0.0)
	label.modulate = Color(1.0, 0.88, 0.62)
	add_child(label)

## === Solid geometry helpers ===
## Every visual piece registers its own collision shape on the structure's single
## StaticBody3D: one body, many shapes, no per-prop physics bodies.
## A kit piece fitted to the same box the procedural mesh would use. Returns
## false when the kit has no such piece, so the caller keeps its fallback mesh.
func _add_kit_surface(node_name: String, piece: String, center: Vector3,
		size: Vector3) -> bool:
	return StructureKit.add(self, piece, Transform3D(Basis.IDENTITY, center),
		size, node_name) != null

func _add_box(node_name: String, center: Vector3, size: Vector3, material: Material,
		collide := true) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_node.mesh = mesh
	mesh_node.material_override = material
	mesh_node.position = center
	add_child(mesh_node)
	if collide:
		_add_box_collision(center, size)
	return mesh_node

func _add_cylinder(node_name: String, center: Vector3, radius: float, height: float,
		material: Material) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.92
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh_node.mesh = mesh
	mesh_node.material_override = material
	mesh_node.position = center
	add_child(mesh_node)
	_add_cylinder_collision(center, radius, height)
	return mesh_node

func _add_cone(node_name: String, center: Vector3, radius: float, height: float,
		material: Material) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh_node.mesh = mesh
	mesh_node.material_override = material
	mesh_node.position = center
	add_child(mesh_node)
	_add_cylinder_collision(center, radius, height)
	return mesh_node

func _add_box_collision(center: Vector3, size: Vector3) -> void:
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = center
	_body.add_child(shape_node)

func _add_cylinder_collision(center: Vector3, radius: float, height: float) -> void:
	var shape_node := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape_node.shape = cylinder
	shape_node.position = center
	_body.add_child(shape_node)

func _add_sphere_collision(center: Vector3, radius: float) -> void:
	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape_node.shape = sphere
	shape_node.position = center
	_body.add_child(shape_node)

func door() -> StaticBody3D:
	return _door
