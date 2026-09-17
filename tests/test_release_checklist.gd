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
			"RevenueCat entitlements never replace the gameplay database",
			"RevenueCat secret keys never ship in the client",
			"web funnel purchase end to end",
			"survives save/load without granting twice",
			"redirects are refused on every provider request",
			"tampered provider ledger row cannot block a legitimate claim",
			"no secret-shaped value appears in any tracked file",
			"enables the `INTERNET` permission"]:
		if not checklist.contains(gate):
			push_error("Release checklist missing gate: %s" % gate)
			quit(1)
			return
	print("RELEASE CHECKLIST CONTRACT PASSED")
	quit(0)
