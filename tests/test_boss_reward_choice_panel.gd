extends SceneTree

func _init() -> void:
	var panel_script := preload("res://scripts/ui/boss_reward_choice_panel.gd")
	var panel: PanelContainer = panel_script.new()
	root.add_child(panel)
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
	print("ALL BOSS REWARD CHOICE PANEL TESTS PASSED")
	panel.queue_free()
	quit()
