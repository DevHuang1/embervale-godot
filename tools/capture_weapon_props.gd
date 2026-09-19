extends SceneTree

## Real-renderer captures of the forge kits: in the hero's hand (world scene)
## and in the satchel preview viewport. Includes the forged `relic_<base>` ids
## so the wielded relic path is covered too. Writes PNGs under
## /tmp/embervale_weapon_props. Run with a real window:
##   godot --path . --script tools/capture_weapon_props.gd --rendering-driver metal

const OUT := "/tmp/embervale_weapon_props"
const WEAPON_IDS := ["mug_mace", "pocket_blade", "snip_twins", "soda_cannon", "slab_hammer"]
const FORGED_TIERS := {"mug_mace": 2, "soda_cannon": 3}

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

func _capture_hand(hero: Node3D, cam: Camera3D, label: String) -> void:
	await _frames(10)
	var basis := hero.global_transform.basis
	var forward := -basis.z.normalized()
	var side := basis.x.normalized()
	var hand = hero.get("_drive_socket")
	var focus := hero.global_position + Vector3(0.0, 1.0, 0.0)
	if hand is Node3D and (hand as Node3D).global_position != Vector3.ZERO:
		focus = (hand as Node3D).global_position
	cam.global_position = focus + forward * 1.5 + side * 0.8 + Vector3(0.0, 0.45, 0.0)
	cam.look_at(focus, Vector3.UP)
	await _frames(4)
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	if image != null:
		image.save_png("%s/hero_%s.png" % [OUT, label])
		print("SNAP hero_%s %s" % [label, str(image.get_size())])
	var wide_focus := hero.global_position + Vector3(0.0, 1.0, 0.0)
	cam.global_position = wide_focus + forward * 2.6 + side * 1.4 + Vector3(0.0, 0.8, 0.0)
	cam.look_at(wide_focus, Vector3.UP)
	await _frames(3)
	await RenderingServer.frame_post_draw
	var wide := root.get_viewport().get_texture().get_image()
	if wide != null:
		wide.save_png("%s/hero_wide_%s.png" % [OUT, label])
		print("SNAP hero_wide_%s %s" % [label, str(wide.get_size())])

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	if gs == null:
		print("FAIL: GameState missing")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	gs.save_path = OUT + "/progress.cfg"
	gs.delete_save()
	gs.reset()

	var scene := (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(40)
	var hero := scene.find_child("Hero", true, false) as Node3D
	if hero == null:
		print("FAIL: hero not found")
		quit(1)
		return
	var rig := scene.get_node_or_null("CameraRig")
	if rig != null:
		rig.set_process(false)
		rig.set_physics_process(false)
	var hud := scene.find_child("HUD", true, false)
	if hud != null and hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.05
	scene.add_child(cam)
	cam.current = true

	for weapon_id in WEAPON_IDS:
		gs.add_weapon(gs.WEAPON_DEFS[weapon_id].duplicate(true), true)
		await _capture_hand(hero, cam, weapon_id)

	for base_id in FORGED_TIERS:
		var def: Dictionary = RelicData.build_weapon_def(
			gs.WEAPON_DEFS[base_id], int(FORGED_TIERS[base_id]),
			"Forged %s" % base_id, ["Rite A", "Rite B", "Rite C"])
		gs.add_weapon(def, true)
		await _capture_hand(hero, cam, "relic_%s" % base_id)

	var panel := HeroPreviewPanel.new()
	root.add_child(panel)
	await _frames(4)
	if panel._viewport != null:
		panel._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for weapon_id in WEAPON_IDS:
		gs.add_weapon(gs.WEAPON_DEFS[weapon_id].duplicate(true), true)
		await _frames(6)
		await RenderingServer.frame_post_draw
		var preview := panel._viewport.get_texture().get_image()
		if preview == null:
			print("FAIL: preview capture ", weapon_id)
			continue
		preview.save_png("%s/preview_%s.png" % [OUT, weapon_id])
		print("SNAP preview_%s %s" % [weapon_id, str(preview.get_size())])
	gs.add_weapon(gs.WEAPON_DEFS["mug_mace"].duplicate(true), true)
	await _frames(6)

	gs.delete_save()
	quit()
