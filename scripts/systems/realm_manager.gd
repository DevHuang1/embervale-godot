extends Node
class_name RealmManager

## === Realm Transition System ===
## Manages instantiation, teardown and blended transition of realm biome builders.
## Wires directly into WorldManager via setup(world_manager).
##
## On realm_changed signal from GameState:
##   1. Fade screen to black (0.35s)
##   2. Queue-free old biome node
##   3. Instantiate + add_child new biome builder (RealmMistfen / RealmHeartwood)
##   4. Update WorldEnvironment (fog, ambient, sky color)
##   5. Update AudioManager ambient bed
##   6. Fade back in (0.35s)
##   7. Emit realm_ready(realm_id)
##
## Usage:
##   # In world_manager.gd _ready():
##   var rm := RealmManager.new()
##   add_child(rm)
##   rm.setup(self)

signal realm_ready(realm_id: String)
signal transition_started(realm_id: String)

@export var fade_duration : float = 0.35
@export var default_realm : String = "bramblewood"

# Realm environment presets
const REALM_ENVS := {
	"bramblewood": {
		"fog_color":      Color(0.42, 0.55, 0.48),
		"fog_density":    0.008,
		"ambient_energy": 0.55,
		"sky_top":        Color(0.10, 0.16, 0.14),
		"sky_horizon":    Color(0.28, 0.38, 0.32),
		"audio_bed":      "bramblewood",
	},
	"mistfen": {
		"fog_color":      Color(0.38, 0.52, 0.60),
		"fog_density":    0.022,
		"ambient_energy": 0.38,
		"sky_top":        Color(0.06, 0.12, 0.22),
		"sky_horizon":    Color(0.22, 0.36, 0.48),
		"audio_bed":      "mistfen",
	},
	"heartwood": {
		"fog_color":      Color(0.48, 0.22, 0.10),
		"fog_density":    0.012,
		"ambient_energy": 0.62,
		"sky_top":        Color(0.18, 0.06, 0.04),
		"sky_horizon":    Color(0.42, 0.18, 0.08),
		"audio_bed":      "heartwood",
	},
	"moonfen": {
		"fog_color":      Color(0.30, 0.38, 0.55),
		"fog_density":    0.028,
		"ambient_energy": 0.28,
		"sky_top":        Color(0.04, 0.06, 0.18),
		"sky_horizon":    Color(0.18, 0.22, 0.42),
		"audio_bed":      "moonfen",
	},
}

# Biome builder scripts (loaded lazily)
const BIOME_SCRIPTS := {
	"mistfen":   "res://scripts/world/realm_mistfen.gd",
	"heartwood": "res://scripts/world/realm_heartwood.gd",
}

var _world      : Node3D = null
var _current    : String = ""
var _biome_node : Node3D = null
var _fade_rect  : ColorRect = null
var _transitioning : bool = false

func setup(world_manager: Node3D) -> void:
	_world = world_manager

func _ready() -> void:
	_build_fade_overlay()
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("realm_changed"):
		gs.realm_changed.connect(_on_realm_changed)
	# Apply starting realm silently
	var start_realm := default_realm
	if gs != null and gs.get("current_realm") != null:
		start_realm = str(gs.get("current_realm"))
	_apply_env_silent(start_realm)
	_current = start_realm

func _build_fade_overlay() -> void:
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.anchor_right  = 1.0
	_fade_rect.anchor_bottom = 1.0
	_fade_rect.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_fade_rect.z_index       = 100
	# Find canvas layer or add one
	var canvas := CanvasLayer.new()
	canvas.layer = 99
	add_child(canvas)
	canvas.add_child(_fade_rect)

# ─────────────────────────────────────────────────────────────────────────────
# Transition
# ─────────────────────────────────────────────────────────────────────────────

func _on_realm_changed(realm_id: String) -> void:
	if realm_id == _current or _transitioning:
		return
	_transitioning = true
	transition_started.emit(realm_id)
	var tw := create_tween()
	# Fade to black
	tw.tween_property(_fade_rect, "color", Color(0, 0, 0, 1.0), fade_duration)
	tw.tween_callback(_swap_biome.bind(realm_id))
	# Fade back in
	tw.tween_property(_fade_rect, "color", Color(0, 0, 0, 0.0), fade_duration)
	tw.tween_callback(_on_transition_done.bind(realm_id))

func _swap_biome(realm_id: String) -> void:
	# Remove previous biome node
	if _biome_node != null and is_instance_valid(_biome_node):
		_biome_node.queue_free()
		_biome_node = null

	# Instantiate new biome builder
	if BIOME_SCRIPTS.has(realm_id):
		var script_path : String = BIOME_SCRIPTS[realm_id]
		if ResourceLoader.exists(script_path):
			var scr : Script = load(script_path)
			if scr != null:
				_biome_node = Node3D.new()
				_biome_node.set_script(scr)
				_biome_node.name = "BiomeBuilder_%s" % realm_id
				if _world != null:
					_world.add_child(_biome_node)
					if _biome_node.has_method("setup"):
						_biome_node.call("setup", _world)

	_apply_env_silent(realm_id)
	_play_realm_ambient(realm_id)
	_current = realm_id

func _on_transition_done(realm_id: String) -> void:
	_transitioning = false
	realm_ready.emit(realm_id)

# ─────────────────────────────────────────────────────────────────────────────
# Environment
# ─────────────────────────────────────────────────────────────────────────────

func _apply_env_silent(realm_id: String) -> void:
	if _world == null:
		return
	var env_node : WorldEnvironment = _world.get_node_or_null("Environment")
	if env_node == null or env_node.environment == null:
		return
	var preset : Dictionary = REALM_ENVS.get(realm_id, REALM_ENVS["bramblewood"])
	var env    : Environment = env_node.environment

	env.fog_enabled    = true
	env.volumetric_fog_enabled = false
	env.fog_light_color = preset["fog_color"]
	env.fog_density     = float(preset["fog_density"])
	env.ambient_light_energy = float(preset["ambient_energy"])

	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		var sky := env.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color     = preset["sky_top"]
		sky.sky_horizon_color = preset["sky_horizon"]

# ─────────────────────────────────────────────────────────────────────────────
# Audio
# ─────────────────────────────────────────────────────────────────────────────

func _play_realm_ambient(realm_id: String) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	if audio.has_method("play_realm_ambient"):
		audio.call("play_realm_ambient", realm_id)
	elif audio.has_method("start_ambient"):
		audio.call("start_ambient")

## Graceful crossfade between two realm environments (no hard cut).
## Call directly when you want a slow atmospheric blend without a scene swap.
func crossfade_env(from_realm: String, to_realm: String, duration: float = 2.0) -> void:
	if _world == null:
		return
	var env_node : WorldEnvironment = _world.get_node_or_null("Environment")
	if env_node == null or env_node.environment == null:
		return
	var from_p : Dictionary = REALM_ENVS.get(from_realm, REALM_ENVS["bramblewood"])
	var to_p   : Dictionary = REALM_ENVS.get(to_realm,   REALM_ENVS["bramblewood"])
	var env    : Environment = env_node.environment
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(env, "fog_light_color", to_p["fog_color"],       duration)
	tw.tween_property(env, "fog_density",     to_p["fog_density"],     duration)
	tw.tween_property(env, "ambient_light_energy", to_p["ambient_energy"], duration)
