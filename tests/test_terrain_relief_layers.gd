extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/systems/terrain_relief.gd")
	var shader := FileAccess.get_file_as_string("res://assets/shaders/terrain_ground_layers.gdshader")
	_assert_true(source.contains("@export var ridge_amplitude: float = 1.15"), "relief enabled")
	_assert_true(source.contains("func height_at(x: float, z: float) -> float:"), "height sampler exists")
	_assert_true(not source.contains("return 0.0\n\tvar p := Vector2(x, z)"), "height sampler is not forced flat")
	_assert_true(source.contains("_flatten_mask(p)"), "gameplay flatten mask retained")
	_assert_true(source.contains("func sample_surface_height"), "surface height API")
	_assert_true(source.contains("func sample_surface_normal"), "surface normal API")
	_assert_true(source.contains("\"traversable\""), "traversability profile")
	var streamer := FileAccess.get_file_as_string("res://scripts/systems/world_chunk_streamer.gd")
	_assert_true(streamer.contains("_surface_height(world)"), "streamed dressing conforms to terrain")
	_assert_true(streamer.contains("func conform_dressing_to_surface"), "dressing correction API")
	_assert_true(streamer.contains("func validate_dressing_clearance"), "dressing validation API")
	_assert_true(streamer.contains("func get_surface_material_report"), "material report API")
	_assert_true(source.contains("sand_color"), "sand color is bound")
	for layer in ["grass", "dirt", "sand"]:
		_assert_true(shader.contains("%s_tex" % layer), "%s texture layer exists" % layer)
	_assert_true(shader.contains("moss_strength"), "moss layer exists")
	_assert_true(shader.contains("moisture_strength"), "wetness control exists")
	print("ALL TERRAIN RELIEF/LAYER TESTS PASSED")
	quit()

func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		push_error("FAIL: %s" % label)
		quit(1)
