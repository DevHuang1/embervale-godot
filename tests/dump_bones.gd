extends SceneTree

func _init() -> void:
	var path := "res://assets/models/hero.fbx"
	var ps: PackedScene = load(path)
	var root := ps.instantiate()
	var skels := root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		print("NO SKELETON3D")
	else:
		var sk: Skeleton3D = skels[0]
		print("total bones: ", sk.get_bone_count())
		for b in sk.get_bone_count():
			var nm := sk.get_bone_name(b)
			if "alm" in nm or "and" in nm or "pine" in nm or "ip" in nm or "eck" in nm:
				print("  bone: ", nm)
	quit()