extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scenario := preload("res://scripts/systems/vertical_slice_scenario.gd")
	var snapshot: Dictionary = scenario.setup_clean()
	var ok := not snapshot.is_empty() and str(snapshot.get("checkpoint", "")) == "grove_arrival"
	scenario.cleanup()
	print("Vertical slice scenario validation: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
