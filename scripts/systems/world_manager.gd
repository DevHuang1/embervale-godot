extends Node3D
class_name WorldManager

const MATRIARCH_BOSS_KEY := "res://scripts/entities/boss_hushling_matriarch.gd"
const THORN_WARDEN_BOSS_KEY := "res://scripts/entities/boss_bramblewood_thornwarden.gd"
const ROOT_HARROW_BOSS_KEY := "boss_whispergrove_root_harrow"
const BOSS_DIRECTOR_SCRIPT := preload("res://scripts/systems/boss_encounter_director.gd")
const TRAINING_TARGET_SCENE: PackedScene = preload("res://scenes/entities/combat_training_target.tscn")
const PROFILE_TELEMETRY := preload("res://scripts/systems/android_profile_telemetry.gd")
const ENEMY_VISUALS := preload("res://scripts/systems/enemy_visual_registry.gd")
## Contextual-button reach for walk-over loot. The drop itself still auto-
## collects under LootDrop.COLLECT_RADIUS; this only lets the on-screen
## button claim one the hero stopped just short of.
const LOOT_REACH := 2.0

## === Whispergrove World Manager ===
## Handles quest progression, spawns, day/night, environment

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var camera_rig: Node3D = $CameraRig
@onready var hero: Node3D = $Hero
@onready var hushling: Node3D = $Hushling
@onready var shard_spawn: Area3D = $ShardSpawn
@onready var beacon_spawn: Area3D = $BeaconSpawn
@onready var player_spawn: Marker3D = $PlayerSpawn
@onready var hushling_spawn: Marker3D = $HushlingSpawn
@onready var quest_board: MeshInstance3D = $QuestBoard
@onready var warm_lights: Node3D = $WarmLights
@onready var fireflies: GPUParticles3D = $Fireflies
@onready var mist_particles: GPUParticles3D = $MistParticles
@onready var moonfen_gate: Node3D = get_node_or_null("MoonfenGate")
@onready var return_gate: Node3D = get_node_or_null("ReturnGate")
@onready var world_environment: WorldEnvironment = $Environment

@export var lantern_active: bool = true
@export_range(0.0, 1.0, 0.01) var starting_time_of_day: float = 0.25
var day_night: DayNightCycle

var current_grove_state: int = 0  # 0=seek, 1=shard, 2=beacon, 3=complete
var hushling_defeated: bool = false
var shard_spawned: bool = false
var beacon_active: bool = false
var matriarch: Node3D = null
var matriarch_spawned: bool = false

# Realm ladder + tiered encounter packs (Bestiary-driven)
var _pack: Array[Node3D] = []
var _gate_opened := false
var _altar: BossAltar = null
var _practice_altar: Node3D = null
var _post_boss_root: Node3D = null
var _camp_shortcut_marker: Label3D = null

var _relic_trophy: Node3D = null
var _realm_expansion: RealmExpansion = null
var _castle_landmark: CastleLandmark = null
var _realm_audio_beds: RealmAudioBeds = null
var golden_route_tracker: GoldenRouteTracker
var android_profile_telemetry: AndroidProfileTelemetry
var _route_feedback_events: Dictionary = {}
var _quest_boss_director: BossEncounterDirector = null

@onready var relic_pedestal: Node3D = get_node_or_null("RelicPedestal")

func _ready() -> void:
	_build_camp_shortcut_marker()
	# Keep legacy quest nodes visible to the minimap even though they predate
	# the shared world-marker groups used by streamed realms.
	if quest_board != null:
		quest_board.add_to_group("interactable")
		quest_board.add_to_group("task")
	if shard_spawn != null:
		shard_spawn.add_to_group("interactable")
		shard_spawn.add_to_group("task")
	if beacon_spawn != null:
		beacon_spawn.add_to_group("interactable")
		beacon_spawn.add_to_group("event")

	golden_route_tracker = GoldenRouteTracker.new()
	golden_route_tracker.name = "GoldenRouteTracker"
	golden_route_tracker.set_process(false)
	add_child(golden_route_tracker)
	android_profile_telemetry = PROFILE_TELEMETRY.new()
	android_profile_telemetry.name = "AndroidProfileTelemetry"
	add_child(android_profile_telemetry)
	android_profile_telemetry.record_route_event("onboarding")
	_quest_boss_director = BOSS_DIRECTOR_SCRIPT.new()
	_quest_boss_director.setup(self)
	_init_signals()
	_init_day_night()
	_setup_grove()
	_realm_expansion = preload("res://scripts/world/realm_expansion.gd").new()
	_realm_expansion.name = "RealmExpansion"
	add_child(_realm_expansion)
	_realm_expansion.setup(self)
	_build_castle_landmark()
	call_deferred("_conform_runtime_anchors")
	audio.start_ambient()
	_realm_audio_beds = RealmAudioBeds.new()
	_realm_audio_beds.name = "RealmAudioBeds"
	add_child(_realm_audio_beds)
	_realm_audio_beds.setup()
	call_deferred("_play_realm_audio", Bestiary.realm_id_for_stage(current_grove_state))
	call_deferred("_prewarm_mobile_skill_fx")
	
	# Connect game state signals
	game_state.stage_changed.connect(_on_stage_changed)
	game_state.defeated.connect(_on_player_defeated)
	game_state.victory.connect(_on_player_victory)
	
	# Photo-forged relics get a rotating trophy by the quest board.
	ScanManager.relic_forged.connect(_spawn_relic_trophy)
	if ScanManager.last_relic != null:
		_spawn_relic_trophy(ScanManager.last_relic)
	_refresh_camp_shortcut_marker()
	refresh_route_markers()

func route_feedback(message: String, event_id: String = "") -> bool:
	var key := event_id.strip_edges()
	if not key.is_empty() and _route_feedback_events.has(key):
		return false
	if not key.is_empty():
		_route_feedback_events[key] = true
	if message.strip_edges().is_empty():
		return false
	game_state.quest_progress.emit(message)
	if android_profile_telemetry != null:
		android_profile_telemetry.record_route_event("feedback_" + (key if not key.is_empty() else message))
	return true

func _prewarm_mobile_skill_fx() -> void:
	if OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]:
		CombatFx.prewarm_mobile(self)

func refresh_route_markers() -> void:
	_refresh_camp_shortcut_marker()
	if android_profile_telemetry != null:
		android_profile_telemetry.record_route_event("markers_refreshed_%d" % int(game_state.current_stage))

func activate_camp_shortcut(realm: String, shortcut_id: String) -> bool:
	if realm != "bramblewood" or not CampProgression.is_shortcut_unlocked(realm, shortcut_id):
		return false
	game_state.set_route_checkpoint_for_shortcut(shortcut_id)
	if shortcut_id == "rootway_shortcut":
		var expansion := RealmLayoutData.profile("bramblewood").get("expansion_pockets", []) as Array
		for pocket_value in expansion:
			var pocket := pocket_value as Dictionary
			if str(pocket.get("id", "")) != "rootbound_court":
				continue
			var destination := pocket.get("position", Vector3.ZERO) as Vector3
			var terrain := get_node_or_null("Terrain")
			if terrain != null and terrain.has_method("sample_surface_height"):
				destination.y = float(terrain.call("sample_surface_height", destination)) + 0.35
			hero.global_position = destination
			break
	_refresh_camp_shortcut_marker()
	return true

func is_camp_shortcut_active(realm: String, shortcut_id: String) -> bool:
	return CampProgression.is_shortcut_unlocked(realm, shortcut_id)

func _build_camp_shortcut_marker() -> void:
	_camp_shortcut_marker = Label3D.new()
	_camp_shortcut_marker.name = "CampShortcutMarker"
	_camp_shortcut_marker.text = "LANTERN SHORTCUT\nCAMP ROUTE"
	_camp_shortcut_marker.add_to_group("interactable")
	_camp_shortcut_marker.add_to_group("portal")
	_camp_shortcut_marker.font_size = 18
	_camp_shortcut_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_camp_shortcut_marker.modulate = Color(1.0, 0.78, 0.25)
	_camp_shortcut_marker.position = Vector3(-3, 2.0, 13)
	add_child(_camp_shortcut_marker)

func _refresh_camp_shortcut_marker() -> void:
	if _camp_shortcut_marker != null:
		var rootway_open := CampProgression.is_shortcut_unlocked("bramblewood", "rootway_shortcut")
		var camp_route_open := CampProgression.is_shortcut_unlocked("bramblewood", "camp_route")
		_camp_shortcut_marker.visible = rootway_open or camp_route_open
		_camp_shortcut_marker.text = "ROOTWAY BEACON\nRETURN TO COURT" if rootway_open \
			else "LANTERN SHORTCUT\nCAMP ROUTE"

func toggle_dungeon() -> void:
	if _realm_expansion != null:
		_realm_expansion.toggle_dungeon()

func _build_castle_landmark() -> void:
	if _castle_landmark != null and is_instance_valid(_castle_landmark):
		return
	_castle_landmark = preload("res://scripts/world/castle_landmark.gd").new()
	_castle_landmark.name = "EmbervaultCastle"
	add_child(_castle_landmark)
	var terrain := get_node_or_null("Terrain")
	var anchor := Vector3(80.0, 0.0, 6.0)
	if terrain != null and terrain.has_method("sample_surface_height"):
		anchor.y = float(terrain.call("sample_surface_height", anchor))
	_castle_landmark.setup(_realm_expansion, terrain, anchor)

func start_golden_route_tracker() -> void:
	if golden_route_tracker == null:
		return
	golden_route_tracker.set_process(true)
	golden_route_tracker.start_route()

func stop_golden_route_tracker() -> void:
	if golden_route_tracker == null:
		return
	golden_route_tracker.stop_route()
	golden_route_tracker.set_process(false)

func get_android_profile_snapshot() -> Dictionary:
	if android_profile_telemetry == null:
		return {}
	return android_profile_telemetry.latest()

func set_android_profile_diagnostics(enabled: bool) -> void:
	if android_profile_telemetry != null and android_profile_telemetry.has_method(
			"set_diagnostics_enabled"):
		android_profile_telemetry.set_diagnostics_enabled(enabled)

func capture_route_snapshot() -> Dictionary:
	var camp: Node = get_node_or_null("/root/CampProgression")
	return {"realm": game_state.current_realm, "stage": int(game_state.current_stage), "checkpoint": game_state.route_checkpoint_id, "camp": camp.build_debug_snapshot() if camp != null else {}, "world_audit": get_runtime_world_audit(), "profile": get_android_profile_snapshot()}

func get_runtime_world_audit() -> Dictionary:
	var terrain := get_node_or_null("Terrain") as TerrainRelief
	var streamer := get_node_or_null("WorldStreamer") as WorldChunkStreamer
	var below_surface: Array[Dictionary] = []
	if terrain != null:
		for group_name in ["portal", "reward", "chest", "gathering", "task", "event"]:
			for candidate in get_tree().get_nodes_in_group(group_name):
				var anchor := candidate as Node3D
				if anchor == null or not is_ancestor_of(anchor):
					continue
				var surface := terrain.sample_surface_height(anchor.global_position)
				if anchor.global_position.y < surface - 0.04:
					below_surface.append({"node": str(anchor.get_path()),
						"height": anchor.global_position.y, "surface": surface})
	var weapon_id := str(game_state.equipped_weapon.get("id", ""))
	var armor_id := str(game_state.equipped_armor.get("id", ""))
	return {
		"terrain": terrain.get_material_report(hero.global_position) if terrain != null else {},
		"streaming": streamer.get_runtime_diagnostics() if streamer != null else {},
		"weapon_id": weapon_id,
		"weapon_path": WeaponVisualRegistry.path_for(weapon_id),
		"armor_id": armor_id,
		"armor_visual": ArmorVisualRegistry.record_for(armor_id),
		"visible_authored_rigs": find_children("AuthoredRig", "Node3D", true, false).size(),
		"objects_below_surface": below_surface,
		"boss_id": "whispergrove_root_harrow",
		"boss_active": matriarch != null and is_instance_valid(matriarch),
		"castle_active": _castle_landmark != null and is_instance_valid(_castle_landmark),
	}

func save_android_profile_report(path: String = "user://android_profile_report.json") -> bool:
	if android_profile_telemetry == null:
		return false
	return android_profile_telemetry.save_report(path)

func record_golden_route_signal(signal_id: String) -> bool:
	if golden_route_tracker == null:
		return false
	return golden_route_tracker.record_signal(signal_id)

func get_golden_route_report() -> Dictionary:
	if golden_route_tracker == null:
		return {"complete": false, "beats": [], "missing_signals": [], "signal_count": 0}
	return golden_route_tracker.route_report()

func _init_signals() -> void:
	# Hero signals
	if hero and hero.has_signal("position_changed"):
		hero.position_changed.connect(_on_hero_position_changed)
	if hero and hero.has_signal("interact_pressed"):
		hero.interact_pressed.connect(_on_hero_interact)

func _init_day_night() -> void:
	# The cycle owns the runtime Environment copy and applies quest-stage
	# grading as a per-frame bias layer on top of the base values.
	if day_night == null:
		day_night = DayNightCycle.new()
		day_night.name = "DayNightCycle"
		day_night.start_time = starting_time_of_day
		add_child(day_night)

func _setup_grove() -> void:
	# Initial positions
	current_grove_state = int(game_state.current_stage)
	hero.global_position = player_spawn.global_position
	hushling.global_position = hushling_spawn.global_position
	_conform_quest_anchors_to_terrain()

	# Killing the starter sprite is what opens Chapter II
	if hushling != null and hushling.has_signal("died"):
		hushling.died.connect(_on_starter_hushling_died)

	_soften_particle_sprites()
	# Hide quest objects initially
	shard_spawn.visible = false
	beacon_spawn.visible = false
	beacon_spawn.set_collision_layer_value(1, false)
	
	# Set initial quest board texture
	_update_quest_board()
	
	# Sync world visuals to any restored quest state
	_update_grove_for_stage()
	_start_golden_route_if_needed()

## Quest anchors used authored Y=0.5 before terrain relief was introduced.
## Keep their X/Z gameplay coordinates stable, but lift the complete node
## (visuals, light, and pickup collision together) onto the live surface.
func _conform_quest_anchors_to_terrain() -> void:
	var terrain := get_node_or_null("Terrain")
	if terrain == null or not terrain.has_method("sample_surface_height"):
		return
	for anchor in [shard_spawn, beacon_spawn]:
		if anchor == null:
			continue
		var p: Vector3 = anchor.global_position
		p.y = float(terrain.call("sample_surface_height", p)) + 0.35
		anchor.global_position = p

func _conform_runtime_anchors() -> void:
	var terrain := get_node_or_null("Terrain") as TerrainRelief
	if terrain == null:
		return
	var seen: Dictionary = {}
	for group_name in ["portal", "reward", "chest", "gathering", "task", "event"]:
		for candidate in get_tree().get_nodes_in_group(group_name):
			var anchor := candidate as Node3D
			if anchor == null or not is_ancestor_of(anchor) or seen.has(anchor):
				continue
			seen[anchor] = true
			terrain.conform_anchor(anchor, float(anchor.get_meta("terrain_offset", 0.08)))
	_conform_quest_anchors_to_terrain()

func _start_golden_route_if_needed() -> void:
	if golden_route_tracker == null or golden_route_tracker.active:
		return
	# A clean arrival owns the pacing clock. Recovered checkpoints must not
	# restart or overwrite route timing after defeat, reload, or travel.
	if current_grove_state == GameState.QuestStage.SEEK_SPRITE \
			and str(game_state.route_checkpoint_id) == "grove_arrival" \
			and game_state.get_activity_recovery().is_empty():
		start_golden_route_tracker()

func _on_starter_hushling_died() -> void:
	if game_state.current_stage != GameState.QuestStage.SEEK_SPRITE or hushling_defeated:
		return
	hushling_defeated = true
	game_state.advance_stage(GameState.QuestStage.CLAIM_SHARD)

func _on_stage_changed(new_stage: int) -> void:
	current_grove_state = new_stage
	_apply_realm_theme(new_stage)
	_spawn_wave(new_stage)
	_update_grove_for_stage()
	_update_quest_board()
	_play_realm_audio(Bestiary.realm_id_for_stage(new_stage))
	if android_profile_telemetry != null:
		android_profile_telemetry.record_route_event("stage_%d" % new_stage)
	refresh_route_markers()
	route_feedback(str(game_state.get_quest_instruction(game_state.current_stage)), "stage_objective_%d" % new_stage)
	# Stage atmosphere re-grades via DayNightCycle's bias layer (per frame)

func _play_realm_audio(realm_id: String) -> void:
	if _realm_audio_beds != null and is_instance_valid(_realm_audio_beds):
		_realm_audio_beds.play_realm_ambient(realm_id)

## === Realms: palette bias on the shared grove ===
func _apply_realm_theme(stage: int) -> void:
	if day_night == null:
		return
	var realm := Bestiary.realm_for_stage(stage)
	day_night.apply_realm(realm.get("mist_tint", Color(0.65, 0.75, 0.72)),
		realm.get("firefly_tint", Color(1.0, 0.86, 0.45)),
		realm.get("grade", {}))

## === Tiered encounter packs (normal / hard per realm) ===
func _spawn_wave(stage: int) -> void:
	_clear_pack()
	var comp: Dictionary = Bestiary.WAVES.get(int(stage), {})
	if comp.is_empty():
		return
	# Keep total hostiles bounded alongside boss summons
	if get_tree().get_nodes_in_group("enemy").size() > 6:
		return
	var realm_id := Bestiary.realm_id_for_stage(stage)
	var origin := hero.global_position if hero != null else player_spawn.global_position
	var elite_count := int(comp.get("elite", 0))
	var hard_count := int(comp.get("hard", 0))
	var normal_count := int(comp.get("normal", 0))
	var total := elite_count + hard_count + normal_count
	var idx := 0
	for i in elite_count:
		_spawn_pack_enemy(origin, realm_id, true, idx, total, true)
		idx += 1
	for i in hard_count:
		_spawn_pack_enemy(origin, realm_id, true, idx, total)
		idx += 1
	for i in normal_count:
		_spawn_pack_enemy(origin, realm_id, false, idx, total)
		idx += 1

func _spawn_pack_enemy(origin: Vector3, realm_id: String, hard: bool,
		idx: int, total: int, elite: bool = false) -> void:
	var v := Bestiary.variant_for(realm_id, "hard" if hard else "normal")
	if v.is_empty():
		return
	# Every Bestiary kind resolves through the shared enemy scene catalog, so
	# packs and pockets anywhere in the realm field the rigged creatures too.
	var kind := str(v.get("kind", "hushling"))
	# An elite wave wears its realm's elite creature rig and behavior, not the
	# tier kind, so the same realm elite reads the same everywhere it appears.
	var elite_v := Bestiary.variant_for(realm_id, "elite") if elite else {}
	if elite and not elite_v.is_empty():
		kind = str(elite_v.get("kind", kind))
	var scene_path := "res://scenes/entities/elite_hushling.tscn" \
		if elite else ENEMY_VISUALS.scene_for(kind)
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return
	var enemy: Node3D = scene.instantiate()
	if enemy == null:
		return
	if elite and elite_v.has("rig"):
		if "rig_profile_override" in enemy:
			enemy.set("rig_profile_override", str(elite_v.get("rig", "")))
		if "authored_rig_height" in enemy:
			enemy.set("authored_rig_height", float(elite_v.get("rig_height", 0.0)))
	add_child(enemy)
	enemy.global_position = _pack_spot(origin, idx, total)
	var md := CharacterModelData.new()
	md.display_name = "Ember Warden" if elite else str(v.get("display", "Hushling"))
	md.model_scale = 1.18 if elite else float(v.get("scale", 1.0))
	md.body_tint = Color(0.28, 0.08, 0.04, 1.0) if elite else v.get("tint", Color(0, 0, 0, 0))
	md.eye_glow_color = Color(1.0, 0.30, 0.08, 1.0) if elite else v.get("eye", Color(0, 0, 0, 0))
	md.max_hp_override = 0 if elite else int(v.get("hp", 0))
	md.base_atk_bonus = 0 if elite else int(v.get("atk_bonus", 0))
	md.move_speed_mult = 0.92 if elite else float(v.get("speed", 1.0))
	md.configure_entity(enemy)
	if enemy.has_method("configure_archetype"):
		if not enemy is RealmArchetypeEnemy:
			enemy.configure_archetype(kind)
	if bool(v.get("volley", false)) and "thorn_volley" in enemy:
		enemy.thorn_volley = true
	if elite:
		enemy.name = "EliteEmberWarden_%d" % idx
	# Spawn read: realm-tinted portal + positional cue so the pack materializes
	# with clear audio/visual feedback instead of silently popping in.
	var realm: Dictionary = Bestiary.REALMS.get(realm_id, {})
	var portal_color: Color = Color(realm.get("mist_tint",
		Color(0.65, 0.75, 0.72)))
	CombatFx.spawn_spawn_portal(self, enemy.global_position, portal_color)
	if AudioManager.has_method("play_synth_at"):
		AudioManager.play_synth_at(enemy, "enemy_spawn", 0.0)
	_pack.append(enemy)

func _pack_spot(origin: Vector3, idx: int, total: int) -> Vector3:
	var angle := TAU * float(idx) / maxf(float(total), 1.0) + randf_range(-0.25, 0.25)
	var dist := randf_range(9.0, 13.0)
	return origin + Vector3(cos(angle) * dist, 0.2, sin(angle) * dist)

func _clear_pack() -> void:
	for e in _pack:
		if is_instance_valid(e):
			e.queue_free()
	_pack.clear()

# === Relic trophy: the captured object, spinning above its pedestal ===
func _spawn_relic_trophy(relic) -> void:
	if relic_pedestal == null or relic == null or relic.mesh == null:
		return
	if _relic_trophy != null and is_instance_valid(_relic_trophy):
		_relic_trophy.queue_free()
	_relic_trophy = Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = relic.mesh
	_relic_trophy.add_child(mi)
	# Elemental relics tint their pedestal light and shed matching motes
	var element := str(relic.get("element") if relic is Dictionary \
		else relic.element)
	var glow_color: Color = ImpactDirector.ELEMENT_COLORS.get(element,
		Color(1.0, 0.72, 0.29))
	var glow := OmniLight3D.new()
	glow.light_color = glow_color
	glow.light_energy = 0.9
	glow.omni_range = 3.5
	glow.omni_attenuation = 1.6
	_relic_trophy.add_child(glow)
	add_child(_relic_trophy)
	_relic_trophy.global_position = relic_pedestal.global_position + Vector3(0, 1.15, 0)
	if element != "":
		CombatFx.spawn_motes(self,
			relic_pedestal.global_position + Vector3(0, 1.2, 0),
			Color(glow_color.r, glow_color.g, glow_color.b, 0.7),
			12, 0.5, 1.2, 1.4)
	set_process(true)

func _process(delta: float) -> void:
	if _relic_trophy != null and is_instance_valid(_relic_trophy):
		_relic_trophy.rotate_y(delta * 0.7)
	else:
		set_process(false)

# === Particle sprite fix: square quads get a runtime radial-gradient glow ===
func _soften_particle_sprites() -> void:
	for node_path in ["Fireflies", "MistParticles"]:
		var p := get_node_or_null(node_path) as GPUParticles3D
		if p == null or not (p.draw_pass_1 is QuadMesh):
			continue
		var mesh := p.draw_pass_1 as QuadMesh
		if mesh.material is StandardMaterial3D:
			var mat: StandardMaterial3D = mesh.material.duplicate()
			mat.albedo_texture = CombatFx.radial_glow_texture()
			mesh.material = mat

## Cached scene references can be freed before this manager is: a defeated
## hushling frees itself, and a realm teardown runs ahead of the persistent
## GameState signals. Every cached node is checked before it is written to.
static func is_live(node: Variant) -> bool:
	# Untyped on purpose: a typed member that holds a freed node cannot even be
	# bound to an `Object` parameter, which would raise instead of answering.
	return node != null and is_instance_valid(node)

func _update_grove_for_stage() -> void:
	if is_live(moonfen_gate):
		moonfen_gate.visible = current_grove_state == GameState.QuestStage.COMPLETE
	if is_live(return_gate):
		return_gate.visible = true
	match current_grove_state:
		GameState.QuestStage.SEEK_SPRITE:
			# Hushling active, shard/beacon hidden. The hushling frees itself on
			# death, so a later stage change can arrive with it already gone.
			if is_live(hushling):
				hushling.visible = true
				hushling.set_collision_layer_value(1, true)
			if is_live(shard_spawn):
				shard_spawn.visible = false
			if is_live(beacon_spawn):
				beacon_spawn.visible = false
				beacon_spawn.set_collision_layer_value(1, false)
			
		GameState.QuestStage.CLAIM_SHARD:
			# Hushling defeated, shard appears
			hushling_defeated = true
			if is_live(hushling):
				hushling.visible = false
				hushling.set_collision_layer_value(1, false)
			
			if not shard_spawned and is_live(shard_spawn):
				shard_spawn.visible = true
				shard_spawn.set_collision_layer_value(4, true)  # Pickup layer
				shard_spawned = true
				# Pulse animation
				var tween = create_tween()
				tween.set_loops()
				tween.tween_property(shard_spawn, "scale", Vector3(1.2, 1.2, 1.2), 1.0)
				tween.tween_property(shard_spawn, "scale", Vector3(1.0, 1.0, 1.0), 1.0)
			
		GameState.QuestStage.LIGHT_BEACON:
			# Shard collected, beacon activates
			if is_live(shard_spawn):
				shard_spawn.visible = false
				shard_spawn.set_collision_layer_value(4, false)
			if is_live(beacon_spawn):
				beacon_spawn.visible = true
				beacon_spawn.set_collision_layer_value(1, true)
			beacon_active = true
			# Beacon light effect
			_enable_beacon_light()
			
		GameState.QuestStage.COMPLETE:
			# Quest complete - beacon lit permanently
			if is_live(beacon_spawn):
				beacon_spawn.visible = true
			_open_boss_gate()
			if is_live(beacon_spawn):
				_permanent_beacon_light()

func _update_quest_board() -> void:
	# Update quest board material with current stage
	var stage_copy = game_state.get_quest_copy(current_grove_state)
	# In practice, this would update a texture or shader parameter
	pass

func _enable_beacon_light() -> void:
	if not is_live(beacon_spawn):
		return
	# Add strong light at beacon
	var beacon_light = OmniLight3D.new()
	beacon_light.light_color = Color(1.0, 0.84, 0.47)
	beacon_light.light_energy = 3.4
	beacon_light.omni_range = 30.0
	beacon_light.omni_attenuation = 1.5
	add_child(beacon_light)
	beacon_light.global_position = beacon_spawn.global_position + Vector3(0, 3, 0)
	
	# Rising ember motes + warm ground glow (pooled GPU fx)
	var origin: Vector3 = beacon_spawn.global_position
	CombatFx.spawn_burst(self, origin + Vector3(0, 1.2, 0),
		Color(1, 0.84, 0.47, 0.85), 40, 2.2, 1.6, 0.16)
	CombatFx.spawn_ring(self, origin, 3.2, Color(1, 0.84, 0.47, 0.7), 1.4)

func _spawn_matriarch(practice: bool = false) -> void:
	if matriarch != null and is_instance_valid(matriarch):
		return  # an earlier Matriarch still stands
	matriarch_spawned = true
	if _quest_boss_director == null:
		push_error("WorldManager: boss encounter director is unavailable")
		return
	var player_position := hero.global_position if hero != null \
		and is_instance_valid(hero) else beacon_spawn.global_position
	var boss_position := BOSS_DIRECTOR_SCRIPT.entry_position_for(
		beacon_spawn.global_position, player_position)
	boss_position.y += 0.1
	matriarch = _quest_boss_director.spawn_boss(ROOT_HARROW_BOSS_KEY, practice,
		boss_position)
	if matriarch == null:
		return
	var terrain := get_node_or_null("Terrain") as TerrainRelief
	if terrain != null:
		terrain.conform_anchor(matriarch, 0.12)
	if matriarch.has_method("set_encounter_origin"):
		matriarch.set_encounter_origin(matriarch.global_position)
	if camera_rig:
		camera_rig.add_shake(0.6)
		camera_rig.play_boss_intro(matriarch)
	audio.start_boss_score("root_harrow")
	if matriarch.has_signal("phase_changed"):
		matriarch.phase_changed.connect(_on_matriarch_phase_changed)
	if matriarch.has_signal("encounter_reset"):
		matriarch.encounter_reset.connect(_on_matriarch_encounter_reset)
	if matriarch.has_signal("death_sequence_started"):
		matriarch.death_sequence_started.connect(_on_matriarch_death_sequence_started)
	if matriarch.has_signal("died"):
		matriarch.died.connect(_on_matriarch_died.bind(matriarch))

func _on_matriarch_phase_changed(phase: int) -> void:
	audio.set_boss_score_phase(phase)

func _on_matriarch_encounter_reset() -> void:
	audio.reset_boss_score()

func _on_matriarch_death_sequence_started(boss: Node3D) -> void:
	if camera_rig and is_instance_valid(boss):
		camera_rig.play_kill_cam(boss)
	var was_practice: bool = boss.is_practice if "is_practice" in boss else false
	audio.finish_boss_score(not was_practice)
	CombatFx.spawn_shockwave(self, boss.global_position, 5.2,
		Color(0.68, 1.0, 0.76, 0.78), 0.9)
	CombatFx.spawn_motes(self, boss.global_position + Vector3.UP * 1.6,
		Color(0.76, 1.0, 0.82, 0.8), 22, 2.6, 1.3, 2.0)
	if not was_practice:
		FloatingText.spawn_on_entity(boss, "THE ROOT HARROW FALLS",
			Color(0.82, 1.0, 0.84), 1.25)

func _on_matriarch_died(boss: Node3D) -> void:
	var was_practice: bool = boss.is_practice if "is_practice" in boss else false
	matriarch = null
	if not was_practice:
		_apply_post_matriarch_state(true)
		_spawn_practice_altar()

func _exit_tree() -> void:
	# The audio autoload outlives this realm, so stop both fixed boss voices and
	# transient world-space one-shots before travel, reload, or title-screen use.
	if audio != null:
		audio.stop_all_playback()
	# Persistent autoloads outlive the realm too: drop their connections so a
	# reload or realm travel cannot drive a half-torn-down scene.
	_disconnect_persistent_signals()
	# Every gameplay scene replacement must also release any interface hold
	# (boss altar, satchel, settings). A CanvasLayer freed without popping its
	# push would otherwise leave the next scene paused with no way out.
	if game_state != null and is_instance_valid(game_state) \
			and game_state.has_method("clear_ui_freeze"):
		game_state.clear_ui_freeze()

func _disconnect_persistent_signals() -> void:
	if game_state != null and is_instance_valid(game_state):
		for signal_name in ["stage_changed", "defeated", "victory"]:
			var callable := Callable(self, "_on_stage_changed") if signal_name == "stage_changed" \
				else (Callable(self, "_on_player_defeated") if signal_name == "defeated" \
				else Callable(self, "_on_player_victory"))
			if game_state.has_signal(signal_name) \
					and game_state.is_connected(signal_name, callable):
				game_state.disconnect(signal_name, callable)
	if ScanManager != null and is_instance_valid(ScanManager) \
			and ScanManager.relic_forged.is_connected(_spawn_relic_trophy):
		ScanManager.relic_forged.disconnect(_spawn_relic_trophy)

## === Boss gate: "Shape Your Foe" before the Matriarch wakes ===
## Players with scans may spend one to personalize her; everyone else —
## or anyone who declines — faces the untouched default.
func _open_boss_gate() -> void:
	if _gate_opened:
		return
	if game_state.has_boss_killed(ROOT_HARROW_BOSS_KEY) \
			or game_state.has_boss_killed(THORN_WARDEN_BOSS_KEY) \
			or game_state.has_boss_killed(MATRIARCH_BOSS_KEY):
		_apply_post_matriarch_state(false)
		_spawn_practice_altar()
		return
	_gate_opened = true
	if game_state.scans_remaining > 0:
		_show_altar(false)
	else:
		_resolve_boss_gate(false)

func _show_altar(practice: bool) -> void:
	if _altar != null and is_instance_valid(_altar):
		return
	var scene: PackedScene = load("res://scenes/ui/boss_altar.tscn")
	if scene == null:
		push_error("WorldManager: boss altar scene missing!")
		if not practice:
			_resolve_boss_gate(false)
		return
	var altar := scene.instantiate() as BossAltar
	if altar == null:
		push_error("WorldManager: boss altar scene is not a BossAltar")
		if not practice:
			_resolve_boss_gate(false)
		return
	_altar = altar
	add_child(_altar)
	_altar.practice = practice
	_altar.resolved.connect(_on_altar_resolved.bind(practice))
	game_state.push_world_freeze()

func _on_altar_resolved(customized: bool, practice: bool) -> void:
	game_state.pop_world_freeze()
	if is_instance_valid(_altar):
		_altar.queue_free()
	_altar = null
	if practice:
		_spawn_matriarch(true)
		_apply_stored_customization()
		return
	_resolve_boss_gate(customized)

func _resolve_boss_gate(customized: bool) -> void:
	_spawn_matriarch()
	_apply_stored_customization()

## Re-applies whatever customization is stored for the matriarch; a save
## reload keeps skill/palette/SFX and simply omits the idol mesh.
func _apply_stored_customization() -> void:
	if matriarch == null or not is_instance_valid(matriarch):
		return
	var payload := game_state.get_boss_custom("matriarch")
	if payload.is_empty():
		return
	matriarch.apply_customization(BossCustomization.from_payload(payload))

# === Practice altar: re-face a customized Matriarch for another scan ===
func _spawn_practice_altar() -> void:
	if _practice_altar != null and is_instance_valid(_practice_altar):
		return
	if game_state.scans_remaining <= 0:
		return
	_practice_altar = Node3D.new()
	_practice_altar.name = "PracticeAltar"
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.6
	cyl.height = 1.1
	pillar.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.12, 0.10)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.25)
	mat.emission_energy_multiplier = 0.6
	pillar.material_override = mat
	_practice_altar.add_child(pillar)
	var target := TRAINING_TARGET_SCENE.instantiate()
	target.name = "CombatTrainingTarget"
	target.position = Vector3(0.0, 1.0, 1.8)
	_practice_altar.add_child(target)
	add_child(_practice_altar)
	_practice_altar.global_position = relic_pedestal.global_position \
		if relic_pedestal != null else beacon_spawn.global_position + Vector3(4, 0, 0)

## Reconstructed from the saved first-kill flag on every load. The aftermath
## is intentionally collision-free: it changes mood, landmarking, and the next
## goal without altering navigation or trapping the player.
func _apply_post_matriarch_state(announce: bool) -> void:
	_gate_opened = true
	matriarch_spawned = true
	if moonfen_gate:
		moonfen_gate.visible = true
	var ws := get_node_or_null("/root/WorldState")
	if ws != null:
		ws.weather_locked = true
		ws.set_rain(0.0)
	if _post_boss_root != null and is_instance_valid(_post_boss_root):
		return
	_post_boss_root = Node3D.new()
	_post_boss_root.name = "MatriarchAftermath"
	add_child(_post_boss_root)
	_post_boss_root.global_position = beacon_spawn.global_position + Vector3(0, 0.05, 6)
	var sprout_mat := StandardMaterial3D.new()
	sprout_mat.albedo_color = Color(0.16, 0.34, 0.22)
	sprout_mat.roughness = 0.88
	sprout_mat.emission_enabled = true
	sprout_mat.emission = Color(0.32, 0.88, 0.52)
	sprout_mat.emission_energy_multiplier = 0.42
	for i in 8:
		var sprout := MeshInstance3D.new()
		sprout.name = "CleansedSprout_%02d" % i
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.02
		mesh.bottom_radius = 0.13
		mesh.height = 0.8 + float(i % 3) * 0.18
		mesh.radial_segments = 7
		sprout.mesh = mesh
		sprout.material_override = sprout_mat
		var angle := TAU * float(i) / 8.0
		var radius := 4.4 + float(i % 2) * 1.2
		sprout.position = Vector3(cos(angle) * radius, mesh.height * 0.5,
			sin(angle) * radius)
		sprout.rotation = Vector3(sin(angle) * 0.12, 0.0, -cos(angle) * 0.12)
		_post_boss_root.add_child(sprout)
	var marker := Label3D.new()
	marker.name = "AftermathMarker"
	marker.text = "THE GROVE REMEMBERS"
	marker.font_size = 34
	marker.modulate = Color(0.72, 1.0, 0.78)
	marker.outline_size = 7
	marker.position = Vector3(0, 2.2, 0)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_post_boss_root.add_child(marker)
	if announce:
		game_state.quest_progress.emit(
			"The Matriarch has fallen. New growth marks the road to Moonfen.")

func _despawn_practice_altar() -> void:
	if _practice_altar != null and is_instance_valid(_practice_altar):
		_practice_altar.queue_free()
	_practice_altar = null

func _permanent_beacon_light() -> void:
	if not is_live(beacon_spawn):
		return
	# Upgrade beacon to permanent warm light
	var permanent_light = OmniLight3D.new()
	permanent_light.light_color = Color(1.0, 0.84, 0.47)
	permanent_light.light_energy = 2.0
	permanent_light.omni_range = 40.0
	permanent_light.omni_attenuation = 1.2
	add_child(permanent_light)
	permanent_light.global_position = beacon_spawn.global_position + Vector3(0, 4, 0)

func _on_hero_position_changed(pos: Vector3) -> void:
	game_state.player_position = Vector2(pos.x, pos.z)
	
	# Check quest proximity triggers
	_check_quest_proximity(pos)

func _check_quest_proximity(pos: Vector3) -> void:
	if game_state.combat_state != GameState.CombatState.EXPLORING:
		return
	
	var stage: int = current_grove_state
	
	if stage == GameState.QuestStage.CLAIM_SHARD and shard_spawned and not game_state.shard_collected:
		var dist = pos.distance_to(shard_spawn.global_position)
		if dist < 1.1:  # 1.1 units proximity
			_collect_shard()
	
	elif stage == GameState.QuestStage.LIGHT_BEACON and beacon_active and not game_state.beacon_lit:
		var dist = pos.distance_to(beacon_spawn.global_position)
		if dist < 1.45:
			_light_beacon()

	if stage == GameState.QuestStage.COMPLETE and moonfen_gate:
		if pos.distance_to(moonfen_gate.global_position) < 2.0:
			game_state.unlock_realm("moonfen")
			game_state.set_current_realm("moonfen")
			SceneLoader.travel("res://scenes/world/moonfen.tscn")
	elif stage == GameState.QuestStage.COMPLETE and return_gate:
		if pos.distance_to(return_gate.global_position) < 2.0:
			game_state.set_current_realm("bramblewood")
			SceneLoader.travel("res://scenes/world/grove.tscn")

	# Practice altar: walk close to re-personalize the Matriarch (1 scan)
	if stage == GameState.QuestStage.COMPLETE \
			and _practice_altar != null and is_instance_valid(_practice_altar) \
			and _altar == null and game_state.scans_remaining > 0:
		if pos.distance_to(_practice_altar.global_position) < 2.4:
			_despawn_practice_altar()
			_show_altar(true)

func _collect_shard() -> void:
	game_state.shard_collected = true
	game_state.add_loot("ember_shard", 1, "Ember Shard secured in the satchel.")
	game_state.advance_stage(GameState.QuestStage.LIGHT_BEACON)
	audio.play_loot_fanfare()

func _light_beacon() -> void:
	game_state.beacon_lit = true
	if game_state.has_method("update_objective"):
		game_state.update_objective("reach", "chapter3_beacon", 1)
	game_state.advance_stage(GameState.QuestStage.COMPLETE)
	audio.play_victory()
	# The lit beacon calms the sky: weather locks to a warm stillness
	var ws := get_node_or_null("/root/WorldState")
	if ws != null:
		ws.weather_locked = true
		ws.set_rain(0.0)

func _on_hero_interact() -> void:
	# Handle interactions based on nearby objects
	var nearby = _get_nearby_interactable()
	if nearby:
		if nearby == _camp_shortcut_marker:
			var camp_progression := get_node_or_null("/root/CampProgression")
			if camp_progression == null:
				return
			var shortcut_id := "rootway_shortcut" \
				if bool(camp_progression.call("is_shortcut_unlocked", "bramblewood",
					"rootway_shortcut")) \
				else "camp_route"
			camp_progression.call("unlock_shortcut", "bramblewood", shortcut_id)
			return
		# Group membership is a discovery hint, not a capability contract: the
		# quest board, beacon, shard, and realm gates share this group without an
		# interact() method. Calling through blindly raised a runtime error and
		# aborted the interaction, so a real chest standing next to them could
		# never open.
		if nearby.has_method("interact"):
			nearby.interact()
		return
	# Nothing openable in reach: claim the nearest loot drop the hero has not
	# already walked over, so the contextual button always does what it says.
	var drop := _get_nearby_loot_drop()
	if drop != null and drop.has_method("collect"):
		drop.call("collect", hero)

## Contextual interaction contract for the HUD's on-screen action button.
## Returns {} when nothing is in reach; otherwise the verb the button should
## show plus the node a press will act on.
func get_interact_prompt() -> Dictionary:
	var target := _get_nearby_interactable()
	if target != null:
		return {"verb": _interact_verb_for(target), "target": target}
	var drop := _get_nearby_loot_drop()
	if drop != null:
		return {"verb": "PICK UP", "target": drop}
	return {}

func _interact_verb_for(target: Node) -> String:
	if target.has_method("interact_prompt"):
		return str(target.call("interact_prompt"))
	if target.is_in_group("chest"):
		return "OPEN"
	if target.is_in_group("gathering"):
		return "GATHER"
	if target.is_in_group("activity"):
		return "BEGIN"
	return "INTERACT"

func _get_nearby_loot_drop() -> Node3D:
	var closest: Node3D = null
	var closest_dist := LOOT_REACH
	for candidate in get_tree().get_nodes_in_group("loot_drop"):
		var drop := candidate as Node3D
		if drop == null or not is_instance_valid(drop) or bool(drop.get("collected")):
			continue
		var dist := hero.global_position.distance_to(drop.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = drop
	return closest

func _get_nearby_interactable() -> Node:
	# Prefer the facing ray for deliberate interaction, but fall back to the
	# nearest configured prop so touch controls do not require pixel-perfect aim.
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		hero.global_position + Vector3(0, 1, 0),
		hero.global_position + Vector3(0, 1, 0) + hero.global_transform.basis.z * -2.0
	)
	query.collision_mask = 1 << 3 | 1 << 5  # Pickup + Environment
	query.exclude = [hero]
	var result = space_state.intersect_ray(query)
	if result and result.collider and result.collider.is_in_group("interactable") \
			and result.collider.has_method("interact"):
		return result.collider
	var closest: Node = null
	var closest_dist := 2.8
	for candidate in get_tree().get_nodes_in_group("interactable"):
		if not candidate is Node3D or not is_instance_valid(candidate):
			continue
		# Skip discovery-only group members so they cannot shadow a real
		# interactable with no way to respond.
		if not candidate.has_method("interact"):
			continue
		if candidate.get("opened") == true:
			continue
		var dist := hero.global_position.distance_to(candidate.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = candidate
	return closest

func _on_player_defeated() -> void:
	if game_state.has_method("fail_activity"):
		game_state.fail_activity("Defeated in the active activity.")
	# Reset to last safe state
	var respawn := player_spawn.global_position
	if game_state.route_respawn_position is Vector2:
		var saved := game_state.route_respawn_position
		respawn = Vector3(saved.x, player_spawn.global_position.y, saved.y)
	hero.global_position = respawn
	if game_state.has_method("recover_from_defeat"):
		game_state.recover_from_defeat()
	if matriarch != null and is_instance_valid(matriarch) \
			and matriarch.has_method("reset_encounter"):
		matriarch.reset_encounter()
	if has_method("_reset_biome_boss"):
		call("_reset_biome_boss")
	get_tree().call_group("screen_fx", "reset")
	# The starter hushling only returns while its quest stage is live;
	# it queue-frees on death and later stages keep it gone.
	if hushling != null and is_instance_valid(hushling) \
			and current_grove_state == GameState.QuestStage.SEEK_SPRITE:
		hushling.global_position = hushling_spawn.global_position
		hushling.visible = true
		hushling.set_collision_layer_value(1, true)
	hushling_defeated = false
	audio.play_defeat()

func _on_player_victory() -> void:
	# Quest complete - could transition to next area or loop
	if game_state.has_method("flush_save"):
		game_state.flush_save()

# === Public API ===
func get_hushling() -> Node3D:
	return hushling

func is_hushling_alive() -> bool:
	return hushling.visible and is_instance_valid(hushling)

func get_shard_position() -> Vector3:
	return shard_spawn.global_position

func get_beacon_position() -> Vector3:
	return beacon_spawn.global_position
