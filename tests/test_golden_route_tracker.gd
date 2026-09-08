extends SceneTree

const TRACKER_SCRIPT: Script = preload("res://scripts/systems/golden_route_tracker.gd")

func _init() -> void:
	var tracker: Node = TRACKER_SCRIPT.new()
	root.add_child(tracker)
	var emitted: Array[String] = []
	tracker.beat_changed.connect(func(beat_id: String, _beat: Dictionary) -> void: emitted.append(beat_id))
	tracker.start_route()
	assert(tracker.current_beat().get("id", "") == "grove_arrival")
	assert(emitted == ["grove_arrival"])
	tracker.advance(90.0)
	assert(tracker.current_beat().get("id", "") == "living_clue")
	tracker.advance(2000.0)
	assert(not tracker.active)
	assert(tracker.current_beat().get("id", "") == "unlock_aftermath")
	assert(tracker.current_index == 9)
	tracker.queue_free()
	var world_source := FileAccess.get_file_as_string("res://scripts/systems/world_manager.gd")
	assert(world_source.contains("_start_golden_route_if_needed"))
	assert(world_source.contains("get_activity_recovery().is_empty()"))
	print("GOLDEN ROUTE TRACKER PASSED")
	quit()
