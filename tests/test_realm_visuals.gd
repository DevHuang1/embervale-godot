extends SceneTree

## Headless visual-pass validation.
## - Every realm scene boots without script errors (autoloads initialized).
## - The active terrain material binds the stylized albedo/normal/roughness
##   masters (regression guard: scanned PBR or missing samplers fail here).
## - Moonfen keeps its fen water shader + ReflectionProbe and stylized stone.
## Uses the existing Bestiary biome mapping so realm ids stay source-of-truth.

const REALMS := ["bramblewood", "whispergrove", "mistfen", "heartwood", "moonfen"]

const STYLIZED_SAMPLERS := [
	"grass_tex", "grass_norm", "grass_rough",
	"dirt_tex", "dirt_norm", "dirt_rough",
	"sand_tex", "sand_norm", "sand_rough",
	"rock_tex", "rock_norm", "rock_rough",
]

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(60.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — realm visuals test hung")
		quit(2))

func _run() -> void:
	var failures := 0
	var finals := 0
	var gs := root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	for realm in REALMS:
		var scene_path: String = Bestiary.biome_scene(realm) \
			if realm != "whispergrove" else "res://scenes/world/grove.tscn"
		if not ResourceLoader.exists(scene_path):
			failures += 1
			print("FAIL: realm scene missing -> ", realm, " ", scene_path)
			continue
		# Whispergrove renders through the shared grove (biome bramblewood).
		gs.set_current_realm(realm)
		var scene: Node = (load(scene_path) as PackedScene).instantiate()
		root.add_child(scene)
		for i in 6:
			await process_frame

		var terrain := _find_terrain_material(scene)
		if terrain == null:
			failures += 1
			print("FAIL: no terrain_ground material in ", realm)
			scene.queue_free()
			continue
		for sampler in STYLIZED_SAMPLERS:
			var tex = terrain.get_shader_parameter(sampler)
			if tex == null or not (tex is Texture2D):
				failures += 1
				print("FAIL: %s unbound samplers -> %s" % [realm, sampler])
				continue
			var t := tex as Texture2D
			if t.resource_path.is_empty() or not t.resource_path.contains("stylized"):
				failures += 1
				print("FAIL: %s sampler %s not bound to stylized master (%s)"
					% [realm, sampler, t.resource_path])

		# Mobile/compatibility renderers must receive one index-safe continuous
		# surface; exceeding 65,535 vertices produced rectangular ground strips.
		for terrain_node in scene.find_children("TerrainMesh", "MeshInstance3D", true, false):
			var terrain_instance := terrain_node as MeshInstance3D
			if terrain_instance.mesh == null or terrain_instance.mesh.get_surface_count() == 0:
				continue
			var terrain_arrays := terrain_instance.mesh.surface_get_arrays(0)
			var terrain_vertices := terrain_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var terrain_indices := terrain_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			if terrain_vertices.size() > 65535:
				failures += 1
				print("FAIL: %s terrain exceeds compatibility index limit (%d vertices)" \
					% [realm, terrain_vertices.size()])
			if terrain_indices.is_empty() or terrain_indices.size() % 6 != 0:
				failures += 1
				print("FAIL: %s terrain indexed grid is incomplete" % realm)

		var gathering_nodes := scene.find_children("*", "GatheringNode", true, false)
		if gathering_nodes.size() < 4:
			failures += 1
			print("FAIL: %s should expose four deterministic gathering nodes" % realm)
		else:
			for gathering in gathering_nodes:
				if not gathering.is_in_group("interactable"):
					failures += 1
					print("FAIL: %s gathering node is not interactable" % realm)

		# Continuous grass contract: one dense MultiMesh carpet covers the playable
		# route even on the boot-time Low tier. Paths and boss arenas stay clear.
		var grass_batches := scene.find_children("GrassCarpet", "MultiMeshInstance3D", true, false)
		if grass_batches.is_empty():
			failures += 1
			print("FAIL: %s missing continuous GrassCarpet batch" % realm)
		else:
			var grass_batch := grass_batches[0] as MultiMeshInstance3D
			if not grass_batch.multimesh.mesh is ArrayMesh:
				failures += 1
				print("FAIL: %s grass regressed to primitive rod geometry" % realm)
			else:
				var blade_mesh := grass_batch.multimesh.mesh as ArrayMesh
				var arrays := blade_mesh.surface_get_arrays(0)
				var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				if vertices.size() < 30:
					failures += 1
					print("FAIL: %s grass clump lacks tapered multi-blade geometry" % realm)
			var grass_radius := 28.0 if realm == "moonfen" else (56.0 \
				if realm in ["mistfen", "heartwood"] else 72.0)
			var carpet_density := float(grass_batch.multimesh.instance_count) \
				/ (PI * grass_radius * grass_radius)
			if carpet_density < 0.50:
				failures += 1
				print("FAIL: %s grass carpet too sparse (%.2f instances/m2)" \
					% [realm, carpet_density])
			var arena3 := RealmLayoutData.profile(realm).get("arena", Vector3.ZERO) as Vector3
			for grass_index in grass_batch.multimesh.instance_count:
				var grass_pos := grass_batch.multimesh.get_instance_transform(grass_index).origin
				if Vector2(grass_pos.x, grass_pos.z).distance_to(Vector2(arena3.x, arena3.z)) < 4.9:
					failures += 1
					print("FAIL: %s grass obstructs boss telegraph arena" % realm)
					break

		var composition := scene.find_child("WorldGroundComposition", true, false)
		if composition == null:
			failures += 1
			print("FAIL: %s missing world ground composition" % realm)
		else:
			var required_batches := ["SandPatches", "MudPatches", "DirtPatches",
				"VariedTreeTrunks", "VariedTreeLowerCrowns", "AuthoredRockFields",
				"FallenDeadwood"]
			if realm != "heartwood":
				required_batches.append_array(["ShallowPonds", "PondShorelines"])
			for batch_name in required_batches:
				var batch := composition.get_node_or_null(str(batch_name)) as MultiMeshInstance3D
				if batch == null or batch.multimesh == null \
						or batch.multimesh.instance_count == 0:
					failures += 1
					print("FAIL: %s missing populated environment batch %s" % [realm, batch_name])
			var sand_batch := composition.get_node_or_null("SandPatches") as MultiMeshInstance3D
			if sand_batch != null:
				var sand_material := sand_batch.material_override as StandardMaterial3D
				if sand_material == null or sand_material.albedo_texture == null \
						or not sand_material.albedo_texture.resource_path.contains("stylized/sand"):
					failures += 1
					print("FAIL: %s sand patches do not bind stylized surface maps" % realm)

		# The navigation trail must use organic stepping stones. The former
		# BoxMesh rows resembled bright rectangular holes across the terrain.
		var trail_batch := scene.find_child("PalePathStones", true, false) as MultiMeshInstance3D
		if trail_batch == null or trail_batch.multimesh == null:
			failures += 1
			print("FAIL: %s missing named organic path-stone batch" % realm)
		elif trail_batch.multimesh.mesh is BoxMesh:
			failures += 1
			print("FAIL: %s path regressed to rectangular BoxMesh stones" % realm)

		if realm == "moonfen":
			failures += _check_moonfen(scene, failures)

		scene.queue_free()
		# Full audio teardown: looping beds, boss voices and one-shots must
		# all be stopped before their hosts vanish, so no AudioServer
		# playback outlives the realm. (SceneTree test scripts resolve
		# autoloads via node path, not identifier.)
		var audio := root.get_node("/root/AudioManager")
		if audio != null:
			audio.stop_all_playback()
		# The lantern marker holds static refs; free it with the realm or it
		# lingers as an orphaned node holding its script past exit.
		load("res://scripts/systems/target_marker.gd").shutdown()
		await process_frame
		finals += 1
		gs.reset()

	if finals == 0:
		failures += 1
		print("FAIL: no realm scene could boot")

	# Final teardown before quit: stop any voice still playing and give the
	# audio server a few mix frames to release the stopped playbacks, or the
	# ObjectDB exit check reports freshly stopped voices as leaked instances.
	var audio_final := root.get_node("/root/AudioManager")
	if audio_final != null:
		audio_final.stop_all_playback()
	for i in 3:
		await process_frame

	if failures == 0:
		print("ALL REALM VISUAL TESTS PASSED (booted=%d)" % finals)
	else:
		print("%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)


func _find_terrain_material(scene: Node) -> ShaderMaterial:
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi.material_override as ShaderMaterial
		if m != null and m.shader != null \
				and m.shader.resource_path.contains("terrain_ground.gdshader"):
			return m
	return null


## Moonfen visual contract: fen water shader on the water plane, a live
## ReflectionProbe for glints, and stylized stone used by the ruin dressing.
func _check_moonfen(scene: Node, failures: int) -> int:
	var f := 0
	var water := scene.find_children("WaterPlane", "MeshInstance3D", true, false)
	if water.is_empty():
		f += 1
		print("FAIL: moonfen missing WaterPlane")
	else:
		var mat := (water[0] as MeshInstance3D).material_override as ShaderMaterial
		if mat == null or mat.shader == null \
				or not mat.shader.resource_path.contains("water_fen.gdshader"):
			f += 1
			print("FAIL: moonfen WaterPlane does not use water_fen shader")
	var probes := scene.find_children("FenReflection", "ReflectionProbe", true, false)
	if probes.is_empty():
		f += 1
		print("FAIL: moonfen missing ReflectionProbe")
	# Stylized stone rebound on the ruin dressing material (material_override
	# and per-surface materials both count).
	var found_stylized := false
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var candidates: Array[ShaderMaterial] = []
		var ov := (mi as MeshInstance3D).material_override as ShaderMaterial
		if ov != null:
			candidates.append(ov)
		var mesh := (mi as MeshInstance3D).mesh
		if mesh != null:
			for s in mesh.get_surface_count():
				var sm := mesh.surface_get_material(s) as ShaderMaterial
				if sm != null:
					candidates.append(sm)
		for sm in candidates:
			if sm.shader == null:
				continue
			if not sm.shader.resource_path.contains("rock.gdshader"):
				continue
			var albedo = sm.get_shader_parameter("rock_albedo_tex") as Texture2D
			if albedo != null and albedo.resource_path.contains("stylized/rock"):
				found_stylized = true
				break
		if found_stylized:
			break
	if not found_stylized:
		f += 1
		print("FAIL: moonfen rock shader not bound to stylized rock masters")
	return f
