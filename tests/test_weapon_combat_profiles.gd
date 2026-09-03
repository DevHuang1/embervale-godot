extends SceneTree

## Weapon families must make different commitment decisions while preserving
## the existing heavy-strike damage contract and deterministic timing.

func _initialize() -> void:
	var failures := 0
	var modes: Dictionary = {}
	var holds: Dictionary = {}
	var lunges: Dictionary = {}
	for style in ["blunt", "slash", "magic"]:
		var profile := WeaponCombatProfiles.for_style(style)
		if not WeaponCombatProfiles.timing_is_valid(profile):
			failures += 1
			print("FAIL: timing ratios do not total 1.0 -> ", style)
		if absf(float(profile.get("heavy_damage_mult", 0.0)) - 2.2) > 0.001:
			failures += 1
			print("FAIL: profile silently changed heavy damage -> ", style)
		if str(profile.get("identity", "")).is_empty() \
				or str(profile.get("decision", "")).is_empty():
			failures += 1
			print("FAIL: profile has no communicated gameplay identity -> ", style)
		modes[profile.get("heavy_mode", "")] = true
		holds[profile.get("heavy_hold_ms", 0)] = true
		lunges[profile.get("lunge_speed", 0.0)] = true
	if modes.size() != 3 or holds.size() != 3 or lunges.size() != 3:
		failures += 1
		print("FAIL: weapon families do not create three distinct commitments")
	var fallback := WeaponCombatProfiles.for_style("unknown_modded_style")
	if str(fallback.get("heavy_mode", "")) != "passing_cut":
		failures += 1
		print("FAIL: legacy/custom weapon fallback is not stable")
	print("ALL WEAPON COMBAT PROFILE TESTS PASSED" if failures == 0 \
		else "%d WEAPON PROFILE FAILURES" % failures)
	quit(0 if failures == 0 else 1)
