extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/asset_intake_catalog.gd")
	var inventory: Array[Dictionary] = catalog.inventory_downloaded_assets()
	if inventory.size() < catalog.ENTRIES.size():
		push_error("Downloaded asset inventory is unexpectedly smaller than the intake catalog")
		quit(1)
		return
	var gameplay_count := 0
	var review_count := 0
	for item in inventory:
		var path := str(item.get("path", ""))
		if not FileAccess.file_exists(path):
			push_error("Inventory contains missing asset: %s" % path)
			quit(1)
			return
		if str(item.get("classification", "")) == "GAMEPLAY":
			gameplay_count += 1
		elif str(item.get("classification", "")) == "REVIEW_ONLY":
			review_count += 1
		else:
			push_error("Asset has no explicit classification: %s" % path)
			quit(1)
			return
	if gameplay_count == 0 or review_count == 0:
		push_error("Inventory must expose both gameplay and review-only decisions")
		quit(1)
		return
	print("ASSET INVENTORY AUDIT PASSED: %d gameplay, %d review-only" % [gameplay_count, review_count])
	quit()
