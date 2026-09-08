extends SceneTree

func _init() -> void:
	var checklist := FileAccess.get_file_as_string("res://RELEASE_CHECKLIST.md")
	for section in ["Android package and signing", "Privacy and permissions",
			"Store and attribution", "Reliability and support", "RevenueCat gate"]:
		if not checklist.contains(section):
			push_error("Release checklist missing section: %s" % section)
			quit(1)
			return
	for gate in ["suspend/resume", "low-memory recovery", "corrupt-save recovery",
			"RevenueCat entitlements never replace the gameplay database"]:
		if not checklist.contains(gate):
			push_error("Release checklist missing gate: %s" % gate)
			quit(1)
			return
	print("RELEASE CHECKLIST CONTRACT PASSED")
	quit(0)
