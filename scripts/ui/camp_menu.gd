extends CanvasLayer
class_name CampMenu

@onready var cards: VBoxContainer = $Root/VBox/CardsScroll/Cards
@onready var status: Label = $Root/VBox/Status
var pending_id: String = ""
var _freeze_was_visible: bool = false
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
	else:
		GameState.pop_world_freeze()

func open() -> void:
	visible = true
	_refresh()

func close() -> void:
	visible = false

func _refresh() -> void:
	$Root/Header/Title.text = "LANTERN CAMP · LEVEL %d" % CampProgression.camp_level
	if pending_id.is_empty():
		_hide_confirm()
	for child in cards.get_children():
		child.queue_free()
	for id in CampProgression.FACILITIES:
		var definition: Dictionary = CampProgression.facility_definition(str(id))
		var button := Button.new()
		var unlocked := CampProgression.facility_unlocked(str(id))
		var cost: Dictionary = definition.get("cost", {})
		var costs: Array[String] = []
		for material in cost:
			costs.append("%d/%d %s" % [int(GameState.call("get_material_qty", str(material))), int(cost[material]), str(material).replace("_", " ")])
		button.text = ("✓ " if unlocked else "◇ ") + str(definition.get("name", id)).to_upper() + "\n" + str(definition.get("benefit", "")) + ("\nFACILITY ACTIVE" if unlocked else "\nCOST: " + ", ".join(costs))
		button.disabled = unlocked
		button.custom_minimum_size = Vector2(0, 108)
		button.pressed.connect(_purchase.bind(str(id)))
		cards.add_child(button)
	for realm in CampProgression.REALMS:
		var mastery: Dictionary = CampProgression.mastery_for(realm)
		var label := Label.new()
		label.text = "%s MASTERY · %d/4\nKills %d/%d · Boss %d/%d · Gather %d/%d · Discover %d/%d" % [realm.to_upper(), CampProgression.mastery_total(realm), mastery.kills, CampProgression.target_for(realm, "kills"), mastery.boss, CampProgression.target_for(realm, "boss"), mastery.gather, CampProgression.target_for(realm, "gather"), mastery.discover, CampProgression.target_for(realm, "discover")]
		UiKit.style_label(label, &"Body", 16)
		cards.add_child(label)

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
