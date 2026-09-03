extends Node
class_name DayNightCycle

## === DayNightCycle — Atmospheric Time-of-Day Controller ===
## Drives WorldEnvironment (fog, sky, ambient) through a 24-hour cycle.
## A "realm bias" layer is applied on top to retheme the atmosphere
## per quest stage / realm without interrupting the time progression.
##
## Integration with world_manager.gd:
##   day_night = DayNightCycle.new()
##   day_night.name = "DayNightCycle"
##   day_night.start_time = starting_time_of_day
##   add_child(day_night)
##
## Then apply_realm(mist_tint, firefly_tint, grade) is called by
## world_manager._apply_realm_theme() on stage change.
##
## time_of_day: 0.0 = midnight, 0.25 = dawn, 0.5 = noon, 0.75 = dusk, 1.0 = midnight

signal hour_changed(hour: int)
signal dawn
signal dusk

@export var day_duration_seconds : float = 600.0   # 10 min real-time = 1 in-game day
@export var start_time           : float = 0.25    # 0.25 = dawn
@export var time_scale           : float = 1.0     # 0 = paused, >1 = fast

var time_of_day : float = 0.25
var _hour       : int   = 6
var _env        : Environment = null
var _fireflies  : GPUParticles3D = null

# Realm bias (set by apply_realm)
var _mist_tint    : Color = Color(0.65, 0.75, 0.72)
var _firefly_tint : Color = Color(1.00, 0.86, 0.45)
var _grade        : Dictionary = {}

# Keyframe curves: [time, value] pairs
const SKY_TOP_CURVE := [
	[0.00, Color(0.02, 0.04, 0.10)],  # midnight
	[0.22, Color(0.05, 0.08, 0.18)],  # pre-dawn
	[0.28, Color(0.22, 0.28, 0.42)],  # dawn sky
	[0.50, Color(0.10, 0.16, 0.34)],  # noon (forest canopy)
	[0.72, Color(0.18, 0.12, 0.22)],  # dusk
	[0.78, Color(0.04, 0.06, 0.14)],  # post-dusk
	[1.00, Color(0.02, 0.04, 0.10)],  # midnight
]
const AMBIENT_CURVE := [
	[0.00, 0.10], [0.22, 0.18], [0.28, 0.55], [0.50, 0.80],
	[0.72, 0.45], [0.78, 0.20], [1.00, 0.10],
]
const FOG_DENSITY_CURVE := [
	[0.00, 0.022], [0.25, 0.016], [0.50, 0.006], [0.75, 0.014], [1.00, 0.022],
]

func _ready() -> void:
	time_of_day = start_time
	_hour       = int(time_of_day * 24.0)
	_discover_env()

func _process(delta: float) -> void:
	if day_duration_seconds <= 0.0:
		return
	var prev_time := time_of_day
	time_of_day = fmod(time_of_day + delta * time_scale / day_duration_seconds, 1.0)

	# Hour tracking + dawn/dusk signals
	var new_hour := int(time_of_day * 24.0)
	if new_hour != _hour:
		_hour = new_hour
		hour_changed.emit(_hour)
		if _hour == 6:
			dawn.emit()
		elif _hour == 18:
			dusk.emit()

	_apply_tod()

func _discover_env() -> void:
	var scene := get_tree().current_scene if get_tree() else null
	if scene == null:
		return
	var env_node := scene.get_node_or_null("Environment") as WorldEnvironment
	if env_node == null:
		env_node = scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if env_node != null:
		_env = env_node.environment
	# Find fireflies GPUParticles3D
	_fireflies = scene.get_node_or_null("Fireflies") as GPUParticles3D

# ─────────────────────────────────────────────────────────────────────────────
# Apply time-of-day
# ─────────────────────────────────────────────────────────────────────────────

func _apply_tod() -> void:
	if _env == null:
		_discover_env()
	if _env == null:
		return

	var sky_top   := _sample_color(SKY_TOP_CURVE, time_of_day)
	var ambient   := _sample_float(AMBIENT_CURVE, time_of_day)
	var fog_dens  := _sample_float(FOG_DENSITY_CURVE, time_of_day)

	# Blend with realm bias
	sky_top = sky_top.lerp(_mist_tint * 0.35, 0.22)

	_env.ambient_light_energy = ambient
	_env.fog_density          = fog_dens * (1.0 + _grade.get("temperature", 0.0) * 0.2)

	if _env.sky != null and _env.sky.sky_material is ProceduralSkyMaterial:
		var sky := _env.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color     = sky_top
		sky.sky_horizon_color = sky_top.lerp(_mist_tint, 0.55)

	# Night factor: dim fireflies at noon, bright at night
	var night := 1.0 - clampf(sin(time_of_day * TAU) + 0.2, 0.0, 1.0)
	if _fireflies != null and is_instance_valid(_fireflies):
		_fireflies.emitting = night > 0.3
		if _fireflies.process_material is ParticleProcessMaterial:
			(_fireflies.process_material as ParticleProcessMaterial).color = \
				_firefly_tint.lerp(Color(0, 0, 0, 0), 1.0 - night)

# ─────────────────────────────────────────────────────────────────────────────
# Realm bias (called by world_manager._apply_realm_theme)
# ─────────────────────────────────────────────────────────────────────────────

func apply_realm(mist_tint: Color, firefly_tint: Color, grade: Dictionary) -> void:
	_mist_tint    = mist_tint
	_firefly_tint = firefly_tint
	_grade        = grade if grade is Dictionary else {}
	_apply_tod()

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _sample_color(curve: Array, t: float) -> Color:
	if curve.is_empty():
		return Color.WHITE
	for i in range(curve.size() - 1):
		var t0 : float = curve[i][0]
		var t1 : float = curve[i + 1][0]
		if t >= t0 and t <= t1:
			var f := (t - t0) / maxf(t1 - t0, 0.0001)
			return (curve[i][1] as Color).lerp(curve[i + 1][1] as Color, f)
	return curve[-1][1] as Color

func _sample_float(curve: Array, t: float) -> float:
	if curve.is_empty():
		return 1.0
	for i in range(curve.size() - 1):
		var t0 : float = curve[i][0]
		var t1 : float = curve[i + 1][0]
		if t >= t0 and t <= t1:
			var f := (t - t0) / maxf(t1 - t0, 0.0001)
			return lerpf(float(curve[i][1]), float(curve[i + 1][1]), f)
	return float(curve[-1][1])

func get_night_factor() -> float:
	return 1.0 - clampf(sin(time_of_day * TAU) + 0.2, 0.0, 1.0)

func get_hour() -> int:
	return _hour

func is_night() -> bool:
	return get_night_factor() > 0.5
