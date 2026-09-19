extends Node3D
class_name TerrainRelief

const LAYOUT := preload("res://scripts/world/realm_layout_data.gd")
const GROUND_COMPOSITION := preload("res://scripts/systems/world_ground_composition.gd")

## === Terrain Relief ===
## Runtime heightmapped ground: replaces the flat PlaneMesh with a
## ridged ArrayMesh, rolling interior swells, and flattened gameplay
## zones around every landmark. Faithful to the layout (paths, quest
## nodes, gates) so collision and quest ranges are unaffected.

## Keep the default grid below 65,535 vertices. Some mobile/compatibility
## drivers otherwise truncate the indexed surface into rectangular strips.
## 128 subdivisions preserve readable rolling relief while keeping startup and
## mobile collision generation bounded.
@export_range(32, 254, 1) var subdivisions: int = 128
## Authored relief stays gentle around gameplay anchors and rises toward
## readable landmark ridges in the surrounding traversal space.
@export var ridge_amplitude: float = 1.15
@export var roll_amplitude: float = 0.42
@export var carve_amplitude: float = 0.28
@export var flatten_radius: float = 7.0

const HALF_EXTENT: float = 300.0
const MAX_CREST: float = 0.6
## Ashen Rise: long gentle northern ridge (see _ridge_band).
const RIDGE_X_MIN := -34.0
const RIDGE_X_MAX := 28.0
const RIDGE_CENTER_Z := -28.0
const RIDGE_HALF_WIDTH := 22.0
const RIDGE_PEAK_HEIGHT := 4.2

var _flatten_points: Array[Vector2] = [
	Vector2(-16.0, 10.0),   # PlayerSpawn
	Vector2(-6.4, 3.15),    # HushlingSpawn
	Vector2(1.25, -4.1),    # ShardSpawn
	Vector2(14.2, -10.4),   # BeaconSpawn
	Vector2(8.0, -6.0),     # SummonPoint1
	Vector2(20.0, -14.0),   # SummonPoint2
	Vector2(17.0, -3.0),    # SummonPoint3
	Vector2(11.0, -16.0),   # SummonPoint4
	Vector2(0.0, -18.0),    # QuestBoard
	Vector2(20.0, 20.0),    # MoonfenGate
	Vector2(-22.0, -20.0),  # ReturnGate
	Vector2(-16.0, -10.0),  # Boss arena stone
	Vector2(-4.5, 19.7),    # Travel gate A
	Vector2(-27.5, 0.3),    # Travel gate B
	Vector2(-10.0, -17.0),  # Mountain cache chest (ridge foot)
	Vector2(19.0, -16.0),   # Embervault cave entrance (ridge foot)
]
var _boss_anchor_points: Array[Vector2] = []
## Pond basins carved into the heightfield; specs are shared with the water
## presentation so the flat disc always sits inside a real depression.
var _pond_basins: Array[Dictionary] = []

## Per-realm ground palettes for terrain_ground.gdshader. Every explorable
## realm gets a distinct underfoot read: grass/dirt/stone families plus a
## glowing accent fleck (ember, fen-light, moonmoss). Moonfen values echo
## the violet terrain_moonfen.tres it can no longer see (relief overrides
## the scene material at runtime).
const REALM_TERRAIN := {
	"bramblewood": {
		"grass_color": Color(0.30, 0.48, 0.20),
		"grass_dry": Color(0.48, 0.46, 0.20),
		"dirt_color": Color(0.30, 0.22, 0.13),
		"dirt_amount": 0.68, "sand_amount": 0.24,
		"stone_color": Color(0.38, 0.38, 0.35),
		"crest_color": Color(0.45, 0.44, 0.40),
"accent_color": Color(0.96, 0.72, 0.29),
			# Ground-grid accent flecks are disabled: their cell edges read as
			# square cards on the mobile/compatibility renderer.
			"accent_strength": 0.0, "realm_tint": Color(0.88, 1.0, 0.72),
			"realm_tint_strength": 0.16, "moisture_strength": 0.12,
			"moss_color": Color(0.20, 0.52, 0.22), "moss_strength": 0.34,
			"terrain_brightness": 1.18, "uv_world_scale": 0.15, "tex_gain": 1.34,
	},
	"whispergrove": {
		"grass_color": Color(0.32, 0.50, 0.22),
		"grass_dry": Color(0.50, 0.48, 0.22),
		"dirt_color": Color(0.31, 0.24, 0.14),
		"dirt_amount": 0.60, "sand_amount": 0.22,
		"stone_color": Color(0.40, 0.40, 0.37),
		"crest_color": Color(0.47, 0.46, 0.42),
"accent_color": Color(1.00, 0.86, 0.45),
			"accent_strength": 0.0, "realm_tint": Color(0.76, 0.98, 0.82),
			"realm_tint_strength": 0.22, "moisture_strength": 0.28,
			"moss_color": Color(0.28, 0.72, 0.40), "moss_strength": 0.58,
			"terrain_brightness": 1.20, "uv_world_scale": 0.14, "tex_gain": 1.32,
	},
	"mistfen": {
		"grass_color": Color(0.18, 0.32, 0.26),
		"grass_dry": Color(0.30, 0.38, 0.34),
		"dirt_color": Color(0.16, 0.21, 0.24),
		"stone_color": Color(0.30, 0.34, 0.36),
		"crest_color": Color(0.36, 0.41, 0.43),
		"dirt_amount": 0.78, "sand_amount": 0.18,
"accent_color": Color(0.55, 0.85, 1.00),
			"accent_strength": 0.0, "realm_tint": Color(0.54, 0.78, 0.82),
			"realm_tint_strength": 0.30, "moisture_strength": 0.86,
			"moss_color": Color(0.22, 0.62, 0.58), "moss_strength": 0.48,
			"terrain_brightness": 1.12, "uv_world_scale": 0.15, "tex_gain": 1.38,
	},
	"heartwood": {
		"grass_color": Color(0.36, 0.28, 0.16),
		"grass_dry": Color(0.52, 0.36, 0.16),
		"dirt_color": Color(0.23, 0.15, 0.09),
		"dirt_amount": 0.82, "sand_amount": 0.28,
		"stone_color": Color(0.30, 0.26, 0.24),
		"crest_color": Color(0.38, 0.31, 0.26),
"accent_color": Color(1.00, 0.45, 0.12),
			"accent_strength": 0.0, "realm_tint": Color(1.0, 0.62, 0.34),
			"realm_tint_strength": 0.20, "moisture_strength": 0.08,
			"moss_color": Color(0.48, 0.20, 0.08), "moss_strength": 0.22,
			"terrain_brightness": 1.16, "uv_world_scale": 0.14, "tex_gain": 1.36,
	},
	"moonfen": {
		"grass_color": Color(0.28, 0.22, 0.42),
		"grass_dry": Color(0.36, 0.28, 0.48),
		"dirt_color": Color(0.13, 0.10, 0.22),
		"dirt_amount": 0.66, "sand_amount": 0.24,
		"stone_color": Color(0.22, 0.20, 0.30),
		"crest_color": Color(0.28, 0.25, 0.38),
"accent_color": Color(0.45, 0.72, 1.00),
			"accent_strength": 0.0, "realm_tint": Color(0.58, 0.46, 1.0),
			"realm_tint_strength": 0.34, "moisture_strength": 0.42,
			"moss_color": Color(0.30, 0.22, 0.62), "moss_strength": 0.34,
			"terrain_brightness": 1.14, "uv_world_scale": 0.15, "tex_gain": 1.35,
	},
}

@onready var terrain_mesh: MeshInstance3D = $TerrainMesh

## One vertex grid shared by the visual mesh and the collision surface, so the
## ground the character walks on is exactly the ground the player sees. A
## coarser collision grid chorded through hill crests and let the character
## walk up to two metres inside the visible slope.
var _grid_verts := PackedVector3Array()
var _grid_indices := PackedInt32Array()

## POM tiers: LOW off, MEDIUM single-step offset, HIGH short 4-step march.
const POM_BY_LEVEL := [0, 1, 2]
const DESKTOP_TERRAIN_SHADER := "res://assets/shaders/terrain_ground.gdshader"
const MOBILE_TERRAIN_SHADER := "res://assets/shaders/terrain_ground_mobile.gdshader"
## Static references guarantee these low-cost Android albedo resources remain
## in the PCK even though the full desktop layer set is selected dynamically.
const MOBILE_TERRAIN_TEXTURES := {
	"grass": preload("res://assets/textures/stylized/grass/albedo.png"),
	"dirt": preload("res://assets/textures/stylized/dirt/albedo.png"),
	"sand": preload("res://assets/textures/stylized/sand/albedo.png"),
	"rock": preload("res://assets/textures/stylized/rock/albedo.png"),
}

func _ready() -> void:
	add_to_group("terrain_relief")
	_register_layout_boss_anchors()
	_register_layout_content_anchors()
	_register_pond_basins()
	_build_grid()
	terrain_mesh.mesh = _build_mesh()
	terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var ground := _load_realm_material()
	_apply_palette(ground)
	terrain_mesh.material_override = ground
	_build_heightfield_collision()
	var qs := get_node_or_null("/root/WorldState/QualityScaler")
	if qs != null and qs.has_signal("level_changed"):
		qs.level_changed.connect(_on_quality_level)
		_on_quality_level(qs.level)

func _is_mobile_runtime() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]

## Realm material from assets/materials/terrain_<realm>.tres (binds the
## stylized PBR layer sets); falls back to a bare shader material so the
## palette override below still produces valid ground.
func _load_realm_material() -> ShaderMaterial:
	if _is_mobile_runtime():
		var mobile_ground := ShaderMaterial.new()
		mobile_ground.shader = load(MOBILE_TERRAIN_SHADER) as Shader
		return mobile_ground
	var realm := _realm_id()
	for path in ["res://assets/materials/terrain_%s.tres" % realm,
			"res://assets/materials/terrain_bramblewood.tres"]:
		if ResourceLoader.exists(path):
			var source := load(path) as ShaderMaterial
			var mat := source.duplicate(true) as ShaderMaterial if source != null else null
			if mat != null:
				# Keep the UE-style terrain shader as the live path: it owns the
				# sampled albedo, macro breakup, slope masks, and mobile tier gates.
				# The experimental layer compositor remains available for tests and
				# later A/B work, but must not silently flatten the player-facing map.
				mat.shader = load(DESKTOP_TERRAIN_SHADER) as Shader
				return mat
	var ground := ShaderMaterial.new()
	ground.shader = load(DESKTOP_TERRAIN_SHADER) as Shader
	return ground

func _apply_palette(ground: ShaderMaterial) -> void:
	# Keep sampler bindings explicit at runtime.  The terrain material can be
	# replaced by a realm scene, quality reload, or streamed-world setup; relying
	# only on the .tres sampler state made the shader fall back to white on some
	# Android/import paths, which flattened grass, sand, and soil into tint-only
	# colors.
	_bind_ground_texture_layers(ground)
	var pal: Dictionary = REALM_TERRAIN.get(_realm_id(),
		REALM_TERRAIN["bramblewood"])
	# Sand is intentionally explicit: without this binding the layer shader
	# receives its default brown and sand reads like dirt on mobile.
	ground.set_shader_parameter("sand_color",
		pal.get("sand_color", Color(0.68, 0.54, 0.30)))
	for key in ["grass_color", "grass_dry", "dirt_color", "stone_color",
			"crest_color"]:
		if pal.has(key):
			ground.set_shader_parameter(key, pal[key])
	for key in ["dirt_amount", "sand_amount"]:
		if pal.has(key):
			ground.set_shader_parameter(key, pal[key])
	for key in ["realm_tint", "realm_tint_strength", "moisture_strength",
			"moss_color", "moss_strength", "terrain_brightness",
			"uv_world_scale", "tex_gain"]:
		if pal.has(key):
			ground.set_shader_parameter(key, pal[key])
	ground.set_shader_parameter("accent_color",
		pal.get("accent_color", Color(0.96, 0.72, 0.29)))
	ground.set_shader_parameter("accent_strength",
		float(pal.get("accent_strength", 0.0)))
	var moisture := float(pal.get("moisture_strength", 0.0))
	ground.set_shader_parameter("macro_breakup_strength", lerpf(0.34, 0.58, moisture))
	ground.set_shader_parameter("micro_grain_strength", lerpf(0.20, 0.34, moisture))
	ground.set_shader_parameter("puddle_sheen_strength", lerpf(0.10, 0.34, moisture))
	ground.set_shader_parameter("tex_blend", 1.0)
	ground.set_shader_parameter("moss_strength", maxf(float(pal.get("moss_strength", 0.0)), 0.42))

func _bind_ground_texture_layers(ground: ShaderMaterial) -> void:
	# One canonical stylized set per family serves every tier and realm; the
	# former `*_v2` shadow folders are gone, so albedo, normal and roughness
	# always come from the same directory and never double-load a texture.
	var mobile := _is_mobile_runtime()
	var layers := {
		"grass": "grass",
		"dirt": "dirt",
		"sand": "sand",
		"rock": "rock",
	}
	for layer_value in layers:
		var layer := str(layer_value)
		var root := "res://assets/textures/stylized/%s" % str(layers[layer_value])
		var albedo := _mobile_texture(layer) if mobile \
			else _load_texture(root, "albedo")
		if albedo != null:
			ground.set_shader_parameter("%s_tex" % layer, albedo)
		if mobile:
			continue
		var normal := _load_texture(root, "normal")
		var roughness := _load_texture(root, "roughness")
		if normal != null:
			ground.set_shader_parameter("%s_norm" % layer, normal)
		if roughness != null:
			ground.set_shader_parameter("%s_rough" % layer, roughness)
	if mobile:
		return
	for layer_name in ["moss", "mud"]:
		var root := "res://assets/textures/stylized/%s" % layer_name
		var albedo := _load_texture(root, "albedo")
		var normal := _load_texture(root, "normal")
		var roughness := _load_texture(root, "roughness")
		if albedo != null:
			ground.set_shader_parameter("%s_tex" % layer_name, albedo)
		if normal != null:
			ground.set_shader_parameter("%s_norm" % layer_name, normal)
		if roughness != null:
			ground.set_shader_parameter("%s_rough" % layer_name, roughness)

func _load_texture(root: String, channel: String) -> Texture2D:
	var path := "%s/%s.png" % [root, channel]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _mobile_texture(layer: String) -> Texture2D:
	return MOBILE_TERRAIN_TEXTURES.get(layer) as Texture2D

func _on_quality_level(level: int) -> void:
	var ground := terrain_mesh.material_override as ShaderMaterial
	if ground == null or not ground.shader:
		return
	var idx := clampi(level, 0, POM_BY_LEVEL.size() - 1)
	if "pom_mode" in ground.shader.code:
		ground.set_shader_parameter("pom_mode", POM_BY_LEVEL[idx])

## Realm id for this map: biome scenes carry biome_id; Moonfen's manager
## doesn't, so fall back to the current travel realm.
func _realm_id() -> String:
	var world_root := get_parent()
	return LAYOUT.visual_realm_for(world_root)

func _register_layout_boss_anchors() -> void:
	_boss_anchor_points.clear()
	for anchor in LAYOUT.boss_anchor_points_for_world(get_parent()):
		if _boss_anchor_points.has(anchor):
			continue
		_boss_anchor_points.append(anchor)
		if not _flatten_points.has(anchor):
			_flatten_points.append(anchor)

## Level the ground under every authored route, gate, chest, gathering node,
## set-piece, pocket and structure the realm profile declares. The hardcoded
## gameplay list above only covers fixed scene nodes (spawn, summon points,
## quest board); everything that moves with layout data is derived here so
## terrain, content and streaming cannot drift apart.
func _register_layout_content_anchors() -> void:
	for anchor in LAYOUT.flatten_anchors_for_world(get_parent()):
		if _flatten_points.has(anchor):
			continue
		_flatten_points.append(anchor)

func _register_pond_basins() -> void:
	_pond_basins.clear()
	for spec in GROUND_COMPOSITION.pond_specs(_realm_id()):
		if not spec is Dictionary:
			continue
		var basin := (spec as Dictionary).duplicate()
		# Floor sits below the lowest bank sample, so the flat water disc is
		# contained on every side even when the pond lands on a swell.
		basin["floor"] = _lowest_bank(basin) - float(basin.get("depth", 0.32))
		_pond_basins.append(basin)

## Lowest of the base terrain sampled around a basin's rim (no basin applied).
func _lowest_bank(basin: Dictionary) -> float:
	var center: Vector2 = basin.get("center", Vector2.ZERO)
	var br := float(basin.get("radius", 3.0))
	var lowest := INF
	for step in 12:
		var ang := TAU * float(step) / 12.0
		lowest = minf(lowest, _base_height(
			center.x + cos(ang) * br * 1.35,
			center.y + sin(ang) * br * 1.35))
	return lowest if is_finite(lowest) else 0.0

func _base_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var r := p.length()

	# Shallow rolling swells across the open glade
	var rolls := fbm(p * 0.02 + Vector2(101.0, 19.0)) - 0.5
	var h := roll_amplitude * rolls

	# Carved hollow ring between the core and the treeline
	var carve := smoothstep(9.0, 17.0, r)
	carve *= 1.0 - smoothstep(24.0, 29.0, r)
	h -= carve_amplitude * carve

	# Ridged crest rising toward the treeline ring
	var rim := smoothstep(17.0, 24.0, r)
	rim *= 1.0 - smoothstep(29.0, 32.0, r)
	var ridged := fbm(p * 0.045 + Vector2(13.7, 41.3))
	h += ridge_amplitude * rim * ridged

	# The Ashen Rise: a long, gentle northern ridge the character can
	# climb (peaks ~4 m, slopes under 30 deg).
	h += _ridge_band(p)

	# Flatten around gameplay landmarks (ridge included)
	h *= _flatten_mask(p)

	return clampf(h, -1.2, 8.0)

func height_at(x: float, z: float) -> float:
	var h := _base_height(x, z)
	# Authored pond basins: blend to a flat floor that sits below the lowest
	# bank, so the water disc rests in a real depression on every side.
	if not _pond_basins.is_empty():
		var p := Vector2(x, z)
		for basin in _pond_basins:
			var center: Vector2 = basin.get("center", Vector2.ZERO)
			var br := float(basin.get("radius", 3.0))
			var d := p.distance_to(center)
			if d >= br:
				continue
			var floor_y := float(basin.get("floor", h))
			if h <= floor_y:
				continue
			var weight := 1.0 - smoothstep(br * 0.45, br, d)
			h -= (h - floor_y) * weight
	return h

func get_surface_profile(world_position: Vector3) -> Dictionary:
	var p := Vector2(world_position.x, world_position.z)
	var height := height_at(p.x, p.y)
	var nearby := height_at(p.x + 0.5, p.y) - height
	var across := height_at(p.x, p.y + 0.5) - height
	var slope := clampf(sqrt(nearby * nearby + across * across) * 2.0, 0.0, 1.0)
	var wet := clampf((0.45 - height) * 0.8 + (1.0 - slope) * 0.18, 0.0, 1.0)
	return {
		"height": height,
		"normal": sample_surface_normal(world_position),
		"slope": slope,
		"moisture": wet,
		"realm": _realm_id(),
		"material_hint": "rock" if slope > 0.68 else ("mud" if wet > 0.62 else "grass"),
		"traversable": slope < 0.82,
	}

func sample_surface_height(world_position: Vector3) -> float:
	return height_at(world_position.x, world_position.z)

func sample_surface_normal(world_position: Vector3) -> Vector3:
	var step := 0.5
	var dx := (height_at(world_position.x + step, world_position.z)
		- height_at(world_position.x - step, world_position.z)) / (step * 2.0)
	var dz := (height_at(world_position.x, world_position.z + step)
		- height_at(world_position.x, world_position.z - step)) / (step * 2.0)
	return Vector3(-dx, 1.0, -dz).normalized()

func validate_surface_visibility() -> Dictionary:
	var material := terrain_mesh.material_override as ShaderMaterial
	var mesh := terrain_mesh.mesh as ArrayMesh
	var aabb := mesh.get_aabb() if mesh != null else AABB()
	return {"valid": material != null and mesh != null and not aabb.size.is_zero_approx(),
		"opaque": material != null and material.shader != null and not material.shader.code.contains("ALPHA"),
		"depth_draw": "depth_draw_opaque" in str(material.shader.code) if material != null and material.shader != null else false,
		"cull_fallback": "cull_disabled" in str(material.shader.code) if material != null and material.shader != null else false,
		"aabb": aabb, "surface_height": sample_surface_height(global_position)}

func conform_anchor(node: Node3D, vertical_offset: float = 0.0) -> void:
	if node == null or not is_instance_valid(node):
		return
	var target := node.global_position if node.is_inside_tree() else node.position
	target.y = sample_surface_height(target) + vertical_offset
	if node.is_inside_tree():
		node.global_position = target
	else:
		node.position = target
	node.set_meta("terrain_surface_height", target.y - vertical_offset)
	node.set_meta("terrain_vertical_offset", vertical_offset)

func get_material_report(world_position: Vector3) -> Dictionary:
	var material := terrain_mesh.material_override as ShaderMaterial
	var textures: Dictionary = {}
	if material != null:
		for parameter in ["grass_tex", "dirt_tex", "sand_tex", "mud_tex", "moss_tex", "rock_tex"]:
			var resource := material.get_shader_parameter(parameter) as Texture2D
			textures[parameter] = resource.resource_path if resource != null else ""
	var profile := get_surface_profile(world_position)
	return {
		"realm": _realm_id(),
		"shader": material.shader.resource_path if material != null and material.shader != null else "",
		"textures": textures,
		"material_hint": profile.get("material_hint", "grass"),
		"height": profile.get("height", 0.0),
		"moisture": profile.get("moisture", 0.0),
		"uv_world_scale": material.get_shader_parameter("uv_world_scale") if material != null else 0.0,
	}

## Long, gentle northern ridge ("The Ashen Rise"). Bell-curve across its
## length and width, with fbm-shaping so the crest has natural saddles
## and the whole thing climbs at under ~30°.
func _ridge_band(p: Vector2) -> float:
	var along := smoothstep(RIDGE_X_MIN, RIDGE_X_MIN + 8.0, p.x)
	along *= 1.0 - smoothstep(RIDGE_X_MAX - 6.0, RIDGE_X_MAX, p.x)
	# p is Vector2(x, z) — the north axis is .y
	var depth: float = abs(p.y - RIDGE_CENTER_Z)
	var across := 1.0 - smoothstep(0.0, RIDGE_HALF_WIDTH, depth)
	var band := along * across
	if band <= 0.0:
		return 0.0
	var crowness := fbm(p * 0.028 + Vector2(57.3, 91.7))  # 0..1 irregular crest
	crowness = 0.55 + 0.45 * crowness                        # no dead-flat spots
	return RIDGE_PEAK_HEIGHT * band * crowness

func _flatten_mask(p: Vector2) -> float:
	var flat := 1.0
	for fp in _flatten_points:
		var d := p.distance_to(fp)
		flat = minf(flat, smoothstep(flatten_radius * 0.55, flatten_radius + 1.0, d))
	return flat

## Public anchor list for prop placement: the flattened gameplay zones.
func prop_anchor_points() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for anchor in _flatten_points:
		if not _boss_anchor_points.has(anchor):
			result.append(anchor)
	return result

## Fills the shared heightfield grid in the same winding the visual mesh uses.
func _build_grid() -> void:
	var n := clampi(subdivisions, 32, 254)
	var step := HALF_EXTENT * 2.0 / float(n)
	_grid_verts.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var x := -HALF_EXTENT + i * step
			var z := -HALF_EXTENT + j * step
			_grid_verts[j * (n + 1) + i] = Vector3(x, height_at(x, z), z)

	_grid_indices.resize(n * n * 6)
	var k := 0
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := (j + 1) * (n + 1) + i + 1
			var d := (j + 1) * (n + 1) + i
			_grid_indices[k] = a; _grid_indices[k + 1] = c; _grid_indices[k + 2] = b
			_grid_indices[k + 3] = a; _grid_indices[k + 4] = d; _grid_indices[k + 5] = c
			k += 6

func _build_mesh() -> ArrayMesh:
	var n := clampi(subdivisions, 32, 254)
	var step := HALF_EXTENT * 2.0 / float(n)
	var verts := _grid_verts
	var normals := PackedVector3Array()
	normals.resize((n + 1) * (n + 1))

	var e := step * 0.5
	for j in n + 1:
		for i in n + 1:
			var x := -HALF_EXTENT + i * step
			var z := -HALF_EXTENT + j * step
			var idx := j * (n + 1) + i
			var dhx := (height_at(x + e, z) - height_at(x - e, z)) / step
			var dhz := (height_at(x, z + e) - height_at(x, z - e)) / step
			normals[idx] = Vector3(-dhx, 1.0, -dhz).normalized()

	var inds := _grid_indices

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = inds

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.custom_aabb = AABB(Vector3(-302.0, -5.0, -302.0), Vector3(620.0, 20.0, 620.0))
	return am

## Builds the concave trimesh from the same vertex grid as the visual mesh so
## the hero and enemies walk exactly on the visible hill surface (relief mesh
## alone is visual-only). The flat editor plane is removed so it can't shadow
## the relief in dips.
func _build_heightfield_collision() -> void:
	var body := terrain_mesh.get_parent() as StaticBody3D
	if body == null or not is_inside_tree():
		return
	# Drop the legacy flat plane (grove.tscn / moonfen.tscn default child).
	for child in body.get_children():
		if child is CollisionShape3D:
			child.queue_free()

	var faces := PackedVector3Array()
	faces.resize(_grid_indices.size())
	for index in _grid_indices.size():
		faces[index] = _grid_verts[_grid_indices[index]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.name = "ReliefCollision"
	cs.shape = shape
	body.add_child(cs)
	cs.owner = null  # don't persist as an authored child of the scene

# === Deterministic noise (mirrors terrain_moss.gdshader) ===
func hash21(p: Vector2) -> float:
	p = (p - p.floor()) * Vector2(127.13, 311.71)
	var k := p.x * p.x + p.y * p.y + 34.43
	p.x += k
	p.y += k
	var prod := p.x * p.y
	return prod - floor(prod)

func value_noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var ff := f * f
	var u := ff * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := hash21(i)
	var b := hash21(i + Vector2(1.0, 0.0))
	var cx := hash21(i + Vector2(0.0, 1.0))
	var d := hash21(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, u.x), lerpf(cx, d, u.x), u.y)

func fbm(p: Vector2) -> float:
	var total := 0.0
	var amplitude := 0.5
	var q := p
	for l in 4:
		total += value_noise(q) * amplitude
		q = q * Vector2(2.03, 2.03) + Vector2(19.19, 7.33)
		amplitude *= 0.5
	return total
