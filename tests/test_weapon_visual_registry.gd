extends SceneTree

func _init() -> void:
	var registry := preload("res://scripts/systems/weapon_visual_registry.gd")
	var required := ["ember_sword", "arcane_staff", "mug_mace", "matriarch_scepter",
		"pocket_blade", "snip_twins", "slab_hammer", "thorn_mace", "iron_axe",
		"grove_spear", "hunter_bow", "round_shield"]
	for weapon_id in required:
		var path: String = registry.path_for(weapon_id)
		if path.is_empty():
			push_error("No runtime weapon visual for %s" % weapon_id)
			quit(1)
			return
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed == null:
			push_error("Weapon visual is not instantiable: %s" % path)
			quit(1)
			return
		var instance := packed.instantiate() as Node3D
		if instance == null or instance.find_children("*", "MeshInstance3D", true, false).is_empty():
			push_error("Weapon visual has no mesh geometry: %s" % weapon_id)
			quit(1)
			return
		instance.free()
	print("WEAPON VISUAL REGISTRY PASSED: %d models" % required.size())
	quit()
