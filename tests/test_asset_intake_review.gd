extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed := load("res://scenes/tools/asset_intake_review.tscn") as PackedScene
	if packed == null:
		push_error("Asset intake review scene missing")
		quit(1)
		return
	var review := packed.instantiate()
	root.add_child(review)
	await process_frame
	var rows := review.find_child("PackRows", true, false)
	if rows == null or rows.get_child_count() != 6:
		push_error("Asset intake review does not show all six imported packs")
		quit(1)
		return
	var summary := review.find_child("AssetIntakeSummary", true, false)
	if summary == null:
		push_error("Asset intake review summary missing")
		quit(1)
		return
	var readiness := review.find_child("AssetReadinessSummary", true, false)
	if readiness == null or not str(readiness.text).contains("READY 6/6"):
		push_error("Asset intake readiness summary missing reviewed-pack count")
		quit(1)
		return
	if not str(readiness.text).contains("QUALITY") or not str(readiness.text).contains("SHIP-READY"):
		push_error("Asset intake summary did not show aggregate quality readiness")
		quit(1)
		return
	var first_row := rows.get_child(0).get_child(0) as Label
	if first_row == null or not first_row.text.contains("QUALITY 100/100"):
		push_error("Asset intake rows did not show deterministic quality score")
		quit(1)
		return
	print("ALL ASSET INTAKE REVIEW TESTS PASSED")
	review.queue_free()
	quit(0)
