extends Node
class_name RealmExpansion

## === RealmExpansion — Realm Progression Unlock System ===
## Instantiated by world_manager._ready():
##   _realm_expansion = preload("res://scripts/world/realm_expansion.gd").new()
##   _realm_expansion.name = "RealmExpansion"
##   add_child(_realm_expansion)
##   _realm_expansion.setup(self)
##
## Responsibilities:
##   - Gate unlocks: show MoonfenGate when Bramblewood boss is defeated
##   - Show ReturnGate back to previous realm
##   - Handle gate interaction → GameState.realm_changed signal
##   - Altar placement for boss practice respawns
##   - Relic trophy pedestal update after forge

signal gate_opened(target_realm: String)
signal gate_closed
signal altar_placed(altar: Node3D)
signal dungeon_state_changed(interior_active: bool)
signal dungeon_completed(dungeon_id: String)

var _world : Node3D = null
var in_dungeon := false
var _dungeon_root: Node3D = null
var _surface_return_position := Vector3.ZERO

const DUNGEON_POSITION := Vector3(80.0, 0.3, 6.0)
const DUNGEON_MODULES: Dictionary = {
	"floor": "res://assets/models/kenney_mini_dungeon/Models/floor.fbx",
	"wall": "res://assets/models/kenney_mini_dungeon/Models/wall.fbx",
	"column": "res://assets/models/kenney_mini_dungeon/Models/column.fbx",
	"banner": "res://assets/models/kenney_mini_dungeon/Models/banner.fbx",
	"chest": "res://assets/models/kenney_mini_dungeon/Models/chest.fbx",
}
const DUNGEON_ENEMY_SCENE: PackedScene = preload("res://scenes/entities/hushling.tscn")
const DUNGEON_BOSS_SCENE: PackedScene = preload("res://scenes/entities/boss_bramblewood_thornwarden.tscn")

func setup(world_manager: Node3D) -> void:
	_world = world_manager
	_connect_signals()
	_sync_gates()

func toggle_dungeon() -> void:
	if _world == null:
		return
	var hero := _world.get_node_or_null("Hero") as Node3D
	if hero == null:
		return
	if in_dungeon:
		_exit_dungeon(hero)
	else:
		_enter_dungeon(hero)

func _enter_dungeon(hero: Node3D) -> void:
	if in_dungeon:
		return
	_surface_return_position = hero.global_position
	_build_dungeon_interior()
	_set_surface_world_visible(false)
	hero.global_position = DUNGEON_POSITION
	in_dungeon = true
	dungeon_state_changed.emit(true)

func _exit_dungeon(hero: Node3D) -> void:
	if not in_dungeon:
		return
	_set_surface_world_visible(true)
	hero.global_position = _surface_return_position
	in_dungeon = false
	if is_instance_valid(_dungeon_root):
		_dungeon_root.queue_free()
	_dungeon_root = null
	dungeon_state_changed.emit(false)

func _set_surface_world_visible(visible: bool) -> void:
	if _world == null:
		return
	for child in _world.get_children():
		if child == self or child.name == "Hero" or child.name == "CameraRig":
			continue
		if child is CanvasLayer:
			continue
		child.visible = visible

func _build_dungeon_interior() -> void:
	if is_instance_valid(_dungeon_root):
		return
	_dungeon_root = Node3D.new()
	_dungeon_root.name = "EmbervaultInterior"
	_dungeon_root.set_meta("stream_owned", true)
	_dungeon_root.set_meta("dungeon_id", "embervault")
	add_child(_dungeon_root)
	_add_dungeon_module("floor", DUNGEON_POSITION + Vector3(0.0, -0.2, 0.0), Vector3(13.0, 1.0, 9.0))
	for index in 12:
		var side := -1.0 if index < 6 else 1.0
		var column := index % 6
		_add_dungeon_module("wall", DUNGEON_POSITION + Vector3((column - 2.5) * 4.0, 0.0, side * 8.5),
			Vector3(1.0, 1.0, 1.0), side < 0.0)
	for index in 4:
		var side := -1.0 if index % 2 == 0 else 1.0
		var x := -8.0 if index < 2 else 8.0
		_add_dungeon_module("column", DUNGEON_POSITION + Vector3(x, 0.0, side * 6.5), Vector3.ONE)
	_add_dungeon_module("banner", DUNGEON_POSITION + Vector3(0.0, 1.8, -8.0), Vector3.ONE)
	_add_dungeon_module("chest", DUNGEON_POSITION + Vector3(0.0, 0.1, 5.0), Vector3.ONE)
	_add_dungeon_collision()
	_add_dungeon_navigation()
	_add_dungeon_lighting()
	_add_dungeon_exit()
	_add_dungeon_encounter()
	var label := Label3D.new()
	label.text = "EMBERVAULT · DESCEND"
	label.font_size = 32
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = DUNGEON_POSITION + Vector3(0.0, 3.5, -7.5)
	_dungeon_root.add_child(label)

func _add_dungeon_module(module_id: String, location: Vector3, scale: Vector3,
		face_inward := false) -> void:
	var path := str(DUNGEON_MODULES.get(module_id, ""))
	var packed := load(path) as PackedScene if not path.is_empty() else null
	var instance := packed.instantiate() if packed != null else null
	if instance == null:
		var fallback := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(2.0, 1.0, 1.0)
		fallback.mesh = mesh
		instance = fallback
	instance.set_meta("asset_fallback", packed == null)
	_dungeon_root.add_child(instance)
	instance.position = location
	instance.scale = scale
	if face_inward:
		instance.rotation.y = PI

func _add_dungeon_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "InteriorCollision"
	_dungeon_root.add_child(body)
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(26.0, 0.35, 18.0)
	floor_shape.shape = floor_box
	floor_shape.position = DUNGEON_POSITION + Vector3(0.0, -0.2, 0.0)
	body.add_child(floor_shape)
	for side in [-1.0, 1.0]:
		var wall_shape := CollisionShape3D.new()
		var wall_box := BoxShape3D.new()
		wall_box.size = Vector3(26.0, 3.0, 0.7)
		wall_shape.shape = wall_box
		wall_shape.position = DUNGEON_POSITION + Vector3(0.0, 1.5, side * 8.5)
		body.add_child(wall_shape)

func _add_dungeon_navigation() -> void:
	var region := NavigationRegion3D.new()
	region.name = "InteriorNavigation"
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.vertices = PackedVector3Array([
		DUNGEON_POSITION + Vector3(-12.0, 0.0, -8.0),
		DUNGEON_POSITION + Vector3(12.0, 0.0, -8.0),
		DUNGEON_POSITION + Vector3(12.0, 0.0, 8.0),
		DUNGEON_POSITION + Vector3(-12.0, 0.0, 8.0),
	])
	navigation_mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = navigation_mesh
	_dungeon_root.add_child(region)

func _add_dungeon_lighting() -> void:
	var key := OmniLight3D.new()
	key.name = "EmbervaultKeyLight"
	key.position = DUNGEON_POSITION + Vector3(0.0, 3.0, 0.0)
	key.light_color = Color(1.0, 0.48, 0.20)
	key.light_energy = 1.8
	key.omni_range = 14.0
	key.shadow_enabled = true
	_dungeon_root.add_child(key)
	for index in 2:
		var fill := OmniLight3D.new()
		fill.name = "EmbervaultFill_%d" % index
		fill.position = DUNGEON_POSITION + Vector3(-8.0 + index * 16.0, 2.2, 0.0)
		fill.light_color = Color(0.28, 0.48, 0.62)
		fill.light_energy = 0.55
		fill.omni_range = 9.0
		_dungeon_root.add_child(fill)

func _add_dungeon_exit() -> void:
	var exit := preload("res://scripts/world/interaction_prop.gd").new()
	exit.name = "DungeonExit"
	exit.position = DUNGEON_POSITION + Vector3(0.0, 0.0, -7.0)
	exit.configure(self, "dungeon_exit", "embervault_exit", "ASCEND")
	_dungeon_root.add_child(exit)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 1.5
	capsule.height = 2.2
	shape.shape = capsule
	shape.position = Vector3(0.0, 1.1, 0.0)
	exit.add_child(shape)
	var label := Label3D.new()
	label.text = "ASCEND"
	label.font_size = 36
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.4, 0.0)
	label.modulate = Color(1.0, 0.82, 0.46)
	exit.add_child(label)

func _add_dungeon_encounter() -> void:
	var encounter := Node3D.new()
	encounter.name = "RootCavernEncounter"
	encounter.set_meta("encounter_role", "dungeon_guardians")
	_dungeon_root.add_child(encounter)
	for index in 2:
		var enemy := DUNGEON_ENEMY_SCENE.instantiate() as Node3D
		if enemy == null:
			continue
		enemy.name = "EmbervaultGuardian_%d" % index
		enemy.position = DUNGEON_POSITION + Vector3(-4.5 + index * 9.0, 0.0, 1.5)
		if enemy.has_method("configure_archetype"):
			enemy.call("configure_archetype", "charger" if index == 0 else "thorn_charger")
		encounter.add_child(enemy)
	var reward := Marker3D.new()
	reward.name = "BossRewardAnchor"
	reward.position = DUNGEON_POSITION + Vector3(0.0, 0.2, 6.0)
	reward.set_meta("reward_owner", "RewardManager")
	encounter.add_child(reward)
	var boss_room := Node3D.new()
	boss_room.name = "EmbervaultBossRoom"
	boss_room.set_meta("boss_id", "bramblewood_thornwarden")
	_dungeon_root.add_child(boss_room)
	var boss := DUNGEON_BOSS_SCENE.instantiate() as Node3D
	if boss != null:
		boss.name = "EmbervaultThornWarden"
		boss.position = DUNGEON_POSITION + Vector3(0.0, 0.2, -2.5)
		boss_room.add_child(boss)
		if boss.has_signal("died"):
			boss.died.connect(_on_dungeon_boss_died)

func _on_dungeon_boss_died() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var claims: Dictionary = gs.get("quest_reward_claims") \
		if gs.get("quest_reward_claims") is Dictionary else {}
	if bool(claims.get("dungeon_embervault_complete", false)):
		return
	claims["dungeon_embervault_complete"] = true
	gs.set("quest_reward_claims", claims)
	if gs.has_method("record_activity"):
		gs.call("record_activity", "DUNGEON COMPLETE · EMBERVAULT")
	if gs.has_method("save_game"):
		gs.call("save_game")
	dungeon_completed.emit("embervault")

func _dungeon_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material

func _ready() -> void:
	pass  # setup() is called explicitly by world_manager

# ─────────────────────────────────────────────────────────────────────────────
# Gate management
# ─────────────────────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	if gs.has_signal("stage_changed"):
		gs.stage_changed.connect(_on_stage_changed)
	if gs.has_signal("victory"):
		gs.victory.connect(_on_victory)
	if gs.has_signal("realm_changed"):
		gs.realm_changed.connect(_on_realm_changed)

func _sync_gates() -> void:
	if _world == null:
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var stage := int(gs.get("current_stage") if gs.get("current_stage") != null else 0)
	# MoonfenGate opens after COMPLETE (stage 3)
	_set_gate_visible("MoonfenGate",  stage >= 3)
	_set_gate_visible("ReturnGate",   stage >= 1)

func _set_gate_visible(gate_name: String, visible: bool) -> void:
	if _world == null:
		return
	var gate := _world.get_node_or_null(gate_name)
	if gate != null:
		gate.visible = visible
		# Enable/disable collision too
		for child in gate.get_children():
			if child is CollisionShape3D or child is CollisionPolygon3D:
				child.disabled = not visible

func _on_stage_changed(stage: int) -> void:
	_sync_gates()
	if stage >= 3:
		# Spawn a practice altar near the last boss spawn area
		_try_place_practice_altar()

func _on_victory() -> void:
	# Flash the MoonfenGate portal open if stage just completed
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var stage := int(gs.get("current_stage") if gs.get("current_stage") != null else 0)
	if stage >= 3:
		_open_gate_fx("MoonfenGate")

func _on_realm_changed(realm_id: String) -> void:
	# Show ReturnGate in new realm if we came from somewhere
	_set_gate_visible("ReturnGate", true)

# ─────────────────────────────────────────────────────────────────────────────
# Practice altar
# ─────────────────────────────────────────────────────────────────────────────

func _try_place_practice_altar() -> void:
	if _world == null:
		return
	if _world.get("_practice_altar") != null and \
			is_instance_valid(_world.get("_practice_altar")):
		return  # already placed

	# Simple procedural altar: a stone plinth
	var altar := Node3D.new()
	altar.name = "PracticeAltar"
	var plinth := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.55, 0.8)
	plinth.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.18, 0.16)
	mat.roughness    = 0.88
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.18, 0.06)
	mat.emission_energy_multiplier = 0.35
	plinth.material_override = mat
	altar.add_child(plinth)

	# Altar label
	var label := Label3D.new()
	label.text     = "PRACTICE ARENA"
	label.font_size = 48
	label.modulate  = Color(1.0, 0.85, 0.45)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position  = Vector3(0, 0.55, 0)
	altar.add_child(label)

	# Place near hero spawn + offset
	var spawn : Marker3D = _world.get_node_or_null("PlayerSpawn")
	altar.global_position = (spawn.global_position if spawn != null else Vector3.ZERO) \
		+ Vector3(4.0, 0, 0)
	_world.add_child(altar)
	if _world.get("_practice_altar") != null:
		_world.set("_practice_altar", altar)
	altar_placed.emit(altar)

# ─────────────────────────────────────────────────────────────────────────────
# Gate FX
# ─────────────────────────────────────────────────────────────────────────────

func _open_gate_fx(gate_name: String) -> void:
	if _world == null:
		return
	var gate := _world.get_node_or_null(gate_name)
	if gate == null:
		return
	gate.visible = true
	# Spawn portal burst
	CombatFx.spawn_ring(_world, gate.global_position, 1.8,
		Color(0.42, 0.72, 0.50, 0.8), 0.85)
	CombatFx.spawn_burst(_world, gate.global_position + Vector3(0, 1.2, 0),
		Color(0.32, 1.0, 0.55, 0.9), 18, 4.5, 0.55, 0.16)
	gate_opened.emit(gate_name.to_lower().replace("gate", ""))
