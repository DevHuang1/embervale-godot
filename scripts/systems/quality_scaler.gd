class_name QualityScaler
extends Node

## === Adaptive quality ===
## FPS EMA monitor with hysteresis; degrades in a fixed order and restores
## with headroom. Modes: 0=Low (locked), 1=Auto, 2=High (locked).
## Persisted into the shared settings cfg ("quality" section).

signal level_changed(level: int)

enum Mode { LOW, AUTO, HIGH }
enum Level { LOW, MEDIUM, HIGH }

const DEGRADE_FPS := 48.0
const RESTORE_FPS := 58.0
const DEGRADE_SUSTAIN := 2.5
const RESTORE_SUSTAIN := 6.0
const SAMPLE_INTERVAL := 0.5

const SETTINGS_SECTION := "quality"
const SETTINGS_KEY := "mode"

## Overridable for isolated validation; production keeps the shared settings.
var settings_path: String = AudioManager.SETTINGS_PATH

var mode: int = Mode.AUTO
var level: int = Level.HIGH          # applied degradation level (auto-managed)
var particle_scale: float = 1.0      # read by DayNightCycle via WorldState

# --- UE-look feature knobs (per Level.LOW/MEDIUM/HIGH) ---
var debris_max: int = 24             # live RigidBody3D shard cap
var pom_mode: int = 2                # 0 off, 1 parallax offset, 2 POM march
var stochastic_mode: int = 1         # 0 plain tile, 1 hex-tile grass/dirt (v4)
var vegetation_pushers: int = 4      # world_pushers slots published to shaders
var corpse_pool_size: int = 6        # pooled tumble corpses
var contact_shadows: bool = true     # key light contact shadows
var vfx_density: float = 1.0         # particle counts, timing unchanged
var vfx_pool_limit: int = 24         # pooled transparent emitters
var vfx_trail_limit: int = 12        # simultaneous ribbon/core meshes
var transient_light_budget: int = 3  # short-lived impact lights
var distortion_enabled: bool = true  # chroma/rain-smear post effects
var material_detail_level: int = 2   # 0 broad, 1 offset, 2 close POM
var grass_density_scale: float = 1.0 # instanced carpet spacing/count only

var _sample_clock := 0.0
var _low_time := 0.0
var _high_time := 0.0
var _env_cache: Environment = null
var _env_scene: Node = null


func _ready() -> void:
	_load_mode()
	# Boot at the smooth baseline and let AUTO restore detail only when the
	# machine shows clear headroom — smoother-first over razor-sharp.
	_apply_level(int(Level.LOW))


var _qs_scene: Node = null

func _process(delta: float) -> void:
	# Re-apply tier-driven material/env state whenever the active scene
	# changes (covers boot + realm travel, independent of AUTO mode).
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != _qs_scene and scene != null:
		_qs_scene = scene
		_apply_terrain_pom()
		_apply_environment()
	if mode != Mode.AUTO:
		return
	_sample_clock += delta
	if _sample_clock < SAMPLE_INTERVAL:
		return
	_sample_clock = 0.0
	var fps := float(Engine.get_frames_per_second())
	var low := fps > 0.5 and fps < DEGRADE_FPS
	var high := fps >= RESTORE_FPS
	_low_time = _low_time + SAMPLE_INTERVAL if low else 0.0
	_high_time = _high_time + SAMPLE_INTERVAL if high else 0.0
	if _low_time >= DEGRADE_SUSTAIN and level > int(Level.LOW):
		_apply_level(level - 1)
		_low_time = 0.0
	elif _high_time >= RESTORE_SUSTAIN and level < int(Level.HIGH):
		_apply_level(level + 1)
		_high_time = 0.0


## Test hook: simulate an FPS reading through the same hysteresis path.
func feed_fps(fps: float) -> void:
	if mode != Mode.AUTO:
		return
	var low := fps < DEGRADE_FPS
	var high := fps >= RESTORE_FPS
	if low:
		_low_time += DEGRADE_SUSTAIN
		_high_time = 0.0
	elif high:
		_high_time += RESTORE_SUSTAIN
		_low_time = 0.0
	else:
		_low_time = 0.0
		_high_time = 0.0
	if _low_time >= DEGRADE_SUSTAIN and level > int(Level.LOW):
		_apply_level(level - 1)
		_low_time = 0.0
	elif _high_time >= RESTORE_SUSTAIN and level < int(Level.HIGH):
		_apply_level(level + 1)
		_high_time = 0.0


func set_mode(new_mode: int) -> void:
	mode = clampi(new_mode, int(Mode.LOW), int(Mode.HIGH))
	match mode:
		int(Mode.LOW):
			_apply_level(int(Level.LOW))
		int(Mode.HIGH):
			_apply_level(int(Level.HIGH))
		_:
			_apply_level(int(Level.HIGH))
	_save_mode()


func _apply_level(new_level: int) -> void:
	level = clampi(new_level, int(Level.LOW), int(Level.HIGH))
	particle_scale = [0.5, 0.75, 1.0][level]
	debris_max = [6, 12, 24][level]
	pom_mode = [0, 1, 2][level]
	stochastic_mode = [0, 0, 1][level]   # only HIGH pays for 3-tap sampling
	vegetation_pushers = [1, 4, 4][level]
	corpse_pool_size = [2, 4, 6][level]
	contact_shadows = level == int(Level.HIGH)
	vfx_density = [0.45, 0.72, 1.0][level]
	vfx_pool_limit = [10, 16, 24][level]
	vfx_trail_limit = [6, 9, 12][level]
	transient_light_budget = [0, 0, 3][level]
	distortion_enabled = level == int(Level.HIGH)
	material_detail_level = level
	grass_density_scale = [0.65, 0.82, 1.0][level]
	# Trade resolution for smoothness: render at a fraction of the window and
	# bilinearly upscale, so even weak GPUs hold a steadier framerate. The
	# sharper the user wants it, the closer to full res they land.
	if level == int(Level.LOW):
		_set_scaling(0.6)
	elif level == int(Level.MEDIUM):
		_set_scaling(0.75)
	else:
		_set_scaling(1.0)
	_apply_environment()
	_apply_terrain_pom()
	_apply_light_tiers()
	level_changed.emit(level)

## Apply 3D render resolution scaling on the active viewport (safe no-op when
## the viewport is not ready yet, e.g. during autoload boot before a scene).
func _set_scaling(scale_3d: float) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	viewport.scaling_3d_scale = clampf(scale_3d, 0.25, 1.0)
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR


## Key-light tiering (Godot 4 has no contact shadows; omni/spot shadow
## passes are the equivalent mobile cost): only lights that opt in via
## the "contact_shadow" group gain shadows at HIGH; everything else
## stays as authored so decorative fills never turn into blocky shadow
## casters. The directional sun always keeps casting.
const CONTACT_SHADOW_GROUP := "contact_shadow"

func _apply_light_tiers() -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return
	for node in scene.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light == null:
			continue
		if light is DirectionalLight3D:
			light.shadow_blur = 1.2 if contact_shadows else 0.8
		elif light.is_in_group(CONTACT_SHADOW_GROUP):
			light.shadow_enabled = contact_shadows


## Push the active POM tier into every terrain-ground ShaderMaterial in
## the scene. The material resource is shared per realm, so setting the
## `pom_mode` uniform once covers all terrain meshes. Called on level
## change and on scene (re)load so MEDIUM/LOW actually drop to cheaper
## parallax instead of always running the full 8-step march.
func _apply_terrain_pom() -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		_pom_for_material(mi.material_override)
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				_pom_for_material(mi.mesh.surface_get_material(s))


func _pom_for_material(mat) -> void:
	var sm := mat as ShaderMaterial
	if sm == null or sm.shader == null:
		return
	if not str(sm.shader.resource_path).contains("terrain_ground.gdshader"):
		return
	sm.set_shader_parameter("pom_mode", pom_mode)
	sm.set_shader_parameter("stochastic_mode", stochastic_mode)


## Degradation order (cheapest visual win first):
## rain handled by WorldState reading particle_scale -> LOW disables rig;
## SSAO off at MEDIUM; volumetric fog off at LOW.
func _apply_environment() -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != _env_scene:
		_env_cache = null
		_env_scene = scene
	if scene == null:
		return
	var we := scene.get_node_or_null("Environment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	if _env_cache == null:
		_env_cache = we.environment
	match level:
		int(Level.MEDIUM):
			we.environment.ssao_enabled = false
			we.environment.volumetric_fog_enabled = \
				_env_cache.volumetric_fog_enabled if _env_cache != null else true
		int(Level.LOW):
			we.environment.ssao_enabled = false
			we.environment.volumetric_fog_enabled = false
		_:
			if _env_cache != null:
				we.environment.ssao_enabled = _env_cache.ssao_enabled
				we.environment.volumetric_fog_enabled = \
					_env_cache.volumetric_fog_enabled
				# HIGH garnish: a touch more contact occlusion for the
				# UE-style grounded look (Task 9), only when authored on.
				if _env_cache.ssao_enabled:
					we.environment.ssao_intensity = \
						_env_cache.ssao_intensity + 0.2


func _load_mode() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	mode = clampi(int(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, int(Mode.AUTO))),
		int(Mode.LOW), int(Mode.HIGH))


func _save_mode() -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, mode)
	cfg.save(settings_path)
