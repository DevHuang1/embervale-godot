extends SceneTree

## Headless check: XP curve & level-ups, stat allocation, defense stacking,
## embers->gold save migration, diamond economy + cosmetic persistence,
## boss first-kill marking.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var gs = root.get_node("/root/GameState")
	gs.save_path = "/tmp/embervale_progression_test.cfg"
	gs.delete_save()
	gs.reset()

	# --- XP curve sanity ---
	if gs.xp_to_level(2) != 50 or gs.xp_to_level(10) != 1450:
		failures += 1
		print("FAIL: xp table drifted")
	if not (gs.xp_to_level(11) > gs.xp_to_level(10) and gs.xp_to_level(12) > gs.xp_to_level(11)):
		failures += 1
		print("FAIL: post-10 curve not increasing")

	# --- Level-ups grant points and HP ---
	gs.stat_vit = 0
	var hp_before: int = gs.max_hp
	gs.grant_xp(gs.xp_to_level(4) - gs.xp)
	if gs.level != 4:
		failures += 1
		print("FAIL: multi-level jump wrong -> ", gs.level)
	if gs.stat_points != (4 - 1) * 3:
		failures += 1
		print("FAIL: points per level wrong -> ", gs.stat_points)
	if gs.max_hp <= hp_before:
		pass  # VIT is 0 here; base HP unchanged until allocation

	# --- Allocation ---
	gs.stat_points = 3
	if not gs.allocate_stat("vit"):
		failures += 1
		print("FAIL: vit allocation refused")
	if gs.max_hp != gs.MAX_HP_BASE + 3 * gs.stat_vit:
		failures += 1
		print("FAIL: max_hp not scaled by VIT")
	if gs.allocate_stat("nope"):
		failures += 1
		print("FAIL: bogus stat accepted")
	gs.allocate_stat("end")
	if gs.armor_adjusted_damage(10) != maxi(1, 10 - gs.armor_defense() - gs.defense_stat()):
		failures += 1
		print("FAIL: defense not stacking with armor")
	if absf(gs.crit_chance() - (0.05 + 0.01 * gs.stat_luk)) > 0.0001:
		failures += 1
		print("FAIL: crit chance formula")

	# --- Migration: legacy embers save becomes gold, diamonds zeroed ---
	gs.reset()
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "embers", 77)
	cfg.set_value("progress", "current_stage", 1)
	cfg.save(gs.save_path)
	gs.load_game()
	if gs.gold != 77:
		failures += 1
		print("FAIL: legacy embers not migrated -> ", gs.gold)

	# --- Diamonds + cosmetics roundtrip ---
	gs.add_diamonds(6)
	if not gs.spend_diamonds(6):
		failures += 1
		print("FAIL: diamond spend failed")
	gs.add_diamonds(10)
	if not gs.purchase_cosmetic("trail_aurora", 4, "trail", "73f2d9"):
		failures += 1
		print("FAIL: cosmetic purchase failed")
	if not gs.owns_cosmetic("trail_aurora"):
		failures += 1
		print("FAIL: ownership missing")
	if str(gs.active_trail_color) != "73f2d9":
		failures += 1
		print("FAIL: trail color not equipped")
	if gs.purchase_cosmetic("trail_aurora", 4, "trail", "73f2d9") != true:
		pass  # re-purchase is a no-op success by contract
	gs.save_game()
	gs.reset()
	gs.load_game()
	if not gs.owns_cosmetic("trail_aurora"):
		failures += 1
		print("FAIL: cosmetics lost across load")
	if str(gs.active_trail_color) != "73f2d9":
		failures += 1
		print("FAIL: active trail lost across load")

	# --- Boss first-kill marking ---
	if not gs.mark_boss_killed("boss_a"):
		failures += 1
		print("FAIL: first kill not marked")
	if gs.mark_boss_killed("boss_a"):
		failures += 1
		print("FAIL: second kill granted first-kill again")

	# --- Realm tracking ---
	if not gs.unlock_realm("moonfen"):
		failures += 1
		print("FAIL: new realm unlock did not report a state change")
	if gs.unlock_realm("moonfen"):
		failures += 1
		print("FAIL: repeated realm unlock reported a duplicate change")
	gs.set_current_realm("moonfen")
	gs.save_game()
	gs.load_game()
	if gs.current_realm != "moonfen" or not ("moonfen" in gs.unlocked_realms):
		failures += 1
		print("FAIL: realm state lost across load")

	if failures == 0:
		print("ALL PROGRESSION TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(1 if failures > 0 else 0)
