extends SceneTree

func _init() -> void:
	var sampler := preload("res://scripts/systems/android_profile_telemetry.gd").new()
	root.add_child(sampler)
	sampler.samples = [{"fps": 60.0, "frame_time_ms": 16.6, "memory_mb": 10.0,
		"draw_calls": 4, "particles": 8, "lights": 2, "audio_voices": 1,
		"loading_spike_ms": 20.0}]
	var report: Dictionary = sampler.build_report()
	var fps_summary: Dictionary = report.get("summary", {}).get("fps", {})
	if int(report.get("sample_count", 0)) != 1 or float(fps_summary.get("avg", 0.0)) != 60.0:
		push_error("Android profile report aggregation is invalid")
		quit(1)
		return
	print("ANDROID PROFILE REPORT PASSED")
	quit(0)
