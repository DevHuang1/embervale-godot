extends SceneTree

## Regression: logic services must not be represented by off-tree Nodes, and
## the audio autoload must expose an exit cleanup boundary for active voices.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var skill_range := SkillRange.get_instance()
	_assert_true(not is_instance_of(skill_range, Node),
		"SkillRange is a RefCounted service rather than an orphanable Node")
	_assert_true(skill_range.is_in_range(Vector3.ZERO, Vector3(4.0, 0.0, 0.0), 2),
		"SkillRange retains its tile-distance behavior")

	var audio_source := FileAccess.get_file_as_string("res://scripts/autoload/audio_manager.gd")
	_assert_true(audio_source.contains("func _exit_tree() -> void:"),
		"AudioManager owns an autoload teardown hook")
	_assert_true(audio_source.contains("func shutdown_for_exit() -> void:"),
		"AudioManager exposes an explicit exit-only shutdown boundary")
	_assert_true(audio_source.contains("player.stop()") and audio_source.contains("AudioStreamPlayer3D"),
		"AudioManager teardown stops both 2D and 3D voices")

	print("RUNTIME LIFECYCLE CONTRACT PASSED")
	quit(0)

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAIL: " + message)
		quit(1)
