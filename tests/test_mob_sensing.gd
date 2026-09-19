extends SceneTree

## Mob sensing contract: per-archetype sight/hearing/leash/wander data stays
## complete and sane, the cone/hearing math behaves, and the shared enemy AI
## actually reads the profile it is handed.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures: Array[String] = []
	for failure in MobSensing.validate():
		failures.append("profile contract: %s" % failure)

	var mob_kinds := ["hushling", "spitter", "elite", "charger", "ambusher",
		"thorn_charger", "mire_stalker", "ember_warden", "spore_weaver",
		"relic_leech", "fenling", "moonfen_fenling"]
	for kind in mob_kinds:
		var profile := MobSensing.profile_for(kind)
		for key in MobSensing.DEFAULT_PROFILE:
			if not profile.has(key):
				failures.append("%s missing %s" % [kind, key])

	# Vision cone: +Z is forward (hero/boss convention), 110 deg = +/-55.
	var forward := Vector3(0, 0, 1)
	if not MobSensing.in_sight_cone(forward, Vector3(0, 0, 6), 110.0):
		failures.append("straight-ahead target was not seen")
	if MobSensing.in_sight_cone(forward, Vector3(0, 0, -6), 110.0):
		failures.append("target directly behind was seen")
	var inside_edge := Vector3(sin(deg_to_rad(45.0)), 0, cos(deg_to_rad(45.0)))
	if not MobSensing.in_sight_cone(forward, inside_edge, 110.0):
		failures.append("target inside the cone edge was not seen")
	var outside_edge := Vector3(sin(deg_to_rad(70.0)), 0, cos(deg_to_rad(70.0)))
	if MobSensing.in_sight_cone(forward, outside_edge, 110.0):
		failures.append("target outside the cone edge was seen")
	if not MobSensing.in_sight_cone(forward, Vector3(0, 0, -6), 360.0):
		failures.append("360-degree vision missed a target behind")
	if MobSensing.in_sight_cone(Vector3.ZERO, forward, 140.0) \
			or MobSensing.in_sight_cone(forward, Vector3.ZERO, 140.0):
		failures.append("degenerate cone input counted as seen")

	# Hearing: the quieter of the two radii wins.
	if not MobSensing.hears(Vector3(0, 0, 0), 9.0, Vector3(0, 0, 6), 7.0):
		failures.append("noise inside both radii was not heard")
	if MobSensing.hears(Vector3(0, 0, 0), 9.0, Vector3(0, 0, 8), 7.0):
		failures.append("noise beyond the listener's hearing was heard")
	if MobSensing.hears(Vector3(0, 0, 0), 3.0, Vector3(0, 0, 5), 12.0):
		failures.append("quiet noise was heard beyond its own radius")
	if MobSensing.hears(Vector3(0, 0, 0), 0.0, Vector3(0, 0, 1), 12.0):
		failures.append("silent noise was heard")

	# Integration: the shared AI applies the profile it is given.
	var hushling_script := load("res://scripts/entities/hushling.gd") as GDScript
	var enemy := hushling_script.new() as Node3D
	enemy.call("configure_archetype", "thorn_charger")
	var applied: Dictionary = enemy.get("_sensing")
	var profile := MobSensing.profile_for("thorn_charger")
	if float(applied.get("leash_radius", 0.0)) != float(profile.leash_radius):
		failures.append("configure_archetype did not apply the sensing profile")
	if not is_equal_approx(float(enemy.get("aggro_radius")),
			float(profile.sight_radius)):
		failures.append("aggro_radius did not mirror the sight radius")
	enemy.free()

	# Functional perception and idle behaviour on a real enemy instance in a
	# bare world: no occluders, so every vision result is decided by the cone,
	# the peripheral range and the hearing radii alone.
	var arena := Node3D.new()
	root.add_child(arena)
	var player := Node3D.new()
	player.name = "player"
	player.add_to_group("player")
	arena.add_child(player)
	var mob_scene := load("res://scenes/entities/hushling.tscn") as PackedScene
	var mob := mob_scene.instantiate() as Node3D
	arena.add_child(mob)
	mob.call("configure_archetype", "mire_stalker")
	var mob_profile := MobSensing.profile_for("mire_stalker")

	player.global_position = Vector3(0, 0, 5)
	if not bool(mob.call("_can_sense_player", player)):
		failures.append("player straight ahead was not sensed")
	player.global_position = Vector3(0, 0, -5)
	if bool(mob.call("_can_sense_player", player)):
		failures.append("player behind the mob was sensed through the cone")
	player.global_position = Vector3(0, 0, -1.5)
	if not bool(mob.call("_can_sense_player", player)):
		failures.append("player inside the peripheral range was not sensed")
	player.global_position = Vector3(0, 0, -12)
	if bool(mob.call("_can_sense_player", player)):
		failures.append("player beyond the sight radius was sensed")

	# Hearing reaches through the cone: a swing behind the mob still wakes it,
	# a distant one does not.
	player.global_position = Vector3(0, 0, -5)
	mob.call("_on_player_noise", Vector3(0, 0, -7), 12.0)
	if not bool(mob.call("_can_sense_player", player)):
		failures.append("heard noise behind the mob did not engage it")
	mob.call("_on_player_noise", Vector3(0, 0, -40), 12.0)
	if bool(mob.call("_can_sense_player", player)):
		failures.append("noise beyond the hearing radius engaged the mob")

	# Leash: an engaged mob that drifts past its anchor radius breaks off and
	# heads home instead of freezing wherever it happened to be.
	player.global_position = Vector3(0, 0, 3)
	mob.global_position = Vector3.ZERO
	mob.set("_home_position", Vector3(0, 0, -30))
	mob.set("_player_engaged", true)
	mob.call("_update_pattern", 0.1)
	if bool(mob.get("_player_engaged")) or not bool(mob.get("_returning")):
		failures.append("leash break did not disengage the mob")

	# Leash return steers home and settles; wander picks targets inside radius.
	mob.global_position = Vector3(0, 0, 20)
	mob.set("_home_position", Vector3.ZERO)
	mob.set("_returning", true)
	mob.call("_idle_movement", 0.5)
	var homeward := Vector3(mob.velocity.x, 0.0, mob.velocity.z)
	if homeward.length() < 0.05 \
			or homeward.normalized().dot(Vector3(0, 0, -1)) < 0.9:
		failures.append("returning mob did not steer toward its home anchor")
	mob.global_position = Vector3(0, 0, 0.5)
	mob.call("_idle_movement", 0.1)
	if bool(mob.get("_returning")):
		failures.append("returning mob did not settle at its home anchor")
	mob.global_position = Vector3.ZERO
	mob.set("_returning", false)
	mob.set("_wander_target", Vector3.ZERO)
	mob.set("_wander_timer", 0.0)
	mob.call("_idle_movement", 0.2)
	var wander_target: Vector3 = mob.get("_wander_target")
	if wander_target == Vector3.ZERO or Vector3(wander_target.x, 0.0,
			wander_target.z).length() > float(mob_profile.wander_radius) + 0.001:
		failures.append("wander target was not picked inside the wander radius")
	arena.free()

	var source := FileAccess.get_file_as_string("res://scripts/entities/hushling.gd")
	for token in ["MobSensing.profile_for", "_can_sense_player", "_idle_movement",
			"_returning", "_leash_radius", "_home_position", "noise_emitted"]:
		if not source.contains(token):
			failures.append("hushling sensing wiring missing: %s" % token)
	var hero_source := FileAccess.get_file_as_string("res://scripts/entities/hero.gd")
	if not hero_source.contains("signal noise_emitted") \
			or not hero_source.contains("func emit_noise"):
		failures.append("hero noise emitter is missing")

	if failures.is_empty():
		print("MOB SENSING TESTS PASSED")
	else:
		print("FAILURES: ", failures)
	quit(1 if not failures.is_empty() else 0)
