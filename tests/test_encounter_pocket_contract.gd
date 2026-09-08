extends SceneTree

func _init() -> void:
	var zone_script := preload("res://scripts/entities/encounter_zone.gd")
	var zone_source := FileAccess.get_file_as_string("res://scripts/entities/encounter_zone.gd")
	if not zone_source.contains("record_golden_route_signal") or not zone_source.contains("valuable_drop"):
		push_error("Encounter zone is not wired to Golden Route signals")
		quit(1)
		return
	var zone: Area3D = zone_script.new()
	zone.name = "BrambleReveal"
	zone.setup("bramblewood", "elite", 3)
	var contract: Dictionary = zone.pocket_contract()
	if contract.get("id") != "bramble_reveal" \
		or contract.get("realm") != "bramblewood" \
			or contract.get("tier") != "elite" \
			or contract.get("combat") != "Readable combat space" \
			or str((contract.get("ecology", {}) as Dictionary).get("choice", "")).is_empty():
		push_error("Encounter pocket contract is incomplete: %s" % contract)
		quit(1)
		return
	if zone.ecology_choices().size() != 2 or not zone.choose_ecology_tactic("defer") \
			or str(zone.pocket_contract().get("ecology_choice", "")) != "defer":
		push_error("Encounter ecology choice API is incomplete")
		quit(1)
		return
	if not (zone.pocket_contract().get("ecology_modifiers", {}) as Dictionary).is_empty():
		push_error("Deferred ecology tactic should keep default modifiers")
		quit(1)
		return
	var primary := zone_script.new() as Area3D
	primary.setup("bramblewood", "elite", 3)
	if not primary.choose_ecology_tactic("primary") \
			or float((primary.pocket_contract().get("ecology_modifiers", {}) as Dictionary).get("nest_pressure", 0.0)) != 0.7:
		push_error("Primary ecology tactic did not expose bounded consequence")
		quit(1)
		return
	primary.free()
	print("ALL ENCOUNTER POCKET CONTRACT TESTS PASSED")
	zone.free()
	quit()
