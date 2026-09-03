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
	_assert_true(labels.any(func(text: String) -> bool:
		return text.contains("Every second basic strike")),
		"weapon card explains the build-changing passive")
	_assert_true(labels.any(func(text: String) -> bool:
		return text.contains("ATK 11") and text.contains("MAGIC")),
		"weapon card compares attack and playstyle")
	_assert_true(buttons.any(func(text: String) -> bool:
		return text.contains("UPGRADE +1") and text.contains("IRON") and text.contains("GOLD")),
		"weapon card exposes exact forge requirements")
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
