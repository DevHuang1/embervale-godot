extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var panel := preload("res://scripts/ui/reward_reveal_panel.gd").new()
	root.add_child(panel)
	await process_frame
	panel.open_for([{"id": "moss", "label": "Moss Fiber", "quantity": 2, "rarity": 1}], "loot")
	if not panel.visible or panel.find_child("AccessibleRewardSummary", true, false) == null:
		push_error("Reward reveal panel did not build accessible summary")
		quit(1)
		return
	if panel.find_child("SkipRewardReveal", true, false) != null:
		push_error("Reward reveal panel still exposes a manual continue control")
		quit(1)
		return
	var dismissed := [false]
	panel.dismissed.connect(func() -> void: dismissed[0] = true)
	panel.open_for([{"id": "moss", "label": "Moss Fiber", "quantity": 2, "rarity": 1}],
		"loot", "", "", 0.1)
	await create_timer(0.9).timeout
	if panel.visible or not dismissed[0]:
		push_error("Reward reveal panel did not auto-dismiss")
		quit(1)
		return
	panel.open_for([{"id": "moss", "label": "Moss Fiber", "quantity": 2, "rarity": 1}], "loot")
	if not panel.visible:
		push_error("Reward reveal panel did not reopen after auto-dismiss")
		quit(1)
		return
	panel.dismiss()
	if panel.visible:
		push_error("Reward reveal panel did not dismiss")
		quit(1)
		return
	print("REWARD REVEAL PANEL PASSED")
	quit(0)
