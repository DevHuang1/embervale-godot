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
	var r := REALMS.get(realm_id, REALMS["bramblewood"])
	return {
		"mist_tint":    r["mist_tint"],
		"firefly_tint": r["firefly_tint"],
		"grade":        r["grade"],
	}
