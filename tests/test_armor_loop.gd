extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.reset()
	gs.add_armor(GameState.ARMOR_DEFS["warden_plate"].duplicate(true), false)
	gs.equip_armor("warden_plate")
	gs.gold = 35
	gs.raw_materials["iron_shard"] = 5
	var result: Dictionary = gs.upgrade_armor("warden_plate")
	if not bool(result.get("success", false)) or int(result.get("defense", 0)) <= 3:
		print("FAIL: armor upgrade did not apply: ", result)
		quit(1)
		return
	if int(gs.equipped_armor.get("defense", 0)) != int(result.get("defense", 0)):
		print("FAIL: equipped armor did not receive upgraded defense")
		quit(1)
		return
	print("ALL ARMOR LOOP TESTS PASSED")
	quit(0)
