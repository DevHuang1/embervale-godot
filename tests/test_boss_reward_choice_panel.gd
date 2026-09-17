extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var panel_script := preload("res://scripts/ui/boss_reward_choice_panel.gd")
	var panel: PanelContainer = panel_script.new()
	root.add_child(panel)
	await process_frame
	panel.open_for("hushling_matriarch")
	await process_frame
	if panel.get_child_count() != 1 or panel.get_child(0).get_child_count() != 4:
		push_error("Boss reward choice panel did not build title, subtitle, and two choices")
		quit(1)
		return
	var first := panel.get_child(0).get_child(2) as Button
	var second := panel.get_child(0).get_child(3) as Button
	if not first.text.contains("Nature control") or not second.text.contains("Frontline guard"):
		push_error("Boss reward choice panel did not show distinct build directions")
		quit(1)
		return
	# The flavor title must not hide what the direction actually grants.
	var gs := root.get_node_or_null("/root/GameState")
	if gs == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	for choice_node in [first, second]:
		var button := choice_node as Button
		if not button.text.contains("GRANTS "):
			push_error("Boss reward choice does not name the item it grants")
			quit(1)
			return
		var reward_id := "matriarch_scepter" if button == first else "warden_plate"
		var granted_name := str(gs.WEAPON_DEFS[reward_id].get("name", "")) \
			if gs.WEAPON_DEFS.has(reward_id) else str(gs.ARMOR_DEFS[reward_id].get("name", ""))
		if not button.text.contains(granted_name.to_upper()):
			push_error("Boss reward choice names a different item than it grants -> %s" % reward_id)
			quit(1)
			return
	print("ALL BOSS REWARD CHOICE PANEL TESTS PASSED")
	panel.queue_free()
	quit()
