extends Node3D
class_name TerrainRelief

## === Terrain Relief ===
## Runtime heightmapped ground: replaces the flat PlaneMesh with a
## ridged ArrayMesh, rolling interior swells, and flattened gameplay
## zones around every landmark. Faithful to the layout (paths, quest
## nodes, gates) so collision and quest ranges are unaffected.

## Keep the default grid below 65,535 vertices. Some mobile/compatibility
## drivers otherwise truncate the indexed surface into rectangular strips.
## 240 subdivisions produce 58,081 vertices.
@export_range(32, 254, 1) var subdivisions: int = 240
## Flat-world presentation: hills and ridges are intentionally disabled.
## Keep the parameters exposed for saved-scene compatibility and future toggles.
@export var ridge_amplitude: float = 0.0
@export var roll_amplitude: float = 0.0
@export var carve_amplitude: float = 0.0
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
		"stone_color": Color(0.38, 0.38, 0.35),
		"crest_color": Color(0.45, 0.44, 0.40),
"accent_color": Color(0.96, 0.72, 0.29),
			"accent_strength": 0.35, "realm_tint": Color(0.88, 1.0, 0.72),
			"realm_tint_strength": 0.16, "moisture_strength": 0.12,
			"moss_color": Color(0.20, 0.52, 0.22), "moss_strength": 0.34,
			"terrain_brightness": 1.55, "uv_world_scale": 0.34, "tex_gain": 1.9,
	},
	"whispergrove": {
		"grass_color": Color(0.32, 0.50, 0.22),
		"grass_dry": Color(0.50, 0.48, 0.22),
		"dirt_color": Color(0.31, 0.24, 0.14),
		"stone_color": Color(0.40, 0.40, 0.37),
		"crest_color": Color(0.47, 0.46, 0.42),
"accent_color": Color(1.00, 0.86, 0.45),
			"accent_strength": 0.22, "realm_tint": Color(0.76, 0.98, 0.82),
			"realm_tint_strength": 0.22, "moisture_strength": 0.28,
			"moss_color": Color(0.28, 0.72, 0.40), "moss_strength": 0.58,
			"terrain_brightness": 1.52, "uv_world_scale": 0.30, "tex_gain": 1.9,
	},
	"mistfen": {
		"grass_color": Color(0.18, 0.32, 0.26),
		"grass_dry": Color(0.30, 0.38, 0.34),
		"dirt_color": Color(0.16, 0.21, 0.24),
		"stone_color": Color(0.30, 0.34, 0.36),
		"crest_color": Color(0.36, 0.41, 0.43),
		"dirt_amount": 0.6,
"accent_color": Color(0.55, 0.85, 1.00),
			"accent_strength": 0.28, "realm_tint": Color(0.54, 0.78, 0.82),
			"realm_tint_strength": 0.30, "moisture_strength": 0.86,
			"moss_color": Color(0.22, 0.62, 0.58), "moss_strength": 0.48,
			"terrain_brightness": 1.38, "uv_world_scale": 0.33, "tex_gain": 2.0,
	},
	"heartwood": {
		"grass_color": Color(0.36, 0.28, 0.16),
		"grass_dry": Color(0.52, 0.36, 0.16),
		"dirt_color": Color(0.23, 0.15, 0.09),
		"stone_color": Color(0.30, 0.26, 0.24),
		"crest_color": Color(0.38, 0.31, 0.26),
"accent_color": Color(1.00, 0.45, 0.12),
			"accent_strength": 0.50, "realm_tint": Color(1.0, 0.62, 0.34),
			"realm_tint_strength": 0.20, "moisture_strength": 0.08,
			"moss_color": Color(0.48, 0.20, 0.08), "moss_strength": 0.22,
			"terrain_brightness": 1.48, "uv_world_scale": 0.31, "tex_gain": 1.8,
	},
	"moonfen": {
		"grass_color": Color(0.28, 0.22, 0.42),
		"grass_dry": Color(0.36, 0.28, 0.48),
		"dirt_color": Color(0.13, 0.10, 0.22),
		"stone_color": Color(0.22, 0.20, 0.30),
		"crest_color": Color(0.28, 0.25, 0.38),
"accent_color": Color(0.45, 0.72, 1.00),
			"accent_strength": 0.55, "realm_tint": Color(0.58, 0.46, 1.0),
			"realm_tint_strength": 0.34, "moisture_strength": 0.42,
			"moss_color": Color(0.30, 0.22, 0.62), "moss_strength": 0.34,
			"terrain_brightness": 1.42, "uv_world_scale": 0.32, "tex_gain": 1.9,
	},
}

@onready var terrain_mesh: MeshInstance3D = $TerrainMesh

## POM tiers: LOW off, MEDIUM single-step offset, HIGH short 4-step march.
const POM_BY_LEVEL := [0, 1, 2]

func _ready() -> void:
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

## Realm material from assets/materials/terrain_<realm>.tres (binds the
## stylized PBR layer sets); falls back to a bare shader material so the
## palette override below still produces valid ground.
func _load_realm_material() -> ShaderMaterial:
	var realm := _realm_id()
	for path in ["res://assets/materials/terrain_%s.tres" % realm,
			"res://assets/materials/terrain_bramblewood.tres"]:
		if ResourceLoader.exists(path):
			var mat := load(path) as ShaderMaterial
			if mat != null:
				return mat
	var ground := ShaderMaterial.new()
	ground.shader = load("res://assets/shaders/terrain_ground.gdshader")
	return ground

func _apply_palette(ground: ShaderMaterial) -> void:
	var pal: Dictionary = REALM_TERRAIN.get(_realm_id(),
		REALM_TERRAIN["bramblewood"])
	for key in ["grass_color", "grass_dry", "dirt_color", "stone_color",
			"crest_color"]:
		if pal.has(key):
			ground.set_shader_parameter(key, pal[key])
	if pal.has("dirt_amount"):
		ground.set_shader_parameter("dirt_amount", pal["dirt_amount"])
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

func _on_quality_level(level: int) -> void:
	var ground := terrain_mesh.material_override as ShaderMaterial
	if ground == null or not ground.shader:
		return
	var idx := clampi(level, 0, POM_BY_LEVEL.size() - 1)
	ground.set_shader_parameter("pom_mode", POM_BY_LEVEL[idx])

## Realm id for this map: biome scenes carry biome_id; Moonfen's manager
## doesn't, so fall back to the current travel realm.
func _realm_id() -> String:
	var gs := get_node_or_null("/root/GameState")
	var active_realm := str(gs.get("current_realm")) if gs != null else ""
	# Whispergrove and Bramblewood intentionally share grove.tscn. Preserve
	# the active travel identity instead of letting the scene's bramblewood
	# biome_id erase Whispergrove's softer visual profile.
	if active_realm == "whispergrove":
		return active_realm
	var world_root := get_parent()
	if world_root != null and "biome_id" in world_root:
		return str(world_root.get("biome_id"))
	if gs != null:
		return active_realm
	return "bramblewood"

func height_at(x: float, z: float) -> float:
	# Keep rendered terrain and ConcavePolygonShape3D perfectly flat so no
	# character, enemy, or camera can climb/fall through an authored hill.
	return 0.0
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
	return _flatten_points

func _build_mesh() -> ArrayMesh:
	var n := clampi(subdivisions, 32, 254)
	var step := HALF_EXTENT * 2.0 / float(n)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize((n + 1) * (n + 1))
	normals.resize((n + 1) * (n + 1))

	var e := step * 0.5
	for j in n + 1:
		for i in n + 1:
			var x := -HALF_EXTENT + i * step
			var z := -HALF_EXTENT + j * step
			var idx := j * (n + 1) + i
			verts[idx] = Vector3(x, height_at(x, z), z)
			var dhx := (height_at(x + e, z) - height_at(x - e, z)) / step
			var dhz := (height_at(x, z + e) - height_at(x, z - e)) / step
			normals[idx] = Vector3(-dhx, 1.0, -dhz).normalized()

	var inds := PackedInt32Array()
	inds.resize(n * n * 6)
	var k := 0
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := (j + 1) * (n + 1) + i + 1
			var d := (j + 1) * (n + 1) + i
			inds[k] = a; inds[k + 1] = c; inds[k + 2] = b
			inds[k + 3] = a; inds[k + 4] = d; inds[k + 5] = c
			k += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = inds

	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.custom_aabb = AABB(Vector3(-302.0, -5.0, -302.0), Vector3(620.0, 20.0, 620.0))
	return am

## Builds a coarse concave trimesh from the heightfield so the hero and
## enemies actually walk up and down the hills (relief mesh alone is
## visual-only). The flat editor plane is removed so it can't shadow
## the relief in dips. Resolution is half the visual mesh for mobile.
func _build_heightfield_collision() -> void:
	var body := terrain_mesh.get_parent() as StaticBody3D
	if body == null or not is_inside_tree():
		return
	# Drop the legacy flat plane (grove.tscn / moonfen.tscn default child).
	for child in body.get_children():
		if child is CollisionShape3D:
			child.queue_free()

	# Collision does not need visual-grid density on this flat terrain.
	const GRID := 128
	var cell := (HALF_EXTENT * 2.0) / float(GRID)
	var faces := PackedVector3Array()
	faces.resize(GRID * GRID * 6)
	var k := 0
	for j in GRID:
		for i in GRID:
			var x0 := -HALF_EXTENT + i * cell
			var z0 := -HALF_EXTENT + j * cell
			var x1 := x0 + cell
			var z1 := z0 + cell
			var a := Vector3(x0, height_at(x0, z0), z0)
			var b := Vector3(x1, height_at(x1, z0), z0)
			var c := Vector3(x1, height_at(x1, z1), z1)
			var d := Vector3(x0, height_at(x0, z1), z1)
			faces[k] = a; faces[k + 1] = c; faces[k + 2] = b
			faces[k + 3] = a; faces[k + 4] = d; faces[k + 5] = c
			k += 6
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
