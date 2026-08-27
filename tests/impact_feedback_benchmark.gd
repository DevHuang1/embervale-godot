extends Node

## Automated benchmark for the native tiered ImpactDirector + CameraRig path.
## It measures wall-clock dispatch cost, one physics-frame cost, p95/max spikes,
## hit-stop behavior, and the final camera amplitude under simultaneous requests.

const SAMPLE_COUNT := 12
const FRAME_BUDGET_MS := 16.67
const GLOBAL_CAP := 0.65
const ACTOR_COUNTS := [1, 4, 8, 16, 32, 64]
const TIERS := ["medium", "heavy", "major"]
const ENVIRONMENTS := [
	{"name": "Grove", "scene": "res://scenes/world/grove.tscn"},
	{"name": "Moonfen", "scene": "res://scenes/world/moonfen.tscn"},
]

var _records: Array[Dictionary] = []
var _failures: Array[String] = []

func _ready() -> void:
	Engine.time_scale = 1.0
	print("=== Embervale Impact Feedback Performance Benchmark ===")
	print("samples=", SAMPLE_COUNT, " frame_budget_ms=", FRAME_BUDGET_MS,
		" actor_counts=", ACTOR_COUNTS)
	for environment in ENVIRONMENTS:
		await _benchmark_environment(environment)
	_write_report()
	Engine.time_scale = 1.0
	print("BENCHMARK_RESULT=", "PASS" if _failures.is_empty() else "FAIL")
	if not _failures.is_empty():
		for failure in _failures:
			print("FAILURE: ", failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)

func _benchmark_environment(environment: Dictionary) -> void:
	var label := str(environment.name)
	var packed := load(str(environment.scene)) as PackedScene
	if packed == null:
		_failures.append(label + " scene failed to load")
		return
	var world := packed.instantiate()
	add_child(world)
	get_tree().set_current_scene(world)
	await _wait_physics_frames(6)
	var hero := world.get_node_or_null("Hero") as Node3D
	var camera := world.get_node_or_null("CameraRig")
	if hero == null or camera == null:
		_failures.append(label + " missing Hero or CameraRig")
		get_tree().set_current_scene(self)
		world.queue_free()
		await _wait_physics_frames(2)
		return

	var baseline := await _measure_baseline(camera)
	print("-- ", label, " baseline frame_p95_ms=", snapped(baseline.frame_p95, 0.001),
		" dispatch_p95_ms=", snapped(baseline.dispatch_p95, 0.001), " --")

	for tier in TIERS:
		for actor_count in ACTOR_COUNTS:
			var record := await _measure_case(label, hero, camera, tier, actor_count, baseline)
			_records.append(record)
			_print_case(record)

	get_tree().set_current_scene(self)
	world.queue_free()
	await _wait_physics_frames(3)
	Engine.time_scale = 1.0

func _measure_baseline(camera: Node) -> Dictionary:
	var dispatch_samples: Array[float] = []
	var frame_samples: Array[float] = []
	for _sample in SAMPLE_COUNT:
		Engine.time_scale = 1.0
		if camera.has_method("reset_shake"):
			camera.reset_shake()
		var dispatch_start := Time.get_ticks_usec()
		var dispatch_ms := float(Time.get_ticks_usec() - dispatch_start) / 1000.0
		var frame_start := Time.get_ticks_usec()
		await get_tree().physics_frame
		var frame_ms := float(Time.get_ticks_usec() - frame_start) / 1000.0
		dispatch_samples.append(dispatch_ms)
		frame_samples.append(frame_ms)
	return {
		"dispatch_p95": _percentile(dispatch_samples, 0.95),
		"frame_p95": _percentile(frame_samples, 0.95),
		"frame_max": _max_value(frame_samples),
	}

func _measure_case(label: String, hero: Node3D, camera: Node,
		tier: String, actor_count: int, baseline: Dictionary) -> Dictionary:
	Engine.time_scale = 1.0
	if camera.has_method("reset_shake"):
		camera.reset_shake()
	await get_tree().physics_frame
	var dispatch_samples: Array[float] = []
	var frame_samples: Array[float] = []
	var amplitude_peaks: Array[float] = []
	var time_scale_samples: Array[float] = []
	var direction := Vector3(0.0, 0.0, -1.0)

	for _sample in SAMPLE_COUNT:
		Engine.time_scale = 1.0
		if camera.has_method("reset_shake"):
			camera.reset_shake()
		var dispatch_start := Time.get_ticks_usec()
		for actor_index in actor_count:
			var request_tier := tier
			if tier == "major" and actor_index % 4 == 0:
				request_tier = "heavy"
			# Benchmark the feedback core directly to isolate CameraRig merging
			# and hit-stop bookkeeping from pooled VFX/audio allocation costs.
			if camera.has_method("request_feedback"):
				camera.request_feedback(request_tier, direction)
			else:
				ImpactDirector.apply_feedback(hero, request_tier, Vector3.ZERO, direction)
		var dispatch_ms := float(Time.get_ticks_usec() - dispatch_start) / 1000.0
		var frame_start := Time.get_ticks_usec()
		await get_tree().physics_frame
		var frame_ms := float(Time.get_ticks_usec() - frame_start) / 1000.0
		var shake_value = camera.get("current_shake")
		var amplitude: float = shake_value.length() if shake_value is Vector3 else 0.0
		dispatch_samples.append(dispatch_ms)
		frame_samples.append(frame_ms)
		amplitude_peaks.append(amplitude)
		time_scale_samples.append(float(Engine.time_scale))

	var frame_p95 := _percentile(frame_samples, 0.95)
	var dispatch_p95 := _percentile(dispatch_samples, 0.95)
	var frame_max := _max_value(frame_samples)
	var dispatch_max := _max_value(dispatch_samples)
	var baseline_frame := float(baseline.frame_p95)
	var spike_threshold := maxf(FRAME_BUDGET_MS, baseline_frame * 1.5 + 1.0)
	var spike_count := 0
	var budget_exceeded_count := 0
	for value in frame_samples:
		if float(value) > spike_threshold:
			spike_count += 1
		if float(value) > FRAME_BUDGET_MS:
			budget_exceeded_count += 1
	var peak_amplitude := _max_value(amplitude_peaks)
	var cap_ok := peak_amplitude <= GLOBAL_CAP + 0.0001
	if not cap_ok:
		_failures.append("%s %s/%d exceeded amplitude cap: %.4f" %
			[label, tier, actor_count, peak_amplitude])
	return {
		"environment": label,
		"tier": tier,
		"actors": actor_count,
		"samples": SAMPLE_COUNT,
		"baseline_frame_p95_ms": baseline_frame,
		"dispatch_p95_ms": dispatch_p95,
		"dispatch_max_ms": dispatch_max,
		"frame_p95_ms": frame_p95,
		"frame_max_ms": frame_max,
		"spike_threshold_ms": spike_threshold,
		"spike_count": spike_count,
		"frame_budget_exceeded_count": budget_exceeded_count,
		"frame_budget_exceeded_ratio": float(budget_exceeded_count) / float(SAMPLE_COUNT),
		"peak_amplitude": peak_amplitude,
		"cap_ok": cap_ok,
		"min_time_scale": _min_value(time_scale_samples),
		"max_time_scale": _max_value(time_scale_samples),
	}

func _print_case(record: Dictionary) -> void:
	print("  ", record.environment, " tier=", record.tier,
		" actors=", record.actors,
		" dispatch_p95_ms=", snapped(float(record.dispatch_p95_ms), 0.001),
		" frame_p95_ms=", snapped(float(record.frame_p95_ms), 0.001),
		" frame_max_ms=", snapped(float(record.frame_max_ms), 0.001),
		" spikes=", record.spike_count,
		" budget_over=", record.frame_budget_exceeded_count,
		" peak_amp=", snapped(float(record.peak_amplitude), 0.001),
		" cap_ok=", record.cap_ok)

func _percentile(values: Array, percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var index := int(round(float(sorted.size() - 1) * percentile))
	return float(sorted[clampi(index, 0, sorted.size() - 1)])

func _max_value(values: Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, float(value))
	return result

func _min_value(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var result := INF
	for value in values:
		result = minf(result, float(value))
	return result

func _wait_physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame

func _write_report() -> void:
	var report := {
		"sample_count": SAMPLE_COUNT,
		"frame_budget_ms": FRAME_BUDGET_MS,
		"global_amplitude_cap": GLOBAL_CAP,
		"results": _records,
		"failures": _failures,
	}
	var file := FileAccess.open("user://impact_feedback_benchmark.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("REPORT_PATH=user://impact_feedback_benchmark.json")
