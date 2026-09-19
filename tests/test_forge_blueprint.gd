extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var gs = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.save_path = "/tmp/embervale_forge_blueprint_test.cfg"
	gs.delete_save()
	gs.reset()

	if gs.is_blueprint_unlocked("mug_mace"):
		failures += 1
		print("FAIL: blueprint unlocked on a fresh save")
	var locked: Dictionary = gs.forge_blueprint("mug_mace", 0, "TEST MAUL", [])
	if bool(locked.get("success", false)):
		failures += 1
		print("FAIL: locked blueprint forged")
	if gs.get_material_qty("bramble_wood") != 0:
		failures += 1
		print("FAIL: locked forge changed materials")

	var first: Array = gs.register_analysis("hushling")
	if not first.is_empty():
		failures += 1
		print("FAIL: blueprint unlocked after one analysis")
	var second: Array = gs.register_analysis("hushling")
	if second.size() != 1 or str(second[0]) != "mug_mace":
		failures += 1
		print("FAIL: unlock report wrong -> ", second)
	if gs.register_analysis("unknown_beast").size() != 0:
		failures += 1
		print("FAIL: unknown kind recorded analysis")
	var progress: Dictionary = gs.blueprint_progress("mug_mace")
	if not bool(progress.get("unlocked", false)) or int(progress.get("current", 0)) != 2:
		failures += 1
		print("FAIL: blueprint progress wrong -> ", progress)

	gs.add_material("bramble_wood", 3)
	var poor: Dictionary = gs.forge_blueprint("mug_mace", 0, "TEST MAUL", [])
	if bool(poor.get("success", false)):
		failures += 1
		print("FAIL: forged without enough materials")
	if gs.get_material_qty("bramble_wood") != 3:
		failures += 1
		print("FAIL: failed forge deducted materials")

	gs.add_material("bramble_wood", 1)
	var forged: Dictionary = gs.forge_blueprint("mug_mace", 0, "TEST MAUL", ["ONE", "TWO", "THREE"])
	if not bool(forged.get("success", false)):
		failures += 1
		print("FAIL: affordable forge refused -> ", forged.get("message", ""))
	else:
		var def: Dictionary = forged.get("def", {})
		var base: Dictionary = gs.WEAPON_DEFS["mug_mace"]
		if str(def.get("id", "")) != "relic_mug_mace" or def.get("skills", []).size() != 3:
			failures += 1
			print("FAIL: forged def shape wrong -> ", def)
		if int(def.get("atk", 0)) != int(round(float(base.get("atk", 0)) * 1.00)):
			failures += 1
			print("FAIL: tier-0 stat roll wrong -> ", def.get("atk", 0))
		if not bool(def.get("relic", false)):
			failures += 1
			print("FAIL: forged def lost its relic flag")
	if gs.get_material_qty("bramble_wood") != 0:
		failures += 1
		print("FAIL: forge did not deduct exactly -> ", gs.get_material_qty("bramble_wood"))
	if not bool(gs.equipped_weapon.get("relic", false)):
		failures += 1
		print("FAIL: forged kit not equipped")

	var repeat: Dictionary = gs.forge_blueprint("mug_mace", 0, "TEST MAUL", [])
	if bool(repeat.get("success", false)):
		failures += 1
		print("FAIL: repeat craft succeeded without materials")

	if gs.is_blueprint_unlocked("slab_hammer"):
		failures += 1
		print("FAIL: boss blueprint unlocked before first kill")
	gs.mark_boss_killed("res://scripts/entities/boss_hushling_matriarch.gd")
	if not gs.is_blueprint_unlocked("slab_hammer"):
		failures += 1
		print("FAIL: boss first-kill did not unlock blueprint")

	gs.save_game()
	gs.reset()
	gs.load_game()
	if int(gs.analyzed_families.get("swarm", 0)) != 2:
		failures += 1
		print("FAIL: analysis progress lost across load -> ", gs.analyzed_families)
	if not gs.is_blueprint_unlocked("slab_hammer"):
		failures += 1
		print("FAIL: boss blueprint lost across load")
	if not gs.is_blueprint_unlocked("mug_mace"):
		failures += 1
		print("FAIL: family blueprint lost across load")

	if failures == 0:
		print("ALL FORGE BLUEPRINT TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	gs.delete_save()
	quit(1 if failures > 0 else 0)
