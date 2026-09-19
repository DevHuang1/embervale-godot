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
	gs.save_path = "/tmp/embervale_legacy_weapon_names.cfg"
	gs.delete_save()
	gs.reset()

	var base: Dictionary = gs.WEAPON_DEFS["mug_mace"].duplicate(true)
	base["name"] = "MUG MACE"
	var relic: Dictionary = gs.WEAPON_DEFS["mug_mace"].duplicate(true)
	relic["id"] = "relic_mug_mace"
	relic["name"] = "MUG MACE"
	relic["relic"] = true
	var named: Dictionary = gs.WEAPON_DEFS["pocket_blade"].duplicate(true)
	named["id"] = "relic_pocket_blade"
	named["name"] = "MY OWN DAGGER"
	named["relic"] = true
	var crafted: Dictionary = gs.WEAPON_DEFS["thornmace"].duplicate(true)
	crafted["name"] = "Thornmace"
	var weapons: Array[Dictionary] = [base, relic, named, crafted]
	gs.forged_weapons = weapons
	gs.equipped_weapon = base.duplicate(true)
	gs.save_game()
	gs.reset()
	if not gs.load_game():
		print("FAIL: legacy save did not load")
		quit(1)
		return

	var by_id := {}
	for weapon in gs.forged_weapons:
		by_id[str(weapon.get("id", ""))] = weapon
	if str(by_id.get("mug_mace", {}).get("name", "")) != "CINDER MAUL":
		failures += 1
		print("FAIL: legacy base-kit name did not migrate -> ",
			by_id.get("mug_mace", {}).get("name", ""))
	if str(gs.equipped_weapon.get("name", "")) != "CINDER MAUL":
		failures += 1
		print("FAIL: equipped legacy name did not migrate -> ",
			gs.equipped_weapon.get("name", ""))
	if str(by_id.get("relic_mug_mace", {}).get("name", "")) != "MUG MACE":
		failures += 1
		print("FAIL: player-named relic was rewritten -> ",
			by_id.get("relic_mug_mace", {}).get("name", ""))
	if str(by_id.get("relic_pocket_blade", {}).get("name", "")) != "MY OWN DAGGER":
		failures += 1
		print("FAIL: custom relic name was lost -> ",
			by_id.get("relic_pocket_blade", {}).get("name", ""))
	if str(by_id.get("thornmace", {}).get("name", "")) != "Thornmace":
		failures += 1
		print("FAIL: crafted weapon name was rewritten -> ",
			by_id.get("thornmace", {}).get("name", ""))

	var added: Dictionary = gs.WEAPON_DEFS["slab_hammer"].duplicate(true)
	added["name"] = "SLAB HAMMER"
	gs.add_weapon(added, false)
	var stored: Dictionary = {}
	for weapon in gs.forged_weapons:
		if str(weapon.get("id", "")) == "slab_hammer":
			stored = weapon
			break
	if str(stored.get("name", "")) != "ASHFALL MAUL":
		failures += 1
		print("FAIL: added legacy name did not normalize -> ", stored.get("name", ""))

	gs.delete_save()
	if failures == 0:
		print("ALL LEGACY WEAPON NAME TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(1 if failures > 0 else 0)
