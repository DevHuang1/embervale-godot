extends SceneTree

func _init() -> void:
	var tracker := preload("res://scripts/systems/golden_route_tracker.gd").new()
	tracker.start_route()
	if not tracker.record_signal(" lantern_path "):
		push_error("Active route rejected a valid signal")
		quit(1)
		return
	var partial: Dictionary = tracker.route_report()
	if bool(partial.get("complete", true)) or not str(partial.get("missing_signals", [])[0]).contains("welcome_arch"):
		push_error("Partial route report did not identify missing signals")
		quit(1)
		return
	for beat in tracker.ROUTE.BEATS:
		for required in beat.get("required_signals", []):
			tracker.record_signal(str(required))
	var complete: Dictionary = tracker.route_report()
	if not bool(complete.get("complete", false)) or complete.get("missing_signals", []).size() != 0:
		push_error("Complete route report still has missing signals")
		quit(1)
		return
	tracker.stop_route()
	if tracker.record_signal("ignored_after_stop"):
		push_error("Stopped route accepted a signal")
		quit(1)
		return
	print("GOLDEN ROUTE TRACKER SIGNALS PASSED")
	quit(0)
