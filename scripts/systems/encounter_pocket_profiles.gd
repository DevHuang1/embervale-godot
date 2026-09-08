extends RefCounted
class_name EncounterPocketProfiles

static func for_realm(realm: String, index: int, tier: String) -> Dictionary:
	var profiles := {
		"bramblewood": [{"id": "thorn_gate_%d" % index, "approach": "Follow the lantern path", "reveal": "Thorns stir ahead", "reward": "Warmth cache", "exit": "Beacon road"}, {"id": "root_clearing_%d" % index, "approach": "Cross the root bridge", "reveal": "The clearing wakes", "reward": "Rootbound cache", "exit": "Oakline trail"}],
		"mistfen": [{"id": "reed_hollow_%d" % index, "approach": "Listen beyond the reeds", "reveal": "Water ripples back", "reward": "Fen reliquary", "exit": "Moonlit boardwalk"}],
		"heartwood": [{"id": "ash_ring_%d" % index, "approach": "Cross the cooling stones", "reveal": "Embers break loose", "reward": "Forge cache", "exit": "Basalt ascent"}],
		"moonfen": [{"id": "storm_pool_%d" % index, "approach": "Trace the silver grass", "reveal": "The storm answers", "reward": "Moonfen cache", "exit": "Crystal causeway"}],
	}
	var realm_profiles: Array = profiles.get(realm, profiles["bramblewood"])
	var selected: Dictionary = realm_profiles[index % realm_profiles.size()].duplicate(true)
	if tier == "elite":
		selected["reveal"] = "%s elite emerges" % realm.capitalize()
	return selected
