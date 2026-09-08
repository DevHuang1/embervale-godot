extends SceneTree

func _init() -> void:
	var scene := load("res://scenes/entities/combat_training_target.tscn") as PackedScene
	var target: CharacterBody3D = scene.instantiate()
	root.add_child(target)
	await process_frame
	if not target.is_in_group("enemy") or target.hp != 120:
		push_error("training target setup failed")
		quit(1)
		return
	target.take_damage(40, Vector3.FORWARD)
	if target.hp != 80 or target.is_defeated:
		push_error("training target damage contract failed")
		quit(1)
		return
	target.take_damage(80)
	if not target.is_defeated or target.visible:
		push_error("training target defeat state failed")
		quit(1)
		return
	target.reset_target()
	if target.hp != 120 or target.is_defeated or not target.visible:
		push_error("training target reset failed")
		quit(1)
		return
	print("ALL COMBAT TRAINING TARGET TESTS PASSED")
	quit()
