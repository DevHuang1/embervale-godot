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
	print("ALL CONTENT SCHEMA LOAD TESTS PASSED")
	quit()
