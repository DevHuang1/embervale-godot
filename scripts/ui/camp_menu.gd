extends CanvasLayer
class_name CampMenu

@onready var cards: VBoxContainer = $Root/VBox/CardsScroll/Cards
@onready var status: Label = $Root/VBox/Status
@onready var title: Label = $Root/Header/Title
@onready var intro: Label = $Root/VBox/Intro

## Facilities carry an authored icon where one exists; the rest fall back to the
## shared diamond inlay so a missing glyph never reads as a bug.
const FACILITY_ICONS := {
	"forge": "ore",
	"gatherer_grove": "sigil_bramble",
	"lantern_beacon": "fire",
	"rootway_beacon": "sigil_root",
}
const MASTERY_TRACKS := [
	{"key": "kills", "label": "Kills"},
	{"key": "boss", "label": "Bosses"},
	{"key": "gather", "label": "Gathered"},
	{"key": "discover", "label": "Discovered"},
]
var pending_id: String = ""
var _freeze_was_visible: bool = false
var _freeze_held: bool = false
## One persistent confirm control for the whole menu. The previous version
## appended a fresh button on every facility press and never removed it, so the
## list grew duplicate CONFIRM UNLOCK entries that all fired at whatever was
## pressed last.
var _confirm_button: Button = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Root.add_theme_stylebox_override("panel", UiKit.glass_stylebox())
	$Root/Header/Close.pressed.connect(close)
	_build_confirm_button()
	CampProgression.changed.connect(_refresh)
	CampProgression.notice.connect(_show_notice)
	_apply_responsive_frame()
	get_viewport().size_changed.connect(_apply_responsive_frame)
	_refresh()

## Phone frame: the camp panel is authored 60 px in from the sides and 130 px
## top/bottom, so those are the margins apply_menu_frame must reproduce.
func _apply_responsive_frame() -> void:
	# The dimmer is authored at a fixed 1080x1920; keep it covering any viewport.
	var dim := get_node_or_null("Dim") as Control
	if dim != null:
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiKit.apply_menu_frame(get_node_or_null("Root") as Control,
		get_viewport().get_visible_rect().size, 60.0, 130.0)

func _build_confirm_button() -> void:
	_confirm_button = Button.new()
	_confirm_button.name = "ConfirmUnlock"
	_confirm_button.custom_minimum_size = Vector2(0, 56)
	_confirm_button.visible = false
	UiKit.style_primary_button(_confirm_button)
	_confirm_button.pressed.connect(_confirm_purchase)
	var vbox := get_node_or_null("Root/VBox")
	if vbox != null:
		vbox.add_child(_confirm_button)
		if status != null and status.get_parent() == vbox:
			vbox.move_child(_confirm_button, status.get_index())

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
	_refresh()

func close() -> void:
	visible = false

func _refresh() -> void:
	title.text = "LANTERN CAMP"
	intro.text = "Level %d · Strengthen the light you carry between realms." % CampProgression.camp_level
	if pending_id.is_empty():
		_hide_confirm()
	for child in cards.get_children():
		child.queue_free()
	cards.add_child(UiKit.section_header("Facilities", UiKit.COPPER,
		"%d / %d ACTIVE" % [_unlocked_count(), CampProgression.FACILITIES.size()]))
	for id in CampProgression.FACILITIES:
		cards.add_child(_build_facility_card(str(id)))
	if not CampProgression.REALMS.is_empty():
		cards.add_child(UiKit.section_header("Realm Mastery", UiKit.VERDIGRIS,
			"EARN CAMP LEVELS"))
	for realm in CampProgression.REALMS:
		cards.add_child(_build_mastery_card(str(realm)))

func _unlocked_count() -> int:
	var count := 0
	for id in CampProgression.FACILITIES:
		if CampProgression.facility_unlocked(str(id)):
			count += 1
	return count

## One facility reads as a card, not a paragraph: icon, name, what it unlocks,
## its material costs as chips, and a single action whose label says what will
## happen. A story-granted facility shows why it has no button instead of an
## empty cost line.
func _build_facility_card(id: String) -> Control:
	var definition := CampProgression.facility_definition(id)
	var unlocked := CampProgression.facility_unlocked(id)
	var grant_only := bool(definition.get("grant_only", false))
	var cost: Dictionary = definition.get("cost", {})
	var missing: Array[String] = []
	for material in cost:
		if int(GameState.call("get_material_qty", str(material))) < int(cost[material]):
			missing.append(str(material))
	var affordable := missing.is_empty()

	var panel := PanelContainer.new()
	panel.name = "Facility_%s" % id
	panel.add_theme_stylebox_override("panel",
		UiKit.glass_stylebox(false, 0.30 if unlocked else 0.55))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	row.add_child(UiKit.icon_well(str(FACILITY_ICONS.get(id, id)),
		UiKit.VERDIGRIS if unlocked else UiKit.COPPER, 64.0))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	# A flow container lets the state badge drop to a second line instead of
	# squeezing the facility name into an ellipsis on a narrow phone.
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 10)
	head.add_theme_constant_override("v_separation", 6)
	info.add_child(head)
	var name_label := Label.new()
	name_label.text = str(definition.get("name", id))
	name_label.custom_minimum_size = Vector2(170, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiKit.style_label(name_label, &"RowLabel", 24)
	head.add_child(name_label)
	if unlocked:
		head.add_child(UiKit.badge("Active", UiKit.VERDIGRIS))
	elif grant_only:
		head.add_child(UiKit.badge("Story unlock", UiKit.MOON))
	elif affordable:
		head.add_child(UiKit.badge("Ready", UiKit.EMBER))
	else:
		head.add_child(UiKit.badge("Missing materials", UiKit.COPPER))
	var benefit := Label.new()
	benefit.text = str(definition.get("benefit", ""))
	benefit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(benefit, &"Caption", 18)
	benefit.add_theme_color_override("font_color", Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.72))
	info.add_child(benefit)
	if not cost.is_empty():
		var costs := HFlowContainer.new()
		costs.add_theme_constant_override("h_separation", 8)
		costs.add_theme_constant_override("v_separation", 6)
		info.add_child(costs)
		for material in cost:
			var have := int(GameState.call("get_material_qty", str(material)))
			var need := int(cost[material])
			costs.add_child(UiKit.badge("%s %d/%d" % [str(material).replace("_", " "), have, need],
				UiKit.VERDIGRIS if have >= need else UiKit.BLOOD))

	var action := Button.new()
	action.name = "Action"
	action.custom_minimum_size = Vector2(136, 56)
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if unlocked:
		action.text = "ACTIVE"
		action.disabled = true
		UiKit.style_secondary_button(action)
	elif grant_only:
		action.text = "EARN IN STORY"
		action.disabled = true
		action.tooltip_text = "This facility is granted by progress, not purchased."
		UiKit.style_secondary_button(action)
	else:
		action.text = "UNLOCK"
		action.disabled = not affordable
		if affordable:
			UiKit.style_primary_button(action)
			action.tooltip_text = "Spend the listed materials to unlock this facility."
			action.pressed.connect(_purchase.bind(id))
		else:
			UiKit.style_secondary_button(action)
			action.tooltip_text = "Still missing: %s" % ", ".join(missing).replace("_", " ")
	row.add_child(action)
	return panel

## Mastery reads as progress, not a wall of counters: one header, one bar, and a
## single compact track line underneath.
func _build_mastery_card(realm: String) -> Control:
	var mastery: Dictionary = CampProgression.mastery_for(realm)
	var total := CampProgression.mastery_total(realm)
	var panel := PanelContainer.new()
	panel.name = "Mastery_%s" % realm
	panel.add_theme_stylebox_override("panel", UiKit.glass_stylebox(false, 0.38))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UiKit.section_header(realm.replace("_", " "), UiKit.VERDIGRIS,
		"%d / 4" % total))
	box.add_child(UiKit.progress_bar(float(total), 4.0, UiKit.VERDIGRIS))
	var parts: Array[String] = []
	for track in MASTERY_TRACKS:
		var key := str(track["key"])
		parts.append("%s %d/%d" % [str(track["label"]).to_upper(),
			int(mastery.get(key, 0)), CampProgression.target_for(realm, key)])
	var line := Label.new()
	line.text = " · ".join(parts)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(line, &"Caption", 18)
	line.add_theme_color_override("font_color", Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.62))
	box.add_child(line)
	return panel

func _purchase(id: String) -> void:
	pending_id = id
	var facility_name := str(CampProgression.facility_definition(id).get("name", id))
	status.text = "CONFIRM %s — press CONFIRM UNLOCK below." % facility_name
	if _confirm_button != null and is_instance_valid(_confirm_button):
		_confirm_button.text = "CONFIRM UNLOCK: %s" % facility_name.to_upper()
		_confirm_button.visible = true

func _confirm_purchase() -> void:
	if pending_id.is_empty():
		_hide_confirm()
		return
	var id := pending_id
	pending_id = ""
	_hide_confirm()
	CampProgression.purchase_facility(id)
	_refresh()

func _hide_confirm() -> void:
	if _confirm_button != null and is_instance_valid(_confirm_button):
		_confirm_button.visible = false

func _show_notice(message: String) -> void:
	status.text = message

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
