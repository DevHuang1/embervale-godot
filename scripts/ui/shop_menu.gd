extends CanvasLayer
class_name ShopMenu

## === Ember Trader ===
## Buy weapons and armor with 🪙 gold gathered from fallen foes.
## Purchases equip immediately; owned pieces can be re-equipped here.

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var items_vbox: VBoxContainer = $Root/VBox/ItemsScroll/ItemsVBox
@onready var gold_label: Label = $Root/VBox/Header/GoldLabel
@onready var close_button: Button = $Root/VBox/Header/CloseButton
@onready var message_label: Label = $Root/VBox/MessageLabel

func _ready() -> void:
	UiKit.apply_glass($Root)
	UiKit.style_button(close_button, UiKit.SAGE)
	close_button.add_theme_font_size_override("font_size", 14)
	game_state.gold_changed.connect(_on_gold_changed)
	_refresh()

func open() -> void:
	visible = true
	_refresh()
	audio.play_ui_blip()

func close() -> void:
	visible = false
	audio.play_ui_back()

func _on_gold_changed(_total: int) -> void:
	_refresh()

func _refresh() -> void:
	gold_label.text = "🪙 %d" % game_state.gold
	for child in items_vbox.get_children():
		child.queue_free()
	
	for stock in GameState.SHOP_STOCK:
		items_vbox.add_child(_build_row(stock))

func _build_row(stock: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_constant_override("panel_inset", 10)
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)
		# Tint rows so equipped gear reads as warm amber.
	var equipped: bool = game_state.equipped_weapon.get("id", "") == stock.id \
		or game_state.equipped_armor.get("id", "") == stock.id
	var row_sb := UiKit.parchment_stylebox(UiKit.RADIUS_BUTTON)
	if equipped:
		row_sb.bg_color = Color(0.52, 0.44, 0.24, 0.86)
	panel.add_theme_stylebox_override("panel", row_sb)

	var def: Dictionary = GameState.WEAPON_DEFS.get(stock.id, {}) \
		if stock.kind == "weapon" else GameState.ARMOR_DEFS.get(stock.id, {})
	var glyph := Label.new()
	glyph.text = str(def.get("glyph", "?"))
	UiKit.style_label(glyph, "", 22)
	hbox.add_child(glyph)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_label := Label.new()
	name_label.text = str(def.get("name", stock.id))
	UiKit.style_label(name_label, &"MenuTitle", 15)
	info.add_child(name_label)

	var stat_label := Label.new()
	stat_label.text = _stat_line(stock.kind, def)
	UiKit.style_label(stat_label, &"Caption", 12)
	info.add_child(stat_label)

	var desc := Label.new()
	desc.text = str(def.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(desc, &"Caption", 11)
	info.add_child(desc)

	var price := int(stock.price)
	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 0)
	var owned: bool = game_state.owns_shop_item(str(stock.id))
	if equipped:
		button.text = "EQUIPPED"
		button.disabled = true
		UiKit.style_secondary_button(button)
	elif owned:
		button.text = "EQUIP"
		UiKit.style_button(button)
		button.pressed.connect(_on_equip_pressed.bind(str(stock.id), stock.kind))
	else:
		button.text = "BUY %d🪙" % price
		UiKit.style_primary_button(button)
		button.pressed.connect(_on_buy_pressed.bind(str(stock.id)))
	hbox.add_child(button)
	return panel

func _stat_line(kind: String, def: Dictionary) -> String:
	if kind == "weapon":
		var kit: Array = def.get("skills", [])
		var names: Array = []
		for sk in kit:
			names.append(sk.get("name", ""))
		return "%s ATK · REACH %.1f · [%s]" % [
			int(def.get("atk", 0)), float(def.get("range", 0.0)),
			" / ".join(names)]
	return "DEFENSE -%d · SPEED ×%.2f" % [
		int(def.get("defense", 0)), float(def.get("speed_mult", 1.0))]

func _on_buy_pressed(id: String) -> void:
	var result: Dictionary = game_state.buy_shop_item(id)
	if result.success:
		message_label.text = "%s is yours — equipped and ready." % id.to_upper()
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
	message_label.text = "%s strapped on." % id.to_upper()
	audio.play_ui_blip()
	_refresh()
