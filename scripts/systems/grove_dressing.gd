extends Node3D
class_name GroveDressing

## === Whispergrove Dressing ===
## Seeded runtime vegetation across the full expanded realm: border
## treeline, interior groves, rocks/bushes/pebbles/grass (MultiMesh
## batches), glow-mushroom clusters, ancient ruins and lit torches.

@export var seed_value: int = 20260823
@export var tree_ring_min: float = 232.0
@export var tree_ring_max: float = 292.0
@export var tree_count: int = 360
@export var grove_cluster_count: int = 26
@export var rock_count: int = 320
@export var bush_count: int = 240
@export var pebble_count: int = 1100
@export var tuft_count: int = 36000
@export_range(0.5, 2.5, 0.1) var ecosystem_density: float = 1.6
@export var scatter_radius: float = 300.0
@export var tree_trunk_color: Color = Color(0.12, 0.095, 0.075)
@export var tree_canopy_color: Color = Color(0.075, 0.15, 0.10)
@export var rock_color: Color = Color(0.27, 0.29, 0.26)
@export var tuft_color: Color = Color(0.16, 0.24, 0.10)
@export var mushroom_cap_color: Color = Color(0.36, 0.52, 0.40)

var rng := RandomNumberGenerator.new()

## Signature prop layer keyed to the explorable realm (falls back through
## biome_id, then the current travel realm, then Bramblewood).
enum RealmFlavor { BRAMBLEWOOD, MISTFEN, HEARTWOOD, MOONFEN }

func _ready() -> void:
	rng.seed = seed_value
	_build_trees()
	_build_grove_clusters()
	_build_rocks()
	_build_bushes()
	_build_pale_path()
	_build_tufts()
	_build_pebbles()
	_build_mushrooms()
	_build_ruins()
	_build_torches()
	_build_realm_flavor()
	_build_props()
	var ecosystem := RealmEcosystem.new()
	ecosystem.name = "RealmEcosystem"
	ecosystem.foliage_density = ecosystem_density
	add_child(ecosystem)
	var ecosystem_id := "bramblewood"
	match _realm_flavor():
		RealmFlavor.MISTFEN:
			ecosystem_id = "mistfen"
		RealmFlavor.HEARTWOOD:
			ecosystem_id = "heartwood"
		RealmFlavor.MOONFEN:
			ecosystem_id = "moonfen"
		_: 
			ecosystem_id = "bramblewood"
	ecosystem.setup(ecosystem_id, seed_value + 1337, scatter_radius)

func _realm_flavor() -> int:
	var id := ""
	var world_root := get_parent()
	if world_root != null and "biome_id" in world_root:
		id = str(world_root.get("biome_id"))
	else:
		var gs := get_node_or_null("/root/GameState")
		if gs != null:
			id = str(gs.get("current_realm"))
	match id:
		"mistfen":
			return RealmFlavor.MISTFEN
		"heartwood":
			return RealmFlavor.HEARTWOOD
		"moonfen":
			return RealmFlavor.MOONFEN
		_:
			return RealmFlavor.BRAMBLEWOOD

func _build_realm_flavor() -> void:
	match _realm_flavor():
		RealmFlavor.MISTFEN:
			_build_reeds()
			_build_drowned_stones()
		RealmFlavor.HEARTWOOD:
			_build_charred_spires()
			_build_ember_motes()
		RealmFlavor.MOONFEN:
			_build_glowcaps()
		_:
			_build_thorn_arches()

func _ground_height(x: float, z: float) -> float:
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("height_at"):
		return terrain.height_at(x, z)
	return 0.0

## Breakable loot props near gameplay landmarks (flattened zones), flavored
## per realm. Anchors come from TerrainRelief so props sit on walkable
## ground away from quest hotspots.
func _build_props() -> void:
	var pools := {
		RealmFlavor.BRAMBLEWOOD: ["pot", "pot", "crate"],
		RealmFlavor.MISTFEN: ["pot", "crate"],
		RealmFlavor.HEARTWOOD: ["crate", "crate", "pot"],
		RealmFlavor.MOONFEN: ["glowcap", "glowcap", "pot"],
	}
	var pool: Array = pools.get(_realm_flavor(), pools[RealmFlavor.BRAMBLEWOOD])
	var anchors := _prop_anchors()
	var placed := 0
	for i in mini(anchors.size() * 2, 14):
		if placed >= 11:
			break
		var anchor: Vector2 = anchors[rng.randi() % anchors.size()]
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(3.6, 6.6)
		var p := anchor + Vector2(cos(ang) * rad, sin(ang) * rad)
		var prop := DestructibleProp.create(str(pool[rng.randi() % pool.size()]))
		prop.position = Vector3(p.x, _ground_height(p.x, p.y), p.y)
		add_child(prop)
		placed += 1

func _prop_anchors() -> Array[Vector2]:
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain != null and terrain.has_method("prop_anchor_points"):
		return terrain.prop_anchor_points()
	return [Vector2.ZERO, Vector2(12, -8), Vector2(-14, 6),
		Vector2(18, 14), Vector2(-6, -16)]

func _mat(color: Color, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m

func _shader_mat(path: String, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	_bind_scan_textures(m, path)
	for key in params:
		m.set_shader_parameter(key, params[key])
	return m

## Bind the scanned CC0 PBR sets onto rock/bark shader materials unless the
## caller overrides them, so procedural surfaces pick up photo detail for
## free and never fall back to the white default texture.
func _bind_scan_textures(m: ShaderMaterial, path: String) -> void:
	if path.ends_with("rock.gdshader"):
		for pair in [["rock_albedo_tex", "rock/albedo.jpg"],
				["rock_normal_tex", "rock/normal.jpg"],
				["rock_rough_tex", "rock/roughness.jpg"]]:
			m.set_shader_parameter(pair[0], load(
				"res://assets/textures/pbr/%s" % pair[1]))
	elif path.ends_with("bark.gdshader"):
		for pair in [["bark_albedo_tex", "bark/albedo.jpg"],
				["bark_normal_tex", "bark/normal.jpg"],
				["bark_rough_tex", "bark/roughness.jpg"]]:
			m.set_shader_parameter(pair[0], load(
				"res://assets/textures/pbr/%s" % pair[1]))

func _batch(mesh: Mesh, material: Material, transforms: Array[Transform3D],
		shadows: bool, extent: float = 35.0) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.custom_aabb = AABB(Vector3(-extent, -2, -extent), Vector3(extent * 2, 18, extent * 2))
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	if shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _rand_pos_in(radius: float) -> Vector2:
	var ang := rng.randf() * TAU
	var r := sqrt(rng.randf()) * radius
	return Vector2(cos(ang) * r, sin(ang) * r)

func _build_trees() -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.34
	trunk.height = 3.2
	trunk.radial_segments = 6
	trunk.rings = 1

	var canopy := SphereMesh.new()
	canopy.radius = 1.5
	canopy.height = 2.2
	canopy.radial_segments = 8
	canopy.rings = 4

	var bark := _shader_mat("res://assets/shaders/bark.gdshader", {
		"bark_color": tree_trunk_color,
	})
	var canopy_mat := _shader_mat("res://assets/shaders/canopy.gdshader", {
		"canopy_color": tree_canopy_color,
		"highlight_color": tree_canopy_color.lightened(0.5),
	})

	var trunks: Array[Transform3D] = []
	var canopies: Array[Transform3D] = []

	# Dense border treeline ringing the realm
	for i in tree_count:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(tree_ring_min, tree_ring_max)
		var pos := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var s := rng.randf_range(0.75, 1.7)
		var ground_y := _ground_height(pos.x, pos.z)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(s, s * rng.randf_range(0.9, 1.3), s))
		trunks.append(Transform3D(b, Vector3(pos.x, ground_y, pos.z)))
		canopies.append(Transform3D(b, Vector3(pos.x, ground_y + 3.05 * s, pos.z)))

	_batch(trunk, bark, trunks, true, 310.0)
	_batch(canopy, canopy_mat, canopies, true, 310.0)

## Small interior groves so the open plain isn't empty between landmarks
func _build_grove_clusters() -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.14
	trunk.bottom_radius = 0.28
	trunk.height = 2.6
	trunk.radial_segments = 6
	trunk.rings = 1
	var canopy := SphereMesh.new()
	canopy.radius = 1.2
	canopy.height = 1.8
	canopy.radial_segments = 8
	canopy.rings = 4
	var bark := _shader_mat("res://assets/shaders/bark.gdshader", {
		"bark_color": tree_trunk_color,
	})
	var canopy_mat := _shader_mat("res://assets/shaders/canopy.gdshader", {
		"canopy_color": tree_canopy_color,
		"highlight_color": tree_canopy_color.lightened(0.5),
	})
	var trunks: Array[Transform3D] = []
	var canopies: Array[Transform3D] = []
	for c in grove_cluster_count:
		var center := _rand_pos_in(scatter_radius * 0.72)
		# Keep clusters clear of spawn/quest core
		if center.length() < 26.0 or center.distance_to(Vector2(-16, 10)) < 22.0 \
				or center.distance_to(Vector2(14.2, -10.4)) < 16.0:
			continue
		for j in rng.randi_range(4, 8):
			var p := center + _rand_pos_in(5.5)
			var s := rng.randf_range(0.55, 1.05)
			var gy := _ground_height(p.x, p.y)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
			trunks.append(Transform3D(b, Vector3(p.x, gy, p.y)))
			canopies.append(Transform3D(b, Vector3(p.x, gy + 2.5 * s, p.y)))
	_batch(trunk, bark, trunks, true, 310.0)
	_batch(canopy, canopy_mat, canopies, true, 310.0)

func _build_rocks() -> void:
	var rock := SphereMesh.new()
	rock.radius = 0.55
	rock.height = 0.8
	rock.radial_segments = 7
	rock.rings = 4

	var rock_mat := _shader_mat("res://assets/shaders/rock.gdshader", {
		"rock_color": rock_color,
		"moss_color": tuft_color,
		"mottle_scale": 3.0,
	})

	var transforms: Array[Transform3D] = []
	for i in rock_count:
		var p := _rand_pos_in(scatter_radius)
		var pos := Vector3(p.x, _ground_height(p.x, p.y) + rng.randf_range(-0.18, -0.04), p.y)
		var s := rng.randf_range(0.4, 1.9 if p.length() > 40.0 else 1.3)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(s, s * rng.randf_range(0.35, 0.7), s))
		transforms.append(Transform3D(b, pos))

	_batch(rock, rock_mat, transforms, true, 310.0)

## Low leafy bushes for mid-distance texture
func _build_bushes() -> void:
	var bush := SphereMesh.new()
	bush.radius = 0.42
	bush.height = 0.55
	bush.radial_segments = 6
	bush.rings = 3
	var mat := _shader_mat("res://assets/shaders/canopy.gdshader", {
		"canopy_color": tuft_color.darkened(0.15),
		"highlight_color": tuft_color.lightened(0.4),
	})
	var transforms: Array[Transform3D] = []
	for i in bush_count:
		var p := _rand_pos_in(scatter_radius * 0.85)
		if p.distance_to(Vector2(-16, 10)) < 6.0:
			continue
		var s := rng.randf_range(0.6, 1.5)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(s, s * rng.randf_range(0.5, 0.8), s))
		transforms.append(Transform3D(b,
			Vector3(p.x, _ground_height(p.x, p.y) + 0.08, p.y)))
	_batch(bush, mat, transforms, true, 310.0)

## Tiny ground stones — cheap detail that sells scale
func _build_pebbles() -> void:
	var pebble := SphereMesh.new()
	pebble.radius = 0.09
	pebble.height = 0.12
	pebble.radial_segments = 5
	pebble.rings = 2
	var mat := _mat(rock_color.lightened(0.15))
	var transforms: Array[Transform3D] = []
	for i in pebble_count:
		var p := _rand_pos_in(scatter_radius)
		var s := rng.randf_range(0.4, 1.4)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(s, s * 0.55, s * rng.randf_range(0.8, 1.2)))
		transforms.append(Transform3D(b,
			Vector3(p.x, _ground_height(p.x, p.y) - 0.02, p.y)))
	_batch(pebble, mat, transforms, false, 310.0)

func _build_pale_path() -> void:
	var stone := BoxMesh.new()
	stone.size = Vector3(0.9, 0.12, 1.25)
	stone.material = _shader_mat("res://assets/shaders/rock.gdshader", {
		"rock_color": Color(0.34, 0.40, 0.32),
		"moss_color": tuft_color,
		"mottle_scale": 6.0,
		"moss_amount": 0.30,
		"emission_color": Color(0.18, 0.28, 0.18),
		"emission_energy": 0.25,
	})

	var transforms: Array[Transform3D] = []
	var start := Vector3(-16.0, 0.08, 10.0)
	var finish := Vector3(-6.4, 0.08, 3.15)
	var forward := (finish - start).normalized()
	var angle := atan2(forward.x, forward.z)
	var path_basis := Basis(Vector3.UP, angle)
	for i in 18:
		var t := i / 17.0
		var center := start.lerp(finish, t)
		center += Vector3(0.0, 0.0, sin(t * PI) * 0.35)
		for side in [-1.0, 1.0]:
			var local_offset := Vector3(side * rng.randf_range(0.35, 0.7), 0.0, rng.randf_range(-0.18, 0.18))
			var scale := rng.randf_range(0.75, 1.15)
			var stone_pos := center + path_basis * local_offset
			stone_pos.y = _ground_height(stone_pos.x, stone_pos.z) + 0.08
			var basis := path_basis.scaled(Vector3(scale, rng.randf_range(0.8, 1.1), scale))
			transforms.append(Transform3D(basis, stone_pos))

	# Long pilgrim road toward the boss arena stone
	var arena := Vector3(-16.0, 0.08, -10.0)
	var to_arena := (arena - start).normalized()
	var arena_basis := Basis(Vector3.UP, atan2(to_arena.x, to_arena.z))
	for i in 46:
		var center := start.lerp(arena, float(i) / 45.0)
		center += Vector3(sin(float(i) * 0.7) * 0.8, 0.0, cos(float(i) * 0.5) * 0.5)
		for side in [-1.0, 1.0]:
			var off := Vector3(side * rng.randf_range(0.4, 0.85), 0.0,
				rng.randf_range(-0.2, 0.2))
			var sp := center + arena_basis * off
			sp.y = _ground_height(sp.x, sp.z) + 0.07
			transforms.append(Transform3D(
				arena_basis.scaled(Vector3.ONE * rng.randf_range(0.7, 1.2)), sp))

	_batch(stone, stone.material, transforms, false, 310.0)

func _build_tufts() -> void:
	var tuft := CylinderMesh.new()
	tuft.top_radius = 0.03
	tuft.bottom_radius = 0.09
	tuft.height = 0.6
	tuft.radial_segments = 3
	tuft.rings = 1

	var grass := ShaderMaterial.new()
	grass.shader = load("res://assets/shaders/grass_blade.gdshader")
	grass.set_shader_parameter("blade_color", tuft_color)
	grass.set_shader_parameter("tip_color", tuft_color.lightened(0.45))
	grass.set_shader_parameter("blade_height", 0.6)

	var transforms: Array[Transform3D] = []
	for i in tuft_count:
		var p := _rand_pos_in(scatter_radius)
		var b := Basis.from_euler(Vector3(
			rng.randf_range(-0.2, 0.2),
			rng.randf() * TAU,
			rng.randf_range(-0.2, 0.2)))
		transforms.append(Transform3D(b, Vector3(p.x, _ground_height(p.x, p.y), p.y)))

	_batch(tuft, grass, transforms, false, 310.0)

func _build_mushrooms() -> void:
	var lights_node := get_parent().get_node_or_null("WarmLights")
	if lights_node == null:
		return

	var stem := CylinderMesh.new()
	stem.top_radius = 0.05
	stem.bottom_radius = 0.08
	stem.height = 0.3
	stem.radial_segments = 5
	stem.rings = 1

	var cap := SphereMesh.new()
	cap.radius = 0.18
	cap.height = 0.22
	cap.radial_segments = 7
	cap.rings = 3

	var stems: Array[Transform3D] = []
	var caps: Array[Transform3D] = []
	for light in lights_node.get_children():
		if light is OmniLight3D:
			var base := Vector3(light.position.x, 0.0, light.position.z)
			for j in rng.randi_range(3, 5):
				var p := base + Vector3(
					rng.randf_range(-2.2, 2.2), 0.0,
					rng.randf_range(-2.2, 2.2))
				var ground_y := _ground_height(p.x, p.z)
				var s := rng.randf_range(0.6, 1.1)
				stems.append(Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(p.x, ground_y, p.z)))
				caps.append(Transform3D(
					Basis().scaled(Vector3(s, s * 0.6, s)),
					Vector3(p.x, ground_y + 0.26 * s, p.z)))

	_batch(stem, _mat(Color(0.32, 0.30, 0.26)), stems, false)
	_batch(cap, _mat(mushroom_cap_color, Color(0.45, 0.85, 0.50), 1.1), caps, false)

## Ancient ruin circle: broken columns of a forgotten rite-ground (NE reach)
func _build_ruins() -> void:
	var center := Vector2(38.0, -32.0)
	if center.length() > scatter_radius:
		center = center.normalized() * scatter_radius * 0.82
	var column := CylinderMesh.new()
	column.top_radius = 0.42
	column.bottom_radius = 0.5
	column.height = 2.6
	column.radial_segments = 9
	column.rings = 2
	var broken := CylinderMesh.new()
	broken.top_radius = 0.44
	broken.bottom_radius = 0.52
	broken.height = 0.9
	broken.radial_segments = 9
	broken.rings = 1
	var marble := _shader_mat("res://assets/shaders/rock.gdshader", {
		"rock_color": Color(0.52, 0.50, 0.44),
		"moss_color": tuft_color,
		"mottle_scale": 2.2,
		"moss_amount": 0.5,
	})
	var standing: Array[Transform3D] = []
	var fallen: Array[Transform3D] = []
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var p := center + Vector2(cos(ang), sin(ang)) * 6.5
		var gy := _ground_height(p.x, p.y)
		var ruined := i % 3 == 0
		var b := Basis(Vector3.UP, ang + rng.randf_range(-0.1, 0.1))
		if ruined:
			var tilt := Basis(Vector3(1, 0, 0), rng.randf_range(0.9, 1.35)) * b
			fallen.append(Transform3D(tilt, Vector3(p.x, gy + 0.35, p.y)))
		else:
			standing.append(Transform3D(b, Vector3(p.x, gy, p.y)))
	_batch(column, marble, standing, true, 310.0)
	_batch(broken, marble, fallen, true, 310.0)

	# Cracked plaza floor under the columns
	var slab := BoxMesh.new()
	slab.size = Vector3(1.6, 0.14, 1.6)
	slab.material = marble
	var slabs: Array[Transform3D] = []
	for gx in range(-2, 3):
		for gz in range(-2, 3):
			var p := center + Vector2(gx * 1.75, gz * 1.75)
			if Vector2(gx, gz).length() > 2.4:
				continue
			var gy := _ground_height(p.x, p.y)
			slabs.append(Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU),
				Vector3(p.x, gy + 0.02, p.y)))
	_batch(slab, slab.material, slabs, false, 310.0)

## Lit torches marking the road: near spawn, mid-road, arena mouth
func _build_torches() -> void:
	var post := CylinderMesh.new()
	post.top_radius = 0.06
	post.bottom_radius = 0.09
	post.height = 1.7
	post.radial_segments = 6
	post.rings = 1
	var bowl := SphereMesh.new()
	bowl.radius = 0.16
	bowl.height = 0.24
	bowl.radial_segments = 7
	bowl.rings = 3
	var wood := _mat(Color(0.14, 0.10, 0.07))
	var iron := _mat(Color(0.20, 0.17, 0.13))
	var flame_mat := _mat(Color(1.0, 0.62, 0.20), Color(1.0, 0.48, 0.08), 2.4)

	var spots := [
		Vector3(-11.2, 0, 6.6), Vector3(-19.8, 0, 8.2),          # camp mouth
		Vector3(-12.4, 0, 1.2), Vector3(-19.0, 0, -1.8),         # mid road
		Vector3(-13.6, 0, -6.4), Vector3(-18.2, 0, -8.6),        # arena approach
	]
	var posts: Array[Transform3D] = []
	var bowls: Array[Transform3D] = []
	for spot in spots:
		var gy := _ground_height(spot.x, spot.z)
		posts.append(Transform3D(Basis(), Vector3(spot.x, gy + 0.85, spot.z)))
		bowls.append(Transform3D(Basis(), Vector3(spot.x, gy + 1.76, spot.z)))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.62, 0.25)
		light.light_energy = 1.5
		light.omni_range = 7.5
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		light.position = Vector3(spot.x, gy + 2.0, spot.z)
		add_child(light)
		# Flicker driver
		var flicker := LightFlicker.new()
		flicker.base_energy = 1.5
		light.add_child(flicker)
	_batch(post, wood, posts, true, 310.0)
	_batch(bowl, flame_mat, bowls, false, 310.0)

## Tiny helper node so torch flames breathe without per-frame GD cost
class LightFlicker:
	extends Node
	var base_energy := 1.5
	var _t := randf() * 10.0
	func _process(delta: float) -> void:
		_t += delta
		var light := get_parent() as OmniLight3D
		if light:
			light.light_energy = base_energy * (0.86 + 0.14 * sin(_t * 9.0) \
				+ 0.06 * sin(_t * 23.7))

# === Realm signature props ===

## BRAMBLEWOOD: thorn arches straddling the pilgrim road — living gate
## hoops woven from dark briar, announcing this realm's tangled character.
func _build_thorn_arches() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 1.68
	ring.outer_radius = 2.12
	ring.rings = 10
	ring.ring_segments = 6
	var briar := _shader_mat("res://assets/shaders/bark.gdshader", {
		"bark_color": Color(0.09, 0.075, 0.05),
	})
	var transforms: Array[Transform3D] = []
	var spots := [
		Vector2(-16.0, 5.4), Vector2(-15.1, 1.1), Vector2(-13.8, -2.8),
		Vector2(-15.3, -6.6), Vector2(-11.6, 5.0), Vector2(-18.8, 3.2),
	]
	for i in spots.size():
		var s: Vector2 = spots[i]
		var gy := _ground_height(s.x, s.y)
		var b := Basis(Vector3(1, 0, 0), PI / 2.0) \
			* Basis(Vector3.UP, rng.randf_range(-0.35, 0.35))
		b = b.scaled(Vector3.ONE * rng.randf_range(0.9, 1.25))
		transforms.append(Transform3D(b, Vector3(s.x, gy + 1.35, s.y)))
	_batch(ring, briar, transforms, true, 310.0)

## MISTFEN: swaying reeds in the damp hollows and pale drowned stones.
func _build_reeds() -> void:
	var reed := CylinderMesh.new()
	reed.top_radius = 0.012
	reed.bottom_radius = 0.045
	reed.height = 1.05
	reed.radial_segments = 4
	reed.rings = 1
	var grass := ShaderMaterial.new()
	grass.shader = load("res://assets/shaders/grass_blade.gdshader")
	grass.set_shader_parameter("blade_color", Color(0.28, 0.40, 0.34))
	grass.set_shader_parameter("tip_color", Color(0.55, 0.72, 0.60))
	grass.set_shader_parameter("blade_height", 1.05)
	var transforms: Array[Transform3D] = []
	var placed := 0
	var tries := 0
	while placed < 340 and tries < 1400:
		tries += 1
		var p := _rand_pos_in(scatter_radius)
		if p.length() < 12.0:
			continue
		var gy := _ground_height(p.x, p.y)
		if gy > -0.22:  # reeds crowd only the damp hollows
			continue
		var b := Basis.from_euler(Vector3(
			rng.randf_range(-0.12, 0.12),
			rng.randf() * TAU,
			rng.randf_range(-0.12, 0.12)))
		b = b.scaled(Vector3.ONE * rng.randf_range(0.55, 1.35))
		transforms.append(Transform3D(b, Vector3(p.x, gy + 0.42, p.y)))
		placed += 1
	_batch(reed, grass, transforms, false, 310.0)

func _build_drowned_stones() -> void:
	var stone := SphereMesh.new()
	stone.radius = 0.62
	stone.height = 0.9
	stone.radial_segments = 8
	stone.rings = 4
	var wet := _shader_mat("res://assets/shaders/rock.gdshader", {
		"rock_color": Color(0.44, 0.50, 0.53),
		"moss_color": Color(0.22, 0.32, 0.30),
		"mottle_scale": 2.6,
		"moss_amount": 0.45,
	})
	var transforms: Array[Transform3D] = []
	for i in 48:
		var p := _rand_pos_in(scatter_radius * 0.9)
		if p.length() < 14.0:
			continue
		var gy := _ground_height(p.x, p.y)
		var s := rng.randf_range(0.5, 1.5)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(s, s * rng.randf_range(0.4, 0.65), s))
		# Half-sunk: pushed down so only the crown breaks the fen floor
		transforms.append(Transform3D(b,
			Vector3(p.x, gy - 0.18 * s, p.y)))
	_batch(stone, wet, transforms, true, 310.0)

## HEARTWOOD: charred spires with ember seams and a slow drifting mote field.
func _build_charred_spires() -> void:
	var spire := CylinderMesh.new()
	spire.top_radius = 0.09
	spire.bottom_radius = 0.52
	spire.height = 4.6
	spire.radial_segments = 8
	spire.rings = 2
	var charred := _mat(Color(0.07, 0.06, 0.055))
	charred.roughness = 0.95

	var seam := CylinderMesh.new()
	seam.top_radius = 0.20
	seam.bottom_radius = 0.30
	seam.height = 0.5
	seam.radial_segments = 8
	seam.rings = 1
	var ember := _mat(Color(0.55, 0.16, 0.04), Color(1.0, 0.38, 0.08), 1.8)

	var trunks: Array[Transform3D] = []
	var seams: Array[Transform3D] = []
	var tall_spots: Array[Vector3] = []
	for i in 16:
		var p := _rand_pos_in(scatter_radius * 0.62)
		if p.length() < 19.0 or Vector2(p.x, p.y).distance_to(Vector2(-16, 10)) < 13.0:
			continue
		var gy := _ground_height(p.x, p.y)
		var s := rng.randf_range(0.7, 1.5)
		var b := Basis.from_euler(Vector3(
			rng.randf_range(-0.06, 0.06),
			rng.randf() * TAU,
			rng.randf_range(-0.06, 0.06))).scaled(Vector3(s, s, s))
		trunks.append(Transform3D(b, Vector3(p.x, gy + 2.1 * s, p.y)))
		# Ember seam bleeding through the bark at a random height
		var seam_y := gy + rng.randf_range(0.7, 2.6) * s
		seams.append(Transform3D(
			Basis().scaled(Vector3.ONE * s * rng.randf_range(0.7, 1.1)),
			Vector3(p.x, seam_y, p.y)))
		if i % 3 == 0 and tall_spots.size() < 5:
			tall_spots.append(Vector3(p.x, gy + 2.6 * s, p.y))
	_batch(spire, charred, trunks, true, 310.0)
	_batch(seam, ember, seams, false, 310.0)

	for spot in tall_spots:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.45, 0.15)
		light.light_energy = 1.3
		light.omni_range = 7.0
		light.omni_attenuation = 1.6
		light.shadow_enabled = false
		light.position = spot
		add_child(light)

func _build_ember_motes() -> void:
	var motes := GPUParticles3D.new()
	motes.name = "EmberMotes"
	motes.amount = 56
	motes.lifetime = 5.0
	motes.preprocess = 5.0
	motes.local_coords = false
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(34.0, 3.5, 34.0)
	proc.direction = Vector3.UP
	proc.spread = 24.0
	proc.initial_velocity_min = 0.15
	proc.initial_velocity_max = 0.55
	proc.gravity = Vector3(0, 0.12, 0)
	proc.scale_min = 0.35
	proc.scale_max = 0.9
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.55, 0.18, 0.0))
	ramp.set_color(1, Color(1.0, 0.42, 0.10, 0.75))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	proc.color_ramp = ramp_tex
	motes.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = CombatFx.radial_glow_texture()
	quad.material = mat
	motes.draw_pass_1 = quad
	add_child(motes)

## MOONFEN: oversized glowcap clusters breathing cold cyan light.
func _build_glowcaps() -> void:
	var stem := CylinderMesh.new()
	stem.top_radius = 0.07
	stem.bottom_radius = 0.12
	stem.height = 0.52
	stem.radial_segments = 6
	stem.rings = 1
	var cap := SphereMesh.new()
	cap.radius = 0.30
	cap.height = 0.36
	cap.radial_segments = 9
	cap.rings = 4

	var stems: Array[Transform3D] = []
	var caps: Array[Transform3D] = []
	var clusters := 9
	for c in clusters:
		var center := _rand_pos_in(scatter_radius * 0.55)
		if center.length() < 10.0 \
				or center.distance_to(Vector2(-7.0, -4.0)) < 7.0:
			continue
		for j in rng.randi_range(4, 7):
			var p := center + _rand_pos_in(2.6)
			var gy := _ground_height(p.x, p.y)
			var s := rng.randf_range(0.7, 1.6)
			stems.append(Transform3D(Basis().scaled(Vector3.ONE * s),
				Vector3(p.x, gy, p.y)))
			caps.append(Transform3D(
				Basis().scaled(Vector3(s, s * 0.6, s)),
				Vector3(p.x, gy + 0.46 * s, p.y)))

	_batch(stem, _mat(Color(0.58, 0.56, 0.66)), stems, false)
	_batch(cap, _mat(Color(0.20, 0.42, 0.55), Color(0.45, 0.85, 1.0), 1.7),
		caps, false)
