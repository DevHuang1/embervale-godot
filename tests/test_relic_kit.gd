extends SceneTree

## Headless functional check: scan-forged relic weapon kits.
## Covers user naming (sanitize + fallbacks), app-controlled numbers
## (rarity scaling, fixed cooldowns), equip flow, skill slots firing,
## and save/load roundtrip of named kits.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	# --- Kit generation ---
	var base: Dictionary = {
		"id": "mug_mace", "name": "MUG MACE", "glyph": "☕",
		"atk": 7, "swing_time": 0.38, "range": 8.2,
	}
	var item_name := "My Trusted Mug"
	var rite_names := ["Boom Tap", "Spin Storm", "TOTAL MUG"]
	var def := RelicData.build_weapon_def(base, 2, item_name, rite_names)

	if str(def.name) != item_name:
		failures += 1
		print("FAIL: item name not applied -> ", def.name)
	if not def.get("relic", false):
		failures += 1
		print("FAIL: relic flag missing")
	var skills: Array = def.skills
	if skills.size() != 3:
		failures += 1
		print("FAIL: kit size != 3")
	for i in skills.size():
		if str(skills[i].name) != rite_names[i]:
			failures += 1
			print("FAIL: rite %d name not applied" % i)
		if float(skills[i].cooldown) <= 0.0:
			failures += 1
			print("FAIL: rite %d has no cooldown" % i)
	if not str(skills[2].type) in ["comet", "explosion"]:
		failures += 1
		print("FAIL: ultimate slot is not a finisher type")

	# --- App-controlled numbers: rarity scales damage, never cooldowns ---
	var common := RelicData.build_weapon_def(base, 0, item_name, rite_names)
	if not (common.skills[0].dmg_mult < def.skills[0].dmg_mult):
		failures += 1
		print("FAIL: rarity did not scale damage")
	if absf(float(common.skills[0].cooldown) - float(def.skills[0].cooldown)) > 0.001:
		failures += 1
		print("FAIL: cooldowns drifted between rarities")
	if int(common.atk) >= int(def.atk):
		failures += 1
		print("FAIL: ATK did not scale with rarity")
	# Player input cannot touch numbers
	var troll := RelicData.build_weapon_def(base, 2, item_name,
		["999999999", "x".repeat(500), "-1e9 dmg"])
	if float(troll.skills[0].dmg_mult) != float(def.skills[0].dmg_mult) \
			or float(troll.skills[2].cooldown) != float(def.skills[2].cooldown):
		failures += 1
		print("FAIL: player input leaked into numbers")

	# --- Naming rules ---
	if RelicData.sanitize_name("a".repeat(50), "X").length() > RelicData.NAME_LIMIT:
		failures += 1
		print("FAIL: name length not capped")
	if RelicData.sanitize_name("  \t ", "FALLBACK") != "FALLBACK":
		failures += 1
		print("FAIL: empty name did not fall back")
	var dirty := RelicData.sanitize_name("Ok\bInvalidate", "FALLBACK")
	if dirty.contains("\b"):
		failures += 1
		print("FAIL: control chars survived sanitization")
	if RelicData.style_for("Alpha") != RelicData.style_for("Alpha"):
		failures += 1
		print("FAIL: style_for nondeterministic")

	# --- Equip & fire the kit ---
	gs.add_weapon(def.duplicate(true), true, "")
	if str(gs.equipped_weapon.get("id", "")).begins_with("relic_") == false:
		failures += 1
		print("FAIL: relic kit not equipped")
	if gs.get_skill(2).is_empty():
		failures += 1
		print("FAIL: ultimate slot missing after equip")
	
	var dummy := Node3D.new()
	dummy.add_to_group("enemy")
	root.add_child(dummy)
	if not gs.engage_enemy(dummy):
		failures += 1
		print("FAIL: relic wielder could not engage a target")
	var cast: Dictionary = gs.use_skill(0)
	if not cast.success:
		failures += 1
		print("FAIL: named skill rejected: ", cast.message)
	if gs.use_skill(0).success:
		failures += 1
		print("FAIL: same skill fired while cooling down")
	gs.update_skill_cooldowns(float(cast.skill.cooldown) + 0.1)
	if not gs.can_use_skill_slot(0):
		failures += 1
		print("FAIL: skill cooldown never recovered")
	var ult: Dictionary = gs.use_skill(2)
	if not ult.success:
		failures += 1
		print("FAIL: ultimate rejected: ", ult.message)

	# --- Save / load roundtrip keeps names and numbers ---
	gs.save_game()
	gs.reset()
	gs.load_game()
	if str(gs.equipped_weapon.get("id", "")).begins_with("relic_") == false:
		failures += 1
		print("FAIL: relic kit lost across save/load")
	var loaded: Array = gs.equipped_weapon.get("skills", [])
	if loaded.size() != 3:
		failures += 1
		print("FAIL: kit size lost across save/load")
	else:
		for i in 3:
			if str(loaded[i].name) != rite_names[i]:
				failures += 1
				print("FAIL: rite %d renamed across save/load" % i)
			if absf(float(loaded[i].dmg_mult) - float(skills[i].dmg_mult)) > 0.001:
				failures += 1
				print("FAIL: rite %d numbers changed across save/load" % i)

	dummy.queue_free()

	if failures == 0:
		print("ALL RELIC KIT TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(1 if failures > 0 else 0)
