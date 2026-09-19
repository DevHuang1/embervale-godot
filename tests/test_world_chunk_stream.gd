extends SceneTree

## Headless validation of the world chunk streamer.
## - One deterministic chunk owner serves every realm.
## - Deterministic world content: two boots build identical chunk content.
## - Per-chunk caps hold (grass, trees, rocks, bushes) and the arena route
##   stays clear of grass.
## - Terrain tiles stay under the 65,535-vertex compatibility index limit.
## - Moving the stream center spawns and despawns chunks (ring stays sized).
## - Wall collision barriers relocate to the extended ±1001 m boundary.

const STREAM_REALMS := ["bramblewood", "whispergrove", "mistfen", "heartwood"]

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(90.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — world chunk stream test hung")
		quit(2))

func _boot_grove(realm: String) -> Node:
	var gs := root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()
	gs.set_current_realm(realm)
	var scene: Node = (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame
	var streamer := scene.find_child("WorldStreamer", true, false)
	for _frame in 80:
		if streamer != null:
			var report := streamer.call("get_runtime_diagnostics") as Dictionary
			if int(report.get("queued_chunks", 0)) == 0:
				break
		await process_frame
	return scene

func _run() -> void:
	var failures := 0

	## 1. Determinism: two whispergrove boots produce identical chunk content.
	var snapshot_a := await _snapshot("whispergrove")
	var snapshot_b := await _snapshot("whispergrove")
	if not snapshot_a.get("active", false) or not snapshot_b.get("active", false):
		failures += 1
		print("FAIL: streamer failed to activate during determinism check")
	elif snapshot_a != snapshot_b:
		failures += 1
		print("FAIL: streamed world content not deterministic across boots")

	## 2. Caps + clearance + tile limit observed on a single boot.
	failures += await _check_caps("bramblewood")

	## 3. Stream center movement spawns and despawns chunks.
	failures += await _check_movement("whispergrove")

	## 3b. Streamed flavor props (ruins, ponds) conform to the relief surface.
	failures += await _check_flavor_conformity("whispergrove")

	## 3c. Rivers, bridges, vines and multi-type trees exist and hold clear.
	failures += await _check_river_and_undergrowth("bramblewood")

	## 4. Other inherited realm scenes use the same procedural owner.
	for realm in ["mistfen", "heartwood"]:
		failures += await _check_active_realm(realm)

	var audio_final := root.get_node("/root/AudioManager")
	if audio_final != null:
		audio_final.stop_all_playback()
	for i in 3:
		await process_frame

	if failures == 0:
		print("ALL WORLD CHUNK STREAM TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)


func _snapshot(realm: String) -> Dictionary:
	var snapshot := {}
	var scene := await _boot_grove(realm)
	var streamer := scene.find_child("WorldStreamer", true, false)
	if streamer == null or not streamer.call("is_active"):
		snapshot["active"] = false
		scene.queue_free()
		await process_frame
		return snapshot
	snapshot["active"] = true
	snapshot["seed"] = int(streamer.call("get_world_seed"))
	snapshot["chunks"] = int(streamer.call("get_chunk_count"))
	var counts := {}
	for chunk_node in streamer.get_children():
		if not str(chunk_node.name).begins_with("StreamChunk_"):
			continue
		var grass := 0
		var trees := 0
		var rocks := 0
		var bushes := 0
		var vines := 0
		for child in chunk_node.get_children():
			var batch_name := str(child.name)
			if batch_name == "GrassCarpet":
				grass = (child as MultiMeshInstance3D).multimesh.instance_count
			elif batch_name.begins_with("StreamTrees"):
				trees += (child as MultiMeshInstance3D).multimesh.instance_count
			elif batch_name == "StreamRocks":
				rocks = (child as MultiMeshInstance3D).multimesh.instance_count
			elif batch_name.begins_with("StreamBushes"):
				bushes += (child as MultiMeshInstance3D).multimesh.instance_count
			elif batch_name == "StreamVines":
				vines = (child as MultiMeshInstance3D).multimesh.instance_count
		counts[str(chunk_node.name)] = [grass, trees, rocks, bushes, vines]
	snapshot["content"] = counts
	scene.queue_free()
	await process_frame
	return snapshot

func _check_caps(realm: String) -> int:
	var f := 0
	var scene := await _boot_grove(realm)
	var streamer := scene.find_child("WorldStreamer", true, false)
	if streamer == null or not streamer.call("is_active"):
		f += 1
		print("FAIL: %s streamer inactive" % realm)
		scene.queue_free()
		await process_frame
		return f
	var activity_director := scene.find_child("RealmActivityDirector", true, false)
	if activity_director == null:
		f += 1
		print("FAIL: %s activity director missing from streamed realm" % realm)
	else:
		var activity_report: Dictionary = activity_director.call("get_diagnostics")
		if int(activity_report.get("active_combat_count", 0)) > 2:
			f += 1
			print("FAIL: %s streamed activity combat cap exceeded" % realm)

	var boss_anchors := RealmLayoutData.boss_anchor_points(realm)
	var chunk_total := 0
	for chunk_node in streamer.get_children():
		if not str(chunk_node.name).begins_with("StreamChunk_"):
			continue
		chunk_total += 1
		var grass_count := 0
		var tree_count := 0
		var bush_count := 0
		for child in chunk_node.get_children():
			if child.name == "GrassCarpet":
				grass_count = (child as MultiMeshInstance3D).multimesh.instance_count
				if grass_count > 2600:
					f += 1
					print("FAIL: %s chunk %s grass exceeds cap (%d)" \
						% [realm, chunk_node.name, grass_count])
				for i in grass_count:
					var origin := (child as MultiMeshInstance3D).multimesh \
						.get_instance_transform(i).origin
					var world_pos := Vector2((child as MultiMeshInstance3D).global_position.x,
						(child as MultiMeshInstance3D).global_position.z) \
						+ Vector2(origin.x, origin.z)
					for boss_anchor in boss_anchors:
						if world_pos.distance_to(boss_anchor) < RealmLayoutData.BOSS_ARENA_CLEARANCE_RADIUS:
							f += 1
							print("FAIL: %s streamed grass inside boss arena" % realm)
							break
			elif str(child.name).begins_with("StreamTrees"):
				tree_count += (child as MultiMeshInstance3D).multimesh.instance_count
			elif child.name == "StreamRocks":
				var rocks := (child as MultiMeshInstance3D).multimesh.instance_count
				if rocks < 8 or rocks > 16:
					f += 1
					print("FAIL: %s chunk %s rock count out of band (%d)" \
						% [realm, chunk_node.name, rocks])
			elif str(child.name).begins_with("StreamBushes"):
				bush_count += (child as MultiMeshInstance3D).multimesh.instance_count
			elif child.name == "StreamTerrainMesh":
				var arrays := (child as MeshInstance3D).mesh.surface_get_arrays(0)
				var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				if vertices.size() > 65535:
					f += 1
					print("FAIL: %s tile exceeds compatibility vertex limit (%d)" \
						% [realm, vertices.size()])
		if tree_count < 7 or tree_count > 11:
			f += 1
			print("FAIL: %s chunk %s tree count out of band (%d)" \
				% [realm, chunk_node.name, tree_count])
		if bush_count < 5 or bush_count > 11:
			f += 1
			print("FAIL: %s chunk %s bush count out of band (%d)" \
				% [realm, chunk_node.name, bush_count])
	if chunk_total < 9:
		f += 1
		print("FAIL: %s streamer built too few chunks (%d)" % [realm, chunk_total])
	if realm == "bramblewood":
		for pocket_value in RealmLayoutData.profile(realm).get("expansion_pockets", []):
			var pocket: Dictionary = pocket_value as Dictionary
			var position: Vector3 = pocket.get("position", Vector3.ZERO)
			if not bool(streamer.call("_clearance_blocks", Vector2(position.x, position.z))):
				f += 1
				print("FAIL: Bramblewood pocket lacks streamer clearance -> ",
					str(pocket.get("id", "")))
	for boss_anchor in boss_anchors:
		if not bool(streamer.call("_clearance_blocks", boss_anchor)):
			f += 1
			print("FAIL: %s boss anchor lacks streamer clearance -> %s" % [realm, boss_anchor])

	## Walls moved to the extended boundary only when streaming.
	var world_bounds := scene.get_node_or_null("WorldBounds")
	if world_bounds != null:
		var wall := world_bounds.get_node_or_null("WallEast") as CollisionShape3D
		if wall == null or wall.position.x < 900.0:
			f += 1
			print("FAIL: %s east wall not relocated for streamed realm" % realm)

	## No resident all-world far-fill is allowed; it caused the startup hitch.
	var far_fill_group := scene.find_child("GrassFarFill", true, false)
	if far_fill_group != null:
		f += 1
		print("FAIL: %s still creates resident GrassFarFill" % realm)
	scene.queue_free()
	await process_frame
	return f


func _check_movement(realm: String) -> int:
	var f := 0
	var scene := await _boot_grove(realm)
	var streamer := scene.find_child("WorldStreamer", true, false)
	if streamer == null or not streamer.call("is_active"):
		scene.queue_free()
		await process_frame
		return f
	var first_count := int(streamer.call("get_chunk_count"))
	streamer.call("debug_center_on", Vector3(500.0, 0.0, 300.0))
	for i in 4:
		await process_frame
	var moved_count := int(streamer.call("get_chunk_count"))
	if moved_count > first_count * 2:
		f += 1
		print("FAIL: stream grew without bound after teleport (%d -> %d)" \
			% [first_count, moved_count])
	streamer.call("debug_center_on", Vector3(-500.0, 0.0, -300.0))
	for i in 4:
		await process_frame
	var count_after_move := int(streamer.call("get_chunk_count"))
	if count_after_move > 0 and count_after_move > moved_count + 4:
		f += 1
		print("FAIL: stream did not despawn on relocation (%d -> %d)" \
			% [moved_count, count_after_move])
	f += _check_tree_silhouette(streamer)
	scene.queue_free()
	await process_frame
	return f

## Streamed trees must be base-anchored (instance transform is ground contact)
## and carry visible limbs; the old centered trunk buried half the tree and a
## bare pole under a dome gave the far canopy no structure.
func _check_tree_silhouette(streamer: Node) -> int:
	var mesh := streamer.get("_tree_mesh") as ArrayMesh
	if mesh == null or mesh.get_surface_count() != 2:
		print("FAIL: streamed tree mesh lost its trunk/canopy surfaces")
		return 1
	var surface := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	var min_y := INF
	var max_y := -INF
	var half_x := 0.0
	for vertex in vertices:
		min_y = minf(min_y, vertex.y)
		max_y = maxf(max_y, vertex.y)
		half_x = maxf(half_x, absf(vertex.x))
	var f := 0
	if min_y < -0.05 or min_y > 0.05:
		f += 1
		print("FAIL: streamed tree trunk is not base-anchored (min y %.2f)" % min_y)
	if half_x < 0.45:
		f += 1
		print("FAIL: streamed tree trunk has no limb spread (half width %.2f)" % half_x)
	if max_y < 3.0:
		f += 1
		print("FAIL: streamed tree trunk does not reach its canopy (max y %.2f)" % max_y)
	if f == 0:
		print("PASS: streamed trees are base-anchored and branched")
	return f


## Streamed ruins and ponds must sit on the sampled relief, not at y=0.
func _check_flavor_conformity(realm: String) -> int:
	var f := 0
	var scene := await _boot_grove(realm)
	var streamer := scene.find_child("WorldStreamer", true, false)
	if streamer == null or not streamer.call("is_active"):
		f += 1
		print("FAIL: flavor conformity needs an active streamer")
		scene.queue_free()
		await process_frame
		return f
	var chunk := Node3D.new()
	chunk.name = "FlavorProbeChunk"
	var min_world := Vector3(640.0, 0.0, 384.0)
	chunk.position = min_world
	streamer.add_child(chunk)
	var surf := func(x: float, z: float) -> float:
		return float(streamer.call("_surface_height", Vector2(x, z)))
	var pond_rng := RandomNumberGenerator.new()
	pond_rng.seed = 4242
	streamer.call("_build_pond", chunk, min_world, pond_rng)
	var ruin_rng := RandomNumberGenerator.new()
	ruin_rng.seed = 1717
	streamer.call("_build_ruins", chunk, min_world, ruin_rng)
	for group in chunk.get_children():
		if group.name == "StreamPond":
			for child in group.get_children():
				if child is MeshInstance3D and child.name == "WaterBody":
					f += _check_water_conforms(child as MeshInstance3D, min_world, surf)
				elif child is MeshInstance3D:
					f += _check_prop_conforms(child as MeshInstance3D, min_world, surf, 0.10)
		elif group.name == "StreamRuins":
			for child in group.get_children():
				if child is MeshInstance3D and child.name == "RuinWall":
					var wall := child as MeshInstance3D
					var height := (wall.mesh as BoxMesh).size.y if wall.mesh is BoxMesh else 0.0
					var base := wall.position.y - height * 0.5
					var ground := float(surf.call(min_world.x + wall.position.x,
						min_world.z + wall.position.z))
					if absf(base - ground) > 0.05:
						f += 1
						print("FAIL: StreamRuin wall base %.3f vs ground %.3f" \
							% [base, ground])
				elif child is MeshInstance3D and child.name == "Bone":
					var bone := child as MeshInstance3D
					var ground := float(surf.call(min_world.x + bone.position.x,
						min_world.z + bone.position.z))
					if absf((bone.position.y - 0.05) - ground) > 0.02:
						f += 1
						print("FAIL: StreamRuin bone floats at %.3f vs ground %.3f" \
							% [bone.position.y - 0.05, ground])
	chunk.queue_free()
	scene.queue_free()
	await process_frame
	if f == 0:
		print("PASS: streamed flavor conforms to the relief surface")
	return f

## Pond water is a flat plane: it must sit just above the lowest footprint
## corner so a rolling swell never pierces the middle of the pool.
func _check_water_conforms(water: MeshInstance3D, min_world: Vector3,
		surf: Callable) -> int:
	var quad := water.mesh as QuadMesh
	if quad == null:
		print("FAIL: pond water is not a QuadMesh")
		return 1
	var half_x := quad.size.x * 0.5
	var half_z := quad.size.y * 0.5
	var lowest := INF
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			var corner := water.transform * Vector3(half_x * x_sign, half_z * z_sign, 0.0)
			lowest = minf(lowest, float(surf.call(
				min_world.x + corner.x, min_world.z + corner.z)))
	if absf(water.transform.origin.y - (lowest + 0.05)) > 0.01:
		print("FAIL: pond water %.3f vs lowest bank %.3f" \
			% [water.transform.origin.y, lowest + 0.05])
		return 1
	return 0

func _check_prop_conforms(prop: MeshInstance3D, min_world: Vector3,
		surf: Callable, sink: float) -> int:
	var ground := float(surf.call(min_world.x + prop.position.x,
		min_world.z + prop.position.z))
	var expected := ground + sink * prop.scale.x
	if absf(prop.position.y - expected) > 0.02:
		print("FAIL: streamed prop %s sits at %.3f, expected %.3f" \
			% [prop.name, prop.position.y, expected])
		return 1
	return 0

## River presentation, bridge collision, riverbank clearance and undergrowth
## variety (multi-type trees and vines) in the streamed ring.
func _check_river_and_undergrowth(realm: String) -> int:
	var f := 0
	var scene := await _boot_grove(realm)
	var streamer := scene.find_child("WorldStreamer", true, false)
	if streamer == null or not streamer.call("is_active"):
		f += 1
		print("FAIL: river check needs an active streamer")
		scene.queue_free()
		await process_frame
		return f
	var spec := WorldWaterways.river_for(realm)
	var water := streamer.find_child("RiverWater", true, false) as MeshInstance3D
	if water == null or water.mesh == null or water.mesh.get_surface_count() == 0:
		f += 1
		print("FAIL: %s streamed river has no water ribbon" % realm)
	else:
		var vertices := water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] \
			as PackedVector3Array
		if vertices.size() < 200:
			f += 1
			print("FAIL: %s river ribbon is too short (%d verts)" \
				% [realm, vertices.size()])
		var half := WorldWaterways.water_half_width(spec)
		for vertex in vertices:
			if WorldWaterways.lateral_distance(spec, Vector2(vertex.x, vertex.z)) > half + 0.1:
				f += 1
				print("FAIL: %s river ribbon leaves its channel" % realm)
				break
	var bridge := streamer.find_child("RiverBridge", true, false) as StaticBody3D
	if bridge == null:
		f += 1
		print("FAIL: %s river has no bridge" % realm)
	else:
		var shapes := bridge.find_children("*", "CollisionShape3D", true, false)
		if shapes.size() < 3 or float(bridge.get_meta("bridge_span", 0.0)) < 8.0:
			f += 1
			print("FAIL: %s bridge has no walkable deck collision" % realm)
	var stones := streamer.find_child("RiverStones", true, false) as MultiMeshInstance3D
	if stones == null or stones.multimesh == null or stones.multimesh.instance_count == 0:
		f += 1
		print("FAIL: %s riverbanks have no stone dressing" % realm)

	var tree_families := {}
	var vine_total := 0
	var reach := WorldWaterways.carve_reach(spec)
	for chunk_node in streamer.get_children():
		if not str(chunk_node.name).begins_with("StreamChunk_"):
			continue
		for child in chunk_node.get_children():
			var batch := child as MultiMeshInstance3D
			if batch == null or batch.multimesh == null:
				continue
			var batch_name := str(batch.name)
			if batch_name.begins_with("StreamVines"):
				vine_total += batch.multimesh.instance_count
				continue
			if batch_name.begins_with("StreamTrees") or batch_name.begins_with("StreamBushes") \
					or batch_name == "StreamRocks":
				if batch.multimesh.instance_count > 0:
					tree_families[batch_name] = true
				for i in batch.multimesh.instance_count:
					var origin := batch.multimesh.get_instance_transform(i).origin
					var world_xz := Vector2(batch.global_position.x + origin.x,
						batch.global_position.z + origin.z)
					if WorldWaterways.lateral_distance(spec, world_xz) < reach:
						f += 1
						print("FAIL: %s %s rooted inside the river channel" \
							% [realm, batch_name])
						break
	if tree_families.size() < 3:
		f += 1
		print("FAIL: %s streamed world has fewer than three prop families" % realm)
	if vine_total == 0:
		f += 1
		print("FAIL: %s streamed trees carry no vines" % realm)
	scene.queue_free()
	await process_frame
	if f == 0:
		print("PASS: river, bridge, vines and multi-type trees hold")
	return f

func _check_active_realm(realm: String) -> int:
	var f := 0
	var scene_path := "res://scenes/world/%s.tscn" % realm
	if not ResourceLoader.exists(scene_path):
		print("FAIL: missing realm scene %s" % scene_path)
		return f
	var gs := root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()
	gs.set_current_realm(realm)
	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	root.add_child(scene)
	for i in 8:
		await process_frame
	var streamer := scene.find_child("WorldStreamer", true, false)
	if streamer == null or not streamer.call("is_active"):
		f += 1
		print("FAIL: %s must use the shared procedural streamer" % realm)
	scene.queue_free()
	await process_frame
	return f
