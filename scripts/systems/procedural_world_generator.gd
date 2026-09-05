extends Node
class_name ProceduralWorldGenerator

## === Procedural World Generator ===
## Generates a dynamic, replayable world layout each session.
## Seeded so the same save seed reproduces the same world.
##
## What it spawns:
##   - TerrainRelief heightmap parameters (passed to terrain node)
##   - Rock clusters (MeshInstance3D static props)
##   - Tree silhouettes (per-realm: oak/willow/petrified)
##   - Moss patches / ember vents (per-realm atmosphere)
##   - EncounterZone triggers (enemy pack zones)
##   - ResourceGatherNode pickups (realm materials)
##   - ChestNode placements (common/rare, gated by stage)
##   - Landmark markers (discoverable named locations)
##   - Altar / boss spawn anchor
##
## Usage in WorldManager._ready():
##   var pwg := ProceduralWorldGenerator.new()
##   pwg.name = "ProceduralWorldGenerator"
##   add_child(pwg)
##   pwg.generate(self, realm_id, world_seed)

signal generation_complete(stats: Dictionary)

## Config
@export var rock_count           : int   = 22
@export var tree_count           : int   = 28
@export var encounter_zone_count : int   = 6
@export var resource_node_count  : int   = 14
@export var chest_count          : int   = 4
@export var landmark_count       : int   = 3
@export var world_radius         : float = 38.0

var _rng   : RandomNumberGenerator = RandomNumberGenerator.new()
var _world : Node3D = null
var _realm : String = "bramblewood"
var _seed  : int    = 0

# ─── Public API ───────────────────────────────────────────────────────────────

func generate(world_manager: Node3D, realm_id: String, world_seed: int = 0) -> void:
	_world = world_manager
	_realm = realm_id
	_seed  = world_seed if world_seed != 0 else randi()
	_rng.seed = _seed

	# WorldState stores seed for save persistence
	var ws := get_node_or_null("/root/WorldState")
	if ws != null:
		ws.call("set_flag", "world_seed", _seed) if ws.has_method("set_flag") else null

	_generate_terrain_variation()
	_place_rocks()
	_place_trees()
	_place_atmosphere_props()
	_place_encounter_zones()
	_place_resource_nodes()
	_place_chests()
	_place_landmarks()
	_place_boss_altar()

	generation_complete.emit({
		"realm":      _realm,
		"seed":       _seed,
		"rocks":      rock_count,
		"trees":      tree_count,
		"encounters": encounter_zone_count,
		"resources":  resource_node_count,
		"chests":     chest_count,
	})

# ─── Terrain variation ────────────────────────────────────────────────────────

func _generate_terrain_variation() -> void:
	# If a terrain node exists, pass heightmap parameters
	var terrain := _world.get_node_or_null("Terrain")
	if terrain == null:
		return
	if terrain.has_method("set_heightmap_params"):
		terrain.call("set_heightmap_params", {
			"seed":         _seed,
			"amplitude":    _realm_terrain_amplitude(),
			"frequency":    0.12 + _rng.randf_range(-0.02, 0.02),
			"octaves":      4,
			"water_level":  -0.15 if _realm == "mistfen" else -99.0,
		})

func _realm_terrain_amplitude() -> float:
	match _realm:
		"bramblewood": return 1.8
		"mistfen":     return 0.6   # flat with water
		"heartwood":   return 3.2   # rugged volcanic
		"moonfen":     return 1.2
		_:             return 2.0

# ─── Rocks ────────────────────────────────────────────────────────────────────

func _place_rocks() -> void:
	var host := _get_or_create("StaticProps_Rocks")
	var rock_col := _realm_rock_color()
	for i in rock_count:
		var pos := _rand_pos(world_radius * 0.85)
		# Skip too close to player spawn
		if pos.length() < 4.5: continue
		var cluster_count := _rng.randi_range(1, 4)
		for c in cluster_count:
			var rock := MeshInstance3D.new()
			rock.name = "Rock_%d_%d" % [i, c]
			var sm := SphereMesh.new()
			sm.radius         = _rng.randf_range(0.30, 0.95)
			sm.height         = sm.radius * _rng.randf_range(0.55, 1.1)
			sm.radial_segments = 8; sm.rings = 5
			rock.mesh = sm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = rock_col
			mat.roughness    = _rng.randf_range(0.80, 0.96)
			rock.material_override = mat
			rock.global_position = _world.global_position + \
				Vector3(pos.x + _rng.randf_range(-0.8, 0.8),
					_rng.randf_range(-0.15, 0.08),
					pos.y + _rng.randf_range(-0.8, 0.8))
			rock.rotation = Vector3(
				_rng.randf_range(-0.15, 0.15),
				_rng.randf_range(0, TAU),
				_rng.randf_range(-0.12, 0.12))
			rock.scale = Vector3.ONE * _rng.randf_range(0.75, 1.35)
			host.add_child(rock)
			# Static body for collision
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var sp := SphereShape3D.new()
			sp.radius = sm.radius * 0.88
			cs.shape  = sp
			sb.global_position = rock.global_position
			host.add_child(sb)
			sb.add_child(cs)

func _realm_rock_color() -> Color:
	match _realm:
		"mistfen":   return Color(0.22, 0.28, 0.30)
		"heartwood": return Color(0.18, 0.10, 0.08)
		"moonfen":   return Color(0.30, 0.28, 0.38)
		_:           return Color(0.28, 0.24, 0.20)

# ─── Trees ────────────────────────────────────────────────────────────────────

func _place_trees() -> void:
	var host := _get_or_create("StaticProps_Trees")
	for i in tree_count:
		var pos := _rand_ring(6.0, world_radius * 0.90)
		_build_tree(host, _world.global_position + Vector3(pos.x, 0, pos.y), i)

func _build_tree(host: Node3D, world_pos: Vector3, idx: int) -> void:
	var root := Node3D.new()
	root.name = "Tree_%d" % idx
	host.add_child(root)
	root.global_position = world_pos
	root.rotation.y = _rng.randf_range(0, TAU)

	var trunk_h := _rng.randf_range(2.0, 5.5)
	var trunk   := MeshInstance3D.new()
	var tcm     := CylinderMesh.new()
	tcm.bottom_radius = _rng.randf_range(0.12, 0.28)
	tcm.top_radius    = tcm.bottom_radius * _rng.randf_range(0.55, 0.78)
	tcm.height        = trunk_h
	tcm.radial_segments = 7
	trunk.mesh = tcm
	trunk.material_override = _trunk_mat()
	trunk.position.y = trunk_h * 0.5
	root.add_child(trunk)

	match _realm:
		"heartwood":
			# Petrified tree — no canopy, just cracked stone trunk + ember glow
			var mat := trunk.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = Color(0.18, 0.10, 0.08)
				mat.emission_enabled = true
				mat.emission = Color(0.85, 0.28, 0.06)
				mat.emission_energy_multiplier = 0.15
		"mistfen":
			# Dead willow — drooping canopy
			for branch in 5:
				var bang := TAU * float(branch) / 5.0
				var blen := _rng.randf_range(1.2, 2.2)
				var b    := MeshInstance3D.new()
				var bcm  := CylinderMesh.new()
				bcm.bottom_radius = 0.045; bcm.top_radius = 0.018; bcm.height = blen; bcm.radial_segments = 5
				b.mesh = bcm; b.material_override = _trunk_mat()
				b.position = Vector3(cos(bang)*0.55, trunk_h * 0.85, sin(bang)*0.55)
				b.rotation = Vector3(0.65, bang, 0)
				root.add_child(b)
		_:
			# Bramblewood oak — round canopy
			var canopy := MeshInstance3D.new()
			var csm    := SphereMesh.new()
			csm.radius = _rng.randf_range(1.0, 2.2)
			csm.height = csm.radius * _rng.randf_range(0.75, 1.2)
			csm.radial_segments = 10
			canopy.mesh = csm
			canopy.material_override = _canopy_mat()
			canopy.position.y = trunk_h + csm.radius * 0.55
			root.add_child(canopy)

func _trunk_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.22, 0.16, 0.10); m.roughness = 0.90; return m

func _canopy_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	match _realm:
		"moonfen": m.albedo_color = Color(0.22, 0.28, 0.38)
		_:         m.albedo_color = Color(0.18, 0.36, 0.18)
	m.roughness = 0.85; return m

# ─── Atmosphere props ─────────────────────────────────────────────────────────

func _place_atmosphere_props() -> void:
	var host := _get_or_create("StaticProps_Atmosphere")
	match _realm:
		"mistfen":   _place_lily_pads(host); _place_reeds(host)
		"heartwood": _place_ember_vents(host)
		"moonfen":   _place_crystal_shards(host)
		_:           _place_mushrooms(host); _place_moss_patches(host)

func _place_mushrooms(host: Node3D) -> void:
	for i in 18:
		var pos := _rand_pos(world_radius * 0.80)
		var shroom := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = _rng.randf_range(0.18, 0.42)
		sm.bottom_radius = 0.03; sm.height = 0.06; sm.radial_segments = 8
		shroom.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(_rng.randf_range(0.55, 0.85), _rng.randf_range(0.20, 0.35), 0.12)
		mat.roughness = 0.72
		shroom.material_override = mat
		shroom.global_position = _world.global_position + Vector3(pos.x, 0.03, pos.y)
		host.add_child(shroom)

func _place_moss_patches(host: Node3D) -> void:
	for i in 12:
		var pos := _rand_pos(world_radius * 0.75)
		var moss := MeshInstance3D.new()
		var qm   := QuadMesh.new()
		qm.size = Vector2(_rng.randf_range(0.6, 2.0), _rng.randf_range(0.5, 1.8))
		moss.mesh = qm
		var mat  := StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.36, 0.16, 0.88)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness    = 0.95
		moss.material_override = mat
		moss.global_position = _world.global_position + Vector3(pos.x, 0.01, pos.y)
		moss.rotation.x = -PI * 0.5
		moss.rotation.z = _rng.randf_range(0, TAU)
		host.add_child(moss)

func _place_lily_pads(host: Node3D) -> void:
	for i in 10:
		var pos := _rand_pos(world_radius * 0.65)
		var lp := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(_rng.randf_range(0.4, 1.0), _rng.randf_range(0.4, 1.0))
		lp.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.42, 0.22, 0.82)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lp.material_override = mat
		lp.global_position = _world.global_position + Vector3(pos.x, 0.04, pos.y)
		lp.rotation.x = -PI * 0.5
		host.add_child(lp)

func _place_reeds(host: Node3D) -> void:
	for i in 16:
		var pos := _rand_pos(world_radius * 0.70)
		var h   := _rng.randf_range(0.6, 1.8)
		var r   := MeshInstance3D.new()
		var cm  := CylinderMesh.new()
		cm.bottom_radius = 0.018; cm.top_radius = 0.025; cm.height = h; cm.radial_segments = 4
		r.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.38, 0.46, 0.28); mat.roughness = 0.85
		r.material_override = mat
		r.global_position = _world.global_position + Vector3(pos.x, h*0.5, pos.y)
		r.rotation = Vector3(_rng.randf_range(-0.18, 0.18), _rng.randf_range(0, TAU), _rng.randf_range(-0.15, 0.15))
		host.add_child(r)

func _place_ember_vents(host: Node3D) -> void:
	for i in 8:
		var pos := _rand_ring(3.0, world_radius * 0.75)
		var vent := GPUParticles3D.new()
		vent.amount = 22; vent.lifetime = 1.2; vent.emitting = true
		var pm  := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0); pm.spread = 28.0
		pm.initial_velocity_min = 1.2; pm.initial_velocity_max = 3.5
		pm.gravity = Vector3(0, -0.8, 0)
		pm.scale_min = 0.06; pm.scale_max = 0.18
		pm.color = Color(1.0, 0.42, 0.10)
		vent.process_material = pm
		vent.global_position = _world.global_position + Vector3(pos.x, 0.08, pos.y)
		host.add_child(vent)

func _place_crystal_shards(host: Node3D) -> void:
	for i in 12:
		var pos := _rand_pos(world_radius * 0.80)
		for c in _rng.randi_range(2, 5):
			var shard := MeshInstance3D.new()
			var cm    := CylinderMesh.new()
			cm.top_radius = 0.0; cm.bottom_radius = _rng.randf_range(0.06, 0.16); cm.height = _rng.randf_range(0.35, 1.0); cm.radial_segments = 6
			shard.mesh = cm
			var mat   := StandardMaterial3D.new()
			mat.albedo_color = Color(0.55, 0.72, 0.95, 0.80)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.08; mat.metallic = 0.55
			mat.emission_enabled = true; mat.emission = Color(0.30, 0.50, 0.90)
			mat.emission_energy_multiplier = 0.55
			shard.material_override = mat
			shard.global_position = _world.global_position + \
				Vector3(pos.x + _rng.randf_range(-0.5, 0.5), cm.height*0.5, pos.y + _rng.randf_range(-0.5, 0.5))
			shard.rotation = Vector3(_rng.randf_range(-0.2, 0.2), _rng.randf_range(0, TAU), _rng.randf_range(-0.15, 0.15))
			host.add_child(shard)

# ─── Encounter zones ──────────────────────────────────────────────────────────

func _place_encounter_zones() -> void:
	var gs    := get_node_or_null("/root/GameState")
	var stage := int(gs.get("current_stage") if gs and gs.get("current_stage") != null else 0)
	var host  := _get_or_create("EncounterZones")
	var tier_weights := _tier_weights(stage)

	for i in encounter_zone_count:
		var pos   := _rand_ring(8.0, world_radius * 0.80)
		var tier  := _weighted_tier(tier_weights)
		var zone := EncounterZone.new() if ClassDB.class_exists("EncounterZone") else Node3D.new()
		zone.name = "EncounterZone_%d" % i
		host.add_child(zone)
		zone.global_position = _world.global_position + Vector3(pos.x, 0, pos.y)
		if zone.has_method("setup"):
			zone.call("setup", _realm, tier, stage)
		elif zone.get("realm_id") != null:
			zone.set("realm_id", _realm)
			zone.set("tier",     tier)
			zone.set("stage",    stage)

func _tier_weights(stage: int) -> Dictionary:
	match stage:
		0: return { "normal": 1.0, "hard": 0.0, "elite": 0.0 }
		1: return { "normal": 0.7, "hard": 0.3, "elite": 0.0 }
		2: return { "normal": 0.5, "hard": 0.4, "elite": 0.1 }
		_: return { "normal": 0.3, "hard": 0.5, "elite": 0.2 }

func _weighted_tier(weights: Dictionary) -> String:
	var r := _rng.randf()
	var cumulative := 0.0
	for tier in weights:
		cumulative += float(weights[tier])
		if r <= cumulative:
			return tier
	return "normal"

# ─── Resource nodes ───────────────────────────────────────────────────────────

func _place_resource_nodes() -> void:
	var host    := _get_or_create("ResourceNodes")
	var mats    := _realm_materials()
	for i in resource_node_count:
		var pos := _rand_ring(4.0, world_radius * 0.82)
		var mat_id: String = mats[i % mats.size()]
		var rn := ResourceGatherNode.new() if ClassDB.class_exists("ResourceGatherNode") else Node3D.new()
		rn.name = "ResourceNode_%d" % i
		host.add_child(rn)
		rn.global_position = _world.global_position + Vector3(pos.x, 0, pos.y)
		if rn.has_method("setup"):
			rn.call("setup", mat_id, 1, _realm)
		elif rn.get("material_id") != null:
			rn.set("material_id",   mat_id)
			rn.set("quantity_min",  1)
			rn.set("quantity_max",  3)
			rn.set("realm_id",      _realm)

func _realm_materials() -> Array:
	match _realm:
		"mistfen":   return ["fen_reed", "spore_dust", "moss_fiber"]
		"heartwood": return ["emberstone", "monster_core", "iron_shard"]
		"moonfen":   return ["moonmoss", "crystal_fragment", "spore_dust"]
		_:           return ["bramble_wood", "moss_fiber", "beast_hide", "iron_shard"]

# ─── Chests ───────────────────────────────────────────────────────────────────

func _place_chests() -> void:
	var host  := _get_or_create("Chests")
	var gs    := get_node_or_null("/root/GameState")
	var stage := int(gs.get("current_stage") if gs and gs.get("current_stage") != null else 0)
	for i in chest_count:
		var pos  := _rand_ring(6.0, world_radius * 0.72)
		var tier := "common"
		if i == 0 and stage >= 2:
			tier = "rare"
		elif i == 0 and stage >= 3:
			tier = "boss"
		var chest := ChestNode.new() if ClassDB.class_exists("ChestNode") else Node3D.new()
		chest.name = "Chest_%d" % i
		host.add_child(chest)
		chest.global_position = _world.global_position + Vector3(pos.x, 0, pos.y)
		if chest.get("chest_tier") != null:
			chest.set("chest_tier", tier)
			chest.set("realm_id",   _realm)

# ─── Landmarks ────────────────────────────────────────────────────────────────

func _place_landmarks() -> void:
	var host   := _get_or_create("Landmarks")
	var names  := _realm_landmark_names()
	for i in landmark_count:
		var pos  := _rand_ring(5.0, world_radius * 0.65)
		var lname: String = names[i % names.size()]
		_build_landmark(host, _world.global_position + Vector3(pos.x, 0, pos.y), lname, i)

func _realm_landmark_names() -> Array:
	match _realm:
		"mistfen":   return ["Sunken Grotto", "Reed Hollow", "The Still Water"]
		"heartwood": return ["Ember Spire", "Ashen Vault", "The Smelted Ring"]
		"moonfen":   return ["Moonrise Arch", "The Drift Pool", "Starwrack Hollow"]
		_:           return ["Whisper Stone", "Old Root Clearing", "The Lantern Post"]

func _build_landmark(host: Node3D, world_pos: Vector3, lname: String, idx: int) -> void:
	var root := Node3D.new()
	root.name = "Landmark_%d" % idx
	host.add_child(root)
	root.global_position = world_pos

	# Stone marker pillar
	var pillar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = 0.25; cm.top_radius = 0.20; cm.height = 1.4; cm.radial_segments = 8
	pillar.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.24, 0.20); mat.roughness = 0.90
	pillar.material_override = mat
	pillar.position.y = 0.7
	root.add_child(pillar)

	# Name label (billboard)
	var label := Label3D.new()
	label.text = lname
	label.font_size = 44
	label.modulate = Color(0.88, 0.80, 0.55)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 1.7
	root.add_child(label)

	# Glow light
	var light := OmniLight3D.new()
	light.light_color = Color(0.85, 0.75, 0.45)
	light.light_energy = 0.55; light.omni_range = 3.5
	light.position.y = 1.4
	root.add_child(light)

	# Discovery trigger
	var area := Area3D.new()
	area.collision_layer = 0; area.collision_mask = 1 << 0
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new(); sp.radius = 2.5
	cs.shape = sp; area.add_child(cs)
	root.add_child(area)
	var landmark_id := lname.to_lower().replace(" ", "_")
	area.body_entered.connect(func(body: Node3D):
		if body.is_in_group("player"):
			var sm := get_node_or_null("/root/StoryManager")
			var ws := get_node_or_null("/root/WorldState")
			if ws and ws.has_method("discover_landmark"):
				if ws.call("discover_landmark", landmark_id):
					FloatingText.spawn_on_entity(body, lname, Color(0.88, 0.80, 0.55))
					if sm: sm.call("trigger_event", "landmark_" + landmark_id))

# ─── Boss altar ───────────────────────────────────────────────────────────────

func _place_boss_altar() -> void:
	# Place a glowing boss-encounter anchor in the far reach of the arena
	var host := _get_or_create("BossAnchor")
	var ang  := _rng.randf_range(0, TAU)
	var r    := world_radius * 0.78
	var pos  := _world.global_position + Vector3(cos(ang)*r, 0, sin(ang)*r)

	var altar := Node3D.new()
	altar.name = "BossAltar"
	host.add_child(altar)
	altar.global_position = pos

	# Runed circle (TorusMesh ground)
	var ring := MeshInstance3D.new()
	var tm   := TorusMesh.new()
	tm.inner_radius = 2.8; tm.outer_radius = 3.2; tm.ring_segments = 48; tm.rings = 3
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.06, 0.04, 0.04)
	rmat.emission_enabled = true
	rmat.emission = _realm_altar_color()
	rmat.emission_energy_multiplier = 0.55
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rmat
	ring.rotation.x = PI * 0.5
	ring.position.y = 0.04
	altar.add_child(ring)

	# Pulse tween
	var tw: Tween = rmat.create_tween().set_loops()
	tw.tween_property(rmat, "emission_energy_multiplier", 1.4, 1.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(rmat, "emission_energy_multiplier", 0.25, 1.5).set_trans(Tween.TRANS_SINE)

func _realm_altar_color() -> Color:
	match _realm:
		"mistfen":   return Color(0.28, 0.82, 0.94)
		"heartwood": return Color(1.0, 0.38, 0.06)
		"moonfen":   return Color(0.42, 0.18, 0.88)
		_:           return Color(0.76, 0.18, 0.06)

# ─── Helpers ──────────────────────────────────────────────────────────────────

func _get_or_create(child_name: String) -> Node3D:
	if _world == null: return Node3D.new()
	var existing := _world.get_node_or_null(child_name)
	if existing != null: return existing as Node3D
	var n := Node3D.new(); n.name = child_name
	_world.add_child(n); return n

func _rand_pos(max_r: float) -> Vector2:
	var ang := _rng.randf_range(0, TAU)
	var r   := _rng.randf_range(0, max_r)
	return Vector2(cos(ang)*r, sin(ang)*r)

func _rand_ring(min_r: float, max_r: float) -> Vector2:
	var ang := _rng.randf_range(0, TAU)
	var r   := _rng.randf_range(min_r, max_r)
	return Vector2(cos(ang)*r, sin(ang)*r)
