extends CanvasLayer
class_name SatchelUI

## === Field Satchel ===
## Inventory, forged gear + armor, the equipped weapon's skill kit

@onready var game_state: GameState = GameState
@onready var items_vbox: VBoxContainer = $Root/VBox/ItemsList/ItemsVBox
@onready var count_label: Label = $Root/VBox/Header/CountLabel
@onready var close_button: TextureButton = $Root/VBox/Header/CloseButton
@onready var weapon_name: Label = $Root/VBox/ForgedGear/ForgedVBox/CurrentWeapon/WeaponInfo/WeaponName
@onready var weapon_stats: Label = $Root/VBox/ForgedGear/ForgedVBox/CurrentWeapon/WeaponInfo/WeaponStats
@onready var forge_button: Button = $Root/VBox/ForgedGear/ForgedVBox/CurrentWeapon/ForgeButton
@onready var forged_vbox: VBoxContainer = $Root/VBox/ForgedGear/ForgedVBox
@onready var skill_kit: HBoxContainer = $Root/VBox/ClassFooter/ClassVBox/SkillKit

var _skill_cd_labels: Array[Label] = []

func _ready() -> void:
	_connect_signals()
	_rebuild_inventory()
	_update_forged_gear()
	_rebuild_skill_kit()
	_rebuild_armor_row()
	
	close_button.pressed.connect(_on_close_pressed)
	forge_button.pressed.connect(_on_forge_pressed)

func _process(_delta: float) -> void:
	for slot in _skill_cd_labels.size():
		if slot < 3:
			_skill_cd_labels[slot].text = game_state.get_slot_cooldown_text(slot)

func _connect_signals() -> void:
	game_state.loot_received.connect(_on_inventory_changed)
	game_state.inventory_changed.connect(_on_inventory_changed)
	game_state.weapon_changed.connect(_on_weapon_changed)
	game_state.armor_changed.connect(_on_armor_changed)

func _rebuild_inventory() -> void:
	# Clear
	for child in items_vbox.get_children():
		child.queue_free()
	
	var total = 0
	for item in game_state.inventory:
		total += item.quantity
		if item.quantity > 0:
			_add_item_row(item)
	
	count_label.text = "%d items carried" % total

func _add_item_row(item: Dictionary) -> void:
	var panel = PanelContainer.new()
	panel.add_theme_constant_override("panel_inset", 10)
	
	var hbox = HBoxContainer.new()
	panel.add_child(hbox)
	
	var glyph = Label.new()
	glyph.text = item.glyph
	glyph.add_theme_font_override("font", load("res://assets/fonts/PressStart2P-Regular.ttf"))
	glyph.add_theme_font_size_override("font_size", 24)
	hbox.add_child(glyph)
	
	var info = VBoxContainer.new()
	hbox.add_child(info)
	
	var name_label = Label.new()
	name_label.text = "%s ×%d" % [item.name, item.quantity]
	name_label.add_theme_font_override("font", load("res://assets/fonts/PressStart2P-Regular.ttf"))
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.09, 0.21, 0.17))
	info.add_child(name_label)
	
	var rarity_colors = {
		0: Color(0.58, 0.67, 0.65),  # Common
		1: Color(0.56, 0.67, 0.45),  # Uncommon
		2: Color(0.4, 0.72, 0.7),    # Rare
	}
	var rarity_color = rarity_colors.get(item.rarity, Color(1, 1, 1))
	
	var meta_label = Label.new()
	meta_label.text = "%s · %s" % [["Common", "Uncommon", "Rare"][item.rarity], ["Consumable", "Relic", "Quest"][item.kind]]
	meta_label.add_theme_font_override("font", load("res://assets/fonts/VT323-Regular.ttf"))
	meta_label.add_theme_font_size_override("font_size", 11)
	meta_label.add_theme_color_override("font_color", rarity_color)
	info.add_child(meta_label)
	
	var stats_label = Label.new()
	stats_label.text = " · ".join(item.stats)
	stats_label.add_theme_font_override("font", load("res://assets/fonts/VT323-Regular.ttf"))
	stats_label.add_theme_font_size_override("font_size", 11)
	stats_label.add_theme_color_override("font_color", Color(0.56, 0.67, 0.45))
	info.add_child(stats_label)
	
	if item.kind == 0 and item.quantity > 0 and item.use_label:  # Consumable
		var use_btn = Button.new()
		use_btn.text = item.use_label
		use_btn.add_theme_font_override("font", load("res://assets/fonts/PressStart2P-Regular.ttf"))
		use_btn.add_theme_font_size_override("font_size", 10)
		use_btn.add_theme_color_override("font_color", Color(0.96, 0.84, 0.47))
		use_btn.pressed.connect(_on_use_item.bind(item.id))
		hbox.add_child(use_btn)
	
	items_vbox.add_child(panel)

func _on_inventory_changed(_notice: String = "", _count: int = 0) -> void:
	_rebuild_inventory()
	_update_forged_gear()

func _on_weapon_changed(_weapon: Dictionary) -> void:
	_update_forged_gear()
	_rebuild_skill_kit()

func _on_armor_changed(_armor: Dictionary) -> void:
	_rebuild_armor_row()

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
	glyph.add_theme_font_override("font", load("res://assets/fonts/PressStart2P-Regular.ttf"))
	glyph.add_theme_font_size_override("font_size", 22)
	row.add_child(glyph)
	
	var info := VBoxContainer.new()
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = str(armor.get("name", "TRAVELING LIGHT"))
	name_label.add_theme_font_override("font", load("res://assets/fonts/PressStart2P-Regular.ttf"))
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.09, 0.21, 0.17))
	info.add_child(name_label)
	var desc := Label.new()
	desc.text = str(armor.get("desc", "No armor equipped — visit the Ember Trader.")) \
		if not armor.is_empty() else "No armor equipped — visit the Ember Trader."
	desc.add_theme_font_override("font", load("res://assets/fonts/VT323-Regular.ttf"))
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.56, 0.67, 0.45))
	info.add_child(desc)

## One panel per skill in the equipped weapon's kit (1..3 slots)
func _rebuild_skill_kit() -> void:
	_skill_cd_labels.clear()
	for child in skill_kit.get_children():
		child.queue_free()
	
	var skills: Array = game_state.equipped_weapon.get("skills", [])
	for i in skills.size():
		var sk: Dictionary = skills[i]
		var panel := PanelContainer.new()
		panel.add_theme_constant_override("panel_inset", 8)
		skill_kit.add_child(panel)
		
		var vbox := VBoxContainer.new()
		panel.add_child(vbox)
		
		var header := HBoxContainer.new()
		vbox.add_child(header)
		var rune := Label.new()
		rune.text = "%d. %s" % [i + 1, sk.get("name", "?")]
		rune.add_theme_font_override("font", load("res://assets/fonts/PressStart2P-Regular.ttf"))
		rune.add_theme_font_size_override("font_size", 12)
		rune.add_theme_color_override("font_color",
			Color(0.62, 0.55, 0.96) if str(game_state.equipped_weapon.get("style")) == "magic" \
			else Color(0.96, 0.84, 0.47))
		header.add_child(rune)
		var cd := Label.new()
		cd.text = game_state.get_slot_cooldown_text(i)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cd.add_theme_font_override("font", load("res://assets/fonts/PressStart2P-Regular.ttf"))
		cd.add_theme_font_size_override("font_size", 10)
		cd.add_theme_color_override("font_color", Color(0.56, 0.67, 0.45))
		header.add_child(cd)
		_skill_cd_labels.append(cd)
		
		var desc := Label.new()
		var fallback := "Cooldown %ds." % int(sk.get("cooldown", 0))
		desc.text = str(sk.get("desc", fallback))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(180, 0)
		desc.add_theme_font_override("font", load("res://assets/fonts/VT323-Regular.ttf"))
		desc.add_theme_font_size_override("font_size", 11)
		desc.add_theme_color_override("font_color", Color(0.56, 0.67, 0.45))
		vbox.add_child(desc)

func _on_close_pressed() -> void:
	visible = false

func _on_forge_pressed() -> void:
	visible = false
	var forge = get_tree().root.find_child("ForgeMenu", true, false)
	if forge:
		forge.visible = true
