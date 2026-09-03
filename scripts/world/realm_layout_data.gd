extends RefCounted
class_name RealmLayoutData

## Hand-authored gameplay routes for the five realms. Coordinates are kept in
## world-local space so inherited realm scenes can share systems without
## sharing the same exploration flow.

const PROFILES := {
	"whispergrove": {
		"route": [Vector3(0, 0, 2), Vector3(-7, 0, -7), Vector3(4, 0, -15), Vector3(15, 0, -10), Vector3(18, 0, 2)],
		"checkpoint": Vector3(-5, 0.35, -5),
		"arena": Vector3(16, 0.1, -10),
		"cave": Vector3(18, 0.7, 3),
		"dungeon_name": "ROOTWARD HOLLOW",
"chests": [
		{"id": "whisper_moss_cache", "pos": Vector3(-12, 0.48, -9), "label": "MOSSKEEPER CACHE", "rarity": 2, "type": "instant"},
		{"id": "whisper_shrine_cache", "pos": Vector3(8, 0.48, -18), "label": "SHRINE OFFERING", "rarity": 2, "type": "instant"},
		{"id": "whisper_hidden_cache", "pos": Vector3(20, 0.48, -4), "label": "HIDDEN ROOT CACHE", "rarity": 3, "type": "instant"},
	],
		"enemies": ["hushling", "spitter", "elite_hushling"],
		"resources": [
			{"id": "moss_fiber", "pos": Vector3(-8, 0, -8), "yield": 3},
			{"id": "bramble_wood", "pos": Vector3(5, 0, -16), "yield": 2},
			{"id": "iron_shard", "pos": Vector3(16, 0, -7), "yield": 2},
		],
		"encounters": [
			{"scene": "spore_weaver", "pos": Vector3(5, 0.2, -13)},
			{"scene": "relic_leech", "pos": Vector3(17, 0.2, -6)},
		],
	},
	"bramblewood": {
		"route": [Vector3(0, 0, 2), Vector3(9, 0, -5), Vector3(14, 0, -16), Vector3(2, 0, -24), Vector3(-14, 0, -19)],
		"checkpoint": Vector3(7, 0.35, -4),
		"arena": Vector3(-14, 0.1, -19),
		"cave": Vector3(16, 0.7, -17),
		"dungeon_name": "THORN-SUNK BURROW",
		"chests": [
			{"id": "mountain_cache", "pos": Vector3(13, 0.48, -10), "label": "THORNBOUND CACHE", "rarity": 2, "type": "instant"},
			{"id": "root_cache", "pos": Vector3(1, 0.48, -26), "label": "AMBUSH SPOILS", "rarity": 2, "type": "instant"},
			{"id": "bramble_elite_cache", "pos": Vector3(-17, 0.48, -14), "label": "ALPHA'S HOARD", "rarity": 3, "type": "boss_gated", "boss_key": "biome_thornhide_alpha"},
		],
		"enemies": ["elite_hushling", "hushling", "spitter"],
		"resources": [
			{"id": "bramble_wood", "pos": Vector3(10, 0, -8), "yield": 3},
			{"id": "beast_hide", "pos": Vector3(3, 0, -23), "yield": 2},
			{"id": "iron_shard", "pos": Vector3(-13, 0, -16), "yield": 3},
		],
		"encounters": [
			{"scene": "thorn_charger", "pos": Vector3(12, 0.2, -14)},
			{"scene": "spore_weaver", "pos": Vector3(-11, 0.2, -18)},
		],
	},
	"mistfen": {
		"route": [Vector3(0, 0, 2), Vector3(-8, 0, -4), Vector3(-15, 0, -14), Vector3(-5, 0, -24), Vector3(10, 0, -20), Vector3(18, 0, -9)],
		"checkpoint": Vector3(-7, 0.35, -3),
		"arena": Vector3(18, 0.1, -9),
		"cave": Vector3(-7, 0.7, -25),
		"dungeon_name": "DROWNED OSSUARY",
		"chests": [
			{"id": "mistfen_reed_cache", "pos": Vector3(-15, 0.48, -8), "label": "REED-WRAPPED CHEST", "rarity": 2, "type": "instant"},
			{"id": "mistfen_sunken_cache", "pos": Vector3(-2, 0.48, -26), "label": "SUNKEN RELIQUARY", "rarity": 3, "type": "boss_gated", "boss_key": "biome_fenmaw"},
			{"id": "mistfen_maw_cache", "pos": Vector3(15, 0.48, -15), "label": "FENMAW'S TITHE", "rarity": 3, "type": "boss_gated", "boss_key": "biome_fenmaw"},
		],
		"enemies": ["spitter", "hushling", "elite_hushling"],
		"resources": [
			{"id": "fen_reed", "pos": Vector3(-10, 0, -6), "yield": 3},
			{"id": "spore_dust", "pos": Vector3(-6, 0, -23), "yield": 3},
			{"id": "moss_fiber", "pos": Vector3(12, 0, -18), "yield": 2},
		],
		"encounters": [
			{"scene": "mire_stalker", "pos": Vector3(-13, 0.2, -13)},
			{"scene": "spore_weaver", "pos": Vector3(10, 0.2, -20)},
		],
	},
	"heartwood": {
		"route": [Vector3(0, 0, 2), Vector3(5, 0, -9), Vector3(-5, 0, -17), Vector3(7, 0, -27), Vector3(20, 0, -22)],
		"checkpoint": Vector3(5, 0.35, -8),
		"arena": Vector3(20, 0.1, -22),
		"cave": Vector3(-8, 0.7, -18),
		"dungeon_name": "CINDER-ROOT VAULT",
		"chests": [
			{"id": "heartwood_ash_cache", "pos": Vector3(-7, 0.48, -12), "label": "ASHEN CACHE", "rarity": 2, "type": "instant"},
			{"id": "heartwood_forge_cache", "pos": Vector3(8, 0.48, -28), "label": "FORGEMASTER CHEST", "rarity": 3, "type": "instant"},
			{"id": "heartwood_ember_cache", "pos": Vector3(22, 0.48, -17), "label": "EMBER RELIQUARY", "rarity": 4, "type": "boss_gated", "boss_key": "biome_cinderhart_colossus"},
		],
		"enemies": ["elite_hushling", "spitter", "elite_hushling"],
		"resources": [
			{"id": "emberstone", "pos": Vector3(4, 0, -11), "yield": 3},
			{"id": "iron_shard", "pos": Vector3(-4, 0, -18), "yield": 3},
			{"id": "monster_core", "pos": Vector3(15, 0, -24), "yield": 2},
		],
		"encounters": [
			{"scene": "ember_warden", "pos": Vector3(-3, 0.2, -16)},
			{"scene": "thorn_charger", "pos": Vector3(15, 0.2, -22)},
		],
	},
	"moonfen": {
		"route": [Vector3(0, 0, 2), Vector3(10, 0, 4), Vector3(17, 0, -7), Vector3(8, 0, -18), Vector3(-7, 0, -20), Vector3(-17, 0, -9)],
		"checkpoint": Vector3(9, 0.35, 3),
		"arena": Vector3(-17, 0.1, -9),
		"cave": Vector3(8, 0.7, -20),
		"dungeon_name": "LUNAR UNDERTIDE",
		"chests": [
			{"id": "moonfen_islet_cache", "pos": Vector3(17, 0.48, -3), "label": "ISLET CACHE", "rarity": 2, "type": "instant"},
			{"id": "moonfen_tide_cache", "pos": Vector3(3, 0.48, -21), "label": "UNDERTIDE CHEST", "rarity": 3, "type": "boss_gated", "boss_key": "biome_moonfen_oracle"},
			{"id": "moonfen_lunar_cache", "pos": Vector3(-18, 0.48, -5), "label": "LUNAR RELIQUARY", "rarity": 4, "type": "boss_gated", "boss_key": "biome_moonfen_oracle"},
		],
		"enemies": ["moonfen_fenling", "spitter", "elite_hushling"],
		"resources": [
			{"id": "moonmoss", "pos": Vector3(12, 0, 1), "yield": 3},
			{"id": "crystal_fragment", "pos": Vector3(7, 0, -19), "yield": 2},
			{"id": "fen_reed", "pos": Vector3(-13, 0, -12), "yield": 3},
		],
		"encounters": [
			{"scene": "relic_leech", "pos": Vector3(15, 0.2, -6)},
			{"scene": "mire_stalker", "pos": Vector3(-12, 0.2, -16)},
		],
	},
}

static func profile(realm_id: String) -> Dictionary:
	return (PROFILES.get(realm_id, PROFILES["bramblewood"]) as Dictionary).duplicate(true)

static func resolve_realm(world: Node) -> String:
	var active := ""
	if world != null:
		var game_state := world.get_node_or_null("/root/GameState")
		if game_state != null:
			active = str(game_state.get("current_realm"))
	if PROFILES.has(active):
		return active
	if world != null and "biome_id" in world:
		var biome := str(world.get("biome_id"))
		if PROFILES.has(biome):
			return biome
	return "bramblewood"
