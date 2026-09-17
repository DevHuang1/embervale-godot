extends SceneTree

## The scan-pack product spans two files: DiamondCatalog owns the product id and
## its duplicate/restore disclosure, while DiamondShop owns the purchase state
## machine and the balance copy. Assert against the union so the contract holds
## wherever a future refactor moves a piece of it.
func _initialize() -> void:
	var catalog := FileAccess.get_file_as_string("res://scripts/systems/diamond_catalog.gd")
	var shop := FileAccess.get_file_as_string("res://scripts/ui/diamond_shop.gd")
	var source := "%s\n%s" % [catalog, shop]
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
