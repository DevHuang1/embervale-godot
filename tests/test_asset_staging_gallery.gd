extends SceneTree

func _initialize() -> void:
	var scene := load("res://scenes/tools/asset_staging_gallery.tscn") as PackedScene
	if scene == null:
		push_error("Asset staging gallery scene missing")
		quit(1)
		return
	var gallery := scene.instantiate()
	root.add_child(gallery)
	await process_frame
	if gallery.get_node_or_null("ScaleFloor") == null \
		or gallery.get_node_or_null("ReviewKeyLight") == null \
		or gallery.get_node_or_null("ReviewCamera") == null \
		or gallery.get_node_or_null("Pedestal_00") == null \
		or gallery.get_node_or_null("Label_02") == null \
		or gallery.get_node_or_null("CollisionBounds_00") == null \
		or gallery.get_node_or_null("ReviewTelemetry") == null:
		push_error("Asset staging gallery did not build bounded review stations")
		quit(1)
		return
	var gallery_source := FileAccess.get_file_as_string("res://scripts/tools/asset_staging_gallery.gd")
	if not gallery_source.contains("_preview_animation") \
			or not gallery_source.contains("MEMORY_STATIC") \
			or not gallery_source.contains("DRAW CALLS"):
		push_error("Asset staging gallery is missing animation or cost telemetry")
		quit(1)
		return
	print("ALL ASSET STAGING GALLERY TESTS PASSED")
	gallery.queue_free()
	var full_gallery := scene.instantiate()
	full_gallery.set("review_all_downloads", true)
	root.add_child(full_gallery)
	await process_frame
	var full_list: Array = full_gallery.get("_review_list")
	var expected_downloads := preload("res://scripts/systems/asset_intake_catalog.gd").inventory_downloaded_assets().size()
	if full_list.size() != expected_downloads:
		push_error("Full asset review mode did not enumerate every downloaded source")
		quit(1)
		return
	var loaded_count := int(full_gallery.get("_review_assets_loaded"))
	if loaded_count != expected_downloads:
		push_error("Full asset review mode did not load every downloaded source: %d/%d" % [loaded_count, expected_downloads])
		quit(1)
		return
	full_gallery.queue_free()
	quit(0)
