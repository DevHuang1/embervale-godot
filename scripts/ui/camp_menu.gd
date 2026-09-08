extends CanvasLayer
class_name CampMenu

@onready var cards: VBoxContainer = $Root/VBox/CardsScroll/Cards
@onready var status: Label = $Root/VBox/Status
var pending_id: String = ""
var _freeze_was_visible: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.apply_glass($Root)
	$Root/VBox/Close.pressed.connect(close)
	CampProgression.changed.connect(_refresh)
	CampProgression.notice.connect(_show_notice)
	_refresh()

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
	$Root/VBox/Title.text = "LANTERN CAMP · LEVEL %d" % CampProgression.camp_level
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
	status.text = "CONFIRM %s — press CONFIRM UNLOCK below." % str(CampProgression.facility_definition(id).get("name", id))
	var confirm := Button.new()
	confirm.name = "ConfirmUnlock"
	confirm.text = "CONFIRM UNLOCK"
	confirm.custom_minimum_size = Vector2(0, 56)
	confirm.pressed.connect(_confirm_purchase)
	cards.add_child(confirm)

func _confirm_purchase() -> void:
	if pending_id.is_empty():
		return
	var id := pending_id
	pending_id = ""
	CampProgression.purchase_facility(id)
	_refresh()

func _show_notice(message: String) -> void:
	status.text = message
