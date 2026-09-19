extends SceneTree

var _failures := 0

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

	# --- Material zones + shoreline beaches (Minecraft-style regions) ---
	var desktop_shader := FileAccess.get_file_as_string(
		"res://assets/shaders/terrain_ground.gdshader")
	var mobile_shader := FileAccess.get_file_as_string(
		"res://assets/shaders/terrain_ground_mobile.gdshader")
	for terrain_shader in [desktop_shader, mobile_shader]:
		_assert_true(terrain_shader.contains("region_scale"),
			"terrain shader carves coherent material regions")
		_assert_true(terrain_shader.contains("sand_color"),
			"terrain shader tints sand from the realm palette")
		_assert_true(terrain_shader.contains("shoreline_sand("),
			"terrain shader owns the waterline beach band")
		_assert_true(terrain_shader.contains("river_center_x("),
			"terrain shader mirrors the river centerline")
		_assert_true(terrain_shader.contains("river_half_width")
			and terrain_shader.contains("river_beach"),
			"river beach width is a tunable uniform")
		_assert_true(terrain_shader.contains("pond_a")
			and terrain_shader.contains("pond_b") and terrain_shader.contains("pond_c"),
			"three pond beach slots are declared")
	_assert_true(not desktop_shader.contains("vec4 texture_lift"),
		"per-channel texture lift cannot hue-shift sand again")
	_assert_true(source.contains("func _bind_shoreline"),
		"terrain relief binds the shoreline contract")
	_assert_true(source.contains("POND_SHADER_SLOTS"), "pond shader slots are centralized")
	_assert_true(source.contains("WATERWAYS.water_half_width(_river)"),
		"river beach starts at the real water-plane edge")
	if _failures == 0:
		print("ALL TERRAIN RELIEF/LAYER TESTS PASSED")
	else:
		print("%d FAILURES" % _failures)
	quit(1 if _failures > 0 else 0)

func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % label)
