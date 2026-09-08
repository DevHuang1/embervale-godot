extends Button
class_name EquipmentSlot

signal item_dropped(item_id: String, slot: StringName)

var slot: StringName = &"weapon"
var equipped_item: Dictionary = {}

func configure(slot_id: StringName, item: Dictionary, tint: Color) -> void:
	slot = slot_id
	equipped_item = item.duplicate(true)
	custom_minimum_size = Vector2(112.0, 112.0)
	text = "%s\n%s" % [str(slot).to_upper(),
		str(item.get("name", "EMPTY")) if not item.is_empty() else "EMPTY SLOT"]
	tooltip_text = "Drop compatible gear here" if item.is_empty() else \
		"%s equipped · drag a replacement here" % str(item.get("name", "GEAR"))
	UiKit.style_secondary_button(self)
	add_theme_color_override("font_color", tint)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var item := data as Dictionary
	return GameState.can_equip_item(item, slot)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary:
		item_dropped.emit(str((data as Dictionary).get("id", "")), slot)

