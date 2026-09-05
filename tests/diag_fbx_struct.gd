extends SceneTree

func _initialize() -> void:
	var ps = load("res://assets/models/hero.fbx")
	if not (ps is PackedScene):
		print("DIAG FAIL loaded state=", ps)
		quit(1)
		return
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await process_frame
	var world := AABB()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var t := (mi as Node3D).get_global_transform()
		var bs_x: float = (t.basis * Vector3.RIGHT).length()
		var bs_y: float = (t.basis * Vector3.UP).length()
		var bs_z: float = (t.basis * Vector3.FORWARD).length()
		var scaled: AABB = (mi as Node3D).get_aabb()
		scaled.position *= Vector3(bs_x, bs_y, bs_z)
		scaled.size *= Vector3(bs_x, bs_y, bs_z)
		world = world.merge(scaled)
		print("DIAG mesh '", mi.name, "' parent=", mi.get_parent().name,
			" scaleBasis=(", bs_x, ",", bs_y, ",", bs_z, ") aabbSize=", (mi as Node3D).get_aabb().size)
	print("DIAG est world AABB size=", world.size)
	var arm := inst.get_node_or_null("HumanArmature")
	if arm:
		print("DIAG armature scale=", arm.scale)
	quit()
