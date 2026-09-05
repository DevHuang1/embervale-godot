extends RefCounted
class_name RelicData

## === RelicData — Forged Relic Resource ===
## Created by ScanManager after a successful forge.
## Mounted on Hero.current_relic and displayed in the Field Satchel.
##
## The relic grants a passive modifier (stat bonus or skill enhancement)
## and optionally displays a forged mesh on the hero's back socket.

## Display identity
var relic_id     : String = ""
var relic_name   : String = ""
var description  : String = ""
var glyph        : String = "◈"
var rarity       : int    = 1   # 1=common, 2=uncommon, 3=rare, 4=legendary

## Visual (mesh shown on back socket)
var mesh_scene   : PackedScene = null   # optional; null = no visual

## Photo-forged visual payload (ScanManager + RelicForge):
## raw Mesh shown on the hero's back socket and the relic trophy pedestal.
var mesh         : Mesh = null
var texture      : Texture2D = null

## Passive bonus type — applied by hero when relic is equipped
## Types: "atk_flat", "atk_pct", "hp_flat", "hp_pct",
##        "speed_pct", "crit_pct", "skill_cd_pct", "dodge_pct"
var bonus_type   : String = ""
var bonus_value  : float  = 0.0

## Element affinity (drives elemental status on auto-strikes)
var element      : String = ""   # "" = none

## Forge metadata
var forge_seed   : int    = 0    # reproducible from scan data
var forged_at    : float  = 0.0  # unix timestamp

# ─────────────────────────────────────────────────────────────────────────────
# Factory
# ─────────────────────────────────────────────────────────────────────────────

static func from_dict(d: Dictionary) -> RelicData:
	var r := RelicData.new()
	r.relic_id    = str(d.get("id",          "relic_unknown"))
	r.relic_name  = str(d.get("name",        "Unknown Relic"))
	r.description = str(d.get("description", ""))
	r.glyph       = str(d.get("glyph",       "◈"))
	r.rarity      = int(d.get("rarity",       1))
	r.bonus_type  = str(d.get("bonus_type",  ""))
	r.bonus_value = float(d.get("bonus_value", 0.0))
	r.element     = str(d.get("element",     ""))
	r.forge_seed  = int(d.get("forge_seed",   0))
	r.forged_at   = float(d.get("forged_at",  0.0))
	return r

func to_dict() -> Dictionary:
	return {
		"id":          relic_id,
		"name":        relic_name,
		"description": description,
		"glyph":       glyph,
		"rarity":      rarity,
		"bonus_type":  bonus_type,
		"bonus_value": bonus_value,
		"element":     element,
		"forge_seed":  forge_seed,
		"forged_at":   forged_at,
	}

## Apply this relic's bonus to a hero entity.
func apply_to_hero(hero: Node3D) -> void:
	if hero == null or bonus_type.is_empty():
		return
	match bonus_type:
		"atk_flat":
			var gs := hero.get_node_or_null("/root/GameState")
			if gs != null and gs.has_method("grant_atk_bonus"):
				gs.call("grant_atk_bonus", int(bonus_value))
		"hp_flat":
			var gs := hero.get_node_or_null("/root/GameState")
			if gs != null:
				var cur := int(gs.get("max_hp") if gs.get("max_hp") != null else 60)
				gs.set("max_hp", cur + int(bonus_value))
				gs.set("hp",     mini(int(gs.get("hp") if gs.get("hp") != null else 60), cur + int(bonus_value)))
		"speed_pct":
			if hero.get("move_speed") != null:
				hero.set("move_speed", float(hero.get("move_speed")) * (1.0 + bonus_value))
		"dodge_pct":
			if hero.get("dodge_chance") != null:
				hero.set("dodge_chance", clampf(float(hero.get("dodge_chance")) + bonus_value, 0.0, 1.0))

# ─────────────────────────────────────────────────────────────────────────────
# Scan-forged weapon kit builder
# ─────────────────────────────────────────────────────────────────────────────

## Rarity multipliers, mirroring ScanManager.RARITY_WEIGHTS so every combat
## number in the forged kit derives from the rarity roll alone. The player
## supplies only names; the numbers are computed here.
const FORGE_RARITY_MULTS: Array[float] = [1.00, 1.15, 1.30, 1.45, 1.65]

## Player-facing names are cosmetic: trimmed, control-char-free, length-capped,
## with deterministic fallbacks so the app always ships a complete kit.
const NAME_LIMIT := 22

## Player-facing names are cosmetic: trimmed, control-char-free, length-capped,
## with deterministic fallbacks so the app always ships a complete kit.
static func sanitize_name(raw: String, fallback: String) -> String:
	var clipped := raw.strip_edges().substr(0, NAME_LIMIT)
	var out := ""
	for c in clipped:
		if c.unicode_at(0) >= 32:
			out += c
	out = out.strip_edges()
	return out if not out.is_empty() else fallback


## Wield style derives deterministically from the item's name, so naming an
## artifact subtly flavors how it swings without touching its numbers.
static func style_for(item_name: String) -> String:
	return ["slash", "blunt", "magic"][int(abs(item_name.hash())) % 3]


## Style (attack feel) inherited from the scanned object's base kit.
const FORGE_STYLE_BY_BASE := {
	"mug_mace":     "blunt",
	"slab_hammer":  "blunt",
	"pocket_blade": "slash",
	"snip_twins":   "slash",
	"soda_cannon":  "magic",
}

## Builds the full weapon def Dictionary for a scan-forged relic kit:
## a three-rite loadout (strike → whirl → comet ULT) whose damage scales
## with the rarity roll. The returned def is add_weapon()-ready: it carries
## an id (stable per base item, so re-forging replaces instead of piling up),
## display identity, style, and the skill kit the hero's executor supports.
static func build_weapon_def(base: Dictionary, rarity: int, item_name: String,
		skill_names: Array) -> Dictionary:
	var rarity_index := clampi(rarity, 0, FORGE_RARITY_MULTS.size() - 1)
	var mult := FORGE_RARITY_MULTS[rarity_index]

	var display_name := str(item_name).strip_edges().to_upper()
	if display_name.is_empty():
		display_name = str(base.get("name", "FORGED KIT"))

	var base_id := str(base.get("id", "mug_mace"))
	var names := skill_names.duplicate()
	while names.size() < 3:
		names.append("")
	var kit_names := [
		_str_or_default(names[0], "FORGED STRIKE"),
		_str_or_default(names[1], "FORGED WHIRL"),
		_str_or_default(names[2], "FORGED COMET"),
	]

	return {
		"id": "relic_%s" % base_id,
		"name": display_name,
		"glyph": str(base.get("glyph", "✦")),
		"style": str(FORGE_STYLE_BY_BASE.get(base_id, "blunt")),
		"relic": true,
		"element": "",
		"rarity": rarity_index,
		"atk": maxi(1, int(round(float(base.get("atk", 6)) * mult))),
		"swing_time": float(base.get("swing_time", 0.32)),
		"range": float(base.get("range", 8.0)),
		"skills": [
			{
				"name": kit_names[0], "type": "strike",
				"cooldown": 1.5, "dmg_mult": 2.2 * mult,
				"desc": "A heavy focused blow through the marked foe.",
			},
			{
				"name": kit_names[1], "type": "whirl",
				"cooldown": 2.5, "radius": 3.6, "dmg_mult": 1.6 * mult,
				"desc": "A spinning ring of strikes around you.",
			},
			{
				"name": kit_names[2], "type": "comet",
				"cooldown": 4.0, "radius": 4.0, "dmg_mult": 2.8 * mult,
				"desc": "Call down a slow comet; a wide blast follows.",
			},
		],
	}

## Empty-name fallback so unnamed rites still read as deliberate kit slots.
static func _str_or_default(value, fallback: String) -> String:
	var s := str(value).strip_edges()
	return s if not s.is_empty() else fallback


## Static: create the matriarch scepter relic from GameState definition.
static func matriarch_scepter() -> RelicData:
	var r := RelicData.new()
	r.relic_id    = "matriarch_scepter"
	r.relic_name  = "Crown of the Old Root"
	r.description = "The Matriarch's scepter hums with dormant bramble power."
	r.glyph       = "♛"
	r.rarity      = 4
	r.bonus_type  = "atk_flat"
	r.bonus_value = 3.0
	r.element     = "nature"
	return r
