extends SceneTree

## Headless functional check: 3-biome world layer.
## - Bestiary biome/boss tables resolve and their scenes exist
## - Old "whispergrove" saves normalize to bramblewood
## - Each biome scene boots with packs, gates and (where applicable)
##   an arena stone; realm state follows the entered biome

const BIOMES := ["bramblewood", "mistfen", "heartwood"]

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
		if not id == "heartwood" and (boss_id.is_empty()
				or Bestiary.boss_def(boss_id).is_empty()):
			failures += 1
			print("FAIL: arena boss def missing -> ", id)

	if Bestiary.boss_def("thornhide_alpha").is_empty() \
			or Bestiary.boss_def("fenmaw").is_empty():
		failures += 1
		print("FAIL: new boss defs missing")

	# --- Save compat: whispergrove alias ---
	if gs._normalize_realm("whispergrove") != "bramblewood":
		failures += 1
		print("FAIL: whispergrove alias lost")

	# --- Fresh save unlocks all three biomes ---
	gs.delete_save()
	gs.reset()
	for id in BIOMES:
		if id not in gs.unlocked_realms:
			failures += 1
			print("FAIL: biome locked on fresh save -> ", id)

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
		if gates != 2:
			failures += 1
			print("FAIL: gate count wrong in ", id, " -> ", gates)

		var has_arena := scene.has_node("ArenaStone")
		if id == "heartwood" and has_arena:
			failures += 1
			print("FAIL: heartwood should have no arena stone (quest finale)")
		if id != "heartwood" and not has_arena:
			failures += 1
			print("FAIL: arena stone missing in ", id)

		scene.queue_free()
		await process_frame
		await process_frame

	# --- Biome boss wires its def ---
	gs.reset()
	var boss: Node = (load("res://scenes/entities/boss_biome.tscn") as PackedScene).instantiate()
	boss.def_id = "fenmaw"
	root.add_child(boss)
	await process_frame
	var fen_def: Dictionary = Bestiary.boss_def("fenmaw")
	if boss.max_hp != int(fen_def.get("hp", 0)):
		failures += 1
		print("FAIL: fenmaw hp not wired -> ", boss.max_hp)
	if boss._boss_key() != "biome_fenmaw":
		failures += 1
		print("FAIL: boss key not def-scoped -> ", boss._boss_key())
	boss.queue_free()

	gs.delete_save()
	if failures == 0:
		print("ALL BIOME TESTS PASSED")
	else:
		print("BIOME TESTS FAILED: ", failures)
	quit(1 if failures > 0 else 0)
