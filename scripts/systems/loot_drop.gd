extends Area3D
class_name LootDrop

## Mobile-safe physical loot pickup. Drops are tiny pooled-style nodes with a
## single collision area, a bobbing mesh, and immediate GameState persistence.
var drop_kind := "gold"
var amount := 0
var item_id := ""
var rarity := 1
var collected := false
var _base_y := 0.0
var _time := 0.0
var _mesh: MeshInstance3D

static func spawn_gold(context: Node3D, position: Vector3, value: int) -> LootDrop:
	var drop := LootDrop.new()
	drop.configure_gold(value)
	context.get_parent().add_child(drop)
	drop.global_position = position
	return drop

static func spawn_item(context: Node3D, position: Vector3, id: String, count: int = 1, item_rarity: int = 1) -> LootDrop:
	var drop := LootDrop.new()
	drop.configure_item(id, count, item_rarity)
	context.get_parent().add_child(drop)
	drop.global_position = position
	return drop

func configure_gold(value: int) -> void:
	drop_kind = "gold"
	amount = maxi(1, value)

func configure_item(id: String, count: int = 1, item_rarity: int = 1) -> void:
	drop_kind = "item"
	item_id = id
	amount = maxi(1, count)
	rarity = clampi(item_rarity, 1, 5)

func _ready() -> void:
	add_to_group("loot_drop")
	_base_y = position.y
	collision_layer = 0
	collision_mask = 1 << 0
	monitoring = true
	_build_visual()
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if collected:
		return
	_time += delta
	position.y = _base_y + sin(_time * 3.2) * 0.08
	rotate_y(delta * 1.8)
	var hero := get_tree().get_first_node_in_group("player") as Node3D
	if hero != null and is_instance_valid(hero) and global_position.distance_to(hero.global_position) < 0.72:
		_collect(hero)

func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "GoldCoin" if drop_kind == "gold" else "ItemDrop"
	var material := StandardMaterial3D.new()
	material.emission_enabled = true
	if drop_kind == "gold":
		var coin := CylinderMesh.new()
		coin.top_radius = 0.13
		coin.bottom_radius = 0.13
		coin.height = 0.045
		coin.radial_segments = 10
		_mesh.mesh = coin
		# Warm shaded metal: key-light glints read as gold, with a softer pickup
		# glow instead of a flat unshaded sticker.
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		material.metallic = 1.0
		material.roughness = 0.34
		material.albedo_color = Color(1.0, 0.76, 0.22)
		material.emission = Color(1.0, 0.40, 0.04)
		material.emission_energy_multiplier = 0.9
	else:
		var shard := SphereMesh.new()
		shard.radius = 0.12
		shard.height = 0.24
		shard.radial_segments = 8
		_mesh.mesh = shard
		var rarity_colors := [Color(0.42, 0.88, 1.0), Color(0.46, 1.0, 0.54), Color(0.80, 0.46, 1.0), Color(1.0, 0.52, 0.18), Color(1.0, 0.86, 0.28)]
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = rarity_colors[rarity - 1]
		material.emission = rarity_colors[rarity - 1].lightened(0.15)
		material.emission_energy_multiplier = 1.8
	_mesh.material_override = material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.62
	shape.shape = sphere
	add_child(shape)

func _on_body_entered(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_collect(body)

func _collect(_collector: Node3D) -> void:
	if collected:
		return
	collected = true
	var gs := get_node_or_null("/root/GameState")
	if drop_kind == "gold":
		if gs != null and gs.has_method("add_gold"):
			gs.add_gold(amount)
		FloatingText.spawn_on_entity(self, "+%d gold" % amount,
			Color(1.0, 0.84, 0.30), 1.2)
	else:
		if gs != null and gs.has_method("add_loot"):
			gs.add_loot(item_id, amount, "Loot collected: %s" % item_id)
		var rarity_names := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
		FloatingText.spawn_on_entity(self, "+%d %s · %s" % [amount, item_id, rarity_names[rarity - 1]],
			Color(0.52, 0.90, 1.0), 1.1 + rarity * 0.05)
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_ui_blip"):
		am.play_ui_blip()
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 1.35, 0.08)
	tw.tween_property(self, "scale", Vector3.ZERO, 0.14)
	tw.tween_callback(queue_free)
