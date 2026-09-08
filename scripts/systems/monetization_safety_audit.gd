extends RefCounted
class_name MonetizationSafetyAudit

const FORBIDDEN_URGENCY: Array[String] = ["limited time", "act now", "last chance", "buy now"]
const REQUIRED_SCAN_DISCLOSURES: Array[String] = ["duplicate_behavior", "restore_path", "BALANCE %d/%d", "No guaranteed legendary result"]

static func audit_sources(sources: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var scan_source := ""
	for source_id in sources:
		var source := str(sources[source_id]).to_lower()
		scan_source += source
		for phrase in FORBIDDEN_URGENCY:
			if source.contains(phrase):
				errors.append("Urgency language in %s: %s" % [source_id, phrase])
	for disclosure in REQUIRED_SCAN_DISCLOSURES:
		if not scan_source.contains(disclosure.to_lower()):
			errors.append("Scan offer missing disclosure: %s" % disclosure)
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
		if kind not in ["sfx", "trail", "aura", "scan_pack"]:
			errors.append("Paid item is not cosmetic or disclosed scan utility: %s" % item_id)
		for forbidden in ["atk", "attack", "armor", "defense", "crit", "damage", "stats"]:
			if item.has(forbidden):
				errors.append("Paid item contains gameplay power field %s: %s" % [forbidden, item_id])
		if kind == "scan_pack" and (not item.has("duplicate_behavior") or not item.has("restore_path")):
			errors.append("Scan pack lacks duplicate/restore policy: %s" % item_id)
	return errors
