extends SceneTree

func _init() -> void:
	var route := preload("res://scripts/systems/android_profile_route.gd")
	var errors: Array[String] = route.validate()
	var required_metrics: Array[String] = ["fps", "frame_time_ms", "memory_mb",
		"draw_calls", "particles", "lights", "audio_voices", "time_scale",
		"script_time_ms", "physics_time_ms", "render_time_ms", "loading_spike_ms"]
	for metric in required_metrics:
		if not route.METRICS.has(metric):
			errors.append("Missing Android profile metric: %s" % metric)
	if not errors.is_empty() or route.CHECKPOINTS.size() != 8:
		push_error("Android profile route is incomplete: %s" % "; ".join(errors))
		quit(1)
		return
	var world_source := FileAccess.get_file_as_string("res://scripts/systems/world_manager.gd")
	if not world_source.contains("AndroidProfileTelemetry") \
			or not world_source.contains("get_android_profile_snapshot") \
			or not world_source.contains("save_android_profile_report") \
			or not world_source.contains("record_golden_route_signal") \
			or not world_source.contains("get_golden_route_report"):
		push_error("WorldManager does not expose runtime profile telemetry")
		quit(1)
		return
	print("ANDROID PROFILE ROUTE PASSED")
	quit(0)
