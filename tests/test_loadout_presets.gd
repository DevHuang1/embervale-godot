extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState") as GameState
	if gs == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	var gold := gs.gold
	var weapon_id := str(gs.equipped_weapon.get("id", ""))
	if not gs.save_loadout_preset(0) or str(gs.loadout_presets["0"].get("weapon_id", "")) != weapon_id:
		push_error("Loadout preset did not capture the equipped build")
		quit(1)
		return
	if not gs.apply_loadout_preset(0) or gs.gold != gold:
		push_error("Loadout preset changed currency or failed to apply")
		quit(1)
		return
	if gs.save_loadout_preset(GameState.MAX_LOADOUT_PRESETS) or gs.apply_loadout_preset(99):
		push_error("Loadout preset bounds were not enforced")
		quit(1)
		return
	var ui_source := FileAccess.get_file_as_string("res://scripts/ui/stats_screen.gd")
	if not ui_source.contains("_save_loadout") or not ui_source.contains("_apply_loadout"):
		push_error("Loadout preset controls are missing from the stat screen")
		quit(1)
		return
	print("LOADOUT PRESETS PASSED")
	quit(0)
