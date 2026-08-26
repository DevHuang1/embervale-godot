class_name ImpactDirector
extends Object

## === Impact Director ===
## Maps (weapon style x surface class) to a coordinated sensory profile:
## impact cue, VFX color, shake/hitstop/chroma weights. Also dispatches
## relic-element payloads (fire/frost/shock/nature) using existing CombatFx
## primitives so every hit lands with material-aware weight.

const STYLES := ["slash", "blunt", "magic", "claw"]
const SURFACES := ["flesh", "plant", "stone"]
const ELEMENTS := ["fire", "frost", "shock", "nature"]

## Per-style base feel. Numbers feed CombatFx.impact(shake, hitstop, scale, chroma).
const PROFILES := {
	"slash": {"cue": "", "color": Color(1.0, 0.92, 0.7),
		"shake": 0.09, "hitstop": 0.0, "scale": 1.0, "chroma": 0.18},
	"blunt": {"cue": "impact_thud", "color": Color(1.0, 0.78, 0.42),
		"shake": 0.13, "hitstop": 0.02, "scale": 0.9, "chroma": 0.24},
	"magic": {"cue": "", "color": Color(0.72, 0.62, 1.0),
		"shake": 0.10, "hitstop": 0.0, "scale": 1.1, "chroma": 0.30},
	"claw": {"cue": "impact_claw", "color": Color(1.0, 0.4, 0.2),
		"shake": 0.12, "hitstop": 0.02, "scale": 1.05, "chroma": 0.22},
}

## Surface response: how a style reads on each material class.
const SURFACE_MULT := {
	"flesh": {"cue": "", "shake": 1.0, "burst": 1.0},
	"plant": {"cue": "impact_plant", "shake": 0.9, "burst": 1.15},
	"stone": {"cue": "impact_stone", "shake": 1.35, "burst": 0.8},
}

## DebrisSystem shard flavor per surface class (weapon style nudges count).
const SURFACE_DEBRIS := {
	"stone": {"style": "rock", "count": 3},
	"plant": {"style": "wood", "count": 4},
	"flesh": {"style": "leaf", "count": 2},
}
const STYLE_DEBRIS_BONUS := {"blunt": 2, "claw": 1, "slash": 0, "magic": -1}

## Element payload palette + cues (rendered in AudioManager).
const ELEMENT_COLORS := {
	"fire": Color(1.0, 0.52, 0.16),
	"frost": Color(0.55, 0.85, 1.0),
	"shock": Color(0.98, 0.94, 0.55),
	"nature": Color(0.45, 0.85, 0.45),
}
const ELEMENT_CUES := {
	"fire": "elem_fire",
	"frost": "elem_frost",
	"shock": "elem_shock",
	"nature": "elem_nature",
}


## Resolve a full profile dict for a strike. Unknown keys fall back safely.
static func resolve(style: String, surface: String = "plant") -> Dictionary:
	var p: Dictionary = PROFILES.get(style, PROFILES["slash"])
	var sm: Dictionary = SURFACE_MULT.get(surface, SURFACE_MULT["plant"])
	var cue := str(sm.get("cue", ""))
	if cue.is_empty():
		cue = str(p.get("cue", ""))
	return {
		"cue": cue,
		"color": p.get("color", Color.WHITE),
		"shake": float(p.get("shake", 0.1)) * float(sm.get("shake", 1.0)),
		"hitstop": float(p.get("hitstop", 0.0)),
		"chroma": float(p.get("chroma", 0.2)),
		"burst": float(sm.get("burst", 1.0)),
	}


## Element for a weapon def: explicit field wins; relic kits fall back to a
## deterministic pick per name. Vanilla gear stays elementless.
static func element_for_weapon(weapon: Dictionary) -> String:
	var el := str(weapon.get("element", ""))
	if el in ELEMENTS:
		return el
	if not bool(weapon.get("relic", false)):
		return ""
	var n: String = str(weapon.get("name", ""))
	if n.is_empty():
		return ""
	return ELEMENTS[int(abs(n.hash())) % ELEMENTS.size()]


## Full strike feedback at the impact frame: cue, coordinated impact,
## surface burst and (optional) elemental payload.
static func apply_strike(context: Node, style: String, surface: String,
		hit_pos: Vector3, heavy: bool = false, element: String = "") -> void:
	if context == null or not context.is_inside_tree():
		return
	var audio := context.get_node_or_null("/root/AudioManager")
	var profile := resolve(style, surface)
	if audio != null and not str(profile.cue).is_empty():
		audio.play_cue(str(profile.cue))
	var mult := 1.6 if heavy else 1.0
	CombatFx.impact(context,
		float(profile.shake) * mult,
		float(profile.hitstop) * mult if heavy else float(profile.hitstop),
		0.22 if heavy else 0.08,
		minf(float(profile.chroma) * mult, 0.9))
	CombatFx.spawn_burst(context, hit_pos, profile.color,
		int(10 * float(profile.burst)) + (4 if heavy else 0), 5.5, 0.3)
	_spawn_debris(context, style, surface, hit_pos, heavy)
	if element in ELEMENTS:
		apply_element(context, element, hit_pos)


## Physical shard burst through the pooled DebrisSystem (tier-capped).
static func _spawn_debris(context: Node, style: String, surface: String,
		hit_pos: Vector3, heavy: bool) -> void:
	var debris := context.get_node_or_null("/root/WorldState/DebrisSystem")
	if debris == null or not debris.has_method("spawn_burst"):
		return
	var spec: Dictionary = SURFACE_DEBRIS.get(surface,
		SURFACE_DEBRIS["plant"])
	var count := int(spec.count) + int(STYLE_DEBRIS_BONUS.get(style, 0))
	if heavy:
		count += 3
	if count <= 0:
		return
	debris.spawn_burst(hit_pos, Vector3.UP, str(spec.style), count)


## Convenience for non-strike impacts (hard landings, prop breaks, slams).
static func spawn_impact_debris(context: Node, pos: Vector3,
		style: String, count: int, dir: Vector3 = Vector3.UP) -> void:
	var debris := context.get_node_or_null("/root/WorldState/DebrisSystem")
	if debris != null and debris.has_method("spawn_burst"):
		debris.spawn_burst(pos, dir, style, count)


## Elemental ground payload at a position — momentary FX + decal only.
static func apply_element(context: Node, element: String, pos: Vector3,
		radius: float = 1.6) -> void:
	if context == null or not context.is_inside_tree():
		return
	var color: Color = ELEMENT_COLORS.get(element, Color.WHITE)
	match element:
		"fire":
			CombatFx.spawn_decal(context, pos, radius * 0.7,
				Color(0.14, 0.07, 0.03, 0.8))
			CombatFx.spawn_burst(context, pos + Vector3(0, 0.2, 0), color,
				14, radius * 1.6, 0.42, 0.15)
			CombatFx.spawn_motes(context, pos, Color(color.r, color.g, color.b, 0.6),
				8, radius * 0.4, 0.8, 1.8)
		"frost":
			CombatFx.spawn_ring(context, pos, radius,
				Color(color.r, color.g, color.b, 0.75), 0.8)
			CombatFx.spawn_motes(context, pos + Vector3(0, 0.3, 0),
				Color(color.r, color.g, color.b, 0.5), 8, radius * 0.5, 0.7, 0.9)
		"shock":
			CombatFx.spawn_stretched_burst(context, pos + Vector3(0, 0.3, 0), color,
				12, radius * 3.2, 0.26)
			CombatFx.spawn_ring(context, pos, radius * 0.7,
				Color(color.r, color.g, color.b, 0.6), 0.4)
		"nature":
			CombatFx.spawn_motes(context, pos + Vector3(0, 0.25, 0),
				Color(color.r, color.g, color.b, 0.65), 14, radius * 0.5, 0.95, 2.0)
			CombatFx.spawn_pillar(context, pos, 2.4,
				Color(color.r, color.g, color.b, 0.5), 0.7, 0.6)
	var audio := context.get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.play_cue(str(ELEMENT_CUES.get(element, "")))


## Surface class for an enemy node (group-driven; default plant/flesh blend).
static func surface_for(enemy: Node) -> String:
	if enemy == null:
		return "plant"
	if enemy.is_in_group("boss"):
		return "stone"
	if enemy.is_in_group("hushling"):
		return "plant"
	return "flesh"
