extends SceneTree

func _initialize() -> void:
	var script := load("res://scripts/entities/hushling.gd") as GDScript
	if script == null:
		push_error("Hushling script missing")
		quit(1)
		return
	for kind in ["charge", "bramble_charge", "counter", "charger", "ambusher",
		"mire_stalker", "ember_warden", "spore_weaver", "relic_leech",
		"fenling", "moonfen_fenling", "elite"]:
		var timing: Dictionary = script.special_attack_timing(kind)
		if timing.is_empty() or float(timing.get("anticipation", 0.0)) <= 0.0 \
			or float(timing.get("recovery", 0.0)) <= 0.0:
			push_error("Missing bounded timing contract for %s" % kind)
			quit(1)
			return
		if timing.has("radius") and (float(timing.get("radius", 0.0)) <= 0.0 \
			or float(timing.get("radius", 0.0)) > 8.0):
			push_error("Unbounded elite special radius for %s" % kind)
			quit(1)
			return
	var boss_script := load("res://scripts/entities/boss_base.gd") as GDScript
	if boss_script == null:
		push_error("BossBase script missing")
		quit(1)
		return
	for kind in ["mend", "basic_slam", "ultimate", "root_prison", "thorn_rain", "bramble_storm", "thorn_lattice", "spore_bloom"]:
		var profile: Dictionary = boss_script.attack_profile(kind)
		var boss_timing: Dictionary = boss_script.attack_timing(kind)
		if boss_timing.is_empty() \
			or float(boss_timing.get("anticipation", 0.0)) <= 0.0 \
			or float(boss_timing.get("active", 0.0)) <= 0.0 \
			or float(boss_timing.get("recovery", 0.0)) <= 0.0 \
			or float(boss_timing.get("total_lock", 0.0)) <= float(boss_timing.get("impact_at", 0.0)):
			push_error("Incomplete boss timing contract for %s" % kind)
			quit(1)
			return
		if profile.has("radius") and (float(profile.get("radius", 0.0)) <= 0.0 \
			or float(profile.get("radius", 0.0)) > 12.0):
			push_error("Unbounded boss attack radius for %s" % kind)
			quit(1)
			return
	print("ALL ELITE ATTACK TIMING TESTS PASSED")
	quit(0)
