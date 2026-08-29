extends CanvasLayer
class_name DungeonSelect

const INSTANCES := [
	{"id": "embervault", "name": "EMBERVAULT", "realm": "HEARTWOOD DEPTHS", "glyph": "◆", "difficulty": "NORMAL", "power": 1, "reward": "74 GOLD · EPIC CACHE", "desc": "Descend beneath the old ridge and break the hushling seal."},
	{"id": "moonfen_ruins", "name": "MOONFEN RUINS", "realm": "MOONFEN", "glyph": "☾", "difficulty": "HARD", "power": 3, "reward": "120 GOLD · MOON RELIC", "desc": "A drowned shrine where frost and shadow move together."},
	{"id": "heartwood_core", "name": "HEARTWOOD CORE", "realm": "HEARTWOOD", "glyph": "✦", "difficulty": "ELITE", "power": 5, "reward": "220 GOLD · LEGENDARY CHEST", "desc": "Face the living ember beneath the ancient forest."}
]

@onready var cards: VBoxContainer = $Root/Center/Panel/VBox/Cards
@onready var close_button: Button = $Root/Center/Panel/VBox/Header/Close
@onready var title: Label = $Root/Center/Panel/VBox/Header/Title
@onready var status: Label = $Root/Center/Panel/VBox/Status
var _freeze_was_visible := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_freeze_was_visible = visible
	UiKit.apply_glass($Root/Center/Panel, 18.0, 0.14)
	UiKit.style_button(close_button, UiKit.SAGE)
	close_button.pressed.connect(close)
	_build_cards()

func _process(_delta: float) -> void:
	if visible == _freeze_was_visible:
		return
	_freeze_was_visible = visible
	if visible:
		GameState.push_world_freeze()
	else:
		GameState.pop_world_freeze()

func open() -> void:
	visible = true
	_build_cards()
	UiKit.stagger_entrance(cards, 0.24, 0.04, 16.0)
	AudioManager.play_ui_blip()

func close() -> void:
	visible = false
	AudioManager.play_ui_back()

func _build_cards() -> void:
	for child in cards.get_children():
		child.queue_free()
	for instance in INSTANCES:
		cards.add_child(_build_card(instance))

func _build_card(instance: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 126)
	var sb := UiKit.parchment_stylebox(UiKit.RADIUS_BUTTON)
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var glyph := Label.new()
	glyph.text = str(instance.glyph)
	glyph.custom_minimum_size = Vector2(58, 0)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.style_label(glyph, &"MenuTitle", 34)
	glyph.add_theme_color_override("font_color", UiKit.EMBER)
	row.add_child(glyph)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = "%s  ·  %s" % [str(instance.name), str(instance.difficulty)]
	UiKit.style_label(name_label, &"MenuTitle", 22)
	info.add_child(name_label)
	var realm_label := Label.new()
	realm_label.text = "%s  ·  RECOMMENDED POWER %d" % [str(instance.realm), int(instance.power)]
	UiKit.style_label(realm_label, &"Eyebrow", 14)
	info.add_child(realm_label)
	var desc_label := Label.new()
	desc_label.text = str(instance.desc)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(desc_label, &"Caption", 15)
	info.add_child(desc_label)
	var reward := Label.new()
	reward.text = "REWARDS  ·  %s" % str(instance.reward)
	UiKit.style_label(reward, &"Caption", 14)
	reward.add_theme_color_override("font_color", UiKit.EMBER_BRIGHT)
	info.add_child(reward)
	var enter := Button.new()
	enter.custom_minimum_size = Vector2(190, 58)
	if str(instance.id) == "embervault":
		enter.text = "ENTER"
		UiKit.style_primary_button(enter)
		enter.pressed.connect(_on_enter.bind(str(instance.id)))
	else:
		enter.text = "LOCKED  ·  LV %d" % int(instance.power * 2)
		enter.disabled = true
		UiKit.style_secondary_button(enter)
	row.add_child(enter)
	return panel

func _on_enter(instance_id: String) -> void:
	if instance_id != "embervault":
		return
	var expansion := get_tree().root.find_child("RealmExpansion", true, false)
	if expansion != null and expansion.has_method("toggle_dungeon"):
		close()
		expansion.toggle_dungeon()
		GameState.quest_progress.emit("Embervault selected — descend when ready.")
	else:
		status.text = "The dungeon entrance is not available in this realm."

