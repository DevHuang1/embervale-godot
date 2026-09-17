extends Area3D
class_name LootDrop

## Mobile-safe physical loot pickup. Drops are tiny bounded nodes with a single
## collision area, a bobbing mesh, and immediate GameState persistence.
##
## Every drop carries a canonical drop record ({type, id, quantity, rarity}) so
## the same path serves enemy, boss, and chest loot. Drops spawned from a chest
## remember their chest id + slot index and clear that slot on pickup, which is
## what keeps a claimed-but-uncollected chest exactly once across reloads.

const DEFAULT_LIFETIME := 90.0
const FADE_SECONDS     := 1.4
const MAX_ACTIVE_DROPS := 64
const COLLECT_RADIUS   := 0.72
const RARITY_NAMES     := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]

## Live spawned drops, oldest first. Used to bound concurrent presentation cost.
static var _active: Array[LootDrop] = []

var drop_kind := "gold"
var amount := 0
var item_id := ""
var rarity := 1
var drop_data: Dictionary = {}
var source_chest_id := ""
var source_chest_index := -1
var collected := false
var _base_y := 0.0
var _rest_captured := false
var _time := 0.0
var _age := 0.0
var _lifetime := DEFAULT_LIFETIME
var _expiring := false
var _mesh: MeshInstance3D

static func spawn_gold(context: Node3D, position: Vector3, value: int) -> LootDrop:
	return spawn_drop(context, position,
		{"type": "gold", "id": "", "quantity": maxi(1, value), "rarity": 0})

static func spawn_item(context: Node3D, position: Vector3, id: String,
		count: int = 1, item_rarity: int = 1) -> LootDrop:
	return spawn_drop(context, position,
		{"type": "item", "id": id, "quantity": maxi(1, count),
		"rarity": clampi(item_rarity, 1, 5)})

## Generic factory. `chest_id` / `chest_index` are set only for chest loot so the
## pickup can clear its persisted pending slot.
static func spawn_drop(context: Node3D, position: Vector3, drop: Dictionary,
		chest_id: String = "", chest_index: int = -1) -> LootDrop:
	if context == null or not is_instance_valid(context) or not context.is_inside_tree():
		return null
	var parent := context.get_parent()
	if parent == null:
		return null
	_enforce_cap()
	var instance := LootDrop.new()
	instance.drop_data = drop.duplicate(true)
	instance.source_chest_id = chest_id
	instance.source_chest_index = chest_index
	instance.configure_drop_visual()
	parent.add_child(instance)
	instance.global_position = position
	_active.append(instance)
	return instance

func configure_gold(value: int) -> void:
	drop_kind = "gold"
	amount = maxi(1, value)
	drop_data = {"type": "gold", "id": "", "quantity": amount, "rarity": 0}

func configure_item(id: String, count: int = 1, item_rarity: int = 1) -> void:
	drop_kind = "item"
	item_id = id
	amount = maxi(1, count)
	rarity = clampi(item_rarity, 1, 5)
	drop_data = {"type": "item", "id": id, "quantity": amount, "rarity": rarity}

func configure_drop_visual() -> void:
	var dtype := str(drop_data.get("type", "gold"))
	drop_kind = "gold" if dtype == "gold" else "item"
	item_id = str(drop_data.get("id", ""))
	amount = maxi(1, int(drop_data.get("quantity", 1)))
	rarity = clampi(int(drop_data.get("rarity", 1)), 1, 5)

func _ready() -> void:
	add_to_group("loot_drop")
	collision_layer = 0
	collision_mask = 1 << 0
	monitoring = true
	_build_visual()
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if collected:
		return
	# Capture the rest height on the first tick, after the spawner has assigned
	# the final position. Capturing in _ready() would read the pre-position
	# origin and sink every drop to world y≈0 (often below terrain).
	if not _rest_captured:
		_base_y = position.y
		_rest_captured = true
	_age += delta
	if _age >= _lifetime:
		_expire()
		return
	if not _expiring and _lifetime - _age <= FADE_SECONDS:
		_expiring = true
		_fade_out()
	_time += delta
	position.y = _base_y + sin(_time * 3.2) * 0.08
	rotate_y(delta * 1.8)
	var hero := get_tree().get_first_node_in_group("player") as Node3D
	if hero != null and is_instance_valid(hero) \
			and global_position.distance_to(hero.global_position) < COLLECT_RADIUS:
		_collect(hero)

func _fade_out() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", scale * 0.85, FADE_SECONDS * 0.6)
	tw.tween_property(self, "scale", Vector3.ZERO, FADE_SECONDS * 0.4)

func _expire() -> void:
	if collected:
		return
	if source_chest_id.is_empty():
		collected = true
		_active.erase(self)
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3.ZERO, 0.25)
		tw.tween_callback(queue_free)
	else:
		# Claimed chest loot must never be lost to a timer; auto-collect it.
		_collect(null)

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
	_active.erase(self)
	_grant_reward()
	if not source_chest_id.is_empty():
		var gs := get_node_or_null("/root/GameState")
		if gs != null and gs.has_method("collect_chest_drop"):
			gs.call("collect_chest_drop", source_chest_id, source_chest_index)
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_ui_blip"):
		am.play_ui_blip()
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 1.35, 0.08)
	tw.tween_property(self, "scale", Vector3.ZERO, 0.14)
	tw.tween_callback(queue_free)

# ─────────────────────────────────────────────────────────────────────────────
# Grant
# ─────────────────────────────────────────────────────────────────────────────

func _grant_reward() -> void:
	var gs := get_node_or_null("/root/GameState")
	var dtype := str(drop_data.get("type", drop_kind))
	var did := str(drop_data.get("id", item_id))
	var qty := maxi(1, int(drop_data.get("quantity", amount)))
	var drop_rarity := clampi(int(drop_data.get("rarity", rarity)), 1, 5)
	match dtype:
		"gold":
			if gs != null and gs.has_method("add_gold"):
				gs.add_gold(qty)
			FloatingText.spawn_on_entity(self, "+%d gold" % qty, Color(1.0, 0.84, 0.30), 1.2)
		"xp":
			if gs != null and gs.has_method("grant_xp"):
				gs.grant_xp(qty)
			FloatingText.spawn_on_entity(self, "+%d XP" % qty, Color(0.42, 0.85, 0.55), 1.2)
		"diamond":
			if gs != null and gs.has_method("add_diamonds"):
				gs.add_diamonds(qty)
			FloatingText.spawn_on_entity(self, "+%d diamonds" % qty, Color(0.55, 0.75, 1.0), 1.2)
		"material":
			if gs != null and gs.has_method("add_material"):
				gs.add_material(did, qty)
			var mat_name := str(GameState.MATERIAL_DEFS.get(did, {}).get("name", did))
			FloatingText.spawn_on_entity(self, "+%d %s" % [qty, mat_name],
				Color(0.52, 0.90, 1.0), 1.1)
		"weapon", "armor":
			_grant_gear(gs, did, drop_rarity)
		_:
			_grant_inventory_item(gs, did, qty, drop_rarity)

func _grant_gear(gs: Node, gear_id: String, drop_rarity: int) -> void:
	var label := gear_id.replace("_", " ").capitalize()
	if gear_id.is_empty():
		return
	if GameState.WEAPON_DEFS.has(gear_id) and gs != null and gs.has_method("add_weapon"):
		var wdef: Dictionary = GameState.WEAPON_DEFS[gear_id]
		gs.call("add_weapon", wdef.duplicate(true), true,
			"Recovered: %s" % str(wdef.get("name", gear_id)))
		label = str(wdef.get("name", gear_id))
	elif GameState.ARMOR_DEFS.has(gear_id) and gs != null and gs.has_method("add_armor"):
		var adef: Dictionary = GameState.ARMOR_DEFS[gear_id]
		gs.call("add_armor", adef.duplicate(true), true)
		label = str(adef.get("name", gear_id))
	FloatingText.spawn_on_entity(self, "+%s · %s" % [label, RARITY_NAMES[drop_rarity - 1]],
		Color(0.52, 0.90, 1.0), 1.1 + drop_rarity * 0.05)

func _grant_inventory_item(gs: Node, drop_id: String, qty: int, drop_rarity: int) -> void:
	var label := "%d %s" % [qty, drop_id]
	if gs == null:
		return
	# Gear used to arrive here through the consumable-only add_loot path. Route
	# it to the weapon/armor inventories or the reward silently vanishes.
	if GameState.WEAPON_DEFS.has(drop_id) and gs.has_method("add_weapon"):
		var wdef: Dictionary = GameState.WEAPON_DEFS[drop_id]
		gs.call("add_weapon", wdef.duplicate(true), true,
			"Recovered: %s" % str(wdef.get("name", drop_id)))
		label = str(wdef.get("name", drop_id))
	elif GameState.ARMOR_DEFS.has(drop_id) and gs.has_method("add_armor"):
		var adef: Dictionary = GameState.ARMOR_DEFS[drop_id]
		gs.call("add_armor", adef.duplicate(true), true)
		label = str(adef.get("name", drop_id))
	elif gs.has_method("add_loot"):
		gs.call("add_loot", drop_id, qty, "Loot collected: %s" % drop_id)
	FloatingText.spawn_on_entity(self, "+%s · %s" % [label, RARITY_NAMES[drop_rarity - 1]],
		Color(0.52, 0.90, 1.0), 1.1 + drop_rarity * 0.05)

# ─────────────────────────────────────────────────────────────────────────────
# Bounded pool
# ─────────────────────────────────────────────────────────────────────────────

static func _enforce_cap() -> void:
	for i in range(_active.size() - 1, -1, -1):
		var candidate: LootDrop = _active[i]
		if not is_instance_valid(candidate) or candidate.collected:
			_active.remove_at(i)
	while _active.size() >= MAX_ACTIVE_DROPS:
		var oldest: LootDrop = _active.pop_front()
		if is_instance_valid(oldest) and not oldest.collected:
			oldest._expire()

static func active_drop_count() -> int:
	_enforce_cap()
	return _active.size()
