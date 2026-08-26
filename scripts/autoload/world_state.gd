extends Node

## === WorldState — unified sensory-state engine (autoload) ===
## Single source of truth for the world's "mood": combat intensity,
## ambient magic, realm tint, wind and rain. Publishes everything as
## shader globals each frame so any material can react without wiring.
##
## Feeds off existing signals only — GameState schema is untouched:
##   ScanManager.relic_forged -> scan_depth / magic_level
##   GameState.combat_state polled per frame (cheap dictionary read)
##   DayNightCycle.report_night_factor pushes its cached night factor.

signal rain_changed(level: float)

const INTENSITY_RISE := 0.55      # per second while in combat
const INTENSITY_DECAY := 0.22     # per second while exploring
const IMPACT_BUMP := 0.16         # per registered hit
const CORRUPTION_DECAY := 0.03    # per second; corruption has no source yet
const WEAR_BOUNDS := Rect2(-76, -76, 152, 152)
const HERO_PUSH_RADIUS := 2.4

# --- Mood state (all session-only by design) ---
var combat_intensity: float = 0.0
var magic_level: float = 0.35
var night_factor: float = 0.0
var corruption: float = 0.0
var biome_tint: Color = Color(1, 1, 1)
var scan_depth: int = 0
var weather_locked: bool = false   # beacon-lit calm: scripted weather wins

var hero_position: Vector3 = Vector3.ZERO
var particle_scale: float = 1.0    # QualityScaler multiplies into emitter writes

# --- Wind (drives grass/canopy `world_wind` global) ---
var wind := Vector2.ZERO
var _wind_dir := Vector2.RIGHT.rotated(randf() * TAU)
var _wind_clock := randf() * TAU
var _gust_energy := 0.0

# --- Rain target (eased); rig built lazily per scene ---
var rain_level: float = 0.0
var _rain_target: float = 0.0
var _rain_rig: GPUParticles3D = null
var _rain_quad: QuadMesh = null

# --- Scene-scoped helpers (created on demand) ---
var wear: TerrainWear = null
var quality: QualityScaler = null
var debris: DebrisSystem = null

var _realm_conn_done := false
var _debris_scene: Node = null


func _ready() -> void:
	add_to_group("world_state")
	_register_default_globals()
	ScanManager.relic_forged.connect(_on_relic_forged)
	_scan_realm_tint()
	quality = QualityScaler.new()
	quality.name = "QualityScaler"
	add_child(quality)
	debris = DebrisSystem.new()
	debris.name = "DebrisSystem"
	add_child(debris)


func _register_default_globals() -> void:
	RenderingServer.global_shader_parameter_set("world_combat_intensity", 0.0)
	RenderingServer.global_shader_parameter_set("world_magic_level", magic_level)
	RenderingServer.global_shader_parameter_set("world_rain_level", 0.0)
	RenderingServer.global_shader_parameter_set("world_wind", Vector2.ZERO)
	RenderingServer.global_shader_parameter_set(
		"world_hero_pos_radius",
		Vector4(0, 0, 0, HERO_PUSH_RADIUS))
	for slot in 3:
		RenderingServer.global_shader_parameter_set(
			"world_pusher_%d" % (slot + 1), Vector4())
	RenderingServer.global_shader_parameter_set(
		"world_wear_bounds",
		Vector4(WEAR_BOUNDS.position.x, WEAR_BOUNDS.position.y,
			WEAR_BOUNDS.size.x, WEAR_BOUNDS.size.y))
	var blank := Image.create(2, 2, false, Image.FORMAT_R8)
	for y in 2:
		for x in 2:
			blank.set_pixel(x, y, Color(0, 0, 0))
	RenderingServer.global_shader_parameter_set("world_wear_map", ImageTexture.create_from_image(blank))


func _process(delta: float) -> void:
	_update_intensity(delta)
	_update_corruption(delta)
	_update_magic_level()
	_update_wind(delta)
	_update_rain(delta)
	_track_scene()
	_publish_globals()
	_publish_pushers()
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("update_combat_beds"):
		audio.update_combat_beds(combat_intensity, night_factor)


## Vegetation trample slots: hero is priority; nearest enemies/boss fill
## the rest (tier-controlled count, LOW = hero only). Shader globals cannot
## be arrays, so slots 1-3 publish individually for grass_blade.gdshader.
func _publish_pushers() -> void:
	var slots := quality.vegetation_pushers if quality != null else 4
	var pushers: Array[Vector4] = [
		Vector4(hero_position.x, hero_position.z, HERO_PUSH_RADIUS, 0.0),
		Vector4(), Vector4(), Vector4()]
	if slots > 1:
		var scene := get_tree().current_scene if get_tree() != null else null
		if scene != null:
			var movers: Array[Dictionary] = []
			for group in ["enemy", "boss", "hushling"]:
				for node in scene.get_tree().get_nodes_in_group(group):
					if node is Node3D and is_instance_valid(node) \
							and not node.is_in_group("player"):
						movers.append({
							"node": node,
							"d": hero_position.distance_squared_to(
								(node as Node3D).global_position)})
			movers.sort_custom(func(a, b) -> bool: return a.d < b.d)
			var slot := 1
			for m in movers:
				if slot >= mini(slots, 4):
					break
				var n := m.node as Node3D
				if n.global_position.distance_squared_to(
						Vector3(hero_position.x, 0, hero_position.z)) > 900.0:
					continue   # > 30m away: irrelevant to nearby grass
				var radius := 3.2 if n.is_in_group("boss") else 1.6
				pushers[slot] = Vector4(n.global_position.x,
					n.global_position.z, radius, 0.0)
				slot += 1
	for i in 3:
		RenderingServer.global_shader_parameter_set(
			"world_pusher_%d" % (i + 1), pushers[i + 1])


## Short-lived wind surge (boss slams, phase transitions). Decays fast.
func gust(strength: float) -> void:
	_gust_energy = clampf(maxf(_gust_energy, strength), 0.0, 1.0)


func _update_intensity(delta: float) -> void:
	var in_combat: bool = GameState != null \
		and GameState.combat_state == GameState.CombatState.COMBAT
	if in_combat:
		combat_intensity = minf(combat_intensity + INTENSITY_RISE * delta, 1.0)
	else:
		combat_intensity = maxf(combat_intensity - INTENSITY_DECAY * delta, 0.0)


func _update_corruption(delta: float) -> void:
	corruption = maxf(corruption - CORRUPTION_DECAY * delta, 0.0)


func _update_magic_level() -> void:
	var beacon_bonus := 0.15 if GameState.beacon_lit else 0.0
	magic_level = clampf(
		night_factor * 0.7 + minf(float(scan_depth), 5.0) * 0.06 + beacon_bonus,
		0.0, 1.0)


func _update_wind(delta: float) -> void:
	_wind_clock += delta
	_wind_dir = _wind_dir.rotated(sin(_wind_clock * 0.11) * 0.12 * delta)
	_gust_energy = maxf(_gust_energy - delta * 1.4, 0.0)
	# Layered strength: idle breeze < storm of combat < downpour < slams
	var storm := combat_intensity * combat_intensity * 0.14
	var wet := rain_level * 0.10
	var surge := _gust_energy * 0.30
	var gust := 0.055 + 0.02 * sin(_wind_clock * 0.9) + 0.015 * sin(_wind_clock * 2.7 + 1.3)
	wind = _wind_dir * clampf(gust + storm + wet + surge, 0.0, 0.55)


func _update_rain(delta: float) -> void:
	rain_level = move_toward(rain_level, _rain_target, delta * 0.25)
	if rain_level > 0.005 or _rain_target > 0.005:
		_ensure_rain_rig()
	if _rain_rig != null:
		var rain_ratio := rain_level
		if quality != null:
			rain_ratio *= quality.particle_scale
		_rain_rig.amount_ratio = rain_ratio
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_rain_rig.global_position = cam.global_position \
				+ cam.global_transform.basis.z * 3.0
	RenderingServer.global_shader_parameter_set("world_rain_level", rain_level)


## Scripted weather entry point. Beacon-lit calm ignores calls while locked.
func set_rain(target: float) -> void:
	if weather_locked:
		target = 0.0
	_rain_target = clampf(target, 0.0, 1.0)
	rain_changed.emit(rain_level)


func notify_impact(strength: float) -> void:
	combat_intensity = clampf(maxf(combat_intensity, strength), 0.0, 1.0)


func report_night_factor(nf: float) -> void:
	night_factor = clampf(nf, 0.0, 1.0)


func _on_relic_forged(_relic: RelicData) -> void:
	scan_depth += 1


func _scan_realm_tint() -> void:
	var id: String = GameState.current_realm if GameState != null else ""
	var realm: Dictionary = Bestiary.REALMS.get(id, {})
	if not realm.is_empty():
		biome_tint = realm.get("mist_tint", biome_tint)
	if not _realm_conn_done and GameState != null:
		_realm_conn_done = true
		GameState.realm_changed.connect(func(rid: String) -> void:
			var r: Dictionary = Bestiary.REALMS.get(rid, {})
			if not r.is_empty():
				biome_tint = r.get("mist_tint", biome_tint))


func _publish_globals() -> void:
	RenderingServer.global_shader_parameter_set("world_combat_intensity", combat_intensity)
	RenderingServer.global_shader_parameter_set("world_magic_level", magic_level)
	RenderingServer.global_shader_parameter_set("world_wind", wind)
	hero_position = Vector3(GameState.player_position.x, 0.0,
		GameState.player_position.y)
	RenderingServer.global_shader_parameter_set(
		"world_hero_pos_radius",
		Vector4(hero_position.x, hero_position.z, HERO_PUSH_RADIUS, 0.0))


## Re-scan when the scene changes: attach wear map + drop stale rigs.
func _track_scene() -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return
	if wear == null or not is_instance_valid(wear) or wear.get_parent() != scene:
		if wear != null and is_instance_valid(wear):
			wear.queue_free()
		wear = TerrainWear.new()
		wear.name = "TerrainWear"
		scene.add_child(wear)
	if scene != _debris_scene:
		_debris_scene = scene
		if debris != null:
			debris.reset()
	if _rain_rig != null and is_instance_valid(_rain_rig) \
			and _rain_rig.get_parent() != scene:
		_rain_rig.queue_free()
		_rain_rig = null


func _ensure_rain_rig() -> void:
	if _rain_rig != null and is_instance_valid(_rain_rig):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _rain_quad == null or not is_instance_valid(_rain_quad):
		_rain_quad = QuadMesh.new()
		_rain_quad.size = Vector2(0.03, 0.55)
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color(0.62, 0.72, 0.82, 0.34)
		mat.albedo_texture = CombatFx.radial_glow_texture()
		mat.disable_receive_shadows = true
		_rain_quad.material = mat
	var rig := GPUParticles3D.new()
	rig.draw_pass_1 = _rain_quad
	rig.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	rig.visibility_aabb = AABB(Vector3(-16, -12, -16), Vector3(32, 24, 32))
	rig.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.amount = 240
	rig.lifetime = 0.9
	rig.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(11, 6, 11)
	mat.direction = Vector3(0.08, -1, 0.03)
	mat.spread = 2.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 21.0
	mat.gravity = Vector3(0, -14, 0)
	mat.scale_min = 0.7
	mat.scale_max = 1.3
	mat.color = Color(0.62, 0.72, 0.82, 0.5)
	rig.process_material = mat
	scene.add_child(rig)
	_rain_rig = rig
