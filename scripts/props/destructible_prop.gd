class_name DestructibleProp
extends StaticBody3D

## === Destructible props (UE Chaos-style breakables) ===
## Ember pots / root crates / moonfen glowcaps scattered by GroveDressing.
## Strikes and skill slams chip them (hit-flash + small shard puffs);
## breaking bursts physical debris via DebrisSystem and rolls loot into
## the satchel through GameState.add_loot. Fully code-built to match the
## dressing pipeline (no scene file needed).

signal broke(prop: DestructibleProp)

const VARIANTS := {
	"pot": {
		"hp": 2, "debris": "ceramic", "scale": Vector3.ONE,
		"cue": "impact_stone", "flash_color": Color(1.0, 0.85, 0.6),
	},
	"crate": {
		"hp": 2, "debris": "wood", "scale": Vector3.ONE,
		"cue": "impact_plant", "flash_color": Color(0.9, 0.75, 0.5),
	},
	"glowcap": {
		"hp": 3, "debris": "crystal", "scale": Vector3.ONE,
		"cue": "elem_frost", "flash_color": Color(0.6, 0.9, 1.0),
	},
}

var variant: String = "pot"
var hp: int = 2
var max_hp: int = 2
var is_broken: bool = false

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _cfg: Dictionary


## Factory used by GroveDressing: builds a ready-to-place prop.
static func create(variant_id: String) -> DestructibleProp:
	var prop := DestructibleProp.new()
	prop.name = "Destructible_%s_%d" % [variant_id, randi() % 10000]
	prop.variant = variant_id if VARIANTS.has(variant_id) else "pot"
	return prop


func _ready() -> void:
	add_to_group("destructible")
	collision_layer = 1 << 6          # prop (camera spring-arm mask stays on environment=terrain, so props no longer collapse the camera)
	collision_mask = 0
	_cfg = VARIANTS[variant]
	max_hp = int(_cfg.hp)
	hp = max_hp
	scale = _cfg.scale

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Visual"
	_mesh_instance.mesh = _build_mesh()
	_material = _build_material()
	_material.emission_enabled = true
	_material.emission = Color.BLACK
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)

	var shape := CollisionShape3D.new()
	shape.name = "Hitbox"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.42
	shape.shape = sphere
	shape.position = Vector3(0, 0.35, 0)
	add_child(shape)


func _build_mesh() -> Mesh:
	match variant:
		"crate":
			var box := BoxMesh.new()
			box.size = Vector3(0.55, 0.55, 0.55)
			return box
		"glowcap":
			var shard := PrismMesh.new()
			shard.size = Vector3(0.42, 0.95, 0.42)
			return shard
		_:
			var pot := CylinderMesh.new()
			pot.top_radius = 0.27
			pot.bottom_radius = 0.17
			pot.height = 0.52
			pot.radial_segments = 12
			return pot


func _build_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.85
	match variant:
		"crate":
			m.albedo_texture = load("res://assets/textures/stylized/wood/albedo.png")
			m.normal_enabled = true
			m.normal_texture = load("res://assets/textures/stylized/wood/normal.png")
			m.roughness_texture = load("res://assets/textures/stylized/wood/roughness.png")
			m.uv1_scale = Vector3(0.9, 0.9, 0.9)
		"glowcap":
			m.albedo_color = Color(0.24, 0.5, 0.62)
			m.emission = Color(0.4, 0.78, 1.0)
			m.emission_energy_multiplier = 1.5
		_:
			m.albedo_texture = load("res://assets/textures/stylized/clay/albedo.png")
			m.normal_enabled = true
			m.normal_texture = load("res://assets/textures/stylized/clay/normal.png")
			m.roughness_texture = load("res://assets/textures/stylized/clay/roughness.png")
	return m


## Strike/slam entry point. dir biases the chip spray away from the blow.
func take_hit(amount: int = 1, from_dir: Vector3 = Vector3.UP) -> void:
	if is_broken:
		return
	hp = maxi(hp - maxi(amount, 1), 0)
	_flash()
	ImpactDirector.spawn_impact_debris(self, global_position + Vector3(0, 0.35, 0),
		str(_cfg.debris), 1, from_dir)
	if hp <= 0:
		_break(from_dir)


func _flash() -> void:
	if _material == null:
		return
	var flash: Color = _cfg.flash_color
	_material.emission = flash * 0.9
	_material.emission_energy_multiplier = 1.2
	var tween := create_tween()
	tween.tween_property(_material, "emission_energy_multiplier",
		_base_emission(), 0.22)


func _base_emission() -> float:
	return 1.5 if variant == "glowcap" else 0.0


func _break(dir: Vector3) -> void:
	if is_broken:
		return
	is_broken = true
	broke.emit(self)

	var origin := global_position + Vector3(0, 0.3, 0)
	ImpactDirector.spawn_impact_debris(self, origin, str(_cfg.debris), 7, dir)
	var burst_col := Color(0.72, 0.55, 0.38) \
		if variant != "glowcap" else Color(0.5, 0.85, 1.0)
	CombatFx.spawn_burst(self, origin, burst_col, 14, 5.0, 0.36, 0.14)
	CombatFx.impact(self, 0.16, 0.02, 1.0, 0.2)
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play_cue"):
		audio.play_cue(str(_cfg.cue))
	_roll_loot()

	queue_free()


## Loot flows straight into the satchel (matches the game's loot model).
func _roll_loot() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("add_loot"):
		return
	match variant:
		"crate":
			if randf() < 0.45:
				gs.add_loot("moss_tonic", 1, "A Moss Tonic tumbles from the crate.")
			else:
				gs.add_loot("ember_shard", 1, "The crate hides an Ember Shard.")
		"glowcap":
			gs.add_loot("ember_shard", 2, "Moonfen crystal shards scatter free.")
		_:
			gs.add_loot("ember_shard", 1, "The ember pot cracks open.")
