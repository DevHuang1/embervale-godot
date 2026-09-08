extends RefCounted
class_name BossRewardCatalog

## Alternate boss-reward directions. Existing guaranteed drops remain intact;
## this catalog is the data contract for a future post-boss choice panel.

const CHOICES := {
	"bramblewood_thornwarden": [
		{"id": "matriarch_scepter", "title": "HEARTWOOD SPEAR", "build_tag": "Nature control", "summary": "Root pressure, thorn reach, and a restorative bloom."},
		{"id": "warden_plate", "title": "THORN WARDEN PLATE", "build_tag": "Frontline guard", "summary": "Reliable defense and stagger safety against heavy strikes."},
	],
	"hushling_matriarch": [
		{"id": "matriarch_scepter", "title": "CROWN OF THE OLD ROOT", "build_tag": "Nature control", "summary": "Magic zoning, root pressure, and a healing bloom."},
		{"id": "warden_plate", "title": "MATRIARCH WARDEN PLATE", "build_tag": "Frontline guard", "summary": "Trade speed for reliable damage reduction and stagger safety."},
	],
	"moonfen_matriarch": [
		{"id": "arcane_staff", "title": "MOONBOUGH", "build_tag": "Elemental zoning", "summary": "Long-range bursts and wide elemental control."},
		{"id": "emberweave_cloak", "title": "MOONFEN CLOAK", "build_tag": "Swift caster", "summary": "Movement and recovery for safer repositioning."},
	],
}

static func choices_for(boss_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for choice in CHOICES.get(boss_id, []):
		result.append((choice as Dictionary).duplicate(true))
	return result
