extends SceneTree

func _init() -> void:
	var castle_script := preload("res://scripts/world/castle_landmark.gd")
	var castle := castle_script.new()
	root.add_child(castle)
	castle.setup(Node.new(), null, Vector3(80.0, 0.0, 6.0))
	if castle.get_node_or_null("NorthWall") == null:
		push_error("Castle has no visible wall")
		quit(1)
		return
	if castle.get_node_or_null("EmbervaultCastleEntrance") == null:
		push_error("Castle has no enterable entrance")
		quit(1)
		return
	var tower_names: Array[Node] = castle.find_children("North*TowerBase", "MeshInstance3D", true, false)
	if tower_names.size() < 2:
		push_error("Castle lacks large tower silhouettes")
		quit(1)
		return
	if not castle.is_in_group("structure"):
		push_error("Castle is not registered as a minimap structure")
		quit(1)
	print("CASTLE LANDMARK PASSED")
	quit()
