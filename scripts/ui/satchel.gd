extends CanvasLayer
class_name SatchelUI

## Focused four-tab Satchel. GameState remains the owner of inventory, gear,
## crafting, and stats; this scene only presents and routes those actions.

@onready var game_state: Node = get_node("/root/GameState")
@onready var root_vbox: VBoxContainer = $Root/VBox
@onready var close_button: Button = $Root/Header/CloseButton
@onready var count_label: Label = $Root/Header/CountLabel

var _section_tabs: GridContainer
var _page_host: Control
var _items_page: ScrollContainer
var _hero_page: ScrollContainer
var _stats_page: ScrollContainer
var _crafting_page: ScrollContainer
var _items_grid: GridContainer
var _craft_grid: GridContainer
var _filter_bar: GridContainer
var _filter_buttons: Dictionary = {}
var _inspect_sheet: PanelContainer
var _inspect_title: Label
var _inspect_detail: Label
var _inspect_actions: HBoxContainer
var _selected_item_label: Label
var _inspected_item: Dictionary = {}
var _salvage_confirm_id := ""
var _craft_status: Label
var _hero_preview: HeroPreviewPanel
var _stats_component: StatsPanel
var _active_section := "items"
var _inventory_filter := "all"
var _sort_mode := "rarity"
var _sort_button: Button = null
var _loadout_strip: HBoxContainer = null
var _empty_state: Control = null
const SORTS: Array[String] = ["rarity", "name", "newest"]
var _freeze_was_visible := false
var _freeze_held := false

const FILTERS: Array[String] = ["all", "weapon", "armor", "consumable", "material", "quest"]
# GameState.EQUIPMENT_SLOTS remains the authoritative equipment contract;
# this focused surface exposes its weapon and chest slots beside the hero.
## Recipe order comes from CraftingData so a new recipe can never be craftable
## in data yet invisible here (and no stale ids survive a recipe removal).

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root_panel := $Root as Control
	if root_panel is PanelContainer:
		UiKit.apply_glass(root_panel as PanelContainer)
	else:
		root_panel.add_theme_stylebox_override("panel", UiKit.glass_stylebox())
	UiKit.style_role_button(close_button, "ghost", UiKit.COPPER)
	close_button.pressed.connect(_on_close_pressed)
	UiKit.ornament_corners(root_panel, UiKit.COPPER, 20.0, 2.0, 0.55)
	_build_tabs()
	_build_pages()
	_connect_signals()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_apply_satchel_layout()
	call_deferred("_apply_satchel_layout")
	_rebuild_inventory()
	_refresh_crafting()
	open_tab(&"items")

func _process(_delta: float) -> void:
	if visible == _freeze_was_visible:
		return
	_freeze_was_visible = visible
	if visible:
		game_state.push_world_freeze()
		_freeze_held = true
	else:
		_release_world_freeze()

func _connect_signals() -> void:
	game_state.loot_received.connect(_on_inventory_changed)
	game_state.inventory_changed.connect(_on_inventory_changed)
	game_state.materials_changed.connect(_on_materials_changed)
	game_state.weapon_changed.connect(_on_weapon_changed)
	game_state.armor_changed.connect(_on_armor_changed)
	if game_state.has_signal("stats_changed"):
		game_state.stats_changed.connect(_on_stats_changed)

func _build_tabs() -> void:
	_section_tabs = GridContainer.new()
	_section_tabs.name = "SatchelSections"
	_section_tabs.columns = 4
	_section_tabs.add_theme_constant_override("h_separation", 6)
	_section_tabs.add_theme_constant_override("v_separation", 6)
	root_vbox.add_child(_section_tabs)
	root_vbox.move_child(_section_tabs, 1)
	for entry in [
		{"id": "items", "label": "ITEMS"},
		{"id": "hero", "label": "HERO"},
		{"id": "stats", "label": "STATS"},
		{"id": "crafting", "label": "CRAFTING"},
	]:
		var tab := Button.new()
		tab.name = "%sTab" % str(entry.id).capitalize()
		tab.text = str(entry.label)
		tab.custom_minimum_size = Vector2(0, 58)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.focus_mode = Control.FOCUS_ALL
		tab.pressed.connect(open_tab.bind(StringName(entry.id)))
		_section_tabs.add_child(tab)

func _build_pages() -> void:
	_page_host = Control.new()
	_page_host.name = "TabContent"
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_page_host)

	_items_page = _new_page("ItemsPage")
	var items_content := VBoxContainer.new()
	items_content.name = "ItemsContent"
	items_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items_content.add_theme_constant_override("separation", 8)
	_items_page.add_child(items_content)
	items_content.add_child(UiKit.section_header("Satchel", UiKit.COPPER))
	_filter_bar = GridContainer.new()
	_filter_bar.name = "CategoryToggler"
	_filter_bar.columns = 3
	_filter_bar.add_theme_constant_override("h_separation", 6)
	_filter_bar.add_theme_constant_override("v_separation", 6)
	items_content.add_child(_filter_bar)
	for filter_id in FILTERS:
		var filter_button := Button.new()
		filter_button.text = filter_id.to_upper()
		filter_button.custom_minimum_size = Vector2(0, UiKit.TOUCH_TARGET_MIN)
		filter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filter_button.focus_mode = Control.FOCUS_ALL
		filter_button.pressed.connect(_set_inventory_filter.bind(filter_id))
		UiKit.style_role_button(filter_button, "ghost", UiKit.COPPER, 20)
		_filter_bar.add_child(filter_button)
		_filter_buttons[filter_id] = filter_button
	# What is equipped stays visible while browsing, so a comparison never has
	# to be remembered from another page.
	_loadout_strip = HBoxContainer.new()
	_loadout_strip.name = "LoadoutStrip"
	_loadout_strip.add_theme_constant_override("separation", 10)
	items_content.add_child(_loadout_strip)
	# The drag hint lives here once. Repeating it on every card cost a text row
	# per card and forced the grid wider than the phone frame.
	var tools := HBoxContainer.new()
	tools.name = "GridTools"
	tools.add_theme_constant_override("separation", 10)
	items_content.add_child(tools)
	var grid_hint := Label.new()
	grid_hint.name = "GridHint"
	grid_hint.text = "HOLD A CARD TO DRAG IT ONTO A HERO SLOT"
	grid_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(grid_hint, &"Caption", 18)
	grid_hint.add_theme_color_override("font_color", Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.58))
	tools.add_child(grid_hint)
	_sort_button = Button.new()
	_sort_button.name = "SortButton"
	_sort_button.custom_minimum_size = Vector2(0, UiKit.TOUCH_TARGET_MIN)
	_sort_button.tooltip_text = "Cycle the order of this list"
	_sort_button.pressed.connect(_cycle_sort)
	tools.add_child(_sort_button)
	_items_grid = GridContainer.new()
	_items_grid.name = "InventoryGrid"
	_items_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_grid.add_theme_constant_override("h_separation", 10)
	_items_grid.add_theme_constant_override("v_separation", 10)
	items_content.add_child(_items_grid)

	_hero_page = _new_page("HeroPage")
	var hero_content := VBoxContainer.new()
	hero_content.name = "HeroContent"
	hero_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_content.add_theme_constant_override("separation", 10)
	_hero_page.add_child(hero_content)
	_hero_preview = HeroPreviewPanel.new()
	_hero_preview.name = "HeroPreview"
	_hero_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_preview.equip_requested.connect(_on_hero_equipped)
	_hero_preview.drop_rejected.connect(_on_hero_drop_rejected)
	hero_content.add_child(_hero_preview)

	_stats_page = _new_page("StatsPage")
	var stats_content := VBoxContainer.new()
	stats_content.name = "StatsContent"
	stats_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_content.add_theme_constant_override("separation", 8)
	_stats_page.add_child(stats_content)
	_stats_component = StatsPanel.new()
	_stats_component.name = "Stats"
	_stats_component.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_content.add_child(_stats_component)

	_crafting_page = _new_page("CraftingPage")
	var crafting_content := VBoxContainer.new()
	crafting_content.name = "CraftingContent"
	crafting_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crafting_content.add_theme_constant_override("separation", 8)
	_crafting_page.add_child(crafting_content)
	crafting_content.add_child(UiKit.section_header("Recipes", UiKit.VERDIGRIS,
		"materials are spent on craft"))
	_craft_grid = GridContainer.new()
	_craft_grid.name = "Recipes"
	_craft_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_grid.add_theme_constant_override("h_separation", 10)
	_craft_grid.add_theme_constant_override("v_separation", 10)
	crafting_content.add_child(_craft_grid)
	_craft_status = Label.new()
	_craft_status.name = "CraftingStatus"
	_craft_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_craft_status, &"Body", 20)
	crafting_content.add_child(_craft_status)

	_build_inspect_sheet()

func _new_page(page_name: String) -> ScrollContainer:
	var page := ScrollContainer.new()
	page.name = page_name
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_host.add_child(page)
	return page

func _build_inspect_sheet() -> void:
	_inspect_sheet = PanelContainer.new()
	_inspect_sheet.name = "InspectSheet"
	_inspect_sheet.visible = false
	_inspect_sheet.custom_minimum_size = Vector2(0, 196)
	_inspect_sheet.add_theme_stylebox_override("panel", UiKit.parchment_stylebox(UiKit.RADIUS_PANEL))
	UiKit.ornament_corners(_inspect_sheet, UiKit.COPPER, 16.0, 2.0, 0.5)
	root_vbox.add_child(_inspect_sheet)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_inspect_sheet.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	_inspect_title = Label.new()
	_inspect_title.name = "Title"
	UiKit.style_label(_inspect_title, &"MenuTitle", 32)
	info.add_child(_inspect_title)
	_inspect_detail = Label.new()
	_inspect_detail.name = "Detail"
	_inspect_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_inspect_detail, &"Body", 20)
	info.add_child(_inspect_detail)
	# Compatibility field for older inspection callers; the detail is now only
	# present while this temporary sheet is open.
	_selected_item_label = _inspect_detail
	_inspect_actions = HBoxContainer.new()
	_inspect_actions.name = "Actions"
	_inspect_actions.add_theme_constant_override("separation", 6)
	row.add_child(_inspect_actions)
	var close_inspect := Button.new()
	close_inspect.name = "Close"
	close_inspect.text = "CLOSE"
	close_inspect.custom_minimum_size = Vector2(110, UiKit.TOUCH_TARGET_MIN)
	close_inspect.pressed.connect(_hide_inspect_sheet)
	UiKit.style_role_button(close_inspect, "ghost", UiKit.COPPER, 20)
	row.add_child(close_inspect)

func _apply_satchel_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var metrics := UiKit.responsive_metrics(viewport_size)
	var compact := bool(metrics.get("compact", false))
	var margin := float(metrics.get("safe_margin", UiKit.SAFE_MARGIN_COMPACT))
	var width := minf(1180.0, maxf(320.0, viewport_size.x - margin * 2.0))
	var height := minf(1500.0, maxf(420.0, viewport_size.y - margin * 2.0))
	$Root.anchor_left = 0.5
	$Root.anchor_top = 0.5
	$Root.anchor_right = 0.5
	$Root.anchor_bottom = 0.5
	$Root.offset_left = -width * 0.5
	$Root.offset_right = width * 0.5
	$Root.offset_top = -height * 0.5
	$Root.offset_bottom = height * 0.5
	if _section_tabs != null:
		_section_tabs.columns = 2 if compact else 4
		for tab_node in _section_tabs.get_children():
			var tab := tab_node as Button
			if tab != null:
				tab.custom_minimum_size.x = (width - 6.0) / 2.0 if compact else 0.0
	if _filter_bar != null:
		_filter_bar.columns = 3 if compact else 6
	if _items_grid != null:
		# One column on a phone: an item row needs room for its icon, name,
		# rarity line and comparison, and two 271 px columns force wraps that
		# make card heights unpredictable.
		_items_grid.columns = 1 if compact else 2
	if _craft_grid != null:
		_craft_grid.columns = 1 if compact else 2
	_refresh_tab_styles()

func _on_viewport_size_changed() -> void:
	_apply_satchel_layout()

func _is_compact() -> bool:
	return get_viewport().get_visible_rect().size.x < UiKit.COMPACT_BREAKPOINT

## Kept for existing section-routing callers. New callers should use open_tab.
func _set_section(section: String) -> void:
	var mapped := section
	if section == "inventory":
		mapped = "items"
	elif section == "equipment" or section == "skills":
		mapped = "hero"
	open_tab(StringName(mapped))

func open_tab(tab_id: StringName) -> void:
	var requested := str(tab_id).to_lower()
	if requested not in ["items", "hero", "stats", "crafting"]:
		requested = "items"
	_active_section = requested
	for page in [_items_page, _hero_page, _stats_page, _crafting_page]:
		if page != null:
			page.visible = page.name.to_lower().begins_with(requested)
	_refresh_tab_styles()
	if requested == "stats" and _stats_component != null:
		_stats_component.open()
	elif requested == "hero" and _hero_preview != null:
		_hero_preview.grab_focus()

func _refresh_tab_styles() -> void:
	if _section_tabs == null:
		return
	for tab_node in _section_tabs.get_children():
		var tab := tab_node as Button
		if tab == null:
			continue
		var tab_id := tab.name.replace("Tab", "").to_lower()
		if tab_id == _active_section:
			UiKit.style_role_button(tab, "primary", UiKit.EMBER, 24)
		else:
			UiKit.style_role_button(tab, "ghost", UiKit.COPPER, 24)

func _build_inspect_action(text: String, action_id: String, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, UiKit.TOUCH_TARGET_MIN)
	button.disabled = disabled
	var role := "ghost"
	var accent := UiKit.COPPER
	if action_id == "equip" or action_id == "use":
		role = "primary"
		accent = UiKit.EMBER
	elif action_id == "salvage":
		role = "danger"
		accent = UiKit.BLOOD
	UiKit.style_role_button(button, role, accent, 20)
	button.pressed.connect(_on_inspect_action.bind(action_id))
	_inspect_actions.add_child(button)
	return button

func _show_item_detail(item: Dictionary) -> void:
	# Re-rendering the same item (to arm a confirmation) must not clear arming.
	if str(item.get("id", "")) != str(_inspected_item.get("id", "")):
		_salvage_confirm_id = ""
	_inspected_item = item.duplicate(true)
	_inspect_title.text = str(item.get("name", item.get("id", "ITEM")))
	_inspect_detail.text = _item_detail_text(_inspected_item)
	for child in _inspect_actions.get_children():
		child.queue_free()
	var kind := _item_kind(item)
	if kind == "weapon" or kind == "armor":
		var id := str(item.get("id", ""))
		var equipped_id := str(game_state.equipped_weapon.get("id", "")) if kind == "weapon" else str(game_state.equipped_armor.get("id", ""))
		var is_equipped := id == equipped_id
		# Shared semantic states drive the tooltip and disabled state, so the same
		# gear reads the same here, in the forge, and in the shop instead of a
		# one-off literal per surface. The button copy itself stays as designed:
		# the mobile EQUIP fallback is asserted verbatim by the equipment suite.
		var equip_action := UiKit.action_state("equipped" if is_equipped else "owned",
			"Currently equipped" if is_equipped else "Equip this gear")
		var equip_button := _build_inspect_action(
			"EQUIPPED" if is_equipped else "EQUIP", "equip", is_equipped)
		equip_button.tooltip_text = str(equip_action.get("detail", ""))
		var upgrade_cost: Dictionary = game_state.get_weapon_upgrade_cost(item) \
			if kind == "weapon" else game_state.get_armor_upgrade_cost(item)
		var can_upgrade := bool(upgrade_cost.get("can_upgrade", false))
		var upgrade_action := UiKit.action_state("available" if can_upgrade else "unavailable",
			"Materials and gold ready" if can_upgrade else "Reach the next forge requirement")
		var upgrade_button := _build_inspect_action("UPGRADE", "upgrade", false)
		upgrade_button.tooltip_text = str(upgrade_action.get("detail", ""))
		var salvage_value: int = game_state.get_weapon_salvage_value(item) if kind == "weapon" \
			else game_state.get_armor_salvage_value(item)
		var blocker: String = game_state.salvage_blocker(id, kind)
		var confirm_salvage := _salvage_confirm_id == id
		_build_inspect_action("CONFIRM SALVAGE · %d IRON" % salvage_value if confirm_salvage \
			else "SALVAGE · %d IRON" % salvage_value, "salvage", not blocker.is_empty())
		if not blocker.is_empty():
			_inspect_actions.get_child(_inspect_actions.get_child_count() - 1).tooltip_text = blocker
	elif kind == "consumable":
		_build_inspect_action(str(item.get("use_label", "USE")), "use", int(item.get("quantity", 0)) <= 0)
	_inspect_sheet.visible = true

func _item_detail_text(item: Dictionary) -> String:
	var kind := _item_kind(item).to_upper()
	var rarity := _rarity_label(int(item.get("rarity", 0)))
	if kind == "WEAPON":
		var current_atk := int(game_state.equipped_weapon.get("atk", 0))
		var attack := int(item.get("atk", 0))
		var cost: Dictionary = game_state.get_weapon_upgrade_cost(item)
		var upgrade_text := "MAXIMUM FORGE"
		if bool(cost.get("can_upgrade", false)):
			upgrade_text = "UPGRADE +%d · +%d ATK · %d IRON / %d GOLD" % [
				int(cost.get("next_level", 1)), int(cost.get("stat_gain", 0)),
				int(cost.get("material_cost", 0)), int(cost.get("gold_cost", 0))]
		return "%s · ATK %d (%+d vs current) · %s · SALVAGE %d IRON\n%s\n%s" % [
			rarity, attack, attack - current_atk, str(item.get("style", "gear")).to_upper(),
			game_state.get_weapon_salvage_value(item),
			str(item.get("passive_desc", item.get("desc", "No passive."))), upgrade_text]
	if kind == "ARMOR":
		var current_defense := int(game_state.equipped_armor.get("defense", 0))
		var defense := int(item.get("defense", 0))
		var cost: Dictionary = game_state.get_armor_upgrade_cost(item)
		var upgrade_text := "MAXIMUM FORGE"
		if bool(cost.get("can_upgrade", false)):
			upgrade_text = "UPGRADE +%d · +%d DEF · %d IRON / %d GOLD" % [
				int(cost.get("next_level", 1)), int(cost.get("stat_gain", 0)),
				int(cost.get("material_cost", 0)), int(cost.get("gold_cost", 0))]
		return "DEFENSIVE GEAR · %s · DEF %d (%+d vs current) · SPEED ×%.2f · SOURCE %s · SALVAGE %d IRON\n%s\n%s" % [
			rarity, defense, defense - current_defense, float(item.get("speed_mult", 1.0)),
			str(item.get("source", item.get("realm", "FORGED OR DISCOVERED"))).to_upper(),
			game_state.get_armor_salvage_value(item),
			str(item.get("desc", "Protects the bearer through the next realm.")), upgrade_text]
	if kind == "MATERIAL":
		return "%s · %s" % [rarity, str(item.get("realm", "crafting")).to_upper()]
	return "%s · %s" % [rarity, str(item.get("desc", item.get("use_label", "No action available.")))]

func _hide_inspect_sheet() -> void:
	_inspected_item.clear()
	_inspect_sheet.visible = false

func _on_inspect_action(action_id: String) -> void:
	if _inspected_item.is_empty():
		return
	var item_id := str(_inspected_item.get("id", ""))
	var kind := _item_kind(_inspected_item)
	var result: Dictionary = {}
	match action_id:
		"equip":
			var slot: StringName = &"weapon" if kind == "weapon" else &"chest"
			if game_state.can_equip_item(_inspected_item, slot) and game_state.equip_item_to_slot(item_id, slot):
				_hide_inspect_sheet()
			else:
				_inspect_detail.text = "Cannot equip this item in that slot."
		"upgrade":
			result = game_state.upgrade_weapon(item_id) if kind == "weapon" else game_state.upgrade_armor(item_id)
			_inspect_detail.text = str(result.get("message", "Upgrade complete.")) if not bool(result.get("success", false)) else "Upgrade complete."
			_rebuild_inventory()
		"salvage":
			if _salvage_confirm_id != item_id:
				# Destructive: the first press only arms the confirmation.
				_salvage_confirm_id = item_id
				_show_item_detail(_inspected_item)
			else:
				result = game_state.salvage_gear(item_id, kind)
				_salvage_confirm_id = ""
				if bool(result.get("success", false)):
					_hide_inspect_sheet()
				else:
					_inspect_detail.text = str(result.get("message", "Cannot salvage this item."))
		"use":
			game_state.use_item(item_id)
			_hide_inspect_sheet()
	_rebuild_inventory()

func _add_gear_card(item: Dictionary) -> void:
	var card := EquipmentDragCard.new()
	card.configure(item)
	card.custom_minimum_size = Vector2(0, 118)
	var rarity := clampi(int(item.get("rarity", 0)), 0, 4)
	var accent := _rarity_color(rarity)
	var kind := _item_kind(item)
	var slot: StringName = &"weapon" if kind == "weapon" else &"chest"
	var equipped: Dictionary = game_state.get_equipment_for_slot(slot)
	var is_equipped := str(item.get("id", "")) == str(equipped.get("id", ""))
	card.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(accent, is_equipped))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	card.add_child(line)
	line.add_child(UiKit.icon_well(str(item.get("id", "")), accent, 56.0))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	line.add_child(info)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	info.add_child(title_row)
	var title := Label.new()
	title.text = str(item.get("name", item.get("id", "GEAR"))).to_upper()
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_label(title, &"RowLabel", 22)
	title_row.add_child(title)
	if is_equipped:
		title_row.add_child(UiKit.badge("Equipped", UiKit.VERDIGRIS, 16))
	# The stat line wraps and the delta owns its own line: sharing one row made
	# the two of them set the grid column width and clip the second column.
	var stat := "ATK %d" % int(item.get("atk", 0)) if kind == "weapon" else \
		"DEF %d · SPEED ×%.2f" % [int(item.get("defense", 0)), float(item.get("speed_mult", 1.0))]
	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 10)
	info.add_child(meta_row)
	var meta := Label.new()
	meta.text = "%s · %s" % [_rarity_label(rarity), stat]
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.style_label(meta, &"Body", 20)
	meta.add_theme_color_override("font_color", accent)
	meta_row.add_child(meta)
	if not equipped.is_empty() and not is_equipped:
		var current := int(equipped.get("atk", 0)) if kind == "weapon" else int(equipped.get("defense", 0))
		var candidate := int(item.get("atk", 0)) if kind == "weapon" else int(item.get("defense", 0))
		var delta := UiKit.delta_text(float(candidate - current),
			" ATK" if kind == "weapon" else " DEF")
		var delta_label := Label.new()
		delta_label.text = "VS EQUIPPED  %s" % str(delta.get("text", ""))
		delta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.style_label(delta_label, &"RowLabel", 22)
		delta_label.add_theme_color_override("font_color",
			UiKit.VERDIGRIS_BRIGHT if bool(delta.get("better", false)) else UiKit.DANGER_BRIGHT)
		meta_row.add_child(delta_label)
	card.inspect_requested.connect(_show_item_detail)
	_items_grid.add_child(card)

func _add_material_card(material_id: String, quantity: int) -> void:
	var definition: Dictionary = game_state.MATERIAL_DEFS.get(material_id, {})
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 108)
	card.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(_rarity_color(int(definition.get("rarity", 0)))))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	card.add_child(line)
	line.add_child(UiKit.icon_well(material_id, UiKit.VERDIGRIS_BRIGHT, 72.0))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	line.add_child(info)
	var title := Label.new()
	title.text = "%s  ×%d" % [str(definition.get("name", material_id)).to_upper(), quantity]
	UiKit.style_label(title, &"RowLabel", 24)
	info.add_child(title)
	var meta := Label.new()
	meta.text = "MATERIAL · %s" % str(definition.get("realm", "CRAFTING")).to_upper()
	UiKit.style_label(meta, &"Body", 20)
	meta.add_theme_color_override("font_color", UiKit.VERDIGRIS_BRIGHT)
	info.add_child(meta)
	_items_grid.add_child(card)

func _add_item_card(item: Dictionary) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 108)
	card.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(_rarity_color(int(item.get("rarity", 0)))))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	card.add_child(line)
	line.add_child(UiKit.icon_well(str(item.get("id", "")), _rarity_color(int(item.get("rarity", 0))), 72.0))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	line.add_child(info)
	var title := Label.new()
	title.text = "%s  ×%d" % [str(item.get("name", item.get("id", "ITEM"))).to_upper(), int(item.get("quantity", 0))]
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiKit.style_label(title, &"RowLabel", 24)
	info.add_child(title)
	var stats: Array = item.get("stats", [])
	var key_stat := str(stats[0]) if not stats.is_empty() else str(item.get("use_label", "QUEST ITEM"))
	var meta := Label.new()
	meta.text = "%s · %s" % [_rarity_label(int(item.get("rarity", 0))), key_stat]
	UiKit.style_label(meta, &"Body", 20)
	meta.add_theme_color_override("font_color", _rarity_color(int(item.get("rarity", 0))))
	info.add_child(meta)
	var hint := Label.new()
	hint.text = "TAP TO INSPECT"
	UiKit.style_label(hint, &"Caption", 18)
	hint.add_theme_color_override("font_color", Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.58))
	info.add_child(hint)
	card.gui_input.connect(_on_plain_card_input.bind(item.duplicate(true)))
	_items_grid.add_child(card)

## Backward-compatible adapters for older gear inspection callers.
func _on_inspect_weapon(weapon: Dictionary) -> void:
	_show_item_detail(weapon)

func _on_inspect_armor(armor: Dictionary) -> void:
	_show_item_detail(armor)

## Materials and consumables are not draggable, so they keep a direct tap
## handler: press opens the inspect sheet for that card.
func _on_plain_card_input(event: InputEvent, item: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_show_item_detail(item)
	elif event is InputEventScreenTouch and event.pressed:
		_show_item_detail(item)

func _rebuild_inventory() -> void:
	if _items_grid == null:
		return
	for child in _items_grid.get_children():
		_items_grid.remove_child(child)
		child.queue_free()
	var entries: Array = []
	var total := 0
	for weapon in game_state.forged_weapons:
		if _inventory_filter in ["all", "weapon"]:
			entries.append({"kind": "gear", "item": weapon})
	for armor in game_state.forged_armors:
		if _inventory_filter in ["all", "armor"]:
			entries.append({"kind": "gear", "item": armor})
	for material_id in game_state.raw_materials:
		var quantity := int(game_state.raw_materials[material_id])
		if quantity > 0:
			total += quantity
			if _inventory_filter in ["all", "material"]:
				entries.append({"kind": "material", "id": str(material_id), "quantity": quantity})
	for item in game_state.inventory:
		var quantity := int(item.get("quantity", 0))
		total += quantity
		var kind := _item_kind(item)
		if quantity > 0 and _inventory_filter in ["all", kind]:
			entries.append({"kind": "consumable", "item": item})
	_sort_entries(entries)
	for entry in entries:
		match str(entry.get("kind", "")):
			"gear":
				_add_gear_card(entry["item"])
			"material":
				_add_material_card(str(entry.get("id", "")), int(entry.get("quantity", 0)))
			_:
				_add_item_card(entry["item"])
	count_label.text = "%d carried" % total
	_refresh_filter_buttons()
	_update_sort_button()
	_update_loadout_strip()
	_update_empty_state()

## One sort order at a time, and rarity keeps a name tiebreak so the list never
## reorders itself between two equally rare items.
func _sort_entries(entries: Array) -> void:
	if entries.size() < 2:
		return
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if _sort_mode == "name":
			return _entry_name(a) < _entry_name(b)
		if _sort_mode == "newest":
			return _entry_stamp(a) > _entry_stamp(b)
		var ra := int((a.get("item", {}) as Dictionary).get("rarity", 0))
		var rb := int((b.get("item", {}) as Dictionary).get("rarity", 0))
		if ra != rb:
			return ra > rb
		return _entry_name(a) < _entry_name(b))

func _entry_name(entry: Dictionary) -> String:
	var item: Dictionary = entry.get("item", {})
	if item.is_empty():
		return str(entry.get("id", ""))
	return str(item.get("name", item.get("id", ""))).to_lower()

func _entry_stamp(entry: Dictionary) -> String:
	var item: Dictionary = entry.get("item", {})
	return str(item.get("acquired_at", item.get("forged_at", "")))

func _cycle_sort() -> void:
	var index := SORTS.find(_sort_mode)
	_sort_mode = SORTS[(index + 1) % SORTS.size()]
	_rebuild_inventory()

func _update_sort_button() -> void:
	if _sort_button == null:
		return
	_sort_button.text = "SORT: %s" % _sort_mode.to_upper()
	UiKit.style_role_button(_sort_button, "ghost",
		UiKit.EMBER if _sort_mode != "rarity" else UiKit.COPPER, 20)

## The equipped weapon and chest, kept beside the list so an upgrade decision is
## made against what is actually worn.
func _update_loadout_strip() -> void:
	if _loadout_strip == null:
		return
	for child in _loadout_strip.get_children():
		_loadout_strip.remove_child(child)
		child.queue_free()
	var head := Label.new()
	head.text = "WORN"
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiKit.style_label(head, &"Eyebrow", 20)
	_loadout_strip.add_child(head)
	for slot in [&"weapon", &"chest"]:
		var equipped: Dictionary = game_state.get_equipment_for_slot(slot)
		var chip := HBoxContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_constant_override("separation", 8)
		chip.add_theme_constant_override("alignment", 1)
		_loadout_strip.add_child(chip)
		if equipped.is_empty():
			chip.add_child(UiKit.icon_well("", UiKit.CREAM_DIM, 44.0))
			var vacant := Label.new()
			vacant.text = "%s · EMPTY" % String(slot).to_upper()
			vacant.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			UiKit.style_label(vacant, &"Caption", 18)
			vacant.add_theme_color_override("font_color", Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.45))
			chip.add_child(vacant)
			continue
		var accent := _rarity_color(clampi(int(equipped.get("rarity", 0)), 0, 4))
		chip.add_child(UiKit.icon_well(str(equipped.get("id", "")), accent, 44.0))
		var worn := Label.new()
		worn.text = str(equipped.get("name", equipped.get("id", ""))).to_upper()
		worn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		worn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		worn.clip_text = true
		worn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UiKit.style_label(worn, &"RowLabel", 20)
		worn.add_theme_color_override("font_color", accent)
		chip.add_child(worn)

## An empty page says why it is empty and what fills it, instead of showing a
## blank grid the player has to interpret.
func _update_empty_state() -> void:
	if _empty_state != null and is_instance_valid(_empty_state):
		_empty_state.queue_free()
		_empty_state = null
	if _items_grid.get_child_count() > 0:
		return
	var copy := {
		"weapon": ["No weapons carried", "Buy one from the Ember Trader or forge a relic at the Divining Lens."],
		"armor": ["No armor carried", "Buy armor from the Ember Trader to raise your defense."],
		"consumable": ["No consumables carried", "Gather or buy tonics before a long expedition."],
		"material": ["No materials carried", "Gather from nodes in each realm to unlock camp facilities."],
		"quest": ["No quest items", "Quest items appear here as the route hands them to you."],
	}
	var entry: Array = copy.get(_inventory_filter, ["Nothing here yet", "Change the filter or explore a realm to fill this page."])
	var panel := PanelContainer.new()
	panel.name = "EmptyState"
	panel.add_theme_stylebox_override("panel", UiKit.glass_stylebox(false, 0.40))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = str(entry[0])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.style_label(title, &"RowLabel", 22)
	box.add_child(title)
	var detail := Label.new()
	detail.text = str(entry[1])
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(detail, &"Caption", 18)
	detail.add_theme_color_override("font_color", Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.62))
	box.add_child(detail)
	_empty_state = panel
	_items_grid.add_child(panel)

func _set_inventory_filter(filter_id: String) -> void:
	_inventory_filter = filter_id if filter_id in FILTERS else "all"
	_rebuild_inventory()

func _refresh_filter_buttons() -> void:
	for filter_id in _filter_buttons:
		var button := _filter_buttons[filter_id] as Button
		if button == null:
			continue
		if str(filter_id) == _inventory_filter:
			UiKit.style_primary_button(button)
		else:
			UiKit.style_secondary_button(button)

func _refresh_crafting() -> void:
	if _craft_grid == null:
		return
	for child in _craft_grid.get_children():
		_craft_grid.remove_child(child)
		child.queue_free()
	for recipe_id in CraftingData.recipe_ids():
		var recipe: Dictionary = CraftingData.get_recipe(recipe_id)
		if recipe.is_empty():
			continue
		var preview := CraftingData.output_preview(recipe_id)
		var requirement := CraftingData.requirement_report(recipe_id)
		var can_craft := bool(requirement.get("can_craft", false))
		var card := PanelContainer.new()
		card.name = "Recipe_%s" % recipe_id
		card.custom_minimum_size = Vector2(0, 156)
		card.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(_rarity_color(int(recipe.get("rarity", 0)))))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		card.add_child(box)
		var title := Label.new()
		title.text = str(recipe.get("name", recipe_id)).to_upper()
		UiKit.style_label(title, &"RowLabel", 24)
		box.add_child(title)
		# What the craft actually grants, and how it changes the hero right now.
		var output := Label.new()
		output.name = "Output"
		output.text = _craft_output_text(preview)
		output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiKit.style_label(output, &"Body", 20)
		box.add_child(output)
		var materials: Array[String] = []
		for material_id in recipe.get("materials", {}):
			materials.append("%dx %s" % [int(recipe.materials[material_id]), str(material_id).replace("_", " ")])
		var requirements := Label.new()
		requirements.text = "%s · %d GOLD" % [", ".join(materials), int(recipe.get("gold_cost", 0))]
		requirements.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiKit.style_label(requirements, &"Caption", 18)
		requirements.add_theme_color_override("font_color",
			Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.72))
		box.add_child(requirements)
		var craft := Button.new()
		craft.name = "CraftButton"
		craft.text = "CRAFT" if can_craft else str(requirement.get("summary", "REQUIREMENTS UNMET")).to_upper()
		craft.tooltip_text = str(requirement.get("summary", ""))
		craft.disabled = not can_craft
		craft.custom_minimum_size = Vector2(0, UiKit.TOUCH_TARGET_MIN)
		if can_craft:
			UiKit.style_role_button(craft, "primary", UiKit.EMBER, 22)
		else:
			UiKit.style_role_button(craft, "ghost", UiKit.COPPER, 20)
		craft.pressed.connect(_on_recipe_pressed.bind(recipe_id))
		box.add_child(craft)
		_craft_grid.add_child(card)
	_craft_status.text = "MATERIALS  %s  ·  GOLD %d" % [_craft_material_summary(), game_state.gold]

func _craft_material_summary() -> String:
	var parts: Array[String] = []
	for material_id in game_state.raw_materials:
		var quantity := int(game_state.raw_materials[material_id])
		if quantity > 0:
			parts.append("%s %d" % [str(material_id).replace("_", " ").to_upper(), quantity])
	return ", ".join(parts) if not parts.is_empty() else "NO MATERIALS"

## The card's "what you get" line: the granted item, its stat line, and for
## gear the change against what the hero already carries.
func _craft_output_text(preview: Dictionary) -> String:
	if preview.is_empty():
		return "OUTPUT UNKNOWN"
	var category := str(preview.get("category", ""))
	var granted := str(preview.get("name", "")).to_upper()
	var stat_line := str(preview.get("stat_line", ""))
	if category == "weapon":
		var current := int(game_state.equipped_weapon.get("atk", 0))
		var gain := int(preview.get("atk", 0)) - current
		return "GRANTS %s · %s (%+d vs equipped)" % [granted, stat_line, gain]
	if category == "armor":
		var current_def := int(game_state.equipped_armor.get("defense", 0))
		var gain_def := int(preview.get("defense", 0)) - current_def
		return "GRANTS %s · %s (%+d DEF vs equipped)" % [granted, stat_line, gain_def]
	return "GRANTS %s · %s" % [granted, stat_line]

func _on_recipe_pressed(recipe_id: String) -> void:
	var result := CraftingData.craft(recipe_id)
	if bool(result.get("success", false)):
		_craft_status.text = "CRAFTED %s" % str(result.get("name", recipe_id)).to_upper()
	else:
		_craft_status.text = str(result.get("message", "CRAFT FAILED"))
	_refresh_crafting()
	_rebuild_inventory()

func _on_hero_equipped(_item_id: String, _slot: StringName) -> void:
	_rebuild_inventory()
	_hero_preview.grab_focus()

func _on_hero_drop_rejected(message: String) -> void:
	if _hero_preview != null:
		_hero_preview.tooltip_text = message

func _on_slot_item_dropped(item_id: String, slot: StringName) -> void:
	var item := _find_owned_item(item_id)
	if item.is_empty() or not game_state.can_equip_item(item, slot):
		return
	if game_state.equip_item_to_slot(item_id, slot):
		_rebuild_inventory()
		_hero_preview._refresh()

func _find_owned_item(item_id: String) -> Dictionary:
	for item in game_state.forged_weapons:
		if str(item.get("id", "")) == item_id:
			return item.duplicate(true)
	for item in game_state.forged_armors:
		if str(item.get("id", "")) == item_id:
			return item.duplicate(true)
	return {}

func _on_inventory_changed(_notice: String = "", _count: int = 0) -> void:
	_rebuild_inventory()
	_refresh_crafting()

func _on_materials_changed() -> void:
	_rebuild_inventory()
	_refresh_crafting()

func _on_weapon_changed(_weapon: Dictionary) -> void:
	_rebuild_inventory()
	_refresh_crafting()

func _on_armor_changed(_armor: Dictionary) -> void:
	_rebuild_inventory()

func _on_stats_changed() -> void:
	if _stats_component != null:
		_stats_component._on_stats_changed()

func _item_kind(item: Dictionary) -> String:
	var item_id := str(item.get("id", ""))
	if item.has("atk") or game_state.WEAPON_DEFS.has(item_id):
		return "weapon"
	if item.has("defense") or game_state.ARMOR_DEFS.has(item_id):
		return "armor"
	var raw_kind: Variant = item.get("kind", "")
	if raw_kind is int:
		match int(raw_kind):
			0: return "consumable"
			2: return "quest"
			_: return "relic"
	var kind := str(raw_kind).to_lower()
	if kind in ["weapon", "armor", "consumable", "material", "quest"]:
		return kind
	return "quest"

func _rarity_label(rarity: int) -> String:
	return ["COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"][clampi(rarity, 0, 4)]

func _rarity_color(rarity: int) -> Color:
	return UiKit.rarity_color(rarity)

func _on_close_pressed() -> void:
	_hide_inspect_sheet()
	visible = false

func toggle() -> void:
	visible = not visible
	if visible:
		open_tab(&"items")
		_rebuild_inventory()

func show_stats() -> void:
	visible = true
	open_tab(&"stats")

func _on_forge_pressed() -> void:
	visible = false
	var forge := get_tree().root.find_child("ForgeMenu", true, false)
	if forge != null:
		forge.visible = true

## Compatibility helper retained for old stat layout checks. The shared
## StatsPanel owns the actual responsive grid now.
func _stats_column_count() -> int:
	return 3 if get_viewport().get_visible_rect().size.x < UiKit.COMPACT_BREAKPOINT else 6

## A menu freed while it still holds the world must not leave it paused behind
## it. Every freeze-holding surface shares this guarantee, matching the altar's
## teardown behaviour.
func _exit_tree() -> void:
	_release_world_freeze()

func _release_world_freeze() -> void:
	if not _freeze_held:
		return
	_freeze_held = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("pop_world_freeze"):
		gs.call("pop_world_freeze")
