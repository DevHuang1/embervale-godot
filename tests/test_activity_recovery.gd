extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var dungeon_source := FileAccess.get_file_as_string("res://scripts/ui/dungeon_select.gd")
	var beacon_source := FileAccess.get_file_as_string("res://scripts/world/realm_activity_beacon.gd")
	var world_source := FileAccess.get_file_as_string("res://scripts/systems/world_manager.gd")
	if not dungeon_source.contains("begin_activity") or not beacon_source.contains("begin_activity") \
			or not world_source.contains("fail_activity"):
		push_error("activity entry points are not wired to recovery")
		quit(1)
		return
	var gs = root.get_node_or_null("/root/GameState")
	if gs == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	gs.reset()
	if not gs.begin_activity("bramblewood_elite", "elite_gate") or not gs.fail_activity("Player was defeated"):
		push_error("activity failure was not recorded")
		quit(1)
		return
	var failed: Dictionary = gs.get_activity_recovery()
	if str(failed.get("status", "")) != "failed" or str(failed.get("checkpoint_id", "")) != "elite_gate":
		push_error("failed activity snapshot was incomplete")
		quit(1)
		return
	if not gs.begin_activity("beacon", "beacon_approach") or not gs.abandon_activity():
		push_error("activity abandon was not recorded")
		quit(1)
		return
	if str(gs.get_activity_recovery().get("status", "")) != "abandoned":
		push_error("abandoned activity status missing")
		quit(1)
		return
	gs.clear_activity_recovery()
	if not gs.get_activity_recovery().is_empty():
		push_error("activity recovery did not clear")
		quit(1)
		return
	print("ALL ACTIVITY RECOVERY TESTS PASSED")
	quit()
