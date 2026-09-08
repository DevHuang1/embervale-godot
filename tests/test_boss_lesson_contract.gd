extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/entities/boss_hushling_matriarch.gd")
	for stage in ["introduce", "test", "combine", "mastery_payoff"]:
		if not source.contains('"%s"' % stage):
			push_error("Matriarch lesson is missing stage: %s" % stage)
			quit(1)
			return
	var base_source := FileAccess.get_file_as_string("res://scripts/entities/boss_base.gd")
	if not base_source.contains("func boss_lesson()") \
			or not base_source.contains("LESSON") \
			or not base_source.contains("LESSON ·"):
		push_error("Boss runtime lesson guidance is not wired")
		quit(1)
		return
	print("ALL BOSS LESSON CONTRACT TESTS PASSED")
	quit(0)
