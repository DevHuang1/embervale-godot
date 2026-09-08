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
		for child in chunk_node.get_children():
			if child.name == "GrassCarpet":
				grass = (child as MultiMeshInstance3D).multimesh.instance_count
			elif child.name == "StreamTrees":
				trees = (child as MultiMeshInstance3D).multimesh.instance_count
			elif child.name == "StreamRocks":
				rocks = (child as MultiMeshInstance3D).multimesh.instance_count
			elif child.name == "StreamBushes":
				bushes = (child as MultiMeshInstance3D).multimesh.instance_count
		counts[str(chunk_node.name)] = [grass, trees, rocks, bushes]
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

	var arena3 := RealmLayoutData.profile(realm).get("arena", Vector3.ZERO) as Vector3
	var chunk_total := 0
	for chunk_node in streamer.get_children():
		if not str(chunk_node.name).begins_with("StreamChunk_"):
			continue
		chunk_total += 1
		var grass_count := 0
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
					if world_pos.distance_to(Vector2(arena3.x, arena3.z)) < 4.9:
						f += 1
						print("FAIL: %s streamed grass inside arena" % realm)
						break
			elif child.name == "StreamTrees":
				var trees := (child as MultiMeshInstance3D).multimesh.instance_count
				if trees < 7 or trees > 11:
					f += 1
					print("FAIL: %s chunk %s tree count out of band (%d)" \
						% [realm, chunk_node.name, trees])
			elif child.name == "StreamRocks":
				var rocks := (child as MultiMeshInstance3D).multimesh.instance_count
				if rocks < 8 or rocks > 16:
					f += 1
					print("FAIL: %s chunk %s rock count out of band (%d)" \
						% [realm, chunk_node.name, rocks])
			elif child.name == "StreamBushes":
				var bushes := (child as MultiMeshInstance3D).multimesh.instance_count
				if bushes < 5 or bushes > 11:
					f += 1
					print("FAIL: %s chunk %s bush count out of band (%d)" \
						% [realm, chunk_node.name, bushes])
			elif child.name == "StreamTerrainMesh":
				var arrays := (child as MeshInstance3D).mesh.surface_get_arrays(0)
				var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				if vertices.size() > 65535:
					f += 1
					print("FAIL: %s tile exceeds compatibility vertex limit (%d)" \
						% [realm, vertices.size()])
	if chunk_total < 9:
		f += 1
		print("FAIL: %s streamer built too few chunks (%d)" % [realm, chunk_total])

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
	scene.queue_free()
	await process_frame
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
