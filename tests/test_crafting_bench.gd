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
	gs.gold = 25
	gs.raw_materials["iron_shard"] = 2
	var result: Dictionary = gs.craft_transaction("weapon", "ember_sword", 1,
		"Test Emberfang", 0, {"iron_shard": 2}, 25)
	if not bool(result.get("success", false)):
		print("FAIL: valid craft rejected: ", result)
		quit(1)
		return
	if gs.get_material_qty("iron_shard") != 0 or gs.gold != 0:
		print("FAIL: craft cost was not deducted atomically")
		quit(1)
		return
	if gs.forged_weapons.is_empty() or str(gs.forged_weapons.back().get("name", "")) != "Test Emberfang":
		print("FAIL: crafted weapon missing")
		quit(1)
		return
	print("ALL CRAFTING BENCH TESTS PASSED")
	quit(0)
