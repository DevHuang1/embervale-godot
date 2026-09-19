extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var gs = root.get_node_or_null("/root/GameState")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.save_path = "/tmp/embervale_boss_trophies_test.cfg"
	gs.delete_save()
	gs.reset()

	var def: Dictionary = Bestiary.boss_def("matriarch")
	var trophies: Array = def.get("trophies", [])
	if trophies.size() < 4:
		failures += 1
		print("FAIL: trophy catalog too small -> ", trophies.size())
	var starters := 0
	for raw in trophies:
		if not raw is Dictionary:
			failures += 1
			print("FAIL: trophy entry is not a dictionary")
			continue
		var trophy: Dictionary = raw
		if str(trophy.get("id", "")).is_empty() or str(trophy.get("name", "")).is_empty():
			failures += 1
			print("FAIL: trophy identity incomplete -> ", trophy)
		if (trophy.get("palette", []) as Array).size() < 2:
			failures += 1
			print("FAIL: trophy palette too small -> ", trophy.get("id", ""))
		if str(trophy.get("unlock_boss", "")).is_empty():
			starters += 1
	if starters < 1:
		failures += 1
		print("FAIL: no starter trophy leaves the first fight uncustomizable")

	var source := FileAccess.get_file_as_string("res://scripts/ui/boss_altar.gd")
	for banned in ["capture_frame", "RelicForge", "SCAN AN OBJECT", "RESCAN"]:
		if source.contains(banned):
			failures += 1
			print("FAIL: altar still references camera flow: ", banned)

	var scene := load("res://scenes/ui/boss_altar.tscn") as PackedScene
	if scene == null:
		print("FAIL: altar scene missing")
		quit(1)
		return
	var altar = scene.instantiate()
	root.add_child(altar)
	await process_frame
	await process_frame

	var starter_button := altar.get_node_or_null(
		"Root/VBox/CustomBox/TrophyPanel/TrophyBox/TrophyRow/Trophy_hollow_root")
	if starter_button == null or starter_button.disabled:
		failures += 1
		print("FAIL: starter trophy not selectable")
	var locked_button := altar.get_node_or_null(
		"Root/VBox/CustomBox/TrophyPanel/TrophyBox/TrophyRow/Trophy_emberheart")
	if locked_button == null or not locked_button.disabled:
		failures += 1
		print("FAIL: first-kill trophy available before the kill")
	if altar._palette.size() < 2:
		failures += 1
		print("FAIL: default trophy palette was not painted")

	altar._selected_skill = Bestiary.skill_pool("matriarch")[0]
	altar._refresh_lock()
	var charges_before: int = gs.scans_remaining
	var resolved_calls: Array = []
	altar.resolved.connect(func(customized): resolved_calls.append(customized))
	altar._on_lock_pressed()
	if gs.scans_remaining != charges_before - 1:
		failures += 1
		print("FAIL: lock-in did not spend exactly one lens charge")
	var payload: Dictionary = gs.get_boss_custom("matriarch")
	if payload.is_empty():
		failures += 1
		print("FAIL: trophy customization was not stored")
	else:
		if (payload.get("palette", []) as Array).size() != altar._palette.size():
			failures += 1
			print("FAIL: stored palette size wrong -> ", payload.get("palette", []))
		if str(payload.get("skill", {}).get("id", "")).is_empty():
			failures += 1
			print("FAIL: stored skill missing")
	if resolved_calls != [true]:
		failures += 1
		print("FAIL: altar resolve contract broken -> ", resolved_calls)
	await create_timer(0.7).timeout
	altar.queue_free()
	await process_frame

	gs.mark_boss_killed("whispergrove_root_harrow")
	var altar_two = scene.instantiate()
	root.add_child(altar_two)
	await process_frame
	await process_frame
	var unlocked_button := altar_two.get_node_or_null(
		"Root/VBox/CustomBox/TrophyPanel/TrophyBox/TrophyRow/Trophy_emberheart")
	if unlocked_button == null or unlocked_button.disabled:
		failures += 1
		print("FAIL: first-kill trophy stayed locked after the kill")
	altar_two.queue_free()
	await process_frame
	var audio := root.get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("stop_all_playback"):
		audio.call("stop_all_playback")
	await process_frame
	await process_frame

	if failures == 0:
		print("ALL BOSS TROPHY TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	gs.delete_save()
	quit(1 if failures > 0 else 0)
