extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/boss_reward_catalog.gd")
	var choices: Array[Dictionary] = catalog.choices_for("hushling_matriarch")
	if choices.size() != 2 or choices[0].get("build_tag") == choices[1].get("build_tag"):
		push_error("Matriarch choices do not offer distinct build directions")
		quit(1)
		return
	for choice in choices:
		for key in ["id", "title", "build_tag", "summary"]:
			if str(choice.get(key, "")).is_empty():
				push_error("Boss reward choice is missing %s" % key)
				quit(1)
				return
	if not catalog.choices_for("unknown_boss").is_empty():
		push_error("Unknown boss unexpectedly has reward choices")
		quit(1)
		return
	print("ALL BOSS REWARD CATALOG TESTS PASSED")
	quit()
