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
##   - Gate visibility tracks quest stage (hub travel back is the built gates)
##   - Handle gate interaction → GameState.realm_changed signal
##   - Altar placement for boss practice respawns
##   - Relic trophy pedestal update after forge

signal gate_opened(target_realm: String)
signal gate_closed
signal altar_placed(altar: Node3D)
signal dungeon_state_changed(interior_active: bool)
signal dungeon_completed(dungeon_id: String)
## Emitted when any enterable structure is entered or left, so the HUD can name
## the place the player is standing in rather than a single hard-coded dungeon.
signal structure_state_changed(structure_id: String, interior_active: bool)
signal structure_completed(structure_id: String)

const STRUCTURE_CATALOG := preload("res://scripts/world/structure_catalog.gd")
const ENTERABLE_STRUCTURE := preload("res://scripts/world/enterable_structure.gd")
const STRUCTURE_INTERIOR := preload("res://scripts/world/structure_interior.gd")

var _world : Node3D = null
var in_dungeon := false
var _dungeon_root: Node3D = null
var _surface_return_position := Vector3.ZERO
## Exteriors standing on the current realm surface, keyed by structure id.
var _structures: Dictionary = {}
## The structure the player is inside, empty when on the surface.
var active_structure_id := ""
## Realm environment parked while the player is inside a structure, so the
## interior's own lighting profile is what the player sees.
var _environment_node: WorldEnvironment = null
var _saved_environment: Environment = null
var _environment_parked := false
## Surface collision parked while the player is inside a structure. The realm's
## ground is a full-map collision box whose top sits at y=0; hiding the mesh
## leaves it solid, so without this the hero walks on that plane through lower
## rooms and stair flights instead of climbing them. The camera's spring arm
## also keeps colliding with surface geometry. Keyed by body -> Vector2i(layer,
## mask) so the exact original values are restored on exit.
var _parked_collision: Dictionary = {}
## Dynamic surface bodies are frozen while parked: with the ground parked they
## would otherwise fall through the world and their AI would keep hunting a
## hero it cannot reach. Keyed by body -> Vector2i(process_mode, frozen).
var _parked_process: Dictionary = {}

const DUNGEON_POSITION := Vector3(80.0, 0.3, 6.0)
const DUNGEON_MODULES: Dictionary = {
	"floor": "res://assets/models/kenney_mini_dungeon/Models/floor.fbx",
	"wall": "res://assets/models/kenney_mini_dungeon/Models/wall.fbx",
	"column": "res://assets/models/kenney_mini_dungeon/Models/column.fbx",
	"banner": "res://assets/models/kenney_mini_dungeon/Models/banner.fbx",
	"chest": "res://assets/models/kenney_mini_dungeon/Models/chest.fbx",
}
const DUNGEON_ENEMY_SCENE: PackedScene = preload("res://scenes/entities/hushling.tscn")
const DUNGEON_BOSS_SCENE: PackedScene = preload("res://scenes/entities/boss_articulated.tscn")

func setup(world_manager: Node3D) -> void:
	_world = world_manager
	_connect_signals()
	_sync_gates()
	_place_structures()

## Builds the exteriors for whichever realm is current. Structures are placed on
## the realm surface, each with full collision and its own door, so the map has
## places to walk into rather than only scenery to walk past.
func _place_structures(realm_id: String = "") -> void:
	if _world == null or not is_instance_valid(_world):
		return
	for structure in _structures.values():
		if is_instance_valid(structure):
			# Detach before freeing: queue_free is deferred, so a same-frame
			# rebuild would otherwise collide on the node name and leave the
			# replacement auto-renamed (Structure_x2), which breaks lookups.
			_world.remove_child(structure)
			structure.queue_free()
	_structures.clear()
	# Sweep untracked leftovers too: a node removed or freed outside this
	# system keeps holding its canonical name until the frame ends, and a
	# rebuild inside that window would be renamed on add. The sweep is not
	# realm-scoped because every placement rebuilds the whole surface set.
	for child in _world.get_children():
		if child is Node3D and str(child.name).begins_with("Structure_"):
			_world.remove_child(child)
			child.queue_free()
	var target_realm := realm_id
	if target_realm.is_empty():
		var gs := get_node_or_null("/root/GameState")
		target_realm = str(gs.get("current_realm") if gs != null else "")
	for entry in STRUCTURE_CATALOG.for_realm(target_realm):
		# The Embervault keeps its authored castle landmark and interior.
		if str(entry.get("builder", "generated")) == "authored":
			continue
		var id := str(entry.get("id", ""))
		var structure := ENTERABLE_STRUCTURE.new()
		# Name before add: the node is born canonical, and a forced readable
		# name turns any missed collision into a findable Structure_x2 rather
		# than an anonymous @EnterableStructure@2.
		structure.name = "Structure_%s" % id
		var approach: Vector3 = entry.get("approach", Vector3.ZERO)
		var ground := 0.0
		var terrain := _terrain_node()
		if terrain != null and terrain.has_method("sample_surface_height"):
			ground = float(terrain.call("sample_surface_height", approach))
		_world.add_child(structure, true)
		structure.setup(self, entry, ground)
		_structures[id] = structure

func _terrain_node() -> Node:
	if _world == null:
		return null
	for candidate in ["Terrain", "Ground", "TerrainRelief"]:
		var node := _world.get_node_or_null(candidate)
		if node != null:
			return node
	return null

## Enterable-structure entry point. `toggle_dungeon` remains the Embervault's
## public contract; every other structure routes through here.
func toggle_structure(structure_id: String) -> void:
	if _world == null:
		return
	var hero := _world.get_node_or_null("Hero") as Node3D
	if hero == null:
		return
	if not active_structure_id.is_empty():
		_exit_structure(hero)
		return
	_enter_structure(hero, structure_id)

func _enter_structure(hero: Node3D, structure_id: String) -> void:
	if not active_structure_id.is_empty():
		return
	if structure_id == "embervault" or str(STRUCTURE_CATALOG.get_structure(structure_id)
			.get("builder", "")) == "authored":
		active_structure_id = structure_id
		_enter_dungeon(hero)
		structure_state_changed.emit(structure_id, true)
		return
	var entry := STRUCTURE_CATALOG.get_structure(structure_id)
	if entry.is_empty():
		return
	_surface_return_position = hero.global_position
	var interior := STRUCTURE_INTERIOR.new()
	interior.setup(self, entry)
	interior.completed.connect(_on_structure_completed)
	add_child(interior)
	var spawn: Vector3 = interior.build()
	# Interiors are built at their own origin, so the player is moved into it
	# rather than the interior being moved under the realm's terrain.
	_dungeon_root = interior
	_set_surface_world_visible(false)
	hero.global_position = spawn
	active_structure_id = structure_id
	in_dungeon = true
	structure_state_changed.emit(structure_id, true)
	dungeon_state_changed.emit(true)

func _exit_structure(hero: Node3D) -> void:
	if active_structure_id.is_empty():
		return
	var structure_id := active_structure_id
	active_structure_id = ""
	if structure_id == "embervault":
		_exit_dungeon(hero)
		structure_state_changed.emit(structure_id, false)
		return
	_set_surface_world_visible(true)
	hero.global_position = _surface_return_position
	in_dungeon = false
	_free_interior()
	structure_state_changed.emit(structure_id, false)
	dungeon_state_changed.emit(false)

func _on_structure_completed(structure_id: String) -> void:
	structure_completed.emit(structure_id)
	dungeon_completed.emit(structure_id)

func toggle_dungeon() -> void:
	# The Embervault's original contract, now one structure among several.
	toggle_structure("embervault")

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
	_free_interior()
	dungeon_state_changed.emit(false)

## Detaches the active interior before freeing it: a same-frame re-entry would
## otherwise collide on Interior_<id> and leave the replacement auto-renamed.
func _free_interior() -> void:
	if not is_instance_valid(_dungeon_root):
		_dungeon_root = null
		return
	var interior := _dungeon_root
	_dungeon_root = null
	if interior.get_parent() == self:
		remove_child(interior)
	interior.queue_free()

func _set_surface_world_visible(visible: bool) -> void:
	if _world == null:
		return
	for child in _world.get_children():
		if child == self or child.name == "Hero" or child.name == "CameraRig":
			continue
		if child is CanvasLayer:
			continue
		# WorldEnvironment is a plain Node with no `visible`, so hiding the
		# surface used to throw here. Its sky and fog would also wash out the
		# interior's own lighting, so the environment is parked while inside and
		# restored on the way out.
		if child is WorldEnvironment:
			var env_node := child as WorldEnvironment
			if not visible:
				if not _environment_parked:
					_environment_node = env_node
					_saved_environment = env_node.environment
					_environment_parked = true
				env_node.environment = null
			elif _environment_node == env_node and _environment_parked:
				env_node.environment = _saved_environment
				_environment_parked = false
			continue
		if child is Node3D:
			child.visible = visible
	# Surface physics travels with surface visibility: an interior must be the
	# only thing the hero, enemies and the camera can touch while inside.
	_park_surface_collision(not visible)

## Disables (or restores) collision on every surface body, recursively, except
## the hero and camera rig. Only world geometry and trigger areas park:
## dynamic bodies (enemies, physics props) keep their own collision so they do
## not fall through the world while the player is inside, and their attack/hit
## areas park with the rest, so a hidden fight cannot reach the interior.
func _park_surface_collision(disable: bool) -> void:
	if _world == null:
		return
	for child in _world.get_children():
		if child == self or child.name == "Hero" or child.name == "CameraRig":
			continue
		if child is CanvasLayer:
			continue
		_park_collision_tree(child, disable)
	for body in _parked_collision.keys():
		if not is_instance_valid(body):
			_parked_collision.erase(body)
	for body in _parked_process.keys():
		if not is_instance_valid(body):
			_parked_process.erase(body)

func _park_collision_tree(node: Node, disable: bool) -> void:
	var body := node as CollisionObject3D
	if body != null:
		# World geometry and triggers park their collision; dynamic bodies keep
		# theirs but stop simulating so they neither fall nor chase.
		if body is StaticBody3D or body is Area3D:
			if disable:
				if not _parked_collision.has(body):
					_parked_collision[body] = Vector2i(body.collision_layer, body.collision_mask)
				body.collision_layer = 0
				body.collision_mask = 0
			elif _parked_collision.has(body):
				var saved: Vector2i = _parked_collision[body]
				body.collision_layer = saved.x
				body.collision_mask = saved.y
				_parked_collision.erase(body)
		elif body is CharacterBody3D or body is RigidBody3D:
			if disable:
				if not _parked_process.has(body):
					var frozen := 1 if body is RigidBody3D and (body as RigidBody3D).freeze else 0
					_parked_process[body] = Vector2i(body.process_mode, frozen)
					body.process_mode = Node.PROCESS_MODE_DISABLED
					if body is RigidBody3D:
						(body as RigidBody3D).freeze = true
			elif _parked_process.has(body):
				var saved: Vector2i = _parked_process[body]
				body.process_mode = saved.x as Node.ProcessMode
				if body is RigidBody3D:
					(body as RigidBody3D).freeze = saved.y != 0
				_parked_process.erase(body)
	for child in node.get_children():
		_park_collision_tree(child, disable)

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
	# Player + environment layers so the third-person spring arm collides with
	# the authored interior the same way it does with generated structures.
	body.collision_layer = (1 << 0) | (1 << 5)
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
		if "def_id" in boss:
			boss.set("def_id", "bramblewood_thorn_regent")
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

func _set_gate_visible(gate_name: String, visible: bool) -> void:
	if _world == null or not is_instance_valid(_world):
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

func _on_realm_changed(_realm_id: String) -> void:
	# Realm-to-realm travel is owned by the biome manager's built travel gates,
	# which already expose the hub as a destination in every realm. Only the
	# grove's stage-gated hub portal needs re-syncing when the realm changes,
	# and the structures standing on the new realm's surface are rebuilt.
	_sync_gates()
	_place_structures(_realm_id)

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
	if _world == null or not is_instance_valid(_world):
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
