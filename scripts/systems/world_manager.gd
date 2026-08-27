extends Node3D
class_name WorldManager

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
var _altar: Node3D = null
var _practice_altar: Node3D = null

var _relic_trophy: Node3D = null

@onready var relic_pedestal: Node3D = get_node_or_null("RelicPedestal")

func _ready() -> void:
	_init_signals()
	_init_day_night()
	_setup_grove()
	audio.start_ambient()
	
	# Connect game state signals
	game_state.stage_changed.connect(_on_stage_changed)
	game_state.defeated.connect(_on_player_defeated)
	game_state.victory.connect(_on_player_victory)
	
	# Photo-forged relics get a rotating trophy by the quest board.
	ScanManager.relic_forged.connect(_spawn_relic_trophy)
	if ScanManager.last_relic != null:
		_spawn_relic_trophy(ScanManager.last_relic)

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
	# Stage atmosphere re-grades via DayNightCycle's bias layer (per frame)

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
	var hard_count := int(comp.get("hard", 0))
	var normal_count := int(comp.get("normal", 0))
	var total := hard_count + normal_count
	var idx := 0
	for i in hard_count:
		_spawn_pack_enemy(origin, realm_id, true, idx, total)
		idx += 1
	for i in normal_count:
		_spawn_pack_enemy(origin, realm_id, false, idx, total)
		idx += 1

func _spawn_pack_enemy(origin: Vector3, realm_id: String, hard: bool,
		idx: int, total: int) -> void:
	var v := Bestiary.variant_for(realm_id, "hard" if hard else "normal")
	if v.is_empty():
		return
	# Ranged "spitter" kin get their own rigged scene; everything else is
	# the classic hushling (recolored per realm by CharacterModelData).
	var kind := str(v.get("kind", "hushling"))
	var scene_path := "res://scenes/entities/spitter.tscn" \
		if kind == "spitter" else "res://scenes/entities/hushling.tscn"
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return
	var enemy: Node3D = scene.instantiate()
	add_child(enemy)
	enemy.global_position = _pack_spot(origin, idx, total)
	var md := CharacterModelData.new()
	md.display_name = str(v.get("display", "Hushling"))
	md.model_scale = float(v.get("scale", 1.0))
	md.body_tint = v.get("tint", Color(0, 0, 0, 0))
	md.eye_glow_color = v.get("eye", Color(0, 0, 0, 0))
	md.max_hp_override = int(v.get("hp", 0))
	md.base_atk_bonus = int(v.get("atk_bonus", 0))
	md.move_speed_mult = float(v.get("speed", 1.0))
	md.configure_entity(enemy)
	if bool(v.get("volley", false)) and "thorn_volley" in enemy:
		enemy.thorn_volley = true
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

func _update_grove_for_stage() -> void:
	if moonfen_gate:
		moonfen_gate.visible = current_grove_state == GameState.QuestStage.COMPLETE
	if return_gate:
		return_gate.visible = true
	match current_grove_state:
		GameState.QuestStage.SEEK_SPRITE:
			# Hushling active, shard/beacon hidden
			hushling.visible = true
			hushling.set_collision_layer_value(1, true)
			shard_spawn.visible = false
			beacon_spawn.visible = false
			beacon_spawn.set_collision_layer_value(1, false)
			
		GameState.QuestStage.CLAIM_SHARD:
			# Hushling defeated, shard appears
			hushling_defeated = true
			if hushling != null and is_instance_valid(hushling):
				hushling.visible = false
				hushling.set_collision_layer_value(1, false)
			
			if not shard_spawned:
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
			shard_spawn.visible = false
			shard_spawn.set_collision_layer_value(4, false)
			beacon_spawn.visible = true
			beacon_spawn.set_collision_layer_value(1, true)
			beacon_active = true
			# Beacon light effect
			_enable_beacon_light()
			
		GameState.QuestStage.COMPLETE:
			# Quest complete - beacon lit permanently
			beacon_spawn.visible = true
			_permanent_beacon_light()
			_open_boss_gate()

func _update_quest_board() -> void:
	# Update quest board material with current stage
	var stage_copy = game_state.get_quest_copy(current_grove_state)
	# In practice, this would update a texture or shader parameter
	pass

func _enable_beacon_light() -> void:
	# Add strong light at beacon
	var beacon_light = OmniLight3D.new()
	beacon_light.light_color = Color(1.0, 0.84, 0.47)
	beacon_light.light_energy = 3.4
	beacon_light.omni_range = 30.0
	beacon_light.omni_attenuation = 1.5
	beacon_light.global_position = beacon_spawn.global_position + Vector3(0, 3, 0)
	add_child(beacon_light)
	
	# Rising ember motes + warm ground glow (pooled GPU fx)
	var origin: Vector3 = beacon_spawn.global_position
	CombatFx.spawn_burst(self, origin + Vector3(0, 1.2, 0),
		Color(1, 0.84, 0.47, 0.85), 40, 2.2, 1.6, 0.16)
	CombatFx.spawn_ring(self, origin, 3.2, Color(1, 0.84, 0.47, 0.7), 1.4)

func _spawn_matriarch(practice: bool = false) -> void:
	if matriarch != null and is_instance_valid(matriarch):
		return  # an earlier Matriarch still stands
	matriarch_spawned = true
	var scene: PackedScene = load("res://scenes/entities/boss_matriarch.tscn")
	if scene == null:
		push_error("WorldManager: Matriarch scene missing!")
		return
	matriarch = scene.instantiate()
	add_child(matriarch)
	if "is_practice" in matriarch:
		matriarch.is_practice = practice
	matriarch.global_position = beacon_spawn.global_position + Vector3(0, 0.1, 6)
	if camera_rig:
		camera_rig.add_shake(0.6)
		camera_rig.play_boss_intro(matriarch)
	if matriarch.has_signal("died"):
		matriarch.died.connect(_on_matriarch_died.bind(matriarch))

func _on_matriarch_died(boss: Node3D) -> void:
	if camera_rig and is_instance_valid(boss):
		camera_rig.play_kill_cam(boss)
	var was_practice: bool = boss.is_practice if "is_practice" in boss else false
	matriarch = null
	if not was_practice:
		_spawn_practice_altar()

## === Boss gate: "Shape Your Foe" before the Matriarch wakes ===
## Players with scans may spend one to personalize her; everyone else —
## or anyone who declines — faces the untouched default.
func _open_boss_gate() -> void:
	if _gate_opened:
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
	_altar = scene.instantiate()
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
	add_child(_practice_altar)
	_practice_altar.global_position = relic_pedestal.global_position \
		if relic_pedestal != null else beacon_spawn.global_position + Vector3(4, 0, 0)

func _despawn_practice_altar() -> void:
	if _practice_altar != null and is_instance_valid(_practice_altar):
		_practice_altar.queue_free()
	_practice_altar = null

func _permanent_beacon_light() -> void:
	# Upgrade beacon to permanent warm light
	var permanent_light = OmniLight3D.new()
	permanent_light.light_color = Color(1.0, 0.84, 0.47)
	permanent_light.light_energy = 2.0
	permanent_light.omni_range = 40.0
	permanent_light.omni_attenuation = 1.2
	permanent_light.global_position = beacon_spawn.global_position + Vector3(0, 4, 0)
	add_child(permanent_light)

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
			get_tree().change_scene_to_file("res://scenes/world/moonfen.tscn")
	elif stage == GameState.QuestStage.COMPLETE and return_gate:
		if pos.distance_to(return_gate.global_position) < 2.0:
			game_state.set_current_realm("bramblewood")
			get_tree().change_scene_to_file("res://scenes/world/grove.tscn")

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
		nearby.interact()

func _get_nearby_interactable() -> Node:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		hero.global_position + Vector3(0, 1, 0),
		hero.global_position + Vector3(0, 1, 0) + hero.global_transform.basis.z * -2.0
	)
	query.collision_mask = 1 << 3 | 1 << 5  # Pickup + Environment
	var result = space_state.intersect_ray(query)
	if result and result.collider:
		return result.collider
	return null

func _on_player_defeated() -> void:
	# Reset to last safe state
	hero.global_position = player_spawn.global_position
	game_state.hp = game_state.max_hp
	game_state.hp_changed.emit(0, game_state.hp)
	game_state.combat_state = GameState.CombatState.EXPLORING
	game_state.disengage_enemy()
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
	pass

# === Public API ===
func get_hushling() -> Node3D:
	return hushling

func is_hushling_alive() -> bool:
	return hushling.visible and is_instance_valid(hushling)

func get_shard_position() -> Vector3:
	return shard_spawn.global_position

func get_beacon_position() -> Vector3:
	return beacon_spawn.global_position