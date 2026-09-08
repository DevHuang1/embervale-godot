extends SceneTree

func _init() -> void:
	var script := preload("res://scripts/systems/camp_progression.gd")
	var camp: Node = script.new()
	camp.reset()
	var failures: int = 0
	if camp.camp_level != 1 or camp.facility_unlocked("forge"):
		failures += 1
		push_error("default camp state invalid")
	camp.record_objective("bramblewood", "kills")
	camp.record_objective("bramblewood", "kills")
	if camp.mastery_for("bramblewood").get("kills", 0) != 2:
		failures += 1
		push_error("mastery objective was not idempotent")
	var payload: Dictionary = camp.to_dict()
	var restored: Node = script.new()
	restored.from_dict(payload)
	if restored.progress_for("bramblewood", "kills") != 2:
		failures += 1
		push_error("camp round trip failed")
	var legacy: Node = script.new()
	legacy.from_dict({"version": 0})
	if legacy.camp_level != 1 or not legacy.mastery.has("whispergrove"):
		failures += 1
		push_error("legacy migration failed")
	print("Camp progression validation: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures > 0 else 0)
