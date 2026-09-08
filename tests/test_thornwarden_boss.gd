extends SceneTree

func _init() -> void:
	var path := "res://scenes/entities/boss_bramblewood_thornwarden.tscn"
	var scene_source := FileAccess.get_file_as_string(path)
	var boss_source := FileAccess.get_file_as_string(
		"res://scripts/entities/boss_bramblewood_thornwarden.gd")
	if not scene_source.contains("boss_bramblewood_thornwarden.gd"):
		push_error("Thorn Warden scene does not own its runtime script")
		quit(1)
		return
	for contract in ["root_slam", "vine_grab", "thorn_hurricane", "grove_call",
			"sap_snare", "heartwood_pulse", "thorn_eruption", "grant_boss_kill"]:
		if not boss_source.contains(contract):
			push_error("Thorn Warden missing contract: %s" % contract)
			quit(1)
			return
	print("THORN WARDEN BOSS CONTRACT PASSED")
	quit()
