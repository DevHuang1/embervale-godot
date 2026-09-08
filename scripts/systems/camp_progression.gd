extends Node

signal changed
signal notice(message: String)

const SAVE_VERSION: int = 2
const REALMS: Array[String] = ["whispergrove", "bramblewood"]
const OBJECTIVE_TARGETS: Dictionary = {"kills": 10, "boss": 1, "gather": 5, "discover": 1}
const FACILITIES: Dictionary = {
	"forge": {"name": "FORGE", "cost": {"iron_shard": 5, "crystal_fragment": 1}, "benefit": "Unlocks one weapon improvement tier."},
	"gatherer_grove": {"name": "GATHERER'S GROVE", "cost": {"moss_fiber": 8, "thorn_vine": 3}, "benefit": "Gathering yields one additional resource."},
	"lantern_beacon": {"name": "LANTERN BEACON", "cost": {"ember_shard": 1, "iron_shard": 3}, "benefit": "Unlocks the Grove camp shortcut."},
}

var camp_level: int = 1
var facilities: Dictionary = {}
var mastery: Dictionary = {}
var claimed_rewards: Dictionary = {}

func _ready() -> void:
	reset()

func reset() -> void:
	camp_level = 1
	facilities = {}
	mastery = {}
	claimed_rewards = {}
	for realm in REALMS:
		mastery[realm] = {"kills": 0, "boss": 0, "gather": 0, "discover": 0}

func facility_unlocked(id: String) -> bool:
	return bool(facilities.get(id, false))

func facility_definition(id: String) -> Dictionary:
	return (FACILITIES.get(id, {}) as Dictionary).duplicate(true)

func progress_for(realm: String, objective: String) -> int:
	return maxi(0, int(mastery_for(realm).get(objective, 0)))

func target_for(_realm: String, objective: String) -> int:
	return int(OBJECTIVE_TARGETS.get(objective, 1))

func mastery_for(realm: String) -> Dictionary:
	var fallback: Dictionary = {"kills": 0, "boss": 0, "gather": 0, "discover": 0}
	return (mastery.get(realm, fallback) as Dictionary).duplicate(true)

func mastery_total(realm: String) -> int:
	var total: int = 0
	for objective in OBJECTIVE_TARGETS:
		if progress_for(realm, str(objective)) >= target_for(realm, str(objective)):
			total += 1
	return total

func is_realm_mastered(realm: String) -> bool:
	return mastery_total(realm) == OBJECTIVE_TARGETS.size()

func record_objective(realm: String, objective: String, amount: int = 1) -> void:
	if not OBJECTIVE_TARGETS.has(objective):
		return
	if not mastery.has(realm):
		mastery[realm] = {"kills": 0, "boss": 0, "gather": 0, "discover": 0}
	var entry: Dictionary = mastery[realm]
	entry[objective] = mini(target_for(realm, objective), maxi(0, int(entry.get(objective, 0)) + maxi(1, amount)))
	mastery[realm] = entry
	if is_realm_mastered(realm):
		claim_mastery_reward(realm)
	changed.emit()

func gather_yield_bonus() -> int:
	return 1 if facility_unlocked("gatherer_grove") else 0

func weapon_upgrade_cap() -> int:
	return 6 if facility_unlocked("forge") else 5

func is_shortcut_unlocked(realm: String, shortcut_id: String) -> bool:
	return facility_unlocked("lantern_beacon") and realm == "bramblewood" and shortcut_id == "camp_route"

func camp_material_id() -> String:
	return "camp_ember"

func build_debug_snapshot() -> Dictionary:
	var totals: Dictionary = {}
	for realm in REALMS:
		totals[realm] = mastery_total(realm)
	return {
		"version": SAVE_VERSION,
		"camp_level": camp_level,
		"facilities": facilities.duplicate(true),
		"mastery": mastery.duplicate(true),
		"mastery_totals": totals,
		"claimed_rewards": claimed_rewards.duplicate(true),
	}

func unlock_shortcut(realm: String, shortcut_id: String) -> bool:
	if not is_shortcut_unlocked(realm, shortcut_id):
		return false
	var world := get_tree().current_scene
	if world != null and world.has_method("activate_camp_shortcut"):
		world.activate_camp_shortcut(realm, shortcut_id)
	return true

func purchase_facility(id: String) -> bool:
	if facility_unlocked(id) or not FACILITIES.has(id):
		return false
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return false
	var cost: Dictionary = FACILITIES[id].cost
	for material in cost:
		if int(gs.call("get_material_qty", str(material))) < int(cost[material]):
			notice.emit("MISSING %d %s" % [int(cost[material]), str(material).replace("_", " ").to_upper()])
			return false
	for material in cost:
		gs.call("remove_material", str(material), int(cost[material]))
	facilities[id] = true
	camp_level = mini(4, camp_level + 1)
	claimed_rewards["facility_%s" % id] = true
	gs.call("save_game")
	if id == "lantern_beacon":
		unlock_shortcut("bramblewood", "camp_route")
	changed.emit()
	notice.emit("%s UNLOCKED" % str(FACILITIES[id].name))
	return true

func claim_mastery_reward(realm: String) -> bool:
	if not is_realm_mastered(realm) or bool(claimed_rewards.get("mastery_%s" % realm, false)):
		return false
	claimed_rewards["mastery_%s" % realm] = true
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.call("add_material", "camp_ember", 1)
		gs.call("save_game")
	notice.emit("%s MASTERED · CAMP EMBER EARNED" % realm.to_upper())
	return true

func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "camp_level": camp_level, "facilities": facilities.duplicate(true), "mastery": mastery.duplicate(true), "claimed_rewards": claimed_rewards.duplicate(true)}

func from_dict(payload: Variant) -> void:
	reset()
	if not payload is Dictionary:
		return
	var data: Dictionary = payload
	camp_level = clampi(int(data.get("camp_level", 1)), 1, 4)
	var saved_facilities: Variant = data.get("facilities", {})
	if saved_facilities is Dictionary:
		for id in FACILITIES:
			facilities[id] = bool(saved_facilities.get(id, false))
	var saved_mastery: Variant = data.get("mastery", {})
	var old_version: int = int(data.get("version", 0))
	if saved_mastery is Dictionary:
		for realm in REALMS:
			var entry: Variant = saved_mastery.get(realm, {})
			if entry is Dictionary:
				for objective in OBJECTIVE_TARGETS:
					var value := clampi(int(entry.get(objective, 0)), 0, target_for(realm, str(objective)))
					if old_version < 2 and value == 1 and target_for(realm, str(objective)) > 1:
						value = target_for(realm, str(objective))
					mastery[realm][objective] = value
	var saved_claims: Variant = data.get("claimed_rewards", {})
	if saved_claims is Dictionary:
		claimed_rewards = saved_claims.duplicate(true)
	changed.emit()
