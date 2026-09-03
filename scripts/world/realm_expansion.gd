extends Node3D
class_name RealmExpansion

const PROP_SCRIPT = preload("res://scripts/world/interaction_prop.gd")
const ELEMENT_COLORS := {
    "fire": Color(1.0, 0.30, 0.10),
    "frost": Color(0.40, 0.84, 1.0),
    "shock": Color(0.76, 0.52, 1.0),
    "nature": Color(0.34, 1.0, 0.46),
}

var world: Node3D
var hero: Node3D
var dungeon_root: Node3D
var cave_entry: StaticBody3D
var cave_exit: StaticBody3D
var surface_return := Vector3.ZERO
var in_dungeon := false
var _opened_chests: Dictionary = {}
var _chests: Dictionary = {}
var _chest_specs: Dictionary = {}
var _dungeon_enemies: Array[Node3D] = []
var _surface_enemies: Array[Node3D] = []
var realm_id := "bramblewood"
var layout: Dictionary = {}

func setup(owner_world: Node3D) -> void:
    world = owner_world
    hero = owner_world.get_node_or_null("Hero")
    realm_id = RealmLayoutData.resolve_realm(owner_world)
    layout = RealmLayoutData.profile(realm_id)
    name = "RealmExpansion"
    _build_mountain_ridge()
    _build_route_markers()
    _build_route_resources()
    _build_authored_encounters()
    _build_checkpoint(layout.get("checkpoint", Vector3(3.0, 0.35, 3.5)))
    _build_surface_chests()
    _build_cave_and_dungeon()

func _process(_delta: float) -> void:
    # Cave façades and exits are architecture, not rotating portal props.
    pass

func open_checkpoint() -> void:
    var forge := get_tree().root.find_child("ForgeMenu", true, false)
    if forge != null:
        forge.visible = true
        var note := get_tree().root.find_child("FieldNote", true, false)
        if note is Label:
            note.text = "✦ Checkpoint forge ready — attune your relic."

func open_chest(chest: Node, chest_id: String) -> void:
    if _opened_chests.get(chest_id, false) or GameState.opened_chests.get(chest_id, false):
        return
    
    # Check if this is a boss-gated chest and the boss hasn't been defeated
    var chest_type := str(chest.get_meta("chest_type", "instant"))
    if chest_type == "boss_gated":
        var boss_key := str(chest.get_meta("boss_key", ""))
        if boss_key != "" and not GameState.has_boss_killed(boss_key):
            GameState.quest_progress.emit("This chest is sealed by the boss's power. Defeat %s to claim it." % boss_key)
            return
    
    _opened_chests[chest_id] = true
    GameState.opened_chests[chest_id] = true
    var sm := get_node_or_null("/root/StoryManager")
    if sm != null and sm.has_method("notify_objective"):
        sm.notify_objective("open_chest", chest_id, 1)
    var chest_rarity := _chest_rarity(chest_id)
    var result := LootTable.roll_chest(chest_rarity)
    var pos: Vector3 = chest.global_position if chest is Node3D else global_position
    var loot_drop := preload("res://scripts/systems/loot_drop.gd")
    if result.gold > 0:
        loot_drop.spawn_gold(self, pos + Vector3(0.0, 0.22, 0.0), result.gold)
    for mat in result.materials:
        GameState.add_material(mat.id, mat.qty)
        FloatingText.spawn_on_entity(self, "+%d %s" % [mat.qty, GameState.MATERIAL_DEFS.get(mat.id, {}).get("name", mat.id)],
            Color(0.52, 0.90, 1.0), 1.1)
    if result.gear != null:
        var gear: Dictionary = result.gear
        var item_id := "moss_tonic"
        loot_drop.spawn_item(self, pos + Vector3(0.32, 0.20, 0.0), item_id, 1, gear.rarity)
    var element: String = ["fire", "frost", "shock", "nature"][randi() % 4]
    CombatFx.spawn_chest_open(self, pos, ELEMENT_COLORS.get(element, Color.WHITE))
    var rarity_names := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
    GameState.quest_progress.emit("Chest opened — %s cache, %d gold." % [rarity_names[chest_rarity - 1], result.gold])
    if chest.has_method("mark_opened"):
        chest.mark_opened()

func toggle_dungeon() -> void:
    if hero == null or not is_instance_valid(hero):
        return
    in_dungeon = not in_dungeon
    if in_dungeon:
        surface_return = hero.global_position
        dungeon_root.visible = true
        cave_entry.visible = false
        _set_dungeon_enemies_active(true)
        hero.global_position = dungeon_root.global_position + Vector3(0, 0.3, 6.0)
        GameState.quest_progress.emit("The Embervault descends beneath the mountain.")
    else:
        hero.global_position = surface_return
        dungeon_root.visible = false
        cave_entry.visible = true
        _set_dungeon_enemies_active(false)
        GameState.quest_progress.emit("You return from the Embervault.")

func _build_mountain_ridge() -> void:
    # Hills are intentionally removed from the playable surface. Keep this
    # named empty container so checkpoint/chest/dungeon integrations and old
    # save/test references remain compatible.
    var ridge := Node3D.new()
    ridge.name = "MountainRidge"
    add_child(ridge)

func _mountain_material() -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = load("res://assets/shaders/mountain_rock.gdshader")
    material.set_shader_parameter("rock_tex", load("res://assets/textures/stylized/rock/albedo.png"))
    material.set_shader_parameter("rock_norm", load("res://assets/textures/stylized/rock/normal.png"))
    material.set_shader_parameter("rock_rough", load("res://assets/textures/stylized/rock/roughness.png"))
    material.set_shader_parameter("rock_tint", Color(0.38, 0.40, 0.43))
    material.set_shader_parameter("snow_tint", Color(0.76, 0.84, 0.92))
    material.set_shader_parameter("accent_tint", Color(0.26, 0.52, 0.76))
    material.set_shader_parameter("accent_strength", 0.18)
    return material

func _build_checkpoint(pos: Vector3) -> void:
    var checkpoint := PROP_SCRIPT.new()
    checkpoint.name = "CheckpointForge"
    checkpoint.position = pos
    checkpoint.collision_layer = 1 << 3
    checkpoint.configure(self, "checkpoint", "checkpoint_forge", "OPEN FORGE")
    add_child(checkpoint)
    var base := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.95
    cylinder.bottom_radius = 1.15
    cylinder.height = 0.35
    cylinder.radial_segments = 12
    base.mesh = cylinder
    base.material_override = _emissive_material(Color(1.0, 0.45, 0.12), 0.7)
    checkpoint.add_child(base)
    var flame := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 0.28
    sphere.height = 0.72
    flame.mesh = sphere
    flame.position = Vector3(0, 0.72, 0)
    flame.material_override = _emissive_material(Color(1.0, 0.75, 0.28), 1.8)
    checkpoint.add_child(flame)
    _add_collision(checkpoint, Vector3(1.9, 1.4, 1.9))
    _add_label(checkpoint, "CHECKPOINT · FORGE", Vector3(0, 1.45, 0.2), Color(1.0, 0.76, 0.32))

func _build_surface_chests() -> void:
    var glow := ELEMENT_COLORS.get(_realm_element(), Color(0.40, 0.82, 1.0)) as Color
    for spec_value in layout.get("chests", []):
        var spec := spec_value as Dictionary
        _make_chest(str(spec.id), spec.pos, str(spec.label), glow, spec)

func _make_chest(chest_id: String, pos: Vector3, label_text: String, glow: Color, spec: Dictionary = {}) -> void:
    var chest := PROP_SCRIPT.new()
    chest.name = "Chest_%s" % chest_id
    chest.position = Vector3(pos.x, _surface_height(pos.x, pos.z) + 0.12, pos.z)
    chest.collision_layer = 1 << 3
    chest.configure(self, "chest", chest_id, "OPEN CHEST")
    add_child(chest)
    var is_gated := str(spec.get("type", "instant")) == "boss_gated"
    if is_gated:
        chest.set_meta("chest_type", "boss_gated")
        chest.set_meta("boss_key", str(spec.get("boss_key", "")))
    _build_chest_staging(chest, glow)
    var body := MeshInstance3D.new()
    body.name = "ChestBody"
    var box := BoxMesh.new()
    box.size = Vector3(1.22, 0.56, 0.78)
    body.mesh = box
    body.material_override = _emissive_material(Color(0.20, 0.11, 0.06), 0.12)
    body.position.y = 0.34
    chest.add_child(body)
    var lid := MeshInstance3D.new()
    lid.name = "ChestLid"
    var lid_mesh := CylinderMesh.new()
    lid_mesh.top_radius = 0.39
    lid_mesh.bottom_radius = 0.39
    lid_mesh.height = 1.18
    lid_mesh.radial_segments = 8
    lid.mesh = lid_mesh
    lid.rotation.z = PI * 0.5
    lid.position.y = 0.70
    lid.scale = Vector3(1.0, 1.0, 0.55)
    lid.material_override = _stylized_surface_material("wood", Color(0.42, 0.24, 0.10))
    chest.add_child(lid)
    var band := MeshInstance3D.new()
    var band_mesh := BoxMesh.new()
    band_mesh.size = Vector3(1.32, 0.16, 0.88)
    band.mesh = band_mesh
    band.position = Vector3(0, 0.38, 0)
    band.material_override = _emissive_material(glow.lightened(0.2) if is_gated else glow, 0.7)
    chest.add_child(band)
    _add_collision(chest, Vector3(1.6, 1.25, 1.2))
    _add_label(chest, label_text, Vector3(0, 1.20, 0.18), Color(1.0, 0.6, 0.2) if is_gated else glow)
    _chests[chest_id] = chest

func _build_cave_and_dungeon() -> void:
    cave_entry = PROP_SCRIPT.new()
    cave_entry.name = "EmbervaultEntrance"
    var cave_pos := layout.get("cave", Vector3(19.0, 0.7, -16.0)) as Vector3
    cave_entry.position = Vector3(cave_pos.x,
        _surface_height(cave_pos.x, cave_pos.z), cave_pos.z)
    cave_entry.collision_layer = 1 << 3
    cave_entry.configure(self, "dungeon", "embervault", "ENTER CAVE")
    add_child(cave_entry)
    _build_cave_facade(cave_entry)
    _add_collision(cave_entry, Vector3(3.8, 3.5, 1.4))
    var dungeon_name := str(layout.get("dungeon_name", "EMBERVAULT"))
    _add_label(cave_entry, "CAVE · %s" % dungeon_name, Vector3(0, 4.0, 0.22), Color(0.48, 0.78, 1.0))

    dungeon_root = Node3D.new()
    dungeon_root.name = "EmbervaultDungeon"
    dungeon_root.position = Vector3(80, 0, 0)
    dungeon_root.visible = false
    add_child(dungeon_root)
    var floor := MeshInstance3D.new()
    var floor_mesh := BoxMesh.new()
    floor_mesh.size = Vector3(18, 0.4, 18)
    floor.mesh = floor_mesh
    floor.position = Vector3(0, -0.2, 0)
    floor.material_override = _mountain_material()
    dungeon_root.add_child(floor)
    _build_dungeon_wall_segments(dungeon_root)
    _add_label(dungeon_root, "%s · DEPTH 01" % dungeon_name, Vector3(0, 5.2, -8.4), Color(1.0, 0.62, 0.28))
    _build_dungeon_enemies()
    _make_chest_in_dungeon()
    cave_exit = PROP_SCRIPT.new()
    cave_exit.name = "EmbervaultExit"
    cave_exit.position = Vector3(0, 0.0, 7.5)
    cave_exit.collision_layer = 1 << 3
    cave_exit.configure(self, "dungeon", "embervault_exit", "EXIT CAVE")
    dungeon_root.add_child(cave_exit)
    _build_cave_facade(cave_exit, true)
    _add_collision(cave_exit, Vector3(3.0, 2.6, 1.2))
    _add_label(cave_exit, "EXIT · SURFACE", Vector3(0, 2.4, 0.2), Color(0.48, 0.78, 1.0))

func _surface_height(x: float, z: float) -> float:
    if world != null:
        var terrain := world.get_node_or_null("Terrain")
        if terrain != null and terrain.has_method("height_at"):
            return float(terrain.call("height_at", x, z))
    return 0.0

func _build_chest_staging(chest: Node3D, glow: Color) -> void:
    var stage := Node3D.new()
    stage.name = "GroundedLootStaging"
    chest.add_child(stage)
    var pad := MeshInstance3D.new()
    pad.name = "LootPad"
    var pad_mesh := CylinderMesh.new()
    pad_mesh.top_radius = 1.08
    pad_mesh.bottom_radius = 1.22
    pad_mesh.height = 0.12
    pad_mesh.radial_segments = 9
    pad.mesh = pad_mesh
    pad.position.y = -0.04
    pad.material_override = _stylized_surface_material(
        "clay" if realm_id in ["mistfen", "moonfen"] else "rock", glow.darkened(0.58))
    stage.add_child(pad)
    var rock_material := _stylized_surface_material("rock", glow.darkened(0.68))
    for i in 5:
        var pebble := MeshInstance3D.new()
        pebble.name = "AnchorStone_%d" % i
        var pebble_mesh := SphereMesh.new()
        pebble_mesh.radius = 0.20
        pebble_mesh.height = 0.25
        pebble_mesh.radial_segments = 6
        pebble_mesh.rings = 3
        pebble.mesh = pebble_mesh
        var angle := TAU * float(i) / 5.0 + 0.3
        pebble.position = Vector3(cos(angle) * 0.92, 0.03, sin(angle) * 0.68)
        pebble.scale = Vector3(1.0, 0.55, 0.75)
        pebble.rotation.y = angle
        pebble.material_override = rock_material
        stage.add_child(pebble)

func _build_cave_facade(parent: Node3D, is_exit := false) -> void:
    var facade := Node3D.new()
    facade.name = "GroundedCaveFacade"
    parent.add_child(facade)
    var rock_tint := {
        "whispergrove": Color(0.30, 0.42, 0.28),
        "bramblewood": Color(0.28, 0.24, 0.18),
        "mistfen": Color(0.28, 0.36, 0.39),
        "heartwood": Color(0.23, 0.14, 0.10),
        "moonfen": Color(0.24, 0.20, 0.36),
    }.get(realm_id, Color(0.30, 0.30, 0.28)) as Color
    var rock_material := _stylized_surface_material("rock", rock_tint)
    var mouth := MeshInstance3D.new()
    mouth.name = "RecessedCaveMouth"
    var mouth_mesh := SphereMesh.new()
    mouth_mesh.radius = 1.0
    mouth_mesh.height = 2.0
    mouth_mesh.radial_segments = 12
    mouth_mesh.rings = 6
    mouth.mesh = mouth_mesh
    # Recess behind the rim; placing this in front makes a flat black portal.
    mouth.position = Vector3(0, 1.22, -0.38)
    mouth.scale = Vector3(0.86, 0.96, 0.10)
    var darkness := StandardMaterial3D.new()
    darkness.albedo_color = Color(0.008, 0.012, 0.014, 1.0)
    darkness.roughness = 1.0
    darkness.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mouth.material_override = darkness
    facade.add_child(mouth)
    # Broad rear mass makes the opening read as a hollow in terrain instead
    # of a standalone arch. These sit behind the mouth and rim.
    var backing_specs: Array[Vector4] = [Vector4(-1.18, 1.05, 1.18, -0.04),
        Vector4(1.18, 1.08, 1.20, 0.05), Vector4(0.0, 2.05, 1.12, 0.02)]
    for backing_spec: Vector4 in backing_specs:
        var backing := MeshInstance3D.new()
        backing.name = "CaveBackingRock"
        var backing_mesh := SphereMesh.new()
        backing_mesh.radius = 0.95
        backing_mesh.height = 1.55
        backing_mesh.radial_segments = 8
        backing_mesh.rings = 4
        backing.mesh = backing_mesh
        backing.position = Vector3(backing_spec.x, backing_spec.y, -0.72)
        backing.scale = Vector3(backing_spec.z, backing_spec.z, backing_spec.z * 0.72)
        backing.rotation = Vector3(backing_spec.w, backing_spec.x * 0.16, -backing_spec.w)
        backing.material_override = rock_material
        facade.add_child(backing)
        facade.move_child(backing, 0)
    # Uneven boulders form a load-bearing horseshoe with wide grounded feet.
    var boulder_specs: Array[Vector4] = [
        Vector4(-1.28, 0.48, 0.72, -0.10), Vector4(1.28, 0.48, 0.76, 0.12),
        Vector4(-1.12, 1.25, 0.67, -0.16), Vector4(1.10, 1.28, 0.64, 0.14),
        Vector4(-0.72, 2.02, 0.61, -0.10), Vector4(0.70, 2.04, 0.63, 0.12),
        Vector4(0.0, 2.36, 0.70, 0.03),
    ]
    for i in boulder_specs.size():
        var spec: Vector4 = boulder_specs[i]
        var boulder := MeshInstance3D.new()
        boulder.name = "FacadeBoulder_%d" % i
        var mesh := SphereMesh.new()
        mesh.radius = 0.72
        mesh.height = 1.05
        mesh.radial_segments = 7
        mesh.rings = 4
        boulder.mesh = mesh
        boulder.position = Vector3(spec.x, spec.y, 0.0)
        boulder.scale = Vector3(spec.z * 1.15, spec.z, spec.z * 0.70)
        boulder.rotation = Vector3(spec.w, float(i) * 0.71, spec.w * -0.6)
        boulder.material_override = rock_material
        facade.add_child(boulder)
    var threshold := MeshInstance3D.new()
    threshold.name = "CaveThreshold"
    var threshold_mesh := CylinderMesh.new()
    threshold_mesh.top_radius = 1.34
    threshold_mesh.bottom_radius = 1.52
    threshold_mesh.height = 0.14
    threshold_mesh.radial_segments = 10
    threshold.mesh = threshold_mesh
    threshold.scale.z = 0.58
    threshold.position = Vector3(0, 0.03, -0.16)
    threshold.material_override = rock_material
    facade.add_child(threshold)
    if not is_exit:
        var glow := OmniLight3D.new()
        glow.name = "CaveMouthGlow"
        glow.light_color = ELEMENT_COLORS.get(_realm_element(), Color(0.5, 0.8, 1.0))
        glow.light_energy = 0.42
        glow.omni_range = 3.4
        glow.position = Vector3(0, 1.0, -0.35)
        facade.add_child(glow)

func _build_dungeon_wall_segments(parent: Node3D) -> void:
    var walls := Node3D.new()
    walls.name = "GroundedDungeonWalls"
    parent.add_child(walls)
    var material := _mountain_material()
    for side in 4:
        for segment in 7:
            # Leave a deliberate doorway in the southern wall.
            if side == 1 and segment in [3, 4]:
                continue
            var block := MeshInstance3D.new()
            block.name = "WallBlock_%d_%d" % [side, segment]
            var mesh := BoxMesh.new()
            mesh.size = Vector3(2.65, 2.3 + float((segment + side) % 3) * 0.32, 0.72)
            block.mesh = mesh
            var along := -7.8 + float(segment) * 2.6
            if side < 2:
                block.position = Vector3(along, mesh.size.y * 0.5 - 0.02,
                    -9.0 if side == 0 else 9.0)
            else:
                block.position = Vector3(-9.0 if side == 2 else 9.0,
                    mesh.size.y * 0.5 - 0.02, along)
                block.rotation.y = PI * 0.5
            block.rotation.y += float((segment * 17 + side * 11) % 7 - 3) * 0.012
            block.material_override = material
            walls.add_child(block)

func _build_dungeon_enemies() -> void:
    var roles: Array = layout.get("enemies", ["hushling", "spitter", "elite_hushling"])
    var positions := [Vector3(-4.0, 0.4, -1.5), Vector3(4.0, 0.4, -2.5), Vector3(0.0, 0.4, -4.0)]
    var enemy_specs: Array[Dictionary] = []
    for i in mini(roles.size(), positions.size()):
        enemy_specs.append({"scene": "res://scenes/entities/%s.tscn" % str(roles[i]),
            "name": "%sDepthEnemy%d" % [realm_id.capitalize(), i], "pos": positions[i]})
    for spec in enemy_specs:
        var scene: PackedScene = load(str(spec.scene))
        if scene == null or world == null:
            continue
        var enemy: Node3D = scene.instantiate()
        enemy.name = str(spec.name)
        world.add_child(enemy)
        enemy.global_position = dungeon_root.global_position + spec.pos
        _dungeon_enemies.append(enemy)
    _set_dungeon_enemies_active(false)

func _set_dungeon_enemies_active(active: bool) -> void:
    for enemy in _dungeon_enemies:
        if enemy == null or not is_instance_valid(enemy):
            continue
        enemy.visible = active
        enemy.set_physics_process(active)
        enemy.set_process(active)
        if active:
            enemy.add_to_group("enemy")
        else:
            enemy.remove_from_group("enemy")
        enemy.collision_layer = (1 << 1) if active else 0
        enemy.collision_mask = ((1 << 0) | (1 << 5) | (1 << 6)) if active else 0
        var hitbox := enemy.get_node_or_null("Hitbox")
        var attack_area := enemy.get_node_or_null("AttackArea")
        if hitbox != null:
            hitbox.set_deferred("monitoring", active)
        if attack_area != null:
            attack_area.set_deferred("monitoring", active)

func _make_chest_in_dungeon() -> void:
    var chest := PROP_SCRIPT.new()
    var chest_id := "%s_dungeon_cache" % realm_id
    var spec := {"type": "instant"}
    chest.name = "Chest_%s" % chest_id
    chest.position = Vector3(0, 0.48, -5.5)
    chest.collision_layer = 1 << 3
    chest.configure(self, "chest", chest_id, "OPEN CHEST")
    dungeon_root.add_child(chest)
    var body := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(1.5, 0.86, 0.95)
    body.mesh = box
    body.material_override = _emissive_material(Color(0.12, 0.08, 0.10), 0.18)
    chest.add_child(body)
    chest.set_meta("chest_type", "instant")
    chest.set_meta("boss_key", "")
    _add_collision(chest, Vector3(1.8, 1.4, 1.4))
    _add_label(chest, "EMBER CACHE", Vector3(0, 1.2, 0.2), Color(1.0, 0.42, 0.18))

func _build_route_markers() -> void:
    var route_root := Node3D.new()
    route_root.name = "AuthoredRoute_%s" % realm_id
    add_child(route_root)
    var tint := ELEMENT_COLORS.get(_realm_element(), Color(0.5, 0.8, 1.0)) as Color
    var points: Array = layout.get("route", [])
    for i in points.size():
        _build_route_landmark(route_root, points[i], i, tint)

func _build_route_landmark(parent: Node3D, point: Vector3, index: int, tint: Color) -> void:
    var landmark := Node3D.new()
    landmark.name = "RouteLandmark_%02d_%s" % [index, realm_id]
    landmark.position = point
    parent.add_child(landmark)
    var family := {"whispergrove": "bark", "bramblewood": "wood", "mistfen": "clay",
        "heartwood": "rock", "moonfen": "rock"}.get(realm_id, "rock") as String
    var surface := _stylized_surface_material(family, tint)
    match realm_id:
        "whispergrove":
            _add_landmark_column(landmark, Vector3(-0.7, 1.25, 0), 2.5, 0.22, surface, -0.16)
            _add_landmark_column(landmark, Vector3(0.7, 1.25, 0), 2.5, 0.22, surface, 0.16)
            _add_landmark_beam(landmark, Vector3(0, 2.3, 0), Vector3(1.7, 0.18, 0.25), surface)
        "bramblewood":
            for side in [-1.0, 1.0]:
                _add_landmark_column(landmark, Vector3(0.75 * side, 1.0, 0), 2.1, 0.18, surface, 0.35 * side)
                _add_landmark_spike(landmark, Vector3(0.62 * side, 2.05, 0), 0.75, surface, 0.55 * side)
        "mistfen":
            for offset in [-0.65, 0.0, 0.65]:
                _add_landmark_column(landmark, Vector3(offset, 0.45 + abs(offset), 0),
                    0.9 + abs(offset), 0.28, surface, offset * 0.22)
        "heartwood":
            _add_landmark_column(landmark, Vector3.ZERO + Vector3(0, 1.3, 0), 2.6, 0.42, surface, 0.0)
            for side in [-1.0, 1.0]:
                _add_landmark_spike(landmark, Vector3(0.42 * side, 1.25, 0), 1.0, surface, 0.7 * side)
            var vent := OmniLight3D.new()
            vent.light_color = tint
            vent.light_energy = 0.45
            vent.omni_range = 3.0
            vent.position.y = 0.35
            landmark.add_child(vent)
        "moonfen":
            var island := MeshInstance3D.new()
            var island_mesh := CylinderMesh.new()
            island_mesh.top_radius = 1.0
            island_mesh.bottom_radius = 1.25
            island_mesh.height = 0.22
            island_mesh.radial_segments = 10
            island.mesh = island_mesh
            island.position.y = 0.05
            island.material_override = surface
            landmark.add_child(island)
            for side in [-1.0, 1.0]:
                _add_landmark_spike(landmark, Vector3(0.42 * side, 0.7, 0), 1.1, surface, 0.35 * side)

func _build_route_resources() -> void:
    for i in (layout.get("resources", []) as Array).size():
        var spec := (layout.get("resources", []) as Array)[i] as Dictionary
        var node := GatheringNode.new()
        node.name = "RouteGather_%s_%02d" % [str(spec.get("id", "material")), i]
        var amount := int(spec.get("yield", 2))
        node.configure(str(spec.get("id", "moss_fiber")), amount, amount, 1.2, 210.0, realm_id)
        node.position = spec.get("pos", Vector3.ZERO)
        add_child(node)

func _build_authored_encounters() -> void:
    for i in (layout.get("encounters", []) as Array).size():
        var spec := (layout.get("encounters", []) as Array)[i] as Dictionary
        var scene_id := str(spec.get("scene", "hushling"))
        var path := "res://scenes/entities/%s.tscn" % scene_id
        var packed := load(path) as PackedScene
        if packed == null:
            push_error("RealmExpansion: missing authored encounter scene %s" % path)
            continue
        var enemy := packed.instantiate() as Node3D
        if enemy == null:
            continue
        enemy.name = "%s_%02d" % [scene_id.capitalize().replace(" ", ""), i]
        world.add_child(enemy)
        enemy.global_position = spec.get("pos", Vector3.ZERO)
        _surface_enemies.append(enemy)

func _add_landmark_column(parent: Node3D, pos: Vector3, height: float,
        radius: float, material: Material, lean: float) -> void:
    var mesh_instance := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius * 0.7
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 7
    mesh_instance.mesh = mesh
    mesh_instance.position = pos
    mesh_instance.rotation.z = lean
    mesh_instance.material_override = material
    parent.add_child(mesh_instance)

func _add_landmark_beam(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> void:
    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_instance.mesh = mesh
    mesh_instance.position = pos
    mesh_instance.material_override = material
    parent.add_child(mesh_instance)

func _add_landmark_spike(parent: Node3D, pos: Vector3, height: float,
        material: Material, lean: float) -> void:
    var mesh_instance := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.0
    mesh.bottom_radius = 0.16
    mesh.height = height
    mesh.radial_segments = 6
    mesh_instance.mesh = mesh
    mesh_instance.position = pos
    mesh_instance.rotation.z = lean
    mesh_instance.material_override = material
    parent.add_child(mesh_instance)

func _stylized_surface_material(family: String, tint: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    var root := "res://assets/textures/stylized/%s" % family
    material.albedo_texture = load("%s/albedo.png" % root)
    material.normal_enabled = true
    material.normal_texture = load("%s/normal.png" % root)
    material.roughness_texture = load("%s/roughness.png" % root)
    material.albedo_color = Color.WHITE.lerp(tint, 0.22)
    material.roughness = 0.86
    material.uv1_scale = Vector3(1.6, 1.6, 1.6)
    return material

func _realm_element() -> String:
    return {"whispergrove": "nature", "bramblewood": "fire", "mistfen": "frost",
        "heartwood": "fire", "moonfen": "shock"}.get(realm_id, "nature")

func _chest_rarity(chest_id: String) -> int:
    if chest_id == "%s_dungeon_cache" % realm_id or chest_id == "dungeon_cache":
        return 4
    for spec_value in layout.get("chests", []):
        var spec := spec_value as Dictionary
        if str(spec.get("id", "")) == chest_id:
            return clampi(int(spec.get("rarity", 1)), 1, 5)
    return {"mountain_cache": 2, "root_cache": 2}.get(chest_id, 1)

func _add_collision(parent: StaticBody3D, size: Vector3) -> void:
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    collision.position = Vector3(0, size.y * 0.5, 0)
    parent.add_child(collision)

func _add_label(parent: Node3D, text: String, pos: Vector3, color: Color) -> void:
    var label := Label3D.new()
    label.text = text
    label.font_size = 48
    label.pixel_size = 0.004
    label.outline_size = 8
    label.modulate = color
    label.position = pos
    parent.add_child(label)

func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color.darkened(0.28)
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = energy
    material.roughness = 0.68
    return material
