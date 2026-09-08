extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/boss_lesson_catalog.gd")
	var errors: Array[String] = catalog.validate()
	if not errors.is_empty() or catalog.LESSON.size() != 4:
		push_error("Boss lesson catalog is incomplete: %s" % "; ".join(errors))
		quit(1)
		return
	var boss_source := FileAccess.get_file_as_string("res://scripts/entities/boss_hushling_matriarch.gd")
	for entry in catalog.LESSON:
		if not boss_source.contains('"%s"' % str(entry.get("stage", ""))):
			push_error("Boss implementation is missing lesson stage: %s" % entry.get("stage", ""))
			quit(1)
			return
	print("BOSS LESSON CATALOG PASSED")
	quit(0)
