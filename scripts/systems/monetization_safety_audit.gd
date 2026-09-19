extends RefCounted
class_name MonetizationSafetyAudit

const FORBIDDEN_URGENCY: Array[String] = ["limited time", "act now", "last chance", "buy now"]
const COSMETIC_KINDS: Array[String] = ["sfx", "trail", "aura"]

static func audit_sources(sources: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for source_id in sources:
		var source := str(sources[source_id]).to_lower()
		for phrase in FORBIDDEN_URGENCY:
			if source.contains(phrase):
				errors.append("Urgency language in %s: %s" % [source_id, phrase])
	return errors

static func audit_paid_catalog(items: Array) -> Array[String]:
	var errors: Array[String] = []
	for raw in items:
		if not raw is Dictionary:
			errors.append("Paid catalog entry must be an object")
			continue
		var item: Dictionary = raw
		var item_id := str(item.get("id", ""))
		var kind := str(item.get("kind", "")).to_lower()
		if item_id.is_empty() or float(item.get("price", 0.0)) <= 0.0:
			errors.append("Paid catalog entry has invalid id/price: %s" % item_id)
		if kind not in COSMETIC_KINDS:
			errors.append("Paid item is not cosmetic: %s" % item_id)
		for forbidden in ["atk", "attack", "armor", "defense", "crit", "damage", "stats"]:
			if item.has(forbidden):
				errors.append("Paid item contains gameplay power field %s: %s" % [forbidden, item_id])
	return errors
