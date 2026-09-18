extends CanvasLayer
class_name DungeonSelect

const INSTANCES := [
	{"id": "embervault", "realm_id": "heartwood", "name": "EMBERVAULT", "realm": "HEARTWOOD DEPTHS", "glyph": "◆", "difficulty": "NORMAL", "power": 1, "reward": "74 GOLD · EPIC CACHE", "desc": "Descend beneath the old ridge and break the hushling seal."},
	{"id": "moonfen_ruins", "realm_id": "moonfen", "name": "MOONFEN RUINS", "realm": "MOONFEN", "glyph": "☾", "difficulty": "HARD", "power": 3, "reward": "120 GOLD · MOON RELIC", "desc": "A drowned shrine where frost and shadow move together."},
	{"id": "heartwood_core", "realm_id": "heartwood", "name": "HEARTWOOD CORE", "realm": "HEARTWOOD", "glyph": "✦", "difficulty": "ELITE", "power": 5, "reward": "220 GOLD · LEGENDARY CHEST", "desc": "Face the living ember beneath the ancient forest."}
]

@onready var cards: VBoxContainer = $Root/Center/Panel/VBox/CardsScroll/Cards
@onready var close_button: Button = $Root/Center/Panel/VBox/Header/Close
@onready var title: Label = $Root/Center/Panel/VBox/Header/Title
@onready var status: Label = $Root/Center/Panel/VBox/Status
var _freeze_was_visible := false
var _freeze_held := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
		_freeze_held = true
	else:
		_release_world_freeze()

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
	var unlocked := str(instance.get("id", "")) == "embervault" or str(instance.get("realm_id", "")) in GameState.unlocked_realms
	var current := str(instance.get("realm_id", "")) == str(GameState.current_realm)
	var cleared := bool(GameState.quest_reward_claims.get("dungeon_%s_complete" % str(instance.id), false))
	var realm_state := UiKit.action_state("equipped" if current else ("owned" if unlocked else "locked"),
		"CURRENT REALM" if current else ("AVAILABLE" if unlocked else "UNLOCK TO ENTER"))
	realm_label.text = "%s  ·  RECOMMENDED POWER %d  ·  %s%s" % [str(instance.realm), int(instance.power), str(realm_state.get("detail", "")), "  ·  CLEARED" if cleared else ""]
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
	if unlocked:
		enter.text = "ENTER" if not current else "CURRENT REALM"
		enter.tooltip_text = "Travel to this realm" if not current else "You are already here"
		enter.disabled = current
		UiKit.style_primary_button(enter)
		if not current:
			enter.pressed.connect(_on_enter.bind(str(instance.id)))
	else:
		var locked_state := UiKit.action_state("locked", "UNLOCK %s" % str(instance.realm))
		enter.text = "%s  ·  %s" % [locked_state.get("label", "LOCKED"), locked_state.get("detail", "")]
		enter.disabled = true
		enter.tooltip_text = "Complete the required progression to unlock this realm"
		UiKit.style_secondary_button(enter)
	row.add_child(enter)
	return panel

func _on_enter(instance_id: String) -> void:
	if instance_id != "embervault":
		var target_realm := ""
		for instance in INSTANCES:
			if str(instance.get("id", "")) == instance_id:
				target_realm = str(instance.get("realm_id", ""))
				break
		if target_realm.is_empty() or target_realm not in GameState.unlocked_realms:
			return
		var realm_scene := Bestiary.biome_scene(target_realm)
		if realm_scene.is_empty() or not ResourceLoader.exists(realm_scene):
			status.text = "The %s route is not available yet." % target_realm.to_upper()
			return
		GameState.set_current_realm(target_realm)
		GameState.begin_activity("expedition_%s" % target_realm, str(GameState.route_checkpoint_id))
		GameState.quest_progress.emit("Entering %s — prepare for its realm hazards." % target_realm.to_upper())
		_travel_with_fade(realm_scene)
		return
	var expansion := get_tree().root.find_child("RealmExpansion", true, false)
	if expansion != null and expansion.has_method("toggle_dungeon"):
		GameState.begin_activity("embervault", str(GameState.route_checkpoint_id))
		close()
		expansion.toggle_dungeon()
		GameState.quest_progress.emit("Embervault selected — descend when ready.")
	else:
		status.text = "The dungeon entrance is not available in this realm."

func _travel_with_fade(scene_path: String) -> void:
	close()
	var fade := ColorRect.new()
	fade.name = "RealmTransitionFade"
	fade.color = Color(0.005, 0.01, 0.008, 0.0)
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$Root.add_child(fade)
	var tween := fade.create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(SceneLoader.travel.bind(scene_path))

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
