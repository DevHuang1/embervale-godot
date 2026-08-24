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
	close_button.pressed.connect(close)
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
	
	var def: Dictionary = GameState.WEAPON_DEFS.get(stock.id, {}) \
		if stock.kind == "weapon" else GameState.ARMOR_DEFS.get(stock.id, {})
	var glyph := Label.new()
	glyph.text = str(def.get("glyph", "?"))
	glyph.add_theme_font_override("font", load("res://assets/fonts/PressStart2P-Regular.ttf"))
	glyph.add_theme_font_size_override("font_size", 26)
	hbox.add_child(glyph)
	
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)
	
	var name_label := Label.new()
	name_label.text = str(def.get("name", stock.id))
	name_label.add_theme_font_override("font", load("res://assets/fonts/PressStart2P-Regular.ttf"))
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.09, 0.21, 0.17))
	info.add_child(name_label)
	
	var statline := _stat_line(stock.kind, def)
	var stat_label := Label.new()
	stat_label.text = statline
	stat_label.add_theme_font_override("font", load("res://assets/fonts/VT323-Regular.ttf"))
	stat_label.add_theme_font_size_override("font_size", 12)
	stat_label.add_theme_color_override("font_color", Color(0.4, 0.72, 0.7))
	info.add_child(stat_label)
	
	var desc := Label.new()
	desc.text = str(def.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_override("font", load("res://assets/fonts/VT323-Regular.ttf"))
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.56, 0.67, 0.45))
	info.add_child(desc)
	
	var price := int(stock.price)
	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 0)
	button.add_theme_font_override("font", load("res://assets/fonts/PressStart2P-Regular.ttf"))
	button.add_theme_font_size_override("font_size", 10)
	
	var equipped: bool = game_state.equipped_weapon.get("id", "") == stock.id \
		or game_state.equipped_armor.get("id", "") == stock.id
	var owned: bool = game_state.owns_shop_item(str(stock.id))
	
	if equipped:
		button.text = "EQUIPPED"
		button.disabled = true
	elif owned:
		button.text = "EQUIP"
		button.pressed.connect(_on_equip_pressed.bind(str(stock.id), stock.kind))
	else:
		button.text = "BUY %d🪙" % price
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
