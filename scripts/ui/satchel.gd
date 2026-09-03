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

	close_button.pressed.connect(_on_close_pressed)
	forge_button.pressed.connect(_on_forge_pressed)

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
	_arsenal_grid.columns = 3
	_arsenal_grid.add_theme_constant_override("h_separation", 10)
	_arsenal_grid.add_theme_constant_override("v_separation", 10)
	_arsenal_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_parent.remove_child(items_vbox)
	items_vbox.queue_free()
	list_parent.add_child(_arsenal_grid)
	items_vbox = _arsenal_grid

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

func _build_stats_panel(root_vbox: VBoxContainer) -> void:
	_stats_panel = PanelContainer.new()
	_stats_panel.name = "CharacterStats"
	_stats_panel.custom_minimum_size = Vector2(0, 86)
	_stats_panel.add_theme_stylebox_override("panel", UiKit.parchment_stylebox(UiKit.RADIUS_BUTTON))
	root_vbox.add_child(_stats_panel)
	root_vbox.move_child(_stats_panel, 2)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 6
	_stats_grid.add_theme_constant_override("h_separation", 18)
	_stats_grid.add_theme_constant_override("v_separation", 2)
	_stats_panel.add_child(_stats_grid)
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
		_detail_action.visible = true
		_detail_action.text = item.get("use_label", "USE")
		_detail_action.pressed.connect(func():
			_on_use_item(str(item.get("id", "")))
			_detail_panel.visible = false
		, CONNECT_ONE_SHOT)
	else:
		_detail_action.visible = false

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
		["HP", "%d / %d" % [game_state.hp, game_state.max_hp], Color(0.98, 0.42, 0.42)]
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
	_add_equipment_slot("WEAPON", game_state.equipped_weapon, Color(0.96, 0.72, 0.30))
	_add_equipment_slot("ARMOR", game_state.equipped_armor, Color(0.42, 0.76, 0.96))
	_equipment_row.add_child(_selected_item_label)
	_refresh_stats_panel()

func _add_equipment_slot(slot_name: String, gear: Dictionary, tint: Color) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(230, 84)

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
	title.text = "%s  %s" % [str(weapon.get("glyph", "⚔")), str(weapon.get("name", "WEAPON"))]
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
	identity.text = str(weapon.get("passive_desc",
		"%d bound skills" % weapon.get("skills", []).size()))
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(identity, &"Caption", 12)
	vbox.add_child(identity)
	var equip := Button.new()
	var weapon_id := str(weapon.get("id", ""))
	var is_equipped := str(game_state.equipped_weapon.get("id", "")) == weapon_id
	equip.text = "EQUIPPED" if is_equipped else "EQUIP"
	equip.disabled = is_equipped
	UiKit.style_secondary_button(equip)
	equip.custom_minimum_size = Vector2(0, 42)
	equip.pressed.connect(_on_equip_weapon.bind(weapon_id))
	vbox.add_child(equip)
	var upgrade_cost: Dictionary = game_state.get_weapon_upgrade_cost(weapon)
	var upgrade := Button.new()
	if bool(upgrade_cost.get("can_upgrade", false)):
		upgrade.text = "UPGRADE +%d  ·  %d IRON / %d GOLD" % [
			int(upgrade_cost.get("next_level", 1)),
			int(upgrade_cost.get("material_cost", 0)),
			int(upgrade_cost.get("gold_cost", 0))]
		upgrade.pressed.connect(_on_upgrade_weapon.bind(weapon_id))
	else:
		upgrade.text = "MAXIMUM FORGE"
		upgrade.disabled = true
	UiKit.style_secondary_button(upgrade)
	upgrade.custom_minimum_size = Vector2(0, 42)
	vbox.add_child(upgrade)
	items_vbox.add_child(panel)

func _on_equip_weapon(weapon_id: String) -> void:
	if game_state.equip_weapon_by_id(weapon_id):
		var weapon := game_state.equipped_weapon
		_selected_item_label.text = "Equipped %s — %s" % [
			str(weapon.get("name", weapon_id)),
			str(weapon.get("passive_desc", "Its combat kit is now active."))]
		_rebuild_equipment_loadout()

func _on_upgrade_weapon(weapon_id: String) -> void:
	var result: Dictionary = game_state.upgrade_weapon(weapon_id)
	_selected_item_label.text = "ATK %d · upgrade +%d complete" % [
		int(result.get("atk", 0)), int(result.get("level", 0))] \
		if bool(result.get("success", false)) else str(result.get("message", "Upgrade failed."))
	_rebuild_inventory()

func _rebuild_inventory() -> void:
	# Clear
	for child in items_vbox.get_children():
		child.queue_free()

	var total = 0
	for weapon in game_state.forged_weapons:
		_add_weapon_card(weapon)
	for item in game_state.inventory:
		total += item.quantity
		if item.quantity > 0:
			_add_item_row(item)

	count_label.text = "%d items carried" % total

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
	var glyph = Label.new()
	glyph.text = item.glyph
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiKit.style_label(glyph, "", 26)
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
	var glyph := Label.new()
	glyph.text = armor.get("glyph", "○") if not armor.is_empty() else "○"
	UiKit.style_label(glyph, "", 26)
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
	panel.custom_minimum_size = Vector2(180, 0)
	panel.add_theme_constant_override("panel_inset", 8)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
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

func _on_forge_pressed() -> void:
	visible = false
	var forge = get_tree().root.find_child("ForgeMenu", true, false)
	if forge:
		forge.visible = true
