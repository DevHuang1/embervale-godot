extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState") as GameState
	if gs == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	gs.save_path = "/tmp/embervale_boss_reward_selection.cfg"
	gs.delete_save()
	gs.reset()
	var first: Dictionary = gs.choose_boss_reward("hushling_matriarch", "warden_plate")
	if not bool(first.get("success", false)) or gs.forged_armors.is_empty():
		push_error("Valid boss reward selection failed")
		quit(1)
		return
	if bool(gs.choose_boss_reward("hushling_matriarch", "matriarch_scepter").get("success", false)):
		push_error("Duplicate boss reward selection succeeded")
		quit(1)
		return
	gs.save_game()
	gs.reset()
	if not gs.load_game() or gs.boss_reward_selections.get("hushling_matriarch") != "warden_plate":
		push_error("Boss reward selection did not survive save/load")
		quit(1)
		return

	# Reward directions share a gear pool, so a second boss can offer a piece the
	# player already carries. That must pay the piece's resale value rather than
	# consuming the choice and granting nothing.
	gs.reset()
	gs.add_armor(gs.ARMOR_DEFS["warden_plate"].duplicate(true), false)
	var gold_before: int = gs.gold
	var duplicate_reward: Dictionary = gs.choose_boss_reward("biome_thornhide_alpha",
		"warden_plate")
	if not bool(duplicate_reward.get("success", false)):
		push_error("Duplicate reward selection was rejected outright: %s" % duplicate_reward)
		quit(1)
		return
	if not bool(duplicate_reward.get("duplicate", false)):
		push_error("Duplicate reward was not reported as a duplicate")
		quit(1)
		return
	var expected_pay: int = gs.gear_sell_value("warden_plate", "armor")
	if int(duplicate_reward.get("compensation", 0)) != expected_pay \
			or gs.gold != gold_before + expected_pay:
		push_error("Duplicate reward did not pay the piece's resale value")
		quit(1)
		return
	if gs.forged_armors.size() != 1:
		push_error("Duplicate reward duplicated the owned armor entry")
		quit(1)
		return
	# A fresh reward still grants the item itself, with no compensation.
	gs.reset()
	var fresh_gold: int = gs.gold
	var fresh_reward: Dictionary = gs.choose_boss_reward("biome_thornhide_alpha",
		"thornbite_cleaver")
	if not bool(fresh_reward.get("success", false)) \
			or bool(fresh_reward.get("duplicate", false)) \
			or int(fresh_reward.get("compensation", 0)) != 0:
		push_error("Fresh reward was treated as a duplicate: %s" % fresh_reward)
		quit(1)
		return
	if gs.gold != fresh_gold:
		push_error("Fresh reward changed the player's gold")
		quit(1)
		return
	if not gs.forged_weapons.any(func(w): return str(w.get("id", "")) == "thornbite_cleaver"):
		push_error("Fresh reward did not grant the weapon")
		quit(1)
		return
	gs.delete_save()
	print("ALL BOSS REWARD SELECTION TESTS PASSED")
	quit()
