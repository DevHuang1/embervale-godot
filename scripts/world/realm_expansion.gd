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
var _dungeon_enemies: Array[Node3D] = []

func setup(owner_world: Node3D) -> void:
    world = owner_world
    hero = owner_world.get_node_or_null("Hero")
    name = "RealmExpansion"
    _build_mountain_ridge()
    _build_checkpoint(Vector3(3.0, 0.35, 3.5))
    _build_surface_chests()
    _build_cave_and_dungeon()

func _process(_delta: float) -> void:
    if cave_entry != null and is_instance_valid(cave_entry):
        cave_entry.rotate_y(0.22 * _delta)
    if cave_exit != null and is_instance_valid(cave_exit):
        cave_exit.rotate_y(-0.28 * _delta)

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
    _opened_chests[chest_id] = true
    GameState.opened_chests[chest_id] = true
    var reward: Dictionary = {
        "mountain_cache": {"gold": 38, "item": "moss_tonic", "amount": 1, "rarity": 2, "element": "frost"},
        "root_cache": {"gold": 26, "item": "moss_tonic", "amount": 1, "rarity": 2, "element": "nature"},
        "dungeon_cache": {"gold": 74, "item": "moss_tonic", "amount": 2, "rarity": 4, "element": "shock"},
    }.get(chest_id, {"gold": 18, "item": "moss_tonic", "amount": 1, "rarity": 1, "element": "fire"})
    var gold := int(reward.get("gold", 0))
    var item_id := str(reward.get("item", ""))
    var pos: Vector3 = chest.global_position if chest is Node3D else global_position
    var loot_drop := preload("res://scripts/systems/loot_drop.gd")
    if gold > 0:
        loot_drop.spawn_gold(self, pos + Vector3(0.0, 0.22, 0.0), gold)
    if not item_id.is_empty():
        loot_drop.spawn_item(self, pos + Vector3(0.32, 0.20, 0.0), item_id,
            int(reward.get("amount", 1)), int(reward.get("rarity", 1)))
    var element := str(reward.get("element", "fire"))
    CombatFx.spawn_chest_open(self, pos, ELEMENT_COLORS.get(element, Color.WHITE))
    var rarity_names := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
    var rarity := clampi(int(reward.get("rarity", 1)), 1, 5)
    GameState.quest_progress.emit("Chest opened — %s cache, %d gold and %s attunement shard." % [rarity_names[rarity - 1], gold, element.capitalize()])
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
    _make_chest("mountain_cache", Vector3(-10, 0.48, -17), "MOUNTAIN CACHE", Color(0.40, 0.82, 1.0))
    _make_chest("root_cache", Vector3(11, 0.48, 12), "ROOT CACHE", Color(0.36, 1.0, 0.48))

func _make_chest(chest_id: String, pos: Vector3, label_text: String, glow: Color) -> void:
    var chest := PROP_SCRIPT.new()
    chest.name = "Chest_%s" % chest_id
    chest.position = pos
    chest.collision_layer = 1 << 3
    chest.configure(self, "chest", chest_id, "OPEN CHEST")
    add_child(chest)
    var body := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(1.25, 0.72, 0.82)
    body.mesh = box
    body.material_override = _emissive_material(Color(0.20, 0.11, 0.06), 0.12)
    chest.add_child(body)
    var band := MeshInstance3D.new()
    var band_mesh := BoxMesh.new()
    band_mesh.size = Vector3(1.32, 0.16, 0.88)
    band.mesh = band_mesh
    band.position = Vector3(0, 0.05, 0)
    band.material_override = _emissive_material(glow, 0.7)
    chest.add_child(band)
    _add_collision(chest, Vector3(1.6, 1.25, 1.2))
    _add_label(chest, label_text, Vector3(0, 1.05, 0.18), glow)
    _chests[chest_id] = chest

func _build_cave_and_dungeon() -> void:
    cave_entry = PROP_SCRIPT.new()
    cave_entry.name = "EmbervaultEntrance"
    cave_entry.position = Vector3(19.0, 0.7, -16.0)
    cave_entry.collision_layer = 1 << 3
    cave_entry.configure(self, "dungeon", "embervault", "ENTER CAVE")
    add_child(cave_entry)
    var arch_mat := _emissive_material(Color(0.22, 0.32, 0.42), 0.4)
    for x in [-1.35, 1.35]:
        var pillar := MeshInstance3D.new()
        var cyl := CylinderMesh.new()
        cyl.top_radius = 0.42
        cyl.bottom_radius = 0.62
        cyl.height = 3.1
        cyl.radial_segments = 8
        pillar.mesh = cyl
        pillar.position = Vector3(x, 1.55, 0)
        pillar.material_override = arch_mat
        cave_entry.add_child(pillar)
    var lintel := MeshInstance3D.new()
    var top := BoxMesh.new()
    top.size = Vector3(3.4, 0.7, 0.8)
    lintel.mesh = top
    lintel.position = Vector3(0, 3.0, 0)
    lintel.material_override = arch_mat
    cave_entry.add_child(lintel)
    _add_collision(cave_entry, Vector3(3.8, 3.5, 1.4))
    _add_label(cave_entry, "CAVE · EMBERVAULT", Vector3(0, 4.0, 0.22), Color(0.48, 0.78, 1.0))

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
    for wall_data in [Vector3(0, 2.5, -9), Vector3(0, 2.5, 9), Vector3(-9, 2.5, 0), Vector3(9, 2.5, 0)]:
        var wall := MeshInstance3D.new()
        var wall_mesh := BoxMesh.new()
        wall_mesh.size = Vector3(18, 5, 0.5) if abs(wall_data.x) < 1.0 else Vector3(0.5, 5, 18)
        wall.mesh = wall_mesh
        wall.position = wall_data
        wall.material_override = _mountain_material()
        dungeon_root.add_child(wall)
    _add_label(dungeon_root, "EMBERvault · DEPTH 01", Vector3(0, 5.2, -8.4), Color(1.0, 0.62, 0.28))
    _build_dungeon_enemies()
    _make_chest_in_dungeon()
    cave_exit = PROP_SCRIPT.new()
    cave_exit.name = "EmbervaultExit"
    cave_exit.position = Vector3(0, 0.7, 7.5)
    cave_exit.collision_layer = 1 << 3
    cave_exit.configure(self, "dungeon", "embervault_exit", "EXIT CAVE")
    dungeon_root.add_child(cave_exit)
    _add_collision(cave_exit, Vector3(3.0, 2.6, 1.2))
    _add_label(cave_exit, "EXIT · SURFACE", Vector3(0, 2.4, 0.2), Color(0.48, 0.78, 1.0))

func _build_dungeon_enemies() -> void:
    var enemy_specs := [
        {"scene": "res://scenes/entities/hushling.tscn", "name": "EmbervaultSentinel", "pos": Vector3(-4.0, 0.4, -1.5)},
        {"scene": "res://scenes/entities/spitter.tscn", "name": "EmbervaultSpitter", "pos": Vector3(4.0, 0.4, -2.5)},
        {"scene": "res://scenes/entities/elite_hushling.tscn", "name": "EmbervaultWarden", "pos": Vector3(0.0, 0.4, -4.0)},
    ]
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
    chest.name = "Chest_dungeon_cache"
    chest.position = Vector3(0, 0.48, -5.5)
    chest.collision_layer = 1 << 3
    chest.configure(self, "chest", "dungeon_cache", "OPEN CHEST")
    dungeon_root.add_child(chest)
    var body := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(1.5, 0.86, 0.95)
    body.mesh = box
    body.material_override = _emissive_material(Color(0.12, 0.08, 0.10), 0.18)
    chest.add_child(body)
    _add_collision(chest, Vector3(1.8, 1.4, 1.4))
    _add_label(chest, "EMBER CACHE", Vector3(0, 1.2, 0.2), Color(1.0, 0.42, 0.18))

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
    label.font_size = 72
    label.pixel_size = 0.004
    label.outline_size = 12
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
