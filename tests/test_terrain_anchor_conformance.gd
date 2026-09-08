extends SceneTree

func _init() -> void:
	var relief_script := preload("res://scripts/systems/terrain_relief.gd")
	var terrain := relief_script.new() as TerrainRelief
	var anchor := Node3D.new()
	root.add_child(anchor)
	anchor.position = Vector3(-8.0, -20.0, -27.0)
	terrain.conform_anchor(anchor, 0.2)
	var expected := terrain.sample_surface_height(anchor.position) + 0.2
	if not is_equal_approx(anchor.position.y, expected):
		push_error("Anchor did not conform to terrain")
		quit(1)
		return
	var world_source := FileAccess.get_file_as_string("res://scripts/systems/world_manager.gd")
	var biome_source := FileAccess.get_file_as_string("res://scripts/systems/biome_manager.gd")
	if not world_source.contains("_conform_runtime_anchors") \
			or not biome_source.contains("terrain.conform_anchor(gate"):
		push_error("Portal/reward conformance is not wired")
		quit(1)
		return
	print("TERRAIN ANCHOR CONFORMANCE PASSED")
	anchor.free()
	terrain.free()
	quit()
