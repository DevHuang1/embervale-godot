extends SceneTree

func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/world/service_npc.gd")
	if not source.contains('var menu_name := "ShopMenu" if service_kind == "shop" else "SatchelUI"') \
		or not source.contains('menu.call("show_stats")'):
		print("FAIL: craftsman routing does not target satchel")
		quit(1)
		return
	if not source.contains('"VISIT SHOP" if service_kind == "shop" else "OPEN FORGE"'):
		print("FAIL: service prompt does not explain its destination")
		quit(1)
		return
	print("ALL SERVICE NPC ROUTING TESTS PASSED")
	quit(0)
