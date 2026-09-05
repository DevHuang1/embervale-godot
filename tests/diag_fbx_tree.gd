extends SceneTree

func _initialize() -> void:
	var ps = load("res://assets/models/hero.fbx") as PackedScene
	if ps == null:
		print("FBXTREE null")
		quit(1)
		return
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	_dump(inst, 0, 12)
	quit(0)

func _dump(n: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	var kind := n.get_class()
	var extra := ""
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		extra = " mesh=" + str((n as MeshInstance3D).mesh.resource_name) + " aabb=" + str((n as MeshInstance3D).get_aabb().size)
	elif n is Skeleton3D:
		extra = " bones=" + str((n as Skeleton3D).get_bone_count())
	elif n is OmniLight3D or n is SpotLight3D:
		extra = " energy=" + str((n as OmniLight3D).light_energy if n is OmniLight3D else (n as SpotLight3D).light_energy)
	var sc := " scale=" + str((n as Node3D).scale) if n is Node3D else ""
	print("  ".repeat(depth), n.name, " <", kind, ">", sc, extra)
	for c in n.get_children():
		_dump(c, depth + 1, max_depth)