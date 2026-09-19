extends RefCounted
class_name StructureCatalog

## === StructureCatalog — enterable structures, data first ===
## One table drives both the exterior that stands in the realm and the interior
## the player walks into, so a new castle, mushroom house or pyramid is a data
## entry rather than another scene. Gameplay (rooms, spawns, boss, claim) lives
## here; only presentation differs between kinds.
##
## Every entry is keyed by structure id and declares:
##   name       display name, also the Label3D nameplate
##   kind       castle | mushroom_house | pyramid — selects the exterior shape
##   realm      realm id whose surface carries this structure
##   approach   world position of the door on the realm surface
##   tagline    short verb shown under the nameplate (DESCEND, ENTER, BREAK SEAL)
##   palette    wall/floor/accent colors for the interior
##   spawn      player entry offset, relative to the interior origin
##   rooms      floor plan; each room is a platform plus walls with doorways
##   lights     per-room lighting; the color is what makes a level read as its own
##   mobs       guard spawns with an archetype from the shared enemy roster
##   boss       the structure's own boss hall (id, def_id, model, room, offset)
##   claim      GameState.quest_reward_claims key written on completion
##   activity   activity-log line recorded on completion
##   builder    authored (keep the hand-built Embervault) | generated (this file)
##
## Room layout contract:
##   offset     room centre in interior space; side rooms sit off the main axis
##              so the plan reads as halls you walk around, not one corridor
##   doors      wall openings, any of fwd (-z) / back (+z) / left (-x) / right (+x)
##   kind       hall | chamber | stairs | vault | boss — decides dressing and
##              which rooms hold which mob groups
##   A stairs room has no floor of its own: its flight bridges the previous
##   room's floor to its own, so the two levels are genuinely joined.

const KIND_CASTLE := "castle"
const KIND_MUSHROOM_HOUSE := "mushroom_house"
const KIND_PYRAMID := "pyramid"

## Room kinds decide how a room is dressed:
##   hall     open platform, braziers and banners
##   chamber  smaller platform with crates, tables and pillars
##   stairs   stepped ramp connecting two heights
##   vault    end room holding the reward chest
##   boss     dedicated boss hall with a dais
const ROOM_HALL := "hall"
const ROOM_CHAMBER := "chamber"
const ROOM_STAIRS := "stairs"
const ROOM_VAULT := "vault"
const ROOM_BOSS := "boss"

const STRUCTURES: Dictionary = {
	"embervault": {
		"name": "EMBERVAULT",
		"kind": KIND_CASTLE,
		"realm": "heartwood",
		"approach": Vector3(80.0, 0.3, 6.0),
		"tagline": "DESCEND",
		"builder": "authored",
		"claim": "dungeon_embervault_complete",
		"activity": "DUNGEON COMPLETE · EMBERVAULT",
	},
	"bramble_keep": {
		"name": "BRAMBLE KEEP",
		"kind": KIND_CASTLE,
		"realm": "bramblewood",
		"approach": Vector3(34.0, 0.0, -28.0),
		"tagline": "ENTER THE KEEP",
		"builder": "generated",
		"claim": "dungeon_bramble_keep_complete",
		"activity": "STRUCTURE CLEARED · BRAMBLE KEEP",
		"quest": "The keep's garrison never left. Clear the hall, the armory and the chapel, climb the stair, and break the warden's seal.",
		"palette": {
			"wall": Color(0.26, 0.23, 0.22),
			"floor": Color(0.19, 0.17, 0.16),
			"accent": Color(0.85, 0.42, 0.20),
		},
		"wall_texture": "rock_face",
		"floor_texture": "wood_floor_worn",
		"spawn": Vector3(0.0, 0.2, 8.0),
		"rooms": [
			{"name": "Garrison Hall", "offset": Vector3(0.0, 0.0, 0.0),
				"size": Vector3(22.0, 3.4, 18.0), "kind": ROOM_HALL,
				"doors": ["fwd", "left", "right"]},
			{"name": "Armory", "offset": Vector3(-16.5, 0.0, 0.0),
				"size": Vector3(10.0, 3.4, 12.0), "kind": ROOM_CHAMBER,
				"doors": ["right"]},
			{"name": "Chapel", "offset": Vector3(16.5, 0.0, 0.0),
				"size": Vector3(10.0, 3.4, 12.0), "kind": ROOM_CHAMBER,
				"doors": ["left"]},
			{"name": "North Stair", "offset": Vector3(0.0, 3.4, -14.5),
				"size": Vector3(8.0, 3.4, 10.0), "kind": ROOM_STAIRS,
				"doors": ["back", "fwd"]},
			{"name": "Upper Gallery", "offset": Vector3(0.0, 3.4, -26.0),
				"size": Vector3(20.0, 3.4, 12.0), "kind": ROOM_HALL,
				"doors": ["back", "fwd", "left", "right"]},
			{"name": "Barracks", "offset": Vector3(-15.5, 3.4, -26.0),
				"size": Vector3(10.0, 3.4, 10.0), "kind": ROOM_CHAMBER,
				"doors": ["right"]},
			{"name": "Mess Hall", "offset": Vector3(15.5, 3.4, -26.0),
				"size": Vector3(10.0, 3.4, 10.0), "kind": ROOM_CHAMBER,
				"doors": ["left"]},
			{"name": "Warden's Vault", "offset": Vector3(0.0, 3.4, -40.0),
				"size": Vector3(18.0, 3.6, 14.0), "kind": ROOM_BOSS,
				"doors": ["back"]},
		],
		"lights": [
			{"room": 0, "offset": Vector3(-7.0, 2.4, -6.0), "color": Color(1.0, 0.52, 0.22),
				"energy": 1.5, "range": 12.0},
			{"room": 0, "offset": Vector3(7.0, 2.4, 6.0), "color": Color(1.0, 0.52, 0.22),
				"energy": 1.5, "range": 12.0},
			{"room": 1, "offset": Vector3(0.0, 2.0, 0.0), "color": Color(0.86, 0.56, 0.24),
				"energy": 1.1, "range": 9.0},
			{"room": 2, "offset": Vector3(0.0, 2.0, 0.0), "color": Color(0.44, 0.58, 0.92),
				"energy": 1.1, "range": 9.0},
			{"room": 3, "offset": Vector3(0.0, 1.6, 0.0), "color": Color(0.42, 0.50, 0.72),
				"energy": 0.9, "range": 10.0},
			{"room": 4, "offset": Vector3(-6.0, 2.2, 0.0), "color": Color(1.0, 0.58, 0.26),
				"energy": 1.3, "range": 11.0},
			{"room": 4, "offset": Vector3(6.0, 2.2, 0.0), "color": Color(1.0, 0.58, 0.26),
				"energy": 1.3, "range": 11.0},
			{"room": 5, "offset": Vector3(0.0, 1.8, 0.0), "color": Color(0.70, 0.46, 0.24),
				"energy": 0.8, "range": 8.0},
			{"room": 6, "offset": Vector3(0.0, 1.8, 0.0), "color": Color(0.70, 0.46, 0.24),
				"energy": 0.8, "range": 8.0},
			{"room": 7, "offset": Vector3(0.0, 2.6, 0.0), "color": Color(1.0, 0.36, 0.16),
				"energy": 1.9, "range": 15.0, "shadow": true},
		],
		"mobs": [
			{"archetype": "charger", "room": 0, "offset": Vector3(-5.0, 0.0, 2.0)},
			{"archetype": "thorn_charger", "room": 0, "offset": Vector3(5.0, 0.0, 2.0)},
			{"archetype": "ambusher", "room": 0, "offset": Vector3(0.0, 0.0, -4.0)},
			{"archetype": "thorn_charger", "room": 1, "offset": Vector3(-2.0, 0.0, -2.0)},
			{"archetype": "thorn_charger", "room": 1, "offset": Vector3(2.0, 0.0, 2.0)},
			{"archetype": "ambusher", "room": 2, "offset": Vector3(-2.0, 0.0, -2.0)},
			{"archetype": "ambusher", "room": 2, "offset": Vector3(2.0, 0.0, 2.0)},
			{"archetype": "charger", "room": 4, "offset": Vector3(-5.0, 0.0, 0.0)},
			{"archetype": "thorn_charger", "room": 4, "offset": Vector3(5.0, 0.0, 0.0)},
			{"archetype": "charger", "room": 5, "offset": Vector3(0.0, 0.0, 0.0)},
			{"archetype": "ambusher", "room": 6, "offset": Vector3(0.0, 0.0, 0.0)},
		],
		"boss": {"id": "bramble_keep_warden", "def_id": "bramble_keep_warden",
			"model_profile": "boss_keep_warden", "model_height": 4.4,
			"room": 7, "offset": Vector3(0.0, 0.0, -2.0)},
	},
	"hollowroot_house": {
		"name": "HOLLOWROOT HOUSE",
		"kind": KIND_MUSHROOM_HOUSE,
		"realm": "whispergrove",
		"approach": Vector3(-34.0, 0.0, 30.0),
		"tagline": "DUCK INSIDE",
		"builder": "generated",
		"claim": "dungeon_hollowroot_house_complete",
		"activity": "STRUCTURE CLEARED · HOLLOWROOT HOUSE",
		"quest": "Something took the hollow root. Clear the burrow, the cellar and the spore nook, then face what nests above.",
		"palette": {
			"wall": Color(0.30, 0.34, 0.27),
			"floor": Color(0.21, 0.25, 0.19),
			"accent": Color(0.52, 0.86, 0.46),
		},
		"wall_texture": "rock_face",
		"floor_texture": "grass_ground",
		"spawn": Vector3(0.0, 0.2, 5.0),
		"rooms": [
			{"name": "Entry Burrow", "offset": Vector3(0.0, 0.0, 0.0),
				"size": Vector3(12.0, 2.6, 11.0), "kind": ROOM_HALL,
				"doors": ["fwd", "left", "right"]},
			{"name": "Root Cellar", "offset": Vector3(-10.5, 0.0, 0.0),
				"size": Vector3(8.0, 2.6, 9.0), "kind": ROOM_CHAMBER,
				"doors": ["right"]},
			{"name": "Spore Nook", "offset": Vector3(10.5, 0.0, 0.0),
				"size": Vector3(8.0, 2.6, 9.0), "kind": ROOM_CHAMBER,
				"doors": ["left"]},
			{"name": "Spore Stair", "offset": Vector3(0.0, 2.6, -10.5),
				"size": Vector3(7.0, 2.6, 9.0), "kind": ROOM_STAIRS,
				"doors": ["back", "fwd"]},
			{"name": "Matron's Nook", "offset": Vector3(0.0, 2.6, -22.0),
				"size": Vector3(14.0, 2.8, 12.0), "kind": ROOM_BOSS,
				"doors": ["back"]},
		],
		"lights": [
			{"room": 0, "offset": Vector3(0.0, 2.0, 0.0), "color": Color(0.62, 0.94, 0.58),
				"energy": 1.2, "range": 10.0},
			{"room": 1, "offset": Vector3(0.0, 1.8, 0.0), "color": Color(0.42, 0.72, 0.86),
				"energy": 0.9, "range": 8.0},
			{"room": 2, "offset": Vector3(0.0, 1.8, 0.0), "color": Color(0.66, 0.94, 0.50),
				"energy": 0.9, "range": 8.0},
			{"room": 3, "offset": Vector3(0.0, 1.6, 0.0), "color": Color(0.42, 0.72, 0.86),
				"energy": 1.0, "range": 9.0},
			{"room": 4, "offset": Vector3(0.0, 2.1, 0.0), "color": Color(0.78, 0.58, 0.92),
				"energy": 1.5, "range": 12.0, "shadow": true},
		],
		"mobs": [
			{"archetype": "spore_weaver", "room": 0, "offset": Vector3(-3.5, 0.0, -2.0)},
			{"archetype": "relic_leech", "room": 1, "offset": Vector3(0.0, 0.0, 0.0)},
			{"archetype": "spore_weaver", "room": 2, "offset": Vector3(0.0, 0.0, 0.0)},
			{"archetype": "relic_leech", "room": 3, "offset": Vector3(0.0, 0.0, -3.0)},
		],
		"boss": {"id": "hollowroot_matron", "def_id": "hollowroot_matron",
			"model_profile": "boss_hollowroot_matron", "model_height": 3.2,
			"room": 4, "offset": Vector3(0.0, 0.0, -3.0)},
	},
	"sunken_step_pyramid": {
		"name": "SUNKEN STEP PYRAMID",
		"kind": KIND_PYRAMID,
		"realm": "moonfen",
		"approach": Vector3(48.0, 0.0, -40.0),
		"tagline": "BREAK THE SEAL",
		"builder": "generated",
		"claim": "dungeon_sunken_step_pyramid_complete",
		"activity": "STRUCTURE CLEARED · SUNKEN STEP PYRAMID",
		"quest": "The steps go down further than the fen is deep. Search the burial chambers, then break the seal at the bottom.",
		"palette": {
			"wall": Color(0.31, 0.30, 0.34),
			"floor": Color(0.20, 0.21, 0.26),
			"accent": Color(0.62, 0.72, 1.0),
		},
		"wall_texture": "cobblestone_floor_05",
		"floor_texture": "cobblestone_floor_05",
		"spawn": Vector3(0.0, 0.2, 6.0),
		"rooms": [
			{"name": "Descending Mouth", "offset": Vector3(0.0, 0.0, 0.0),
				"size": Vector3(16.0, 3.0, 13.0), "kind": ROOM_HALL,
				"doors": ["fwd", "left", "right"]},
			{"name": "West Burial", "offset": Vector3(-12.5, 0.0, 0.0),
				"size": Vector3(8.0, 3.0, 9.0), "kind": ROOM_CHAMBER,
				"doors": ["right"]},
			{"name": "East Burial", "offset": Vector3(12.5, 0.0, 0.0),
				"size": Vector3(8.0, 3.0, 9.0), "kind": ROOM_CHAMBER,
				"doors": ["left"]},
			{"name": "Second Descent", "offset": Vector3(0.0, -3.0, -12.5),
				"size": Vector3(9.0, 3.0, 10.0), "kind": ROOM_STAIRS,
				"doors": ["back", "fwd"]},
			{"name": "Flooded Gallery", "offset": Vector3(0.0, -3.0, -25.5),
				"size": Vector3(20.0, 3.2, 14.0), "kind": ROOM_HALL,
				"doors": ["back", "fwd", "left", "right"]},
			{"name": "Drowned Vestry", "offset": Vector3(-14.5, -3.0, -25.5),
				"size": Vector3(8.0, 3.2, 9.0), "kind": ROOM_CHAMBER,
				"doors": ["right"]},
			{"name": "Sun Vestry", "offset": Vector3(14.5, -3.0, -25.5),
				"size": Vector3(8.0, 3.2, 9.0), "kind": ROOM_CHAMBER,
				"doors": ["left"]},
			{"name": "Third Descent", "offset": Vector3(0.0, -6.0, -38.0),
				"size": Vector3(8.0, 3.0, 10.0), "kind": ROOM_STAIRS,
				"doors": ["back", "fwd"]},
			{"name": "Sealed Vault", "offset": Vector3(0.0, -6.0, -51.5),
				"size": Vector3(18.0, 3.6, 16.0), "kind": ROOM_BOSS,
				"doors": ["back"]},
		],
		"lights": [
			{"room": 0, "offset": Vector3(0.0, 2.2, 0.0), "color": Color(1.0, 0.78, 0.42),
				"energy": 1.3, "range": 12.0},
			{"room": 1, "offset": Vector3(0.0, 1.8, 0.0), "color": Color(0.44, 0.62, 0.86),
				"energy": 0.8, "range": 8.0},
			{"room": 2, "offset": Vector3(0.0, 1.8, 0.0), "color": Color(0.52, 0.70, 0.94),
				"energy": 0.8, "range": 8.0},
			{"room": 3, "offset": Vector3(0.0, 1.8, 0.0), "color": Color(0.40, 0.62, 0.86),
				"energy": 0.8, "range": 9.0},
			{"room": 4, "offset": Vector3(-6.0, 2.0, 0.0), "color": Color(0.34, 0.78, 0.82),
				"energy": 1.1, "range": 11.0},
			{"room": 4, "offset": Vector3(6.0, 2.0, 0.0), "color": Color(0.34, 0.78, 0.82),
				"energy": 1.1, "range": 11.0},
			{"room": 5, "offset": Vector3(0.0, 1.8, 0.0), "color": Color(0.36, 0.70, 0.80),
				"energy": 0.8, "range": 8.0},
			{"room": 6, "offset": Vector3(0.0, 1.8, 0.0), "color": Color(0.62, 0.74, 0.98),
				"energy": 0.8, "range": 8.0},
			{"room": 7, "offset": Vector3(0.0, 1.8, 0.0), "color": Color(0.52, 0.44, 0.92),
				"energy": 0.9, "range": 9.0},
			{"room": 8, "offset": Vector3(0.0, 2.4, 0.0), "color": Color(0.72, 0.62, 1.0),
				"energy": 2.0, "range": 16.0, "shadow": true},
		],
		"mobs": [
			{"archetype": "mire_stalker", "room": 0, "offset": Vector3(-4.0, 0.0, -2.0)},
			{"archetype": "relic_leech", "room": 1, "offset": Vector3(0.0, 0.0, 0.0)},
			{"archetype": "fenling", "room": 2, "offset": Vector3(0.0, 0.0, 0.0)},
			{"archetype": "mire_stalker", "room": 4, "offset": Vector3(-5.0, 0.0, 1.0)},
			{"archetype": "fenling", "room": 4, "offset": Vector3(5.0, 0.0, 1.0)},
			{"archetype": "relic_leech", "room": 5, "offset": Vector3(0.0, 0.0, 0.0)},
			{"archetype": "fenling", "room": 6, "offset": Vector3(0.0, 0.0, 0.0)},
			{"archetype": "relic_leech", "room": 7, "offset": Vector3(0.0, 0.0, -3.0)},
		],
		"boss": {"id": "pyramid_sealed_one", "def_id": "pyramid_sealed_one",
			"model_profile": "boss_pyramid_sealed_one", "model_height": 5.0,
			"room": 8, "offset": Vector3(0.0, 0.0, -3.5)},
	},
}

## Every structure, ordered so the first vertical-slice entry stays first.
static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in STRUCTURES:
		out.append(get_structure(str(id)))
	return out

## Every structure that stands on one realm's surface.
static func for_realm(realm_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in all():
		if str(entry.get("realm", "")) == realm_id:
			out.append(entry)
	return out

static func get_structure(structure_id: String) -> Dictionary:
	var entry: Dictionary = STRUCTURES.get(structure_id, {})
	if entry.is_empty():
		return {}
	var copy := entry.duplicate(true)
	copy["id"] = structure_id
	return copy

static func has(structure_id: String) -> bool:
	return STRUCTURES.has(structure_id)

## The reward-claim key for a structure, so completion is claimed exactly once
## even across death, reload and realm travel.
static func claim_key(structure_id: String) -> String:
	return str(get_structure(structure_id).get("claim", "dungeon_%s_complete" % structure_id))

## Absolute world position of a room inside a structure interior.
static func room_origin(entry: Dictionary, room_index: int) -> Vector3:
	var rooms: Array = entry.get("rooms", [])
	if room_index < 0 or room_index >= rooms.size():
		return Vector3.ZERO
	return (rooms[room_index] as Dictionary).get("offset", Vector3.ZERO)

## Absolute world position of a data-declared spawn (mob, light, boss).
static func spawn_position(entry: Dictionary, spawn: Dictionary) -> Vector3:
	var index := int(spawn.get("room", 0))
	return room_origin(entry, index) + (spawn.get("offset", Vector3.ZERO) as Vector3)

## The wall openings for a room: explicit `doors` when authored, otherwise the
## linear-plan default (entry opens forward, the last room opens back, middle
## rooms open both ways). Returns a set of fwd/back/left/right keys.
static func room_doors(entry: Dictionary, room_index: int) -> Dictionary:
	var rooms: Array = entry.get("rooms", [])
	if room_index < 0 or room_index >= rooms.size():
		return {}
	var room: Dictionary = rooms[room_index]
	if room.has("doors"):
		var explicit: Dictionary = {}
		for door in (room.get("doors", []) as Array):
			explicit[str(door)] = true
		return explicit
	var out: Dictionary = {}
	if room_index > 0:
		out["back"] = true
	if room_index < rooms.size() - 1:
		out["fwd"] = true
	return out
