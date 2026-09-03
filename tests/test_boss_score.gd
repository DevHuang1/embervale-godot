extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var audio := root.get_node_or_null("AudioManager") as AudioManager
	_assert_true(audio != null, "AudioManager autoload is available")
	if audio == null:
		_finish()
		return
	audio.stop_boss_score_immediate()
	audio.start_boss_score("matriarch")
	_assert_true(audio._boss_score_players.size() == audio.BOSS_SCORE_LAYER_CAP,
		"boss score owns exactly three capped voices")
	_assert_true(audio._boss_score_streams.size() == audio.BOSS_SCORE_LAYER_CAP,
		"boss score caches exactly three procedural layers")
	for stream in audio._boss_score_streams:
		_assert_true(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"each boss layer is a bounded forward loop")
		_assert_true(not stream.data.is_empty(), "each boss layer contains rendered audio")
	for player in audio._boss_score_players:
		_assert_true(player.playing, "all boss layers launch on the shared start frame")

	var initial_players := audio._boss_score_players.duplicate()
	audio.start_boss_score("matriarch")
	_assert_true(audio._boss_score_players.size() == audio.BOSS_SCORE_LAYER_CAP,
		"restarting the score never allocates extra voices")
	_assert_true(audio._boss_score_players == initial_players,
		"restarting reuses the fixed player pool")

	audio.set_boss_score_phase(0)
	var phase_one := audio._boss_score_targets.duplicate()
	audio.set_boss_score_phase(3)
	var enrage := audio._boss_score_targets.duplicate()
	_assert_true(enrage[1] > phase_one[1] and enrage[2] > phase_one[2],
		"later phases reveal percussion and ostinato without adding voices")
	audio.reset_boss_score()
	_assert_true(audio.boss_score_phase == 0,
		"encounter reset returns the score to its opening orchestration")
	audio.finish_boss_score(false)
	_assert_true(audio._boss_score_fading and audio._boss_score_targets == [-60.0, -60.0, -60.0],
		"death sequence fades every layer through one bounded cleanup path")
	audio.stop_boss_score_immediate()
	_assert_true(not audio.boss_score_active and audio.boss_score_phase == -1,
		"realm exit stops the persistent score state")
	for player in audio._boss_score_players:
		_assert_true(not player.playing, "realm exit stops every boss voice")
	_finish()

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		print("FAILURE: ", message)

func _finish() -> void:
	if failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", failures)
		quit(1)
