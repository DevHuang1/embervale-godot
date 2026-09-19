extends Node

## === Structure validation ===
## Guards the enterable-structure system end to end:
##   - the catalog is coherent (kinds, realms, rooms, spawns, claims)
##   - exteriors are solid (every kind gets collision) and expose a door
##   - interiors build rooms, stairs, lighting, guards, a boss and an exit
##   - entry and exit move the player and restore the surface
##   - a cleared structure claims its reward exactly once

const CATALOG := preload("res://scripts/world/structure_catalog.gd")
const ENTERABLE_STRUCTURE := preload("res://scripts/world/enterable_structure.gd")
const STRUCTURE_INTERIOR := preload("res://scripts/world/structure_interior.gd")

var _failures: Array[String] = []
var _passes := 0

func _ready() -> void:
	_assert_catalog_contract()
	_assert_kit_pieces()
	_assert_surface_families()
	_assert_exteriors_are_solid()
	_assert_interiors_build()
	_assert_walkaround_plans()
	_assert_structure_bosses()
	_assert_completion_claims_once()
	_assert_placements_are_reachable()
	_assert_stair_ramps_exist()
	await _assert_doorways_have_floor()
	_assert_roofs_stay_solid()
	await _assert_third_person_roof_rule()
	await _assert_stairs_are_climbable()
	print("=== Structure Validation ===")
	print("passes=", _passes, " failures=", _failures.size())
	for failure in _failures:
		print("FAILURE: ", failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures.append(message)

## Every entry must declare what the builders actually read, and the generated
## ones must describe a real floor plan with an exit the player can reach.
func _assert_catalog_contract() -> void:
	var structures: Array = CATALOG.all()
	_assert_true(structures.size() >= 3, "the catalog must offer several structures")
	var realms: Dictionary = {}
	for entry in structures:
		var id := str(entry.get("id", ""))
		var kind := str(entry.get("kind", ""))
		_assert_true(kind in [CATALOG.KIND_CASTLE, CATALOG.KIND_MUSHROOM_HOUSE,
			CATALOG.KIND_PYRAMID], "%s declares a known kind" % id)
		_assert_true(not str(entry.get("realm", "")).is_empty(), "%s names a realm" % id)
		_assert_true(not str(entry.get("name", "")).is_empty(), "%s has a display name" % id)
		_assert_true(not str(entry.get("claim", "")).is_empty(), "%s declares a claim key" % id)
		realms[str(entry.get("realm", ""))] = true
		if str(entry.get("builder", "generated")) == "authored":
			continue
		var rooms: Array = entry.get("rooms", [])
		_assert_true(rooms.size() >= 2, "%s has more than one room" % id)
		var has_stairs := false
		for room in rooms:
			var size: Vector3 = (room as Dictionary).get("size", Vector3.ZERO)
			_assert_true(size.x > 0.0 and size.y > 0.0 and size.z > 0.0,
				"%s room %s has a positive size" % [id, str((room as Dictionary).get("name", "?"))])
			if str((room as Dictionary).get("kind", "")) == CATALOG.ROOM_STAIRS:
				has_stairs = true
		_assert_true(has_stairs, "%s connects its levels with stairs" % id)
		_assert_true(not (entry.get("lights", []) as Array).is_empty(),
			"%s lights its rooms" % id)
		_assert_true(not (entry.get("mobs", []) as Array).is_empty(), "%s posts guards" % id)
		_assert_true(not (entry.get("boss", {}) as Dictionary).is_empty(), "%s has a boss" % id)
		# Every spawn must reference a room that exists, or it lands in the void.
		for key in ["lights", "mobs"]:
			for spawn in entry.get(key, []):
				var index := int((spawn as Dictionary).get("room", 0))
				_assert_true(index >= 0 and index < rooms.size(),
					"%s %s spawn references a real room" % [id, key])
		var boss_room := int((entry.get("boss", {}) as Dictionary).get("room", 0))
		_assert_true(boss_room >= 0 and boss_room < rooms.size(),
			"%s boss references a real room" % id)
		_assert_true(str((entry.get("boss", {}) as Dictionary).get("def_id", "")).is_empty() == false,
			"%s boss names a definition" % id)
	_assert_true(realms.size() >= 3, "structures span at least three realms")

## Every mapped kit piece must ship and measure: layouts ask StructureKit to fit
## a piece to real metres, and a missing or zero-size model silently falls back
## to a procedural box, which is exactly the regression this catches.
func _assert_kit_pieces() -> void:
	var pieces: Dictionary = StructureKit.PIECES
	_assert_true(pieces.size() >= 20, "the kit maps several logical pieces")
	for piece in pieces:
		var path := str(pieces[piece])
		_assert_true(ResourceLoader.exists(path, "PackedScene"),
			"kit piece %s ships in the repo" % str(piece))
		if not StructureKit.has_piece(str(piece)):
			continue
		var size := StructureKit.piece_size(str(piece))
		_assert_true(size.x > 0.001 and size.y > 0.001 and size.z > 0.001,
			"kit piece %s has a measured module size" % str(piece))
	_assert_true(StructureKit.make("no_such_piece") == null,
		"an unknown kit piece falls back to the procedural build")

## Every CC0 surface role a structure references must resolve to a full PBR
## material (albedo, normal, roughness), or the build silently drops to flat
## colours and the fetched set is dead weight.
func _assert_surface_families() -> void:
	var roles: Dictionary = {}
	for entry in CATALOG.all():
		for key in ["wall_texture", "floor_texture"]:
			var role := str(entry.get(key, ""))
			if not role.is_empty():
				roles[role] = true
	for role in [StructureSurfaces.STONE, StructureSurfaces.ROCK, StructureSurfaces.WOOD,
			StructureSurfaces.GRASS, StructureSurfaces.THATCH]:
		roles[str(role)] = true
	for role in roles:
		var mat := StructureSurfaces.material(str(role))
		_assert_true(mat != null, "surface family %s resolves" % str(role))
		if mat == null:
			continue
		_assert_true(mat.albedo_texture != null, "%s has an albedo map" % str(role))
		_assert_true(mat.normal_texture != null, "%s has a normal map" % str(role))
		_assert_true(mat.roughness_texture != null, "%s has a roughness map" % str(role))
		_assert_true(mat.uv1_world_triplanar, "%s tiles by world position" % str(role))

## Exteriors must be solid, not scenery: the player walks into a door, not
## through a wall.
func _assert_exteriors_are_solid() -> void:
	for entry in CATALOG.all():
		if str(entry.get("builder", "generated")) == "authored":
			continue
		var structure: Node3D = ENTERABLE_STRUCTURE.new()
		add_child(structure)
		structure.setup(self, entry, 0.0)
		var body := structure.get_node_or_null("ExteriorCollision") as StaticBody3D
		_assert_true(body != null, "%s exterior has a collision body" % str(entry.get("id")))
		if body != null:
			_assert_true(body.get_child_count() >= 8,
				"%s exterior collision covers its solid pieces (%d shapes)"
				% [str(entry.get("id")), body.get_child_count()])
			for shape in body.get_children():
				_assert_true(shape is CollisionShape3D and (shape as CollisionShape3D).shape != null,
					"%s collision shapes are real" % str(entry.get("id")))
		var door := structure.get_node_or_null("StructureDoor")
		_assert_true(door != null, "%s exterior exposes a door" % str(entry.get("id")))
		if door != null:
			_assert_true(str(door.get("action")) == "structure", "%s door routes to the structure handler" % str(entry.get("id")))
			_assert_true(str(door.get("prop_id")) == str(entry.get("id")), "%s door carries its structure id" % str(entry.get("id")))
		structure.queue_free()

func _assert_interiors_build() -> void:
	for entry in CATALOG.all():
		if str(entry.get("builder", "generated")) == "authored":
			continue
		var id := str(entry.get("id"))
		var interior: Node3D = STRUCTURE_INTERIOR.new()
		add_child(interior)
		interior.setup(self, entry)
		var spawn: Vector3 = interior.build()
		var rooms: Array = entry.get("rooms", [])
		_assert_true(spawn != Vector3.ZERO, "%s interior returns an entry position" % id)
		var collision := interior.get_node_or_null("InteriorCollision") as StaticBody3D
		_assert_true(collision != null and collision.get_child_count() >= 20,
			"%s interior is walkable and solid (%d shapes)" % [id,
				collision.get_child_count() if collision != null else 0])
		_assert_true(interior.get_node_or_null("StructureExit") != null,
			"%s interior has an exit" % id)
		_assert_true(interior.get_node_or_null("StructureEncounter") != null,
			"%s interior spawns its encounter" % id)
		_assert_true(interior.get_node_or_null("BossRoom_%s" % id) != null,
			"%s interior has a boss room" % id)
		_assert_true(interior.get_node_or_null("InteriorTitle") != null,
			"%s interior is named in world space" % id)
		# Stairs must actually change height, or the "levels" are a flat plain.
		var heights: Dictionary = {}
		for index in rooms.size():
			heights[index] = (rooms[index] as Dictionary).get("offset", Vector3.ZERO).y
		var distinct := {}
		for value in heights.values():
			distinct[roundf(float(value) * 10.0)] = true
		_assert_true(distinct.size() >= 2, "%s interior has more than one level" % id)
		# A stair must actually bridge two floors, and the room after it must
		# stand on the floor the stair lands on. Otherwise the boss room is a
		# drop or a climb the player cannot make.
		for index in rooms.size():
			var room: Dictionary = rooms[index]
			if str(room.get("kind", "")) != "stairs":
				continue
			var origin_y := float((room.get("offset", Vector3.ZERO) as Vector3).y)
			var prev_y := origin_y
			if index > 0:
				prev_y = float((rooms[index - 1] as Dictionary).get("offset", Vector3.ZERO).y)
			var rise := (origin_y - prev_y) / 6.0
			var last_step := interior.get_node_or_null("Step_%d_5" % index) as MeshInstance3D
			var landing_a := interior.get_node_or_null("Landing_%d_a" % index) as MeshInstance3D
			_assert_true(last_step != null and landing_a != null,
				"%s stair %d builds its flight and landings" % [id, index])
			if last_step != null:
				_assert_true(absf(last_step.position.y + 0.17 - origin_y) < 0.01,
					"%s stair %d lands on its own floor" % [id, index])
			if landing_a != null:
				_assert_true(absf(landing_a.position.y + 0.25 - prev_y) < 0.01,
					"%s stair %d reaches the previous floor" % [id, index])
			_assert_true(absf(rise) > 0.05,
				"%s stair %d changes height" % [id, index])
			_assert_true(interior.get_node_or_null("Floor_%d" % index) == null,
				"%s stair %d leaves the flight open (no floor slab)" % [id, index])
			if index + 1 < rooms.size():
				var next_y := float((rooms[index + 1] as Dictionary).get("offset", Vector3.ZERO).y)
				_assert_true(absf(next_y - origin_y) < 0.01,
					"%s room after stair %d stands on the landing level" % [id, index])
		var light_count := 0
		for child in interior.get_children():
			if child is OmniLight3D:
				light_count += 1
		# Guards live under the encounter node, so the count walks the tree.
		var guard_count := 0
		var stack: Array[Node] = [interior]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			for child in node.get_children():
				stack.append(child)
				if str(child.name).begins_with("Guard_"):
					guard_count += 1
		_assert_true(light_count >= (entry.get("lights", []) as Array).size(),
			"%s interior lights every declared light" % id)
		_assert_true(guard_count == (entry.get("mobs", []) as Array).size(),
			"%s interior spawns every declared guard" % id)
		_assert_doorways_are_open(interior, entry)
		interior.queue_free()

## Every declared doorway must be physically clear in the built collision: a
## wall jamb, stair wall or dais that swallowed an opening would soft-lock the
## route to the boss even though the data plan looks connected.
func _assert_doorways_are_open(interior: Node3D, entry: Dictionary) -> void:
	var id := str(entry.get("id"))
	var body := interior.get_node_or_null("InteriorCollision") as StaticBody3D
	if body == null:
		return
	var shapes: Array[CollisionShape3D] = []
	for child in body.get_children():
		if child is CollisionShape3D:
			shapes.append(child as CollisionShape3D)
	# Guard the guard: the probe must report a solid slab's own centre blocked,
	# otherwise "doorway clear" would pass vacuously.
	var solid_checked := false
	for shape_node in shapes:
		if shape_node.shape is BoxShape3D:
			var half := (shape_node.shape as BoxShape3D).size * 0.5
			if half.x > 0.1 and half.y > 0.1 and half.z > 0.1:
				_assert_true(_point_blocked(shapes, shape_node.position),
					"%s blocked-point probe detects solid geometry" % id)
				solid_checked = true
				break
	_assert_true(solid_checked, "%s has a solid shape to probe" % id)
	var rooms: Array = entry.get("rooms", [])
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		var origin: Vector3 = room.get("offset", Vector3.ZERO)
		var size: Vector3 = room.get("size", Vector3.ZERO)
		for door in StructureCatalog.room_doors(entry, index):
			var probe := origin
			match str(door):
				"left": probe.x -= size.x * 0.5
				"right": probe.x += size.x * 0.5
				"fwd": probe.z -= size.z * 0.5
				"back": probe.z += size.z * 0.5
			# A stair's back wall stands on the previous room's floor, so its
			# opening is probed from that level, not from the stair's own.
			var base_y := origin.y
			if str(room.get("kind", "")) == StructureCatalog.ROOM_STAIRS \
					and str(door) == "back" and index > 0:
				base_y = float((rooms[index - 1] as Dictionary).get("offset", Vector3.ZERO).y)
			probe.y = base_y + 1.3
			_assert_true(not _point_blocked(shapes, probe),
				"%s room %d %s doorway is physically clear" % [id, index, str(door)])

## Every doorway must land on walkable floor. Rooms meet wall-to-wall with a
## gap between their floor slabs, and the doorway threshold patch bridges it;
## without the patch the hero walks out of the upper gallery and falls forever
## at the boss door. The ray starts in the doorway (already proven clear) and
## must find floor at the level the door serves, not the void below.
func _assert_doorways_have_floor() -> void:
	var entry := CATALOG.get_structure("bramble_keep")
	var interior: Node3D = STRUCTURE_INTERIOR.new()
	add_child(interior)
	interior.setup(self, entry)
	interior.build()
	# Earlier checks queue_free their interiors, which are still alive this
	# frame; park this one on a private collision bit so the ray can only hit
	# the floor under test.
	var body := interior.get_node_or_null("InteriorCollision") as StaticBody3D
	_assert_true(body != null, "bramble_keep interior exposes its collision body")
	var saved_layer := body.collision_layer if body != null else 0
	if body != null:
		body.collision_layer = 1 << 19
	var state := interior.get_world_3d().direct_space_state
	await get_tree().physics_frame
	var rooms: Array = entry.get("rooms", [])
	var id := str(entry.get("id"))
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		var origin: Vector3 = room.get("offset", Vector3.ZERO)
		var size: Vector3 = room.get("size", Vector3.ZERO)
		for door in StructureCatalog.room_doors(entry, index):
			var probe := origin
			match str(door):
				"left": probe.x -= size.x * 0.5
				"right": probe.x += size.x * 0.5
				"fwd": probe.z -= size.z * 0.5
				"back": probe.z += size.z * 0.5
			# A stair's back wall stands on the previous room's floor, so the
			# floor it must land on is that level.
			var base_y := origin.y
			if str(room.get("kind", "")) == StructureCatalog.ROOM_STAIRS \
					and str(door) == "back" and index > 0:
				base_y = float((rooms[index - 1] as Dictionary).get("offset", Vector3.ZERO).y)
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(probe.x, base_y + 1.3, probe.z),
				Vector3(probe.x, base_y - 1.5, probe.z))
			query.collision_mask = 1 << 19
			var hit := state.intersect_ray(query)
			var hit_y := (hit["position"] as Vector3).y if not hit.is_empty() else -999.0
			var hit_name := str((hit["collider"] as Node).name) if not hit.is_empty() else "none"
			_assert_true(not hit.is_empty() and absf(hit_y - base_y) <= 0.3,
				"%s room %d %s doorway has walkable floor (hit y=%.2f, want %.2f, collider=%s)"
					% [id, index, str(door), hit_y, base_y, hit_name])
	if body != null:
		body.collision_layer = saved_layer
	interior.queue_free()

## Third person hides the roofs of the rooms the hero and camera occupy; first
## person (the camera rides at the hero's head) leaves every roof alone. The
## roof's collision is never toggled in either mode, so the spring arm still
## clamps under the roofline instead of climbing out over the next room.
func _assert_third_person_roof_rule() -> void:
	await get_tree().process_frame
	var entry := CATALOG.get_structure("bramble_keep")
	var interior: Node3D = STRUCTURE_INTERIOR.new()
	add_child(interior)
	interior.setup(self, entry)
	interior.build()
	await get_tree().physics_frame
	var rooms: Array = entry.get("rooms", [])
	var origin: Vector3 = (rooms[0] as Dictionary).get("offset", Vector3.ZERO)
	var size: Vector3 = (rooms[0] as Dictionary).get("size", Vector3.ZERO)
	var hero := Node3D.new()
	hero.name = "RoofHero"
	hero.add_to_group("hero")
	add_child(hero)
	var camera := Camera3D.new()
	camera.name = "RoofCamera"
	camera.current = true
	add_child(camera)
	var ceiling_0 := interior.get_node_or_null("Ceiling_0") as MeshInstance3D
	var ceiling_1 := interior.get_node_or_null("Ceiling_1") as MeshInstance3D
	# Third person: the rig orbits several metres behind the hero.
	hero.global_position = Vector3(origin.x, origin.y + 0.5, origin.z)
	camera.global_position = hero.global_position + Vector3(0.0, 4.0, 7.0)
	for _frame in 8:
		interior._process(1.0 / 60.0)
	_assert_true(ceiling_0 != null and not ceiling_0.visible,
		"third person hides the occupied room's roof")
	_assert_true(ceiling_1 != null and ceiling_1.visible,
		"third person leaves an unoccupied room's roof visible")
	var state := interior.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(origin.x, origin.y + 1.0, origin.z),
		Vector3(origin.x, origin.y + size.y + 2.0, origin.z))
	var hit := state.intersect_ray(query)
	var hit_y := (hit["position"] as Vector3).y if not hit.is_empty() else -999.0
	_assert_true(not hit.is_empty() and hit_y >= origin.y + size.y,
		"a hidden roof keeps its collision (hit y=%.2f)" % hit_y)
	# First person: the camera sits at the hero's head; nothing is hidden.
	camera.global_position = hero.global_position + Vector3(0.0, 1.0, 0.0)
	for _frame in 8:
		interior._process(1.0 / 60.0)
	_assert_true(ceiling_0 != null and ceiling_0.visible,
		"first person leaves the occupied room's roof alone")
	_assert_true(ceiling_1 != null and ceiling_1.visible,
		"first person leaves every roof alone")
	# The band above a stair room's lower end wall is closed: through an open
	# band the player looks straight out over the next room's ceiling top and
	# the spring arm slips out after it.
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		if str(room.get("kind", "")) != StructureCatalog.ROOM_STAIRS or index == 0:
			continue
		var room_origin: Vector3 = room.get("offset", Vector3.ZERO)
		var room_size: Vector3 = room.get("size", Vector3.ZERO)
		var prev_y := float((rooms[index - 1] as Dictionary)
			.get("offset", Vector3.ZERO).y)
		var high := maxf(room_origin.y, prev_y) + room_size.y
		query = PhysicsRayQueryParameters3D.create(
			Vector3(room_origin.x, high - 0.3, room_origin.z),
			Vector3(room_origin.x, high - 0.3, room_origin.z + room_size.z * 0.5 + 2.0))
		hit = state.intersect_ray(query)
		_assert_true(not hit.is_empty(),
			"stair %d closes the band above its lower end wall" % index)
	interior.queue_free()
	hero.remove_from_group("hero")
	hero.queue_free()
	camera.queue_free()

## True when any collision shape contains the probe point.
func _point_blocked(shapes: Array[CollisionShape3D], point: Vector3) -> bool:
	for shape_node in shapes:
		var shape := shape_node.shape
		var local := point - shape_node.position
		if shape is BoxShape3D:
			var half := (shape as BoxShape3D).size * 0.5
			if absf(local.x) < half.x - 0.05 and absf(local.y) < half.y - 0.05 \
					and absf(local.z) < half.z - 0.05:
				return true
		elif shape is CylinderShape3D:
			var cylinder := shape as CylinderShape3D
			if Vector2(local.x, local.z).length() < cylinder.radius - 0.05 \
					and absf(local.y) < cylinder.height * 0.5 - 0.05:
				return true
	return false

## A structure is a place to walk around, not one corridor: every doorway must
## be answered by the neighbour it opens into, side chambers must exist, guards
## must be spread across several halls, and the boss hall stays clear of them.
func _assert_walkaround_plans() -> void:
	for entry in CATALOG.all():
		if str(entry.get("builder", "generated")) == "authored":
			continue
		var id := str(entry.get("id"))
		var rooms: Array = entry.get("rooms", [])
		var mob_rooms: Dictionary = {}
		for mob in (entry.get("mobs", []) as Array):
			mob_rooms[int((mob as Dictionary).get("room", -1))] = true
		var boss_room := int((entry.get("boss", {}) as Dictionary).get("room", -1))
		var side_rooms := 0
		for index in rooms.size():
			var room: Dictionary = rooms[index]
			var doors := CATALOG.room_doors(entry, index)
			_assert_true(not doors.is_empty(),
				"%s room %d opens onto a neighbour" % [id, index])
			var origin: Vector3 = room.get("offset", Vector3.ZERO)
			if absf(origin.x) > 1.0:
				side_rooms += 1
			for door in doors:
				_assert_true(_has_answer_door(entry, rooms, index, str(door)),
					"%s room %d %s doorway is answered by its neighbour" % [id, index, door])
			if index == boss_room:
				_assert_true(not mob_rooms.has(index),
					"%s boss hall %d holds no guard group" % [id, index])
		_assert_true(side_rooms >= 2,
			"%s has side chambers to walk into (%d)" % [id, side_rooms])
		_assert_true(mob_rooms.size() >= 3, "%s spreads its guards across halls" % id)
		if boss_room >= 0:
			_assert_true(boss_room < rooms.size(), "%s boss hall exists" % id)

## True when the room across `toward` opens the opposite wall back, so a
## doorway is a real connection rather than a sealed alcove.
func _has_answer_door(entry: Dictionary, rooms: Array, index: int, toward: String) -> bool:
	var room: Dictionary = rooms[index]
	var origin: Vector3 = room.get("offset", Vector3.ZERO)
	var size: Vector3 = room.get("size", Vector3.ZERO)
	var probe := origin
	match toward:
		"left": probe.x -= size.x * 0.5 + 2.0
		"right": probe.x += size.x * 0.5 + 2.0
		"fwd": probe.z -= size.z * 0.5 + 2.0
		"back": probe.z += size.z * 0.5 + 2.0
	for other_index in rooms.size():
		if other_index == index:
			continue
		var other: Dictionary = rooms[other_index]
		var other_origin: Vector3 = other.get("offset", Vector3.ZERO)
		var other_size: Vector3 = other.get("size", Vector3.ZERO)
		var inside_x := absf(probe.x - other_origin.x) <= other_size.x * 0.5 + 0.01
		var inside_z := absf(probe.z - other_origin.z) <= other_size.z * 0.5 + 0.01
		# A stair room bridges two levels, so a height difference is expected
		# exactly where one side of the doorway is a flight.
		var level_ok := absf(other_origin.y - origin.y) < 0.01 \
			or str(room.get("kind", "")) == CATALOG.ROOM_STAIRS \
			or str(other.get("kind", "")) == CATALOG.ROOM_STAIRS
		if inside_x and inside_z and level_ok:
			var opposite := "right" if toward == "left" else ("left" if toward == "right" \
				else ("back" if toward == "fwd" else "fwd"))
			return bool(CATALOG.room_doors(entry, other_index).get(opposite, false))
	return false

## Every structure boss must resolve to its own fight and mount a real model:
## three structures sharing one boss, or one missing rig, is the regression
## this guards.
func _assert_structure_bosses() -> void:
	var roster := preload("res://scripts/systems/boss_roster_catalog.gd")
	var seen_defs: Dictionary = {}
	var seen_models: Dictionary = {}
	for entry in CATALOG.all():
		var boss: Dictionary = entry.get("boss", {})
		if boss.is_empty():
			continue
		var id := str(entry.get("id"))
		var def_id := str(boss.get("def_id", ""))
		var definition := roster.definition_for(def_id)
		_assert_true(not definition.is_empty(),
			"%s boss definition %s resolves" % [id, def_id])
		_assert_true(not seen_defs.has(def_id),
			"%s boss %s is unique to its structure" % [id, def_id])
		seen_defs[def_id] = true
		var profile := str(boss.get("model_profile", ""))
		var model_path := str(CharacterRigLoader.EXTERNAL_MODEL_PATHS.get(profile, ""))
		_assert_true(not model_path.is_empty() \
			and ResourceLoader.exists(model_path, "PackedScene"),
			"%s boss model %s is mounted from a shipped rig" % [id, profile])
		_assert_true(not seen_models.has(profile), "%s boss model %s is unique" % [id, profile])
		seen_models[profile] = true
		_assert_true(float(boss.get("model_height", 0.0)) > 0.5,
			"%s boss declares the height its rig is normalised to" % id)
		# The mapping only counts if the rig actually mounts. The articulated
		# boss used to overwrite the structure's profile with the manifest's
		# (empty) answer, so every structure boss silently fell back to its
		# procedural body even though the shipped rig was mapped.
		var scene := load("res://scenes/entities/boss_articulated.tscn") as PackedScene
		if scene == null:
			continue
		var boss_node := scene.instantiate() as Node3D
		if boss_node == null:
			continue
		boss_node.set("def_id", def_id)
		boss_node.set("authored_model_profile", profile)
		boss_node.set("authored_rig_height", float(boss.get("model_height", 0.0)))
		add_child(boss_node)
		await get_tree().process_frame
		_assert_true(bool(boss_node.get("authored_model_mounted")),
			"%s boss %s mounts its shipping rig" % [id, profile])
		var want := float(boss.get("model_height", 0.0))
		var mounted := CharacterRigLoader.mounted_height(boss_node)
		# Animated rigs measure tallest in their bind pose and shorter once an
		# idle clip plays, so allow pose variance; a rig that never mounted
		# still fails at zero.
		_assert_true(absf(mounted - want) <= maxf(0.4, want * 0.2),
			"%s boss rig normalises to %.2f m (got %.2f)" % [id, want, mounted])
		boss_node.queue_free()
		await get_tree().process_frame

## A cleared structure must write its claim once and only once, so death,
## reload and re-entry can never duplicate the reward.
func _assert_completion_claims_once() -> void:
	var entry := CATALOG.get_structure("bramble_keep")
	var gs := get_node_or_null("/root/GameState")
	_assert_true(gs != null, "GameState is available for the claim check")
	if gs == null or entry.is_empty():
		return
	var claims_before: Dictionary = (gs.get("quest_reward_claims") as Dictionary).duplicate()
	var key := CATALOG.claim_key("bramble_keep")
	claims_before.erase(key)
	gs.set("quest_reward_claims", claims_before)
	var interior: Node3D = STRUCTURE_INTERIOR.new()
	add_child(interior)
	interior.setup(self, entry)
	interior.build()
	var completed: Array[String] = []
	interior.completed.connect(func(id: String) -> void: completed.append(id))
	interior.call("_on_boss_died")
	interior.call("_on_boss_died")
	var claims_after: Dictionary = gs.get("quest_reward_claims")
	_assert_true(bool(claims_after.get(key, false)), "clearing a structure writes its claim")
	_assert_true(completed.size() == 2, "completion is reported on every boss death")
	var duplicate := 0
	for child in interior.get_children():
		if str(child.name).begins_with("RewardChest"):
			duplicate += 1
	_assert_true(duplicate <= 1, "a cleared structure never stacks reward chests")
	interior.queue_free()

## Every realm that owns a structure must place it somewhere the player can
## stand: a finite, non-zero approach position on the realm surface.
func _assert_placements_are_reachable() -> void:
	for realm_id in ["whispergrove", "bramblewood", "moonfen"]:
		var placed: Array = CATALOG.for_realm(realm_id)
		_assert_true(not placed.is_empty(), "%s has a structure to enter" % realm_id)
		for entry in placed:
			var approach: Vector3 = (entry as Dictionary).get("approach", Vector3.ZERO)
			_assert_true(approach.length() > 1.0 and approach.length() < 400.0,
				"%s sits inside the realm bounds" % str((entry as Dictionary).get("id")))

## Every stair flight must carry an invisible ramp so the CharacterBody3D can
## slide up the steps instead of catching on the vertical faces.
func _assert_stair_ramps_exist() -> void:
	for entry in CATALOG.all():
		if str(entry.get("builder", "generated")) == "authored":
			continue
		var id := str(entry.get("id"))
		var interior: Node3D = STRUCTURE_INTERIOR.new()
		add_child(interior)
		interior.setup(self, entry)
		interior.build()
		var body := interior.get_node_or_null("InteriorCollision") as StaticBody3D
		var rooms: Array = entry.get("rooms", [])
		for index in rooms.size():
			if str((rooms[index] as Dictionary).get("kind", "")) != CATALOG.ROOM_STAIRS:
				continue
			var ramp := body.get_node_or_null("StairRamp_%d" % index) if body != null else null
			_assert_true(ramp != null, "%s stair %d has a ramp collision" % [id, index])
			if ramp != null:
				_assert_true(ramp.shape is BoxShape3D,
					"%s stair %d ramp is a rotated box" % [id, index])
		interior.queue_free()

## A real CharacterBody3D must walk the whole flight: from the previous room's
## floor, along the ramp, onto the stair room's own floor. Ramp existence alone
## would pass while the geometry still caught on a landing face.
func _assert_stairs_are_climbable() -> void:
	for entry in CATALOG.all():
		if str(entry.get("builder", "generated")) == "authored":
			continue
		var id := str(entry.get("id"))
		var rooms: Array = entry.get("rooms", [])
		for index in rooms.size():
			var room: Dictionary = rooms[index]
			if str(room.get("kind", "")) != CATALOG.ROOM_STAIRS:
				continue
			var origin: Vector3 = room.get("offset", Vector3.ZERO)
			var size: Vector3 = room.get("size", Vector3(8.0, 3.4, 10.0))
			var prev_y := origin.y
			if index > 0:
				prev_y = float((rooms[index - 1] as Dictionary).get("offset", Vector3.ZERO).y)
			var handler := Node.new()
			add_child(handler)
			var interior: Node3D = STRUCTURE_INTERIOR.new()
			add_child(interior)
			interior.setup(handler, entry)
			interior.build()
			await get_tree().physics_frame
			var climber := CharacterBody3D.new()
			var shape := CollisionShape3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.4
			capsule.height = 1.6
			shape.shape = capsule
			shape.position = Vector3(0.0, 0.8, 0.0)
			climber.add_child(shape)
			add_child(climber)
			climber.global_position = Vector3(origin.x, prev_y + 1.2,
				origin.z + size.z * 0.5 - 1.0)
			var reached := false
			for _frame in 240:
				climber.velocity.z = -4.0
				if climber.is_on_floor():
					climber.velocity.y = -0.5
				else:
					climber.velocity.y -= 9.8 * 0.0167
				climber.move_and_slide()
				var past_middle := climber.global_position.z <= origin.z
				var at_far_floor := absf(climber.global_position.y - origin.y) <= 0.4
				if past_middle and at_far_floor:
					reached = true
					break
				await get_tree().physics_frame
			_assert_true(reached,
				"%s stair %d carries a walker from floor to floor" % [id, index])
			climber.queue_free()
			interior.queue_free()
			handler.queue_free()
			await get_tree().process_frame

## The ceiling of the room the hero stands in is hidden, while the rest stay
## visible. This keeps the third-person camera from being blocked by the roof.
## Roofs are solid and never toggle. The indoor camera stays framed by
## flattening its pitch, so the roof must not hide or drop its collision: a
## roof that opened used to strobe on room boundaries and let the camera climb
## above the roofline where it saw nothing but slab tops.
func _assert_roofs_stay_solid() -> void:
	await get_tree().process_frame
	var entry := CATALOG.get_structure("bramble_keep")
	var interior: Node3D = STRUCTURE_INTERIOR.new()
	add_child(interior)
	interior.setup(self, entry)
	interior.build()
	var rooms: Array = entry.get("rooms", [])
	var state := interior.get_world_3d().direct_space_state
	await get_tree().physics_frame
	for index in rooms.size():
		var ceiling := interior.get_node_or_null("Ceiling_%d" % index) as MeshInstance3D
		_assert_true(ceiling != null and ceiling.visible,
			"bramble_keep room %d roof is built and visible" % index)
		var room: Dictionary = rooms[index]
		var origin: Vector3 = room.get("offset", Vector3.ZERO)
		var size: Vector3 = room.get("size", Vector3.ZERO)
		# A ray straight up from the room centre must find the roof slab just
		# above the room, so the spring arm can never pass through it.
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(origin.x, origin.y + 1.0, origin.z),
			Vector3(origin.x, origin.y + size.y + 2.0, origin.z))
		var hit := state.intersect_ray(query)
		var hit_y := (hit["position"] as Vector3).y if not hit.is_empty() else -999.0
		_assert_true(not hit.is_empty() and hit_y >= origin.y + size.y,
			"bramble_keep room %d roof is solid overhead (hit y=%.2f)" % [index, hit_y])
	interior.queue_free()

