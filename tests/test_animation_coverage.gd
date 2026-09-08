extends SceneTree

func _initialize() -> void:
	var rig := Node3D.new()
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for clip in ["Idle", "Walk", "Attack_Slash", "Hit", "Death"]:
		library.add_animation(clip, Animation.new())
	player.add_animation_library("", library)
	rig.add_child(player)
	root.add_child(rig)
	await process_frame
	var coverage: Dictionary = CharacterRigLoader.animation_coverage(rig)
	for key in ["idle", "move", "attack", "hit", "death", "authored_ready"]:
		if not bool(coverage.get(key, false)):
			print("FAIL: animation coverage missing ", key)
			rig.queue_free()
			quit(1)
			return
	print("ALL ANIMATION COVERAGE TESTS PASSED")
	rig.queue_free()
	quit(0)
