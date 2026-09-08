extends RefCounted
class_name RealmModularKitCatalog

const REQUIRED_COMPONENTS: Array[String] = [
	"ground_cover", "flowers", "gardens", "fields", "bushes", "pines",
	"cactuses", "ponds", "rocks", "ruins", "realm_accents"
]

const KITS: Dictionary = {
	"whispergrove": {"palette": "living_green", "component_keys": REQUIRED_COMPONENTS, "components": ["grass", "tiny flowers", "moss gardens", "flower fields", "small bushes", "pines", "ponds", "rocks", "nature ruins", "fireflies"]},
	"bramblewood": {"palette": "thorn_olive", "component_keys": REQUIRED_COMPONENTS, "components": ["grass", "thorn flowers", "root gardens", "clearing fields", "big bushes", "pines", "mud ponds", "rocks", "graveyard ruins", "thorn accents"]},
	"mistfen": {"palette": "fog_teal", "component_keys": REQUIRED_COMPONENTS, "components": ["wet grass", "fen flowers", "reed gardens", "reed fields", "fen bushes", "pines", "ponds", "mud", "stone ruins", "fireflies"]},
	"heartwood": {"palette": "ember_ash", "component_keys": REQUIRED_COMPONENTS, "components": ["ash grass", "ember flowers", "cinder gardens", "ash fields", "charred bushes", "pines", "magma ponds", "lava rocks", "forge ruins", "ember accents"]},
	"moonfen": {"palette": "moon_blue", "component_keys": REQUIRED_COMPONENTS, "components": ["moon grass", "ice flowers", "crystal gardens", "frost fields", "snow bushes", "pines", "ice ponds", "crystal rocks", "monolith ruins", "thunder accents"]},
}

static func validate() -> Array[String]:
	var errors: Array[String] = []
	for realm_id in RealmIdentityCatalog.PROFILES:
		var kit: Dictionary = KITS.get(str(realm_id), {})
		if kit.is_empty():
			errors.append("Missing modular realm kit: %s" % realm_id)
			continue
		if str(kit.get("palette", "")).is_empty():
			errors.append("Modular kit missing palette: %s" % realm_id)
		var components: Array = kit.get("components", [])
		var component_keys: Array = kit.get("component_keys", [])
		for required in REQUIRED_COMPONENTS:
			if required not in component_keys:
				errors.append("Kit %s missing component: %s" % [realm_id, required])
		if components.size() < REQUIRED_COMPONENTS.size() - 1:
			errors.append("Kit %s is too sparse" % realm_id)
	return errors
