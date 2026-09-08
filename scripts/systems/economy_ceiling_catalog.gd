extends RefCounted
class_name EconomyCeilingCatalog

const RULES: Array[Dictionary] = [
	{"currency": "gold", "purpose": "gear_and_crafting", "earn_route": "combat, gathering, quests, selling", "paid": false, "gameplay_critical": true},
	{"currency": "diamonds", "purpose": "cosmetics_only", "earn_route": "boss milestones and optional provider grants", "paid": true, "gameplay_critical": false},
	{"currency": "scans", "purpose": "photo_forging", "earn_route": "free starter grants, quests, boss milestones, fragments", "paid": false, "gameplay_critical": false},
]

static func validate() -> Array[String]:
	var errors: Array[String] = []
	for rule in RULES:
		for field in ["currency", "purpose", "earn_route"]:
			if str(rule.get(field, "")).is_empty():
				errors.append("Economy rule missing %s" % field)
		if bool(rule.get("paid", false)) and bool(rule.get("gameplay_critical", true)):
			errors.append("Paid currency cannot be gameplay-critical: %s" % rule.get("currency", ""))
	return errors
