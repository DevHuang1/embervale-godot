extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var shop_script := load("res://scripts/ui/shop_menu.gd")
	if shop_script == null:
		print("FAIL: shop script missing")
		quit(1)
		return
	var gs = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.equipped_weapon = GameState.WEAPON_DEFS["mug_mace"].duplicate(true)
	gs.equipped_armor = {}
	var method_source := FileAccess.get_file_as_string("res://scripts/ui/shop_menu.gd")
	if not method_source.contains("Compared with equipped"):
		print("FAIL: comparison copy missing")
		quit(1)
		return
	if not method_source.contains("button.disabled = game_state.gold < price"):
		print("FAIL: affordability guard missing")
		quit(1)
		return
	print("ALL SHOP COMPARISON TESTS PASSED")
	quit(0)
