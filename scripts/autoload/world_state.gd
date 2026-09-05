extends Node

## === WorldState AutoLoad ===
## Manages persistent world data that outlives individual scenes:
##   - Environment shader globals (combat intensity, rain, wind, magic level)
##   - Gathered resource nodes (per-node cooldown tracking)
##   - Discovered landmarks
##   - Active realm state
##   - Arena / encounter tracking
##
## Signals let biome builders, enemies, and weather systems react without
## polling every frame.

signal combat_intensity_changed(value: float)
signal rain_changed(value: float)
signal wind_changed(value: Vector2)
signal gust_triggered(direction: Vector2)
signal realm_environment_changed(realm_id: String)

# === Shader global mirrors ====================================================
# Always set via the setters below so the RenderingServer stays in sync.

var _combat_intensity : float  = 0.0
var _rain_level       : float  = 0.0
var _wind             : Vector2 = Vector2.ZERO
var magic_level      : float  = 0.35

# === Node / landmark tracking =================================================
var _gathered_nodes   : Dictionary = {}  # node_id → unix time when re-spawns
var _discovered       : Dictionary = {}  # landmark_id → bool

# === Persistent ground wear ===================================================
## A TerrainWear child node holding the session R8 wear map. Footsteps,
## dashes and impacts call wear.record(); the terrain shader samples the
## uploaded map via the world_wear_map global. Heroes look this up as
## /root/WorldState.wear.
var wear : TerrainWear = null

# === Current realm ============================================================
var _current_realm    : String = "bramblewood"
var _realm_time_of_day: float  = 0.25   # 0=midnight 0.5=noon

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_all_shader_globals()
	# Scene-scoped helpers restored from the canonical WorldState wiring:
	# callers resolve these via "/root/WorldState/QualityScaler" (settings,
	# grove dressing, terrain relief, enemies, boss) and DebrisSystem is the
	# pooled impact-shard service used by destructible props.
	var quality := QualityScaler.new()
	quality.name = "QualityScaler"
	add_child(quality)
	var debris := DebrisSystem.new()
	debris.name = "DebrisSystem"
	add_child(debris)
	var terrain_wear := TerrainWear.new()
	terrain_wear.name = "TerrainWear"
	add_child(terrain_wear)
	wear = terrain_wear

# ─── Shader globals ───────────────────────────────────────────────────────────

func set_combat_intensity(v: float) -> void:
	_combat_intensity = clampf(v, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("world_combat_intensity", _combat_intensity)
	combat_intensity_changed.emit(_combat_intensity)
	# Drive AudioManager combat bed
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("update_combat_beds"):
		audio.call("update_combat_beds", _combat_intensity)

func get_combat_intensity() -> float:
	return _combat_intensity

func set_rain(v: float) -> void:
	_rain_level = clampf(v, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("world_rain_level", _rain_level)
	rain_changed.emit(_rain_level)

func get_rain() -> float:
	return _rain_level

func set_wind(v: Vector2) -> void:
	_wind = v
	RenderingServer.global_shader_parameter_set("world_wind", v)
	wind_changed.emit(v)

func get_wind() -> Vector2:
	return _wind

func gust(direction: Vector2 = Vector2.ZERO, strength: float = 1.0) -> void:
	# Short impulse — biome builders and SpringBoneSystem pick this up
	var dir := direction if direction.length_squared() > 0.01 \
		else Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	set_wind(dir * strength)
	gust_triggered.emit(dir * strength)
	# Fade back to calm
	var tw := create_tween()
	tw.tween_method(func(v): set_wind(v), dir * strength, _wind, 1.8) \
		.set_trans(Tween.TRANS_CUBIC)

func set_hero_pos_radius(pos: Vector3, radius: float) -> void:
	RenderingServer.global_shader_parameter_set(
		"world_hero_pos_radius", Vector4(pos.x, pos.y, pos.z, radius))

func set_magic_level(v: float) -> void:
	magic_level = clampf(v, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("world_magic_level", magic_level)

func _apply_all_shader_globals() -> void:
	RenderingServer.global_shader_parameter_set("world_combat_intensity", _combat_intensity)
	RenderingServer.global_shader_parameter_set("world_rain_level",       _rain_level)
	RenderingServer.global_shader_parameter_set("world_wind",             _wind)
	RenderingServer.global_shader_parameter_set("world_magic_level",      magic_level)

# ─── Pusher helpers (for CombatFx / biome shockwaves) ─────────────────────────

func set_pusher(slot: int, world_pos: Vector3, radius: float) -> void:
	if slot < 1 or slot > 3:
		return
	RenderingServer.global_shader_parameter_set(
		"world_pusher_%d" % slot, Vector4(world_pos.x, world_pos.y, world_pos.z, radius))

func clear_pusher(slot: int) -> void:
	RenderingServer.global_shader_parameter_set(
		"world_pusher_%d" % slot, Vector4(0, 0, 0, 0))

# ─── Resource node tracking ───────────────────────────────────────────────────

func mark_gathered(node_id: String, respawn_seconds: float = 120.0) -> void:
	_gathered_nodes[node_id] = Time.get_unix_time_from_system() + respawn_seconds

func is_gathered(node_id: String) -> bool:
	if not _gathered_nodes.has(node_id):
		return false
	if Time.get_unix_time_from_system() >= _gathered_nodes[node_id]:
		_gathered_nodes.erase(node_id)
		return false
	return true

# ─── Landmarks ────────────────────────────────────────────────────────────────

func discover_landmark(landmark_id: String) -> bool:
	if _discovered.get(landmark_id, false):
		return false  # already known
	_discovered[landmark_id] = true
	return true  # first discovery

func has_discovered(landmark_id: String) -> bool:
	return bool(_discovered.get(landmark_id, false))

# ─── Realm state ─────────────────────────────────────────────────────────────

func set_realm(realm_id: String) -> void:
	_current_realm = realm_id
	realm_environment_changed.emit(realm_id)

func get_realm() -> String:
	return _current_realm

func set_time_of_day(t: float) -> void:
	_realm_time_of_day = fmod(t, 1.0)

func get_time_of_day() -> float:
	return _realm_time_of_day

func is_night() -> bool:
	return _realm_time_of_day > 0.75 or _realm_time_of_day < 0.22

# ─── Serialisation (called by SaveLoadManager) ─────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"combat_intensity": _combat_intensity,
		"rain_level":       _rain_level,
		"magic_level":      magic_level,
		"current_realm":    _current_realm,
		"time_of_day":      _realm_time_of_day,
		"gathered_nodes":   _gathered_nodes.duplicate(),
		"discovered":       _discovered.duplicate(),
	}

func from_dict(d: Dictionary) -> void:
	set_combat_intensity(float(d.get("combat_intensity", 0.0)))
	set_rain(float(d.get("rain_level", 0.0)))
	set_magic_level(float(d.get("magic_level", 0.35)))
	_current_realm    = str(d.get("current_realm", "bramblewood"))
	_realm_time_of_day = float(d.get("time_of_day", 0.25))
	_gathered_nodes   = d.get("gathered_nodes", {})
	_discovered       = d.get("discovered", {})
	_apply_all_shader_globals()
