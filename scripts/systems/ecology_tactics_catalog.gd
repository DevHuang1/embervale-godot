extends RefCounted
class_name EcologyTacticsCatalog

## Small, readable ecology rules. Each rule exposes a player choice and a
## bounded consequence; it is data-only until a realm encounter opts in.
const RULES: Dictionary = {
	"whispergrove": {"trigger": "thorn_guardian_near_hushling", "choice": "pull the guardian into the open clearing or fight in darkness", "consequence": "clearing improves visibility; darkness preserves cover", "primary_modifiers": {"telegraph_readability": 1.2, "hazard_pressure": 0.9}},
	"bramblewood": {"trigger": "charger_near_spitter_nest", "choice": "break the nest first or bait the charger through it", "consequence": "nest pressure falls; charger becomes briefly staggered", "primary_modifiers": {"nest_pressure": 0.7, "elite_stagger_window": 1.25}},
	"mistfen": {"trigger": "wet_ground_near_fenling", "choice": "use shock to chain damage or wait for fog to clear", "consequence": "shock gains reach; waiting improves telegraph distance", "primary_modifiers": {"elemental_chain_range": 1.2, "telegraph_distance": 1.15}},
	"heartwood": {"trigger": "ember_add_near_vent", "choice": "use frost to cool the vent or fire to extend the hazard", "consequence": "cooling opens a safe lane; fire creates damage pressure", "primary_modifiers": {"hazard_pressure": 0.8, "safe_lane_width": 1.2}},
	"moonfen": {"trigger": "storm_spirit_near_wet_target", "choice": "thunder-chain the wet target or disengage before the flash", "consequence": "chain damage rises; disengaging avoids the delayed ring", "primary_modifiers": {"elemental_chain_damage": 1.15, "delayed_ring_radius": 0.8}},
}

static func validate() -> Array[String]:
	var errors: Array[String] = []
	for realm_id in RealmIdentityCatalog.PROFILES:
		var rule: Dictionary = RULES.get(str(realm_id), {})
		for field in ["trigger", "choice", "consequence"]:
			if str(rule.get(field, "")).is_empty():
				errors.append("Ecology rule %s missing %s" % [realm_id, field])
	return errors

static func rule_for(realm_id: String) -> Dictionary:
	return (RULES.get(realm_id, {}) as Dictionary).duplicate(true)
