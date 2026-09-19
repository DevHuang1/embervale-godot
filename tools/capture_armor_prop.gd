extends SceneTree

## Real-renderer review harness for body-armor models. Captures the procedural
## plate and a bone-attached model record on the real hero so an incoming CC0
## armor pack can be seated and scaled visually before it is wired into
## ArmorVisualRegistry. Writes PNGs under /tmp/embervale_armor_props:
##   godot --path . --script tools/capture_armor_prop.gd --rendering-driver metal

const OUT := "/tmp/embervale_armor_props"
const PROBE_MODEL := "res://assets/models/weapons/quaternius/Shield_Round.fbx"

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

func _snap(hero: Node3D, cam: Camera3D, label: String, focus_y: float) -> void:
	var basis := hero.global_transform.basis
	var forward := -basis.z.normalized()
	var side := basis.x.normalized()
	var focus := hero.global_position + Vector3(0.0, focus_y, 0.0)
	cam.global_position = focus + forward * 1.7 + side * 0.9 + Vector3(0.0, 0.25, 0.0)
	cam.look_at(focus, Vector3.UP)
	await _frames(4)
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	if image == null:
		print("FAIL: no frame for ", label)
		return
	image.save_png("%s/%s.png" % [OUT, label])
	print("SNAP %s %s" % [label, str(image.get_size())])

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

	gs.add_armor(gs.ARMOR_DEFS["warden_plate"].duplicate(true), false)
	gs.equip_armor("warden_plate")
	await _snap(hero, cam, "procedural_warden_plate", 1.0)

	for probe in [
		{"label": "probe_model_front", "offset": Vector3(0.0, 0.05, 0.45)},
		{"label": "probe_model_back", "offset": Vector3(0.0, 0.05, -0.45)},
	]:
		var mounted: bool = hero.call("_mount_armor_model_record", {
			"kind": "model", "path": PROBE_MODEL, "bone": "Torso",
			"length": 0.60, "offset": probe["offset"],
		})
		print("model mounted=%s (%s)" % [str(mounted), str(probe["label"])])
		if mounted:
			await _snap(hero, cam, str(probe["label"]), 1.05)
			var sockets: Array = hero.find_children("ArmorSocket_model*", "Node3D", true, false)
			for socket in sockets:
				socket.queue_free()

	gs.delete_save()
	quit()
