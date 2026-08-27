extends Node3D
class_name RealmEcosystem

## Seeded ecosystem layer: biome material parameters, zone-aware foliage,
## MultiMesh batching, and unique landmark candidate selection.
@export var seed_value: int = 20260823
@export var realm_id: String = "bramblewood"
@export var radius: float = 71.0
@export var cell_size: float = 8.5
@export var foliage_density: float = 1.6
@export var landmark_count: int = 3
@export var max_tree_instances: int = 220
@export var max_understory_instances: int = 280
@export var max_groundcover_instances: int = 1600
@export var max_deadwood_instances: int = 90

const CLEARING := "clearing"
const MEADOW := "meadow"
const DEEP := "deep_grove"
const DAMP := "damp_hollow"
const EDGE := "realm_edge"
const RAISED := "raised_island"
const RESERVED := [Vector2(-16.0, 10.0), Vector2(-16.0, -10.0), Vector2(14.2, -10.4), Vector2.ZERO]
const LANDMARKS := {
    "bramblewood": [{"id":"heartwood_altar","zone":DEEP,"kind":"altar","sep":25.0},{"id":"rootway_arch","zone":EDGE,"kind":"arch","sep":23.0},{"id":"leafwell_shrine","zone":MEADOW,"kind":"shrine","sep":22.0}],
    "whispergrove": [{"id":"heartwood_altar","zone":DEEP,"kind":"altar","sep":25.0},{"id":"rootway_arch","zone":EDGE,"kind":"arch","sep":23.0},{"id":"leafwell_shrine","zone":MEADOW,"kind":"shrine","sep":22.0}],
    "moonfen": [{"id":"drowned_watch","zone":RAISED,"kind":"watch","sep":26.0},{"id":"glowcap_basin","zone":DAMP,"kind":"basin","sep":23.0},{"id":"mire_shrine","zone":EDGE,"kind":"shrine","sep":22.0}],
    "mistfen": [{"id":"drowned_watch","zone":RAISED,"kind":"watch","sep":26.0},{"id":"reed_circle","zone":DAMP,"kind":"basin","sep":23.0},{"id":"mire_shrine","zone":EDGE,"kind":"shrine","sep":22.0}],
    "heartwood": [{"id":"ember_spire","zone":DEEP,"kind":"spire","sep":26.0},{"id":"ash_circle","zone":MEADOW,"kind":"basin","sep":23.0},{"id":"charred_gate","zone":EDGE,"kind":"arch","sep":22.0}]
}

var _terrain: Node
var _rng := RandomNumberGenerator.new()
var _zone_points: Dictionary = {}
var _landmark_points: Array[Vector2] = []

func setup(new_realm_id: String, new_seed: int, new_radius: float = 71.0) -> void:
    realm_id = new_realm_id.to_lower()
    seed_value = new_seed
    radius = new_radius
    _rng.seed = seed_value
    var root := get_parent().get_parent()
    _terrain = root.get_node_or_null("Terrain")
    _configure_terrain_material(root)
    _build_zone_map()
    _build_foliage_batches()
    _build_landmarks()

func _hash2(p: Vector2, salt: float = 0.0) -> float:
    var value := sin(p.x * 127.13 + p.y * 311.71 + float(seed_value) * 0.017 + salt) * 43758.5453
    return value - floor(value)

func _value_noise(p: Vector2, salt: float = 0.0) -> float:
    var cell: Vector2 = floor(p)
    var local: Vector2 = p - floor(p)
    var blend: Vector2 = local * local * (Vector2(3.0, 3.0) - 2.0 * local)
    var a := _hash2(cell, salt)
    var b := _hash2(cell + Vector2(1.0, 0.0), salt)
    var c := _hash2(cell + Vector2(0.0, 1.0), salt)
    var d := _hash2(cell + Vector2(1.0, 1.0), salt)
    return lerpf(lerpf(a, b, blend.x), lerpf(c, d, blend.x), blend.y)

func _fbm(p: Vector2, salt: float = 0.0) -> float:
    var total := 0.0
    var amplitude := 0.5
    var sample := p
    for octave in range(4):
        total += _value_noise(sample, salt + float(octave) * 17.3) * amplitude
        sample = sample * 2.03 + Vector2(19.19, 7.33)

        amplitude *= 0.5
    return total

func _ground_height(point: Vector2) -> float:
    if _terrain != null and _terrain.has_method("height_at"):
        return float(_terrain.height_at(point.x, point.y))
    return 0.0

func _is_reserved(point: Vector2, padding: float = 0.0) -> bool:
    if point.length() > radius - 4.0:
        return true
    for anchor in RESERVED:
        if point.distance_to(anchor) < 10.0 + padding:
            return true
    return false

func _classify_zone(point: Vector2) -> String:
    if point.length() < 15.0 or _is_reserved(point, 1.0):
        return CLEARING
    var moisture := _fbm(point * 0.035 + Vector2(7.0, 13.0), 2.1)
    var density := _fbm(point * 0.062 + Vector2(21.0, 5.0), 8.8)
    var edge := smoothstep(radius * 0.64, radius * 0.94, point.length())
    if realm_id == "moonfen" or realm_id == "mistfen":
        if moisture < 0.34:
            return RAISED
        if moisture > 0.62:
            return DAMP
    elif realm_id == "heartwood" and density > 0.64:
        return DEEP
    if edge > 0.72:
        return EDGE
    if density > 0.62:
        return DEEP
    if moisture > 0.66:
        return DAMP
    return MEADOW

func _build_zone_map() -> void:
    _zone_points.clear()
    for zone in [CLEARING, MEADOW, DEEP, DAMP, EDGE, RAISED]:
        _zone_points[zone] = []
    var grid := int(ceil(radius / cell_size))
    for ix in range(-grid, grid + 1):
        for iz in range(-grid, grid + 1):
            var cell := Vector2(ix, iz)
            var point := cell * cell_size + Vector2(_hash2(cell, 4.0) - 0.5, _hash2(cell, 9.0) - 0.5) * cell_size * 0.72
            if point.length() <= radius:
                _zone_points[_classify_zone(point)].append(point)

func _configure_terrain_material(root: Node) -> void:
    var terrain_mesh := root.get_node_or_null("Terrain/TerrainMesh")
    if terrain_mesh == null:
        return
    var material := terrain_mesh.material_override as ShaderMaterial
    if material == null:
        return
    material = material.duplicate() as ShaderMaterial
    var tint := Color(0.84, 1.0, 0.74)
    var tint_strength := 0.10
    var moisture := 0.16
    var moss := Color(0.22, 0.42, 0.24)
    var moss_strength := 0.14
    match realm_id:
        "moonfen":
            tint = Color(0.68, 0.82, 0.88)
            tint_strength = 0.20
            moisture = 0.76
            moss = Color(0.18, 0.45, 0.42)
            moss_strength = 0.34
        "mistfen":
            tint = Color(0.72, 0.84, 0.80)
            tint_strength = 0.16
            moisture = 0.62
            moss = Color(0.24, 0.48, 0.38)
            moss_strength = 0.28
        "heartwood":
            tint = Color(1.0, 0.70, 0.48)
            tint_strength = 0.16
            moisture = 0.08
            moss = Color(0.30, 0.16, 0.08)
            moss_strength = 0.08
    material.set_shader_parameter("realm_tint", tint)
    material.set_shader_parameter("realm_tint_strength", tint_strength)
    material.set_shader_parameter("moisture_strength", moisture)
    material.set_shader_parameter("moss_color", moss)
    material.set_shader_parameter("moss_strength", moss_strength)
    terrain_mesh.material_override = material

func _material(color: Color, roughness: float = 0.9, emission: Color = Color.BLACK) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    if emission != Color.BLACK:
        material.emission_enabled = true
        material.emission = emission
        material.emission_energy_multiplier = 1.4
    return material

func _batch(name: String, mesh: Mesh, material: Material, transforms: Array, shadows: bool, visible_to: float) -> void:
    if transforms.is_empty():
        return
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for i in range(transforms.size()):
        multimesh.set_instance_transform(i, transforms[i])
    multimesh.custom_aabb = AABB(Vector3(-radius - 8.0, -3.0, -radius - 8.0), Vector3((radius + 8.0) * 2.0, 20.0, (radius + 8.0) * 2.0))
    var instance := MultiMeshInstance3D.new()
    instance.name = name
    instance.multimesh = multimesh
    instance.material_override = material
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    instance.visibility_range_end = visible_to
    instance.extra_cull_margin = 4.0
    add_child(instance)

func _build_foliage_batches() -> void:
    var trunk := CylinderMesh.new()
    trunk.top_radius = 0.14
    trunk.bottom_radius = 0.34
    trunk.height = 3.2
    trunk.radial_segments = 6
    var canopy := SphereMesh.new()
    canopy.radius = 1.45
    canopy.height = 2.25
    canopy.radial_segments = 8
    var bush := SphereMesh.new()
    bush.radius = 0.52
    bush.height = 0.72
    bush.radial_segments = 6
    var grass := CylinderMesh.new()
    grass.top_radius = 0.018
    grass.bottom_radius = 0.055
    grass.height = 0.42
    grass.radial_segments = 3
    var log := BoxMesh.new()
    log.size = Vector3(1.7, 0.24, 0.35)
    var trees: Array = []
    var canopies: Array = []
    var bushes: Array = []
    var tufts: Array = []
    var logs: Array = []
    var density_scale := clampf(foliage_density, 0.5, 2.5)
    var candidates: Array = []
    for zone in [DEEP, MEADOW, EDGE, DAMP, RAISED]:
        for point in _zone_points.get(zone, []):
            candidates.append({"p": point, "zone": zone})
            var satellite_count := maxi(0, int(round((density_scale - 1.0) * 2.0)))
            for satellite in range(satellite_count):
                var satellite_seed := float(satellite) * 113.0 + 47.0
                var offset := Vector2(_hash2(point, satellite_seed) - 0.5, _hash2(point, satellite_seed + 1.0) - 0.5) * cell_size * 0.34
                var satellite_point: Vector2 = point + offset
                if satellite_point.length() <= radius - 3.0 and not _is_reserved(satellite_point, 0.0):
                    candidates.append({"p": satellite_point, "zone": zone})
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return _hash2(a.p, 42.0) < _hash2(b.p, 42.0))
    var tree_cap := int(round(float(max_tree_instances) * density_scale))
    var bush_cap := int(round(float(max_understory_instances) * density_scale))
    var tuft_cap := int(round(float(max_groundcover_instances) * density_scale))
    var tree_budget := mini(tree_cap, int(candidates.size() * 0.92 * density_scale))
    var bush_budget := mini(bush_cap, int(candidates.size() * 1.10 * density_scale))
    var tuft_budget := mini(tuft_cap, int(candidates.size() * 2.30 * density_scale))
    var deadwood_cap := int(round(float(max_deadwood_instances) * density_scale))
    for index in range(candidates.size()):
        var item: Dictionary = candidates[index]
        var point: Vector2 = item.p
        var zone: String = item.zone
        var gy := _ground_height(point)
        if trees.size() < tree_budget and (zone == DEEP or zone == EDGE or index % 5 == 0):
            var scale := lerpf(0.72, 1.55, _hash2(point, 71.0))
            if realm_id == "moonfen" or realm_id == "mistfen":
                scale *= 0.88
            var lean := (_hash2(point, 73.0) - 0.5) * 0.18
            var basis := Basis.from_euler(Vector3(lean, _hash2(point, 74.0) * TAU, -lean * 0.7)).scaled(Vector3(scale, scale, scale))
            trees.append(Transform3D(basis, Vector3(point.x, gy + 1.58 * scale, point.y)))
            canopies.append(Transform3D(basis, Vector3(point.x, gy + 3.15 * scale, point.y)))
        if bushes.size() < bush_budget and index % 2 == 0:
            var bush_scale := lerpf(0.65, 1.45, _hash2(point, 81.0))
            bushes.append(Transform3D(Basis(Vector3.UP, _hash2(point, 82.0) * TAU).scaled(Vector3(bush_scale, bush_scale, bush_scale)), Vector3(point.x, gy + 0.24, point.y)))
        if tufts.size() < tuft_budget:
            var tuft_count := 2 if index % 3 == 0 else 1
            for blade in range(tuft_count):
                var gp := point + Vector2(_hash2(point, float(blade) + 92.0) - 0.5, _hash2(point, float(blade) + 93.0) - 0.5) * 1.1
                var tuft_scale := lerpf(0.55, 1.35, _hash2(gp, 94.0))
                tufts.append(Transform3D(Basis.from_euler(Vector3(0.08, _hash2(gp, 95.0) * TAU, -0.08)).scaled(Vector3(tuft_scale, tuft_scale, tuft_scale)), Vector3(gp.x, gy, gp.y)))
        if logs.size() < deadwood_cap and zone == DAMP and index % 4 == 0:
            var log_scale := lerpf(0.7, 1.6, _hash2(point, 101.0))
            logs.append(Transform3D(Basis.from_euler(Vector3(0.03, _hash2(point, 102.0) * TAU, 0.22)).scaled(Vector3(log_scale, log_scale, log_scale)), Vector3(point.x, gy + 0.16, point.y)))
    var bark := Color(0.12, 0.095, 0.075)
    var leaf := Color(0.075, 0.15, 0.10)
    var under := Color(0.12, 0.28, 0.13)
    var ground := Color(0.22, 0.40, 0.12)
    var dead := Color(0.16, 0.12, 0.10)
    if realm_id == "moonfen" or realm_id == "mistfen":
        bark = Color(0.12, 0.15, 0.16)
        leaf = Color(0.08, 0.20, 0.22)
        under = Color(0.12, 0.34, 0.30)
        ground = Color(0.20, 0.46, 0.28)
        dead = Color(0.11, 0.15, 0.14)
    elif realm_id == "heartwood":
        bark = Color(0.12, 0.06, 0.045)
        leaf = Color(0.20, 0.075, 0.035)
        under = Color(0.34, 0.12, 0.045)
        ground = Color(0.42, 0.16, 0.045)
        dead = Color(0.12, 0.055, 0.035)
    _batch("EcosystemTrees", trunk, _material(bark), trees, true, 96.0)
    _batch("EcosystemCanopies", canopy, _material(leaf), canopies, true, 96.0)
    _batch("EcosystemUnderstory", bush, _material(under), bushes, false, 72.0)
    _batch("EcosystemGroundcover", grass, _material(ground), tufts, false, 54.0)
    _batch("EcosystemDeadwood", log, _material(dead), logs, false, 70.0)

func _best_landmark_point(spec: Dictionary, accepted: Array) -> Vector2:
    var points: Array = _zone_points.get(str(spec.zone), _zone_points.get(MEADOW, []))
    var best := Vector2.ZERO
    var best_score := -INF
    for point in points:
        if _is_reserved(point, 4.0):
            continue
        var separated := true
        for other in accepted:
            if point.distance_to(other) < float(spec.sep):
                separated = false
                break
        if not separated:
            continue
        var edge_bias := 1.0 - absf(point.length() / radius - 0.55)
        var noise_score := _fbm(point * 0.052 + Vector2(13.0, -9.0), float(spec.sep))
        var score := noise_score * 0.65 + edge_bias * 0.35
        if score > best_score:
            best_score = score
            best = point
    return best

func _build_landmarks() -> void:
    _landmark_points.clear()
    var library: Array = LANDMARKS.get(realm_id, LANDMARKS["bramblewood"])
    var accepted: Array = []
    for spec in library:
        if accepted.size() >= landmark_count:
            break
        var point := _best_landmark_point(spec, accepted)
        if point == Vector2.ZERO:
            continue
        accepted.append(point)
        _landmark_points.append(point)
        _spawn_landmark(spec, point)

func _spawn_landmark(spec: Dictionary, point: Vector2) -> void:
    var landmark := Node3D.new()
    landmark.name = "Landmark_%s" % str(spec.id)
    landmark.position = Vector3(point.x, _ground_height(point), point.y)
    add_child(landmark)
    var stone := _material(Color(0.28, 0.30, 0.27))
    var accent := Color(0.42, 0.88, 0.62)
    if realm_id == "moonfen" or realm_id == "mistfen":
        stone = _material(Color(0.20, 0.28, 0.30), 0.72)
        accent = Color(0.30, 0.88, 0.96)
    elif realm_id == "heartwood":
        stone = _material(Color(0.24, 0.10, 0.07))
        accent = Color(1.0, 0.34, 0.08)
    var kind: String = spec.kind
    if kind == "arch":
        var pillar := CylinderMesh.new()
        pillar.top_radius = 0.34
        pillar.bottom_radius = 0.5
        pillar.height = 3.2
        pillar.radial_segments = 7
        pillar.material = stone
        _add_mesh(landmark, pillar, Vector3(-1.5, 1.6, 0))
        _add_mesh(landmark, pillar, Vector3(1.5, 1.6, 0))
        var lintel := BoxMesh.new()
        lintel.size = Vector3(3.7, 0.55, 0.55)
        lintel.material = stone
        _add_mesh(landmark, lintel, Vector3(0, 3.0, 0))
    elif kind == "watch" or kind == "spire":
        var tower := CylinderMesh.new()
        tower.top_radius = 0.10
        tower.bottom_radius = 0.72
        tower.height = 5.0
        tower.radial_segments = 8
        tower.material = stone
        _add_mesh(landmark, tower, Vector3(0, 2.5, 0))
    else:
        var base := CylinderMesh.new()
        base.top_radius = 1.25
        base.bottom_radius = 1.55
        base.height = 0.65
        base.radial_segments = 8
        base.material = stone
        _add_mesh(landmark, base, Vector3(0, 0.32, 0))
        var core := SphereMesh.new()
        core.radius = 0.46
        core.height = 0.92
        core.material = _material(accent, 0.35, accent)
        _add_mesh(landmark, core, Vector3(0, 1.02, 0))

func _add_mesh(parent: Node3D, mesh: Mesh, position: Vector3) -> void:
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.position = position
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(instance)
