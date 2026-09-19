extends RefCounted
class_name StructureSurfaces

## === StructureSurfaces — CC0 1K PBR materials for structure geometry ===
## The kit models carry their own atlases; this library textures the geometry
## they cannot cover: interior slabs, the pyramid's tiers, the mushroom's cap
## and stem, the castle's merlons.
##
## Families are Poly Haven CC0 1.0 sets under assets/textures/cc0/ (each ships
## its own SOURCE.txt with the asset URL and download date). Triplanar mapping
## keeps texel density stable on boxes of any size, which is what a module kit
## needs — no per-slab UV authoring, and swapping a family never moves
## collision.

const ROOT := "res://assets/textures/cc0/"

## Logical role -> Poly Haven set. Roles keep call sites readable and let a set
## be swapped in one place.
const STONE := "cobblestone_floor_05"
const ROCK := "rock_face"
const WOOD := "wood_floor_worn"
const GRASS := "grass_ground"
const THATCH := "thatch_roof_angled"

static var _cache: Dictionary = {}

## A textured material for one role. `tint` multiplies the albedo so palettes
## still differentiate realms; `metres` is the world size of one repeat.
## Returns null when the family is unknown or its albedo is missing, so callers
## can keep their flat-colour fallback.
static func material(role: String, tint := Color.WHITE, metres := 4.0) -> StandardMaterial3D:
	var family := str(role)
	if family.is_empty():
		return null
	var key := "%s|%s|%.2f" % [family, str(tint), metres]
	if _cache.has(key):
		return _cache.get(key) as StandardMaterial3D
	var albedo := load(ROOT + family + "/albedo.jpg") as Texture2D
	if albedo == null:
		return null
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = albedo
	mat.albedo_color = tint
	var normal := load(ROOT + family + "/normal.jpg") as Texture2D
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
	var roughness := load(ROOT + family + "/roughness.jpg") as Texture2D
	if roughness != null:
		mat.roughness_texture = roughness
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / maxf(metres, 0.5)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = mat
	return mat

## A role tinted toward a palette colour without crushing the albedo: the flat
## palette colours are interior-dark, and multiplying them straight over a
## texture would hide it.
static func tinted(role: String, palette_color: Color, metres := 4.0) -> StandardMaterial3D:
	return material(role, Color.WHITE.lerp(palette_color, 0.45), metres)
