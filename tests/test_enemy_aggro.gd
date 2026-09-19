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
	# Per-archetype sensing: cone sight, hearing, and an anchor leash the mob
	# breaks off to walk home instead of freezing wherever it was kited.
	_check(source.contains("MobSensing.profile_for"), "archetype sensing profile is read")
	_check(source.contains("_can_sense_player"), "cone/hearing perception gate exists")
	_check(source.contains("_leash_radius"), "anchor leash exists")
	_check(source.contains("_returning") and source.contains("_idle_movement"),
		"leash return and idle wander exist")
	print("ENEMY AGGRO CONTRACT PASSED" if failures.is_empty() else "FAILURES: ", failures)
	quit(1 if not failures.is_empty() else 0)

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
