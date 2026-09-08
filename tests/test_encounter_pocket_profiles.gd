extends SceneTree

func _init() -> void:
	var profiles := preload("res://scripts/systems/encounter_pocket_profiles.gd")
	var profile: Dictionary = profiles.for_realm("mistfen", 2, "elite")
	if profile.get("id") != "reed_hollow_2" or not str(profile.get("reveal", "")).contains("elite"):
		push_error("Mistfen elite pocket profile is incorrect: %s" % profile)
		quit(1)
		return
	profile = profiles.for_realm("heartwood", 0, "normal")
	if profile.get("id") != "ash_ring_0" or profile.get("reward") != "Forge cache":
		push_error("Heartwood pocket profile is incorrect: %s" % profile)
		quit(1)
		return
	print("ALL ENCOUNTER POCKET PROFILE TESTS PASSED")
	quit()
