extends RefCounted
class_name AndroidProfileRoute

## Repeatable checkpoint contract for physical Android profiling. It describes
## what to measure; it does not claim emulator or device performance.
const CHECKPOINTS: Array[Dictionary] = [
	{"id": "startup", "action": "cold launch to playable HUD"},
	{"id": "exploration", "action": "walk one streamed realm chunk"},
	{"id": "crowded_combat", "action": "fight a full normal encounter pack"},
	{"id": "boss_phases", "action": "exercise boss telegraph and phase transition"},
	{"id": "inventory", "action": "open, sort, inspect, equip, and close satchel"},
	{"id": "shop", "action": "browse comparison, purchase, and return"},
	{"id": "scan_preview", "action": "open scan camera preview and cancel safely"},
	{"id": "realm_transition", "action": "travel through a realm gate and return"},
]
const METRICS: Array[String] = ["fps", "frame_time_ms", "memory_mb", "draw_calls",
	"particles", "lights", "audio_voices", "time_scale", "script_time_ms",
	"physics_time_ms", "render_time_ms", "loading_spike_ms"]

static func validate() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for checkpoint in CHECKPOINTS:
		var id := str(checkpoint.get("id", ""))
		if id.is_empty() or seen.has(id):
			errors.append("Duplicate or empty Android profile checkpoint: %s" % id)
		seen[id] = true
		if str(checkpoint.get("action", "")).is_empty():
			errors.append("Android profile checkpoint missing action: %s" % id)
	for metric in METRICS:
		if metric.strip_edges().is_empty():
			errors.append("Android profile metric cannot be empty")
	return errors
