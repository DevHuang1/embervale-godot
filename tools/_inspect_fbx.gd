extends SceneTree

func _init() -> void:
	var pack: PackedScene = load("res://assets/models/hushling.fbx")
	if pack == null:
		print("NO PACK")
		quit()
		return
	var inst := pack.instantiate()
	_walk(inst, 0)
	quit()

func _walk(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		extra = "  [mesh=%s surfaces=%d]" % [str(mi.mesh), mi.mesh.get_surface_count() if mi.mesh else -1]
		for s in range(mi.mesh.get_surface_count() if mi.mesh else 0):
			var m := mi.mesh.surface_get_material(s)
			extra += "  s%d:%s" % [s, str(m).get_file() if m else "none"]
	if n is Skeleton3D:
		var sk := n as Skeleton3D
		extra = "  [skeleton bones=%d]" % sk.get_bone_count()
	if n is AnimationPlayer:
		extra = "  [anim_count=%d] %s" % [n.get_animation_list().size(), str(n.get_animation_list())]
	if n is AnimationTree:
		extra = "  [anim_tree]"
	print(pad, n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_walk(c, depth + 1)