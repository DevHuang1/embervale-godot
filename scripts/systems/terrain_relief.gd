extends Node3D
class_name TerrainRelief

## === Terrain Relief ===
## Runtime heightmapped ground: replaces the flat PlaneMesh with a
## ridged ArrayMesh, rolling interior swells, and flattened gameplay
## zones around every landmark. Faithful to the layout (paths, quest
## nodes, gates) so collision and quest ranges are unaffected.

@export var subdivisions: int = 128
@export var ridge_amplitude: float = 1.35
@export var roll_amplitude: float = 0.4
@export var carve_amplitude: float = 0.95
@export var flatten_radius: float = 7.0

const HALF_EXTENT: float = 76.0
const MAX_CREST: float = 0.6

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
]

## Per-realm ground palettes for terrain_ground.gdshader. Every explorable
## realm gets a distinct underfoot read: grass/dirt/stone families plus a
## glowing accent fleck (ember, fen-light, moonmoss). Moonfen values echo
## the violet terrain_moonfen.tres it can no longer see (relief overrides
## the scene material at runtime).
const REALM_TERRAIN := {
	"bramblewood": {
		"grass_color": Color(0.19, 0.30, 0.13),
		"grass_dry": Color(0.36, 0.38, 0.15),
		"dirt_color": Color(0.30, 0.22, 0.13),
		"stone_color": Color(0.38, 0.38, 0.35),
		"crest_color": Color(0.45, 0.44, 0.40),
		"accent_color": Color(0.96, 0.72, 0.29),
		"accent_strength": 0.35,
	},
	"whispergrove": {
		"grass_color": Color(0.21, 0.32, 0.15),
		"grass_dry": Color(0.39, 0.40, 0.18),
		"dirt_color": Color(0.31, 0.24, 0.14),
		"stone_color": Color(0.40, 0.40, 0.37),
		"crest_color": Color(0.47, 0.46, 0.42),
		"accent_color": Color(1.00, 0.86, 0.45),
		"accent_strength": 0.22,
	},
	"mistfen": {
		"grass_color": Color(0.12, 0.20, 0.17),
		"grass_dry": Color(0.22, 0.29, 0.26),
		"dirt_color": Color(0.16, 0.21, 0.24),
		"stone_color": Color(0.30, 0.34, 0.36),
		"crest_color": Color(0.36, 0.41, 0.43),
		"dirt_amount": 0.6,
		"accent_color": Color(0.55, 0.85, 1.00),
		"accent_strength": 0.28,
	},
	"heartwood": {
		"grass_color": Color(0.26, 0.19, 0.10),
		"grass_dry": Color(0.42, 0.27, 0.11),
		"dirt_color": Color(0.23, 0.15, 0.09),
		"stone_color": Color(0.30, 0.26, 0.24),
		"crest_color": Color(0.38, 0.31, 0.26),
		"accent_color": Color(1.00, 0.45, 0.12),
		"accent_strength": 0.50,
	},
	"moonfen": {
		"grass_color": Color(0.20, 0.15, 0.30),
		"grass_dry": Color(0.28, 0.20, 0.38),
		"dirt_color": Color(0.13, 0.10, 0.22),
		"stone_color": Color(0.22, 0.20, 0.30),
		"crest_color": Color(0.28, 0.25, 0.38),
		"accent_color": Color(0.45, 0.72, 1.00),
		"accent_strength": 0.55,
	},
}

@onready var terrain_mesh: MeshInstance3D = $TerrainMesh

## POM tiers: LOW off, MEDIUM single-step offset, HIGH full 8-step march.
const POM_BY_LEVEL := [0, 1, 2]

func _ready() -> void:
	terrain_mesh.mesh = _build_mesh()
	terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var ground := _load_realm_material()
	_apply_palette(ground)
	terrain_mesh.material_override = ground
	var qs := get_node_or_null("/root/WorldState/QualityScaler")
	if qs != null and qs.has_signal("level_changed"):
		qs.level_changed.connect(_on_quality_level)
		_on_quality_level(qs.level)

## Realm material from assets/materials/terrain_<realm>.tres (binds the
## scanned PBR layer sets); falls back to a bare shader material so the
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
	ground.set_shader_parameter("accent_color",
		pal.get("accent_color", Color(0.96, 0.72, 0.29)))
	ground.set_shader_parameter("accent_strength",
		float(pal.get("accent_strength", 0.0)))

func _on_quality_level(level: int) -> void:
	var ground := terrain_mesh.material_override as ShaderMaterial
	if ground == null or not ground.shader:
		return
	var idx := clampi(level, 0, POM_BY_LEVEL.size() - 1)
	ground.set_shader_parameter("pom_mode", POM_BY_LEVEL[idx])

## Realm id for this map: biome scenes carry biome_id; Moonfen's manager
## doesn't, so fall back to the current travel realm.
func _realm_id() -> String:
	var world_root := get_parent()
	if world_root != null and "biome_id" in world_root:
		return str(world_root.get("biome_id"))
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		return str(gs.get("current_realm"))
	return "bramblewood"

func height_at(x: float, z: float) -> float:
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

	# Flatten around gameplay landmarks
	h *= _flatten_mask(p)

	# Keep crests low so the flat collision plane never hides the hero
	return clampf(h, -1.2, MAX_CREST)

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
	var n := subdivisions
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
	am.custom_aabb = AABB(Vector3(-78.0, -5.0, -78.0), Vector3(156.0, 16.0, 156.0))
	return am

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