extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

## Fail fast with a single message (keeps the headless output greppable).
func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error("FAIL: %s" % message)
		quit(1)
	return condition

func _run() -> void:
	var gs = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return

	# --- Basic weapon craft stays atomic ---
	gs.reset()
	gs.gold = 25
	gs.raw_materials["iron_shard"] = 2
	var result: Dictionary = gs.craft_transaction("weapon", "ember_sword", 1,
		"Test Emberfang", 0, {"iron_shard": 2}, 25)
	if not _check(bool(result.get("success", false)), "valid craft rejected: %s" % result):
		return
	if not _check(gs.get_material_qty("iron_shard") == 0 and gs.gold == 0,
			"craft cost was not deducted atomically"):
		return
	if not _check(not gs.forged_weapons.is_empty()
			and str(gs.forged_weapons.back().get("name", "")) == "Test Emberfang",
			"crafted weapon missing"):
		return

	# --- Epic weapon via CraftingData (the satchel ADVANCED FORGE path) ---
	gs.reset()
	gs.gold = 130
	gs.raw_materials["crystal_fragment"] = 1
	gs.raw_materials["spore_dust"] = 6
	gs.raw_materials["iron_shard"] = 5
	var tier_result := CraftingData.craft("siltcarver_blade")
	if not _check(bool(tier_result.get("success", false)), "epic craft rejected: %s" % tier_result):
		return
	if not _check(gs.get_material_qty("crystal_fragment") == 0
			and gs.get_material_qty("spore_dust") == 0
			and gs.get_material_qty("iron_shard") == 0
			and gs.gold == 0,
			"epic craft cost was not deducted exactly"):
		return
	var crafted_weapon: Dictionary = {}
	for w in gs.forged_weapons:
		if w.get("id", "") == "siltcarver_blade":
			crafted_weapon = w
			break
	if not _check(not crafted_weapon.is_empty(), "epic weapon not added to forged_weapons"):
		return
	if not _check(int(crafted_weapon.get("rarity", 0)) == 3
			and str(crafted_weapon.get("name", "")) == "Siltscale Blade"
			and bool(crafted_weapon.get("crafted", false)),
			"epic weapon lost rarity/name/crafted metadata"):
		return

	# --- Legendary armor via CraftingData ---
	gs.reset()
	gs.gold = 220
	gs.raw_materials["crystal_fragment"] = 2
	gs.raw_materials["moonmoss"] = 6
	gs.raw_materials["camp_ember"] = 1
	var armor_result := CraftingData.craft("moonsilk_vest_recipe")
	if not _check(bool(armor_result.get("success", false)),
			"legendary armor craft rejected: %s" % armor_result):
		return
	var crafted_armor: Dictionary = {}
	for a in gs.forged_armors:
		if a.get("id", "") == "moonsilk_vest":
			crafted_armor = a
			break
	if not _check(not crafted_armor.is_empty()
			and int(crafted_armor.get("rarity", 0)) == 4
			and bool(crafted_armor.get("crafted", false)),
			"legendary armor not crafted with rarity"):
		return

	# --- Potion craft lands a real inventory entry and deducts exactly ---
	gs.reset()
	gs.gold = 20
	gs.raw_materials["emberstone"] = 2
	gs.raw_materials["beast_hide"] = 1
	gs.raw_materials["moss_fiber"] = 2
	var ember_before: int = gs.get_material_qty("emberstone")
	var salve_result := CraftingData.craft("ember_salve")
	if not _check(bool(salve_result.get("success", false)),
			"potion craft rejected: %s" % salve_result):
		return
	if not _check(gs.get_material_qty("emberstone") == ember_before - 2 and gs.gold == 0,
			"potion cost not deducted exactly"):
		return
	var salve: Dictionary = gs.get_item("ember_salve")
	if not _check(not salve.is_empty(), "potion craft produced no inventory entry"):
		return
	if not _check(salve.quantity >= 1, "potion entry has no quantity"):
		return
	gs.hp = 1
	if not _check(String(gs.use_item("ember_salve")).begins_with("You drink"),
			"potion could not be used"):
		return
	if not _check(int(gs.get_item("ember_salve").get("quantity", 0)) == 0,
			"potion use did not consume the entry"):
		return

	# --- Insufficient materials: nothing is deducted ---
	gs.reset()
	gs.gold = 130
	gs.raw_materials["crystal_fragment"] = 0
	var before_gold: int = gs.gold
	var before_weapons: int = gs.forged_weapons.size()
	var fail_result := CraftingData.craft("siltcarver_blade")
	if not _check(not bool(fail_result.get("success", false)),
			"craft with missing materials succeeded: %s" % fail_result):
		return
	if not _check(gs.gold == before_gold, "failed craft deducted gold"):
		return
	if not _check(gs.forged_weapons.size() == before_weapons,
			"failed craft added gear"):
		return

	# --- Utility bundle merges into the existing Moss Tonic entry and grants
	# exactly the quantity its card promises ---
	gs.reset()
	gs.gold = 18
	gs.raw_materials["bramble_wood"] = 2
	gs.raw_materials["beast_hide"] = 2
	gs.raw_materials["moss_fiber"] = 3
	var tonic_before: int = int(gs.get_item("moss_tonic").get("quantity", 0))
	var bundle_recipe: Dictionary = CraftingData.get_recipe("field_tonic_bundle")
	var promised := int(bundle_recipe.get("output_qty", 1))
	var utility_result := CraftingData.craft("field_tonic_bundle")
	if not _check(bool(utility_result.get("success", false)),
			"utility craft rejected: %s" % utility_result):
		return
	if not _check(promised > 1, "utility bundle no longer offers a bulk amount"):
		return
	if not _check(int(gs.get_item("moss_tonic").get("quantity", 0)) == tonic_before + promised,
			"utility bundle did not add exactly %d Moss Tonics" % promised):
		return
	if not _check(CraftingData.can_craft("field_tonic_bundle") == false,
			"utility bundle stayed craftable after spending its materials"):
		return

	print("ALL CRAFTING BENCH TESTS PASSED")
	quit(0)