extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := load("res://scenes/ui/stats_screen.tscn") as PackedScene
	if scene == null:
		push_error("Stats screen scene missing")
		quit(1)
		return
	var stats := scene.instantiate()
	root.add_child(stats)
	await process_frame
	var panel := stats.get_node("Root/Panel") as Control
	var rows := stats.get_node("Root/Panel/VBox/StatsPanel/Rows") as GridContainer
	root.size = Vector2(480.0, 800.0)
	await process_frame
	# The panel is a full-rect frame now, so the contract is that it fits the
	# viewport and the rows drop to one column — not a fixed minimum width.
	if rows.columns != 1 or panel.size.x > 480.0 or panel.size.y > 800.0:
		push_error("Stats screen compact layout did not clamp correctly")
		quit(1)
		return
	root.size = Vector2(1280.0, 800.0)
	await process_frame
	if rows.columns != 2 or panel.size.x > 1280.0 or panel.size.x < 1200.0:
		push_error("Stats screen expanded layout did not restore correctly")
		quit(1)
		return
	print("STATS RESPONSIVE SCENE PASSED")
	stats.queue_free()
	quit(0)
