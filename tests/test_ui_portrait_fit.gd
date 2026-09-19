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
	gs.save_path = "/tmp/embervale_portrait_fit.cfg"
	gs.delete_save()
	gs.reset()
	gs.register_analysis("hushling")
	gs.register_analysis("hushling")
	gs.add_material("bramble_wood", 4)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1080, 1920)
	root.add_child(viewport)

	var forge := (load("res://scenes/ui/forge_menu.tscn") as PackedScene).instantiate()
	viewport.add_child(forge)
	await process_frame
	await process_frame
	forge.visible = true
	forge._select_blueprint("mug_mace")
	await process_frame
	await process_frame
	if not _fits(forge):
		failures += 1
		print("FAIL: forge menu minimum width exceeds the portrait frame -> ",
			forge.get_node("Root/VBox").get_combined_minimum_size().x)
	forge.queue_free()
	await process_frame
	var audio := root.get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("stop_one_shots"):
		audio.call("stop_one_shots")
	await process_frame

	var altar := (load("res://scenes/ui/boss_altar.tscn") as PackedScene).instantiate()
	viewport.add_child(altar)
	await process_frame
	await process_frame
	if not _fits(altar):
		failures += 1
		print("FAIL: boss altar minimum width exceeds the portrait frame -> ",
			altar.get_node("Root/VBox").get_combined_minimum_size().x)
	altar.queue_free()
	viewport.queue_free()
	await process_frame
	if audio != null and audio.has_method("stop_all_playback"):
		audio.call("stop_all_playback")
	await process_frame

	if failures == 0:
		print("ALL PORTRAIT FIT TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	gs.delete_save()
	quit(1 if failures > 0 else 0)

func _fits(menu: Node) -> bool:
	var vbox := menu.get_node_or_null("Root/VBox") as Control
	if vbox == null:
		return false
	var frame_width := 1080.0 - 48.0
	return vbox.get_combined_minimum_size().x <= frame_width
