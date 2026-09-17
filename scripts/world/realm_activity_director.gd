extends Node3D
class_name RealmActivityDirector

const CATALOG := preload("res://scripts/world/realm_activity_catalog.gd")
const ACTIVITY_NODE := preload("res://scripts/world/realm_activity_node.gd")
const LIFE_FIELD := preload("res://scripts/world/realm_life_field.gd")
const ENCOUNTER_ZONE := preload("res://scripts/entities/encounter_zone.gd")
const GATHERING_NODE := preload("res://scripts/world/gathering_node.gd")

signal activity_started(activity_id: String, activity_type: String)
signal activity_completed(activity_id: String, result: Dictionary)
signal activity_state_changed(realm_id: String)

const MAX_ACTIVE_COMBAT: int = 2
const MAX_MARKERS: int = 8
const MAX_VISIBLE_LIFE_FIELDS: int = 1
const MAX_AMBIENT_AGENTS: int = 8
const ACTIVATION_RADIUS: float = 18.0
const LIFE_VISIBLE_RADIUS: float = 48.0
const LIFE_LABEL_RADIUS: float = 34.0
const UNLOAD_RADIUS: float = 75.0
const POLL_SECONDS: float = 0.25

var realm_id: String = "bramblewood"
var world_owner: Node3D = null
var route_seed: int = 0
var _definitions: Array[Dictionary] = []
var _markers: Dictionary = {}
var _active: Dictionary = {}
var _life_fields: Dictionary = {}
var _spawned_count: int = 0
var _completed_count: int = 0
var _life_spawned_count: int = 0
var _life_cleaned_count: int = 0
var _visible_patrol_count: int = 0
var _current_route_beat: String = ""
var _poll_in: float = 0.0

func setup(owner: Node3D, p_realm_id: String, p_seed: int = 0) -> void:
	world_owner = owner
	realm_id = p_realm_id
	route_seed = p_seed if p_seed != 0 else abs(hash(p_realm_id))
	call_deferred("_build_activity_catalog")

func _ready() -> void:
	set_process(false)

func _build_activity_catalog() -> void:
	if not is_inside_tree() or not is_instance_valid(world_owner):
		return
	_definitions = CATALOG.for_realm(realm_id)
	var terrain := world_owner.get_node_or_null("Terrain") as Node
	for definition in _definitions:
		if _markers.size() >= MAX_MARKERS:
			break
		var activity_id := str(definition.get("id", ""))
		if activity_id.is_empty() or _markers.has(activity_id):
			continue
		definition["realm"] = realm_id
		var marker: Node3D = ACTIVITY_NODE.new()
		marker.name = "Activity_%s" % activity_id
		marker.call("configure", definition, self)
		add_child(marker)
		marker.global_position = definition.get("position", Vector3.ZERO)
		if terrain != null and terrain.has_method("conform_anchor"):
			terrain.call("conform_anchor", marker, 0.06)
		else:
			marker.global_position.y = 0.06
		_markers[activity_id] = marker
		marker.call("set_approach_visible", false)
		if _is_one_time_completed(activity_id):
			marker.call("set_available", false)
	set_process(true)
	activity_state_changed.emit(realm_id)

func _process(delta: float) -> void:
	_poll_in -= delta
	if _poll_in > 0.0:
		return
	_poll_in = POLL_SECONDS
	var hero := _hero()
	if hero == null:
		return
	_update_life_fields(hero)
	var combat_count := _active_combat_count()
	for definition in _definitions:
		var activity_id := str(definition.get("id", ""))
		if activity_id.is_empty() or _active.has(activity_id):
			continue
		var position: Vector3 = definition.get("position", Vector3.ZERO)
		var distance := hero.global_position.distance_to(position)
		if distance > ACTIVATION_RADIUS:
			continue
		var activity_type := str(definition.get("type", ""))
		if activity_type in ["combat_patrol", "combat_ambush"] and combat_count < MAX_ACTIVE_COMBAT:
			if begin_activity(activity_id):
				combat_count += 1
	_cleanup_distant_activity_nodes(hero.global_position)

func activity_contract() -> Dictionary:
	return {
		"realm": realm_id,
		"seed": route_seed,
		"activities": _definitions.duplicate(true),
		"diagnostics": get_diagnostics(),
	}

func begin_activity(activity_id: String) -> bool:
	var definition := _definition_for(activity_id)
	if definition.is_empty() or _active.has(activity_id):
		return false
	if _is_one_time_completed(activity_id) or not _cooldown_ready(activity_id):
		return false
	var activity_type := str(definition.get("type", ""))
	if activity_type in ["combat_patrol", "combat_ambush"] \
			and _active_combat_count() >= MAX_ACTIVE_COMBAT:
		return false
	_active[activity_id] = {"definition": definition, "started_at": Time.get_unix_time_from_system()}
	_spawned_count += 1
	var marker := _markers.get(activity_id) as Node3D
	if marker != null and is_instance_valid(marker):
		marker.call("set_available", false)
	activity_started.emit(activity_id, activity_type)
	match activity_type:
		"combat_patrol", "combat_ambush":
			_spawn_encounter(definition)
		"gathering":
			_spawn_gathering(definition)
		_:
			complete_activity(activity_id, {"grant_reward": true, "source": activity_type})
	return true

func complete_activity(activity_id: String, result: Dictionary) -> bool:
	var definition := _definition_for(activity_id)
	if definition.is_empty() or not _active.has(activity_id):
		return false
	var persistence := str(definition.get("persistence", "one_time"))
	if persistence == "one_time" and _is_one_time_completed(activity_id):
		return false
	var result_copy := result.duplicate(true)
	if bool(result_copy.get("grant_reward", false)):
		_grant_reward(definition.get("reward", {}) as Dictionary)
	var gs := _game_state()
	if gs != null:
		if gs.has_method("complete_world_activity"):
			gs.call("complete_world_activity", realm_id, activity_id, persistence)
		if gs.has_method("unlock_world_activity"):
			var soft_unlock: Dictionary = definition.get("soft_unlock", {})
			var unlock_id := str(soft_unlock.get("id", ""))
			if not unlock_id.is_empty():
				gs.call("unlock_world_activity", realm_id, unlock_id, str(soft_unlock.get("label", unlock_id)))
		if gs.has_method("record_activity"):
			gs.call("record_activity", "%s · %s" % [str(definition.get("label", activity_id)).to_upper(), "COMPLETE"])
		if gs.has_method("save_game"):
			gs.call("save_game")
	if persistence == "repeatable":
		var cooldown := float(definition.get("cooldown_seconds", 0.0))
		if gs != null and gs.has_method("set_world_activity_cooldown"):
			gs.call("set_world_activity_cooldown", realm_id, activity_id,
				Time.get_unix_time_from_system() + cooldown)
	_completed_count += 1
	var active_record: Dictionary = _active.get(activity_id, {})
	var runtime_node := active_record.get("node") as Node3D
	if runtime_node != null and is_instance_valid(runtime_node):
		runtime_node.queue_free()
	_active.erase(activity_id)
	var marker := _markers.get(activity_id) as Node3D
	if marker != null and is_instance_valid(marker):
		marker.call("set_available", persistence == "repeatable")
	result_copy["activity_id"] = activity_id
	result_copy["persistence"] = persistence
	activity_completed.emit(activity_id, result_copy)
	activity_state_changed.emit(realm_id)
	return true

func get_diagnostics() -> Dictionary:
	var active_ids: Array[String] = []
	for activity_id in _active.keys():
		active_ids.append(str(activity_id))
	active_ids.sort()
	return {
		"realm": realm_id,
		"active_count": active_ids.size(),
		"active_combat_count": _active_combat_count(),
		"spawned_count": _spawned_count,
		"completed_count": _completed_count,
		"marker_count": _markers.size(),
		"current_activity_ids": active_ids,
		"max_active_combat": MAX_ACTIVE_COMBAT,
		"active_ambient_count": _active_ambient_count(),
		"active_world_event_count": _life_fields.size(),
		"visible_patrol_count": _visible_patrol_count,
		"current_route_beat": _current_route_beat,
		"life_spawned_count": _life_spawned_count,
		"life_cleaned_count": _life_cleaned_count,
		"max_ambient_agents": MAX_AMBIENT_AGENTS,
		"max_world_events": MAX_VISIBLE_LIFE_FIELDS,
	}

func nearby_activity_snapshot() -> Dictionary:
	var hero := _hero()
	if hero == null:
		return {}
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for definition in _definitions:
		var activity_id := str(definition.get("id", ""))
		var marker := _markers.get(activity_id) as Node3D
		if marker == null or not is_instance_valid(marker) or not marker.visible:
			continue
		var distance := hero.global_position.distance_to(marker.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = {
				"id": activity_id,
				"label": str(definition.get("label", activity_id)),
				"type": str(definition.get("type", "")),
				"distance": distance,
				"prompt": "INTERACT" if distance <= 3.0 else "AHEAD",
			}
	return nearest

func _update_life_fields(hero: Node3D) -> void:
	var candidates: Array[Dictionary] = []
	var visible_patrols := 0
	for definition in _definitions:
		var activity_id := str(definition.get("id", ""))
		var marker := _markers.get(activity_id) as Node3D
		if marker == null or not is_instance_valid(marker):
			continue
		var distance := hero.global_position.distance_to(marker.global_position)
		var in_view := marker.visible and distance <= LIFE_VISIBLE_RADIUS
		marker.call("set_approach_visible", in_view and distance <= LIFE_LABEL_RADIUS)
		var activity_type := str(definition.get("type", ""))
		if in_view and activity_type in ["combat_patrol", "combat_ambush"]:
			visible_patrols += 1
		if not in_view:
			continue
		candidates.append({"definition": definition, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance", INF)) < float(b.get("distance", INF)))
	_visible_patrol_count = visible_patrols
	_current_route_beat = str(candidates[0].get("definition", {}).get("id", "")) \
		if not candidates.is_empty() else ""

	var desired: Dictionary = {}
	var ambient_agents := 0
	for candidate in candidates:
		if desired.size() >= MAX_VISIBLE_LIFE_FIELDS:
			break
		var definition: Dictionary = candidate.get("definition", {})
		var activity_id := str(definition.get("id", ""))
		var agent_count := mini(int(definition.get("life_count", 3)),
			MAX_AMBIENT_AGENTS - ambient_agents)
		if agent_count <= 0:
			break
		desired[activity_id] = true
		ambient_agents += agent_count
		if not _life_fields.has(activity_id):
			_spawn_life_field(definition, agent_count)
		var field := _life_fields.get(activity_id) as RealmLifeField
		if field != null and is_instance_valid(field):
			field.set_label_visible(float(candidate.get("distance", INF)) <= LIFE_LABEL_RADIUS)

	for activity_id in _life_fields.keys().duplicate():
		if desired.has(activity_id):
			continue
		_remove_life_field(str(activity_id))

func _spawn_life_field(definition: Dictionary, agent_count: int) -> void:
	var activity_id := str(definition.get("id", ""))
	var marker := _markers.get(activity_id) as Node3D
	if marker == null or not is_instance_valid(marker):
		return
	var field: RealmLifeField = LIFE_FIELD.new()
	field.name = "LifeField_%s" % activity_id
	field.configure(realm_id, route_seed ^ activity_id.hash(),
		str(definition.get("life_behavior", "drift")), agent_count, activity_id,
		str(definition.get("life_label", definition.get("label", activity_id))),
		str(definition.get("presentation_type", "world_life")))
	add_child(field)
	field.global_position = marker.global_position
	_life_fields[activity_id] = field
	_life_spawned_count += 1
	_play_life_cue(definition, marker)

func _remove_life_field(activity_id: String) -> void:
	var field := _life_fields.get(activity_id) as RealmLifeField
	if field != null and is_instance_valid(field):
		field.set_active(false)
		field.queue_free()
	_life_fields.erase(activity_id)
	_life_cleaned_count += 1

func _play_life_cue(definition: Dictionary, marker: Node3D) -> void:
	var activity_type := str(definition.get("type", ""))
	if activity_type not in ["beacon", "discovery", "combat_patrol", "combat_ambush"]:
		return
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_synth_at"):
		audio.call("play_synth_at", marker, "lantern_creak", -14.0)

func _active_ambient_count() -> int:
	var count := 0
	for field_value in _life_fields.values():
		var field := field_value as RealmLifeField
		if field != null and is_instance_valid(field):
			count += field.agent_count()
	return count

func _spawn_encounter(definition: Dictionary) -> void:
	var zone: EncounterZone = ENCOUNTER_ZONE.new()
	var activity_id := str(definition.get("id", ""))
	zone.name = "ActivityEncounter_%s" % activity_id
	zone.set("pocket_id", activity_id)
	zone.call("setup", realm_id, str(definition.get("enemy_tier", "normal")), int(GameState.current_stage))
	add_child(zone)
	zone.global_position = definition.get("position", Vector3.ZERO)
	var terrain: Node = world_owner.get_node_or_null("Terrain") if world_owner != null else null
	if terrain != null and terrain.has_method("conform_anchor"):
		terrain.call("conform_anchor", zone, 0.04)
	zone.pack_cleared.connect(_on_encounter_cleared.bind(activity_id))
	_active[activity_id]["node"] = zone
	var hero := _hero()
	if hero != null and hero.global_position.distance_to(zone.global_position) <= ACTIVATION_RADIUS:
		zone.call_deferred("_on_body_entered", hero)

func _spawn_gathering(definition: Dictionary) -> void:
	var node: GatheringNode = GATHERING_NODE.new()
	var activity_id := str(definition.get("id", ""))
	node.name = "ActivityGathering_%s" % activity_id
	node.call("configure", str(definition.get("material_id", "moss_fiber")),
		int(definition.get("yield_min", 1)), int(definition.get("yield_max", 2)),
		1.2, float(definition.get("cooldown_seconds", 50.0)), realm_id)
	add_child(node)
	node.global_position = definition.get("position", Vector3.ZERO)
	var terrain: Node = world_owner.get_node_or_null("Terrain") if world_owner != null else null
	if terrain != null and terrain.has_method("conform_anchor"):
		terrain.call("conform_anchor", node, 0.04)
	node.gathered.connect(_on_gathered.bind(activity_id))
	_active[activity_id]["node"] = node

func _on_encounter_cleared(activity_id: String) -> void:
	complete_activity(activity_id, {"source": "encounter", "grant_reward": true})

func _on_gathered(material_id: String, quantity: int, activity_id: String) -> void:
	complete_activity(activity_id, {"source": "gathering", "material_id": material_id, "quantity": quantity})

func _grant_reward(reward: Dictionary) -> void:
	var gs := _game_state()
	if gs == null:
		return
	var quantity := maxi(0, int(reward.get("quantity", 0)))
	if quantity <= 0:
		return
	match str(reward.get("type", "")):
		"gold":
			if gs.has_method("add_gold"):
				gs.call("add_gold", quantity, "Activity reward secured.")
		"material":
			if gs.has_method("add_material"):
				gs.call("add_material", str(reward.get("id", "")), quantity)
		"scan_fragment":
			if gs.has_method("add_scan_fragment"):
				gs.call("add_scan_fragment", quantity)
		"iron_shard":
			if gs.has_method("add_material"):
				gs.call("add_material", "iron_shard", quantity)

func _cleanup_distant_activity_nodes(hero_position: Vector3) -> void:
	for activity_id in _active.keys().duplicate():
		var record: Dictionary = _active.get(activity_id, {})
		var node := record.get("node") as Node3D
		if node == null or not is_instance_valid(node):
			continue
		if hero_position.distance_to(node.global_position) <= UNLOAD_RADIUS:
			continue
		if node is EncounterZone and not bool(node.get("_spawned")):
			node.queue_free()
			_active.erase(activity_id)
			var marker := _markers.get(activity_id) as Node3D
			if marker != null and is_instance_valid(marker):
				marker.call("set_available", true)
		elif node is GatheringNode and not bool(node.get("_gathering")):
			node.queue_free()
			_active.erase(activity_id)
			var gather_marker := _markers.get(activity_id) as Node3D
			if gather_marker != null and is_instance_valid(gather_marker):
				gather_marker.call("set_available", true)

func _definition_for(activity_id: String) -> Dictionary:
	for definition in _definitions:
		if str(definition.get("id", "")) == activity_id:
			return definition
	return {}

func _is_one_time_completed(activity_id: String) -> bool:
	var gs := _game_state()
	return gs != null and gs.has_method("is_world_activity_completed") \
		and bool(gs.call("is_world_activity_completed", realm_id, activity_id))

func _cooldown_ready(activity_id: String) -> bool:
	var gs := _game_state()
	if gs == null or not gs.has_method("get_world_activity_cooldown"):
		return true
	return float(gs.call("get_world_activity_cooldown", realm_id, activity_id)) <= Time.get_unix_time_from_system()

func _active_combat_count() -> int:
	var count := 0
	for activity_id in _active.keys():
		var definition := _definition_for(str(activity_id))
		if str(definition.get("type", "")) in ["combat_patrol", "combat_ambush"]:
			count += 1
	return count

func _hero() -> Node3D:
	if world_owner == null or not is_instance_valid(world_owner):
		return null
	return world_owner.get_node_or_null("Hero") as Node3D

func _game_state() -> Node:
	return get_node_or_null("/root/GameState")
