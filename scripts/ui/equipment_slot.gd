extends Button
class_name EquipmentSlot

## === Equipment slot ===
## The hero's drop target for one gear slot: a sunken well holding the item's
## icon, the item's name, and the slot's own caption. A filled slot lights its
## frame with the item's rarity; an empty slot stays dark and says EMPTY, so a
## missing piece never reads as a broken one.
##
## Drops arrive from two places: Godot's mouse drag, and the satchel's touch
## long-press drag (which calls force_drag). Both end in _drop_data.

signal item_dropped(item_id: String, slot: StringName)

const SLOT_SIZE := 124.0
const ICON_SIZE := 78.0
const SLOT_CAPTIONS: Dictionary = {
	&"weapon": "WEAPON",
	&"chest": "CHEST",
	&"head": "HEAD",
	&"hands": "HANDS",
	&"relic": "RELIC",
}

var slot: StringName = &"weapon"
var equipped_item: Dictionary = {}

var _accent: Color = UiKit.COPPER
var _icon_holder: PanelContainer
var _icon_rect: TextureRect
var _empty_marker: Control
var _name_label: Label
var _caption_label: Label
var _drop_active := false

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_text = false
	text = ""
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE + 54.0)
	_ensure_children()
	_apply_content()
	_restyle()

## Fills the slot. `tint` is the slot's own accent; a filled slot re-tints to the
## item's rarity so the frame itself reports quality.
func configure(slot_id: StringName, item: Dictionary, tint: Color) -> void:
	slot = slot_id
	equipped_item = item.duplicate(true)
	_accent = tint
	if not equipped_item.is_empty():
		_accent = UiKit.rarity_color(int(equipped_item.get("rarity", 0)), tint)
	_ensure_children()
	_apply_content()
	_restyle()

func _ensure_children() -> void:
	if _icon_holder != null:
		return
	var margin := MarginContainer.new()
	margin.name = "SlotContent"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 8)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	_icon_holder = PanelContainer.new()
	_icon_holder.name = "IconWell"
	_icon_holder.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_icon_holder)
	_icon_rect = TextureRect.new()
	_icon_rect.name = "Icon"
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_holder.add_child(_icon_rect)
	_empty_marker = CenterContainer.new()
	_empty_marker.name = "EmptyMarker"
	_empty_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_marker.add_child(UiKit.diamond_marker(
		Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.30), 22.0))
	_icon_holder.add_child(_empty_marker)
	_name_label = Label.new()
	_name_label.name = "ItemName"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.max_lines_visible = 2
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.style_label(_name_label, &"RowLabel", 22)
	column.add_child(_name_label)
	_caption_label = Label.new()
	_caption_label.name = "SlotCaption"
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.style_label(_caption_label, &"Caption", 18)
	_caption_label.add_theme_color_override("font_color",
		Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.55))
	column.add_child(_caption_label)

func _apply_content() -> void:
	var has_item := not equipped_item.is_empty()
	var item_id := str(equipped_item.get("id", ""))
	var icon: Texture2D = UiKit.icon_texture(item_id) if has_item else null
	_icon_rect.texture = icon
	_icon_rect.visible = icon != null
	_icon_rect.self_modulate = _accent.lightened(0.35)
	_empty_marker.visible = icon == null
	_icon_holder.add_theme_stylebox_override("panel", UiKit.icon_well_stylebox(_accent))
	_name_label.text = str(equipped_item.get("name", item_id)).to_upper() if has_item else "EMPTY"
	_name_label.add_theme_color_override("font_color",
		UiKit.CREAM if has_item else Color(UiKit.CREAM.r, UiKit.CREAM.g, UiKit.CREAM.b, 0.42))
	_caption_label.text = str(SLOT_CAPTIONS.get(slot, str(slot).to_upper()))
	tooltip_text = "%s equipped · drag a replacement here" % str(equipped_item.get("name", "GEAR")) \
		if has_item else "Empty %s slot · drag gear here" % _caption_label.text.to_lower()

func _restyle() -> void:
	var filled := not equipped_item.is_empty()
	add_theme_stylebox_override("normal", UiKit.slot_stylebox(
		filled, _accent, "drop" if _drop_active else "normal"))
	add_theme_stylebox_override("hover", UiKit.slot_stylebox(filled, _accent, "hover"))
	add_theme_stylebox_override("pressed", UiKit.slot_stylebox(filled, _accent, "drop"))
	add_theme_stylebox_override("disabled", UiKit.slot_stylebox(filled, _accent, "normal"))
	add_theme_stylebox_override("focus", UiKit.focus_stylebox(_accent))

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var accepted := false
	if data is Dictionary:
		var item := data as Dictionary
		var game_state := get_tree().root.get_node_or_null("GameState")
		accepted = game_state != null and bool(game_state.call("can_equip_item", item, slot))
	if _drop_active != accepted:
		_drop_active = accepted
		_restyle()
	return accepted

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drop_active = false
	_restyle()
	if data is Dictionary:
		item_dropped.emit(str((data as Dictionary).get("id", "")), slot)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _drop_active:
		_drop_active = false
		_restyle()
