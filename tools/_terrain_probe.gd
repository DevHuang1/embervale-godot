extends SceneTree

## Terrain probe: boots the grove (Bramblewood) WITH a real window, snaps the
## ground from a gameplay-low angle and from a full-coverage overhead, saves
## to .captures/, prints per-realm stats, then quits. Not for --headless.

func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(path: String) -> void:
	var vp := root.get_viewport()
	var img := vp.get_texture().get_image()
	if img == null:
		print("SKIP(no image): ", path)
		return
	DirAccess.make_dir_recursive_absolute(".captures")
	var err := img.save_png(path)
	print("SNAP ", path, " err=", err, " size=", img.get_size())


func _cam(scene: Node) -> Camera3D:
	for c in scene.find_children("*", "Camera3D", true, false):
		var cam := c as Camera3D
		if cam.is_inside_tree():
			cam.current = true
			return cam
	return null


func _run() -> void:
	var gs := root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()
	var qs := root.get_node_or_null("/root/WorldState/QualityScaler") as QualityScaler
	if qs != null:
		qs.set_mode(QualityScaler.Mode.HIGH)

	change_scene_to_file("res://scenes/world/grove.tscn")
	await _frames(90)

	var scene := root.get_child(root.get_child_count() - 1)
	var cam := _cam(scene)
	if cam != null:
		# Gameplay-low angle: ground detail as the player sees it.
		cam.fov = 60.0
		cam.global_position = Vector3(0, 2.6, 6)
		cam.rotation_degrees = Vector3(-28, 0, 0)
		await _frames(4)
		_snap(".captures/terrain_low.png")

		# Full-coverage overhead: the whole 600x600 ground in frame.
		cam.fov = 75.0
		cam.global_position = Vector3(0, 780, 0)
		cam.rotation_degrees = Vector3(-90, 0, 0)
		await _frames(4)
		_snap(".captures/terrain_overhead.png")

	# Second realm identity for contrast (Moonfen violet sheen).
	gs.set_current_realm("moonfen")
	change_scene_to_file("res://scenes/world/moonfen.tscn")
	await _frames(90)
	var moon := root.get_child(root.get_child_count() - 1)
	var mc := _cam(moon)
	if mc != null:
		mc.fov = 75.0
		mc.global_position = Vector3(0, 780, 0)
		mc.rotation_degrees = Vector3(-90, 0, 0)
		await _frames(4)
		_snap(".captures/terrain_moonfen_overhead.png")

	print("TERRAIN_PROBE_DONE")
	gs.delete_save()
	quit(0)