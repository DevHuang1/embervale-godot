extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := get_root().get_node_or_null("/root/GameState") as GameState
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.reset()
	var grove_scene := load("res://scenes/world/grove.tscn") as PackedScene
	var grove := grove_scene.instantiate()
	get_root().add_child(grove)
	await process_frame
	var hero := grove.get_node_or_null("Hero")
	if hero == null:
		print("FAIL: Grove Hero missing")
		quit(1)
		return
	var a := Node3D.new()
	var b := Node3D.new()
	a.add_to_group("enemy")
	b.add_to_group("enemy")
	grove.add_child(a)
	grove.add_child(b)
	a.global_position = hero.global_position + Vector3(2, 0, 0)
	b.global_position = hero.global_position + Vector3(3, 0, 0)
	await process_frame
	var first := hero.call("cycle_target", 18.0) as Node3D
	var second := hero.call("cycle_target", 18.0) as Node3D
	if first == null or second == null or first == second or gs.enemy_target != second:
		print("FAIL: target switch did not rotate nearby foes first=", first, " second=", second, " locked=", gs.enemy_target)
		quit(1)
		return
	grove.queue_free()
	print("ALL TARGET SWITCH TESTS PASSED")
	quit(0)
