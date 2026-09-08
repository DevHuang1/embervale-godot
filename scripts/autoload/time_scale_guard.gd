extends Node

## === Central time-scale safety guard ===
## Global Engine.time_scale feedback is permanently disabled. Camera shake,
## FOV, and impact presentation remain available, but combat feedback must
## never slow the simulation clock: a leaked lease or platform-detection
## mismatch otherwise makes the whole mobile world run in slow motion.

var _leases: Dictionary = {}
var _now_override_msec: int = -1   # test hook; -1 = real wall clock

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0

func _now() -> int:
	if _now_override_msec >= 0:
		return _now_override_msec
	return Time.get_ticks_msec()

## Compatibility entry point for legacy impact callers.
##
## Global time scaling is intentionally disabled. `scale` and `wall_seconds`
## remain in the signature so older callers stay source-compatible, but no
## caller can create a simulation slowdown or a lingering lease.
func slow_motion(key: String, scale: float, wall_seconds: float) -> void:
	if key.is_empty():
		return
	# Keep this public API backward-compatible for existing combat callers,
	# while making the unsafe behavior impossible on every export target.
	_leases.erase(key)
	Engine.time_scale = 1.0

## Cancel a lease early (e.g. cinematic interrupted before its timer).
func cancel(key: String) -> void:
	_leases.erase(key)

func active_leases() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in _leases:
		var lease: Dictionary = _leases[key]
		result.append({"key": str(key), "scale": float(lease.scale),
			"remaining_ms": maxi(int(lease.expires_msec) - _now(), 0)})
	return result

func cancel_owner_leases(owner_id: String) -> void:
	# Owners use a stable prefix, e.g. "skill:". This keeps the public API
	# useful without coupling the guard to gameplay nodes.
	for key in _leases.keys():
		if str(key).begins_with(owner_id):
			_leases.erase(key)

func is_slowed() -> bool:
	return Engine.time_scale < 0.99

func _process(_delta: float) -> void:
	if not _leases.is_empty():
		_leases.clear()
	Engine.time_scale = 1.0
