extends SceneTree

func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/autoload/game_state.gd")
	var failures := 0
	for required in ["EQUIPMENT_SLOTS", "equipment_slots", "get_equipment_for_slot",
			"can_equip_item", "equip_item_to_slot", "unequip_slot",
			"equipment_changed", "equipment_slots\", equipment_slots"]:
		if not source.contains(required):
			failures += 1
	if not source.contains("cfg.get_value(\"progress\", \"equipped_weapon\"") \
			or not source.contains("cfg.get_value(\"progress\", \"equipped_armor\""):
		failures += 1
	if failures > 0:
		print("FAIL: equipment migration contract missing %d requirements" % failures)
		quit(1)
		return
	print("ALL EQUIPMENT MIGRATION CONTRACT TESTS PASSED")
	quit(0)

