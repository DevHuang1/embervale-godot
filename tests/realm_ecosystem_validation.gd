extends Node

const RESERVED_ANCHORS := [Vector2(-16.0, 10.0), Vector2(-16.0, -10.0), Vector2(14.2, -10.4), Vector2.ZERO]
const MIN_LANDMARK_SEPARATION := 21.9

var _failures: Array[String] = []
var _passes := 0

func _ready() -> void:
    await _run_validation()
    print("=== Realm Ecosystem Validation ===")
    print("passes=", _passes, " failures=", _failures.size())
    for failure in _failures:
        print("FAILURE: ", failure)
    get_tree().quit(1 if not _failures.is_empty() else 0)

func _run_validation() -> void:
    var grove_a := await _build_ecosystem("bramblewood", 41827)
    var grove_b := await _build_ecosystem("bramblewood", 41827)
    _assert_same_layout(grove_a, grove_b, "same realm and seed")
    _assert_landmarks(grove_a, "Bramblewood")
    _assert_batch_contract(grove_a, "Bramblewood")
    var grove_material := _terrain_material(grove_a)
    _assert_true(grove_material != null, "Bramblewood terrain uses ShaderMaterial")
    if grove_material != null:
        _assert_true(float(grove_material.get_shader_parameter("realm_tint_strength")) > 0.0, "Bramblewood realm tint is configured")
        _assert_true(float(grove_material.get_shader_parameter("moisture_strength")) > 0.0, "Bramblewood moisture is configured")

    var fen := await _build_ecosystem("moonfen", 41827)
    _assert_landmarks(fen, "Moonfen")
    _assert_batch_contract(fen, "Moonfen")
    var fen_material := _terrain_material(fen)
    _assert_true(fen_material != null, "Moonfen terrain uses ShaderMaterial")
    if fen_material != null and grove_material != null:
        _assert_true(fen_material.get_shader_parameter("realm_tint") != grove_material.get_shader_parameter("realm_tint"), "Moonfen tint differs from Bramblewood")
        _assert_true(float(fen_material.get_shader_parameter("moisture_strength")) > float(grove_material.get_shader_parameter("moisture_strength")), "Moonfen moisture exceeds Bramblewood")

    grove_a.get_parent().queue_free()
    grove_b.get_parent().queue_free()
    fen.get_parent().queue_free()
    await get_tree().process_frame

func _build_ecosystem(realm: String, seed_value: int) -> RealmEcosystem:
    var world := Node3D.new()
    world.name = "ValidationWorld_" + realm
    var terrain := Node3D.new()
    terrain.name = "Terrain"
    world.add_child(terrain)
    var terrain_mesh := MeshInstance3D.new()
    terrain_mesh.name = "TerrainMesh"
    terrain_mesh.mesh = PlaneMesh.new()
    var terrain_material := ShaderMaterial.new()
    terrain_material.shader = load("res://assets/shaders/terrain_ground.gdshader")
    terrain_mesh.material_override = terrain_material
    terrain.add_child(terrain_mesh)
    var border := Node3D.new()
    border.name = "ForestBorder"
    world.add_child(border)
    add_child(world)
    var ecosystem := RealmEcosystem.new()
    ecosystem.name = "RealmEcosystem"
    border.add_child(ecosystem)
    ecosystem.setup(realm, seed_value, 71.0)
    await get_tree().process_frame
    return ecosystem

func _assert_same_layout(first: RealmEcosystem, second: RealmEcosystem, label: String) -> void:
    var first_points: Array = first._landmark_points
    var second_points: Array = second._landmark_points
    _assert_true(first_points.size() == second_points.size(), label + " landmark count is stable")
    for index in range(mini(first_points.size(), second_points.size())):
        _assert_true(first_points[index].distance_to(second_points[index]) < 0.001, label + " landmark %d position is stable" % index)
    var first_names := _landmark_names(first)
    var second_names := _landmark_names(second)
    _assert_true(first_names == second_names, label + " landmark ids are stable")

func _assert_landmarks(ecosystem: RealmEcosystem, label: String) -> void:
    var points: Array = ecosystem._landmark_points
    _assert_true(points.size() >= 2, label + " creates at least two unique landmarks")
    for index in range(points.size()):
        var point: Vector2 = points[index]
        for anchor in RESERVED_ANCHORS:
            _assert_true(point.distance_to(anchor) >= 13.99, label + " landmark avoids reserved anchor")
        for other_index in range(index):
            var other: Vector2 = points[other_index]
            _assert_true(point.distance_to(other) >= MIN_LANDMARK_SEPARATION, label + " landmarks maintain separation")

func _assert_batch_contract(ecosystem: RealmEcosystem, label: String) -> void:
    var batches := 0
    var instances := 0
    for child in ecosystem.get_children():
        if child is MultiMeshInstance3D:
            batches += 1
            var multimesh: MultiMesh = (child as MultiMeshInstance3D).multimesh
            if multimesh != null:
                instances += multimesh.instance_count
    _assert_true(batches >= 4, label + " uses at least four MultiMesh foliage batches")
    _assert_true(instances >= 100, label + " produces a meaningful instanced foliage population")

func _terrain_material(ecosystem: RealmEcosystem) -> ShaderMaterial:
    var terrain_mesh := ecosystem.get_parent().get_parent().get_node("Terrain/TerrainMesh") as MeshInstance3D
    return terrain_mesh.material_override as ShaderMaterial

func _landmark_names(ecosystem: RealmEcosystem) -> Array[String]:
    var names: Array[String] = []
    for child in ecosystem.get_children():
        if str(child.name).begins_with("Landmark_"):
            names.append(str(child.name))
    return names

func _assert_true(condition: bool, message: String) -> void:
    if condition:
        _passes += 1
        print("PASS: ", message)
    else:
        _failures.append(message)
        push_error("FAIL: " + message)
