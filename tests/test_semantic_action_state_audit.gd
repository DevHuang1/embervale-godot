extends SceneTree

func _init() -> void:
	var owners := {
		"HUD": "res://scripts/ui/hud.gd",
		"FightButton": "res://scripts/ui/fight_button.gd",
		"Shop": "res://scripts/ui/shop_menu.gd",
		"Forge": "res://scripts/ui/forge_menu.gd",
		"Satchel": "res://scripts/ui/satchel.gd",
		"Dungeon": "res://scripts/ui/dungeon_select.gd",
		"MainMenu": "res://scripts/ui/main_menu.gd",
		"DiamondShop": "res://scripts/ui/diamond_shop.gd",
	}
	for owner in owners:
		var path := str(owners[owner])
		var source := FileAccess.get_file_as_string(path)
		if source.is_empty() or not source.contains("UiKit.action_state"):
			push_error("%s has no shared semantic action-state usage: %s" % [owner, path])
			quit(1)
			return
	for state in ["locked", "unavailable", "loading", "purchased", "equipped",
			"success", "crafting", "scanning", "restoring", "failed"]:
		var copy_source := FileAccess.get_file_as_string("res://scripts/ui/ui_kit.gd")
		if not copy_source.contains('"%s"' % state):
			push_error("Shared semantic state missing: %s" % state)
			quit(1)
			return
	print("ALL SEMANTIC ACTION STATE AUDIT TESTS PASSED")
	quit()
