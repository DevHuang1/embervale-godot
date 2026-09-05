extends SceneTree

func _initialize() -> void:
	var ps = load("res://assets/models/hero.fbx")
	print("DIAG loaded=", ps, " is PackedScene=", ps is PackedScene)
	if ps is PackedScene:
		var inst: Node = ps.instantiate()
		root.add_child(inst)
		_dump(inst, 0, 40)
	quit()

func _dump(n: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth: return
	var t := n.get_class()
	print("  ".repeat(depth), n.name, " (", t, ")")
	if t == "Skeleton3D":
		print("  ".repeat(depth+1), "BONES=", n.get_bone_count())
		for i in mini(n.get_bone_count(), 20):
			print("  ".repeat(depth+2), i, ":", n.get_bone_name(i))
	for c in n.get_children():
		_dump(c, depth+1, max_depth)
