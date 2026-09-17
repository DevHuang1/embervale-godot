extends RefCounted
class_name RealmActivityCatalog

## Stable, authored activity beats for every playable realm.  This catalog is
## data-only: the director owns activation, persistence, and scene lifetime.

const LAYOUT := preload("res://scripts/world/realm_layout_data.gd")
const REALMS: Array[String] = ["whispergrove", "bramblewood", "mistfen", "heartwood", "moonfen"]
const ACTIVITY_TYPES: Array[String] = [
	"combat_patrol", "combat_ambush", "gathering", "discovery", "beacon", "cache"
]
const MIN_SPACING: float = 4.0
const LIFE_BEHAVIORS: Dictionary = {
	"whispergrove": {"combat_patrol": "crossing", "combat_ambush": "skitter", "gathering": "drift", "discovery": "orbit", "beacon": "rise", "cache": "crossing"},
	"bramblewood": {"combat_patrol": "crossing", "combat_ambush": "skitter", "gathering": "skitter", "discovery": "orbit", "beacon": "rise", "cache": "crossing"},
	"mistfen": {"combat_patrol": "crossing", "combat_ambush": "skitter", "gathering": "drift", "discovery": "orbit", "beacon": "rise", "cache": "crossing"},
	"heartwood": {"combat_patrol": "rise", "combat_ambush": "skitter", "gathering": "rise", "discovery": "orbit", "beacon": "rise", "cache": "crossing"},
	"moonfen": {"combat_patrol": "orbit", "combat_ambush": "skitter", "gathering": "orbit", "discovery": "orbit", "beacon": "rise", "cache": "crossing"},
}

const ACTIVITIES: Dictionary = {
	"whispergrove": [
		{"id": "whisper_lantern_path", "type": "discovery", "position": Vector3(-3, 0, -2),
			"label": "Lantern Path Discovery", "description": "A warm trail marker glows between the roots.",
			"reward": {"type": "scan_fragment", "quantity": 1}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "whisper_lantern_map", "label": "Lantern path revealed"}},
		{"id": "whisper_moss_cache", "type": "gathering", "position": Vector3(-11, 0, -5),
			"label": "Warm Moss Cache", "description": "Soft moss gathers beneath a fallen lantern post.",
			"reward": {"type": "material", "id": "moss_fiber", "quantity": 2}, "material_id": "moss_fiber",
			"yield_min": 1, "yield_max": 2, "persistence": "repeatable", "cooldown_seconds": 45.0},
		{"id": "whisper_sprite_glimmer", "type": "combat_patrol", "position": Vector3(0, 0, -11),
			"label": "Sprite Glimmer Patrol", "description": "A playful rustle turns into a gentle hushling patrol.",
			"reward": {"type": "gold", "quantity": 8}, "persistence": "repeatable",
			"cooldown_seconds": 55.0, "enemy_tier": "normal"},
		{"id": "whisper_lantern_bend", "type": "beacon", "position": Vector3(10, 0, -12),
			"label": "Lantern Bend", "description": "A half-buried lantern remembers the safe route.",
			"reward": {"type": "scan_fragment", "quantity": 1}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "whisper_safe_bend", "label": "Safe bend marked"}},
		{"id": "whisper_rootstone_salvage", "type": "gathering", "position": Vector3(12, 0, -4),
			"label": "Rootstone Salvage", "description": "A small rootstone vein can be gathered without leaving the path.",
			"reward": {"type": "material", "id": "bramble_wood", "quantity": 2}, "material_id": "bramble_wood",
			"yield_min": 1, "yield_max": 2, "persistence": "repeatable", "cooldown_seconds": 50.0},
		{"id": "whisper_hidden_cache", "type": "cache", "position": Vector3(18, 0, -1),
			"label": "Sprite Cache", "description": "A sprite has tucked a small cache beside the old path.",
			"reward": {"type": "gold", "quantity": 20}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "whisper_sprite_cache", "label": "Sprite cache claimed"}},
	],
	"bramblewood": [
		{"id": "bramble_thorn_patrol", "type": "combat_patrol", "position": Vector3(31, 0, -65),
			"label": "Thorn Patrol", "description": "A charger patrol circles the cut road.",
			"reward": {"type": "material", "id": "beast_hide", "quantity": 1}, "persistence": "repeatable",
			"cooldown_seconds": 50.0, "enemy_tier": "hard"},
		{"id": "bramble_rootcut_cache", "type": "gathering", "position": Vector3(57, 0, -99),
			"label": "Rootcut Material Cache", "description": "Fresh-cut roots expose wood and iron beneath the gully.",
			"reward": {"type": "material", "id": "bramble_wood", "quantity": 3}, "material_id": "bramble_wood",
			"yield_min": 2, "yield_max": 3, "persistence": "repeatable", "cooldown_seconds": 55.0},
		{"id": "bramble_forester_relic", "type": "discovery", "position": Vector3(95, 0, -137),
			"label": "Forester Relic", "description": "A weathered route token points toward the breached beacon.",
			"reward": {"type": "gold", "quantity": 24}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "bramble_forester_route", "label": "Forester route revealed"}},
		{"id": "bramble_charger_ambush", "type": "combat_ambush", "position": Vector3(137, 0, -176),
			"label": "Charger Ambush", "description": "The beacon breach hides a charger and a space-controlling spitter.",
			"reward": {"type": "material", "id": "iron_shard", "quantity": 1}, "persistence": "repeatable",
			"cooldown_seconds": 65.0, "enemy_tier": "hard"},
		{"id": "bramble_beacon_watch", "type": "beacon", "position": Vector3(151, 0, -195),
			"label": "Breached Beacon Watch", "description": "A broken beacon still flashes a readable route signal.",
			"reward": {"type": "scan_fragment", "quantity": 1}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "bramble_beacon_route", "label": "Beacon route marked"}},
		{"id": "bramble_rootway_cache", "type": "cache", "position": Vector3(198, 0, -226),
			"label": "Rootway Side Cache", "description": "A valuable cache sits just off the court approach.",
			"reward": {"type": "material", "id": "iron_shard", "quantity": 2}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "bramble_side_route", "label": "Rootway side route revealed"}},
	],
	"mistfen": [
		{"id": "mistfen_fog_window", "type": "discovery", "position": Vector3(-4, 0, -1),
			"label": "Fog Window", "description": "A brief clear pocket reveals the safe reed-bank crossing.",
			"reward": {"type": "scan_fragment", "quantity": 1}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "mistfen_fog_window", "label": "Fog window marked"}},
		{"id": "mistfen_reed_bank", "type": "gathering", "position": Vector3(-17, 0, -4),
			"label": "Reed-Bank Cache", "description": "Tall reeds hide a harvestable pocket beside the water.",
			"reward": {"type": "material", "id": "fen_reed", "quantity": 3}, "material_id": "fen_reed",
			"yield_min": 2, "yield_max": 3, "persistence": "repeatable", "cooldown_seconds": 50.0},
		{"id": "mistfen_leech_patrol", "type": "combat_patrol", "position": Vector3(-8, 0, -17),
			"label": "Leech Patrol", "description": "Relic leeches stir under the fog bank.",
			"reward": {"type": "material", "id": "spore_dust", "quantity": 1}, "persistence": "repeatable",
			"cooldown_seconds": 55.0, "enemy_tier": "normal"},
		{"id": "mistfen_stillwater", "type": "beacon", "position": Vector3(2, 0, -22),
			"label": "Stillwater Signal", "description": "A fen marker pulses when the fog briefly thins.",
			"reward": {"type": "gold", "quantity": 18}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "mistfen_stillwater", "label": "Stillwater route marked"}},
		{"id": "mistfen_fenling_encounter", "type": "combat_ambush", "position": Vector3(10, 0, -15),
			"label": "Fenling Ambush", "description": "A fenling and relic leech contest the narrow bank.",
			"reward": {"type": "gold", "quantity": 22}, "persistence": "repeatable",
			"cooldown_seconds": 65.0, "enemy_tier": "hard"},
		{"id": "mistfen_reliquary_cache", "type": "cache", "position": Vector3(3, 0, -28),
			"label": "Fogbound Reliquary", "description": "A relic cache waits below the last boardwalk.",
			"reward": {"type": "material", "id": "spore_dust", "quantity": 2}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "mistfen_reliquary_route", "label": "Reliquary route revealed"}},
	],
	"heartwood": [
		{"id": "heartwood_cooling_mark", "type": "discovery", "position": Vector3(2, 0, -2),
			"label": "Cooling Mark", "description": "Ash marks show the safe side of the first vent lane.",
			"reward": {"type": "gold", "quantity": 15}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "heartwood_cooling_lane", "label": "Cooling lane marked"}},
		{"id": "heartwood_emberstone_salvage", "type": "gathering", "position": Vector3(-1, 0, -7),
			"label": "Emberstone Salvage", "description": "A cooling seam exposes emberstone between vent pulses.",
			"reward": {"type": "material", "id": "emberstone", "quantity": 2}, "material_id": "emberstone",
			"yield_min": 1, "yield_max": 2, "persistence": "repeatable", "cooldown_seconds": 50.0},
		{"id": "heartwood_ash_patrol", "type": "combat_patrol", "position": Vector3(0, 0, -19),
			"label": "Ash Patrol", "description": "Ash wardens cross the cooling lane between vent breaths.",
			"reward": {"type": "material", "id": "monster_core", "quantity": 1}, "persistence": "repeatable",
			"cooldown_seconds": 55.0, "enemy_tier": "normal"},
		{"id": "heartwood_vent_signal", "type": "beacon", "position": Vector3(10, 0, -25),
			"label": "Vent Signal", "description": "A heat-safe marker flashes beside the ash route.",
			"reward": {"type": "scan_fragment", "quantity": 1}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "heartwood_vent_route", "label": "Vent route marked"}},
		{"id": "heartwood_ash_ambush", "type": "combat_ambush", "position": Vector3(14, 0, -15),
			"label": "Ash Ambush", "description": "Heat pressure drives an elite pack out of the vent shadow.",
			"reward": {"type": "gold", "quantity": 24}, "persistence": "repeatable",
			"cooldown_seconds": 65.0, "enemy_tier": "hard"},
		{"id": "heartwood_forge_cache", "type": "cache", "position": Vector3(-10, 0, -24),
			"label": "Cooling-Lane Cache", "description": "A sealed cache rewards a careful route around the ash.",
			"reward": {"type": "material", "id": "emberstone", "quantity": 3}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "heartwood_forge_route", "label": "Forge route revealed"}},
	],
	"moonfen": [
		{"id": "moonfen_crystal_causeway", "type": "discovery", "position": Vector3(4, 0, 0),
			"label": "Crystal Causeway", "description": "A crystal line shows the safest way across the moon pools.",
			"reward": {"type": "gold", "quantity": 18}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "moonfen_crystal_causeway", "label": "Crystal causeway marked"}},
		{"id": "moonfen_storm_lull", "type": "gathering", "position": Vector3(7, 0, 6),
			"label": "Storm-Lull Gathering", "description": "A quiet interval leaves moonmoss exposed beside the causeway.",
			"reward": {"type": "material", "id": "moonmoss", "quantity": 2}, "material_id": "moonmoss",
			"yield_min": 1, "yield_max": 2, "persistence": "repeatable", "cooldown_seconds": 50.0},
		{"id": "moonfen_leech_patrol", "type": "combat_patrol", "position": Vector3(14, 0, -10),
			"label": "Moonfen Patrol", "description": "Fenlings and relic leeches circle a charged pool.",
			"reward": {"type": "material", "id": "crystal_fragment", "quantity": 1}, "persistence": "repeatable",
			"cooldown_seconds": 55.0, "enemy_tier": "normal"},
		{"id": "moonfen_lull_beacon", "type": "beacon", "position": Vector3(2, 0, -17),
			"label": "Storm-Lull Beacon", "description": "The beacon pulses only while the storm rests.",
			"reward": {"type": "scan_fragment", "quantity": 1}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "moonfen_storm_lull", "label": "Storm lull marked"}},
		{"id": "moonfen_relic_ambush", "type": "combat_ambush", "position": Vector3(-8, 0, -19),
			"label": "Relic Ambush", "description": "A wet crystal shelf hides a fenling and relic leech pair.",
			"reward": {"type": "gold", "quantity": 26}, "persistence": "repeatable",
			"cooldown_seconds": 65.0, "enemy_tier": "hard"},
		{"id": "moonfen_islet_cache", "type": "cache", "position": Vector3(-13, 0, -6),
			"label": "Islet Side Cache", "description": "A small cache sits beyond the crystal causeway.",
			"reward": {"type": "material", "id": "crystal_fragment", "quantity": 2}, "persistence": "one_time",
			"cooldown_seconds": 0.0, "soft_unlock": {"id": "moonfen_islet_route", "label": "Islet side route revealed"}},
	],
}

## === Route-aware placement ===
## The six beats per realm used to sit in a cluster around spawn while the boss
## arena sat 90-170 m down the route, so the middle of every run had no live
## content. Each beat is now interpolated along its realm's authored route.
## Progress is compressed away from both ends: 0 would put a beat on the spawn
## point and 1 would put it inside the boss arena.
const ROUTE_PROGRESS_MIN := 0.08
const ROUTE_PROGRESS_MAX := 0.82
## An activity must keep this far from arenas, caves, checkpoints, chests,
## resources, encounters and expansion pockets (mirrors validate()).
const CLEARANCE_RADIUS := 3.5
const CLEARANCE_PROGRESS_STEP := 0.02
const CLEARANCE_MAX_STEPS := 14

## Point at `progress` along the realm's route polyline, measured by arc length
## so beats are evenly spaced in metres rather than per-waypoint.
static func route_position(realm_id: String, progress: float) -> Vector3:
	var profile: Dictionary = LAYOUT.profile(realm_id)
	var route: Array = profile.get("route", [])
	if route.size() < 2:
		return Vector3.ZERO
	var lengths: Array[float] = []
	var total := 0.0
	for i in route.size() - 1:
		var a := route[i] as Vector3
		var b := route[i + 1] as Vector3
		var segment := Vector2(b.x - a.x, b.z - a.z).length()
		lengths.append(segment)
		total += segment
	if total <= 0.001:
		return route[0] as Vector3
	var target := clampf(progress, 0.0, 1.0) * total
	var travelled := 0.0
	for i in lengths.size():
		var segment := lengths[i]
		if travelled + segment >= target or i == lengths.size() - 1:
			var local := 0.0 if segment <= 0.001 else (target - travelled) / segment
			var a := route[i] as Vector3
			var b := route[i + 1] as Vector3
			return a.lerp(b, clampf(local, 0.0, 1.0))
		travelled += segment
	return route[route.size() - 1] as Vector3

## Every authored point an activity must not overlap, plus each previously
## placed beat (added as it is placed, so neighbours cannot converge).
static func blocking_zones(realm_id: String) -> Array[Dictionary]:
	var profile: Dictionary = LAYOUT.profile(realm_id)
	var zones: Array[Dictionary] = []
	for key in ["arena", "cave", "checkpoint"]:
		var value: Variant = profile.get(key, Vector3.ZERO)
		if value is Vector3:
			zones.append({"pos": value as Vector3, "radius": CLEARANCE_RADIUS})
	for field in ["encounters", "chests", "resources"]:
		for entry_value in profile.get(field, []) as Array:
			if not entry_value is Dictionary:
				continue
			var pos: Variant = (entry_value as Dictionary).get("pos", Vector3.ZERO)
			if pos is Vector3:
				zones.append({"pos": pos as Vector3, "radius": CLEARANCE_RADIUS})
	for pocket_value in profile.get("expansion_pockets", []) as Array:
		if not pocket_value is Dictionary:
			continue
		var pocket_pos: Variant = (pocket_value as Dictionary).get("position", Vector3.ZERO)
		if pocket_pos is Vector3:
			zones.append({"pos": pocket_pos as Vector3, "radius": CLEARANCE_RADIUS})
	return zones

static func position_clear(candidate: Vector3, zones: Array[Dictionary]) -> bool:
	for zone in zones:
		var pos: Vector3 = zone.get("pos", Vector3.ZERO)
		if candidate.distance_to(pos) < float(zone.get("radius", CLEARANCE_RADIUS)):
			return false
	return true

## Walk the route forward until the beat clears every zone, so placement stays
## route-driven without ever parking a cache inside a boss arena, a chest, the
## spawn checkpoint, or another beat.
static func resolve_route_position(realm_id: String, progress: float,
		zones: Array[Dictionary]) -> Vector3:
	var candidate_progress := clampf(progress, ROUTE_PROGRESS_MIN, ROUTE_PROGRESS_MAX)
	var candidate := route_position(realm_id, candidate_progress)
	var step := 0
	while not position_clear(candidate, zones) and step < CLEARANCE_MAX_STEPS:
		step += 1
		candidate_progress = minf(candidate_progress + CLEARANCE_PROGRESS_STEP, 0.95)
		candidate = route_position(realm_id, candidate_progress)
	return candidate

static func for_realm(realm_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var entries: Array = ACTIVITIES.get(realm_id, []) as Array
	var zones := blocking_zones(realm_id)
	for index in entries.size():
		var entry: Dictionary = (entries[index] as Dictionary).duplicate(true)
		var activity_type := str(entry.get("type", ""))
		var behavior_map: Dictionary = LIFE_BEHAVIORS.get(realm_id, {})
		var span := float(maxi(entries.size() - 1, 1))
		var progress := lerpf(ROUTE_PROGRESS_MIN, ROUTE_PROGRESS_MAX, float(index) / span)
		var position := resolve_route_position(realm_id, progress, zones)
		zones.append({"pos": position, "radius": MIN_SPACING})
		entry["route_progress"] = progress
		entry["position"] = position
		entry["presentation_type"] = "patrol" if activity_type in ["combat_patrol", "combat_ambush"] else "world_life"
		entry["life_behavior"] = str(behavior_map.get(activity_type, "drift"))
		entry["life_visible_radius"] = 48.0
		entry["life_activation_radius"] = 18.0
		entry["life_unload_radius"] = 75.0
		entry["life_count"] = 4 if activity_type in ["combat_patrol", "combat_ambush"] else 3
		entry["life_duration_seconds"] = 28.0 if str(entry.get("persistence", "")) == "repeatable" else 0.0
		entry["life_label"] = str(entry.get("label", entry.get("id", "WORLD LIFE")))
		result.append(entry)
	return result

static func all_activity_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for realm_id in REALMS:
		for entry in for_realm(realm_id):
			result.append(entry)
	return result

static func validate() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for realm_id in REALMS:
		var definitions := for_realm(realm_id)
		if definitions.size() != 6:
			errors.append("%s must have six activities" % realm_id)
		var profile: Dictionary = LAYOUT.profile("bramblewood" if realm_id == "bramblewood" else realm_id)
		var anchors: Array[Vector3] = []
		for route_value in profile.get("route", []) as Array:
			anchors.append(route_value as Vector3)
		for pocket_value in profile.get("expansion_pockets", []) as Array:
			anchors.append((pocket_value as Dictionary).get("position", Vector3.ZERO) as Vector3)
		for entry in definitions:
			var activity_id := str(entry.get("id", ""))
			var prefix := "%s.%s" % [realm_id, activity_id]
			if activity_id.is_empty() or seen.has(activity_id):
				errors.append("duplicate or empty activity id: %s" % prefix)
			seen[activity_id] = true
			if str(entry.get("type", "")) not in ACTIVITY_TYPES:
				errors.append("invalid activity type: %s" % prefix)
			if not (entry.get("position", null) is Vector3):
				errors.append("missing position: %s" % prefix)
			if not (entry.get("reward", null) is Dictionary) or (entry.get("reward", {}) as Dictionary).is_empty():
				errors.append("missing reward: %s" % prefix)
			var route_progress := float(entry.get("route_progress", -1.0))
			if route_progress < 0.0 or route_progress > 1.0:
				errors.append("invalid route progress: %s" % prefix)
			if str(entry.get("life_behavior", "")) not in ["drift", "crossing", "orbit", "rise", "skitter"]:
				errors.append("invalid life behavior: %s" % prefix)
			var presentation_type := str(entry.get("presentation_type", ""))
			if presentation_type not in ["patrol", "world_life"]:
				errors.append("invalid presentation type: %s" % prefix)
			if str(entry.get("type", "")) in ["combat_patrol", "combat_ambush"] \
					and presentation_type != "patrol":
				errors.append("combat activity missing patrol presentation: %s" % prefix)
			if float(entry.get("life_unload_radius", 0.0)) < float(entry.get("life_visible_radius", 0.0)):
				errors.append("life unload radius too small: %s" % prefix)
			if int(entry.get("life_count", 0)) < 1 or int(entry.get("life_count", 0)) > 8:
				errors.append("life count exceeds cap: %s" % prefix)
			var position: Vector3 = entry.get("position", Vector3.ZERO)
			if not anchors.is_empty() and _nearest_distance(position, anchors) > 48.0:
				errors.append("activity is outside route coverage: %s" % prefix)
			for other in definitions:
				if other == entry:
					continue
				var other_pos: Vector3 = other.get("position", Vector3.ZERO)
				if position.distance_to(other_pos) < MIN_SPACING:
					errors.append("activities overlap: %s and %s" % [prefix, str(other.get("id", ""))])
					break
			for clearance_value in [profile.get("arena", Vector3.ZERO), profile.get("cave", Vector3.ZERO), profile.get("checkpoint", Vector3.ZERO)]:
				var clearance: Vector3 = clearance_value as Vector3
				if position.distance_to(clearance) < 3.5:
					errors.append("activity enters route clearance: %s" % prefix)
			for clearance_field in ["encounters", "chests", "resources"]:
				for clearance_entry in profile.get(clearance_field, []) as Array:
					var clearance_dict := clearance_entry as Dictionary
					var clearance_position: Vector3 = clearance_dict.get("pos", Vector3.ZERO)
					if position.distance_to(clearance_position) < 3.5:
						errors.append("activity overlaps %s clearance: %s" % [clearance_field, prefix])
						break
			for pocket_value in profile.get("expansion_pockets", []) as Array:
				var pocket := pocket_value as Dictionary
				var pocket_position: Vector3 = pocket.get("position", Vector3.ZERO)
				if position.distance_to(pocket_position) < 3.5:
					errors.append("activity overlaps authored pocket clearance: %s" % prefix)
	return errors

static func _nearest_distance(position: Vector3, anchors: Array[Vector3]) -> float:
	var nearest := INF
	for anchor in anchors:
		nearest = minf(nearest, position.distance_to(anchor))
	return nearest
