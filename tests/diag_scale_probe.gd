extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var ps = load("res://assets/models/hero.fbx")
	if not (ps is PackedScene):
		quit(1)
		return
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await process_frame
	for skel_n in inst.find_children("*", "Skeleton3D", true, false):
		var skel: Skeleton3D = skel_n
		var gm := skel.global_transform
		var min_y := 1e9
		var max_y := -1e9
		var min_x := 1e9
		var max_x := -1e9
		for i in skel.get_bone_count():
			var o := (gm * skel.get_bone_global_pose(i)).origin
			min_y = minf(min_y, o.y)
			max_y = maxf(max_y, o.y)
			min_x = minf(min_x, o.x)
			max_x = maxf(max_x, o.x)
		print("PROCG bone span x=[", min_x, ",", max_x, "] y=[", min_y, ",", max_y,
			"] height=", max_y - min_y)
		var foot_i := -1
		for nm in ["Foot.L", "Foot.R"]:
			var f := skel.find_bone(nm)
			if f >= 0 and (foot_i < 0 or (gm * skel.get_bone_global_pose(f)).origin.y < (gm * skel.get_bone_global_pose(foot_i)).origin.y):
				foot_i = f
		if foot_i >= 0:
			print("PROCG lowest foot y=", (gm * skel.get_bone_global_pose(foot_i)).origin.y)
	quit()
