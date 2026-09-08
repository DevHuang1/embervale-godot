extends RefCounted
class_name EnvironmentStoryCatalog

## Readable environmental clues for the five realms. These are authored
## composition prompts; they never create invisible collision or alter combat.
const REQUIRED_LAYERS: Array[String] = ["ruins", "camps", "trails", "tools", "gathering_traces", "creature_evidence"]
const STORIES: Dictionary = {
	"whispergrove": {"ruins": "weathered welcome arch", "camps": "warm lantern camp", "trails": "moss-lit path", "tools": "abandoned basket and hoe", "gathering_traces": "fresh moss cuttings", "creature_evidence": "tiny footprints beside flowers"},
	"bramblewood": {"ruins": "root-wrapped stone marker", "camps": "overgrown scout camp", "trails": "broken thorn lane", "tools": "notched pruning axe", "gathering_traces": "cut bramble stumps", "creature_evidence": "charger gouges and spitter husks"},
	"mistfen": {"ruins": "half-sunk grave marker", "camps": "collapsed reed shelter", "trails": "boardwalk fragments", "tools": "rusted fishing hook", "gathering_traces": "drawn reed bundles", "creature_evidence": "wet tracks around a still pool"},
	"heartwood": {"ruins": "ash-forge foundation", "camps": "cooling-stone refuge", "trails": "ember-marked route", "tools": "spent smithing tongs", "gathering_traces": "cracked emberstone vein", "creature_evidence": "hoof marks around vents"},
	"moonfen": {"ruins": "charged monolith ring", "camps": "stormwatch shelter", "trails": "crystal causeway", "tools": "broken survey rod", "gathering_traces": "fresh crystal chips", "creature_evidence": "scorched wetland marks"},
}

static func validate() -> Array[String]:
	var errors: Array[String] = []
	for realm_id in RealmIdentityCatalog.PROFILES:
		var story: Dictionary = STORIES.get(str(realm_id), {})
		for layer in REQUIRED_LAYERS:
			if str(story.get(layer, "")).strip_edges().is_empty():
				errors.append("Environment story missing %s for %s" % [layer, realm_id])
	return errors

static func for_realm(realm_id: String) -> Dictionary:
	return (STORIES.get(realm_id, {}) as Dictionary).duplicate(true)
