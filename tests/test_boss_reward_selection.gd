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
	gs.delete_save()
	print("ALL BOSS REWARD SELECTION TESTS PASSED")
	quit()
