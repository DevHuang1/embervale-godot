extends SceneTree

## Real-renderer portrait captures of the forge menu and the boss altar at the
## authored 1080x1920 target. Writes PNGs under /tmp/embervale_ui_capture.
## Run: godot --path . --script tools/capture_ui_portrait.gd

const OUTPUT_DIR := "/tmp/embervale_ui_capture"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var gs := get_root().get_node_or_null("GameState")
	if gs != null:
		gs.save_path = OUTPUT_DIR.path_join("progress.cfg")
		gs.delete_save()
		gs.reset()
		gs.register_analysis("hushling")
		gs.register_analysis("hushling")
		gs.add_material("bramble_wood", 12)
		gs.add_material("moss_fiber", 8)
		gs.add_material("iron_shard", 6)
		gs.add_material("beast_hide", 4)
		gs.add_material("spore_dust", 4)
	await _capture_forge()
	await _capture_altar()
	await _capture_hud_ledger()
	if gs != null:
		gs.delete_save()
	quit()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _capture_forge() -> void:
	var instance := (load("res://scenes/ui/forge_menu.tscn") as PackedScene).instantiate()
	get_root().add_child(instance)
	await process_frame
	await process_frame
	instance.visible = true
	instance._select_blueprint("mug_mace")
	await process_frame
	await process_frame
	await _save_capture("forge_menu_portrait.png")
	instance.queue_free()
	await process_frame

func _capture_altar() -> void:
	var instance := (load("res://scenes/ui/boss_altar.tscn") as PackedScene).instantiate()
	get_root().add_child(instance)
	await process_frame
	await process_frame
	await _save_capture("boss_altar_portrait.png")
	instance.queue_free()
	await process_frame

## Quest-ledger fold over the live grove HUD: expanded tracker, the one-line
## strip it folds into, and the enlarged joystick the freed corner allows. The
## preference is applied directly (never through the player's settings file).
func _capture_hud_ledger() -> void:
	var instance := (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	get_root().add_child(instance)
	await _frames(30)
	var hud := instance.get_node_or_null("HUD") as Node
	if hud == null:
		print("FAIL: grove HUD missing for quest-ledger capture")
		instance.queue_free()
		return
	hud.call("_set_ledger_minimized", false, false)
	await _frames(4)
	await _save_capture("hud_quest_ledger_expanded.png")
	hud.call("_set_ledger_minimized", true, false)
	await _frames(4)
	await _save_capture("hud_quest_ledger_folded.png")
	var joystick := hud.get_node_or_null("Root/MoveJoystick") as Control
	if joystick != null:
		joystick.scale = Vector2.ONE * 1.45
		hud.call("_sync_joystick_pivot")
		await _frames(4)
		await _save_capture("hud_joystick_large_folded.png")
	instance.queue_free()
	await process_frame

func _save_capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	if image == null:
		print("FAIL: no capture for ", file_name)
		return
	var path := OUTPUT_DIR.path_join(file_name)
	image.save_png(path)
	print("SAVED %s %s" % [path, str(image.get_size())])
