extends SceneTree

func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/equipment_slot.gd")
	var card_source := FileAccess.get_file_as_string("res://scripts/ui/equipment_drag_card.gd")
	var satchel_source := FileAccess.get_file_as_string("res://scripts/ui/satchel.gd")
	var failures := 0
	for required in ["_can_drop_data", "_drop_data", "item_dropped"]:
		if not source.contains(required):
			failures += 1
	for required in ["_get_drag_data", "set_drag_preview", "duplicate(true)"]:
		if not card_source.contains(required):
			failures += 1
	for required in ["_on_slot_item_dropped", "EQUIPMENT_SLOTS", "_set_section"]:
		if not satchel_source.contains(required):
			failures += 1
	if failures > 0:
		print("FAIL: equipment drag/drop contract missing %d requirements" % failures)
		quit(1)
		return
	print("ALL EQUIPMENT DRAG/DROP CONTRACT TESTS PASSED")
	quit(0)

