extends SceneTree

func _init() -> void:
	var sampler := preload("res://scripts/systems/android_profile_telemetry.gd").new()
	root.add_child(sampler)
	var sample: Dictionary = sampler.snapshot()
	for key in ["fps", "frame_time_ms", "memory_mb", "draw_calls", "particles", "lights", "audio_voices", "loading_spike_ms"]:
		if not sample.has(key):
			push_error("Telemetry sample missing %s" % key)
			quit(1)
			return
	if float(sample.get("frame_time_ms", 0.0)) <= 0.0 or sampler.max_samples <= 0:
		push_error("Telemetry sample has invalid bounds")
		quit(1)
		return
	print("ANDROID PROFILE TELEMETRY PASSED")
	quit(0)
