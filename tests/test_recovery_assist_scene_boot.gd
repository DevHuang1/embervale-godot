extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var game_state: Node = root.get_node_or_null("/root/GameState")
	if game_state == null:
		push_error("GameState autoload missing during recovery-assist scene boot")
		quit(1)
		return
	game_state.reset()
	var packed := load("res://scenes/world/grove.tscn") as PackedScene
	if packed == null:
		push_error("Grove scene could not load for recovery-assist boot")
		quit(1)
		return
	var grove := packed.instantiate()
	root.add_child(grove)
	for _frame in 12:
		await process_frame
	var hero: Node = grove.get_node_or_null("Hero")
	if hero == null:
		push_error("Hero missing after normal gameplay scene boot")
		quit(1)
		return
	var base := float(hero.get("dodge_iframes"))
	var assisted: float = float(hero.recovery_assist_iframes(base, true))
	var disabled: float = float(hero.recovery_assist_iframes(base, false))
	if assisted <= base or assisted > base + 0.10 or disabled != base:
		push_error("Recovery assist exceeded its capped dodge-only contract")
		quit(1)
		return
	if int(game_state.get("max_hp")) != 100 or int(game_state.get("gold")) != 30:
		push_error("Recovery-assist scene probe changed progression state")
		quit(1)
		return
	grove.queue_free()
	print("ALL RECOVERY ASSIST SCENE BOOT TESTS PASSED")
	quit()
