extends Node
class_name AndroidProfileTelemetry

const AndroidProfileRoute := preload("res://scripts/systems/android_profile_route.gd")

## Bounded runtime sampler for the Android profile route. Values describe the
## running renderer; they are evidence only when collected on the target device.
@export_range(1, 120, 1) var max_samples: int = 60
@export var sample_interval: float = 0.5
@export var diagnostics_enabled: bool = false
var samples: Array[Dictionary] = []
var _elapsed: float = 0.0
var route_events: Dictionary = {}
var _last_sample_usec: int = 0
var _last_memory_mb: float = 0.0
var _frame_over_33: int = 0
var _frame_over_100: int = 0
var _frame_over_500: int = 0
var _max_frame_ms: float = 0.0
var _last_frame_ms: float = 0.0
var _frame_history: Array[Dictionary] = []
const FRAME_HISTORY_CAP := 120
var _last_recovery_msec: int = -10000

func reset_route_events() -> void:
	route_events.clear()

func set_diagnostics_enabled(enabled: bool) -> void:
	diagnostics_enabled = enabled
	# The normal game must not pay for the per-frame correlation ring. Enable
	# this explicitly for the physical-device profile route or dev overlay.
	if not diagnostics_enabled:
		_frame_history.clear()

func record_route_event(event_id: String) -> void:
	if event_id.strip_edges().is_empty() or route_events.has(event_id):
		return
	route_events[event_id] = {"timestamp_ms": Time.get_ticks_msec(), "sample_index": samples.size()}

func _process(delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	if _last_sample_usec > 0:
		var frame_ms := float(now_usec - _last_sample_usec) / 1000.0
		_last_frame_ms = frame_ms
		_max_frame_ms = maxf(_max_frame_ms, frame_ms)
		if frame_ms > 33.0: _frame_over_33 += 1
		if frame_ms > 100.0: _frame_over_100 += 1
		if frame_ms > 500.0: _frame_over_500 += 1
		if frame_ms > 100.0 and (OS.has_feature("mobile") \
			or OS.get_name() in ["Android", "iOS"]) \
			and Time.get_ticks_msec() - _last_recovery_msec > 1000:
			_last_recovery_msec = Time.get_ticks_msec()
			record_route_event("stall_recovery_%d" % _last_recovery_msec)
			var skill_executor := get_tree().get_first_node_in_group("skill_executor")
			if skill_executor != null and skill_executor.has_method("cancel_active_effects"):
				skill_executor.cancel_active_effects()
			CombatFx.clear_expired_effects()
			Engine.time_scale = 1.0
		if diagnostics_enabled:
			_record_frame_context(frame_ms)
	_last_sample_usec = now_usec
	_elapsed += maxf(delta, 0.0)
	if _elapsed < sample_interval or samples.size() >= max_samples:
		return
	_elapsed = 0.0
	samples.append(snapshot())

func snapshot() -> Dictionary:
	var fps := float(Performance.get_monitor(Performance.TIME_FPS))
	var memory_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	var scene_tree := Engine.get_main_loop() as SceneTree
	var streamer := scene_tree.get_first_node_in_group("world_chunk_streamer") \
		if scene_tree != null else null
	var stream_report: Dictionary = streamer.performance_report() if streamer != null and streamer.has_method("performance_report") else {}
	var fx_report: Dictionary = CombatFx.performance_report()
	fx_report["active_effects"] = CombatFx.active_effect_counts()
	var memory_delta_mb := memory_mb - _last_memory_mb
	_last_memory_mb = memory_mb
	return {
		"fps": fps,
		"frame_time_ms": _last_frame_ms if _last_frame_ms > 0.0 \
			else 1000.0 / maxf(fps, 0.01),
		"memory_mb": memory_mb,
		"memory_delta_mb": memory_delta_mb,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"particles": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"lights": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"audio_voices": _active_audio_voices(),
		"time_scale": Engine.time_scale,
		"script_time_ms": float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		"physics_time_ms": float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
		# Godot 4.7 exposes process/physics monitors here, but no portable
		# TIME_RENDER monitor. Renderer load remains represented by FPS, frame
		# duration, draw calls, and primitives.
		"render_time_ms": 0.0,
		"streaming": stream_report,
		"fx": fx_report,
		"loading_spike_ms": 0.0,
		"stall": stall_report(),
	}

func stall_report() -> Dictionary:
	return {"max_frame_ms": _max_frame_ms, "over_33ms": _frame_over_33,
		"over_100ms": _frame_over_100, "over_500ms": _frame_over_500,
		"last_frame_ms": _last_frame_ms, "recent_frames": _frame_history.duplicate(true)}

func _record_frame_context(frame_ms: float) -> void:
	if _frame_history.size() >= FRAME_HISTORY_CAP:
		_frame_history.pop_front()
	var tree := get_tree()
	var hero := tree.get_first_node_in_group("player") if tree != null else null
	var skill: Dictionary = hero.skill_performance_report() \
		if hero != null and hero.has_method("skill_performance_report") else {}
	var streamer := tree.get_first_node_in_group("world_chunk_streamer") \
		if tree != null else null
	var streaming: Dictionary = streamer.stall_context_report() \
		if streamer != null and streamer.has_method("stall_context_report") else {}
	_frame_history.append({"timestamp_ms": Time.get_ticks_msec(),
		"frame_ms": frame_ms, "time_scale": Engine.time_scale,
		"skill": skill, "fx": CombatFx.active_effect_counts(),
		"streaming": streaming})

func latest() -> Dictionary:
	return samples.back().duplicate(true) if not samples.is_empty() else snapshot()

func build_report() -> Dictionary:
	var report := {"sample_count": samples.size(), "samples": samples.duplicate(true),
		"route_events": route_events.duplicate(true), "stall": stall_report(), "summary": {}}
	for metric in AndroidProfileRoute.METRICS:
		var values: Array[float] = []
		for sample in samples:
			if sample.has(metric):
				values.append(float(sample[metric]))
		if values.is_empty():
			continue
		var total := 0.0
		for value in values:
			total += value
		report["summary"][metric] = {"min": values.min(), "avg": total / values.size(), "max": values.max()}
	return report

func save_report(path: String = "user://android_profile_report.json") -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(build_report()))
	file.close()
	return true

func _active_audio_voices() -> int:
	if not is_inside_tree():
		return 0
	var tree := get_tree()
	if tree == null or tree.root == null:
		return 0
	var active := 0
	for node in tree.root.find_children("*", "AudioStreamPlayer", true, false):
		if node is AudioStreamPlayer and (node as AudioStreamPlayer).playing:
			active += 1
	return active
