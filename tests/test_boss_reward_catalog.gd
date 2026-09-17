extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/boss_reward_catalog.gd")
	var required_bosses := [
		"hushling_matriarch",
		"bramblewood_thornwarden",
		"moonfen_voidweaver",
		"heartwood_cindercolossus",
		"mistfen_siltcrawler",
		"biome_thornhide_alpha",
		"biome_rootbound_warden",
		"biome_fenmaw",
		"biome_cinderhart_colossus",
		"biome_moonfen_oracle",
	]
	for boss_id in required_bosses:
		var choices: Array[Dictionary] = catalog.choices_for(boss_id)
		if choices.size() < 2:
			push_error("Boss %s has fewer than 2 reward choices" % boss_id)
			quit(1)
			return
		if choices[0].get("build_tag") == choices[1].get("build_tag"):
			push_error("Boss %s choices do not offer distinct build directions" % boss_id)
			quit(1)
			return
		for choice in choices:
			for key in ["id", "title", "build_tag", "summary"]:
				if str(choice.get(key, "")).is_empty():
					push_error("Boss %s reward choice is missing %s" % [boss_id, key])
					quit(1)
					return
	if not catalog.choices_for("unknown_boss").is_empty():
		push_error("Unknown boss unexpectedly has reward choices")
		quit(1)
		return
	print("ALL BOSS REWARD CATALOG TESTS PASSED")
	quit()
