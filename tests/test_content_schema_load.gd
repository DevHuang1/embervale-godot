extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState") as GameState
	if gs == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	var path := "/tmp/embervale_legacy_content.cfg"
	gs.save_path = path
	gs.delete_save()
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema_version", 1)
	cfg.set_value("progress", "forged_weapons", [{"id": "ember_sword", "atk": 8}])
	cfg.set_value("progress", "equipped_weapon", {"id": "ember_sword", "atk": 8})
	cfg.set_value("progress", "forged_armors", [{"id": "warden_plate", "defense": 3}])
	cfg.set_value("progress", "equipped_armor", {"id": "warden_plate", "defense": 3})
	if cfg.save(path) != OK or not gs.load_game():
		push_error("Legacy content save could not be loaded")
		quit(1)
		return
	if int(gs.forged_weapons[0].get("content_schema", 0)) != 1 \
		or int(gs.forged_weapons[0].get("upgrade_level", -1)) != 0 \
		or int(gs.forged_armors[0].get("upgrade_level", -1)) != 0:
		push_error("Legacy gear did not migrate additively")
		quit(1)
		return
	gs.delete_save()

	# A veteran save that stored only the equipped starter weapon (no forge
	# ledger entry) must gain it on load so it can be upgraded and salvaged.
	var legacy_path := "/tmp/embervale_legacy_starter_weapon.cfg"
	gs.save_path = legacy_path
	gs.delete_save()
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "schema_version", 4)
	legacy.set_value("progress", "forged_weapons", [])
	legacy.set_value("progress", "equipped_weapon", {"id": "mug_mace"})
	if legacy.save(legacy_path) != OK or not gs.load_game():
		push_error("Starter-weapon-only save could not be loaded")
		quit(1)
		return
	if not gs.forged_weapons.any(func(w): return str(w.get("id", "")) == "mug_mace"):
		push_error("Equipped starter weapon was not adopted into the forge ledger")
		quit(1)
		return
	var adopted: Dictionary = {}
	for weapon in gs.forged_weapons:
		if str(weapon.get("id", "")) == "mug_mace":
			adopted = weapon
			break
	if str(adopted.get("name", "")).is_empty() or int(adopted.get("atk", 0)) <= 0:
		push_error("Adopted starter weapon was not normalized from its def")
		quit(1)
		return
	gs.delete_save()
	gs.save_path = path
	print("ALL CONTENT SCHEMA LOAD TESTS PASSED")
	quit()
