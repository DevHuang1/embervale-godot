extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/diamond_catalog.gd")
	var audit := preload("res://scripts/systems/monetization_safety_audit.gd")
	for item in catalog.ITEMS:
		if not item is Dictionary:
			push_error("Catalog entry must be a dictionary")
			quit(1)
			return
		if str(item.get("kind", "")) == "scan_pack" \
				or str(item.get("id", "")) == "scan_pack_5":
			push_error("Removed scan-pack product still sold: %s" % item.get("id", ""))
			quit(1)
			return
	var errors: Array[String] = audit.audit_paid_catalog(catalog.ITEMS)
	if not errors.is_empty():
		push_error("Catalog audit failed: %s" % "; ".join(errors))
		quit(1)
		return
	print("ALL MONETIZATION CATALOG TESTS PASSED")
	quit()
