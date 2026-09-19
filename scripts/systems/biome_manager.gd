## Use the source path here instead of the global class name so standalone
## validation scenes resolve this dependency before the global class cache has
## been populated.
extends "res://scripts/systems/world_manager.gd"
class_name BiomeManager

const BRAMBLEWOOD_EXPEDITION_SCRIPT := preload("res://scripts/world/bramblewood_expedition.gd")
const REALM_ACTIVITY_DIRECTOR_SCRIPT := preload("res://scripts/world/realm_activity_director.gd")
const CHEST_NODE_SCRIPT := preload("res://scripts/entities/chest_node.gd")
const GATHERING_NODE_SCRIPT := preload("res://scripts/world/gathering_node.gd")
const MOBILE_LOD_SCRIPT := preload("res://scripts/systems/mobile_lod_controller.gd")
const BIOME_BOSS_DIRECTOR_SCRIPT := preload("res://scripts/systems/boss_encounter_director.gd")
const BOSS_ROSTER := preload("res://scripts/systems/boss_roster_catalog.gd")
const BOSS_COMPOUND_SCRIPT := preload("res://scripts/world/boss_compound.gd")
const BOSS_COMPOUND_CATALOG := preload("res://scripts/systems/boss_compound_catalog.gd")
# ENEMY_VISUALS is inherited from WorldManager; redeclaring the same const in
# this subclass is a hard GDScript parse error, so use the parent's binding.

## === Biome Manager ===
## Turns a grove-derived scene into one explorable biome: fixed realm
## theming, respawning realm-tier packs, travel gates to sibling biomes,
## and an arena stone that wakes this biome's boss.

@export var biome_id: String = "bramblewood"

## Pack budget is measured around the hero, not the whole realm, so enemies
## cluster at the boss stone never starve the travel zones of encounters.
const PACK_LIVE_RADIUS := 90.0
## Idle pack leftovers behind the player are despawned beyond this radius.
const DESPAWN_FAR_RADIUS := 130.0
## Packs never spawn inside this radius around the arena stone (readable boss).
const ARENA_CLEAR_RADIUS := 16.0

## === Map-wide encounter pockets ===
## Authored hostile groups placed along the whole realm route so the map has
## life at every beat instead of only materialising a ring around the hero. A
## pocket wakes when the hero walks near it and its leftovers are culled once
## the player moves on, so the realm-wide hostile budget stays bounded.
const POCKET_GLOBAL_CAP := 16
const POCKET_DESPAWN_MARGIN := 44.0
const POCKET_RESPAWN_SECONDS := 20.0
## Cluster spacing inside a pocket ring.
const POCKET_SPAWN_INNER := 0.30
const POCKET_SPAWN_OUTER := 0.62

var _spawn_pockets: Array[Dictionary] = []
## Rotates the realm roster across pocket fill calls so successive groups mix
## kinds instead of repeating one archetype per tier.
var _roster_cursor := 0
var _structures_built := false
var _pocket_sweep_in := 1.0

var _despawn_sweep_in := 0.25

var _biome_def: Dictionary = {}
var _gates: Array[Dictionary] = []  # {node, dest}
var _arena_compound: BossCompound = null
var _biome_boss: Node3D = null
var _traveling := false
var _arrival_focus_played := false
var _bramblewood_expedition: Node3D = null
var _realm_activity_director: RealmActivityDirector = null
var _authored_chest_host: Node3D = null
var _authored_resource_host: Node3D = null
var _authored_encounter_host: Node3D = null
var _mobile_lod: MobileLodController = null
var _boss_director: BossEncounterDirector = null
var _side_boss_markers: Array[Dictionary] = []

func _ready() -> void:
	_biome_def = Bestiary.biome(biome_id)
	if _biome_def.is_empty():
		push_error("BiomeManager: unknown biome_id '%s'" % biome_id)
	super._ready()
	_boss_director = BIOME_BOSS_DIRECTOR_SCRIPT.new()
	_boss_director.setup(self)
	_enter_biome()

## === Identity ===

func _enter_biome() -> void:
	var shared_whispergrove := biome_id == "bramblewood" \
		and game_state.current_realm == "whispergrove"
	if game_state.current_realm != biome_id and not shared_whispergrove:
		game_state.set_current_realm(biome_id)
	_apply_realm_theme(game_state.current_stage)
	var title := str(_biome_def.get("title", biome_id.capitalize()))
	game_state.quest_progress.emit("Now entering %s." % title)
	_play_realm_audio(_visual_realm_id())
	_build_profile_chests()
	_build_profile_resources()
	_build_profile_encounters()
	_build_spawn_pockets()
	_build_structures()
	_build_gates()
	_build_arena()
	_build_side_bosses()
	_build_bramblewood_expansion()
	call_deferred("_build_realm_activity_director")
	_spawn_wave(current_grove_state)
	_start_respawner()
	call_deferred("_play_realm_arrival")

func _build_profile_chests() -> void:
	if _authored_chest_host != null and is_instance_valid(_authored_chest_host):
		return
	# The shared grove presents Whispergrove during onboarding and Bramblewood
	# once the expedition unlocks, so the authored chests must follow the
	# *presented* realm. Using biome_id here left onboarding with Bramblewood
	# caches (and no Whispergrove ones) on the same ground.
	var profile := RealmLayoutData.profile(_visual_realm_id())
	var chest_values: Variant = profile.get("chests", [])
	if not chest_values is Array or (chest_values as Array).is_empty():
		return
	_authored_chest_host = Node3D.new()
	_authored_chest_host.name = "AuthoredChests"
	add_child(_authored_chest_host)
	var seen_ids: Dictionary = {}
	for chest_value in chest_values:
		if not chest_value is Dictionary:
			continue
		var definition: Dictionary = chest_value
		var chest_id := str(definition.get("id", "")).strip_edges()
		if chest_id.is_empty() or seen_ids.has(chest_id):
			continue
		seen_ids[chest_id] = true
		var chest: ChestNode = CHEST_NODE_SCRIPT.new()
		chest.name = "Chest_%s" % chest_id
		chest.realm_id = _visual_realm_id()
		if not chest.configure_from_definition(definition):
			chest.queue_free()
			continue
		chest.add_to_group("authored_chest")
		_authored_chest_host.add_child(chest)
		var position_value: Variant = definition.get("pos", Vector3.ZERO)
		if position_value is Vector3:
			chest.global_position = position_value
		var terrain := get_node_or_null("Terrain") as TerrainRelief
		if terrain != null:
			terrain.conform_anchor(chest, 0.04)

## === Map-wide gathering nodes ===
## The realm profiles have always carried authored `resources`; nothing built
## them, so gathering existed only as activity markers near spawn. These become
## real, persisted GatheringNodes spread along the route.
func _build_profile_resources() -> void:
	if _authored_resource_host != null and is_instance_valid(_authored_resource_host):
		return
	var profile := RealmLayoutData.profile(_visual_realm_id())
	var values: Variant = profile.get("resources", [])
	if not values is Array or (values as Array).is_empty():
		return
	_authored_resource_host = Node3D.new()
	_authored_resource_host.name = "AuthoredResources"
	add_child(_authored_resource_host)
	var realm := _visual_realm_id()
	for value in values:
		if not value is Dictionary:
			continue
		var definition: Dictionary = value
		var material_id := str(definition.get("id", "")).strip_edges()
		if material_id.is_empty():
			continue
		var pos_value: Variant = definition.get("pos", Vector3.ZERO)
		if not pos_value is Vector3:
			continue
		var node: GatheringNode = GATHERING_NODE_SCRIPT.new()
		node.name = "Gather_%s" % material_id
		var amount := maxi(int(definition.get("yield", 2)), 1)
		node.configure(material_id, amount, amount, 1.15, 240.0, realm)
		_authored_resource_host.add_child(node)
		node.global_position = _resolve_content_spot(pos_value as Vector3)
		var terrain := get_node_or_null("Terrain") as TerrainRelief
		if terrain != null:
			terrain.conform_anchor(node, 0.04)

## === Authored encounters ===
## Realm profiles author specific enemy kinds per position. These are one-time
## set-pieces: respawning pressure across the map comes from spawn pockets, so
## this stays a bounded, hand-placed complement.
func _build_profile_encounters() -> void:
	if _authored_encounter_host != null and is_instance_valid(_authored_encounter_host):
		return
	var profile := RealmLayoutData.profile(_visual_realm_id())
	var values: Variant = profile.get("encounters", [])
	if not values is Array or (values as Array).is_empty():
		return
	_authored_encounter_host = Node3D.new()
	_authored_encounter_host.name = "AuthoredEncounters"
	add_child(_authored_encounter_host)
	var index := 0
	for value in values:
		if not value is Dictionary:
			continue
		var definition: Dictionary = value
		var scene_name := str(definition.get("scene", "")).strip_edges()
		if scene_name.is_empty():
			continue
		var pos_value: Variant = definition.get("pos", Vector3.ZERO)
		if not pos_value is Vector3:
			continue
		var enemy := _spawn_named_enemy(scene_name,
			_resolve_content_spot(pos_value as Vector3),
			str(definition.get("tier", "normal")), index)
		if enemy == null:
			continue
		index += 1

func _spawn_named_enemy(scene_name: String, world_pos: Vector3, tier: String,
		index: int) -> Node3D:
	var path := "res://scenes/entities/%s.tscn" % scene_name
	if not ResourceLoader.exists(path):
		push_warning("BiomeManager: authored encounter scene missing: %s" % path)
		return null
	var scene: PackedScene = load(path)
	if scene == null or _authored_encounter_host == null:
		return null
	var enemy: Node3D = scene.instantiate()
	if enemy == null:
		return null
	enemy.name = "AuthoredEncounter_%s_%d" % [scene_name, index]
	enemy.set_meta("authored_encounter", scene_name)
	_authored_encounter_host.add_child(enemy)
	enemy.global_position = world_pos
	_register_detail_lod(enemy)
	var model := CharacterModelData.for_realm(_visual_realm_id(), tier)
	if model != null:
		model.configure_entity(enemy)
	var terrain := get_node_or_null("Terrain") as TerrainRelief
	if terrain != null:
		terrain.conform_anchor(enemy, 0.12)
	return enemy

func _play_realm_arrival() -> void:
	if _arrival_focus_played:
		return
	_arrival_focus_played = true
	var focus: Node3D = _arena_compound if _arena_compound != null else hero
	if focus == null or not is_instance_valid(focus):
		return
	var camera_rig := get_node_or_null("CameraRig")
	if camera_rig != null and camera_rig.has_method("play_focus_moment"):
		# Frame the focus from the hero's side. The old build hardcoded a
		# near-spawn camera anchor, which swept the lens across the whole realm
		# once the arenas moved 90-170 m out.
		var focus_offset := Vector3(0.0, 1.4, 0.0)
		var anchor := focus.global_position + focus_offset + Vector3(0.0, 1.0, 5.0)
		if hero != null and is_instance_valid(hero):
			var toward_hero := hero.global_position - focus.global_position
			toward_hero.y = 0.0
			if toward_hero.length() > 0.5:
				anchor = focus.global_position + focus_offset \
					+ toward_hero.normalized() * 5.0 + Vector3(0.0, 1.0, 0.0)
		camera_rig.play_focus_moment(focus, anchor, focus_offset, 1.6)

func _realm_tint() -> Color:
	return Bestiary.REALMS.get(_visual_realm_id(), {}).get(
		"mist_tint", Color(0.65, 0.75, 0.72))

func _fx_tint() -> Color:
	return Bestiary.REALMS.get(_visual_realm_id(), {}).get(
		"firefly_tint", Color(1.0, 0.86, 0.45))

func _visual_realm_id() -> String:
	return RealmLayoutData.visual_realm_for(self)

## === Theming: fixed to this biome, not the quest ladder ===

func _apply_realm_theme(_stage: int) -> void:
	if day_night == null:
		return
	day_night.apply_realm(_realm_tint(), _fx_tint(),
		Bestiary.REALMS.get(_visual_realm_id(), {}).get("grade", {}))
	var fog_mult := float(_biome_def.get("fog_energy", 1.0))
	if world_environment != null and world_environment.environment != null and fog_mult != 1.0:
		world_environment.environment.fog_density *= fog_mult

## === Packs: realm-tier enemies, respawn while you stay ===

func _spawn_wave(_stage: int) -> void:
	if _biome_def.is_empty():
		return
	_clear_pack()
	_spawn_biome_pack(hero.global_position if hero != null else player_spawn.global_position)

func _start_respawner() -> void:
	var timer := Timer.new()
	timer.name = "PackRespawner"
	timer.wait_time = float(_biome_def.get("respawn_seconds", 17.0))
	timer.autostart = true
	timer.timeout.connect(_on_respawn_tick)
	add_child(timer)

func _on_respawn_tick() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	_despawn_distant_enemies()
	# The cap is *nearby* only: leftovers from an earlier pack must not starve
	# the traversal zones once the hero leaves the arena area. Without this,
	# the global pool stayed pinned at pack_cap by enemies clustering around
	# the boss stone and no pack ever respawned anywhere else in the realm.
	_tick_spawn_pockets()
	# Hero-relative packs remain only as cover for ground the authored pockets
	# do not reach, so travelling never crosses a completely empty stretch.
	var cap := int(_biome_def.get("pack_cap", 5))
	if _nearby_enemy_count(hero.global_position, PACK_LIVE_RADIUS) >= cap:
		return
	if not _pocket_covers(hero.global_position):
		_spawn_biome_pack(hero.global_position)

func _pocket_covers(point: Vector3) -> bool:
	for pocket in _spawn_pockets:
		var origin: Vector3 = pocket.get("origin", Vector3.ZERO)
		var reach := float(pocket.get("radius", 24.0)) + POCKET_DESPAWN_MARGIN
		if Vector2(point.x - origin.x, point.z - origin.z).length() <= reach:
			return true
	return false

## Idle pack enemies far behind the hero are culled so the realm's encounter
## budget travels with the player instead of accumulating around the boss.
## Bosses, elites, and anything in active combat are never swept.
func _despawn_distant_enemies() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var center := hero.global_position
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not (enemy is Node3D) or not is_instance_valid(enemy):
			continue
		if enemy.is_in_group("boss"):
			continue
		# Authored set-pieces are hand-placed and bounded per realm; distance
		# culling is for procedural pressure only, and would silently delete a
		# hand-placed encounter the first frame a realm loads.
		if enemy.has_meta("authored_encounter"):
			continue
		if enemy.global_position.distance_to(center) > DESPAWN_FAR_RADIUS:
			enemy.queue_free()

func _nearby_enemy_count(center: Vector3, radius: float) -> int:
	var count := 0
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy) and enemy is Node3D \
				and enemy.global_position.distance_to(center) <= radius:
			count += 1
	return count

func _spawn_biome_pack(origin: Vector3) -> void:
	# Keep the arena stone readable: packs materialise outside the boss circle
	# unless the hero is already far away from it.
	var anchor := origin
	if _arena_compound != null and is_instance_valid(_arena_compound):
		var to_arena := origin - _arena_compound.global_position
		to_arena.y = 0.0
		if to_arena.length() < ARENA_CLEAR_RADIUS:
			var push := to_arena.normalized() if to_arena.length() > 0.1 else Vector3.BACK
			anchor = _arena_compound.global_position + push * ARENA_CLEAR_RADIUS
			anchor.y = origin.y
	var comp: Dictionary = _biome_def.get("pack", {})
	var hard_count := int(comp.get("hard", 0))
	var normal_count := int(comp.get("normal", 0))
	var total := hard_count + normal_count
	var idx := 0
	for i in hard_count:
		_spawn_pack_enemy(anchor, biome_id, true, idx, total)
		idx += 1
	for i in normal_count:
		_spawn_pack_enemy(anchor, biome_id, false, idx, total)
		idx += 1

## === Map-wide spawn pockets ===
## Authored groups pulled from the realm layout so hostile life exists down the
## whole route. Progress is gameplay-identical across quality tiers: only the
## presentation budget scales, never the pocket positions, tiers, or counts.

func _build_spawn_pockets() -> void:
	if not _spawn_pockets.is_empty():
		return
	var profile := RealmLayoutData.profile(_visual_realm_id())
	var values: Variant = profile.get("spawn_pockets", [])
	if not values is Array:
		return
	for value in values:
		if not value is Dictionary:
			continue
		var definition: Dictionary = value
		var pos_value: Variant = definition.get("pos", Vector3.ZERO)
		if not pos_value is Vector3:
			continue
		_spawn_pockets.append({
			"id": str(definition.get("id", "")),
			"origin": _resolve_content_spot(pos_value as Vector3),
			"tier": str(definition.get("tier", "normal")),
			"count": maxi(int(definition.get("count", 2)), 1),
			"radius": maxf(float(definition.get("radius", 24.0)), 8.0),
			"alive": [],
			"next_at": 0.0,
		})

## Fill any pocket the hero is close to. Cheap enough to run on a slow sweep:
## a handful of distance checks against authored origins.
func _tick_spawn_pockets() -> void:
	if _spawn_pockets.is_empty() or hero == null or not is_instance_valid(hero):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var center := hero.global_position
	for pocket in _spawn_pockets:
		var origin: Vector3 = pocket.get("origin", Vector3.ZERO)
		var radius: float = float(pocket.get("radius", 24.0))
		var distance := Vector2(center.x - origin.x, center.z - origin.z).length()
		var living: Array = []
		for enemy in pocket.get("alive", []):
			if is_instance_valid(enemy) and enemy is Node3D:
				living.append(enemy)
		pocket["alive"] = living
		if distance > radius + POCKET_DESPAWN_MARGIN:
			for enemy in living:
				if enemy.is_in_group("boss"):
					continue
				enemy.queue_free()
			pocket["alive"] = []
			continue
		if distance > radius:
			continue
		if now < float(pocket.get("next_at", 0.0)):
			continue
		if living.size() >= int(pocket.get("count", 2)):
			continue
		if _spawn_pocket_group(pocket, living) > 0:
			pocket["next_at"] = now + POCKET_RESPAWN_SECONDS

func _spawn_pocket_group(pocket: Dictionary, living: Array) -> int:
	var budget := _hostile_budget_remaining()
	if budget <= 0:
		return 0
	var total := int(pocket.get("count", 2))
	var missing := mini(total - living.size(), budget)
	if missing <= 0:
		return 0
	var origin: Vector3 = pocket.get("origin", Vector3.ZERO)
	var radius := float(pocket.get("radius", 24.0))
	var tier := str(pocket.get("tier", "normal"))
	var spawned := 0
	for i in missing:
		var angle := TAU * float(living.size() + i) / maxf(float(total), 1.0) \
			+ randf_range(-0.28, 0.28)
		var dist := randf_range(radius * POCKET_SPAWN_INNER, radius * POCKET_SPAWN_OUTER)
		var spot := origin + Vector3(cos(angle) * dist, 0.2, sin(angle) * dist)
		# A pocket ring can reach into a boss arena or a gate; never let an
		# individual spawn land there even when the pocket origin is legal.
		# Elite pockets keep their dedicated elite scene; normal/hard pockets
		# rotate the realm roster so every mob kind appears across the map.
		var roster_kind := "" if tier == "elite" else _next_pocket_kind(tier)
		var enemy := _spawn_tiered_enemy(
			push_clear_of_zones(spot, _reserved_zones()), tier, roster_kind)
		if enemy == null:
			continue
		enemy.set_meta("spawn_pocket_id", str(pocket.get("id", "")))
		living.append(enemy)
		spawned += 1
	return spawned

## The realm's authored enemy roster mapped to spawnable scene ids. Entries the
## shared kind->scene catalog cannot serve are dropped so a typo never silently
## falls back to a hushling.
func _realm_roster() -> Array[String]:
	var result: Array[String] = []
	var profile := RealmLayoutData.profile(_visual_realm_id())
	var values: Variant = profile.get("enemies", [])
	if not values is Array:
		return result
	for value in values:
		var scene_id := str(value).strip_edges()
		if scene_id.is_empty() or result.has(scene_id):
			continue
		if not ENEMY_VISUALS.ENEMY_SCENES.has(scene_id):
			continue
		result.append(scene_id)
	return result

## Next pocket member kind: the realm roster plus the tier's signature Bestiary
## kind, rotated so a realm fields its whole roster map-wide instead of one
## archetype per tier.
func _next_pocket_kind(tier: String) -> String:
	var cycle := _realm_roster()
	var variant_tier := "hard" if tier == "hard" else "normal"
	var signature := str(Bestiary.variant_for(_visual_realm_id(), variant_tier) \
		.get("kind", ""))
	if not signature.is_empty() and not cycle.has(signature):
		cycle.append(signature)
	if cycle.is_empty():
		return ""
	var pick := cycle[_roster_cursor % cycle.size()]
	_roster_cursor += 1
	return pick

## === Presentation LOD ===
## One shared, distance-budgeted controller for every authoritative prop and
## actor this manager builds. It is presentation-only: shadows and opted-in
## micro detail, never collision, timing or telegraphs.
func _register_detail_lod(node: Node3D) -> void:
	if node == null:
		return
	var lod := _ensure_mobile_lod()
	if lod != null:
		lod.register_detail(node)

func _ensure_mobile_lod() -> MobileLodController:
	if _mobile_lod != null and is_instance_valid(_mobile_lod):
		return _mobile_lod
	if not is_inside_tree():
		return null
	_mobile_lod = MOBILE_LOD_SCRIPT.new()
	_mobile_lod.name = "MobileLod"
	add_child(_mobile_lod)
	return _mobile_lod

## Realm-wide hostile budget. Counts every live enemy (bosses included) so a
## boss fight plus pocket refills can never stack past the mobile ceiling.
func _hostile_budget_remaining() -> int:
	var total := 0
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy) and enemy is Node3D:
			total += 1
	return POCKET_GLOBAL_CAP - total

func _spawn_tiered_enemy(world_pos: Vector3, tier: String,
		scene_id: String = "") -> Node3D:
	var elite := tier == "elite"
	var variant_tier := "elite" if elite else ("hard" if tier == "hard" else "normal")
	var realm_id := _visual_realm_id()
	var v := Bestiary.variant_for(realm_id, variant_tier)
	if v.is_empty():
		return null
	var kind := str(v.get("kind", "hushling"))
	# The tier's Bestiary kind is the fallback; the roster/pocket spread can
	# request a concrete scene id instead. Every id resolves through the shared
	# catalog so pockets far from the authored route field rigged creatures.
	var request_id := scene_id if not scene_id.is_empty() else kind
	var scene_path := "res://scenes/entities/elite_hushling.tscn" if elite \
		else ENEMY_VISUALS.scene_for(request_id)
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return null
	var enemy: Node3D = scene.instantiate()
	if enemy == null:
		return null
	# Realm elite identity: the elite keeps its scene mechanics but wears the
	# realm's creature rig at its own silhouette height. Both must be set before
	# add_child, which is when the rig mounts.
	if elite and v.has("rig"):
		if "rig_profile_override" in enemy:
			enemy.set("rig_profile_override", str(v.get("rig", "")))
		if "authored_rig_height" in enemy:
			enemy.set("authored_rig_height", float(v.get("rig_height", 0.0)))
	add_child(enemy)
	enemy.global_position = world_pos
	_register_detail_lod(enemy)
	var md := CharacterModelData.new()
	md.display_name = str(v.get("display", "Hushling"))
	md.model_scale = float(v.get("scale", 1.0))
	md.body_tint = v.get("tint", Color(0, 0, 0, 0))
	md.eye_glow_color = v.get("eye", Color(0, 0, 0, 0))
	md.max_hp_override = int(v.get("hp", 0))
	md.base_atk_bonus = int(v.get("atk_bonus", 0))
	md.move_speed_mult = float(v.get("speed", 1.0))
	md.configure_entity(enemy)
	# A roster pick owns its identity through its own scene script; only the
	# tier-kind fallback applies a Bestiary archetype on top.
	if scene_id.is_empty() and enemy.has_method("configure_archetype") \
			and not enemy is RealmArchetypeEnemy:
		enemy.configure_archetype(kind)
	if bool(v.get("volley", false)) and "thorn_volley" in enemy:
		enemy.thorn_volley = true
	var terrain := get_node_or_null("Terrain") as TerrainRelief
	if terrain != null:
		terrain.conform_anchor(enemy, 0.12)
	return enemy

## === Authored structures: readable set-pieces down the whole route ===

func _build_structures() -> void:
	if _structures_built:
		return
	var profile := RealmLayoutData.profile(_visual_realm_id())
	var values: Variant = profile.get("structures", [])
	if not values is Array or (values as Array).is_empty():
		return
	_structures_built = true
	var host := Node3D.new()
	host.name = "AuthoredStructures"
	add_child(host)
	for value in values:
		if not value is Dictionary:
			continue
		var definition: Dictionary = value
		var pos_value: Variant = definition.get("pos", Vector3.ZERO)
		if not pos_value is Vector3:
			continue
		var root := Node3D.new()
		root.name = "Structure_%s" % str(definition.get("id", "structure"))
		root.add_to_group("structure")
		root.set_meta("structure_id", str(definition.get("id", "")))
		root.set_meta("structure_kind", str(definition.get("kind", "ruins")))
		host.add_child(root)
		root.global_position = _resolve_content_spot(pos_value as Vector3)
		_build_structure_kind(root, str(definition.get("kind", "ruins")))
		_register_detail_lod(root)
		var label := Label3D.new()
		label.name = "StructureLabel"
		label.text = str(definition.get("label", "LANDMARK")).to_upper()
		label.font_size = 30
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = _fx_tint()
		label.position = Vector3(0.0, 3.6, 0.0)
		root.add_child(label)
		var terrain := get_node_or_null("Terrain") as TerrainRelief
		if terrain != null:
			terrain.conform_anchor(root, 0.06)

func _structure_stone_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/stylized/rock/albedo.png")
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/textures/stylized/rock/normal.png")
	mat.roughness_texture = load("res://assets/textures/stylized/rock/roughness.png")
	mat.albedo_color = _realm_tint().darkened(0.45).lerp(Color(0.30, 0.28, 0.25), 0.35)
	mat.roughness = 0.92
	return mat

func _structure_mesh(parent: Node3D, mesh: Mesh, position: Vector3,
		material: Material, rotation_y: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation.y = rotation_y
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _build_structure_kind(root: Node3D, kind: String) -> void:
	var stone := _structure_stone_material()
	match kind:
		"arch":
			var pillar := CylinderMesh.new()
			pillar.top_radius = 0.34
			pillar.bottom_radius = 0.5
			pillar.height = 3.2
			pillar.radial_segments = 7
			_structure_mesh(root, pillar, Vector3(-1.5, 1.6, 0), stone)
			_structure_mesh(root, pillar, Vector3(1.5, 1.6, 0), stone)
			var lintel := BoxMesh.new()
			lintel.size = Vector3(3.7, 0.55, 0.55)
			_structure_mesh(root, lintel, Vector3(0, 3.0, 0), stone)
		"watch", "spire":
			var tower := CylinderMesh.new()
			tower.top_radius = 0.10 if kind == "spire" else 0.42
			tower.bottom_radius = 0.72
			tower.height = 5.0
			tower.radial_segments = 8
			_structure_mesh(root, tower, Vector3(0, 2.5, 0), stone)
			var crown := CylinderMesh.new()
			crown.top_radius = 0.95
			crown.bottom_radius = 0.95
			crown.height = 0.24
			crown.radial_segments = 8
			_structure_mesh(root, crown, Vector3(0, 4.9, 0), stone)
			var lamp := SphereMesh.new()
			lamp.radius = 0.28
			lamp.height = 0.56
			var glow := StandardMaterial3D.new()
			glow.albedo_color = _fx_tint().darkened(0.2)
			glow.emission_enabled = true
			glow.emission = _fx_tint()
			glow.emission_energy_multiplier = 1.1
			_structure_mesh(root, lamp, Vector3(0, 5.35, 0), glow)
		"camp":
			var ground := CylinderMesh.new()
			ground.top_radius = 3.0
			ground.bottom_radius = 3.2
			ground.height = 0.12
			ground.radial_segments = 12
			_structure_mesh(root, ground, Vector3(0, 0.06, 0), stone)
			var tent := CylinderMesh.new()
			tent.top_radius = 0.05
			tent.bottom_radius = 1.5
			tent.height = 1.9
			tent.radial_segments = 7
			_structure_mesh(root, tent, Vector3(-1.1, 0.95, 0.6), stone)
			var fire := SphereMesh.new()
			fire.radius = 0.26
			fire.height = 0.5
			var ember := StandardMaterial3D.new()
			ember.albedo_color = Color(0.4, 0.16, 0.06)
			ember.emission_enabled = true
			ember.emission = _fx_tint()
			ember.emission_energy_multiplier = 0.9
			_structure_mesh(root, fire, Vector3(1.2, 0.22, -0.4), ember)
			var light := OmniLight3D.new()
			light.light_color = _fx_tint()
			light.light_energy = 0.7
			light.omni_range = 6.0
			light.position = Vector3(1.2, 1.0, -0.4)
			root.add_child(light)
		"basin":
			var rim := TorusMesh.new()
			rim.inner_radius = 1.7
			rim.outer_radius = 2.1
			rim.ring_segments = 20
			var rim_instance := _structure_mesh(root, rim, Vector3(0, 0.16, 0), stone)
			rim_instance.rotation.x = PI * 0.5
			var pool := CylinderMesh.new()
			pool.top_radius = 1.75
			pool.bottom_radius = 1.75
			pool.height = 0.06
			pool.radial_segments = 16
			var water := StandardMaterial3D.new()
			water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			water.albedo_color = Color(_realm_tint().r, _realm_tint().g, _realm_tint().b, 0.6)
			water.emission_enabled = true
			water.emission = _realm_tint()
			water.emission_energy_multiplier = 0.25
			_structure_mesh(root, pool, Vector3(0, 0.14, 0), water)
		"shrine":
			var base := CylinderMesh.new()
			base.top_radius = 1.25
			base.bottom_radius = 1.55
			base.height = 0.65
			base.radial_segments = 8
			_structure_mesh(root, base, Vector3(0, 0.32, 0), stone)
			var core := SphereMesh.new()
			core.radius = 0.46
			core.height = 0.92
			var glow := StandardMaterial3D.new()
			glow.albedo_color = _fx_tint().darkened(0.3)
			glow.emission_enabled = true
			glow.emission = _fx_tint()
			glow.emission_energy_multiplier = 0.8
			_structure_mesh(root, core, Vector3(0, 1.02, 0), glow)
		_:  # ruins
			var column_tall := CylinderMesh.new()
			column_tall.top_radius = 0.26
			column_tall.bottom_radius = 0.36
			column_tall.height = 2.2
			column_tall.radial_segments = 6
			var column_broken := CylinderMesh.new()
			column_broken.top_radius = 0.26
			column_broken.bottom_radius = 0.36
			column_broken.height = 1.1
			column_broken.radial_segments = 6
			for i in 7:
				var angle := TAU * float(i) / 7.0
				var broken := i % 3 == 0
				var mesh: CylinderMesh = column_broken if broken else column_tall
				var instance := _structure_mesh(root, mesh,
					Vector3(cos(angle) * 2.6, mesh.height * 0.5, sin(angle) * 2.6), stone)
				instance.rotation.z = 0.22 if broken else 0.0

## === Travel gates ===

## Realm travel stays a short walk from the arrival point. Gates own only the
## first few route waypoints: deriving them from the whole route pushed them
## 30-90 m out once the routes lengthened to reach the far boss arenas.
const GATE_ROUTE_SPAN := 3
## Hostiles and set-pieces keep this far clear of a travel gate.
const GATE_CLEARANCE := 12.0
## Authored props keep this far clear of an authored chest.
const CHEST_CLEARANCE := 4.0

## Deterministic gate anchors, filtered to the destinations that resolve to a
## real realm so callers and builders agree on the order.
func _gate_anchor_positions() -> Array[Vector3]:
	var dests: Array = _biome_def.get("gates", [])
	var origin := player_spawn.global_position
	var route: Array = RealmLayoutData.profile(_visual_realm_id()).get("route", [])
	var result: Array[Vector3] = []
	var base_angle := float(abs(int(biome_id.hash())) % 628) / 100.0
	for i in dests.size():
		if not Bestiary.WORLD_REALMS.has(str(dests[i])):
			continue
		var angle := base_angle + TAU * float(i) / maxf(float(dests.size()), 1.0)
		var pos := origin + Vector3(cos(angle) * 15.0, 0, sin(angle) * 15.0)
		if route.size() > 1:
			var span := mini(route.size() - 1, GATE_ROUTE_SPAN)
			var route_index := 1 + (i * maxi(span, 1)) / maxi(dests.size(), 1)
			pos = route[mini(route_index, span)]
		result.append(pos)
	return result

func _build_gates() -> void:
	var dests: Array = _biome_def.get("gates", [])
	var anchors := _gate_anchor_positions()
	var anchor_index := 0
	for i in dests.size():
		var dest := str(dests[i])
		if not Bestiary.WORLD_REALMS.has(dest):
			continue
		var pos: Vector3 = anchors[anchor_index] if anchor_index < anchors.size() \
			else player_spawn.global_position
		anchor_index += 1
		_gates.append({"node": _make_monolith(dest, pos), "dest": dest})

## === Reserved ground: boss arenas and travel gates ===
## Readable boss fights and unobstructed portals are gameplay contracts, not
## decoration. Authored hostiles and set-pieces are pushed clear of these zones
## at build time so future data edits cannot silently break them.

func _reserved_zones() -> Array[Dictionary]:
	var zones: Array[Dictionary] = []
	for anchor in RealmLayoutData.boss_anchor_points_for_world(self):
		zones.append({"pos": Vector3(anchor.x, 0.0, anchor.y), "radius": ARENA_CLEAR_RADIUS})
	for gate_pos in _gate_anchor_positions():
		zones.append({"pos": gate_pos, "radius": GATE_CLEARANCE})
	return zones

func _chest_anchor_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for chest in get_tree().get_nodes_in_group("authored_chest"):
		var node := chest as Node3D
		if node != null and is_instance_valid(node):
			result.append(node.global_position)
	return result

## Slide a point just outside every reserved circle it violates. Blockers push
## in order, so a point trapped between two zones settles outside the last one.
static func push_clear_of_zones(origin: Vector3, zones: Array[Dictionary]) -> Vector3:
	var result := origin
	for zone in zones:
		var blocker: Vector3 = zone.get("pos", Vector3.ZERO)
		var min_distance := float(zone.get("radius", 12.0))
		var offset := Vector3(result.x - blocker.x, 0.0, result.z - blocker.z)
		var gap := offset.length()
		if gap >= min_distance:
			continue
		var direction := offset.normalized() if gap > 0.1 else Vector3.BACK
		result = blocker + direction * min_distance
		result.y = origin.y
	return result

func _resolve_content_spot(origin: Vector3) -> Vector3:
	var spot := push_clear_of_zones(origin, _reserved_zones())
	for chest_pos in _chest_anchor_points():
		var offset := Vector3(spot.x - chest_pos.x, 0.0, spot.z - chest_pos.z)
		if offset.length() >= CHEST_CLEARANCE:
			continue
		var direction := offset.normalized() if offset.length() > 0.1 else Vector3.BACK
		spot = chest_pos + direction * CHEST_CLEARANCE
		spot.y = origin.y
	return spot

func _make_monolith(dest: String, pos: Vector3) -> Node3D:
	var gate := Node3D.new()
	gate.name = "Gate_%s" % dest
	gate.add_to_group("portal")
	gate.add_to_group("interactable")
	var dest_tint: Color = Bestiary.REALMS.get(dest, {}).get("mist_tint", Color(0.7, 0.8, 0.75))
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_texture = load("res://assets/textures/stylized/rock/albedo.png")
	stone_mat.normal_enabled = true
	stone_mat.normal_texture = load("res://assets/textures/stylized/rock/normal.png")
	stone_mat.roughness_texture = load("res://assets/textures/stylized/rock/roughness.png")
	stone_mat.albedo_color = Color(0.32, 0.30, 0.28).lerp(dest_tint, 0.16)
	stone_mat.roughness = 0.9
	var arch := Node3D.new()
	arch.name = "GroundedTravelArch"
	gate.add_child(arch)
	var stones: Array[Vector4] = [
		Vector4(-1.05, 0.48, 0.62, -0.10), Vector4(1.05, 0.48, 0.66, 0.12),
		Vector4(-0.95, 1.25, 0.58, -0.14), Vector4(0.92, 1.28, 0.60, 0.13),
		Vector4(-0.62, 2.02, 0.55, -0.12), Vector4(0.58, 2.06, 0.57, 0.10),
		Vector4(0.0, 2.34, 0.61, 0.02),
	]
	for i in stones.size():
		var spec: Vector4 = stones[i]
		var rock := MeshInstance3D.new()
		rock.name = "ArchStone_%d" % i
		var rock_mesh := SphereMesh.new()
		rock_mesh.radius = 0.68
		rock_mesh.height = 1.0
		rock_mesh.radial_segments = 7
		rock_mesh.rings = 4
		rock.mesh = rock_mesh
		rock.position = Vector3(spec.x, spec.y, 0.0)
		rock.scale = Vector3(spec.z * 1.12, spec.z, spec.z * 0.72)
		rock.rotation = Vector3(spec.w, float(i) * 0.73, -spec.w * 0.5)
		rock.material_override = stone_mat
		arch.add_child(rock)
	var threshold := MeshInstance3D.new()
	threshold.name = "TravelThreshold"
	var threshold_mesh := CylinderMesh.new()
	threshold_mesh.top_radius = 1.16
	threshold_mesh.bottom_radius = 1.32
	threshold_mesh.height = 0.12
	threshold_mesh.radial_segments = 9
	threshold.mesh = threshold_mesh
	threshold.scale.z = 0.52
	threshold.position.y = 0.03
	threshold.material_override = stone_mat
	arch.add_child(threshold)
	var veil := MeshInstance3D.new()
	veil.name = "PortalMistVolume"
	var veil_mesh := SphereMesh.new()
	veil_mesh.radius = 1.0
	veil_mesh.height = 2.0
	veil_mesh.radial_segments = 12
	veil_mesh.rings = 6
	veil.mesh = veil_mesh
	veil.position = Vector3(0, 1.18, 0.18)
	veil.scale = Vector3(0.70, 0.96, 0.10)
	var veil_mat := StandardMaterial3D.new()
	veil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil_mat.albedo_color = Color(dest_tint.r, dest_tint.g, dest_tint.b, 0.22)
	veil_mat.emission_enabled = true
	veil_mat.emission = dest_tint
	veil_mat.emission_energy_multiplier = 0.45
	veil.material_override = veil_mat
	arch.add_child(veil)
	var label := Label3D.new()
	label.text = str(Bestiary.WORLD_REALMS.get(dest, {}).get("name", dest)).to_upper()
	label.font_size = 62
	label.pixel_size = 0.004
	label.modulate = dest_tint
	label.outline_size = 11
	label.position = Vector3(0, 3.05, 0.3)
	gate.add_child(label)
	var glow := OmniLight3D.new()
	glow.light_color = dest_tint
	glow.light_energy = 0.8
	glow.omni_range = 4.5
	glow.position = Vector3(0, 1.6, 0)
	gate.add_child(glow)
	add_child(gate)
	gate.global_position = pos
	var terrain := get_node_or_null("Terrain") as TerrainRelief
	if terrain != null:
		terrain.conform_anchor(gate, 0.06)
	gate.set_meta("terrain_conformed", terrain != null)
	return gate

## === Compound: step into the ruin to wake the biome boss ===

func _build_arena() -> void:
	if _expansion_accessible():
		return
	var boss_id := str(_biome_def.get("boss_id", ""))
	if boss_id.is_empty():
		return  # final-boss biome: the Matriarch answers the quest rite only
	var theme := BOSS_COMPOUND_CATALOG.theme_for(boss_id)
	var arena_pos: Vector3 = RealmLayoutData.profile(_visual_realm_id()).get(
		"arena", player_spawn.global_position + Vector3(0, 0.1, -20))
	_arena_compound = BOSS_COMPOUND_SCRIPT.new()
	_arena_compound.name = "BossCompound"
	_arena_compound.add_to_group("boss_arena")
	add_child(_arena_compound)
	_arena_compound.setup({
		"boss_id": boss_id,
		"realm_id": _visual_realm_id(),
		"compound_radius": float(theme.get("radius", 22.0)),
		"trigger_radius": float(theme.get("trigger", 5.5)),
		"director": _boss_director,
		"host": self,
		"allowed": _primary_boss_allowed,
	})
	_arena_compound.global_position = arena_pos
	var terrain := get_node_or_null("Terrain") as TerrainRelief
	if terrain != null:
		terrain.conform_anchor(_arena_compound, 0.06)
	_arena_compound.boss_spawned.connect(_on_arena_boss_spawned)
	_arena_compound.boss_died.connect(_on_arena_boss_died)
	_arena_compound.boss_despawned.connect(_on_arena_boss_despawned)

func _primary_boss_allowed() -> bool:
	# The shared grove presents Whispergrove until the quest completes; the
	# Thorn Regent's compound stays dormant until then, exactly like the old
	# stage-gated arena stone.
	if biome_id == Bestiary.REALM_BRAMBLEWOOD \
			and int(game_state.current_stage) < int(game_state.QuestStage.COMPLETE):
		return false
	return true

func _build_side_bosses() -> void:
	if not _side_boss_markers.is_empty():
		return
	var profile := RealmLayoutData.profile(_visual_realm_id())
	var side_values: Variant = profile.get("side_bosses", [])
	if not side_values is Array:
		return
	for side_value in side_values:
		if not side_value is Dictionary:
			continue
		var definition: Dictionary = side_value
		var boss_id := BOSS_ROSTER.canonical_id_for(str(definition.get("id", "")))
		if BOSS_ROSTER.definition_for(boss_id).is_empty():
			continue
		var position_value: Variant = definition.get("position", Vector3.ZERO)
		if not position_value is Vector3:
			continue
		var theme := BOSS_COMPOUND_CATALOG.theme_for(boss_id)
		var compound := BOSS_COMPOUND_SCRIPT.new()
		compound.name = "BossCompound_%s" % boss_id
		compound.add_to_group("boss_arena")
		add_child(compound)
		var compound_radius := maxf(float(definition.get("arena_radius", 18.0)), 16.0)
		compound.setup({
			"boss_id": boss_id,
			"realm_id": _visual_realm_id(),
			"compound_radius": compound_radius,
			"trigger_radius": float(theme.get("trigger", 5.5)),
			"director": _boss_director,
			"host": self,
			"allowed": _side_boss_allowed,
		})
		compound.global_position = position_value
		var terrain := get_node_or_null("Terrain") as TerrainRelief
		if terrain != null:
			terrain.conform_anchor(compound, 0.06)
		compound.boss_spawned.connect(_on_side_boss_spawned)
		compound.boss_died.connect(_on_side_boss_died)
		compound.boss_despawned.connect(_on_side_boss_despawned)
		_side_boss_markers.append({"id": boss_id, "node": compound})

func _side_boss_allowed() -> bool:
	# Optional side bosses wake only after the primary boss is cleared, and
	# never while another compound boss is already on the field.
	if not _primary_boss_cleared():
		return false
	if _biome_boss != null and is_instance_valid(_biome_boss):
		return false
	return true

func _expansion_accessible() -> bool:
	return biome_id == Bestiary.REALM_BRAMBLEWOOD and game_state != null \
		and (bool(game_state.get("onboarding_completed")) \
		or int(game_state.get("current_stage")) >= int(game_state.QuestStage.COMPLETE))

func _build_bramblewood_expansion() -> void:
	if not _expansion_accessible() or (_bramblewood_expedition != null \
			and is_instance_valid(_bramblewood_expedition)):
		return
	if _arena_compound != null and is_instance_valid(_arena_compound):
		_arena_compound.queue_free()
		_arena_compound = null
	_bramblewood_expedition = BRAMBLEWOOD_EXPEDITION_SCRIPT.new()
	_bramblewood_expedition.name = "BramblewoodExpedition"
	add_child(_bramblewood_expedition)
	if _bramblewood_expedition.has_method("setup"):
		_bramblewood_expedition.call("setup", self)

func _build_realm_activity_director() -> void:
	if _realm_activity_director != null and is_instance_valid(_realm_activity_director):
		return
	_realm_activity_director = REALM_ACTIVITY_DIRECTOR_SCRIPT.new()
	_realm_activity_director.name = "RealmActivityDirector"
	add_child(_realm_activity_director)
	var activity_realm := _visual_realm_id()
	# The shared grove scene represents Whispergrove during onboarding and
	# Bramblewood after the expedition opens.  Save compatibility still
	# canonicalizes the old whispergrove id to bramblewood, so stage/access is
	# the reliable runtime discriminator for this activity layer.
	if biome_id == Bestiary.REALM_BRAMBLEWOOD and activity_realm == "bramblewood" \
			and not _expansion_accessible() and int(game_state.current_stage) < int(game_state.QuestStage.COMPLETE):
		activity_realm = "whispergrove"
	_realm_activity_director.setup(self, activity_realm, abs(int(biome_id.hash())))

func _engage_arena_boss() -> void:
	if _arena_compound == null or not is_instance_valid(_arena_compound):
		return
	if _biome_boss != null and is_instance_valid(_biome_boss):
		return
	_arena_compound.force_spawn()

func _engage_side_boss(index: int) -> void:
	if _biome_boss != null and is_instance_valid(_biome_boss):
		return
	if index < 0 or index >= _side_boss_markers.size():
		return
	var entry := _side_boss_markers[index]
	var compound := entry.get("node") as BossCompound
	if compound == null or not is_instance_valid(compound):
		return
	compound.force_spawn()

func _on_arena_boss_spawned(boss: Node3D) -> void:
	_biome_boss = boss

func _on_arena_boss_despawned(_boss_id: String) -> void:
	_biome_boss = null

func _on_side_boss_spawned(boss: Node3D) -> void:
	_biome_boss = boss

func _on_side_boss_despawned(_boss_id: String) -> void:
	_biome_boss = null

func _on_side_boss_died(_boss_id: String) -> void:
	_biome_boss = null

func _primary_boss_cleared() -> bool:
	if game_state == null or not game_state.has_method("has_boss_killed"):
		return false
	var required_key := BOSS_ROSTER.gameplay_key_for(str(_biome_def.get("boss_id", "")))
	if biome_id == Bestiary.REALM_BRAMBLEWOOD:
		required_key = "boss_whispergrove_root_harrow"
	return bool(game_state.call("has_boss_killed", required_key))

func _process_side_bosses(_player_position: Vector3) -> void:
	# Side-boss compounds own their trigger, gate, retreat and rematch timing.
	# Kept as the roster hook the map validation expects; no polling is needed.
	pass

func _reset_biome_boss() -> void:
	if _arena_compound != null and is_instance_valid(_arena_compound):
		_arena_compound.reset_encounter()
	for entry in _side_boss_markers:
		var compound := entry.get("node") as BossCompound
		if compound != null and is_instance_valid(compound):
			compound.reset_encounter()
	_biome_boss = null

func _on_arena_boss_died(_boss_id: String) -> void:
	_biome_boss = null
	game_state.quest_progress.emit("The biome exhales. The ruin will stir again if you seek a rematch.")

## === Frame: relic spin + proximity triggers ===
## NOTE: does not chain to WorldManager._process — the base version calls
## set_process(false) whenever no relic trophy exists, which would kill
## gate/arena polling.
func _process(delta: float) -> void:
	if _bramblewood_expedition == null and _expansion_accessible():
		_build_bramblewood_expansion()
	if _relic_trophy != null and is_instance_valid(_relic_trophy):
		_relic_trophy.rotate_y(delta * 0.7)
	# Throttled clean-up pass so packs left behind on the route are pruned
	# between respawn ticks, keeping the nearby cap honest while travelling.
	_despawn_sweep_in -= delta
	if _despawn_sweep_in <= 0.0:
		_despawn_sweep_in = 0.5
		_despawn_distant_enemies()
	_pocket_sweep_in -= delta
	if _pocket_sweep_in <= 0.0:
		_pocket_sweep_in = 1.0
		_tick_spawn_pockets()
	if _traveling or hero == null or not is_instance_valid(hero):
		return
	if _biome_boss != null and is_instance_valid(_biome_boss):
		return
	var pos := hero.global_position
	# Gates
	for g in _gates:
		var node: Node3D = g.get("node")
		if node == null or not is_instance_valid(node):
			continue
		if pos.distance_to(node.global_position) < 1.9:
			_travel_to(str(g.get("dest")))
			return
	_process_side_bosses(pos)

func _travel_to(dest: String) -> void:
	if _traveling:
		return
	var scene_path := Bestiary.biome_scene(dest)
	if scene_path.is_empty():
		return
	_traveling = true
	game_state.set_current_realm(dest)
	SceneLoader.travel.call_deferred(scene_path)

## === Quest finale stays out of Mistfen ===

func _open_boss_gate() -> void:
	if biome_id == Bestiary.REALM_MISTFEN:
		return  # no throne here for the Bramble Queen
	super._open_boss_gate()
