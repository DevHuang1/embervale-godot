extends SceneTree

## Responsive HUD contract: portrait keeps the primary HUD readable by hiding
## the secondary action row behind one explicit control.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 12:
		await process_frame
	var hud := scene.get_node_or_null("HUD") as Node
	if hud == null:
		push_error("HUD missing")
		quit(1)
		return
	root.size = Vector2i(1080, 1920)
	await process_frame
	var toggle := hud.get_node_or_null("Root/MetaRow/TopRow/ActionsToggle") as Button
	var action_row := hud.get_node_or_null("Root/MetaRow/ActionRow") as Control
	if toggle == null or action_row == null:
		push_error("compact action controls missing")
		quit(1)
		return
	if not toggle.visible or action_row.visible:
		push_error("compact HUD did not collapse secondary actions")
		quit(1)
		return
	toggle.emit_signal("pressed")
	await process_frame
	if not action_row.visible or toggle.text != "HIDE":
		push_error("compact HUD action drawer did not open")
		quit(1)
		return
	var close_button := scene.get_node_or_null("SettingsMenu/Root/Panel/Header/CloseButton") as Button
	if close_button == null or close_button.text != "CLOSE":
		push_error("settings exit control is not explicit")
		quit(1)
		return
	var rewards := root.get_node("/root/RewardManager")
	rewards.quest_reward_granted.emit("objective:test", "Gather", {
		"gold": 10, "xp": 0, "diamonds": 0, "items": [], "materials": [],
		"weapons": [], "armors": [], "loot_context": [],
		"completion_kind": "quest_objective"})
	rewards.quest_reward_granted.emit("stage:test", "Chapter", {
		"gold": 0, "xp": 25, "diamonds": 0, "items": [], "materials": [],
		"weapons": [], "armors": [], "loot_context": [],
		"completion_kind": "quest_stage"})
	await process_frame
	var reveal_center := hud.find_child("RewardRevealCenter*", true, false)
	if reveal_center == null or hud.get("_reward_popup_queue").size() != 1:
		push_error("reward popup queue did not retain the second completion")
		quit(1)
		return
	var first_panel := reveal_center.get_child(0) as RewardRevealPanel
	var first_title := first_panel.find_child("RewardRevealTitle", true, false) as Label \
		if first_panel != null else null
	if first_panel == null or first_title == null or first_title.text != "OBJECTIVE COMPLETE":
		push_error("first queued reward popup was not shown")
		quit(1)
		return
	first_panel.dismiss()
	for i in 6:
		await process_frame
	var next_center := hud.find_child("RewardRevealCenter*", true, false)
	if next_center == null or hud.get("_reward_popup_queue").size() != 0:
		push_error("reward popup queue did not advance after dismissal")
		quit(1)
		return
	scene.queue_free()
	# Process the free before quitting so the scene is torn down while the
	# tree is still alive.
	await process_frame
	print("HUD COMPACT ACTION TESTS PASSED")
	quit()
