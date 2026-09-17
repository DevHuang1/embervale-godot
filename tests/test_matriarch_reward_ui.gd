extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var game_state := root.get_node("GameState")
	game_state.save_path = "/tmp/embervale_matriarch_reward_ui.cfg"
	game_state.delete_save()
	game_state.reset()
	game_state.grant_unique_weapon("matriarch_scepter")
	var packed := load("res://scenes/ui/satchel.tscn") as PackedScene
	_assert_true(packed != null, "satchel scene loads")
	if packed == null:
		_finish(game_state)
		return
	var satchel := packed.instantiate()
	root.add_child(satchel)
	await process_frame
	var labels: Array[String] = []
	for label in satchel.find_children("*", "Label", true, false):
		labels.append(str((label as Label).text))
	var buttons: Array[String] = []
	for button in satchel.find_children("*", "Button", true, false):
		buttons.append(str((button as Button).text))
	_assert_true(labels.any(func(text: String) -> bool:
		return text.contains("CROWN OF THE OLD ROOT")),
		"owned Matriarch reward appears by authored name")
	# Select by id: the starter weapon is ledger gear now, so index 0 is not
	# necessarily the reward.
	var reward_weapon: Dictionary = {}
	for weapon in game_state.forged_weapons:
		if str(weapon.get("id", "")) == "matriarch_scepter":
			reward_weapon = weapon
			break
	_assert_true(not reward_weapon.is_empty(), "Matriarch reward is in the forge ledger")
	if reward_weapon.is_empty():
		_finish(game_state)
		return
	satchel.call("_show_item_detail", reward_weapon)
	await process_frame
	var inspect_detail := str(satchel.get("_selected_item_label").text)
	_assert_true(inspect_detail.contains("Every second basic strike"),
		"inspect sheet explains the build-changing passive")
	_assert_true(inspect_detail.contains("ATK 11") and inspect_detail.contains("MAGIC")
		and inspect_detail.contains("vs current"),
		"inspect sheet compares attack and playstyle")
	_assert_true(inspect_detail.contains("UPGRADE") and inspect_detail.contains("IRON")
		and inspect_detail.contains("GOLD"),
		"inspect sheet exposes exact forge requirements")
	satchel.queue_free()
	await process_frame
	_finish(game_state)

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		print("FAILURE: ", message)

func _finish(game_state: Node) -> void:
	game_state.delete_save()
	if failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", failures)
		quit(1)
