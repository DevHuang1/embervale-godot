extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_probe("res://assets/models/hero.fbx")
	await process_frame
	_probe("res://assets/models/boss_matriarch.glb")
	await process_frame
	quit(0)

func _probe(path: String) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		print("SCALEPROBE ", path, " -> null")
		return
	var inst: Node3D = ps.instantiate()
	root.add_child(inst)
	for frame in 2:
		await process_frame
	print("SCALEPROBE ", path)
	var root_scale = inst.scale
	print("  root_scale=", root_scale)
	for child in inst.get_children():
		var n := child as Node3D
		if n == null:
			continue
		print("  child[", n.name, "] type=", n.get_class(), " scale=", n.scale, " pos=", n.position)
	var box := AABB()
	var started := false
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		var xf := m.global_transform
		for i in 8:
			var wp: Vector3 = xf * m.get_aabb().get_endpoint(i)
			if not started:
				box = AABB(wp, Vector3.ZERO)
				started = true
			else:
				box = box.expand(wp)
	if started:
		print("  aabb_size=", box.size, " ground_y=", box.position.y, " top_y=", box.end.y)
	# Highest mesh AABB on each horizontal axis for a read on limb span
	inst.queue_free()
	for frame in 2:
		await process_frame