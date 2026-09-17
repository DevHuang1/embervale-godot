extends SceneTree

## Headless functional check: 4-biome world layer.
## - Bestiary biome/boss tables resolve and their scenes exist
## - Old "whispergrove" saves normalize to bramblewood
## - Each biome scene boots with packs, gates and (where applicable)
##   an arena stone; realm state follows the entered biome

const BIOMES := ["bramblewood", "mistfen", "heartwood", "moonfen"]
const LOD_SCRIPT := preload("res://scripts/systems/mobile_lod_controller.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var gs = root.get_node("/root/GameState")
	gs.save_path = "/tmp/embervale_biome_expansion_test.cfg"
	gs.delete_save()
	gs.reset()

	# --- Table sanity ---
	for id in BIOMES:
		var b: Dictionary = Bestiary.biome(id)
		if b.is_empty() or str(b.get("title", "")) == "":
			failures += 1
			print("FAIL: biome def missing -> ", id)
		if Bestiary.biome_scene(id).is_empty() \
				or not ResourceLoader.exists(Bestiary.biome_scene(id)):
			failures += 1
			print("FAIL: biome scene missing -> ", id)
		var boss_id := str(b.get("boss_id", ""))
		if boss_id.is_empty() or Bestiary.boss_def(boss_id).is_empty():
			failures += 1
			print("FAIL: arena boss def missing -> ", id)

	if Bestiary.boss_def("thornhide_alpha").is_empty() \
			or Bestiary.boss_def("fenmaw").is_empty() \
			or Bestiary.boss_def("cinderhart_colossus").is_empty() \
			or Bestiary.boss_def("moonfen_oracle").is_empty():
		failures += 1
		print("FAIL: new boss defs missing")

	# --- Save compat: whispergrove alias ---
	if gs._normalize_realm("whispergrove") != "bramblewood":
		failures += 1
		print("FAIL: whispergrove alias lost")

	# --- Fresh save keeps the vertical-slice realms open; Moonfen remains the
	# Matriarch reward and is tested by direct scene boot below. ---
	gs.delete_save()
	gs.reset()
	for id in ["bramblewood", "mistfen", "heartwood"]:
		if id not in gs.unlocked_realms:
			failures += 1
			print("FAIL: biome locked on fresh save -> ", id)
	if "moonfen" in gs.unlocked_realms:
		failures += 1
		print("FAIL: Moonfen should remain a visible post-Matriarch unlock")

	# --- Each biome scene boots correctly ---
	for id in BIOMES:
		gs.reset()
		var scene: Node = (load(Bestiary.biome_scene(id)) as PackedScene).instantiate()
		root.add_child(scene)
		for i in 5:
			await process_frame

		if gs.current_realm != id:
			failures += 1
			print("FAIL: realm not set on entry -> ", id, " got ", gs.current_realm)

		var enemies := get_nodes_in_group("enemy").size()
		var expected: int = int(Bestiary.biome(id).get("pack", {}).get("normal", 0)) \
			+ int(Bestiary.biome(id).get("pack", {}).get("hard", 0))
		if enemies < expected:
			failures += 1
			print("FAIL: pack under-spawned in ", id, " -> ", enemies, "/", expected)

		var gates := 0
		for child in scene.get_children():
			if child.name.begins_with("Gate_"):
				gates += 1
				var travel_arch := child.get_node_or_null("GroundedTravelArch")
				if travel_arch == null \
						or travel_arch.get_node_or_null("PortalMistVolume") == null:
					failures += 1
					print("FAIL: travel gate lacks grounded arch/mist volume -> ", id)
				for mesh_node in child.find_children("*", "MeshInstance3D", true, false):
					if mesh_node.name == "PortalMistVolume" and mesh_node.mesh is BoxMesh:
						failures += 1
						print("FAIL: travel portal regressed to square slab -> ", id)
		var expected_gates: int = (Bestiary.biome(id).get("gates", []) as Array).size()
		if gates != expected_gates:
			failures += 1
			print("FAIL: gate count wrong in ", id, " -> ", gates, "/", expected_gates)

		var has_arena := scene.has_node("ArenaStone")
		if id == "bramblewood" \
				and scene.find_child("RootboundCourtArena", true, false) != null:
			has_arena = true
		if not has_arena:
			failures += 1
			print("FAIL: arena stone missing in ", id)

		# --- Authored structures populate the realm map ---
		var visual_realm: String = str(id)
		if scene.has_method("_visual_realm_id"):
			visual_realm = str(scene.call("_visual_realm_id"))
		var profile: Dictionary = RealmLayoutData.profile(visual_realm)
		var structure_specs: Array = profile.get("structures", [])
		var structure_host := scene.get_node_or_null("AuthoredStructures")
		if structure_specs.is_empty():
			failures += 1
			print("FAIL: %s has no authored structures to build" % visual_realm)
		elif structure_host == null or structure_host.get_child_count() != structure_specs.size():
			failures += 1
			print("FAIL: %s built %s of %d authored structures" % [visual_realm,
				str(structure_host.get_child_count()) if structure_host != null else "no host",
				structure_specs.size()])

		# --- Spawn pockets actually populate ground away from spawn ---
		var pocket_specs: Array = profile.get("spawn_pockets", [])
		var hero := scene.get_node_or_null("Hero") as Node3D
		if pocket_specs.is_empty() or hero == null or not scene.has_method("_tick_spawn_pockets"):
			failures += 1
			print("FAIL: %s cannot exercise map-wide spawn pockets" % visual_realm)
		else:
			var first: Dictionary = pocket_specs[0] as Dictionary
			var pocket_id := str(first.get("id", ""))
			var origin: Vector3 = first.get("pos", Vector3.ZERO)
			var distance_from_spawn := Vector2(origin.x, origin.z).length()
			if distance_from_spawn < 10.0:
				failures += 1
				print("FAIL: %s first pocket sits on top of spawn (%.1f m)" \
					% [visual_realm, distance_from_spawn])
			hero.global_position = origin
			scene.call("_tick_spawn_pockets")
			var in_pocket := 0
			for enemy in get_nodes_in_group("enemy"):
				if enemy is Node3D and str(enemy.get_meta("spawn_pocket_id", "")) == pocket_id:
					in_pocket += 1
			if in_pocket < 1:
				failures += 1
				print("FAIL: %s pocket %s produced no enemies" % [visual_realm, pocket_id])
			var cap_regex := RegEx.new()
			cap_regex.compile("const POCKET_GLOBAL_CAP := (\\d+)")
			var cap_match := cap_regex.search(FileAccess.get_file_as_string(
				"res://scripts/systems/biome_manager.gd"))
			if cap_match != null:
				var live_cap := int(cap_match.get_string(1))
				var total_hostiles := get_nodes_in_group("enemy").size()
				if total_hostiles > live_cap:
					failures += 1
					print("FAIL: %s exceeded the realm hostile ceiling (%d > %d)" \
						% [visual_realm, total_hostiles, live_cap])

		# --- Authored resources become real, persisted gathering nodes ---
		var resource_specs: Array = profile.get("resources", [])
		var resource_host := scene.get_node_or_null("AuthoredResources")
		if resource_specs.is_empty():
			failures += 1
			print("FAIL: %s authors no gathering resources" % visual_realm)
		elif resource_host == null \
				or resource_host.get_child_count() != resource_specs.size():
			failures += 1
			print("FAIL: %s built %s of %d authored gathering nodes" % [visual_realm,
				str(resource_host.get_child_count()) if resource_host != null else "no host",
				resource_specs.size()])
		else:
			for resource_child in resource_host.get_children():
				if not resource_child.is_in_group("gathering") \
						or not resource_child.has_method("configure"):
					failures += 1
					print("FAIL: %s authored resource is not a gathering node -> %s" \
						% [visual_realm, resource_child.name])
					break
			var resource_terrain := scene.get_node_or_null("Terrain")
			if resource_terrain != null \
					and resource_terrain.has_method("sample_surface_height"):
				var sample := resource_host.get_child(0) as Node3D
				var surface := float(resource_terrain.call("sample_surface_height",
					sample.global_position))
				if absf(sample.global_position.y - surface) > 0.5:
					failures += 1
					print("FAIL: %s gathering node is not terrain-conformed (%.2f vs %.2f)" \
						% [visual_realm, sample.global_position.y, surface])

		# --- Authored encounters build their named set-pieces ---
		var encounter_specs: Array = profile.get("encounters", [])
		var encounter_host := scene.get_node_or_null("AuthoredEncounters")
		if encounter_specs.is_empty():
			failures += 1
			print("FAIL: %s authors no encounters" % visual_realm)
		elif encounter_host == null \
				or encounter_host.get_child_count() != encounter_specs.size():
			failures += 1
			print("FAIL: %s built %s of %d authored encounters (missing scene?)" \
				% [visual_realm,
				str(encounter_host.get_child_count()) if encounter_host != null else "no host",
				encounter_specs.size()])
		else:
			for index in encounter_specs.size():
				var spec: Dictionary = encounter_specs[index] as Dictionary
				if str(encounter_host.get_child(index).get_meta("authored_encounter", "")) \
						!= str(spec.get("scene", "")):
					failures += 1
					print("FAIL: %s authored encounter order drifted -> %s" \
						% [visual_realm, spec.get("scene", "")])
					break

		# --- Presentation LOD is wired to the built content and tiers by distance ---
		var lod := scene.get_node_or_null("MobileLod")
		if lod == null:
			failures += 1
			print("FAIL: %s did not create the mobile detail-LOD controller" % visual_realm)
		else:
			var registered: int = int(lod.call("registered_detail_count"))
			var expected_details: int = structure_specs.size() + resource_specs.size() \
				+ encounter_specs.size()
			if registered < expected_details:
				failures += 1
				print("FAIL: %s registered %d of %d built details for LOD" \
					% [visual_realm, registered, expected_details])
			var lod_sample := structure_host.get_child(0) as Node3D \
				if structure_host != null and structure_host.get_child_count() > 0 else null
			if lod_sample != null:
				var shadow_meshes: Array = lod.call("detail_state", lod_sample).get("meshes", [])
				if shadow_meshes.is_empty():
					failures += 1
					print("FAIL: %s structure registered no meshes for LOD" % visual_realm)
				else:
					lod.call("_update_detail_lod", lod_sample,
						lod_sample.global_position + Vector3(0.0, 0.0, LOD_SCRIPT.TIER2_DIST * 2.0))
					var still_on := 0
					for shadow_mesh in shadow_meshes:
						if is_instance_valid(shadow_mesh) \
								and shadow_mesh.cast_shadow \
								!= GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
							still_on += 1
					if still_on > 0:
						failures += 1
						print("FAIL: %s kept %d distant shadows on" \
							% [visual_realm, still_on])
					lod.call("_update_detail_lod", lod_sample, lod_sample.global_position)
					var restored := 0
					for shadow_mesh in shadow_meshes:
						if is_instance_valid(shadow_mesh) and shadow_mesh.cast_shadow \
								== GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
							restored += 1
					if restored > 0:
						failures += 1
						print("FAIL: %s did not restore %d close shadows" \
							% [visual_realm, restored])

		scene.queue_free()
		await process_frame
		await process_frame

	# --- Every arena boss wires stats, identity geometry and unique key ---
	for boss_id in ["fenmaw", "cinderhart_colossus", "moonfen_oracle"]:
		gs.reset()
		var boss: Node = (load("res://scenes/entities/boss_biome.tscn") as PackedScene).instantiate()
		boss.def_id = boss_id
		root.add_child(boss)
		await process_frame
		var boss_def: Dictionary = Bestiary.boss_def(boss_id)
		if boss.max_hp != int(boss_def.get("hp", 0)):
			failures += 1
			print("FAIL: %s hp not wired -> %d" % [boss_id, boss.max_hp])
		if boss._boss_key() != "biome_%s" % boss_id:
			failures += 1
			print("FAIL: boss key not def-scoped -> ", boss._boss_key())
		if boss_id in ["cinderhart_colossus", "moonfen_oracle"] \
				and boss.get_node("Visual").get_child_count() <= 8:
			failures += 1
			print("FAIL: %s lacks unique silhouette geometry" % boss_id)
		var materials: Dictionary = boss_def.get("rewards", {}).get("materials", {})
		for material_id in materials:
			if not gs.MATERIAL_DEFS.has(material_id):
				failures += 1
				print("FAIL: %s reward material invalid -> %s" % [boss_id, material_id])
		boss.queue_free()
		await process_frame

	# --- Bramblewood expansion data and route boot ---
	var expansion_profile: Dictionary = RealmLayoutData.profile("bramblewood")
	var pockets: Array = expansion_profile.get("expansion_pockets", [])
	if pockets.size() != 5:
		failures += 1
		print("FAIL: Bramblewood expansion pocket count wrong")
	var expected_pockets := ["split_road_oak", "rootcut_gully", "hollow_camp",
		"beacon_breach", "rootbound_court"]
	for i in pockets.size():
		if str(pockets[i].get("id", "")) != expected_pockets[i]:
			failures += 1
			print("FAIL: expansion pocket order changed -> ", pockets[i])
	if Bestiary.boss_def("rootbound_warden").get("hp", 0) != 640:
		failures += 1
		print("FAIL: Rootbound Warden stats missing")
	var rootbound_def: Dictionary = Bestiary.boss_def("rootbound_warden")
	if str(rootbound_def.get("special_1", {}).get("kind", "")) != "root_lattice" \
			or int(rootbound_def.get("ultimate", {}).get("eruptions", 0)) != 18 \
			or str(rootbound_def.get("special_2", {}).get("kind", "")) != "root_guard" \
			or int(rootbound_def.get("special_2", {}).get("count", 0)) != 2:
		failures += 1
		print("FAIL: Rootbound Warden attack contract missing")
	if Bestiary.boss_def("thornhide_alpha").is_empty():
		failures += 1
		print("FAIL: legacy Thornhide Alpha definition was removed")
	gs.reset()
	gs.begin_bramblewood_expansion()
	if not bool(gs.bramblewood_expansion.get("started", false)) \
			or gs.route_checkpoint_id != "bramblewood_expansion_start" \
			or gs.route_respawn_position != Vector2(20, -48):
		failures += 1
		print("FAIL: expansion start checkpoint contract missing")
	for pocket_id in expected_pockets:
		gs.discover_bramblewood_pocket(pocket_id)
	if gs.bramblewood_expansion.get("discovered_pockets", []).size() != 5:
		failures += 1
		print("FAIL: discovered pocket state did not retain stable IDs")
	var boss: Node = (load("res://scenes/entities/boss_biome.tscn") as PackedScene).instantiate()
	boss.def_id = "rootbound_warden"
	root.add_child(boss)
	await process_frame
	boss.call("_on_death_finished")
	await process_frame
	var wood_after_first: int = gs.get_material_qty("bramble_wood")
	var iron_after_first: int = gs.get_material_qty("iron_shard")
	if wood_after_first != 4 or iron_after_first != 3:
		failures += 1
		print("FAIL: first-clear materials were not granted exactly once -> ",
			wood_after_first, "/", iron_after_first)
	var repeat_boss: Node = (load("res://scenes/entities/boss_biome.tscn") as PackedScene).instantiate()
	repeat_boss.def_id = "rootbound_warden"
	root.add_child(repeat_boss)
	await process_frame
	repeat_boss.call("_on_death_finished")
	await process_frame
	if gs.get_material_qty("bramble_wood") != wood_after_first \
			or gs.get_material_qty("iron_shard") != iron_after_first:
		failures += 1
		print("FAIL: repeat Rootbound kill duplicated first-clear materials")
	if not gs.complete_bramblewood_expansion():
		failures += 1
		print("FAIL: expansion completion was not accepted")
	if gs.complete_bramblewood_expansion():
		failures += 1
		print("FAIL: expansion completion was not idempotent")
	var camp := root.get_node_or_null("/root/CampProgression")
	if camp == null or not bool(camp.call("facility_unlocked", "rootway_beacon")) \
			or not camp.call("is_shortcut_unlocked", "bramblewood", "rootway_shortcut") \
			or gs.route_checkpoint_id != "rootway_shortcut" \
			or gs.route_respawn_position != Vector2(172, -208):
		failures += 1
		print("FAIL: Rootway shortcut completion state missing")
	var shortcut_scene: Node = (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(shortcut_scene)
	for i in 5:
		await process_frame
	if not shortcut_scene.has_method("activate_camp_shortcut") \
			or not shortcut_scene.call("activate_camp_shortcut", "bramblewood", "rootway_shortcut"):
		failures += 1
		print("FAIL: Rootway shortcut API did not activate")
	else:
		var shortcut_hero := shortcut_scene.get_node_or_null("Hero") as Node3D
		if shortcut_hero == null or Vector2(shortcut_hero.global_position.x,
				shortcut_hero.global_position.z) != Vector2(172, -208):
			failures += 1
			print("FAIL: Rootway shortcut did not place the hero at Rootbound Court")
		var shortcut_marker := shortcut_scene.get_node_or_null("CampShortcutMarker") as Label3D
		if shortcut_marker == null or not shortcut_marker.visible:
			failures += 1
			print("FAIL: Rootway shortcut marker was not activated")
	shortcut_scene.queue_free()
	await process_frame
	gs.reset()
	gs.onboarding_completed = true
	var expansion_scene: Node = (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(expansion_scene)
	for i in 8:
		await process_frame
	var expedition := expansion_scene.get_node_or_null("BramblewoodExpedition")
	if expedition == null:
		failures += 1
		print("FAIL: Bramblewood expedition did not boot after onboarding")
	else:
		var terrain := expansion_scene.find_child("Terrain", true, false)
		for pocket_id in expected_pockets:
			var pocket_node := expansion_scene.find_child("ExpansionPocket_%s" % pocket_id,
				true, false) as Node3D
			if pocket_node == null:
				failures += 1
				print("FAIL: expansion pocket missing -> ", pocket_id)
			elif terrain != null and terrain.has_method("sample_surface_height"):
				var surface_y := float(terrain.call("sample_surface_height", pocket_node.global_position))
				if absf(pocket_node.global_position.y - surface_y - 0.04) > 0.08:
					failures += 1
					print("FAIL: pocket is not terrain-conformed -> ", pocket_id)
		var root_cluster := expansion_scene.find_child("BrambleRootCluster", true, false) \
				as MultiMeshInstance3D
		if root_cluster == null or root_cluster.multimesh == null \
					or root_cluster.multimesh.instance_count != 8:
			failures += 1
			print("FAIL: repeated root prop batch is missing or uncapped")
		var breach := expansion_scene.find_child("Encounter_beacon_breach", true, false)
		if breach == null or not breach.has_method("pocket_contract") \
				or str(breach.call("pocket_contract").get("tier", "")) != "elite":
			failures += 1
			print("FAIL: Beacon Breach encounter contract missing")
		var route_hero := expansion_scene.get_node_or_null("Hero") as Node3D
		if route_hero != null:
			for route_index in 4:
				var route_pocket := expansion_scene.find_child(
					"ExpansionPocket_%s" % expected_pockets[route_index], true, false) as Node3D
				if route_pocket == null:
					continue
				route_hero.global_position = route_pocket.global_position
				await process_frame
				var expected_checkpoint := str(pockets[route_index].get("checkpoint_id", ""))
				if gs.route_checkpoint_id != expected_checkpoint:
					failures += 1
					print("FAIL: route marker did not advance -> ", expected_pockets[route_index])
		if gs.complete_bramblewood_expansion():
			expedition.call("_refresh_post_clear_state")
			await process_frame
			var rootway_marker := expansion_scene.find_child("RootwayOpenMarker", true, false) as Label3D
			if rootway_marker == null or not rootway_marker.visible:
				failures += 1
				print("FAIL: completed route did not show the Rootway unlock marker")
	if expansion_scene.find_child("RootboundCourtArena", true, false) == null:
		failures += 1
		print("FAIL: Rootbound Court arena missing")
	expansion_scene.queue_free()
	await process_frame

	gs.delete_save()
	if failures == 0:
		print("ALL BIOME TESTS PASSED")
	else:
		print("BIOME TESTS FAILED: ", failures)
	quit(1 if failures > 0 else 0)
