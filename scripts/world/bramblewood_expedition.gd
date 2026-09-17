extends Node3D
class_name BramblewoodExpedition

## Authored Bramblewood expansion. Terrain, broad foliage, and quality-tier
## presentation remain owned by the existing world systems; this node owns
## only the bounded route pockets, their interaction state, and the new finale.

const LAYOUT := preload("res://scripts/world/realm_layout_data.gd")
const LANDMARK := preload("res://scripts/world/landmark.gd")
const GATHERING_NODE := preload("res://scripts/world/gathering_node.gd")
const CHEST_NODE := preload("res://scripts/entities/chest_node.gd")
const ENCOUNTER_ZONE := preload("res://scripts/entities/encounter_zone.gd")
const BOSS_DIRECTOR_SCRIPT := preload("res://scripts/systems/boss_encounter_director.gd")
const BARK_SHADER: Shader = preload("res://assets/shaders/bark.gdshader")
const CANOPY_SHADER: Shader = preload("res://assets/shaders/canopy.gdshader")
const ROCK_SHADER: Shader = preload("res://assets/shaders/rock.gdshader")
const BARK_ALBEDO: Texture2D = preload("res://assets/textures/stylized/bark/albedo.png")
const BARK_NORMAL: Texture2D = preload("res://assets/textures/stylized/bark/normal.png")
const BARK_ROUGHNESS: Texture2D = preload("res://assets/textures/stylized/bark/roughness.png")
const ROCK_ALBEDO: Texture2D = preload("res://assets/textures/stylized/rock/albedo.png")
const ROCK_NORMAL: Texture2D = preload("res://assets/textures/stylized/rock/normal.png")
const ROCK_ROUGHNESS: Texture2D = preload("res://assets/textures/stylized/rock/roughness.png")

const REALM_ID := "bramblewood"
const BOSS_ID := "rootbound_warden"
const BOSS_KEY := "biome_rootbound_warden"
const ACTIVE_BOSS_ID := "bramblewood_thorn_regent"
const POCKET_RADIUS := 7.0

var _world: Node3D = null
var _hero: Node3D = null
var _terrain: Node = null
var _pockets: Array[Dictionary] = []
var _pocket_nodes: Dictionary = {}
var _pocket_labels: Dictionary = {}
var _arena: Node3D = null
var _boss: Node3D = null
var _built := false
var _checkpoint_index := -1
var _boss_director: BossEncounterDirector = null

func setup(world: Node3D) -> void:
	_world = world
	_hero = world.get_node_or_null("Hero") as Node3D
	_terrain = world.get_node_or_null("Terrain")
	_boss_director = BOSS_DIRECTOR_SCRIPT.new()
	_boss_director.setup(world)
	if is_inside_tree():
		call_deferred("_build_route")

func _ready() -> void:
	if _world == null:
		_world = get_parent() as Node3D
	if _world != null:
		_hero = _world.get_node_or_null("Hero") as Node3D
		_terrain = _world.get_node_or_null("Terrain")
		if _boss_director == null:
			_boss_director = BOSS_DIRECTOR_SCRIPT.new()
			_boss_director.setup(_world)
	call_deferred("_build_route")

func _process(_delta: float) -> void:
	if not _built:
		if _is_accessible():
			_build_route()
		return
	if _hero == null or not is_instance_valid(_hero):
		return
	var hero_xz := Vector2(_hero.global_position.x, _hero.global_position.z)
	for pocket in _pockets:
		var pocket_id := str(pocket.get("id", ""))
		var node := _pocket_nodes.get(pocket_id) as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var distance := hero_xz.distance_to(Vector2(node.global_position.x, node.global_position.z))
		var label := _pocket_labels.get(pocket_id) as Label3D
		if label != null and is_instance_valid(label):
			label.visible = distance <= 13.0
		if distance <= POCKET_RADIUS:
			_mark_pocket_reached(pocket)
			if pocket_id == "rootbound_court" and _arena != null \
					and _arena.visible and distance <= 3.2:
				_engage_boss()

func _is_accessible() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return false
	return bool(gs.get("onboarding_completed")) \
		or int(gs.get("current_stage")) >= int(gs.QuestStage.COMPLETE)

func _build_route() -> void:
	if _built or _world == null or not _is_accessible():
		return
	var pocket_values: Variant = LAYOUT.profile(REALM_ID).get("expansion_pockets", [])
	_pockets.clear()
	if pocket_values is Array:
		for pocket_value in pocket_values:
			if pocket_value is Dictionary:
				_pockets.append(pocket_value)
	if _pockets.is_empty():
		return
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		var saved_checkpoint := str(gs.get("route_checkpoint_id"))
		_checkpoint_index = _checkpoint_index_for(saved_checkpoint)
	if gs != null and gs.has_method("begin_bramblewood_expansion"):
		gs.call("begin_bramblewood_expansion")
	for pocket in _pockets:
		_build_pocket(pocket)
	_built = true
	if gs != null and gs.has_signal("defeated"):
		gs.defeated.connect(_on_player_defeated)
	_refresh_post_clear_state()

func _build_pocket(pocket: Dictionary) -> void:
	var pocket_id := str(pocket.get("id", ""))
	if pocket_id.is_empty():
		return
	var pocket_root := Node3D.new()
	pocket_root.name = "ExpansionPocket_%s" % pocket_id
	pocket_root.add_to_group("route_marker")
	pocket_root.add_to_group("structure")
	pocket_root.set_meta("pocket_id", pocket_id)
	_world.add_child(pocket_root)
	pocket_root.global_position = _position_for(pocket)
	_conform(pocket_root, 0.04)
	_pocket_nodes[pocket_id] = pocket_root

	var label := Label3D.new()
	label.name = "PocketLabel"
	label.text = _pocket_title(pocket)
	label.font_size = 26
	label.outline_size = 7
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.91, 0.83, 0.57)
	label.position = Vector3(0.0, 2.8, 0.0)
	label.visible = false
	pocket_root.add_child(label)
	_pocket_labels[pocket_id] = label

	match str(pocket.get("role", "")):
		"landmark":
			_build_split_road_oak(pocket_root, pocket)
		"gathering":
			_build_rootcut_gully(pocket_root, pocket)
		"discovery":
			_build_hollow_camp(pocket_root, pocket)
		"elite_encounter":
			_build_beacon_breach(pocket_root, pocket)
		"boss":
			_build_rootbound_court(pocket_root, pocket)
	_add_root_cluster(pocket_root, 8, 3.8, 0.25)

func _position_for(pocket: Dictionary) -> Vector3:
	var position_value: Variant = pocket.get("position", Vector3.ZERO)
	if position_value is Vector3:
		return position_value
	return Vector3.ZERO

func _conform(node: Node3D, offset: float = 0.0) -> void:
	if _terrain != null and _terrain.has_method("conform_anchor"):
		_terrain.call("conform_anchor", node, offset)

func _mark_pocket_reached(pocket: Dictionary) -> void:
	var pocket_id := str(pocket.get("id", ""))
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	if gs.has_method("discover_bramblewood_pocket"):
		gs.call("discover_bramblewood_pocket", pocket_id)
	var index := _pockets.find(pocket)
	if index <= _checkpoint_index:
		return
	_checkpoint_index = index
	var checkpoint_id := str(pocket.get("checkpoint_id", pocket_id))
	if gs.has_method("set_route_checkpoint"):
		gs.call("set_route_checkpoint", checkpoint_id)
	if _world != null and _world.has_method("route_feedback"):
		_world.call("route_feedback", str(pocket.get("reveal_label", "Route milestone reached.")),
			"bramblewood_pocket_%s" % pocket_id)

func _checkpoint_index_for(checkpoint_id: String) -> int:
	if checkpoint_id == "rootway_shortcut":
		return _pockets.size()
	for i in _pockets.size():
		if str(_pockets[i].get("checkpoint_id", "")) == checkpoint_id:
			return i
	return -1

func _build_split_road_oak(parent: Node3D, pocket: Dictionary) -> void:
	var landmark := LANDMARK.new()
	landmark.name = "Landmark_%s" % str(pocket.get("landmark_id", "split_road_oak"))
	landmark.configure(str(pocket.get("landmark_id", "bramblewood_split_road_oak")),
		str(pocket.get("display_name", "SPLIT-ROAD OAK")), "materials", REALM_ID)
	parent.add_child(landmark)
	landmark.position = Vector3(0.0, 0.0, 0.0)

	var bark := _bark_material(Color(0.13, 0.075, 0.035))
	var trunk := _mesh(parent, _cylinder(0.72, 7.0, 10), bark,
		Vector3(0.0, 3.5, 0.0), Vector3(1.0, 1.0, 1.0))
	trunk.rotation.z = -0.07
	for side in [-1.0, 1.0]:
		var limb := _mesh(parent, _cylinder(0.26, 4.4, 8), bark,
			Vector3(0.85 * side, 5.5, 0.0), Vector3.ONE)
		limb.rotation = Vector3(0.0, 0.0, 0.72 * side)
	var canopy_mat := _canopy_material(Color(0.055, 0.15, 0.075))
	for point in [Vector3(-1.5, 6.8, 0.0), Vector3(1.4, 6.7, 0.3), Vector3(0.0, 7.6, -0.4)]:
		_mesh(parent, _sphere(2.0, 10, 6), canopy_mat, point, Vector3(1.3, 0.85, 1.15))
	_add_beacon(parent, Vector3(0.0, 0.25, 2.7), Color(1.0, 0.54, 0.18))

func _build_rootcut_gully(parent: Node3D, _pocket: Dictionary) -> void:
	var root_mat := _bark_material(Color(0.19, 0.09, 0.045))
	for side in [-1.0, 1.0]:
		var arch := _mesh(parent, _cylinder(0.30, 4.4, 7), root_mat,
			Vector3(3.0 * side, 2.2, 0.0), Vector3.ONE)
		arch.rotation = Vector3(0.0, 0.0, -0.32 * side)
	var cross := _mesh(parent, _cylinder(0.34, 6.2, 7), root_mat,
		Vector3(0.0, 4.9, 0.0), Vector3.ONE)
	cross.rotation = Vector3(0.0, 0.0, PI * 0.5)
	_add_gathering_node(parent, "rootcut_bramble_wood", "bramble_wood", 3, Vector3(-2.5, 0.0, 2.0))
	_add_gathering_node(parent, "rootcut_iron_shard", "iron_shard", 3, Vector3(2.4, 0.0, -1.3))
	_add_gathering_node(parent, "rootcut_beast_hide", "beast_hide", 2, Vector3(-1.0, 0.0, -2.8))

func _build_hollow_camp(parent: Node3D, pocket: Dictionary) -> void:
	var landmark := LANDMARK.new()
	landmark.name = "Landmark_%s" % str(pocket.get("landmark_id", "bramblewood_hollow_camp"))
	landmark.configure(str(pocket.get("landmark_id", "bramblewood_hollow_camp")),
		str(pocket.get("display_name", "HOLLOW FORESTER CAMP")), "heal", REALM_ID)
	parent.add_child(landmark)
	var wood := _bark_material(Color(0.20, 0.12, 0.07))
	var cloth := _material(Color(0.22, 0.28, 0.18), 0.94)
	# A low octagonal pad keeps the camp grounded without introducing a square
	# floating slab into the route view.
	var camp_pad := CylinderMesh.new()
	camp_pad.top_radius = 1.0
	camp_pad.bottom_radius = 1.03
	camp_pad.height = 0.16
	camp_pad.radial_segments = 10
	camp_pad.rings = 1
	_mesh(parent, camp_pad, wood, Vector3(0.0, 0.08, 0.4),
		Vector3(2.1, 1.0, 1.4))
	for side in [-1.0, 1.0]:
		_mesh(parent, _box(Vector3(0.12, 2.1, 2.4)), wood,
			Vector3(1.8 * side, 1.05, 0.4), Vector3.ONE)
	_mesh(parent, _box(Vector3(3.5, 0.10, 2.4)), cloth,
		Vector3(0.0, 2.0, 0.4), Vector3.ONE)
	var chest: ChestNode = CHEST_NODE.new()
	chest.name = "Chest_hollow_forester_cache"
	chest.chest_id = "bramblewood_hollow_forester_cache"
	chest.chest_tier = "rare"
	chest.realm_id = REALM_ID
	chest.respawn_time_sec = 0.0
	parent.add_child(chest)
	chest.position = Vector3(0.0, 0.0, -2.1)
	_conform(chest, 0.02)
	_add_beacon(parent, Vector3(0.0, 0.18, 2.2), Color(0.70, 0.90, 0.38))

func _build_beacon_breach(parent: Node3D, pocket: Dictionary) -> void:
	var zone: EncounterZone = ENCOUNTER_ZONE.new()
	zone.name = "Encounter_beacon_breach"
	zone.pocket_id = str(pocket.get("id", "beacon_breach"))
	zone.zone_radius = 6.2
	zone.approach_label = str(pocket.get("approach_label", "Approach"))
	zone.reveal_label = str(pocket.get("reveal_label", "Threat revealed"))
	zone.reward_label = str(pocket.get("reward_label", "Reward"))
	zone.exit_label = str(pocket.get("exit_label", "Exit"))
	var encounter_data: Dictionary = pocket.get("encounter", {}) \
		if pocket.get("encounter", {}) is Dictionary else {}
	zone.setup(REALM_ID, str(encounter_data.get("tier",
		pocket.get("encounter_tier", "elite"))), 0)
	parent.add_child(zone)
	zone.position = Vector3.ZERO
	zone.pack_cleared.connect(_on_beacon_breach_cleared)
	var beacon_mat := _bark_material(Color(0.10, 0.15, 0.09))
	for side in [-1.0, 1.0]:
		var broken := _mesh(parent, _cylinder(0.28, 3.0, 8), beacon_mat,
			Vector3(2.6 * side, 1.5, 0.0), Vector3.ONE)
		broken.rotation = Vector3(0.0, 0.0, 0.38 * side)
	_add_beacon(parent, Vector3(0.0, 0.22, 0.0), Color(1.0, 0.38, 0.10))

func _build_rootbound_court(parent: Node3D, pocket: Dictionary) -> void:
	_arena = Node3D.new()
	_arena.name = "RootboundCourtArena"
	_arena.add_to_group("event")
	parent.add_child(_arena)
	var stone_mat := _rock_material(Color(0.12, 0.12, 0.095))
	var ring := _mesh(_arena, _torus(8.8, 9.25, 48, 4), stone_mat,
		Vector3(0.0, 0.12, 0.0), Vector3.ONE)
	ring.rotation.x = PI * 0.5
	for i in 6:
		var angle := TAU * float(i) / 6.0
		var root := _mesh(_arena, _cylinder(0.32, 2.8, 7),
			_bark_material(Color(0.18, 0.08, 0.035)),
			Vector3(cos(angle) * 7.4, 1.4, sin(angle) * 7.4), Vector3.ONE)
		root.rotation = Vector3(sin(angle) * 0.22, 0.0, cos(angle) * 0.22)
	var altar := _mesh(_arena, _cylinder(1.1, 1.0, 10), stone_mat,
		Vector3.ZERO, Vector3.ONE)
	var altar_ring := _mesh(_arena, _torus(BOSS_DIRECTOR_SCRIPT.ARENA_MARKER_INNER_RADIUS,
		BOSS_DIRECTOR_SCRIPT.ARENA_MARKER_OUTER_RADIUS, 28, 3),
		_material(Color(0.72, 0.34, 0.08), 0.68), Vector3(0.0, 0.56, 0.0), Vector3.ONE)
	altar_ring.rotation.x = PI * 0.5
	var label := Label3D.new()
	label.name = "RootboundCourtTitle"
	label.text = "ROOTBOUND COURT"
	label.font_size = 34
	label.outline_size = 8
	label.modulate = Color(0.94, 0.60, 0.24)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 3.2, 0.0)
	label.visible = false
	_arena.add_child(label)
	_conform(_arena, 0.04)

func _add_gathering_node(parent: Node3D, node_name: String, material_id: String,
		yield_amount: int, offset: Vector3) -> void:
	var node: GatheringNode = GATHERING_NODE.new()
	node.name = "Gather_%s" % node_name
	node.configure(material_id, yield_amount, yield_amount, 1.15, 180.0, REALM_ID)
	parent.add_child(node)
	node.position = offset
	_conform(node, 0.04)

func _add_root_cluster(parent: Node3D, count: int, radius: float, height: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _cylinder(0.08, height, 5)
	mm.instance_count = count
	mm.custom_aabb = AABB(Vector3(-radius - 1.0, -1.0, -radius - 1.0),
		Vector3(radius * 2.0 + 2.0, height + 2.0, radius * 2.0 + 2.0))
	for i in count:
		var angle := TAU * float(i) / float(count)
		var position := Vector3(cos(angle) * radius, height * 0.5, sin(angle) * radius)
		var basis := Basis.from_euler(Vector3(0.0, angle, sin(angle) * 0.18))
		mm.set_instance_transform(i, Transform3D(basis, position))
	var roots := MultiMeshInstance3D.new()
	roots.name = "BrambleRootCluster"
	roots.multimesh = mm
	roots.material_override = _bark_material(Color(0.16, 0.07, 0.03))
	roots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	roots.visibility_range_end = 120.0
	parent.add_child(roots)

func _add_beacon(parent: Node3D, position: Vector3, color: Color) -> void:
	var orb := _mesh(parent, _sphere(0.22, 8, 5), _material(color, 0.42, color),
		position + Vector3.UP * 1.3, Vector3.ONE)
	orb.set_meta("transient_lifetime", 0.0)

func _mesh(parent: Node3D, mesh: Mesh, material: Material, position: Vector3,
		scale: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.scale = scale
	parent.add_child(instance)
	return instance

func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _cylinder(radius: float, height: float, segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.82
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	return mesh

func _sphere(radius: float, radial_segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	return mesh

func _torus(inner: float, outer: float, ring_segments: int, rings: int) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.ring_segments = ring_segments
	mesh.rings = rings
	return mesh

func _material(color: Color, roughness: float, emission: Color = Color.TRANSPARENT) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission.a > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 0.7
	return material

func _bark_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BARK_SHADER
	material.set_shader_parameter("bark_color", color)
	material.set_shader_parameter("bark_albedo_tex", BARK_ALBEDO)
	material.set_shader_parameter("bark_normal_tex", BARK_NORMAL)
	material.set_shader_parameter("bark_rough_tex", BARK_ROUGHNESS)
	material.set_shader_parameter("moon_rim_color", Color(0.28, 0.42, 0.24))
	material.set_shader_parameter("rim_intensity", 0.12)
	return material

func _canopy_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CANOPY_SHADER
	material.set_shader_parameter("canopy_color", color)
	material.set_shader_parameter("highlight_color", color.lightened(0.36))
	material.set_shader_parameter("wind_strength", 0.06)
	return material

func _rock_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ROCK_SHADER
	material.set_shader_parameter("rock_color", color)
	material.set_shader_parameter("moss_color", Color(0.10, 0.20, 0.09))
	material.set_shader_parameter("rock_albedo_tex", ROCK_ALBEDO)
	material.set_shader_parameter("rock_normal_tex", ROCK_NORMAL)
	material.set_shader_parameter("rock_rough_tex", ROCK_ROUGHNESS)
	return material

func _pocket_title(pocket: Dictionary) -> String:
	var display_name := str(pocket.get("display_name", ""))
	if not display_name.is_empty():
		return display_name
	return str(pocket.get("id", "ROUTE POCKET")).replace("_", " ").to_upper()

func _has_boss_clear() -> bool:
	var gs := get_node_or_null("/root/GameState")
	return gs != null and (bool(gs.call("has_boss_killed", BOSS_KEY)) \
		or bool(gs.get("bramblewood_expansion").get("completed", false)))

func _engage_boss() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	if _boss != null and is_instance_valid(_boss):
		return
	if _has_boss_clear():
		return
	if _arena == null or not is_instance_valid(_arena):
		return
	if _boss_director == null:
		return
	var player_position := _hero.global_position if _hero != null \
		and is_instance_valid(_hero) else _arena.global_position
	var boss_position := BOSS_DIRECTOR_SCRIPT.entry_position_for(
		_arena.global_position, player_position)
	boss_position.y += 0.1
	var boss := _boss_director.spawn_boss(ACTIVE_BOSS_ID, false, boss_position)
	if boss == null:
		return
	boss.name = "RootboundWarden"
	_conform(boss, 0.12)
	_boss = boss
	_arena.visible = false
	var camera := _world.get_node_or_null("CameraRig")
	if camera != null:
		camera.call("add_shake", 0.6)
		camera.call("play_boss_intro", boss)
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_enemy_telegraph"):
		audio.call("play_enemy_telegraph")
	var def := Bestiary.boss_def(ACTIVE_BOSS_ID)
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.quest_progress.emit(str(def.get("intro", "The court wakes.")))
	if boss.has_signal("died"):
		boss.died.connect(_on_boss_died)

func _on_boss_died() -> void:
	_boss = null
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("complete_bramblewood_expansion"):
		gs.call("complete_bramblewood_expansion")
	_refresh_post_clear_state()
	if _world != null and _world.has_method("refresh_route_markers"):
		_world.call("refresh_route_markers")

func _on_player_defeated() -> void:
	if _boss != null and is_instance_valid(_boss) and _boss.has_method("reset_encounter"):
		_boss.call("reset_encounter")
		if _arena != null and is_instance_valid(_arena):
			_arena.visible = false
		return
	if not _has_boss_clear() and _arena != null and is_instance_valid(_arena):
		_arena.visible = true

func _on_beacon_breach_cleared() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("record_activity"):
		gs.call("record_activity", "BEACON BREACH CLEARED")
	if _world != null and _world.has_method("route_feedback"):
		_world.call("route_feedback", "The broken beacon clears a line to the root court.",
			"bramblewood_beacon_breach_cleared")

func _refresh_post_clear_state() -> void:
	if not _has_boss_clear() or _arena == null or not is_instance_valid(_arena):
		return
	var pocket_root := _arena.get_parent() as Node3D
	if pocket_root == null:
		return
	_arena.visible = false
	if pocket_root.get_node_or_null("RootwayOpenMarker") != null:
		return
	var marker := Label3D.new()
	marker.name = "RootwayOpenMarker"
	marker.text = "ROOTWAY OPEN\nRETURN TO CAMP"
	marker.font_size = 24
	marker.outline_size = 7
	marker.modulate = Color(0.78, 1.0, 0.62)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.position = Vector3(0.0, 2.1, 0.0)
	pocket_root.add_child(marker)
