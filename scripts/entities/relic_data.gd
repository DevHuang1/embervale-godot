class_name RelicData
extends Resource

## === Captured Relic ===
## A photo-forged object born from a camera scan: the silhouette of
## whatever the lens saw, extruded into paper-craft geometry and
## textured with the capture itself.
##
## Relics become wieldable weapon kits: the player names the item and its
## three rites (Skill 1 / Skill 2 / Ultimate), while every combat number —
## ATK, damage multipliers, cooldowns, radii — is computed here from the
## rarity roll. Player input is strictly cosmetic.

@export var title: String = "Unnamed Relic"
@export var glyph: String = "✦"
@export var rarity: int = 0
@export var mesh: Mesh
@export var texture: ImageTexture

const NAME_LIMIT := 22

const DEFAULT_ITEM_NAME := "Unnamed Relic"
const DEFAULT_SKILL_NAMES := ["Kindled Strike", "Grove Cyclone", "Relic Cataclysm"]
const SLOT_TITLES := ["SKILL 1", "SKILL 2", "ULTIMATE"]

# App-owned kit template: fixed slots, numbers scale only with rarity.
# Types are ones Hero._execute_skill already directs: strike / whirl /
# explosion / comet (magic-styled relics ultimate into a comet).
const KIT_TEMPLATE := [
	{"type": "strike", "cooldown": 4.0, "dmg_mult_base": 2.0,
		"desc": "A heavy crescent slash through the marked target."},
	{"type": "whirl", "cooldown": 6.5, "radius": 3.6, "dmg_mult_base": 1.7,
		"desc": "Spin a ring of bramble slashes around you."},
	{"type": "explosion", "cooldown": 12.0, "radius": 4.0, "dmg_mult_base": 3.0,
		"desc": "Detonate a relic burst on the marked target."},
]

const RARITY_MULTS := [1.0, 1.15, 1.3, 1.45, 1.65]


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


## Builds a WEAPON_DEFS-compatible kit from the detected class base stats.
## `base` comes from ScanManager.CLASS_TO_WEAPON; `skill_names` holds the
## player's three rite names in slot order (Skill 1, Skill 2, Ultimate).
static func build_weapon_def(base: Dictionary, rarity: int, item_name: String,
		skill_names: Array) -> Dictionary:
	var tier := clampi(rarity, 0, RARITY_MULTS.size() - 1)
	var mult := float(RARITY_MULTS[tier])
	var name := sanitize_name(item_name, str(base.get("name", DEFAULT_ITEM_NAME)))
	var style := style_for(name)

	var skills := []
	for i in KIT_TEMPLATE.size():
		var tpl: Dictionary = KIT_TEMPLATE[i]
		var sk := {
			"name": sanitize_name(
				str(skill_names[i]) if i < skill_names.size() else "",
				DEFAULT_SKILL_NAMES[i]),
			"type": str(tpl.type),
			"cooldown": float(tpl.cooldown),
			"dmg_mult": snappedf(float(tpl.dmg_mult_base) * mult, 0.01),
			"desc": str(tpl.desc),
		}
		if tpl.has("radius"):
			sk["radius"] = float(tpl.radius)
		# Magic-flavored relics finish on a falling star instead of a blast
		if i == 2 and style == "magic":
			sk["type"] = "comet"
		skills.append(sk)

	return {
		"id": "relic_%08x" % (int(abs(name.hash())) + Time.get_ticks_msec()),
		"name": name,
		"glyph": str(base.get("glyph", "✦")),
		"style": style,
		"atk": int(round(float(base.get("atk", 6)) * mult)),
		"swing_time": float(base.get("swing_time", 0.38)),
		"range": float(base.get("range", 8.0)),
		"rarity": tier,
		"relic": true,
		"skills": skills,
	}
