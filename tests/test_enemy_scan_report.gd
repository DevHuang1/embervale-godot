extends SceneTree

func _initialize() -> void:
	var dummy := Node3D.new()
	dummy.name = "Fen Stalker"
	dummy.set_meta("scan_hp", 50)
	dummy.set_meta("scan_attack", 8)
	dummy.set_meta("scan_speed", 3.5)
	dummy.set_meta("scan_kind", "mire_stalker")
	root.add_child(dummy)
	var report := Bestiary.scan_report(dummy)
	if int(report.get("hp", 0)) != 50 or int(report.get("attack", 0)) != 8 \
		or int(report.get("magic_resist", 0)) != 5:
		print("FAIL: enemy scan report did not resolve bounded stats")
		quit(1)
		return
	if not str(report.get("ecology", "")).contains("PREDATOR / PREY"):
		print("FAIL: enemy scan report did not expose readable ecology context")
		quit(1)
		return
	print("ALL ENEMY SCAN REPORT TESTS PASSED")
	quit(0)
