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
	gs.save_path = "/tmp/embervale_realm_visuals_%d.cfg" % OS.get_process_id()
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
		if realm == "bramblewood":
			# The shared grove is visually Whispergrove until the route unlocks the
			# Bramblewood expedition; force the latter for this realm pass.
			gs.current_stage = GameState.QuestStage.COMPLETE
			gs.scans_remaining = 0
		var scene: Node = (load(scene_path) as PackedScene).instantiate()
		root.add_child(scene)
		for i in 6:
			await process_frame
		var profile_realm: String = "whispergrove" if realm == "whispergrove" else realm
		var profile_chests: Array = RealmLayoutData.profile(profile_realm).get("chests", [])
		var runtime_chests: Array = []
		for chest_value in scene.find_children("*", "ChestNode", true, false):
			if (chest_value as ChestNode).is_in_group("authored_chest"):
				runtime_chests.append(chest_value)
		if runtime_chests.size() != profile_chests.size():
			failures += 1
			print("FAIL: %s authored chest count mismatch (%d != %d)" \
				% [realm, runtime_chests.size(), profile_chests.size()])
		var expected_chests: Dictionary = {}
		for chest_value in profile_chests:
			if chest_value is Dictionary:
				var definition: Dictionary = chest_value
				expected_chests[str(definition.get("id", ""))] = definition
		var runtime_ids: Dictionary = {}
		for chest_value in runtime_chests:
			var chest := chest_value as ChestNode
			if chest == null:
				continue
			var chest_id := chest.chest_id
			if runtime_ids.has(chest_id) or not expected_chests.has(chest_id):
				failures += 1
				print("FAIL: %s runtime chest id is missing or duplicated: %s" % [realm, chest_id])
			else:
				runtime_ids[chest_id] = true
				var definition: Dictionary = expected_chests[chest_id]
				if chest.chest_tier != ChestNode.tier_for_rarity(int(definition.get("rarity", 0))):
					failures += 1
					print("FAIL: %s chest %s has wrong tier" % [realm, chest_id])
				if str(definition.get("type", "")) == "boss_gated" \
						and chest.required_boss_key != str(definition.get("boss_key", "")):
					failures += 1
					print("FAIL: %s chest %s has wrong boss gate" % [realm, chest_id])
		if failures == 0:
			print("PASS: %s authored chests instantiated with unique ids and correct gates" % realm)
		var activity_director := scene.find_child("RealmActivityDirector", true, false)
		if activity_director == null:
			failures += 1
			print("FAIL: %s missing shared realm activity director" % realm)
		else:
			var activity_report: Dictionary = activity_director.call("get_diagnostics")
			if int(activity_report.get("marker_count", 0)) != 6:
				failures += 1
				print("FAIL: %s activity catalog is not six beats" % realm)
			if int(activity_report.get("active_combat_count", 0)) > 2:
				failures += 1
				print("FAIL: %s activity combat cap exceeded" % realm)
			for marker in scene.get_tree().get_nodes_in_group("activity_marker"):
				if is_instance_valid(marker) and not marker.has_meta("terrain_surface_height"):
					failures += 1
					print("FAIL: %s activity marker is not terrain-conformed" % realm)
		var vista := scene.find_child("DistantLandmarkSilhouettes", true, false)
		if vista == null or vista.get_child_count() == 0 or vista.get_child_count() > 3:
			failures += 1
			print("FAIL: %s distant landmark silhouettes must be bounded 1..3" % realm)

		var terrain := _find_terrain_material(scene)
		if terrain == null:
			failures += 1
			print("FAIL: no terrain_ground material in ", realm)
			scene.queue_free()
			continue
		var expected_samplers := STYLIZED_SAMPLERS
		if terrain.shader.resource_path.contains("terrain_ground_mobile"):
			expected_samplers = ["grass_tex", "dirt_tex", "sand_tex", "rock_tex"]
		for sampler in expected_samplers:
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
		# Streamed realms (bramblewood/whispergrove) carry the carpet as many
		# per-chunk "GrassCarpet" batches, so their density is measured by
		# aggregating every instance inside the 72 m disc around the hero spawn.
		var grass_batches := scene.find_children("GrassCarpet*", "MultiMeshInstance3D", true, false)
		var stream_realm: bool = realm in ["bramblewood", "whispergrove"]
		if grass_batches.is_empty():
			failures += 1
			print("FAIL: %s missing continuous GrassCarpet batch" % realm)
		else:
			if not stream_realm:
				failures += _check_grass_batch(scene, grass_batches[0] as MultiMeshInstance3D,
					realm, 28.0 if realm == "moonfen" else 56.0)
			else:
				var spawn_marker := scene.find_child("PlayerSpawn", true, false) as Marker3D
				if spawn_marker == null:
					failures += 1
					print("FAIL: %s missing PlayerSpawn anchor for streamed grass" % realm)
				else:
					var center := Vector2(spawn_marker.global_position.x,
						spawn_marker.global_position.z)
					var count := 0
					for batch in grass_batches:
						var mmi := batch as MultiMeshInstance3D
						for i in mmi.multimesh.instance_count:
							var origin := mmi.multimesh.get_instance_transform(i).origin
							if (Vector2(mmi.global_position.x, mmi.global_position.z) \
									+ Vector2(origin.x, origin.z)).distance_to(center) <= 72.0:
								count += 1
					var area := PI * 72.0 * 72.0
					if float(count) / area < 0.45:
						failures += 1
						print("FAIL: %s streamed grass carpet too sparse (%.2f instances/m2)" \
							% [realm, float(count) / area])
					var band_names := {"GrassCarpet": false, "GrassCarpet_mid": false,
						"GrassCarpet_far": false}
					for batch in grass_batches:
						if band_names.has(str((batch as Node).name)):
							band_names[str((batch as Node).name)] = true
					var streamer := scene.find_child("WorldStreamer", true, false)
					var expects_far_band := false
					if streamer != null and streamer.has_method("get_tier_spec"):
						expects_far_band = float(streamer.call("get_tier_spec").get("radius", 0.0)) >= 190.0
					for band_name in band_names:
						if band_name == "GrassCarpet_far" and not expects_far_band:
							continue
						if not band_names[band_name]:
							failures += 1
							print("FAIL: %s missing streamed grass band %s" % [realm, band_name])
				# Arena clearance spans every chunk batch for streamed realms.
				var arena3 := RealmLayoutData.profile(realm).get("arena", Vector3.ZERO) as Vector3
				for batch in grass_batches:
					var mmi := batch as MultiMeshInstance3D
					for grass_index in mmi.multimesh.instance_count:
						var grass_pos := mmi.multimesh.get_instance_transform(grass_index).origin
						var world_pos := Vector2(mmi.global_position.x, mmi.global_position.z) \
							+ Vector2(grass_pos.x, grass_pos.z)
						if world_pos.distance_to(Vector2(arena3.x, arena3.z)) < 4.9:
							failures += 1
							print("FAIL: %s grass obstructs boss telegraph arena" % realm)
							break
					if failures > 0 and arena3 != Vector3.ZERO:
						break
		var boss_anchors := RealmLayoutData.boss_anchor_points_for_world(scene)
		var dressing := scene.find_child("ForestBorder", true, false)
		if dressing != null and dressing.has_method("_grass_clearance"):
			for boss_anchor in boss_anchors:
				if not bool(dressing.call("_grass_clearance", boss_anchor)):
					failures += 1
					print("FAIL: %s boss anchor lacks static grass clearance: %s" \
						% [realm, boss_anchor])
		# Static-dressing realms own their tree batches; streamed realms get
		# trees from the chunk streamer instead. Trunks must be base-anchored
		# (the old centered cylinder buried half of every tree) and carry limbs.
		if not stream_realm and dressing != null:
			var trunk_boxes: Array[AABB] = []
			var widest_trunk := 0.0
			for child in dressing.get_children():
				if not (child is MultiMeshInstance3D):
					continue
				var mmi := child as MultiMeshInstance3D
				if mmi.multimesh == null:
					continue
				var box: AABB = mmi.multimesh.mesh.get_aabb()
				if box.size.y > 2.0 and absf(box.position.y) < 0.05:
					trunk_boxes.append(box)
					widest_trunk = maxf(widest_trunk, box.size.x)
			if trunk_boxes.is_empty():
				failures += 1
				print("FAIL: %s static dressing has no base-anchored tree trunks" % realm)
			elif widest_trunk < 0.9:
				failures += 1
				print("FAIL: %s static tree trunks have no limb spread (%.2f m wide)" \
					% [realm, widest_trunk])
		if stream_realm:
			var streamer_for_clearance := scene.find_child("WorldStreamer", true, false)
			if streamer_for_clearance != null and streamer_for_clearance.has_method("_clearance_blocks"):
				for boss_anchor in boss_anchors:
					if not bool(streamer_for_clearance.call("_clearance_blocks", boss_anchor)):
						failures += 1
						print("FAIL: %s boss anchor lacks streamed clearance: %s" \
							% [realm, boss_anchor])

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
	gs.delete_save()

	if failures == 0:
		print("ALL REALM VISUAL TESTS PASSED (booted=%d)" % finals)
	else:
		print("%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)


func _find_terrain_material(scene: Node) -> ShaderMaterial:
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi.material_override as ShaderMaterial
		if m != null and m.shader != null \
				and (m.shader.resource_path.contains("terrain_ground.gdshader") \
				or m.shader.resource_path.contains("terrain_ground_layers.gdshader")):
			return m
	return null


## Blade geometry + static-density contract shared by the non-streamed realms.
func _check_grass_batch(scene: Node, grass_batch: MultiMeshInstance3D,
		realm: String, grass_radius: float) -> int:
	var f := 0
	if not grass_batch.multimesh.mesh is ArrayMesh:
		f += 1
		print("FAIL: %s grass regressed to primitive rod geometry" % realm)
	else:
		var blade_mesh := grass_batch.multimesh.mesh as ArrayMesh
		var arrays := blade_mesh.surface_get_arrays(0)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		if vertices.size() < 30:
			f += 1
			print("FAIL: %s grass clump lacks tapered multi-blade geometry" % realm)
	var carpet_density := float(grass_batch.multimesh.instance_count) \
		/ (PI * grass_radius * grass_radius)
	if carpet_density < 0.50:
		f += 1
		print("FAIL: %s grass carpet too sparse (%.2f instances/m2)" \
			% [realm, carpet_density])
	return f


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
