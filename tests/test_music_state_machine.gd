extends SceneTree

func _init() -> void:
	var audio_script := preload("res://scripts/autoload/audio_manager.gd")
	var audio: Node = audio_script.new()
	if audio.music_state != "exploration":
		push_error("Audio manager did not start in exploration state")
		quit(1)
		return
	audio.set_music_state("danger")
	if audio.music_state != "danger":
		push_error("Music state did not transition")
		quit(1)
		return
	audio.set_music_state("not-a-state")
	if audio.music_state != "danger":
		push_error("Invalid music state was accepted")
		quit(1)
		return
	print("ALL MUSIC STATE MACHINE TESTS PASSED")
	audio.free()
	quit()
