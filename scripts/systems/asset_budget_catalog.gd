extends RefCounted
class_name AssetBudgetCatalog

## Review-time aggregate budgets for an Android-oriented vertical slice.
## These are presentation/content caps, not gameplay timing or damage rules.

const CATEGORY_LIMITS: Dictionary = {
	"hero": {"instances": 1, "materials": 12, "texture_mb": 32},
	"enemy": {"instances": 12, "materials": 48, "texture_mb": 64},
	"prop": {"instances": 80, "materials": 80, "texture_mb": 48},
	"foliage": {"instances": 64, "materials": 8, "texture_mb": 16},
	"vfx": {"instances": 24, "materials": 24, "texture_mb": 24},
	"ui": {"instances": 40, "materials": 20, "texture_mb": 24},
	"audio": {"instances": 24, "materials": 0, "texture_mb": 48},
}

static func validate_manifest(manifest: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for category in CATEGORY_LIMITS:
		var limit: Dictionary = CATEGORY_LIMITS[category]
		var measured: Dictionary = manifest.get(category, {})
		for field in ["instances", "materials", "texture_mb"]:
			var value := int(measured.get(field, 0))
			if value < 0:
				errors.append("Negative %s/%s measurement" % [category, field])
			elif value > int(limit[field]):
				errors.append("Budget exceeded %s/%s: %d > %d" % [
					category, field, value, int(limit[field])])
	return errors

static func empty_manifest() -> Dictionary:
	var manifest: Dictionary = {}
	for category in CATEGORY_LIMITS:
		manifest[category] = {"instances": 0, "materials": 0, "texture_mb": 0}
	return manifest
