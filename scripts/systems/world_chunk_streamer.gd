extends Node3D

class_name WorldChunkStreamer

## Runtime diagnostic for terrain visibility and streamed tile bounds. Kept
## lightweight so it can be queried from an Android profile route.
func terrain_visibility_report() -> Dictionary:
	var report := {"valid": true, "resident_tiles": 0, "invalid_tiles": 0,
		"missing_meshes": 0, "undersized_aabbs": 0}
	for child in get_children():
		if not is_instance_valid(child):
			continue
		var mesh_instances := child.find_children("*", "MeshInstance3D", true, false)
		for node in mesh_instances:
			var instance := node as MeshInstance3D
			if instance == null or instance.mesh == null:
				report.missing_meshes += 1
				continue
			report.resident_tiles += 1
			var aabb := instance.get_aabb()
			if aabb.size.x < 1.0 or aabb.size.z < 1.0 or aabb.size.y <= 0.0:
				report.undersized_aabbs += 1
	report.invalid_tiles = report.missing_meshes + report.undersized_aabbs
	report.valid = report.invalid_tiles == 0
	return report

## === World Chunk Streamer ===
## Extends the grove realms (whispergrove/bramblewood) from the authored
## 600 m core out to a ~2000 m streaming world. A ring of 60 m chunks is
## built/despawned around the hero as they move; each chunk carries a
## flat terrain tile plus MultiMesh batches (grass, trees, rocks, bushes,
## deadwood) and occasional flavor (ruined settlements, ponds).
##
## Self-disables unless the owning realm is the bramblewood biome (which
## also covers whispergrove's visual identity). mistfen/heartwood/moonfen
## keep their static arenas untouched.

const CHUNK_SIZE := 60.0
const TILE_SUBDIVISIONS := 20
const INNER_HALF := 300.0
const WORLD_WALL := 1001.0
const NEAR_ZONE := 72.0
const WORLD_SEED := 2026082357
## Dense-carpet baseline spacing (metres) used with QualityScaler's
## grass_density_scale applied as 1/sqrt(), reproducing the pre-streaming
## GroveDressing carpet density so the world reads as full of grass.
const CARPET_SPACING := 1.08
const CHUNKS_PER_FRAME := 2
const PREFETCH_CHUNKS := 1
## World-edge grass: a sparse blade layer past the tier's far ring so the
## whole TerrainRelief extent (half-width 300 m) reads as covered ground.
const FRINGE_SPACING := 9.0
const FRINGE_END := 342.0
const KNOWN_REALMS: Array[String] = [
	"whispergrove", "bramblewood", "mistfen", "heartwood", "moonfen"]
## Per-quality-tier world tuning. {level: {radius, far}} where radius is the
## stream view radius in metres and far is the sparse ring fill spacing
## outside the dense near carpet.
const TIERS := {
	# Every active chunk receives a grass batch. The far spacing is still
	# cheaper than the close carpet, but dense enough that world blocks do not
	# turn into bare green planes between the camera and the horizon.
	0: {"radius": 110.0, "far": 4.5, "grass": [0.0, 70.0, 60.0, 115.0, 105.0, 155.0]},
	1: {"radius": 170.0, "far": 3.6, "grass": [0.0, 105.0, 85.0, 180.0, 165.0, 250.0]},
	2: {"radius": 250.0, "far": 1.8, "grass": [0.0, 170.0, 115.0, 330.0, 285.0, 430.0]},
}

const GRASS_SHADER := preload("res://assets/shaders/grass_blade.gdshader")
const ROCK_SHADER := preload("res://assets/shaders/rock.gdshader")
const BARK_SHADER := preload("res://assets/shaders/bark.gdshader")
const AMBIENT_FOLIAGE_SCRIPT := preload("res://scripts/systems/ambient_foliage_patch.gd")
const AMBIENT_LIFE_SCRIPT := preload("res://scripts/systems/ambient_life_field.gd")

var _active := false
var _realm_id := "bramblewood"
var _hero: Node3D
var _terrain_material: Material
var _terrain_relief: TerrainRelief
var _tier: Dictionary = TIERS[0]
var _grass_density: float = 1.0
var _chunks: Dictionary = {}
var _generation_queue: Array[Vector2i] = []
var _desired_keys: Dictionary = {}
var _queue_center := Vector3.ZERO
var _last_generation_usec: int = 0
var _last_center := Vector2i(1 << 30, 1 << 30)
var _decoration_queue: Array[Dictionary] = []
var _mobile_chunk_work: Dictionary = {}
var _mobile_chunk_phase: String = "idle"
var _mobile_chunk_key := Vector2i.ZERO

var _grass_mesh: ArrayMesh
var _grass_mid_mesh: ArrayMesh
var _grass_far_mesh: ArrayMesh
var _grass_material: ShaderMaterial
var _tree_mesh: ArrayMesh
var _tree_trunk_material: ShaderMaterial
var _tree_canopy_material: Material
var _rock_mesh: SphereMesh
var _rock_material: ShaderMaterial
var _bush_mesh: SphereMesh
var _bush_material: Material
var _deadwood_mesh: CylinderMesh
var _deadwood_material: ShaderMaterial
var _stone_material: ShaderMaterial
## Sand / clay / dirt patch surfaces shared across every streamed chunk so
## ground texture variety reaches the whole world (origin patches previously
## faded at ~64 m and left the far terrain a single grass wash).
var _patch_mesh: CylinderMesh
var _patch_materials: Dictionary = {}  # family -> StandardMaterial3D

## World-space clearance anchors {pos: Vector2, radius: float} mirrored from
## grove_dressing.gd so streamed grass keeps gameplay readable at exactly the
## same clearance the static carpet used.
var _clearances: Array[Dictionary] = []
var _chunks_per_frame: int = CHUNKS_PER_FRAME
@export var mobile_stream_budget_ms: float = 3.0
var _last_chunk_build_ms: float = 0.0
var _max_chunk_build_ms: float = 0.0
var _chunks_built_total: int = 0
var _movement_callbacks: int = 0
var _last_movement_msec: int = 0

func _is_mobile_runtime() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

func _world_view_scale() -> float:
	var scaler := get_node_or_null("/root/WorldState/QualityScaler")
	if scaler == null:
		scaler = get_node_or_null("/root/QualityScaler")
	if scaler != null and scaler.has_method("get_world_view_scale"):
		return clampf(float(scaler.call("get_world_view_scale")), 0.45, 1.0)
	return 0.55 if _is_mobile_runtime() else 1.0

func _effective_world_radius() -> float:
	return float(_tier["radius"]) * _world_view_scale()

func _ready() -> void:
	add_to_group("world_chunk_streamer")
	_active = _is_streaming_realm()
	if not _active:
		return
	_setup()
	set_process(true)

func _process(_delta: float) -> void:
	if not _active:
		return
	var started := Time.get_ticks_usec()
	if _is_mobile_runtime():
		# A chunk is advanced in small units: one terrain row, one grass band,
		# or one decoration phase. This makes the wall-clock budget apply to
		# actual construction instead of only between completed chunks.
		if _mobile_chunk_work.is_empty() and not _generation_queue.is_empty():
			_start_mobile_chunk_work(_generation_queue.pop_front() as Vector2i)
		if not _mobile_chunk_work.is_empty():
			var build_started := Time.get_ticks_usec()
			_process_mobile_chunk_work()
			_last_chunk_build_ms = float(Time.get_ticks_usec() - build_started) / 1000.0
			_max_chunk_build_ms = maxf(_max_chunk_build_ms, _last_chunk_build_ms)
		elif not _decoration_queue.is_empty():
			_process_one_decoration()
		_last_generation_usec = Time.get_ticks_usec() - started
		return
	for _index in _chunks_per_frame:
		if _generation_queue.is_empty():
			break
		var key: Vector2i = _generation_queue.pop_front()
		if _desired_keys.has(key) and not _chunks.has(key):
			var build_started := Time.get_ticks_usec()
			_build_chunk(key, _queue_center)
			_last_chunk_build_ms = float(Time.get_ticks_usec() - build_started) / 1000.0
			_max_chunk_build_ms = maxf(_max_chunk_build_ms, _last_chunk_build_ms)
			_chunks_built_total += 1
	_last_generation_usec = Time.get_ticks_usec() - started

func _start_mobile_chunk_work(key: Vector2i) -> void:
	if not _desired_keys.has(key) or _chunks.has(key):
		return
	var chunk := Node3D.new()
	chunk.name = "StreamChunk_%d_%d" % [key.x, key.y]
	add_child(chunk)
	var min_world := Vector3(float(key.x) * CHUNK_SIZE, 0.0,
		float(key.y) * CHUNK_SIZE)
	chunk.position = min_world
	_chunks[key] = chunk
	_mobile_chunk_key = key
	_mobile_chunk_phase = "terrain"
	_mobile_chunk_work = {
		"key": key,
		"chunk": chunk,
		"min_world": min_world,
		"center": min_world + Vector3(CHUNK_SIZE * 0.5, 0.0, CHUNK_SIZE * 0.5),
		"rng": _chunk_rng(key.x, key.y),
		"terrain_row": 0,
		"terrain_vertices": PackedVector3Array(),
	}

func _process_mobile_chunk_work() -> void:
	var chunk := _mobile_chunk_work.get("chunk") as Node3D
	var key: Vector2i = _mobile_chunk_work.get("key", Vector2i.ZERO)
	if chunk == null or not is_instance_valid(chunk) or not _desired_keys.has(key):
		if _chunks.get(key) == chunk:
			_chunks.erase(key)
		if is_instance_valid(chunk):
			chunk.queue_free()
		_mobile_chunk_work.clear()
		_mobile_chunk_phase = "idle"
		return
	var phase := str(_mobile_chunk_work.get("phase", "terrain"))
	var min_world: Vector3 = _mobile_chunk_work.get("min_world", Vector3.ZERO)
	match phase:
		"terrain":
			_process_mobile_terrain_row()
		"near_grass":
			_process_mobile_grass_band("near")
		"mid_grass":
			_process_mobile_grass_band("mid")
		"decorations":
			_decoration_queue.append({"key": key, "chunk": chunk,
				"min_world": min_world,
				"center": _mobile_chunk_work.get("center", Vector3.ZERO),
				"rng": _chunk_rng(key.x, key.y), "phase": 0})
			_mobile_chunk_work.clear()
			_mobile_chunk_phase = "idle"
			_chunks_built_total += 1
	if not _mobile_chunk_work.is_empty():
		_mobile_chunk_phase = str(_mobile_chunk_work.get("phase", phase))

func _process_mobile_terrain_row() -> void:
	var key: Vector2i = _mobile_chunk_work.get("key", Vector2i.ZERO)
	var min_world: Vector3 = _mobile_chunk_work.get("min_world", Vector3.ZERO)
	var row := int(_mobile_chunk_work.get("terrain_row", 0))
	var vertices: PackedVector3Array = _mobile_chunk_work.get(
		"terrain_vertices", PackedVector3Array())
	var cells := TILE_SUBDIVISIONS
	var step := CHUNK_SIZE / float(cells)
	if _is_inner_cell(key.x, key.y):
		_mobile_chunk_work["phase"] = "near_grass"
		return
	for ix in range(cells):
		var x0 := min_world.x + float(ix) * step
		var x1 := x0 + step
		var z0 := min_world.z + float(row) * step
		var z1 := z0 + step
		var a := Vector3(x0, _surface_height(Vector2(x0, z0)), z0)
		var b := Vector3(x1, _surface_height(Vector2(x1, z0)), z0)
		var c := Vector3(x1, _surface_height(Vector2(x1, z1)), z1)
		var d := Vector3(x0, _surface_height(Vector2(x0, z1)), z1)
		var offset := Vector3(min_world.x, 0.0, min_world.z)
		vertices.append(a - offset)
		vertices.append(b - offset)
		vertices.append(c - offset)
		vertices.append(a - offset)
		vertices.append(c - offset)
		vertices.append(d - offset)
	_mobile_chunk_work["terrain_vertices"] = vertices
	row += 1
	_mobile_chunk_work["terrain_row"] = row
	if row < cells:
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in vertices:
		surface.add_vertex(vertex)
	surface.generate_normals()
	var terrain_mesh := surface.commit()
	var body := StaticBody3D.new()
	body.name = "StreamTerrain"
	body.collision_layer = 32
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = terrain_mesh.create_trimesh_shape()
	body.add_child(collider)
	var mesh := MeshInstance3D.new()
	mesh.name = "StreamTerrainMesh"
	mesh.mesh = terrain_mesh
	if _terrain_material != null:
		mesh.material_override = _terrain_material
	else:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.22, 0.26, 0.16)
		fallback.roughness = 1.0
		mesh.material_override = fallback
	body.add_child(mesh)
	chunk_add_child_for_key(body, key)
	_mobile_chunk_work["phase"] = "near_grass"
	_mobile_chunk_work["grass_row"] = 0
	_mobile_chunk_work["grass_transforms"] = []

func _process_mobile_grass_band(band: String) -> void:
	var key: Vector2i = _mobile_chunk_work.get("key", Vector2i.ZERO)
	var min_world: Vector3 = _mobile_chunk_work.get("min_world", Vector3.ZERO)
	var chunk := _mobile_chunk_work.get("chunk") as Node3D
	var rng := _mobile_chunk_work.get("rng") as RandomNumberGenerator
	var spacing := _near_spacing() if band == "near" \
		else 1.8 / sqrt(_grass_density)
	var mesh := _grass_mesh if band == "near" else _grass_mid_mesh
	var base_cap := 1200 if band == "near" else 500
	var band_index := 0 if band == "near" else 1
	var range_n := int(ceil(CHUNK_SIZE / maxf(spacing, 1.0)))
	var start := (CHUNK_SIZE - float(range_n) * spacing) * 0.5
	var max_count := maxi(96, int(round(float(base_cap) * _grass_density)))
	var row := int(_mobile_chunk_work.get("grass_row", 0))
	var transforms: Array = _mobile_chunk_work.get("grass_transforms", [])
	if row >= range_n or transforms.size() >= max_count:
		_finish_mobile_grass_band(band, chunk, mesh, band_index, transforms)
		return
	for j in range(range_n):
		var local := Vector2(start + float(row) * spacing,
			start + float(j) * spacing)
		if local.x >= CHUNK_SIZE or local.y >= CHUNK_SIZE:
			continue
		local += Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)) * spacing
		var world := Vector2(min_world.x + local.x, min_world.z + local.y)
		var clearance := _clearance_strength(world)
		if clearance >= 0.98:
			continue
		if clearance > 0.0 and rng.randf() < clearance * (0.82 if band == "near" else 0.55):
			continue
		var ground_y := _surface_height(world)
		var scale := rng.randf_range(0.72, 1.08)
		if band == "mid":
			scale *= 0.90
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.10, 0.10),
			rng.randf() * TAU, rng.randf_range(-0.10, 0.10))).scaled(
			Vector3(scale, scale, scale))
		transforms.append(Transform3D(basis,
			Vector3(local.x, ground_y + 0.015, local.y)))
		if transforms.size() >= max_count:
			break
	_mobile_chunk_work["grass_transforms"] = transforms
	_mobile_chunk_work["grass_row"] = row + 1
	if row + 1 >= range_n or transforms.size() >= max_count:
		_finish_mobile_grass_band(band, chunk, mesh, band_index, transforms)

func _finish_mobile_grass_band(band: String, chunk: Node3D, mesh: ArrayMesh,
		band_index: int, transforms: Array) -> void:
	var typed_transforms: Array[Transform3D] = []
	for value in transforms:
		if value is Transform3D:
			typed_transforms.append(value as Transform3D)
	_emit_grass_band(chunk, typed_transforms, mesh, band, band_index)
	if band == "near":
		_mobile_chunk_work["phase"] = "mid_grass"
		_mobile_chunk_work["grass_row"] = 0
		_mobile_chunk_work["grass_transforms"] = []
	else:
		_mobile_chunk_work["phase"] = "decorations"

func chunk_add_child_for_key(child: Node, key: Vector2i) -> void:
	var chunk := _chunks.get(key) as Node3D
	if chunk != null and is_instance_valid(chunk):
		chunk.add_child(child)

func _process_one_decoration() -> void:
	if _decoration_queue.is_empty():
		return
	var work: Dictionary = _decoration_queue.pop_front()
	var key: Vector2i = work.get("key", Vector2i.ZERO)
	if not _chunks.has(key) or not _desired_keys.has(key):
		return
	var chunk := work.get("chunk") as Node3D
	if chunk == null or not is_instance_valid(chunk):
		return
	var min_world: Vector3 = work.get("min_world", Vector3.ZERO)
	var center: Vector3 = work.get("center", Vector3.ZERO)
	var rng := work.get("rng") as RandomNumberGenerator
	var phase := int(work.get("phase", 0))
	match phase:
		0: _build_ambient_foliage(chunk, rng)
		1: _build_trees(chunk, min_world, rng)
		2: _build_rocks_and_bushes(chunk, min_world, rng)
		3: _build_deadwood(chunk, min_world, rng)
		4:
			_build_flavor(chunk, min_world, center, rng)
			_finalize_chunk_visibility(chunk)
			return
	work.phase = phase + 1
	_decoration_queue.append(work)

func _finalize_chunk_visibility(chunk: Node3D) -> void:
	for child in chunk.get_children():
		if child is GeometryInstance3D:
			var geometry := child as GeometryInstance3D
			if not str(geometry.name).begins_with("GrassCarpet"):
				geometry.visibility_range_end = _effective_world_radius() + 30.0
				geometry.visibility_range_end_margin = 12.0

func _refresh_resident_visibility_ranges() -> void:
	var ranges := _grass_ranges()
	for chunk_value in _chunks.values():
		var chunk := chunk_value as Node3D
		if chunk == null or not is_instance_valid(chunk):
			continue
		for child in chunk.get_children():
			var geometry := child as GeometryInstance3D
			if geometry == null:
				continue
			if str(geometry.name).begins_with("GrassCarpet"):
				var band := str(geometry.get_meta("source_layer", "near"))
				var band_index: int = int({"near": 0, "mid": 1, "far": 2}.get(band, 0))
				geometry.visibility_range_begin = ranges[band_index * 2]
				geometry.visibility_range_end = ranges[band_index * 2 + 1]
			else:
				geometry.visibility_range_end = _effective_world_radius() + 30.0
			geometry.visibility_range_end_margin = 12.0

func _is_streaming_realm() -> bool:
	var world_root := get_parent()
	if world_root == null:
		return false
	var realm := str(world_root.get("biome_id")) if "biome_id" in world_root else _visual_realm_id()
	return realm in KNOWN_REALMS

func _visual_realm_id() -> String:
	var world_root := get_parent()
	return RealmLayoutData.visual_realm_for(world_root)

func _setup() -> void:
	if _is_mobile_runtime():
		# Chunk creation is synchronous and allocates several MultiMeshes. Keep
		# one build per frame so crossing a streaming boundary cannot create a
		# repeating hitch on mobile.
		_chunks_per_frame = 1
	_realm_id = _visual_realm_id()
	var world := get_parent() as Node3D
	_hero = world.get_node_or_null("Hero")
	_apply_quality_startup()
	_collect_terrain_material(world)
	_build_shared_resources()
	_build_clearances()
	_relocate_walls(world)
	_build_ambient_life()
	if _hero != null and _hero.has_signal("position_changed"):
		if _hero.is_connected("position_changed", _on_hero_moved):
			_hero.disconnect("position_changed", _on_hero_moved)
		_hero.connect("position_changed", _on_hero_moved)
		call_deferred("_build_initial_ring")

func _apply_quality_startup() -> void:
	var scaler := get_node_or_null("/root/WorldState/QualityScaler")
	if scaler == null:
		scaler = get_node_or_null("/root/QualityScaler")
	if scaler == null:
		_tier = TIERS[0]
		_grass_density = 0.42
	else:
		_tier = TIERS[clampi(int(scaler.get("level")), 0, 2)]
		_grass_density = clampf(float(scaler.get("grass_density_scale")), 0.35, 1.0)
		if _is_mobile_runtime():
			_grass_density = minf(_grass_density, 0.42)
		if not scaler.is_connected("level_changed", _on_quality_level_changed):
			scaler.connect("level_changed", _on_quality_level_changed)
		if scaler.has_signal("world_view_changed") \
				and not scaler.is_connected("world_view_changed", _on_world_view_changed):
			scaler.connect("world_view_changed", _on_world_view_changed)

func _collect_terrain_material(world: Node3D) -> void:
	_terrain_relief = world.get_node_or_null("Terrain") as TerrainRelief
	var terrain_mesh := world.get_node_or_null("Terrain/TerrainMesh") as MeshInstance3D
	if terrain_mesh != null and terrain_mesh.material_override != null:
		_terrain_material = terrain_mesh.material_override

func _surface_height(world_xz: Vector2) -> float:
	if _terrain_relief != null:
		return _terrain_relief.sample_surface_height(Vector3(world_xz.x, 0.0, world_xz.y))
	return 0.0

func _surface_profile(world_xz: Vector2) -> Dictionary:
	if _terrain_relief != null:
		return _terrain_relief.get_surface_profile(Vector3(world_xz.x, 0.0, world_xz.y))
	return {"height": 0.0, "normal": Vector3.UP, "traversable": true}

func _on_quality_level_changed(level: int) -> void:
	if not _active:
		return
	_tier = TIERS[clampi(int(level), 0, 2)]
	_refresh_resident_visibility_ranges()
	_last_center = Vector2i(1 << 30, 1 << 30)
	if _hero != null:
		call_deferred("_rebuild_ring", _hero.global_position)

func _on_world_view_changed(_mode: int) -> void:
	if not _active:
		return
	_refresh_resident_visibility_ranges()
	_last_center = Vector2i(1 << 30, 1 << 30)
	if _hero != null:
		call_deferred("_rebuild_ring", _hero.global_position)

func _build_initial_ring() -> void:
	if _hero != null:
		_rebuild_ring(_hero.global_position)

func _on_hero_moved(new_position: Vector3) -> void:
	_movement_callbacks += 1
	_last_movement_msec = Time.get_ticks_msec()
	var cell := Vector2i(int(floor(new_position.x / CHUNK_SIZE)),
		int(floor(new_position.z / CHUNK_SIZE)))
	if cell == _last_center:
		return
	_rebuild_ring(new_position)

func conform_dressing_to_surface() -> void:
	for chunk_value in _chunks.values():
		var chunk := chunk_value as Node3D
		if chunk == null:
			continue
		for child_value in chunk.get_children():
			var batch := child_value as MultiMeshInstance3D
			if batch == null or batch.multimesh == null:
				continue
			_conform_batch(batch)

func _conform_batch(batch: MultiMeshInstance3D) -> void:
	var mm := batch.multimesh
	for index in mm.instance_count:
		var transform := mm.get_instance_transform(index)
		var world_xz := Vector2(batch.global_position.x + transform.origin.x,
			batch.global_position.z + transform.origin.z)
		transform.origin.y = _surface_height(world_xz) - batch.global_position.y + 0.015
		mm.set_instance_transform(index, transform)

func validate_dressing_clearance() -> Array[Dictionary]:
	var violations: Array[Dictionary] = []
	for chunk_value in _chunks.values():
		var chunk := chunk_value as Node3D
		if chunk == null:
			continue
		for child_value in chunk.get_children():
			var batch := child_value as MultiMeshInstance3D
			if batch == null or batch.multimesh == null:
				continue
			for index in batch.multimesh.instance_count:
				var origin := batch.multimesh.get_instance_transform(index).origin
				var world_xz := Vector2(batch.global_position.x + origin.x,
					batch.global_position.z + origin.z)
				var expected := _surface_height(world_xz)
				var actual := batch.global_position.y + origin.y
				if actual < expected - 0.08:
					violations.append({"batch": batch.name, "index": index,
						"expected": expected, "actual": actual})
	return violations

func get_surface_material_report(world_position: Vector3) -> Dictionary:
	var profile := _surface_profile(Vector2(world_position.x, world_position.z))
	return {"realm": _realm_id, "material": profile.get("material_hint", "grass"),
		"height": profile.get("height", 0.0), "moisture": profile.get("moisture", 0.0),
		"terrain_bound": _terrain_relief != null}

func _ring_radius() -> int:
	return int(ceil(_effective_world_radius() / CHUNK_SIZE)) + PREFETCH_CHUNKS

func _rebuild_ring(center: Vector3) -> void:
	var cell_x := int(floor(center.x / CHUNK_SIZE))
	var cell_z := int(floor(center.z / CHUNK_SIZE))
	if cell_x == _last_center.x and cell_z == _last_center.y:
		return
	_last_center = Vector2i(cell_x, cell_z)
	_queue_center = center
	var radius := _ring_radius()
	var keep: Dictionary = {}
	for gx in range(cell_x - radius, cell_x + radius + 1):
		for gz in range(cell_z - radius, cell_z + radius + 1):
			keep[Vector2i(gx, gz)] = true
	_desired_keys = keep
	for key_value in _chunks.keys():
		var key := key_value as Vector2i
		if not keep.has(key):
			var node: Node = _chunks[key]
			_chunks.erase(key)
			node.queue_free()
	_decoration_queue = _decoration_queue.filter(
		func(work: Dictionary) -> bool: return keep.has(work.get("key", Vector2i.ZERO)))
	if not _mobile_chunk_work.is_empty() and not keep.has(
		_mobile_chunk_work.get("key", Vector2i.ZERO)):
		var stale_chunk := _mobile_chunk_work.get("chunk") as Node3D
		if is_instance_valid(stale_chunk):
			stale_chunk.queue_free()
		_mobile_chunk_work.clear()
		_mobile_chunk_phase = "idle"
	_generation_queue.clear()
	var missing: Array[Vector2i] = []
	for key_value in keep:
		var key := key_value as Vector2i
		if not _chunks.has(key):
			missing.append(key)
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a.x - cell_x, a.y - cell_z).length_squared() \
			< Vector2(b.x - cell_x, b.y - cell_z).length_squared())
	_generation_queue.assign(missing)

## ---- Walls: push the authored ±301 m barriers out to ±1001 only for the
## streamed realm. Per-instance subresource mutation is safe because mistfen
## and heartwood never run a streamer in the same session.
func _relocate_walls(world: Node3D) -> void:
	var bounds := world.get_node_or_null("WorldBounds")
	if bounds == null:
		return
	var east := bounds.get_node_or_null("WallEast") as CollisionShape3D
	var west := bounds.get_node_or_null("WallWest") as CollisionShape3D
	var north := bounds.get_node_or_null("WallNorth") as CollisionShape3D
	var south := bounds.get_node_or_null("WallSouth") as CollisionShape3D
	if east != null and west != null:
		east.position = Vector3(WORLD_WALL, 2.0, 0.0)
		west.position = Vector3(-WORLD_WALL, 2.0, 0.0)
		if east.shape is BoxShape3D:
			(east.shape as BoxShape3D).size = Vector3(2.0, 4.0, WORLD_WALL * 2.0)
		if west.shape is BoxShape3D:
			(west.shape as BoxShape3D).size = Vector3(2.0, 4.0, WORLD_WALL * 2.0)
	if north != null and south != null:
		north.position = Vector3(0.0, 2.0, -WORLD_WALL)
		south.position = Vector3(0.0, 2.0, WORLD_WALL)
		if north.shape is BoxShape3D:
			(north.shape as BoxShape3D).size = Vector3(WORLD_WALL * 2.0, 4.0, 2.0)
		if south.shape is BoxShape3D:
			(south.shape as BoxShape3D).size = Vector3(WORLD_WALL * 2.0, 4.0, 2.0)

## ---- Clearance anchors, matching grove_dressing._grass_clearance() ----
func _build_clearances() -> void:
	var profile := RealmLayoutData.profile(_realm_id)
	_clearances.clear()
	for boss_anchor in RealmLayoutData.boss_anchor_points_for_world(get_parent()):
		_clearances.append({"pos": boss_anchor,
			"radius": RealmLayoutData.BOSS_ARENA_CLEARANCE_RADIUS})
	for key in ["checkpoint", "cave"]:
		var anchor3 := profile.get(key, Vector3.ZERO) as Vector3
		var radius := 2.6 if key == "checkpoint" else 2.2
		_clearances.append({"pos": Vector2(anchor3.x, anchor3.z), "radius": radius})
	for chest_value in profile.get("chests", []):
		var chest := chest_value as Dictionary
		var chest3 := chest.get("pos", Vector3.ZERO) as Vector3
		_clearances.append({"pos": Vector2(chest3.x, chest3.z), "radius": 1.3})
	var expansion_profile := profile
	var world_root := get_parent()
	if world_root != null and "biome_id" in world_root:
		var biome_profile := RealmLayoutData.profile(str(world_root.get("biome_id")))
		if biome_profile.has("expansion_pockets"):
			expansion_profile = biome_profile
	for pocket_value in expansion_profile.get("expansion_pockets", []):
		var pocket := pocket_value as Dictionary
		if str(pocket.get("role", "")) == "boss":
			continue
		var pocket3 := pocket.get("position", Vector3.ZERO) as Vector3
		_clearances.append({"pos": Vector2(pocket3.x, pocket3.z), "radius": 4.2})
	for pond_value in WorldGroundComposition.pond_centers(_realm_id):
		_clearances.append({"pos": pond_value as Vector2, "radius": 4.8})

func _clearance_blocks(point: Vector2) -> bool:
	for entry in _clearances:
		if point.distance_to(entry["pos"] as Vector2) < float(entry["radius"]):
			return true
	return false

## Returns a soft clearance factor: 1.0 is a hard gameplay clearing, while
## values between 0 and 1 shorten/sparsify grass without leaving empty holes.
func _clearance_strength(point: Vector2) -> float:
	var strongest := 0.0
	for entry in _clearances:
		var radius := float(entry["radius"])
		var distance := point.distance_to(entry["pos"] as Vector2)
		strongest = maxf(strongest, 1.0 - smoothstep(radius, radius + 2.4, distance))
	return strongest

func _rocks_clearance(point: Vector2) -> bool:
	return int(bool(_clearance_blocks(point)))

func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(start)
	var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * amount)

## ---- Shared geometry / materials ----
func _palette() -> Dictionary:
	match _realm_id:
		"whispergrove":
			return {
				"tuft": Color(0.18, 0.32, 0.16),
				"rock": Color(0.31, 0.34, 0.29),
				"trunk": Color(0.13, 0.09, 0.06),
				"canopy": Color(0.09, 0.21, 0.13),
			}
		_:
			return {
				"tuft": Color(0.15, 0.25, 0.10),
				"rock": Color(0.28, 0.29, 0.25),
				"trunk": Color(0.105, 0.075, 0.055),
				"canopy": Color(0.065, 0.145, 0.08),
			}

func _build_shared_resources() -> void:
	var pal := _palette()
	_grass_mesh = _make_grass_clump()
	_grass_mid_mesh = _make_grass_card_mesh(true)
	_grass_far_mesh = _make_grass_card_mesh(false)
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER
	_grass_material.set_shader_parameter("blade_color", pal["tuft"])
	_grass_material.set_shader_parameter("tip_color", (pal["tuft"] as Color).lightened(0.18))
	_grass_material.set_shader_parameter("root_color", (pal["tuft"] as Color).darkened(0.58))
	_grass_material.set_shader_parameter("dry_color", (pal["tuft"] as Color).lerp(Color(0.38, 0.31, 0.12), 0.52))
	_grass_material.set_shader_parameter("blade_height", 0.36)
	_grass_material.set_shader_parameter("root_height_offset", 0.0)
	_grass_material.set_shader_parameter("wind_distance_fade", 0.55 if _effective_world_radius() > 150.0 else 0.75)
	_grass_material.set_shader_parameter("interaction_strength", 1.0)

	var trunk_cyl := CylinderMesh.new()
	trunk_cyl.top_radius = 0.14
	trunk_cyl.bottom_radius = 0.3
	trunk_cyl.height = 3.4
	trunk_cyl.radial_segments = 7
	trunk_cyl.rings = 1
	_tree_trunk_material = ShaderMaterial.new()
	_tree_trunk_material.shader = BARK_SHADER
	for pair in [["bark_albedo_tex", "bark/albedo.png"],
			["bark_normal_tex", "bark/normal.png"],
			["bark_rough_tex", "bark/roughness.png"]]:
		_tree_trunk_material.set_shader_parameter(pair[0],
			load("res://assets/textures/stylized/%s" % pair[1]))

	_tree_canopy_material = StandardMaterial3D.new()
	_tree_canopy_material.albedo_color = pal["canopy"]
	_tree_canopy_material.roughness = 0.9
	_tree_canopy_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var canopy := SphereMesh.new()
	canopy.radius = 1.45
	canopy.height = 2.4
	canopy.radial_segments = 8
	canopy.rings = 5
	canopy.is_hemisphere = true

	_tree_mesh = ArrayMesh.new()
	var trunk_surface := SurfaceTool.new()
	trunk_surface.create_from(trunk_cyl, 0)
	trunk_surface.commit(_tree_mesh)
	_tree_mesh.surface_set_material(0, _tree_trunk_material)
	var canopy_surface := SurfaceTool.new()
	canopy_surface.create_from(canopy, 0)
	canopy_surface.commit(_tree_mesh)
	_tree_mesh.surface_set_material(1, _tree_canopy_material)

	_rock_mesh = SphereMesh.new()
	_rock_mesh.radius = 1.0
	_rock_mesh.height = 1.0
	_rock_mesh.radial_segments = 5
	_rock_mesh.rings = 5
	_rock_material = ShaderMaterial.new()
	_rock_material.shader = ROCK_SHADER
	_rock_material.set_shader_parameter("rock_color", pal["rock"])
	_rock_material.set_shader_parameter("moss_color", pal["tuft"])
	for pair in [["rock_albedo_tex", "rock/albedo.png"],
			["rock_normal_tex", "rock/normal.png"],
			["rock_rough_tex", "rock/roughness.png"]]:
		_rock_material.set_shader_parameter(pair[0],
			load("res://assets/textures/stylized/%s" % pair[1]))

	_bush_mesh = SphereMesh.new()
	_bush_mesh.radius = 0.6
	_bush_mesh.height = 0.9
	_bush_mesh.radial_segments = 6
	_bush_mesh.rings = 3
	_bush_material = StandardMaterial3D.new()
	_bush_material.albedo_color = (pal["canopy"] as Color).darkened(0.18)
	_bush_material.roughness = 1.0
	_bush_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_deadwood_mesh = CylinderMesh.new()
	_deadwood_mesh.top_radius = 0.11
	_deadwood_mesh.bottom_radius = 0.16
	_deadwood_mesh.height = 2.4
	_deadwood_mesh.radial_segments = 6
	_deadwood_material = ShaderMaterial.new()
	_deadwood_material.shader = BARK_SHADER
	for pair in [["bark_albedo_tex", "bark/albedo.png"],
			["bark_normal_tex", "bark/normal.png"],
			["bark_rough_tex", "bark/roughness.png"]]:
		_deadwood_material.set_shader_parameter(pair[0],
			load("res://assets/textures/stylized/%s" % pair[1]))

	_stone_material = ShaderMaterial.new()
	_stone_material.shader = ROCK_SHADER
	_stone_material.set_shader_parameter("rock_color", Color(0.32, 0.31, 0.28))
	_stone_material.set_shader_parameter("moss_color", pal["tuft"])
	for pair in [["rock_albedo_tex", "rock/albedo.png"],
			["rock_normal_tex", "rock/normal.png"],
			["rock_rough_tex", "rock/roughness.png"]]:
		_stone_material.set_shader_parameter(pair[0],
			load("res://assets/textures/stylized/%s" % pair[1]))

	_build_patch_shared_resources()

## Sand/clay/dirt patch surfaces follow WorldGroundComposition's material rule
## (stylized PBR albedo/normal/roughness + realm tint) so the streamed world
## reads as fully covered, matching the authored 60 m ring.
func _build_patch_shared_resources() -> void:
	_patch_mesh = CylinderMesh.new()
	_patch_mesh.top_radius = 1.0
	_patch_mesh.bottom_radius = 1.0
	_patch_mesh.height = 0.035
	_patch_mesh.radial_segments = 14
	for family in ["sand", "clay", "dirt"]:
		var material := StandardMaterial3D.new()
		var root := "res://assets/textures/stylized/%s" % family
		material.albedo_texture = load("%s/albedo.png" % root)
		material.normal_enabled = true
		material.normal_texture = load("%s/normal.png" % root)
		material.roughness_texture = load("%s/roughness.png" % root)
		material.albedo_color = _patch_tint(family)
		material.roughness = 0.88
		material.uv1_scale = Vector3(1.8, 1.8, 1.8)
		_patch_materials[family] = material

func _patch_tint(family: String) -> Color:
	match family:
		"sand":
			return Color(0.72, 0.64, 0.44) if _realm_id != "moonfen" \
				else Color(0.38, 0.34, 0.52)
		"clay":
			return {"mistfen": Color(0.36, 0.43, 0.45),
				"moonfen": Color(0.22, 0.20, 0.36),
				"heartwood": Color(0.34, 0.16, 0.09) \
			}.get(_realm_id, Color(0.34, 0.28, 0.18))
		_:  # dirt
			return {"heartwood": Color(0.28, 0.12, 0.06),
				"moonfen": Color(0.20, 0.14, 0.30),
				"mistfen": Color(0.25, 0.30, 0.29) \
			}.get(_realm_id, Color(0.34, 0.25, 0.14))

## Eight tapered, slightly leaning blades per clump (>= 30 verts so dense
## coverage reads as grass, never as primitive rods). Matches the grove
## carpet's leaf shape.
func _make_grass_clump() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blade_specs := [
		Vector4(-0.07, 0.10, 0.025, 0.012), Vector4(0.0, 0.92, 0.0, 0.02),
		Vector4(0.07, 1.85, -0.02, 0.02), Vector4(-0.035, 2.8, 0.01, -0.015),
		Vector4(0.035, 3.7, -0.015, -0.02), Vector4(0.0, 4.6, 0.02, 0.015),
		Vector4(-0.03, 5.5, -0.01, 0.01), Vector4(0.05, 6.4, 0.01, -0.01),
	]
	for spec_value in blade_specs:
		var spec: Vector4 = spec_value as Vector4
		var offset := Vector3(spec.x, 0.0, 0.0)
		var yaw: float = spec.y
		var lean := Vector3(spec.z, 0.0, spec.w)
		var right := Vector3(cos(yaw), 0.0, sin(yaw))
		var width := 0.10
		var height := 0.34
		var base_left := offset - right * width * 0.5
		var base_right := offset + right * width * 0.5
		var tip_center := offset + Vector3(0.0, height, 0.0) + lean
		var tip_left := tip_center - right * width * 0.14
		var tip_right := tip_center + right * width * 0.14
		var a := base_left
		var b := base_right
		var c := tip_right
		var d := tip_left
		surface.add_vertex(a)
		surface.add_vertex(b)
		surface.add_vertex(c)
		surface.add_vertex(a)
		surface.add_vertex(c)
		surface.add_vertex(d)
	surface.generate_normals()
	var mesh := surface.commit()
	return mesh

## Cheaper silhouettes for the mid/far bands. These remain alpha-cutout
## geometry, never transparent particles, so the batches stay mobile-safe.
func _make_grass_card_mesh(crossed: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := 0.16 if crossed else 0.20
	var height := 0.31 if crossed else 0.25
	var directions := [0.0, PI * 0.5] if crossed else [0.0]
	for yaw in directions:
		var right := Vector3(cos(yaw), 0.0, sin(yaw)) * width
		var left := -right
		var base_left := left
		var base_right := right
		var tip_left := left * 0.12 + Vector3(0.0, height, 0.0)
		var tip_right := right * 0.12 + Vector3(0.0, height, 0.0)
		surface.add_vertex(base_left)
		surface.add_vertex(base_right)
		surface.add_vertex(tip_right)
		surface.add_vertex(base_left)
		surface.add_vertex(tip_right)
		surface.add_vertex(tip_left)
		# Double-sided geometry is intentional; the material also disables cull.
		surface.add_vertex(base_right)
		surface.add_vertex(base_left)
		surface.add_vertex(tip_left)
		surface.add_vertex(base_right)
		surface.add_vertex(tip_left)
		surface.add_vertex(tip_right)
	surface.generate_normals()
	return surface.commit()

## ---- Chunk construction ----
func _chunk_hash(cx: int, cz: int) -> int:
	var h := cx * 374761393 + cz * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return h ^ (h >> 16)

func _chunk_rng(cx: int, cz: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED ^ _chunk_hash(cx, cz)
	return rng

func _build_chunk(key: Vector2i, hero_center: Vector3) -> void:
	var cx := key.x
	var cz := key.y
	var chunk := Node3D.new()
	chunk.name = "StreamChunk_%d_%d" % [cx, cz]
	add_child(chunk)
	_chunks[key] = chunk

	var min_world := Vector3(float(cx) * CHUNK_SIZE, 0.0, float(cz) * CHUNK_SIZE)
	var chunk_center_world := min_world + Vector3(CHUNK_SIZE * 0.5, 0.0, CHUNK_SIZE * 0.5)
	var rng := _chunk_rng(cx, cz)
	# Child transforms are authored in chunk-local coordinates. Without this
	# parent translation every streamed grass/tree/rock batch was stacked at the
	# world origin, away from the terrain cell that generated it.
	chunk.position = min_world

	_build_terrain_tile(chunk, min_world)
	_build_grass(chunk, min_world, chunk_center_world, hero_center, rng)
	if _is_mobile_runtime():
		_decoration_queue.append({"key": key, "chunk": chunk,
			"min_world": min_world, "center": chunk_center_world,
			"rng": _chunk_rng(cx, cz), "phase": 0})
	else:
		_build_ambient_foliage(chunk, rng)
		_build_trees(chunk, min_world, rng)
		_build_rocks_and_bushes(chunk, min_world, rng)
		_build_deadwood(chunk, min_world, rng)
		_build_flavor(chunk, min_world, chunk_center_world, rng)
		_finalize_chunk_visibility(chunk)

func _build_ambient_foliage(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var patch: MultiMeshInstance3D = AMBIENT_FOLIAGE_SCRIPT.new()
	patch.name = "AmbientFoliage"
	patch.position = Vector3(CHUNK_SIZE * 0.5, 0.0, CHUNK_SIZE * 0.5)
	patch.setup(_realm_id, rng.randi(), _foliage_instance_cap(), _terrain_relief)
	patch.call("set_coverage_range", 0.0, _grass_ranges()[3])
	chunk.add_child(patch)

func _grass_ranges() -> Array[float]:
	var values: Array[float] = []
	for value in _tier.get("grass", [0.0, 90.0, 60.0, 145.0, 125.0, 230.0]):
		values.append(float(value) * _world_view_scale())
	return values

func _build_ambient_life() -> void:
	var field: Node3D = AMBIENT_LIFE_SCRIPT.new()
	field.name = "AmbientLife"
	field.position = Vector3(0.0, 1.2, 0.0)
	field.call("setup", _realm_id, WORLD_SEED, 8)
	add_child(field)

func _foliage_instance_cap() -> int:
	match int(_tier.get("radius", 100.0)):
		100: return 12
		140: return 18
		_: return 24

func _is_inner_cell(cx: int, cz: int) -> bool:
	return absf(float(cx) * CHUNK_SIZE) < INNER_HALF and \
		absf(float(cz) * CHUNK_SIZE) < INNER_HALF and \
		absf((float(cx) + 1.0) * CHUNK_SIZE) <= INNER_HALF and \
		absf((float(cz) + 1.0) * CHUNK_SIZE) <= INNER_HALF

func _cell_fully_outside_origin(cx: int, cz: int) -> bool:
	var min_x := float(cx) * CHUNK_SIZE
	var max_x := (float(cx) + 1.0) * CHUNK_SIZE
	var min_z := float(cz) * CHUNK_SIZE
	var max_z := (float(cz) + 1.0) * CHUNK_SIZE
	var best_x := min_x if absf(min_x) <= absf(max_x) else max_x
	var best_z := min_z if absf(min_z) <= absf(max_z) else max_z
	return Vector2(best_x, best_z).length() > 140.0

func _build_terrain_tile(chunk: Node3D, min_world: Vector3) -> void:
	if _is_inner_cell(int(floor(min_world.x / CHUNK_SIZE)),
			int(floor(min_world.z / CHUNK_SIZE))):
		return
	var body := StaticBody3D.new()
	body.name = "StreamTerrain"
	body.collision_layer = 32
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	body.add_child(collider)
	var mesh := MeshInstance3D.new()
	mesh.name = "StreamTerrainMesh"
	var terrain_mesh := _make_terrain_tile_mesh(min_world)
	mesh.mesh = terrain_mesh
	if _terrain_material != null:
		mesh.material_override = _terrain_material
	collider.shape = terrain_mesh.create_trimesh_shape()
	body.add_child(mesh)
	chunk.add_child(body)

	## Two material_override instances share one resource; also reserve the
	## tile locally in case the core terrain palette is unavailable.
	if _terrain_material == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.22, 0.26, 0.16)
		fallback.roughness = 1.0
		mesh.material_override = fallback

func _make_terrain_tile_mesh(min_world: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := TILE_SUBDIVISIONS
	var step := CHUNK_SIZE / float(cells)
	for ix in range(cells):
		for iz in range(cells):
			var x0 := min_world.x + float(ix) * step
			var x1 := x0 + step
			var z0 := min_world.z + float(iz) * step
			var z1 := z0 + step
			var a := Vector3(x0, _surface_height(Vector2(x0, z0)), z0)
			var b := Vector3(x1, _surface_height(Vector2(x1, z0)), z0)
			var c := Vector3(x1, _surface_height(Vector2(x1, z1)), z1)
			var d := Vector3(x0, _surface_height(Vector2(x0, z1)), z1)
			surface.add_vertex(a - Vector3(min_world.x, 0.0, min_world.z))
			surface.add_vertex(b - Vector3(min_world.x, 0.0, min_world.z))
			surface.add_vertex(c - Vector3(min_world.x, 0.0, min_world.z))
			surface.add_vertex(a - Vector3(min_world.x, 0.0, min_world.z))
			surface.add_vertex(c - Vector3(min_world.x, 0.0, min_world.z))
			surface.add_vertex(d - Vector3(min_world.x, 0.0, min_world.z))
	surface.generate_normals()
	return surface.commit()

func _build_grass(chunk: Node3D, min_world: Vector3, chunk_center_world: Vector3,
		hero_center: Vector3, rng: RandomNumberGenerator,
		band_filter: String = "") -> void:
	var near := chunk_center_world.distance_to(hero_center) <= NEAR_ZONE
	chunk.set_meta("near_grass", near)
	# Build all bands from the same seeded chunk lattice. This guarantees a
	# visible grass layer at every streamed block while allowing geometry cost
	# to fall sharply with distance.
	var mobile := _is_mobile_runtime()
	if band_filter.is_empty() or band_filter == "near":
		_build_grass_band(chunk, min_world, rng, "near", _near_spacing(),
				_grass_mesh, 1200 if mobile else 2200, 0)
	if band_filter.is_empty() or band_filter == "mid":
		_build_grass_band(chunk, min_world, rng, "mid", 1.8 / sqrt(_grass_density),
				_grass_mid_mesh, 500 if mobile else 1100, 1)
	if band_filter.is_empty() and not mobile and _effective_world_radius() >= 190.0:
		_build_grass_band(chunk, min_world, rng, "far", float(_tier["far"]),
				_grass_far_mesh, 450, 2)

## Each instance is a multi-blade clump. A one-metre grid gives continuous
## coverage without the old duplicate half-metre carpet's overdraw cost.
func _near_spacing() -> float:
	return clampf(CARPET_SPACING / sqrt(_grass_density), 0.95, 1.8)

func _build_grass_band(chunk: Node3D, min_world: Vector3,
		rng: RandomNumberGenerator, band: String, spacing: float,
		mesh: ArrayMesh, base_cap: int, band_index: int) -> void:
	spacing = maxf(spacing, 1.0)
	var range_n := int(ceil(CHUNK_SIZE / spacing))
	var start := (CHUNK_SIZE - float(range_n) * spacing) * 0.5
	var transforms: Array[Transform3D] = []
	var max_count := maxi(96, int(round(base_cap * _grass_density)))
	for i in range(range_n):
		for j in range(range_n):
			var local := Vector2(start + float(i) * spacing, start + float(j) * spacing)
			if local.x >= CHUNK_SIZE or local.y >= CHUNK_SIZE:
				continue
			local += Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)) * spacing
			var world := Vector2(min_world.x + local.x, min_world.z + local.y)
			var clearance := _clearance_strength(world)
			if clearance >= 0.98:
				continue
			if clearance > 0.0 and rng.randf() < clearance * (0.82 if band == "near" else 0.55):
				continue
			var ground_y := _surface_height(world)
			var scale := rng.randf_range(0.72, 1.08)
			if band == "mid":
				scale *= 0.90
			elif band == "far":
				scale *= 0.72
			var basis := Basis.from_euler(Vector3(rng.randf_range(-0.10, 0.10),
				rng.randf() * TAU, rng.randf_range(-0.10, 0.10))).scaled(
				Vector3(scale, scale, scale))
			transforms.append(Transform3D(basis, Vector3(local.x, ground_y + 0.015, local.y)))
			if transforms.size() >= max_count:
				break
		if transforms.size() >= max_count:
			break
	_emit_grass_band(chunk, transforms, mesh, band, band_index)

func _emit_grass_band(chunk: Node3D, transforms: Array[Transform3D],
		mesh: ArrayMesh, band: String, band_index: int) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.custom_aabb = AABB(Vector3(-2, -2, -2),
		Vector3(CHUNK_SIZE + 4.0, 12.0, CHUNK_SIZE + 4.0))
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassCarpet" if band == "near" else "GrassCarpet_%s" % band
	mmi.multimesh = mm
	mmi.material_override = _grass_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ranges := _grass_ranges()
	mmi.visibility_range_begin = ranges[band_index * 2]
	mmi.visibility_range_end = ranges[band_index * 2 + 1]
	mmi.visibility_range_end_margin = 18.0
	mmi.set_meta("coverage_min", mmi.visibility_range_begin)
	mmi.set_meta("coverage_max", mmi.visibility_range_end)
	mmi.set_meta("source_layer", band)
	mmi.set_meta("chunk_key", chunk.name)
	chunk.add_child(mmi)

func performance_report() -> Dictionary:
	var grass_instances := 0
	var grass_batches := 0
	for chunk_value in _chunks.values():
		var chunk := chunk_value as Node3D
		if chunk == null:
			continue
		for child in chunk.get_children():
			var grass := child as MultiMeshInstance3D
			if grass == null or grass.multimesh == null or not str(grass.name).begins_with("GrassCarpet"):
				continue
			grass_batches += 1
			grass_instances += grass.multimesh.instance_count
	return {"chunks": _chunks.size(), "grass_instances": grass_instances,
		"grass_batches": grass_batches, "generation_usec": _last_generation_usec,
		"mobile": _is_mobile_runtime(), "queue_length": _generation_queue.size(),
		"chunks_built": _chunks_built_total, "last_build_ms": _last_chunk_build_ms,
		"max_build_ms": _max_chunk_build_ms, "mobile_budget_ms": mobile_stream_budget_ms,
		"last_process_ms": float(_last_generation_usec) / 1000.0,
		"decoration_queue_length": _decoration_queue.size(),
		"movement_callbacks": _movement_callbacks, "last_movement_msec": _last_movement_msec,
		"mobile_build_phase": _mobile_chunk_phase,
		"mobile_build_key": _mobile_chunk_key}

func stall_context_report() -> Dictionary:
	return {"queue_length": _generation_queue.size(),
		"decoration_queue_length": _decoration_queue.size(),
		"mobile_build_phase": _mobile_chunk_phase,
		"last_build_ms": _last_chunk_build_ms,
		"max_build_ms": _max_chunk_build_ms,
		"movement_callbacks": _movement_callbacks}

func _batch_mm(chunk: Node3D, name: String, mesh: Mesh, material: Material,
		transforms: Array[Transform3D], cast_shadows: bool) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.custom_aabb = AABB(Vector3(-4, -2, -4), Vector3(68, 14, 68))
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = material
	if cast_shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(mmi)

## Scatter authoritative counts while honouring gameplay clearances. The target
## band is the authored chunk density; skipping a cleared candidate without a
## top-up would leave a chunk that overlaps an arena nearly bare (previously the
## decoration disappeared instead of relocating). `_clearance_blocks` still wins,
## so cleared ground is never covered, and chunks with no clearance accept
## exactly the same first `target` candidates as before.
func _fill_scatter(target: int, min_world: Vector3, rng: RandomNumberGenerator,
		make_transform: Callable) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	if target <= 0:
		return transforms
	var attempts := 0
	var max_attempts := maxi(target * 8, 24)
	while transforms.size() < target and attempts < max_attempts:
		attempts += 1
		var local := Vector2(rng.randf(), rng.randf()) * CHUNK_SIZE
		var world := Vector2(min_world.x + local.x, min_world.z + local.y)
		if _clearance_blocks(world):
			continue
		transforms.append(make_transform.call(local, world) as Transform3D)
	return transforms

func _build_trees(chunk: Node3D, min_world: Vector3, rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(7, 11)
	var transforms := _fill_scatter(count, min_world, rng,
		func(local: Vector2, world: Vector2) -> Transform3D:
			var s := rng.randf_range(0.75, 1.25)
			var basis := Basis.from_euler(Vector3(0.0, rng.randf() * TAU, 0.0)).scaled(
				Vector3(s, rng.randf_range(0.85, 1.15), s))
			return Transform3D(basis, Vector3(local.x, _surface_height(world), local.y)))
	_batch_mm(chunk, "StreamTrees", _tree_mesh, null, transforms, true)

func _build_rocks_and_bushes(chunk: Node3D, min_world: Vector3,
		rng: RandomNumberGenerator) -> void:
	var rock_count := rng.randi_range(8, 14)
	var rock_transforms := _fill_scatter(rock_count, min_world, rng,
		func(local: Vector2, world: Vector2) -> Transform3D:
			var s := rng.randf_range(0.35, 1.0)
			var basis := Basis.from_euler(Vector3(rng.randf_range(-0.2, 0.2),
				rng.randf() * TAU, rng.randf_range(-0.2, 0.2))).scaled(
				Vector3(s, rng.randf_range(0.5, 0.85), s))
			return Transform3D(basis, Vector3(local.x, _surface_height(world) + 0.05, local.y)))
	_batch_mm(chunk, "StreamRocks", _rock_mesh, _rock_material, rock_transforms, true)

	var bush_count := rng.randi_range(5, 11)
	var bush_transforms := _fill_scatter(bush_count, min_world, rng,
		func(local: Vector2, world: Vector2) -> Transform3D:
			var s := rng.randf_range(0.6, 1.3)
			var basis := Basis.from_euler(Vector3(0.0, rng.randf() * TAU, 0.0)).scaled(
				Vector3(s, rng.randf_range(0.7, 1.3), s))
			return Transform3D(basis, Vector3(local.x, _surface_height(world) + 0.02, local.y)))
	_batch_mm(chunk, "StreamBushes", _bush_mesh, _bush_material, bush_transforms, true)

func _build_deadwood(chunk: Node3D, min_world: Vector3,
		rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(0, 3)
	var transforms: Array[Transform3D] = []
	for i in count:
		var local := Vector2(rng.randf(), rng.randf()) * CHUNK_SIZE
		var world := Vector2(min_world.x + local.x, min_world.z + local.y)
		if _clearance_blocks(world):
			continue
		var basis := Basis.from_euler(Vector3(0.0, rng.randf() * TAU, 0.0)).rotated(
			Vector3(1.0, 0.0, 0.0), rng.randf_range(-0.15, 0.15)).scaled(
				Vector3(rng.randf_range(0.7, 1.3), 1.0, rng.randf_range(0.7, 1.3)))
		transforms.append(Transform3D(basis,
			Vector3(local.x, _surface_height(world) + 0.08, local.y)))
	_batch_mm(chunk, "StreamDeadwood", _deadwood_mesh, _deadwood_material,
		transforms, true)

## ---- Flavor: ruined settlements and ponds, far from the authored core ----
func _build_flavor(chunk: Node3D, min_world: Vector3, chunk_center_world: Vector3,
		rng: RandomNumberGenerator) -> void:
	if not _cell_fully_outside_origin(int(floor(min_world.x / CHUNK_SIZE)),
			int(floor(min_world.z / CHUNK_SIZE))):
		return
	var roll := rng.randf()
	if roll < 0.14:
		_build_ruins(chunk, min_world, rng)
	elif roll < 0.26:
		_build_pond(chunk, min_world, rng)

func _build_ruins(chunk: Node3D, min_world: Vector3, rng: RandomNumberGenerator) -> void:
	var group := Node3D.new()
	group.name = "StreamRuins"
	chunk.add_child(group)
	var anchor := Vector3(rng.randf_range(6.0, 54.0), 0.0, rng.randf_range(6.0, 54.0))
	var wall_count := rng.randi_range(2, 3)
	for i in wall_count:
		var wall := MeshInstance3D.new()
		wall.name = "RuinWall"
		var box := BoxMesh.new()
		var h := rng.randf_range(0.9, 1.6)
		box.size = Vector3(rng.randf_range(2.0, 3.2), h, 0.5)
		wall.mesh = box
		wall.material_override = _stone_material
		wall.position = anchor + Vector3(
			rng.randf_range(-1.6, 1.6) * (wall_count - i), h * 0.5,
			rng.randf_range(-1.6, 1.6) * (wall_count - i))
		wall.rotation.y = rng.randf() * TAU
		group.add_child(wall)
	# Ruins sit directly on the streamed terrain.  A flat BoxMesh floor makes
	# an isolated square patch at chunk distance and exposes the terrain tile
	# boundary to the camera.
	## Scattered bones and a charred beam.
	for b in rng.randi_range(4, 7):
		var bone := MeshInstance3D.new()
		bone.name = "Bone"
		var bone_mesh := CylinderMesh.new()
		bone_mesh.top_radius = 0.022
		bone_mesh.bottom_radius = 0.03
		bone_mesh.height = rng.randf_range(0.18, 0.34)
		bone_mesh.radial_segments = 4
		bone.mesh = bone_mesh
		bone.material_override = StandardMaterial3D.new()
		(bone.material_override as StandardMaterial3D).albedo_color = Color(0.82, 0.79, 0.72)
		var bone_pos := anchor + Vector3(rng.randf_range(-1.4, 1.4), 0.05,
			rng.randf_range(-1.4, 1.4))
		bone.position = bone_pos
		bone.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		group.add_child(bone)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.09
	beam_mesh.bottom_radius = 0.12
	beam_mesh.height = 2.6
	beam_mesh.radial_segments = 5
	beam.mesh = beam_mesh
	beam.material_override = _deadwood_material
	beam.position = anchor + Vector3(0.0, 0.35, 0.0)
	beam.rotation = Vector3(0.9, rng.randf() * TAU, 0.3)
	group.add_child(beam)

func _build_pond(chunk: Node3D, min_world: Vector3, rng: RandomNumberGenerator) -> void:
	var group := Node3D.new()
	group.name = "StreamPond"
	chunk.add_child(group)
	var center := Vector3(rng.randf_range(8.0, 52.0), 0.0, rng.randf_range(8.0, 52.0))
	var water_mesh := QuadMesh.new()
	var half := rng.randf_range(2.6, 4.4)
	water_mesh.size = Vector2(half * 2.0, half * 1.4)
	var water_mat := StandardMaterial3D.new()
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.albedo_color = Color(0.10, 0.24, 0.30, 0.72)
	water_mat.roughness = 0.25
	water_mat.refraction_enabled = true
	var water := MeshInstance3D.new()
	water.mesh = water_mesh
	water.material_override = water_mat
	water.name = "WaterBody"
	water.transform = Transform3D(
		Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)),
		center + Vector3(0.0, 0.06, 0.0))
	group.add_child(water)
	for s in rng.randi_range(6, 10):
		var stone := MeshInstance3D.new()
		var stone_mesh := SphereMesh.new()
		stone_mesh.radius = 0.5
		stone_mesh.height = 0.5
		stone_mesh.radial_segments = 5
		stone_mesh.rings = 3
		stone.mesh = stone_mesh
		stone.material_override = _rock_material
		var ang := rng.randf() * TAU
		var dist := half + rng.randf_range(-0.3, 0.9)
		var stone_pos := Vector2(center.x + cos(ang) * dist, center.z + sin(ang) * dist)
		stone.position = Vector3(stone_pos.x, 0.1, stone_pos.y)
		stone.scale = Vector3.ONE * rng.randf_range(0.5, 1.2)
		group.add_child(stone)

## ---- Public contract for tests ----
func is_active() -> bool:
	return _active

func debug_center_on(world_position: Vector3) -> void:
	_last_center = Vector2i(1 << 30, 1 << 30)
	_rebuild_ring(world_position)

func get_world_seed() -> int:
	return WORLD_SEED

func get_chunk_count() -> int:
	return _chunks.size()

func get_tier_spec() -> Dictionary:
	return {
		"radius": _effective_world_radius(),
		"near": _near_spacing(),
		"far": float(_tier["far"]),
		"near_zone": NEAR_ZONE,
		"density": _grass_density,
		"view_scale": _world_view_scale(),
	}

func get_runtime_diagnostics() -> Dictionary:
	var grass_instances := 0
	var grass_by_band := {"near": 0, "mid": 0, "far": 0}
	var grass_batches := 0
	for chunk_value in _chunks.values():
		var chunk := chunk_value as Node3D
		if chunk == null:
			continue
		for child in chunk.get_children():
			var grass := child as MultiMeshInstance3D
			if grass == null or grass.multimesh == null or not str(grass.name).begins_with("GrassCarpet"):
				continue
			grass_batches += 1
			var count := grass.multimesh.instance_count
			grass_instances += count
			var band := str(grass.get_meta("source_layer", "near"))
			grass_by_band[band] = int(grass_by_band.get(band, 0)) + count
	return {
		"realm": _realm_id,
		"active_chunks": _chunks.size(),
		"queued_chunks": _generation_queue.size(),
		"grass_instances": grass_instances,
		"grass_batches": grass_batches,
		"grass_by_band": grass_by_band,
		"last_generation_ms": float(_last_generation_usec) / 1000.0,
		"resident_far_fill": grass_by_band["far"] > 0,
		"quality_radius": _effective_world_radius(),
		"world_view_scale": _world_view_scale(),
	}
