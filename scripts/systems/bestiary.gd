extends Node
class_name Bestiary

## === Bestiary — Realm + Wave + Enemy Variant Registry ===
## Single source of truth for:
##   - REALMS: palette/audio/material tints per realm
##   - WAVES:  quest-stage → enemy composition (normal/hard/elite counts)
##   - variant_for(realm_id, tier): archetype + stats for a specific enemy slot
##   - realm_for_stage(stage): realm dict for a quest stage index
##   - realm_id_for_stage(stage): just the realm id string
##
## All callers already exist in world_manager.gd — this file satisfies them.

const REALMS := {
	"bramblewood": {
		"id":            "bramblewood",
		"display":       "Whispergrove",
		"mist_tint":     Color(0.65, 0.75, 0.72),
		"firefly_tint":  Color(1.00, 0.86, 0.45),
		"enemy_tint":    Color(0.22, 0.40, 0.28, 1.0),
		"eye_glow":      Color(0.20, 1.00, 0.44, 1.0),
		"archetype":     "hushling",
		"boss_key":      "hushling_matriarch",
		"grade":         { "saturation": 1.0, "temperature": 0.0 },
	},
	"mistfen": {
		"id":            "mistfen",
		"display":       "Mistfen Hollows",
		"mist_tint":     Color(0.38, 0.55, 0.68),
		"firefly_tint":  Color(0.60, 0.82, 0.94),
		"enemy_tint":    Color(0.15, 0.27, 0.34, 1.0),
		"eye_glow":      Color(0.30, 0.82, 0.94, 1.0),
		"archetype":     "fenling",
		"boss_key":      "moonfen_broodmother",
		"grade":         { "saturation": 0.80, "temperature": -0.15 },
	},
	"heartwood": {
		"id":            "heartwood",
		"display":       "The Heartwood",
		"mist_tint":     Color(0.55, 0.25, 0.12),
		"firefly_tint":  Color(1.00, 0.50, 0.18),
		"enemy_tint":    Color(0.25, 0.10, 0.07, 1.0),
		"eye_glow":      Color(1.00, 0.30, 0.08, 1.0),
		"archetype":     "ember_warden",
		"boss_key":      "heartwood_sentinel",
		"grade":         { "saturation": 1.10, "temperature": 0.20 },
	},
	"moonfen": {
		"id":            "moonfen",
		"display":       "Moonfen Drift",
		"mist_tint":     Color(0.28, 0.35, 0.60),
		"firefly_tint":  Color(0.72, 0.82, 1.00),
		"enemy_tint":    Color(0.18, 0.20, 0.38, 1.0),
		"eye_glow":      Color(0.32, 0.90, 1.00, 1.0),
		"archetype":     "moonfen_fenling",
		"boss_key":      "moonfen_matriarch",
		"grade":         { "saturation": 0.65, "temperature": -0.25 },
	},
}

# Quest stage → realm id mapping (index matches QuestStage enum)
const STAGE_REALMS := ["bramblewood", "bramblewood", "mistfen", "heartwood"]

# Quest stage → enemy wave composition
# Keys: normal (standard count), hard (hard-tier count), elite (elite count)
const WAVES := {
	0: { "normal": 2, "hard": 0, "elite": 0 },  # SEEK_SPRITE
	1: { "normal": 2, "hard": 1, "elite": 0 },  # CLAIM_SHARD
	2: { "normal": 2, "hard": 1, "elite": 1 },  # LIGHT_BEACON — Mistfen opens
	3: { "normal": 3, "hard": 2, "elite": 1 },  # COMPLETE — Heartwood tier
}

# Archetype + visual variant definitions per realm × tier
# Each entry: kind, display, hp, atk_bonus, speed, scale, tint, eye, volley
const VARIANTS := {
	"bramblewood": {
		"normal": { "kind": "hushling",      "display": "Bramble Sprite",   "hp": 28,  "atk_bonus": 0, "speed": 1.00, "scale": 1.00, "tint": Color(0,0,0,0), "eye": Color(0,0,0,0) },
		"hard":   { "kind": "charger",       "display": "Bramble Charger",  "hp": 44,  "atk_bonus": 2, "speed": 1.08, "scale": 1.08, "tint": Color(0.25,0.18,0.12,1), "eye": Color(0.95,0.35,0.12,1) },
		"elite":  { "kind": "thorn_charger", "display": "Elder Thorn",      "hp": 68,  "atk_bonus": 4, "speed": 1.12, "scale": 1.18, "tint": Color(0.20,0.10,0.06,1), "eye": Color(1.00,0.22,0.06,1) },
	},
	"mistfen": {
		"normal": { "kind": "fenling",        "display": "Fen Sprite",       "hp": 32,  "atk_bonus": 0, "speed": 1.08, "scale": 0.92, "tint": Color(0.15,0.27,0.34,1), "eye": Color(0.28,0.82,0.94,1), "volley": true },
		"hard":   { "kind": "mire_stalker",   "display": "Mire Stalker",     "hp": 50,  "atk_bonus": 2, "speed": 1.10, "scale": 1.00, "tint": Color(0.12,0.22,0.30,1), "eye": Color(0.20,0.75,0.90,1) },
		"elite":  { "kind": "moonfen_fenling","display": "Moonfen Warden",   "hp": 78,  "atk_bonus": 4, "speed": 1.12, "scale": 1.10, "tint": Color(0.08,0.18,0.30,1), "eye": Color(0.32,0.90,1.00,1), "volley": true },
	},
	"heartwood": {
		"normal": { "kind": "ember_warden",   "display": "Ember Warden",     "hp": 38,  "atk_bonus": 2, "speed": 0.88, "scale": 1.08, "tint": Color(0.25,0.10,0.07,1), "eye": Color(1.00,0.28,0.06,1) },
		"hard":   { "kind": "spore_weaver",   "display": "Spore Weaver",     "hp": 55,  "atk_bonus": 3, "speed": 0.95, "scale": 1.04, "tint": Color(0.22,0.30,0.14,1), "eye": Color(0.62,0.88,0.30,1) },
		"elite":  { "kind": "relic_leech",    "display": "Ember Leech",      "hp": 88,  "atk_bonus": 5, "speed": 0.92, "scale": 1.14, "tint": Color(0.20,0.08,0.06,1), "eye": Color(1.00,0.18,0.06,1) },
	},
	"moonfen": {
		"normal": { "kind": "moonfen_fenling","display": "Moon Sprite",      "hp": 36,  "atk_bonus": 1, "speed": 1.05, "scale": 0.94, "tint": Color(0.18,0.20,0.38,1), "eye": Color(0.32,0.90,1.00,1), "volley": true },
		"hard":   { "kind": "ambusher",       "display": "Moonfen Ambusher", "hp": 52,  "atk_bonus": 3, "speed": 1.12, "scale": 0.98, "tint": Color(0.14,0.16,0.32,1), "eye": Color(0.28,0.80,0.96,1) },
		"elite":  { "kind": "relic_leech",    "display": "Moonfen Leech",    "hp": 82,  "atk_bonus": 4, "speed": 1.00, "scale": 1.08, "tint": Color(0.16,0.18,0.38,1), "eye": Color(0.44,0.76,1.00,1), "volley": true },
	},
}

# ─────────────────────────────────────────────────────────────────────────────
# Public API (called by world_manager.gd)
# ─────────────────────────────────────────────────────────────────────────────

static func realm_for_stage(stage: int) -> Dictionary:
	var rid := realm_id_for_stage(stage)
	return REALMS.get(rid, REALMS["bramblewood"])

static func realm_id_for_stage(stage: int) -> String:
	if stage < 0 or stage >= STAGE_REALMS.size():
		return "bramblewood"
	return STAGE_REALMS[stage]

## Returns the variant dict for (realm_id, tier) — tier is "normal", "hard", or "elite".
static func variant_for(realm_id: String, tier: String) -> Dictionary:
	var realm_variants : Dictionary = VARIANTS.get(realm_id, VARIANTS["bramblewood"])
	return realm_variants.get(tier, realm_variants.get("normal", {}))

## All realm ids as an array.
static func all_realm_ids() -> Array:
	return REALMS.keys()

## Palette bias applied to DayNightCycle per realm.
## Returns { mist_tint, firefly_tint, grade } matching what world_manager expects.
static func realm_grade(realm_id: String) -> Dictionary:
	var r: Dictionary = REALMS.get(realm_id, REALMS["bramblewood"])
	return {
		"mist_tint":    r["mist_tint"],
		"firefly_tint": r["firefly_tint"],
		"grade":        r["grade"],
	}

# === Realm id constants (stable string ids used by footsteps, gates, saves) ===
const REALM_BRAMBLEWOOD := "bramblewood"
const REALM_MISTFEN := "mistfen"
const REALM_HEARTWOOD := "heartwood"
const REALM_MOONFEN := "moonfen"

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
