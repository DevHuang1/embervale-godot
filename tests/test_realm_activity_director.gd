extends SceneTree

## Runtime contract for the shared director across all five realms.

const CATALOG := preload("res://scripts/world/realm_activity_catalog.gd")
const REALMS := ["bramblewood", "whispergrove", "mistfen", "heartwood", "moonfen"]

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")
	var watchdog := create_timer(90.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — realm activity director test hung")
		quit(2))

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		print("FAIL: ", message)

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState") as GameState
	_check(gs != null, "GameState autoload missing")
	if gs == null:
		quit(1)
		return
	gs.save_path = "/tmp/embervale_realm_activity_%d.cfg" % OS.get_process_id()
	gs.delete_save()
	for realm in REALMS:
		gs.reset()
		if realm == "bramblewood":
			gs.onboarding_completed = true
		else:
			gs.set_current_realm(realm)
		var scene_path := "res://scenes/world/grove.tscn" \
			if realm == "whispergrove" else Bestiary.biome_scene(realm)
		var packed := load(scene_path) as PackedScene
		_check(packed != null, "%s scene failed to load" % realm)
		if packed == null:
			continue
		var scene := packed.instantiate()
		root.add_child(scene)
		for i in 10:
			await process_frame
		var director := scene.find_child("RealmActivityDirector", true, false)
		_check(director != null, "%s director did not boot" % realm)
		if director == null:
			scene.queue_free()
			await process_frame
			continue
		var diagnostics: Dictionary = director.call("get_diagnostics")
		var activity_realm := str(diagnostics.get("realm", realm))
		_check(int(diagnostics.get("marker_count", 0)) == 6,
			"%s director did not expose six markers" % realm)
		_check(int(diagnostics.get("active_combat_count", 0)) <= 2,
			"%s exceeded the active combat cap" % realm)
		var definitions: Array[Dictionary] = CATALOG.for_realm(activity_realm)
		var preview_hero := scene.get_node_or_null("Hero") as Node3D
		if preview_hero != null and not definitions.is_empty():
			var preview_position: Vector3 = definitions[0].get("position", Vector3.ZERO)
			preview_hero.global_position = preview_position + Vector3(0.0, 0.0, 26.0)
		for i in 20:
			await process_frame
		var life_diagnostics: Dictionary = director.call("get_diagnostics")
		_check(int(life_diagnostics.get("active_world_event_count", 0)) <= 1,
			"%s exceeded the world-event cap" % realm)
		_check(int(life_diagnostics.get("active_ambient_count", 0)) <= 8,
			"%s exceeded the ambient-agent cap" % realm)
		_check(int(life_diagnostics.get("active_world_event_count", 0)) >= 1,
			"%s did not show a life field before interaction range" % realm)
		_check(str(life_diagnostics.get("current_route_beat", "")).is_empty() == false,
			"%s did not expose a current route beat" % realm)
		for marker in scene.get_tree().get_nodes_in_group("activity_marker"):
			if not is_instance_valid(marker) or not marker.is_inside_tree():
				continue
			_check(marker.has_meta("terrain_surface_height"),
				"%s marker %s lacks terrain conformity" % [realm, marker.name])

		var cache_id := str(definitions[5].get("id", ""))
		_check(bool(director.call("begin_activity", cache_id)),
			"%s cache could not begin" % realm)
		await process_frame
		_check(gs.is_world_activity_completed(realm, cache_id),
			"%s cache did not persist completion" % realm)
		_check(not bool(director.call("begin_activity", cache_id)),
			"%s one-time cache began twice" % realm)

		var gather_id := str(definitions[1].get("id", ""))
		_check(bool(director.call("begin_activity", gather_id)),
			"%s gathering activity could not begin" % realm)
		var hero := scene.get_node_or_null("Hero") as Node3D
		if hero != null:
			hero.global_position += Vector3(500.0, 0.0, 500.0)
		for i in 25:
			await process_frame
		var after_unload: Dictionary = director.call("get_diagnostics")
		_check(int(after_unload.get("active_count", 0)) == 0,
			"%s activity node did not unload after leaving range" % realm)
		_check(int(after_unload.get("active_world_event_count", 0)) == 0,
			"%s life field did not clean up after leaving range" % realm)
		_check(int(after_unload.get("life_cleaned_count", 0)) >= 1,
			"%s life cleanup counter did not advance" % realm)
		_check(bool(director.call("begin_activity", gather_id)),
			"%s repeatable activity could not restart after unload" % realm)
		_check(bool(director.call("complete_activity", gather_id,
			{"source": "test", "grant_reward": false})),
			"%s repeatable activity could not complete" % realm)
		_check(not bool(director.call("begin_activity", gather_id)),
			"%s repeatable activity ignored cooldown" % realm)

		scene.queue_free()
		await process_frame
		var audio := root.get_node_or_null("/root/AudioManager")
		if audio != null:
			audio.stop_all_playback()
	gs.delete_save()
	if _failures == 0:
		print("REALM ACTIVITY DIRECTOR PASSED (realms=%d)" % REALMS.size())
	quit(0 if _failures == 0 else 1)
