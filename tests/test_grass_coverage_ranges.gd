extends SceneTree

func _init() -> void:
	var streamer := FileAccess.get_file_as_string("res://scripts/systems/world_chunk_streamer.gd")
	var foliage := FileAccess.get_file_as_string("res://scripts/systems/ambient_foliage_patch.gd")
	for tier in ["[0.0, 70.0, 60.0, 115.0, 105.0, 155.0]", "[0.0, 105.0, 85.0, 180.0, 165.0, 250.0]", "[0.0, 170.0, 115.0, 330.0, 285.0, 430.0]"]:
		_assert_true(streamer.contains(tier), "tier range exists %s" % tier)
	_assert_true(streamer.contains("visibility_range_begin"), "grass begin ranges exist")
	_assert_true(streamer.contains("coverage_min"), "grass coverage metadata exists")
	_assert_true(streamer.contains("custom_aabb"), "grass batches define bounds")
	_assert_true(foliage.contains("set_coverage_range"), "ambient foliage range is configurable")
	_assert_true(foliage.contains("visibility_range_end_margin = 18.0"), "ambient foliage has fade margin")
	print("ALL GRASS COVERAGE RANGE TESTS PASSED")
	quit()

func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		push_error("FAIL: %s" % label)
		quit(1)
