extends SceneTree

func _initialize() -> void:
	var ps = load("res://assets/models/hero.fbx") as PackedScene
	var inst: Node3D = ps.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	var mesh_count := 0
	var box := AABB()
	var started := false
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		mesh_count += 1
		var xf := m.global_transform
		for i in 8:
			var wp: Vector3 = xf * m.get_aabb().get_endpoint(i)
			if not started:
				box = AABB(wp, Vector3.ZERO)
				started = true
			else:
				box = box.expand(wp)
	print("FBXPROBE root_scale=", inst.scale)
	print("FBXPROBE mesh_count=", mesh_count)
	if started:
		print("FBXPROBE aabb_size=", box.size, " center=", box.get_center())
	var anim_players := inst.find_children("*", "AnimationPlayer", true, false)
	print("FBXPROBE animation_players=", anim_players.size())
	if not anim_players.is_empty():
		var ap := anim_players[0] as AnimationPlayer
		print("FBXPROBE animations=", ap.get_animation_list())
	quit(0)