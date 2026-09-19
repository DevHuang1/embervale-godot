extends Node3D
class_name StructureInterior

## === StructureInterior — generated enterable interior ===
## Builds a walkable interior from a StructureCatalog entry: a floor plan of
## platforms joined by real stairs, walls with full collision, one lighting
## profile per room, guard spawns, an optional boss, a reward chest and the
## exit back to the realm surface.
##
## Everything is data-driven, so a new structure gets rooms, stairs, lighting,
## mobs and a boss without a new scene. The interior is built once on entry and
## freed on exit, and every node it adds lives under this node — one owner, one
## cleanup path.

signal completed(structure_id: String)
signal boss_defeated(structure_id: String)

const ENEMY_SCENE: PackedScene = preload("res://scenes/entities/hushling.tscn")
const BOSS_SCENE: PackedScene = preload("res://scenes/entities/boss_articulated.tscn")
const INTERACTION_PROP := preload("res://scripts/world/interaction_prop.gd")

## Walls, floors and steps share one collision body per interior: many shapes,
## one broadphase entry, which is what keeps this cheap on Android.
var _body: StaticBody3D = null
var _entry: Dictionary = {}
var _handler: Node = null
var _wall_material: StandardMaterial3D = null
var _floor_material: StandardMaterial3D = null
var _accent_material: StandardMaterial3D = null
var _boss: Node3D = null
## Tiled kit surfaces on Medium/High; a single scaled piece on Low. Tiering may
## only change presentation cost, never the layout or the collision.
var _kit_tiled := true
## The roof of the room the player occupies is hidden in third person so the
## camera frames the room instead of looking at a slab; in first person (the
## camera rides at the hero's head) every roof stays visible and nothing
## changes. Collision is never touched: the roof stays solid, which is what
## keeps the spring arm under the roofline instead of climbing out to stare at
## the tops of the neighbouring rooms.
##
## Hiding is latched: a roof opens when an occupant enters a room and only
## closes once they are clearly outside it, because a hero or camera resting on
## a boundary jitters by centimetres and would otherwise strobe the roof.
const CEILING_ENTER_MARGIN := 0.4
const CEILING_EXIT_MARGIN := 1.6
## Once open, a roof cannot close for this long even after its occupant has
## left the exit margin.
const CEILING_HOLD_SECONDS := 0.6
## A camera further than this from the hero is the orbiting third-person rig
## rather than the first-person head camera.
const THIRD_PERSON_CAMERA_GAP := 1.5
## Per-room roof meshes, grouped by the room index encoded in their names.
var _ceiling_visuals: Array[Array] = []
## Room indices whose roofs are open, mapped to the remaining hold time.
var _open_rooms: Dictionary = {}

func setup(handler: Node, entry: Dictionary) -> void:
	_handler = handler
	_entry = entry
	name = "Interior_%s" % str(entry.get("id", "structure"))

## Builds the whole interior and returns the player's entry position.
func build() -> Vector3:
	if _entry.is_empty():
		return Vector3.ZERO
	var scaler := get_node_or_null("/root/QualityScaler")
	if scaler != null:
		_kit_tiled = int(scaler.get("level")) >= 1
	_build_materials()
	_body = StaticBody3D.new()
	_body.name = "InteriorCollision"
	# Player layer + environment layer: the third-person spring arm only
	# collides with the environment layer, so interior walls and ceilings must
	# carry it or the camera stays outside the room looking at a wall.
	_body.collision_layer = (1 << 0) | (1 << 5)
	add_child(_body)
	_build_rooms()
	_build_lights()
	_build_title()
	_build_exit()
	_build_encounter()
	_collect_ceiling_visuals()
	return _entry.get("spawn", Vector3(0.0, 0.4, 0.0)) as Vector3

## Third person: hide the roofs of the rooms the hero and camera occupy.
## First person: leave every roof alone. Collision is never toggled.
func _process(delta: float) -> void:
	if _ceiling_visuals.is_empty():
		return
	var active := _rooms_occupied_by_third_person(delta)
	for index in _ceiling_visuals.size():
		var hide := active.has(index)
		for visual in _ceiling_visuals[index]:
			if visual.visible == hide:
				visual.visible = not hide

## Returns the rooms whose roofs should be hidden this frame. Empty whenever the
## camera is the first-person head camera, or there is no camera at all.
func _rooms_occupied_by_third_person(delta: float) -> Dictionary:
	var hero := _find_hero()
	var camera := _find_camera()
	# Horizontal gap, not 3D distance: the first-person camera sits at the head,
	# which is still metres above the hero node's feet.
	if hero == null or camera == null or _horizontal_gap(camera, hero) \
			< THIRD_PERSON_CAMERA_GAP:
		_open_rooms = {}
		return {}
	var inside := _rooms_at(hero.global_position, CEILING_ENTER_MARGIN, 0.4)
	inside.merge(_rooms_at(camera.global_position, CEILING_ENTER_MARGIN, 0.4))
	var near := _rooms_at(hero.global_position, CEILING_EXIT_MARGIN, 1.6)
	near.merge(_rooms_at(camera.global_position, CEILING_EXIT_MARGIN, 1.6))
	var active := {}
	var held := {}
	for index in _open_rooms:
		var grace := maxf(0.0, float(_open_rooms[index]) - delta)
		if near.has(index) or grace > 0.0:
			active[index] = true
			held[index] = grace
	for index in inside:
		active[index] = true
		held[index] = CEILING_HOLD_SECONDS
	_open_rooms = held
	return active

## Planar distance between two nodes: view mode is told apart by how far the
## camera orbits, not by the head-height difference the camera has anyway.
func _horizontal_gap(a: Node3D, b: Node3D) -> float:
	var delta := a.global_position - b.global_position
	return Vector2(delta.x, delta.z).length()

func _find_hero() -> Node3D:
	if _handler != null and is_instance_valid(_handler):
		var world := _handler.get("_world") as Node
		if world != null:
			return world.get_node_or_null("Hero") as Node3D
	return get_tree().get_first_node_in_group("hero") as Node3D

func _find_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport != null:
		return viewport.get_camera_3d()
	return null

## A point occupies a room when it is within the room's horizontal footprint
## (grown by margin_xz) and at or above its floor, up to margin_top over it.
func _rooms_at(point: Vector3, margin_xz: float, margin_top: float) -> Dictionary:
	var result := {}
	var rooms: Array = _entry.get("rooms", [])
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		var origin: Vector3 = room.get("offset", Vector3.ZERO)
		var size: Vector3 = room.get("size", Vector3.ZERO)
		var in_xz := absf(point.x - origin.x) <= size.x * 0.5 + margin_xz \
			and absf(point.z - origin.z) <= size.z * 0.5 + margin_xz
		# A stair room's floor is its landing, but the flight below it belongs
		# to the room too, so a hero mid-climb still owns its roof.
		var low := origin.y
		if str(room.get("kind", "")) == StructureCatalog.ROOM_STAIRS and index > 0:
			low = minf(origin.y, float((rooms[index - 1] as Dictionary)
				.get("offset", Vector3.ZERO).y))
		var in_y := point.y >= low - 0.6 and point.y <= origin.y + size.y + margin_top
		if in_xz and in_y:
			result[index] = true
	return result

## Groups every roof mesh (procedural slab, or a kit piece named as one) by the
## room index encoded in its name.
func _collect_ceiling_visuals() -> void:
	_ceiling_visuals.clear()
	var rooms: Array = _entry.get("rooms", [])
	_ceiling_visuals.resize(rooms.size())
	for index in rooms.size():
		_ceiling_visuals[index] = []
	for child in get_children():
		if not (child is MeshInstance3D):
			continue
		var name_str := str(child.name)
		var index := -1
		if name_str.begins_with("Ceiling_"):
			index = _extract_leading_index(name_str, "Ceiling_")
		elif name_str.begins_with("KitCeiling_"):
			index = _extract_leading_index(name_str, "KitCeiling_")
		if index >= 0 and index < _ceiling_visuals.size():
			_ceiling_visuals[index].append(child as MeshInstance3D)

func _extract_leading_index(name_str: String, prefix: String) -> int:
	var rest := name_str.trim_prefix(prefix)
	var split_at := rest.find("_")
	var number := rest if split_at < 0 else rest.left(split_at)
	return int(number) if number.is_valid_int() else -1

func _build_materials() -> void:
	var palette: Dictionary = _entry.get("palette", {})
	var wall_color: Color = palette.get("wall", Color(0.26, 0.24, 0.23))
	var floor_color: Color = palette.get("floor", Color(0.18, 0.17, 0.16))
	# Textured CC0 surfaces where the kits cannot cover (stair walls, slabs); the
	# palette still tints each structure its own colour.
	_wall_material = StructureSurfaces.tinted(
		str(_entry.get("wall_texture", StructureSurfaces.ROCK)), wall_color, 4.0)
	if _wall_material == null:
		_wall_material = _material(wall_color, 0.05, 0.85)
	_floor_material = StructureSurfaces.tinted(
		str(_entry.get("floor_texture", StructureSurfaces.WOOD)), floor_color, 4.0)
	if _floor_material == null:
		_floor_material = _material(floor_color, 0.02, 0.92)
	_accent_material = _material(palette.get("accent", Color(0.85, 0.45, 0.22)), 0.35, 0.45)

func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat

## A room is a floor slab plus four walls, with doorways wherever the catalog
## says the plan connects — including side openings into off-axis chambers, so
## the interior is a place to walk around rather than one corridor. A stairs
## room has no floor of its own: its flight bridges the previous room's floor
## to its own.
func _build_rooms() -> void:
	var rooms: Array = _entry.get("rooms", [])
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		var size: Vector3 = room.get("size", Vector3(12.0, 3.0, 12.0))
		var origin: Vector3 = room.get("offset", Vector3.ZERO)
		var kind := str(room.get("kind", StructureCatalog.ROOM_HALL))
		var doors := StructureCatalog.room_doors(_entry, index)
		if kind == StructureCatalog.ROOM_STAIRS:
			var prev_floor := origin.y
			if index > 0:
				prev_floor = float((rooms[index - 1] as Dictionary).get("offset", Vector3.ZERO).y)
			_build_stairs(index, origin, size, prev_floor)
			continue
		_add_floor(index, origin, size)
		_build_walls(index, origin, size, doors)
		_build_room_dressing(index, origin, size, kind)
		_add_ceiling(index, origin, size)

## A room floor: one collision slab, then the kit surface on top of it. Low
## tier lays a single scaled piece; Medium/High tile the real 4 m modules.
func _add_floor(index: int, origin: Vector3, size: Vector3) -> void:
	_add_slab("Floor_%d" % index, origin + Vector3(0.0, -0.25, 0.0),
		Vector3(size.x, 0.5, size.z), _floor_material)
	if _kit_tiled:
		StructureKit.tile_floor(self,
			Vector3(origin.x - size.x * 0.5, origin.y - 0.06, origin.z - size.z * 0.5),
			Vector2(size.x, size.z), origin.y - 0.06, "floor", "KitFloor_%d" % index)
	else:
		StructureKit.add(self, "floor", Transform3D(Basis.IDENTITY,
			origin + Vector3(0.0, -0.06, 0.0)), Vector3(size.x, 0.15, size.z),
			"KitFloor_%d" % index)

## A room roof: one solid slab of collision and mesh. The player sees it from
## inside and the spring arm clamps under it, which is what keeps the indoor
## camera framed on the room instead of climbing over the roofline.
func _add_ceiling(index: int, origin: Vector3, size: Vector3) -> void:
	_add_slab("Ceiling_%d" % index,
		origin + Vector3(0.0, size.y + 0.25, 0.0),
		Vector3(size.x, 0.5, size.z), _wall_material)

## Steps rise (or descend) from the previous room's floor to this room's floor,
## landing on both so a player can always walk the whole plan. The flight is
## closed in by side walls and a ceiling, otherwise the doorway shows the void.
func _build_stairs(index: int, origin: Vector3, size: Vector3, prev_floor_y: float) -> void:
	var step_count := 6
	var rise := (origin.y - prev_floor_y) / float(step_count)
	var run := size.z / float(step_count)
	# Visual steps only: the invisible ramp below provides the smooth climb.
	for step in step_count:
		var step_top := prev_floor_y + rise * float(step + 1)
		_add_slab("Step_%d_%d" % [index, step],
			Vector3(origin.x, step_top - 0.17, origin.z + size.z * 0.5 - run * (float(step) + 0.5)),
			Vector3(size.x * 0.8, 0.34, run), _floor_material, "floor", false)
	# Landings at both ends so a step never ends in mid-air.
	_add_slab("Landing_%d_a" % index,
		Vector3(origin.x, prev_floor_y - 0.25, origin.z + size.z * 0.5),
		Vector3(size.x * 0.9, 0.5, 1.6), _floor_material, "floor")
	_add_slab("Landing_%d_b" % index,
		Vector3(origin.x, origin.y - 0.25, origin.z - size.z * 0.5),
		Vector3(size.x * 0.9, 0.5, 1.6), _floor_material, "floor")
	var low := minf(origin.y, prev_floor_y)
	var high := maxf(origin.y, prev_floor_y) + size.y
	for side in [-1.0, 1.0]:
		_add_slab("Wall_%d_%s" % [index, "L" if side < 0.0 else "R"],
			Vector3(origin.x + side * size.x * 0.5, (low + high) * 0.5, origin.z),
			Vector3(0.6, high - low, size.z), _wall_material, "wall")
	# End walls sit on the floor they serve, so their doorways line up with the
	# rooms on either side instead of floating a level above or below.
	_add_wall_with_door("Wall_%d_F" % index,
		Vector3(origin.x, origin.y + size.y * 0.5, origin.z - size.z * 0.5),
		Vector3(size.x, size.y, 0.6), true)
	_add_wall_with_door("Wall_%d_B" % index,
		Vector3(origin.x, prev_floor_y + size.y * 0.5, origin.z + size.z * 0.5),
		Vector3(size.x, size.y, 0.6), true)
	# Each end wall stands on the floor it serves, so above the lower one the
	# flight's ceiling leaves a band that opens straight out over the roof of
	# the room behind: from the stairs the player sees the top of that room's
	# ceiling, and the spring arm slips out through the gap. Close it.
	for end in ["B", "F"]:
		var base := prev_floor_y if end == "B" else origin.y
		var band_low := base + size.y
		if high - band_low > 0.05:
			var z_sign := 1.0 if end == "B" else -1.0
			_add_slab("Wall_%d_%sUpper" % [index, end],
				Vector3(origin.x, (band_low + high) * 0.5,
					origin.z + z_sign * size.z * 0.5),
				Vector3(size.x, high - band_low, 0.6), _wall_material, "wall")
	_add_slab("Ceiling_%d" % index, Vector3(origin.x, high + 0.25, origin.z),
		Vector3(size.x, 0.5, size.z), _wall_material)
	# Invisible ramp so CharacterBody3D slides up the flight smoothly instead of
	# catching on the vertical faces between tall steps.
	_add_stair_ramp(index, origin, size, prev_floor_y)

func _add_stair_ramp(index: int, origin: Vector3, size: Vector3, prev_floor_y: float) -> void:
	if _body == null:
		return
	var rise := origin.y - prev_floor_y
	# The flight's walkable surface runs between the two landings' inner edges:
	# that is what keeps the ramp flush with the landing tops instead of hitting
	# their exposed front faces.
	var run := size.z - 1.6
	if run < 0.5:
		run = size.z
	if absf(rise) < 0.05 or run < 0.05:
		return
	var thickness := 0.2
	var ramp_length := sqrt(run * run + rise * rise)
	# The ramp top surface must be flush with both landings.
	var ramp_center := Vector3(origin.x,
		(prev_floor_y + origin.y - thickness) * 0.5, origin.z)
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x * 0.75, thickness, ramp_length)
	var shape_node := CollisionShape3D.new()
	shape_node.name = "StairRamp_%d" % index
	shape_node.shape = shape
	shape_node.position = ramp_center
	# The flight ascends toward -z when rise is positive (the front end, at +z,
	# is the low one), so the ramp's +z end must tilt down.
	shape_node.rotation.x = atan2(rise, run)
	_body.add_child(shape_node)

func _build_walls(index: int, origin: Vector3, size: Vector3, doors: Dictionary) -> void:
	var height := size.y
	var thickness := 0.6
	# Side walls close the room in and open where the plan leads sideways.
	for side in [-1.0, 1.0]:
		var key := "left" if side < 0.0 else "right"
		var side_open := bool(doors.get(key, false))
		_add_side_wall("Wall_%d_%s" % [index, "L" if side < 0.0 else "R"],
			origin + Vector3(side * size.x * 0.5, height * 0.5, 0.0),
			Vector3(thickness, height, size.z), side_open)
		if side_open:
			_add_door_threshold("Threshold_%d_%s" % [index, key],
				Vector3(origin.x + side * size.x * 0.5, origin.y, origin.z), false)
	var fwd_open := bool(doors.get("fwd", false))
	_add_wall_with_door("Wall_%d_F" % index,
		origin + Vector3(0.0, height * 0.5, -size.z * 0.5),
		Vector3(size.x, height, thickness), fwd_open)
	if fwd_open:
		_add_door_threshold("Threshold_%d_F" % index,
			Vector3(origin.x, origin.y, origin.z - size.z * 0.5), true)
	var back_open := bool(doors.get("back", false))
	_add_wall_with_door("Wall_%d_B" % index,
		origin + Vector3(0.0, height * 0.5, size.z * 0.5),
		Vector3(size.x, height, thickness), back_open)
	if back_open:
		_add_door_threshold("Threshold_%d_B" % index,
			Vector3(origin.x, origin.y, origin.z + size.z * 0.5), true)

## A floor patch under a doorway. Rooms meet wall-to-wall with no floor slab in
## the gap between them, so a doorway over open air used to drop the hero into
## the void forever. The patch sits 2 cm below the room floors so the two never
## z-fight, and is deep enough (1.6 m) to bridge the gap between facing walls.
func _add_door_threshold(threshold_name: String, center: Vector3, along_x: bool) -> void:
	if _body == null:
		return
	var width := 3.2
	var depth := 1.6
	var size := Vector3(width, 0.5, depth) if along_x else Vector3(depth, 0.5, width)
	var slab_center := center + Vector3(0.0, -0.27, 0.0)
	_add_box_collision(slab_center, size)
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = threshold_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_node.mesh = mesh
	mesh_node.material_override = _floor_material
	mesh_node.position = slab_center
	add_child(mesh_node)

## A wall running along z, with a centred doorway when the room opens sideways.
func _add_side_wall(wall_name: String, center: Vector3, size: Vector3, open: bool) -> void:
	if not open:
		_add_slab(wall_name, center, size, _wall_material, "wall")
		return
	var door_width := 3.2
	var door_height := 2.6
	var jamb := (size.z - door_width) * 0.5
	for side in [-1.0, 1.0]:
		_add_slab("%s_Jamb%s" % [wall_name, "L" if side < 0.0 else "R"],
			center + Vector3(0.0, 0.0, side * (door_width * 0.5 + jamb * 0.5)),
			Vector3(size.x, size.y, jamb), _wall_material, "wall")
	var lintel_height := maxf(size.y - door_height, 0.4)
	_add_slab("%s_Lintel" % wall_name,
		center + Vector3(0.0, door_height * 0.5 + lintel_height * 0.5, 0.0),
		Vector3(size.x, lintel_height, door_width), _wall_material, "wall")

## A wall with a centred doorway: two jambs and a lintel, all solid.
func _add_wall_with_door(wall_name: String, center: Vector3, size: Vector3,
		open: bool) -> void:
	if not open:
		_add_slab(wall_name, center, size, _wall_material, "wall")
		return
	var door_width := 3.2
	var door_height := 2.6
	var jamb := (size.x - door_width) * 0.5
	for side in [-1.0, 1.0]:
		_add_slab("%s_Jamb%s" % [wall_name, "L" if side < 0.0 else "R"],
			center + Vector3(side * (door_width * 0.5 + jamb * 0.5), 0.0, 0.0),
			Vector3(jamb, size.y, size.z), _wall_material, "wall")
	var lintel_height := maxf(size.y - door_height, 0.4)
	_add_slab("%s_Lintel" % wall_name,
		center + Vector3(0.0, door_height * 0.5 + lintel_height * 0.5, 0.0),
		Vector3(door_width, lintel_height, size.z), _wall_material, "wall")

## Per-kind dressing: halls get banners and a table, chambers get storage, and
## vaults/boss halls get the dais the reward sits on. Props are decor only (no
## collision) so they can never block a guard or the player's route.
func _build_room_dressing(index: int, origin: Vector3, size: Vector3, kind: String) -> void:
	match kind:
		StructureCatalog.ROOM_HALL:
			_add_banner(index, origin + Vector3(-size.x * 0.25, 0.0, -size.z * 0.5 + 0.3))
			_add_banner(index, origin + Vector3(size.x * 0.25, 0.0, -size.z * 0.5 + 0.3))
			_add_prop("Room_%d_Table" % index, "table",
				origin + Vector3(0.0, 0.0, size.z * 0.2), Vector3(2.0, 1.0, 4.0))
		StructureCatalog.ROOM_CHAMBER:
			_add_prop("Room_%d_Barrel" % index, "barrel",
				origin + Vector3(-size.x * 0.3, 0.0, size.z * 0.25), Vector3(1.8, 2.0, 1.8))
			_add_prop("Room_%d_Crates" % index, "crates",
				origin + Vector3(size.x * 0.3, 0.0, -size.z * 0.25), Vector3(2.09, 2.14, 2.25))
			_add_prop("Room_%d_Table" % index, "table_small",
				origin + Vector3(0.0, 0.0, size.z * 0.3), Vector3(1.2, 0.8, 1.2))
		StructureCatalog.ROOM_VAULT, StructureCatalog.ROOM_BOSS:
			_build_vault_dressing(index, origin, size)
			_add_banner(index, origin + Vector3(-size.x * 0.3, 0.0, -size.z * 0.5 + 0.3))
			_add_banner(index, origin + Vector3(size.x * 0.3, 0.0, -size.z * 0.5 + 0.3))
			_add_prop("Room_%d_Chest" % index, "chest_gold",
				origin + Vector3(0.0, 0.0, -size.z * 0.35), Vector3(1.7, 1.3, 1.45))

## A prop stands on the floor at `base` (its authored pivot), not centred on a
## slab, so barrels and chests never sink into the ground.
func _add_prop(node_name: String, piece: String, base: Vector3, size: Vector3) -> bool:
	return StructureKit.place(self, piece, Transform3D(Basis.IDENTITY, base),
		size, node_name) != null

func _add_banner(index: int, base: Vector3) -> void:
	StructureKit.place(self, "banner", Transform3D(Basis.IDENTITY, base),
		Vector3(1.5, 2.8, 0.31), "Room_%d_Banner_%d" % [index, get_child_count()])

func _build_vault_dressing(index: int, origin: Vector3, size: Vector3) -> void:
	# A brazier ring and a raised dais: the reward room should read as the end.
	for corner in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(-1.0, 1.0), Vector2(1.0, 1.0)]:
		var post := MeshInstance3D.new()
		post.name = "VaultPost_%d_%s" % [index, str(corner)]
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.16
		mesh.bottom_radius = 0.22
		mesh.height = 2.2
		post.mesh = mesh
		post.material_override = _wall_material
		post.position = origin + Vector3(corner.x * (size.x * 0.5 - 1.4), 1.1,
			corner.y * (size.z * 0.5 - 1.4))
		add_child(post)
		_add_cylinder_collision(post.position, 0.24, 2.2)
	_add_slab("VaultDais_%d" % index, origin + Vector3(0.0, -0.1, -size.z * 0.25),
		Vector3(size.x * 0.5, 0.7, size.z * 0.4), _accent_material)

## One solid box: the collision is always the box, and the box mesh keeps its
## authored name/position (tests and layout math read it) while the kit piece
## is drawn as a hidden-mesh sibling. Swapping kits can never change gameplay.
## Pass collide=false when the visual box should not participate in physics
## (e.g. stair steps that are covered by an invisible ramp).
func _add_slab(slab_name: String, center: Vector3, size: Vector3,
		material: Material, kit := "", collide := true) -> CollisionShape3D:
	var shape_node: CollisionShape3D = null
	if collide:
		shape_node = _add_box_collision(center, size)
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = slab_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_node.mesh = mesh
	mesh_node.material_override = material
	mesh_node.position = center
	add_child(mesh_node)
	if not kit.is_empty() \
			and StructureKit.add(self, kit, Transform3D(Basis.IDENTITY, center),
				size, "%s_Kit" % slab_name) != null:
		mesh_node.visible = false
	return shape_node

func _add_box_collision(center: Vector3, size: Vector3) -> CollisionShape3D:
	if _body == null:
		return null
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = center
	_body.add_child(shape_node)
	return shape_node

func _add_cylinder_collision(center: Vector3, radius: float, height: float) -> void:
	if _body == null:
		return
	var shape_node := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape_node.shape = cylinder
	shape_node.position = center
	_body.add_child(shape_node)

## One lighting profile per room is what makes a level read as its own place:
## warm garrison braziers, cold stair wells, a hot vault, a violet seal.
func _build_lights() -> void:
	for light_data in _entry.get("lights", []):
		var data: Dictionary = light_data
		var light := OmniLight3D.new()
		light.name = "InteriorLight_%d_%d" % [int(data.get("room", 0)),
			get_child_count()]
		light.position = StructureCatalog.spawn_position(_entry, data)
		light.light_color = data.get("color", Color(1.0, 0.7, 0.4))
		light.light_energy = float(data.get("energy", 1.2))
		light.omni_range = float(data.get("range", 12.0))
		light.shadow_enabled = bool(data.get("shadow", false))
		add_child(light)

func _build_title() -> void:
	var label := Label3D.new()
	label.name = "InteriorTitle"
	label.text = str(_entry.get("name", "STRUCTURE"))
	label.font_size = 40
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = _entry.get("spawn", Vector3.ZERO) + Vector3(0.0, 3.2, -1.0)
	add_child(label)

## The way out is always reachable: it stands at the entry room, not at the
## boss, so a player who cannot finish can still leave.
func _build_exit() -> void:
	var exit := INTERACTION_PROP.new()
	exit.name = "StructureExit"
	exit.position = _entry.get("spawn", Vector3.ZERO) + Vector3(0.0, 0.0, 1.2)
	exit.configure(_handler, "structure_exit", str(_entry.get("id", "")), "LEAVE")
	add_child(exit)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 1.6
	capsule.height = 2.4
	shape.shape = capsule
	shape.position = Vector3(0.0, 1.2, 0.0)
	exit.add_child(shape)
	var label := Label3D.new()
	label.text = "LEAVE"
	label.font_size = 34
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.6, 0.0)
	label.modulate = Color(1.0, 0.82, 0.46)
	exit.add_child(label)

func _build_encounter() -> void:
	var encounter := Node3D.new()
	encounter.name = "StructureEncounter"
	encounter.set_meta("encounter_role", "structure_guardians")
	encounter.set_meta("structure_id", str(_entry.get("id", "")))
	add_child(encounter)
	for index in (_entry.get("mobs", []) as Array).size():
		var data: Dictionary = (_entry.get("mobs", []) as Array)[index]
		var enemy := ENEMY_SCENE.instantiate() as Node3D
		if enemy == null:
			continue
		enemy.name = "Guard_%d" % index
		enemy.position = StructureCatalog.spawn_position(_entry, data)
		if enemy.has_method("configure_archetype"):
			enemy.call("configure_archetype", str(data.get("archetype", "charger")))
		encounter.add_child(enemy)
	_build_boss()

func _build_boss() -> void:
	var boss_data: Dictionary = _entry.get("boss", {})
	if boss_data.is_empty():
		return
	var room := Node3D.new()
	room.name = "BossRoom_%s" % str(_entry.get("id", ""))
	room.set_meta("boss_id", str(boss_data.get("id", "")))
	room.set_meta("structure_id", str(_entry.get("id", "")))
	add_child(room)
	var boss := BOSS_SCENE.instantiate() as Node3D
	if boss == null:
		return
	if "def_id" in boss:
		boss.set("def_id", str(boss_data.get("def_id", "bramblewood_thorn_regent")))
	# The structure's own boss borrows a CC0 model; the height normalisation
	# keeps a borrowed rig at the fight's silhouette instead of the exporter's
	# units. Both are set before add_child, which is when the rig mounts.
	if "authored_model_profile" in boss:
		boss.set("authored_model_profile", str(boss_data.get("model_profile", "")))
	if "authored_rig_height" in boss:
		boss.set("authored_rig_height", float(boss_data.get("model_height", 0.0)))
	boss.name = "StructureBoss"
	boss.position = StructureCatalog.spawn_position(_entry, boss_data)
	room.add_child(boss)
	_boss = boss
	if boss.has_signal("died"):
		boss.died.connect(_on_boss_died)

func _on_boss_died() -> void:
	var structure_id := str(_entry.get("id", ""))
	boss_defeated.emit(structure_id)
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var claims: Dictionary = gs.get("quest_reward_claims") \
		if gs.get("quest_reward_claims") is Dictionary else {}
	var key := StructureCatalog.claim_key(structure_id)
	if bool(claims.get(key, false)):
		completed.emit(structure_id)
		return
	claims[key] = true
	gs.set("quest_reward_claims", claims)
	if gs.has_method("record_activity"):
		gs.call("record_activity", str(_entry.get("activity", "STRUCTURE CLEARED")))
	if gs.has_method("save_game"):
		gs.call("save_game")
	completed.emit(structure_id)

func boss_alive() -> bool:
	return _boss != null and is_instance_valid(_boss) and not bool(_boss.get("is_dead"))
