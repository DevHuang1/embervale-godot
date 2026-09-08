extends RefCounted
class_name LicenseAudit

static func validate_catalog(entries: Array[Dictionary], credits_text: String) -> Array[String]:
	var errors: Array[String] = []
	for entry in entries:
		var id := str(entry.get("id", ""))
		var license := str(entry.get("license", ""))
		var source := str(entry.get("source_url", ""))
		var license_path := str(entry.get("license_file", ""))
		if license in ["", "UNKNOWN"] or license_path.is_empty():
			errors.append("License is not cleared: %s" % id)
		if not FileAccess.file_exists(license_path):
			errors.append("License evidence is missing: %s" % id)
		if not source.begins_with("https://"):
			errors.append("Source URL is not HTTPS: %s" % id)
		# The credits table must identify the pack, license, evidence filename,
		# and source URL; otherwise release attribution is incomplete.
		for marker in [str(entry.get("pack", id)), license, license_path.get_file(), source]:
			if not credits_text.contains(marker):
				errors.append("Credits document missing %s for %s" % [marker, id])
	return errors
