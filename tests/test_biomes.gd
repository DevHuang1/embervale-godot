extends SceneTree

## Headless functional check: 4-biome world layer.
## - Bestiary biome/boss tables resolve and their scenes exist
## - Old "whispergrove" saves normalize to bramblewood
## - Each biome scene boots with packs, gates and (where applicable)
##   an arena stone; realm state follows the entered biome

const BIOMES := ["bramblewood", "mistfen", "heartwood", "moonfen"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var gs = root.get_node("/root/GameState")
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
		if not has_arena:
			failures += 1
			print("FAIL: arena stone missing in ", id)

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

	gs.delete_save()
	if failures == 0:
		print("ALL BIOME TESTS PASSED")
	else:
		print("BIOME TESTS FAILED: ", failures)
	quit(1 if failures > 0 else 0)
