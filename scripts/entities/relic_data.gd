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
