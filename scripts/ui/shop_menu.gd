extends CanvasLayer
class_name ShopMenu

## Touch-friendly Ember Trader: Buy and Sell weapons, armor, and potions.
@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var items_vbox: VBoxContainer = $Root/VBox/ItemsScroll/ItemsVBox
@onready var gold_label: Label = $Root/Header/GoldLabel
@onready var close_button: Button = $Root/Header/CloseButton
@onready var message_label: Label = $Root/VBox/MessageLabel

var _freeze_was_visible := false
var _freeze_held := false
var _mode := "buy"
var _tabs: GridContainer
var _buy_button: Button
var _sell_button: Button
var _sort_button: Button
var _sort_mode := "recommended"
var _filter_button: Button
var _ownership_label: Label
var _history_button: Button
var _kind_filter := "all"
const RARITY_COLORS: Array[Color] = [
	Color(0.58, 0.67, 0.65), Color(0.56, 0.74, 0.45),
	Color(0.38, 0.72, 0.86), Color(0.70, 0.48, 0.88), UiKit.EMBER]

func _ready() -> void:
	$Root.add_theme_stylebox_override("panel", UiKit.glass_stylebox())
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.style_button(close_button, UiKit.SAGE)
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.pressed.connect(close)
	game_state.gold_changed.connect(_on_gold_changed)
	game_state.inventory_changed.connect(_on_inventory_changed)
	_build_tabs()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_refresh()

func _apply_responsive_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var root_panel := $Root as Control
	var metrics := UiKit.responsive_metrics(viewport_size)
	var margin := float(metrics.get("safe_margin", UiKit.SAFE_MARGIN_COMPACT))
	var width := minf(1120.0, viewport_size.x - margin * 2.0)
	var height := minf(1080.0, viewport_size.y - margin * 2.0)
	root_panel.offset_left = -width * 0.5
	root_panel.offset_right = width * 0.5
	root_panel.offset_top = -height * 0.5
	root_panel.offset_bottom = height * 0.5
	_layout_header(root_panel, bool(metrics.get("compact", false)))
	if _tabs != null:
		var compact := bool(metrics.get("compact", false))
		_tabs.columns = int(metrics.get("columns", 2))
		var tab_width := maxf(180.0, (width - float(metrics.get("gap", 8.0)) * 2.0) / 2.0) if compact else 0.0
		for button in _tabs.get_children():
			if button is Button:
				(button as Button).custom_minimum_size.x = tab_width

## The authored header used absolute offsets that only worked at one width: the
## title overflowed both edges and ran under the purse and close button. Lay it
## out from the measured controls instead, so it holds on a phone in portrait.
func _layout_header(root_panel: Control, compact: bool) -> void:
	var header := root_panel.get_node_or_null("Header") as Control
	if header == null:
		return
	var title := header.get_node_or_null("Title") as Label
	var gold := header.get_node_or_null("GoldLabel") as Label
	var close := header.get_node_or_null("CloseButton") as Button
	var mark := header.get_node_or_null("MerchantMark") as Label
	var close_width := close.custom_minimum_size.x if close != null else 110.0
	var gold_width := 130.0
	var gap := 12.0
	if title != null:
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.offset_left = 0.0
		title.offset_right = -(gold_width + close_width + gap * 2.0)
		UiKit.style_label(title, &"MenuTitle", 34 if compact else 44)
	if gold != null:
		gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gold.offset_left = -(close_width + gap + gold_width)
		gold.offset_right = -(close_width + gap)
		UiKit.style_label(gold, &"RowLabel", 20)
	if mark != null:
		# The merchant mark is a second line of copy sharing one header row: it
		# only fits beside the title on a wide screen, so on compact it is
		# dropped rather than stacked on top of the title it used to collide with.
		mark.visible = not compact
		mark.text = str(mark.text).replace("◈", "").strip_edges().to_upper()
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		mark.clip_text = true
		mark.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		mark.offset_left = -(close_width + gap + gold_width + gap + 220.0)
		mark.offset_right = -(close_width + gap + gold_width + gap)
		UiKit.style_label(mark, &"Eyebrow", 20)
		if compact:
			title.offset_right = -(gold_width + close_width + gap * 2.0)
	if close != null:
		close.offset_left = -close_width
		close.offset_right = 0.0

func _build_tabs() -> void:
	_tabs = GridContainer.new()
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
	_sort_button = Button.new()
	_sort_button.text = "SORT: RECOMMENDED"
	_sort_button.custom_minimum_size = Vector2(220, 48)
	_sort_button.pressed.connect(_cycle_sort)
	_tabs.add_child(_sort_button)
	_filter_button = Button.new()
	_filter_button.text = "FILTER: ALL"
	_filter_button.custom_minimum_size = Vector2(150, 48)
	_filter_button.pressed.connect(_cycle_filter)
	_tabs.add_child(_filter_button)
	_ownership_label = Label.new()
	_ownership_label.name = "OwnershipLedgerSummary"
	_ownership_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.style_label(_ownership_label, &"Caption", 18)
	$Root/VBox.add_child(_ownership_label)
	_history_button = Button.new()
	_history_button.name = "ViewOwnershipHistory"
	_history_button.text = "VIEW OWNERSHIP HISTORY"
	_history_button.custom_minimum_size = Vector2(0, 44)
	_history_button.tooltip_text = "Review recent shop purchases"
	_history_button.pressed.connect(_show_ownership_history)
	UiKit.style_secondary_button(_history_button)
	$Root/VBox.add_child(_history_button)
	_update_tab_styles()

func _show_ownership_history() -> void:
	var ledger: Array[Dictionary] = game_state.get_purchase_ledger()
	if ledger.is_empty():
		message_label.text = "OWNERSHIP HISTORY · No shop purchases recorded."
		return
	var entries: Array[String] = []
	var start := maxi(0, ledger.size() - 5)
	for index in range(start, ledger.size()):
		var purchase := ledger[index]
		var currency := str(purchase.get("currency", "gold")).to_upper()
		entries.append("%s · %d %s" % [str(purchase.get("id", "")).replace("_", " ").to_upper(), int(purchase.get("price", 0)), currency])
	message_label.text = "OWNERSHIP HISTORY\n" + "\n".join(entries)

func _cycle_sort() -> void:
	_sort_mode = "price" if _sort_mode == "recommended" else ("power" if _sort_mode == "price" else "recommended")
	_sort_button.text = "SORT: %s" % _sort_mode.to_upper()
	_refresh()

func _cycle_filter() -> void:
	var filters := ["all", "weapon", "armor", "potion"]
	var index := filters.find(_kind_filter)
	_kind_filter = filters[(index + 1) % filters.size()]
	_filter_button.text = "FILTER: %s" % _kind_filter.to_upper()
	_refresh()

func _set_mode(mode: String) -> void:
	_mode = mode
	if _filter_button != null:
		_filter_button.disabled = _mode != "buy"
		_filter_button.tooltip_text = "Buy-category filter" if _mode == "buy" else "Category filters apply to buying only"
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
	if _sort_button != null:
		UiKit.style_secondary_button(_sort_button)
	if _filter_button != null:
		UiKit.style_secondary_button(_filter_button)
		_filter_button.disabled = _mode != "buy"

func _poll_world_freeze() -> void:
	if visible == _freeze_was_visible:
		return
	_freeze_was_visible = visible
	if visible:
		game_state.push_world_freeze()
		_freeze_held = true
	else:
		_release_world_freeze()

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
	gold_label.text = "%d  GOLD" % game_state.gold
	if _ownership_label != null:
		var ledger: Array[Dictionary] = game_state.get_purchase_ledger()
		var latest := "NONE YET"
		if not ledger.is_empty():
			latest = str(ledger.back().get("id", "")).replace("_", " ").to_upper()
		_ownership_label.text = "OWNERSHIP LEDGER  ·  %d PURCHASE%s  ·  LAST: %s" % [ledger.size(), "" if ledger.size() == 1 else "S", latest]
		_ownership_label.tooltip_text = "Informational history · latest recorded purchase: %s" % latest
	for child in items_vbox.get_children():
		child.queue_free()
	if _mode == "buy":
		for stock in _sorted_stock():
			items_vbox.add_child(_build_buy_row(stock))
		if items_vbox.get_child_count() == 0:
			var empty := Label.new()
			empty.text = "NO STOCK IN THIS CATEGORY"
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			UiKit.style_label(empty, &"Caption", 18)
			items_vbox.add_child(empty)
	else:
		_build_sell_rows()

func _sorted_stock() -> Array[Dictionary]:
	var stock: Array[Dictionary] = []
	for entry in GameState.SHOP_STOCK:
		var candidate := (entry as Dictionary).duplicate(true)
		if _kind_filter == "all" or str(candidate.get("kind", "")) == _kind_filter:
			stock.append(candidate)
	if _sort_mode == "price":
		stock.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return GameState.gear_buy_price(str(a.get("id", "")),
				str(a.get("kind", ""))) < GameState.gear_buy_price(str(b.get("id", "")),
				str(b.get("kind", ""))))
	elif _sort_mode == "power":
		stock.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _stock_power(a) > _stock_power(b))
	return stock

func _stock_power(stock: Dictionary) -> float:
	var id := str(stock.get("id", ""))
	var kind := str(stock.get("kind", ""))
	if kind == "weapon":
		return float(GameState.WEAPON_DEFS.get(id, {}).get("atk", 0))
	if kind == "armor":
		return float(GameState.ARMOR_DEFS.get(id, {}).get("defense", 0))
	return float(GameState.MOSS_TONIC_HEAL)

func _build_buy_row(stock: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var kind := str(stock.get("kind", "item"))
	var accent := UiKit.EMBER if kind == "weapon" else (Color(0.42, 0.76, 0.96) if kind == "armor" else UiKit.SAGE_BRIGHT)
	panel.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(accent))
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 10)
	panel.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 10)
	card.add_child(actions)
	var id := str(stock.get("id", ""))
	var def: Dictionary = GameState.WEAPON_DEFS.get(id, {}) if kind == "weapon" else (GameState.ARMOR_DEFS.get(id, {}) if kind == "armor" else game_state.get_item(id))
	row.add_child(UiKit.icon_well(id, accent, 72.0))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var title := Label.new()
	title.text = str(def.get("name", id))
	UiKit.style_label(title, &"MenuTitle", 32)
	info.add_child(title)
	var stat := Label.new()
	stat.text = "%s  •  %s" % [kind.to_upper(), _stat_line(kind, def)]
	UiKit.style_label(stat, &"Caption", 18)
	stat.add_theme_color_override("font_color", accent.lightened(0.12))
	info.add_child(stat)
	var comparison := Label.new()
	comparison.text = _comparison_line(kind, def)
	comparison.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(comparison, &"Caption", 18)
	comparison.add_theme_color_override("font_color", Color(0.78, 0.86, 0.72))
	info.add_child(comparison)
	var desc := Label.new()
	desc.text = str(def.get("description", def.get("desc", "")))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(desc, &"Caption", 18)
	info.add_child(desc)
	var price := GameState.gear_buy_price(id, kind)
	if kind == "weapon" or kind == "armor":
		var preview := Button.new()
		preview.text = "PREVIEW"
		preview.custom_minimum_size = Vector2(0, 52)
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiKit.style_role_button(preview, "ghost", UiKit.COPPER, 20)
		preview.pressed.connect(_on_preview_pressed.bind(kind, def.duplicate(true)))
		actions.add_child(preview)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if kind != "potion" and game_state.owns_shop_item(id):
		var equipped := (kind == "weapon" and str(game_state.equipped_weapon.get("id", "")) == id) \
			or (kind == "armor" and str(game_state.equipped_armor.get("id", "")) == id)
		var owned_state := UiKit.action_state("equipped" if equipped else "owned")
		button.text = str(owned_state.get("label", "OWNED / EQUIP"))
		button.disabled = equipped
		button.tooltip_text = "Currently equipped" if equipped else "Equip this owned item"
		UiKit.style_role_button(button, "primary", UiKit.EMBER, 20)
		if not equipped:
			button.pressed.connect(_on_equip_pressed.bind(id, kind))
	else:
		var missing_gold := maxi(0, price - game_state.gold)
		var purchase_state := UiKit.action_state("unavailable" if missing_gold > 0 else "purchased",
			"%d GOLD" % (missing_gold if missing_gold > 0 else price))
		button.text = ("NEED " if missing_gold > 0 else "BUY  ") + str(purchase_state.get("detail", ""))
		UiKit.style_role_button(button, "ghost" if missing_gold > 0 else "primary",
			UiKit.COPPER if missing_gold > 0 else UiKit.EMBER, 20)
		button.disabled = game_state.gold < price
		button.tooltip_text = "Earn %d more gold to afford this item." % missing_gold if missing_gold > 0 else "Purchase this item for %d gold." % price
		UiKit.style_primary_button(button)
		if not button.disabled:
			button.pressed.connect(_on_buy_pressed.bind(id))
	actions.add_child(button)
	return panel

func _on_preview_pressed(kind: String, definition: Dictionary) -> void:
	var scene := get_tree().current_scene
	var satchel := scene.find_child("Satchel", true, false) if scene != null else null
	if satchel == null:
		message_label.text = "Preview unavailable in this scene."
		return
	close()
	satchel.visible = true
	if kind == "weapon" and satchel.has_method("_on_inspect_weapon"):
		satchel.call("_on_inspect_weapon", definition)
	elif kind == "armor" and satchel.has_method("_on_inspect_armor"):
		satchel.call("_on_inspect_armor", definition)

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
		UiKit.style_label(empty, &"Caption", 18)
		items_vbox.add_child(empty)

func _build_sell_row(kind: String, item: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var rarity := clampi(int(item.get("rarity", 0)), 0, RARITY_COLORS.size() - 1)
	var accent: Color = RARITY_COLORS[rarity]
	panel.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(accent))
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 10)
	panel.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 10)
	card.add_child(actions)
	row.add_child(UiKit.icon_well(str(item.get("id", "")), accent, 72.0))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var id := str(item.get("id", ""))
	var title := Label.new()
	title.text = "%s  ×%d" % [str(item.get("name", id)), int(item.get("quantity", 1))] if kind == "potion" else str(item.get("name", id))
	UiKit.style_label(title, &"MenuTitle", 32)
	info.add_child(title)
	var value := _sell_value(kind, id)
	var meta := Label.new()
	meta.text = "SELL VALUE  %d GOLD" % value
	UiKit.style_label(meta, &"Caption", 18)
	info.add_child(meta)
	var button := Button.new()
	button.text = "SELL  %d GOLD" % value
	button.custom_minimum_size = Vector2(0, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_role_button(button, "danger", UiKit.BLOOD, 20)
	button.pressed.connect(_on_sell_pressed.bind(id, kind))
	actions.add_child(button)
	return panel

func _sell_value(kind: String, id: String) -> int:
	return GameState.gear_sell_value(id, kind)

func _stat_line(kind: String, def: Dictionary) -> String:
	if kind == "weapon":
		return "%s ATK  ·  REACH %.1f" % [int(def.get("atk", 0)), float(def.get("range", 0.0))]
	if kind == "armor":
		return "DEFENSE -%d  ·  SPEED ×%.2f" % [int(def.get("defense", 0)), float(def.get("speed_mult", 1.0))]
	return "RESTORES %d HP  ·  SINGLE USE" % GameState.MOSS_TONIC_HEAL

func _comparison_line(kind: String, def: Dictionary) -> String:
	if kind == "weapon":
		var delta_atk := int(def.get("atk", 0)) - int(game_state.equipped_weapon.get("atk", 0))
		var delta_reach := float(def.get("range", 0.0)) - float(game_state.equipped_weapon.get("range", 0.0))
		return "Compared with equipped: ATK %+d  ·  REACH %+0.1f" % [delta_atk, delta_reach]
	if kind == "armor":
		var delta_def := int(def.get("defense", 0)) - int(game_state.equipped_armor.get("defense", 0))
		var delta_speed := float(def.get("speed_mult", 1.0)) - float(game_state.equipped_armor.get("speed_mult", 1.0))
		return "Compared with equipped: DEF %+d  ·  SPEED %+0.2f" % [delta_def, delta_speed]
	return "Single-use recovery item"

func _on_buy_pressed(id: String) -> void:
	var result: Dictionary = game_state.buy_shop_item(id)
	if result.success:
		var confirmed := UiKit.action_state("purchased", "Ownership saved to your inventory")
		message_label.text = "%s · %s" % [str(confirmed.get("label", "PURCHASED")), id.to_upper()]
		audio.play_loot_fanfare()
	else:
		message_label.text = "PURCHASE FAILED · %s" % str(result.message)
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
