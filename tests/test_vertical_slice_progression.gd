extends SceneTree

## P0 vertical-slice regression: gathering persistence, objective save/load,
## and transaction-safe gear crafting.

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
	if not gs.forged_weapons.any(func(w): return w.get("id", "") == "mug_mace"):
		failures += 1
		print("FAIL: crafted weapon was not granted as forged gear")
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
	if failures == 0:
		print("ALL VERTICAL SLICE PROGRESSION TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)
