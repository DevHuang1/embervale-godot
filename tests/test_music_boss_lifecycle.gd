extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var audio_script := preload("res://scripts/autoload/audio_manager.gd")
	var audio: Node = audio_script.new()
	root.add_child(audio)
	# The procedural score has no external asset dependency and can be created
	# in the normal project runtime; this test checks the state contract itself.
	audio.set_music_state("boss")
	if audio.music_state != "boss":
		push_error("Boss music state was not accepted")
		quit(1)
		return
	audio.set_music_state("victory")
	if audio.music_state != "victory":
		push_error("Victory music state was not accepted")
		quit(1)
		return
	audio.start_boss_score("test")
	audio.finish_boss_score(false)
	if audio.music_state != "defeat":
		push_error("Defeat music state was not accepted without score layers")
		quit(1)
		return
	audio.start_boss_score("test")
	audio.stop_boss_score_immediate()
	if audio.music_state != "exploration":
		push_error("Immediate boss teardown did not restore exploration state")
		quit(1)
		return
	print("ALL MUSIC BOSS LIFECYCLE TESTS PASSED")
	audio.queue_free()
	quit()
