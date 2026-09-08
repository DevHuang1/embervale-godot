extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node("/root/GameState")
	var failures := 0
	for weapon_id in gs.WEAPON_DEFS:
		var weapon: Dictionary = gs.WEAPON_DEFS[weapon_id]
		var skills: Array = weapon.get("skills", [])
		if skills.size() != 3 or str(weapon.get("style", "")).is_empty():
			failures += 1
			print("FAIL: incomplete canonical weapon ", weapon_id)
		for skill in skills:
			if not skill is Dictionary or str(skill.get("name", "")).is_empty() \
					or str(skill.get("type", "")).is_empty() \
					or float(skill.get("cooldown", 0.0)) <= 0.0:
				failures += 1
				print("FAIL: incomplete skill on ", weapon_id)

	var legacy := {"id": "pocket_blade", "name": "POCKET BLADE", "skill": {"name": "FLASH", "type": "strike", "cooldown": 1.0}}
		# add_weapon performs the legacy-to-canonical normalization in-place for storage.
	gs.add_weapon(legacy, false)
	var stored: Dictionary = gs.forged_weapons.back()
	if stored.get("skills", []).size() != 3 or stored.has("skill"):
		failures += 1
		print("FAIL: legacy scan weapon was not normalized")
	print("WEAPON CATALOG COMPLETE" if failures == 0 else "%d WEAPON CATALOG FAILURES" % failures)
	quit(1 if failures > 0 else 0)
