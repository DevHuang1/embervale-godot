extends CanvasLayer
class_name SatchelUI

## === Field Satchel ===
## Inventory, forged gear + armor, the equipped weapon's skill kit
## Albion Online-inspired UX with equipment slots, item detail panel,
## and improved readability.

@onready var game_state: GameState = GameState
@onready var items_vbox: Container = $Root/VBox/ItemsList/ItemsVBox
@onready var count_label: Label = $Root/VBox/Header/CountLabel
@onready var close_button: Button = $Root/VBox/Header/CloseButton
@onready var weapon_name: Label = $Root/VBox/ForgedGear/ForgedVBox/CurrentWeapon/WeaponInfo/WeaponName
@onready var weapon_stats: Label = $Root/VBox/ForgedGear/ForgedVBox/CurrentWeapon/WeaponInfo/WeaponStats
@onready var forge_button: Button = $Root/VBox/ForgedGear/ForgedVBox/CurrentWeapon/ForgeButton
@onready var forged_vbox: VBoxContainer = $Root/VBox/ForgedGear/ForgedVBox
@onready var skill_kit: HBoxContainer = $Root/VBox/ClassFooter/ClassVBox/SkillKit

var _skill_cd_labels: Array[Label] = []
var _arsenal_grid: GridContainer
var _equipment_row: HBoxContainer
var _selected_item_label: Label
var _stats_panel: PanelContainer
var _stats_grid: GridContainer
var _detail_panel: PanelContainer
var _detail_name: Label
var _detail_desc: Label
var _detail_stats: Label
var _detail_action: Button
var _detail_item_id := ""
var _preview_viewport: SubViewport
var _preview_root: Node3D
var _craft_panel: PanelContainer
var _craft_status: Label
var _inventory_filter := "all"
var _filter_bar: HBoxContainer
var _filter_buttons: Dictionary = {}
var _section_tabs: GridContainer
var _active_section := "inventory"
var _bottom_close_button: Button

const CRAFT_RECIPES: Array[Dictionary] = [
	{"category": "weapon", "id": "ember_sword", "name": "EMBERFANG", "materials": {"iron_shard": 2}, "gold": 25},
	{"category": "armor", "id": "warden_plate", "name": "WARDEN PLATE", "materials": {"iron_shard": 3}, "gold": 30},
]
const PREVIEW_WEAPON_PATHS: Dictionary = {
	"ember_sword": "res://assets/models/weapons/ember_sword.glb",
	"arcane_staff": "res://assets/models/weapons/arcane_staff.glb",
	"matriarch_scepter": "res://assets/models/weapons/quaternius/Staff.fbx",
	"mug_mace": "res://assets/models/weapons/quaternius/Hammer_Small.fbx",
}

func _ready() -> void:
	UiKit.apply_glass($Root)
	process_mode = Node.PROCESS_MODE_ALWAYS  # stay interactive while the world is frozen
	_freeze_was_visible = visible
	# Warm letter-stock interiors for the gear card and class footer so
	# stat text reads against the dark glass frame.
	UiKit.apply_parchment($Root/VBox/ForgedGear)
	UiKit.apply_parchment($Root/VBox/ClassFooter)
	UiKit.style_button(forge_button)
	forge_button.add_theme_font_size_override("font_size", 18)
	UiKit.style_button(close_button, UiKit.SAGE)
	_connect_signals()
	_build_albion_layout()
	_rebuild_inventory()
	_update_forged_gear()
	_rebuild_skill_kit()
	_rebuild_armor_row()
	_apply_satchel_layout()

	close_button.pressed.connect(_on_close_pressed)
	forge_button.pressed.connect(_on_forge_pressed)
	get_viewport().size_changed.connect(_apply_satchel_layout)

var _freeze_was_visible := false

## Freeze/resume the world whenever this interface toggles, whichever
## code path opened or closed it.
func _poll_world_freeze() -> void:
	if visible == _freeze_was_visible:
		return
	_freeze_was_visible = visible
	if visible:
		game_state.push_world_freeze()
	else:
		game_state.pop_world_freeze()

func _process(_delta: float) -> void:
	_poll_world_freeze()
	for slot in _skill_cd_labels.size():
		if slot < 3:
			_skill_cd_labels[slot].text = game_state.get_slot_cooldown_text(slot)

func _connect_signals() -> void:
	game_state.loot_received.connect(_on_inventory_changed)
	game_state.inventory_changed.connect(_on_inventory_changed)
	game_state.weapon_changed.connect(_on_weapon_changed)
	game_state.armor_changed.connect(_on_armor_changed)
	if game_state.has_signal("stats_changed"):
		game_state.stats_changed.connect(_on_stats_changed)

func _build_albion_layout() -> void:
	var root_vbox := $Root/VBox as VBoxContainer
	var list_parent := items_vbox.get_parent()
	_arsenal_grid = GridContainer.new()
	_arsenal_grid.name = "ArsenalGrid"
	_arsenal_grid.columns = 2
	_arsenal_grid.add_theme_constant_override("h_separation", 10)
	_arsenal_grid.add_theme_constant_override("v_separation", 10)
	_arsenal_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_parent.remove_child(items_vbox)
	items_vbox.queue_free()
	list_parent.add_child(_arsenal_grid)
	items_vbox = _arsenal_grid
	_filter_bar = HBoxContainer.new()
	_filter_bar.name = "InventoryFilters"
	_filter_bar.add_theme_constant_override("separation", 8)
	root_vbox.add_child(_filter_bar)
	root_vbox.move_child(_filter_bar, 1)
	for filter_id in ["all", "weapon", "armor", "consumable", "material", "quest"]:
		var filter_button := Button.new()
		filter_button.text = str(filter_id).to_upper()
		filter_button.custom_minimum_size = Vector2(116, 42)
		UiKit.style_secondary_button(filter_button)
		filter_button.pressed.connect(_set_inventory_filter.bind(str(filter_id)))
		_filter_bar.add_child(filter_button)
		_filter_buttons[str(filter_id)] = filter_button
	_refresh_filter_buttons()

	_equipment_row = HBoxContainer.new()
	_equipment_row.name = "EquipmentLoadout"
	_equipment_row.add_theme_constant_override("separation", 12)
	root_vbox.add_child(_equipment_row)
	root_vbox.move_child(_equipment_row, 1)
	_selected_item_label = Label.new()
	_selected_item_label.text = "Select a weapon or item to inspect"
	_selected_item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_item_label.custom_minimum_size = Vector2(230, 0)
	UiKit.style_label(_selected_item_label, &"Caption", 15)
	_rebuild_equipment_loadout()
	_build_stats_panel(root_vbox)
	_build_detail_panel(root_vbox)
	_build_crafting_panel(root_vbox)
	_build_section_tabs(root_vbox)
	_bottom_close_button = Button.new()
	_bottom_close_button.name = "CloseInventoryButton"
	_bottom_close_button.text = "✕  CLOSE SATCHEL"
	_bottom_close_button.custom_minimum_size = Vector2(0, 52)
	_bottom_close_button.pressed.connect(_on_close_pressed)
	UiKit.style_secondary_button(_bottom_close_button)
	root_vbox.add_child(_bottom_close_button)
	_set_section("inventory")
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _build_section_tabs(root_vbox: VBoxContainer) -> void:
	_section_tabs = GridContainer.new()
	_section_tabs.name = "SatchelSections"
	_section_tabs.columns = 5
	_section_tabs.add_theme_constant_override("h_separation", 10)
	_section_tabs.add_theme_constant_override("v_separation", 10)
	root_vbox.add_child(_section_tabs)
	root_vbox.move_child(_section_tabs, 1)
	for entry in [
		{"id": "inventory", "label": "INVENTORY"},
		{"id": "equipment", "label": "EQUIPMENT"},
		{"id": "crafting", "label": "CRAFTING"},
		{"id": "skills", "label": "SKILLS"},
		{"id": "stats", "label": "STATS"},
	]:
		var tab := Button.new()
		tab.name = "%sTab" % str(entry.id).capitalize()
		tab.text = str(entry.label)
		tab.custom_minimum_size = Vector2(156, 58)
		tab.pressed.connect(_set_section.bind(str(entry.id)))
		_section_tabs.add_child(tab)
	_set_section_tab_styles()
	_section_tabs.set_meta("compact_columns", 2)

func _apply_satchel_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var metrics := UiKit.responsive_metrics(viewport_size)
	var margin := float(metrics.get("safe_margin", UiKit.SAFE_MARGIN_COMPACT))
	var width := minf(1180.0, viewport_size.x - margin * 2.0)
	var height := minf(1500.0, viewport_size.y - margin * 2.0)
	$Root.anchor_left = 0.5
	$Root.anchor_top = 0.5
	$Root.anchor_right = 0.5
	$Root.anchor_bottom = 0.5
	$Root.offset_left = -width * 0.5
	$Root.offset_right = width * 0.5
	$Root.offset_top = -height * 0.5
	$Root.offset_bottom = height * 0.5
	var items_list := $Root/VBox/ItemsList as ScrollContainer
	items_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	items_list.custom_minimum_size.y = 430.0 if bool(metrics.get("compact", false)) else 360.0
	if _section_tabs != null:
		_section_tabs.columns = 2 if bool(metrics.get("compact", false)) else 5
		for tab_node in _section_tabs.get_children():
			var tab := tab_node as Button
			if tab != null:
				tab.custom_minimum_size.x = (width - 10.0) / 2.0 if bool(metrics.get("compact", false)) else 156.0
	if _arsenal_grid != null:
		_arsenal_grid.columns = 2 if bool(metrics.get("compact", false)) else 3

func _set_section(section: String) -> void:
	_active_section = section
	var root_vbox := $Root/VBox as VBoxContainer
	var visibility := {
		"inventory": ["ItemsList", "EquipmentLoadout", "ItemDetail"],
		"equipment": ["EquipmentLoadout", "ForgedGear", "ItemDetail"],
		"crafting": ["CraftingBench", "ForgedGear"],
		"skills": ["ClassFooter"],
		"stats": ["CharacterStats"],
	}
	for node_name in ["ItemsList", "EquipmentLoadout", "ItemDetail", "ForgedGear",
			"CraftingBench", "ClassFooter", "CharacterStats"]:
		var node := root_vbox.get_node_or_null(node_name) as Control
		if node != null:
			node.visible = node_name in visibility.get(section, [])
	_set_section_tab_styles()
	if _bottom_close_button != null:
		_bottom_close_button.visible = true

func _set_section_tab_styles() -> void:
	if _section_tabs == null:
		return
	for tab_node in _section_tabs.get_children():
		var tab := tab_node as Button
		if tab == null:
			continue
		if tab.name.to_lower().begins_with(_active_section):
			UiKit.style_primary_button(tab)
		else:
			UiKit.style_secondary_button(tab)

func _build_crafting_panel(root_vbox: VBoxContainer) -> void:
	_craft_panel = PanelContainer.new()
	_craft_panel.name = "CraftingBench"
	_craft_panel.custom_minimum_size = Vector2(0, 118)
	_craft_panel.add_theme_stylebox_override("panel", UiKit.parchment_stylebox(UiKit.RADIUS_BUTTON))
	var outer := VBoxContainer.new()
	_craft_panel.add_child(outer)
	var title := Label.new()
	title.text = "CRAFTING BENCH  ·  GATHER IRON SHARDS TO BEGIN"
	UiKit.style_label(title, &"Eyebrow", 14)
	outer.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	outer.add_child(row)
	for recipe in CRAFT_RECIPES:
		var button := Button.new()
		button.custom_minimum_size = Vector2(250, 52)
		button.text = "%s\n%d IRON  ·  %d GOLD" % [recipe.name, int(recipe.materials.iron_shard), int(recipe.gold)]
		var can_afford := game_state.get_material_qty("iron_shard") >= int(recipe.materials.iron_shard) \
			and game_state.gold >= int(recipe.gold)
		var action := UiKit.action_state("available" if can_afford else "unavailable",
			"Materials and gold ready" if can_afford else "Gather iron shards and gold")
		button.tooltip_text = "%s · %s · Permanent %s upgrade." % [
			str(action.get("label", "")), str(action.get("detail", "")), recipe.name]
		UiKit.style_secondary_button(button)
		button.pressed.connect(_on_craft_recipe_pressed.bind(recipe))
		row.add_child(button)
	_craft_status = Label.new()
	_craft_status.text = _craft_material_summary()
	UiKit.style_label(_craft_status, &"Caption", 13)
	outer.add_child(_craft_status)
	root_vbox.add_child(_craft_panel)
	root_vbox.move_child(_craft_panel, 3)

func _craft_material_summary() -> String:
	return "IRON SHARDS: %d  ·  GOLD: %d  ·  Crafted gear is saved immediately." % [
		game_state.get_material_qty("iron_shard"), game_state.gold]

func _on_craft_recipe_pressed(recipe: Dictionary) -> void:
	var result := game_state.craft_transaction(
		str(recipe.category), str(recipe.id), 1, str(recipe.name), 0,
		recipe.materials, int(recipe.gold))
	var success := bool(result.get("success", false))
	var action := UiKit.action_state("purchased" if success else "failed",
		"Saved immediately" if success else "No resources were deducted")
	_craft_status.text = "%s · %s" % [str(action.get("label", "FAILED")),
		str(result.get("message", "Crafted %s." % recipe.name))] \
		if not success else "%s · %s · %s" % [str(action.get("label", "CRAFTED")),
			str(result.get("name", recipe.name)), _craft_material_summary()]
	_rebuild_inventory()
	_rebuild_equipment_loadout()

func _build_stats_panel(root_vbox: VBoxContainer) -> void:
	_stats_panel = PanelContainer.new()
	_stats_panel.name = "CharacterStats"
	_stats_panel.custom_minimum_size = Vector2(0, 150)
	_stats_panel.add_theme_stylebox_override("panel", UiKit.parchment_stylebox(UiKit.RADIUS_BUTTON))
	root_vbox.add_child(_stats_panel)
	root_vbox.move_child(_stats_panel, 2)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = _stats_column_count()
	_stats_grid.add_theme_constant_override("h_separation", 18)
	_stats_grid.add_theme_constant_override("v_separation", 2)
	_stats_panel.add_child(_stats_grid)
	_refresh_stats_panel()

func _stats_column_count() -> int:
	return 3 if get_viewport().get_visible_rect().size.x < UiKit.COMPACT_BREAKPOINT else 6

func _on_viewport_size_changed() -> void:
	if _stats_grid == null:
		return
	_stats_grid.columns = _stats_column_count()
	_refresh_stats_panel()

func _build_detail_panel(root_vbox: VBoxContainer) -> void:
	_detail_panel = PanelContainer.new()
	_detail_panel.name = "ItemDetail"
	_detail_panel.custom_minimum_size = Vector2(0, 140)
	_detail_panel.visible = false
	_detail_panel.add_theme_stylebox_override("panel", UiKit.parchment_stylebox(UiKit.RADIUS_BUTTON))
	root_vbox.add_child(_detail_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	_detail_panel.add_child(hbox)
	var preview_container := SubViewportContainer.new()
	preview_container.name = "GearPreview"
	preview_container.custom_minimum_size = Vector2(190, 150)
	preview_container.stretch = true
	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "GearPreviewViewport"
	_preview_viewport.size = Vector2i(380, 300)
	_preview_viewport.transparent_bg = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_container.add_child(_preview_viewport)
	hbox.add_child(preview_container)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	_detail_name = Label.new()
	_detail_name.text = ""
	UiKit.style_label(_detail_name, &"MenuTitle", 20)
	info_vbox.add_child(_detail_name)

	_detail_desc = Label.new()
	_detail_desc.text = ""
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_detail_desc, &"Body", 15)
	info_vbox.add_child(_detail_desc)

	_detail_stats = Label.new()
	_detail_stats.text = ""
	UiKit.style_label(_detail_stats, &"Caption", 14)
	info_vbox.add_child(_detail_stats)

	_detail_action = Button.new()
	_detail_action.text = "USE"
	_detail_action.custom_minimum_size = Vector2(140, 48)
	UiKit.style_primary_button(_detail_action)
	_detail_action.pressed.connect(_on_detail_action_pressed)
	hbox.add_child(_detail_action)

func _show_item_detail(item: Dictionary) -> void:
	_detail_panel.visible = true
	_detail_name.text = str(item.get("name", "UNKNOWN"))
	_detail_desc.text = str(item.get("desc", "No description available."))

	var rarity_names := ["COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]
	var rarity := clampi(int(item.get("rarity", 0)), 0, 4)
	var kind_names := ["Consumable", "Relic", "Quest"]
	var kind := clampi(int(item.get("kind", 0)), 0, 2)
	_detail_stats.text = "%s %s" % [rarity_names[rarity], kind_names[kind]]

	if item.get("kind", 0) == 0 and item.get("quantity", 0) > 0:
		_detail_item_id = str(item.get("id", ""))
		_detail_action.visible = true
		_detail_action.text = item.get("use_label", "USE")
	else:
		_detail_item_id = ""
		_detail_action.visible = false

func _refresh_gear_preview(kind: String, item: Dictionary) -> void:
	if _preview_viewport == null:
		return
	if is_instance_valid(_preview_root):
		_preview_root.queue_free()
	_preview_root = Node3D.new()
	_preview_root.name = "PreviewRig"
	_preview_viewport.add_child(_preview_root)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.9, 3.4)
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
		var authored_hero := authored_scene.instantiate() as Node3D
		authored_hero.name = "AuthoredHeroPreview"
		authored_hero.position = Vector3(0.0, 0.0, 0.0)
		authored_hero.scale = Vector3.ONE * 0.62
		_preview_root.add_child(authored_hero)
	else:
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.height = 1.55
		capsule.radius = 0.38
		body.mesh = capsule
		body.position = Vector3(0.0, 0.78, 0.0)
		body.material_override = _preview_material(Color(0.22, 0.27, 0.32))
		_preview_root.add_child(body)
		for side in [-1.0, 1.0]:
			var arm := MeshInstance3D.new()
			var arm_mesh := CapsuleMesh.new()
			arm_mesh.height = 0.92
			arm_mesh.radius = 0.13
			arm.mesh = arm_mesh
			arm.position = Vector3(0.47 * side, 0.86, 0.0)
			arm.rotation_degrees = Vector3(0.0, 0.0, -18.0 * side)
			arm.material_override = _preview_material(Color(0.18, 0.22, 0.27))
			_preview_root.add_child(arm)
	var item_mesh := MeshInstance3D.new()
	if kind == "weapon":
		var weapon_path := str(PREVIEW_WEAPON_PATHS.get(str(item.get("id", "")), ""))
		var weapon_scene := ResourceLoader.load(weapon_path, "PackedScene") as PackedScene if not weapon_path.is_empty() else null
		if weapon_scene != null:
			var authored_weapon := weapon_scene.instantiate() as Node3D
			authored_weapon.name = "AuthoredWeaponPreview"
			authored_weapon.position = Vector3(0.73, 1.02, 0.0)
			authored_weapon.rotation_degrees = Vector3(0.0, 0.0, -28.0)
			authored_weapon.scale = Vector3.ONE * 0.42
			_preview_root.add_child(authored_weapon)
			item_mesh.set_meta("asset_path", weapon_path)
		else:
			var blade := BoxMesh.new()
			blade.size = Vector3(0.12, 1.15, 0.18)
			item_mesh.mesh = blade
			item_mesh.position = Vector3(0.73, 1.02, 0.0)
			item_mesh.rotation_degrees = Vector3(0.0, 0.0, -28.0)
			item_mesh.material_override = _preview_material(Color(0.95, 0.56, 0.20))
	else:
		var chest := BoxMesh.new()
		chest.size = Vector3(0.84, 0.72, 0.48)
		item_mesh.mesh = chest
		item_mesh.position = Vector3(0.0, 0.92, -0.28)
		item_mesh.material_override = _preview_material(Color(0.28, 0.62, 0.78))
	if item_mesh.mesh != null:
		_preview_root.add_child(item_mesh)
	# Keep the item argument explicit so future previews can bind authored IDs
	# without coupling this isolated presentation scene to gameplay state.
	item_mesh.set_meta("item_id", str(item.get("id", "")))

func _preview_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.62
	return material

func _on_detail_action_pressed() -> void:
	if _detail_item_id.is_empty():
		return
	_on_use_item(_detail_item_id)
	_detail_panel.visible = false

func _refresh_stats_panel() -> void:
	if _stats_grid == null:
		return
	for child in _stats_grid.get_children():
		child.queue_free()
	var attack_total := game_state.get_base_auto_damage()
	var defense_total := game_state.armor_defense() + game_state.defense_stat()
	var speed_total := game_state.attack_speed_mult() * game_state.armor_speed_mult()
	var values := [
		["ATTACK", str(attack_total), Color(1.0, 0.66, 0.30)],
		["DEFENSE", str(defense_total), Color(0.42, 0.82, 0.98)],
		["CRIT CHANCE", "%d%%" % roundi(game_state.crit_chance() * 100.0), Color(1.0, 0.82, 0.34)],
		["CRIT MULT", "×%.2f" % game_state.crit_damage(), Color(0.92, 0.48, 1.0)],
		["ATTACK SPEED", "×%.2f" % speed_total, Color(0.48, 1.0, 0.62)],
		["HP", "%d / %d" % [game_state.hp, game_state.max_hp], Color(0.98, 0.42, 0.42)],
		["STRENGTH", str(game_state.stat_str), Color(0.92, 0.48, 0.32)],
		["DEXTERITY", str(game_state.stat_dex), Color(0.40, 0.86, 0.66)],
		["LUCK", str(game_state.stat_luk), Color(0.92, 0.70, 0.34)],
		["ENDURANCE", str(game_state.stat_end), Color(0.44, 0.68, 0.94)]
	]
	for entry in values:
		var label := Label.new()
		label.text = str(entry[0]) + "\n" + str(entry[1])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiKit.style_label(label, &"Caption", 14)
		label.add_theme_color_override("font_color", entry[2])
		_stats_grid.add_child(label)

func _rebuild_equipment_loadout() -> void:
	if _equipment_row == null:
		return
	# Detach BEFORE queue_free: re-adding a child that is still parented (or
	# already queued for deletion) throws "already has a parent" and can abort
	# the rebuild mid-way, leaving the equipment row stale/empty. The selected
	# item label is a persistent member — detach it but never free it, or the
	# next rebuild and _select_item would touch a freed instance.
	for child in _equipment_row.get_children():
		_equipment_row.remove_child(child)
		if child != _selected_item_label:
			child.queue_free()
	for slot in GameState.EQUIPMENT_SLOTS:
		_add_equipment_slot(str(slot).to_upper(), game_state.get_equipment_for_slot(slot),
			Color(0.96, 0.72, 0.30) if slot == &"weapon" else Color(0.42, 0.76, 0.96))
	_equipment_row.add_child(_selected_item_label)
	_refresh_stats_panel()

func _add_equipment_slot(slot_name: String, gear: Dictionary, tint: Color) -> void:
	var slot_id := StringName(slot_name.to_lower())
	var panel := EquipmentSlot.new()
	panel.configure(slot_id, gear, tint)
	panel.item_dropped.connect(_on_slot_item_dropped)
	_equipment_row.add_child(panel)
	return

	# Rarity-colored border
	var rarity := clampi(int(gear.get("rarity", 0)), 0, 4)
	var rarity_colors := [
		Color(0.58, 0.67, 0.65),  # Common
		Color(0.56, 0.67, 0.45),  # Uncommon
		Color(0.4, 0.72, 0.7),    # Rare
		Color(0.62, 0.48, 0.82),  # Epic
		Color(0.96, 0.72, 0.30),  # Legendary
	]
	var border_color: Color
	if not gear.is_empty():
		border_color = rarity_colors[rarity]
	else:
		border_color = tint

	var sb := UiKit.item_card_stylebox(border_color, not gear.is_empty())
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var slot_label := Label.new()
	slot_label.text = slot_name
	UiKit.style_label(slot_label, &"Eyebrow", 13)
	slot_label.add_theme_color_override("font_color", tint)
	vbox.add_child(slot_label)
	var name_label := Label.new()
	name_label.text = str(gear.get("name", "EMPTY SLOT")) if not gear.is_empty() else "EMPTY SLOT"
	UiKit.style_label(name_label, &"MenuTitle", 17)
	vbox.add_child(name_label)
	var stat_label := Label.new()
	if not gear.is_empty():
		stat_label.text = "ATK %d  ·  DEF %d" % [int(gear.get("atk", 0)), int(gear.get("defense", 0))]
	else:
		stat_label.text = "Visit the Ember Trader"
	UiKit.style_label(stat_label, &"Caption", 14)
	vbox.add_child(stat_label)
	_equipment_row.add_child(panel)

func _add_weapon_card(weapon: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.set_script(load("res://scripts/ui/equipment_drag_card.gd"))
	(panel as EquipmentDragCard).configure(weapon)
	panel.custom_minimum_size = Vector2(210, 126)

	# Rarity-colored border
	var rarity := clampi(int(weapon.get("rarity", 0)), 0, 4)
	var rarity_colors := [
		Color(0.58, 0.67, 0.65),  # Common
		Color(0.56, 0.67, 0.45),  # Uncommon
		Color(0.4, 0.72, 0.7),    # Rare
		Color(0.62, 0.48, 0.82),  # Epic
		Color(0.96, 0.72, 0.30),  # Legendary
	]
	var sb := UiKit.item_card_stylebox(rarity_colors[rarity],
		str(game_state.equipped_weapon.get("id", "")) == str(weapon.get("id", "")))
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var rarity_names := ["COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]
	var title := Label.new()
	title.text = "WEAPON  ·  %s" % str(weapon.get("name", "WEAPON"))
	UiKit.style_label(title, &"MenuTitle", 15)
	vbox.add_child(title)
	var meta := Label.new()
	var equipped_atk := int(game_state.equipped_weapon.get("atk", 0))
	var candidate_atk := int(weapon.get("atk", 0))
	var delta := candidate_atk - equipped_atk
	meta.text = "%s · ATK %d (%+d) · %s" % [rarity_names[rarity], candidate_atk,
		delta, str(weapon.get("style", "gear")).to_upper()]
	UiKit.style_label(meta, &"Caption", 13)
	vbox.add_child(meta)
	var identity := Label.new()
	var combat_profile := WeaponCombatProfiles.for_weapon(weapon)
	identity.text = "%s · %s\n%s" % [
		str(combat_profile.get("identity", "WEAPON STYLE")),
		str(weapon.get("passive_desc", "%d bound skills" % weapon.get("skills", []).size())),
		str(combat_profile.get("decision", "Choose this weapon for its combat rhythm."))]
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(identity, &"Caption", 12)
	vbox.add_child(identity)
	var inspect := Button.new()
	inspect.text = "INSPECT"
	inspect.custom_minimum_size = Vector2(0, 34)
	UiKit.style_secondary_button(inspect)
	inspect.pressed.connect(_on_inspect_weapon.bind(weapon.duplicate(true)))
	vbox.add_child(inspect)
	var equip := Button.new()
	var weapon_id := str(weapon.get("id", ""))
	var is_equipped := str(game_state.equipped_weapon.get("id", "")) == weapon_id
	var weapon_action := UiKit.action_state("equipped" if is_equipped else "owned")
	equip.text = str(weapon_action.get("label", "EQUIP"))
	equip.disabled = is_equipped
	equip.tooltip_text = "Currently equipped" if is_equipped else "Equip this weapon"
	UiKit.style_secondary_button(equip)
	equip.custom_minimum_size = Vector2(0, 42)
	equip.pressed.connect(_on_equip_weapon.bind(weapon_id))
	vbox.add_child(equip)
	var upgrade_cost: Dictionary = game_state.get_weapon_upgrade_cost(weapon)
	var upgrade := Button.new()
	var can_upgrade := bool(upgrade_cost.get("can_upgrade", false))
	var upgrade_action := UiKit.action_state("available" if can_upgrade else "unavailable",
		"Materials and gold ready" if can_upgrade else "Reach the next forge requirement")
	if can_upgrade:
		upgrade.text = "UPGRADE +%d  ·  +%d ATK  ·  %d IRON / %d GOLD" % [
			int(upgrade_cost.get("next_level", 1)),
			int(upgrade_cost.get("stat_gain", 0)),
			int(upgrade_cost.get("material_cost", 0)),
			int(upgrade_cost.get("gold_cost", 0))]
		upgrade.pressed.connect(_on_upgrade_weapon.bind(weapon_id))
	else:
		upgrade.text = "MAXIMUM FORGE"
		upgrade.disabled = true
	upgrade.tooltip_text = "%s · %s" % [str(upgrade_action.get("label", "")),
		str(upgrade_action.get("detail", ""))]
	UiKit.style_secondary_button(upgrade)
	upgrade.custom_minimum_size = Vector2(0, 42)
	vbox.add_child(upgrade)
	items_vbox.add_child(panel)

func _on_inspect_weapon(weapon: Dictionary) -> void:
	_refresh_gear_preview("weapon", weapon)
	var profile := WeaponCombatProfiles.for_weapon(weapon)
	var equipped_atk := int(game_state.equipped_weapon.get("atk", 0))
	var candidate_atk := int(weapon.get("atk", 0))
	var equipped_name := str(game_state.equipped_weapon.get("name", "NONE EQUIPPED"))
	var source := str(weapon.get("realm", weapon.get("source", "FORGED OR DISCOVERED"))).to_upper()
	_selected_item_label.text = "INSPECTING · %s\n%s · %s\nATK %d (%+d vs %s)\n%s\n%s\nSOURCE %s · SALVAGE %d IRON" % [
		str(weapon.get("name", "WEAPON")),
		str(profile.get("identity", "STYLE")),
		str(weapon.get("rarity", "COMMON")).to_upper(),
		candidate_atk, candidate_atk - equipped_atk,
		equipped_name,
		str(weapon.get("passive_desc", "No passive")),
		str(profile.get("decision", "Choose its rhythm.")),
		source, maxi(1, int(candidate_atk / 3))]

func _on_equip_weapon(weapon_id: String) -> void:
	if game_state.equip_weapon_by_id(weapon_id):
		var weapon := game_state.equipped_weapon
		_selected_item_label.text = "Equipped %s — %s" % [
			str(weapon.get("name", weapon_id)),
			str(weapon.get("passive_desc", "Its combat kit is now active."))]
		_rebuild_equipment_loadout()

func _on_upgrade_weapon(weapon_id: String) -> void:
	var result: Dictionary = game_state.upgrade_weapon(weapon_id)
	var success := bool(result.get("success", false))
	_selected_item_label.text = "ATK %d · upgrade +%d complete" % [
		int(result.get("atk", 0)), int(result.get("level", 0))] \
		if success else str(result.get("message", "Upgrade failed."))
	if success:
		AudioManager.play_forge_success()
		var scene := get_tree().current_scene
		var camera_rig := scene.get_node_or_null("CameraRig") if scene != null else null
		var hero := scene.get_node_or_null("Hero") if scene != null else null
		if camera_rig != null and hero != null \
				and camera_rig.has_method("play_focus_moment"):
			camera_rig.play_focus_moment(hero, Vector3(0.0, 3.8, 6.2),
				Vector3(0.0, 1.25, 0.0), 1.15)
	_rebuild_inventory()

func _rebuild_inventory() -> void:
	# Clear
	for child in items_vbox.get_children():
		child.queue_free()

	var total = 0
	for weapon in game_state.forged_weapons:
		if _inventory_filter in ["all", "weapon"]:
			_add_weapon_card(weapon)
	for armor in game_state.forged_armors:
		if _inventory_filter in ["all", "armor"]:
			_add_armor_card(armor)
	if _inventory_filter in ["all", "material"]:
		for material_id in game_state.raw_materials:
			var quantity := int(game_state.raw_materials[material_id])
			if quantity > 0:
				_add_material_card(str(material_id), quantity)
				total += quantity
	for item in game_state.inventory:
		total += item.quantity
		var item_filter := "consumable" if int(item.get("kind", 0)) == 0 else "quest"
		if item.quantity > 0 and _inventory_filter in ["all", item_filter]:
			_add_item_row(item)

	count_label.text = "%d items carried" % total

func _set_inventory_filter(filter_id: String) -> void:
	_inventory_filter = filter_id if filter_id in ["all", "weapon", "armor", "consumable", "material", "quest"] else "all"
	_refresh_filter_buttons()
	_rebuild_inventory()

func _add_material_card(material_id: String, quantity: int) -> void:
	var definition: Dictionary = game_state.MATERIAL_DEFS.get(material_id, {})
	var rarity := clampi(int(definition.get("rarity", 0)), 0, 2)
	var rarity_colors := [Color(0.58, 0.67, 0.65), Color(0.4, 0.72, 0.7), Color(0.62, 0.48, 0.82)]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(210, 92)
	panel.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(rarity_colors[rarity]))
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "MATERIAL  ·  %s ×%d" % [str(definition.get("name", material_id)), quantity]
	UiKit.style_label(title, &"MenuTitle", 16)
	box.add_child(title)
	var meta := Label.new()
	meta.text = "Used for crafting and upgrades  ·  %s" % str(definition.get("realm", "unknown")).to_upper()
	UiKit.style_label(meta, &"Caption", 13)
	box.add_child(meta)
	items_vbox.add_child(panel)

func _refresh_filter_buttons() -> void:
	for filter_id in _filter_buttons:
		var button := _filter_buttons[filter_id] as Button
		if button == null:
			continue
		if str(filter_id) == _inventory_filter:
			UiKit.style_primary_button(button)
		else:
			UiKit.style_secondary_button(button)

func _add_armor_card(armor: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.set_script(load("res://scripts/ui/equipment_drag_card.gd"))
	(panel as EquipmentDragCard).configure(armor)
	panel.custom_minimum_size = Vector2(210, 126)
	var rarity := clampi(int(armor.get("rarity", 0)), 0, 4)
	var rarity_colors := [Color(0.58, 0.67, 0.65), Color(0.56, 0.67, 0.45),
		Color(0.4, 0.72, 0.7), Color(0.62, 0.48, 0.82), Color(0.96, 0.72, 0.30)]
	panel.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(rarity_colors[rarity],
		str(game_state.equipped_armor.get("id", "")) == str(armor.get("id", ""))))
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "ARMOR  ·  %s" % str(armor.get("name", "ARMOR"))
	UiKit.style_label(title, &"MenuTitle", 15)
	vbox.add_child(title)
	var current_def := int(game_state.equipped_armor.get("defense", 0))
	var current_speed := float(game_state.equipped_armor.get("speed_mult", 1.0))
	var def := int(armor.get("defense", 0))
	var speed := float(armor.get("speed_mult", 1.0))
	var meta := Label.new()
	meta.text = "DEF %d (%+d)  ·  SPEED ×%.2f (%+0.2f)" % [def, def - current_def, speed, speed - current_speed]
	UiKit.style_label(meta, &"Caption", 13)
	vbox.add_child(meta)
	var armor_id := str(armor.get("id", ""))
	var inspect := Button.new()
	inspect.text = "INSPECT"
	inspect.custom_minimum_size = Vector2(0, 34)
	UiKit.style_secondary_button(inspect)
	inspect.pressed.connect(_on_inspect_armor.bind(armor.duplicate(true)))
	vbox.add_child(inspect)
	var equip := Button.new()
	var armor_equipped := str(game_state.equipped_armor.get("id", "")) == armor_id
	var armor_action := UiKit.action_state("equipped" if armor_equipped else "owned")
	equip.text = str(armor_action.get("label", "EQUIP"))
	equip.disabled = armor_equipped
	equip.tooltip_text = "Currently equipped" if armor_equipped else "Equip this armor"
	UiKit.style_secondary_button(equip)
	equip.custom_minimum_size = Vector2(0, 40)
	equip.pressed.connect(_on_equip_armor.bind(armor_id))
	vbox.add_child(equip)
	var cost: Dictionary = game_state.get_armor_upgrade_cost(armor)
	var upgrade := Button.new()
	var can_upgrade := bool(cost.get("can_upgrade", false))
	var upgrade_action := UiKit.action_state("available" if can_upgrade else "unavailable",
		"Materials and gold ready" if can_upgrade else "Reach the next forge requirement")
	if can_upgrade:
		upgrade.text = "UPGRADE +%d  ·  +%d DEF  ·  %d IRON / %d GOLD" % [int(cost.next_level),
			int(cost.get("stat_gain", 0)),
			int(cost.material_cost), int(cost.gold_cost)]
		upgrade.pressed.connect(_on_upgrade_armor.bind(armor_id))
	else:
		upgrade.text = "MAXIMUM FORGE"
		upgrade.disabled = true
	upgrade.tooltip_text = "%s · %s" % [str(upgrade_action.get("label", "")),
		str(upgrade_action.get("detail", ""))]
	UiKit.style_secondary_button(upgrade)
	upgrade.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(upgrade)
	items_vbox.add_child(panel)

func _on_inspect_armor(armor: Dictionary) -> void:
	_refresh_gear_preview("armor", armor)
	var current_def := int(game_state.equipped_armor.get("defense", 0))
	var current_speed := float(game_state.equipped_armor.get("speed_mult", 1.0))
	var defense := int(armor.get("defense", 0))
	var speed := float(armor.get("speed_mult", 1.0))
	var equipped_name := str(game_state.equipped_armor.get("name", "NONE EQUIPPED"))
	var source := str(armor.get("realm", armor.get("source", "FORGED OR DISCOVERED"))).to_upper()
	_selected_item_label.text = "INSPECTING · %s\nDEFENSIVE GEAR · %s\nDEF %d (%+d vs %s)\nSPEED ×%.2f (%+0.2f)\n%s\nSOURCE %s · SALVAGE %d IRON" % [
		str(armor.get("name", "ARMOR")), str(armor.get("rarity", "COMMON")).to_upper(),
		defense, defense - current_def, equipped_name, speed, speed - current_speed,
		str(armor.get("desc", "Protects the bearer through the next realm.")),
		source, maxi(1, int(defense / 2))]

func _on_equip_armor(armor_id: String) -> void:
	game_state.equip_armor(armor_id)
	_selected_item_label.text = "Equipped %s." % armor_id.to_upper()
	_rebuild_inventory()
	_rebuild_equipment_loadout()

func _on_slot_item_dropped(item_id: String, slot: StringName) -> void:
	if game_state.equip_item_to_slot(item_id, slot):
		_selected_item_label.text = "EQUIPPED · %s → %s" % [item_id.to_upper(), str(slot).to_upper()]
		_rebuild_equipment_loadout()
		_rebuild_inventory()
	else:
		_selected_item_label.text = "INVALID DROP · %s cannot use %s" % [item_id.to_upper(), str(slot).to_upper()]

func _on_upgrade_armor(armor_id: String) -> void:
	var result: Dictionary = game_state.upgrade_armor(armor_id)
	var success := bool(result.get("success", false))
	_selected_item_label.text = "DEF %d · upgrade +%d complete" % [int(result.get("defense", 0)),
		int(result.get("level", 0))] if success else str(result.get("message", "Upgrade failed."))
	if success:
		AudioManager.play_forge_success()
		var scene := get_tree().current_scene
		var camera_rig := scene.get_node_or_null("CameraRig") if scene != null else null
		var hero := scene.get_node_or_null("Hero") if scene != null else null
		if camera_rig != null and hero != null \
				and camera_rig.has_method("play_focus_moment"):
			camera_rig.play_focus_moment(hero, Vector3(0.0, 3.8, 6.2),
				Vector3(0.0, 1.25, 0.0), 1.15)
	_rebuild_inventory()
	_rebuild_equipment_loadout()

func _add_item_row(item: Dictionary) -> void:
	var panel = PanelContainer.new()
	panel.add_theme_constant_override("panel_inset", 14)

	# Rarity-colored border
	var rarity_colors := [
		Color(0.58, 0.67, 0.65),  # Common
		Color(0.56, 0.67, 0.45),  # Uncommon
		Color(0.4, 0.72, 0.7),    # Rare
		Color(0.62, 0.48, 0.82),  # Epic
		Color(0.96, 0.72, 0.30),  # Legendary
	]
	var rarity := clampi(int(item.get("rarity", 0)), 0, 4)
	var sb := UiKit.item_card_stylebox(rarity_colors[rarity])
	panel.add_theme_stylebox_override("panel", sb)

	var hbox = HBoxContainer.new()
	panel.add_child(hbox)

	var glyph_well := PanelContainer.new()
	glyph_well.custom_minimum_size = Vector2(64, 64)
	glyph_well.add_theme_stylebox_override("panel", UiKit.icon_well_stylebox(rarity_colors[rarity]))
	hbox.add_child(glyph_well)
	var icon := IconRegistry.icon_for(str(item.get("id", "")))
	if icon != null:
		var image := TextureRect.new()
		image.texture = icon
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.custom_minimum_size = Vector2(52, 52)
		glyph_well.add_child(image)
	else:
		var glyph := Label.new()
		glyph.text = str(item.get("glyph", "ITEM"))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UiKit.style_label(glyph, "", 20)
		glyph_well.add_child(glyph)

	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_label = Label.new()
	name_label.text = "%s ×%d" % [item.name, item.quantity]
	UiKit.style_label(name_label, &"MenuTitle", 18)
	info.add_child(name_label)

	var rarity_color = rarity_colors[rarity]
	var meta_label = Label.new()
	meta_label.text = "%s · %s" % [["Common", "Uncommon", "Rare", "Epic", "Legendary"][rarity], ["Consumable", "Relic", "Quest"][item.kind]]
	UiKit.style_label(meta_label, &"Caption", 15)
	meta_label.add_theme_color_override("font_color", rarity_color)
	info.add_child(meta_label)

	var stats_label = Label.new()
	if item.get("stats") is Array:
		stats_label.text = " · ".join(item.stats)
	else:
		stats_label.text = ""
	UiKit.style_label(stats_label, &"Caption", 15)
	info.add_child(stats_label)

	# Click to show detail panel
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_item_detail(item)
		elif event is InputEventScreenTouch and event.pressed:
			_show_item_detail(item)
	)

	if item.kind == 0 and item.quantity > 0 and item.use_label:  # Consumable
		var use_btn = Button.new()
		use_btn.text = item.use_label
		use_btn.custom_minimum_size = Vector2(150, 0)
		UiKit.style_secondary_button(use_btn)
		use_btn.pressed.connect(_on_use_item.bind(item.id))
		hbox.add_child(use_btn)

	items_vbox.add_child(panel)

func _on_inventory_changed(_notice: String = "", _count: int = 0) -> void:
	_rebuild_inventory()
	_update_forged_gear()
	_rebuild_equipment_loadout()

func _on_weapon_changed(_weapon: Dictionary) -> void:
	_update_forged_gear()
	_rebuild_skill_kit()
	_rebuild_equipment_loadout()
	_refresh_stats_panel()

func _on_armor_changed(_armor: Dictionary) -> void:
	_rebuild_armor_row()
	_rebuild_equipment_loadout()
	_refresh_stats_panel()

func _on_stats_changed() -> void:
	_refresh_stats_panel()

func _on_use_item(item_id: String) -> void:
	var result = game_state.use_item(item_id)
	_rebuild_inventory()
	_update_forged_gear()
	print(result)

func _update_forged_gear() -> void:
	var weapon = game_state.equipped_weapon
	var style_names := {
		"slash": "SLASH", "magic": "MAGIC", "blunt": "BLUNT"
	}
	weapon_name.text = str(weapon.get("name", "NO WEAPON"))
	weapon_stats.text = "%s · ATK %d · REACH %.1f · %d SKILL%s" % [
		style_names.get(str(weapon.get("style", "")), "GEAR"),
		int(weapon.get("atk", 0)), float(weapon.get("range", 0.0)),
		weapon.get("skills", []).size(),
		"" if weapon.get("skills", []).size() == 1 else "S"]

func _rebuild_armor_row() -> void:
	# Armor line lives right after the weapon row, rebuilt on change
	var existing := forged_vbox.get_node_or_null("ArmorRow")
	if existing:
		existing.queue_free()
	var row := HBoxContainer.new()
	row.name = "ArmorRow"
	forged_vbox.add_child(row)

	var armor: Dictionary = game_state.equipped_armor
	var icon := IconRegistry.icon_for(str(armor.get("id", ""))) if not armor.is_empty() else null
	if icon != null:
		var image := TextureRect.new()
		image.texture = icon
		image.custom_minimum_size = Vector2(48, 48)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(image)
	else:
		var glyph := Label.new()
		glyph.text = "ARMOR" if armor.is_empty() else "ARM"
		UiKit.style_label(glyph, "", 18)
		row.add_child(glyph)

	var info := VBoxContainer.new()
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = str(armor.get("name", "TRAVELING LIGHT"))
	UiKit.style_label(name_label, &"MenuTitle", 18)
	info.add_child(name_label)
	var desc := Label.new()
	desc.text = str(armor.get("desc", "No armor equipped — visit the Ember Trader.")) \
		if not armor.is_empty() else "No armor equipped — visit the Ember Trader."
	UiKit.style_label(desc, &"Caption", 15)
	info.add_child(desc)

## One panel per skill in the equipped weapon's kit (1..3 slots)
## Uses GridContainer for proper wrapping on narrow screens.
func _rebuild_skill_kit() -> void:
	_skill_cd_labels.clear()
	for child in skill_kit.get_children():
		child.queue_free()

	var skills: Array = game_state.equipped_weapon.get("skills", [])
	# Switch to GridContainer for better wrapping if 3 skills
	if skills.size() >= 3:
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		skill_kit.add_child(grid)
		for i in skills.size():
			_add_skill_card(grid, skills[i], i)
	else:
		for i in skills.size():
			_add_skill_card(skill_kit, skills[i], i)

func _add_skill_card(parent: Container, sk: Dictionary, index: int) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(188, 92)
	panel.add_theme_constant_override("panel_inset", 8)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var icon := FightButton.new()
	icon.custom_minimum_size = Vector2(52, 52)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.shape = FightButton.Shape.CIRCLE
	icon.skill_kind = str(sk.get("type", ""))
	icon.accent = Color(0.62, 0.55, 0.96) if str(game_state.equipped_weapon.get("style")) == "magic" else Color(0.96, 0.72, 0.30)
	icon.tooltip_text = str(sk.get("desc", "Skill"))
	header.add_child(icon)
	var rune := Label.new()
	rune.text = "%d. %s" % [index + 1, sk.get("name", "?")]
	var rune_tint := Color(0.62, 0.55, 0.96) \
		if str(game_state.equipped_weapon.get("style")) == "magic" \
		else Color(0.96, 0.84, 0.47)
	UiKit.style_label(rune, "", 16)
	rune.add_theme_color_override("font_color", rune_tint)
	header.add_child(rune)
	var cd := Label.new()
	cd.text = game_state.get_slot_cooldown_text(index)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_label(cd, &"Caption", 14)
	header.add_child(cd)
	_skill_cd_labels.append(cd)

	var desc := Label.new()
	var fallback := "Cooldown %ds." % int(sk.get("cooldown", 0))
	desc.text = str(sk.get("desc", fallback))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(160, 0)
	UiKit.style_label(desc, &"Caption", 14)
	vbox.add_child(desc)

func _on_close_pressed() -> void:
	visible = false

func toggle() -> void:
	visible = not visible
	if visible:
		_set_section("inventory")
		_rebuild_inventory()
		_rebuild_equipment_loadout()

func show_stats() -> void:
	visible = true
	_set_section("stats")
	_rebuild_inventory()
	_rebuild_equipment_loadout()
	if _stats_panel != null:
		_stats_panel.grab_focus()

func _on_forge_pressed() -> void:
	visible = false
	var forge = get_tree().root.find_child("ForgeMenu", true, false)
	if forge:
		forge.visible = true
