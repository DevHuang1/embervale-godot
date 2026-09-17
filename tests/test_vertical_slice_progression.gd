extends SceneTree

## P0 vertical-slice regression: gathering persistence, objective save/load,
## and transaction-safe gear crafting.

var _material_signal_count := 0

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(20.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — vertical slice progression test hung")
		quit(2))

func _run() -> void:
	var failures := 0
	var gs := root.get_node("/root/GameState")
	gs.save_path = "/tmp/embervale_vertical_slice_test.cfg"
	gs.delete_save()
	gs.reset()
	gs.materials_changed.connect(_on_materials_changed)
	if gs.get_onboarding_hint().is_empty():
		failures += 1
		print("FAIL: fresh save has no playable onboarding hint")
	for trigger in ["movement", "combat", "dodge", "loot", "gather", "craft"]:
		gs.check_onboarding_trigger(trigger)
	if not gs.onboarding_completed or gs.onboarding_step != gs.ONBOARDING_STEPS.size():
		failures += 1
		print("FAIL: onboarding triggers did not complete in playable order")
	gs.load_game()
	if not gs.onboarding_completed:
		failures += 1
		print("FAIL: onboarding completion was not persisted")

	# Objectives survive a round trip and malformed entries are rejected.
	gs.add_objective("gather_bramble_wood", "Gather Bramblewood", "gather", 2)
	gs.update_objective("gather", "bramble_wood", 1)
	gs.save_game()
	gs.reset()
	if not gs.load_game():
		failures += 1
		print("FAIL: progression save did not load")
	elif gs.quest_objectives.size() != 1 \
			or int(gs.quest_objectives[0].current_qty) != 1:
		failures += 1
		print("FAIL: quest objective progress did not round-trip")

	# Gathering uses the persisted dictionary, never dynamic GameState fields.
	var gather := GatheringNode.new()
	gather.name = "Gather_bramble_wood_test"
	gather.configure("bramble_wood", 2, 2, 0.01, 180.0, "bramblewood")
	root.add_child(gather)
	await process_frame
	gather.start_gather()
	await create_timer(0.05).timeout
	if gs.get_material_qty("bramble_wood") != 2:
		failures += 1
		print("FAIL: gathering did not award its configured material")
	var gather_key := "gather_bramblewood_Gather_bramble_wood_test"
	if gs.get_gathered_node_state(gather_key).is_empty():
		failures += 1
		print("FAIL: gathering depletion was not persisted")
	gather.queue_free()
	await process_frame

	# Enemy/chest rewards and legacy procedural nodes share the same canonical
	# material mutation path as authored gathering. Invalid quantities are ignored
	# without changing inventory or emitting a false material update.
	var reward_manager := root.get_node("/root/RewardManager") as Node
	var reward_signal_baseline := _material_signal_count
	reward_manager.call("grant_drops", [
		{"type": "material", "id": "iron_shard", "quantity": 2, "rarity": 1},
		{"type": "material", "id": "missing_material", "quantity": 3, "rarity": 0},
		{"type": "material", "id": "iron_shard", "quantity": 0, "rarity": 1},
		{"type": "material", "id": "iron_shard", "quantity": -4, "rarity": 1},
	])
	if gs.get_material_qty("iron_shard") != 2 \
			or _material_signal_count - reward_signal_baseline != 1:
		failures += 1
		print("FAIL: reward materials did not use the canonical validated mutation")

	var procedural_gather := ResourceGatherNode.new()
	procedural_gather.name = "CanonicalResourceGatherTest"
	procedural_gather.setup("beast_hide", 2, "bramblewood")
	procedural_gather.quantity_max = 2
	procedural_gather.respawn_time_sec = 180.0
	root.add_child(procedural_gather)
	await process_frame
	var procedural_signal_baseline := _material_signal_count
	procedural_gather.call("_do_gather")
	if gs.get_material_qty("beast_hide") != 2 \
			or _material_signal_count - procedural_signal_baseline != 1:
		failures += 1
		print("FAIL: procedural gathering did not use the canonical material mutation")
	procedural_gather.queue_free()
	await process_frame

	# Weapon crafting spends the exact cost once and grants actual forged gear.
	gs.reset()
	var recipe: Dictionary = CraftingData.get_recipe("thorn_mace")
	for material_id in recipe.materials:
		gs.add_material(str(material_id), int(recipe.materials[material_id]))
	gs.gold = int(recipe.gold_cost)
	var crafted := CraftingData.craft("thorn_mace")
	if not bool(crafted.get("success", false)):
		failures += 1
		print("FAIL: valid weapon recipe failed -> ", crafted)
	var crafted_mace: Dictionary = {}
	for weapon in gs.forged_weapons:
		if str(weapon.get("id", "")) == "thornmace":
			crafted_mace = weapon
			break
	if crafted_mace.is_empty() or not bool(crafted_mace.get("crafted", false)):
		failures += 1
		print("FAIL: crafted weapon was not granted as forged gear")
	elif int(crafted_mace.get("atk", 0)) <= int(gs.WEAPON_DEFS["mug_mace"].get("atk", 0)):
		failures += 1
		print("FAIL: Thornmace recipe does not improve on the starter weapon")
	elif str(crafted_mace.get("name", "")) != "Thornmace":
		failures += 1
		print("FAIL: crafted Thornmace did not keep its recipe name")
	elif gs.gear_sell_value("thornmace", "weapon") <= 1:
		failures += 1
		print("FAIL: crafted weapon has no resale value")
	# The starter must survive a craft untouched: same entry, still owned.
	if not gs.forged_weapons.any(func(w): return str(w.get("id", "")) == "mug_mace"):
		failures += 1
		print("FAIL: crafting replaced the starter weapon entry")
	if gs.gold != 0:
		failures += 1
		print("FAIL: crafting gold deduction was not exact")
	for material_id in recipe.materials:
		if gs.get_material_qty(str(material_id)) != 0:
			failures += 1
			print("FAIL: crafting material deduction was not exact -> ", material_id)
	var second := CraftingData.craft("thorn_mace")
	if bool(second.get("success", false)):
		failures += 1
		print("FAIL: repeated craft succeeded without another full cost")

	# The starter weapon is real gear from the first minute: it lives in the
	# forge ledger, can be upgraded without crafting anything, and comes back
	# after swapping to another weapon.
	gs.reset()
	var starter_id := str(gs.equipped_weapon.get("id", ""))
	if starter_id.is_empty() or not gs.forged_weapons.any(
			func(w): return str(w.get("id", "")) == starter_id):
		failures += 1
		print("FAIL: starter weapon is missing from the forge ledger")
	else:
		gs.add_material("iron_shard", 8)
		gs.gold = 200
		var starter_upgrade: Dictionary = gs.upgrade_weapon(starter_id)
		if not bool(starter_upgrade.get("success", false)):
			failures += 1
			print("FAIL: starter weapon could not be upgraded -> ", starter_upgrade)
		else:
			gs.add_weapon(gs.WEAPON_DEFS["ember_sword"].duplicate(true), true)
			if str(gs.equipped_weapon.get("id", "")) != "ember_sword":
				failures += 1
				print("FAIL: could not swap away from the starter weapon")
			elif not gs.equip_weapon_by_id(starter_id):
				failures += 1
				print("FAIL: starter weapon could not be re-equipped after a swap")
			elif int(gs.equipped_weapon.get("upgrade_level", 0)) < 1:
				failures += 1
				print("FAIL: re-equipped starter weapon lost its upgrade")

	# Pricing has one source: the item's own def. Every stock row must resolve a
	# real asking price, resale is half of it, and buying charges exactly it.
	for stock in gs.SHOP_STOCK:
		var stock_id := str(stock.get("id", ""))
		var stock_kind := str(stock.get("kind", ""))
		var asking: int = gs.gear_buy_price(stock_id, stock_kind)
		if asking <= 0:
			failures += 1
			print("FAIL: stock row has no price in its def -> ", stock_id)
		elif gs.gear_sell_value(stock_id, stock_kind) != asking / 2:
			failures += 1
			print("FAIL: stock item does not sell for half its asking price -> ", stock_id)
	if gs.gear_buy_price("ember_sword", "weapon") <= 0 \
			or gs.gear_sell_value("ember_sword", "weapon") \
			!= gs.gear_buy_price("ember_sword", "weapon") / 2:
		failures += 1
		print("FAIL: ember_sword pricing contract broke")
	if gs.gear_buy_price("moss_tonic", "potion") != int(
			CraftingData.get_recipe("moss_tonic").get("gold_cost", 0)):
		failures += 1
		print("FAIL: consumable asking price drifted from its recipe cost")
	if gs.gear_sell_value("mug_mace", "weapon") <= 1:
		failures += 1
		print("FAIL: starter weapon has no honest resale value")
	# A purchase charges the def price and grants the item.
	gs.reset()
	gs.gold = gs.gear_buy_price("moss_tonic", "potion")
	var tonics_before: int = int(gs.get_item("moss_tonic").get("quantity", 0))
	var bought: Dictionary = gs.buy_shop_item("moss_tonic")
	if not bool(bought.get("success", false)):
		failures += 1
		print("FAIL: affordable purchase was refused -> ", bought)
	elif gs.gold != 0:
		failures += 1
		print("FAIL: purchase did not charge exactly the def price")
	elif int(gs.get_item("moss_tonic").get("quantity", 0)) != tonics_before + 1:
		failures += 1
		print("FAIL: purchase did not grant the item")
	if bool(gs.buy_shop_item("moss_tonic").get("success", true)):
		failures += 1
		print("FAIL: purchase succeeded without enough gold")
	gs.reset()
	gs.add_weapon(gs.WEAPON_DEFS["ember_sword"].duplicate(true), true)
	gs.add_weapon(gs.WEAPON_DEFS["mug_mace"].duplicate(true), false)
	var gold_before_sale: int = gs.gold
	var starter_value: int = gs.gear_sell_value("mug_mace", "weapon")
	var sold: Dictionary = gs.sell_shop_item("mug_mace", "weapon")
	if not bool(sold.get("success", false)) or int(sold.get("value", 0)) != starter_value:
		failures += 1
		print("FAIL: starter weapon sale did not pay the advertised value -> ", sold)
	elif gs.gold != gold_before_sale + starter_value:
		failures += 1
		print("FAIL: starter weapon sale did not credit the exact gold")
	var blocked_sale: Dictionary = gs.sell_shop_item("ember_sword", "weapon")
	if bool(blocked_sale.get("success", true)):
		failures += 1
		print("FAIL: shop sold the currently equipped weapon")

	# No replacement path may wipe invested forge work: a duplicate drop, a
	# boss reward or a recraft of the same id keeps the earned upgrade level
	# and the stats that level had paid for.
	gs.reset()
	gs.add_material("iron_shard", 8)
	gs.gold = 200
	var starter_for_replacement := str(gs.equipped_weapon.get("id", ""))
	var before_upgrade: Dictionary = gs.upgrade_weapon(starter_for_replacement)
	if not bool(before_upgrade.get("success", false)):
		failures += 1
		print("FAIL: could not prepare an upgraded piece for the replacement test")
	else:
		var upgraded_atk := int(gs.equipped_weapon.get("atk", 0))
		gs.add_weapon(gs.WEAPON_DEFS[starter_for_replacement].duplicate(true), false)
		var replaced: Dictionary = {}
		for weapon in gs.forged_weapons:
			if str(weapon.get("id", "")) == starter_for_replacement:
				replaced = weapon
				break
		if int(replaced.get("upgrade_level", 0)) < 1:
			failures += 1
			print("FAIL: a duplicate weapon reset its upgrade level")
		elif int(replaced.get("atk", 0)) != upgraded_atk:
			failures += 1
			print("FAIL: preserved level did not keep its stat (%d != %d)"
				% [int(replaced.get("atk", 0)), upgraded_atk])
	gs.reset()
	gs.add_material("iron_shard", 8)
	gs.gold = 200
	gs.add_armor(gs.ARMOR_DEFS["spore_wrap"].duplicate(true), true)
	var armor_upgrade: Dictionary = gs.upgrade_armor("spore_wrap")
	if not bool(armor_upgrade.get("success", false)):
		failures += 1
		print("FAIL: could not upgrade armor for the replacement test")
	else:
		var upgraded_def := int(gs.equipped_armor.get("defense", 0))
		gs.add_armor(gs.ARMOR_DEFS["spore_wrap"].duplicate(true), false)
		var replaced_armor: Dictionary = {}
		for piece in gs.forged_armors:
			if str(piece.get("id", "")) == "spore_wrap":
				replaced_armor = piece
				break
		if int(replaced_armor.get("upgrade_level", 0)) < 1 \
				or int(replaced_armor.get("defense", 0)) != upgraded_def:
			failures += 1
			print("FAIL: a duplicate armor piece reset its forge work")

	# The first boss-clear bundle is intentionally sufficient for the same
	# upgrade and realm unlocks remain idempotent.
	gs.reset()
	gs.add_material("bramble_wood", 3)
	gs.add_material("beast_hide", 2)
	gs.add_material("iron_shard", 4)
	gs.gold = int(recipe.gold_cost)
	if not bool(CraftingData.craft("thorn_mace").get("success", false)):
		failures += 1
		print("FAIL: first-clear material bundle cannot fund the upgrade")
	if not gs.unlock_realm("moonfen") or gs.unlock_realm("moonfen"):
		failures += 1
		print("FAIL: visible next-realm unlock is not idempotent")

	# The boss reward is a complete combat kit, not a high-stat placeholder.
	gs.reset()
	var crown: Dictionary = gs.WEAPON_DEFS.get("matriarch_scepter", {})
	if crown.get("style", "") != "magic" or crown.get("element", "") != "nature" \
			or crown.get("skills", []).size() != 3:
		failures += 1
		print("FAIL: Matriarch reward is not a valid three-skill nature kit")
	if not gs.grant_unique_weapon("matriarch_scepter"):
		failures += 1
		print("FAIL: first Matriarch reward grant did not create ownership")
	if gs.grant_unique_weapon("matriarch_scepter"):
		failures += 1
		print("FAIL: repeat Matriarch reward duplicated ownership")
	if not gs.equip_weapon_by_id("matriarch_scepter"):
		failures += 1
		print("FAIL: Matriarch reward could not be equipped")
	var dummy := Node3D.new()
	root.add_child(dummy)
	gs.combat_state = gs.CombatState.EXPLORING
	gs.engage_enemy(dummy)
	var first_strike: Dictionary = gs.perform_auto_strike()
	var second_strike: Dictionary = gs.perform_auto_strike()
	if bool(first_strike.get("is_bloom", true)) \
			or not bool(second_strike.get("is_bloom", false)) \
			or int(second_strike.get("damage", 0)) - int(first_strike.get("damage", 0)) != 5:
		failures += 1
		print("FAIL: Crown passive does not bloom every second strike for +5")
	dummy.queue_free()
	gs.disengage_enemy()

	gs.add_objective("upgrade_matriarch_scepter",
		"Strengthen the Crown", "upgrade", 1)
	var crown_cost: Dictionary = gs.get_weapon_upgrade_cost(gs.equipped_weapon)
	gs.add_material(str(crown_cost.material_id), int(crown_cost.material_cost))
	gs.gold = int(crown_cost.gold_cost)
	var crown_upgrade: Dictionary = gs.upgrade_weapon("matriarch_scepter")
	if not bool(crown_upgrade.get("success", false)):
		failures += 1
		print("FAIL: Matriarch reward could not consume its exact upgrade cost")
	elif gs.quest_objectives.is_empty() \
			or not bool(gs.quest_objectives.back().get("completed", false)):
		failures += 1
		print("FAIL: weapon upgrade did not complete the post-boss objective")
	var upgraded_atk := int(gs.equipped_weapon.get("atk", 0))
	if gs.grant_unique_weapon("matriarch_scepter") \
			or int(gs.equipped_weapon.get("atk", 0)) != upgraded_atk:
		failures += 1
		print("FAIL: repeat reward replaced the upgraded Crown")
	gs.save_game()
	gs.reset()
	if not gs.load_game() \
			or int(gs.equipped_weapon.get("upgrade_level", 0)) != 1 \
			or int(gs.equipped_weapon.get("atk", 0)) != upgraded_atk:
		failures += 1
		print("FAIL: upgraded Matriarch reward did not round-trip through save/load")

	gs.delete_save()
	gs.materials_changed.disconnect(_on_materials_changed)
	var audio_manager := root.get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("shutdown_for_exit"):
		audio_manager.call("shutdown_for_exit")
	await _frames(60)
	if failures == 0:
		print("ALL VERTICAL SLICE PROGRESSION TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)

func _on_materials_changed() -> void:
	_material_signal_count += 1

func _frames(count: int) -> void:
	for _i in count:
		await process_frame
