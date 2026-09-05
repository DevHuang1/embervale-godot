extends SceneTree

## Grip verification shot: hero closeup with weapon equipped.
## Requires a real renderer: run WITHOUT --headless
##   godot --path . --script tests/diag_grip_shot.gd

const OUT := "/tmp/grip_shot.png"

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var gs := root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()
	change_scene_to_file("res://scenes/world/grove.tscn")
	await _frames(150)
	var hero := current_scene.find_child("Hero", true, false)
	if hero == null:
		print("NO HERO")
		quit(1)
		return
	# Socket diagnostics FIRST: headless viewports have null textures, so the
	# capture below may be impossible — these prints are the real output.
	for pair in [["hand_l", "hand_socket_l"], ["hand_r", "hand_socket_r"]]:
		var sock: AttachmentSocket = hero.get(pair[1])
		if sock != null:
			var bone := sock.get_parent() as Node3D
			print(pair[0], " parent=", sock.get_parent().name,
				" occupied=", sock.has_item(),
				" sock_gpos=", sock.global_position,
				" bone_gpos=", bone.global_position if bone != null else Vector3.INF,
				" dist=", sock.global_position.distance_to(bone.global_position) if bone != null else -1.0)
	# Park the camera rig so it can't re-aim, then frame the hero's hands.
	var rig := current_scene.find_child("CameraRig", true, false)
	if rig is Node:
		(rig as Node).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(2)
	var cam := root.get_viewport().get_camera_3d()
	var hp: Vector3 = (hero as Node3D).global_position
	cam.global_position = hp + Vector3(1.4, 1.2, 1.4)
	cam.look_at(hp + Vector3(0, 0.75, 0))
	await _frames(4)
	var tex := root.get_viewport().get_texture()
	if tex != null and tex.get_image() != null:
		tex.get_image().save_png(OUT)
		print("saved ", OUT)
	else:
		print("capture_unavailable (headless dummy renderer)")
	quit(0)

