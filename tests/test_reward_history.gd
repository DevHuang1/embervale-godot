extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(900, 600)
	var grove_scene := load("res://scenes/world/grove.tscn") as PackedScene
	if grove_scene == null:
		push_error("Grove scene missing")
		quit(1)
		return
	var grove := grove_scene.instantiate()
	root.add_child(grove)
	await process_frame
	await process_frame
	var hud := grove.get_node_or_null("HUD")
	if hud == null:
		push_error("Grove HUD missing")
		quit(1)
		return
	for i in 10:
		hud.call("_on_loot_received", "Reward %d" % i, 1)
	hud.call("_on_journal_pressed")
	await process_frame
	var history := hud.find_child("RecentRewardHistory", true, false)
	if history == null:
		push_error("Journal recent activity section missing")
		quit(1)
		return
	var text := str(history.text)
	if not text.contains("Reward 9") or text.contains("Reward 0"):
		push_error("Reward history cap/order incorrect: %s" % text)
		quit(1)
		return
	var viewport_size: Vector2 = root.get_viewport().get_visible_rect().size
	var panel_rect := (hud.get_node("ExpeditionJournal") as Control).get_global_rect()
	if panel_rect.position.x < 0.0 or panel_rect.position.y < 0.0 \
			or panel_rect.end.x > viewport_size.x + 1.0 \
			or panel_rect.end.y > viewport_size.y + 1.0:
		push_error("Journal panel escaped the viewport: %s in %s" % [panel_rect, viewport_size])
		quit(1)
		return
	print("ALL REWARD HISTORY TESTS PASSED")
	grove.queue_free()
	quit(0)
