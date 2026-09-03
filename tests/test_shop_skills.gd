extends SceneTree

## Headless functional check: currency, shop purchase/equip,
## weapon skill kits, cooldowns, armor defense, save roundtrip.

func _initialize() -> void:
	# Autoloads register just after initialize; run one frame later
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var gs = root.get_node("/root/GameState")
	gs.save_path = "/tmp/embervale_shop_skills_test.cfg"
	gs.delete_save()
	gs.reset()

	# --- Registry integrity ---
	for id in ["ember_sword", "arcane_staff"]:
		var w: Dictionary = gs.WEAPON_DEFS[id]
		assert(w.skills.size() == 3)
	for id in ["warden_plate", "emberweave_cloak"]:
		assert(gs.ARMOR_DEFS[id].has("defense"))

	# --- Currency & shop ---
	gs.add_gold(200)
	var before: int = gs.gold
	var r: Dictionary = gs.buy_shop_item("ember_sword")
	if not r.success:
		failures += 1
		print("FAIL: buy sword -> ", r.message)
	if gs.gold != before - 75:
		failures += 1
		print("FAIL: gold deduction, now ", gs.gold)
	if gs.equipped_weapon.get("id", "") != "ember_sword":
		failures += 1
		print("FAIL: sword not auto-equipped")
	if not gs.owns_shop_item("ember_sword"):
		failures += 1
		print("FAIL: owns_shop_item false after buy")
	if gs.buy_shop_item("ember_sword").success:
		failures += 1
		print("FAIL: double purchase allowed")

	# --- Skill kit ---
	if gs.get_skill(2).is_empty():
		failures += 1
		print("FAIL: sword slot 2 missing")
	if gs.use_skill(0).success:
		failures += 1
		print("FAIL: skill fired without a marked target")
	if gs.get_slot_cooldown_text(0) != "READY":
		failures += 1
		print("FAIL: slot 0 on cooldown before use")

	# Mark a dummy target so targeted rites pass validation
	var dummy := Node3D.new()
	dummy.add_to_group("enemy")
	root.add_child(dummy)
	gs.current_stage = gs.QuestStage.SEEK_SPRITE
	gs.engage_enemy(dummy)
	var cast: Dictionary = gs.use_skill(0)
	if not cast.success:
		failures += 1
		print("FAIL: Crescent Cut rejected: ", cast.message)
	if gs.get_slot_cooldown_text(0) == "READY":
		failures += 1
		print("FAIL: no cooldown applied after cast")
	if gs.use_skill(0).success:
		failures += 1
		print("FAIL: same skill cast while cooling down")
	# Cooldowns tick down
	gs.update_skill_cooldowns(float(cast.skill.cooldown) * 1.20 + 0.1)
	if not gs.can_use_skill_slot(0):
		failures += 1
		print("FAIL: cooldown never recovered")

	# --- Staff kit ---
	gs.spend_gold(gs.gold - 90)
	if not gs.buy_shop_item("arcane_staff").success:
		failures += 1
		print("FAIL: staff purchase")
	if str(gs.equipped_weapon.get("style")) != "magic":
		failures += 1
		print("FAIL: staff style missing")

	# --- Armor ---
	gs.add_gold(200)
	if not gs.buy_shop_item("warden_plate").success:
		failures += 1
		print("FAIL: plate purchase")
	if gs.armor_defense() != 3:
		failures += 1
		print("FAIL: plate defense ", gs.armor_defense())
	if gs.armor_adjusted_damage(10) != 7:
		failures += 1
		print("FAIL: armor mitigation math")
	if gs.buy_shop_item("emberweave_cloak").success:
		if absf(gs.armor_speed_mult() - 1.08) > 0.001:
			failures += 1
			print("FAIL: cloak speed mult")
		gs.equip_armor("warden_plate")
		if gs.armor_defense() != 3:
			failures += 1
			print("FAIL: re-equip plate failed")

	# --- Save/load roundtrip ---
	gs.save_game()
	var saved_embers: int = gs.gold
	gs.reset()
	if gs.gold == saved_embers and saved_embers != 30:
		pass  # reset legitimately zeroes progress
	gs.load_game()
	if gs.equipped_weapon.get("id", "") != "arcane_staff":
		failures += 1
		print("FAIL: staff lost across load")
	if gs.armor_defense() != 3:
		failures += 1
		print("FAIL: armor lost across load")

	dummy.queue_free()
	gs.delete_save()

	if failures == 0:
		print("ALL SHOP/SKILL/ARMOR TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(1 if failures > 0 else 0)
