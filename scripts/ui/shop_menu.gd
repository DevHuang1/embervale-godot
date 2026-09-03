extends CanvasLayer
class_name ShopMenu

## Touch-friendly Ember Trader: Buy and Sell weapons, armor, and potions.
@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var items_vbox: VBoxContainer = $Root/VBox/ItemsScroll/ItemsVBox
@onready var gold_label: Label = $Root/VBox/Header/GoldLabel
@onready var close_button: Button = $Root/VBox/Header/CloseButton
@onready var message_label: Label = $Root/VBox/MessageLabel

var _freeze_was_visible := false
var _mode := "buy"
var _tabs: HBoxContainer
var _buy_button: Button
var _sell_button: Button
const RARITY_COLORS: Array[Color] = [
	Color(0.58, 0.67, 0.65), Color(0.56, 0.74, 0.45),
	Color(0.38, 0.72, 0.86), Color(0.70, 0.48, 0.88), UiKit.EMBER]

func _ready() -> void:
	UiKit.apply_glass($Root)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_freeze_was_visible = visible
	UiKit.style_button(close_button, UiKit.SAGE)
	close_button.add_theme_font_size_override("font_size", 16)
	close_button.pressed.connect(close)
	game_state.gold_changed.connect(_on_gold_changed)
	game_state.inventory_changed.connect(_on_inventory_changed)
	_build_tabs()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_refresh()

func _apply_responsive_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var root_panel := $Root as PanelContainer
	var margin := 28.0 if viewport_size.x < 900.0 else 72.0
	var width := minf(1040.0, viewport_size.x - margin * 2.0)
	var height := minf(920.0, viewport_size.y - margin * 2.0)
	root_panel.offset_left = -width * 0.5
	root_panel.offset_right = width * 0.5
	root_panel.offset_top = -height * 0.5
	root_panel.offset_bottom = height * 0.5

func _build_tabs() -> void:
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	$Root/VBox.add_child(_tabs)
	$Root/VBox.move_child(_tabs, 1)
	_buy_button = Button.new()
	_buy_button.text = "BUY"
	_buy_button.custom_minimum_size = Vector2(150, 48)
	_buy_button.pressed.connect(_set_mode.bind("buy"))
	_tabs.add_child(_buy_button)
	_sell_button = Button.new()
	_sell_button.text = "SELL"
	_sell_button.custom_minimum_size = Vector2(150, 48)
	_sell_button.pressed.connect(_set_mode.bind("sell"))
	_tabs.add_child(_sell_button)
	_update_tab_styles()

func _set_mode(mode: String) -> void:
	_mode = mode
	_update_tab_styles()
	_refresh()

func _update_tab_styles() -> void:
	if _buy_button == null:
		return
	if _mode == "buy":
		UiKit.style_primary_button(_buy_button)
		UiKit.style_secondary_button(_sell_button)
	else:
		UiKit.style_secondary_button(_buy_button)
		UiKit.style_primary_button(_sell_button)

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

func open() -> void:
	visible = true
	_refresh()
	audio.play_ui_blip()

func close() -> void:
	visible = false
	audio.play_ui_back()

func _on_gold_changed(_total: int) -> void:
	_refresh()

func _on_inventory_changed(_notice: String = "", _count: int = 0) -> void:
	_refresh()

func _refresh() -> void:
	gold_label.text = "◆  %d  GOLD" % game_state.gold
	for child in items_vbox.get_children():
		child.queue_free()
	if _mode == "buy":
		for stock in GameState.SHOP_STOCK:
			items_vbox.add_child(_build_buy_row(stock))
	else:
		_build_sell_rows()

func _build_buy_row(stock: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var kind := str(stock.get("kind", "item"))
	var accent := UiKit.EMBER if kind == "weapon" else (Color(0.42, 0.76, 0.96) if kind == "armor" else UiKit.SAGE_BRIGHT)
	panel.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(accent))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var id := str(stock.get("id", ""))
	var def: Dictionary = GameState.WEAPON_DEFS.get(id, {}) if kind == "weapon" else (GameState.ARMOR_DEFS.get(id, {}) if kind == "armor" else game_state.get_item(id))
	var glyph_well := PanelContainer.new()
	glyph_well.custom_minimum_size = Vector2(66, 66)
	glyph_well.add_theme_stylebox_override("panel", UiKit.icon_well_stylebox(accent))
	row.add_child(glyph_well)
	var glyph := Label.new()
	glyph.text = str(def.get("glyph", "🧪"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiKit.style_label(glyph, "", 30)
	glyph_well.add_child(glyph)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var title := Label.new()
	title.text = str(def.get("name", id))
	UiKit.style_label(title, &"MenuTitle", 19)
	info.add_child(title)
	var stat := Label.new()
	stat.text = "%s  •  %s" % [kind.to_upper(), _stat_line(kind, def)]
	UiKit.style_label(stat, &"Caption", 15)
	stat.add_theme_color_override("font_color", accent.lightened(0.12))
	info.add_child(stat)
	var desc := Label.new()
	desc.text = str(def.get("description", def.get("desc", "")))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(desc, &"Caption", 14)
	info.add_child(desc)
	var price := int(stock.get("price", def.get("price", 1)))
	var button := Button.new()
	button.custom_minimum_size = Vector2(190, 48)
	if kind != "potion" and game_state.owns_shop_item(id):
		button.text = "OWNED / EQUIP"
		UiKit.style_secondary_button(button)
		button.pressed.connect(_on_equip_pressed.bind(id, kind))
	else:
		button.text = "BUY  %d GOLD" % price
		UiKit.style_primary_button(button)
		button.pressed.connect(_on_buy_pressed.bind(id))
	row.add_child(button)
	return panel

func _build_sell_rows() -> void:
	for weapon in game_state.forged_weapons:
		items_vbox.add_child(_build_sell_row("weapon", weapon))
	for armor in game_state.forged_armors:
		items_vbox.add_child(_build_sell_row("armor", armor))
	for item in game_state.inventory:
		if int(item.get("quantity", 0)) > 0 and int(item.get("kind", -1)) == GameState.ItemKind.CONSUMABLE:
			items_vbox.add_child(_build_sell_row("potion", item))
	if items_vbox.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "No eligible goods to sell."
		UiKit.style_label(empty, &"Caption", 17)
		items_vbox.add_child(empty)

func _build_sell_row(kind: String, item: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var rarity := clampi(int(item.get("rarity", 0)), 0, RARITY_COLORS.size() - 1)
	var accent: Color = RARITY_COLORS[rarity]
	panel.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(accent))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var glyph_well := PanelContainer.new()
	glyph_well.custom_minimum_size = Vector2(66, 66)
	glyph_well.add_theme_stylebox_override("panel", UiKit.icon_well_stylebox(accent))
	row.add_child(glyph_well)
	var glyph := Label.new()
	glyph.text = str(item.get("glyph", "⚔"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiKit.style_label(glyph, "", 30)
	glyph_well.add_child(glyph)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var id := str(item.get("id", ""))
	var title := Label.new()
	title.text = "%s  ×%d" % [str(item.get("name", id)), int(item.get("quantity", 1))] if kind == "potion" else str(item.get("name", id))
	UiKit.style_label(title, &"MenuTitle", 18)
	info.add_child(title)
	var value := _sell_value(kind, id)
	var meta := Label.new()
	meta.text = "SELL VALUE  %d GOLD" % value
	UiKit.style_label(meta, &"Caption", 14)
	info.add_child(meta)
	var button := Button.new()
	button.text = "SELL  %d GOLD" % value
	button.custom_minimum_size = Vector2(190, 48)
	UiKit.style_secondary_button(button)
	button.pressed.connect(_on_sell_pressed.bind(id, kind))
	row.add_child(button)
	return panel

func _sell_value(kind: String, id: String) -> int:
	if kind == "weapon":
		return maxi(1, int(GameState.WEAPON_DEFS.get(id, {}).get("price", 1)) / 2)
	if kind == "armor":
		return maxi(1, int(GameState.ARMOR_DEFS.get(id, {}).get("price", 1)) / 2)
	return 6

func _stat_line(kind: String, def: Dictionary) -> String:
	if kind == "weapon":
		return "%s ATK  ·  REACH %.1f" % [int(def.get("atk", 0)), float(def.get("range", 0.0))]
	if kind == "armor":
		return "DEFENSE -%d  ·  SPEED ×%.2f" % [int(def.get("defense", 0)), float(def.get("speed_mult", 1.0))]
	return "RESTORES %d HP  ·  SINGLE USE" % GameState.MOSS_TONIC_HEAL

func _on_buy_pressed(id: String) -> void:
	var result: Dictionary = game_state.buy_shop_item(id)
	if result.success:
		message_label.text = "%s purchased." % id.to_upper()
		audio.play_loot_fanfare()
	else:
		message_label.text = str(result.message)
		audio.play_ui_back()
	_refresh()

func _on_sell_pressed(id: String, kind: String) -> void:
	var result: Dictionary = game_state.sell_shop_item(id, kind)
	if result.success:
		message_label.text = "%s sold for %d gold." % [id.to_upper(), int(result.value)]
		audio.play_loot_fanfare()
	else:
		message_label.text = str(result.message)
		audio.play_ui_back()
	_refresh()

func _on_equip_pressed(id: String, kind: String) -> void:
	if kind == "weapon":
		game_state.equip_weapon_by_id(id)
	else:
		game_state.equip_armor(id)
	message_label.text = "%s equipped." % id.to_upper()
	audio.play_ui_blip()
	_refresh()
