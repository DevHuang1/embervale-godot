extends RefCounted
class_name BossCompoundCatalog

## Data-driven compound identity for every canonical boss. Each boss owns a
## visually distinct "compound" — the large, bounded ruin the boss haunts — so
## no two bosses share the same landmark. Presentation only: the kind, label and
## radius hints below never change encounter timing, damage, hitboxes, or reset
## semantics. Combat tint is still sourced from the boss roster palette.

const COMPOUND_KINDS := {
	"whispergrove_root_harrow": {
		"kind": "overgrown_shrine",
		"label": "MOSS-SUNK SHRINE",
		"radius": 22.0,
		"trigger": 5.5,
	},
	"bramblewood_thorn_regent": {
		"kind": "thorn_court",
		"label": "THORN CROWN COURT",
		"radius": 24.0,
		"trigger": 6.0,
	},
	"bramblewood_briar_widow": {
		"kind": "widow_grove",
		"label": "ROOT-SEWN GROVE",
		"radius": 20.0,
		"trigger": 5.5,
	},
	"mistfen_fogmaw": {
		"kind": "sunken_maw",
		"label": "DROWNED MAW",
		"radius": 22.0,
		"trigger": 5.5,
	},
	"heartwood_cinderhart": {
		"kind": "cinder_foundry",
		"label": "BROKEN FOUNDRY",
		"radius": 24.0,
		"trigger": 6.0,
	},
	"heartwood_ash_bellower": {
		"kind": "ash_belltower",
		"label": "FALLEN BELLTOWER",
		"radius": 20.0,
		"trigger": 5.5,
	},
	"moonfen_tide_oracle": {
		"kind": "tide_sanctum",
		"label": "SUNKEN SANCTUM",
		"radius": 22.0,
		"trigger": 5.5,
	},
	"moonfen_lunar_leviathan": {
		"kind": "lunar_henge",
		"label": "LUNAR HENGE",
		"radius": 26.0,
		"trigger": 6.5,
	},
}

## Defaults for the three enterable-structure bosses (Keep Warden, Hollowroot
## Matron, the Sealed One) and any unknown id, keyed by realm so a future boss
## still lands on a thematically correct compound rather than a shared circle.
const REALM_DEFAULT := {
	"whispergrove": {"kind": "overgrown_shrine", "label": "OVERGROWN SHRINE"},
	"bramblewood": {"kind": "thorn_court", "label": "THORN CROWN COURT"},
	"mistfen": {"kind": "sunken_maw", "label": "DROWNED MAW"},
	"heartwood": {"kind": "cinder_foundry", "label": "BROKEN FOUNDRY"},
	"moonfen": {"kind": "lunar_henge", "label": "LUNAR HENGE"},
}

static func theme_for(boss_id: String) -> Dictionary:
	var canonical := BossRosterCatalog.canonical_id_for(boss_id)
	if COMPOUND_KINDS.has(canonical):
		return (COMPOUND_KINDS[canonical] as Dictionary).duplicate(true)
	var definition := BossRosterCatalog.definition_for(canonical)
	var realm := str(definition.get("realm", "bramblewood"))
	var fallback := REALM_DEFAULT.get(realm, REALM_DEFAULT["bramblewood"]) as Dictionary
	var result: Dictionary = fallback.duplicate(true)
	result["radius"] = 22.0
	result["trigger"] = 5.5
	return result

static func label_for(boss_id: String) -> String:
	return str(theme_for(boss_id).get("label", "RUINED SHRINE"))
