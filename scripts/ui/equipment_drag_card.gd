extends PanelContainer
class_name EquipmentDragCard

## === Draggable gear card ===
## Mouse drags use Godot's built-in drag-and-drop. Touch drags start from a short
## hold, because a plain finger drag inside a ScrollContainer is consumed as
## scrolling long before the card sees a drag. Both paths hand the hero slots the
## same dictionary, so a drop equips identically either way.
##
## A tap that never becomes a drag reports inspect_requested instead, which keeps
## the whole item loop reachable without dragging.

signal inspect_requested(item: Dictionary)

const LONG_PRESS_SECONDS := 0.35

var item: Dictionary = {}

var _hold: Timer
var _press_started_ms := -1
var _dragged := false

func configure(value: Dictionary) -> void:
	item = value.duplicate(true)
	mouse_filter = Control.MOUSE_FILTER_PASS

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	_hold = Timer.new()
	_hold.name = "HoldToDrag"
	_hold.one_shot = true
	_hold.wait_time = LONG_PRESS_SECONDS
	_hold.timeout.connect(_begin_touch_drag)
	add_child(_hold)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item.is_empty():
		return null
	_dragged = true
	set_drag_preview(drag_preview())
	return item.duplicate(true)

## A miniature of the card itself, so the drag reads as the item travelling
## rather than as a floating word.
func drag_preview() -> Control:
	var accent := UiKit.rarity_color(int(item.get("rarity", 0)))
	var preview := PanelContainer.new()
	preview.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(accent, true))
	preview.custom_minimum_size = Vector2(240, 88)
	preview.modulate.a = 0.94
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	preview.add_child(row)
	row.add_child(UiKit.icon_well(str(item.get("id", "")), accent, 56.0))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = str(item.get("name", "GEAR")).to_upper()
	UiKit.style_label(name_label, &"RowLabel", 22)
	info.add_child(name_label)
	var hint := Label.new()
	hint.text = "DROP ON A HERO SLOT"
	UiKit.style_label(hint, &"Caption", 18)
	hint.add_theme_color_override("font_color", accent)
	info.add_child(hint)
	return preview

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press_started_ms = Time.get_ticks_msec()
			_hold.start()
		else:
			_hold.stop()
			_report_tap()
	elif event is InputEventScreenDrag:
		# The finger is scrolling the grid, not dragging gear.
		_hold.stop()
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_press_started_ms = Time.get_ticks_msec()
		else:
			_report_tap()

func _report_tap() -> void:
	var held_ms := Time.get_ticks_msec() - _press_started_ms if _press_started_ms >= 0 else 0
	_press_started_ms = -1
	if _dragged:
		_dragged = false
		return
	if held_ms < int(LONG_PRESS_SECONDS * 1000.0) and not item.is_empty():
		inspect_requested.emit(item.duplicate(true))

func _begin_touch_drag() -> void:
	if _dragged or item.is_empty() or not is_inside_tree():
		return
	_dragged = true
	force_drag(item.duplicate(true), drag_preview())
