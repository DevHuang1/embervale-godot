extends SceneTree

func _init() -> void:
	var registry := preload("res://scripts/systems/enemy_visual_registry.gd")
	var required := ["thorn_charger", "mire_stalker", "spore_weaver", "ember_warden", "relic_leech"]
	for enemy_id in required:
		var path: String = registry.path_for(enemy_id)
		if path.is_empty():
			push_error("Missing enemy visual for %s" % enemy_id)
			quit(1)
			return
		var scene := load(path) as PackedScene
		var instance := scene.instantiate() as Node3D if scene != null else null
		if instance == null or instance.find_children("*", "MeshInstance3D", true, false).is_empty():
			push_error("Enemy visual has no mesh: %s" % enemy_id)
			quit(1)
			return
		instance.free()
	print("ENEMY VISUAL REGISTRY PASSED: %d models" % required.size())
	quit()
