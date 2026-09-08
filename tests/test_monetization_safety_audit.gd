extends SceneTree

func _init() -> void:
	var audit := preload("res://scripts/systems/monetization_safety_audit.gd")
	var sources := {
		"diamond_shop": FileAccess.get_file_as_string("res://scripts/ui/diamond_shop.gd"),
		"diamond_catalog": FileAccess.get_file_as_string("res://scripts/systems/diamond_catalog.gd"),
		"forge": FileAccess.get_file_as_string("res://scripts/ui/forge_menu.gd"),
		"shop": FileAccess.get_file_as_string("res://scripts/ui/shop_menu.gd"),
	}
	var errors: Array[String] = audit.audit_sources(sources)
	if not errors.is_empty():
		push_error("Monetization safety audit failed: %s" % "; ".join(errors))
		quit(1)
		return
	var catalog_script := preload("res://scripts/systems/diamond_catalog.gd")
	var catalog_errors: Array[String] = audit.audit_paid_catalog(catalog_script.ITEMS)
	if not catalog_errors.is_empty():
		push_error("Paid catalog safety audit failed: %s" % "; ".join(catalog_errors))
		quit(1)
		return
	print("MONETIZATION SAFETY AUDIT PASSED")
	quit(0)
