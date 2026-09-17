extends PanelContainer
class_name HeroPreviewPanel

## Dedicated equipment drop target with a lightweight SubViewport hero preview.

signal equip_requested(item_id: String, slot: StringName)
signal drop_rejected(message: String)

const PREVIEW_WEAPON_PATHS: Dictionary = {
	"ember_sword": "res://assets/models/weapons/ember_sword.glb",
	"arcane_staff": "res://assets/models/weapons/arcane_staff.glb",
	"matriarch_scepter": "res://assets/models/weapons/quaternius/Staff.fbx",
	"mug_mace": "res://assets/models/weapons/quaternius/Hammer_Small.fbx",
	"siltcarver_blade": "res://assets/models/weapons/quaternius/Dagger_2.fbx",
	"cinderbound_maul": "res://assets/models/weapons/quaternius/Hammer_Double.fbx",
	"tideward_staff": "res://assets/models/weapons/quaternius/Spear.fbx",
	"rootbound_cleaver": "res://assets/models/weapons/quaternius/Claymore.fbx",
	"moonpact_staff": "res://assets/models/weapons/quaternius/Spear.fbx",
}

var game_state: Node
var _viewport: SubViewport
var _preview_root: Node3D
var _weapon_slot: EquipmentSlot
var _chest_slot: EquipmentSlot
var _status: Label
var _skills: HBoxContainer

func _ready() -> void:
	game_state = get_node("/root/GameState")
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	add_theme_stylebox_override("panel", UiKit.parchment_stylebox(UiKit.RADIUS_BUTTON))
	_build_ui()
	game_state.weapon_changed.connect(_on_weapon_changed)
	game_state.armor_changed.connect(_on_armor_changed)
	game_state.equipment_changed.connect(_on_equipment_changed)
	get_viewport().size_changed.connect(_apply_layout)
	_apply_layout()
	_refresh()

func _build_ui() -> void:
	var outer := VBoxContainer.new()
	outer.name = "HeroContent"
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)
	var title := Label.new()
	title.text = "HERO LOADOUT"
	UiKit.style_label(title, &"Eyebrow", 13)
	outer.add_child(title)
	var body := HBoxContainer.new()
	body.name = "PreviewAndSlots"
	body.add_theme_constant_override("separation", 12)
	outer.add_child(body)
	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "HeroPreview"
	viewport_container.custom_minimum_size = Vector2(280, 360)
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Keep the viewport at its authored render size; the surrounding Control
	# adapts instead of scaling the 3D render target on every layout pass.
	viewport_container.stretch = false
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.name = "HeroViewport"
	_viewport.size = Vector2i(560, 720)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(_viewport)
	body.add_child(viewport_container)
	var slots := VBoxContainer.new()
	slots.name = "EquipmentSlots"
	slots.custom_minimum_size = Vector2(156, 0)
	slots.add_theme_constant_override("separation", 8)
	body.add_child(slots)
	_weapon_slot = EquipmentSlot.new()
	_weapon_slot.name = "WeaponSlot"
	_weapon_slot.item_dropped.connect(_on_slot_item_dropped)
	slots.add_child(_weapon_slot)
	_chest_slot = EquipmentSlot.new()
	_chest_slot.name = "ChestSlot"
	_chest_slot.item_dropped.connect(_on_slot_item_dropped)
	slots.add_child(_chest_slot)
	_status = Label.new()
	_status.name = "DropStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_status, &"Caption", 13)
	outer.add_child(_status)
	var skill_title := Label.new()
	skill_title.text = "ACTIVE SKILLS"
	UiKit.style_label(skill_title, &"Eyebrow", 12)
	outer.add_child(skill_title)
	_skills = HBoxContainer.new()
	_skills.name = "ActiveSkills"
	_skills.add_theme_constant_override("separation", 8)
	outer.add_child(_skills)

func _apply_layout() -> void:
	if _viewport == null:
		return
	var compact := get_viewport().get_visible_rect().size.x < UiKit.COMPACT_BREAKPOINT
	var outer := get_node_or_null("HeroContent") as VBoxContainer
	var body := outer.get_node_or_null("PreviewAndSlots") as HBoxContainer if outer != null else null
	if body != null:
		body.get_node("HeroPreview").custom_minimum_size = Vector2(280 if compact else 360, 340 if compact else 400)

func _slot_for_item(item: Dictionary) -> StringName:
	var kind := str(item.get("kind", ""))
	var item_id := str(item.get("id", ""))
	if kind == "weapon" or item.has("atk") or game_state.WEAPON_DEFS.has(item_id):
		return &"weapon"
	if kind == "armor" or item.has("defense") or game_state.ARMOR_DEFS.has(item_id) \
		or str(item.get("equipment_slot", "")) == "chest":
		return &"chest"
	return &""

func _can_drop_item(item: Dictionary) -> bool:
	var slot := _slot_for_item(item)
	return slot != &"" and game_state.can_equip_item(item, slot)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and _can_drop_item(data as Dictionary)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		_reject("Drop a weapon or chest piece here.")
		return
	var item := data as Dictionary
	var slot := _slot_for_item(item)
	if slot == &"" or not game_state.can_equip_item(item, slot):
		_reject("That item does not fit this hero slot.")
		return
	if not game_state.equip_item_to_slot(str(item.get("id", "")), slot):
		_reject("This item is not available to equip.")
		return
	_status.text = "EQUIPPED · %s" % str(item.get("name", item.get("id", "GEAR")))
	_refresh()
	equip_requested.emit(str(item.get("id", "")), slot)

func _on_slot_item_dropped(item_id: String, slot: StringName) -> void:
	var item := _find_owned_item(item_id)
	if item.is_empty() or not game_state.can_equip_item(item, slot):
		_reject("That item does not fit this hero slot.")
		return
	if game_state.equip_item_to_slot(item_id, slot):
		_status.text = "EQUIPPED · %s" % str(item.get("name", item_id))
		_refresh()
		equip_requested.emit(item_id, slot)
	else:
		_reject("This item is not available to equip.")

func _find_owned_item(item_id: String) -> Dictionary:
	for item in game_state.forged_weapons:
		if str(item.get("id", "")) == item_id:
			return item.duplicate(true)
	for item in game_state.forged_armors:
		if str(item.get("id", "")) == item_id:
			return item.duplicate(true)
	return {}

func _reject(message: String) -> void:
	_status.text = "REJECTED · %s" % message
	drop_rejected.emit(message)

func _refresh() -> void:
	if _weapon_slot == null:
		return
	_weapon_slot.configure(&"weapon", game_state.get_equipment_for_slot(&"weapon"), UiKit.EMBER)
	_chest_slot.configure(&"chest", game_state.get_equipment_for_slot(&"chest"), Color(0.42, 0.76, 0.96))
	for child in _skills.get_children():
		child.queue_free()
	var skills: Array = game_state.equipped_weapon.get("skills", [])
	for index in mini(3, skills.size()):
		var skill := skills[index] as Dictionary
		var label := Label.new()
		label.text = "%d  %s\n%s" % [index + 1, str(skill.get("name", "RITE")), game_state.get_slot_cooldown_text(index)]
		label.custom_minimum_size = Vector2(0, 48)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiKit.style_label(label, &"Caption", 12)
		_skills.add_child(label)
	_refresh_preview()

func _refresh_preview() -> void:
	if _viewport == null:
		return
	if is_instance_valid(_preview_root):
		_preview_root.queue_free()
	_preview_root = Node3D.new()
	_preview_root.name = "HeroPreviewRig"
	_viewport.add_child(_preview_root)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.95, 3.4)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.8, 0.0))
	_preview_root.add_child(camera)
	var key := OmniLight3D.new()
	key.light_color = Color(1.0, 0.82, 0.62)
	key.light_energy = 2.2
	key.omni_range = 5.0
	key.position = Vector3(1.2, 2.0, 2.0)
	_preview_root.add_child(key)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.42, 0.62, 1.0)
	fill.light_energy = 1.0
	fill.omni_range = 4.0
	fill.position = Vector3(-1.4, 1.0, 1.5)
	_preview_root.add_child(fill)
	var authored_scene := ResourceLoader.load("res://assets/models/hero.fbx", "PackedScene") as PackedScene
	if authored_scene != null:
		var hero := authored_scene.instantiate() as Node3D
		hero.name = "AuthoredHero"
		hero.scale = Vector3.ONE * 0.62
		_preview_root.add_child(hero)
	else:
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.height = 1.55
		capsule.radius = 0.38
		body.mesh = capsule
		body.position = Vector3(0.0, 0.78, 0.0)
		body.material_override = _preview_material(Color(0.22, 0.27, 0.32))
		_preview_root.add_child(body)
	_add_current_weapon()
	_add_current_armor()

func _add_current_weapon() -> void:
	var weapon: Dictionary = game_state.equipped_weapon
	var path := str(PREVIEW_WEAPON_PATHS.get(str(weapon.get("id", "")), ""))
	var scene := ResourceLoader.load(path, "PackedScene") as PackedScene if not path.is_empty() else null
	if scene != null:
		var model := scene.instantiate() as Node3D
		model.name = "CurrentWeapon"
		model.position = Vector3(0.73, 1.02, 0.0)
		model.rotation_degrees = Vector3(0.0, 0.0, -28.0)
		model.scale = Vector3.ONE * 0.42
		_preview_root.add_child(model)
		return
	var blade := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 1.15, 0.18)
	blade.mesh = mesh
	blade.position = Vector3(0.73, 1.02, 0.0)
	blade.rotation_degrees = Vector3(0.0, 0.0, -28.0)
	blade.material_override = _preview_material(UiKit.EMBER)
	_preview_root.add_child(blade)

func _add_current_armor() -> void:
	if game_state.equipped_armor.is_empty():
		return
	var chest := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.84, 0.72, 0.48)
	chest.mesh = mesh
	chest.position = Vector3(0.0, 0.92, -0.28)
	chest.material_override = _preview_material(Color(0.28, 0.62, 0.78))
	_preview_root.add_child(chest)

func _preview_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.62
	return material

func _on_weapon_changed(_weapon: Dictionary) -> void:
	_refresh()

func _on_armor_changed(_armor: Dictionary) -> void:
	_refresh()

func _on_equipment_changed(_slots: Dictionary) -> void:
	_refresh()
