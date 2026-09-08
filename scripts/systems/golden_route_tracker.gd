extends Node
class_name GoldenRouteTracker

const ROUTE = preload("res://scripts/systems/golden_route_catalog.gd")
const MAX_ROUTE_SECONDS: float = 1800.0
const MAX_SIGNAL_EVENTS: int = 128

signal beat_changed(beat_id: String, beat: Dictionary)
signal route_finished()

var active: bool = false
var elapsed_seconds: float = 0.0
var current_index: int = -1
var signal_events: Array[Dictionary] = []

func _process(delta: float) -> void:
	if active:
		advance(delta)

func start_route() -> void:
	elapsed_seconds = 0.0
	current_index = -1
	signal_events.clear()
	active = true
	advance(0.0)

func stop_route() -> void:
	active = false

func advance(delta: float) -> void:
	if not active:
		return
	elapsed_seconds = clampf(elapsed_seconds + maxf(delta, 0.0), 0.0, MAX_ROUTE_SECONDS)
	var next_index := _index_for_time(elapsed_seconds)
	if next_index != current_index and next_index >= 0:
		current_index = next_index
		var beat: Dictionary = ROUTE.BEATS[current_index].duplicate(true)
		beat_changed.emit(str(beat.get("id", "")), beat)
		_record_activity(str(beat.get("id", "")))
	if elapsed_seconds >= MAX_ROUTE_SECONDS:
		active = false
		route_finished.emit()

func current_beat() -> Dictionary:
	if current_index < 0 or current_index >= ROUTE.BEATS.size():
		return {}
	return ROUTE.BEATS[current_index].duplicate(true)

func snapshot() -> Dictionary:
	return {
		"active": active,
		"elapsed_seconds": elapsed_seconds,
		"current_index": current_index,
		"beat": current_beat(),
		"signal_events": signal_events.duplicate(true),
	}

func record_signal(signal_id: String) -> bool:
	var normalized := signal_id.strip_edges().to_lower()
	if normalized.is_empty() or not active:
		return false
	if signal_events.size() >= MAX_SIGNAL_EVENTS:
		signal_events.pop_front()
	signal_events.append({"id": normalized, "elapsed_seconds": elapsed_seconds})
	return true

func route_report() -> Dictionary:
	var seen: Dictionary = {}
	for event in signal_events:
		seen[str(event.get("id", ""))] = true
	var beats: Array[Dictionary] = []
	var missing_total: Array[String] = []
	for beat in ROUTE.BEATS:
		var missing: Array[String] = []
		for required in beat.get("required_signals", []):
			if not seen.has(str(required)):
				missing.append(str(required))
		if not missing.is_empty():
			missing_total.append_array(missing)
		beats.append({"id": str(beat.get("id", "")), "missing_signals": missing})
	return {"complete": missing_total.is_empty(), "beats": beats, "missing_signals": missing_total, "signal_count": signal_events.size()}

func _index_for_time(time_seconds: float) -> int:
	for index in ROUTE.BEATS.size():
		var beat: Dictionary = ROUTE.BEATS[index]
		if time_seconds < float(beat.get("end_sec", 0)) or index == ROUTE.BEATS.size() - 1:
			return index
	return -1

func _record_activity(beat_id: String) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree.root == null:
		return
	var state := tree.root.get_node_or_null("GameState")
	if state != null:
		if state.has_method("record_activity"):
			state.record_activity("ROUTE BEAT · %s" % beat_id)
