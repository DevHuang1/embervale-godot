class_name Bestiary
extends Object

## === Whispergrove Bestiary ===
## Static tables for the realm ladder, enemy tier variants, boss identity
## (skill pools + locked traits) and SFX profile ids. Pure data + lookup
## helpers; nothing here touches the tree.

const REALM_BRAMBLEWOOD := "bramblewood"
const REALM_MISTFEN := "mistfen"
const REALM_HEARTWOOD := "heartwood"
const REALM_MOONFEN := "moonfen"

## Realm per quest stage: stages 0-1 share the green edge, stage 2 sinks
## into mistfen, stage 3 is the Heartwood rite where the Matriarch waits.
const STAGE_REALM := {
	0: REALM_BRAMBLEWOOD,
	1: REALM_BRAMBLEWOOD,
	2: REALM_MISTFEN,
	3: REALM_HEARTWOOD,
}

const REALMS := {
	"whispergrove": {
		"title": "Whispergrove",
		"intro": "Jade boughs gather around the Lantern Bearer.",
		"mist_tint": Color(0.58, 0.76, 0.65),
		"firefly_tint": Color(1.0, 0.84, 0.38),
		"grade": {"saturation": 1.08, "contrast": 1.02, "glow": 1.08},
	},
	REALM_BRAMBLEWOOD: {
		"title": "Bramblewood",
		"intro": "The grove's green edge stirs with small hungers.",
		"mist_tint": Color(0.65, 0.75, 0.72),
		"firefly_tint": Color(1.0, 0.86, 0.45),
		"grade": {"saturation": 1.12, "contrast": 1.04, "glow": 1.05},
	},
	REALM_MISTFEN: {
		"title": "Mistfen",
		"intro": "Pale fog pools between the roots — eyes move in it.",
		"mist_tint": Color(0.55, 0.66, 0.78),
		"firefly_tint": Color(0.62, 0.80, 0.96),
		"grade": {"saturation": 0.92, "contrast": 1.07, "glow": 1.15},
	},
	REALM_HEARTWOOD: {
		"title": "Heartwood Rite",
		"intro": "The old altar answers. Something ancient wakes.",
		"mist_tint": Color(0.78, 0.60, 0.52),
		"firefly_tint": Color(1.0, 0.55, 0.30),
		"grade": {"saturation": 1.06, "contrast": 1.10, "glow": 1.2},
	},
	"moonfen": {
		"title": "Moonfen",
		"intro": "Violet water holds a cold reflection of the old moon.",
		"mist_tint": Color(0.42, 0.58, 0.78),
		"firefly_tint": Color(0.36, 0.86, 1.0),
		"grade": {"saturation": 1.08, "contrast": 1.08, "glow": 1.22},
	},
}

## Enemy tier variants per realm. Fields feed CharacterModelData plus the
## Hushling behavior flags; hp/atk tuned against hero armor math.
## Scales sit ~0.85x under the classic sizes so packs read smaller against
## the untouched boss scale (hero adds its own visual_scale on top).
const ENEMY_VARIANTS := {
	REALM_BRAMBLEWOOD: {
		"normal": {
			"display": "Hushling", "scale": 0.85, "hp": 28, "atk_bonus": 0,
			"speed": 1.0, "volley": false,
			"tint": Color(0, 0, 0, 0), "eye": Color(0, 0, 0, 0),
		},
"hard": {
				"kind": "charger",
				"display": "Elder Charger", "scale": 1.12, "hp": 48, "atk_bonus": 2,
				"speed": 0.92, "volley": true,
			"tint": Color(0.13, 0.20, 0.12), "eye": Color(1.0, 0.42, 0.16),
		},
	},
	REALM_MISTFEN: {
"normal": {
				"kind": "fenling",
				"display": "Fenling Mire Sprite", "scale": 0.92, "hp": 34, "atk_bonus": 1,
				"speed": 1.04, "volley": false,
				"tint": Color(0.13, 0.20, 0.26), "eye": Color(0.42, 0.86, 1.0),
			},
		"hard": {
			"kind": "spitter",
			"display": "Fen Spitter", "scale": 1.05, "hp": 46, "atk_bonus": 3,
			"speed": 0.95, "volley": false,
			"tint": Color(0.12, 0.20, 0.20), "eye": Color(0.45, 0.85, 1.0),
		},
	},
	REALM_HEARTWOOD: {
		"normal": {
			"kind": "hushling",
			"display": "Ember Hushling", "scale": 0.95, "hp": 38, "atk_bonus": 1,
			"speed": 1.08, "volley": false,
			"tint": Color(0.24, 0.14, 0.10), "eye": Color(1.0, 0.55, 0.30),
		},
		"hard": {
			"kind": "spitter",
			"display": "Cinder Spitter", "scale": 1.1, "hp": 52, "atk_bonus": 4,
			"speed": 1.0, "volley": false,
			"tint": Color(0.22, 0.10, 0.07), "eye": Color(1.0, 0.30, 0.12),
		},
	},
	REALM_MOONFEN: {
		"normal": {
			"kind": "moonfen_fenling",
			"display": "Lunar Fenling", "scale": 0.94, "hp": 40, "atk_bonus": 2,
			"speed": 1.08, "volley": true,
			"tint": Color(0.08, 0.22, 0.30), "eye": Color(0.32, 0.92, 1.0),
		},
		"hard": {
			"kind": "relic_leech",
			"display": "Moon Relic Leech", "scale": 1.08, "hp": 54, "atk_bonus": 4,
			"speed": 0.98, "volley": false,
			"tint": Color(0.16, 0.10, 0.28), "eye": Color(0.52, 0.86, 1.0),
		},
	},
}

## Wave composition on each quest-stage entry (packs around the hero).
const WAVES := {
	0: {"normal": 2, "hard": 0},
	1: {"normal": 2, "hard": 1},
	2: {"normal": 2, "hard": 2, "elite": 1},
}

## Boss identity: what the player may bend vs what stays locked forever.
const BOSS_DEFS := {
	"matriarch": {
		"name": "HUSHLING MATRIARCH",
		"title": "the Bramble Queen",
		"locked_blurb": "Summons, Root Prison and the Bramble Storm are hers alone — one rite answers to you.",
		"default_skill_label": "Thorn Cascade",
		# Exactly one of these replaces her phase-3 ranged rite.
		"skill_pool": [
			{"id": "thorn_lattice", "name": "Thorn Lattice", "type": "lattice",
				"cooldown": 11.0, "desc": "Twin rings of brambles close from every side."},
			{"id": "spore_bloom", "name": "Spore Bloom", "type": "bloom",
				"cooldown": 15.0, "desc": "Rot-blooms knit her wounds while they hiss."},
			{"id": "husk_legion", "name": "Husk Legion", "type": "legion",
				"cooldown": 17.0, "desc": "Three elders rise at once to shield her."},
			{"id": "root_snare", "name": "Root Snare", "type": "snare",
				"cooldown": 14.0, "desc": "Roots leap the distance and cage you where you stand."},
		],
		"sfx_presets": ["hollow_resin", "grave_moss", "ember_glass"],
			"model_variants": ["boss_whispergrove_rootwarden", "boss_whispergrove_dewseer"],
	},
	# === Biome bosses (arena challenges) ===
	"thornhide_alpha": {
		"name": "THORNHIDE ALPHA",
		"title": "the First Hunger",
		"scene": "res://scenes/entities/boss_biome.tscn",
		"hp": 560, "atk": 12, "speed": 4.8, "scale": 1.0,
		"palette": [Color(0.16, 0.23, 0.13), Color(1.0, 0.42, 0.16)],
			"diamond_reward": 3,
			"model_variants": ["boss_bramblewood_thornregent", "boss_bramblewood_briarwidow"],
			"special_1": {"kind": "volley", "cooldown": 9.0, "damage": 10},

		"special_2": {"kind": "summon", "cooldown": 16.0, "count": 2},
		"ultimate": {"kind": "storm", "cooldown": 22.0, "eruptions": 16, "damage": 20},
		"intro": "The underbrush folds open — something old and hungry has been waiting.",
		"rewards": {
			"xp": 250,
			"loot": {"hushling_thorn": 4},
			"weapon": {"id": "thornbite_cleaver", "name": "THORNBITE CLEAVER", "glyph": "🪓",
				"atk": 18, "swing_time": 0.7, "range": 9.5,
				"skill": {"name": "Bramble Rend", "type": "heavy_aoe", "cooldown": 9.0,
					"radius": 14.0, "dmg_mult": 1.8}, "rarity": 3},
		},
	},
	"fenmaw": {
		"name": "FENMAW",
		"title": "the Drowned Choir",
		"scene": "res://scenes/entities/boss_biome.tscn",
		"hp": 700, "atk": 14, "speed": 4.2, "scale": 1.12,
		"palette": [Color(0.10, 0.17, 0.24), Color(0.45, 0.85, 1.0)],
			"diamond_reward": 4,
			"model_variants": ["boss_mistfen_veilmother", "boss_mistfen_drownedsage"],
			"special_1": {"kind": "volley", "cooldown": 8.0, "damage": 12},
		"special_2": {"kind": "heal", "cooldown": 15.0, "amount": 14},
		"ultimate": {"kind": "storm", "cooldown": 21.0, "eruptions": 18, "damage": 22},
		"intro": "The fen goes still. Under the pale water, a chorus of throats opens.",
		"rewards": {
			"xp": 320,
			"loot": {"moss_tonic": 3},
			"weapon": {"id": "tidecall_brand", "name": "TIDECALL BRAND", "glyph": "🔱",
				"atk": 20, "swing_time": 0.65, "range": 11.0,
				"skill": {"name": "Drowning Wake", "type": "heavy_aoe", "cooldown": 8.0,
					"radius": 16.0, "dmg_mult": 2.0}, "rarity": 3},
		},
	},
	"cinderhart_colossus": {
		"name": "CINDERHART COLOSSUS", "title": "the Walking Furnace",
		"scene": "res://scenes/entities/boss_biome.tscn",
		"hp": 810, "atk": 16, "speed": 3.8, "scale": 1.18,
		"palette": [Color(0.16, 0.07, 0.04), Color(1.0, 0.28, 0.06)],
					"silhouette": "cinder_antlers", "diamond_reward": 5,
			"model_variants": ["boss_heartwood_cinderhart", "boss_heartwood_ashcolossus"],
			"special_1": {"kind": "fissure", "cooldown": 8.5, "damage": 14},

		"special_2": {"kind": "summon", "cooldown": 17.0, "count": 2,
			"scene": "res://scenes/entities/ember_warden.tscn"},
		"ultimate": {"kind": "spiral", "cooldown": 23.0, "eruptions": 20, "damage": 24},
		"intro": "The ash causeway splits. A furnace with antlers drags itself into the rite.",
		"rewards": {
			"xp": 410, "materials": {"emberstone": 5, "monster_core": 2},
			"loot": {"moss_tonic": 2},
			"weapon": {"id": "cinderhart_maul", "name": "CINDERHART MAUL", "glyph": "🔨",
				"atk": 23, "swing_time": 0.82, "range": 10.0,
				"skill": {"name": "Furnace Break", "type": "heavy_aoe", "cooldown": 9.5,
					"radius": 15.0, "dmg_mult": 2.25}, "rarity": 4},
		},
	},
	"moonfen_oracle": {
		"name": "MOONFEN ORACLE", "title": "the Reflection Beneath",
		"scene": "res://scenes/entities/boss_biome.tscn",
		"hp": 900, "atk": 17, "speed": 4.6, "scale": 1.12,
		"palette": [Color(0.07, 0.12, 0.24), Color(0.22, 0.92, 1.0)],
		"silhouette": "lunar_crown", "diamond_reward": 6,
			"model_variants": ["boss_moonfen_tideoracle", "boss_moonfen_lunarleviathan"],
		"special_1": {"kind": "tide_cross", "cooldown": 7.5, "damage": 15},
		"special_2": {"kind": "summon", "cooldown": 16.0, "count": 2,
			"scene": "res://scenes/entities/relic_leech.tscn"},
		"ultimate": {"kind": "spiral", "cooldown": 21.0, "eruptions": 24, "damage": 25},
		"intro": "The water reflects no hero. The thing wearing your moonlit shadow rises instead.",
		"rewards": {
			"xp": 480, "materials": {"moonmoss": 5, "crystal_fragment": 3},
			"loot": {"moss_tonic": 3},
			"weapon": {"id": "oracle_crescent", "name": "ORACLE CRESCENT", "glyph": "☾",
				"atk": 24, "swing_time": 0.58, "range": 12.0,
				"skill": {"name": "Undertide Mirror", "type": "whirl", "cooldown": 8.0,
					"radius": 17.0, "dmg_mult": 2.1}, "rarity": 4},
		},
	},
}

static func realm_id_for_stage(stage: int) -> String:
	return String(STAGE_REALM.get(stage, REALM_BRAMBLEWOOD))

static func realm_for_stage(stage: int) -> Dictionary:
	var id := realm_id_for_stage(stage)
	var realm: Dictionary = REALMS.get(id, {})
	realm["id"] = id
	return realm

static func variant_for(realm_id: String, tier: String) -> Dictionary:
	return ENEMY_VARIANTS.get(realm_id, {}).get(tier, {})

static func boss_def(boss_id: String) -> Dictionary:
	return BOSS_DEFS.get(boss_id, {})

static func skill_pool(boss_id: String) -> Array:
	return boss_def(boss_id).get("skill_pool", [])

# === World realms (travel layer) ===
# Scene-linked zones with their own map bounds, tints and unlock gates.
const WORLD_REALMS := {
	"whispergrove": {
		"name": "Whispergrove",
		"scene": "res://scenes/world/grove.tscn",
		"unlock": "",
		"bounds": Rect2(-300, -300, 600, 600),
		"map_color": Color(0.14, 0.22, 0.18),
	},
	"bramblewood": {
		"name": "Bramblewood",
		"scene": "res://scenes/world/grove.tscn",
		"unlock": "",
		"bounds": Rect2(-300, -300, 600, 600),
		"map_color": Color(0.14, 0.22, 0.18),
	},
	"mistfen": {
		"name": "Mistfen",
		"scene": "res://scenes/world/mistfen.tscn",
		"unlock": "",
		"bounds": Rect2(-76, -76, 152, 152),
		"map_color": Color(0.10, 0.14, 0.26),
	},
	"heartwood": {
		"name": "Heartwood",
		"scene": "res://scenes/world/heartwood.tscn",
		"unlock": "",
		"bounds": Rect2(-76, -76, 152, 152),
		"map_color": Color(0.26, 0.16, 0.10),
	},
	"moonfen": {
		"name": "Moonfen",
		"scene": "res://scenes/world/moonfen.tscn",
		"unlock": "beacon_lit",
		"bounds": Rect2(-52, -40, 104, 80),
		"map_color": Color(0.10, 0.14, 0.26),
	},
}

## Biome layer: the three explorable realms. Each hosts its own enemy
## packs (respawning), travel gates to the sibling biomes, and an arena
## stone that wakes its boss. The Matriarch stays the quest finale.
const BIOMES := {
	REALM_BRAMBLEWOOD: {
		"title": "Bramblewood",
		"boss_id": "thornhide_alpha",
		"final_boss_biome": false,
		"pack": {"normal": 2, "hard": 1},
		"pack_cap": 5,
		"respawn_seconds": 17.0,
		"gates": [REALM_MISTFEN, REALM_HEARTWOOD],
	},
	REALM_MISTFEN: {
		"title": "Mistfen",
		"boss_id": "fenmaw",
		"final_boss_biome": false,
		"pack": {"normal": 2, "hard": 1},
		"pack_cap": 5,
		"respawn_seconds": 15.0,
		"fog_energy": 1.35,
		"gates": [REALM_BRAMBLEWOOD, REALM_HEARTWOOD],
	},
	REALM_HEARTWOOD: {
		"title": "Heartwood",
		"boss_id": "cinderhart_colossus",
		"final_boss_biome": true,
		"pack": {"normal": 1, "hard": 2},
		"pack_cap": 4,
		"respawn_seconds": 19.0,
		"gates": [REALM_BRAMBLEWOOD, REALM_MISTFEN, REALM_MOONFEN],
	},
	REALM_MOONFEN: {
		"title": "Moonfen",
		"boss_id": "moonfen_oracle",
		"final_boss_biome": false,
		"pack": {"normal": 2, "hard": 1},
		"pack_cap": 5,
		"respawn_seconds": 18.0,
		"fog_energy": 1.18,
		"gates": [REALM_BRAMBLEWOOD, REALM_HEARTWOOD],
	},
}

static func world_realm(id: String) -> Dictionary:
	return WORLD_REALMS.get(id, {})

static func biome(id: String) -> Dictionary:
	var def: Dictionary = BIOMES.get(id, {}).duplicate()
	def["id"] = id
	return def

static func biome_scene(id: String) -> String:
	return String(WORLD_REALMS.get(id, {}).get("scene", ""))
