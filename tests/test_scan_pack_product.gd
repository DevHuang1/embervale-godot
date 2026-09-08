extends SceneTree

func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/diamond_shop.gd")
	if not source.contains("scan_pack_5") or not source.contains("Purchase integration is not connected") \
			or not source.contains("duplicate_behavior") or not source.contains("restore_path") \
			or not source.contains("BALANCE %d/%d") \
			or not source.contains("pending") or not source.contains("cancelled") \
			or not source.contains("restoring") or not source.contains("set_scan_purchase_state"):
		print("FAIL: scan pack product state missing")
		quit(1)
		return
	print("ALL SCAN PACK PRODUCT TESTS PASSED")
	quit(0)
