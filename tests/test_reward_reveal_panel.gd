extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var panel := preload("res://scripts/ui/reward_reveal_panel.gd").new()
	root.add_child(panel)
	await process_frame
	panel.open_for([{"id": "moss", "label": "Moss Fiber", "quantity": 2, "rarity": 1}], "loot")
	if not panel.visible or panel.find_child("AccessibleRewardSummary", true, false) == null \
			or panel.find_child("SkipRewardReveal", true, false) == null:
		push_error("Reward reveal panel did not build accessible summary/skip controls")
		quit(1)
		return
	panel.dismiss()
	if panel.visible:
		push_error("Reward reveal panel did not dismiss")
		quit(1)
		return
	print("REWARD REVEAL PANEL PASSED")
	quit(0)
