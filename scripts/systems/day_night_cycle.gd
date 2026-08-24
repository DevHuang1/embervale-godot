extends Node3D
class_name DayNightCycle

## === Day/Night Cycle ===
## Continuous ~6-minute cycle driving sun/moon arc, sky, fog, ambient and
## warm-light/firefly crossfades. Quest stages bias the cycle (never replace
## it): WorldManager's current_grove_state is read directly each frame.
## Owns the runtime Environment copy so exactly one node mutates it.

@export var day_length_seconds: float = 900.0
@export var start_time: float = 0.78  # night-ish start preserves first-impression mood
@export var time_scale_debug: float = 1.0

## time_of_day: 0=dawn, 0.25=noon, 0.5=dusk, 0.75=midnight (wraps)
var time_of_day: float = 0.78

# Scene nodes resolved generically by name so Grove and Moonfen both work
var _env_node: WorldEnvironment
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _warm_lights: Node3D
var _fireflies: GPUParticles3D
var _mist: GPUParticles3D

var _warm_base_energy := {}
var _firefly_proc: ParticleProcessMaterial
var _mist_proc: ParticleProcessMaterial
var _mist_base_color := Color(0.65, 0.75, 0.72, 0.08)

# Keyframe ramps evaluated at the (biased) time of day
var _light_color: Gradient
var _light_energy: Gradient
var _sky_top: Gradient
var _sky_horizon: Gradient
var _ground_horizon: Gradient
var _ambient_color: Gradient
var _ambient_energy: Gradient
var _fog_color: Gradient
var _fog_density: Gradient
var _vol_fog_density: Gradient
var _vol_fog_emission: Gradient
var _bg_energy: Gradient

# Quest-stage bias applied AFTER the cycle computes base values.
# Keys are GameState.QuestStage values; stage grading survives as this layer.
const STAGE_BIAS := {
	0: {"energy_mult": 1.00, "fog_add": 0.0000, "time_shift": 0.000},
	1: {"energy_mult": 0.93, "fog_add": 0.0015, "time_shift": 0.030},
	2: {"energy_mult": 0.95, "fog_add": 0.0010, "time_shift": 0.020},
	3: {"energy_mult": 0.88, "fog_add": 0.0040, "time_shift": 0.070},
}

func _ready() -> void:
	time_of_day = wrapf(start_time, 0.0, 1.0)
	var parent := get_parent()
	_env_node = parent.get_node_or_null("Environment") as WorldEnvironment
	_sun = parent.get_node_or_null("SunLight") as DirectionalLight3D
	if _sun == null:
		_sun = parent.get_node_or_null("MoonLight") as DirectionalLight3D
	_warm_lights = parent.get_node_or_null("WarmLights")
	_fireflies = parent.get_node_or_null("Fireflies") as GPUParticles3D
	_mist = parent.get_node_or_null("MistParticles") as GPUParticles3D
	_own_environment()
	_cache_scene_state()
	_build_gradients()

func _own_environment() -> void:
	if _env_node == null or _env_node.environment == null:
		return
	_env = _env_node.environment.duplicate()
	_env_node.environment = _env
	var sky: Sky = _env.sky as Sky
	if sky != null:
		sky = sky.duplicate() as Sky
		if sky.sky_material is ProceduralSkyMaterial:
			_sky_mat = sky.sky_material.duplicate() as ProceduralSkyMaterial
			sky.sky_material = _sky_mat
		_env.sky = sky

func _cache_scene_state() -> void:
	if _warm_lights:
		for light in _warm_lights.get_children():
			if light is OmniLight3D:
				_warm_base_energy[light.get_instance_id()] = light.light_energy
	if _fireflies and _fireflies.process_material is ParticleProcessMaterial:
		_firefly_proc = _fireflies.process_material.duplicate()
		_fireflies.process_material = _firefly_proc
	if _mist and _mist.process_material is ParticleProcessMaterial:
		_mist_proc = _mist.process_material.duplicate()
		_mist.process_material = _mist_proc
		_mist_base_color = _mist_proc.color

static func _grad(points: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for p in points:
		offs.append(p[0])
		cols.append(p[1])
	g.offsets = offs
	g.colors = cols
	return g

func _build_gradients() -> void:
	# Sun/moon light: warm dawn -> neutral noon -> amber dusk -> blue moon night
	_light_color = _grad([
		[0.00, Color(1.00, 0.62, 0.38)], [0.08, Color(1.00, 0.86, 0.66)],
		[0.25, Color(0.99, 0.97, 0.92)], [0.42, Color(1.00, 0.80, 0.55)],
		[0.50, Color(0.90, 0.48, 0.28)], [0.58, Color(0.52, 0.60, 0.86)],
		[0.75, Color(0.72, 0.80, 0.96)], [0.94, Color(0.50, 0.56, 0.85)],
		[1.00, Color(1.00, 0.62, 0.38)]])
	_light_energy = _grad([
		[0.00, Color(0.85, 0, 0)], [0.10, Color(1.20, 0, 0)],
		[0.25, Color(1.45, 0, 0)], [0.44, Color(1.15, 0, 0)],
		[0.50, Color(0.70, 0, 0)], [0.60, Color(1.05, 0, 0)],
		[0.75, Color(1.35, 0, 0)], [0.96, Color(0.75, 0, 0)],
		[1.00, Color(0.85, 0, 0)]])
	_sky_top = _grad([
		[0.00, Color(0.18, 0.16, 0.24)], [0.12, Color(0.16, 0.26, 0.38)],
		[0.25, Color(0.20, 0.34, 0.46)], [0.46, Color(0.14, 0.18, 0.30)],
		[0.53, Color(0.08, 0.08, 0.17)], [0.75, Color(0.043, 0.094, 0.13)],
		[0.94, Color(0.05, 0.07, 0.13)], [1.00, Color(0.18, 0.16, 0.24)]])
	_sky_horizon = _grad([
		[0.00, Color(0.55, 0.36, 0.26)], [0.12, Color(0.40, 0.42, 0.42)],
		[0.25, Color(0.44, 0.52, 0.52)], [0.47, Color(0.36, 0.26, 0.24)],
		[0.53, Color(0.30, 0.17, 0.13)], [0.75, Color(0.11, 0.17, 0.19)],
		[0.94, Color(0.09, 0.11, 0.15)], [1.00, Color(0.55, 0.36, 0.26)]])
	_ground_horizon = _grad([
		[0.00, Color(0.34, 0.22, 0.17)], [0.25, Color(0.28, 0.33, 0.31)],
		[0.53, Color(0.16, 0.10, 0.09)], [0.75, Color(0.09, 0.14, 0.14)],
		[1.00, Color(0.34, 0.22, 0.17)]])
	_ambient_color = _grad([
		[0.00, Color(0.50, 0.42, 0.38)], [0.25, Color(0.55, 0.58, 0.55)],
		[0.50, Color(0.45, 0.36, 0.33)], [0.75, Color(0.44, 0.47, 0.43)],
		[1.00, Color(0.50, 0.42, 0.38)]])
	_ambient_energy = _grad([
		[0.00, Color(1.00, 0, 0)], [0.25, Color(1.15, 0, 0)],
		[0.50, Color(0.95, 0, 0)], [0.75, Color(1.05, 0, 0)],
		[1.00, Color(1.00, 0, 0)]])
	_fog_color = _grad([
		[0.00, Color(0.30, 0.22, 0.18)], [0.25, Color(0.20, 0.26, 0.26)],
		[0.50, Color(0.25, 0.15, 0.12)], [0.75, Color(0.12, 0.16, 0.17)],
		[1.00, Color(0.30, 0.22, 0.18)]])
	_fog_density = _grad([
		[0.00, Color(0.0075, 0, 0)], [0.25, Color(0.0042, 0, 0)],
		[0.50, Color(0.0072, 0, 0)], [0.75, Color(0.0060, 0, 0)],
		[1.00, Color(0.0075, 0, 0)]])
	_vol_fog_density = _grad([
		[0.00, Color(0.020, 0, 0)], [0.25, Color(0.006, 0, 0)],
		[0.50, Color(0.019, 0, 0)], [0.75, Color(0.011, 0, 0)],
		[1.00, Color(0.020, 0, 0)]])
	_vol_fog_emission = _grad([
		[0.00, Color(0.06, 0.05, 0.04)], [0.25, Color(0.05, 0.07, 0.06)],
		[0.50, Color(0.06, 0.04, 0.03)], [0.75, Color(0.04, 0.08, 0.07)],
		[1.00, Color(0.06, 0.05, 0.04)]])
	_bg_energy = _grad([
		[0.00, Color(0.88, 0, 0)], [0.25, Color(1.00, 0, 0)],
		[0.50, Color(0.82, 0, 0)], [0.75, Color(0.80, 0, 0)],
		[1.00, Color(0.88, 0, 0)]])

func is_daylight() -> bool:
	var t := effective_time_of_day()
	return t >= 0.08 and t < 0.50

func effective_time_of_day() -> float:
	var shift := 0.0
	var wm := get_parent() as WorldManager
	if wm != null:
		var bias: Dictionary = STAGE_BIAS.get(int(wm.current_grove_state), {})
		shift = float(bias.get("time_shift", 0.0))
	return fposmod(time_of_day + shift, 1.0)

func _process(delta: float) -> void:
	time_of_day = fposmod(
		time_of_day + delta * time_scale_debug / maxf(day_length_seconds, 0.001), 1.0)
	if _env == null:
		return
	_apply()

func _apply() -> void:
	var t := effective_time_of_day()
	var bias := {}
	var wm := get_parent() as WorldManager
	if wm != null:
		bias = STAGE_BIAS.get(int(wm.current_grove_state), STAGE_BIAS[0])
	var energy_mult := float(bias.get("energy_mult", 1.0))
	var fog_add := float(bias.get("fog_add", 0.0))

	var nf := _night_factor(t)

	# --- Sun/moon light ---
	if _sun:
		_sun.light_color = _light_color.sample(t)
		_sun.light_energy = _light_energy.sample(t).r * energy_mult
		var elev: float
		if t < 0.5:
			elev = lerpf(7.0, 64.0, sin((t / 0.5) * PI))
		else:
			elev = lerpf(9.0, 46.0, sin(((t - 0.5) / 0.5) * PI))
		var az := -60.0 + t * 180.0  # slow azimuth drift across the full cycle
		_sun.global_transform.basis = \
			Basis(Vector3.UP, deg_to_rad(az)) * Basis(Vector3.RIGHT, deg_to_rad(-elev))

	# --- Sky ---
	if _sky_mat:
		_sky_mat.sky_top_color = _sky_top.sample(t)
		_sky_mat.sky_horizon_color = _sky_horizon.sample(t)
		_sky_mat.ground_horizon_color = _ground_horizon.sample(t)
		_env.background_energy_multiplier = _bg_energy.sample(t).r \
			* lerpf(1.0, energy_mult, 0.6)

	# --- Ambient / fog ---
	_env.ambient_light_color = _ambient_color.sample(t)
	_env.ambient_light_energy = _ambient_energy.sample(t).r * energy_mult
	_env.fog_light_color = _fog_color.sample(t)
	_env.fog_density = _fog_density.sample(t).r + fog_add
	_env.volumetric_fog_density = _vol_fog_density.sample(t).r + fog_add * 0.5
	_env.volumetric_fog_emission = _vol_fog_emission.sample(t)

	# --- Night factor drives warm lights + fireflies/mist ---
	if not _warm_base_energy.is_empty() and _warm_lights:
		var warm_mult := lerpf(0.55, 1.25, nf)
		for light in _warm_lights.get_children():
			if light is OmniLight3D and _warm_base_energy.has(light.get_instance_id()):
				light.light_energy = _warm_base_energy[light.get_instance_id()] * warm_mult
	if _fireflies:
		_fireflies.amount_ratio = lerpf(0.06, 1.0, nf)
	if _mist and _mist_proc:
		_mist_proc.color = Color(_mist_base_color.r, _mist_base_color.g,
			_mist_base_color.b, lerpf(_mist_base_color.a * 0.7, _mist_base_color.a, nf))

func _night_factor(t: float) -> float:
	var up := smoothstep(0.46, 0.55, t)
	var down := smoothstep(0.93, 1.0, t)
	return clampf(up - down, 0.0, 1.0)

## Realm theming: shifts the cached particle bases so the per-frame
## night crossfade keeps working on the new palette (Bramblewood gold,
## Mistfen blue, Heartwood ember).
func apply_realm(mist_color: Color, firefly_color: Color) -> void:
	if _mist_proc:
		_mist_base_color = Color(mist_color.r, mist_color.g, mist_color.b,
			_mist_base_color.a)
	if _firefly_proc:
		var c := _firefly_proc.color
		_firefly_proc.color = Color(firefly_color.r, firefly_color.g,
			firefly_color.b, c.a)
		var ramp := _firefly_proc.color_ramp as GradientTexture1D
		if ramp and ramp.gradient and ramp.gradient.colors.size() >= 2:
			ramp.gradient.set_color(0, Color(firefly_color.r, firefly_color.g,
				firefly_color.b, ramp.gradient.colors[0].a))
			ramp.gradient.set_color(1, Color(firefly_color.r * 0.85,
				firefly_color.g * 0.9, firefly_color.b, 0.0))
