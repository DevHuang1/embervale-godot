class_name BossCustomization
extends Resource

## === Boss Customization ===
## What a spent scan buys: the scanned idol mesh + its texture, an extracted
## palette, ONE realm skill from the boss's pool, and a generic SFX preset.
## Everything else about the boss (ultimate, summons, stingers, arena) stays
## locked to preserve identity and balance.

@export var boss_id: String = ""
@export var skill: Dictionary = {}
@export var sfx_preset: String = "vanilla"
@export var palette: Array[Color] = []
@export var idol_mesh: Mesh
@export var idol_texture: Texture2D


static func from_payload(data: Dictionary) -> BossCustomization:
	var c := BossCustomization.new()
	c.boss_id = str(data.get("boss_id", ""))
	c.skill = data.get("skill", {}).duplicate(true)
	c.sfx_preset = str(data.get("sfx_preset", "vanilla"))
	var cols: Array = data.get("palette", [])
	for col in cols:
		if col is Color:
			c.palette.append(col)
		elif col is String:
			c.palette.append(Color(col))
	return c


## Save-safe payload (colors as hex strings; mesh/texture stay runtime-only —
## a reloaded save keeps skill/palette/SFX and simply omits the idol).
func to_payload() -> Dictionary:
	return {
		"boss_id": boss_id,
		"skill": skill.duplicate(true),
		"sfx_preset": sfx_preset,
		"palette": palette.map(func(c): return c.to_html(true)),
	}
