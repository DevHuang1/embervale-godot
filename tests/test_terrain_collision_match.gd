extends SceneTree

## Regression: the terrain collision surface must be the visual heightfield, not
## a coarser approximation of it. The old collision grid sampled every second
## visual vertex, so on ridge flanks its chords ran up to ~2 m below the
## rendered slope and the character walked through the visible hill. Run:
##   godot --headless --path . --script tests/test_terrain_collision_match.gd

const TOLERANCE := 0.01

var _failures: Array[String] = []
var _passes := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed := load("res://scenes/world/grove.tscn") as PackedScene
	if packed == null:
		_fail("grove scene loads")
		_report()
		return
	_pass("grove scene loads")
	var world := packed.instantiate()
	root.add_child(world)
	for _i in 8:
		await process_frame

	var terrain := world.get_node_or_null("Terrain")
	if terrain == null or not terrain.has_method("height_at"):
		_fail("terrain relief exposes height_at")
		_report()
		return
	_pass("terrain relief exposes height_at")
	var shape_node := terrain.get_node_or_null("ReliefCollision") as CollisionShape3D
	if shape_node == null or shape_node.shape is not ConcavePolygonShape3D:
		_fail("heightfield collision shape is built")
		_report()
		return
	_pass("heightfield collision shape is built")
	var mesh_node := terrain.get_node_or_null("TerrainMesh") as MeshInstance3D
	var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
	var mesh_verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var mesh_inds: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var shape := shape_node.shape as ConcavePolygonShape3D
	var faces := shape.get_faces()

	_check(faces.size() == mesh_inds.size(),
		"collision has one vertex per visual index (%d vs %d)" % [faces.size(), mesh_inds.size()])
	var worst_face := 0.0
	for index in mesh_inds.size():
		worst_face = maxf(worst_face, mesh_verts[mesh_inds[index]].distance_to(faces[index]))
	_check(worst_face <= TOLERANCE,
		"collision triangles match the visual mesh (worst %.5f m)" % worst_face)

	# The character must stand on the rendered surface, so cast rays at real
	# mesh vertices (ridge crest, flank and low ground) and compare heights.
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var terrain_layer: int = terrain.collision_layer
	var probes: Array[Vector2] = [
		Vector2(-8.0, -36.0), Vector2(-8.0, -32.0), Vector2(0.0, -40.0),
		Vector2(16.0, -24.0), Vector2(-30.0, -30.0), Vector2(20.0, 0.0),
		Vector2(0.0, 0.0), Vector2(-60.0, 40.0),
	]
	var worst_ray := 0.0
	var worst_at := Vector2.ZERO
	for probe in probes:
		var vertex := _nearest_vertex(mesh_verts, probe)
		var vertex_pos := Vector3(vertex.x, vertex.y + 30.0, vertex.z)
		var query := PhysicsRayQueryParameters3D.create(
			vertex_pos, vertex_pos - Vector3(0.0, 60.0, 0.0))
		query.collide_with_areas = false
		query.collision_mask = terrain_layer
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			_fail("terrain ray hits at %s" % probe)
			continue
		var gap: float = absf(vertex.y - (hit["position"] as Vector3).y)
		if gap > worst_ray:
			worst_ray = gap
			worst_at = probe
	_check(worst_ray <= 0.05,
		"rays land on the rendered surface (worst %.3f m at %s)" % [worst_ray, worst_at])

	# Authored pond basins: the shared water presentation sits at floor + 0.055,
	# so the floor must stay below the lowest bank all around or the water disc
	# pokes through the terrain.
	var realm := str(terrain.call("_realm_id"))
	var pond_specs := WorldGroundComposition.pond_specs(realm)
	if pond_specs.is_empty():
		_pass("realm '%s' declares no authored ponds" % realm)
	else:
		var worst_margin := INF
		for spec in pond_specs:
			var center: Vector2 = spec.get("center", Vector2.ZERO)
			var basin_radius := float(spec.get("radius", 3.0))
			var floor_y := float(terrain.call("height_at", center.x, center.y))
			var water_y := floor_y + 0.055
			var rim_y := INF
			for step in 16:
				var ang := TAU * float(step) / 16.0
				rim_y = minf(rim_y, float(terrain.call("height_at",
					center.x + cos(ang) * basin_radius * 1.25,
					center.y + sin(ang) * basin_radius * 1.25)))
			worst_margin = minf(worst_margin, rim_y - water_y)
		_check(worst_margin > 0.12,
			"pond basins hold water below the lowest bank (worst margin %.2f m)" \
				% worst_margin)

	_report()

## Nearest mesh-grid vertex to a plan-view point (the grid is regular, so the
## nearest vertex is at most half a cell away).
func _nearest_vertex(vertices: PackedVector3Array, point: Vector2) -> Vector3:
	var best := vertices[0]
	var best_distance := INF
	for vertex in vertices:
		var distance := Vector2(vertex.x - point.x, vertex.z - point.y).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = vertex
	return best

func _check(condition: bool, label: String) -> void:
	if condition:
		_pass(label)
	else:
		_fail(label)

func _pass(label: String) -> void:
	_passes += 1
	print("PASS: ", label)

func _fail(label: String) -> void:
	_failures.append(label)
	print("FAIL: ", label)

func _report() -> void:
	print("=== Terrain Collision Match Validation ===")
	print("passes=", _passes, " failures=", _failures.size())
	for failure in _failures:
		print("  - ", failure)
	quit(0 if _failures.is_empty() else 1)
