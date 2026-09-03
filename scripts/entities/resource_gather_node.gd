extends Node3D
class_name ResourceGatherNode

## === ResourceGatherNode — Interactable Material Gathering Node ===
## Placed by ProceduralWorldGenerator in each realm.
## Hero walks into interact radius → press interact → gather material.
## Respawns after respawn_time_sec tracked via WorldState.
##
## Visual: realm-coloured ore/herb cluster + floating sparkle particles
##         + interact prompt Label3D.
##
## Usage (auto from generator):
##   var rn := ResourceGatherNode.new()
##   rn.setup(material_id, quantity_min, realm_id)
##   add_child(rn)

signal gathered(material_id: String, quantity: int)

@export var material_id     : String = "bramble_wood"
@export var quantity_min    : int    = 1
@export var quantity_max    : int    = 3
@export var respawn_time_sec: float  = 90.0
@export var interact_radius : float  = 2.2
@export var realm_id        : String = "bramblewood"

var _node_id    : String = ""
var _available  : bool   = true
var _hero_nearby: bool   = false
var _prompt     : Label3D = null
var _mesh_root  : Node3D  = null
var _sparkle    : GPUParticles3D = null
var _mat_color  : Color  = Color(0.42, 0.88, 0.30)
var _t          : float  = 0.0

func _ready() -> void:
	_node_id = "%s_%s" % [material_id, get_instance_id()]
	_check_cooldown()
	_build_visual()
	_build_interact_area()
	_build_sparkle()
	_build_prompt()

func setup(mat_id: String, qty_min: int = 1, p_realm: String = "bramblewood") -> void:
	material_id  = mat_id
	quantity_min = qty_min
	quantity_max = max(qty_min, qty_min + 2)
	realm_id     = p_realm
	_mat_color   = _material_color(mat_id)
	# refresh visual if already built
	if _sparkle:
		if _sparkle.process_material is ParticleProcessMaterial:
			(_sparkle.process_material as ParticleProcessMaterial).color = _mat_color

func _check_cooldown() -> void:
	var ws := get_node_or_null("/root/WorldState")
	if ws and ws.has_method("is_gathered"):
		_available = not ws.call("is_gathered", _node_id)

# ─── Visual ───────────────────────────────────────────────────────────────────

func _build_visual() -> void:
	_mesh_root = Node3D.new()
	_mesh_root.name = "MeshRoot"
	add_child(_mesh_root)
	_mat_color = _material_color(material_id)

	# Cluster of 3 node meshes
	for i in 3:
		var ni := MeshInstance3D.new()
		var mesh_type := _material_mesh_type(material_id)
		if mesh_type == "sphere":
			var sm := SphereMesh.new()
			sm.radius = 0.15 + float(i) * 0.06; sm.height = sm.radius * 1.4; sm.radial_segments = 8
			ni.mesh = sm
		else:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0; cm.bottom_radius = 0.08 + float(i) * 0.03; cm.height = 0.28 + float(i) * 0.08; cm.radial_segments = 6
			ni.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _mat_color
		mat.roughness    = 0.72; mat.metallic = 0.18
		mat.emission_enabled = true
		mat.emission = _mat_color
		mat.emission_energy_multiplier = 0.55
		ni.material_override = mat
		var ang := TAU * float(i) / 3.0
		ni.position = Vector3(cos(ang)*0.22, 0.12 + float(i)*0.06, sin(ang)*0.22)
		ni.rotation.y = ang
		_mesh_root.add_child(ni)

func _build_sparkle() -> void:
	_sparkle = GPUParticles3D.new()
	_sparkle.amount = 12; _sparkle.lifetime = 1.5; _sparkle.emitting = _available
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 1, 0); pm.spread = 65.0
	pm.initial_velocity_min = 0.3; pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, -0.4, 0)
	pm.scale_min = 0.04; pm.scale_max = 0.10
	pm.color = _mat_color
	_sparkle.process_material = pm
	_sparkle.position.y = 0.28
	add_child(_sparkle)

func _build_interact_area() -> void:
	var area := Area3D.new()
	area.collision_layer = 0; area.collision_mask = 1 << 0
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new(); sp.radius = interact_radius
	cs.shape = sp; area.add_child(cs)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)

func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.text     = "[Gather] %s" % material_id.replace("_", " ").capitalize()
	_prompt.font_size = 42
	_prompt.modulate  = Color(0.88, 0.80, 0.55)
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.position.y = 0.75
	_prompt.visible    = false
	add_child(_prompt)

# ─── Interaction ──────────────────────────────────────────────────────────────

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"): return
	_hero_nearby = true
	if _prompt and _available: _prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"): return
	_hero_nearby = false
	if _prompt: _prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not _available or not _hero_nearby: return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_do_gather()

func _do_gather() -> void:
	if not _available: return
	_available = false

	var qty := randi_range(quantity_min, quantity_max)
	gathered.emit(material_id, qty)

	# Grant to GameState
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		var mats : Dictionary = gs.get("raw_materials") if gs.get("raw_materials") != null else {}
		mats[material_id] = int(mats.get(material_id, 0)) + qty
		gs.set("raw_materials", mats)
		if gs.has_method("save_game"): gs.call("save_game")

	# Mark in WorldState for respawn tracking
	var ws := get_node_or_null("/root/WorldState")
	if ws and ws.has_method("mark_gathered"):
		ws.call("mark_gathered", _node_id, respawn_time_sec)

	# FloatingText
	var hero := _find_hero()
	if hero:
		FloatingText.spawn_on_entity(hero,
			"+%d %s" % [qty, material_id.replace("_", " ").capitalize()],
			_mat_color)

	# Visual feedback
	if _prompt: _prompt.visible = false
	if _sparkle:
		_sparkle.emitting = false
		_sparkle.one_shot = true
		_sparkle.emitting = true   # final burst
	if _mesh_root:
		var tw := create_tween()
		tw.tween_property(_mesh_root, "scale", Vector3.ONE * 0.01, 0.45).set_trans(Tween.TRANS_EXPO)

	# Schedule respawn
	var timer := get_tree().create_timer(respawn_time_sec, false)
	timer.timeout.connect(_respawn)

func _respawn() -> void:
	var ws := get_node_or_null("/root/WorldState")
	if ws and ws.has_method("is_gathered"):
		if ws.call("is_gathered", _node_id):
			return  # still on cooldown
	_available = true
	if _mesh_root:
		var tw := create_tween()
		tw.tween_property(_mesh_root, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_BACK)
	if _sparkle:
		_sparkle.emitting = true
		_sparkle.one_shot = false

func _find_hero() -> Node3D:
	if get_tree() == null: return null
	var heroes := get_tree().get_nodes_in_group("player")
	return heroes[0] as Node3D if not heroes.is_empty() else null

# ─── Per-frame animation ──────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _available: return
	_t += delta
	if _mesh_root:
		_mesh_root.position.y = sin(_t * 1.6) * 0.05

# ─── Material helpers ─────────────────────────────────────────────────────────

func _material_color(mat_id: String) -> Color:
	match mat_id:
		"bramble_wood":      return Color(0.45, 0.28, 0.14)
		"moss_fiber":        return Color(0.28, 0.55, 0.22)
		"fen_reed":          return Color(0.40, 0.55, 0.28)
		"emberstone":        return Color(0.90, 0.35, 0.10)
		"moonmoss":          return Color(0.45, 0.65, 0.92)
		"iron_shard":        return Color(0.55, 0.58, 0.62)
		"beast_hide":        return Color(0.55, 0.38, 0.22)
		"spore_dust":        return Color(0.62, 0.88, 0.30)
		"crystal_fragment":  return Color(0.55, 0.75, 1.00)
		"monster_core":      return Color(0.85, 0.22, 0.08)
		_:                   return Color(0.55, 0.55, 0.55)

func _material_mesh_type(mat_id: String) -> String:
	match mat_id:
		"bramble_wood", "fen_reed":     return "cylinder"
		"monster_core", "beast_hide":  return "sphere"
		_:                             return "sphere"
