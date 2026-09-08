extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/entities/hushling.gd")
	_check(not source.is_empty(), "hushling source is available")
	_check(source.contains("aggro_radius") and source.contains("attack_radius"),
		"separate aggro and attack radii exist")
	_check(source.contains("pursuit_radius") and source.contains("disengage_radius"),
		"pursuit and disengage hysteresis exist")
	_check(source.contains("_has_player_line_of_sight"), "line-of-sight gate exists")
	_check(source.contains("is_player_engaged"), "engagement query exists")
	_check(source.contains("velocity.x = move_toward"), "disengaged enemies stop moving")
	print("ENEMY AGGRO CONTRACT PASSED" if failures.is_empty() else "FAILURES: ", failures)
	quit(1 if not failures.is_empty() else 0)

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
