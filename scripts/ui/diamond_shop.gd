extends CanvasLayer
class_name DiamondShop

## === The Glintmonger's Case — Diamond Cosmetics ===
## 💎 buys looks and voice ONLY. Every item here is a sidegrade:
## prettier SFX, trail colors, body auras. No stat lines exist on this shelf.

const ITEMS := [
	{"id": "sfx_starlight", "kind": "sfx", "price": 6,
		"name": "Starlight Strikes", "desc": "Bright crystalline combat voice.",
		"value": "ember_glass"},
	{"id": "sfx_shadowstep", "kind": "sfx", "price": 6,
		"name": "Shadow Step", "desc": "Deep moss-dark combat voice.",
		"value": "grave_moss"},
	{"id": "sfx_emberbloom", "kind": "sfx", "price": 6,
		"name": "Ember Bloom", "desc": "Resinous, hollow-grove voice.",
		"value": "hollow_resin"},
	{"id": "trail_aurora", "kind": "trail", "price": 4,
		"name": "Aurora Trail", "desc": "Teal-green blade ribbons.",
		"value": "73f2d9"},
	{"id": "trail_bloodmoon", "kind": "trail", "price": 4,
		"name": "Bloodmoon Trail", "desc": "Crimson blade ribbons.",
		"value": "ff4d47"},
	{"id": "aura_lostlantern", "kind": "aura", "price": 8,
		"name": "Lantern of the Lost", "desc": "Violet soul-shine aura.",
		"value": "8a63ff55"},
	{"id": "aura_crownlight", "kind": "aura", "price": 8,
		"name": "Crown of Light", "desc": "Warm halo-gold aura.",
		"value": "ffd27a55"},
]

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var diamonds_label: Label = $Root/Center/Panel/VBox/Header/DiamondsLabel
@onready var items_vbox: VBoxContainer = $Root/Center/Panel/VBox/Scroll/ItemsVBox
@onready var message_label: Label = $Root/Center/Panel/VBox/Message
@onready var close_button: Button = $Root/Center/Panel/VBox/Footer/Close
@onready var unequip_button: Button = $Root/Center/Panel/VBox/Footer/UnequipAll

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS  # stay interactive while the world is frozen
	_freeze_was_visible = visible
	# The Glintmonger's case reads as a warm display sheet over the dim.
	UiKit.apply_parchment($Root/Center/Panel)
	UiKit.style_secondary_button(close_button)
	UiKit.style_secondary_button(unequip_button)
	close_button.pressed.connect(close)
	unequip_button.pressed.connect(_on_unequip_all)
	game_state.diamonds_changed.connect(func(_t): _refresh())

func open() -> void:
	visible = true
	_refresh()
	audio.play_ui_blip()

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

func close() -> void:
	visible = false
	audio.play_ui_cancel()

func _refresh() -> void:
	diamonds_label.text = "💎 %d" % game_state.diamonds
	for child in items_vbox.get_children():
		child.queue_free()
	for item in ITEMS:
		items_vbox.add_child(_build_row(item))

func _build_row(item: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_constant_override("panel_inset", 10)
	panel.add_theme_stylebox_override("panel", UiKit.parchment_stylebox(UiKit.RADIUS_BUTTON))
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	var glyph := Label.new()
	match str(item.kind):
		"sfx":
			glyph.text = "🔊"
		"trail":
			glyph.text = "🗡"
		_:
			glyph.text = "✨"
	UiKit.style_label(glyph, "", 22)
	hbox.add_child(glyph)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)
	var name_l := Label.new()
	name_l.text = "%s%s" % [str(item.name),
		"" if str(item.kind) != "sfx" else "  (SFX)"]
	UiKit.style_label(name_l, &"MenuTitle", 13)
	info.add_child(name_l)
	var desc := Label.new()
	desc.text = str(item.desc)
	UiKit.style_label(desc, &"Caption", 11)
	info.add_child(desc)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(160, 0)
	if game_state.active_cosmetic_id_for(str(item.kind)) == str(item.id):
		btn.text = "WORN"
		btn.disabled = true
		UiKit.style_secondary_button(btn)
	elif game_state.owns_cosmetic(str(item.id)):
		btn.text = "EQUIP"
		UiKit.style_button(btn)
		btn.pressed.connect(_on_equip.bind(item))
	else:
		btn.text = "💎 %d" % int(item.price)
		UiKit.style_primary_button(btn)
		btn.pressed.connect(_on_buy.bind(item))
	hbox.add_child(btn)
	return panel

func _on_buy(item: Dictionary) -> void:
	if game_state.purchase_cosmetic(str(item.id), int(item.price),
			str(item.kind), str(item.value)):
		message_label.text = "%s is yours — purely beautiful." % str(item.name)
		audio.play_forge_success()
	else:
		message_label.text = "Not enough diamonds — they favor the patient."
		audio.play_ui_cancel()
	_refresh()

func _on_equip(item: Dictionary) -> void:
	game_state.equip_cosmetic(str(item.kind), str(item.value), str(item.id))
	audio.play_ui_blip()
	_refresh()

func _on_unequip_all() -> void:
	game_state.equip_cosmetic("sfx", "", "")
	game_state.equip_cosmetic("trail", "", "")
	game_state.equip_cosmetic("aura", "", "")
	audio.play_ui_back()
	_refresh()
