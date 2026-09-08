extends PanelContainer
class_name EquipmentDragCard

var item: Dictionary = {}

func configure(value: Dictionary) -> void:
	item = value.duplicate(true)
	mouse_filter = Control.MOUSE_FILTER_PASS

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item.is_empty():
		return null
	var preview := Label.new()
	preview.text = "  %s  " % str(item.get("name", "GEAR"))
	preview.add_theme_font_size_override("font_size", 18)
	set_drag_preview(preview)
	return item.duplicate(true)
